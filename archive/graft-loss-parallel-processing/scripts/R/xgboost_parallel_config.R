##' XGBoost Parallel Processing Configuration
##' 
##' Comprehensive configuration for optimal XGBoost parallel processing
##' Based on XGBoost's automatic parallelization and nthread parameter control
##' 
##' Key features:
##' - Automatic thread detection and configuration
##' - Environment variable management for XGBoost threads
##' - Memory-efficient parallel processing
##' - Performance monitoring and optimization
##' - Integration with existing pipeline parallel setup

##' Configure XGBoost parallel processing settings
##' 
##' @param nthread Number of threads for XGBoost (NULL = all cores, 0 = all cores)
##' @param use_all_cores Whether to use all available cores (overrides nthread)
##' @param target_utilization Target CPU utilization (0.8 = 80%)
##' @param tree_method Tree construction method ('auto', 'hist', 'gpu_hist', 'approx')
##' @param gpu_id GPU ID for GPU acceleration (NULL = CPU only)
##' @param verbose Whether to print configuration details
##' @return List with XGBoost configuration settings
configure_xgboost_parallel <- function(nthread = NULL, 
                                     use_all_cores = TRUE,
                                     target_utilization = 0.8,
                                     tree_method = 'auto',
                                     gpu_id = NULL,
                                     verbose = TRUE) {
  
  # Detect available cores
  available_cores <- tryCatch({
    if (requireNamespace("future", quietly = TRUE)) {
      as.numeric(future::availableCores())
    } else {
      parallel::detectCores(logical = TRUE)
    }
  }, error = function(e) {
    warning("Could not detect cores, defaulting to 4")
    4L
  })
  
  # Determine optimal thread count
  if (is.null(nthread)) {
    if (use_all_cores) {
      # CRITICAL FIX: Cap threads on EC2 to prevent oversubscription
      # EC2 instances with many cores can cause conflicts when using all cores
      max_safe_threads <- as.numeric(Sys.getenv("XGB_MAX_THREADS", unset = "16"))
      if (available_cores > max_safe_threads) {
        nthread <- max_safe_threads
        if (verbose) {
          message(sprintf("EC2 Safety: Capping XGBoost threads to %d (detected %d cores)", 
                         max_safe_threads, available_cores))
        }
      } else {
        nthread <- 0  # Use all cores if under the safety limit
      }
    } else {
      nthread <- max(1L, floor(available_cores * target_utilization))
    }
  }
  
  # Set XGBoost-specific environment variables
  # CRITICAL FIX: Always set BLAS/OpenMP to 1 thread to prevent oversubscription
  # XGBoost handles its own threading internally, BLAS should be single-threaded
  xgboost_env_vars <- list(
    OMP_NUM_THREADS = "1",                             # Always 1 to prevent oversubscription
    MKL_NUM_THREADS = "1",                             # Always 1 to prevent oversubscription
    OPENBLAS_NUM_THREADS = "1",                        # Always 1 to prevent oversubscription
    VECLIB_MAXIMUM_THREADS = "1",                      # Always 1 to prevent oversubscription
    NUMEXPR_NUM_THREADS = "1",                         # Always 1 to prevent oversubscription
    XGBOOST_NTHREAD = as.character(nthread)  # Package can use 0
  )
  
  # Add GPU-specific variables if GPU is requested
  if (!is.null(gpu_id)) {
    xgboost_env_vars$CUDA_VISIBLE_DEVICES <- as.character(gpu_id)
    tree_method <- 'gpu_hist'
  }
  
  # Apply environment variables
  for (var_name in names(xgboost_env_vars)) {
    do.call(Sys.setenv, setNames(list(xgboost_env_vars[[var_name]]), var_name))
  }
  
  # Create configuration object
  config <- list(
    nthread = nthread,
    available_cores = available_cores,
    target_utilization = target_utilization,
    tree_method = tree_method,
    gpu_id = gpu_id,
    environment_vars = xgboost_env_vars,
    timestamp = Sys.time()
  )
  
  if (verbose) {
    message("=== XGBoost Parallel Configuration ===")
    message(sprintf("Available cores: %d", available_cores))
    message(sprintf("XGBoost threads: %s", ifelse(nthread == 0, "all cores", as.character(nthread))))
    message(sprintf("Target utilization: %.1f%%", target_utilization * 100))
    message(sprintf("Tree method: %s", tree_method))
    if (!is.null(gpu_id)) {
      message(sprintf("GPU ID: %s", gpu_id))
    }
    message("Environment variables set:")
    for (var in names(xgboost_env_vars)) {
      message(sprintf("  %s = %s", var, xgboost_env_vars[[var]]))
    }
    message("=====================================")
  }
  
  return(config)
}

