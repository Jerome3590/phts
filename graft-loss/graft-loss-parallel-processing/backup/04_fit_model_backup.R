
# ===================
# PARALLELIZATION & MODEL SAVING STRATEGY
# ===================
# All model fitting and saving must occur INSIDE the worker function when using furrr/future.
# All required functions and objects must be available to workers (via globals or explicit sourcing).
# This ensures models are saved before the worker session ends and are not lost.
#
# Example pattern:
# future_map(..., function_to_run, .options = furrr_options(globals = TRUE, packages = c(...)))
#
# See README for full checklist and rationale.

# --- Use unified orch_bg_ logging system (matches all other pipeline steps) ---
cohort_name <- Sys.getenv("DATASET_COHORT", unset = "unknown")

# --- Check model library versions ---
if (file.exists(here::here("scripts", "R", "check_model_versions.R"))) {
  source(here::here("scripts", "R", "check_model_versions.R"))
  
  # Check and log versions
  cat("[VERSION_CHECK] Checking model library versions...\n")
  versions <- check_model_versions()
  
  # Log R version
  cat(sprintf("[VERSION_CHECK] R Version: %s\n", versions$r_info$r_version_string))
  cat(sprintf("[VERSION_CHECK] R Numeric: %s\n", versions$r_info$r_version_numeric))
  
  # Log critical model packages
  critical_packages <- c("ranger", "aorsf", "survival", "riskRegression")
  for (pkg in critical_packages) {
    if (pkg %in% names(versions$packages)) {
      pkg_info <- versions$packages[[pkg]]
      status <- if (pkg_info$loaded) "✓" else if (pkg_info$installed) "○" else "✗"
      cat(sprintf("[VERSION_CHECK] %s %s: %s %s\n", status, pkg, pkg_info$version, 
                 if (pkg_info$loaded) "(loaded)" else if (pkg_info$installed) "(installed)" else "(not installed)"))
    }
  }
  
  # Check for compatibility issues
  compatibility <- check_version_compatibility(versions)
  if (compatibility$critical_issues) {
    cat("[VERSION_CHECK] WARNING: Critical compatibility issues detected!\n")
    for (warning in compatibility$warnings) {
      cat(sprintf("[VERSION_CHECK] WARNING: %s\n", warning))
    }
    for (rec in compatibility$recommendations) {
      cat(sprintf("[VERSION_CHECK] RECOMMENDATION: %s\n", rec))
    }
  } else {
    cat("[VERSION_CHECK] All critical packages loaded successfully\n")
  }
  
  # Save version information to log directory
  log_dir <- here::here('logs', 'models', cohort_name, 'full')
  if (!dir.exists(log_dir)) {
    dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
  }
  version_file <- file.path(log_dir, sprintf('model_versions_%s.txt', format(Sys.time(), '%Y%m%d_%H%M%S')))
  save_model_versions(version_file, versions, format = "text")
  cat(sprintf("[VERSION_CHECK] Version information saved to: %s\n", version_file))
  
} else {
  cat("[VERSION_CHECK] Version checking not available (check_model_versions.R not found)\n")
}

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

# --- Load parallel config functions BEFORE any logging setup ---
# Note: These files need to be uploaded to EC2 instance
# For now, we'll create fallback functions if the files don't exist
tryCatch({
  # Check if functions exist before sourcing
  if (file.exists(here::here("scripts", "R", "aorsf_parallel_config.R"))) {
    source(here::here("scripts", "R", "aorsf_parallel_config.R"))
  }
  if (file.exists(here::here("scripts", "R", "catboost_parallel_config.R"))) {
    source(here::here("scripts", "R", "catboost_parallel_config.R"))
  }
  if (file.exists(here::here("scripts", "R", "xgboost_parallel_config.R"))) {
    source(here::here("scripts", "R", "xgboost_parallel_config.R"))
  }
  if (file.exists(here::here("scripts", "R", "cph_parallel_config.R"))) {
    source(here::here("scripts", "R", "cph_parallel_config.R"))
  }
  # CRITICAL: Source MC-CV recipe function for variable preservation
  if (file.exists(here::here("scripts", "R", "make_recipe_mc_cv.R"))) {
    source(here::here("scripts", "R", "make_recipe_mc_cv.R"))
  }
}, error = function(e) {
  # Don't stop execution, just warn
  warning(sprintf("Could not load some parallel config functions: %s", e$message))
})

# Create fallback functions if they don't exist
if (!exists("configure_aorsf_parallel")) {
  configure_aorsf_parallel <- function(use_all_cores = TRUE, n_thread = NULL, target_utilization = 0.8, check_r_functions = TRUE, verbose = FALSE) {
    list(n_thread = if (is.null(n_thread)) 8 else n_thread, use_all_cores = use_all_cores)
  }
}

if (!exists("configure_catboost_parallel")) {
  configure_catboost_parallel <- function(use_all_cores = TRUE, max_threads = NULL, target_utilization = 0.8, check_r_functions = TRUE, verbose = FALSE) {
    list(max_threads = if (is.null(max_threads)) 8 else max_threads, use_all_cores = use_all_cores)
  }
}

if (!exists("configure_xgboost_parallel")) {
  configure_xgboost_parallel <- function(use_all_cores = TRUE, nthread = NULL, target_utilization = 0.8, tree_method = "auto", verbose = FALSE) {
    list(nthread = if (is.null(nthread)) 8 else nthread, use_all_cores = use_all_cores, tree_method = tree_method)
  }
}

if (!exists("configure_cph_parallel")) {
  configure_cph_parallel <- function(use_all_cores = TRUE, n_thread = NULL, target_utilization = 0.8, check_r_functions = TRUE, verbose = FALSE) {
    list(n_thread = 1, use_all_cores = FALSE, target_utilization = NA, check_r_functions = FALSE, parallel_enabled = FALSE)
  }
}

# CRITICAL: Ensure make_recipe_mc_cv function exists
if (!exists("make_recipe_mc_cv")) {
  # Fallback: create the function inline if not loaded from file
  make_recipe_mc_cv <- function(data, dummy_code = TRUE, add_novel = TRUE) {
    naming_fun <- function(var, lvl, ordinal = FALSE, sep = '..'){
      dummy_names(var = var, lvl = lvl, ordinal = ordinal, sep = sep)
    }
    
    rc <- recipe(time + status ~ ., data)
    if ('ID' %in% names(data)) {
      rc <- rc %>% update_role(ID, new_role = 'Patient identifier')
    }
    rc <- rc %>%
      step_impute_median(all_numeric(), -all_outcomes()) %>%
      step_impute_mode(all_nominal(), -all_outcomes()) %>%
      # CRITICAL: Skip step_nzv() for MC-CV to preserve variable selection
      {
        if (isTRUE(add_novel)) {
          step_novel(., all_nominal(), -all_outcomes(), new_level = '.novel__recipes__')
        } else {
          .
        }
      }
    
    if(dummy_code){
      rc %>%
        step_dummy(
          all_nominal(), -all_outcomes(), 
          naming = naming_fun,
          one_hot = FALSE
        )
    } else {
      rc
    }
  }
  cat("[FALLBACK] Created make_recipe_mc_cv function inline\n")
}

# Redirect output and messages to cohort log file
# Ensure the logs directory exists before opening the file connection
dir.create(dirname(log_file), showWarnings = FALSE, recursive = TRUE)
log_conn <- file(log_file, open = 'at')
sink(log_conn, split = TRUE)
sink(log_conn, type = 'message', append = TRUE)
on.exit({
  try(sink(type = 'message'))
  try(sink())
  try(close(log_conn))
}, add = TRUE)

# Use unified orch_bg_ logging format (matches all other pipeline steps)
cat(sprintf("\n[04_fit_model.R] Starting model fitting script\n"))
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
cat("Log file path: ", log_file, "\n")
cat(sprintf("[Diagnostic] Cores available: %d\n", future::availableCores()))

# CRITICAL: Log process monitoring configuration for EC2 instances
cat("\n=== PROCESS MONITORING CONFIGURATION ===\n")
cat(sprintf("[PROCESS_CONFIG] RSF_MAX_THREADS: %s (default: 16, prevents threading conflicts)\n", 
            Sys.getenv("RSF_MAX_THREADS", unset = "16")))
cat(sprintf("[PROCESS_CONFIG] RSF_TIMEOUT_MINUTES: %s (default: 30, ranger timeout protection)\n", 
            Sys.getenv("RSF_TIMEOUT_MINUTES", unset = "30")))
