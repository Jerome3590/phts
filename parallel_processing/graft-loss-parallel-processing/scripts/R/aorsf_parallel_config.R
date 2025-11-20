##' aorsf Parallel Processing Configuration
##' 
##' Comprehensive configuration for optimal aorsf parallel processing
##' Based on aorsf's n_thread parameter and multithreading capabilities
##' 
##' Key features:
##' - Automatic thread detection and configuration
##' - Environment variable management for aorsf threads
##' - Performance monitoring and optimization
##' - Integration with existing pipeline parallel setup
##' - Handling of R function limitations

##' Configure aorsf parallel processing settings
##' 
##' @param n_thread Number of threads for aorsf (0 = auto-detect, NULL = auto-detect)
##' @param use_all_cores Whether to use all available cores (overrides n_thread)
##' @param target_utilization Target CPU utilization (0.8 = 80%)
##' @param check_r_functions Whether to check for R functions that limit threading
##' @param verbose Whether to print configuration details
##' @return List with aorsf configuration settings
configure_aorsf_parallel <- function(n_thread = NULL, 
                                   use_all_cores = TRUE,
                                   target_utilization = 0.8,
                                   check_r_functions = TRUE,
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
  if (is.null(n_thread)) {
    if (use_all_cores) {
      # CRITICAL FIX: Cap threads on EC2 to prevent oversubscription
      # EC2 instances with many cores can cause conflicts when using all cores
      max_safe_threads <- as.numeric(Sys.getenv("ORSF_MAX_THREADS", unset = "16"))
      if (available_cores > max_safe_threads) {
        n_thread <- max_safe_threads
        if (verbose) {
          message(sprintf("EC2 Safety: Capping ORSF threads to %d (detected %d cores)", 
                         max_safe_threads, available_cores))
        }
      } else {
        n_thread <- 0  # Use aorsf's auto-detection if under the safety limit
      }
    } else {
      n_thread <- max(1L, floor(available_cores * target_utilization))
    }
  }
  
  # Check for R functions that limit threading
  r_function_limitation <- FALSE
  if (check_r_functions) {
    # Check if any R functions are being used that would limit threading
    # This is a simplified check - in practice, you'd need to examine the specific
    # functions being passed to aorsf
    r_function_limitation <- FALSE  # Placeholder for actual R function detection
  }
  
  # If R functions are detected, limit to single thread
  if (r_function_limitation) {
    if (verbose) {
      message("R functions detected - aorsf threading limited to 1 thread")
    }
    n_thread <- 1L
  }
  
  # Set aorsf-specific environment variables
  # CRITICAL FIX: Always set BLAS/OpenMP to 1 thread to prevent oversubscription
  # ORSF handles its own threading internally, BLAS should be single-threaded
  aorsf_env_vars <- list(
    OMP_NUM_THREADS = "1",                             # Always 1 to prevent oversubscription
    MKL_NUM_THREADS = "1",                             # Always 1 to prevent oversubscription
    OPENBLAS_NUM_THREADS = "1",                        # Always 1 to prevent oversubscription
    VECLIB_MAXIMUM_THREADS = "1",                      # Always 1 to prevent oversubscription
    NUMEXPR_NUM_THREADS = "1",                         # Always 1 to prevent oversubscription
    AORSF_NTHREAD = as.character(n_thread)  # Package can use 0
  )
  
  # Apply environment variables
  for (var_name in names(aorsf_env_vars)) {
    do.call(Sys.setenv, setNames(list(aorsf_env_vars[[var_name]]), var_name))
  }
  
  # Create configuration object
  config <- list(
    n_thread = n_thread,
    available_cores = available_cores,
    target_utilization = target_utilization,
    r_function_limitation = r_function_limitation,
    environment_vars = aorsf_env_vars,
    timestamp = Sys.time()
  )
  
  if (verbose) {
    message("=== aorsf Parallel Configuration ===")
    message(sprintf("Available cores: %d", available_cores))
    message(sprintf("aorsf threads: %s", ifelse(n_thread == 0, "auto-detect", as.character(n_thread))))
    message(sprintf("Target utilization: %.1f%%", target_utilization * 100))
    message(sprintf("R function limitation: %s", r_function_limitation))
    message("Environment variables set:")
    for (var in names(aorsf_env_vars)) {
      message(sprintf("  %s = %s", var, aorsf_env_vars[[var]]))
    }
    message("=====================================")
  }
  
  return(config)
}

