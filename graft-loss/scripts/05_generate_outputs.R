source("scripts/00_setup.R")
cat(sprintf("[%s] After setup: starting outputs script\n", format(Sys.time(), "%H:%M:%S")))
flush.console()

dir.create(here::here('data', 'outputs'), showWarnings = FALSE, recursive = TRUE)
log_conn <- file(here::here('data','outputs','run_outputs.log'), open = 'wt')
sink(log_conn, split = TRUE)
sink(log_conn, type = 'message', append = TRUE)
on.exit({
  try(sink(type = 'message'))
  try(sink())
  try(close(log_conn))
}, add = TRUE)

log_step <- function(msg) {
  message(sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), msg))
  flush.console()
}

message("Outputs logging started.")

log_step("Outputs logging started.")
log_step("Loading inputs")
phts_all <- readRDS(here::here('data', 'phts_all.rds'))
labels <- readRDS(here::here('data', 'labels.rds'))
final_features <- readRDS(here::here('data', 'final_features.rds'))
final_recipe <- readRDS(here::here('data', 'final_recipe.rds'))
final_data <- readRDS(here::here('data', 'final_data.rds'))
default_final_model_path <- here::here('data', 'final_model.rds')
final_model <- readRDS(default_final_model_path)
model_for_outputs <- final_model
model_for_outputs_path <- default_final_model_path
# For partial dependence, prefer an R-native model that supports newdata+times (ORSF/RSF)
partials_model <- final_model
partials_model_name <- 'ORSF'
log_step(sprintf("Loaded: n=%s, p=%s; features=%s", nrow(final_data), ncol(final_data), length(final_features$variables)))

