cat("\n\n##############################################\n")
cat(sprintf("### STARTING STEP: 07_generate_outputs.R [%s] ###\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("##############################################\n\n")

# Load required packages
library(here)
library(dplyr)

# Test the script with minimal data
log_step <- function(msg) {
  message(sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), msg))
  flush.console()
}

log_step("Testing 07_generate_outputs.R with minimal data")

# Check if required files exist
required_files <- c(
  'model_data/phts_all.rds',
  'model_data/labels.rds', 
  'model_data/final_features.rds',
  'model_data/final_recipe.rds',
  'model_data/final_data.rds'
)

missing_files <- c()
for (file in required_files) {
  if (!file.exists(file)) {
    missing_files <- c(missing_files, file)
  }
}

if (length(missing_files) > 0) {
  cat("Missing required files:\n")
  for (file in missing_files) {
    cat(sprintf("  - %s\n", file))
  }
  cat("\nThis script requires these files to run properly.\n")
  cat("In a real scenario, these would be created by earlier pipeline steps.\n")
} else {
  cat("All required files found!\n")
}

# Test loading the main data file
if (file.exists('model_data/phts_all.rds')) {
  log_step("Loading phts_all.rds")
  phts_all <- readRDS(here::here('model_data', 'phts_all.rds'))
  cat(sprintf("Loaded phts_all: %d rows, %d columns\n", nrow(phts_all), ncol(phts_all)))
} else {
  cat("ERROR: phts_all.rds not found\n")
}

# Test the model loading logic
log_step("Testing model loading logic")
cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
cat(sprintf("Cohort: %s\n", cohort_name))

models_dir <- here::here('models', cohort_name)
cat(sprintf("Models directory: %s\n", models_dir))

if (dir.exists(models_dir)) {
  split_files <- list.files(models_dir, pattern = "_split[0-9]{3}\\.rds$", full.names = TRUE)
  cat(sprintf("Found %d split files\n", length(split_files)))
  mc_cv_mode <- length(split_files) > 0
  cat(sprintf("MC-CV mode: %s\n", mc_cv_mode))
} else {
  cat("Models directory does not exist\n")
}

log_step("Test completed successfully")
