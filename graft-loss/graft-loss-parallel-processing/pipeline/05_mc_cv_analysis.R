# ===================
# STEP 5: MC-CV ANALYSIS
# ===================
# This step handles Monte Carlo Cross-Validation analysis.

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
cat(sprintf("\n[05_mc_cv_analysis.R] Starting MC-CV analysis\n"))
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
cat("Log file path: ", log_file, "\n")

# Load modular components
source(here::here("scripts", "R", "mc_cv_analysis.R"))
source(here::here("scripts", "R", "environment_transition.R"))

# Load the run_mc function for MC-CV analysis
if (file.exists(here::here("scripts", "R", "run_mc.R"))) {
  source(here::here("scripts", "R", "run_mc.R"))
}

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
  
  # Run MC-CV analysis if enabled
  if (data_setup$mc_cv) {
    cat("[DEBUG] Running MC-CV analysis...\n")
    mc_cv_results <- run_mc_cv_analysis(data_setup)
    if (mc_cv_results$success) {
      cat("[DEBUG] MC-CV analysis completed successfully\n")
      
      # Save MC-CV results for next steps (cohort-specific)
      mc_cv_file <- get_cohort_path(here::here('model_data', 'mc_cv_results.rds'), cohort_name)
      saveRDS(mc_cv_results, mc_cv_file)
      cat(sprintf("[DEBUG] MC-CV results saved to: %s\n", mc_cv_file))
    } else {
      cat(sprintf("[WARNING] MC-CV analysis failed: %s\n", mc_cv_results$error))
    }
  } else {
    cat("[DEBUG] Skipping MC-CV analysis (mc_cv = FALSE)\n")
    
    # Create empty MC-CV results for consistency
    mc_cv_results <- list(
      success = TRUE,
      message = "MC-CV skipped",
      testing_rows = data_setup$testing_rows,
      use_global_xgb = FALSE
    )
    
    # Save empty MC-CV results for next steps (cohort-specific)
    mc_cv_file <- get_cohort_path(here::here('model_data', 'mc_cv_results.rds'), cohort_name)
    saveRDS(mc_cv_results, mc_cv_file)
    cat(sprintf("[DEBUG] Empty MC-CV results saved to: %s\n", mc_cv_file))
  }
  
  cat("[DEBUG] MC-CV step completed successfully\n")
  
}, error = function(e) {
  cat(sprintf("[ERROR] MC-CV analysis failed: %s\n", e$message))
  stop(e)
})

cat("=====================================\n")
cat("[DEBUG] ===============================================\n\n")
flush.console()

# Append session info snapshot for reproducibility
try({
  si_path <- here::here('logs', paste0('sessionInfo_step05_', format(Sys.time(), '%Y%m%d_%H%M%S'), '.txt'))
  dir.create(here::here('logs'), showWarnings = FALSE, recursive = TRUE)
  utils::capture.output(sessionInfo(), file = si_path)
  message('Saved sessionInfo to ', si_path)
}, silent = TRUE)
