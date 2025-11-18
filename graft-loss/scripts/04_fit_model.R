source("scripts/00_setup.R")

final_features <- readRDS(here::here('data', 'final_features.rds'))

# Configure per-worker threading to avoid CPU oversubscription during parallel workflows.
# Controlled by env var MC_WORKER_THREADS (default 1). Applies to BLAS/OMP, ranger, xgboost.
worker_threads <- suppressWarnings(as.integer(Sys.getenv("MC_WORKER_THREADS", unset = "1")))
if (!is.finite(worker_threads) || worker_threads < 1) worker_threads <- 1L
options(mc.per.worker.threads = worker_threads)
Sys.setenv(
  OMP_NUM_THREADS = as.character(worker_threads),
  OPENBLAS_NUM_THREADS = as.character(worker_threads),
  MKL_NUM_THREADS = as.character(worker_threads),
  VECLIB_MAXIMUM_THREADS = as.character(worker_threads),
  NUMEXPR_NUM_THREADS = as.character(worker_threads)
)
message(sprintf("Per-worker threads set to %d (MC_WORKER_THREADS)", worker_threads))

# Tuning knobs (optional, via environment variables):
# - ORSF_NTREES (default 1000)
# - RSF_NTREES (default 1000)
# - XGB_NROUNDS (default 500) and MC_WORKER_THREADS (default 1)

# Select data variant based on environment variable USE_ENCODED
# - default ("0" or missing): CatBoost/native categoricals
# - "1": use encoded (dummy-coded) dataset
use_encoded <- Sys.getenv("USE_ENCODED", unset = "0")
if (nzchar(use_encoded) && use_encoded %in% c("1", "true", "TRUE")) {
  final_data <- readRDS(here::here('data', 'final_data_encoded.rds'))
  model_vars <- final_features$terms  # use dummy-coded terms with encoded data
  message("Model input: final_data_encoded.rds (encoded); using final_features$terms")
} else {
  final_data <- readRDS(here::here('data', 'final_data.rds'))
  model_vars <- final_features$variables  # use base variable names with native categoricals
  message("Model input: final_data.rds (catboost/native categoricals); using final_features$variables")
}

# Helper to treat multiple flag name variants as TRUE
env_truthy <- function(name, default = FALSE) {
  val <- Sys.getenv(name, unset = ifelse(default, "1", "0"))
  tolower(val) %in% c('1','true','yes','y')
}

# ORSF full feature (accept multiple variants: ORSF_FULL, AORSF_FULL, ORSF_USE_FULL)
orsf_full_flag <- any(vapply(c('ORSF_FULL','AORSF_FULL','ORSF_USE_FULL','AORSF_USE_FULL'), env_truthy, logical(1)))
if (orsf_full_flag) {
  full_native_vars <- setdiff(colnames(final_data), c('time','status','ID'))
  if (nzchar(use_encoded) && use_encoded %in% c("1", "true", "TRUE")) {
    # Encoded path: all encoded predictors
    full_encoded_vars <- setdiff(colnames(final_data), c('time','status'))
    model_vars <- full_encoded_vars
    message(sprintf('ORSF_FULL: using ALL encoded predictors (%d)', length(model_vars)))
  } else {
    model_vars <- full_native_vars
    message(sprintf('ORSF_FULL: using ALL native predictors (%d)', length(model_vars)))
  }
}

# XGB full feature (XGB_FULL / XGB_USE_FULL) stored for later use
xgb_full_flag <- any(vapply(c('XGB_FULL','XGB_USE_FULL'), env_truthy, logical(1)))

# Candidate full feature set for CatBoost (native path recommended). Exclude outcomes & obvious identifiers.
# CatBoost full variables (native) for its override
catboost_full_vars <- setdiff(colnames(final_data), c('time','status','ID'))

# Accept alternate naming CATBOOST_FULL in addition to CATBOOST_USE_FULL
if (!env_truthy('CATBOOST_USE_FULL') && env_truthy('CATBOOST_FULL')) {
  Sys.setenv(CATBOOST_USE_FULL = '1')
}

dir.create(here::here('data','models'), showWarnings = FALSE, recursive = TRUE)

mc_cv <- tolower(Sys.getenv("MC_CV", unset = "0")) %in% c("1","true","yes","y")