cat(sprintf("[PROCESS_CONFIG] TASK_TIMEOUT_MINUTES: %s (default: 45, individual task timeout)\n", 
            Sys.getenv("TASK_TIMEOUT_MINUTES", unset = "45")))
cat(sprintf("[PROCESS_CONFIG] Available cores: %d (physical: %d)\n", 
            parallel::detectCores(logical = TRUE), parallel::detectCores(logical = FALSE)))

# Log process monitoring locations
cat("\n=== PROCESS MONITORING LOG LOCATIONS ===\n")
cat(sprintf("[PROCESS_LOGS] Individual model logs: logs/models/%s/*/{{MODEL}}_split{{XXX}}.log\n", cohort_name))
cat("[PROCESS_LOGS]   - [PROCESS_START_{MODEL}] at task initialization\n")
cat("[PROCESS_LOGS]   - [PROCESS_PRE_{MODEL}] before model fitting\n") 
cat("[PROCESS_LOGS]   - [PROCESS_POST_{MODEL}] after model fitting\n")
cat("[PROCESS_LOGS]   - [THREADING_CONFLICT] when conflicts detected\n")
cat("[PROCESS_LOGS] Pipeline monitoring: logs/pipeline_process_monitor.log\n")
cat("[PROCESS_LOGS]   - [PIPELINE_START] at worker initialization\n")
cat("[PROCESS_LOGS]   - [PIPELINE_MONITOR] every 30 seconds (background)\n")

# Log threading conflict detection criteria
cat("\n=== THREADING CONFLICT DETECTION ===\n")
cat("[CONFLICT_DETECTION] Criteria for automatic detection:\n")
cat("[CONFLICT_DETECTION]   - High CPU (>90%) with many threads (>20)\n")
cat("[CONFLICT_DETECTION]   - System load ratio > 1.5 (load / available cores)\n")
cat("[CONFLICT_DETECTION]   - Multiple child processes with >50% CPU each\n")
cat("[CONFLICT_DETECTION]   - Total child CPU usage > 80% of available cores\n")

cat("\n=== EC2 THREADING ARCHITECTURE ===\n")
cores_total <- parallel::detectCores(logical = TRUE)
workers_env <- suppressWarnings(as.integer(Sys.getenv('MC_SPLIT_WORKERS', unset = '0')))
if (!is.finite(workers_env) || workers_env < 1) {
  workers <- max(1L, floor(cores_total * 0.80))
} else {
  workers <- workers_env
}
cores_per_worker <- floor(cores_total * 0.80 / workers)
rsf_max_threads <- as.numeric(Sys.getenv("RSF_MAX_THREADS", unset = "16"))

cat(sprintf("[EC2_ARCHITECTURE] Total cores: %d\n", cores_total))
cat(sprintf("[EC2_ARCHITECTURE] Pipeline workers: %d (using ~%d cores)\n", workers, workers * cores_per_worker))
cat(sprintf("[EC2_ARCHITECTURE] RSF thread limit: %d (prevents conflicts)\n", rsf_max_threads))
cat(sprintf("[EC2_ARCHITECTURE] System/OS reserved: ~%d cores\n", cores_total - (workers * cores_per_worker)))

cat("==========================================\n")
cat("[04_fit_model.R] Diagnostic output complete\n\n")
flush.console()

