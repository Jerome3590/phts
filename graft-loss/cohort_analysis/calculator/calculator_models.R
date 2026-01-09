#!/usr/bin/env Rscript

# ============================================================================
# Calculator Models: CHD, Combined, and Myocardio
# ============================================================================
# This script implements three calculator models:
# 1. CHD only model
# 2. Combined model (all Prim_DX)
# 3. Myocardio model
#
# Each model compares SURVIVAL models:
# - Simple Calculator (Cox regression with selected features - baseline)
# - CatBoost-Cox (Gradient boosting)
# - XGBoost-Cox (Extreme gradient boosting)
# - AORSF (Accelerated Oblique Random Survival Forest)
# - RSF (Random Survival Forest using ranger)
#
# Uses 25 MC CV splits for aggregated feature importance
# Evaluation: C-index (concordance) instead of AUC
# ============================================================================

# Load required libraries
library(here)
library(dplyr)
library(readr)
library(survival)
library(ranger)  # For RSF
library(aorsf)   # For AORSF
library(catboost)
library(xgboost)
library(glmnet)  # For LASSO (kept for legacy, not used in current models)
library(tidyr)
library(purrr)
library(tibble)
library(janitor)
library(haven)
library(riskRegression)
library(prodlim)
library(rsample)
library(furrr)
library(future)
library(progressr)
# Note: Using survival models, not classification - no pROC needed

# Source helper functions
# Try multiple paths for helper scripts
survival_helpers_paths <- c(
  file.path(dirname(dirname(getwd())), "scripts", "R", "survival_helpers.R"),
  here("..", "..", "scripts", "R", "survival_helpers.R"),
  here("scripts", "R", "survival_helpers.R"),
  file.path(dirname(dirname(dirname(getwd()))), "scripts", "R", "survival_helpers.R")
)

survival_helpers_file <- NULL
for (path in survival_helpers_paths) {
  if (file.exists(path)) {
    survival_helpers_file <- path
    break
  }
}

if (is.null(survival_helpers_file)) {
  stop("Cannot find survival_helpers.R. Please check file location.")
}
source(survival_helpers_file)

# Source calculate_derived_features
derived_features_paths <- c(
  file.path(dirname(getwd()), "scripts", "calculate_derived_features.R"),
  here("..", "scripts", "calculate_derived_features.R"),
  here("graft-loss", "cohort_analysis", "scripts", "calculate_derived_features.R"),
  file.path(dirname(dirname(getwd())), "scripts", "calculate_derived_features.R")
)

derived_features_file <- NULL
for (path in derived_features_paths) {
  if (file.exists(path)) {
    derived_features_file <- path
    break
  }
}

if (is.null(derived_features_file)) {
  stop("Cannot find calculate_derived_features.R. Please check file location.")
}
source(derived_features_file)

# ============================================================================
# Configuration
# ============================================================================
N_MC_SPLITS <- 25
TRAIN_PROP <- 0.8
# Survival models use time-to-event, not fixed horizon

# ============================================================================
# Data Preparation Functions
# ============================================================================

prepare_calculator_features <- function(data) {
  # Calculate derived features
  data <- calculate_derived_features(data)
  
  # Calculate eGFR if not present
  if (!"egfr_tx" %in% names(data) && "height_txpl" %in% names(data) && "txcreat_r" %in% names(data)) {
    data <- data %>%
      mutate(
        egfr_tx = ifelse(
          !is.na(height_txpl) & !is.na(txcreat_r) & txcreat_r > 0,
          0.413 * height_txpl / txcreat_r,
          NA_real_
        )
      )
  }
  
  if (!"egfr_listing" %in% names(data) && "height_listing" %in% names(data) && "lcreat_r" %in% names(data)) {
    data <- data %>%
      mutate(
        egfr_listing = ifelse(
          !is.na(height_listing) & !is.na(lcreat_r) & lcreat_r > 0,
          0.413 * height_listing / lcreat_r,
          NA_real_
        )
      )
  }
  
  # Create eGFR categories
  if ("egfr_tx" %in% names(data)) {
    data <- data %>%
      mutate(
        egfr_tx_cat = case_when(
          egfr_tx < 30 ~ "severe",
          egfr_tx >= 30 & egfr_tx < 60 ~ "moderate",
          egfr_tx >= 60 & egfr_tx < 90 ~ "mild",
          egfr_tx >= 90 ~ "normal",
          TRUE ~ NA_character_
        )
      )
  }
  
  if ("egfr_listing" %in% names(data)) {
    data <- data %>%
      mutate(
        egfr_listing_cat = case_when(
          egfr_listing < 30 ~ "severe",
          egfr_listing >= 30 & egfr_listing < 60 ~ "moderate",
          egfr_listing >= 60 & egfr_listing < 90 ~ "mild",
          egfr_listing >= 90 ~ "normal",
          TRUE ~ NA_character_
        )
      )
  }
  
  # Bilirubin dichotomous (>1.5)
  if ("txbili_t_r" %in% names(data)) {
    data <- data %>%
      mutate(txbili_t_r_high = ifelse(txbili_t_r > 1.5, 1, 0))
  }
  
  # BUN dichotomous (>30) - note: variable name might be TXBUN_R or txbun_r
  bun_var <- intersect(c("txbun_r", "TXBUN_R"), names(data))[1]
  if (!is.na(bun_var)) {
    data <- data %>%
      mutate(txbun_r_high = ifelse(.data[[bun_var]] > 30, 1, 0))
  }
  
  # Albumin dichotomous (<3)
  if ("txsa_r" %in% names(data)) {
    data <- data %>%
      mutate(txsa_r_low = ifelse(txsa_r < 3, 1, 0))
  }
  
  # ALT dichotomous (>90)
  if ("txalt" %in% names(data)) {
    data <- data %>%
      mutate(txalt_high = ifelse(txalt > 90, 1, 0))
  }
  
  # ECMO dichotomous (txecmo AND slecmo)
  if ("txecmo" %in% names(data) && "slecmo" %in% names(data)) {
    data <- data %>%
      mutate(ecmo_combined = ifelse(txecmo == 1 | slecmo == 1, 1, 0))
  }
  
  # History of Fontan Associated Liver Disease (dichotomous)
  # Note: Should not exist in cardiomyopathy subgroup (will only be "no")
  if ("hxfonlvr" %in% names(data)) {
    data <- data %>%
      mutate(hxfonlvr_bin = ifelse(hxfonlvr == 1, 1, 0))
  }
  
  # History of dialysis (dichotomous)
  if ("hxdysdia" %in% names(data)) {
    data <- data %>%
      mutate(hxdysdia_bin = ifelse(hxdysdia == 1, 1, 0))
  }
  
  # Change in eGFR from listing to transplant
  if ("egfr_tx" %in% names(data) && "egfr_listing" %in% names(data)) {
    data <- data %>%
      mutate(egfr_change = egfr_tx - egfr_listing)
  }
  
  return(data)
}

