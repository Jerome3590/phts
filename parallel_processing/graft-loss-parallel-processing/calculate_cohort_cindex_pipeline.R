#!/usr/bin/env Rscript
# Direct C-index calculation for cohorts using pipeline data structure
# Based on your existing pipeline approach

library(here)
library(dplyr)
library(tidyr)
library(survival)
library(glmnet)
library(aorsf)
library(catboost)
library(readr)
library(tibble)

# Set seed for reproducibility
set.seed(1997)

# Load data from your existing pipeline
cat("Loading data from pipeline...\n")

# Try to load from different possible locations
data_paths <- c(
  "model_data/phts_all_fixed.rds",  # Use fixed data first
  "model_data/phts_all.rds",
  "model_data/phts_all.csv",
  "data/phts_all.rds",
  "data/phts_all.csv"
)

model_data <- NULL
for (path in data_paths) {
  if (file.exists(path)) {
    cat("Loading data from:", path, "\n")
    if (grepl("\\.rds$", path)) {
      model_data <- readRDS(path)
    } else {
      model_data <- read_csv(path, show_col_types = FALSE)
    }
    break
  }
}

if (is.null(model_data)) {
  stop("Could not find data file. Please ensure phts_all.rds or phts_all.csv exists in model_data/ or data/ directory.")
}

cat("Dataset dimensions:", paste(dim(model_data), collapse = " x "), "\n")

# Check for required columns and rename if needed
if (!"time" %in% names(model_data)) {
  time_cols <- names(model_data)[grep("time|Time|TIME", names(model_data))]
  if (length(time_cols) > 0) {
    model_data <- model_data %>% rename(time = !!sym(time_cols[1]))
    cat("Renamed", time_cols[1], "to 'time'\n")
  } else {
    stop("No time column found")
  }
}

if (!"status" %in% names(model_data)) {
  status_cols <- names(model_data)[grep("status|Status|STATUS|outcome|Outcome|OUTCOME", names(model_data))]
  if (length(status_cols) > 0) {
    model_data <- model_data %>% rename(status = !!sym(status_cols[1]))
    cat("Renamed", status_cols[1], "to 'status'\n")
  } else {
    stop("No status column found")
  }
}

# Ensure data types
model_data <- model_data %>%
  mutate(
    status = as.integer(status),
    time = as.numeric(time)
  )

# Handle missing or invalid times
model_data <- model_data %>%
  filter(!is.na(time), !is.na(status), time > 0) %>%
  mutate(
    time = if_else(is.infinite(time), median(time, na.rm = TRUE), time)
  )

cat("Final dataset dimensions:", paste(dim(model_data), collapse = " x "), "\n")
cat("Event rate:", round(mean(model_data$status, na.rm = TRUE) * 100, 2), "%\n")

# Define study period filters based on available columns
define_cohorts <- function(data) {
  cohorts <- list()
  
  # Check for year column
  year_cols <- names(data)[grep("year|Year|YEAR|date|Date|DATE", names(data))]
  
  if (length(year_cols) > 0) {
    year_col <- year_cols[1]
    cat("Using year column:", year_col, "\n")
    
    # Original study (pre-COVID) - adjust dates as needed
    cohorts$original <- data %>% filter(!!sym(year_col) < 2020)
    
    # Full study with COVID (all data)
    cohorts$full_with_covid <- data
    
    # Non-COVID full study (exclude COVID period 2020-2023)
    cohorts$non_covid_full <- data %>% filter(!!sym(year_col) < 2020 | !!sym(year_col) > 2023)
  } else {
    # No year column - use all data for all cohorts
    cat("No year column found - using all data for all cohorts\n")
    cohorts$original <- data
    cohorts$full_with_covid <- data
    cohorts$non_covid_full <- data
  }
  
  return(cohorts)
}

