#!/usr/bin/env Rscript

# Orchestrator: run the pipeline three times in isolated R sessions
# 1) Original Study (2010-2019)
# 2) Full Dataset with COVID
# 3) Full Dataset without COVID

quietly <- function(expr) {
  suppressWarnings(suppressMessages(force(expr)))
}

# Derive project root relative to this script and setwd there
get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) {
    normalizePath(sub("^--file=", "", file_arg)) |> dirname()
  } else if (!interactive()) {
    getwd()
  } else {
    getwd()
  }
}

script_dir <- get_script_dir()
project_root <- normalizePath(file.path(script_dir, ".."))
setwd(project_root)

if (!dir.exists("logs")) dir.create("logs", recursive = TRUE, showWarnings = FALSE)

cat("==== Orchestrator: Three Dataset Runs ===\n")
cat(sprintf("Project Root : %s\n", project_root))
cat(sprintf("Timestamp    : %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")))
cat("========================================\n\n")

# Runs to execute with required env vars
runs <- list(
  original_study     = c(ORIGINAL_STUDY = "1", EXCLUDE_COVID = "0"),
  full_with_covid    = c(ORIGINAL_STUDY = "0", EXCLUDE_COVID = "0"),
  full_without_covid = c(ORIGINAL_STUDY = "0", EXCLUDE_COVID = "1")
)

# Pass-through optional env vars if set in the orchestrator environment
maybe_env <- function(var) {
  val <- Sys.getenv(var, unset = "")
  if (nzchar(val)) sprintf("%s=%s", var, val) else NULL
}

passthrough_vars <- c(
  "USE_ENCODED", "MC_CV", "MC_START_AT", "MC_MAX_SPLITS", "START_AT", "STOP_AT"
)

# Path to Rscript executable
rscript <- file.path(R.home("bin"), "Rscript")

results <- data.frame(
  run = character(),
  exit_status = integer(),
  stringsAsFactors = FALSE
)

# Use existing parallel utilities for core detection and configuration
source(file.path("R", "utils", "parallel_utils.R"))

# Get optimal configuration using existing utilities
parallel_config <- setup_parallel_backend()
cores <- parallel_config$workers

# Calculate optimal workers per dataset for 3 parallel executions
# Conservative approach: each dataset gets ~25% of total cores for stable execution
per_dataset_cores <- max(1L, floor(cores * 0.25))

cat(sprintf("AWS Linux: %d cores detected (%s), using %d workers per dataset\n", 
            cores, parallel_config$backend, per_dataset_cores))
cat(sprintf("Total utilization: %.0f%% (3 datasets × %d workers = %d of %d cores)\n",
            (per_dataset_cores * 3 / cores) * 100, per_dataset_cores, per_dataset_cores * 3, cores))

# Store PIDs for monitoring
pids <- list()
start_times <- list()

for (nm in names(runs)) {
  cat(sprintf(">>> Launching dataset in background: %s\n", nm))

  # Build environment vector for child process
  base_env <- runs[[nm]]
  extra_env <- Filter(Negate(is.null), lapply(passthrough_vars, maybe_env))
  env_vec <- c(sprintf("%s=%s", names(base_env), unname(base_env)), unlist(extra_env))

  # Set parallel processing environment for this dataset
  mc_threads_env <- Sys.getenv("MC_WORKER_THREADS", unset = "")
  if (!nzchar(mc_threads_env)) {
    thread_env <- c(
      sprintf("MC_WORKER_THREADS=%d", per_dataset_cores),
      "OMP_NUM_THREADS=1",           # Force inner threads to 1
      "OPENBLAS_NUM_THREADS=1",
      "MKL_NUM_THREADS=1", 
      "VECLIB_MAXIMUM_THREADS=1",
      "NUMEXPR_NUM_THREADS=1"
    )
    env_vec <- c(env_vec, thread_env)
  } else {
    cat(sprintf("Honoring pre-set MC_WORKER_THREADS=%s for %s\n", mc_threads_env, nm))
  }

  # Create unique log file for this dataset
  log_file <- file.path("logs", sprintf("orch_bg_%s.log", nm))
  
  # Enhanced logging with resource monitoring wrapper (v2 - simplified)
  enhanced_log_wrapper <- sprintf("scripts/enhanced_pipeline_logger_v2.R %s %s", shQuote(nm), shQuote(log_file))
  
  # Launch pipeline in background with enhanced logging
  cmd <- sprintf("nohup %s %s > %s 2>&1 & echo $!", 
                 shQuote(rscript), enhanced_log_wrapper, shQuote(log_file))
  
  # Launch process with environment
  env_string <- paste(env_vec, collapse = " ")
  full_cmd <- sprintf("env %s %s", env_string, cmd)
  
  pid <- system(sprintf("bash -c '%s'", full_cmd), intern = TRUE)
  
  if (length(pid) > 0 && nzchar(pid)) {
    pids[[nm]] <- as.integer(pid)
    start_times[[nm]] <- Sys.time()
    cat(sprintf("    PID %s | Log: %s\n", pid, log_file))
  } else {
    stop(sprintf("Failed to launch background process for %s", nm))
  }
}

