#!/usr/bin/env Rscript

# Simplified model fitting script that works with the simplified dataset
# No complex pipeline dependencies - just load simplified data and fit models

# Load required libraries
library(here)
library(dplyr)

# Source setup
source(here("scripts", "00_setup.R"))

cat("[04_fit_model_simple.R] Starting simplified model fitting\n")

# Load the simplified dataset
phts_simple_path <- here("model_data", "phts_simple.rds")
if (!file.exists(phts_simple_path)) {
  stop("phts_simple.rds not found. Please run 01_prepare_data_simple.R first.")
}

cat("[04_fit_model_simple.R] Loading simplified dataset...\n")
phts_simple <- readRDS(phts_simple_path)

cat(sprintf("[04_fit_model_simple.R] Loaded dataset: %d rows, %d columns\n", 
            nrow(phts_simple), ncol(phts_simple)))

# Define the 15 Wisotzkey features
wisotzkey_features <- c(
  "prim_dx",      # Primary Etiology
  "txmcsd",       # MCSD at Transplant (using txmcsd from simplified dataset)
  "chd_sv",       # Single Ventricle CHD
  "hxsurg",       # Surgeries Prior to Listing
  "txsa_r",       # Serum Albumin at Transplant
  "txbun_r",      # BUN at Transplant
  "txecmo",       # ECMO at Transplant
  "txpl_year",    # Transplant Year
  "weight_txpl",  # Recipient Weight at Transplant
  "txalt",        # ALT at Transplant
  "bmi_txpl",     # BMI at Transplant (derived)
  "pra_listing",  # PRA Max at Listing (derived)
  "egfr_tx",      # eGFR at Transplant (derived)
  "hxmed",        # Medical History at Listing
  "listing_year"  # Listing Year (derived)
)

# Check which features are available
available_features <- intersect(wisotzkey_features, colnames(phts_simple))
missing_features <- setdiff(wisotzkey_features, colnames(phts_simple))

cat(sprintf("[04_fit_model_simple.R] Available Wisotzkey features: %d/%d\n", 
            length(available_features), length(wisotzkey_features)))

if (length(missing_features) > 0) {
  cat(sprintf("[04_fit_model_simple.R] Missing features: %s\n", 
              paste(missing_features, collapse = ", ")))
}

# Create the final dataset with only the features we need
final_data <- phts_simple %>%
  select(time, status, ID, all_of(available_features))

cat(sprintf("[04_fit_model_simple.R] Final dataset: %d rows, %d columns\n", 
            nrow(final_data), ncol(final_data)))

# Save the final dataset
final_data_path <- here("model_data", "final_data.rds")
saveRDS(final_data, final_data_path)
cat(sprintf("[04_fit_model_simple.R] Saved final dataset to: %s\n", final_data_path))

# Create a simple final_features object for compatibility
final_features <- list(
  terms = available_features,
  n_features = length(available_features)
)

final_features_path <- here("model_data", "final_features.rds")
saveRDS(final_features, final_features_path)
cat(sprintf("[04_fit_model_simple.R] Saved final features to: %s\n", final_features_path))

# Create encoded dataset for XGBoost (convert factors to dummy variables)
cat("[04_fit_model_simple.R] Creating encoded dataset for XGBoost...\n")

# Identify factor variables
factor_vars <- names(final_data)[sapply(final_data, is.factor)]
cat(sprintf("[04_fit_model_simple.R] Factor variables: %s\n", 
            paste(factor_vars, collapse = ", ")))

if (length(factor_vars) > 0) {
  # Create dummy variables for factors
  encoded_data <- final_data
  
  for (var in factor_vars) {
    if (var %in% colnames(final_data)) {
      # Create dummy variables using model.matrix
      dummy_vars <- model.matrix(~ 0 + get(var), data = final_data)
      colnames(dummy_vars) <- paste0(var, "_", levels(final_data[[var]]))
      
      # Add dummy variables to encoded dataset
      encoded_data <- cbind(encoded_data, dummy_vars)
    }
  }
  
  # Remove original factor variables
  encoded_data <- encoded_data[, !colnames(encoded_data) %in% factor_vars]
  
} else {
  encoded_data <- final_data
}

cat(sprintf("[04_fit_model_simple.R] Encoded dataset: %d rows, %d columns\n", 
            nrow(encoded_data), ncol(encoded_data)))

# Save encoded dataset
encoded_data_path <- here("model_data", "final_data_encoded.rds")
saveRDS(encoded_data, encoded_data_path)
cat(sprintf("[04_fit_model_simple.R] Saved encoded dataset to: %s\n", encoded_data_path))

# Create CSV version for CatBoost
csv_data_path <- here("model_data", "final_data.csv")
readr::write_csv(final_data, csv_data_path)
cat(sprintf("[04_fit_model_simple.R] Saved CSV dataset to: %s\n", csv_data_path))

# Now run the original model fitting script
cat("[04_fit_model_simple.R] Running original model fitting script...\n")

# Set environment variables
Sys.setenv(DATASET_COHORT = "original")
Sys.setenv(USE_ENCODED = "1")
Sys.setenv(XGB_FULL = "0")
Sys.setenv(MC_CV = "1")
Sys.setenv(USE_CATBOOST = "0")  # Disable CatBoost for now
Sys.setenv(MC_FI = "0")  # Disable feature importance calculation since we're self-selecting variables

# Source the original model fitting script
source(here("scripts", "04_fit_model.R"))

cat("[04_fit_model_simple.R] Simplified model fitting completed\n")