##' Get optimal aorsf parameters for parallel processing
##' 
##' @param config aorsf configuration object (from configure_aorsf_parallel)
##' @param n_tree Number of trees (default: 1000)
##' @param mtry Number of variables to try at each split (default: sqrt(p))
##' @param n_split Minimum observations to split node (default: 10)
##' @param oobag_fun Out-of-bag function (default: NULL)
##' @param sample_fraction Sample fraction (default: 0.8)
##' @param eval_times Evaluation times for survival prediction (default: NULL)
##' @return List of aorsf parameters optimized for parallel processing
get_aorsf_params <- function(config, 
                           n_tree = 1000,
                           mtry = NULL,
                           n_split = 10,
                           oobag_fun = NULL,
                           sample_fraction = 0.8,  # Use 80% for training, 20% for OOB
                           eval_times = NULL) {
  
  # Build parameter list with correct parameter names
  params <- list(
    n_tree = n_tree,
    mtry = mtry,
    n_split = n_split,
    oobag_fun = oobag_fun,
    sample_fraction = sample_fraction,
    n_thread = config$n_thread
  )
  
  # Add evaluation times if specified
  if (!is.null(eval_times)) {
    params$eval_times <- eval_times
  }
  
  return(params)
}

##' Create aorsf model with optimal parallel settings
##' 
##' @param data Training data
##' @param formula Model formula
##' @param config aorsf configuration object
##' @param ... Additional parameters passed to orsf()
##' @return Fitted aorsf model
aorsf_parallel <- function(data, formula, config, ...) {
  # Get optimal parameters
  params <- get_aorsf_params(config, ...)
  
  # Add formula and data
  params$data <- data
  params$formula <- formula
  
  # Fit model
  do.call(aorsf::orsf, params)
}

##' Predict with aorsf model using parallel processing
##' 
##' @param object Fitted aorsf model
##' @param new_data New data for prediction
##' @param config aorsf configuration object
##' @param times Prediction times
##' @param ... Additional parameters passed to predict()
##' @return Predictions
predict_aorsf_parallel <- function(object, new_data, config, times = NULL, ...) {
  # Build prediction parameters
  params <- list(
    object = object,
    new_data = new_data,
    n_thread = config$n_thread,
    ...
  )
  
  # Add times if specified
  if (!is.null(times)) {
    params$times <- times
  }
  
  # Make prediction
  do.call(predict, params)
}

##' Monitor aorsf performance during training
##' 
##' @param config aorsf configuration object
##' @param log_file File to write performance logs
##' @param interval Monitoring interval in seconds
##' @return Function to stop monitoring
monitor_aorsf_performance <- function(config, 
                                    log_file = "logs/aorsf_performance.log", 
                                    interval = 10) {
  
  if (!dir.exists(dirname(log_file))) {
    dir.create(dirname(log_file), recursive = TRUE)
  }
  
  message(sprintf("Monitoring aorsf performance to: %s", log_file))
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
        
        # aorsf-specific info
        aorsf_info <- sprintf("AORSF_THREADS: %s | R_LIMITATION: %s", 
                             ifelse(config$n_thread == 0, "auto-detect", as.character(config$n_thread)),
                             config$r_function_limitation)
        
        # Format log entry
        log_entry <- sprintf("[%s] %s | %s | %s | %s", 
                            timestamp, mem_info, cpu_info, aorsf_info, "AORSF_MONITOR")
        
        # Write to log file
        write(log_entry, file = log_file, append = TRUE)
        
      }, error = function(e) {
        # Fallback logging
        log_entry <- sprintf("[%s] AORSF_MONITOR | Error: %s", timestamp, e$message)
        write(log_entry, file = log_file, append = TRUE)
      })
      
      Sys.sleep(interval)
    }
  }
  
  # Return monitoring function
  return(monitor_func)
}

