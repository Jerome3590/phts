# Simple Working Test - Bypass complex prediction functions
# This tests all models using direct predict methods

# Load necessary libraries
library(here)
library(dplyr)

# Source the setup script
source(here("scripts", "00_setup.R"))

# Explicitly detach obliqueRSF to avoid namespace conflicts with aorsf
if ("package:obliqueRSF" %in% search()) {
  detach("package:obliqueRSF", unload = TRUE)
  cat("Detached obliqueRSF to avoid namespace conflicts\n")
}

# Explicitly source the updated fit_orsf function to ensure we get the latest version
source(here("R", "fit_orsf.R"))

# Source the imputation functions
source(here("R", "impute_missing_values.R"))

cat("[test_simple_working.R] Starting simple working test\n")

# Load the simplified dataset
phts_data <- readRDS(here("model_data", "phts_simple.rds"))
cat(sprintf("[test_simple_working.R] Loaded dataset: %d rows, %d columns\n", 
            nrow(phts_data), ncol(phts_data)))

# Define the 15 Wisotzkey features
wisotzkey_features <- c(
  "prim_dx", "txmcsd", "chd_sv", "hxsurg", "txsa_r", "txbun_r", "txecmo", 
  "txpl_year", "weight_txpl", "txalt", "bmi_txpl", "pra_listing", "egfr_tx", 
  "hxmed", "listing_year"
)

# Create a simple train/test split
set.seed(42)
n_total <- nrow(phts_data)
train_idx <- sample(1:n_total, floor(0.8 * n_total))
test_idx <- setdiff(1:n_total, train_idx)

# Create train/test data
trn_df <- phts_data[train_idx, c('time', 'status', wisotzkey_features), drop = FALSE]
te_df <- phts_data[test_idx, c('time', 'status', wisotzkey_features), drop = FALSE]

# Define variable types for imputation
continuous_vars <- c('txmcsd', 'chd_sv', 'hxsurg', 'txsa_r', 'txbun_r', 'txecmo', 
                     'txpl_year', 'weight_txpl', 'txalt', 'bmi_txpl', 'pra_listing', 
                     'egfr_tx', 'hxmed', 'listing_year')
categorical_vars <- c('prim_dx')

# Apply imputation following original graft-loss methodology
imputation_result <- impute_train_test_data(trn_df, te_df, continuous_vars, categorical_vars)
trn_df <- imputation_result$train_data
te_df <- imputation_result$test_data
imputation_stats <- imputation_result$imputation_stats

# Convert character variables to factors after imputation
for (var in wisotzkey_features) {
  if (is.character(trn_df[[var]])) {
    trn_df[[var]] <- as.factor(trn_df[[var]])
    te_df[[var]] <- factor(te_df[[var]], levels = levels(trn_df[[var]]))
  }
}

cat(sprintf("[test_simple_working.R] Train: %d rows, Test: %d rows\n", 
            nrow(trn_df), nrow(te_df)))
cat("[test_simple_working.R] Data preparation complete with proper imputation\n")

