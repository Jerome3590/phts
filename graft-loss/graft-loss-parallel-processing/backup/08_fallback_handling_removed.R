# ===================
# STEP 8: FALLBACK HANDLING
# ===================
# This step handles fallback scenarios when model fitting fails.

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
cat(sprintf("\n[08_fallback_handling.R] Starting fallback handling\n"))
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
cat("Log file path: ", log_file, "\n")

# Load modular components
source(here::here("scripts", "R", "fit_models_fallback.R"))
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
  
  # Check if there are any model fitting errors from step 06 (cohort-specific)
  error_file <- get_cohort_path(here::here('model_data', 'model_fitting_error.rds'), cohort_name)
  if (file.exists(error_file)) {
    error_info <- readRDS(error_file)
    cat(sprintf("[DEBUG] Found model fitting error from step 06: %s\n", error_info$error))
    
    # Load data setup for fallback (cohort-specific)
    data_setup_file <- get_cohort_path(here::here('model_data', 'data_setup.rds'), cohort_name)
    if (file.exists(data_setup_file)) {
      data_setup <- readRDS(data_setup_file)
      cat("[DEBUG] Loaded data setup for fallback\n")
      
      # Try fallback fitting
      cat("[DEBUG] Attempting fallback fitting...\n")
      fallback_result <- comprehensive_fallback(error_info$error, data_setup$final_data, data_setup$model_vars)
      
      if (fallback_result$success) {
        cat("[DEBUG] Fallback fitting successful\n")
        
        # Save fallback results
        save_results <- save_model_results(fallback_result$results, data_setup$cohort_name)
        if (save_results$success) {
          cat("[DEBUG] Fallback results saved successfully\n")
          
          # Log summary
          cat("\n=== FALLBACK SUMMARY ===\n")
          cat(sprintf("Fallback strategy: %s\n", fallback_result$message))
          cat(sprintf("Models saved: %d\n", save_results$saved_models))
          cat("=======================\n")
        } else {
          cat(sprintf("[WARNING] Failed to save fallback results: %s\n", save_results$error))
        }
      } else {
        cat(sprintf("[ERROR] All fallback strategies failed: %s\n", fallback_result$error))
      }
    } else {
      cat("[ERROR] data_setup.rds not found for fallback\n")
    }
  } else {
    cat("[DEBUG] No model fitting errors found, fallback step not needed\n")
    
    # Check if models were successfully created in step 07 (cohort-specific)
    models_file <- get_cohort_path(here::here('model_data', 'final_models.rds'), cohort_name)
    if (file.exists(models_file)) {
      final_models <- readRDS(models_file)
      if (final_models$success) {
        cat("[DEBUG] Models were successfully fitted in step 06, no fallback needed\n")
      } else {
        cat("[DEBUG] Models failed in step 06 but no error file found\n")
      }
    } else {
      cat("[DEBUG] No model results found from step 06\n")
    }
  }
  
  cat("[DEBUG] Fallback handling step completed\n")
  
}, error = function(e) {
  cat(sprintf("[ERROR] Fallback handling failed: %s\n", e$message))
  stop(e)
})

cat("=====================================\n")
cat("[DEBUG] ===============================================\n\n")
flush.console()

# Append session info snapshot for reproducibility
try({
  si_path <- here::here('logs', paste0('sessionInfo_step08_', format(Sys.time(), '%Y%m%d_%H%M%S'), '.txt'))
  dir.create(here::here('logs'), showWarnings = FALSE, recursive = TRUE)
  utils::capture.output(sessionInfo(), file = si_path)
}, silent = TRUE)
