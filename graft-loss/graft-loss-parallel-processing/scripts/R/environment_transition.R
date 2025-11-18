# ===================
# ENVIRONMENT TRANSITION SOLUTION
# ===================
# This file provides utilities for proper environment transitions in parallel pipeline steps

#' Get cohort-specific file path
#' @param base_path Base file path
#' @param cohort_name Cohort name (from DATASET_COHORT)
#' @return Cohort-specific file path
get_cohort_path <- function(base_path, cohort_name = NULL) {
  if (is.null(cohort_name)) {
    cohort_name <- Sys.getenv("DATASET_COHORT", unset = "unknown")
  }
  
  # Create cohort-specific subdirectory
  cohort_dir <- file.path(dirname(base_path), cohort_name)
  file_name <- basename(base_path)
  
  # Ensure directory exists
  dir.create(cohort_dir, showWarnings = FALSE, recursive = TRUE)
  
  return(file.path(cohort_dir, file_name))
}

#' Get cohort-specific log file path
#' @param step_name Step name (e.g., "04_data_setup")
#' @param cohort_name Cohort name (from DATASET_COHORT)
#' @return Cohort-specific log file path
get_cohort_log_path <- function(step_name, cohort_name = NULL) {
  if (is.null(cohort_name)) {
    cohort_name <- Sys.getenv("DATASET_COHORT", unset = "unknown")
  }
  
  # Create step-specific log directory
  log_dir <- file.path("logs", "steps", cohort_name)
  dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
  
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  log_file <- sprintf("%s_%s.log", step_name, timestamp)
  
  return(file.path(log_dir, log_file))
}

#' Set up environment variables for pipeline steps
#' @param cohort_name Cohort name
#' @param step_name Step name
#' @return List of environment variables
setup_step_environment <- function(cohort_name, step_name) {
  # Base environment variables
  env_vars <- list(
    DATASET_COHORT = cohort_name,
    STEP_NAME = step_name,
    TIMESTAMP = format(Sys.time(), "%Y%m%d_%H%M%S")
  )
  
  # Step-specific environment variables
  if (step_name %in% c("04_data_setup", "05_mc_cv_analysis", "06_parallel_model_fitting", 
                       "07_model_saving", "08_fallback_handling")) {
    # Model fitting steps need additional variables
    env_vars <- c(env_vars, list(
      MC_CV = "1",
      MC_TIMES = "20",
      USE_ENCODED = "0",
      XGB_FULL = "0",
      USE_CATBOOST = "0",
      FINAL_MODEL_WORKERS = "4",
      FINAL_MODEL_PLAN = "multisession",
      MC_WORKER_THREADS = "8",
      OMP_NUM_THREADS = "1",
      MKL_NUM_THREADS = "1",
      OPENBLAS_NUM_THREADS = "1",
      VECLIB_MAXIMUM_THREADS = "1",
      NUMEXPR_NUM_THREADS = "1"
    ))
  }
  
  return(env_vars)
}

#' Update pipeline steps to use cohort-specific paths
#' @param step_script Path to step script
#' @param cohort_name Cohort name
#' @return Updated step script content
update_step_for_cohort <- function(step_script, cohort_name) {
  if (!file.exists(step_script)) {
    stop(sprintf("Step script not found: %s", step_script))
  }
  
  # Read the step script
  content <- readLines(step_script)
  
  # Replace hardcoded paths with cohort-specific paths
  updated_content <- gsub(
    "here::here\\('model_data', '([^']+)'\\)",
    sprintf("get_cohort_path(here::here('model_data', '\\1'), '%s')", cohort_name),
    content
  )
  
  # Replace log file paths
  updated_content <- gsub(
    "logs/orch_bg_([^/]+)\\.log",
    sprintf("logs/steps/%s/\\1.log", cohort_name),
    updated_content
  )
  
  return(updated_content)
}

#' Create cohort-specific step script
#' @param step_script Original step script path
#' @param cohort_name Cohort name
#' @param temp_dir Temporary directory for modified scripts
#' @return Path to cohort-specific step script
create_cohort_step_script <- function(step_script, cohort_name, temp_dir = "temp_steps") {
  # Create temporary directory
  dir.create(temp_dir, showWarnings = FALSE, recursive = TRUE)
  
  # Generate cohort-specific script
  updated_content <- update_step_for_cohort(step_script, cohort_name)
  
  # Create cohort-specific script file
  step_name <- tools::file_path_sans_ext(basename(step_script))
  cohort_script <- file.path(temp_dir, sprintf("%s_%s.R", step_name, cohort_name))
  
  writeLines(updated_content, cohort_script)
  
  return(cohort_script)
}

#' Run pipeline steps with proper environment transitions
#' @param steps Vector of step script paths
#' @param cohort_name Cohort name
#' @param parallel Whether to run steps in parallel
#' @return List of results
run_pipeline_steps <- function(steps, cohort_name, parallel = FALSE) {
  # Set up environment variables
  env_vars <- setup_step_environment(cohort_name, "pipeline")
  
  # Create cohort-specific scripts
  cohort_steps <- sapply(steps, function(step) {
    create_cohort_step_script(step, cohort_name)
  })
  
  if (parallel) {
    # Run steps in parallel using furrr
    suppressPackageStartupMessages({
      library(furrr)
      library(future)
    })
    
    # Set up parallel plan
    future::plan(future::multisession, workers = min(length(steps), 4))
    
    results <- furrr::future_map(cohort_steps, function(step_script) {
      with_envvar(env_vars, {
        source(step_script, local = new.env(parent = globalenv()))
      })
    }, .options = furrr::furrr_options(seed = TRUE))
    
    # Clean up parallel plan
    future::plan(future::sequential)
  } else {
    # Run steps sequentially
    results <- lapply(cohort_steps, function(step_script) {
      with_envvar(env_vars, {
        source(step_script, local = new.env(parent = globalenv()))
      })
    })
  }
  
  # Clean up temporary scripts
  unlink(cohort_steps)
  
  return(results)
}
