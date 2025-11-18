#!/usr/bin/env Rscript
# Direct C-index calculation for cohorts
# Based on cohort_survival_analysis.qmd template

library(here)
library(dplyr)
library(survival)
library(glmnet)
library(aorsf)
library(catboost)
library(readr)
library(tibble)

# Set seed for reproducibility
set.seed(1997)

# Load the preprocessed modeling dataset
cat("Loading data...\n")
model_data <- read_csv("preprocessed_model_data.csv", show_col_types = FALSE)

# Check for survival variables and identify available columns
available_time <- names(model_data)[grep("time|Time|TIME", names(model_data))]
available_event <- names(model_data)[grep("event|Event|EVENT|type|Type|TYPE|status|Status|STATUS", names(model_data))]

cat("Available time columns:", paste(available_time, collapse = ", "), "\n")
cat("Available event columns:", paste(available_event, collapse = ", "), "\n")

# Verify the data structure
cat("Dataset dimensions:", paste(dim(model_data), collapse = " x "), "\n")

# Rename columns if needed
if(!("ev_time" %in% names(model_data)) && length(available_time) == 1) {
  model_data <- model_data %>% rename(ev_time = !!sym(available_time))
}
if(!("outcome" %in% names(model_data)) && length(available_event) == 1) {
  model_data <- model_data %>% rename(outcome = !!sym(available_event))
}

# Normalize types
model_data <- model_data %>%
  mutate(
    outcome = as.integer(outcome),
    ev_time = suppressWarnings(as.numeric(ev_time))
  )

# Handle censored times
med_censored_time <- model_data %>%
  filter(outcome == 0L, is.finite(ev_time), ev_time > 0) %>%
  summarise(med = median(ev_time, na.rm = TRUE)) %>% pull(med)

if (!is.finite(med_censored_time) || is.na(med_censored_time)) {
  med_censored_time <- model_data %>%
    filter(is.finite(ev_time), ev_time > 0) %>%
    summarise(med = median(ev_time, na.rm = TRUE)) %>% pull(med)
}
if (!is.finite(med_censored_time) || is.na(med_censored_time)) {
  med_censored_time <- 1 / (365.25 * 24 * 60)  # ~1 minute in years
}

# Replace bad times for censored rows
model_data <- model_data %>%
  mutate(
    ev_time_replaced = outcome == 0L & is.finite(ev_time) & ev_time <= 0,
    ev_time = if_else(outcome == 0L & (is.na(ev_time) | ev_time <= 0),
                      med_censored_time, ev_time)
  )

cat("Replaced", sum(model_data$ev_time_replaced, na.rm = TRUE),
    "censored non-positive ev_time values with median =", med_censored_time, "\n")

# Define study period filters
define_cohorts <- function(data) {
  # Assuming transplant_year or similar column exists
  # Adjust these filters based on your actual data structure
  
  cohorts <- list()
  
  # Original study (pre-COVID) - adjust dates as needed
  if ("transplant_year" %in% names(data)) {
    cohorts$original <- data %>% filter(transplant_year < 2020)
  } else {
    # Fallback: use all data if no year column
    cohorts$original <- data
  }
  
  # Full study with COVID (all data)
  cohorts$full_with_covid <- data
  
  # Non-COVID full study (exclude COVID period)
  if ("transplant_year" %in% names(data)) {
    cohorts$non_covid_full <- data %>% filter(transplant_year < 2020 | transplant_year > 2021)
  } else {
    # Fallback: use all data
    cohorts$non_covid_full <- data
  }
  
  return(cohorts)
}

# Define survival lagging keywords (from template)
survival_lagging_keywords <- c(
  "transplant_year", "primary_etiology",
  "graft_loss", "int_graft_loss", "dtx_", "cc_", "isc_oth",
  "dcardiac", "dcon", "dpri", "dpricaus", "rec_", "papooth",
  "dneuro", "sdprathr", "int_dead", "listing_year", "cpathneg",
  "dcauseod", "race", "sex", "drace_b", "rrace_a", "hisp", "Iscntry",
  "dreject", "dsecaccsEmpty", "dmajbldEmpty", "pishltgr1R", 
  "drejectEmpty", "drejectHyperacute", "pishltgrEmpty",
  "pishltgr", "dmajbld", "dsecaccs", "dsecaccs_bin", 
  "dx_cardiomyopathy", "deathspc", "dlist", "pmorexam", 
  "patsupp", "concod", "pcadrem", "pcadrec", "pathero", 
  "pdiffib", "dmalcanc", "alt_tx", "age_death", "pacuref",
  "lsvcma"
)

