#!/usr/bin/env Rscript

# run_pipeline.R
# Main pipeline orchestrator for running the complete graft loss analysis pipeline

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

cat("=== Graft Loss Pipeline Orchestrator ===\n")
cat("Project root:", project_root, "\n")
cat("Working directory:", getwd(), "\n")
cat("Timestamp:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Source configuration
source("scripts/R/config.R")

# Initialize pipeline
initialize_pipeline(load_functions = TRUE, minimal_packages = FALSE, quiet = FALSE)

# Define cohorts
cohorts <- c("original", "full_with_covid", "full_without_covid")

# Create logs directory
dir.create("logs", showWarnings = FALSE, recursive = TRUE)

# Function to run pipeline for a single cohort
run_cohort_pipeline <- function(cohort) {
  cat(sprintf("\n=== Starting Pipeline for Cohort: %s ===\n", cohort))
  
  # Set environment variables for this cohort
  Sys.setenv(DATASET_COHORT = cohort)
  
  # Set up cohort-specific log file
  log_file <- switch(cohort,
    original = "logs/orch_bg_original_study.log",
    full_with_covid = "logs/orch_bg_full_with_covid.log",
    full_without_covid = "logs/orch_bg_full_without_covid.log"
  )
  
  # Redirect output to both console and log file
  log_conn <- file(log_file, open = 'at')
  sink(log_conn, split = TRUE)
  sink(log_conn, type = 'message', append = TRUE)
  
  # Set up cleanup on exit
  on.exit({
    try(sink(type = 'message'))
    try(sink())
    try(close(log_conn))
  }, add = TRUE)
  
  cat(sprintf("=== Pipeline Start for %s ===\n", cohort))
  cat("Timestamp:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
  cat("Log file:", log_file, "\n\n")
  
  # Run pipeline steps (prefer pipeline/ wrappers, fall back to scripts/)
  # NOTE: Steps 7 & 8 removed - unnecessary for MC-CV mode
  # - Step 7 (model_saving): Models already saved during Step 6 MC-CV fitting
  # - Step 8 (fallback_handling): Not needed when Step 6 succeeds
  steps <- c(
    "00_setup.R",
    "01_prepare_data.R",
    "02_resampling.R",
    "03_prep_model_data.R",
    "04_data_setup.R",
    "05_mc_cv_analysis.R",
    "06_parallel_model_fitting.R",
    "09_generate_outputs.R"
  )

  for (step in steps) {
    pipeline_path <- file.path("pipeline", step)
    scripts_path  <- file.path("scripts", step)

    if (file.exists(pipeline_path)) {
      step_path <- pipeline_path
      source_origin <- "pipeline"
    } else if (file.exists(scripts_path)) {
      step_path <- scripts_path
      source_origin <- "scripts"
    } else {
      cat(sprintf("\n⚠ %s not found in pipeline/ or scripts/, skipping\n", step))
      next
    }

    cat(sprintf("\n--- Running %s (from %s) ---\n", step, source_origin))
    start_time <- Sys.time()

    tryCatch({
      source(step_path)
      elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
      cat(sprintf("✓ %s completed in %.2f seconds (source: %s)\n", step, elapsed, source_origin))
    }, error = function(e) {
      cat(sprintf("✗ %s failed: %s\n", step, conditionMessage(e)))
      stop(sprintf("Pipeline failed at %s: %s", step, conditionMessage(e)))
    })
  }
  
  cat(sprintf("\n=== Pipeline Complete for %s ===\n", cohort))
  cat("Finished at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
}

# Run pipeline for each cohort
for (cohort in cohorts) {
  tryCatch({
    run_cohort_pipeline(cohort)
  }, error = function(e) {
    cat(sprintf("\n✗ Pipeline failed for cohort %s: %s\n", cohort, conditionMessage(e)))
    # Continue with other cohorts
  })
}

cat("\n=== All Pipeline Runs Complete ===\n")
cat("Finished at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")

