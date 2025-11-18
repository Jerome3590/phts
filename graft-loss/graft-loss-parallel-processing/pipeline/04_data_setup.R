# ===================
# STEP 4: DATA SETUP AND PREPARATION
# ===================
# This step handles data loading, variable setup, and preparation for model fitting.

# --- Use unified orch_bg_ logging system (matches all other pipeline steps) ---
cohort_name <- Sys.getenv("DATASET_COHORT", unset = "unknown")

# UNIFIED LOG FILE LOCATION STRUCTURE (matches 01-05 pipeline steps):
# logs/orch_bg_{cohort_name}.log
# Example: logs/orch_bg_original_study.log
log_file <- switch(cohort_name,
  original = "logs/orch_bg_original_study.log",
  full_with_covid = "logs/orch_bg_full_with_covid.log",
  full_without_covid = "logs/orch_bg_full_without_covid.log",
  "logs/orch_bg_unknown.log"
)

# --- Early logging setup: ensure early_log_file is defined ---
early_log_file <- gsub("orch_bg_", "early_", log_file)
# --- Step timing setup: ensure step_start_time is defined ---
step_start_time <- Sys.time()

# Note: Logging is managed by run_pipeline.R orchestrator
# Individual pipeline scripts should not set up their own sink/on.exit handlers
# to avoid conflicts with the parent script's logging management
dir.create(dirname(log_file), showWarnings = FALSE, recursive = TRUE)

# Use unified orch_bg_ logging format (matches all other pipeline steps)
cat(sprintf("\n[04_data_setup.R] Starting data setup and preparation\n"))
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
cat("Log file path: ", log_file, "\n")

# Load modular components
source(here::here("scripts", "R", "fit_models_parallel.R"))
source(here::here("scripts", "R", "environment_transition.R"))

# Protected setup with error logging
tryCatch({
  cat("[DEBUG] About to source 00_setup.R...\n")
  cat("[DEBUG] Current working directory:", getwd(), "\n")
  cat("[DEBUG] File exists check:", file.exists("pipeline/00_setup.R"), "\n")
  cat("[DEBUG] About to call source()...\n")
  source("pipeline/00_setup.R")
  cat("[DEBUG] Successfully sourced 00_setup.R\n")
  
  # Load data and setup variables
  cat("[DEBUG] Setting up model data...\n")
  data_setup <- setup_model_data()
  if (!data_setup$success) {
    stop(data_setup$error)
  }
  
  # Save data setup for next steps (cohort-specific)
  data_setup_file <- get_cohort_path(here::here('model_data', 'data_setup.rds'), cohort_name)
  saveRDS(data_setup, data_setup_file)
  cat(sprintf("[DEBUG] Data setup saved to: %s\n", data_setup_file))
  
  # Log summary
  cat("\n=== DATA SETUP SUMMARY ===\n")
  cat(sprintf("Dataset: %d rows, %d columns\n", nrow(data_setup$final_data), ncol(data_setup$final_data)))
  cat(sprintf("Model variables: %d encoded terms\n", length(data_setup$model_vars)))
  cat(sprintf("Original variables: %d terms\n", length(data_setup$original_vars)))
  cat(sprintf("Wisotzkey features: %d available\n", length(data_setup$available_wisotzkey)))
  cat(sprintf("MC-CV enabled: %s\n", data_setup$mc_cv))
  cat(sprintf("Testing rows: %d splits\n", length(data_setup$testing_rows)))
  cat("===========================\n")
  
  cat("[DEBUG] Data setup completed successfully\n")
  
}, error = function(e) {
  cat(sprintf("[ERROR] Data setup failed: %s\n", e$message))
  stop(e)
})

cat("=====================================\n")
cat("[DEBUG] ===============================================\n\n")
flush.console()

# Append session info snapshot for reproducibility
try({
  si_path <- here::here('logs', paste0('sessionInfo_step04_', format(Sys.time(), '%Y%m%d_%H%M%S'), '.txt'))
  dir.create(here::here('logs'), showWarnings = FALSE, recursive = TRUE)
  utils::capture.output(sessionInfo(), file = si_path)
  message('Saved sessionInfo to ', si_path)
}, silent = TRUE)
