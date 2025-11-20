##' Fit Oblique Random Survival Forest with optimal parallel processing
##'
##' Uses aorsf with optimized parallel processing configuration
##' 
##' @param trn Training data
##' @param vars Variable names
##' @param tst Test data (optional)
##' @param predict_horizon Prediction horizon (optional)
##' @param use_parallel Whether to use parallel processing (default: TRUE)
##' @param n_thread Number of threads (NULL = auto-detect)
##' @param check_r_functions Whether to check for R functions that limit threading
##' @return Fitted aorsf model or predictions
fit_orsf <- function(trn,
                     vars,
                     tst = NULL,
                     predict_horizon = NULL,
                     use_parallel = TRUE,
                     n_thread = NULL,
                     check_r_functions = TRUE) {
  
  # ENHANCED LOGGING: Log initial data diagnostics for MC-CV debugging
  predictor_vars <- if (!is.null(vars)) vars else setdiff(names(trn), c('time', 'status'))
  
  cat(sprintf("[ORSF_INIT] Starting ORSF model with %d observations, %d predictors\n", 
              nrow(trn), length(predictor_vars)))
  cat(sprintf("[ORSF_INIT] Events: %d (%.1f%%), Censored: %d (%.1f%%)\n", 
              sum(trn$status), 100 * mean(trn$status), 
              sum(1 - trn$status), 100 * (1 - mean(trn$status))))
  cat(sprintf("[ORSF_INIT] Events per predictor ratio: %.2f (recommended: >10)\n", 
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
    cat(sprintf("[ORSF_INIT] Potential MC-CV issues detected in %d variables:\n", length(potential_issues)))
    for (issue in potential_issues) {
      cat(sprintf("[ORSF_INIT] - %s\n", issue))
    }
  } else {
    cat("[ORSF_INIT] No obvious MC-CV data issues detected\n")
  }
  
  # Configure aorsf parallel processing
  if (use_parallel) {
    # Check for environment variable overrides
    env_threads <- suppressWarnings(as.integer(Sys.getenv("MC_WORKER_THREADS", unset = "0")))
    if (is.finite(env_threads) && env_threads > 0) {
      n_thread <- env_threads
    }
    
    # Configure aorsf with optimal settings
    aorsf_config <- configure_aorsf_parallel(
      n_thread = n_thread,
      use_all_cores = is.null(n_thread),
      target_utilization = 0.8,
      check_r_functions = check_r_functions,
      verbose = FALSE
    )
  } else {
    # Single-threaded configuration
    aorsf_config <- configure_aorsf_parallel(
      n_thread = 1,
      use_all_cores = FALSE,
      check_r_functions = FALSE,
      verbose = FALSE
    )
  }
  
  # Get number of trees from environment or use default
  ntree <- suppressWarnings(as.integer(Sys.getenv("ORSF_NTREES", unset = "1000")))
  if (!is.finite(ntree) || ntree < 1) ntree <- 1000L
  
  # Track which variables were actually used to train the model
  vars_used <- vars
  
  # Fit model using aorsf directly (not obliqueRSF)
  # Handle constant column errors gracefully by removing problematic variables
  fit_result <- tryCatch({
    model_fit <- aorsf::orsf(
      data = trn[, c('time', 'status', vars)],
      formula = Surv(time, status) ~ .,
      n_tree = ntree,
      n_thread = aorsf_config$n_thread
    )
    list(model = model_fit, vars_used = vars)
  }, error = function(e) {
    # Check if error is about constant columns
    if (grepl("constant", e$message, ignore.case = TRUE)) {
      cat(sprintf("[ORSF_WARNING] Constant column detected, attempting to fit without problematic variables\n"))
      
      # Find truly constant columns in this fold
      constant_vars <- character(0)
      for (v in vars) {
        if (v %in% names(trn)) {
          if (is.numeric(trn[[v]])) {
            if (length(unique(trn[[v]][!is.na(trn[[v]])])) <= 1) {
              constant_vars <- c(constant_vars, v)
            }
          }
        }
      }
      
      if (length(constant_vars) > 0) {
        cat(sprintf("[ORSF_WARNING] Removing %d constant variables: %s\n", 
                    length(constant_vars), paste(constant_vars, collapse = ", ")))
        vars_filtered <- setdiff(vars, constant_vars)
        
        if (length(vars_filtered) == 0) {
          stop("All variables are constant in this fold - cannot fit model")
        }
        
        # Retry with filtered variables
        model_fit <- aorsf::orsf(
          data = trn[, c('time', 'status', vars_filtered)],
          formula = Surv(time, status) ~ .,
          n_tree = ntree,
          n_thread = aorsf_config$n_thread
        )
        list(model = model_fit, vars_used = vars_filtered)
      } else {
        # Re-throw the original error if we couldn't identify constant columns
        stop(e)
      }
    } else {
      # Re-throw non-constant-column errors
      stop(e)
    }
  })
  
  model <- fit_result$model
  vars_used <- fit_result$vars_used
  
  # Attach metadata to model for prediction
  attr(model, "vars_used") <- vars_used
  
  if(is.null(tst)) return(model)
  
  if(is.null(predict_horizon)) stop("specify prediction horizon", call. = F)
  
  # Use aorsf prediction directly with the variables that were actually used for training
  predictions <- predict(model, new_data = tst[, c('time', 'status', vars_used)], pred_horizon = predict_horizon)
  
  # Convert matrix to vector and return 1 - predictions for risk score
  as.numeric(1 - predictions)
}
