##' Fit CatBoost survival model using Python integration
##'
##' This function integrates with the Python CatBoost implementation for survival analysis
##' using signed-time labels as a proxy for survival modeling.
##'
##' @param trn Training data frame with time, status, and predictor variables
##' @param vars Character vector of predictor variable names to use
##' @param tst Test data frame (optional, defaults to NULL)
##' @param predict_horizon Time horizon for predictions (not used in CatBoost implementation)
##' @param use_parallel Whether to use parallel processing (CatBoost handles this internally)
##' @param iterations Number of boosting iterations (default: 2000)
##' @param depth Tree depth (default: 6)
##' @param learning_rate Learning rate (default: 0.05)
##' @param l2_leaf_reg L2 regularization (default: 3.0)
##' @param cat_cols Character vector of categorical column names (auto-detected if NULL)
##' @return List containing model path, predictions, and metadata
##' @title Fit CatBoost Survival Model

fit_catboost <- function(trn, vars = NULL, tst = NULL, predict_horizon = NULL, 
                        use_parallel = TRUE, iterations = 2000, depth = 6, 
                        learning_rate = 0.05, l2_leaf_reg = 3.0, cat_cols = NULL) {
  
  # DEBUG: Capture function call to diagnose "all arguments must be named" error
  cat("\n[CATBOOST_DEBUG] ========== FUNCTION CALL DEBUG ==========\n")
  cat("[CATBOOST_DEBUG] match.call():\n")
  print(match.call())
  cat("\n[CATBOOST_DEBUG] Arguments passed:\n")
  cat(sprintf("  trn: %s (%d rows, %d cols)\n", class(trn)[1], nrow(trn), ncol(trn)))
  cat(sprintf("  vars: %s (length: %d)\n", if(is.null(vars)) "NULL" else "character", if(is.null(vars)) 0 else length(vars)))
  cat(sprintf("  tst: %s\n", if(is.null(tst)) "NULL" else sprintf("%s (%d rows)", class(tst)[1], nrow(tst))))
  cat(sprintf("  predict_horizon: %s\n", if(is.null(predict_horizon)) "NULL" else predict_horizon))
  cat(sprintf("  use_parallel: %s\n", use_parallel))
  cat(sprintf("  iterations: %d\n", iterations))
  cat(sprintf("  depth: %d\n", depth))
  cat(sprintf("  learning_rate: %.3f\n", learning_rate))
  cat(sprintf("  l2_leaf_reg: %.3f\n", l2_leaf_reg))
  cat(sprintf("  cat_cols: %s\n", if(is.null(cat_cols)) "NULL" else paste(cat_cols, collapse=", ")))
  cat("[CATBOOST_DEBUG] =========================================\n\n")
  
  # ENHANCED LOGGING: Log initial data diagnostics for MC-CV debugging
  predictor_vars <- if (!is.null(vars)) vars else setdiff(names(trn), c('time', 'status'))
  
  cat(sprintf("[CATBOOST_INIT] Starting CatBoost model with %d observations, %d predictors\n", 
              nrow(trn), length(predictor_vars)))
  cat(sprintf("[CATBOOST_INIT] Events: %d (%.1f%%), Censored: %d (%.1f%%)\n", 
              sum(trn$status), 100 * mean(trn$status), 
              sum(1 - trn$status), 100 * (1 - mean(trn$status))))
  cat(sprintf("[CATBOOST_INIT] Events per predictor ratio: %.2f (recommended: >10)\n", 
              sum(trn$status) / length(predictor_vars)))
  
  # Check for potential MC-CV issues
  potential_issues <- character(0)
  
  for (var in predictor_vars) {
    if (var %in% names(trn)) {
      if (is.numeric(trn[[var]])) {
        var_sd <- sd(trn[[var]], na.rm = TRUE)
        if (is.finite(var_sd) && var_sd < 1e-10) {
          potential_issues <- c(potential_issues, sprintf("%s (zero variance)", var))
        }
      } else if (is.factor(trn[[var]]) || is.character(trn[[var]])) {
        var_table <- table(trn[[var]], useNA = "ifany")
        if (length(var_table) == 1) {
          potential_issues <- c(potential_issues, sprintf("%s (single level)", var))
        } else if (any(var_table < 5)) {
          small_levels <- names(var_table)[var_table < 5]
          potential_issues <- c(potential_issues, sprintf("%s (small levels: %s)", var, paste(small_levels, collapse = ",")))
        }
      }
    }
  }
  
  if (length(potential_issues) > 0) {
    cat(sprintf("[CATBOOST_INIT] Potential MC-CV issues detected in %d variables:\n", length(potential_issues)))
    for (issue in potential_issues) {
      cat(sprintf("[CATBOOST_INIT] - %s\n", issue))
    }
  } else {
    cat("[CATBOOST_INIT] No obvious MC-CV data issues detected\n")
  }
  
  # Configure CatBoost parallel processing
  if (use_parallel) {
    # Check for environment variable overrides
    env_threads <- suppressWarnings(as.integer(Sys.getenv("CATBOOST_MAX_THREADS", unset = "0")))
    if (is.finite(env_threads) && env_threads > 0) {
      # CatBoost threading is handled internally, but we can set CPU limit
      cat(sprintf("[CATBOOST_CONFIG] Using %d threads (from CATBOOST_MAX_THREADS)\n", env_threads))
    } else {
      cat("[CATBOOST_CONFIG] Using CatBoost default threading\n")
    }
  }
  
  # Prepare data for CatBoost
  cat(sprintf("[CATBOOST_DEBUG] tst parameter: %s\n", if(is.null(tst)) "NULL" else sprintf("data.frame with %d rows", nrow(tst))))
  if (is.null(tst)) {
    # Create a simple train/test split for validation
    cat("[CATBOOST_DEBUG] Creating internal train/test split (tst was NULL)\n")
    set.seed(42)  # Reproducible split
    test_idx <- sample(nrow(trn), size = floor(0.2 * nrow(trn)))
    train_data <- trn[-test_idx, ]
    test_data <- trn[test_idx, ]
  } else {
    cat("[CATBOOST_DEBUG] Using provided test data (tst was provided)\n")
    train_data <- trn
    test_data <- tst
  }
  cat(sprintf("[CATBOOST_DEBUG] Final train_data: %d rows, test_data: %d rows\n", nrow(train_data), nrow(test_data)))
  
  # Select only specified variables plus time and status
  if (!is.null(vars)) {
    required_cols <- c("time", "status", vars)
    train_data <- train_data[, required_cols, drop = FALSE]
    test_data <- test_data[, required_cols, drop = FALSE]
  }
  
  # Auto-detect categorical columns if not specified
  if (is.null(cat_cols)) {
    cat_cols <- names(train_data)[sapply(train_data, function(x) is.factor(x) || is.character(x))]
    cat_cols <- setdiff(cat_cols, c("time", "status"))  # Exclude outcome variables
  }
  
  # Use persistent CSV files for CatBoost (CSV-first approach)
  # Create data directory for CatBoost CSV files
  csv_data_dir <- here::here("model_data", "catboost_csv")
  dir.create(csv_data_dir, showWarnings = FALSE, recursive = TRUE)
  
  # Create unique filenames for this split/run
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  split_id <- Sys.getenv("CURRENT_SPLIT_ID", unset = "1")
  
  train_file <- file.path(csv_data_dir, sprintf("catboost_train_split%s_%s.csv", split_id, timestamp))
  test_file <- file.path(csv_data_dir, sprintf("catboost_test_split%s_%s.csv", split_id, timestamp))
  output_dir <- file.path(csv_data_dir, sprintf("catboost_output_split%s_%s", split_id, timestamp))
  
  # Ensure output directory exists
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  
  # Write data to persistent CSV files (CatBoost primary format)
  cat(sprintf("[CATBOOST_CSV] Writing training data to: %s\n", train_file))
  write.csv(train_data, train_file, row.names = FALSE, na = "")
  cat(sprintf("[CATBOOST_CSV] Writing test data to: %s\n", test_file))
  write.csv(test_data, test_file, row.names = FALSE, na = "")
  
  # Find Python script
  python_script <- here::here("scripts", "py", "catboost_survival.py")
  if (!file.exists(python_script)) {
    stop("CatBoost Python script not found: ", python_script)
  }
  
  # Build command - try multiple Python installations
  # Check for EC2-specific environment variable first
  python_cmd <- Sys.getenv("PYTHON_CMD", unset = "")
  if (python_cmd == "") {
    python_cmd <- Sys.getenv("EC2_PYTHON_PATH", unset = "")
  }
  
  # If PYTHON_CMD not set, try to find Python
  if (python_cmd == "") {
    # Check for common Python installations, including EC2 jupyter environments
    python_candidates <- c(
      "/home/pgx3874/jupyter-env/bin/python3",  # EC2 jupyter environment
      "/home/pgx3874/jupyter-env/bin/python",   # EC2 jupyter environment
      "python3", "python", "python3.11"
    )
    python_cmd <- ""
    
    for (candidate in python_candidates) {
      # Check if command exists using multiple methods
      found <- FALSE
      
      # Method 1: Check if file exists (for absolute paths)
      if (grepl("^/", candidate) && file.exists(candidate)) {
        found <- TRUE
      }
      
      # Method 2: which command (for commands in PATH)
      if (!found) {
        which_result <- tryCatch({
          suppressWarnings(system(paste("which", candidate), intern = TRUE))
        }, error = function(e) character(0))
        status <- attr(which_result, "status")
        # which returns 0 on success, NULL if status not set (also success), non-zero on failure
        if (length(which_result) > 0 && (is.null(status) || status == 0)) {
          found <- TRUE
        }
      }
      
      # Method 4: try to run python --version
      if (!found) {
        version_result <- tryCatch({
          suppressWarnings(system(paste(candidate, "--version"), intern = TRUE))
        }, error = function(e) NULL)
        if (!is.null(version_result) && length(version_result) > 0) {
          found <- TRUE
        }
      }
      
      if (found) {
        python_cmd <- candidate
        cat(sprintf("[CATBOOST_PYTHON] Found Python at: %s\n", python_cmd))
        break
      }
    }
    
    if (python_cmd == "") {
      stop("Python not found. Please install Python or set PYTHON_CMD environment variable.")
    }
  }
  
  cat(sprintf("[CATBOOST_PYTHON] Using Python command: %s\n", python_cmd))
  cat_cols_str <- if (length(cat_cols) > 0) paste(cat_cols, collapse = ",") else ""
  
  # Build command arguments properly for system2
  cmd_args <- c(
    python_script,
    "--train", train_file,
    "--test", test_file,
    "--time-col", "time",
    "--status-col", "status",
    "--outdir", output_dir
  )
  
  if (nchar(cat_cols_str) > 0) {
    cmd_args <- c(cmd_args, "--cat-cols", cat_cols_str)
  }
  
  # Convert to proper format for system2
  cmd_string <- paste(c(python_cmd, cmd_args), collapse = " ")
  
  cat(sprintf("[CATBOOST_EXEC] Running CatBoost with %d iterations, depth %d, lr %.3f\n", 
              iterations, depth, learning_rate))
  cat(sprintf("[CATBOOST_EXEC] Categorical columns: %s\n", 
              if (length(cat_cols) > 0) paste(cat_cols, collapse = ", ") else "none"))
  
  # Execute Python script with improved error handling
  tryCatch({
    # Use system() instead of system2 to avoid argument naming issues
    cat(sprintf("[CATBOOST_CMD] Executing: %s\n", cmd_string))
    result <- system(cmd_string, intern = TRUE)
    
    # Check if result contains error indicators
    if (is.character(result) && any(grepl("Error|Exception|Traceback", result, ignore.case = TRUE))) {
      cat("[CATBOOST_ERROR] Python script failed with errors:\n")
      cat("[CATBOOST_ERROR] Command:", cmd_string, "\n")
      cat("[CATBOOST_ERROR] Output:\n")
      cat(paste(result, collapse = "\n"), "\n")
      
      # Provide specific error guidance
      if (any(grepl("ModuleNotFoundError.*catboost", result, ignore.case = TRUE))) {
        stop("CatBoost not installed. Run: pip install catboost")
      } else if (any(grepl("MemoryError", result, ignore.case = TRUE))) {
        stop("Insufficient memory for CatBoost training. Try reducing dataset size.")
      } else if (any(grepl("FileNotFoundError|command not found", result, ignore.case = TRUE))) {
        stop("Python executable not found. Try setting PYTHON_CMD environment variable to 'python3' or install Python.")
      } else {
        stop("CatBoost Python script execution failed. Check output above for details.")
      }
    }
    
    cat("[CATBOOST_SUCCESS] CatBoost training completed successfully\n")
    
    # Log Python output for debugging (first few lines only)
    if (length(result) > 0) {
      debug_output <- head(result, 5)
      cat("[CATBOOST_DEBUG] Python output (first 5 lines):\n")
      cat(paste(debug_output, collapse = "\n"), "\n")
    }
    
  }, error = function(e) {
    cat(sprintf("[CATBOOST_ERROR] Failed to execute CatBoost: %s\n", e$message))
    
    # Additional debugging information
    cat(sprintf("[CATBOOST_DEBUG] Python command: %s\n", python_cmd))
    cat(sprintf("[CATBOOST_DEBUG] Working directory: %s\n", getwd()))
    cat(sprintf("[CATBOOST_DEBUG] Train file exists: %s\n", file.exists(train_file)))
    cat(sprintf("[CATBOOST_DEBUG] Test file exists: %s\n", file.exists(test_file)))
    cat(sprintf("[CATBOOST_DEBUG] Python script exists: %s\n", file.exists(python_script)))
    
    stop("CatBoost execution failed: ", e$message)
  })
  
  # Read results
  summary_file <- file.path(output_dir, "catboost_summary.json")
  if (file.exists(summary_file)) {
    summary <- jsonlite::fromJSON(summary_file)
    cat(sprintf("[CATBOOST_RESULTS] Model trained on %d samples, tested on %d samples\n", 
                summary$n_train, summary$n_test))
    cat(sprintf("[CATBOOST_RESULTS] Used %d features, %d categorical\n", 
                summary$n_features, length(summary$cat_features)))
  } else {
    summary <- list(
      model_file = file.path(output_dir, "catboost_model.cbm"),
      pred_file = file.path(output_dir, "catboost_predictions.csv"),
      imp_file = file.path(output_dir, "catboost_importance.csv"),
      n_train = nrow(train_data),
      n_test = nrow(test_data),
      n_features = length(predictor_vars),
      cat_features = cat_cols
    )
  }
  
  # Keep CSV files for CatBoost (CSV-first approach) - no cleanup
  cat(sprintf("[CATBOOST_CSV] Preserved training data: %s\n", train_file))
  cat(sprintf("[CATBOOST_CSV] Preserved test data: %s\n", test_file))
  cat(sprintf("[CATBOOST_CSV] Output directory: %s\n", output_dir))
  
  # Return model information (CSV-first approach)
  result <- list(
    model_path = summary$model_file,
    predictions_path = summary$pred_file,
    importance_path = summary$imp_file,
    # CSV data files (primary format for CatBoost)
    train_csv_path = train_file,
    test_csv_path = test_file,
    csv_data_dir = csv_data_dir,
    summary = summary,
    output_dir = output_dir,
    variables = predictor_vars,
    categorical_variables = cat_cols,
    hyperparameters = list(
      iterations = iterations,
      depth = depth,
      learning_rate = learning_rate,
      l2_leaf_reg = l2_leaf_reg
    )
  )
  
  class(result) <- c("catboost_survival", "list")
  return(result)
}
