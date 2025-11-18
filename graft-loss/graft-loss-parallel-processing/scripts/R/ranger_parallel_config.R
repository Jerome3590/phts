##' Ranger Parallel Processing Configuration
##' 
##' Comprehensive configuration for optimal ranger parallel processing
##' Based on ranger's C++ implementation and multithreading capabilities
##' 
##' Key features:
##' - Automatic thread detection and configuration
##' - Environment variable management for ranger threads
##' - Memory-efficient parallel processing
##' - Performance monitoring and optimization
##' - Integration with existing pipeline parallel setup

##' Configure ranger parallel processing settings
##' 
##' @param num_threads Number of threads for ranger (0 = all cores, NULL = auto-detect)
##' @param use_all_cores Whether to use all available cores (overrides num_threads)
##' @param target_utilization Target CPU utilization (0.8 = 80%)
##' @param memory_efficient Whether to enable memory saving mode
##' @param regularization_factor Regularization factor (disables multithreading if > 0)
##' @param verbose Whether to print configuration details
##' @return List with ranger configuration settings
configure_ranger_parallel <- function(num_threads = NULL, 
                                    use_all_cores = TRUE,
                                    target_utilization = 0.8,
                                    memory_efficient = FALSE,
                                    regularization_factor = 0,
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
  if (is.null(num_threads)) {
    if (use_all_cores) {
      # CRITICAL FIX: Cap threads on EC2 to prevent hanging
      # EC2 instances with many cores can cause ranger to hang when using all cores
      max_safe_threads <- as.numeric(Sys.getenv("RSF_MAX_THREADS", unset = "16"))
      if (available_cores > max_safe_threads) {
        num_threads <- max_safe_threads
        if (verbose) {
          message(sprintf("EC2 Safety: Capping ranger threads to %d (detected %d cores)", 
                         max_safe_threads, available_cores))
        }
      } else {
        num_threads <- 0  # Use all cores if under the safety limit
      }
    } else {
      num_threads <- max(1L, floor(available_cores * target_utilization))
    }
  }
  
  # Check for regularization (disables multithreading)
  if (regularization_factor > 0) {
    if (verbose) {
      message("Regularization enabled - ranger multithreading will be disabled")
    }
    num_threads <- 1L
  }
  
  # Set ranger-specific environment variables
  # CRITICAL FIX: Always set BLAS/OpenMP to 1 thread to prevent oversubscription
  # Ranger handles its own threading internally, BLAS should be single-threaded
  ranger_env_vars <- list(
    R_RANGER_NUM_THREADS = as.character(num_threads),  # Package can use 0 or specific count
    OMP_NUM_THREADS = "1",                             # Always 1 to prevent oversubscription
    MKL_NUM_THREADS = "1",                             # Always 1 to prevent oversubscription
    OPENBLAS_NUM_THREADS = "1",                        # Always 1 to prevent oversubscription
    VECLIB_MAXIMUM_THREADS = "1",                      # Always 1 to prevent oversubscription
    NUMEXPR_NUM_THREADS = "1"                          # Always 1 to prevent oversubscription
  )
  
  # Apply environment variables
  for (var_name in names(ranger_env_vars)) {
    do.call(Sys.setenv, setNames(list(ranger_env_vars[[var_name]]), var_name))
  }
  
  # Set R options for ranger
  options(ranger.num.threads = num_threads)
  
  # Create configuration object
  config <- list(
    num_threads = num_threads,
    available_cores = available_cores,
    target_utilization = target_utilization,
    memory_efficient = memory_efficient,
    regularization_factor = regularization_factor,
    environment_vars = ranger_env_vars,
    timestamp = Sys.time()
  )
  
  if (verbose) {
    message("=== Ranger Parallel Configuration ===")
    message(sprintf("Available cores: %d", available_cores))
    message(sprintf("Ranger threads: %s", ifelse(num_threads == 0, "all cores", as.character(num_threads))))
    message(sprintf("Target utilization: %.1f%%", target_utilization * 100))
    message(sprintf("Memory efficient: %s", memory_efficient))
    message(sprintf("Regularization factor: %.2f", regularization_factor))
    message("Environment variables set:")
    for (var in names(ranger_env_vars)) {
      message(sprintf("  %s = %s", var, ranger_env_vars[[var]]))
    }
    message("=====================================")
  }
  
  return(config)
}

