# ===================
# STEP 6: PARALLEL MODEL FITTING
# ===================
# This step handles parallel fitting of all models (ORSF, CatBoost, XGB, CPH).

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
cat(sprintf("\n[06_parallel_model_fitting.R] Starting parallel model fitting\n"))
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
  
  # Load data setup from previous step (cohort-specific)
  data_setup_file <- get_cohort_path(here::here('model_data', 'data_setup.rds'), cohort_name)
  if (file.exists(data_setup_file)) {
    data_setup <- readRDS(data_setup_file)
    cat("[DEBUG] Loaded data setup from previous step\n")
  } else {
    stop("data_setup.rds not found. Please run step 04 first.")
  }
  
  # Fit final models
  cat("[DEBUG] Starting final model fitting...\n")
  final_models <- fit_final_models_parallel(data_setup)
  
  if (final_models$success) {
    cat("[DEBUG] All models fitted successfully\n")
    
    # Save model results for next steps (cohort-specific)
    models_file <- get_cohort_path(here::here('model_data', 'final_models.rds'), cohort_name)
    saveRDS(final_models, models_file)
    cat(sprintf("[DEBUG] Model results saved to: %s\n", models_file))
    
    # Log summary
    cat("\n=== MODEL FITTING SUMMARY ===\n")
    for (model_name in names(final_models$results)) {
      result <- final_models$results[[model_name]]
      if (result$success) {
        cat(sprintf("✓ %s: %.2f MB, %.2f mins\n", 
                   result$model_name, result$model_size_mb, result$elapsed_mins))
      } else {
        cat(sprintf("✗ %s: Failed\n", result$model_name))
      }
    }
    cat("=============================\n")
  } else {
    cat(sprintf("[ERROR] Model fitting failed: %s\n", final_models$error))
    
    # Save error information for fallback step (cohort-specific)
    error_file <- get_cohort_path(here::here('model_data', 'model_fitting_error.rds'), cohort_name)
    saveRDS(list(error = final_models$error, timestamp = Sys.time()), error_file)
    cat(sprintf("[DEBUG] Error information saved to: %s\n", error_file))
  }
  
  cat("[DEBUG] Parallel model fitting step completed\n")
  
}, error = function(e) {
  cat(sprintf("[ERROR] Parallel model fitting failed: %s\n", e$message))
  
  # Save error information for fallback step (cohort-specific)
  error_file <- get_cohort_path(here::here('model_data', 'model_fitting_error.rds'), cohort_name)
  saveRDS(list(error = e$message, timestamp = Sys.time()), error_file)
  cat(sprintf("[DEBUG] Error information saved to: %s\n", error_file))
  
  stop(e)
})

cat("=====================================\n")
cat("[DEBUG] ===============================================\n\n")
flush.console()

# Append session info snapshot for reproducibility
try({
  si_path <- here::here('logs', paste0('sessionInfo_step06_', format(Sys.time(), '%Y%m%d_%H%M%S'), '.txt'))
  dir.create(here::here('logs'), showWarnings = FALSE, recursive = TRUE)
  utils::capture.output(sessionInfo(), file = si_path)
  message('Saved sessionInfo to ', si_path)
}, silent = TRUE)
