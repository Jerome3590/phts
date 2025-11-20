##' Fit Random Survival Forest with optimal parallel processing
##'
##' Uses ranger with optimized parallel processing configuration
##' 
##' @param trn Training data
##' @param vars Variable names
##' @param tst Test data (optional)
##' @param predict_horizon Prediction horizon (optional)
##' @param use_parallel Whether to use parallel processing (default: TRUE)
##' @param num_threads Number of threads (NULL = auto-detect)
##' @param memory_efficient Whether to use memory saving mode
##' @return Fitted ranger model or predictions
fit_rsf <- function(trn,
                    vars,
                    tst = NULL,
                    predict_horizon = NULL,
                    use_parallel = TRUE,
                    num_threads = NULL,
                    memory_efficient = FALSE) {
  
  # ENHANCED LOGGING: Log initial data diagnostics for MC-CV debugging
  predictor_vars <- if (!is.null(vars)) vars else setdiff(names(trn), c('time', 'status'))
  
  cat(sprintf("[RSF_INIT] Starting RSF model with %d observations, %d predictors\n", 
              nrow(trn), length(predictor_vars)))
  cat(sprintf("[RSF_INIT] Events: %d (%.1f%%), Censored: %d (%.1f%%)\n", 
              sum(trn$status), 100 * mean(trn$status), 
              sum(1 - trn$status), 100 * (1 - mean(trn$status))))
  cat(sprintf("[RSF_INIT] Events per predictor ratio: %.2f (recommended: >10)\n", 
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
    cat(sprintf("[RSF_INIT] Potential MC-CV issues detected in %d variables:\n", length(potential_issues)))
    for (issue in potential_issues) {
      cat(sprintf("[RSF_INIT] - %s\n", issue))
    }
  } else {
    cat("[RSF_INIT] No obvious MC-CV data issues detected\n")
  }
  
  # Configure ranger parallel processing
  if (use_parallel) {
    # Check for environment variable overrides
    env_threads <- suppressWarnings(as.integer(Sys.getenv("MC_WORKER_THREADS", unset = "0")))
    if (is.finite(env_threads) && env_threads > 0) {
      num_threads <- env_threads
    }
    
    # Configure ranger with optimal settings
    ranger_config <- configure_ranger_parallel(
      num_threads = num_threads,
      use_all_cores = is.null(num_threads),
      target_utilization = 0.8,
      memory_efficient = memory_efficient,
      verbose = FALSE
    )
  } else {
    # Single-threaded configuration
    ranger_config <- configure_ranger_parallel(
      num_threads = 1,
      use_all_cores = FALSE,
      verbose = FALSE
    )
  }
  
  # Get number of trees from environment or use default
  ntree <- suppressWarnings(as.integer(Sys.getenv("RSF_NTREES", unset = "1000")))
  if (!is.finite(ntree) || ntree < 1) ntree <- 1000L
  
  # Fit model using optimal parallel configuration
  model <- ranger_parallel(
    formula = Surv(time, status) ~ .,
    data = trn[, c('time', 'status', vars)],
    config = ranger_config,
    num.trees = ntree,
    min.node.size = 10,
    splitrule = 'C',
    importance = 'none',  # Faster for parallel processing
    write.forest = TRUE
  )
  
  if(is.null(tst)) return(model)
  
  if(is.null(predict_horizon)) stop("specify prediction horizon", call. = F)
  
  # Use parallel prediction if available
  if (use_parallel) {
    pred_result <- predict_ranger_parallel(
      object = model,
      newdata = tst,
      config = ranger_config
    )
    ranger_predictrisk(model, 
                       newdata = tst, 
                       times = predict_horizon)
  } else {
    ranger_predictrisk(model, 
                       newdata = tst, 
                       times = predict_horizon)
  }
}