##' Get optimal ranger parameters for parallel processing
##' 
##' @param config Ranger configuration object (from configure_ranger_parallel)
##' @param num_trees Number of trees (default: 1000)
##' @param min_node_size Minimum node size (default: 10)
##' @param splitrule Split rule (default: 'C' for C-index)
##' @param importance Importance calculation method (default: 'none' for speed)
##' @param write_forest Whether to write forest (default: TRUE)
##' @param save_memory Whether to use memory saving mode
##' @return List of ranger parameters optimized for parallel processing
get_ranger_params <- function(config, 
                            num_trees = 1000,
                            min_node_size = 10,
                            splitrule = 'C',
                            importance = 'none',
                            write_forest = TRUE,
                            save_memory = NULL,
                            num_random_splits = NULL) {
  
  # Use memory efficient mode if specified in config or parameter
  if (is.null(save_memory)) {
    save_memory <- config$memory_efficient
  }
  
  # Build parameter list
  params <- list(
    num.trees = num_trees,
    min.node.size = min_node_size,
    splitrule = splitrule,
    importance = importance,
    write.forest = write_forest,
    num.threads = config$num_threads,
    save.memory = save_memory
  )
  
  # Add num.random.splits if specified
  if (!is.null(num_random_splits)) {
    params$num.random.splits <- num_random_splits
  }
  
  # Add regularization if specified
  if (config$regularization_factor > 0) {
    params$regularization.factor <- config$regularization_factor
  }
  
  return(params)
}

##' Create ranger model with optimal parallel settings
##' 
##' @param formula Model formula
##' @param data Training data
##' @param config Ranger configuration object
##' @param ... Additional parameters passed to ranger()
##' @return Fitted ranger model
ranger_parallel <- function(formula, data, config, ...) {
  # Convert dot-notation parameters to underscore notation for get_ranger_params
  dots <- list(...)
  
  # Map dot-notation to underscore notation
  if (!is.null(dots$num.trees)) dots$num_trees <- dots$num.trees
  if (!is.null(dots$min.node.size)) dots$min_node_size <- dots$min.node.size
  if (!is.null(dots$num.random.splits)) dots$num_random_splits <- dots$num.random.splits
  if (!is.null(dots$write.forest)) dots$write_forest <- dots$write.forest
  
  # Remove dot-notation parameters
  dots <- dots[!names(dots) %in% c("num.trees", "min.node.size", "num.random.splits", "write.forest")]
  
  # Get optimal parameters
  params <- do.call(get_ranger_params, c(list(config = config), dots))
  
  # Add formula and data
  params$formula <- formula
  params$data <- data
  
  # CRITICAL FIX: Add timeout protection for ranger fitting
  # EC2 instances with many cores can cause ranger to hang
  timeout_minutes <- as.numeric(Sys.getenv("RSF_TIMEOUT_MINUTES", unset = "30"))
  
  tryCatch({
    # Use R.utils::withTimeout if available, otherwise use base timeout
    if (requireNamespace("R.utils", quietly = TRUE)) {
      result <- R.utils::withTimeout({
        do.call(ranger::ranger, params)
      }, timeout = timeout_minutes * 60, onTimeout = "error")
    } else {
      # Fallback: use setTimeLimit (less reliable but better than nothing)
      setTimeLimit(elapsed = timeout_minutes * 60)
      on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
      result <- do.call(ranger::ranger, params)
    }
    return(result)
  }, error = function(e) {
    if (grepl("timeout|time.*out", e$message, ignore.case = TRUE)) {
      # Timeout occurred - try with reduced threads
      warning(sprintf("Ranger fitting timed out after %d minutes, retrying with single thread", timeout_minutes))
      
      # Force single-threaded mode
      params$num.threads <- 1
      
      # Also reduce trees if timeout
      if (params$num.trees > 500) {
        params$num.trees <- 500
        warning("Reduced tree count to 500 due to timeout")
      }
      
      # Retry with conservative settings
      tryCatch({
        do.call(ranger::ranger, params)
      }, error = function(e2) {
        stop(sprintf("Ranger fitting failed even with conservative settings: %s", e2$message))
      })
    } else {
      # Re-throw non-timeout errors
      stop(sprintf("Ranger fitting failed: %s", e$message))
    }
  })
}

##' Predict with ranger model using parallel processing
##' 
##' @param object Fitted ranger model
##' @param newdata New data for prediction
##' @param config Ranger configuration object
##' @param ... Additional parameters passed to predict.ranger()
##' @return Predictions
predict_ranger_parallel <- function(object, newdata, config, ...) {
  # Try different parameter names for predict.ranger to support multiple ranger versions
  err_msgs <- character(0)
  result <- tryCatch({
    params <- list(object = object, new_data = newdata, num.threads = config$num_threads)
    params <- c(params, list(...))
    do.call(ranger::predict.ranger, params)
  }, error = function(e) {
    err_msgs <<- c(err_msgs, paste0('new_data: ', e$message)); NULL
  })

  if (is.null(result)) {
    result <- tryCatch({
      params <- list(object = object, data = newdata, num.threads = config$num_threads)
      params <- c(params, list(...))
      do.call(ranger::predict.ranger, params)
    }, error = function(e) {
      err_msgs <<- c(err_msgs, paste0('data: ', e$message)); NULL
    })
  }

  if (is.null(result)) {
    result <- tryCatch({
      params <- list(object = object, newdata = newdata, num.threads = config$num_threads)
      params <- c(params, list(...))
      do.call(ranger::predict.ranger, params)
    }, error = function(e) {
      err_msgs <<- c(err_msgs, paste0('newdata: ', e$message)); NULL
    })
  }

  if (is.null(result)) {
    stop(sprintf('predict_ranger_parallel: unable to call predict.ranger. Attempts: %s', paste(err_msgs, collapse = ' | ')))
  }

  return(result)
}