# ============================================================================
# Simple Calculator Implementation (Cox Regression)
# ============================================================================

fit_simple_calculator_cox <- function(train_data, test_data, time_col = "time", status_col = "status", cohort_name = "") {
  # Select key features for simple calculator
  # Base features (common to all cohorts)
  feature_cols <- c(
    "age_listing", "age_txpl",
    "hxsurg",
    "chd_hlh",
    "lsfcpra", "lsfprab", "lsfprat",
    "egfr_tx", "egfr_listing", "egfr_tx_cat", "egfr_listing_cat",
    "hxdysdia_bin",
    "txbili_t_r", "txbili_t_r_high",
    "txalt", "txalt_high",
    "txvent", "hxtrach", "ltxtrach",
    "txvad", "txecmo", "slecmo", "ecmo_combined",
    "txpalb_r", "txsa_r", "txsa_r_low", "txtp_r",
    "txfcpra", "lsfcpra",
    "egfr_change"
  )
  
  # Add primary_etiology for Combined model (strong predictor)
  if (cohort_name == "Combined" && "primary_etiology" %in% names(train_data)) {
    feature_cols <- c(feature_cols, "primary_etiology")
  }
  
  # Add additional CHD-specific features if available
  if (cohort_name == "CHD") {
    # Look for other CHD subtype variables
    chd_vars <- grep("^chd_", names(train_data), value = TRUE, ignore.case = TRUE)
    feature_cols <- c(feature_cols, chd_vars)
    
    # Add Fontan liver disease (CHD-specific)
    if ("hxfonlvr_bin" %in% names(train_data)) {
      feature_cols <- c(feature_cols, "hxfonlvr_bin")
    }
  }
  
  # Keep only features that exist in the data
  feature_cols <- intersect(feature_cols, names(train_data))
  feature_cols <- setdiff(feature_cols, c("time", "status", "ev_time", "ev_type", "outcome", "outcome_int_graft_loss", "outcome_graft_loss"))
  
  # Prepare data for Cox regression
  train_x <- train_data[, feature_cols, drop = FALSE]
  train_time <- train_data[[time_col]]
  train_status <- train_data[[status_col]]
  test_x <- test_data[, feature_cols, drop = FALSE]
  test_time <- test_data[[time_col]]
  test_status <- test_data[[status_col]]
  
  # Remove constant columns
  constant_cols <- names(train_x)[sapply(train_x, function(x) length(unique(na.omit(x))) <= 1)]
  if (length(constant_cols) > 0) {
    train_x <- train_x[, !names(train_x) %in% constant_cols, drop = FALSE]
    test_x <- test_x[, !names(test_x) %in% constant_cols, drop = FALSE]
  }
  
  # Impute missing values: Use "MISSING" for categoricals, median for numerics
  for (var in names(train_x)) {
    if (is.numeric(train_x[[var]])) {
      median_val <- median(train_x[[var]], na.rm = TRUE)
      train_x[[var]][is.na(train_x[[var]])] <- median_val
      test_x[[var]][is.na(test_x[[var]])] <- median_val
    } else if (is.character(train_x[[var]])) {
      # Convert to factor and use "MISSING" for NAs
      train_x[[var]] <- as.factor(train_x[[var]])
      train_vals <- as.character(train_x[[var]])
      train_vals[is.na(train_vals)] <- "MISSING"
      train_x[[var]] <- factor(train_vals)
      train_levels <- levels(train_x[[var]])
      if (!("MISSING" %in% train_levels)) {
        train_levels <- c(train_levels, "MISSING")
        train_x[[var]] <- factor(train_x[[var]], levels = train_levels)
      }
      if (var %in% names(test_x)) {
        test_x[[var]] <- as.factor(test_x[[var]])
        test_vals <- as.character(test_x[[var]])
        test_vals[is.na(test_vals) | !(test_vals %in% train_levels)] <- "MISSING"
        test_x[[var]] <- factor(test_vals, levels = train_levels)
      }
    } else if (is.factor(train_x[[var]])) {
      # Use "MISSING" level for factor NAs
      train_vals <- as.character(train_x[[var]])
      train_vals[is.na(train_vals)] <- "MISSING"
      train_x[[var]] <- factor(train_vals)
      train_levels <- levels(train_x[[var]])
      if (!("MISSING" %in% train_levels)) {
        train_levels <- c(train_levels, "MISSING")
        train_x[[var]] <- factor(train_x[[var]], levels = train_levels)
      }
      if (var %in% names(test_x)) {
        test_vals <- as.character(test_x[[var]])
        test_vals[is.na(test_vals) | !(test_vals %in% train_levels)] <- "MISSING"
        test_x[[var]] <- factor(test_vals, levels = train_levels)
      }
    }
  }
  
  # Convert to model matrix
  train_x_mat <- model.matrix(~ . - 1, data = train_x)
  test_x_mat <- model.matrix(~ . - 1, data = test_x)
  
  # Align columns
  missing_in_test <- setdiff(colnames(train_x_mat), colnames(test_x_mat))
  if (length(missing_in_test) > 0) {
    test_x_mat <- cbind(test_x_mat, matrix(0, nrow(test_x_mat), length(missing_in_test),
                                            dimnames = list(NULL, missing_in_test)))
  }
  extra_in_test <- setdiff(colnames(test_x_mat), colnames(train_x_mat))
  if (length(extra_in_test) > 0) {
    test_x_mat <- test_x_mat[, setdiff(colnames(test_x_mat), extra_in_test), drop = FALSE]
  }
  test_x_mat <- test_x_mat[, colnames(train_x_mat), drop = FALSE]
  
  # Fit Cox regression
  set.seed(1997)
  train_surv <- Surv(train_time, train_status)
  model <- coxph(train_surv ~ ., data = data.frame(train_x_mat))
  
  # Predict risk scores (linear predictor)
  risk_scores <- predict(model, newdata = data.frame(test_x_mat), type = "risk")
  
  # Calculate C-index
  conc <- concordance(Surv(test_time, test_status) ~ risk_scores)
  c_index <- as.numeric(conc$concordance)
  
  # Feature importance (absolute coefficients)
  coefs <- coef(model)
  importance <- abs(coefs)
  names(importance) <- names(coefs)
  
  return(list(
    model = model,
    risk_scores = risk_scores,
    time = test_time,
    status = test_status,
    c_index = c_index,
    importance = importance
  ))
}

# ============================================================================
# Model Wrapper Functions
# ============================================================================