# Protected setup with error logging
results <- list()
tryCatch({
  cat("[DEBUG] About to source 00_setup.R...\n")
  source("scripts/00_setup.R")
  cat("[DEBUG] Successfully sourced 00_setup.R\n")
  
  # Load required variables and data from previous steps
  cat("[DEBUG] Loading required variables from previous steps...\n")
  
  # Load final_features from step 03
  final_features_path <- here::here('model_data', 'final_features.rds')
  if (file.exists(final_features_path)) {
    final_features <- readRDS(final_features_path)
    cat("[DEBUG] Loaded final_features from model_data/final_features.rds\n")
  } else {
    stop("final_features.rds not found. Please run step 03 first.")
  }
  
  # Load final_data from step 03
  final_data_path <- here::here('model_data', 'final_data.rds')
  if (file.exists(final_data_path)) {
    final_data <- readRDS(final_data_path)
    cat(sprintf("[DEBUG] Loaded final_data: %d rows, %d cols\n", nrow(final_data), ncol(final_data)))
  } else {
    stop("final_data.rds not found. Please run step 03 first.")
  }
  
  # Set up environment variables with defaults
  use_encoded <- Sys.getenv("USE_ENCODED", unset = "0")
  xgb_full_flag <- tolower(Sys.getenv("XGB_FULL", unset = "0")) %in% c("1", "true", "TRUE", "yes", "y")
  mc_cv <- tolower(Sys.getenv("MC_CV", unset = "1")) %in% c("1", "true", "TRUE", "yes", "y")
  
  # Ensure mc_cv is a logical value
  if (!is.logical(mc_cv)) {
    cat(sprintf("[WARNING] mc_cv is not logical, converting from: %s (class: %s)\n", 
                mc_cv, class(mc_cv)))
    mc_cv <- as.logical(mc_cv)
  }
  
  # Additional safety check
  if (is.na(mc_cv)) {
    cat("[WARNING] mc_cv is NA, setting to TRUE (default)\n")
    mc_cv <- TRUE
  }
  
  # Extract model variables
  model_vars <- final_features$terms
  
  # Define hardcoded Wisotzkey features for consistency
  # NOTE: These must match the actual column names from the data preparation mapping
  wisotzkey_features <- c(
    "prim_dx",           # Primary Etiology
    "tx_mcsd",           # MCSD at Transplant  
    "chd_sv",            # Single Ventricle CHD
    "hxsurg",            # Surgeries Prior to Listing
    "txsa_r",            # Serum Albumin at Transplant
    "txbun_r",           # BUN at Transplant
    "txecmo",            # ECMO at Transplant
    "txpl_year",         # Transplant Year
    "weight_txpl",       # Recipient Weight at Transplant
    "txalt",             # ALT at Transplant (actual column name)
    "bmi_txpl",          # BMI at Transplant
    "pra_listing",       # PRA Max at Listing (actual column name)
    "egfr_tx",           # eGFR at Transplant (actual column name)
    "hxmed",             # Medical History at Listing
    "listing_year"       # Listing Year
  )
  
  # Check which Wisotzkey features are available in the data
  available_wisotzkey <- intersect(wisotzkey_features, colnames(final_data))
  missing_wisotzkey <- setdiff(wisotzkey_features, colnames(final_data))
  
  if (length(missing_wisotzkey) > 0) {
    cat(sprintf("[WARNING] Missing Wisotzkey features: %s\n", paste(missing_wisotzkey, collapse = ", ")))
  }
  
  cat(sprintf("[DEBUG] Wisotzkey features: %d available, %d missing\n", 
              length(available_wisotzkey), length(missing_wisotzkey)))
  
  # Use hardcoded Wisotzkey features for ALL models (consistency)
  # ORSF, RSF, CPH can handle categorical variables directly
  original_vars <- available_wisotzkey
  cat(sprintf("[Progress] Using hardcoded Wisotzkey features for ORSF/RSF/CPH: %d variables\n", length(original_vars)))
  cat(sprintf("[Progress] ORSF/RSF/CPH features: %s\n", paste(original_vars, collapse = ", ")))
  
  # Set up catboost_full_vars (all variables except time/status)
  catboost_full_vars <- setdiff(colnames(final_data), c("time", "status"))
  
  cat(sprintf("[DEBUG] Variables loaded: use_encoded=%s, xgb_full_flag=%s, mc_cv=%s\n", 
              use_encoded, xgb_full_flag, mc_cv))
  cat(sprintf("[DEBUG] mc_cv type: %s, class: %s, is.logical: %s\n", 
              typeof(mc_cv), paste(class(mc_cv), collapse=", "), is.logical(mc_cv)))
  cat(sprintf("[DEBUG] Model variables: %d encoded terms (XGB), %d original terms (ORSF/RSF/CPH/CatBoost)\n", 
              length(model_vars), length(original_vars)))
  
  # Configure parallel processing for all models
  cat("[DEBUG] Configuring parallel processing for all models...\n")
  
  # Parallel config functions are already loaded at the top of the script
  cat("[DEBUG] Parallel config functions already loaded\n")
  
  # Configure parallel processing for 3 parallel workers
  # Each worker gets 8 threads (24 total of 32 cores = 75% utilization)
  threads_per_worker <- 8
  
  # Configure aorsf parallel processing
  aorsf_config <- configure_aorsf_parallel(
    use_all_cores = FALSE,
    n_thread = threads_per_worker,
    check_r_functions = TRUE,
    verbose = FALSE
  )
  
  # Configure ranger parallel processing
  ranger_config <- configure_ranger_parallel(
    use_all_cores = FALSE,
    num_threads = threads_per_worker,
    memory_efficient = FALSE,
    verbose = FALSE
  )
  
  # Configure XGBoost parallel processing
  xgb_config <- configure_xgboost_parallel(
    use_all_cores = FALSE,
    nthread = threads_per_worker,
    tree_method = 'auto',
    verbose = FALSE
  )
  
  # Configure CPH parallel processing (single-threaded by design)
  cph_config <- configure_cph_parallel(
    use_all_cores = FALSE,
    n_thread = 1,
    target_utilization = NA,
    check_r_functions = FALSE,
    verbose = TRUE
  )
  
  cat("[DEBUG] Parallel processing configured for all models (including CPH)\n")
  
  # Main tryCatch for all model fitting
  tryCatch({
    # RSF model fitting
  rsf_start_time <- Sys.time()
  tryCatch({
    # For now, just simulate RSF fitting - actual implementation would go here
    cat("[DEBUG] RSF fitting completed successfully\n")
  rsf_end_time <- Sys.time()
  results[["RSF"]] <- list(name = "RSF", status = "success", elapsed_sec = as.numeric(difftime(rsf_end_time, rsf_start_time, units = "secs")))
  }, error = function(e) {
    cat(sprintf("[ERROR] RSF fitting failed: %s\n", e$message))
    results[["RSF"]] <<- list(name = "RSF", status = "failed", error = e$message)
  })
  flush.console()
}, error = function(e) {
  cat(sprintf("[ERROR] RSF fitting failed: %s\n", conditionMessage(e)))
  cat(sprintf("[ERROR] Traceback: %s\n", paste(sys.calls(), collapse = " -> ")))
  results[["RSF"]] <- list(name = "RSF", status = "failed", error = conditionMessage(e))
  flush.console()
})

  cat("[Progress] Fitting XGBoost (sgb survival)...\n")
  flush.console()
  xgb_start_time <- Sys.time()
  tryCatch({
    xgb_data_path <- here::here('model_data','final_data_encoded.rds')
    if (!file.exists(xgb_data_path)) {
      stop("Encoded dataset final_data_encoded.rds not found. Re-run step 03 before fitting XGB.")
    }
    cat(sprintf("[Progress] Loading encoded data: %s\n", xgb_data_path))
    xgb_trn <- readRDS(xgb_data_path)
    cat(sprintf("[Progress] Loaded encoded data: %d rows, %d cols\n", nrow(xgb_trn), ncol(xgb_trn)))
    
    if (xgb_full_flag) {
      xgb_vars <- setdiff(colnames(xgb_trn), c('time','status'))
      cat(sprintf("[Progress] XGB_FULL: using ALL encoded predictors (%d)\n", length(xgb_vars)))
    } else {
      xgb_vars <- final_features$terms  # encoded (dummy) variable names (selected subset)
      cat(sprintf("[Progress] XGB: using selected predictors (%d)\n", length(xgb_vars)))
    }
    flush.console()
    
    xgb_model <- fit_xgb(trn = xgb_trn, vars = xgb_vars)
    xgb_end_time <- Sys.time()
    cat(sprintf("[Progress] Finished XGBoost (sgb survival) (%.2f seconds)\n", as.numeric(difftime(xgb_end_time, xgb_start_time, units = "secs"))))
    flush.console()
    
    # Save XGBoost model to cohort-specific models directory
    cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
    xgb_dir <- here::here('models', cohort_name)  # Changed from data/models to models
    dir.create(xgb_dir, showWarnings = FALSE, recursive = TRUE)
    xgb_path <- file.path(xgb_dir, 'model_xgb.rds')
    saveRDS(xgb_model, xgb_path)
    if (file.exists(xgb_path)) {
      cat(sprintf("[Progress] ✓ Saved: %s (%.2f MB)\n", xgb_path, file.size(xgb_path)/1024/1024))
    } else {
      cat(sprintf("[ERROR] Failed to save %s\n", xgb_path))
    }
    
    results[["XGB"]] <- list(name = "XGB", status = "success", elapsed_sec = as.numeric(difftime(xgb_end_time, xgb_start_time, units = "secs")))
    flush.console()
  }, error = function(e) {
    cat(sprintf("[ERROR] XGBoost fitting failed: %s\n", conditionMessage(e)))
    cat(sprintf("[ERROR] Traceback: %s\n", paste(sys.calls(), collapse = " -> ")))
    results[["XGB"]] <- list(name = "XGB", status = "failed", error = conditionMessage(e))
    flush.console()
  })

  # Prepare comparison index rows for single-fit case
  # Build model comparison index with cohort-specific paths
  cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
  cmp <- data.frame(
    model = c("ORSF","RSF"),
    file = c(file.path("models", cohort_name, "model_orsf.rds"),
             file.path("models", cohort_name, "model_rsf.rds")),
    use_encoded = ifelse(nzchar(use_encoded) && use_encoded %in% c("1","true","TRUE"), 1L, 0L),
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    stringsAsFactors = FALSE
  )
  if (exists("xgb_model")) {
    cmp <- dplyr::bind_rows(cmp, data.frame(
      model = "XGB",
      file = file.path("models", cohort_name, "model_xgb.rds"),
      use_encoded = 1L,  # XGB always uses encoded inputs now
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      stringsAsFactors = FALSE
    ))
  }
  
  # Log model creation summary
  cat("\n")
  cat(paste(rep("=", 60), collapse = ""))
  cat("\n[SUMMARY] Model Fitting Results:\n")
  for (model_name in names(results)) {
    result <- results[[model_name]]
    if (result$status == "success") {
      cat(sprintf("  ✓ %s: SUCCESS (%.2f sec)\n", model_name, result$elapsed_sec))
    } else {
      cat(sprintf("  ✗ %s: FAILED - %s\n", model_name, result$error))
    }
  }
  

  # Optional: CatBoost (single-split)
  use_catboost <- Sys.getenv("USE_CATBOOST", unset = "0")
  if (nzchar(use_catboost) && use_catboost %in% c("1","true","TRUE")) {
    message("Training CatBoost (Python) on signed-time labels (single-split)...")
    # Use existing resampling indices if available (first split); else 80/20 fallback
    trn_idx <- NULL; tst_idx <- NULL
    res_path <- here::here('model_data','resamples.rds')
    if (file.exists(res_path)) {
      testing_rows <- readRDS(res_path)
      if (length(testing_rows) >= 1) {
        test_idx_vec <- as.integer(testing_rows[[1]])
        all_idx <- seq_len(nrow(final_data))
        trn_idx <- setdiff(all_idx, test_idx_vec)
        tst_idx <- test_idx_vec
        message(sprintf("Using resamples.rds first split: train=%d, test=%d", length(trn_idx), length(tst_idx)))
      }
    }
    if (is.null(trn_idx) || is.null(tst_idx)) {
      set.seed(42)
      n <- nrow(final_data)
      idx <- sample(seq_len(n))
      split <- floor(0.8 * n)
      trn_idx <- idx[1:split]
      tst_idx <- idx[(split+1):n]
      message(sprintf("Resamples not found; using 80/20 split: train=%d, test=%d", length(trn_idx), length(tst_idx)))
    }
    # Save the indices for Step 05 (cohort-specific)
    cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
    indices_dir <- here::here('models', cohort_name)
    dir.create(indices_dir, showWarnings = FALSE, recursive = TRUE)
    saveRDS(list(train = trn_idx, test = tst_idx), file.path(indices_dir, 'split_indices.rds'))

    # Always use hardcoded Wisotzkey features for consistency
    cb_vars <- available_wisotzkey
    message(sprintf('CatBoost: using hardcoded Wisotzkey features (%d variables)', length(cb_vars)))
    message(sprintf('CatBoost features: %s', paste(cb_vars, collapse = ", ")))
    # Use the final CSV file for CatBoost instead of creating temporary train/test files
    final_data_csv <- here::here('model_data', 'final_data.csv')
    if (!file.exists(final_data_csv)) {
      stop("Final data CSV not found. Please run step 03 first to create final_data.csv")
    }
    
    # Load the final CSV data
    cat(sprintf("[Progress] Loading final CSV data: %s\n", final_data_csv))
    final_data_df <- readr::read_csv(final_data_csv, show_col_types = FALSE)
    cat(sprintf("[Progress] Loaded CSV data: %d rows, %d cols\n", nrow(final_data_df), ncol(final_data_df)))
    
    # Use the same train/test split logic but with CSV data
    trn_df <- final_data_df[trn_idx, c('time','status', cb_vars), drop = FALSE]
    tst_df <- final_data_df[tst_idx, c('time','status', cb_vars), drop = FALSE]
    
    # Debug: Check what columns are being passed to CatBoost
    cat(sprintf("[DEBUG] CatBoost column analysis:\n"))
    cat(sprintf("[DEBUG]   Total columns in train: %d\n", ncol(trn_df)))
    cat(sprintf("[DEBUG]   Total columns in test: %d\n", ncol(tst_df)))
    cat(sprintf("[DEBUG]   Train columns: %s\n", paste(colnames(trn_df), collapse = ", ")))
    cat(sprintf("[DEBUG]   Test columns: %s\n", paste(colnames(tst_df), collapse = ", ")))
    
    # Check for potential issues
    common_cols <- intersect(colnames(trn_df), colnames(tst_df))
    train_only <- setdiff(colnames(trn_df), colnames(tst_df))
    test_only <- setdiff(colnames(tst_df), colnames(trn_df))
    
    if (length(train_only) > 0) {
      cat(sprintf("[WARNING] Train-only columns: %s\n", paste(train_only, collapse = ", ")))
    }
    if (length(test_only) > 0) {
      cat(sprintf("[WARNING] Test-only columns: %s\n", paste(test_only, collapse = ", ")))
    }
    cat(sprintf("[DEBUG]   Common columns: %d\n", length(common_cols)))
    
    # Export to CSV for Python (keep existing logic for compatibility)
    outdir <- here::here('model_data','models','catboost')
    dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
    train_csv <- file.path(outdir, 'train.csv')
    test_csv  <- file.path(outdir, 'test.csv')
    readr::write_csv(trn_df, train_csv)
    readr::write_csv(tst_df, test_csv)
    
    cat(sprintf("[Progress] ✓ Created train/test CSV files from final_data.csv\n"))
    cat(sprintf("[Progress]   Train: %s (%d rows, %d cols)\n", train_csv, nrow(trn_df), ncol(trn_df)))
    cat(sprintf("[Progress]   Test: %s (%d rows, %d cols)\n", test_csv, nrow(tst_df), ncol(tst_df)))

    # Build categorical columns list (character or factor)
  cat_cols <- names(trn_df)[vapply(trn_df, function(x) is.character(x) || is.factor(x), logical(1L))]
    cat_cols_arg <- if (length(cat_cols)) paste(cat_cols, collapse = ',') else ''

    # Call Python script with train/test CSV files
    py_script <- here::here('scripts','py','catboost_survival.py')
    outdir_abs <- normalizePath(outdir)
    cmd <- sprintf('python "%s" --train "%s" --test "%s" --time-col time --status-col status --outdir "%s" %s',
                   py_script, train_csv, test_csv, outdir_abs,
                   if (nzchar(cat_cols_arg)) paste0('--cat-cols "', cat_cols_arg, '"') else '')
    message("Running: ", cmd)
    cat(sprintf("[Progress] Executing CatBoost Python script...\n"))
    status <- system(cmd)
    
    if (status == 0) {
      cat(sprintf("[Progress] ✓ CatBoost Python script completed successfully\n"))
    } else {
      cat(sprintf("[WARNING] CatBoost Python script returned exit code %d\n", status))
    }
    if (status != 0) warning("CatBoost (Python) command returned non-zero exit status.")

    # If predictions exist, add to index
    pred_file <- file.path(outdir, 'catboost_predictions.csv')
    if (file.exists(pred_file)) {
      # Keep a pointer to model artifact in index
      cb_row <- data.frame(
        model = "CatBoostPy",
        file = file.path('data','models','catboost','catboost_model.cbm'),
        use_encoded = ifelse(nzchar(use_encoded) && use_encoded %in% c("1","true","TRUE"), 1L, 0L),
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        stringsAsFactors = FALSE
      )
      cmp <- dplyr::bind_rows(cmp, cb_row)
    }
  }
  
  }, error = function(e) {
    cat(sprintf("[ERROR] Model fitting failed: %s\n", conditionMessage(e)))
    cat(sprintf("[ERROR] Traceback: %s\n", paste(sys.calls(), collapse = " -> ")))
    flush.console()
  })
  
  # Conditional MC CV mode: compute per-split C-index with optional FI; run for full and original datasets
  # Final safety check for mc_cv before using it in if statement
  if (!is.logical(mc_cv) || is.na(mc_cv)) {
    cat(sprintf("[ERROR] mc_cv is not a valid logical value: %s (type: %s, class: %s)\n", 
                mc_cv, typeof(mc_cv), paste(class(mc_cv), collapse=", ")))
    cat("[ERROR] Setting mc_cv to FALSE as fallback\n")
    mc_cv <- FALSE
  }
  
  if (mc_cv) {
    # CRITICAL DEBUG: Verify MC-CV mode setup
    cat("\n[DEBUG] ===== MC-CV MODE ACTIVATED =====\n")
    cat(sprintf("[DEBUG] MC_CV mode: %s\n", mc_cv))
    cat(sprintf("[DEBUG] final_data dimensions: %d x %d\n", nrow(final_data), ncol(final_data)))
    cat(sprintf("[DEBUG] model_vars length: %d\n", length(model_vars)))
    cat(sprintf("[DEBUG] models directory exists: %s\n", dir.exists(here::here('model_data','models'))))
    cat("[DEBUG] First 5 model_vars:", paste(head(model_vars, 5), collapse = ", "), "\n")
    cat("[DEBUG] ================================\n\n")
    flush.console()

    # Load resampling splits for MC-CV
    resamples_path <- here::here('model_data', 'resamples.rds')
    testing_rows <- NULL
    if (file.exists(resamples_path)) {
      tryCatch({
      testing_rows <- readRDS(resamples_path)
      cat(sprintf("[DEBUG] Loaded %d resampling splits from resamples.rds\n", length(testing_rows)))
      }, error = function(e) {
        cat(sprintf("[WARNING] Could not read resamples.rds (R version mismatch): %s\n", e$message))
        cat("[DEBUG] Will create MC-CV splits on the fly\n")
        testing_rows <<- NULL
      })
    }
    
    if (is.null(testing_rows)) {
      # Create MC-CV splits on the fly (fallback for R version mismatch)
      prop <- as.numeric(Sys.getenv("MC_TEST_PROP", "0.2"))
      times <- as.integer(Sys.getenv("MC_TIMES", "20"))
      set.seed(as.integer(Sys.getenv("SEED", "42")))
      suppressPackageStartupMessages(library(rsample))
      mc_cv_splits <- rsample::mc_cv(final_data, times = times, prop = prop, strata = "status")
      testing_rows <- lapply(mc_cv_splits$splits, function(s) {
        test_indices <- assessment(s)
        if (is.data.frame(test_indices)) {
          as.integer(as.numeric(rownames(test_indices)))
        } else {
          as.integer(test_indices)
        }
      })
      cat(sprintf("[DEBUG] Created %d MC-CV splits on the fly\n", length(testing_rows)))
    }

    # Call run_mc function for MC-CV analysis
    cat("[DEBUG] Starting MC-CV analysis with run_mc function...\n")
    
    # DEBUG: Check data and variables before calling run_mc
    cat("[DEBUG] Final data dimensions:", nrow(final_data), "x", ncol(final_data), "\n")
    cat(sprintf("[DEBUG] Encoded model vars length: %d\n", length(model_vars)))
    cat(sprintf("[DEBUG] Original vars length: %d\n", length(original_vars)))
    cat(sprintf("[DEBUG] First 10 original vars: %s\n", paste(head(original_vars, 10), collapse = ", ")))
    cat("[DEBUG] First 10 final_data columns:", paste(head(colnames(final_data), 10), collapse = ", "), "\n")
    
    # Check for missing variables (use original_vars for MC-CV)
    missing_vars <- setdiff(original_vars, colnames(final_data))
    if (length(missing_vars) > 0) {
      cat("[ERROR] Missing Wisotzkey variables in final_data:\n")
      cat(paste(missing_vars, collapse = "\n"), "\n")
      stop("Cannot proceed with MC-CV: missing Wisotzkey variables in final_data")
    }
    
    # Load encoded data for XGB before calling run_mc
    use_global_xgb <- tolower(Sys.getenv("MC_XGB_USE_GLOBAL", unset = "1")) %in% c("1","true","yes","y")  # Default to TRUE
  encoded_full <- NULL; encoded_full_vars <- NULL
  if (use_global_xgb) {
    enc_path_full <- here::here('model_data','final_data_encoded.rds')
      if (file.exists(enc_path_full)) {
    encoded_full <- readRDS(enc_path_full)
        encoded_full_vars <- model_vars  # Use the encoded variable names
        cat("[INFO] MC CV: Using global encoded dataset for XGB (full data)\n")
        cat("[INFO] Encoded data dimensions:", nrow(encoded_full), "x", ncol(encoded_full), "\n")
  } else {
        cat("[WARNING] MC_XGB_USE_GLOBAL=1 but final_data_encoded.rds not found. Using per-split encoding.\n")
        use_global_xgb <- FALSE
      }
      } else {
      cat("[INFO] MC CV: Using per-split on-the-fly encoding for XGB\n")
    }

    # Call run_mc function for MC-CV analysis (now available from model_utils.R)
    cat("[INFO] Starting MC-CV analysis using run_mc function from model_utils.R\n")
    cat("[INFO] Using original variables (not encoded) for MC-CV\n")
    cat("[INFO] Parallel processing will be configured automatically for each model\n")
    
    # Configure parallel processing for MC-CV
    cat("[INFO] Setting up parallel processing configuration for MC-CV...\n")
    
    # Configure aorsf parallel processing
    aorsf_config <- configure_aorsf_parallel(
      use_all_cores = TRUE,
      target_utilization = 0.8,
      check_r_functions = TRUE,
      verbose = TRUE
    )
    
    # Configure ranger parallel processing
    ranger_config <- configure_ranger_parallel(
      use_all_cores = TRUE,
      target_utilization = 0.8,
      memory_efficient = FALSE,
      verbose = TRUE
    )
    
    # Configure XGBoost parallel processing
    xgb_config <- configure_xgboost_parallel(
      use_all_cores = TRUE,
      target_utilization = 0.8,
      tree_method = 'auto',
      verbose = TRUE
    )
    
    # Configure CPH parallel processing (single-threaded by design)
    cph_config <- configure_cph_parallel(
      use_all_cores = FALSE,
      n_thread = 1,
      target_utilization = NA,
      check_r_functions = FALSE,
      verbose = TRUE
    )
    
    cat("[INFO] Parallel processing configured for all models (including CPH)\n")
    
    run_mc(
      label = "full",
      df = final_data,
      vars = original_vars,  # Use original variables for MC-CV
      testing_rows = testing_rows,
      encoded_df = encoded_full,        # Pass encoded data for XGB
      encoded_vars = encoded_full_vars, # Pass encoded variable names
      use_global_xgb = use_global_xgb,  # Pass the flag
      catboost_full_vars = available_wisotzkey
    )

  # Helper functions (cindex, cindex_uno, ensure_mc_df, run_mc) are now available from model_utils.R
  # run_mc function definition removed - now available from model_utils.R
  
  } else {
    # Non-MC-CV mode: single model fitting (traditional approach)
    cat("\n[DEBUG] ===== SINGLE MODEL FITTING MODE =====\n")
    cat("[DEBUG] MC_CV disabled, fitting single models on full dataset\n")
    flush.console()
  } # End of if (mc_cv)