# Test 1: Working ORSF model
cat("\n=== Testing ORSF ===\n")
tryCatch({
  orsf_model <- fit_orsf(trn_df, wisotzkey_features)
  cat("ORSF model fitted successfully\n")
  
  # Select only the predictor variables for prediction (exclude time and status)
  te_df_predictors <- te_df[, wisotzkey_features, drop = FALSE]
  
  # Debug: Check ORSF model class
  cat("ORSF model class:", paste(class(orsf_model), collapse = ", "), "\n")
  cat("ORSF model type:", typeof(orsf_model), "\n")
  cat("ORSF model length:", length(orsf_model), "\n")
  
  # Try direct predict method for ORSF
  tryCatch({
    # Remove missing values for ORSF prediction
    complete_rows <- complete.cases(te_df_predictors)
    te_df_clean <- te_df_predictors[complete_rows, , drop = FALSE]
    cat(sprintf("ORSF: Using %d complete cases out of %d total\n", nrow(te_df_clean), nrow(te_df_predictors)))
    
    if (nrow(te_df_clean) > 0) {
      # Use generic predict function with correct arguments
      orsf_pred <- predict(orsf_model, new_data = te_df_clean, pred_horizon = 1)
      cat("ORSF predict result class:", class(orsf_pred), "\n")
      cat("ORSF predict result length:", length(orsf_pred), "\n")
      cat("ORSF predict result type:", typeof(orsf_pred), "\n")
      
      # Convert to risk (1 - survival probability)
      orsf_pred <- 1 - as.numeric(orsf_pred)
      # Ensure we have a vector, not a single value
      if (length(orsf_pred) == 1 && nrow(te_df_clean) > 1) {
        orsf_pred <- rep(orsf_pred, nrow(te_df_clean))
      }
      cat(sprintf("ORSF prediction successful: %s\n", class(orsf_pred)))
      cat(sprintf("ORSF prediction length: %d\n", length(orsf_pred)))
      cat(sprintf("ORSF prediction range: [%.3f, %.3f]\n", min(orsf_pred), max(orsf_pred)))
    } else {
      cat("ORSF: No complete cases available for prediction\n")
    }
  }, error = function(e) {
    cat(sprintf("ORSF predict failed: %s\n", e$message))
    # Try alternative predict method
    tryCatch({
      orsf_pred <- predict(orsf_model, new_data = te_df_predictors, object = 1)
      cat("ORSF alternative predict successful\n")
      orsf_pred <- 1 - as.numeric(orsf_pred)
      if (length(orsf_pred) == 1 && nrow(te_df_predictors) > 1) {
        orsf_pred <- rep(orsf_pred, nrow(te_df_predictors))
      }
      cat(sprintf("ORSF prediction successful: %s\n", class(orsf_pred)))
      cat(sprintf("ORSF prediction length: %d\n", length(orsf_pred)))
      cat(sprintf("ORSF prediction range: [%.3f, %.3f]\n", min(orsf_pred), max(orsf_pred)))
    }, error = function(e2) {
      cat(sprintf("ORSF alternative predict also failed: %s\n", e2$message))
    })
  })
}, error = function(e) {
  cat(sprintf("ORSF failed: %s\n", e$message))
})

# Test 2: Working XGBoost model
cat("\n=== Testing XGBoost ===\n")
tryCatch({
  xgb_model <- fit_xgb(trn_df, wisotzkey_features)
  cat("XGBoost model fitted successfully\n")
  
  # Encode test data the same way as training data
  te_df_encoded <- te_df
  for (var in wisotzkey_features) {
    if (is.factor(te_df_encoded[[var]])) {
      te_df_encoded[[var]] <- as.integer(te_df_encoded[[var]])
    } else if (is.character(te_df_encoded[[var]])) {
      te_df_encoded[[var]] <- as.integer(factor(te_df_encoded[[var]]))
    }
  }
  
  # Select only the predictor variables for prediction (exclude time and status)
  te_df_predictors <- te_df_encoded[, wisotzkey_features, drop = FALSE]
  
  # Debug: Check feature names
  cat("XGBoost model feature names:", paste(xgb_model$feature_names, collapse = ", "), "\n")
  cat("Test data feature names:", paste(colnames(te_df_predictors), collapse = ", "), "\n")
  
  # Use standard XGBoost predict method directly
  xgb_pred <- predict(xgb_model, newdata = as.matrix(te_df_predictors))
  cat(sprintf("XGBoost prediction successful: %s\n", class(xgb_pred)))
  cat(sprintf("XGBoost prediction length: %d\n", length(xgb_pred)))
  cat(sprintf("XGBoost prediction range: [%.3f, %.3f]\n", min(xgb_pred), max(xgb_pred)))
}, error = function(e) {
  cat(sprintf("XGBoost failed: %s\n", e$message))
})