# Unified train/test split function
create_unified_train_test_split <- function(data, cohort_name, seed = 1997) {
  set.seed(seed)
  
  n_total <- nrow(data)
  n_train <- floor(0.8 * n_total)
  
  all_indices <- 1:n_total
  train_indices <- sample(all_indices, size = n_train)
  test_indices <- setdiff(all_indices, train_indices)
  
  train_data <- data[train_indices, ]
  test_data <- data[test_indices, ]
  
  cat("=== Unified Train/Test Split for", cohort_name, "===\n")
  cat("Total patients:", n_total, "\n")
  cat("Training set:", n_train, "patients\n")
  cat("Test set:", length(test_indices), "patients\n")
  cat("Split ratio:", round(n_train/n_total, 3), ":", round(length(test_indices)/n_total, 3), "\n")
  cat("=====================================\n\n")
  
  return(list(
    train_data = train_data,
    test_data = test_data,
    split_info = list(
      cohort = cohort_name,
      train_indices = train_indices,
      test_indices = test_indices,
      n_total = n_total,
      n_train = n_train,
      n_test = length(test_indices),
      seed = seed
    )
  ))
}

# LASSO model function
fit_lasso_model <- function(train_data, test_data, cohort_name) {
  cat("Fitting LASSO model for", cohort_name, "\n")
  
  # Prepare data
  surv_data <- train_data %>%
    select(!(matches(paste(survival_lagging_keywords, collapse = "|")) | starts_with("sd"))) %>%
    mutate(
      time = ev_time,
      status = outcome
    ) %>%
    mutate(across(where(is.numeric), ~if_else(is.infinite(.), NA_real_, .))) %>%
    select(-where(~all(is.na(.)))) %>%
    select(-ev_time, -outcome) %>%
    mutate(across(where(is.character), as.factor)) %>%
    mutate(across(where(is.factor), as.numeric))
  
  # Remove constant columns
  constant_cols <- names(surv_data)[sapply(surv_data, function(x) {
    length(unique(na.omit(x))) == 1
  })]
  if(length(constant_cols) > 0) {
    surv_data <- surv_data %>% select(-all_of(constant_cols))
  }
  
  # Impute missing values
  surv_data <- surv_data %>%
    mutate(across(everything(), ~if_else(is.na(.), median(., na.rm = TRUE), .)))
  
  # Prepare test data similarly
  test_surv_data <- test_data %>%
    select(!(matches(paste(survival_lagging_keywords, collapse = "|")) | starts_with("sd"))) %>%
    mutate(
      time = ev_time,
      status = outcome
    ) %>%
    mutate(across(where(is.numeric), ~if_else(is.infinite(.), NA_real_, .))) %>%
    select(-where(~all(is.na(.)))) %>%
    select(-ev_time, -outcome) %>%
    mutate(across(where(is.character), as.factor)) %>%
    mutate(across(where(is.factor), as.numeric))
  
  # Remove same constant columns
  if(length(constant_cols) > 0) {
    test_surv_data <- test_surv_data %>% select(-all_of(constant_cols))
  }
  
  # Impute missing values
  test_surv_data <- test_surv_data %>%
    mutate(across(everything(), ~if_else(is.na(.), median(., na.rm = TRUE), .)))
  
  # Create matrices
  y_train <- Surv(surv_data$time, surv_data$status)
  x_train <- as.matrix(surv_data %>% select(-time, -status))
  y_test <- Surv(test_surv_data$time, test_surv_data$status)
  x_test <- as.matrix(test_surv_data %>% select(-time, -status))
  
  # Fit LASSO
  set.seed(1997)
  lasso_cv <- cv.glmnet(
    x = x_train,
    y = y_train,
    family = "cox",
    alpha = 1,
    nfolds = 5,
    type.measure = "C"
  )
  
  # Get predictions
  risk_scores <- predict(lasso_cv, newx = x_test, s = "lambda.min")
  c_index <- survival::concordance(y_test ~ risk_scores)
  
  return(as.numeric(c_index$concordance))
}

