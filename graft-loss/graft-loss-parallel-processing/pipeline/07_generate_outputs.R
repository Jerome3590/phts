cat("\n\n##############################################\n")
cat(sprintf("### STARTING STEP: 07_generate_outputs.R [%s] ###\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("##############################################\n\n")
# Resource monitoring: log memory, CPU, and elapsed time
step_start_time <- Sys.time()
cat(sprintf("[Resource] Start: %s\n", format(step_start_time, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("[Resource] Memory used: %.2f MB\n", sum(gc()[,2])))
if (.Platform$OS.type == "unix" && file.exists("/proc/self/status")) {
  status <- readLines("/proc/self/status")
  rss <- as.numeric(gsub("[^0-9]", "", status[grep("VmRSS", status)]))
  cat(sprintf("[Resource] VmRSS: %.2f MB\n", rss/1024))
}

# Diagnostic output for debugging parallel execution and logging
cat("\n[07_generate_outputs.R] Starting generate outputs script\n")
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
log_file <- switch(Sys.getenv("DATASET_COHORT", unset = ""),
  original = "logs/orch_bg_original_study.log",
  full_with_covid = "logs/orch_bg_full_with_covid.log",
  full_without_covid = "logs/orch_bg_full_without_covid.log",
  "logs/orch_bg_unknown.log"
)
cat("Log file path: ", log_file, "\n")
cat("[05_generate_outputs.R] Diagnostic output complete\n\n")

# Diagnostic: print threading and parallel info
cat(sprintf("[Diagnostic] OMP_NUM_THREADS: %s\n", Sys.getenv("OMP_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] MKL_NUM_THREADS: %s\n", Sys.getenv("MKL_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] OPENBLAS_NUM_THREADS: %s\n", Sys.getenv("OPENBLAS_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] NUMEXPR_NUM_THREADS: %s\n", Sys.getenv("NUMEXPR_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] VECLIB_MAXIMUM_THREADS: %s\n", Sys.getenv("VECLIB_MAXIMUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] parallel::detectCores(): %d\n", parallel::detectCores()))
cat(sprintf("[Diagnostic] parallel::detectCores(logical=FALSE): %d\n", parallel::detectCores(logical=FALSE)))
cat(sprintf("[Diagnostic] Sys.info()['nodename']: %s\n", Sys.info()[['nodename']]))

source("pipeline/00_setup.R")
cat(sprintf("[%s] After setup: starting outputs script\n", format(Sys.time(), "%H:%M:%S")))
flush.console()

dir.create(here::here('model_data', 'outputs'), showWarnings = FALSE, recursive = TRUE)
# Note: Logging is managed by run_pipeline.R orchestrator
# Individual pipeline scripts should not set up their own sink/on.exit handlers
# to avoid conflicts with the parent script's logging management

log_step <- function(msg) {
  message(sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), msg))
  flush.console()
}

message("Outputs logging started.")

log_step("Outputs logging started.")
log_step("Loading inputs")
phts_all <- readRDS(here::here('model_data', 'phts_all.rds'))

# Load labels with fallback creation if missing
labels_path <- here::here('model_data', 'labels.rds')
if (file.exists(labels_path)) {
  labels <- readRDS(labels_path)
  log_step("Loaded existing labels.rds")
} else {
  log_step("labels.rds not found, creating fallback labels...")
  # Create minimal labels structure
  labels <- list(
    variables = data.frame(
      variable = names(phts_all)[1:min(20, ncol(phts_all))],
      label = paste("Variable", names(phts_all)[1:min(20, ncol(phts_all))]),
      stringsAsFactors = FALSE
    ),
    categories = data.frame(
      category = c("congenital_hd", "cardiomyopathy", "no", "yes", "other"),
      label = c("Congenital heart disease", "Cardiomyopathy", "No", "Yes", "Other"),
      stringsAsFactors = FALSE
    )
  )
  # Save for future use
  saveRDS(labels, labels_path)
  log_step("Created and saved fallback labels.rds")
}

final_features <- readRDS(here::here('model_data', 'final_features.rds'))

# End of script resource monitoring
step_end_time <- Sys.time()
cat(sprintf("[Resource] End: %s\n", format(step_end_time, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("[Resource] Elapsed: %.2f sec\n", as.numeric(difftime(step_end_time, step_start_time, units = "secs"))))
cat(sprintf("[Resource] Memory used: %.2f MB\n", sum(gc()[,2])))
final_recipe <- readRDS(here::here('model_data', 'final_recipe.rds'))
final_data <- readRDS(here::here('model_data', 'final_data.rds'))
# Load models - handle both MC-CV mode (split files) and single-fit mode
cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
cat(sprintf("[Progress] Loading models for cohort: %s\n", cohort_name))

# Check if we're in MC-CV mode by looking for split files
models_dir <- here::here('models', cohort_name)
split_files <- list.files(models_dir, pattern = "_split[0-9]{3}\\.rds$", full.names = TRUE)
mc_cv_mode <- length(split_files) > 0

if (mc_cv_mode) {
  cat(sprintf("[Progress] Detected MC-CV mode: found %d split files\n", length(split_files)))
  
  # For MC-CV, we'll load one model for partial dependence (prefer ORSF split 001)
  orsf_split1 <- file.path(models_dir, "ORSF_split001.rds")
  if (file.exists(orsf_split1)) {
    final_model <- readRDS(orsf_split1)
    model_for_outputs <- final_model
    model_for_outputs_path <- orsf_split1
    partials_model <- final_model
    partials_model_name <- 'ORSF'
    cat(sprintf("[Progress] Loaded ORSF split 1 for partial dependence: %s\n", orsf_split1))
  } else {
    # Try any split file as fallback
    first_split <- split_files[1]
    final_model <- readRDS(first_split)
    model_for_outputs <- final_model
    model_for_outputs_path <- first_split
    partials_model <- final_model
    partials_model_name <- toupper(sub("_split.*", "", basename(first_split)))
    cat(sprintf("[Progress] Loaded %s for partial dependence: %s\n", partials_model_name, first_split))
  }
} else {
  # Single-fit mode: look for final_model.rds
  cohort_final_model_path <- here::here('models', cohort_name, 'final_model.rds')
  default_final_model_path <- here::here('model_data', 'final_model.rds')
  
  if (file.exists(cohort_final_model_path)) {
    final_model <- readRDS(cohort_final_model_path)
    model_for_outputs <- final_model
    model_for_outputs_path <- cohort_final_model_path
    cat(sprintf("[Progress] Loaded cohort-specific final model: %s\n", cohort_final_model_path))
  } else if (file.exists(default_final_model_path)) {
    final_model <- readRDS(default_final_model_path)
    model_for_outputs <- final_model
    model_for_outputs_path <- default_final_model_path
    cat(sprintf("[Progress] Loaded legacy final model: %s\n", default_final_model_path))
  } else {
    stop(sprintf("No final model found for cohort %s. Expected: %s", cohort_name, cohort_final_model_path))
  }
  # For partial dependence, prefer an R-native model that supports newdata+times (ORSF/CatBoost)
  partials_model <- final_model
  partials_model_name <- 'ORSF'
}

log_step(sprintf("Loaded: n=%s, p=%s; features=%s", nrow(final_data), ncol(final_data), length(final_features$variables)))

# Optional: model comparison metrics (C-index) across saved models
log_step("Computing model comparison metrics (if models present)")
# Use cohort-specific paths
cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
metrics <- NULL
skip_metrics <- tolower(Sys.getenv('SKIP_COMPARISON_METRICS', unset = '0')) %in% c('1','true','yes','y')

if (!skip_metrics) tryCatch({
  if (mc_cv_mode) {
    # MC-CV Mode: Read all split files and compute aggregated metrics
    log_step("MC-CV mode: Computing metrics across all splits")
    
    # Load resamples to get test indices
    resamples_path <- here::here('model_data', 'resamples.rds')
    if (!file.exists(resamples_path)) {
      log_step("WARNING: resamples.rds not found - cannot compute MC-CV metrics")
    } else {
      resamples <- readRDS(resamples_path)
      # resamples is a list of test index vectors, not an rsample object
      n_splits <- length(resamples)
      cat(sprintf("[MC-CV] Loaded resamples with %d splits\n", n_splits))
      cat(sprintf("[MC-CV] Resamples structure: %s\n", paste(names(resamples), collapse = ", ")))
      if (n_splits > 0) {
        cat(sprintf("[MC-CV] First split class: %s, length: %d\n", class(resamples[[1]]), length(resamples[[1]])))
      }
      
      # Get all split files by model type
      model_types <- c("ORSF", "CPH", "XGB", "CATBOOST")
      all_metrics <- list()
      
      for (model_type in model_types) {
        split_pattern <- sprintf("%s_split[0-9]{3}\\.rds$", model_type)
        model_splits <- list.files(models_dir, pattern = split_pattern, full.names = TRUE)
        
        if (length(model_splits) == 0) {
          cat(sprintf("[MC-CV] No splits found for %s\n", model_type))
          next
        }
        
        cat(sprintf("[MC-CV] Processing %d splits for %s\n", length(model_splits), model_type))
        
        # Compute C-index for each split
        split_metrics <- list()
        for (split_file in model_splits) {
          # Extract split number from filename
          split_num <- as.integer(sub(".*split([0-9]{3})\\.rds$", "\\1", basename(split_file)))
          cat(sprintf("[MC-CV] Processing split %d for %s\n", split_num, model_type))
          
          if (split_num > n_splits || split_num < 1) {
            cat(sprintf("[MC-CV] WARNING: Split %d out of range (1-%d), skipping\n", split_num, n_splits))
            next
          }
          
          # Get test indices for this split
          test_idx <- resamples[[split_num]]
          # test_idx should already be a vector of row indices
          if (!is.numeric(test_idx)) {
            cat(sprintf("[MC-CV] WARNING: Split %d indices not numeric, skipping\n", split_num))
            next
          }
          
          # Load model
          mdl <- tryCatch(readRDS(split_file), error = function(e) NULL)
          if (is.null(mdl)) {
            cat(sprintf("[MC-CV] Failed to load %s\n", basename(split_file)))
            next
          }
          
          # Get test data
          te_df <- final_data[test_idx, , drop = FALSE]
          
          # Make predictions based on model type
          score <- tryCatch({
            if (model_type == "ORSF") {
              # Check for vars_used metadata (from constant column handling)
              vars_to_use <- attr(mdl, "vars_used")
              if (is.null(vars_to_use)) vars_to_use <- final_features$variables
              safe_model_predict(mdl, newdata = te_df[, c('time', 'status', vars_to_use), drop = FALSE], times = 1)
            } else if (model_type == "CPH") {
              # Check for vars_used metadata
              vars_to_use <- attr(mdl, "vars_used")
              if (is.null(vars_to_use)) vars_to_use <- final_features$variables
              safe_model_predict(mdl, newdata = te_df[, c('time', 'status', vars_to_use), drop = FALSE], times = 1)
            } else if (model_type == "XGB") {
              # XGB needs encoded data with exact feature names from training
              # First priority: use stored feature names from training
              xgb_features <- attr(mdl, "xgb_feature_names")
              if (is.null(xgb_features)) {
                # Fallback: try vars_used metadata
                xgb_features <- attr(mdl, "vars_used")
              }
              
              if (is.null(xgb_features)) {
                # Last resort: use numeric columns only
                xgb_features <- names(te_df)[sapply(te_df, is.numeric)]
                xgb_features <- setdiff(xgb_features, c('time', 'status'))
              }
              
              # Clean column names in test data to match training
              te_df_clean <- te_df
              colnames(te_df_clean) <- gsub("[^A-Za-z0-9_]", "_", colnames(te_df_clean))
              
              # Select only the features that were used in training
              available_features <- intersect(xgb_features, colnames(te_df_clean))
              if (length(available_features) == 0) {
                cat(sprintf("[MC-CV] WARNING: No matching features found for XGB split %d\n", split_num))
                rep(NA_real_, nrow(te_df))
              } else {
                te_matrix <- as.matrix(te_df_clean[, available_features, drop = FALSE])
                safe_model_predict(mdl, new_data = te_matrix)
              }
            } else if (model_type == "CATBOOST") {
              # CatBoost prediction
              safe_model_predict(mdl, newdata = te_df, times = 1)
            }
          }, error = function(e) {
            cat(sprintf("[MC-CV] Prediction failed for %s split %d: %s\n", model_type, split_num, e$message))
            rep(NA_real_, nrow(te_df))
          })
          
          # Compute C-index
          cidx <- NA_real_
          if (!is.null(score) && length(score) == nrow(te_df) && !all(is.na(score))) {
            cidx <- tryCatch({
              surv_obj <- survival::Surv(te_df$time, te_df$status)
              as.numeric(survival::concordance(surv_obj ~ as.numeric(score))$concordance)
            }, error = function(e) NA_real_)
          }
          
          split_metrics[[length(split_metrics) + 1]] <- data.frame(
            model = model_type,
            split = split_num,
            cindex = cidx,
            n_test = nrow(te_df),
            n_predictions = sum(!is.na(score)),
            stringsAsFactors = FALSE
          )
        }
        
        if (length(split_metrics) > 0) {
          all_metrics[[model_type]] <- dplyr::bind_rows(split_metrics)
        }
      }
      
      if (length(all_metrics) > 0) {
        metrics <- dplyr::bind_rows(all_metrics)
        
        # Save per-split metrics
        metrics_file <- file.path(models_dir, 'model_mc_cv_metrics.csv')
        readr::write_csv(metrics, metrics_file)
        log_step(sprintf('Saved MC-CV per-split metrics: %s', metrics_file))
        
        # Compute summary statistics
        summary_metrics <- metrics %>%
          dplyr::group_by(model) %>%
          dplyr::summarise(
            n_splits = dplyr::n(),
            mean_cindex = mean(cindex, na.rm = TRUE),
            median_cindex = median(cindex, na.rm = TRUE),
            sd_cindex = sd(cindex, na.rm = TRUE),
            min_cindex = min(cindex, na.rm = TRUE),
            max_cindex = max(cindex, na.rm = TRUE),
            q25_cindex = quantile(cindex, 0.25, na.rm = TRUE),
            q75_cindex = quantile(cindex, 0.75, na.rm = TRUE),
            .groups = 'drop'
          ) %>%
          dplyr::arrange(dplyr::desc(median_cindex))
        
        # Save summary
        summary_file <- file.path(models_dir, 'model_mc_cv_summary.csv')
        readr::write_csv(summary_metrics, summary_file)
        log_step(sprintf('Saved MC-CV summary metrics: %s', summary_file))
        
        # Print summary to console
        cat("\n=== MC-CV Model Performance Summary ===\n")
        print(summary_metrics)
        cat("======================================\n\n")
      }
    }
  } else {
    # Single-fit mode: Original comparison logic
    cmp_idx_path <- here::here('models', cohort_name, 'model_comparison_index.csv')
    split_idx_path <- here::here('models', cohort_name, 'split_indices.rds')
    
    if (!file.exists(cmp_idx_path)) {
      log_step("Single-fit mode: model_comparison_index.csv not found")
    } else {
  cmp_idx <- readr::read_csv(cmp_idx_path, show_col_types = FALSE)
  trn_idx <- tst_idx <- NULL
  if (file.exists(split_idx_path)) {
    idxs <- readRDS(split_idx_path)
    trn_idx <- idxs$train; tst_idx <- idxs$test
  } else {
    # Fallback: 80/20 split by row order
    n <- nrow(final_data)
    split <- floor(0.8 * n)
    trn_idx <- seq_len(split)
    tst_idx <- (split+1):n
  }
  # Build evaluation frame
  te <- final_data[tst_idx, , drop = FALSE]
  # Helper to compute C-index (safe) using a non-conflicting name
  cindex <- function(time, status, pred) {
    pred <- as.numeric(pred)
    if (length(pred) != length(time) || all(is.na(pred))) return(NA_real_)
    surv_obj <- survival::Surv(time, status)
    out <- tryCatch({
      as.numeric(survival::concordance(surv_obj ~ pred)$concordance)
    }, error = function(e) NA_real_)
    out
  }
  rows <- list()
  for (i in seq_len(nrow(cmp_idx))) {
    mname <- cmp_idx$model[i]
    # Resolve model file path with cohort-specific logic
    mfile_rel <- cmp_idx$file[i]
    
    # Handle cohort-specific paths
    if (grepl('^models/', mfile_rel) || grepl('^data/models/', mfile_rel)) {
      # Path already includes models/ prefix - use as-is
      mfile <- here::here(mfile_rel)
    } else {
      # Try cohort-specific path first (models/{cohort}/), then fallback to legacy
      cohort_path <- here::here('models', cohort_name, basename(mfile_rel))
      legacy_path <- here::here('models', basename(mfile_rel))
      # Note: XGB models are now also in models/{cohort}/ not data/models/{cohort}/
      data_legacy_path <- here::here('data', 'models', basename(mfile_rel))
      
      if (file.exists(cohort_path)) {
        mfile <- cohort_path
      } else if (file.exists(legacy_path)) {
        mfile <- legacy_path
      } else if (file.exists(data_legacy_path)) {
        mfile <- data_legacy_path
      } else {
        mfile <- cohort_path  # Use cohort path as default even if it doesn't exist
      }
    }
    if (!file.exists(mfile)) {
      next
    }
    if (mname %in% c('ORSF')) {
      mdl <- readRDS(mfile)
      horizon <- 1
      score <- tryCatch({
        safe_model_predict(mdl, newdata = te[, c('time','status', final_features$variables), drop = FALSE], times = horizon)
      }, error = function(e) {
        # fallback: try safe wrapper without times, else NA
        tryCatch(as.numeric(safe_model_predict(mdl, newdata = te[, c('time','status', final_features$variables), drop = FALSE])), error = function(e2) NA_real_)
      })
  rows[[length(rows)+1]] <- data.frame(model=mname, cindex=cindex(te$time, te$status, as.numeric(score)))
    } else if (mname %in% c('CatBoost')) {
      mdl <- readRDS(mfile)
      horizon <- 1
      score <- tryCatch({
        # CatBoost prediction - use safe wrapper for compatibility
        safe_model_predict(mdl, newdata = te, times = horizon)
      }, error = function(e) {
        # Fallback to safe wrapper which will try multiple argument names and predictable shapes
        tryCatch(as.numeric(safe_model_predict(mdl, newdata = te, times = horizon)), error = function(e2) NA_real_)
      })
  rows[[length(rows)+1]] <- data.frame(model=mname, cindex=cindex(te$time, te$status, as.numeric(score)))
    } else if (mname %in% c('XGB')) {
      mdl <- readRDS(mfile)
      horizon <- 1
      # Prefer encoded dataset for XGB predictions
      enc_path <- here::here('data','final_data_encoded.rds')
      te_base <- NULL
      if (file.exists(enc_path)) {
        enc_all <- readRDS(enc_path)
        te_base <- enc_all[tst_idx, , drop = FALSE]
      } else {
        te_base <- te[, final_features$variables, drop = FALSE]
      }
      # Helper to coerce non-numeric columns to numeric codes
      coerce_numeric_df <- function(df) {
        for (nm in names(df)) {
          if (!is.numeric(df[[nm]])) {
            if (is.factor(df[[nm]])) df[[nm]] <- as.integer(df[[nm]])
            else if (is.character(df[[nm]])) df[[nm]] <- as.integer(factor(df[[nm]]))
            else if (is.logical(df[[nm]])) df[[nm]] <- as.integer(df[[nm]])
            else suppressWarnings(df[[nm]] <- as.numeric(df[[nm]]))
          }
        }
        df
      }
      # Try to discover model's feature names
      xgb_features <- tryCatch({
        if (!is.null(mdl$feature_names)) mdl$feature_names
        else if (!is.null(mdl$bst) && !is.null(mdl$bst$feature_names)) mdl$bst$feature_names
        else if (!is.null(mdl$booster) && !is.null(mdl$booster$feature_names)) mdl$booster$feature_names
        else NULL
      }, error = function(e) NULL)
      use_vars <- NULL
      if (!is.null(xgb_features)) {
        use_vars <- intersect(xgb_features, colnames(te_base))
      }
      if (is.null(use_vars) || !length(use_vars)) {
        # Fall back to encoded terms or numeric-only columns
        if (file.exists(enc_path)) {
          # guard against missing terms field
          ff_terms <- tryCatch(final_features$terms, error = function(e) NULL)
          if (is.null(ff_terms)) ff_terms <- colnames(te_base)
          use_vars <- intersect(ff_terms, colnames(te_base))
        } else {
          use_vars <- names(te_base)[vapply(te_base, is.numeric, logical(1))]
        }
      }
      te_base <- coerce_numeric_df(te_base)
      xmat <- as.matrix(te_base[, use_vars, drop = FALSE])
      score <- tryCatch({
        safe_model_predict(mdl, new_data = xmat)
      }, error = function(e) {
        suppressWarnings(as.numeric(safe_model_predict(mdl, new_data = xmat)))
      })
  rows[[length(rows)+1]] <- data.frame(model=mname, cindex=cindex(te$time, te$status, as.numeric(score)))
    } else if (mname %in% c('CPH')) {
      mdl <- readRDS(mfile)
      horizon <- 1
      score <- tryCatch({
        # CPH models: prefer safe_model_predict which handles riskRegression fallback and baseline hazard fallback
        rs <- tryCatch(safe_model_predict(mdl, newdata = te[, c('time','status', final_features$variables), drop = FALSE], times = horizon), error = function(e) NA_real_)
        if (is.numeric(rs)) {
          # safe_model_predict returns risk directly when possible
          1 - rs
        } else {
          NA_real_
        }
      }, error = function(e) {
        # Fallback: use linear predictor
        suppressWarnings(as.numeric(stats::predict(mdl, newdata = te[, c('time','status', final_features$variables), drop = FALSE])))
      })
  rows[[length(rows)+1]] <- data.frame(model=mname, cindex=cindex(te$time, te$status, as.numeric(score)))
    } else if (mname %in% c('CatBoostPy')) {
      # Load predictions saved by Python script
      pred_csv <- here::here('model_data','models','catboost','catboost_predictions.csv')
      if (file.exists(pred_csv)) {
        pr <- readr::read_csv(pred_csv, show_col_types = FALSE)
        score <- pr$prediction
  rows[[length(rows)+1]] <- data.frame(model=mname, cindex=cindex(te$time, te$status, as.numeric(score)))
      }
    }
  }
  if (length(rows)) {
    metrics_local <- dplyr::bind_rows(rows)
    
    # Save to cohort-specific directory in models/
    metrics_dir <- here::here('models', cohort_name)
    dir.create(metrics_dir, showWarnings = FALSE, recursive = TRUE)
    metrics_file <- file.path(metrics_dir, 'model_comparison_metrics.csv')
    readr::write_csv(metrics_local, metrics_file)
    log_step(sprintf('Saved: %s', metrics_file))

    # Choose best model by C-index for downstream outputs.
    best <- tryCatch({
      metrics_local %>% dplyr::arrange(dplyr::desc(cindex)) %>% dplyr::slice(1)
    }, error = function(e) NULL)
    chosen_reason <- NA_character_
    partials_model <- model_for_outputs
    partials_model_name <- 'ORSF'
    if (!is.null(best) && nrow(best) == 1) {
      chosen <- best
      if (identical(chosen$model[1], 'CatBoostPy')) {
        chosen_reason <- 'best_by_cindex_catboost'
        # For partials, select the best available R-native model but DO NOT replace final_model.rds
  supported <- metrics_local %>% dplyr::filter(model %in% c('ORSF','CatBoost','XGB','CPH')) %>% dplyr::arrange(dplyr::desc(cindex)) %>% dplyr::slice(1)
        if (nrow(supported) == 1) {
          cmprow2 <- tryCatch({ cmp_idx %>% dplyr::filter(model == supported$model[1]) %>% dplyr::slice(1) }, error = function(e) NULL)
          if (!is.null(cmprow2) && nrow(cmprow2) == 1 && !is.na(cmprow2$file[1])) {
            supported_path <- here::here(cmprow2$file[1])
            if (file.exists(supported_path)) {
              # If the supported model is XGB, avoid using it for partials; prefer ORSF/CatBoost
              if (identical(supported$model[1], 'XGB')) {
                # Try ORSF first, then CatBoost, then CPH, then fallback to default_final_model_path
                orsf_row <- tryCatch({ cmp_idx %>% dplyr::filter(model == 'ORSF') %>% dplyr::slice(1) }, error = function(e) NULL)
                catboost_row  <- tryCatch({ cmp_idx %>% dplyr::filter(model == 'CatBoost') %>% dplyr::slice(1) }, error = function(e) NULL)
                cph_row  <- tryCatch({ cmp_idx %>% dplyr::filter(model == 'CPH') %>% dplyr::slice(1) }, error = function(e) NULL)
                chosen_partials <- NULL; chosen_partials_name <- NULL
                if (!is.null(orsf_row) && nrow(orsf_row) == 1 && !is.na(orsf_row$file[1]) && file.exists(here::here(orsf_row$file[1]))) {
                  chosen_partials <- readRDS(here::here(orsf_row$file[1])); chosen_partials_name <- 'ORSF'
                } else if (!is.null(catboost_row) && nrow(catboost_row) == 1 && !is.na(catboost_row$file[1]) && file.exists(here::here(catboost_row$file[1]))) {
                  chosen_partials <- readRDS(here::here(catboost_row$file[1])); chosen_partials_name <- 'CatBoost'
                } else if (!is.null(cph_row) && nrow(cph_row) == 1 && !is.na(cph_row$file[1]) && file.exists(here::here(cph_row$file[1]))) {
                  chosen_partials <- readRDS(here::here(cph_row$file[1])); chosen_partials_name <- 'CPH'
                } else {
                  chosen_partials <- final_model; chosen_partials_name <- 'ORSF'
                }
                partials_model <- chosen_partials
                partials_model_name <- chosen_partials_name
                log_step(sprintf('CatBoost selected as best; avoiding XGB for partials. Using %s for partials.', partials_model_name))
              } else {
                partials_model <- readRDS(supported_path)
                partials_model_name <- supported$model[1]
                log_step(sprintf('CatBoost selected as best by C-index; using %s for partials.', partials_model_name))
              }
            }
          }
        } else {
          log_step('CatBoost selected as best by C-index; no supported R-native model found for partials, using default ORSF.')
        }
      } else {
        chosen_reason <- 'best_by_cindex'
        # Map to file path for chosen R-native model to ensure outputs model matches
        cmprow <- tryCatch({ cmp_idx %>% dplyr::filter(model == chosen$model[1]) %>% dplyr::slice(1) }, error = function(e) NULL)
        if (!is.null(cmprow) && nrow(cmprow) == 1 && !is.na(cmprow$file[1])) {
          chosen_path <- here::here(cmprow$file[1])
          if (file.exists(chosen_path)) {
            model_for_outputs <- readRDS(chosen_path)
            model_for_outputs_path <- chosen_path
            # Keep final_model.rds as-is; it is ORSF for back-compat
            log_step(sprintf('Using best R-native model for outputs: %s (cindex=%.4f)', chosen$model[1], chosen$cindex[1]))
          }
        }
        # For partial dependence, avoid using XGB even if it was selected for outputs.
        if (identical(chosen$model[1], 'XGB')) {
          # Prefer ORSF, then CatBoost, then CPH, else fallback to final_model
          orsf_row <- tryCatch({ cmp_idx %>% dplyr::filter(model == 'ORSF') %>% dplyr::slice(1) }, error = function(e) NULL)
          catboost_row  <- tryCatch({ cmp_idx %>% dplyr::filter(model == 'CatBoost') %>% dplyr::slice(1) }, error = function(e) NULL)
          cph_row  <- tryCatch({ cmp_idx %>% dplyr::filter(model == 'CPH') %>% dplyr::slice(1) }, error = function(e) NULL)
          if (!is.null(orsf_row) && nrow(orsf_row) == 1 && !is.na(orsf_row$file[1]) && file.exists(here::here(orsf_row$file[1]))) {
            partials_model <- readRDS(here::here(orsf_row$file[1])); partials_model_name <- 'ORSF'
          } else if (!is.null(catboost_row) && nrow(catboost_row) == 1 && !is.na(catboost_row$file[1]) && file.exists(here::here(catboost_row$file[1]))) {
            partials_model <- readRDS(here::here(catboost_row$file[1])); partials_model_name <- 'CatBoost'
          } else if (!is.null(cph_row) && nrow(cph_row) == 1 && !is.na(cph_row$file[1]) && file.exists(here::here(cph_row$file[1]))) {
            partials_model <- readRDS(here::here(cph_row$file[1])); partials_model_name <- 'CPH'
          } else {
            partials_model <- final_model; partials_model_name <- 'ORSF'
          }
          log_step(sprintf('Outputs model is XGB; using %s for partials to ensure native compatibility.', partials_model_name))
        } else {
          partials_model <- model_for_outputs
          partials_model_name <- chosen$model[1]
        }
      }

      # Record choice
      choice_df <- data.frame(
        chosen_model = if (!is.null(best)) best$model[1] else NA_character_,
        chosen_model_used_for_outputs = if (exists('chosen') && nrow(chosen) == 1) chosen$model[1] else NA_character_,
        chosen_reason = chosen_reason,
        chosen_cindex = if (!is.null(best)) best$cindex[1] else NA_real_,
        outputs_model_path = model_for_outputs_path,
        partials_model = partials_model_name,
        stringsAsFactors = FALSE
      )
      # Save to cohort-specific directory
      choice_file <- file.path(metrics_dir, 'final_model_choice.csv')
      readr::write_csv(choice_df, choice_file)
      log_step(sprintf('Saved: %s', choice_file))
    }
  } else {
    log_step("No comparable models/predictions found for metrics.")
  }
    }  # End single-fit mode else block
  }  # End mc_cv_mode if/else
}, error = function(e){
  log_step(sprintf('Metrics computation skipped due to error: %s', conditionMessage(e)))
})

skip_partials <- tolower(Sys.getenv('SKIP_PARTIALS', unset = '0')) %in% c('1','true','yes','y')
if (skip_partials) {
  log_step('SKIP_PARTIALS=1: skipping partial dependence computations and tables')
} else {
  log_step("Computing final_partial (limited vars, n_boots=50)")
  final_partial <- make_final_partial(
    final_model = partials_model,
    final_data = final_data,
    final_features = final_features,
    variables = head(final_features$variables, 10),
    n_boots = 50
  )
  log_step("Computed final_partial")

  log_step("Computing partial_cpbypass (timeout=180s, tolerant)")
  partial_cpbypass <- tryCatch({
    val <- R.utils::withTimeout({
      make_partial_cpbypass(partials_model, final_data)
    }, timeout = 180, onTimeout = "warning")
    if (is.null(val)) {
      log_step("partial_cpbypass timed out; using empty result.")
      tibble::tibble()
    } else {
      val
    }
  }, error = function(e){
    log_step(sprintf("partial_cpbypass failed: %s", conditionMessage(e)))
    tibble::tibble()
  })
  log_step("Computed partial_cpbypass (tolerant)")

  log_step("Building partial_table_data")
  partial_table_data <- tryCatch({
    make_partial_table_data(final_partial, labels)
  }, error = function(e) {
    log_step(sprintf("partial_table_data failed: %s", conditionMessage(e)))
    log_step("Creating empty partial_table_data as fallback")
    tibble::tibble()
  })
  log_step("Built partial_table_data")
}

top10_features <- final_features$variables[1:10]
other_features <- final_features$variables[-c(1:10)]

log_step("Creating tables: tbl_one (timeout=120s)")
tbl_one <- tryCatch({
  R.utils::withTimeout(tabulate_characteristics(phts_all, labels, top10_features), timeout = 120, onTimeout = "error")
}, error = function(e) {
  log_step(sprintf("tbl_one failed: %s", conditionMessage(e)))
  log_step("Creating empty tbl_one as fallback")
  tibble::tibble()
})
log_step("Creating tables: tbl_predictor_smry (timeout=120s)")
tbl_predictor_smry <- tryCatch({
  R.utils::withTimeout(tabulate_predictor_smry(phts_all, labels), timeout = 120, onTimeout = "error")
}, error = function(e) {
  log_step(sprintf("tbl_predictor_smry failed: %s", conditionMessage(e)))
  log_step("Creating empty tbl_predictor_smry as fallback")
  tibble::tibble()
})
log_step("Creating tables: tbl_variables (timeout=120s)")
tbl_variables <- tryCatch({
  R.utils::withTimeout(tabulate_missingness(final_recipe, phts_all, final_features, labels), timeout = 120, onTimeout = "error")
}, error = function(e) {
  log_step(sprintf("tbl_variables failed: %s", conditionMessage(e)))
  log_step("Creating empty tbl_variables as fallback")
  tibble::tibble()
})
if (!skip_partials) {
  log_step("Creating tables: tbl_partial_main/supp (timeout=120s)")
  tbl_partial_main <- tryCatch({
    R.utils::withTimeout(tabulate_partial_table_data(partial_table_data, top10_features), timeout = 120, onTimeout = "error")
  }, error = function(e) {
    log_step(sprintf("tbl_partial_main failed: %s", conditionMessage(e)))
    tibble::tibble()
  })
  tbl_partial_supp <- tryCatch({
    R.utils::withTimeout(tabulate_partial_table_data(partial_table_data, other_features), timeout = 120, onTimeout = "error")
  }, error = function(e) {
    log_step(sprintf("tbl_partial_supp failed: %s", conditionMessage(e)))
    tibble::tibble()
  })
}

log_step("Saving outputs")
if (!skip_partials) {
  saveRDS(final_partial, here::here('model_data', 'outputs', 'final_partial.rds'))
  saveRDS(partial_cpbypass, here::here('model_data', 'outputs', 'partial_cpbypass.rds'))
  saveRDS(partial_table_data, here::here('model_data', 'outputs', 'partial_table_data.rds'))
}
saveRDS(tbl_one, here::here('model_data', 'outputs', 'tbl_one.rds'))
saveRDS(tbl_predictor_smry, here::here('model_data', 'outputs', 'tbl_predictor_smry.rds'))
saveRDS(tbl_variables, here::here('model_data', 'outputs', 'tbl_variables.rds'))
if (!skip_partials) {
  saveRDS(tbl_partial_main, here::here('model_data', 'outputs', 'tbl_partial_main.rds'))
  saveRDS(tbl_partial_supp, here::here('model_data', 'outputs', 'tbl_partial_supp.rds'))
}
log_step('Saved outputs to model_data/outputs')

# Simple normalized feature-importance tables from MC-CV (if available)
log_step('Building normalized feature-importance tables (MC-CV)')

fi_paths <- list(
  full = here::here('model_data','models','model_mc_importance_full.csv'),
  original = here::here('model_data','models','model_mc_importance_original.csv'),
  covid = here::here('model_data','models','model_mc_importance_covid.csv'),
  full_no_covid = here::here('model_data','models','model_mc_importance_full_no_covid.csv')
)

normalize_fi <- function(df) {
  # Expect columns: model, feature, n_splits, mean_importance, sd_importance
  if (!all(c('model','feature','n_splits','mean_importance') %in% names(df))) return(NULL)
  df %>%
    dplyr::group_by(model) %>%
    dplyr::mutate(
      .min = suppressWarnings(min(mean_importance, na.rm = TRUE)),
      .max = suppressWarnings(max(mean_importance, na.rm = TRUE)),
      normalized_importance = dplyr::if_else((.max - .min) > 0,
        (mean_importance - .min) / (.max - .min),
        dplyr::if_else(!is.na(mean_importance), 1.0, NA_real_)
      )
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(model, feature, n_splits, mean_importance, normalized_importance)
}

fi_norm_rows <- list()
fi_by_model_rows <- list()
for (lbl in names(fi_paths)) {
  p <- fi_paths[[lbl]]
  if (!file.exists(p)) {
    log_step(sprintf("MC FI summary not found for '%s': %s", lbl, p))
    next
  }
  fi <- tryCatch(readr::read_csv(p, show_col_types = FALSE), error = function(e) NULL)
  if (is.null(fi) || !nrow(fi)) next
  fi_norm <- normalize_fi(fi)
  if (!is.null(fi_norm)) {
    fi_norm$dataset <- lbl
    fi_norm_rows[[length(fi_norm_rows)+1]] <- fi_norm[, c('dataset','model','feature','n_splits','mean_importance','normalized_importance')]
    # Model-level counts: total features and total occurrences (sum over n_splits)
    by_model <- fi_norm %>% dplyr::group_by(model) %>% dplyr::summarise(
      total_features = dplyr::n(),
      total_feature_occurrences = sum(n_splits, na.rm = TRUE),
      .groups = 'drop'
    )
    by_model$dataset <- lbl
    fi_by_model_rows[[length(fi_by_model_rows)+1]] <- by_model[, c('dataset','model','total_features','total_feature_occurrences')]
  }
}

if (length(fi_norm_rows)) {
  fi_norm_all <- dplyr::bind_rows(fi_norm_rows) %>% dplyr::arrange(dataset, model, dplyr::desc(normalized_importance))
  out1 <- here::here('model_data','models','model_mc_importance_normalized.csv')
  readr::write_csv(fi_norm_all, out1)
  log_step(sprintf('Saved: %s', out1))
}
if (length(fi_by_model_rows)) {
  fi_by_model_all <- dplyr::bind_rows(fi_by_model_rows) %>% dplyr::arrange(dataset, model)
  out2 <- here::here('model_data','models','model_mc_importance_by_model.csv')
  readr::write_csv(fi_by_model_all, out2)
  log_step(sprintf('Saved: %s', out2))
}

# --- Model Selection Rationale Artifact (JSON + CSV + MD) ----------------------------------
log_step('Building model selection rationale artifacts')
tryCatch({
  # Helper: read MC metrics if present; fall back to single-run metrics computed earlier
  mc_metric_files <- list.files(here::here('model_data','models'), pattern = '^model_mc_metrics_.*\\.csv$', full.names = TRUE)
  mc_metrics <- NULL
  if (length(mc_metric_files)) {
    mc_list <- lapply(mc_metric_files, function(f){
      df <- tryCatch(readr::read_csv(f, show_col_types = FALSE), error = function(e) NULL)
      if (!is.null(df) && !('dataset' %in% names(df))) {
        # infer dataset label from filename pattern model_mc_metrics_<label>.csv
        lbl <- sub('^model_mc_metrics_(.*?)\\.csv$', '\\1', basename(f))
        df$dataset <- lbl
      }
      df
    })
    mc_metrics <- dplyr::bind_rows(mc_list)
  }
  # Standardize column names expectation: dataset, model, cindex, split (optional)
  if (is.null(mc_metrics) || !nrow(mc_metrics)) {
    if (exists('metrics') && !is.null(metrics)) {
      # Single-fit provisional metrics
      mc_metrics <- metrics
      if (!('dataset' %in% names(mc_metrics))) mc_metrics$dataset <- 'single_fit'
      if (!('split' %in% names(mc_metrics))) mc_metrics$split <- 1L
    }
  }
  if (!is.null(mc_metrics) && nrow(mc_metrics) && all(c('model','cindex') %in% names(mc_metrics))) {
    # Focus on primary dataset label preference order
    preferred_dataset <- dplyr::case_when(
      any(mc_metrics$dataset == 'full') ~ 'full',
      any(mc_metrics$dataset == 'single_fit') ~ 'single_fit',
      TRUE ~ mc_metrics$dataset[1]
    )

    sel_df <- mc_metrics %>% dplyr::filter(dataset == preferred_dataset)
    # Summaries with both mean and median C-index
    summary_df <- sel_df %>%
      dplyr::group_by(model) %>%
      dplyr::summarise(
        n_splits = dplyr::n(),
        mean_cindex = mean(cindex, na.rm = TRUE),
        median_cindex = stats::median(cindex, na.rm = TRUE),        # Median C-index (more robust)
        sd_cindex = stats::sd(cindex, na.rm = TRUE),
        # Confidence intervals for median using bootstrap-style approach
        q25_cindex = stats::quantile(cindex, 0.25, na.rm = TRUE),   # 25th percentile
        q75_cindex = stats::quantile(cindex, 0.75, na.rm = TRUE),   # 75th percentile
        # 95% CI for median using order statistics approximation
        median_ci_lower = stats::quantile(cindex, pmax(0, 0.5 - 1.96 * sqrt(0.25/n_splits)), na.rm = TRUE),
        median_ci_upper = stats::quantile(cindex, pmin(1, 0.5 + 1.96 * sqrt(0.25/n_splits)), na.rm = TRUE),
        # Keep mean-based CI for comparison
        mean_ci_lower = mean_cindex - 1.96 * sd_cindex / sqrt(n_splits),
        mean_ci_upper = mean_cindex + 1.96 * sd_cindex / sqrt(n_splits),
        .groups = 'drop'
      ) %>%
      dplyr::arrange(dplyr::desc(median_cindex))  # Rank by median instead of mean

    # Feature dispersion proxy: number of moderately contributing features (normalized_importance >= 0.1)
    dispersion <- NULL
    norm_fi_path <- here::here('model_data','models','model_mc_importance_normalized.csv')
    if (file.exists(norm_fi_path)) {
      fi_norm_all <- tryCatch(readr::read_csv(norm_fi_path, show_col_types = FALSE), error = function(e) NULL)
      if (!is.null(fi_norm_all) && nrow(fi_norm_all)) {
        dispersion <- fi_norm_all %>%
          dplyr::filter(dataset == preferred_dataset) %>%
          dplyr::group_by(model) %>%
          dplyr::summarise(
            feature_dispersion = sum(!is.na(normalized_importance) & normalized_importance >= 0.1),
            .groups = 'drop'
          )
      }
    }
    if (!is.null(dispersion)) {
      summary_df <- summary_df %>% dplyr::left_join(dispersion, by = 'model')
    } else {
      summary_df$feature_dispersion <- NA_integer_
    }

    # Apply heuristic based on median C-index
    path_log <- c()
    tie_ci_threshold <- 0.005
    # Primary: highest median cindex
    top_median <- summary_df$median_cindex[1]
    top_model <- summary_df$model[1]
    path_log <- c(path_log, sprintf('Primary metric: %s (median C-index=%.4f)', top_model, top_median))
    # Identify practical equivalents using median CI overlap
    summary_df$practical_equiv <- with(summary_df, (abs(median_cindex - top_median) <= tie_ci_threshold) &
      (pmax(median_ci_lower, summary_df$median_ci_lower[1]) <= pmin(median_ci_upper, summary_df$median_ci_upper[1])))
    candidates <- summary_df %>% dplyr::filter(practical_equiv)
    chosen_rule <- 'primary_metric'
    if (nrow(candidates) > 1) {
      # Rule 1 tie-break: lower sd
      best_sd <- min(candidates$sd_cindex, na.rm = TRUE)
      cand_sd <- candidates %>% dplyr::filter(abs(sd_cindex - best_sd) < 1e-12)
      if (nrow(cand_sd) == 1) {
        chosen_rule <- 'tie_rule_sd'
        chosen_model <- cand_sd$model[1]
        path_log <- c(path_log, sprintf('Tie resolved by SD: %s (SD=%.4f)', chosen_model, cand_sd$sd_cindex[1]))
      } else {
        # Rule 2: feature dispersion (higher better)
        cand_sd$feature_dispersion[is.na(cand_sd$feature_dispersion)] <- -Inf
        best_disp <- max(cand_sd$feature_dispersion)
        cand_disp <- cand_sd %>% dplyr::filter(feature_dispersion == best_disp)
        if (nrow(cand_disp) == 1) {
          chosen_rule <- 'tie_rule_dispersion'
          chosen_model <- cand_disp$model[1]
          path_log <- c(path_log, sprintf('Tie resolved by feature dispersion: %s (disp=%d)', chosen_model, cand_disp$feature_dispersion[1]))
        } else {
          # Rule 3: clinical consensus placeholder; choose first alphabetically for determinism
            chosen_rule <- 'tie_rule_clinical_consensus_placeholder'
            chosen_model <- sort(cand_disp$model)[1]
            path_log <- c(path_log, sprintf('Remaining tie; placeholder consensus pick: %s', chosen_model))
        }
      }
    } else {
      chosen_model <- top_model
    }
    summary_df$selected <- summary_df$model == chosen_model
    # Rank ordering
    summary_df$selection_rank <- seq_len(nrow(summary_df))
    summary_df$chosen_rule <- chosen_rule
    summary_df$dataset <- preferred_dataset

    # Persist artifacts with median statistics
    out_csv <- here::here('model_data','models','model_selection_summary.csv')
    readr::write_csv(summary_df %>% dplyr::select(dataset, model, selection_rank, selected, 
                                                  mean_cindex, median_cindex, sd_cindex, n_splits, 
                                                  mean_ci_lower, mean_ci_upper, median_ci_lower, median_ci_upper,
                                                  q25_cindex, q75_cindex, feature_dispersion, chosen_rule), out_csv)
    # Markdown table for manuscript with median statistics
    md_lines <- c(
      '# Model Selection Summary',
      sprintf('*Dataset:* %s  ', preferred_dataset),
      sprintf('*Generated:* %s', format(Sys.time(), '%Y-%m-%d %H:%M:%S %Z')),
      '',
      '| Rank | Model | Mean C-index | Median C-index | SD | Median 95% CI | n_splits | Dispersion | Selected | Rule |',
      '|------|-------|-------------:|---------------:|----:|:--------------|--------:|-----------:|:--------:|:-----|'
    )
    md_lines <- c(md_lines, apply(summary_df, 1, function(r) {
      sprintf('| %s | %s | %.4f | %.4f | %.4f | %.4f–%.4f | %d | %s | %s | %s |',
        r['selection_rank'], r['model'], 
        as.numeric(r['mean_cindex']), as.numeric(r['median_cindex']), as.numeric(r['sd_cindex']), 
        as.numeric(r['median_ci_lower']), as.numeric(r['median_ci_upper']), 
        as.integer(r['n_splits']), 
        ifelse(is.na(r['feature_dispersion']), 'NA', r['feature_dispersion']), 
        ifelse(r['selected']=='TRUE','YES',''), r['chosen_rule'])
    }))
    out_md <- here::here('model_data','models','model_selection_summary.md')
    writeLines(md_lines, out_md)
    # JSON
    rationale <- list(
      timestamp = format(Sys.time(), '%Y-%m-%dT%H:%M:%S%z'),
      dataset_primary = preferred_dataset,
      heuristic = list(
        primary_metric = 'median_mc_cindex',  # Updated to median
        tie_ci_overlap_threshold = tie_ci_threshold,
        rules_order = c('primary_metric','tie_rule_sd','tie_rule_dispersion','tie_rule_clinical_consensus')
      ),
      selection = list(
        chosen_model = chosen_model,
        chosen_rule = chosen_rule,
        path = path_log
      ),
      models = lapply(split(summary_df, summary_df$model), function(d){
        list(
          model = d$model[1],
          mean_cindex = d$mean_cindex[1],
          median_cindex = d$median_cindex[1],        # Added median
          sd_cindex = d$sd_cindex[1],
          n_splits = d$n_splits[1],
          mean_ci_lower = d$mean_ci_lower[1],
          mean_ci_upper = d$mean_ci_upper[1],
          median_ci_lower = d$median_ci_lower[1],    # Added median CI
          median_ci_upper = d$median_ci_upper[1],    # Added median CI
          q25_cindex = d$q25_cindex[1],              # Added quartiles
          q75_cindex = d$q75_cindex[1],              # Added quartiles
          feature_dispersion = d$feature_dispersion[1],
          selected = isTRUE(d$selected[1]),
          selection_rank = d$selection_rank[1]
        )
      })
    )
    out_json <- here::here('model_data','models','model_selection_rationale.json')
    jsonlite::write_json(rationale, out_json, auto_unbox = TRUE, pretty = TRUE)
    log_step(sprintf('Saved: %s, %s, %s', out_csv, out_md, out_json))

    # Synchronize final_model_choice reason if file exists
    fmc_path <- here::here('model_data','models','final_model_choice.csv')
    if (file.exists(fmc_path)) {
      fmc <- tryCatch(readr::read_csv(fmc_path, show_col_types = FALSE), error = function(e) NULL)
      if (!is.null(fmc) && nrow(fmc)) {
        # Update chosen_reason with heuristic tag
        fmc$chosen_reason <- paste0('heuristic_', chosen_rule)
        fmc$chosen_model <- chosen_model
        readr::write_csv(fmc, fmc_path)
        log_step('Updated final_model_choice.csv with heuristic selection reason.')
      }
    }
  } else {
    log_step('No metrics available for selection rationale artifact.')
  }
}, error = function(e){
  log_step(sprintf("Comparison metrics skipped due to error: %s", conditionMessage(e)))
})

# CatBoost-best helpers: emit ready-to-use CSVs if CatBoost artifacts exist
log_step('Checking for CatBoost CSV artifacts')
if (exists('read_catboost_predictions')) {
  # Ensure target directory exists for convenience CSVs
  dir.create(here::here('model_data','models','catboost'), showWarnings = FALSE, recursive = TRUE)
  cb_preds <- read_catboost_predictions()
  cb_imp <- read_catboost_importance()
  if (!is.null(cb_imp) && nrow(cb_imp)) {
    cb_top <- normalize_and_topn_importance(cb_imp, top_n = 25)
    if (!is.null(cb_top) && nrow(cb_top)) {
      out3 <- here::here('model_data','models','catboost','catboost_top_features.csv')
      readr::write_csv(cb_top, out3)
      log_step(sprintf('Saved: %s', out3))
    }
  }
  if (!is.null(cb_preds) && nrow(cb_preds)) {
    cb_sum <- summarize_predictions(cb_preds)
    if (!is.null(cb_sum)) {
      out4 <- here::here('model_data','models','catboost','catboost_predictions_summary.csv')
      readr::write_csv(cb_sum, out4)
      log_step(sprintf('Saved: %s', out4))
    }
  }
}