##' Get optimal XGBoost parameters for parallel processing
##' 
##' @param config XGBoost configuration object (from configure_xgboost_parallel)
##' @param objective Objective function (default: "survival:aft")
##' @param eval_metric Evaluation metric (default: "aft-nloglik")
##' @param eta Learning rate (default: 0.01)
##' @param max_depth Maximum tree depth (default: 3)
##' @param gamma Minimum loss reduction (default: 0.5)
##' @param min_child_weight Minimum child weight (default: 2)
##' @param subsample Subsample ratio (default: 0.5)
##' @param colsample_bynode Column sample ratio (default: 0.5)
##' @param nrounds Number of boosting rounds (default: 500)
##' @return List of XGBoost parameters optimized for parallel processing
get_xgboost_params <- function(config, 
                             objective = "survival:aft",
                             eval_metric = "aft-nloglik",
                             eta = 0.01,
                             max_depth = 3,
                             gamma = 0.5,
                             min_child_weight = 2,
                             subsample = 0.5,
                             colsample_bynode = 0.5,
                             nrounds = 500) {
  
  # Build parameter list
  params <- list(
    objective = objective,
    eval_metric = eval_metric,
    eta = eta,
    max_depth = max_depth,
    gamma = gamma,
    min_child_weight = min_child_weight,
    subsample = subsample,
    colsample_bynode = colsample_bynode,
    nthread = config$nthread,
    tree_method = config$tree_method
  )
  
  # Add GPU-specific parameters if using GPU
  if (!is.null(config$gpu_id)) {
    params$gpu_id <- config$gpu_id
  }
  
  return(params)
}

##' Create XGBoost model with optimal parallel settings
##' 
##' @param data Training data matrix
##' @param label Training labels (for backward compatibility)
##' @param label_lower Lower bound labels for AFT (optional)
##' @param label_upper Upper bound labels for AFT (optional)
##' @param config XGBoost configuration object
##' @param ... Additional parameters passed to sgb_fit()
##' @return Fitted XGBoost model
xgboost_parallel <- function(data, label = NULL, label_lower = NULL, label_upper = NULL, config, ...) {
  # Get optimal parameters
  params <- get_xgboost_params(config, ...)
  
  # Extract nrounds from ... arguments
  args <- list(...)
  nrounds <- if (!is.null(args$nrounds)) args$nrounds else 500
  
  # Create data object for AFT
  if (!is.null(label_lower) && !is.null(label_upper)) {
    # AFT mode: use xgb.DMatrix with AFT labels
    # Ensure data is numeric before creating DMatrix
    if (!is.numeric(data)) {
      cat("[XGB_WARNING] Converting non-numeric data to numeric for DMatrix\n")
      data <- apply(data, 2, function(col) {
        if (is.logical(col)) {
          as.numeric(col)
        } else if (is.character(col)) {
          as.numeric(factor(col))
        } else {
          as.numeric(col)
        }
      })
    }
    
    dtrain <- xgboost::xgb.DMatrix(data = data)
    xgboost::setinfo(dtrain, 'label_lower_bound', label_lower)
    xgboost::setinfo(dtrain, 'label_upper_bound', label_upper)
    
    # Use xgb.train directly for AFT models
    xgb.train(
      data = dtrain,
      params = params,
      nrounds = nrounds,
      verbose = 0
    )
  } else {
    # Backward compatibility: use sgb_fit for non-AFT models
    sgb_data_obj <- sgb_data(data = data, label = label)
    sgb_fit(
      sgb_df = sgb_data_obj,
      verbose = 0,
      params = params
    )
  }
}

##' Predict with XGBoost model using parallel processing
##' 
##' @param object Fitted XGBoost model
##' @param new_data New data for prediction
##' @param config XGBoost configuration object
##' @param ... Additional parameters passed to predict()
##' @return Predictions
predict_xgboost_parallel <- function(object, new_data, config, ...) {
  # Create sgb_data object for prediction
  sgb_data_obj <- sgb_data(data = new_data, label = rep(0, nrow(new_data)))
  
  # Make prediction using native XGBoost survival:aft
  # The survival:aft objective handles risk prediction internally
  predict(object, newdata = sgb_data_obj, ...)
}

