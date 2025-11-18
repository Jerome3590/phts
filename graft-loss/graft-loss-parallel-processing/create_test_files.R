# Create test files for 07_generate_outputs.R
library(here)

# Load the main data
phts_all <- readRDS('model_data/phts_all.rds')

# Create labels.rds - should have variables and categories
labels <- list(
  variables = data.frame(
    variable = c("prim_dx", "tx_mcsd", "chd_sv", "hxsurg", "txsa_r", 
                "txbun_r", "txecmo", "txpl_year", "weight_txpl", "txalt",
                "bmi_txpl", "pra_listing", "egfr_tx", "hxmed", "listing_year"),
    label = c("Primary Etiology", "MCSD at Transplant", "Single Ventricle CHD", 
              "Surgeries Prior to Listing", "Serum Albumin at Transplant",
              "BUN at Transplant", "ECMO at Transplant", "Transplant Year",
              "Recipient Weight at Transplant", "ALT at Transplant",
              "BMI at Transplant", "PRA at Listing", "eGFR at Transplant",
              "Medical History at Listing", "Listing Year"),
    stringsAsFactors = FALSE
  ),
  categories = data.frame(
    category = c("congenital_hd", "cardiomyopathy", "no", "yes", "other"),
    label = c("Congenital heart disease", "Cardiomyopathy", "No", "Yes", "Other"),
    stringsAsFactors = FALSE
  )
)
saveRDS(labels, 'model_data/labels.rds')

# Create final_features.rds - should have variables list
final_features <- list(
  variables = c("prim_dx", "tx_mcsd", "chd_sv", "hxsurg", "txsa_r", 
               "txbun_r", "txecmo", "txpl_year", "weight_txpl", "txalt",
               "bmi_txpl", "pra_listing", "egfr_tx", "hxmed", "listing_year"),
  terms = c("prim_dx", "tx_mcsd", "chd_sv", "hxsurg", "txsa_r", 
           "txbun_r", "txecmo", "txpl_year", "weight_txpl", "txalt",
           "bmi_txpl", "pra_listing", "egfr_tx", "hxmed", "listing_year")
)
saveRDS(final_features, 'model_data/final_features.rds')

# Create final_recipe.rds - simple recipe object
library(recipes)
final_recipe <- recipe(~ ., data = phts_all[1:100, 1:20])
saveRDS(final_recipe, 'model_data/final_recipe.rds')

# Create final_data.rds - subset of phts_all with key variables
# Add time and status columns if they don't exist
final_data <- phts_all[1:100, 1:20]
if (!"time" %in% names(final_data)) {
  final_data$time <- runif(nrow(final_data), 0, 10)
}
if (!"status" %in% names(final_data)) {
  final_data$status <- rbinom(nrow(final_data), 1, 0.3)
}
saveRDS(final_data, 'model_data/final_data.rds')

cat("Created all test files successfully!\n")
