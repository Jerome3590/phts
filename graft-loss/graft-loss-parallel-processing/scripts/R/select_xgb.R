##' Select features using XGBoost with parallel processing
##'
##' Uses XGBoost with optimized parallel processing for feature selection
##' 
##' @param trn Training data
##' @param n_predictors Number of predictors to select
##' @param n_rounds Number of boosting rounds (default: 250)
##' @param eta Learning rate (default: 0.01)
##' @param max_depth Maximum tree depth (default: 3)
##' @param gamma Minimum loss reduction (default: 0.5)
##' @param min_child_weight Minimum child weight (default: 2)
##' @param subsample Subsample ratio (default: 0.5)
##' @param colsample_bynode Column sample ratio (default: 0.5)
##' @param objective Objective function (default: "survival:aft")
##' @param eval_metric Evaluation metric (default: "aft-nloglik")
##' @param use_parallel Whether to use parallel processing (default: TRUE)
##' @param nthread Number of threads (NULL = auto-detect)
##' @param tree_method Tree construction method (default: 'auto')
##' @param gpu_id GPU ID for GPU acceleration (NULL = CPU only)
##' @return Selected feature names
select_xgb <- function(trn,
                       n_predictors,
                       n_rounds = 250,
                       eta = 0.01,
                       max_depth = 3,
                       gamma = 0.5,
                       min_child_weight = 2,
                       subsample = 0.5,
                       colsample_bynode = 0.5,
                       objective = "survival:aft",
                       eval_metric = "aft-nloglik",
                       use_parallel = TRUE,
                       nthread = NULL,
                       tree_method = 'auto',
                       gpu_id = NULL) {

  trn_x <- as.matrix(select(trn, -c(time, status)))
  trn_y <- as.matrix(select(trn, c(time, status)))
  
  # Format labels for XGBoost AFT
  time_values <- trn_y[, 1]
  status_values <- trn_y[, 2]
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
    
    # Fit model using optimal parallel configuration
    model <- xgboost_parallel(
      data = trn_x,
      label_lower = xgb_label_lower,
      label_upper = xgb_label_upper,
      config = xgb_config,
      nrounds = n_rounds,
      eta = eta,
      max_depth = max_depth,
      gamma = gamma,
      min_child_weight = min_child_weight,
      subsample = subsample,
      colsample_bynode = colsample_bynode,
      objective = objective,
      eval_metric = eval_metric
    )
  } else {
    # Single-threaded configuration
    xgb_config <- configure_xgboost_parallel(
      nthread = 1,
      use_all_cores = FALSE,
      tree_method = tree_method,
      verbose = FALSE
    )
    
    # Build parameter list for single-threaded
    params <- list(    
      eta = eta,
      max_depth = max_depth,
      gamma = gamma,
      min_child_weight = min_child_weight,
      subsample = subsample,
      colsample_bynode = colsample_bynode,
      objective = objective,
      eval_metric = eval_metric,
      nthread = 1,
      tree_method = tree_method
    )
    
    sgb_trn <- sgb_data(data = trn_x, label = xgb_label)
    
    model <- sgb_fit(
      sgb_df = sgb_trn, 
      nrounds = n_rounds,
      verbose = 0,
      params = params
    )
  }
  
  # Extract feature importance
  model %>% 
    use_series('fit') %>% 
    xgb.importance(model = .) %>% 
    slice(1:n_predictors) %>% 
    pull(Feature)
}