if (!mc_cv) {
  # Train single fits for quick comparison
  results <- list()

  message("Fitting ORSF...")
  orsf_model <- fit_orsf(trn = final_data, vars = model_vars)
  saveRDS(orsf_model, here::here('data','models','model_orsf.rds'))
  message("Saved: data/models/model_orsf.rds")
  results[["ORSF"]] <- list(name = "ORSF")

  message("Fitting RSF (ranger)...")
  rsf_model <- fit_rsf(trn = final_data, vars = model_vars)
  saveRDS(rsf_model, here::here('data','models','model_rsf.rds'))
  message("Saved: data/models/model_rsf.rds")
  results[["RSF"]] <- list(name = "RSF")

  message("Fitting XGBoost (sgb survival)...")
  xgb_data_path <- here::here('data','final_data_encoded.rds')
  if (!file.exists(xgb_data_path)) {
    stop("Encoded dataset final_data_encoded.rds not found. Re-run step 03 before fitting XGB.")
  }
  xgb_trn <- readRDS(xgb_data_path)
  if (xgb_full_flag) {
    xgb_vars <- setdiff(colnames(xgb_trn), c('time','status'))
    message(sprintf('XGB_FULL: using ALL encoded predictors (%d)', length(xgb_vars)))
  } else {
    xgb_vars <- final_features$terms  # encoded (dummy) variable names (selected subset)
  }
  xgb_model <- fit_xgb(trn = xgb_trn, vars = xgb_vars)
  saveRDS(xgb_model, here::here('data','models','model_xgb.rds'))
  message("Saved: data/models/model_xgb.rds")
  results[["XGB"]] <- list(name = "XGB")

  # Prepare comparison index rows for single-fit case
  cmp <- data.frame(
    model = c("ORSF","RSF"),
    file = c("data/models/model_orsf.rds","data/models/model_rsf.rds"),
    use_encoded = ifelse(nzchar(use_encoded) && use_encoded %in% c("1","true","TRUE"), 1L, 0L),
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    stringsAsFactors = FALSE
  )
  if (exists("xgb_model")) {
    cmp <- dplyr::bind_rows(cmp, data.frame(
      model = "XGB",
      file = "data/models/model_xgb.rds",
      use_encoded = 1L,  # XGB always uses encoded inputs now
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      stringsAsFactors = FALSE
    ))
  }

  # Optional: CatBoost (single-split)
  use_catboost <- Sys.getenv("USE_CATBOOST", unset = "0")
  if (nzchar(use_catboost) && use_catboost %in% c("1","true","TRUE")) {
    message("Training CatBoost (Python) on signed-time labels (single-split)...")
    # Use existing resampling indices if available (first split); else 80/20 fallback
    trn_idx <- NULL; tst_idx <- NULL
    res_path <- here::here('data','resamples.rds')
    if (file.exists(res_path)) {
      testing_rows <- readRDS(res_path)
      if (length(testing_rows) >= 1) {
        test_idx_vec <- as.integer(testing_rows[[1]])
        all_idx <- seq_len(nrow(final_data))
        trn_idx <- setdiff(all_idx, test_idx_vec)
        tst_idx <- test_idx_vec
        message(sprintf("Using resamples.rds first split: train=%d, test=%d", length(trn_idx), length(tst_idx)))
      }
    }
    if (is.null(trn_idx) || is.null(tst_idx)) {
      set.seed(42)
      n <- nrow(final_data)
      idx <- sample(seq_len(n))
      split <- floor(0.8 * n)
      trn_idx <- idx[1:split]
      tst_idx <- idx[(split+1):n]
      message(sprintf("Resamples not found; using 80/20 split: train=%d, test=%d", length(trn_idx), length(tst_idx)))
    }
    # Save the indices for Step 05
    saveRDS(list(train = trn_idx, test = tst_idx), here::here('data','models','split_indices.rds'))

    use_cb_full <- tolower(Sys.getenv('CATBOOST_USE_FULL', unset = '1')) %in% c('1','true','yes','y')
    cb_vars <- if (use_cb_full) catboost_full_vars else model_vars
    if (use_cb_full) {
      message(sprintf('CatBoost: using full native feature set (%d variables)', length(cb_vars)))
    } else {
      message(sprintf('CatBoost: using selected feature subset (%d variables)', length(cb_vars)))
    }
    trn_df <- final_data[trn_idx, c('time','status', cb_vars), drop = FALSE]
    tst_df <- final_data[tst_idx, c('time','status', cb_vars), drop = FALSE]

    # Export to CSV for Python
    outdir <- here::here('data','models','catboost')
    dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
    train_csv <- file.path(outdir, 'train.csv')
    test_csv  <- file.path(outdir, 'test.csv')
    readr::write_csv(trn_df, train_csv)
    readr::write_csv(tst_df, test_csv)

    # Build categorical columns list (character or factor)
  cat_cols <- names(trn_df)[vapply(trn_df, function(x) is.character(x) || is.factor(x), logical(1L))]
    cat_cols_arg <- if (length(cat_cols)) paste(cat_cols, collapse = ',') else ''

    # Call Python script
    py_script <- here::here('scripts','py','catboost_survival.py')
    outdir_abs <- normalizePath(outdir)
    cmd <- sprintf('python "%s" --train "%s" --test "%s" --time-col time --status-col status --outdir "%s" %s',
                   py_script, train_csv, test_csv, outdir_abs,
                   if (nzchar(cat_cols_arg)) paste0('--cat-cols "', cat_cols_arg, '"') else '')
    message("Running: ", cmd)
    status <- system(cmd)
    if (status != 0) warning("CatBoost (Python) command returned non-zero exit status.")

    # If predictions exist, add to index
    pred_file <- file.path(outdir, 'catboost_predictions.csv')
    if (file.exists(pred_file)) {
      # Keep a pointer to model artifact in index
      cb_row <- data.frame(
        model = "CatBoostPy",
        file = file.path('data','models','catboost','catboost_model.cbm'),
        use_encoded = ifelse(nzchar(use_encoded) && use_encoded %in% c("1","true","TRUE"), 1L, 0L),
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        stringsAsFactors = FALSE
      )
      cmp <- dplyr::bind_rows(cmp, cb_row)
    }
  }

} else {
  # MC CV mode: compute per-split C-index with optional FI; run for full and original datasets

  # Option: use globally pre-encoded dataset for XGB across all splits (consistent feature space)
  use_global_xgb <- tolower(Sys.getenv("MC_XGB_USE_GLOBAL", unset = "0")) %in% c("1","true","yes","y")
  encoded_full <- NULL; encoded_full_vars <- NULL
  if (use_global_xgb) {
    enc_path_full <- here::here('data','final_data_encoded.rds')
    if (!file.exists(enc_path_full)) stop("MC_XGB_USE_GLOBAL=1 but final_data_encoded.rds not found. Re-run step 03.")
    encoded_full <- readRDS(enc_path_full)
    encoded_full_vars <- final_features$terms
    message("MC CV: Using global encoded dataset for XGB (full data)")
  } else {
    message("MC CV: Using per-split on-the-fly encoding for XGB")
  }

  # Helper: c-index
  cindex <- function(time, status, score) {
    survival::concordance(survival::Surv(time, status) ~ score)$concordance
  }

  # Helper: Uno's time-dependent C-index at a specific horizon (requires riskRegression)
  cindex_uno <- function(time, status, score, eval_time = 1) {
    # Best-effort extraction across riskRegression::Cindex result structures
    df <- data.frame(time = as.numeric(time), status = as.numeric(status), score = as.numeric(score))
    val <- tryCatch({
      res <- riskRegression::Cindex(
        formula = survival::Surv(time, status) ~ score,
        data = df,
        eval.times = eval_time,
        method = "Uno",
        cens.model = "marginal"
      )
      # Try common structures to extract the C value
      if (is.list(res)) {
        # Look for a data.frame with a C-index-like column
        df_list <- Filter(is.data.frame, res)
        for (d in df_list) {
          nm <- tolower(gsub("[^a-z]", "", names(d)))
          # candidate columns that may hold the index
          cand <- which(nm %in% c("cindex", "cindexuno", "concordance"))
          if (length(cand)) {
            row <- 1L
            if ("eval.time" %in% names(d)) {
              # pick row matching eval_time, else first row
              rr <- which(round(d$eval.time, 6) == round(eval_time, 6))
              if (length(rr)) row <- rr[1]
            }
            v <- suppressWarnings(as.numeric(d[row, cand[1]]))
            if (is.finite(v) && v > 0 && v < 1) return(v)
          }
        }
        # Specific common slot
        if (!is.null(res$AppCindex) && is.data.frame(res$AppCindex) && "Cindex" %in% names(res$AppCindex)) {
          v <- suppressWarnings(as.numeric(res$AppCindex$Cindex[1]))
          if (is.finite(v) && v > 0 && v < 1) return(v)
        }
      }
      NA_real_
    }, error = function(e) NA_real_)
    # Fallback to Harrell if Uno failed
    if (!is.finite(val)) val <- suppressWarnings(cindex(df$time, df$status, df$score))
    as.numeric(val)
  }

  # Helper: run MC CV for a given dataset and write labeled outputs
  run_mc <- function(label, df, vars, testing_rows, encoded_df = NULL, encoded_vars = NULL, use_global_xgb = FALSE, catboost_full_vars = NULL) {
    total_splits <- length(testing_rows)
    mc_start <- suppressWarnings(as.integer(Sys.getenv("MC_START_AT", unset = "1")))
    if (!is.finite(mc_start) || mc_start < 1) mc_start <- 1
    mc_max <- suppressWarnings(as.integer(Sys.getenv("MC_MAX_SPLITS", unset = "0")))
    if (!is.finite(mc_max) || mc_max < 1) mc_max <- total_splits - mc_start + 1
    split_idx <- seq.int(from = mc_start, length.out = min(mc_max, total_splits - mc_start + 1))

    do_fi <- tolower(Sys.getenv("MC_FI", unset = "1")) %in% c("1","true","yes","y")
    max_vars <- suppressWarnings(as.integer(Sys.getenv("MC_FI_MAX_VARS", unset = "30")))
    if (!is.finite(max_vars) || max_vars < 1) max_vars <- min(length(vars), 30L)

    horizon <- 1
    mc_rows <- list()
    mc_rows_uno <- list()
    mc_fi_rows <- list()

    # Progress directory & writer
    progress_dir <- here::here('data','progress')
    dir.create(progress_dir, showWarnings = FALSE, recursive = TRUE)
    progress_file <- file.path(progress_dir, 'pipeline_progress.json')
    step_names <- c('00_setup','01_prepare_data','02_resampling','03_prep_model_data','04_fit_model','05_generate_outputs')
    current_step_index <- 5  # 1-based index for 04_fit_model within overall pipeline sequence
    write_progress <- function(split_done = 0, split_total = length(split_idx), label_cur = label, note = NULL) {
      # Basic timing & ETA
      now <- Sys.time()
      if (split_done > 0) {
        elapsed <- as.numeric(difftime(now, mc_t0, units = 'secs'))
        avg_per <- elapsed / split_done
        remaining <- max(split_total - split_done, 0)
        eta_sec <- remaining * avg_per
      } else {
        elapsed <- 0; avg_per <- NA; eta_sec <- NA
      }
      obj <- list(
        timestamp = format(now, '%Y-%m-%dT%H:%M:%S%z'),
        current_step = '04_fit_model',
        step_index = current_step_index,
        total_steps = length(step_names),
        step_names = step_names,
        mc = list(
          dataset_label = label_cur,
          split_done = split_done,
          split_total = split_total,
          percent = if (split_total > 0) round(100 * split_done / split_total, 2) else NA,
          elapsed_sec = elapsed,
          avg_sec_per_split = if (is.finite(avg_per)) round(avg_per, 3) else NA,
          eta_sec = if (is.finite(eta_sec)) round(eta_sec) else NA
        ),
        note = note
      )
      tmp <- paste0(progress_file, '.tmp')
      jsonlite::write_json(obj, tmp, auto_unbox = TRUE, pretty = TRUE)
      file.rename(tmp, progress_file)
    }

    mc_t0 <- Sys.time()
    write_progress(split_done = 0, note = sprintf('Starting MC CV (%s)', label))

    # Processor for a single split k; returns list of dfs: rows, rows_uno, fi_rows
    process_split <- function(k) {
      rows <- list(); rows_uno <- list(); fi_rows <- list()
      message(sprintf("[MC %s] begin split %d", label, k))
      test_idx <- as.integer(testing_rows[[k]])
      all_idx <- seq_len(nrow(df))
      train_idx <- setdiff(all_idx, test_idx)
      # Per-split recipe: impute using training data only (match paper); disable novel level creation
      rec_native <- prep(make_recipe(df[train_idx, c('time','status', vars), drop = FALSE], dummy_code = FALSE, add_novel = FALSE))
      trn_df <- juice(rec_native)
      te_df  <- bake(rec_native, new_data = df[test_idx, c('time','status', vars), drop = FALSE])
      vars_native <- setdiff(colnames(trn_df), c('time','status'))

      # ORSF
      orsf_m <- fit_orsf(trn = trn_df, vars = vars_native)
      orsf_score <- tryCatch({
        1 - predict(orsf_m, newdata = te_df[, c('time','status', vars_native)], times = horizon)
      }, error = function(e) suppressWarnings(as.numeric(predict(orsf_m, newdata = te_df[, c('time','status', vars_native)]))))
      orsf_cidx <- cindex(te_df$time, te_df$status, as.numeric(orsf_score))
      rows[[length(rows)+1]] <- data.frame(split=k, model="ORSF", cindex=orsf_cidx)
      # Uno C at 1-year
      orsf_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(orsf_score), eval_time = horizon)
      rows_uno[[length(rows_uno)+1]] <- data.frame(split=k, model="ORSF", cindex=orsf_cidx_uno)

      # RSF
      rsf_m <- fit_rsf(trn = trn_df, vars = vars_native)
      rsf_score <- tryCatch({
        ranger_predictrisk(rsf_m, newdata = te_df, times = horizon)
      }, error = function(e) suppressWarnings(as.numeric(predict(rsf_m, data = te_df)$predictions)))
      rsf_cidx <- cindex(te_df$time, te_df$status, as.numeric(rsf_score))
      rows[[length(rows)+1]] <- data.frame(split=k, model="RSF", cindex=rsf_cidx)
      # Uno C at 1-year
      rsf_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(rsf_score), eval_time = horizon)
      rows_uno[[length(rows_uno)+1]] <- data.frame(split=k, model="RSF", cindex=rsf_cidx_uno)

      # XGB
      xgb_m <- NULL; xgb_cidx <- NA_real_; xgb_score <- NULL; xgb_feature_space <- NULL
      if (use_global_xgb && !is.null(encoded_df) && !is.null(encoded_vars)) {
        # Subset encoded data using same row indices
        full_enc_space <- setdiff(colnames(encoded_df), c('time','status'))
        use_vars <- if (xgb_full_flag) full_enc_space else encoded_vars
        if (xgb_full_flag) message(sprintf('[MC %s %d/%d] XGB_FULL: using ALL encoded predictors (%d)', label, which(split_idx==k), length(split_idx), length(use_vars)))
        trn_enc <- encoded_df[train_idx, c('time','status', use_vars), drop = FALSE]
        te_enc  <- encoded_df[test_idx,  c('time','status', use_vars), drop = FALSE]
        xgb_m <- fit_xgb(trn = trn_enc, vars = use_vars)
        xgb_score <- tryCatch({
          1 - predict(xgb_m, new_data = as.matrix(te_enc[, use_vars, drop = FALSE]), eval_times = horizon)
        }, error = function(e) suppressWarnings(as.numeric(predict(xgb_m, new_data = as.matrix(te_enc[, use_vars, drop = FALSE])))))
        xgb_cidx <- cindex(te_df$time, te_df$status, as.numeric(xgb_score))
        xgb_feature_space <- use_vars
        rows[[length(rows)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx)
        # Uno C at 1-year
        xgb_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(xgb_score), eval_time = horizon)
        rows_uno[[length(rows_uno)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx_uno)
      } else {
        # Per-split encoding (previous behavior)
        all_num <- all(vapply(trn_df[, vars_native, drop = FALSE], is.numeric, logical(1L)))
        if (all_num) {
          use_vars <- if (xgb_full_flag) vars_native else vars_native
          xgb_m <- fit_xgb(trn = trn_df, vars = use_vars)
          xgb_score <- tryCatch({
            1 - predict(xgb_m, new_data = as.matrix(te_df[, use_vars, drop = FALSE]), eval_times = horizon)
          }, error = function(e) suppressWarnings(as.numeric(predict(xgb_m, new_data = as.matrix(te_df[, use_vars, drop = FALSE])))))
          xgb_cidx <- cindex(te_df$time, te_df$status, as.numeric(xgb_score))
          xgb_feature_space <- use_vars
          rows[[length(rows)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx)
          # Uno C at 1-year
          xgb_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(xgb_score), eval_time = horizon)
          rows_uno[[length(rows_uno)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx_uno)
        } else {
          # Sanitize factor levels to avoid duplicate dummy names from special symbols
          sanitize_levels <- function(df) {
            for (nm in names(df)) {
              if (is.factor(df[[nm]])) {
                lv <- levels(df[[nm]])
                lv <- ifelse(lv == "<5", "lt5", lv)
                lv <- ifelse(lv == "\u22655", "ge5", lv)
                # Ensure uniqueness if any collisions occur after translation
                if (any(duplicated(lv))) lv <- make.unique(lv)
                levels(df[[nm]]) <- lv
              }
            }
            df
          }
          trn_df <- sanitize_levels(trn_df)
          te_df  <- sanitize_levels(te_df)

          # Provide a stable dummy naming function to avoid duplicate names
          dummy_namer <- function(var, lvl, ordinal = FALSE) {
            lvl_clean <- gsub("[^A-Za-z0-9]+", "_", as.character(lvl))
            paste(var, lvl_clean, sep = "_")
          }
          rec_xgb <- recipes::recipe(~ ., data = trn_df[, c('time','status', vars_native), drop = FALSE]) |>
            recipes::update_role(time, status, new_role = "outcome") |>
            recipes::step_impute_median(recipes::all_numeric_predictors()) |>
            recipes::step_impute_mode(recipes::all_nominal_predictors()) |>
            recipes::step_dummy(recipes::all_nominal_predictors(), one_hot = TRUE, naming = dummy_namer) |>
            recipes::step_zv(recipes::all_predictors())
          rec_xgb_prep <- recipes::prep(rec_xgb, training = trn_df)
          trn_enc <- recipes::bake(rec_xgb_prep, new_data = trn_df)
          te_enc  <- recipes::bake(rec_xgb_prep, new_data = te_df)
          # Enforce unique column names deterministically
          nm_trn <- names(trn_enc)
          names(trn_enc) <- make.unique(nm_trn)
          names(te_enc)  <- make.unique(names(te_enc))
          enc_vars <- setdiff(colnames(trn_enc), c('time','status'))
          use_vars <- if (xgb_full_flag) enc_vars else enc_vars
          if (xgb_full_flag) message(sprintf('[MC %s %d/%d] XGB_FULL(per-split encode): using ALL encoded predictors (%d)', label, which(split_idx==k), length(split_idx), length(use_vars)))
          xgb_m <- fit_xgb(trn = trn_enc, vars = use_vars)
          xgb_score <- tryCatch({
            1 - predict(xgb_m, new_data = as.matrix(te_enc[, use_vars, drop = FALSE]), eval_times = horizon)
          }, error = function(e) suppressWarnings(as.numeric(predict(xgb_m, new_data = as.matrix(te_enc[, use_vars, drop = FALSE])))))
          xgb_cidx <- cindex(te_df$time, te_df$status, as.numeric(xgb_score))
          xgb_feature_space <- use_vars
          rows[[length(rows)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx)
          # Uno C at 1-year
          xgb_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(xgb_score), eval_time = horizon)
          rows_uno[[length(rows_uno)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx_uno)
        }
      }

      # CatBoost (Python) if requested
      use_catboost <- tolower(Sys.getenv("USE_CATBOOST", unset = "0")) %in% c("1","true","yes","y")
      if (use_catboost) {
        outdir <- here::here('data','models','catboost', label, 'splits', paste0('split_', k))
        dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
        train_csv <- file.path(outdir, 'train.csv')
        test_csv  <- file.path(outdir, 'test.csv')
        use_cb_full <- tolower(Sys.getenv('CATBOOST_USE_FULL', unset = '1')) %in% c('1','true','yes','y')
        cb_vars <- if (use_cb_full && !is.null(catboost_full_vars)) catboost_full_vars else vars
        if (use_cb_full && !is.null(catboost_full_vars)) {
          message(sprintf('[MC %s %d/%d] CatBoost: using full feature set (%d vars)', label, which(split_idx==k), length(split_idx), length(cb_vars)))
        } else {
          message(sprintf('[MC %s %d/%d] CatBoost: using selected subset (%d vars)', label, which(split_idx==k), length(split_idx), length(cb_vars)))
        }
        trn_cb <- df[train_idx, c('time','status', cb_vars), drop = FALSE]
        te_cb  <- df[test_idx,  c('time','status', cb_vars), drop = FALSE]
        readr::write_csv(trn_cb, train_csv)
        readr::write_csv(te_cb,  test_csv)
        cat_cols <- names(trn_cb)[vapply(trn_cb, function(x) is.character(x) || is.factor(x), logical(1L))]
        cat_cols_arg <- if (length(cat_cols)) paste(cat_cols, collapse = ',') else ''
        py_script <- here::here('scripts','py','catboost_survival.py')
        outdir_abs <- normalizePath(outdir)
        cmd <- sprintf('python "%s" --train "%s" --test "%s" --time-col time --status-col status --outdir "%s" %s',
                       py_script, train_csv, test_csv, outdir_abs,
                       if (nzchar(cat_cols_arg)) paste0('--cat-cols "', cat_cols_arg, '"') else '')
        message("Running: ", cmd)
        status_cb <- system(cmd)
        if (status_cb != 0) warning(sprintf("CatBoost split %d returned non-zero exit status.", k))
        pred_file <- file.path(outdir, 'catboost_predictions.csv')
        if (file.exists(pred_file)) {
          pr <- readr::read_csv(pred_file, show_col_types = FALSE)
          cb_score <- pr$prediction
          cb_cidx <- cindex(te_df$time, te_df$status, as.numeric(cb_score))
          rows[[length(rows)+1]] <- data.frame(split=k, model="CatBoostPy", cindex=cb_cidx)
          # Uno C at 1-year
          cb_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(cb_score), eval_time = horizon)
          rows_uno[[length(rows_uno)+1]] <- data.frame(split=k, model="CatBoostPy", cindex=cb_cidx_uno)
          # Collect CatBoost feature importances for aggregation
          imp_file <- file.path(outdir, 'catboost_importance.csv')
          if (file.exists(imp_file)) {
            imp_df <- readr::read_csv(imp_file, show_col_types = FALSE)
            if (all(c('feature','importance') %in% names(imp_df))) {
              imp_df$split <- k; imp_df$model <- "CatBoostPy"
              fi_rows[[length(fi_rows)+1]] <- imp_df[, c('split','model','feature','importance')]
            }
          }
        }
      }

      # Permutation-based FI for ORSF/RSF/XGB (subset of variables for speed)
      if (do_fi) {
        fi_vars <- utils::head(vars, max_vars)
        fi_vars_xgb <- utils::head(if (!is.null(xgb_feature_space)) xgb_feature_space else vars, max_vars)
        for (f in fi_vars) {
          # Permute feature in test set
          te_perm <- te_df
          te_perm[[f]] <- sample(te_perm[[f]])

          # ORSF permuted c-index
          orsf_perm_score <- tryCatch({
            1 - predict(orsf_m, newdata = te_perm[, c('time','status', vars)], times = horizon)
          }, error = function(e) suppressWarnings(as.numeric(predict(orsf_m, newdata = te_perm[, c('time','status', vars)]))))
          orsf_perm_cidx <- suppressWarnings(cindex(te_perm$time, te_perm$status, as.numeric(orsf_perm_score)))
          fi_rows[[length(fi_rows)+1]] <- data.frame(split=k, model="ORSF", feature=f, importance=as.numeric(orsf_cidx - orsf_perm_cidx))

          # RSF permuted c-index
          rsf_perm_score <- tryCatch({
            ranger_predictrisk(rsf_m, newdata = te_perm, times = horizon)
          }, error = function(e) suppressWarnings(as.numeric(predict(rsf_m, data = te_perm)$predictions)))
          rsf_perm_cidx <- suppressWarnings(cindex(te_perm$time, te_perm$status, as.numeric(rsf_perm_score)))
          fi_rows[[length(fi_rows)+1]] <- data.frame(split=k, model="RSF", feature=f, importance=as.numeric(rsf_cidx - rsf_perm_cidx))

          # XGB FI over its own feature space (encoded or original vars)
          if (!is.null(xgb_m) && length(fi_vars_xgb)) {
            for (fx in fi_vars_xgb) {
              te_xgb_perm <- if (use_global_xgb && !is.null(encoded_df)) {
                encoded_df[test_idx, c('time','status', xgb_feature_space), drop = FALSE]
              } else if (exists("te_enc")) {
                if (exists("enc_vars")) te_enc[, c('time','status', enc_vars), drop = FALSE] else te_df[, c('time','status', vars), drop = FALSE]
              } else {
                te_df[, c('time','status', xgb_feature_space), drop = FALSE]
              }
              if (fx %in% colnames(te_xgb_perm)) {
                te_xgb_perm[[fx]] <- sample(te_xgb_perm[[fx]])
                xgb_perm_score <- tryCatch({
                  1 - predict(xgb_m, new_data = as.matrix(te_xgb_perm[, xgb_feature_space, drop = FALSE]), eval_times = horizon)
                }, error = function(e) suppressWarnings(as.numeric(predict(xgb_m, new_data = as.matrix(te_xgb_perm[, xgb_feature_space, drop = FALSE])))))
                xgb_perm_cidx <- suppressWarnings(cindex(te_df$time, te_df$status, as.numeric(xgb_perm_score)))
                fi_rows[[length(fi_rows)+1]] <- data.frame(split=k, model="XGB", feature=fx, importance=as.numeric(xgb_cidx - xgb_perm_cidx))
              }
            }
          }
        }
      }

      # Best-effort progress note from worker (no split_done count to avoid race)
      write_progress(split_done = NA, note = sprintf('Completed split=%d (%s)', k, label))

      list(
        rows = if (length(rows)) dplyr::bind_rows(rows) else NULL,
        rows_uno = if (length(rows_uno)) dplyr::bind_rows(rows_uno) else NULL,
        fi_rows = if (length(fi_rows)) dplyr::bind_rows(fi_rows) else NULL
      )
    }

    parallel_splits <- TRUE
    if (parallel_splits) {
      # Configure future plan with optimized settings for EC2
      workers_env <- suppressWarnings(as.integer(Sys.getenv('MC_SPLIT_WORKERS', unset = '0')))
      if (!is.finite(workers_env) || workers_env < 1) {
        cores <- tryCatch(as.numeric(future::availableCores()), error = function(e) parallel::detectCores(logical = TRUE))
        workers <- max(1L, floor(cores * 0.80))
      } else {
        workers <- workers_env
      }
      
      # Use furrr with optimized settings for high-performance EC2
      if (future::supportsMulticore()) {
        future::plan(future::multicore, workers = workers)
      } else {
        future::plan(future::multisession, workers = workers)
      }
      
      # Use furrr for better performance with optimized chunk size
      chunk_size <- max(1L, ceiling(length(split_idx) / workers))
      res_list <- furrr::future_map(
        split_idx, 
        process_split,
        .options = furrr::furrr_options(
          seed = TRUE,
          chunk_size = chunk_size,
          scheduling = 1.0  # Optimal for compute-intensive tasks
        )
      )
      
      # Combine results
      if (length(res_list)) {
        mc_rows <- do.call(dplyr::bind_rows, lapply(res_list, function(x) x$rows))
        mc_rows_uno <- do.call(dplyr::bind_rows, lapply(res_list, function(x) x$rows_uno))
        mc_fi_rows <- do.call(dplyr::bind_rows, lapply(res_list, function(x) x$fi_rows))
      }
    } else {
      for (k in split_idx) {
      message(sprintf("[MC %s %d/%d] split %d", label, which(split_idx==k), length(split_idx), k))
      test_idx <- as.integer(testing_rows[[k]])
      all_idx <- seq_len(nrow(df))
      train_idx <- setdiff(all_idx, test_idx)
      # Per-split recipe: impute using training data only (match paper); disable novel level creation
      rec_native <- prep(make_recipe(df[train_idx, c('time','status', vars), drop = FALSE], dummy_code = FALSE, add_novel = FALSE))
      trn_df <- juice(rec_native)
      te_df  <- bake(rec_native, new_data = df[test_idx, c('time','status', vars), drop = FALSE])
      vars_native <- setdiff(colnames(trn_df), c('time','status'))

      # ORSF
      orsf_m <- fit_orsf(trn = trn_df, vars = vars_native)
      orsf_score <- tryCatch({
        1 - predict(orsf_m, newdata = te_df[, c('time','status', vars_native)], times = horizon)
      }, error = function(e) suppressWarnings(as.numeric(predict(orsf_m, newdata = te_df[, c('time','status', vars_native)]))))
  orsf_cidx <- cindex(te_df$time, te_df$status, as.numeric(orsf_score))
  mc_rows[[length(mc_rows)+1]] <- data.frame(split=k, model="ORSF", cindex=orsf_cidx)
  # Uno C at 1-year
  orsf_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(orsf_score), eval_time = horizon)
  mc_rows_uno[[length(mc_rows_uno)+1]] <- data.frame(split=k, model="ORSF", cindex=orsf_cidx_uno)

      # RSF
      rsf_m <- fit_rsf(trn = trn_df, vars = vars_native)
      rsf_score <- tryCatch({
        ranger_predictrisk(rsf_m, newdata = te_df, times = horizon)
      }, error = function(e) suppressWarnings(as.numeric(predict(rsf_m, data = te_df)$predictions)))
  rsf_cidx <- cindex(te_df$time, te_df$status, as.numeric(rsf_score))
  mc_rows[[length(mc_rows)+1]] <- data.frame(split=k, model="RSF", cindex=rsf_cidx)
  # Uno C at 1-year
  rsf_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(rsf_score), eval_time = horizon)
  mc_rows_uno[[length(mc_rows_uno)+1]] <- data.frame(split=k, model="RSF", cindex=rsf_cidx_uno)

      # XGB
      xgb_m <- NULL; xgb_cidx <- NA_real_; xgb_score <- NULL; xgb_feature_space <- NULL
      if (use_global_xgb && !is.null(encoded_df) && !is.null(encoded_vars)) {
        # Subset encoded data using same row indices
        full_enc_space <- setdiff(colnames(encoded_df), c('time','status'))
        use_vars <- if (xgb_full_flag) full_enc_space else encoded_vars
        if (xgb_full_flag) message(sprintf('[MC %s %d/%d] XGB_FULL: using ALL encoded predictors (%d)', label, which(split_idx==k), length(split_idx), length(use_vars)))
        trn_enc <- encoded_df[train_idx, c('time','status', use_vars), drop = FALSE]
        te_enc  <- encoded_df[test_idx,  c('time','status', use_vars), drop = FALSE]
        xgb_m <- fit_xgb(trn = trn_enc, vars = use_vars)
        xgb_score <- tryCatch({
          1 - predict(xgb_m, new_data = as.matrix(te_enc[, use_vars, drop = FALSE]), eval_times = horizon)
        }, error = function(e) suppressWarnings(as.numeric(predict(xgb_m, new_data = as.matrix(te_enc[, use_vars, drop = FALSE])))))
  xgb_cidx <- cindex(te_df$time, te_df$status, as.numeric(xgb_score))
  xgb_feature_space <- use_vars
  mc_rows[[length(mc_rows)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx)
  # Uno C at 1-year
  xgb_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(xgb_score), eval_time = horizon)
  mc_rows_uno[[length(mc_rows_uno)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx_uno)
      } else {
        # Per-split encoding (previous behavior)
        all_num <- all(vapply(trn_df[, vars_native, drop = FALSE], is.numeric, logical(1L)))
        if (all_num) {
          use_vars <- if (xgb_full_flag) vars_native else vars_native
          xgb_m <- fit_xgb(trn = trn_df, vars = use_vars)
          xgb_score <- tryCatch({
            1 - predict(xgb_m, new_data = as.matrix(te_df[, use_vars, drop = FALSE]), eval_times = horizon)
          }, error = function(e) suppressWarnings(as.numeric(predict(xgb_m, new_data = as.matrix(te_df[, use_vars, drop = FALSE])))))
          xgb_cidx <- cindex(te_df$time, te_df$status, as.numeric(xgb_score))
          xgb_feature_space <- use_vars
          mc_rows[[length(mc_rows)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx)
          # Uno C at 1-year
          xgb_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(xgb_score), eval_time = horizon)
          mc_rows_uno[[length(mc_rows_uno)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx_uno)
        } else {
          # Sanitize factor levels to avoid duplicate dummy names from special symbols
          sanitize_levels <- function(df) {
            for (nm in names(df)) {
              if (is.factor(df[[nm]])) {
                lv <- levels(df[[nm]])
                lv <- ifelse(lv == "<5", "lt5", lv)
                lv <- ifelse(lv == "\u22655", "ge5", lv)
                # Ensure uniqueness if any collisions occur after translation
                if (any(duplicated(lv))) lv <- make.unique(lv)
                levels(df[[nm]]) <- lv
              }
            }
            df
          }
          trn_df <- sanitize_levels(trn_df)
          te_df  <- sanitize_levels(te_df)

          # Provide a stable dummy naming function to avoid duplicate names
          dummy_namer <- function(var, lvl, ordinal = FALSE) {
            lvl_clean <- gsub("[^A-Za-z0-9]+", "_", as.character(lvl))
            paste(var, lvl_clean, sep = "_")
          }
          rec_xgb <- recipes::recipe(~ ., data = trn_df[, c('time','status', vars_native), drop = FALSE]) |>
            recipes::update_role(time, status, new_role = "outcome") |>
            recipes::step_impute_median(recipes::all_numeric_predictors()) |>
            recipes::step_impute_mode(recipes::all_nominal_predictors()) |>
            recipes::step_dummy(recipes::all_nominal_predictors(), one_hot = TRUE, naming = dummy_namer) |>
            recipes::step_zv(recipes::all_predictors())
          rec_xgb_prep <- recipes::prep(rec_xgb, training = trn_df)
          trn_enc <- recipes::bake(rec_xgb_prep, new_data = trn_df)
            te_enc  <- recipes::bake(rec_xgb_prep, new_data = te_df)
          # Enforce unique column names deterministically
          nm_trn <- names(trn_enc)
          names(trn_enc) <- make.unique(nm_trn)
          names(te_enc)  <- make.unique(names(te_enc))
          enc_vars <- setdiff(colnames(trn_enc), c('time','status'))
          use_vars <- if (xgb_full_flag) enc_vars else enc_vars
          if (xgb_full_flag) message(sprintf('[MC %s %d/%d] XGB_FULL(per-split encode): using ALL encoded predictors (%d)', label, which(split_idx==k), length(split_idx), length(use_vars)))
          xgb_m <- fit_xgb(trn = trn_enc, vars = use_vars)
          xgb_score <- tryCatch({
            1 - predict(xgb_m, new_data = as.matrix(te_enc[, use_vars, drop = FALSE]), eval_times = horizon)
          }, error = function(e) suppressWarnings(as.numeric(predict(xgb_m, new_data = as.matrix(te_enc[, use_vars, drop = FALSE])))))
          xgb_cidx <- cindex(te_df$time, te_df$status, as.numeric(xgb_score))
          xgb_feature_space <- use_vars
          mc_rows[[length(mc_rows)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx)
          # Uno C at 1-year
          xgb_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(xgb_score), eval_time = horizon)
          mc_rows_uno[[length(mc_rows_uno)+1]] <- data.frame(split=k, model="XGB", cindex=xgb_cidx_uno)
        }
      }

      # CatBoost (Python) if requested
      use_catboost <- tolower(Sys.getenv("USE_CATBOOST", unset = "0")) %in% c("1","true","yes","y")
      if (use_catboost) {
        outdir <- here::here('data','models','catboost', label, 'splits', paste0('split_', k))
        dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
        train_csv <- file.path(outdir, 'train.csv')
        test_csv  <- file.path(outdir, 'test.csv')
        use_cb_full <- tolower(Sys.getenv('CATBOOST_USE_FULL', unset = '1')) %in% c('1','true','yes','y')
        cb_vars <- if (use_cb_full && !is.null(catboost_full_vars)) catboost_full_vars else vars
        if (use_cb_full && !is.null(catboost_full_vars)) {
          message(sprintf('[MC %s %d/%d] CatBoost: using full feature set (%d vars)', label, which(split_idx==k), length(split_idx), length(cb_vars)))
        } else {
          message(sprintf('[MC %s %d/%d] CatBoost: using selected subset (%d vars)', label, which(split_idx==k), length(split_idx), length(cb_vars)))
        }
        trn_cb <- df[train_idx, c('time','status', cb_vars), drop = FALSE]
        te_cb  <- df[test_idx,  c('time','status', cb_vars), drop = FALSE]
        readr::write_csv(trn_cb, train_csv)
        readr::write_csv(te_cb,  test_csv)
        cat_cols <- names(trn_cb)[vapply(trn_cb, function(x) is.character(x) || is.factor(x), logical(1L))]
        cat_cols_arg <- if (length(cat_cols)) paste(cat_cols, collapse = ',') else ''
        py_script <- here::here('scripts','py','catboost_survival.py')
        outdir_abs <- normalizePath(outdir)
        cmd <- sprintf('python "%s" --train "%s" --test "%s" --time-col time --status-col status --outdir "%s" %s',
                       py_script, train_csv, test_csv, outdir_abs,
                       if (nzchar(cat_cols_arg)) paste0('--cat-cols "', cat_cols_arg, '"') else '')
        message("Running: ", cmd)
        status_cb <- system(cmd)
        if (status_cb != 0) warning(sprintf("CatBoost split %d returned non-zero exit status.", k))
        pred_file <- file.path(outdir, 'catboost_predictions.csv')
        if (file.exists(pred_file)) {
          pr <- readr::read_csv(pred_file, show_col_types = FALSE)
          cb_score <- pr$prediction
          cb_cidx <- cindex(te_df$time, te_df$status, as.numeric(cb_score))
          mc_rows[[length(mc_rows)+1]] <- data.frame(split=k, model="CatBoostPy", cindex=cb_cidx)
          # Uno C at 1-year
          cb_cidx_uno <- cindex_uno(te_df$time, te_df$status, as.numeric(cb_score), eval_time = horizon)
          mc_rows_uno[[length(mc_rows_uno)+1]] <- data.frame(split=k, model="CatBoostPy", cindex=cb_cidx_uno)
          # Collect CatBoost feature importances for aggregation
          imp_file <- file.path(outdir, 'catboost_importance.csv')
          if (file.exists(imp_file)) {
            imp_df <- readr::read_csv(imp_file, show_col_types = FALSE)
            if (all(c('feature','importance') %in% names(imp_df))) {
              imp_df$split <- k; imp_df$model <- "CatBoostPy"
              mc_fi_rows[[length(mc_fi_rows)+1]] <- imp_df[, c('split','model','feature','importance')]
            }
          }
        }
      }

      # Permutation-based FI for ORSF/RSF/XGB (subset of variables for speed)
      if (do_fi) {
        fi_vars <- utils::head(vars, max_vars)
        fi_vars_xgb <- utils::head(if (!is.null(xgb_feature_space)) xgb_feature_space else vars, max_vars)
        for (f in fi_vars) {
          # Permute feature in test set
          te_perm <- te_df
          te_perm[[f]] <- sample(te_perm[[f]])

          # ORSF permuted c-index
          orsf_perm_score <- tryCatch({
            1 - predict(orsf_m, newdata = te_perm[, c('time','status', vars)], times = horizon)
          }, error = function(e) suppressWarnings(as.numeric(predict(orsf_m, newdata = te_perm[, c('time','status', vars)]))))
          orsf_perm_cidx <- suppressWarnings(cindex(te_perm$time, te_perm$status, as.numeric(orsf_perm_score)))
          mc_fi_rows[[length(mc_fi_rows)+1]] <- data.frame(split=k, model="ORSF", feature=f, importance=as.numeric(orsf_cidx - orsf_perm_cidx))

          # RSF permuted c-index
          rsf_perm_score <- tryCatch({
            ranger_predictrisk(rsf_m, newdata = te_perm, times = horizon)
          }, error = function(e) suppressWarnings(as.numeric(predict(rsf_m, data = te_perm)$predictions)))
          rsf_perm_cidx <- suppressWarnings(cindex(te_perm$time, te_perm$status, as.numeric(rsf_perm_score)))
          mc_fi_rows[[length(mc_fi_rows)+1]] <- data.frame(split=k, model="RSF", feature=f, importance=as.numeric(rsf_cidx - rsf_perm_cidx))

          # XGB permuted c-index (only if model fit)
          # XGB FI over its own feature space (encoded or original vars)
          if (!is.null(xgb_m) && length(fi_vars_xgb)) {
            # Randomly choose a mapped feature if spaces differ (only if var not present in XGB space)
            for (fx in fi_vars_xgb) {
          te_xgb_perm <- if (use_global_xgb && !is.null(encoded_df)) {
                encoded_df[test_idx, c('time','status', xgb_feature_space), drop = FALSE]
              } else if (exists("te_enc")) {
                # te_enc may exist from per-split encoding branch
                if (exists("enc_vars")) te_enc[, c('time','status', enc_vars), drop = FALSE] else te_df[, c('time','status', vars), drop = FALSE]
              } else {
                te_df[, c('time','status', xgb_feature_space), drop = FALSE]
              }
              if (fx %in% colnames(te_xgb_perm)) {
                te_xgb_perm[[fx]] <- sample(te_xgb_perm[[fx]])
                xgb_perm_score <- tryCatch({
                  1 - predict(xgb_m, new_data = as.matrix(te_xgb_perm[, xgb_feature_space, drop = FALSE]), eval_times = horizon)
                }, error = function(e) suppressWarnings(as.numeric(predict(xgb_m, new_data = as.matrix(te_xgb_perm[, xgb_feature_space, drop = FALSE])))))
                xgb_perm_cidx <- suppressWarnings(cindex(te_df$time, te_df$status, as.numeric(xgb_perm_score)))
                mc_fi_rows[[length(mc_fi_rows)+1]] <- data.frame(split=k, model="XGB", feature=fx, importance=as.numeric(xgb_cidx - xgb_perm_cidx))
              }
            }
          }
        }
      }
      # Update progress after each split of this label
        splits_completed <- which(split_idx == k)
        write_progress(split_done = splits_completed, note = sprintf('Last split=%d (%s)', k, label))
      }
    }

  mc_metrics <- dplyr::bind_rows(mc_rows)
    readr::write_csv(mc_metrics, here::here('data','models', sprintf('model_mc_metrics_%s.csv', label)))
    message(sprintf("Saved: data/models/model_mc_metrics_%s.csv", label))

    mc_summary <- mc_metrics %>% dplyr::group_by(model) %>% dplyr::summarise(
      n_splits = dplyr::n(),
      mean_cindex = mean(cindex, na.rm = TRUE),
      sd_cindex = stats::sd(cindex, na.rm = TRUE),
      ci_lower = mean_cindex + stats::qt(0.025, df = pmax(n_splits-1,1)) * sd_cindex / sqrt(pmax(n_splits,1)),
      ci_upper = mean_cindex + stats::qt(0.975, df = pmax(n_splits-1,1)) * sd_cindex / sqrt(pmax(n_splits,1))
    )
    readr::write_csv(mc_summary, here::here('data','models', sprintf('model_mc_summary_%s.csv', label)))
    message(sprintf("Saved: data/models/model_mc_summary_%s.csv", label))

    # Also save Uno's C metrics/summaries if computed
    if (length(mc_rows_uno)) {
      mc_metrics_uno <- dplyr::bind_rows(mc_rows_uno)
      readr::write_csv(mc_metrics_uno, here::here('data','models', sprintf('model_mc_metrics_%s_uno.csv', label)))
      message(sprintf("Saved: data/models/model_mc_metrics_%s_uno.csv", label))
      mc_summary_uno <- mc_metrics_uno %>% dplyr::group_by(model) %>% dplyr::summarise(
        n_splits = dplyr::n(),
        mean_cindex = mean(cindex, na.rm = TRUE),
        sd_cindex = stats::sd(cindex, na.rm = TRUE),
        ci_lower = mean_cindex + stats::qt(0.025, df = pmax(n_splits-1,1)) * sd_cindex / sqrt(pmax(n_splits,1)),
        ci_upper = mean_cindex + stats::qt(0.975, df = pmax(n_splits-1,1)) * sd_cindex / sqrt(pmax(n_splits,1))
      )
      readr::write_csv(mc_summary_uno, here::here('data','models', sprintf('model_mc_summary_%s_uno.csv', label)))
      message(sprintf("Saved: data/models/model_mc_summary_%s_uno.csv", label))
    }

    if (length(mc_fi_rows)) {
      mc_fi <- dplyr::bind_rows(mc_fi_rows)
      readr::write_csv(mc_fi, here::here('data','models', sprintf('model_mc_importance_splits_%s.csv', label)))
      message(sprintf("Saved: data/models/model_mc_importance_splits_%s.csv", label))
      mc_fi_summary <- mc_fi %>% dplyr::group_by(model, feature) %>% dplyr::summarise(
        n_splits = dplyr::n(),
        mean_importance = mean(importance, na.rm = TRUE),
        sd_importance = stats::sd(importance, na.rm = TRUE),
        .groups = 'drop'
      ) %>% dplyr::arrange(model, dplyr::desc(mean_importance))
      readr::write_csv(mc_fi_summary, here::here('data','models', sprintf('model_mc_importance_%s.csv', label)))
      message(sprintf("Saved: data/models/model_mc_importance_%s.csv", label))

      # Ranger (RSF) + CatBoost union importance aggregation
      if (any(mc_fi_summary$model %in% c('RSF')) && any(mc_fi_summary$model %in% c('CatBoostPy'))) {
        rsf_imp <- dplyr::filter(mc_fi_summary, model == 'RSF') %>% dplyr::select(feature, rsf_mean = mean_importance)
        cb_imp  <- dplyr::filter(mc_fi_summary, model == 'CatBoostPy') %>% dplyr::select(feature, cb_mean = mean_importance)
        union_imp <- dplyr::full_join(rsf_imp, cb_imp, by = 'feature')
        # Normalize each model's mean to [0,1] independently (robust to negative or zero-only sets)
        norm01 <- function(x) {
          if (all(is.na(x))) return(x)
          rng <- range(x, na.rm = TRUE)
          if (diff(rng) == 0) return(ifelse(is.na(x), NA_real_, 1))
          (x - rng[1]) / diff(rng)
        }
        union_imp <- union_imp %>%
          dplyr::mutate(
            rsf_norm = norm01(rsf_mean),
            cb_norm  = norm01(cb_mean),
            # Combined score: average of available normalized scores
            combined_score = rowMeans(cbind(rsf_norm, cb_norm), na.rm = TRUE),
            combined_rank = dplyr::min_rank(dplyr::desc(combined_score))
          ) %>% dplyr::arrange(combined_rank, feature)
        out_union <- here::here('data','models', sprintf('model_mc_importance_union_rsf_catboost_%s.csv', label))
        readr::write_csv(union_imp, out_union)
        message(sprintf('Saved: %s (RSF + CatBoost union importance)', out_union))
        # Also save a compact top list (e.g., top 50)
        top_n <- min(50, nrow(union_imp))
        if (top_n > 0) {
          out_union_top <- here::here('data','models', sprintf('model_mc_importance_union_rsf_catboost_top50_%s.csv', label))
          readr::write_csv(utils::head(union_imp, top_n), out_union_top)
          message(sprintf('Saved: %s (top %d union features)', out_union_top, top_n))
        }
      } else {
        message('Union RSF + CatBoost importance not generated: one or both models absent in MC CV results for label ', label)
      }
    }
  }

  # Run MC for full dataset using existing resamples
  message("Running full Monte Carlo CV across resamples (full dataset)...")
  res_path <- here::here('data','resamples.rds')
  if (!file.exists(res_path)) stop("MC_CV requested but data/resamples.rds not found. Run step 02_resampling first.")
  testing_rows_full <- readRDS(res_path)
  run_mc("full", final_data, model_vars, testing_rows_full, encoded_df = encoded_full, encoded_vars = encoded_full_vars, use_global_xgb = use_global_xgb)

  # Prepare and run MC for original study period (2010-2019)
  message("Preparing original study dataset (2010-2019) for MC CV...")
  phts_all_src <- readRDS(here::here('data','phts_all.rds'))
  if (!'txpl_year' %in% names(phts_all_src)) {
    warning("txpl_year not found in phts_all; skipping original study MC CV.")
  } else {
    phts_orig <- dplyr::filter(phts_all_src, txpl_year >= 2010 & txpl_year <= 2019)
    # Rebuild features for original subset
    final_features_orig <- make_final_features(phts_orig)
    use_enc_flag <- nzchar(use_encoded) && use_encoded %in% c("1","true","TRUE")
  rec_orig <- prep(make_recipe(phts_orig, dummy_code = use_enc_flag, add_novel = FALSE))
    data_orig <- juice(rec_orig)
    names(data_orig) <- make.unique(names(data_orig))
    vars_orig <- if (use_enc_flag) final_features_orig$terms else final_features_orig$variables
    # Optional global encoded subset for XGB (original window)
    encoded_orig <- NULL; encoded_orig_vars <- NULL
    if (use_global_xgb) {
  rec_orig_enc <- prep(make_recipe(phts_orig, dummy_code = TRUE, add_novel = FALSE))
      encoded_orig <- juice(rec_orig_enc)
      names(encoded_orig) <- make.unique(names(encoded_orig))
      encoded_orig_vars <- final_features_orig$terms
      message("MC CV: Using global encoded dataset for XGB (original subset)")
    }

    # Build resamples for original subset to match count (inline)
    ntimes <- length(testing_rows_full)
    rs <- rsample::mc_cv(data = phts_orig, prop = 3/4, times = ntimes, strata = status)
    testing_rows_orig <- lapply(rs$splits, rsample::complement)
    saveRDS(testing_rows_orig, here::here('data','resamples_original.rds'))
    message("Saved: data/resamples_original.rds")

    run_mc("original", data_orig, vars_orig, testing_rows_orig, encoded_df = encoded_orig, encoded_vars = encoded_orig_vars, use_global_xgb = use_global_xgb)
  }

  # Prepare and run MC for COVID-era dataset (configurable; default 2020 to max year)
  message("Preparing COVID-era dataset for MC CV...")
  phts_all_src2 <- readRDS(here::here('data','phts_all.rds'))
  if (!'txpl_year' %in% names(phts_all_src2)) {
    warning("txpl_year not found in phts_all; skipping COVID-era MC CV.")
  } else {
    covid_min <- suppressWarnings(as.integer(Sys.getenv('COVID_MIN_YEAR', unset = '2020')))
    covid_max <- suppressWarnings(as.integer(Sys.getenv('COVID_MAX_YEAR', unset = '3000')))
    if (!is.finite(covid_min)) covid_min <- 2020L
    if (!is.finite(covid_max)) covid_max <- 3000L
    phts_covid <- dplyr::filter(phts_all_src2, txpl_year >= covid_min & txpl_year <= covid_max)
    if (nrow(phts_covid) < 50) {
      warning(sprintf("COVID-era subset too small (n=%d); skipping MC CV.", nrow(phts_covid)))
    } else {
      # Rebuild features for COVID subset
      final_features_covid <- make_final_features(phts_covid, n_predictors = 15)
      use_enc_flag2 <- nzchar(use_encoded) && use_encoded %in% c("1","true","TRUE")
      rec_covid <- prep(make_recipe(phts_covid, dummy_code = use_enc_flag2, add_novel = FALSE))
      data_covid <- juice(rec_covid)
      names(data_covid) <- make.unique(names(data_covid))
      vars_covid <- if (use_enc_flag2) final_features_covid$terms else final_features_covid$variables
      # Optional global encoded subset for XGB (covid window) to ensure row indices align
      encoded_covid <- NULL; encoded_covid_vars <- NULL
      if (use_global_xgb) {
        rec_covid_enc <- prep(make_recipe(phts_covid, dummy_code = TRUE, add_novel = FALSE))
        encoded_covid <- juice(rec_covid_enc)
        names(encoded_covid) <- make.unique(names(encoded_covid))
        encoded_covid_vars <- final_features_covid$terms
        message("MC CV: Using global encoded dataset for XGB (covid subset)")
      }
      # Build resamples for COVID subset to match count (inline)
      ntimes2 <- length(testing_rows_full)
      rs2 <- rsample::mc_cv(data = phts_covid, prop = 3/4, times = ntimes2, strata = status)
      testing_rows_covid <- lapply(rs2$splits, rsample::complement)
      saveRDS(testing_rows_covid, here::here('data','resamples_covid.rds'))
      message("Saved: data/resamples_covid.rds")
      run_mc("covid", data_covid, vars_covid, testing_rows_covid, encoded_df = encoded_covid, encoded_vars = encoded_covid_vars, use_global_xgb = use_global_xgb)
    }
  }

  # Prepare and run MC for full_no_covid dataset (<= 2019)
  message("Preparing full_no_covid dataset (<=2019) for MC CV...")
  phts_all_src3 <- readRDS(here::here('data','phts_all.rds'))
  if (!'txpl_year' %in% names(phts_all_src3)) {
    warning("txpl_year not found in phts_all; skipping full_no_covid MC CV.")
  } else {
    phts_fnc <- dplyr::filter(phts_all_src3, txpl_year <= 2019)
    if (nrow(phts_fnc) < 50) {
      warning(sprintf("full_no_covid subset too small (n=%d); skipping MC CV.", nrow(phts_fnc)))
    } else {
      final_features_fnc <- make_final_features(phts_fnc)
      use_enc_flag3 <- nzchar(use_encoded) && use_encoded %in% c("1","true","TRUE")
      rec_fnc <- prep(make_recipe(phts_fnc, dummy_code = use_enc_flag3, add_novel = FALSE))
      data_fnc <- juice(rec_fnc)
      names(data_fnc) <- make.unique(names(data_fnc))
      vars_fnc <- if (use_enc_flag3) final_features_fnc$terms else final_features_fnc$variables
      # Optional global encoded subset for XGB (full_no_covid window)
      encoded_fnc <- NULL; encoded_fnc_vars <- NULL
      if (use_global_xgb) {
        rec_fnc_enc <- prep(make_recipe(phts_fnc, dummy_code = TRUE, add_novel = FALSE))
        encoded_fnc <- juice(rec_fnc_enc)
        names(encoded_fnc) <- make.unique(names(encoded_fnc))
        encoded_fnc_vars <- final_features_fnc$terms
        message("MC CV: Using global encoded dataset for XGB (full_no_covid subset)")
      }
      # Build resamples for full_no_covid to match count (inline)
      ntimes3 <- length(testing_rows_full)
      rs3 <- rsample::mc_cv(data = phts_fnc, prop = 3/4, times = ntimes3, strata = status)
      testing_rows_fnc <- lapply(rs3$splits, rsample::complement)
      saveRDS(testing_rows_fnc, here::here('data','resamples_full_no_covid.rds'))
      message("Saved: data/resamples_full_no_covid.rds")
      run_mc("full_no_covid", data_fnc, vars_fnc, testing_rows_fnc, encoded_df = encoded_fnc, encoded_vars = encoded_fnc_vars, use_global_xgb = use_global_xgb)
    }
  }
}

