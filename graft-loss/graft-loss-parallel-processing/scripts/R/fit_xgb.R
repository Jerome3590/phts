##' Fit XGBoost with optimal parallel processing
##'
##' Uses XGBoost with optimized parallel processing configuration
##' 
##' @param trn Training data
##' @param vars Variable names
##' @param tst Test data (optional)
##' @param predict_horizon Prediction horizon (optional)
##' @param use_parallel Whether to use parallel processing (default: TRUE)
##' @param nthread Number of threads (NULL = auto-detect)
##' @param tree_method Tree construction method (default: 'auto')
##' @param gpu_id GPU ID for GPU acceleration (NULL = CPU only)
##' @return Fitted XGBoost model or predictions
fit_xgb <- function(trn,
                    vars,
                    tst = NULL,
                    predict_horizon = NULL,
                    use_parallel = TRUE,
                    nthread = NULL,
                    tree_method = 'auto',
                    gpu_id = NULL){

  # ENHANCED LOGGING: Log initial data diagnostics for MC-CV debugging
  predictor_vars <- if (!is.null(vars)) vars else setdiff(names(trn), c('time', 'status'))
  
  cat(sprintf("[XGB_INIT] Starting XGBoost model with %d observations, %d predictors\n", 
              nrow(trn), length(predictor_vars)))
  cat(sprintf("[XGB_INIT] Events: %d (%.1f%%), Censored: %d (%.1f%%)\n", 
              sum(trn$status), 100 * mean(trn$status), 
              sum(1 - trn$status), 100 * (1 - mean(trn$status))))
  cat(sprintf("[XGB_INIT] Events per predictor ratio: %.2f (recommended: >10)\n", 
              sum(trn$status) / length(predictor_vars)))
  
  # Check for potential MC-CV issues
  potential_issues <- character(0)
  
  for (var in predictor_vars) {
    if (var %in% names(trn)) {
      if (is.numeric(trn[[var]])) {
        var_sd <- sd(trn[[var]], na.rm = TRUE)
        if (is.finite(var_sd) && var_sd < 1e-10) {
          potential_issues <- c(potential_issues, sprintf("%s (zero variance)", var))
        }
      } else if (is.factor(trn[[var]]) || is.character(trn[[var]])) {
        var_table <- table(trn[[var]], useNA = "ifany")
        if (length(var_table) == 1) {
          potential_issues <- c(potential_issues, sprintf("%s (single level)", var))
        } else if (any(var_table < 5)) {
          small_levels <- names(var_table)[var_table < 5]
          potential_issues <- c(potential_issues, sprintf("%s (small levels: %s)", var, paste(small_levels, collapse = ",")))
        }
      }
    }
  }
  
  if (length(potential_issues) > 0) {
    cat(sprintf("[XGB_INIT] Potential MC-CV issues detected in %d variables:\n", length(potential_issues)))
    for (issue in potential_issues) {
      cat(sprintf("[XGB_INIT] - %s\n", issue))
    }
  } else {
    cat("[XGB_INIT] No obvious MC-CV data issues detected\n")
  }

  # Guard: ensure all requested predictor columns exist
  missing_cols <- setdiff(vars, names(trn))
  if (length(missing_cols)) {
    stop(sprintf("fit_xgb: missing predictor columns: %s", paste(missing_cols, collapse=", ")), call. = FALSE)
  }

  # Extract predictor frame
  x_frame <- dplyr::select(trn, dplyr::all_of(vars))

  # Handle non-numeric columns instead of failing early: coerce factors/characters to integer codes.
  non_numeric <- names(x_frame)[!vapply(x_frame, is.numeric, logical(1))]
  if (length(non_numeric)) {
    message("fit_xgb: coercing non-numeric predictors to integer codes: ", paste(non_numeric, collapse=", "))
    for (nm in non_numeric) {
      # Convert factor/character/logical to integer codes (stable ordering for factor levels)
      if (is.factor(x_frame[[nm]])) {
        x_frame[[nm]] <- as.integer(x_frame[[nm]])
      } else if (is.character(x_frame[[nm]])) {
        x_frame[[nm]] <- as.integer(factor(x_frame[[nm]]))
      } else if (is.logical(x_frame[[nm]])) {
        x_frame[[nm]] <- as.integer(x_frame[[nm]])
      } else {
        # Fallback: best-effort numeric coercion
        suppressWarnings(x_frame[[nm]] <- as.numeric(x_frame[[nm]]))
      }
    }
  }

  # Build training matrix limited to vars for clarity (avoid unintended columns)
  # Ensure all data is numeric before creating matrix
  trn_x <- as.matrix(x_frame)
  
  # Additional safety check: ensure matrix is numeric
  if (!is.numeric(trn_x)) {
    cat("[XGB_WARNING] Converting non-numeric matrix elements to numeric\n")
    trn_x <- apply(trn_x, 2, function(col) {
      if (is.logical(col)) {
        as.numeric(col)
      } else if (is.character(col)) {
        as.numeric(factor(col))
      } else {
        as.numeric(col)
      }
    })
  }
  
  trn_y <- as.matrix(dplyr::select(trn, c(time, status)))
  
  # Format labels for XGBoost AFT (Accelerated Failure Time)
  # AFT requires label_lower_bound and label_upper_bound arrays
  time_values <- trn_y[, 1]
  status_values <- trn_y[, 2]
  
  # For AFT: uncensored = [time, time], right-censored = [time, Inf]
  xgb_label_lower <- time_values
  xgb_label_upper <- ifelse(status_values == 1, time_values, Inf)
  
  # Configure XGBoost parallel processing
  if (use_parallel) {
    # Check for environment variable overrides
    env_threads <- suppressWarnings(as.integer(Sys.getenv("MC_WORKER_THREADS", unset = "0")))
    if (is.finite(env_threads) && env_threads > 0) {
      nthread <- env_threads
    }
    
    # Configure XGBoost with optimal settings
    xgb_config <- configure_xgboost_parallel(
      nthread = nthread,
      use_all_cores = is.null(nthread),
      target_utilization = 0.8,
      tree_method = tree_method,
      gpu_id = gpu_id,
      verbose = FALSE
    )
  } else {
    # Single-threaded configuration
    xgb_config <- configure_xgboost_parallel(
      nthread = 1,
      use_all_cores = FALSE,
      tree_method = tree_method,
      verbose = FALSE
    )
  }
  
  # Get number of rounds from environment or use default
  nrounds <- suppressWarnings(as.integer(Sys.getenv("XGB_NROUNDS", unset = "500")))
  if (!is.finite(nrounds) || nrounds < 10) nrounds <- 500L

  # Fit model using optimal parallel configuration
  model <- xgboost_parallel(
    data = trn_x[, vars, drop = FALSE],
    label_lower = xgb_label_lower,
    label_upper = xgb_label_upper,
    config = xgb_config,
    nrounds = nrounds,
    eta = 0.01,
    max_depth = 3,
    gamma = 0.5,
    min_child_weight = 2,
    subsample = 0.5,
    colsample_bynode = 0.5,
    objective = "survival:aft",
    eval_metric = "aft-nloglik"
  )
  
  if(is.null(tst)) return(model)
  
  if(is.null(predict_horizon)) stop("specify prediction horizon", call. = F)
  
  # Use parallel prediction if available
  if (use_parallel) {
    predictions <- predict_xgboost_parallel(
      object = model,
      new_data = as.matrix(tst[, vars]),
      config = xgb_config
    )
    # XGBoost survival:aft returns risk scores directly, no need to invert
    predictions
  } else {
    # Use safe wrapper for non-parallel predictions; return NA if it fails
    tryCatch(
      safe_model_predict(model, new_data = as.matrix(tst[, vars])),
      error = function(e) NA_real_
    )
  }
 
}