# AORSF model function
fit_aorsf_model <- function(train_data, test_data, cohort_name) {
  cat("Fitting AORSF model for", cohort_name, "\n")
  
  # Prepare data
  aorsf_data <- train_data %>%
    select(!(matches(paste(survival_lagging_keywords, collapse = "|")) | starts_with("sd"))) %>%
    mutate(
      time = ev_time,
      status = as.integer(outcome == 1)
    ) %>%
    select(-ev_time, -outcome) %>%
    mutate(across(where(is.character), as.factor))
  
  # Remove constant columns
  constant_cols <- names(aorsf_data)[sapply(aorsf_data, function(x) {
    length(unique(na.omit(x))) == 1
  })]
  if(length(constant_cols) > 0) {
    aorsf_data <- aorsf_data %>% select(-all_of(constant_cols))
  }
  
  # Prepare test data
  test_aorsf_data <- test_data %>%
    select(!(matches(paste(survival_lagging_keywords, collapse = "|")) | starts_with("sd"))) %>%
    mutate(
      time = ev_time,
      status = as.integer(outcome == 1)
    ) %>%
    select(-ev_time, -outcome) %>%
    mutate(across(where(is.character), as.factor))
  
  # Remove same constant columns
  if(length(constant_cols) > 0) {
    test_aorsf_data <- test_aorsf_data %>% select(-all_of(constant_cols))
  }
  
  # Ensure consistent features
  common_features <- intersect(colnames(aorsf_data), colnames(test_aorsf_data))
  aorsf_data <- aorsf_data %>% select(all_of(common_features))
  test_aorsf_data <- test_aorsf_data %>% select(all_of(common_features))
  
  # Fit AORSF
  set.seed(1997)
  aorsf_model <- orsf(
    data = aorsf_data,
    formula = Surv(time, status) ~ .,
    na_action = 'impute_meanmode',
    n_tree = 100
  )
  
  # Get predictions
  risk_scores <- predict(aorsf_model, new_data = test_aorsf_data, pred_type = 'risk')
  surv_obj_test <- Surv(test_aorsf_data$time, test_aorsf_data$status)
  c_index <- survival::concordance(surv_obj_test ~ risk_scores)
  
  return(as.numeric(c_index$concordance))
}

# CatBoost model function
fit_catboost_model <- function(train_data, test_data, cohort_name) {
  cat("Fitting CatBoost model for", cohort_name, "\n")
  
  # Clean data for CatBoost
  clean_data <- function(data) {
    data %>%
      filter(!is.nan(ev_time)) %>%
      filter(!is.infinite(ev_time)) %>%
      filter(!is.nan(outcome)) %>%
      filter(!is.infinite(outcome)) %>%
      filter(ev_time > 0) %>%
      filter(!is.na(ev_time)) %>%
      filter(!is.na(outcome)) %>%
      filter(outcome %in% c(0, 1))
  }
  
  train_clean <- clean_data(train_data)
  test_clean <- clean_data(test_data)
  
  # Prepare features
  feature_exclusion_cols <- c("ev_time", "outcome")
  
  train_features <- train_clean %>%
    select(!(matches(paste(survival_lagging_keywords, collapse = "|")) | starts_with("sd"))) %>%
    select(-any_of(feature_exclusion_cols)) %>%
    mutate(across(where(is.character), as.factor))
  
  test_features <- test_clean %>%
    select(!(matches(paste(survival_lagging_keywords, collapse = "|")) | starts_with("sd"))) %>%
    select(-any_of(feature_exclusion_cols)) %>%
    mutate(across(where(is.character), as.factor))
  
  # Synchronize factor levels
  for (col in names(train_features)) {
    if (is.factor(train_features[[col]])) {
      train_levels <- levels(train_features[[col]])
      test_features[[col]] <- factor(test_features[[col]], levels = train_levels)
    }
  }
  
  # Create survival labels
  train_labels <- ifelse(train_clean$outcome == 1, 
                        train_clean$ev_time, 
                        -train_clean$ev_time)
  test_labels <- ifelse(test_clean$outcome == 1, 
                       test_clean$ev_time, 
                       -test_clean$ev_time)
  
  # Filter valid records
  valid_train_indices <- which(is.finite(train_labels) & train_labels != 0)
  train_labels <- train_labels[valid_train_indices]
  train_features <- train_features[valid_train_indices, ]
  
  valid_test_indices <- which(is.finite(test_labels) & test_labels != 0)
  test_labels <- test_labels[valid_test_indices]
  test_features <- test_features[valid_test_indices, ]
  
  # Create pools
  train_pool <- catboost.load_pool(data = train_features, label = train_labels)
  test_pool <- catboost.load_pool(data = test_features, label = test_labels)
  
  # Fit model
  set.seed(1997)
  params <- list(
    loss_function = 'Cox',
    eval_metric = 'Cox',
    iterations = 2000,
    depth = 4,
    verbose = FALSE
  )
  
  model <- catboost.train(
    learn_pool = train_pool,
    test_pool = test_pool,
    params = params
  )
  
  # Get predictions
  predictions <- catboost.predict(model, test_pool)
  inverted_scores <- -1 * predictions
  
  # Calculate C-index
  test_time <- abs(test_labels)
  test_status <- ifelse(test_labels > 0, 1, 0)
  surv_obj_test <- Surv(test_time, test_status)
  c_index <- survival::concordance(surv_obj_test ~ inverted_scores)
  
  return(as.numeric(c_index$concordance))
}