# Back-compat: keep ORSF as final_model.rds (trained on full data)
final_orsf_full <- fit_orsf(trn = final_data, vars = model_vars)
saveRDS(final_orsf_full, here::here('data', 'final_model.rds'))
message("Saved: final_model.rds (ORSF, full-data)")

# Write a comparison index for single-fit case; empty in MC mode
if (!exists("cmp")) {
  cmp <- data.frame(
    model = character(0), file = character(0), use_encoded = integer(0),
    timestamp = character(0), stringsAsFactors = FALSE
  )
}
readr::write_csv(cmp, here::here('data','models','model_comparison_index.csv'))
message("Saved: data/models/model_comparison_index.csv")

# Model Selection Heuristic (standardized across docs):
# 1. Primary metric: mean Monte Carlo C-index (full dataset label).
# 2. Tie / practical equivalence (overlapping 95% CIs within absolute 0.005):
#    a. Prefer lower SD (stability)
#    b. Prefer broader clinically interpretable feature signal (importance dispersion across plausible predictors)
#    c. If still tied: defer to domain/clinical interpretability consensus (deployment complexity NOT a criterion)
# Notes:
# - Single-fit mode (MC_CV=0) is exploratory only; final decision should reference MC summaries.
# - Union importance (RSF + CatBoost) supports interpretation, not ranking.
# - Future: calibration or additional metrics (time-dependent AUC, Brier/IBS) may extend criteria.

# Append session info snapshot for reproducibility
try({
  si_path <- here::here('logs', paste0('sessionInfo_step04_', format(Sys.time(), '%Y%m%d_%H%M%S'), '.txt'))
  dir.create(here::here('logs'), showWarnings = FALSE, recursive = TRUE)
  utils::capture.output(sessionInfo(), file = si_path)
  message('Saved sessionInfo to ', si_path)
}, silent = TRUE)