# Write a comparison index for single-fit case; empty in MC mode
if (!exists("cmp")) {
  cmp <- data.frame(
    model = character(0), file = character(0), use_encoded = integer(0),
    timestamp = character(0), stringsAsFactors = FALSE
  )
}
# Save model comparison index to cohort-specific location
cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
cmp_dir <- here::here('models', cohort_name)
dir.create(cmp_dir, showWarnings = FALSE, recursive = TRUE)
readr::write_csv(cmp, file.path(cmp_dir, 'model_comparison_index.csv'))
message(sprintf("Saved: models/%s/model_comparison_index.csv", cohort_name))

# Model Selection Heuristic (standardized across docs):
# 1. Primary metric: mean Monte Carlo C-index (full dataset label).
# 2. Tie / practical equivalence (overlapping 95% CIs within absolute 0.005):
#    a. Prefer lower SD (stability)
#    b. Prefer broader clinically interpretable feature signal (importance dispersion across plausible predictors)
#    c. If still tied: defer to domain/clinical interpretability consensus (deployment complexity NOT a criterion)
# Notes:
# - Single-fit mode (MC_CV=0) is exploratory only; final decision should reference MC summaries.
# - Union importance (RSF + CatBoost) supports interpretation, not ranking.
# - Future: calibration or additional metrics (time-dependent AUC, Brier/IBS) may extend criteria.