##' Monitor XGBoost performance during training
##' 
##' @param config XGBoost configuration object
##' @param log_file File to write performance logs
##' @param interval Monitoring interval in seconds
##' @return Function to stop monitoring
monitor_xgboost_performance <- function(config, 
                                      log_file = "logs/xgboost_performance.log", 
                                      interval = 10) {
  
  if (!dir.exists(dirname(log_file))) {
    dir.create(dirname(log_file), recursive = TRUE)
  }
  
  message(sprintf("Monitoring XGBoost performance to: %s", log_file))
  message("Press Ctrl+C to stop monitoring")
  
  # Create monitoring function
  monitor_func <- function() {
    while (TRUE) {
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      
      # Get system stats
      tryCatch({
        # Memory usage
        mem_info <- if (file.exists("/proc/meminfo")) {
          meminfo <- readLines("/proc/meminfo")
          total_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemTotal", meminfo)])) / 1024 / 1024
          avail_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemAvailable", meminfo)])) / 1024 / 1024
          used_mem <- total_mem - avail_mem
          sprintf("MEM: %.1f/%.1f GB (%.1f%%)", used_mem, total_mem, (used_mem/total_mem)*100)
        } else {
          gc_info <- gc()
          sprintf("MEM: %.1f MB", sum(gc_info[,2]))
        }
        
        # CPU usage
        cpu_info <- tryCatch({
          if (Sys.which("ps") != "") {
            ps_out <- system("ps -eo comm,pcpu | grep -E 'R$|Rscript' | awk '{sum+=$2} END {print sum}'", intern = TRUE)
            if (length(ps_out) > 0 && ps_out != "") {
              sprintf("CPU: %s%%", trimws(ps_out))
            } else "CPU: N/A"
          } else "CPU: N/A"
        }, error = function(e) "CPU: N/A")
        
        # XGBoost-specific info
        xgb_info <- sprintf("XGBOOST_THREADS: %s | TREE_METHOD: %s", 
                           ifelse(config$nthread == 0, "all cores", as.character(config$nthread)),
                           config$tree_method)
        
        # Format log entry
        log_entry <- sprintf("[%s] %s | %s | %s | %s", 
                            timestamp, mem_info, cpu_info, xgb_info, "XGBOOST_MONITOR")
        
        # Write to log file
        write(log_entry, file = log_file, append = TRUE)
        
      }, error = function(e) {
        # Fallback logging
        log_entry <- sprintf("[%s] XGBOOST_MONITOR | Error: %s", timestamp, e$message)
        write(log_entry, file = log_file, append = TRUE)
      })
      
      Sys.sleep(interval)
    }
  }
  
  # Return monitoring function
  return(monitor_func)
}

##' Benchmark XGBoost performance with different thread configurations
##' 
##' @param data Training data matrix
##' @param label Training labels
##' @param thread_configs Vector of thread configurations to test
##' @param nrounds Number of boosting rounds for benchmarking
##' @param n_runs Number of runs per configuration
##' @return Data frame with benchmark results
benchmark_xgboost_threads <- function(data, label, 
                                    thread_configs = c(1, 2, 4, 8, 0),
                                    nrounds = 500,
                                    n_runs = 3) {
  
  results <- list()
  
  for (threads in thread_configs) {
    message(sprintf("Benchmarking with %d threads...", threads))
    
    # Configure XGBoost for this thread count
    config <- configure_xgboost_parallel(nthread = threads, verbose = FALSE)
    
    # Run multiple times
    run_times <- numeric(n_runs)
    
    for (run in seq_len(n_runs)) {
      start_time <- Sys.time()
      
      # Fit model
      model <- xgboost_parallel(data, label, config, nrounds = nrounds)
      
      end_time <- Sys.time()
      run_times[run] <- as.numeric(difftime(end_time, start_time, units = "secs"))
    }
    
    # Store results
    results[[length(results) + 1]] <- data.frame(
      threads = threads,
      mean_time = mean(run_times),
      sd_time = sd(run_times),
      min_time = min(run_times),
      max_time = max(run_times),
      runs = n_runs
    )
  }
  
  # Combine results
  benchmark_df <- do.call(rbind, results)
  
  # Add speedup relative to single thread
  single_thread_time <- benchmark_df$mean_time[benchmark_df$threads == 1]
  benchmark_df$speedup <- single_thread_time / benchmark_df$mean_time
  
  return(benchmark_df)
}