# Define survival lagging keywords (from your template)
survival_lagging_keywords <- c(
  "transplant_year", "primary_etiology", "ptid_e",
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

# LASSO model function (based on your template)
fit_lasso_model <- function(train_data, test_data, cohort_name) {
  cat("Fitting LASSO model for", cohort_name, "\n")
  
  # Prepare data - remove lagging keywords and create matrices
  prepare_survival_data <- function(data) {
    data %>%
      select(!(matches(paste(survival_lagging_keywords, collapse = "|")) | starts_with("sd"))) %>%
      select(-time, -status) %>%  # Remove outcome variables
      mutate(across(where(is.character), as.factor)) %>%
      mutate(across(where(is.factor), as.numeric)) %>%
      mutate(across(everything(), ~if_else(is.na(.), median(., na.rm = TRUE), .))) %>%
      select(-where(~all(is.na(.))))  # Remove all-NA columns
  }
  
  train_features <- prepare_survival_data(train_data)
  test_features <- prepare_survival_data(test_data)
  
  # Ensure same columns
  common_cols <- intersect(names(train_features), names(test_features))
  train_features <- train_features %>% select(all_of(common_cols))
  test_features <- test_features %>% select(all_of(common_cols))
  
  # Create matrices
  y_train <- Surv(train_data$time, train_data$status)
  x_train <- as.matrix(train_features)
  y_test <- Surv(test_data$time, test_data$status)
  x_test <- as.matrix(test_features)
  
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

# AORSF model function (based on your template)
fit_aorsf_model <- function(train_data, test_data, cohort_name) {
  cat("Fitting AORSF model for", cohort_name, "\n")
  
  # Prepare data
  prepare_aorsf_data <- function(data) {
    data %>%
      select(!(matches(paste(survival_lagging_keywords, collapse = "|")) | starts_with("sd"))) %>%
      mutate(across(where(is.character), as.factor)) %>%
      select(-where(~all(is.na(.))))  # Remove all-NA columns
  }
  
  train_features <- prepare_aorsf_data(train_data)
  test_features <- prepare_aorsf_data(test_data)
  
  # Ensure same columns
  common_cols <- intersect(names(train_features), names(test_features))
  train_features <- train_features %>% select(all_of(common_cols))
  test_features <- test_features %>% select(all_of(common_cols))
  
  # Remove constant columns
  constant_cols <- names(train_features)[sapply(train_features, function(x) {
    length(unique(na.omit(x))) == 1
  })]
  if(length(constant_cols) > 0) {
    cat("Removing constant columns:", paste(constant_cols, collapse = ", "), "\n")
    train_features <- train_features %>% select(-all_of(constant_cols))
    test_features <- test_features %>% select(-all_of(constant_cols))
  }
  
  # Fit AORSF
  set.seed(1997)
  aorsf_model <- orsf(
    data = train_features,
    formula = Surv(time, status) ~ .,
    na_action = 'impute_meanmode',
    n_tree = 100
  )
  
  # Get predictions
  risk_scores <- predict(aorsf_model, new_data = test_features, pred_type = 'risk')
  surv_obj_test <- Surv(test_data$time, test_data$status)
  c_index <- survival::concordance(surv_obj_test ~ risk_scores)
  
  return(as.numeric(c_index$concordance))
}

# CatBoost model function (based on your template)
fit_catboost_model <- function(train_data, test_data, cohort_name) {
  cat("Fitting CatBoost model for", cohort_name, "\n")
  
  # Clean data for CatBoost
  clean_data <- function(data) {
    data %>%
      filter(!is.na(time), !is.na(status), time > 0, status %in% c(0, 1)) %>%
      filter(!is.infinite(time))
  }
  
  train_clean <- clean_data(train_data)
  test_clean <- clean_data(test_data)
  
  if (nrow(train_clean) < 10 || nrow(test_clean) < 5) {
    cat("Insufficient clean data for CatBoost\n")
    return(NA)
  }
  
  # Prepare features
  prepare_catboost_features <- function(data) {
    data %>%
      select(!(matches(paste(survival_lagging_keywords, collapse = "|")) | starts_with("sd"))) %>%
      select(-time, -status) %>%
      mutate(across(where(is.character), as.factor))
  }
  
  train_features <- prepare_catboost_features(train_clean)
  test_features <- prepare_catboost_features(test_clean)
  
  # Synchronize factor levels
  for (col in names(train_features)) {
    if (is.factor(train_features[[col]])) {
      train_levels <- levels(train_features[[col]])
      test_features[[col]] <- factor(test_features[[col]], levels = train_levels)
    }
  }
  
  # Create survival labels
  train_labels <- ifelse(train_clean$status == 1, 
                        train_clean$time, 
                        -train_clean$time)
  test_labels <- ifelse(test_clean$status == 1, 
                       test_clean$time, 
                       -test_clean$time)
  
  # Filter valid records
  valid_train_indices <- which(is.finite(train_labels) & train_labels != 0)
  train_labels <- train_labels[valid_train_indices]
  train_features <- train_features[valid_train_indices, ]
  
  valid_test_indices <- which(is.finite(test_labels) & test_labels != 0)
  test_labels <- test_labels[valid_test_indices]
  test_features <- test_features[valid_test_indices, ]
  
  if (length(train_labels) < 10 || length(test_labels) < 5) {
    cat("Insufficient valid labels for CatBoost\n")
    return(NA)
  }
  
  # Create pools
  train_pool <- catboost.load_pool(data = train_features, label = train_labels)
  test_pool <- catboost.load_pool(data = test_features, label = test_labels)
  
  # Fit model
  set.seed(1997)
  params <- list(
    loss_function = 'Cox',
    eval_metric = 'Cox',
    iterations = 1000,  # Reduced for speed
    depth = 4
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
    if (!is.na(catboost_cindex)) {
      results <- rbind(results, data.frame(Cohort = cohort_name, Model = "CatBoost", C_Index = catboost_cindex))
      cat("CatBoost C-index:", round(catboost_cindex, 4), "\n")
    }
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
} else {
  cat("No results generated - check data and model fitting errors\n")
}
