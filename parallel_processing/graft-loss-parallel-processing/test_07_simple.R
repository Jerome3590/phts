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

# Load the data files
log_step("Loading inputs")
phts_all <- readRDS(here::here('model_data', 'phts_all.rds'))
labels <- readRDS(here::here('model_data', 'labels.rds'))
final_features <- readRDS(here::here('model_data', 'final_features.rds'))
final_recipe <- readRDS(here::here('model_data', 'final_recipe.rds'))
final_data <- readRDS(here::here('model_data', 'final_data.rds'))

log_step(sprintf("Loaded: n=%s, p=%s; features=%s", nrow(final_data), ncol(final_data), length(final_features$variables)))

# Test model loading
log_step("Testing model loading")
cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
models_dir <- here::here('models', cohort_name)

if (file.exists(file.path(models_dir, 'final_model.rds'))) {
  final_model <- readRDS(file.path(models_dir, 'final_model.rds'))
  log_step("Loaded final model successfully")
} else {
  log_step("No final model found")
}

# Test the concordance calculation functions
log_step("Testing concordance functions")

# Test cindex function
test_time <- c(1, 2, 3, 4, 5)
test_status <- c(1, 0, 1, 0, 1)
test_score <- c(0.8, 0.6, 0.9, 0.4, 0.7)

# Load the model_utils functions
source("scripts/R/utils/model_utils.R")

# Test cindex
cindex_result <- cindex(test_time, test_status, test_score)
log_step(sprintf("cindex test result: %f", cindex_result))

# Test cindex_uno
cindex_uno_result <- cindex_uno(test_time, test_status, test_score, eval_time = 2)
log_step(sprintf("cindex_uno test result: %f", cindex_uno_result))

log_step("Test completed successfully")
