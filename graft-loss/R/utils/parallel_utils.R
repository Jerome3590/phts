##' Parallel processing utilities
##' 
##' Helper functions for efficient parallel processing configuration

##' Configure optimal parallel processing backend (EC2-compatible)
##' @param workers Number of workers (auto-detected if NULL)
##' @param target_utilization Target CPU utilization (0.8 = 80%)
##' @param force_backend Force specific backend ("multicore" or "multisession")
setup_parallel_backend <- function(workers = NULL, target_utilization = 0.8, force_backend = NULL) {
  # Auto-detect optimal workers with EC2 safety
  if (is.null(workers)) {
    workers_env <- suppressWarnings(as.integer(Sys.getenv('MC_SPLIT_WORKERS', unset = '0')))
    if (!is.finite(workers_env) || workers_env < 1) {
      # Robust core detection for EC2
      cores <- tryCatch({
        # Try future package if available
        if (requireNamespace("future", quietly = TRUE)) {
          as.numeric(future::availableCores())
        } else {
          parallel::detectCores(logical = TRUE)
        }
      }, error = function(e) {
        # Fallback: Linux /proc method
        tryCatch({
          length(readLines("/proc/cpuinfo")[grep("^processor", readLines("/proc/cpuinfo"))])
        }, error = function(e2) {
          # Ultimate fallback
          warning("Could not detect cores, defaulting to 4")
          4L
        })
      })
      workers <- max(1L, floor(cores * target_utilization))
    } else {
      workers <- workers_env
    }
  }
  
  # Select optimal backend with EC2 safety checks
  if (is.null(force_backend)) {
    # Check if future package is available
    future_available <- requireNamespace("future", quietly = TRUE)
    
    if (future_available && future::supportsMulticore()) {
      backend <- "multicore"
      tryCatch({
        future::plan(future::multicore, workers = workers)
      }, error = function(e) {
        warning("Multicore setup failed, falling back to basic parallel")
        backend <<- "parallel"
      })
    } else if (future_available) {
      backend <- "multisession" 
      tryCatch({
        future::plan(future::multisession, workers = workers)
      }, error = function(e) {
        warning("Multisession setup failed, falling back to basic parallel")
        backend <<- "parallel"
      })
    } else {
      # Fallback to basic parallel package
      backend <- "parallel"
      warning("Future package not available, using basic parallel")
    }
  } else {
    backend <- force_backend
    if (requireNamespace("future", quietly = TRUE)) {
      tryCatch({
        if (backend == "multicore") {
          future::plan(future::multicore, workers = workers)
        } else if (backend == "multisession") {
          future::plan(future::multisession, workers = workers)
        }
      }, error = function(e) {
        warning("Forced backend setup failed: ", e$message)
        backend <<- "parallel"
      })
    } else {
      backend <- "parallel"
    }
  }
  
  message(sprintf("Configured %s backend with %d workers (%.1f%% utilization)", 
                  backend, workers, target_utilization * 100))
  
  return(list(backend = backend, workers = workers, utilization = target_utilization))
}

##' Parallel map with optimal chunking
##' @param .x Input vector/list
##' @param .f Function to apply
##' @param .workers Number of workers (auto-detected if NULL)
##' @param .chunk_size Chunk size (auto-calculated if NULL)
##' @param .scheduling Scheduling parameter for furrr
##' @param ... Additional arguments to .f
parallel_map_optimal <- function(.x, .f, .workers = NULL, .chunk_size = NULL, 
                                  .scheduling = 1.0, ...) {
  # Setup backend if not already configured
  if (is.null(.workers)) {
    config <- setup_parallel_backend()
    .workers <- config$workers
  }
  
  # Calculate optimal chunk size
  if (is.null(.chunk_size)) {
    .chunk_size <- max(1L, ceiling(length(.x) / .workers))
  }
  
  furrr::future_map(
    .x, 
    .f,
    ...,
    .options = furrr::furrr_options(
      seed = TRUE,
      chunk_size = .chunk_size,
      scheduling = .scheduling
    )
  )
}

##' Monitor parallel processing performance
##' @param log_file File to write performance logs
##' @param interval Monitoring interval in seconds
monitor_parallel_performance <- function(log_file = "logs/parallel_performance.log", 
                                         interval = 30) {
  if (!dir.exists(dirname(log_file))) {
    dir.create(dirname(log_file), recursive = TRUE)
  }
  
  message(sprintf("Monitoring parallel performance to: %s", log_file))
  message("Press Ctrl+C to stop monitoring")
  
  while (TRUE) {
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    
    # Get system stats (platform independent)
    r_processes <- length(grep("R$|Rscript", system("ps -eo comm", intern = TRUE)))
    
    log_line <- sprintf("[%s] R Processes: %d | Memory: %s", 
                        timestamp, r_processes, 
                        format(object.size(ls(envir = .GlobalEnv)), "MB"))
    
    write(log_line, file = log_file, append = TRUE)
    Sys.sleep(interval)
  }
}