# Optional: model comparison metrics (C-index) across saved models
log_step("Computing model comparison metrics (if models present)")
cmp_idx_path <- here::here('data','models','model_comparison_index.csv')
split_idx_path <- here::here('data','models','split_indices.rds')
metrics <- NULL
skip_metrics <- tolower(Sys.getenv('SKIP_COMPARISON_METRICS', unset = '0')) %in% c('1','true','yes','y')
if (!skip_metrics && file.exists(cmp_idx_path)) tryCatch({
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
    mfile <- here::here(cmp_idx$file[i])
    if (!file.exists(mfile)) {
      next
    }
    if (mname %in% c('ORSF')) {
      mdl <- readRDS(mfile)
      horizon <- 1
      score <- tryCatch({
        1 - predict(mdl, newdata = te[, c('time','status', final_features$variables), drop = FALSE], times = horizon)
      }, error = function(e) {
        suppressWarnings(as.numeric(predict(mdl, newdata = te[, c('time','status', final_features$variables), drop = FALSE])))
      })
  rows[[length(rows)+1]] <- data.frame(model=mname, cindex=cindex(te$time, te$status, as.numeric(score)))
    } else if (mname %in% c('RSF')) {
      mdl <- readRDS(mfile)
      horizon <- 1
      score <- tryCatch({
        ranger_predictrisk(mdl, newdata = te, times = horizon)
      }, error = function(e) {
        suppressWarnings(as.numeric(predict(mdl, data = te)$predictions))
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
        1 - predict(mdl, new_data = xmat, eval_times = horizon)
      }, error = function(e) {
        suppressWarnings(as.numeric(predict(mdl, new_data = xmat)))
      })
  rows[[length(rows)+1]] <- data.frame(model=mname, cindex=cindex(te$time, te$status, as.numeric(score)))
    } else if (mname %in% c('CatBoostPy')) {
      # Load predictions saved by Python script
      pred_csv <- here::here('data','models','catboost','catboost_predictions.csv')
      if (file.exists(pred_csv)) {
        pr <- readr::read_csv(pred_csv, show_col_types = FALSE)
        score <- pr$prediction
  rows[[length(rows)+1]] <- data.frame(model=mname, cindex=cindex(te$time, te$status, as.numeric(score)))
      }
    }
  }
  if (length(rows)) {
    metrics_local <- dplyr::bind_rows(rows)
    readr::write_csv(metrics_local, here::here('data','models','model_comparison_metrics.csv'))
    log_step('Saved: data/models/model_comparison_metrics.csv')

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
  supported <- metrics_local %>% dplyr::filter(model %in% c('ORSF','RSF','XGB')) %>% dplyr::arrange(dplyr::desc(cindex)) %>% dplyr::slice(1)
        if (nrow(supported) == 1) {
          cmprow2 <- tryCatch({ cmp_idx %>% dplyr::filter(model == supported$model[1]) %>% dplyr::slice(1) }, error = function(e) NULL)
          if (!is.null(cmprow2) && nrow(cmprow2) == 1 && !is.na(cmprow2$file[1])) {
            supported_path <- here::here(cmprow2$file[1])
            if (file.exists(supported_path)) {
              # If the supported model is XGB, avoid using it for partials; prefer ORSF/RSF
              if (identical(supported$model[1], 'XGB')) {
                # Try ORSF first, then RSF, then fallback to default_final_model_path
                orsf_row <- tryCatch({ cmp_idx %>% dplyr::filter(model == 'ORSF') %>% dplyr::slice(1) }, error = function(e) NULL)
                rsf_row  <- tryCatch({ cmp_idx %>% dplyr::filter(model == 'RSF') %>% dplyr::slice(1) }, error = function(e) NULL)
                chosen_partials <- NULL; chosen_partials_name <- NULL
                if (!is.null(orsf_row) && nrow(orsf_row) == 1 && !is.na(orsf_row$file[1]) && file.exists(here::here(orsf_row$file[1]))) {
                  chosen_partials <- readRDS(here::here(orsf_row$file[1])); chosen_partials_name <- 'ORSF'
                } else if (!is.null(rsf_row) && nrow(rsf_row) == 1 && !is.na(rsf_row$file[1]) && file.exists(here::here(rsf_row$file[1]))) {
                  chosen_partials <- readRDS(here::here(rsf_row$file[1])); chosen_partials_name <- 'RSF'
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
          # Prefer ORSF, then RSF, else fallback to final_model
          orsf_row <- tryCatch({ cmp_idx %>% dplyr::filter(model == 'ORSF') %>% dplyr::slice(1) }, error = function(e) NULL)
          rsf_row  <- tryCatch({ cmp_idx %>% dplyr::filter(model == 'RSF') %>% dplyr::slice(1) }, error = function(e) NULL)
          if (!is.null(orsf_row) && nrow(orsf_row) == 1 && !is.na(orsf_row$file[1]) && file.exists(here::here(orsf_row$file[1]))) {
            partials_model <- readRDS(here::here(orsf_row$file[1])); partials_model_name <- 'ORSF'
          } else if (!is.null(rsf_row) && nrow(rsf_row) == 1 && !is.na(rsf_row$file[1]) && file.exists(here::here(rsf_row$file[1]))) {
            partials_model <- readRDS(here::here(rsf_row$file[1])); partials_model_name <- 'RSF'
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
      readr::write_csv(choice_df, here::here('data','models','final_model_choice.csv'))
      log_step('Saved: data/models/final_model_choice.csv')
    }
  } else {
    log_step("No comparable models/predictions found for metrics.")
  }
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
  partial_table_data <- make_partial_table_data(final_partial, labels)
  log_step("Built partial_table_data")
}

top10_features <- final_features$variables[1:10]
other_features <- final_features$variables[-c(1:10)]

log_step("Creating tables: tbl_one (timeout=120s)")
tbl_one <- R.utils::withTimeout(tabulate_characteristics(phts_all, labels, top10_features), timeout = 120, onTimeout = "error")
log_step("Creating tables: tbl_predictor_smry (timeout=120s)")
tbl_predictor_smry <- R.utils::withTimeout(tabulate_predictor_smry(phts_all, labels), timeout = 120, onTimeout = "error")
log_step("Creating tables: tbl_variables (timeout=120s)")
tbl_variables <- R.utils::withTimeout(tabulate_missingness(final_recipe, phts_all, final_features, labels), timeout = 120, onTimeout = "error")
if (!skip_partials) {
  log_step("Creating tables: tbl_partial_main/supp (timeout=120s)")
  tbl_partial_main <- R.utils::withTimeout(tabulate_partial_table_data(partial_table_data, top10_features), timeout = 120, onTimeout = "error")
  tbl_partial_supp <- R.utils::withTimeout(tabulate_partial_table_data(partial_table_data, other_features), timeout = 120, onTimeout = "error")
}

log_step("Saving outputs")
if (!skip_partials) {
  saveRDS(final_partial, here::here('data', 'outputs', 'final_partial.rds'))
  saveRDS(partial_cpbypass, here::here('data', 'outputs', 'partial_cpbypass.rds'))
  saveRDS(partial_table_data, here::here('data', 'outputs', 'partial_table_data.rds'))
}
saveRDS(tbl_one, here::here('data', 'outputs', 'tbl_one.rds'))
saveRDS(tbl_predictor_smry, here::here('data', 'outputs', 'tbl_predictor_smry.rds'))
saveRDS(tbl_variables, here::here('data', 'outputs', 'tbl_variables.rds'))
if (!skip_partials) {
  saveRDS(tbl_partial_main, here::here('data', 'outputs', 'tbl_partial_main.rds'))
  saveRDS(tbl_partial_supp, here::here('data', 'outputs', 'tbl_partial_supp.rds'))
}
log_step('Saved outputs to data/outputs')

# Simple normalized feature-importance tables from MC-CV (if available)
log_step('Building normalized feature-importance tables (MC-CV)')

fi_paths <- list(
  full = here::here('data','models','model_mc_importance_full.csv'),
  original = here::here('data','models','model_mc_importance_original.csv'),
  covid = here::here('data','models','model_mc_importance_covid.csv'),
  full_no_covid = here::here('data','models','model_mc_importance_full_no_covid.csv')
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
  out1 <- here::here('data','models','model_mc_importance_normalized.csv')
  readr::write_csv(fi_norm_all, out1)
  log_step(sprintf('Saved: %s', out1))
}
if (length(fi_by_model_rows)) {
  fi_by_model_all <- dplyr::bind_rows(fi_by_model_rows) %>% dplyr::arrange(dataset, model)
  out2 <- here::here('data','models','model_mc_importance_by_model.csv')
  readr::write_csv(fi_by_model_all, out2)
  log_step(sprintf('Saved: %s', out2))
}

# --- Model Selection Rationale Artifact (JSON + CSV + MD) ----------------------------------
log_step('Building model selection rationale artifacts')
tryCatch({
  # Helper: read MC metrics if present; fall back to single-run metrics computed earlier
  mc_metric_files <- list.files(here::here('data','models'), pattern = '^model_mc_metrics_.*\\.csv$', full.names = TRUE)
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
    # Summaries
    summary_df <- sel_df %>%
      dplyr::group_by(model) %>%
      dplyr::summarise(
        n_splits = dplyr::n(),
        mean_cindex = mean(cindex, na.rm = TRUE),
        sd_cindex = stats::sd(cindex, na.rm = TRUE),
        ci_lower = mean_cindex - 1.96 * sd_cindex / sqrt(n_splits),
        ci_upper = mean_cindex + 1.96 * sd_cindex / sqrt(n_splits),
        .groups = 'drop'
      ) %>%
      dplyr::arrange(dplyr::desc(mean_cindex))

    # Feature dispersion proxy: number of moderately contributing features (normalized_importance >= 0.1)
    dispersion <- NULL
    norm_fi_path <- here::here('data','models','model_mc_importance_normalized.csv')
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

    # Apply heuristic
    path_log <- c()
    tie_ci_threshold <- 0.005
    # Primary: highest mean cindex
    top_mean <- summary_df$mean_cindex[1]
    top_model <- summary_df$model[1]
    path_log <- c(path_log, sprintf('Primary metric: %s (mean C-index=%.4f)', top_model, top_mean))
    # Identify practical equivalents
    summary_df$practical_equiv <- with(summary_df, (abs(mean_cindex - top_mean) <= tie_ci_threshold) &
      (pmax(ci_lower, summary_df$ci_lower[1]) <= pmin(ci_upper, summary_df$ci_upper[1])))
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

    # Persist artifacts
    out_csv <- here::here('data','models','model_selection_summary.csv')
    readr::write_csv(summary_df %>% dplyr::select(dataset, model, selection_rank, selected, mean_cindex, sd_cindex, n_splits, ci_lower, ci_upper, feature_dispersion, chosen_rule), out_csv)
    # Markdown table for manuscript
    md_lines <- c(
      '# Model Selection Summary',
      sprintf('*Dataset:* %s  ', preferred_dataset),
      sprintf('*Generated:* %s', format(Sys.time(), '%Y-%m-%d %H:%M:%S %Z')),
      '',
      '| Rank | Model | Mean C-index | SD | 95% CI | n_splits | Dispersion | Selected | Rule |',
      '|------|-------|-------------:|----:|:-------|---------:|-----------:|:--------:|:-----|'
    )
    md_lines <- c(md_lines, apply(summary_df, 1, function(r) {
      sprintf('| %s | %s | %.4f | %.4f | %.4f–%.4f | %d | %s | %s | %s |',
        r['selection_rank'], r['model'], as.numeric(r['mean_cindex']), as.numeric(r['sd_cindex']), as.numeric(r['ci_lower']), as.numeric(r['ci_upper']), as.integer(r['n_splits']), ifelse(is.na(r['feature_dispersion']), 'NA', r['feature_dispersion']), ifelse(r['selected']=='TRUE','YES',''), r['chosen_rule'])
    }))
    out_md <- here::here('data','models','model_selection_summary.md')
    writeLines(md_lines, out_md)
    # JSON
    rationale <- list(
      timestamp = format(Sys.time(), '%Y-%m-%dT%H:%M:%S%z'),
      dataset_primary = preferred_dataset,
      heuristic = list(
        primary_metric = 'mean_mc_cindex',
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
          sd_cindex = d$sd_cindex[1],
          n_splits = d$n_splits[1],
            ci_lower = d$ci_lower[1],
            ci_upper = d$ci_upper[1],
            feature_dispersion = d$feature_dispersion[1],
            selected = isTRUE(d$selected[1]),
            selection_rank = d$selection_rank[1]
        )
      })
    )
    out_json <- here::here('data','models','model_selection_rationale.json')
    jsonlite::write_json(rationale, out_json, auto_unbox = TRUE, pretty = TRUE)
    log_step(sprintf('Saved: %s, %s, %s', out_csv, out_md, out_json))

    # Synchronize final_model_choice reason if file exists
    fmc_path <- here::here('data','models','final_model_choice.csv')
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
  dir.create(here::here('data','models','catboost'), showWarnings = FALSE, recursive = TRUE)
  cb_preds <- read_catboost_predictions()
  cb_imp <- read_catboost_importance()
  if (!is.null(cb_imp) && nrow(cb_imp)) {
    cb_top <- normalize_and_topn_importance(cb_imp, top_n = 25)
    if (!is.null(cb_top) && nrow(cb_top)) {
      out3 <- here::here('data','models','catboost','catboost_top_features.csv')
      readr::write_csv(cb_top, out3)
      log_step(sprintf('Saved: %s', out3))
    }
  }
  if (!is.null(cb_preds) && nrow(cb_preds)) {
    cb_sum <- summarize_predictions(cb_preds)
    if (!is.null(cb_sum)) {
      out4 <- here::here('data','models','catboost','catboost_predictions_summary.csv')
      readr::write_csv(cb_sum, out4)
      log_step(sprintf('Saved: %s', out4))
    }
  }
}