##' Monitor ranger performance during training
##' 
##' @param config Ranger configuration object
##' @param log_file File to write performance logs
##' @param interval Monitoring interval in seconds
##' @return Function to stop monitoring
monitor_ranger_performance <- function(config, 
                                     log_file = "logs/ranger_performance.log", 
                                     interval = 10) {
  
  if (!dir.exists(dirname(log_file))) {
    dir.create(dirname(log_file), recursive = TRUE)
  }
  
  message(sprintf("Monitoring ranger performance to: %s", log_file))
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
        
        # Ranger-specific info
        ranger_info <- sprintf("RANGER_THREADS: %s", 
                              ifelse(config$num_threads == 0, "all cores", as.character(config$num_threads)))
        
        # Format log entry
        log_entry <- sprintf("[%s] %s | %s | %s | %s", 
                            timestamp, mem_info, cpu_info, ranger_info, "RANGER_MONITOR")
        
        # Write to log file
        write(log_entry, file = log_file, append = TRUE)
        
      }, error = function(e) {
        # Fallback logging
        log_entry <- sprintf("[%s] RANGER_MONITOR | Error: %s", timestamp, e$message)
        write(log_entry, file = log_file, append = TRUE)
      })
      
      Sys.sleep(interval)
    }
  }
  
  # Return monitoring function
  return(monitor_func)
}

##' Benchmark ranger performance with different thread configurations
##' 
##' @param formula Model formula
##' @param data Training data
##' @param thread_configs Vector of thread configurations to test
##' @param num_trees Number of trees for benchmarking
##' @param n_runs Number of runs per configuration
##' @return Data frame with benchmark results
benchmark_ranger_threads <- function(formula, data, 
                                   thread_configs = c(1, 2, 4, 8, 0),
                                   num_trees = 1000,
                                   n_runs = 3) {
  
  results <- list()
  
  for (threads in thread_configs) {
    message(sprintf("Benchmarking with %d threads...", threads))
    
    # Configure ranger for this thread count
    config <- configure_ranger_parallel(num_threads = threads, verbose = FALSE)
    
    # Run multiple times
    run_times <- numeric(n_runs)
    
    for (run in seq_len(n_runs)) {
      start_time <- Sys.time()
      
      # Fit model
      model <- ranger_parallel(formula, data, config, num.trees = num_trees)
      
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

##' Get ranger system information
##' 
##' @return List with system information relevant to ranger
get_ranger_system_info <- function() {
  # Use the comprehensive version checker if available
  if (exists("check_model_versions")) {
    all_versions <- check_model_versions()
    return(list(
      r_version = all_versions$r_info$r_version_string,
      platform = all_versions$r_info$r_platform,
      available_cores = all_versions$system_info$available_cores,
      ranger_loaded = all_versions$packages$ranger$loaded,
      ranger_version = all_versions$packages$ranger$version,
      environment_vars = all_versions$environment_vars,
      r_options = all_versions$r_options
    ))
  } else {
    # Fallback to original implementation
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
      ranger_loaded = requireNamespace("ranger", quietly = TRUE),
      ranger_version = if (requireNamespace("ranger", quietly = TRUE)) {
        as.character(packageVersion("ranger"))
      } else "Not installed",
      environment_vars = list(
        R_RANGER_NUM_THREADS = Sys.getenv("R_RANGER_NUM_THREADS", unset = "Not set"),
        OMP_NUM_THREADS = Sys.getenv("OMP_NUM_THREADS", unset = "Not set"),
        MKL_NUM_THREADS = Sys.getenv("MKL_NUM_THREADS", unset = "Not set"),
        OPENBLAS_NUM_THREADS = Sys.getenv("OPENBLAS_NUM_THREADS", unset = "Not set")
      ),
      r_options = list(
        ranger.num.threads = getOption("ranger.num.threads", "Not set"),
        Ncpus = getOption("Ncpus", "Not set")
      )
    )
    return(info)
  }
}

##' Print ranger system information
##' 
##' @param info System information object (from get_ranger_system_info)
print_ranger_system_info <- function(info = NULL) {
  if (is.null(info)) {
    info <- get_ranger_system_info()
  }
  
  message("=== Ranger System Information ===")
  message(sprintf("R Version: %s", info$r_version))
  message(sprintf("Platform: %s", info$platform))
  message(sprintf("Available cores: %s", info$available_cores))
  message(sprintf("Ranger loaded: %s", info$ranger_loaded))
  message(sprintf("Ranger version: %s", info$ranger_version))
  message("\nEnvironment Variables:")
  for (var in names(info$environment_vars)) {
    message(sprintf("  %s = %s", var, info$environment_vars[[var]]))
  }
  message("\nR Options:")
  for (opt in names(info$r_options)) {
    message(sprintf("  %s = %s", opt, info$r_options[[opt]]))
  }
  message("===============================")
}
