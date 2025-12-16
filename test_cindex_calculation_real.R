# Test C-index calculation methods with real CatBoost predictions
# Compare time-dependent vs time-independent C-index

library(here)
library(haven)
library(dplyr)
library(catboost)
library(survival)
library(riskRegression)
library(rsample)

cat("=== Testing C-index Calculation Methods ===\n\n")

# Load and prepare data (same as before)
sas_path <- here("graft-loss", "data", "phts_txpl_ml.sas7bdat")
if (!file.exists(sas_path)) {
  stop("Cannot find phts_txpl_ml.sas7bdat")
}

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

if ("donisch" %in% names(phts_base)) {
  phts_base <- phts_base %>%
    mutate(donisch = if_else(donisch > 240, 1, 0, missing = NA_real_))
}

if ("cpbypass" %in% names(phts_base)) {
  phts_base <- phts_base %>% select(-cpbypass)
}

phts_original <- phts_base %>%
  filter(txpl_year >= 2010 & txpl_year <= 2019)

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

modeling_data <- prepare_modeling_data(phts_original)

# Single split
set.seed(1997)
split <- initial_split(modeling_data, prop = 0.75, strata = status)
train_data <- training(split)
test_data <- testing(split)

# Train CatBoost
eps <- .Machine$double.eps
train_time <- suppressWarnings(as.numeric(train_data$time))
test_time <- suppressWarnings(as.numeric(test_data$time))
train_time[!is.finite(train_time) | train_time <= 0] <- eps
test_time[!is.finite(test_time) | test_time <= 0] <- eps

train_status <- as.integer(train_data$status)
test_status <- as.integer(test_data$status)

train_labels <- ifelse(train_status == 1L, train_time, -train_time)
test_labels <- ifelse(test_status == 1L, test_time, -test_time)

train_features <- train_data %>% select(-time, -status)
test_features <- test_data %>% select(-time, -status)

for (col in names(train_features)) {
  if (is.factor(train_features[[col]])) {
    train_levels <- levels(train_features[[col]])
    test_features[[col]] <- factor(test_features[[col]], levels = train_levels)
  }
}

train_pool <- catboost.load_pool(data = train_features, label = train_labels)
test_pool <- catboost.load_pool(data = test_features, label = test_labels)

params <- list(
  loss_function = 'Cox',
  eval_metric = 'Cox',
  iterations = 2000,
  depth = 4,
  learning_rate = 0.03,
  thread_count = 1,
  logging_level = 'Silent',
  verbose = 0L
)

cat("Training CatBoost model...\n")
model <- catboost.train(learn_pool = train_pool, test_pool = test_pool, params = params)

preds <- catboost.predict(model, test_pool)
predictions <- -1 * as.numeric(preds)

cat(sprintf("\nPredictions: range=[%.4f, %.4f], mean=%.4f, sd=%.4f\n",
            min(predictions), max(predictions), mean(predictions), sd(predictions)))

# Test different C-index calculations
cat("\n=== C-index Calculations ===\n\n")

# 1. Simple concordance (time-independent)
cat("1. Time-Independent (Harrell's C-index):\n")
c_ti <- tryCatch({
  conc <- concordance(Surv(test_time, test_status) ~ predictions)
  cidx <- as.numeric(conc$concordance)
  cat(sprintf("   C-index: %.4f\n", cidx))
  cidx
}, error = function(e) {
  cat(sprintf("   Error: %s\n", e$message))
  NA_real_
})

# 2. Time-dependent using riskRegression::Score (as in notebook)
cat("\n2. Time-Dependent (riskRegression::Score):\n")
horizon <- quantile(test_time[test_status == 1], 0.5, na.rm = TRUE)
cat(sprintf("   Horizon: %.4f years\n", horizon))

c_td <- tryCatch({
  # Format as in notebook
  score_data <- data.frame(time = test_time, status = test_status)
  pred_matrix <- matrix(predictions, ncol = 1)
  
  evaluation <- riskRegression::Score(
    object = list(Model = pred_matrix),
    formula = Surv(time, status) ~ 1,
    data = score_data,
    times = horizon,
    summary = "IPA"
  )
  
  cidx <- as.numeric(evaluation$AUC$score$AUC[1])
  cat(sprintf("   C-index: %.4f\n", cidx))
  cidx
}, error = function(e) {
  cat(sprintf("   Error: %s\n", e$message))
  cat("   Full error:\n")
  print(e)
  NA_real_
})

# 3. Check if predictions are reversed
cat("\n3. Testing if predictions are reversed:\n")
c_ti_reversed <- tryCatch({
  conc <- concordance(Surv(test_time, test_status) ~ -predictions)
  as.numeric(conc$concordance)
}, error = function(e) NA_real_)

cat(sprintf("   C-index (original): %.4f\n", c_ti))
cat(sprintf("   C-index (reversed): %.4f\n", c_ti_reversed))
if (c_ti_reversed < c_ti) {
  cat("   ✓ Original direction is correct\n")
} else {
  cat("   ⚠ Reversed direction gives better C-index!\n")
}

# 4. Check prediction distribution by status
cat("\n4. Prediction distribution by event status:\n")
cat(sprintf("   Events (status=1): mean=%.4f, median=%.4f\n",
            mean(predictions[test_status == 1]), median(predictions[test_status == 1])))
cat(sprintf("   Censored (status=0): mean=%.4f, median=%.4f\n",
            mean(predictions[test_status == 0]), median(predictions[test_status == 0])))
cat("   (Events should have HIGHER risk scores)\n")

if (mean(predictions[test_status == 1]) > mean(predictions[test_status == 0])) {
  cat("   ✓ Predictions correctly ordered\n")
} else {
  cat("   ⚠ Predictions may be reversed!\n")
}

cat("\n=== Summary ===\n")
cat(sprintf("Time-Independent C-index: %.4f\n", c_ti))
cat(sprintf("Time-Dependent C-index: %.4f\n", c_td))
cat(sprintf("Difference: %.4f\n", c_ti - c_td))

if (!is.na(c_td) && c_td < c_ti) {
  cat("\n⚠ WARNING: Time-dependent C-index is LOWER than time-independent!\n")
  cat("This is unusual and suggests an issue with the time-dependent calculation.\n")
}

cat("\n=== Test Complete ===\n")


