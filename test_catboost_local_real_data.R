# Local test of CatBoost Cox with actual PHTS data
# Tests the learning_rate fix on real data

library(here)
library(haven)
library(dplyr)
library(catboost)
library(survival)
library(rsample)
library(purrr)

cat("=== CatBoost Cox Test with Real PHTS Data ===\n\n")

# Load data (same as notebook)
# Try multiple paths
sas_path <- NULL
possible_paths <- c(
  here("graft-loss", "data", "phts_txpl_ml.sas7bdat"),
  here("data", "phts_txpl_ml.sas7bdat"),
  file.path("graft-loss", "data", "phts_txpl_ml.sas7bdat"),
  file.path("data", "phts_txpl_ml.sas7bdat")
)

for (path in possible_paths) {
  if (file.exists(path)) {
    sas_path <- path
    break
  }
}

if (is.null(sas_path)) {
  stop("Cannot find phts_txpl_ml.sas7bdat. Tried:", paste(possible_paths, collapse=", "))
}

cat("Loading data from:", sas_path, "\n")
phts_base <- haven::read_sas(sas_path) %>%
  filter(TXPL_YEAR >= 2010) %>%
  janitor::clean_names() %>%
  rename(
    outcome_int_graft_loss = int_graft_loss,
    outcome_graft_loss = graft_loss
  ) %>%
  mutate(
    ID = 1:n(),
    across(.cols = where(is.character), ~ ifelse(.x %in% c("", "unknown", "missing"), NA_character_, .x)),
    across(.cols = where(is.character), as.factor),
    tx_mcsd = if ('txnomcsd' %in% names(.)) {
      if_else(txnomcsd == 'yes', 0, 1)
    } else if ('txmcsd' %in% names(.)) {
      txmcsd
    } else {
      NA_real_
    }
  )

cat(sprintf("✓ Loaded data: %d rows, %d columns\n", nrow(phts_base), ncol(phts_base)))

# Process DONISCH (dichotomize)
if ("donisch" %in% names(phts_base)) {
  phts_base <- phts_base %>%
    mutate(
      donisch = if_else(donisch > 240, 1, 0, missing = NA_real_)
    )
}

# Remove CPBYPASS if present
if ("cpbypass" %in% names(phts_base)) {
  phts_base <- phts_base %>% select(-cpbypass)
}

# Prepare modeling data (simplified version)
prepare_modeling_data <- function(data) {
  time_col <- "outcome_int_graft_loss"
  status_col <- "outcome_graft_loss"
  
  modeling_data <- data %>%
    filter(!is.na(!!sym(time_col)), !is.na(!!sym(status_col))) %>%
    mutate(
      time = pmax(!!sym(time_col), 1/365),  # Ensure positive times
      status = as.integer(!!sym(status_col))
    ) %>%
    select(-all_of(c(time_col, status_col, "ID"))) %>%
    # Remove columns with all NA
    select(where(~ !all(is.na(.x))))
  
  return(modeling_data)
}

# Filter to "original" period (2010-2019)
phts_original <- phts_base %>%
  filter(txpl_year >= 2010 & txpl_year <= 2019)

cat("\n=== Original Period (2010-2019) ===\n")
cat(sprintf("Rows: %d\n", nrow(phts_original)))

# Prepare modeling data
modeling_data <- prepare_modeling_data(phts_original)
cat(sprintf("After preparation: %d rows, %d columns\n", nrow(modeling_data), ncol(modeling_data)))
cat(sprintf("Events: %d (%.1f%%)\n", sum(modeling_data$status), 100*mean(modeling_data$status)))

# Create a single train/test split for testing
set.seed(1997)
split <- initial_split(modeling_data, prop = 0.75, strata = status)
train_data <- training(split)
test_data <- testing(split)

cat(sprintf("\nTrain: %d rows (%d events)\n", nrow(train_data), sum(train_data$status)))
cat(sprintf("Test: %d rows (%d events)\n", nrow(test_data), sum(test_data$status)))