##' Get XGBoost system information
##' 
##' @return List with system information relevant to XGBoost
get_xgboost_system_info <- function() {
  info <- list(
    r_version = R.version.string,
    platform = R.version$platform,
    available_cores = tryCatch({
      if (requireNamespace("future", quietly = TRUE)) {
        as.numeric(future::availableCores())
      } else {
        parallel::detectCores(logical = TRUE)
      }
    }, error = function(e) "Unknown"),
    xgboost_loaded = requireNamespace("xgboost", quietly = TRUE),
    xgboost_version = if (requireNamespace("xgboost", quietly = TRUE)) {
      as.character(packageVersion("xgboost"))
    } else "Not installed",
    # xgboost.surv removed from pipeline
    environment_vars = list(
      OMP_NUM_THREADS = Sys.getenv("OMP_NUM_THREADS", unset = "Not set"),
      MKL_NUM_THREADS = Sys.getenv("MKL_NUM_THREADS", unset = "Not set"),
      OPENBLAS_NUM_THREADS = Sys.getenv("OPENBLAS_NUM_THREADS", unset = "Not set"),
      VECLIB_MAXIMUM_THREADS = Sys.getenv("VECLIB_MAXIMUM_THREADS", unset = "Not set"),
      NUMEXPR_NUM_THREADS = Sys.getenv("NUMEXPR_NUM_THREADS", unset = "Not set"),
      XGBOOST_NTHREAD = Sys.getenv("XGBOOST_NTHREAD", unset = "Not set"),
      CUDA_VISIBLE_DEVICES = Sys.getenv("CUDA_VISIBLE_DEVICES", unset = "Not set")
    ),
    gpu_available = tryCatch({
      if (requireNamespace("xgboost", quietly = TRUE)) {
        xgboost::xgb.config()$gpu_id >= 0
      } else FALSE
    }, error = function(e) FALSE)
  )
  
  return(info)
}

##' Print XGBoost system information
##' 
##' @param info System information object (from get_xgboost_system_info)
print_xgboost_system_info <- function(info = NULL) {
  if (is.null(info)) {
    info <- get_xgboost_system_info()
  }
  
  message("=== XGBoost System Information ===")
  message(sprintf("R Version: %s", info$r_version))
  message(sprintf("Platform: %s", info$platform))
  message(sprintf("Available cores: %s", info$available_cores))
  message(sprintf("XGBoost loaded: %s", info$xgboost_loaded))
  message(sprintf("XGBoost version: %s", info$xgboost_version))
  message(sprintf("XGBoost.surv loaded: %s", info$xgboost_surv_loaded))
  message(sprintf("XGBoost.surv version: %s", info$xgboost_surv_version))
  message(sprintf("GPU available: %s", info$gpu_available))
  message("\nEnvironment Variables:")
  for (var in names(info$environment_vars)) {
    message(sprintf("  %s = %s", var, info$environment_vars[[var]]))
  }
  message("===============================")
}

##' Check XGBoost GPU availability and configuration
##' 
##' @return List with GPU information
check_xgboost_gpu <- function() {
  gpu_info <- list(
    cuda_available = FALSE,
    gpu_count = 0,
    gpu_memory = NULL,
    xgboost_gpu_support = FALSE
  )
  
  # Check CUDA availability
  tryCatch({
    if (Sys.which("nvidia-smi") != "") {
      nvidia_smi <- system("nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits", 
                          intern = TRUE)
      if (length(nvidia_smi) > 0) {
        gpu_info$cuda_available <- TRUE
        gpu_info$gpu_count <- length(nvidia_smi)
        gpu_info$gpu_memory <- nvidia_smi
      }
    }
  }, error = function(e) {
    # CUDA not available
  })
  
  # Check XGBoost GPU support
  tryCatch({
    if (requireNamespace("xgboost", quietly = TRUE)) {
      # Try to create a simple model with GPU
      test_data <- matrix(rnorm(100), ncol = 10)
      test_label <- rnorm(10)
      
      # This will fail if GPU is not available
      test_model <- xgboost::xgb.train(
        data = xgboost::xgb.DMatrix(test_data, label = test_label),
        params = list(objective = "reg:squarederror", tree_method = "gpu_hist"),
        nrounds = 1,
        verbose = FALSE
      )
      gpu_info$xgboost_gpu_support <- TRUE
    }
  }, error = function(e) {
    # GPU not supported in XGBoost
  })
  
  return(gpu_info)
}