##' Benchmark aorsf performance with different thread configurations
##' 
##' @param data Training data
##' @param formula Model formula
##' @param thread_configs Vector of thread configurations to test
##' @param n_tree Number of trees for benchmarking
##' @param n_runs Number of runs per configuration
##' @return Data frame with benchmark results
benchmark_aorsf_threads <- function(data, formula, 
                                  thread_configs = c(1, 2, 4, 8, 0),
                                  n_tree = 1000,
                                  n_runs = 3) {
  
  results <- list()
  
  for (threads in thread_configs) {
    message(sprintf("Benchmarking with %d threads...", threads))
    
    # Configure aorsf for this thread count
    config <- configure_aorsf_parallel(n_thread = threads, verbose = FALSE)
    
    # Run multiple times
    run_times <- numeric(n_runs)
    
    for (run in seq_len(n_runs)) {
      start_time <- Sys.time()
      
      # Fit model
      model <- aorsf_parallel(data, formula, config, n_tree = n_tree)
      
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

##' Get aorsf system information
##' 
##' @return List with system information relevant to aorsf
get_aorsf_system_info <- function() {
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
    aorsf_loaded = requireNamespace("aorsf", quietly = TRUE),
    aorsf_version = if (requireNamespace("aorsf", quietly = TRUE)) {
      as.character(packageVersion("aorsf"))
    } else "Not installed",
    environment_vars = list(
      OMP_NUM_THREADS = Sys.getenv("OMP_NUM_THREADS", unset = "Not set"),
      MKL_NUM_THREADS = Sys.getenv("MKL_NUM_THREADS", unset = "Not set"),
      OPENBLAS_NUM_THREADS = Sys.getenv("OPENBLAS_NUM_THREADS", unset = "Not set"),
      VECLIB_MAXIMUM_THREADS = Sys.getenv("VECLIB_MAXIMUM_THREADS", unset = "Not set"),
      NUMEXPR_NUM_THREADS = Sys.getenv("NUMEXPR_NUM_THREADS", unset = "Not set"),
      AORSF_NTHREAD = Sys.getenv("AORSF_NTHREAD", unset = "Not set")
    ),
    r_function_limitation = FALSE  # Placeholder for actual detection
  )
  
  return(info)
}

##' Print aorsf system information
##' 
##' @param info System information object (from get_aorsf_system_info)
print_aorsf_system_info <- function(info = NULL) {
  if (is.null(info)) {
    info <- get_aorsf_system_info()
  }
  
  message("=== aorsf System Information ===")
  message(sprintf("R Version: %s", info$r_version))
  message(sprintf("Platform: %s", info$platform))
  message(sprintf("Available cores: %s", info$available_cores))
  message(sprintf("aorsf loaded: %s", info$aorsf_loaded))
  message(sprintf("aorsf version: %s", info$aorsf_version))
  message(sprintf("R function limitation: %s", info$r_function_limitation))
  message("\nEnvironment Variables:")
  for (var in names(info$environment_vars)) {
    message(sprintf("  %s = %s", var, info$environment_vars[[var]]))
  }
  message("===============================")
}

##' Check for R functions that limit aorsf threading
##' 
##' @param custom_functions List of custom functions to check
##' @return List with R function limitation information
check_aorsf_r_functions <- function(custom_functions = NULL) {
  limitation_info <- list(
    has_r_functions = FALSE,
    limited_functions = character(0),
    recommendation = "Use n_thread = 0 for optimal performance"
  )
  
  # Check for common R functions that limit threading
  common_limiting_functions <- c(
    "custom_oob_error",
    "custom_linear_combinations",
    "custom_split_functions"
  )
  
  if (!is.null(custom_functions)) {
    for (func in custom_functions) {
      if (is.function(func)) {
        limitation_info$has_r_functions <- TRUE
        limitation_info$limited_functions <- c(limitation_info$limited_functions, deparse(substitute(func)))
      }
    }
  }
  
  if (limitation_info$has_r_functions) {
    limitation_info$recommendation <- "R functions detected - use n_thread = 1 to avoid crashes"
  }
  
  return(limitation_info)
}