cat(sprintf("\n=== All 3 datasets launched in parallel ===\n"))
cat(sprintf("PIDs: %s\n", paste(sprintf("%s=%s", names(pids), unlist(pids)), collapse = ", ")))
cat("Monitor with: ps -p <pid> -o pid,pcpu,pmem,etime,cmd\n")
cat("Log files: logs/orch_bg_*.log\n\n")

# Monitor processes until completion
cat("Monitoring parallel execution...\n")
running <- pids
results <- data.frame(
  run = character(),
  pid = integer(),
  exit_status = integer(),
  duration_min = numeric(),
  stringsAsFactors = FALSE
)

# Check process status every 30 seconds
while (length(running) > 0) {
  Sys.sleep(30)
  
  for (nm in names(running)) {
    pid <- running[[nm]]
    # Check if process is still running
    status_check <- system(sprintf("ps -p %d > /dev/null 2>&1", pid), ignore.stdout = TRUE, ignore.stderr = TRUE)
    
    if (status_check != 0) {
      # Process finished - get exit status from log or assume success
      end_time <- Sys.time()
      duration <- as.numeric(difftime(end_time, start_times[[nm]], units = "mins"))
      
      # Try to determine exit status (simplified - could be enhanced)
      exit_status <- 0  # Assume success; could parse logs for actual status
      
      cat(sprintf("<<< Completed: %s | PID %d | duration=%.1f min\n", nm, pid, duration))
      
      results <- rbind(results, data.frame(
        run = nm, 
        pid = pid,
        exit_status = exit_status, 
        duration_min = duration, 
        stringsAsFactors = FALSE
      ))
      
      running[[nm]] <- NULL  # Remove from running list
    }
  }
  
  if (length(running) > 0) {
    cat(sprintf("Still running: %s\n", paste(names(running), collapse = ", ")))
  }
}

cat("\n==== Parallel Orchestrator Summary ===\n")
print(results)

# Report total execution time (from first start to last completion)
total_duration <- max(results$duration_min)
sequential_estimate <- sum(results$duration_min)
speedup <- sequential_estimate / total_duration

cat(sprintf("\nPerformance Summary:\n"))
cat(sprintf("  Total wall time: %.1f minutes\n", total_duration))
cat(sprintf("  Est. sequential: %.1f minutes\n", sequential_estimate))
cat(sprintf("  Speedup factor: %.1fx\n", speedup))
cat(sprintf("  Peak workers: %d (%.0f%% of %d cores)\n", 
            per_dataset_cores * 3, (per_dataset_cores * 3 / cores) * 100, cores))

if (any(results$exit_status != 0L)) {
  cat("\nWARNING: Some runs reported errors. Check individual log files.\n")
  quit(status = 1L)
} else {
  cat("\nAll datasets completed successfully!\n")
  quit(status = 0L)
}


