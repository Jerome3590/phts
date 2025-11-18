#!/usr/bin/env Rscript

# Enhanced Pipeline Logger: Wraps run_pipeline.R with resource monitoring and step tracking
# Usage: enhanced_pipeline_logger.R <dataset_name> <log_file>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: enhanced_pipeline_logger.R <dataset_name> <log_file>")
}

dataset_name <- args[1]
log_file <- args[2]

# Setup logging functions
log_with_resources <- function(message, step = NULL) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  # Get current process PID
  pid <- Sys.getpid()
  
  # Memory usage (attempt multiple methods for cross-platform compatibility)
  mem_info <- tryCatch({
    # Try Linux /proc/meminfo first
    if (file.exists("/proc/meminfo")) {
      meminfo <- readLines("/proc/meminfo")
      total_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemTotal", meminfo)])) / 1024 / 1024
      avail_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemAvailable", meminfo)])) / 1024 / 1024
      used_mem <- total_mem - avail_mem
      sprintf("MEM: %.1f/%.1f GB (%.1f%%)", used_mem, total_mem, (used_mem/total_mem)*100)
    } else {
      "MEM: N/A"
    }
  }, error = function(e) "MEM: N/A")
  
  # CPU usage for current process
  cpu_info <- tryCatch({
    if (Sys.which("ps") != "") {
      ps_out <- system(sprintf("ps -p %d -o pcpu= 2>/dev/null || echo 'N/A'", pid), intern = TRUE)
      if (length(ps_out) > 0 && ps_out != "N/A") {
        sprintf("CPU: %s%%", trimws(ps_out))
      } else {
        "CPU: N/A"
      }
    } else {
      "CPU: N/A"
    }
  }, error = function(e) "CPU: N/A")
  
  # Format log entry
  step_info <- if (!is.null(step)) sprintf("[STEP: %s] ", step) else ""
  log_entry <- sprintf("[%s] [%s] %s| %s | %s | %s", 
                      timestamp, dataset_name, step_info, mem_info, cpu_info, message)
  
  # Write to both console and log file
  cat(log_entry, "\n")
  cat(log_entry, "\n", file = log_file, append = TRUE)
}

# Log start of enhanced logging
log_with_resources(sprintf("=== Enhanced Pipeline Logger Started for %s ===", dataset_name))
log_with_resources(sprintf("PID: %d | Log File: %s", Sys.getpid(), log_file))

# Monitor pipeline progress by wrapping run_pipeline.R
tryCatch({
  
  # Source the actual pipeline with step monitoring
  log_with_resources("Initializing pipeline...", step = "INIT")
  
  # Get script directory and set working directory
  script_dir <- dirname(normalizePath(sys.frame(1)$ofile))
  project_root <- normalizePath(file.path(script_dir, ".."))
  setwd(project_root)
  
  log_with_resources(sprintf("Working directory: %s", getwd()), step = "SETUP")
  
  # Source config and initialize
  source(file.path("scripts", "config.R"))
  log_with_resources("Config loaded", step = "SETUP")
  
  # Initialize pipeline
  initialize_pipeline(load_functions = TRUE, minimal_packages = FALSE, quiet = TRUE)
  log_with_resources("Pipeline initialized", step = "SETUP")
  
  # Load the main pipeline plan
  source(file.path("R", "plan.R"))
  log_with_resources("Pipeline plan loaded", step = "SETUP")
  
  # Execute pipeline with step-by-step monitoring
  log_with_resources("Starting pipeline execution...", step = "EXEC")
  
  # Enhanced drake execution with progress monitoring
  if (requireNamespace("drake", quietly = TRUE)) {
    
    # Get all targets from the plan
    all_targets <- drake::drake_plan_source(plan)$target
    total_targets <- length(all_targets)
    
    log_with_resources(sprintf("Total pipeline targets: %d", total_targets), step = "EXEC")
    
    # Execute with monitoring
    drake::make(plan, verbose = 2, lock_envir = FALSE, 
                hook = list(
                  start = function(target) {
                    current_step <- which(all_targets == target)
                    log_with_resources(sprintf("Starting target: %s (%d/%d)", 
                                             target, current_step, total_targets), 
                                     step = sprintf("TARGET-%03d", current_step))
                  },
                  finish = function(target) {
                    current_step <- which(all_targets == target)
                    log_with_resources(sprintf("Completed target: %s (%d/%d)", 
                                             target, current_step, total_targets), 
                                     step = sprintf("TARGET-%03d", current_step))
                  },
                  error = function(target, e) {
                    current_step <- which(all_targets == target)
                    log_with_resources(sprintf("ERROR in target: %s (%d/%d) - %s", 
                                             target, current_step, total_targets, as.character(e)), 
                                     step = sprintf("ERROR-%03d", current_step))
                  }
                ))
    
    log_with_resources("Pipeline execution completed successfully", step = "COMPLETE")
    
  } else {
    # Fallback: source run_pipeline.R directly
    log_with_resources("Drake not available, running pipeline directly", step = "FALLBACK")
    source(file.path("scripts", "run_pipeline.R"))
    log_with_resources("Pipeline completed via direct execution", step = "COMPLETE")
  }
  
}, error = function(e) {
  log_with_resources(sprintf("PIPELINE FAILED: %s", as.character(e)), step = "ERROR")
  log_with_resources(sprintf("Traceback: %s", paste(traceback(), collapse = "\n")), step = "ERROR")
  quit(status = 1)
})

# Final resource report
log_with_resources(sprintf("=== Pipeline %s Completed Successfully ===", dataset_name), step = "FINAL")

# Memory cleanup summary
if (exists("gc")) {
  gc_result <- gc()
  log_with_resources(sprintf("Final memory: %.1f MB used, %.1f MB max used", 
                           sum(gc_result[,"used"] * c(8, 8)), 
                           sum(gc_result[,"max used"] * c(8, 8))), step = "FINAL")
}