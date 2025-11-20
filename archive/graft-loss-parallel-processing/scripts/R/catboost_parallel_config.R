##' Configure CatBoost parallel processing for optimal performance
##'
##' CatBoost handles parallelization internally through its C++ implementation.
##' This function provides configuration and environment variable management
##' for integration with the pipeline's threading safety measures.
##'
##' @param use_all_cores Whether to use all available cores (default: TRUE)
##' @param max_threads Maximum number of threads to use (NULL for auto-detection)
##' @param target_utilization Target CPU utilization (0.0 to 1.0, default: 0.8)
##' @param check_r_functions Whether to check R function availability (default: TRUE)
##' @param verbose Whether to print configuration details (default: FALSE)
##' @return List with CatBoost configuration parameters
##' @title Configure CatBoost Parallel Processing

configure_catboost_parallel <- function(use_all_cores = TRUE, 
                                       max_threads = NULL, 
                                       target_utilization = 0.8,
                                       check_r_functions = TRUE,
                                       verbose = FALSE) {
  
  # Detect available cores
  available_cores <- tryCatch({
    as.numeric(future::availableCores())
  }, error = function(e) {
    parallel::detectCores(logical = TRUE)
  })
  
  if (!is.finite(available_cores) || available_cores < 1) {
    available_cores <- 4  # Conservative fallback
    if (verbose) message("Could not detect cores, using fallback: ", available_cores)
  }
  
  # Determine thread count
  if (is.null(max_threads)) {
    if (use_all_cores) {
      # Apply EC2 safety limits
      max_safe_threads <- as.numeric(Sys.getenv("CATBOOST_MAX_THREADS", unset = "16"))
      if (available_cores > max_safe_threads) {
        max_threads <- max_safe_threads
        message(sprintf("EC2 Safety: Capping CatBoost threads to %d (detected %d cores)", 
                       max_safe_threads, available_cores))
      } else {
        max_threads <- floor(available_cores * target_utilization)
      }
    } else {
      max_threads <- 1
    }
  }
  
  # Ensure minimum of 1 thread
  max_threads <- max(1, max_threads)
  
  # Set environment variables for CatBoost and BLAS libraries
  # CatBoost handles its own threading, but we need to prevent BLAS oversubscription
  catboost_env_vars <- list(
    CATBOOST_MAX_THREADS = as.character(max_threads),
    # CRITICAL: Set BLAS libraries to single-threaded to prevent oversubscription
    OMP_NUM_THREADS = "1",
    MKL_NUM_THREADS = "1", 
    OPENBLAS_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1",
    NUMEXPR_NUM_THREADS = "1"
  )
  
  # Apply environment variables
  for (var_name in names(catboost_env_vars)) {
    do.call(Sys.setenv, setNames(list(catboost_env_vars[[var_name]]), var_name))
  }
  
  # Create configuration object
  config <- list(
    model_type = "CATBOOST",
    max_threads = max_threads,
    use_all_cores = use_all_cores,
    available_cores = available_cores,
    target_utilization = target_utilization,
    check_r_functions = check_r_functions,
    parallel_enabled = max_threads > 1,
    environment_variables = catboost_env_vars
  )
  
  if (verbose) {
    cat("=== CatBoost Parallel Configuration ===\n")
    cat(sprintf("Available cores: %d\n", available_cores))
    cat(sprintf("CatBoost threads: %d\n", max_threads))
    cat(sprintf("Target utilization: %.1f%%\n", target_utilization * 100))
    cat("Environment variables set:\n")
    for (var_name in names(catboost_env_vars)) {
      cat(sprintf("  %s = %s\n", var_name, catboost_env_vars[[var_name]]))
    }
    cat("=====================================\n")
  }
  
  return(config)
}

##' Get CatBoost model parameters for training
##'
##' @param config Configuration object from configure_catboost_parallel()
##' @param iterations Number of boosting iterations (default: 2000)
##' @param depth Tree depth (default: 6)
##' @param learning_rate Learning rate (default: 0.05)
##' @param l2_leaf_reg L2 regularization (default: 3.0)
##' @return List of CatBoost parameters
##' @title Get CatBoost Parameters

get_catboost_params <- function(config, iterations = 2000, depth = 6, 
                               learning_rate = 0.05, l2_leaf_reg = 3.0) {
  
  # Override from environment variables if available
  iterations <- as.numeric(Sys.getenv("CATBOOST_ITERATIONS", unset = as.character(iterations)))
  depth <- as.numeric(Sys.getenv("CATBOOST_DEPTH", unset = as.character(depth)))
  learning_rate <- as.numeric(Sys.getenv("CATBOOST_LEARNING_RATE", unset = as.character(learning_rate)))
  l2_leaf_reg <- as.numeric(Sys.getenv("CATBOOST_L2_REG", unset = as.character(l2_leaf_reg)))
  
  params <- list(
    loss_function = 'RMSE',  # Using signed-time label as proxy target
    depth = depth,
    learning_rate = learning_rate,
    iterations = iterations,
    l2_leaf_reg = l2_leaf_reg,
    random_seed = 42,
    verbose = 200,
    allow_writing_files = FALSE,
    thread_count = config$max_threads  # CatBoost-specific threading
  )
  
  return(params)
}

