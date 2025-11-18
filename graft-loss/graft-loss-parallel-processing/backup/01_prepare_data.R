#!/usr/bin/env Rscript

# Simple data preparation script using existing clean_phts() function
# This avoids the SAS parsing issues by using the already-working data cleaning pipeline

# Load required libraries
library(here)
library(dplyr)

# Source setup
source(here("pipeline", "00_setup.R"))

cat("[01_prepare_data.R] Starting simple data preparation using clean_phts()\n")

# Use the existing clean_phts() function instead of reading raw SAS
min_txpl_year <- 2010
predict_horizon <- 1

cat("[01_prepare_data.R] Calling clean_phts() function...\n")
phts_all <- clean_phts(
  min_txpl_year = min_txpl_year,
  predict_horizon = predict_horizon,
  time = outcome_int_graft_loss,
  status = outcome_graft_loss,
  case = 'snake',
  set_to_na = c("", "unknown", "missing")
)

cat("[01_prepare_data.R] clean_phts() completed successfully\n")
cat("[01_prepare_data.R] phts_all dimensions:", dim(phts_all), "\n")
cat("[01_prepare_data.R] phts_all column names:", paste(colnames(phts_all), collapse = ", "), "\n")

# Define the 15 Wisotzkey variables (using the cleaned column names)
wisotzkey_features <- c(
  "prim_dx",      # Primary Etiology
  "txmcsd",        # MCSD at Transplant  
  "chd_sv",        # Single Ventricle CHD
  "hxsurg",        # Surgeries Prior to Listing
  "txsa_r",        # Serum Albumin at Transplant
  "txbun_r",       # BUN at Transplant
  "txecmo",        # ECMO at Transplant
  "txpl_year",     # Transplant Year
  "weight_txpl",   # Weight at Transplant
  "txalt",         # ALT at Transplant
  "hxmed",         # Medical History
  "age_txpl",      # Age at Transplant
  "height_txpl",   # Height at Transplant
  "txcreat_r",     # Creatinine at Transplant
  "age_listing"    # Age at Listing
)

# Check which Wisotzkey features are available
available_features <- intersect(wisotzkey_features, colnames(phts_all))
missing_features <- setdiff(wisotzkey_features, colnames(phts_all))

cat("[01_prepare_data.R] Available Wisotzkey features:", length(available_features), "\n")
cat("[01_prepare_data.R] Available features:", paste(available_features, collapse = ", "), "\n")

if (length(missing_features) > 0) {
  cat("[01_prepare_data.R] Missing features:", paste(missing_features, collapse = ", "), "\n")
}

# Create derived variables that might be missing
cat("[01_prepare_data.R] Creating derived variables...\n")

# BMI at transplant (if not already present)
if (!"bmi_txpl" %in% colnames(phts_all) && "weight_txpl" %in% colnames(phts_all) && "height_txpl" %in% colnames(phts_all)) {
  phts_all$bmi_txpl <- phts_all$weight_txpl / (phts_all$height_txpl / 100)^2
  cat("[01_prepare_data.R] Created bmi_txpl\n")
}

# eGFR at transplant (if not already present)
if (!"egfr_tx" %in% colnames(phts_all) && "txcreat_r" %in% colnames(phts_all) && "age_txpl" %in% colnames(phts_all)) {
  # Simple eGFR calculation (Schwartz formula for pediatrics)
  # Handle division by zero and very low creatinine values
  phts_all$egfr_tx <- ifelse(
    phts_all$txcreat_r <= 0 | is.na(phts_all$txcreat_r), 
    NA,  # Set to NA if creatinine is 0 or missing
    0.413 * phts_all$height_txpl / phts_all$txcreat_r
  )
  cat("[01_prepare_data.R] Created egfr_tx (handled division by zero)\n")
}

# Listing year (if not already present)
if (!"listing_year" %in% colnames(phts_all) && "txpl_year" %in% colnames(phts_all)) {
  # Assume listing year is transplant year minus 1 (simplified)
  phts_all$listing_year <- phts_all$txpl_year - 1
  cat("[01_prepare_data.R] Created listing_year\n")
}

# PRA at listing (if not already present)
if (!"pra_listing" %in% colnames(phts_all) && "lsfprat" %in% colnames(phts_all)) {
  phts_all$pra_listing <- phts_all$lsfprat
  cat("[01_prepare_data.R] Created pra_listing from lsfprat\n")
}

# Select the final 15 Wisotzkey features plus time, status, and ID
final_features <- c(available_features, "bmi_txpl", "egfr_tx", "listing_year", "pra_listing")
final_features <- intersect(final_features, colnames(phts_all))

# Add time, status, and ID
required_cols <- c("time", "status", "ID")
final_cols <- c(final_features, required_cols)

# Select only the columns we need
phts_simple <- phts_all[, final_cols, drop = FALSE]

cat("[01_prepare_data.R] Final data dimensions:", dim(phts_simple), "\n")
cat("[01_prepare_data.R] Final column names:", paste(colnames(phts_simple), collapse = ", "), "\n")

# Check that time and status are properly formatted
cat("[01_prepare_data.R] time class:", class(phts_simple$time), "\n")
cat("[01_prepare_data.R] status class:", class(phts_simple$status), "\n")
cat("[01_prepare_data.R] time first 5 values:", paste(head(phts_simple$time, 5), collapse = ", "), "\n")
cat("[01_prepare_data.R] status first 5 values:", paste(head(phts_simple$status, 5), collapse = ", "), "\n")

# Save the simplified dataset in dual format (RDS + CSV)
output_path_rds <- here("model_data", "phts_simple.rds")
output_path_csv <- here("model_data", "phts_simple.csv")

# Save RDS
saveRDS(phts_simple, output_path_rds)
cat("[01_prepare_data.R] Saved RDS to:", output_path_rds, "\n")

# Save CSV for CatBoost
write.csv(phts_simple, output_path_csv, row.names = FALSE)
cat("[01_prepare_data.R] Saved CSV to:", output_path_csv, "\n")

cat("[01_prepare_data.R] Simple data preparation completed successfully\n")