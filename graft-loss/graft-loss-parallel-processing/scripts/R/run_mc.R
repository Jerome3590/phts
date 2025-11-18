##' Simplified Monte Carlo Cross-Validation for Wisotzkey Features
##'
##' This function bypasses recipe processing since we're using pre-selected
##' Wisotzkey features that don't need complex preprocessing.
##'
##' @param df Data frame with Wisotzkey features
##' @param vars Variable names to use
##' @param testing_rows List of test indices for each split
##' @param label Label for the analysis
##' @return List of results
run_mc <- function(df, vars, testing_rows, label = "simple") {
  
  # Source the imputation functions
  source(here("scripts", "R", "impute_missing_values.R"))
  
  # Source the XGBoost parallel configuration
  source(here("scripts", "R", "xgboost_parallel_config.R"))
  
  # Define thread configuration for parallel processing
  threads_per_worker <- 8  # Conservative setting for both EC2 and local
  
  cat(sprintf("[MC-SIMPLE] Starting simplified MC-CV with %d splits\n", length(testing_rows)))
  cat(sprintf("[MC-SIMPLE] Using %d variables: %s\n", length(vars), paste(vars, collapse = ", ")))
  
  # Ensure df is a data.frame (not tibble)
  df <- as.data.frame(df)
  
  # Simple compute task function without recipe processing
  compute_task_simple <- function(k, model_type, testing_rows_local, cohort_name = 'unknown') {
    
    # Get test indices
    test_idx <- as.integer(testing_rows_local[[k]])
    all_idx <- seq_len(nrow(df))
    train_idx <- setdiff(all_idx, test_idx)
    
    # Create simple train/test splits without recipe processing
    trn_df <- df[train_idx, c('time', 'status', vars), drop = FALSE]
    te_df <- df[test_idx, c('time', 'status', vars), drop = FALSE]
    
    # Define variable types for imputation
    continuous_vars <- c('tx_mcsd', 'chd_sv', 'hxsurg', 'txsa_r', 'txbun_r', 'txecmo', 
                         'txpl_year', 'weight_txpl', 'txalt', 'bmi_txpl', 'pra_listing', 
                         'egfr_tx', 'hxmed', 'listing_year')
    categorical_vars <- c('prim_dx')
    
    # Apply imputation following original graft-loss methodology
    imputation_result <- impute_train_test_data(trn_df, te_df, continuous_vars, categorical_vars)
    trn_df <- imputation_result$train_data
    te_df <- imputation_result$test_data
    
    # Convert character variables to factors after imputation
    for (var in vars) {
      if (is.character(trn_df[[var]])) {
        trn_df[[var]] <- as.factor(trn_df[[var]])
        te_df[[var]] <- factor(te_df[[var]], levels = levels(trn_df[[var]]))
      }
    }
    
    cat(sprintf("[MC-SIMPLE] Split %d: Train=%d, Test=%d, Vars=%d\n", 
                k, nrow(trn_df), nrow(te_df), length(vars)))
    
    # Fit model based on type
    fitted_model <- NULL
    performance <- NULL
    
    tryCatch({
      if (model_type == "ORSF") {
        fitted_model <- fit_orsf(trn_df, vars)
        if (!is.null(fitted_model)) {
          # Ensure test data has no missing values for ORSF
          te_df_clean <- te_df[complete.cases(te_df), , drop = FALSE]
          if (nrow(te_df_clean) > 0) {
            # Use safe_model_predict for ORSF with proper data structure
            pred_scores <- safe_model_predict(fitted_model, newdata = te_df_clean[, c('time', 'status', vars)], times = 1)
            # Ensure pred_scores is a vector
            if (is.data.frame(pred_scores)) {
              pred_scores <- pred_scores[[1]]
            }
            performance <- compute_model_performance(fitted_model, te_df_clean, model_type = "ORSF", split_id = k, vars_native = vars)
          }
        }
      } else if (model_type == "XGB") {
        # Configure XGBoost parallel processing before fitting
        xgb_config <- configure_xgboost_parallel(
          use_all_cores = FALSE,
          nthread = threads_per_worker,
          tree_method = "auto",
          verbose = FALSE
        )
        
        # Debug XGBoost data before fitting
        cat(sprintf("[XGB_DEBUG] Split %d: Training data dimensions: %dx%d\n", k, nrow(trn_df), ncol(trn_df)))
        cat(sprintf("[XGB_DEBUG] Split %d: All columns: %s\n", k, paste(colnames(trn_df), collapse = ", ")))
        cat(sprintf("[XGB_DEBUG] Split %d: Variables: %s\n", k, paste(vars, collapse = ", ")))
        cat(sprintf("[XGB_DEBUG] Split %d: Has time/status: time=%s, status=%s\n", k, "time" %in% colnames(trn_df), "status" %in% colnames(trn_df)))
        cat(sprintf("[XGB_DEBUG] Split %d: Training data classes: %s\n", k, paste(sapply(trn_df[, vars, drop = FALSE], class), collapse = ", ")))
        
        tryCatch({
          fitted_model <- fit_xgb(trn_df, vars)
          cat(sprintf("[XGB_DEBUG] Split %d: XGBoost fitting successful\n", k))
        }, error = function(e) {
          cat(sprintf("[XGB_ERROR] Split %d: XGBoost fitting failed: %s\n", k, e$message))
          fitted_model <<- NULL
        })
        if (!is.null(fitted_model)) {
          # XGBoost prediction is handled by compute_model_performance
          # No need to call safe_model_predict here as it will be called again
          performance <- compute_model_performance(fitted_model, te_df, model_type = "XGB", split_id = k, vars_native = vars)
        }
      } else if (model_type == "CPH") {
        fitted_model <- fit_cph(trn_df, vars)
        if (!is.null(fitted_model)) {
          # Use safe_model_predict for CPH with proper times handling
          pred_scores <- safe_model_predict(fitted_model, newdata = te_df, times = 1)
          # Ensure pred_scores is a vector
          if (is.data.frame(pred_scores)) {
            pred_scores <- pred_scores[[1]]
          }
          # Handle case where pred_scores might be a matrix
          if (is.matrix(pred_scores) && ncol(pred_scores) == 1) {
            pred_scores <- as.numeric(pred_scores[, 1])
          }
          performance <- compute_model_performance(fitted_model, te_df, model_type = "CPH", split_id = k, vars_native = vars)
        }
      }
      
      # Save model if successful
      if (!is.null(fitted_model)) {
        model_dir <- here("models", cohort_name, "mc_cv")
        dir.create(model_dir, showWarnings = FALSE, recursive = TRUE)
        model_file <- file.path(model_dir, sprintf("%s_split%03d.rds", model_type, k))
        saveRDS(fitted_model, model_file)
        cat(sprintf("Saved model: %s\n", model_file))
      }
      
    }, error = function(e) {
      cat(sprintf("[ERROR] %s split %d failed: %s\n", model_type, k, e$message))
      performance <- NULL
    })
    
    return(list(
      rows = if (!is.null(performance)) performance else NULL,
      split = k,
      model = model_type,
      success = !is.null(performance)
    ))
  }
  
  # Run MC-CV for each model type
  model_types <- c("ORSF", "XGB", "CPH")
  results <- list()
  
  for (model_type in model_types) {
    cat(sprintf("[MC-SIMPLE] Running %s across %d splits...\n", model_type, length(testing_rows)))
    
    model_results <- list()
    for (k in seq_along(testing_rows)) {
      result <- compute_task_simple(k, model_type, testing_rows, "original")
      model_results[[k]] <- result
    }
    
    results[[model_type]] <- model_results
  }
  
  return(results)
}