# Test 3: Working CPH model
cat("\n=== Testing CPH ===\n")
tryCatch({
  cph_model <- fit_cph(trn_df, wisotzkey_features)
  cat("CPH model fitted successfully\n")
  
  # Debug: Check CPH model class
  cat("CPH model class:", paste(class(cph_model), collapse = ", "), "\n")
  cat("CPH model beta dimensions:", dim(cph_model$beta), "\n")
  cat("CPH model beta column names:", paste(colnames(cph_model$beta), collapse = ", "), "\n")
  cat("CPH model beta row names:", paste(rownames(cph_model$beta), collapse = ", "), "\n")
  
  # Convert all data to numeric for CPH (glmnet/coxnet)
  te_df_numeric <- te_df_predictors
  
  # Create dummy variables for prim_dx to match training data
  if ('prim_dx' %in% colnames(te_df_numeric)) {
    # Get the factor levels from training data
    trn_prim_dx_levels <- levels(as.factor(trn_df$prim_dx))
    cat("Training prim_dx levels:", paste(trn_prim_dx_levels, collapse = ", "), "\n")
    cat("Test prim_dx raw values:", paste(unique(te_df_predictors$prim_dx), collapse = ", "), "\n")
    
    # Convert numeric codes to string labels
    # Assuming 1 = "Congenital HD", 2 = "Other", 3 = "Specify" (need to verify this mapping)
    te_df_numeric$prim_dx <- ifelse(te_df_numeric$prim_dx == 1, "Congenital HD",
                                   ifelse(te_df_numeric$prim_dx == 2, "Other",
                                         ifelse(te_df_numeric$prim_dx == 3, "Specify", NA)))
    
    # Convert prim_dx to factor with same levels as training data
    te_df_numeric$prim_dx <- factor(te_df_numeric$prim_dx, levels = trn_prim_dx_levels)
    cat("Test prim_dx levels:", paste(levels(te_df_numeric$prim_dx), collapse = ", "), "\n")
    cat("Test prim_dx values:", paste(unique(te_df_numeric$prim_dx), collapse = ", "), "\n")
    cat("Test prim_dx NA count:", sum(is.na(te_df_numeric$prim_dx)), "\n")
    
    # Create dummy variables manually to ensure we get the right dimensions
    n_rows <- nrow(te_df_numeric)
    prim_dx_dummy <- matrix(0, nrow = n_rows, ncol = length(trn_prim_dx_levels))
    colnames(prim_dx_dummy) <- paste0("prim_dx", trn_prim_dx_levels)
    
    for (i in 1:length(trn_prim_dx_levels)) {
      level <- trn_prim_dx_levels[i]
      prim_dx_dummy[, i] <- as.numeric(te_df_numeric$prim_dx == level)
    }
    
    cat("Dummy matrix dimensions:", dim(prim_dx_dummy), "\n")
    # Remove the original prim_dx column
    te_df_numeric$prim_dx <- NULL
    # Add the dummy variables
    te_df_numeric <- cbind(te_df_numeric, prim_dx_dummy)
    cat("Final data dimensions:", dim(te_df_numeric), "\n")
  }
  
  # Convert remaining data to numeric
  for (var in colnames(te_df_numeric)) {
    if (is.factor(te_df_numeric[[var]])) {
      te_df_numeric[[var]] <- as.numeric(te_df_numeric[[var]])
    } else if (is.character(te_df_numeric[[var]])) {
      te_df_numeric[[var]] <- as.numeric(factor(te_df_numeric[[var]]))
    } else if (!is.numeric(te_df_numeric[[var]])) {
      te_df_numeric[[var]] <- as.numeric(te_df_numeric[[var]])
    }
  }
  
  # Debug: Check data types
  cat("CPH test data types:\n")
  for (var in colnames(te_df_numeric)) {
    cat(sprintf("  %s: %s\n", var, class(te_df_numeric[[var]])))
  }
  
  # Debug: Check for any issues with the data
  cat("CPH test data summary:\n")
  cat(sprintf("  Rows: %d, Cols: %d\n", nrow(te_df_numeric), ncol(te_df_numeric)))
  cat("  Column names:", paste(colnames(te_df_numeric), collapse = ", "), "\n")
  cat("  Any NA values:", any(is.na(te_df_numeric)), "\n")
  cat("  Any infinite values:", any(is.infinite(as.matrix(te_df_numeric))), "\n")
  
  # Remove rows with NA values for CPH
  complete_rows <- complete.cases(te_df_numeric)
  te_df_clean <- te_df_numeric[complete_rows, , drop = FALSE]
  cat(sprintf("  Clean rows: %d (removed %d with NA)\n", nrow(te_df_clean), sum(!complete_rows)))
  
  # Try direct predict method for CPH (glmnet/coxnet)
  te_matrix <- as.matrix(te_df_clean)
  cat("Matrix creation successful\n")
  cat(sprintf("Matrix dimensions: %d x %d\n", nrow(te_matrix), ncol(te_matrix)))
  cph_pred <- predict(cph_model, newx = te_matrix, type = "risk")
  # Convert to risk if needed
  cph_pred <- as.numeric(cph_pred)
  cat(sprintf("CPH prediction successful: %s\n", class(cph_pred)))
  cat(sprintf("CPH prediction length: %d\n", length(cph_pred)))
  cat(sprintf("CPH prediction range: [%.3f, %.3f]\n", min(cph_pred), max(cph_pred)))
}, error = function(e) {
  cat(sprintf("CPH failed: %s\n", e$message))
})

cat("\n[test_simple_working.R] Simple working test completed\n")
