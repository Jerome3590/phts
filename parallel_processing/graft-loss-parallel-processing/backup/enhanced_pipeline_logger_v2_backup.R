#!/usr/bin/env Rscript

# Enhanced Pipeline Logger v2: Simple wrapper for run_pipeline.R with resource monitoring
# Usage: enhanced_pipeline_logger_v2.R <dataset_name> <log_file>

dataset_name <- args[1]

cat("[DIAGNOSTIC] Logger script started\n")
args <- commandArgs(trailingOnly = TRUE)
cat("[DIAGNOSTIC] Command line args: ", paste(args, collapse = ", "), "\n")
if (length(args) < 2) {
  stop("Usage: enhanced_pipeline_logger_v2.R <dataset_name> <log_file>")
}

dataset_name <- args[1]
log_file <- args[2]
cat("[DIAGNOSTIC] Log file path: ", log_file, "\n")
cat("[DIAGNOSTIC] Working directory: ", getwd(), "\n")

# Setup logging functions
log_with_resources <- function(message, step = NULL) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  # Get current process PID
  pid <- Sys.getpid()
  
  # Memory usage (safe cross-platform method)
  mem_info <- tryCatch({
    if (file.exists("/proc/meminfo")) {
      meminfo <- readLines("/proc/meminfo")
      total_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemTotal", meminfo)])) / 1024 / 1024
      avail_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemAvailable", meminfo)])) / 1024 / 1024
      used_mem <- total_mem - avail_mem
      sprintf("MEM: %.1f/%.1f GB (%.1f%%)", used_mem, total_mem, (used_mem/total_mem)*100)
    } else {
      "MEM: N/A"
    }
  }, error = function(e) "MEM: Error")
  
  # CPU usage (basic)
  cpu_info <- tryCatch({
    if (file.exists("/proc/loadavg")) {
      load_avg <- readLines("/proc/loadavg")[1]
      load_1m <- as.numeric(strsplit(load_avg, " ")[[1]][1])
      cores <- parallel::detectCores(logical = TRUE)
      cpu_pct <- (load_1m / cores) * 100
      sprintf("CPU: %.1f%%", cpu_pct)
    } else {
      "CPU: N/A"
    }
  }, error = function(e) "CPU: N/A")
  
  # Format message
  step_prefix <- if (!is.null(step)) sprintf("[STEP: %s] | ", step) else "| "
  formatted_msg <- sprintf("[%s] [%s] %s%s | %s | %s",
                          timestamp, dataset_name, step_prefix, mem_info, cpu_info, message)
  
  # Log to console and file
  cat(formatted_msg, "\n")
  cat(formatted_msg, "\n", file = log_file, append = TRUE)
}

# Start logging
log_with_resources(sprintf("=== Enhanced Pipeline Logger v2 Started for %s ===", dataset_name))
log_with_resources(sprintf("PID: %d | Log File: %s", Sys.getpid(), log_file))

# Execute the pipeline with monitoring
tryCatch({
  
  log_with_resources("Initializing pipeline wrapper...", step = "INIT")
  
  # Robust file path resolution for EC2
  run_pipeline_path <- "scripts/run_pipeline.R"
  
  # Check current working directory and adjust if needed
  if (!file.exists(run_pipeline_path)) {
    # Try from project root
    if (basename(getwd()) == "scripts") {
      setwd("..")
      log_with_resources("Adjusted working directory to project root", step = "SETUP")
    }
    
    # Recheck
    if (!file.exists(run_pipeline_path)) {
      # Try alternative locations
      alt_paths <- c(
        "run_pipeline.R",
        "../scripts/run_pipeline.R", 
        "./scripts/run_pipeline.R"
      )
      
      found <- FALSE
      for (alt_path in alt_paths) {
        if (file.exists(alt_path)) {
          run_pipeline_path <- alt_path
          found <- TRUE
          log_with_resources(sprintf("Found pipeline at alternative path: %s", alt_path), step = "SETUP")
          break
        }
      }
      
      if (!found) {
        stop("run_pipeline.R not found. Checked paths: ", paste(c("scripts/run_pipeline.R", alt_paths), collapse = ", "))
      }
    }
  }
  
  log_with_resources(sprintf("Executing: %s (from %s)", run_pipeline_path, getwd()), step = "EXEC")
  
  # Execute run_pipeline.R with error handling
  # This preserves all the existing logic and error handling in run_pipeline.R
  source(run_pipeline_path, local = FALSE, echo = FALSE)
  
  log_with_resources("Pipeline execution completed successfully", step = "SUCCESS")
  
}, error = function(e) {
  log_with_resources(sprintf("PIPELINE FAILED: %s", as.character(e)), step = "ERROR")
  
  # Get traceback safely
  tb <- tryCatch({
    tb_lines <- capture.output(traceback())
    if (length(tb_lines) > 0) {
      paste(tb_lines, collapse = "\n")
    } else {
      "No traceback available"
    }
  }, error = function(e2) "Traceback capture failed")
  
  log_with_resources(sprintf("Traceback: %s", tb), step = "ERROR")
  quit(status = 1)
})

# Final resource report
log_with_resources(sprintf("=== Pipeline %s Completed Successfully ===", dataset_name), step = "FINAL")

# Memory cleanup summary
tryCatch({
  gc_result <- gc()
  log_with_resources(sprintf("Final memory: %.1f MB used, %.1f MB max used", 
                           sum(gc_result[,"used"] * c(8, 8)), 
                           sum(gc_result[,"max used"] * c(8, 8))), step = "FINAL")
}, error = function(e) {
  log_with_resources("Memory cleanup summary failed", step = "FINAL")
})

log_with_resources("Enhanced pipeline logger completed", step = "FINAL")