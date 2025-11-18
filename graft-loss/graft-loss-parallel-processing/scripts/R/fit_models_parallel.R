# ===================
# DATA SETUP AND MODEL FITTING MODULE
# ===================
# This module handles data loading, setup, and parallel model fitting.

#' Setup model data and variables
#' @return List with success status, data, and configuration
setup_model_data <- function() {
  tryCatch({
    # Get cohort name for cohort-specific file paths
    cohort_name <- Sys.getenv("DATASET_COHORT", unset = "unknown")
    
    # Load final_features from step 03 (cohort-specific)
    # Try cohort-specific path first, fall back to global path for backward compatibility
    final_features_path_cohort <- file.path(here::here('model_data'), cohort_name, 'final_features.rds')
    final_features_path_global <- here::here('model_data', 'final_features.rds')
    
    if (file.exists(final_features_path_cohort)) {
      final_features <- readRDS(final_features_path_cohort)
      cat(sprintf("[DEBUG] Loaded final_features from cohort-specific path: %s\n", final_features_path_cohort))
    } else if (file.exists(final_features_path_global)) {
      final_features <- readRDS(final_features_path_global)
      cat(sprintf("[DEBUG] Loaded final_features from global path: %s\n", final_features_path_global))
    } else {
      return(list(success = FALSE, error = sprintf("final_features.rds not found in %s or %s. Please run step 03 first.", 
                                                     final_features_path_cohort, final_features_path_global)))
    }
    
    # Load final_data from step 03 (cohort-specific or global)
    final_data_path_cohort <- file.path(here::here('model_data'), cohort_name, 'final_data.rds')
    final_data_path_global <- here::here('model_data', 'final_data.rds')
    
    if (file.exists(final_data_path_cohort)) {
      final_data <- readRDS(final_data_path_cohort)
      cat(sprintf("[DEBUG] Loaded final_data from cohort-specific path: %s (%d rows, %d cols)\n", 
                  final_data_path_cohort, nrow(final_data), ncol(final_data)))
    } else if (file.exists(final_data_path_global)) {
      final_data <- readRDS(final_data_path_global)
      cat(sprintf("[DEBUG] Loaded final_data from global path: %s (%d rows, %d cols)\n", 
                  final_data_path_global, nrow(final_data), ncol(final_data)))
    } else {
      return(list(success = FALSE, error = sprintf("final_data.rds not found in %s or %s. Please run step 03 first.", 
                                                     final_data_path_cohort, final_data_path_global)))
    }
    
    # Set up environment variables with defaults
    use_encoded <- Sys.getenv("USE_ENCODED", unset = "0")
    xgb_full_flag <- tolower(Sys.getenv("XGB_FULL", unset = "0")) %in% c("1", "true", "TRUE", "yes", "y")
    mc_cv <- tolower(Sys.getenv("MC_CV", unset = "1")) %in% c("1", "true", "TRUE", "yes", "y")
    
    # Ensure mc_cv is a logical value
    if (!is.logical(mc_cv)) {
      tryCatch({
        cat(sprintf("[WARNING] mc_cv is not logical, converting from: %s (class: %s)\n", 
                    mc_cv, class(mc_cv)))
      }, error = function(e) {
        cat(sprintf("[ERROR] Failed to print mc_cv warning: %s\n", e$message))
        cat(sprintf("[ERROR] mc_cv value: %s, type: %s\n", mc_cv, typeof(mc_cv)))
      })
      mc_cv <- as.logical(mc_cv)
    }
    
    # Additional safety check
    if (is.na(mc_cv)) {
      cat("[WARNING] mc_cv is NA, setting to TRUE (default)\n")
      mc_cv <- TRUE
    }
    
    # Extract model variables
    model_vars <- final_features$terms
    
    # Define hardcoded Wisotzkey features for consistency (must match 01_prepare_data.R)
    # NOTE: tx_mcsd has underscore - this is the derived column created by clean_phts()
    wisotzkey_features <- c(
      "prim_dx",           # Primary Etiology
      "tx_mcsd",           # MCSD at Transplant (with underscore - derived column!)
      "chd_sv",            # Single Ventricle CHD
      "hxsurg",            # Surgeries Prior to Listing
      "txsa_r",            # Serum Albumin at Transplant
      "txbun_r",           # BUN at Transplant
      "txecmo",            # ECMO at Transplant
      "txpl_year",         # Transplant Year
      "weight_txpl",       # Weight at Transplant
      "txalt",             # ALT at Transplant (cleaned name)
      "bmi_txpl",          # BMI at Transplant (created from weight/height)
      "pra_listing",       # PRA at Listing (created from lsfprat)
      "egfr_tx",           # eGFR at Transplant (created from creatinine)
      "hxmed",             # Medical History at Listing
      "listing_year"       # Listing Year (created from txpl_year)
    )
    
    # Check which Wisotzkey features are available in the data
    available_wisotzkey <- intersect(wisotzkey_features, colnames(final_data))
    missing_wisotzkey <- setdiff(wisotzkey_features, colnames(final_data))
    
    # Debug: Check missing_wisotzkey before sprintf
    cat(sprintf("[DEBUG] missing_wisotzkey type: %s, length: %d\n", typeof(missing_wisotzkey), length(missing_wisotzkey)))
    if (length(missing_wisotzkey) > 0) {
      cat(sprintf("[DEBUG] missing_wisotzkey[1] type: %s\n", typeof(missing_wisotzkey[1])))
      if (is.function(missing_wisotzkey[1])) {
        cat("[DEBUG] missing_wisotzkey[1] is a function!\n")
      }
    }
    # Protect against function objects in sprintf
    safe_missing <- if (is.character(missing_wisotzkey)) missing_wisotzkey else as.character(missing_wisotzkey)
    cat(sprintf("[WARNING] Missing Wisotzkey features: %s\n", paste(safe_missing, collapse = ", ")))
    
    cat(sprintf("[DEBUG] Wisotzkey features: %d available, %d missing\n", 
                length(available_wisotzkey), length(missing_wisotzkey)))
    
    # Define original_vars (non-encoded variables for ORSF/RSF/CPH)
    original_vars <- available_wisotzkey
    
    # Debug: Check original_vars before sprintf
    cat(sprintf("[DEBUG] original_vars type: %s, length: %d\n", typeof(original_vars), length(original_vars)))
    if (length(original_vars) > 0) {
      cat(sprintf("[DEBUG] original_vars[1] type: %s\n", typeof(original_vars[1])))
      if (is.function(original_vars[1])) {
        cat("[DEBUG] original_vars[1] is a function!\n")
      }
    }
    # Protect against function objects in sprintf
    safe_original <- if (is.character(original_vars)) original_vars else as.character(original_vars)
    cat(sprintf("[Progress] ORSF/RSF/CPH features: %s\n", paste(safe_original, collapse = ", ")))
    
    # Set up catboost_full_vars (all variables except time/status)
    catboost_full_vars <- setdiff(colnames(final_data), c("time", "status"))
    
    cat(sprintf("[DEBUG] Variables loaded: use_encoded=%s, xgb_full_flag=%s, mc_cv=%s\n", 
                use_encoded, xgb_full_flag, mc_cv))
    cat(sprintf("[DEBUG] mc_cv type: %s, class: %s, is.logical: %s\n", 
                typeof(mc_cv), paste(class(mc_cv), collapse=", "), is.logical(mc_cv)))
    
    # Load testing_rows from step 02 (cohort-specific or global)
    # Step 2 saves as 'resamples.rds', not 'testing_rows.rds'
    testing_rows_path_cohort <- file.path(here::here('model_data'), cohort_name, 'resamples.rds')
    testing_rows_path_global <- here::here('model_data', 'resamples.rds')
    testing_rows <- NULL
    
    if (file.exists(testing_rows_path_cohort)) {
      testing_rows <- readRDS(testing_rows_path_cohort)
      cat(sprintf("[DEBUG] Loaded resamples.rds from cohort-specific path: %s (%d splits)\n", 
                  testing_rows_path_cohort, length(testing_rows)))
    } else if (file.exists(testing_rows_path_global)) {
      testing_rows <- readRDS(testing_rows_path_global)
      cat(sprintf("[DEBUG] Loaded resamples.rds from global path: %s (%d splits)\n", 
                  testing_rows_path_global, length(testing_rows)))
    } else {
      cat("[DEBUG] resamples.rds not found in either cohort-specific or global path, will create MC-CV splits on the fly\n")
    }
    
    # Create MC-CV splits on the fly if needed (fallback for R version mismatch)
    if (is.null(testing_rows)) {
      # Create MC-CV splits on the fly (fallback for R version mismatch)
      prop <- as.numeric(Sys.getenv("MC_TEST_PROP", "0.2"))
      times <- as.integer(Sys.getenv("MC_TIMES", "25"))  # Default matches Step 2
      set.seed(as.integer(Sys.getenv("SEED", "42")))
      suppressPackageStartupMessages(library(rsample))
      cat("[DEBUG] About to call rsample::mc_cv...\n")
      mc_cv_splits <- rsample::mc_cv(final_data, times = times, prop = prop, strata = "status")
      cat("[DEBUG] Successfully created mc_cv_splits\n")
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
    
    return(list(
      success = TRUE,
      final_data = final_data,
      final_features = final_features,
      model_vars = model_vars,
      original_vars = original_vars,
      available_wisotzkey = available_wisotzkey,
      catboost_full_vars = catboost_full_vars,
      testing_rows = testing_rows,
      use_encoded = use_encoded,
      xgb_full_flag = xgb_full_flag,
      mc_cv = mc_cv,
      cohort_name = Sys.getenv("DATASET_COHORT", unset = "unknown")
    ))
    
  }, error = function(e) {
    return(list(success = FALSE, error = conditionMessage(e)))
  })
}

#' Fit final models in parallel
#' @param data_setup List containing data and configuration from setup_model_data()
#' @return List with success status and results
fit_final_models_parallel <- function(data_setup) {
  tryCatch({
    # Always use parallel model fitting for optimal performance
    cat("[DEBUG] ===== FITTING FINAL MODELS IN PARALLEL =====\n")
    cat(sprintf("[Progress] Dataset size: %d rows, %d variables\n", 
                nrow(data_setup$final_data), length(data_setup$model_vars)))
    flush.console()
    
    # Parallel execution with smart thread allocation
    suppressPackageStartupMessages({
      library(future)
      library(furrr)
    })
    
    # Configure parallel workers with conservative threading
    workers_env <- suppressWarnings(as.integer(Sys.getenv('FINAL_MODEL_WORKERS', unset = '0')))
    
    # Get actual physical cores (not limited by threading env vars)
    cores <- tryCatch({
      # Use parallel::detectCores() which reads /proc/cpuinfo directly
      parallel::detectCores(logical = TRUE)
    }, error = function(e) {
      warning("Could not detect cores, defaulting to 4")
      4L
    })
    
    if (!is.finite(workers_env) || workers_env < 1) {
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
    
    # Override parallelly's conservative core detection
    # Tell it to use actual physical cores, not threading limits
    options(parallelly.availableCores.system = cores)
    options(parallelly.maxWorkers.localhost = workers)
    
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
      list(model = "CatBoost", fit_func = "fit_catboost"),
      list(model = "XGB", fit_func = "fit_xgb"),
      list(model = "CPH", fit_func = "fit_cph")
    )
    
    # Parallel model fitting for optimal performance
    cat("[Progress] Starting parallel model fitting (ORSF + CatBoost + XGB + CPH simultaneously)...\n")
    cat(sprintf("[Progress] Individual model logs will be written to: logs/models/%s/full/\n", 
               data_setup$cohort_name))
    flush.console()
    
    # Parallel execution using furrr::future_map
    final_models <- furrr::future_map(model_tasks, function(task) {
      # Set up model-specific logging within worker
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
      }, silent = TRUE)
      
      # Load required packages in each worker
      library(aorsf)
      library(survival)
      library(riskRegression)
      library(glue)
      library(here)
      
      # Load CatBoost if available (it's loaded separately when needed)
      if (task$model == "CatBoost") {
        if (requireNamespace("catboost", quietly = TRUE)) {
          library(catboost)
        } else {
          stop("CatBoost package not available. Please install it first.")
        }
      }
      
      # Load required functions in each worker
      source(here::here("scripts", "R", "fit_orsf.R"))
      source(here::here("scripts", "R", "fit_catboost.R"))
      source(here::here("scripts", "R", "fit_cph.R"))
      source(here::here("scripts", "R", "safe_coxph.R"))
      source(here::here("scripts", "R", "fit_xgb.R"))
      source(here::here("scripts", "R", "utils", "model_utils.R"))  # Load parallel processing utilities
      
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
                      task$model, length(data_setup$original_vars), nrow(data_setup$final_data)), 
              file = model_log, append = TRUE), silent = TRUE)
      
      if (task$fit_func == "fit_orsf") {
        # Configure aorsf parallel processing with conservative threading
        aorsf_config <- configure_aorsf_parallel(
          use_all_cores = FALSE,
          n_thread = threads_per_worker,
          check_r_functions = TRUE,
          verbose = FALSE
        )
        
        model_result <- fit_orsf(trn = data_setup$final_data, vars = data_setup$original_vars, 
                                use_parallel = TRUE, check_r_functions = TRUE)
      } else if (task$fit_func == "fit_rsf") {
        # Configure ranger parallel processing with conservative threading
        ranger_config <- configure_ranger_parallel(
          use_all_cores = FALSE,
          num_threads = threads_per_worker,
          memory_efficient = FALSE,
          verbose = FALSE
        )
        
        model_result <- fit_rsf(trn = data_setup$final_data, vars = data_setup$original_vars, 
                               use_parallel = TRUE)
      } else if (task$fit_func == "fit_xgb") {
        # Configure XGBoost parallel processing with conservative threading
        xgb_config <- configure_xgboost_parallel(
          use_all_cores = FALSE,
          nthread = threads_per_worker,
          tree_method = 'auto',
          verbose = FALSE
        )
        
        # XGBoost needs encoded data, so we need to load it
        xgb_data_path <- here::here('model_data','final_data_encoded.rds')
        if (!file.exists(xgb_data_path)) {
          stop("Encoded dataset final_data_encoded.rds not found. Re-run step 03 before fitting XGB.")
        }
        xgb_trn <- readRDS(xgb_data_path)
        
        # Use encoded variables for XGBoost
        xgb_vars <- data_setup$final_features$terms  # encoded variable names
        
        model_result <- fit_xgb(trn = xgb_trn, vars = xgb_vars)
      } else if (task$fit_func == "fit_cph") {
        model_result <- fit_cph(trn = data_setup$final_data, vars = data_setup$original_vars, tst = NULL)
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
      } else if (task$model == "RSF") {
        model_path <- file.path(models_dir, 'model_rsf.rds')  # Cohort-specific path
      } else if (task$model == "XGB") {
        model_path <- file.path(models_dir, 'model_xgb.rds')  # Cohort-specific path
      } else if (task$model == "CPH") {
        model_path <- file.path(models_dir, 'model_cph.rds')  # Cohort-specific path
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
        final_data = data_setup$final_data, 
        original_vars = data_setup$original_vars,
        threads_per_worker = threads_per_worker,
        # Include parallel processing configuration functions
        configure_ranger_parallel = configure_ranger_parallel,
        configure_xgboost_parallel = configure_xgboost_parallel,
        configure_aorsf_parallel = configure_aorsf_parallel,
        configure_cph_parallel = configure_cph_parallel
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
    
    cat("[DEBUG] Final models fitted and saved successfully IN PARALLEL!\n")
    
    # Clean up parallel backend
    future::plan(future::sequential)
    cat("[Progress] Parallel backend cleaned up\n")
    
    return(list(
      success = TRUE,
      results = successful_models,
      final_orsf_path = final_orsf_path
    ))
    
  }, error = function(e) {
    # Clean up parallel backend in case of error
    tryCatch(future::plan(future::sequential), error = function(e2) NULL)
    
    cat(sprintf("[ERROR] Failed to fit final models: %s\n", conditionMessage(e)))
    if (grepl("timeout", conditionMessage(e), ignore.case = TRUE)) {
      cat("[ERROR] Model fitting timed out - likely too large for available resources\n")
    }
    
    return(list(
      success = FALSE,
      error = conditionMessage(e)
    ))
  })
}