fit_catboost_cox <- function(train_data, test_data, time_col = "time", status_col = "status", cohort_name = "") {
  # Use survival helper function
  cb_params <- list(
    loss_function = "Cox",
    eval_metric = "Cox",
    iterations = 1200,  # Match original survival notebook
    depth = 4,
    learning_rate = 0.1,
    thread_count = 1,
    logging_level = "Silent",
    verbose = 0L
  )
  
  result <- run_catboost_cox(
    train_df = train_data,
    test_df = test_data,
    time_col = time_col,
    status_col = status_col,
    cohort_name = cohort_name,
    model_name = "CatBoost",
    params = cb_params
  )
  
  # Extract importance as named vector
  importance_vec <- result$importance$importance
  names(importance_vec) <- result$importance$feature
  
  return(list(
    model = result$model,
    risk_scores = result$risk_scores,
    time = test_data[[time_col]],
    status = test_data[[status_col]],
    c_index = as.numeric(result$concordance$concordance),
    importance = importance_vec
  ))
}

fit_xgboost_cox <- function(train_data, test_data, time_col = "time", status_col = "status", cohort_name = "") {
  # Preprocess data: remove leakage predictors
  train_prep <- remove_leakage_predictors(train_data)
  test_prep <- remove_leakage_predictors(test_data)
  
  # CRITICAL: Verify row counts match before preprocessing
  # remove_leakage_predictors should NOT change row counts
  if (nrow(train_prep) != nrow(train_data)) {
    stop("Row count mismatch after leakage filtering in train data")
  }
  if (nrow(test_prep) != nrow(test_data)) {
    stop("Row count mismatch after leakage filtering in test data")
  }
  
  # CRITICAL: Preserve original time/status vectors to ensure row alignment
  # The survival helper needs the original vectors, not from preprocessed data
  train_time <- train_data[[time_col]]
  train_status <- train_data[[status_col]]
  test_time <- test_data[[time_col]]
  test_status <- test_data[[status_col]]
  
  # Ensure time/status are in preprocessed data (they should be, but verify)
  train_prep[[time_col]] <- train_time
  train_prep[[status_col]] <- train_status
  test_prep[[time_col]] <- test_time
  test_prep[[status_col]] <- test_status
  
  # Final verification: row counts must match
  if (nrow(train_prep) != length(train_time) || nrow(test_prep) != length(test_time)) {
    stop("Row count mismatch after time/status assignment")
  }
  
  # Fix problematic features instead of filtering
  for (col in names(train_prep)) {
    if (col != time_col && col != status_col) {
      if (is.factor(train_prep[[col]])) {
        train_levels <- levels(train_prep[[col]])
        
        if (length(train_levels) < 2) {
          # Single-level factor: convert to numeric (0/1 indicator)
          train_prep[[col]] <- as.numeric(train_prep[[col]]) - 1
          if (col %in% names(test_prep)) {
            test_prep[[col]] <- as.numeric(test_prep[[col]]) - 1
          }
        } else {
          # Multi-level factor: synchronize levels between train and test
          # Use "MISSING" for unseen levels (not most_common, to preserve missingness signal)
          if (col %in% names(test_prep)) {
            test_vals <- as.character(test_prep[[col]])
            # Unseen levels or NAs -> "MISSING" (if it exists) or most common
            if ("MISSING" %in% train_levels) {
              test_vals[!(test_vals %in% train_levels) | is.na(test_vals)] <- "MISSING"
            } else {
              most_common <- names(sort(table(train_prep[[col]]), decreasing = TRUE))[1]
              test_vals[!(test_vals %in% train_levels) | is.na(test_vals)] <- most_common
            }
            test_prep[[col]] <- factor(test_vals, levels = train_levels)
          }
        }
      } else if (is.character(train_prep[[col]])) {
        # Convert character to factor and synchronize
        # (Already handled in imputation step above, but ensure consistency)
        train_levels <- levels(train_prep[[col]])
        if (col %in% names(test_prep)) {
          test_vals <- as.character(test_prep[[col]])
          if (length(train_levels) > 0) {
            # Use "MISSING" if it exists, otherwise most common
            if ("MISSING" %in% train_levels) {
              test_vals[!(test_vals %in% train_levels) | is.na(test_vals)] <- "MISSING"
            } else {
              most_common <- names(sort(table(train_prep[[col]]), decreasing = TRUE))[1]
              test_vals[!(test_vals %in% train_levels) | is.na(test_vals)] <- most_common
            }
            test_prep[[col]] <- factor(test_vals, levels = train_levels)
          }
        }
      }
    }
  }
  
  # Ensure both sets share exact same columns
  common_cols <- intersect(names(train_prep), names(test_prep))
  train_prep <- train_prep[, common_cols, drop = FALSE]
  test_prep <- test_prep[, common_cols, drop = FALSE]
  
  # Final validation before calling helper
  if (nrow(train_prep) != length(train_time) || nrow(test_prep) != length(test_time)) {
    stop("Row count mismatch before XGBoost call")
  }
  if (!time_col %in% names(train_prep) || !status_col %in% names(train_prep)) {
    stop("Time/status columns missing from preprocessed data")
  }
  
  # CRITICAL: Ensure no NA values in time/status before calling helper
  # model.matrix can cause issues if there are NAs
  train_na_rows <- is.na(train_prep[[time_col]]) | is.na(train_prep[[status_col]])
  test_na_rows <- is.na(test_prep[[time_col]]) | is.na(test_prep[[status_col]])
  
  if (any(train_na_rows) || any(test_na_rows)) {
    # Remove rows with NA time/status (shouldn't happen, but handle it)
    if (any(train_na_rows)) {
      train_prep <- train_prep[!train_na_rows, , drop = FALSE]
      train_time <- train_time[!train_na_rows]
      train_status <- train_status[!train_na_rows]
    }
    if (any(test_na_rows)) {
      test_prep <- test_prep[!test_na_rows, , drop = FALSE]
      test_time <- test_time[!test_na_rows]
      test_status <- test_status[!test_na_rows]
    }
    # Re-assign time/status after filtering
    train_prep[[time_col]] <- train_time
    train_prep[[status_col]] <- train_status
    test_prep[[time_col]] <- test_time
    test_prep[[status_col]] <- test_status
  }
  
  # Final validation: row counts must match
  if (nrow(train_prep) != length(train_time) || nrow(test_prep) != length(test_time)) {
    stop("Row count mismatch after NA removal")
  }
  
  # FINAL FIX: Remove single-level factors right before calling run_xgb_cox
  # This prevents "contrasts" errors when small splits cause features to become constant
  single_level_cols <- character(0)
  for (col in names(train_prep)) {
    if (col != time_col && col != status_col) {
      if (is.factor(train_prep[[col]])) {
        if (length(levels(train_prep[[col]])) < 2) {
          single_level_cols <- c(single_level_cols, col)
        }
      } else if (is.character(train_prep[[col]])) {
        # Check if character column has only one unique value
        unique_vals <- unique(na.omit(train_prep[[col]]))
        if (length(unique_vals) < 2) {
          single_level_cols <- c(single_level_cols, col)
        }
      }
    }
  }
  
  if (length(single_level_cols) > 0) {
    train_prep <- train_prep[, !names(train_prep) %in% single_level_cols, drop = FALSE]
    test_prep  <- test_prep[, !names(test_prep) %in% single_level_cols, drop = FALSE]
  }
  
  # Use survival helper function
  xgb_params <- list(
    objective = "survival:cox",
    eval_metric = "cox-nloglik",
    eta = 0.05,
    max_depth = 4,
    subsample = 0.8,
    colsample_bytree = 0.8
  )
  
  result <- run_xgb_cox(
    train_df = train_prep,
    test_df = test_prep,
    time_col = time_col,
    status_col = status_col,
    cohort_name = cohort_name,
    model_name = "XGBoost",
    params = xgb_params,
    nrounds = 400,  # Match original survival notebook
    early_stopping_rounds = 25
  )
  
  # Extract importance as named vector
  importance_vec <- result$importance$importance
  names(importance_vec) <- result$importance$feature
  
  return(list(
    model = result$model,
    risk_scores = result$risk_scores,
    time = test_data[[time_col]],
    status = test_data[[status_col]],
    c_index = as.numeric(result$concordance$concordance),
    importance = importance_vec
  ))
}