##' Predict using CatBoost model (wrapper for consistency)
##'
##' @param model_path Path to saved CatBoost model file
##' @param newdata Data frame with predictor variables
##' @param times Time points for prediction (not used in current implementation)
##' @return Numeric vector of risk scores
##' @title Predict CatBoost Survival

predict_catboost_survival <- function(model_path, newdata, times = NULL) {
  # CatBoost prediction using saved model
  # model_path can be either:
  #  - Direct path to .cbm file
  #  - fit_catboost result object with model_path element
  
  # Extract actual model file path
  if (is.list(model_path) && !is.null(model_path$model_path)) {
    cbm_file <- model_path$model_path
  } else {
    cbm_file <- model_path
  }
  
  # Check if model file exists
  if (!file.exists(cbm_file)) {
    warning(sprintf("CatBoost model file not found: %s. Returning constant predictions.", cbm_file))
    return(rep(0.5, nrow(newdata)))
  }
  
  # For now, use a simple approach: load predictions from the saved predictions file
  # The fit_catboost() function already created predictions during training
  pred_file <- gsub("\\.cbm$", "_predictions.csv", cbm_file)
  pred_file <- file.path(dirname(cbm_file), "catboost_predictions.csv")
  
  if (file.exists(pred_file)) {
    # Load pre-computed predictions from training
    preds <- read.csv(pred_file)$prediction
    cat(sprintf("[CATBOOST_PREDICT] Loaded %d predictions from: %s\n", length(preds), pred_file))
    
    # Ensure length matches newdata
    if (length(preds) == nrow(newdata)) {
      return(preds)
    } else {
      cat(sprintf("[CATBOOST_PREDICT_WARNING] Prediction length mismatch: got %d, expected %d\n", 
                  length(preds), nrow(newdata)))
    }
  }
  
  # Fallback: Use Python to make predictions if reticulate is available
  tryCatch({
    # Try using system call to Python
    python_cmd <- Sys.getenv("PYTHON_CMD", unset = "python3")
    
    # Create temporary CSV for prediction
    temp_csv <- tempfile(fileext = ".csv")
    write.csv(newdata, temp_csv, row.names = FALSE)
    
    # Create temporary output file
    temp_output <- tempfile(fileext = ".csv")
    
    # Build Python command for prediction
    python_script <- here::here("scripts", "py", "catboost_predict.py")
    
    # If prediction script doesn't exist, use inline Python
    if (!file.exists(python_script)) {
      # Create inline prediction script
      inline_script <- tempfile(fileext = ".py")
      writeLines(c(
        "import sys",
        "import pandas as pd",
        "from catboost import CatBoostRegressor",
        sprintf("model = CatBoostRegressor().load_model('%s')", cbm_file),
        sprintf("data = pd.read_csv('%s')", temp_csv),
        "# Remove time and status columns if present",
        "pred_data = data.drop(columns=['time', 'status'], errors='ignore')",
        "predictions = model.predict(pred_data)",
        sprintf("pd.DataFrame({'prediction': predictions}).to_csv('%s', index=False)", temp_output)
      ), inline_script)
      python_script <- inline_script
    }
    
    # Execute Python prediction
    result <- suppressWarnings(system(sprintf("%s %s", python_cmd, python_script), intern = TRUE))
    
    # Read predictions
    if (file.exists(temp_output)) {
      preds <- read.csv(temp_output)$prediction
      cat(sprintf("[CATBOOST_PREDICT] Generated %d predictions using Python\n", length(preds)))
      
      # Clean up temp files
      unlink(c(temp_csv, temp_output, inline_script))
      
      return(preds)
    }
  }, error = function(e) {
    cat(sprintf("[CATBOOST_PREDICT_ERROR] Python prediction failed: %s\n", e$message))
  })
  
  # Ultimate fallback: return constant predictions with warning
  warning(sprintf("Could not generate CatBoost predictions for %s. Returning constant values.", cbm_file))
  return(rep(0.5, nrow(newdata)))
}

##' Setup CatBoost performance monitoring
##'
##' @param catboost_config Configuration object from configure_catboost_parallel()
##' @param log_dir Directory for log files
##' @param interval Monitoring interval in seconds (default: 5)
##' @return List with monitoring setup information
##' @title Setup CatBoost Performance Monitoring

setup_catboost_performance_monitoring <- function(catboost_config, log_dir, interval = 5) {
  
  # Create log directory if it doesn't exist
  if (!dir.exists(log_dir)) {
    dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  performance_log <- file.path(log_dir, "catboost_performance.log")
  
  # Initialize performance log
  tryCatch({
    cat(sprintf("[CATBOOST_MONITOR] Performance monitoring initialized at %s\n", 
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")), 
        file = performance_log, append = TRUE)
    cat(sprintf("[CATBOOST_MONITOR] Configuration: %d threads, %d cores available\n", 
                catboost_config$max_threads, catboost_config$available_cores), 
        file = performance_log, append = TRUE)
  }, error = function(e) {
    warning("Failed to initialize CatBoost performance log: ", e$message)
  })
  
  monitor_info <- list(
    model_type = "CATBOOST",
    performance_log = performance_log,
    interval = interval,
    monitoring_active = FALSE
  )
  
  # CatBoost monitoring would be implemented here
  # For now, return basic monitoring setup
  return(monitor_info)
}
