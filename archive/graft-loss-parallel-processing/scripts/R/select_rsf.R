##' Select features using Random Survival Forest with parallel processing
##'
##' Uses ranger with optimized parallel processing for feature selection
##' 
##' @param trn Training data
##' @param n_predictors Number of predictors to select
##' @param num.trees Number of trees (default: 250)
##' @param importance Importance calculation method (default: 'permutation')
##' @param min.node.size Minimum node size (default: 20)
##' @param splitrule Split rule (default: 'extratrees')
##' @param num.random.splits Number of random splits (default: 10)
##' @param return_importance Whether to return importance values (default: FALSE)
##' @param use_parallel Whether to use parallel processing (default: TRUE)
##' @param num_threads Number of threads (NULL = auto-detect)
##' @return Selected feature names or importance data frame
select_rsf <- function(trn, 
                       n_predictors,
                       num.trees = 250,
                       importance = 'permutation',
                       min.node.size = 20,
                       splitrule = 'extratrees',
                       num.random.splits = 10,
                       return_importance = FALSE,
                       use_parallel = TRUE,
                       num_threads = NULL) {

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
      memory_efficient = FALSE,  # Feature selection needs full memory
      verbose = FALSE
    )
    
    # Fit model using optimal parallel configuration
    model <- ranger_parallel(
      formula = Surv(time, status) ~ .,
      data = trn,
      config = ranger_config,
      num.trees = num.trees,
      importance = importance,
      min.node.size = min.node.size,
      splitrule = splitrule,
      num.random.splits = num.random.splits,
      write.forest = FALSE  # Not needed for feature selection
    )
  } else {
    # Single-threaded configuration
    ranger_config <- configure_ranger_parallel(
      num_threads = 1,
      use_all_cores = FALSE,
      verbose = FALSE
    )
    
    model <- ranger(
      formula = Surv(time, status) ~ .,
      data = trn,
      num.trees = num.trees,
      importance = importance,
      min.node.size = min.node.size,
      splitrule = splitrule,
      num.random.splits = num.random.splits,
      num.threads = 1
    )
  }
  
  ftr_importance <- enframe(model$variable.importance) %>% 
    arrange(desc(value)) %>% 
    slice(1:n_predictors)
  
  if(return_importance) return(ftr_importance)
  
  pull(ftr_importance, name)

}
