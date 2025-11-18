# Working Model Test Script
# This tests individual models with proper prediction handling

# Load necessary libraries
library(here)
library(dplyr)

# Source the setup script
source(here("scripts", "00_setup.R"))

cat("[test_working_models.R] Starting working model test\n")

# Load the simplified dataset
phts_data <- readRDS(here("model_data", "phts_simple.rds"))
cat(sprintf("[test_working_models.R] Loaded dataset: %d rows, %d columns\n", 
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

# Handle missing values
trn_complete <- complete.cases(trn_df)
te_complete <- complete.cases(te_df)

trn_df <- trn_df[trn_complete, , drop = FALSE]
te_df <- te_df[te_complete, , drop = FALSE]

cat(sprintf("[test_working_models.R] Train: %d rows, Test: %d rows\n", 
            nrow(trn_df), nrow(te_df)))

# Convert character variables to factors
for (var in wisotzkey_features) {
  if (is.character(trn_df[[var]])) {
    trn_df[[var]] <- as.factor(trn_df[[var]])
    te_df[[var]] <- factor(te_df[[var]], levels = levels(trn_df[[var]]))
  }
}

cat("[test_working_models.R] Data preparation complete\n")

# Test 1: Working ORSF model
cat("\n=== Testing ORSF ===\n")
tryCatch({
  orsf_model <- fit_orsf(trn_df, wisotzkey_features)
  cat("ORSF model fitted successfully\n")
  
  # Ensure test data has no missing values for ORSF
  te_df_clean <- te_df[complete.cases(te_df), , drop = FALSE]
  cat(sprintf("Clean test data: %d rows\n", nrow(te_df_clean)))
  
  if (nrow(te_df_clean) > 0) {
    orsf_pred <- predict(orsf_model, new_data = te_df_clean, pred_horizon = 1)
    cat(sprintf("ORSF prediction successful: %s\n", class(orsf_pred)))
    cat(sprintf("ORSF prediction length: %d\n", length(orsf_pred)))
    cat(sprintf("ORSF prediction range: [%.3f, %.3f]\n", min(orsf_pred), max(orsf_pred)))
  } else {
    cat("No complete test cases for ORSF prediction\n")
  }
}, error = function(e) {
  cat(sprintf("ORSF failed: %s\n", e$message))
})

# Test 2: Working XGBoost model
cat("\n=== Testing XGBoost ===\n")
tryCatch({
  xgb_model <- fit_xgb(trn_df, wisotzkey_features)
  cat("XGBoost model fitted successfully\n")
  
  # For XGBoost, we need to ensure the data is properly formatted
  # Convert factors to numeric for prediction
  te_df_xgb <- te_df
  for (var in wisotzkey_features) {
    if (is.factor(te_df_xgb[[var]])) {
      te_df_xgb[[var]] <- as.numeric(te_df_xgb[[var]])
    }
  }
  
  xgb_pred <- predict(xgb_model, newdata = te_df_xgb, pred_horizon = 1)
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
  
  # For CPH, create a proper matrix with only numeric variables
  te_df_cph <- te_df
  for (var in wisotzkey_features) {
    if (is.factor(te_df_cph[[var]])) {
      te_df_cph[[var]] <- as.numeric(te_df_cph[[var]])
    }
  }
  
  # Create matrix with only the predictor variables
  te_matrix <- as.matrix(te_df_cph[, wisotzkey_features, drop = FALSE])
  cat(sprintf("CPH test matrix: %d rows, %d cols\n", nrow(te_matrix), ncol(te_matrix)))
  
  cph_pred <- predict(cph_model, newx = te_matrix, pred_horizon = 1)
  cat(sprintf("CPH prediction successful: %s\n", class(cph_pred)))
  cat(sprintf("CPH prediction length: %d\n", length(cph_pred)))
  cat(sprintf("CPH prediction range: [%.3f, %.3f]\n", min(cph_pred), max(cph_pred)))
}, error = function(e) {
  cat(sprintf("CPH failed: %s\n", e$message))
})

cat("\n[test_working_models.R] Working model test completed\n")