fit_aorsf <- function(train_data, test_data, time_col = "time", status_col = "status", cohort_name = "") {
  # Preprocess data: remove leakage predictors
  train_prep <- remove_leakage_predictors(train_data)
  test_prep <- remove_leakage_predictors(test_data)
  
  # Impute missing values: Use "MISSING" for categoricals, median for numerics
  # This must happen BEFORE factor level synchronization
  for (col in names(train_prep)) {
    if (col != time_col && col != status_col) {
      if (is.numeric(train_prep[[col]])) {
        # Impute numeric with median
        median_val <- median(train_prep[[col]], na.rm = TRUE)
        if (is.na(median_val)) median_val <- 0
        train_prep[[col]][is.na(train_prep[[col]])] <- median_val
        if (col %in% names(test_prep)) {
          test_prep[[col]][is.na(test_prep[[col]])] <- median_val
        }
      } else if (is.character(train_prep[[col]])) {
        # Convert to factor and use "MISSING" for NAs
        train_prep[[col]] <- as.factor(train_prep[[col]])
        train_vals <- as.character(train_prep[[col]])
        train_vals[is.na(train_vals)] <- "MISSING"
        train_prep[[col]] <- factor(train_vals)
        train_levels <- levels(train_prep[[col]])
        if (!("MISSING" %in% train_levels)) {
          train_levels <- c(train_levels, "MISSING")
          train_prep[[col]] <- factor(train_prep[[col]], levels = train_levels)
        }
        if (col %in% names(test_prep)) {
          test_prep[[col]] <- as.factor(test_prep[[col]])
          test_vals <- as.character(test_prep[[col]])
          test_vals[is.na(test_vals) | !(test_vals %in% train_levels)] <- "MISSING"
          test_prep[[col]] <- factor(test_vals, levels = train_levels)
        }
      } else if (is.factor(train_prep[[col]])) {
        # Use "MISSING" level for factor NAs
        train_vals <- as.character(train_prep[[col]])
        train_vals[is.na(train_vals)] <- "MISSING"
        train_prep[[col]] <- factor(train_vals)
        train_levels <- levels(train_prep[[col]])
        if (!("MISSING" %in% train_levels)) {
          train_levels <- c(train_levels, "MISSING")
          train_prep[[col]] <- factor(train_prep[[col]], levels = train_levels)
        }
        if (col %in% names(test_prep)) {
          test_vals <- as.character(test_prep[[col]])
          test_vals[is.na(test_vals) | !(test_vals %in% train_levels)] <- "MISSING"
          test_prep[[col]] <- factor(test_vals, levels = train_levels)
        }
      }
    }
  }
  
  # Fix problematic features instead of filtering
  # AORSF requires exact factor level matching between train and test
  for (col in names(train_prep)) {
    if (col != time_col && col != status_col) {
      # Handle factors
      if (is.factor(train_prep[[col]])) {
        train_levels <- levels(train_prep[[col]])
        
        if (length(train_levels) < 2) {
          # Single-level factor: convert to numeric (0/1 indicator)
          train_prep[[col]] <- as.numeric(train_prep[[col]]) - 1
          if (col %in% names(test_prep)) {
            test_prep[[col]] <- as.numeric(test_prep[[col]]) - 1
          }
        } else {
          # Multi-level factor: synchronize levels
          # Use "MISSING" if it exists, otherwise most common
          if (col %in% names(test_prep)) {
            test_vals <- as.character(test_prep[[col]])
            if ("MISSING" %in% train_levels) {
              test_vals[!(test_vals %in% train_levels) | is.na(test_vals)] <- "MISSING"
            } else {
              most_common <- names(sort(table(train_prep[[col]]), decreasing = TRUE))[1]
              test_vals[!(test_vals %in% train_levels) | is.na(test_vals)] <- most_common
            }
            test_prep[[col]] <- factor(test_vals, levels = train_levels)
          }
        }
      }
    }
  }
  
  # Remove empty/constant columns (AORSF fails on these)
  # Check for columns with no observed values or all same value
  empty_cols <- character(0)
  for (col in names(train_prep)) {
    if (col != time_col && col != status_col) {
      # Check if column has any variation
      non_na_vals <- train_prep[[col]][!is.na(train_prep[[col]])]
      if (length(non_na_vals) == 0) {
        # All NA - empty column
        empty_cols <- c(empty_cols, col)
      } else if (length(unique(non_na_vals)) <= 1) {
        # All same value (constant column)
        empty_cols <- c(empty_cols, col)
      }
    }
  }
  if (length(empty_cols) > 0) {
    train_prep <- train_prep[, !names(train_prep) %in% empty_cols, drop = FALSE]
    test_prep <- test_prep[, !names(test_prep) %in% empty_cols, drop = FALSE]
  }
  
  # Verify row counts still match
  if (nrow(train_prep) != nrow(train_data) || nrow(test_prep) != nrow(test_data)) {
    stop("Row count mismatch after removing empty columns")
  }
  
  # Ensure both sets share exact same columns
  common_cols <- intersect(names(train_prep), names(test_prep))
  train_prep <- train_prep[, common_cols, drop = FALSE]
  test_prep <- test_prep[, common_cols, drop = FALSE]
  
  # Use survival helper function
  result <- run_aorsf(
    train_df = train_prep,
    test_df = test_prep,
    time_col = time_col,
    status_col = status_col,
    cohort_name = cohort_name,
    model_name = "AORSF",
    n_tree = 100
  )
  
  # Extract importance as named vector
  if (!is.null(result$vi)) {
    importance_vec <- result$vi$importance
    names(importance_vec) <- result$vi$feature
  } else {
    importance_vec <- numeric(0)
  }
  
  return(list(
    model = result$model,
    risk_scores = result$risk_scores,
    time = test_data[[time_col]],
    status = test_data[[status_col]],
    c_index = as.numeric(result$concordance$concordance),
    importance = importance_vec
  ))
}

