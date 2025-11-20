# ===================
# STEP 7: MODEL SAVING AND INDEXING
# ===================
# This step handles model saving, comparison indexing, and CatBoost fitting.

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
cat(sprintf("\n[07_model_saving.R] Starting model saving and indexing\n"))
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
cat("Log file path: ", log_file, "\n")

# Load modular components
source(here::here("scripts", "R", "model_saving.R"))
source(here::here("scripts", "R", "environment_transition.R"))

# Protected setup with error logging
tryCatch({
  cat("[DEBUG] About to source 00_setup.R...\n")
  cat("[DEBUG] Current working directory:", getwd(), "\n")
  cat("[DEBUG] File exists check:", file.exists("pipeline/00_setup.R"), "\n")
  cat("[DEBUG] About to call source()...\n")
  source("pipeline/00_setup.R")
  cat("[DEBUG] Successfully sourced 00_setup.R\n")
  
  # Load data setup from previous step (cohort-specific)
  data_setup_file <- get_cohort_path(here::here('model_data', 'data_setup.rds'), cohort_name)
  if (file.exists(data_setup_file)) {
    data_setup <- readRDS(data_setup_file)
    cat("[DEBUG] Loaded data setup from previous step\n")
  } else {
    stop("data_setup.rds not found. Please run step 04 first.")
  }
  
  # Load model results from previous step (cohort-specific)
  models_file <- get_cohort_path(here::here('model_data', 'final_models.rds'), cohort_name)
  if (file.exists(models_file)) {
    final_models <- readRDS(models_file)
    cat("[DEBUG] Loaded model results from previous step\n")
  } else {
    stop("final_models.rds not found. Please run step 06 first.")
  }
  
  if (final_models$success) {
    cat("[DEBUG] Processing successful model results...\n")
    
    # Handle optional CatBoost fitting
    final_models$results <- handle_catboost_fitting(data_setup, final_models$results)
    
    # Save results and create comparison index
    save_results <- save_model_results(final_models$results, data_setup$cohort_name)
    if (save_results$success) {
      cat("[DEBUG] Results saved successfully\n")
      
      # Log summary
      cat("\n=== MODEL SAVING SUMMARY ===\n")
      cat(sprintf("Models saved: %d\n", save_results$saved_models))
      cat(sprintf("Comparison index: models/%s/model_comparison_index.csv\n", data_setup$cohort_name))
      cat("============================\n")
    } else {
      cat(sprintf("[WARNING] Failed to save results: %s\n", save_results$error))
    }
  } else {
    cat("[DEBUG] No successful models to save, skipping model saving step\n")
  }
  
  cat("[DEBUG] Model saving and indexing step completed\n")
  
}, error = function(e) {
  cat(sprintf("[ERROR] Model saving failed: %s\n", e$message))
  stop(e)
})

cat("=====================================\n")
cat("[DEBUG] ===============================================\n\n")
flush.console()

# Append session info snapshot for reproducibility
try({
  si_path <- here::here('logs', paste0('sessionInfo_step07_', format(Sys.time(), '%Y%m%d_%H%M%S'), '.txt'))
  dir.create(here::here('logs'), showWarnings = FALSE, recursive = TRUE)
  utils::capture.output(sessionInfo(), file = si_path)
  message('Saved sessionInfo to ', si_path)
}, silent = TRUE)