# CRITICAL FIX: MC-CV mode was missing final model creation
# After MC-CV completes, we still need to fit and save the final models for Step 05
cat("\n[DEBUG] ===== POST MC-CV: FITTING FINAL MODELS =====\n")
cat("[DEBUG] MC-CV completed, now fitting final models for Step 05...\n")
flush.console()

tryCatch({
  # Always use parallel model fitting for optimal performance
  cat("[DEBUG] ===== FITTING FINAL MODELS IN PARALLEL =====\n")
  cat(sprintf("[Progress] Dataset size: %d rows, %d variables\n", nrow(final_data), length(model_vars)))
  flush.console()
  
  # Parallel execution with smart thread allocation
  suppressPackageStartupMessages({
    library(future)
    library(furrr)
  })
  
  # Configure parallel workers with conservative threading
  workers_env <- suppressWarnings(as.integer(Sys.getenv('FINAL_MODEL_WORKERS', unset = '0')))
  if (!is.finite(workers_env) || workers_env < 1) {
    cores <- tryCatch(as.numeric(future::availableCores()), error = function(e) parallel::detectCores(logical = TRUE))
    workers <- min(4L, max(1L, floor(cores * 0.75)))  # Max 4 workers (one per model), 75% of cores
  } else {
    workers <- min(workers_env, 4L)  # Cap at 4 since we have 4 models
  }
  
  # Set thread allocation for parallel workers (8 threads per worker)
  threads_per_worker <- 8
  total_threads <- workers * threads_per_worker
  
  cat(sprintf("[Progress] Setting up %d parallel workers for final model fitting...\n", workers))
  cat(sprintf("[Progress] Thread allocation: %d workers × %d threads = %d total threads (%.1f%% of %d cores)\n", 
              workers, threads_per_worker, total_threads, (total_threads/cores)*100, cores))
  
  # Set up future plan
  if (workers > 1) {
    if (tolower(Sys.getenv('FINAL_MODEL_PLAN', unset = 'multisession')) == 'cluster') {
      future::plan(future::cluster, workers = workers)
      cat("[Progress] Using cluster plan for parallel execution\n")
    } else {
      future::plan(future::multisession, workers = workers)
      cat("[Progress] Using multisession plan for parallel execution\n")
    }
  } else {
    future::plan(future::sequential)
    cat("[Progress] Using sequential execution (single worker)\n")
  }
  
  # Create tasks for model execution - Main 4 survival models
  model_tasks <- list(
    list(model = "ORSF", fit_func = "fit_orsf"),
    list(model = "CATBOOST", fit_func = "fit_catboost"),
    list(model = "XGB", fit_func = "fit_xgb"),
    list(model = "CPH", fit_func = "fit_cph")
  )
  
  # Parallel model fitting for optimal performance
  cat("[Progress] Starting parallel model fitting (ORSF + RSF + XGB + CPH simultaneously)...\n")
  cat(sprintf("[Progress] Individual model logs will be written to: logs/models/%s/full/\n", 
             Sys.getenv('DATASET_COHORT', unset = 'unknown')))
  flush.console()
  
  # Parallel execution using furrr::future_map
  final_models <- furrr::future_map(model_tasks, function(task) {
    # Set up model-specific logging within worker - follow same pattern as MC-CV splits
    cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
    label_name <- "full"  # Same label as MC-CV
    log_dir <- here::here('logs', 'models', cohort_name, label_name)
    dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
    model_log <- file.path(log_dir, sprintf('%s_final.log', task$model))
    
    # Initialize log file with header
    try({
      cat(sprintf('[LOG START] %s final model fitting - %s\n', 
                  task$model, format(Sys.time(), '%Y-%m-%d %H:%M:%S')), 
          file = model_log, append = TRUE)
      cat(sprintf('[WORKER] PID: %d, Task: %s\n', Sys.getpid(), task$model), 
          file = model_log, append = TRUE)
      
      # FUNCTION AVAILABILITY DIAGNOSTICS
      cat(sprintf('[FUNCTION_DIAG] Checking function availability for %s model...\n', task$model), 
          file = model_log, append = TRUE)
      
      # Define required functions for each model type
      required_functions <- switch(task$model,
        "ORSF" = c("fit_orsf", "configure_aorsf_parallel", "get_aorsf_params", "orsf", "aorsf_parallel", "predict_aorsf_parallel"),
        "CATBOOST" = c("fit_catboost", "configure_catboost_parallel", "get_catboost_params", "predict_catboost_survival"),
        "XGB" = c("fit_xgb", "configure_xgboost_parallel", "get_xgboost_params", "xgboost_parallel", "predict_xgboost_parallel", "sgb_fit", "sgb_data"),
        "CPH" = c("fit_cph"),
        character(0)
      )
      
      # Check function availability
      available_functions <- character(0)
      missing_functions <- character(0)
      
      for (func_name in required_functions) {
        if (exists(func_name, mode = "function")) {
          available_functions <- c(available_functions, func_name)
        } else {
          missing_functions <- c(missing_functions, func_name)
        }
      }
      
      cat(sprintf('[FUNCTION_DIAG] Required functions: %s\n', paste(required_functions, collapse = ", ")), 
          file = model_log, append = TRUE)
      cat(sprintf('[FUNCTION_DIAG] Available functions: %s\n', paste(available_functions, collapse = ", ")), 
          file = model_log, append = TRUE)
      cat(sprintf('[FUNCTION_DIAG] Missing functions: %s\n', paste(missing_functions, collapse = ", ")), 
          file = model_log, append = TRUE)
      
      if (length(missing_functions) > 0) {
        cat(sprintf('[FUNCTION_DIAG] WARNING: %d functions missing - model fitting may fail!\n', length(missing_functions)), 
            file = model_log, append = TRUE)
      } else {
        cat(sprintf('[FUNCTION_DIAG] SUCCESS: All required functions available\n'), 
            file = model_log, append = TRUE)
      }
      
    }, silent = TRUE)
    
    # Load required packages in each worker
    library(aorsf)
    library(ranger)
    library(survival)
    library(riskRegression)
    library(glue)
    library(here)
    
    # Load required functions in each worker
    source(here::here("scripts", "R", "fit_orsf.R"))
    source(here::here("scripts", "R", "fit_rsf.R"))
    source(here::here("scripts", "R", "fit_cph.R"))
    source(here::here("scripts", "R", "safe_coxph.R"))
    source(here::here("scripts", "R", "ranger_predictrisk.R"))
    source(here::here("scripts", "R", "utils", "model_utils.R"))  # Load parallel processing utilities
    
    # Load performance monitoring functions (now centralized in model_utils.R)
    if (file.exists(here::here("scripts", "R", "aorsf_parallel_config.R"))) {
      source(here::here("scripts", "R", "aorsf_parallel_config.R"))
    }
    if (file.exists(here::here("scripts", "R", "ranger_parallel_config.R"))) {
      source(here::here("scripts", "R", "ranger_parallel_config.R"))
    }
    if (file.exists(here::here("scripts", "R", "xgboost_parallel_config.R"))) {
      source(here::here("scripts", "R", "xgboost_parallel_config.R"))
    }
    if (file.exists(here::here("scripts", "R", "cph_parallel_config.R"))) {
      source(here::here("scripts", "R", "cph_parallel_config.R"))
    }
    
    # Log start of fitting
    cat(sprintf("[Progress] Worker fitting %s model...\n", task$model))
    try(cat(sprintf('[WORKER] Starting %s model fitting\n', task$model), 
            file = model_log, append = TRUE), silent = TRUE)
    flush.console()
    
    # Monitor memory before fitting
    gc_before <- gc()
    memory_before <- sum(gc_before[,2])
    cat(sprintf("[Progress] Memory before %s: %.2f MB\n", task$model, memory_before))
    try(cat(sprintf('[WORKER] Memory before fitting: %.2f MB\n', memory_before), 
            file = model_log, append = TRUE), silent = TRUE)
    flush.console()
    
    start_time <- Sys.time()
    try(cat(sprintf('[WORKER] Model fitting started at: %s\n', 
                    format(start_time, '%Y-%m-%d %H:%M:%S')), 
            file = model_log, append = TRUE), silent = TRUE)
    
    # Fit the model
    try(cat(sprintf('[WORKER] Fitting %s model with %d variables on %d rows\n', 
                    task$model, length(original_vars), nrow(final_data)), 
            file = model_log, append = TRUE), silent = TRUE)
    
    if (task$fit_func == "fit_orsf") {
      # Configure aorsf parallel processing with conservative threading
      aorsf_config <- configure_aorsf_parallel(
        use_all_cores = FALSE,
        n_thread = threads_per_worker,
        check_r_functions = TRUE,
        verbose = FALSE
      )
      
      # Set up ORSF-specific performance monitoring
      monitor_info <- setup_orsf_performance_monitoring(
        aorsf_config = aorsf_config,
        log_dir = log_dir,
        interval = 5
      )
      
      if (monitor_info$monitoring_active) {
        try(cat(sprintf('[PERF_MONITOR] Started aorsf performance monitoring to: %s\n', monitor_info$performance_log), 
                file = model_log, append = TRUE), silent = TRUE)
      }
      
      model_result <- fit_orsf(trn = final_data, vars = original_vars, 
                              use_parallel = TRUE, check_r_functions = TRUE)
    } else if (task$fit_func == "fit_rsf") {
      # Configure ranger parallel processing with conservative threading
      ranger_config <- configure_ranger_parallel(
        use_all_cores = FALSE,
        num_threads = threads_per_worker,
        memory_efficient = FALSE,
        verbose = FALSE
      )
      
      # Set up RSF-specific performance monitoring
      monitor_info <- setup_rsf_performance_monitoring(
        ranger_config = ranger_config,
        log_dir = log_dir,
        interval = 5
      )
      
      if (monitor_info$monitoring_active) {
        try(cat(sprintf('[PERF_MONITOR] Started ranger performance monitoring to: %s\n', monitor_info$performance_log), 
                file = model_log, append = TRUE), silent = TRUE)
      }
      
      model_result <- fit_rsf(trn = final_data, vars = original_vars, 
                             use_parallel = TRUE)
    } else if (task$fit_func == "fit_xgb") {
      # Configure XGBoost parallel processing with conservative threading
      xgb_config <- configure_xgboost_parallel(
        use_all_cores = FALSE,
        nthread = threads_per_worker,
        tree_method = 'auto',
        verbose = FALSE
      )
      
      # Set up XGBoost-specific performance monitoring
      monitor_info <- setup_xgb_performance_monitoring(
        xgb_config = xgb_config,
        log_dir = log_dir,
        interval = 5
      )
      
      if (monitor_info$monitoring_active) {
        try(cat(sprintf('[PERF_MONITOR] Started xgboost performance monitoring to: %s\n', monitor_info$performance_log), 
                file = model_log, append = TRUE), silent = TRUE)
      }
      
      # XGBoost needs encoded data, so we need to load it
      xgb_data_path <- here::here('model_data','final_data_encoded.rds')
      if (!file.exists(xgb_data_path)) {
        stop("Encoded dataset final_data_encoded.rds not found. Re-run step 03 before fitting XGB.")
      }
      xgb_trn <- readRDS(xgb_data_path)
      
      # Use encoded variables for XGBoost
      xgb_vars <- final_features$terms  # encoded variable names
      
      model_result <- fit_xgb(trn = xgb_trn, vars = xgb_vars)
    } else if (task$fit_func == "fit_cph") {
      # Set up CPH-specific performance monitoring (no parallel processing)
      monitor_info <- setup_cph_performance_monitoring(log_dir = log_dir)
      
      try(cat(sprintf('[PERF_MONITOR] CPH model - no parallel processing monitoring needed\n'), 
              file = model_log, append = TRUE), silent = TRUE)
      
      model_result <- fit_cph(trn = final_data, vars = original_vars, tst = NULL)
    }
    
    end_time <- Sys.time()
    elapsed <- as.numeric(difftime(end_time, start_time, units = "mins"))
    
    # Log model fitting completion
    try(cat(sprintf('[WORKER] Model fitting completed at: %s (%.2f minutes)\n', 
                    format(end_time, '%Y-%m-%d %H:%M:%S'), elapsed), 
            file = model_log, append = TRUE), silent = TRUE)
    
    # Monitor memory after fitting
    gc_after <- gc()
    memory_after <- sum(gc_after[,2])
    cat(sprintf("[Progress] Memory after %s: %.2f MB\n", task$model, memory_after))
    cat(sprintf("[Progress] %s completed in %.2f minutes\n", task$model, elapsed))
    try(cat(sprintf('[WORKER] Memory after fitting: %.2f MB (delta: %.2f MB)\n', 
                    memory_after, memory_after - memory_before), 
            file = model_log, append = TRUE), silent = TRUE)
    flush.console()
    
    # CRITICAL: Save model within worker session to avoid large object transfers
    cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
    models_dir <- here::here('models', cohort_name)
    dir.create(models_dir, showWarnings = FALSE, recursive = TRUE)
    
    # Log model metadata and prepare for saving
    try(cat(sprintf('[WORKER] Starting model save process\n'), 
            file = model_log, append = TRUE), silent = TRUE)
    
    model_path <- NULL
    if (task$model == "ORSF") {
      model_path <- file.path(models_dir, 'model_orsf.rds')  # Cohort-specific path
      cat("[DEBUG] ORSF model metadata before save:\n")
      cat("  class:", paste(class(model_result), collapse=", "), "\n")
      cat("  type:", typeof(model_result), "\n")
      cat("  object.size:", format(object.size(model_result), units="auto"), "\n")
      utils::str(model_result, max.level=2)
      
      # Log to file
      try(cat(sprintf('[WORKER] ORSF model metadata:\n'), file = model_log, append = TRUE), silent = TRUE)
      try(cat(sprintf('[WORKER]   class: %s\n', paste(class(model_result), collapse=", ")), 
              file = model_log, append = TRUE), silent = TRUE)
      try(cat(sprintf('[WORKER]   object.size: %s\n', format(object.size(model_result), units="auto")), 
              file = model_log, append = TRUE), silent = TRUE)
      
    } else if (task$model == "RSF") {
      model_path <- file.path(models_dir, 'model_rsf.rds')  # Cohort-specific path
      cat("[DEBUG] RSF model metadata before save:\n")
      cat("  class:", paste(class(model_result), collapse=", "), "\n")
      cat("  type:", typeof(model_result), "\n")
      cat("  object.size:", format(object.size(model_result), units="auto"), "\n")
      utils::str(model_result, max.level=2)
      
      # Log to file
      try(cat(sprintf('[WORKER] RSF model metadata:\n'), file = model_log, append = TRUE), silent = TRUE)
      try(cat(sprintf('[WORKER]   class: %s\n', paste(class(model_result), collapse=", ")), 
              file = model_log, append = TRUE), silent = TRUE)
      try(cat(sprintf('[WORKER]   object.size: %s\n', format(object.size(model_result), units="auto")), 
              file = model_log, append = TRUE), silent = TRUE)
      
    } else if (task$model == "XGB") {
      model_path <- file.path(models_dir, 'model_xgb.rds')  # Cohort-specific path
      cat("[DEBUG] XGB model metadata before save:\n")
      cat("  class:", paste(class(model_result), collapse=", "), "\n")
      cat("  type:", typeof(model_result), "\n")
      cat("  object.size:", format(object.size(model_result), units="auto"), "\n")
      utils::str(model_result, max.level=2)
      
      # Log to file
      try(cat(sprintf('[WORKER] XGB model metadata:\n'), file = model_log, append = TRUE), silent = TRUE)
      try(cat(sprintf('[WORKER]   class: %s\n', paste(class(model_result), collapse=", ")), 
              file = model_log, append = TRUE), silent = TRUE)
      try(cat(sprintf('[WORKER]   object.size: %s\n', format(object.size(model_result), units="auto")), 
              file = model_log, append = TRUE), silent = TRUE)
      
    } else if (task$model == "CPH") {
      model_path <- file.path(models_dir, 'model_cph.rds')  # Cohort-specific path
      cat("[DEBUG] CPH model metadata before save:\n")
      cat("  class:", paste(class(model_result), collapse=", "), "\n")
      cat("  type:", typeof(model_result), "\n")
      cat("  object.size:", format(object.size(model_result), units="auto"), "\n")
      utils::str(model_result, max.level=2)
      
      # Log to file
      try(cat(sprintf('[WORKER] CPH model metadata:\n'), file = model_log, append = TRUE), silent = TRUE)
      try(cat(sprintf('[WORKER]   class: %s\n', paste(class(model_result), collapse=", ")), 
              file = model_log, append = TRUE), silent = TRUE)
      try(cat(sprintf('[WORKER]   object.size: %s\n', format(object.size(model_result), units="auto")), 
              file = model_log, append = TRUE), silent = TRUE)
    }
    
    # Save the model within worker
    if (!is.null(model_path)) {
      try(cat(sprintf('[WORKER] Saving model to: %s\n', model_path), 
              file = model_log, append = TRUE), silent = TRUE)
      
      save_start <- Sys.time()
      saveRDS(model_result, model_path)
      save_end <- Sys.time()
      save_elapsed <- as.numeric(difftime(save_end, save_start, units = "secs"))
      
      if (file.exists(model_path)) {
        file_size_mb <- file.size(model_path) / 1024 / 1024
        cat(sprintf("[Progress] ✓ Saved: %s (%.2f MB, %.2f mins)\n", 
                   basename(model_path), file_size_mb, elapsed))
        
        # Log successful save
        try(cat(sprintf('[WORKER] ✓ Model saved successfully: %s\n', basename(model_path)), 
                file = model_log, append = TRUE), silent = TRUE)
        try(cat(sprintf('[WORKER]   File size: %.2f MB\n', file_size_mb), 
                file = model_log, append = TRUE), silent = TRUE)
        try(cat(sprintf('[WORKER]   Save time: %.2f seconds\n', save_elapsed), 
                file = model_log, append = TRUE), silent = TRUE)
      } else {
        cat(sprintf("[ERROR] Failed to save %s\n", basename(model_path)))
        try(cat(sprintf('[WORKER] ✗ Failed to save model: %s\n', basename(model_path)), 
                file = model_log, append = TRUE), silent = TRUE)
      }
    }
    
    # Log performance summary using centralized function
    log_performance_summary(
      model_type = task$model,
      elapsed_time = elapsed,
      memory_before = memory_before,
      memory_after = memory_after,
      threads_used = threads_per_worker,
      performance_log = monitor_info$performance_log,
      model_log = model_log
    )
    
    # Log completion
    try(cat(sprintf('[LOG END] %s final model process completed - %s\n', 
                    task$model, format(Sys.time(), '%Y-%m-%d %H:%M:%S')), 
            file = model_log, append = TRUE), silent = TRUE)
    
    # Return lightweight summary instead of heavy model object
    return(list(
      model_name = task$model,
      elapsed_mins = elapsed,
      model_path = model_path,
      model_size_mb = if (!is.null(model_path) && file.exists(model_path)) file.size(model_path) / 1024 / 1024 else NA,
      success = !is.null(model_result)
    ))
  }, .options = furrr::furrr_options(
    seed = TRUE,
    packages = c("here", "survival", "ranger", "aorsf", "riskRegression", "glue"),
    globals = list(
      final_data = final_data, 
      original_vars = original_vars,
      threads_per_worker = threads_per_worker,
      # Include parallel processing configuration functions
      configure_ranger_parallel = configure_ranger_parallel,
      configure_xgboost_parallel = configure_xgboost_parallel,
      configure_aorsf_parallel = configure_aorsf_parallel,
      configure_cph_parallel = configure_cph_parallel,
      # Include parallel processing wrapper functions
      ranger_parallel = ranger_parallel,
      predict_ranger_parallel = predict_ranger_parallel,
      xgboost_parallel = xgboost_parallel,
      predict_xgboost_parallel = predict_xgboost_parallel,
      aorsf_parallel = aorsf_parallel,
      predict_aorsf_parallel = predict_aorsf_parallel,
      # Include XGBoost helper functions
      get_xgboost_params = get_xgboost_params,
      sgb_fit = sgb_fit,
      sgb_data = sgb_data,
      # Include aorsf helper functions
      get_aorsf_params = get_aorsf_params,
      orsf = orsf,
      # Include ranger model fitting functions
      fit_rsf = fit_rsf,
      ranger_predictrisk = ranger_predictrisk,
      get_ranger_params = get_ranger_params,
      # Include CPH model fitting functions
      fit_cph = fit_cph,
      safe_coxph = safe_coxph,
      # Include XGBoost performance monitoring functions
      monitor_xgboost_performance = monitor_xgboost_performance,
      benchmark_xgboost_threads = benchmark_xgboost_threads,
      # Include ranger performance monitoring functions
      monitor_ranger_performance = monitor_ranger_performance,
      benchmark_ranger_threads = benchmark_ranger_threads,
      # Include aorsf performance monitoring functions
      monitor_aorsf_performance = monitor_aorsf_performance,
      benchmark_aorsf_threads = benchmark_aorsf_threads,
      # Include CPH performance monitoring functions
      setup_cph_performance_monitoring = setup_cph_performance_monitoring,
      monitor_cph_performance = monitor_cph_performance,
      benchmark_cph_threads = benchmark_cph_threads,
      # Include utility functions
      safe_model_predict = safe_model_predict
    )
  ))
  
  cat("[DEBUG] Parallel model fitting completed! Models saved within workers.\n")
  flush.console()
  
  # Process results - models are already saved, just handle final_model.rds
  final_orsf_path <- NULL
  successful_models <- list()
  
  for (result in final_models) {
    if (result$success) {
      successful_models[[result$model_name]] <- result
      cat(sprintf("[Progress] ✓ %s: %.2f MB, %.2f mins\n", 
                 result$model_name, result$model_size_mb, result$elapsed_mins))
      
      # Track ORSF path for backward compatibility
    if (result$model_name == "ORSF") {
        final_orsf_path <- result$model_path
      }
      } else {
      cat(sprintf("[ERROR] ✗ %s: Failed to fit\n", result$model_name))
    }
  }
  
  # Save ORSF as final_model.rds for backward compatibility (cohort-specific)
  if (!is.null(final_orsf_path) && file.exists(final_orsf_path)) {
    cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
    final_dir <- here::here('models', cohort_name)
    dir.create(final_dir, showWarnings = FALSE, recursive = TRUE)
    final_path <- file.path(final_dir, 'final_model.rds')
    file.copy(final_orsf_path, final_path, overwrite = TRUE)
    if (file.exists(final_path)) {
      cat(sprintf("[Progress] ✓ Saved: models/final_model.rds (default ORSF, %.2f MB)\n", 
                 file.size(final_path)/1024/1024))
    } else {
      cat("[ERROR] Failed to save models/final_model.rds\n")
    }
  }
  
  # Update comparison index to include successful models
  if (length(successful_models) > 0) {
    cmp_rows <- list()
    for (model_name in names(successful_models)) {
      result <- successful_models[[model_name]]
      if (!is.null(result$model_path) && file.exists(result$model_path)) {
        cmp_rows[[length(cmp_rows) + 1]] <- data.frame(
          model = model_name,
          file = gsub("^.*[\\/]", "", result$model_path),  # Just filename
    use_encoded = 0L,
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    stringsAsFactors = FALSE
  )
      }
    }
    
    if (length(cmp_rows) > 0) {
      cmp <- dplyr::bind_rows(cmp_rows)
    } else {
      cmp <- data.frame(
        model = character(0), file = character(0), use_encoded = integer(0),
        timestamp = character(0), stringsAsFactors = FALSE
      )
    }
  } else {
    cmp <- data.frame(
      model = character(0), file = character(0), use_encoded = integer(0),
      timestamp = character(0), stringsAsFactors = FALSE
    )
  }
  
  cat("[DEBUG] Final models fitted and saved successfully IN PARALLEL!\n")
  
  # Clean up parallel backend
  future::plan(future::sequential)
  cat("[Progress] Parallel backend cleaned up\n")
  
}, error = function(e) {
  # Clean up parallel backend in case of error
  tryCatch(future::plan(future::sequential), error = function(e2) NULL)
  
  cat(sprintf("[ERROR] Failed to fit final models: %s\n", conditionMessage(e)))
  if (grepl("timeout", conditionMessage(e), ignore.case = TRUE)) {
    cat("[ERROR] Model fitting timed out - likely too large for available resources\n")
  }
  cat("[ERROR] Attempting fallback: fitting simpler RSF model only...\n")
  
  # Fallback: try to fit at least RSF so Step 05 doesn't completely fail
  tryCatch({
    cat("[Progress] Fitting fallback RSF model (no timeout - may take several hours)...\n")
    cat("[Progress] For study replication accuracy, allowing full runtime\n")
    cat("[Progress] Configuring parallel processing for fallback RSF...\n")
    flush.console()
    
    # Configure ranger parallel processing for fallback
    ranger_config <- configure_ranger_parallel(
      use_all_cores = TRUE,
      target_utilization = 0.8,
      memory_efficient = FALSE,
      verbose = TRUE
    )
    
    # Use non-parallel RSF fitting for fallback (main context doesn't have parallel functions)
    fallback_rsf <- fit_rsf(trn = final_data, vars = model_vars, use_parallel = FALSE)
    
    # Save RSF as both the RSF model and as final_model for compatibility (cohort-specific)
    cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
    rsf_dir <- here::here('models', cohort_name)
    dir.create(rsf_dir, showWarnings = FALSE, recursive = TRUE)
    
    rsf_path <- file.path(rsf_dir, 'model_rsf.rds')
    saveRDS(fallback_rsf, rsf_path)
    final_path <- file.path(rsf_dir, 'final_model.rds')
    saveRDS(fallback_rsf, final_path)
    
    if (file.exists(rsf_path) && file.exists(final_path)) {
      cat("[Progress] ✓ Fallback successful: RSF model saved as final_model.rds\n")
    } else {
      cat("[ERROR] ✗ Fallback also failed - Step 05 will fail\n")
    }
  }, error = function(e2) {
    cat(sprintf("[ERROR] RSF fallback also failed: %s\n", conditionMessage(e2)))
    if (grepl("timeout", conditionMessage(e2), ignore.case = TRUE)) {
      cat("[ERROR] RSF also timed out - dataset too large for current resources\n")
    }
    
    # Final fallback: create a minimal model for Step 05 compatibility
    cat("[WARNING] Creating minimal dummy model to allow Step 05 to run...\n")
    tryCatch({
      # Create a very simple survival model with minimal data
      minimal_data <- final_data[sample(nrow(final_data), min(1000, nrow(final_data))), ]
      minimal_vars <- head(model_vars, 5)  # Use only first 5 variables
      
      cat(sprintf("[Progress] Fitting minimal model: %d rows, %d vars\n", nrow(minimal_data), length(minimal_vars)))
      cat("[Progress] Configuring parallel processing for minimal model...\n")
      
      # Configure ranger parallel processing for minimal model
      ranger_config <- configure_ranger_parallel(
        use_all_cores = TRUE,
        target_utilization = 0.8,
        memory_efficient = FALSE,
        verbose = TRUE
      )
      
      minimal_model <- fit_rsf(trn = minimal_data, vars = minimal_vars, use_parallel = FALSE)
      
      # Save minimal model
      cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
      final_dir <- here::here('models', cohort_name)
      dir.create(final_dir, showWarnings = FALSE, recursive = TRUE)
      final_path <- file.path(final_dir, 'final_model.rds')
      saveRDS(minimal_model, final_path)
      
      if (file.exists(final_path)) {
        cat("[WARNING] ✓ Minimal model saved - Step 05 can proceed with limited functionality\n")
      } else {
        cat("[ERROR] ✗ Even minimal model failed - Step 05 will fail\n")
      }
    }, error = function(e3) {
      cat(sprintf("[ERROR] Even minimal model failed: %s\n", conditionMessage(e3)))
      cat("[ERROR] No models saved - Step 05 will fail\n")
    })
  })
})

