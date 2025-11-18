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

##' Configure explicit parallel plan by env var MC_PLAN
##' @param workers Integer number of workers
##' @param plan One of 'cluster' (default), 'multisession', 'multicore'
##' @param preload_packages Character vector of packages to load on workers (cluster only)
##' @param preload_sources Character vector of project R files to source on workers (cluster only)
##' @return Named list with selected plan and worker count
configure_explicit_parallel <- function(workers,
                                        plan = tolower(Sys.getenv('MC_PLAN', unset = 'multisession')),
                                        preload_packages = character(0),
                                        preload_sources = character(0)) {
  if (missing(workers) || !is.finite(workers) || workers < 1) {
    stop('configure_explicit_parallel: valid workers required')
  }
  
  # Override parallelly's conservative core detection
  # Get actual physical cores (not limited by threading env vars like OMP_NUM_THREADS)
  cores <- tryCatch({
    parallel::detectCores(logical = TRUE)
  }, error = function(e) {
    32L  # EC2 default
  })
  
  # Tell parallelly to use actual physical cores and allow the requested workers
  options(parallelly.availableCores.system = cores)
  options(parallelly.maxWorkers.localhost = workers)
  
  if (plan %in% c('multicore')) {
    future::plan(future::multicore, workers = workers)
    message(sprintf('Parallel plan: multicore (%d workers)', workers))
  } else if (plan %in% c('multisession', 'session')) {
    future::plan(future::multisession, workers = workers)
    message(sprintf('Parallel plan: multisession (%d workers)', workers))
  } else {
    rscript_bin <- file.path(R.home('bin'), ifelse(.Platform$OS.type == 'windows', 'Rscript.exe', 'Rscript'))
    if (!file.exists(rscript_bin)) rscript_bin <- 'Rscript'
    cl <- parallelly::makeClusterPSOCK(workers, rscript = rscript_bin)
    future::plan(future::cluster, workers = cl)
    message(sprintf('Parallel plan: PSOCK cluster (%d workers)', workers))
    if (length(preload_packages)) {
      parallel::clusterCall(cl, function(pkgs) {
        for (p in pkgs) {
          suppressPackageStartupMessages(try(library(p, character.only = TRUE), silent = TRUE))
        }
        NULL
      }, preload_packages)
    }
    if (length(preload_sources)) {
      parallel::clusterCall(cl, function(files) {
        for (f in files) try(source(f), silent = TRUE)
        NULL
      }, preload_sources)
    }
  }
  list(plan = plan, workers = workers)
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
    # Immediate log/progress output before parallel backend setup
    cat("[parallel_map_optimal] Setting up parallel workers...\n", file = stdout())
    if (exists("write_progress", mode = "function")) {
      try(write_progress(split_done = 0, note = "parallel_map_optimal: Setting up parallel workers"), silent = TRUE)
    }
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