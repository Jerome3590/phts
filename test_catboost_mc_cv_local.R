# Test CatBoost with MC-CV splits on real data
# This will help identify if the issue appears with multiple splits

library(here)
library(haven)
library(dplyr)
library(catboost)
library(survival)
library(rsample)
library(purrr)

cat("=== CatBoost MC-CV Test with Real PHTS Data ===\n\n")

# Load data
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
  stop("Cannot find phts_txpl_ml.sas7bdat")
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

# Process DONISCH
if ("donisch" %in% names(phts_base)) {
  phts_base <- phts_base %>%
    mutate(
      donisch = if_else(donisch > 240, 1, 0, missing = NA_real_)
    )
}

# Remove CPBYPASS
if ("cpbypass" %in% names(phts_base)) {
  phts_base <- phts_base %>% select(-cpbypass)
}

# Prepare modeling data
prepare_modeling_data <- function(data) {
  time_col <- "outcome_int_graft_loss"
  status_col <- "outcome_graft_loss"
  
  modeling_data <- data %>%
    filter(!is.na(!!sym(time_col)), !is.na(!!sym(status_col))) %>%
    mutate(
      time = pmax(!!sym(time_col), 1/365),
      status = as.integer(!!sym(status_col))
    ) %>%
    select(-all_of(c(time_col, status_col, "ID"))) %>%
    select(where(~ !all(is.na(.x))))
  
  return(modeling_data)
}

# Filter to "original" period
phts_original <- phts_base %>%
  filter(txpl_year >= 2010 & txpl_year <= 2019)

modeling_data <- prepare_modeling_data(phts_original)
cat(sprintf("Data: %d rows, %d events (%.1f%%)\n", 
            nrow(modeling_data), sum(modeling_data$status), 
            100*mean(modeling_data$status)))

# Create 10 MC-CV splits
set.seed(1997)
n_splits <- 10
mc_splits <- mc_cv(modeling_data, times = n_splits, prop = 0.75, strata = status)

cat(sprintf("\nCreated %d MC-CV splits\n", n_splits))

# Function to run CatBoost on a split
run_split <- function(split, params, split_id) {
  train_data <- analysis(split)
  test_data <- assessment(split)
  
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
  
  # Train and predict
  model <- tryCatch({
    catboost.train(learn_pool = train_pool, test_pool = test_pool, params = params)
  }, error = function(e) {
    cat(sprintf("Split %d: Training error: %s\n", split_id, e$message))
    return(NULL)
  })
  
  if (is.null(model)) {
    return(list(c_index = NA_real_, pred_range = NA_real_, success = FALSE))
  }
  
  preds <- catboost.predict(model, test_pool)
  predictions <- -1 * as.numeric(preds)
  
  # Calculate C-index
  c_index <- tryCatch({
    conc <- concordance(Surv(test_time, test_status) ~ predictions)
    as.numeric(conc$concordance)
  }, error = function(e) {
    NA_real_
  })
  
  pred_range <- diff(range(predictions))
  
  return(list(
    c_index = c_index,
    pred_range = pred_range,
    success = TRUE
  ))
}

# Test configurations
configs <- list(
  list(
    name = "No learning_rate",
    params = list(
      loss_function = 'Cox',
      eval_metric = 'Cox',
      iterations = 2000,
      depth = 4,
      thread_count = 1,
      logging_level = 'Silent',
      verbose = 0L
    )
  ),
  list(
    name = "learning_rate = 0.03",
    params = list(
      loss_function = 'Cox',
      eval_metric = 'Cox',
      iterations = 2000,
      depth = 4,
      learning_rate = 0.03,
      thread_count = 1,
      logging_level = 'Silent',
      verbose = 0L
    )
  )
)

# Run tests
results_all <- list()

for (config in configs) {
  cat(sprintf("\n=== Testing: %s ===\n", config$name))
  
  results <- map(seq_len(n_splits), function(i) {
    split <- mc_splits$splits[[i]]
    result <- run_split(split, config$params, i)
    if (result$success) {
      cat(sprintf("Split %d: C-index = %.4f, Range = %.2f\n", 
                  i, result$c_index, result$pred_range))
    } else {
      cat(sprintf("Split %d: FAILED\n", i))
    }
    return(result)
  })
  
  c_indices <- map_dbl(results, ~ .x$c_index)
  c_indices <- c_indices[!is.na(c_indices)]
  pred_ranges <- map_dbl(results, ~ .x$pred_range)
  pred_ranges <- pred_ranges[!is.na(pred_ranges)]
  
  results_all[[config$name]] <- list(
    c_indices = c_indices,
    pred_ranges = pred_ranges,
    mean_cindex = mean(c_indices),
    sd_cindex = sd(c_indices),
    mean_range = mean(pred_ranges),
    sd_range = sd(pred_ranges),
    n_successful = length(c_indices)
  )
  
  cat(sprintf("\nSummary: Mean C-index = %.4f ± %.4f (n=%d)\n",
              mean(c_indices), sd(c_indices), length(c_indices)))
  cat(sprintf("Mean prediction range = %.2f ± %.2f\n",
              mean(pred_ranges), sd(pred_ranges)))
}

# Final comparison
cat("\n" , rep("=", 70), "\n", sep="")
cat("=== FINAL COMPARISON ===\n\n")
cat(sprintf("%-25s | %8s | %8s | %10s | %10s\n", 
            "Configuration", "Mean C", "SD C", "Mean Range", "SD Range"))
cat(rep("-", 75), "\n", sep="")

for (name in names(results_all)) {
  r <- results_all[[name]]
  cat(sprintf("%-25s | %8.4f | %8.4f | %10.2f | %10.2f\n",
              name, r$mean_cindex, r$sd_cindex, r$mean_range, r$sd_range))
}

cat("\n=== Test Complete ===\n")


