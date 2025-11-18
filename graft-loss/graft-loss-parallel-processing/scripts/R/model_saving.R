# ===================
# MODEL SAVING AND INDEXING MODULE
# ===================
# This module handles model saving, comparison indexing, and result management.

#' Save model results and create comparison index
#' @param results List of successful model results from parallel fitting
#' @param cohort_name The cohort name for file paths
#' @return List with success status and details
save_model_results <- function(results, cohort_name) {
  tryCatch({
    # Write a comparison index for single-fit case; empty in MC mode
    if (!exists("cmp")) {
      cmp <- data.frame(
        model = character(0), file = character(0), use_encoded = integer(0),
        timestamp = character(0), stringsAsFactors = FALSE
      )
    }
    
    # Update comparison index to include successful models
    if (length(results) > 0) {
      cmp_rows <- list()
      for (model_name in names(results)) {
        result <- results[[model_name]]
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
    
    # Save model comparison index to cohort-specific location
    cmp_dir <- here::here('models', cohort_name)
    dir.create(cmp_dir, showWarnings = FALSE, recursive = TRUE)
    readr::write_csv(cmp, file.path(cmp_dir, 'model_comparison_index.csv'))
    message(sprintf("Saved: models/%s/model_comparison_index.csv", cohort_name))
    
    # Log model creation summary
    cat("\n")
    cat(paste(rep("=", 60), collapse = ""))
    cat("\n[SUMMARY] Model Fitting Results:\n")
    for (model_name in names(results)) {
      result <- results[[model_name]]
      if (result$success) {
        cat(sprintf("  ✓ %s: SUCCESS (%.2f mins)\n", model_name, result$elapsed_mins))
      } else {
        cat(sprintf("  ✗ %s: FAILED - %s\n", model_name, result$error))
      }
    }
    
    return(list(
      success = TRUE,
      message = "Model results saved successfully",
      comparison_index = cmp,
      saved_models = length(results)
    ))
    
  }, error = function(e) {
    cat(sprintf("[ERROR] Failed to save model results: %s\n", conditionMessage(e)))
    return(list(
      success = FALSE,
      error = conditionMessage(e)
    ))
  })
}

#' Handle CatBoost model fitting (optional)
#' @param data_setup List containing data and configuration from setup_model_data()
#' @param results Existing results list to append to
#' @return Updated results list
handle_catboost_fitting <- function(data_setup, results) {
  tryCatch({
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
          all_idx <- seq_len(nrow(data_setup$final_data))
          trn_idx <- setdiff(all_idx, test_idx_vec)
          tst_idx <- test_idx_vec
          message(sprintf("Using resamples.rds first split: train=%d, test=%d", length(trn_idx), length(tst_idx)))
        }
      }
      if (is.null(trn_idx) || is.null(tst_idx)) {
        set.seed(42)
        n <- nrow(data_setup$final_data)
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
      cb_vars <- data_setup$available_wisotzkey
      message(sprintf('CatBoost: using hardcoded Wisotzkey features (%d variables)', length(cb_vars)))
      
      # Protect against function objects in sprintf
      safe_cb_vars <- if (is.character(cb_vars)) cb_vars else as.character(cb_vars)
      message(sprintf('CatBoost features: %s', paste(safe_cb_vars, collapse = ", ")))
      
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
      
      # Protect against function objects in sprintf
      safe_train_cols <- if (is.character(colnames(trn_df))) colnames(trn_df) else as.character(colnames(trn_df))
      safe_test_cols <- if (is.character(colnames(tst_df))) colnames(tst_df) else as.character(colnames(tst_df))
      cat(sprintf("[DEBUG]   Train columns: %s\n", paste(safe_train_cols, collapse = ", ")))
      cat(sprintf("[DEBUG]   Test columns: %s\n", paste(safe_test_cols, collapse = ", ")))
      
      # Check for potential issues
      common_cols <- intersect(colnames(trn_df), colnames(tst_df))
      train_only <- setdiff(colnames(trn_df), colnames(tst_df))
      test_only <- setdiff(colnames(tst_df), colnames(trn_df))
      
      if (length(train_only) > 0) {
        # Protect against function objects in sprintf
        safe_train_only <- if (is.character(train_only)) train_only else as.character(train_only)
        cat(sprintf("[WARNING] Train-only columns: %s\n", paste(safe_train_only, collapse = ", ")))
      }
      if (length(test_only) > 0) {
        # Protect against function objects in sprintf
        safe_test_only <- if (is.character(test_only)) test_only else as.character(test_only)
        cat(sprintf("[WARNING] Test-only columns: %s\n", paste(safe_test_only, collapse = ", ")))
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
          use_encoded = ifelse(nzchar(data_setup$use_encoded) && data_setup$use_encoded %in% c("1","true","TRUE"), 1L, 0L),
          timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          stringsAsFactors = FALSE
        )
        results[["CatBoost"]] <- list(
          model_name = "CatBoost",
          success = TRUE,
          model_path = pred_file,
          elapsed_mins = NA
        )
      }
    }
    
    return(results)
    
  }, error = function(e) {
    cat(sprintf("[ERROR] CatBoost fitting failed: %s\n", conditionMessage(e)))
    return(results)  # Return original results if CatBoost fails
  })
}

#' Create model comparison index
#' @param results List of model results
#' @param cohort_name The cohort name
#' @param use_encoded Whether encoded variables were used
#' @return Data frame with comparison index
create_model_comparison_index <- function(results, cohort_name, use_encoded) {
  tryCatch({
    # Build model comparison index with cohort-specific paths
    cmp <- data.frame(
      model = c("ORSF","RSF"),
      file = c(file.path("models", cohort_name, "model_orsf.rds"),
               file.path("models", cohort_name, "model_rsf.rds")),
      use_encoded = ifelse(nzchar(use_encoded) && use_encoded %in% c("1","true","TRUE"), 1L, 0L),
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      stringsAsFactors = FALSE
    )
    
    # Add XGB if it exists
    if ("XGB" %in% names(results)) {
      cmp <- dplyr::bind_rows(cmp, data.frame(
        model = "XGB",
        file = file.path("models", cohort_name, "model_xgb.rds"),
        use_encoded = 1L,  # XGB always uses encoded inputs now
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        stringsAsFactors = FALSE
      ))
    }
    
    # Add CPH if it exists
    if ("CPH" %in% names(results)) {
      cmp <- dplyr::bind_rows(cmp, data.frame(
        model = "CPH",
        file = file.path("models", cohort_name, "model_cph.rds"),
        use_encoded = 0L,  # CPH uses original variables
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        stringsAsFactors = FALSE
      ))
    }
    
    # Add CatBoost if it exists
    if ("CatBoost" %in% names(results)) {
      cmp <- dplyr::bind_rows(cmp, data.frame(
        model = "CatBoostPy",
        file = file.path('data','models','catboost','catboost_model.cbm'),
        use_encoded = ifelse(nzchar(use_encoded) && use_encoded %in% c("1","true","TRUE"), 1L, 0L),
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        stringsAsFactors = FALSE
      ))
    }
    
    return(cmp)
    
  }, error = function(e) {
    cat(sprintf("[ERROR] Failed to create comparison index: %s\n", conditionMessage(e)))
    return(data.frame(
      model = character(0), file = character(0), use_encoded = integer(0),
      timestamp = character(0), stringsAsFactors = FALSE
    ))
  })
}