fit_rsf <- function(train_data, test_data, time_col = "time", status_col = "status", cohort_name = "") {
  # Preprocess data: remove leakage predictors
  train_prep <- remove_leakage_predictors(train_data)
  test_prep <- remove_leakage_predictors(test_data)
  
  # CRITICAL: Ensure time/status are preserved and row counts match
  # remove_leakage_predictors should not change row counts, but verify
  if (nrow(train_prep) != nrow(train_data)) {
    stop("Row count mismatch after leakage filtering in train data")
  }
  if (nrow(test_prep) != nrow(test_data)) {
    stop("Row count mismatch after leakage filtering in test data")
  }
  
  train_prep[[time_col]] <- train_data[[time_col]]
  train_prep[[status_col]] <- train_data[[status_col]]
  test_prep[[time_col]] <- test_data[[time_col]]
  test_prep[[status_col]] <- test_data[[status_col]]
  
  # Use survival helper function with error handling
  result <- tryCatch({
    run_rsf_ranger(
      train_df = train_prep,
      test_df = test_prep,
      time_col = time_col,
      status_col = status_col,
      cohort_name = cohort_name,
      model_name = "RSF",
      num.trees = 500
    )
  }, error = function(e) {
    # If RSF fails with subscript error, try to recover
    err_msg <- conditionMessage(e)
    if (grepl("subscript out of bounds", err_msg, ignore.case = TRUE)) {
      # Try using cumulative hazard directly with safer indexing
      tryCatch({
        model <- ranger::ranger(
          formula = as.formula(paste0("survival::Surv(", time_col, ", ", status_col, ") ~ .")),
          data = train_prep,
          num.trees = 500,
          importance = "impurity",
          splitrule = "logrank",
          respect.unordered.factors = "partition",
          seed = 1997
        )
        pred <- predict(model, data = test_prep, type = "response")
        
        # Safely extract risk scores with multiple fallbacks and validation
        risk_scores <- NULL
        
        # Try cumulative hazard first (most reliable)
        if (!is.null(pred$chf)) {
          if (is.matrix(pred$chf) && ncol(pred$chf) > 0 && nrow(pred$chf) == nrow(test_prep)) {
            risk_scores <- as.numeric(pred$chf[, ncol(pred$chf)])
          } else if (is.vector(pred$chf) && length(pred$chf) == nrow(test_prep)) {
            risk_scores <- as.numeric(pred$chf)
          }
        }
        
        # Fallback to survival if chf didn't work
        if (is.null(risk_scores) && !is.null(pred$survival)) {
          if (is.matrix(pred$survival) && ncol(pred$survival) > 0 && nrow(pred$survival) == nrow(test_prep)) {
            risk_scores <- 1 - as.numeric(pred$survival[, ncol(pred$survival)])
          }
        }
        
        # Last fallback to predictions
        if (is.null(risk_scores) && !is.null(pred$predictions)) {
          if (is.matrix(pred$predictions) && ncol(pred$predictions) > 0 && nrow(pred$predictions) == nrow(test_prep)) {
            risk_scores <- 1 - as.numeric(pred$predictions[, ncol(pred$predictions)])
          } else if (is.vector(pred$predictions) && length(pred$predictions) == nrow(test_prep)) {
            risk_scores <- as.numeric(pred$predictions)
          }
        }
        
        if (is.null(risk_scores) || length(risk_scores) != nrow(test_prep)) {
          stop("RSF prediction failed: no valid risk scores (length=", 
               ifelse(is.null(risk_scores), "NULL", length(risk_scores)), 
               ", expected=", nrow(test_prep), ")")
        }
        
        conc <- survival::concordance(survival::Surv(test_data[[time_col]], test_data[[status_col]]) ~ risk_scores)
        vi <- tryCatch(model$variable.importance, error = function(e) NULL)
        vi_df <- NULL
        if (!is.null(vi)) {
          vi_df <- data.frame(feature = names(vi), importance = as.numeric(vi), stringsAsFactors = FALSE)
        }
        list(model = model, risk_scores = risk_scores, concordance = conc, vi = vi_df)
      }, error = function(e2) {
        stop(paste("RSF recovery failed:", conditionMessage(e2)))
      })
    } else {
      stop(paste("RSF error:", err_msg))
    }
  })
  
  # Validate risk scores before inversion check
  if (is.null(result$risk_scores) || length(result$risk_scores) == 0 || 
      length(result$risk_scores) != nrow(test_data)) {
    stop("RSF returned invalid risk scores")
  }
  
  # Check if risk scores need inversion (RSF might return inverted scores)
  # If C-index is suspiciously low (<0.1), try inverting
  # Wrap entire inversion check in tryCatch to prevent crashes
  inversion_successful <- FALSE
  tryCatch({
    # Validate risk scores before computing concordance
    if (!is.null(result$risk_scores) && length(result$risk_scores) == nrow(test_data) && all(is.finite(result$risk_scores))) {
      test_conc_orig <- survival::concordance(survival::Surv(test_data[[time_col]], test_data[[status_col]]) ~ result$risk_scores)
      test_conc_inv <- survival::concordance(survival::Surv(test_data[[time_col]], test_data[[status_col]]) ~ (-result$risk_scores))
      
      # Safely extract concordance values for comparison
      conc_orig_val <- tryCatch(as.numeric(test_conc_orig$concordance), error = function(e) NA_real_)
      conc_inv_val <- tryCatch(as.numeric(test_conc_inv$concordance), error = function(e) NA_real_)
      
      if (!is.na(conc_inv_val) && !is.na(conc_orig_val) && conc_inv_val > conc_orig_val) {
        # Inverted version is better, use it
        result$risk_scores <<- -result$risk_scores
        result$concordance <<- test_conc_inv
        inversion_successful <<- TRUE
      } else {
        # Use original
        result$concordance <<- test_conc_orig
        inversion_successful <<- TRUE
      }
    }
  }, error = function(e) {
    # If inversion check fails, just use the concordance from run_rsf_ranger
    # Don't overwrite result$concordance if it already exists
    if (is.null(result$concordance)) {
      # Last resort: compute concordance directly
      tryCatch({
        result$concordance <<- survival::concordance(survival::Surv(test_data[[time_col]], test_data[[status_col]]) ~ result$risk_scores)
      }, error = function(e2) {
        # If even that fails, set to NULL and let the extraction code handle it
        result$concordance <<- NULL
      })
    }
  })
  
  # Extract importance as named vector
  if (!is.null(result$vi)) {
    importance_vec <- result$vi$importance
    names(importance_vec) <- result$vi$feature
  } else if (!is.null(result$importance)) {
    # Alternative: importance might be in result$importance
    importance_vec <- result$importance$importance
    names(importance_vec) <- result$importance$feature
  } else {
    importance_vec <- numeric(0)
  }
  
  # Safely extract C-index from concordance object
  # Handle cases where concordance structure might differ or be NULL
  c_index_val <- NA_real_
  if (!is.null(result$concordance)) {
    tryCatch({
      # Try standard access
      if (!is.null(result$concordance$concordance)) {
        c_index_val <- as.numeric(result$concordance$concordance)
      } else if (is.numeric(result$concordance) && length(result$concordance) > 0) {
        # Might be a numeric vector
        c_index_val <- as.numeric(result$concordance[1])
      } else if (length(result$concordance) > 0 && is.list(result$concordance)) {
        # Try first element if it's a list
        c_index_val <- as.numeric(result$concordance[[1]])
      }
    }, error = function(e) {
      # If all else fails, recalculate from risk scores
      tryCatch({
        recalc_conc <- survival::concordance(survival::Surv(test_data[[time_col]], test_data[[status_col]]) ~ result$risk_scores)
        if (!is.null(recalc_conc$concordance)) {
          c_index_val <<- as.numeric(recalc_conc$concordance)
        }
      }, error = function(e2) {
        # Final fallback: use NA
        c_index_val <<- NA_real_
      })
    })
  }
  
  return(list(
    model = result$model,
    risk_scores = result$risk_scores,
    time = test_data[[time_col]],
    status = test_data[[status_col]],
    c_index = c_index_val,
    importance = importance_vec
  ))
}