# Function to run CatBoost with given parameters
run_catboost_test <- function(train_data, test_data, params, label) {
  cat(sprintf("\n--- Testing: %s ---\n", label))
  
  # Prepare signed time labels
  eps <- .Machine$double.eps
  train_time <- suppressWarnings(as.numeric(train_data$time))
  test_time <- suppressWarnings(as.numeric(test_data$time))
  train_time[!is.finite(train_time) | train_time <= 0] <- eps
  test_time[!is.finite(test_time) | test_time <= 0] <- eps
  
  train_status <- as.integer(train_data$status)
  test_status <- as.integer(test_data$status)
  
  train_labels <- ifelse(train_status == 1L, train_time, -train_time)
  test_labels <- ifelse(test_status == 1L, test_time, -test_time)
  
  # Prepare features
  train_features <- train_data %>% select(-time, -status)
  test_features <- test_data %>% select(-time, -status)
  
  # Sync factor levels
  for (col in names(train_features)) {
    if (is.factor(train_features[[col]])) {
      train_levels <- levels(train_features[[col]])
      test_features[[col]] <- factor(test_features[[col]], levels = train_levels)
    }
  }
  
  # Create pools
  train_pool <- catboost.load_pool(data = train_features, label = train_labels)
  test_pool <- catboost.load_pool(data = test_features, label = test_labels)
  
  # Train model
  cat("Training CatBoost model...\n")
  model <- catboost.train(learn_pool = train_pool, test_pool = test_pool, params = params)
  
  # Predict
  preds <- catboost.predict(model, test_pool)
  predictions <- -1 * as.numeric(preds)
  
  # Calculate C-index
  c_index <- tryCatch({
    conc <- concordance(Surv(test_time, test_status) ~ predictions)
    as.numeric(conc$concordance)
  }, error = function(e) {
    cat(sprintf("Error calculating C-index: %s\n", e$message))
    NA_real_
  })
  
  # Statistics
  pred_range <- diff(range(predictions))
  pred_mean <- mean(predictions)
  pred_sd <- sd(predictions)
  
  cat(sprintf("Prediction range: %.6f\n", pred_range))
  cat(sprintf("Prediction mean: %.6f\n", pred_mean))
  cat(sprintf("Prediction SD: %.6f\n", pred_sd))
  cat(sprintf("C-index: %.4f\n", c_index))
  
  if (pred_range < 0.01) {
    cat("⚠ WARNING: Prediction range is very small (< 0.01)\n")
  }
  
  return(list(
    c_index = c_index,
    pred_range = pred_range,
    pred_mean = pred_mean,
    pred_sd = pred_sd,
    predictions = predictions
  ))
}

# Test 1: Without learning_rate (old approach)
cat("\n" , rep("=", 60), "\n", sep="")
params_no_lr <- list(
  loss_function = 'Cox',
  eval_metric = 'Cox',
  iterations = 2000,
  depth = 4,
  thread_count = 1,
  logging_level = 'Silent',
  verbose = 0L
)
result_no_lr <- run_catboost_test(train_data, test_data, params_no_lr, "Without learning_rate")

# Test 2: With learning_rate = 0.03 (new approach)
cat("\n" , rep("=", 60), "\n", sep="")
params_with_lr <- list(
  loss_function = 'Cox',
  eval_metric = 'Cox',
  iterations = 2000,
  depth = 4,
  learning_rate = 0.03,
  thread_count = 1,
  logging_level = 'Silent',
  verbose = 0L
)
result_with_lr <- run_catboost_test(train_data, test_data, params_with_lr, "With learning_rate = 0.03")

# Test 3: With learning_rate = 0.05 (alternative)
cat("\n" , rep("=", 60), "\n", sep="")
params_lr_005 <- list(
  loss_function = 'Cox',
  eval_metric = 'Cox',
  iterations = 2000,
  depth = 4,
  learning_rate = 0.05,
  thread_count = 1,
  logging_level = 'Silent',
  verbose = 0L
)
result_lr_005 <- run_catboost_test(train_data, test_data, params_lr_005, "With learning_rate = 0.05")

# Summary comparison
cat("\n" , rep("=", 60), "\n", sep="")
cat("=== SUMMARY COMPARISON ===\n\n")
cat(sprintf("%-30s | %10s | %12s | %10s\n", "Configuration", "C-index", "Pred Range", "Pred SD"))
cat(rep("-", 70), "\n", sep="")
cat(sprintf("%-30s | %10.4f | %12.6f | %10.6f\n", 
            "No learning_rate", 
            result_no_lr$c_index, 
            result_no_lr$pred_range, 
            result_no_lr$pred_sd))
cat(sprintf("%-30s | %10.4f | %12.6f | %10.6f\n", 
            "learning_rate = 0.03", 
            result_with_lr$c_index, 
            result_with_lr$pred_range, 
            result_with_lr$pred_sd))
cat(sprintf("%-30s | %10.4f | %12.6f | %10.6f\n", 
            "learning_rate = 0.05", 
            result_lr_005$c_index, 
            result_lr_005$pred_range, 
            result_lr_005$pred_sd))
cat("\n")

# Improvement
improvement_003 <- result_with_lr$c_index - result_no_lr$c_index
improvement_005 <- result_lr_005$c_index - result_no_lr$c_index

cat(sprintf("Improvement with LR=0.03: %.4f (%.1f%%)\n", 
            improvement_003, 100 * improvement_003 / result_no_lr$c_index))
cat(sprintf("Improvement with LR=0.05: %.4f (%.1f%%)\n", 
            improvement_005, 100 * improvement_005 / result_no_lr$c_index))

cat("\n=== Test Complete ===\n")

