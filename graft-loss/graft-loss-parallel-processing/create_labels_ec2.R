# Create labels.rds for EC2 environment
# This script should be run on EC2 to create the missing labels.rds file

library(here)

# Check if phts_all.rds exists
if (!file.exists('model_data/phts_all.rds')) {
  stop("phts_all.rds not found. Please run earlier pipeline steps first.")
}

# Load the main data to get variable names
phts_all <- readRDS('model_data/phts_all.rds')

# Create labels structure based on the Wisotzkey variables
# These are the key variables used in the analysis
wisotzkey_variables <- c(
  "prim_dx",           # Primary Etiology
  "tx_mcsd",           # MCSD at Transplant
  "chd_sv",            # Single Ventricle CHD
  "hxsurg",            # Surgeries Prior to Listing
  "txsa_r",            # Serum Albumin at Transplant
  "txbun_r",           # BUN at Transplant
  "txecmo",            # ECMO at Transplant
  "txpl_year",         # Transplant Year
  "weight_txpl",       # Recipient Weight at Transplant
  "txalt",             # ALT at Transplant
  "bmi_txpl",          # BMI at Transplant
  "pra_listing",       # PRA at Listing
  "egfr_tx",           # eGFR at Transplant
  "hxmed",             # Medical History at Listing
  "listing_year"       # Listing Year
)

# Create labels for variables that exist in the data
available_vars <- intersect(wisotzkey_variables, names(phts_all))
if (length(available_vars) == 0) {
  # Fallback: use first 20 variables
  available_vars <- names(phts_all)[1:min(20, ncol(phts_all))]
}

# Create variable labels
variable_labels <- c(
  "prim_dx" = "Primary Etiology",
  "tx_mcsd" = "MCSD at Transplant", 
  "chd_sv" = "Single Ventricle CHD",
  "hxsurg" = "Surgeries Prior to Listing",
  "txsa_r" = "Serum Albumin at Transplant",
  "txbun_r" = "BUN at Transplant",
  "txecmo" = "ECMO at Transplant",
  "txpl_year" = "Transplant Year",
  "weight_txpl" = "Recipient Weight at Transplant",
  "txalt" = "ALT at Transplant",
  "bmi_txpl" = "BMI at Transplant",
  "pra_listing" = "PRA at Listing",
  "egfr_tx" = "eGFR at Transplant",
  "hxmed" = "Medical History at Listing",
  "listing_year" = "Listing Year"
)

# Create labels data frame
labels_df <- data.frame(
  variable = available_vars,
  label = ifelse(available_vars %in% names(variable_labels), 
                 variable_labels[available_vars], 
                 paste("Variable", available_vars)),
  stringsAsFactors = FALSE
)

# Create categories
categories_df <- data.frame(
  category = c("congenital_hd", "cardiomyopathy", "no", "yes", "other"),
  label = c("Congenital heart disease", "Cardiomyopathy", "No", "Yes", "Other"),
  stringsAsFactors = FALSE
)

# Create the labels object
labels <- list(
  variables = labels_df,
  categories = categories_df
)

# Save the labels file
saveRDS(labels, 'model_data/labels.rds')

cat("Created labels.rds successfully!\n")
cat("Variables:", nrow(labels$variables), "\n")
cat("Categories:", nrow(labels$categories), "\n")