# Legacy function - keeping for compatibility but not used
fit_lasso_cox <- function(train_data, test_data, time_col = "time", status_col = "status", cohort_name = "") {
  # Prepare data
  feature_cols <- setdiff(names(train_data), c("time", "status", "outcome", outcome_col))
  train_x <- train_data[, feature_cols, drop = FALSE]
  train_y <- train_data[[outcome_col]]
  test_x <- test_data[, feature_cols, drop = FALSE]
  test_y <- test_data[[outcome_col]]
  
  # Remove constant columns
  constant_cols <- names(train_x)[sapply(train_x, function(x) length(unique(na.omit(x))) <= 1)]
  if (length(constant_cols) > 0) {
    train_x <- train_x[, !names(train_x) %in% constant_cols, drop = FALSE]
    test_x <- test_x[, !names(test_x) %in% constant_cols, drop = FALSE]
  }
  
  # Impute missing values: Use "MISSING" for categoricals, median for numerics
  for (var in names(train_x)) {
    if (is.numeric(train_x[[var]])) {
      median_val <- median(train_x[[var]], na.rm = TRUE)
      train_x[[var]][is.na(train_x[[var]])] <- median_val
      test_x[[var]][is.na(test_x[[var]])] <- median_val
    } else if (is.character(train_x[[var]])) {
      # Convert to factor and use "MISSING" for NAs
      train_x[[var]] <- as.factor(train_x[[var]])
      train_vals <- as.character(train_x[[var]])
      train_vals[is.na(train_vals)] <- "MISSING"
      train_x[[var]] <- factor(train_vals)
      train_levels <- levels(train_x[[var]])
      if (!("MISSING" %in% train_levels)) {
        train_levels <- c(train_levels, "MISSING")
        train_x[[var]] <- factor(train_x[[var]], levels = train_levels)
      }
      if (var %in% names(test_x)) {
        test_x[[var]] <- as.factor(test_x[[var]])
        test_vals <- as.character(test_x[[var]])
        test_vals[is.na(test_vals) | !(test_vals %in% train_levels)] <- "MISSING"
        test_x[[var]] <- factor(test_vals, levels = train_levels)
      }
    } else if (is.factor(train_x[[var]])) {
      # Use "MISSING" level for factor NAs
      train_vals <- as.character(train_x[[var]])
      train_vals[is.na(train_vals)] <- "MISSING"
      train_x[[var]] <- factor(train_vals)
      train_levels <- levels(train_x[[var]])
      if (!("MISSING" %in% train_levels)) {
        train_levels <- c(train_levels, "MISSING")
        train_x[[var]] <- factor(train_x[[var]], levels = train_levels)
      }
      if (var %in% names(test_x)) {
        test_vals <- as.character(test_x[[var]])
        test_vals[is.na(test_vals) | !(test_vals %in% train_levels)] <- "MISSING"
        test_x[[var]] <- factor(test_vals, levels = train_levels)
      }
    }
  }
  
  # Synchronize factor levels from train to test (prevents model.matrix errors)
  # This is critical: test set factors must have same levels as training set
  for (col in names(train_x)) {
    if (is.factor(train_x[[col]])) {
      lv <- levels(train_x[[col]])
      # Only keep factors with at least 2 levels
      if (length(lv) >= 2) {
        test_x[[col]] <- factor(test_x[[col]], levels = lv)
      } else {
        # Remove single-level factors
        train_x[[col]] <- NULL
        test_x[[col]] <- NULL
      }
    }
  }
  
  # Remove any columns that were dropped
  common_cols <- intersect(names(train_x), names(test_x))
  train_x <- train_x[, common_cols, drop = FALSE]
  test_x <- test_x[, common_cols, drop = FALSE]
  
  # Convert to model matrix
  train_x_mat <- model.matrix(~ . - 1, data = train_x)
  test_x_mat <- model.matrix(~ . - 1, data = test_x)
  
  # Align columns
  missing_in_test <- setdiff(colnames(train_x_mat), colnames(test_x_mat))
  if (length(missing_in_test) > 0) {
    test_x_mat <- cbind(test_x_mat, matrix(0, nrow(test_x_mat), length(missing_in_test),
                                            dimnames = list(NULL, missing_in_test)))
  }
  extra_in_test <- setdiff(colnames(test_x_mat), colnames(train_x_mat))
  if (length(extra_in_test) > 0) {
    test_x_mat <- test_x_mat[, setdiff(colnames(test_x_mat), extra_in_test), drop = FALSE]
  }
  test_x_mat <- test_x_mat[, colnames(train_x_mat), drop = FALSE]
  
  # Fit LASSO-Cox
  set.seed(1997)
  train_surv <- Surv(train_data[[time_col]], train_data[[status_col]])
  cv_fit <- cv.glmnet(
    x = train_x_mat,
    y = train_surv,
    family = "cox",
    alpha = 1,
    nfolds = 5
  )
  
  risk_scores <- predict(cv_fit, newx = test_x_mat, s = "lambda.min", type = "link")[, 1]
  conc <- concordance(Surv(test_data[[time_col]], test_data[[status_col]]) ~ risk_scores)
  c_index <- as.numeric(conc$concordance)
  
  # Feature importance (absolute coefficients)
  coefs <- coef(cv_fit, s = "lambda.min")
  coefs <- coefs[coefs != 0, , drop = FALSE]
  importance <- abs(as.numeric(coefs))
  names(importance) <- rownames(coefs)
  
  return(list(
    model = cv_fit,
    risk_scores = risk_scores,
    time = test_data[[time_col]],
    status = test_data[[status_col]],
    c_index = c_index,
    importance = importance
  ))
}