# Main analysis
cat("=== Starting Cohort C-index Analysis ===\n")

# Define cohorts
cohorts <- define_cohorts(model_data)

# Initialize results
results <- data.frame(
  Cohort = character(),
  Model = character(),
  C_Index = numeric(),
  stringsAsFactors = FALSE
)

# Analyze each cohort
for (cohort_name in names(cohorts)) {
  cat("\n=== Analyzing Cohort:", cohort_name, "===\n")
  
  cohort_data <- cohorts[[cohort_name]]
  cat("Cohort size:", nrow(cohort_data), "patients\n")
  
  if (nrow(cohort_data) < 50) {
    cat("Skipping", cohort_name, "- insufficient data (< 50 patients)\n")
    next
  }
  
  # Create train/test split
  split_data <- create_unified_train_test_split(cohort_data, cohort_name)
  
  # Fit models and calculate C-indexes
  tryCatch({
    lasso_cindex <- fit_lasso_model(split_data$train_data, split_data$test_data, cohort_name)
    results <- rbind(results, data.frame(Cohort = cohort_name, Model = "LASSO", C_Index = lasso_cindex))
    cat("LASSO C-index:", round(lasso_cindex, 4), "\n")
  }, error = function(e) {
    cat("LASSO failed:", e$message, "\n")
  })
  
  tryCatch({
    aorsf_cindex <- fit_aorsf_model(split_data$train_data, split_data$test_data, cohort_name)
    results <- rbind(results, data.frame(Cohort = cohort_name, Model = "AORSF", C_Index = aorsf_cindex))
    cat("AORSF C-index:", round(aorsf_cindex, 4), "\n")
  }, error = function(e) {
    cat("AORSF failed:", e$message, "\n")
  })
  
  tryCatch({
    catboost_cindex <- fit_catboost_model(split_data$train_data, split_data$test_data, cohort_name)
    results <- rbind(results, data.frame(Cohort = cohort_name, Model = "CatBoost", C_Index = catboost_cindex))
    cat("CatBoost C-index:", round(catboost_cindex, 4), "\n")
  }, error = function(e) {
    cat("CatBoost failed:", e$message, "\n")
  })
}

# Display results
cat("\n=== FINAL RESULTS ===\n")
print(results)

# Save results
write_csv(results, "cohort_cindex_results.csv")
cat("\nResults saved to cohort_cindex_results.csv\n")

# Create summary table
if (nrow(results) > 0) {
  summary_table <- results %>%
    pivot_wider(names_from = Model, values_from = C_Index) %>%
    arrange(Cohort)
  
  cat("\n=== SUMMARY TABLE ===\n")
  print(summary_table)
  
  # Save summary
  write_csv(summary_table, "cohort_cindex_summary.csv")
  cat("Summary saved to cohort_cindex_summary.csv\n")
}
