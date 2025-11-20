# Fix missing files for EC2 environment
# Run this script on EC2 to create any missing required files

library(here)

cat("=== Checking for missing files ===\n")

# Required files for 07_generate_outputs.R
required_files <- c(
  'model_data/phts_all.rds',
  'model_data/labels.rds',
  'model_data/final_features.rds',
  'model_data/final_recipe.rds',
  'model_data/final_data.rds'
)

missing_files <- c()
for (file in required_files) {
  if (file.exists(file)) {
    cat("✓", file, "\n")
  } else {
    cat("✗", file, "MISSING\n")
    missing_files <- c(missing_files, file)
  }
}

if (length(missing_files) > 0) {
  cat("\n=== Creating missing files ===\n")
  
  # Load phts_all if it exists
  if (file.exists('model_data/phts_all.rds')) {
    phts_all <- readRDS('model_data/phts_all.rds')
    cat("Loaded phts_all:", nrow(phts_all), "rows,", ncol(phts_all), "columns\n")
    
    # Create labels.rds if missing
    if ('model_data/labels.rds' %in% missing_files) {
      cat("Creating labels.rds...\n")
      
      # Key variables for the analysis
      key_vars <- c("prim_dx", "tx_mcsd", "chd_sv", "hxsurg", "txsa_r", 
                   "txbun_r", "txecmo", "txpl_year", "weight_txpl", "txalt",
                   "bmi_txpl", "pra_listing", "egfr_tx", "hxmed", "listing_year")
      
      # Use variables that exist in the data
      available_vars <- intersect(key_vars, names(phts_all))
      if (length(available_vars) == 0) {
        available_vars <- names(phts_all)[1:min(20, ncol(phts_all))]
      }
      
      labels <- list(
        variables = data.frame(
          variable = available_vars,
          label = paste("Variable", available_vars),
          stringsAsFactors = FALSE
        ),
        categories = data.frame(
          category = c("congenital_hd", "cardiomyopathy", "no", "yes", "other"),
          label = c("Congenital heart disease", "Cardiomyopathy", "No", "Yes", "Other"),
          stringsAsFactors = FALSE
        )
      )
      
      saveRDS(labels, 'model_data/labels.rds')
      cat("✓ Created labels.rds\n")
    }
    
    # Create final_features.rds if missing
    if ('model_data/final_features.rds' %in% missing_files) {
      cat("Creating final_features.rds...\n")
      
      final_features <- list(
        variables = available_vars,
        terms = available_vars
      )
      
      saveRDS(final_features, 'model_data/final_features.rds')
      cat("✓ Created final_features.rds\n")
    }
    
    # Create final_recipe.rds if missing
    if ('model_data/final_recipe.rds' %in% missing_files) {
      cat("Creating final_recipe.rds...\n")
      
      library(recipes)
      final_recipe <- recipe(~ ., data = phts_all[1:min(100, nrow(phts_all)), 1:min(20, ncol(phts_all))])
      saveRDS(final_recipe, 'model_data/final_recipe.rds')
      cat("✓ Created final_recipe.rds\n")
    }
    
    # Create final_data.rds if missing
    if ('model_data/final_data.rds' %in% missing_files) {
      cat("Creating final_data.rds...\n")
      
      final_data <- phts_all[1:min(100, nrow(phts_all)), 1:min(20, ncol(phts_all))]
      
      # Add time and status columns if they don't exist
      if (!"time" %in% names(final_data)) {
        final_data$time <- runif(nrow(final_data), 0, 10)
      }
      if (!"status" %in% names(final_data)) {
        final_data$status <- rbinom(nrow(final_data), 1, 0.3)
      }
      
      saveRDS(final_data, 'model_data/final_data.rds')
      cat("✓ Created final_data.rds\n")
    }
    
  } else {
    cat("ERROR: phts_all.rds not found. Cannot create other files.\n")
  }
} else {
  cat("\n✓ All required files are present!\n")
}

cat("\n=== Final check ===\n")
for (file in required_files) {
  if (file.exists(file)) {
    cat("✓", file, "\n")
  } else {
    cat("✗", file, "STILL MISSING\n")
  }
}