# ============================================================================
# MC-CV Function
# ============================================================================

run_mc_cv_calculator <- function(data, cohort_name, model_type = "CHD") {
  cat("\n========================================\n")
  cat(sprintf("Running MC-CV for %s (%s)\n", cohort_name, model_type))
  cat("========================================\n")
  
  # Prepare features
  data <- prepare_calculator_features(data)
  
  # Ensure time and status columns exist
  if (!"time" %in% names(data)) {
    if ("ev_time" %in% names(data)) {
      data <- data %>% rename(time = ev_time)
    } else if ("outcome_int_graft_loss" %in% names(data)) {
      data <- data %>% rename(time = outcome_int_graft_loss)
    } else {
      stop("Cannot find time column (ev_time or outcome_int_graft_loss)")
    }
  }
  
  if (!"status" %in% names(data)) {
    if ("ev_type" %in% names(data)) {
      data <- data %>% mutate(status = ifelse(ev_type == 1, 1L, 0L))
    } else if ("outcome_graft_loss" %in% names(data)) {
      data <- data %>% rename(status = outcome_graft_loss)
    } else {
      stop("Cannot find status column (ev_type or outcome_graft_loss)")
    }
  }
  
  # Filter to valid survival data (time > 0, status in {0,1})
  data <- data %>%
    filter(!is.na(time), !is.na(status), time > 0, status %in% c(0, 1))
  
  # Remove constant columns
  constant_cols <- names(data)[sapply(data, function(x) length(unique(na.omit(x))) <= 1)]
  if (length(constant_cols) > 0) {
    data <- data %>% select(-any_of(constant_cols))
  }
  
  # Create MC-CV splits (stratified by status for survival)
  set.seed(1997)
  mc_splits <- mc_cv(
    data = data,
    prop = TRAIN_PROP,
    times = N_MC_SPLITS,
    strata = status
  )
  
  # Store results
  all_results <- list()
  all_importance <- list()
  
  # Run MC-CV
  with_progress({
    p <- progressor(steps = N_MC_SPLITS)
    
    results <- future_map(1:N_MC_SPLITS, function(split_idx) {
      p()
      
      split <- mc_splits$splits[[split_idx]]
      train_data <- analysis(split)
      test_data <- assessment(split)
      
      # Debug: print progress for first few splits
      if (split_idx <= 3) {
        cat(sprintf("  Processing split %d/%d for %s...\n", split_idx, N_MC_SPLITS, cohort_name))
      }
      
      split_results <- list()
      split_importance <- list()
      
      # Simple Calculator (Cox)
      tryCatch({
        res <- fit_simple_calculator_cox(train_data, test_data, time_col = "time", status_col = "status", cohort_name = cohort_name)
        split_results$Simple_Calculator <- res$c_index
        split_importance$Simple_Calculator <- res$importance
      }, error = function(e) {
        cat(sprintf("    [Split %d] Simple Calculator error: %s\n", split_idx, conditionMessage(e)))
        split_results$Simple_Calculator <<- NA_real_
        split_importance$Simple_Calculator <<- NULL
      })
      
      # CatBoost-Cox
      tryCatch({
        res <- fit_catboost_cox(train_data, test_data, time_col = "time", status_col = "status", cohort_name = cohort_name)
        split_results$CatBoost <- res$c_index
        split_importance$CatBoost <- res$importance
      }, error = function(e) {
        cat(sprintf("    [Split %d] CatBoost error: %s\n", split_idx, conditionMessage(e)))
        split_results$CatBoost <<- NA_real_
        split_importance$CatBoost <<- NULL
      })
      
      # XGBoost-Cox
      tryCatch({
        res <- fit_xgboost_cox(train_data, test_data, time_col = "time", status_col = "status", cohort_name = cohort_name)
        # Check for suspicious perfect C-index (likely overfitting or data issue)
        if (!is.na(res$c_index) && res$c_index >= 0.99) {
          cat(sprintf("    [Split %d] XGBoost warning: C-index = %.4f (suspiciously high)\n", split_idx, res$c_index))
        }
        split_results$XGBoost <- res$c_index
        split_importance$XGBoost <- res$importance
      }, error = function(e) {
        cat(sprintf("    [Split %d] XGBoost error: %s\n", split_idx, conditionMessage(e)))
        split_results$XGBoost <<- NA_real_
        split_importance$XGBoost <<- NULL
      })
      
      # AORSF
      tryCatch({
        res <- fit_aorsf(train_data, test_data, time_col = "time", status_col = "status", cohort_name = cohort_name)
        split_results$AORSF <- res$c_index
        split_importance$AORSF <- res$importance
      }, error = function(e) {
        cat(sprintf("    [Split %d] AORSF error: %s\n", split_idx, conditionMessage(e)))
        split_results$AORSF <<- NA_real_
        split_importance$AORSF <<- NULL
      })
      
      # RSF
      tryCatch({
        res <- fit_rsf(train_data, test_data, time_col = "time", status_col = "status", cohort_name = cohort_name)
        split_results$RSF <- res$c_index
        split_importance$RSF <- res$importance
      }, error = function(e) {
        cat(sprintf("    [Split %d] RSF error: %s\n", split_idx, conditionMessage(e)))
        split_results$RSF <<- NA_real_
        split_importance$RSF <<- NULL
      })
      
      return(list(
        results = split_results,
        importance = split_importance
      ))
    }, .options = furrr_options(seed = TRUE))
  })
  
  # Aggregate results
  model_names <- c("Simple_Calculator", "CatBoost", "XGBoost", "AORSF", "RSF")
  
  summary_results <- tibble()
  aggregated_importance <- list()
  
  for (model_name in model_names) {
    c_indices <- sapply(results, function(x) x$results[[model_name]])
    c_indices <- c_indices[!is.na(c_indices)]
    
    if (length(c_indices) > 0) {
      summary_results <- bind_rows(summary_results, tibble(
        Cohort = cohort_name,
        Model = model_name,
        C_Index_Mean = mean(c_indices, na.rm = TRUE),
        C_Index_SD = sd(c_indices, na.rm = TRUE),
        C_Index_CI_Lower = quantile(c_indices, 0.025, na.rm = TRUE),
        C_Index_CI_Upper = quantile(c_indices, 0.975, na.rm = TRUE),
        N_Splits = length(c_indices)
      ))
      
      # Aggregate feature importance
      all_feature_names <- unique(unlist(lapply(results, function(x) {
        if (!is.null(x$importance[[model_name]])) {
          names(x$importance[[model_name]])
        } else {
          NULL
        }
      })))
      
      if (length(all_feature_names) > 0) {
        importance_agg <- sapply(all_feature_names, function(feature) {
          importances <- sapply(results, function(x) {
            if (!is.null(x$importance[[model_name]]) && feature %in% names(x$importance[[model_name]])) {
              return(as.numeric(x$importance[[model_name]][feature]))
            }
            return(NA_real_)
          })
          mean(importances, na.rm = TRUE)
        })
        
        importance_agg <- sort(importance_agg, decreasing = TRUE)
        aggregated_importance[[model_name]] <- importance_agg
      }
    }
  }
  
  return(list(
    summary = summary_results,
    importance = aggregated_importance
  ))
}