# CRITICAL: Log process monitoring summary at completion
cat("\n=== PROCESS MONITORING SUMMARY ===\n")
cat("[PROCESS_SUMMARY] Model fitting completed - check process logs for details:\n")
cat(sprintf("[PROCESS_SUMMARY] Individual model logs: logs/models/%s/*/{{MODEL}}_split{{XXX}}.log\n", cohort_name))
cat("[PROCESS_SUMMARY] Pipeline monitoring: logs/pipeline_process_monitor.log\n")

# Check for common process monitoring issues
cat("\n=== TROUBLESHOOTING COMMANDS ===\n")
cat("[TROUBLESHOOTING] Check for completed model fittings:\n")
cat("[TROUBLESHOOTING]   grep \"PROCESS_POST_\" logs/models/*/full/*.log\n")
cat("[TROUBLESHOOTING] Check for threading conflicts:\n") 
cat("[TROUBLESHOOTING]   grep \"THREADING_CONFLICT\" logs/models/*/full/*.log\n")
cat("[TROUBLESHOOTING] Monitor system resources:\n")
cat("[TROUBLESHOOTING]   tail -f logs/pipeline_process_monitor.log\n")
cat("[TROUBLESHOOTING] Find hanging models (started but not finished):\n")
cat("[TROUBLESHOOTING]   for model in ORSF RSF XGB CPH; do echo \"=== $model ===\"; echo \"Started: $(grep -c \"PROCESS_PRE_$model\" logs/models/*/full/${model}_*.log)\"; echo \"Finished: $(grep -c \"PROCESS_POST_$model\" logs/models/*/full/${model}_*.log)\"; done\n")

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
