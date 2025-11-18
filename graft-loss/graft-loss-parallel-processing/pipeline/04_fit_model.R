# Simplified Model Fitting with MC-CV for Wisotzkey Features
# This script bypasses complex recipe processing since we're using pre-selected features

# Load necessary libraries
library(here)
library(dplyr)
library(rsample)

# Source the setup script for parallel processing configuration
source(here("scripts", "00_setup.R"))

# Source the simplified MC-CV function
source(here("scripts", "R", "run_mc.R"))

cat("[04_fit_model.R] Starting simplified model fitting with MC-CV\n")

# Load the simplified dataset
phts_path <- here("model_data", "phts_simple.rds")
if (!file.exists(phts_path)) {
  stop("Simplified dataset not found. Please run 01_prepare_data.R first.")
}

phts_data <- readRDS(phts_path)
cat(sprintf("[04_fit_model.R] Loaded dataset: %d rows, %d columns\n", 
            nrow(phts_data), ncol(phts_data)))

# Define the 15 Wisotzkey features
wisotzkey_features <- c(
  "prim_dx",      # Primary Etiology
  "tx_mcsd",      # MCSD at Transplant (with underscore - derived column!)
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
available_features <- intersect(wisotzkey_features, colnames(phts_data))
missing_features <- setdiff(wisotzkey_features, colnames(phts_data))

if (length(missing_features) > 0) {
  cat(sprintf("[WARNING] Missing features: %s\n", paste(missing_features, collapse = ", ")))
}

cat(sprintf("[04_fit_model_simple_mc.R] Using %d features: %s\n", 
            length(available_features), paste(available_features, collapse = ", ")))

# Create MC-CV splits
      set.seed(42)
n_splits <- 25
test_prop <- 0.2

# Create splits using rsample
splits <- rsample::mc_cv(phts_data, times = n_splits, prop = 1 - test_prop, strata = "status")
      testing_rows <- lapply(splits$splits, function(s) {
        test_indices <- assessment(s)
        if (is.data.frame(test_indices)) {
    as.integer(rownames(test_indices))
        } else {
          as.integer(test_indices)
        }
      })

cat(sprintf("[04_fit_model.R] Created %d MC-CV splits\n", length(testing_rows)))

# Run simplified MC-CV
cat("[04_fit_model.R] Running simplified MC-CV...\n")
results <- run_mc(phts_data, available_features, testing_rows, "simple")

# Summarize results
cat("\n[SUMMARY] MC-CV Results:\n")
for (model_type in names(results)) {
  model_results <- results[[model_type]]
  successful_splits <- sum(sapply(model_results, function(x) x$success))
  cat(sprintf("  %s: %d/%d splits successful\n", model_type, successful_splits, length(model_results)))
}

cat("[04_fit_model.R] Simplified model fitting completed\n")