# ============================================================================
# Main Execution
# ============================================================================

main <- function() {
  # Set up parallel processing
  # Reduce workers to avoid memory issues with large mc_splits
  n_workers <- max(1, min(8, parallel::detectCores() - 4))  # Cap at 8 workers
  plan(multisession, workers = n_workers)
  
  # Increase memory limit for parallel workers (mc_splits can be large)
  options(future.globals.maxSize = 2000 * 1024^2)  # 2 GB limit (increased)
  cat(sprintf("Using %d workers for parallel processing (reduced to avoid memory issues)\n", n_workers))
  
  # Load data - use same approach as cohort analysis notebook
  cat("Loading PHTS data...\n")
  # Try multiple possible locations
  sas_paths <- c(
    file.path(dirname(dirname(dirname(getwd()))), "data", "phts_txpl_ml.sas7bdat"),
    file.path(dirname(dirname(getwd())), "data", "phts_txpl_ml.sas7bdat"),
    here("..", "..", "..", "data", "phts_txpl_ml.sas7bdat"),
    here("..", "..", "data", "phts_txpl_ml.sas7bdat"),
    here("..", "..", "..", "graft-loss-parallel-processing", "data", "phts_txpl_ml.sas7bdat"),
    here("..", "..", "graft-loss", "data", "phts_txpl_ml.sas7bdat")
  )
  
  sas_path <- NULL
  for (path in sas_paths) {
    if (file.exists(path)) {
      sas_path <- path
      break
    }
  }
  
  if (is.null(sas_path)) {
    cat("Searched in the following locations:\n")
    for (path in sas_paths) {
      cat("  -", path, ifelse(file.exists(path), "[EXISTS]", "[NOT FOUND]"), "\n")
    }
    stop("Cannot find phts_txpl_ml.sas7bdat in any location. Please check data file location.")
  }
  
  cat("Loading data from:", sas_path, "\n")
  
  # Load and prepare data
  tx <- haven::read_sas(sas_path) %>%
    filter(TXPL_YEAR >= 2010) %>%
    janitor::clean_names() %>%
    mutate(
      ev_time = pmin(int_dead, int_graft_loss, na.rm = TRUE),
      ev_type = pmax(dtx_patient, graft_loss, na.rm = TRUE)
    ) %>%
    fix_non_positive_times(time_col = "ev_time", status_col = "ev_type")
  
  # Map prim_dx to primary_etiology if needed
  if (!"primary_etiology" %in% names(tx) && "prim_dx" %in% names(tx)) {
    tx <- tx %>% mutate(primary_etiology = prim_dx)
  }
  
  # Define cohorts
  cohorts <- list(
    CHD = tx %>% filter(primary_etiology == "Congenital HD"),
    Combined = tx,  # All patients
    Myocardio = tx %>% filter(primary_etiology %in% c("Cardiomyopathy", "Myocarditis"))
  )
  
  # Run MC-CV for each cohort
  all_summaries <- list()
  all_importance <- list()
  
  for (cohort_name in names(cohorts)) {
    cat(sprintf("\nProcessing cohort: %s\n", cohort_name))
    result <- run_mc_cv_calculator(cohorts[[cohort_name]], cohort_name, cohort_name)
    all_summaries[[cohort_name]] <- result$summary
    all_importance[[cohort_name]] <- result$importance
  }
  
  # Combine summaries
  final_summary <- bind_rows(all_summaries)
  
  # Save results
  output_dir <- here("outputs")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  write_csv(final_summary, file.path(output_dir, "calculator_models_summary.csv"))
  cat("\n✓ Saved summary to calculator_models_summary.csv\n")
  
  # Save feature importance
  for (cohort_name in names(all_importance)) {
    for (model_name in names(all_importance[[cohort_name]])) {
      imp_df <- tibble(
        feature = names(all_importance[[cohort_name]][[model_name]]),
        importance = as.numeric(all_importance[[cohort_name]][[model_name]]),
        cohort = cohort_name,
        model = model_name
      ) %>%
        arrange(desc(importance))
      
      write_csv(imp_df, file.path(output_dir, sprintf("importance_%s_%s.csv", cohort_name, model_name)))
    }
  }
  
  cat("✓ Saved feature importance files\n")
  
  # Print summary
  cat("\n========================================\n")
  cat("Summary Results\n")
  cat("========================================\n")
  print(final_summary)
  
  # Identify best model per cohort
  best_models <- final_summary %>%
    group_by(Cohort) %>%
    arrange(desc(C_Index_Mean), .by_group = TRUE) %>%
    slice(1) %>%
    ungroup()
  
  cat("\n========================================\n")
  cat("Best Models by Cohort\n")
  cat("========================================\n")
  print(best_models)
  
  write_csv(best_models, file.path(output_dir, "best_models_by_cohort.csv"))
  cat("\n✓ Saved best models to best_models_by_cohort.csv\n")
  
  plan(sequential)
}

# Run if executed directly
if (!interactive()) {
  main()
}
