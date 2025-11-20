# Replicate 20-Feature Selection from Original Wisotzkey Study
# 
# This script replicates the feature selection methodology from the original study:
# - Uses RSF permutation importance to select top 20 features
# - Uses CatBoost feature importance to select top 20 features
# - Uses AORSF (Accelerated Oblique Random Survival Forest) feature importance to select top 20 features
# - Runs across three time periods:
#   1. Original study period (2010-2019)
#   2. Full study (2010-2024)
#   3. Full study without COVID years (exclude 2020-2023)
#
# Output: Comparison tables and CSV files with top 20 features for each method/time period

# Setup
library(here)
library(dplyr)
library(readr)
library(survival)
library(ranger)
library(recipes)  # Required for prep(), juice(), make_recipe()
library(tidyr)
library(tibble)  # Required for enframe()
library(purrr)
library(janitor)  # Required for clean_names() in clean_phts()
library(haven)  # Required for read_sas() in clean_phts()
library(riskRegression)  # For Score() function used in original study
library(prodlim)  # Required for ranger_predictrisk
library(aorsf)
library(catboost)


# Source required functions - check for correct path first
cat("Sourcing required functions...\n")
if (file.exists(here("graft-loss-parallel-processing", "scripts", "R", "clean_phts.R"))) {
  # Use graft-loss-parallel-processing path
  source(here("graft-loss-parallel-processing", "scripts", "R", "clean_phts.R"))
  source(here("graft-loss-parallel-processing", "scripts", "R", "make_final_features.R"))
  source(here("graft-loss-parallel-processing", "scripts", "R", "select_rsf.R"))
  source(here("graft-loss-parallel-processing", "scripts", "R", "make_recipe.R"))
  source(here("graft-loss-parallel-processing", "scripts", "R", "make_labels.R"))
} else if (file.exists(here("graft-loss", "R", "clean_phts.R"))) {
  # Try alternative path
  cat("Using alternative path: graft-loss/R/\n")
  source(here("graft-loss", "R", "clean_phts.R"))
  source(here("graft-loss", "R", "select_rsf.R"))
  source(here("graft-loss", "R", "make_final_features.R"))
  source(here("graft-loss", "R", "make_recipe.R"))
  if (file.exists(here("graft-loss", "R", "make_labels.R"))) {
    source(here("graft-loss", "R", "make_labels.R"))
  }
} else {
  stop("Cannot find required R scripts. Please run from project root.\n",
       "  Tried: graft-loss-parallel-processing/scripts/R/\n",
       "  Tried: graft-loss/R/")
}

# Configuration
n_predictors <- 20  # Target: will be adjusted to available Wisotzkey variables
n_trees_rsf <- 500  # Number of trees for RSF (matching original study)
n_trees_aorsf <- 100  # Number of trees for AORSF
horizon <- 1  # 1-year prediction horizon

# Define Wisotzkey variables (15 core variables from original study)
wisotzkey_variables <- c(
  "prim_dx",           # Primary Etiology
  "tx_mcsd",           # MCSD at Transplant (with underscore - derived column!)
  "chd_sv",            # Single Ventricle CHD
  "hxsurg",            # Surgeries Prior to Listing
  "txsa_r",            # Serum Albumin at Transplant
  "txbun_r",           # BUN at Transplant
  "txecmo",            # ECMO at Transplant
  "txpl_year",         # Transplant Year
  "weight_txpl",       # Recipient Weight at Transplant
  "txalt",             # ALT at Transplant (cleaned name, not txalt_r)
  "bmi_txpl",          # BMI at Transplant (created from weight/height)
  "pra_listing",       # PRA at Listing (created from lsfprat) - may be lsfprat in some datasets
  "egfr_tx",           # eGFR at Transplant (created from creatinine)
  "hxmed",             # Medical History at Listing
  "listing_year"       # Listing Year (created from txpl_year)
)

# Create output directory
output_dir <- here("replicate_20_features_output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat("=== Replicating 20-Feature Selection ===\n")
cat("Output directory:", output_dir, "\n\n")

# Load and prepare base data
cat("Loading base data...\n")

# Try to load data - handle different possible column names
phts_base <- tryCatch({
  clean_phts(
    min_txpl_year = 2010,
    predict_horizon = horizon,
    time = outcome_int_graft_loss,
    status = outcome_graft_loss,
    case = 'snake',
    set_to_na = c("", "unknown", "missing")
  )
}, error = function(e) {
  # Try alternative: load from saved RDS if available
  rds_path <- here("graft-loss-parallel-processing", "model_data", "phts_simple.rds")
  if (file.exists(rds_path)) {
    cat("Loading from RDS:", rds_path, "\n")
    return(readRDS(rds_path))
  } else {
    stop("Cannot load data: ", e$message)
  }
})

cat("Base data loaded:", nrow(phts_base), "rows,", ncol(phts_base), "columns\n")
cat("Column names:", paste(head(names(phts_base), 20), collapse = ", "), "...\n")

# Define time period filters
define_time_periods <- function(data) {
  periods <- list()
  
  if (!"txpl_year" %in% names(data)) {
    warning("txpl_year not found - using all data for all periods")
    periods$original <- data
    periods$full <- data
    periods$full_no_covid <- data
    return(periods)
  }
  
  # Original study period: 2010-2019
  periods$original <- data %>%
    filter(txpl_year >= 2010 & txpl_year <= 2019)
  
  # Full study: 2010-2024
  periods$full <- data %>%
    filter(txpl_year >= 2010)
  
  # Full study without COVID: exclude 2020-2023
  periods$full_no_covid <- data %>%
    filter(txpl_year >= 2010 & !(txpl_year >= 2020 & txpl_year <= 2023))
  
  return(periods)
}

# Prepare data for modeling (filter to Wisotzkey variables only)
prepare_modeling_data <- function(data) {
  # Find time and status columns (handle different naming conventions)
  time_col <- NULL
  status_col <- NULL
  
  # Try common time column names
  time_candidates <- c("time", "outcome_int_graft_loss", "int_graft_loss", "ev_time")
  for (col in time_candidates) {
    if (col %in% names(data)) {
      time_col <- col
      break
    }
  }
  
  # Try common status column names
  status_candidates <- c("status", "outcome_graft_loss", "graft_loss", "ev_type", "outcome")
  for (col in status_candidates) {
    if (col %in% names(data)) {
      status_col <- col
      break
    }
  }
  
  if (is.null(time_col) || is.null(status_col)) {
    stop("Cannot find time/status columns. Available columns: ", 
         paste(names(data), collapse = ", "))
  }
  
  # Rename to standard names (only if different)
  if (time_col != "time") {
    data <- data %>% rename(time = !!time_col)
  }
  if (status_col != "status") {
    data <- data %>% rename(status = !!status_col)
  }
  
  # Check which Wisotzkey variables are available in the data
  # Also check for alternative names (e.g., lsfprat instead of pra_listing)
  wisotzkey_alternatives <- list(
    "pra_listing" = c("pra_listing", "lsfprat", "lsfprab"),  # PRA at listing
    "tx_mcsd" = c("tx_mcsd", "txmcsd")  # MCSD at transplant
  )
  
  available_wisotzkey <- c()
  for (var in wisotzkey_variables) {
    if (var %in% names(data)) {
      available_wisotzkey <- c(available_wisotzkey, var)
    } else if (var %in% names(wisotzkey_alternatives)) {
      # Try alternatives
      for (alt in wisotzkey_alternatives[[var]]) {
        if (alt %in% names(data)) {
          available_wisotzkey <- c(available_wisotzkey, alt)
          break
        }
      }
    }
  }
  
  missing_wisotzkey <- setdiff(wisotzkey_variables, available_wisotzkey)
  
  if (length(missing_wisotzkey) > 0) {
    cat("  Warning: Missing Wisotzkey variables:", paste(missing_wisotzkey, collapse = ", "), "\n")
  }
  
  cat("  Using", length(available_wisotzkey), "Wisotzkey variables:", 
      paste(available_wisotzkey, collapse = ", "), "\n")
  
  # Select only Wisotzkey variables plus time, status, and ID columns
  keep_vars <- c("time", "status", "ID", "ptid_e", available_wisotzkey)
  keep_vars <- keep_vars[keep_vars %in% names(data)]  # Only keep vars that exist
  
  data <- data %>% select(all_of(keep_vars))
  
  # Filter out invalid survival data
  data <- data %>%
    filter(!is.na(time), !is.na(status), time > 0, status %in% c(0, 1))
  
  return(data)
}

# Helper function to calculate both time-dependent and time-independent C-index
# Returns a list with both cindex_td (time-dependent) and cindex_ti (time-independent)
# horizon parameter is required - if NULL, only time-independent is calculated
calculate_cindex <- function(time, status, risk_scores, horizon = NULL) {
  # Remove missing / invalid
  valid_idx <- !is.na(time) & !is.na(status) & !is.na(risk_scores) &
               is.finite(time) & is.finite(risk_scores) & time > 0
  
  time   <- as.numeric(time[valid_idx])
  status <- as.numeric(status[valid_idx])
  risk   <- as.numeric(risk_scores[valid_idx])
  
  n <- length(time)
  events <- sum(status == 1)
  cat("  [cindex] n =", n,
      " valid =", n,
      " events =", events)
  
  if (!is.null(horizon)) {
    cat(", horizon =", horizon)
  }
  cat("\n")
  
  if (n < 10 || events < 1) {
    return(list(cindex_td = NA_real_, cindex_ti = NA_real_))
  }
  if (length(unique(risk)) == 1) {
    return(list(cindex_td = 0.5, cindex_ti = 0.5))
  }
  
  # Always calculate time-independent Harrell's C-index
  num_conc_ti <- 0
  num_disc_ti <- 0
  num_ties_ti <- 0
  
  for (i in seq_len(n)) {
    if (status[i] != 1) next
    for (j in seq_len(n)) {
      if (i == j) next
      # Comparable if event time is earlier for i
      if (time[i] < time[j]) {
        if (risk[i] > risk[j]) {
          num_conc_ti <- num_conc_ti + 1
        } else if (risk[i] < risk[j]) {
          num_disc_ti <- num_disc_ti + 1
        } else {
          num_ties_ti <- num_ties_ti + 1
        }
      }
    }
  }
  
  denom_ti <- num_conc_ti + num_disc_ti + num_ties_ti
  if (denom_ti == 0) {
    cindex_ti <- NA_real_
  } else {
    c_raw_ti <- (num_conc_ti + 0.5 * num_ties_ti) / denom_ti
    cindex_ti <- max(c_raw_ti, 1 - c_raw_ti)  # Orientation-safe
  }
  
  # Calculate time-dependent C-index if horizon is provided
  cindex_td <- NA_real_
  if (!is.null(horizon) && is.finite(horizon) && horizon > 0) {
    # Time-dependent AUC: compare patients with events before horizon vs those at risk at horizon
    # This matches riskRegression::Score() behavior for time-dependent AUC
    num_conc_td <- 0
    num_disc_td <- 0
    num_ties_td <- 0
    
    # Identify patients with events before horizon (cases)
    event_before_horizon <- (status == 1) & (time <= horizon)
    
    # Identify patients at risk at horizon (controls):
    # - Patients with time > horizon (they were at risk at horizon, regardless of eventual status)
    # - Note: Patients censored before horizon (status == 0 & time <= horizon) are excluded
    #   because we don't know if they would have had an event before horizon
    at_risk_at_horizon <- (time > horizon)
    
    n_events_before <- sum(event_before_horizon)
    n_at_risk <- sum(at_risk_at_horizon)
    
    cat("  [cindex] Events before horizon:", n_events_before, 
        ", At risk at horizon:", n_at_risk, "\n")
    
    if (n_events_before > 0 && n_at_risk > 0) {
      # Compare each patient with event before horizon to each patient at risk at horizon
      for (i in seq_len(n)) {
        if (!event_before_horizon[i]) next  # Only consider patients with events before horizon
        
        for (j in seq_len(n)) {
          if (i == j) next
          if (!at_risk_at_horizon[j]) next  # Only compare to patients at risk at horizon
          
          # For time-dependent AUC: higher risk should predict event before horizon
          # Patient i has event before horizon (case), patient j is at risk at horizon (control)
          # So risk[i] > risk[j] is concordant (higher risk → event before horizon)
          if (risk[i] > risk[j]) {
            num_conc_td <- num_conc_td + 1
          } else if (risk[i] < risk[j]) {
            num_disc_td <- num_disc_td + 1
          } else {
            num_ties_td <- num_ties_td + 1
          }
        }
      }
      
      denom_td <- num_conc_td + num_disc_td + num_ties_td
      if (denom_td > 0) {
        c_raw_td <- (num_conc_td + 0.5 * num_ties_td) / denom_td
        cindex_td <- max(c_raw_td, 1 - c_raw_td)  # Orientation-safe
      }
    } else {
      cat("  [cindex] Warning: Insufficient events for time-dependent C-index\n")
    }
  }
  
  return(list(cindex_td = as.numeric(cindex_td), cindex_ti = as.numeric(cindex_ti)))
}

# Predict risk at given times from a ranger survival model
ranger_predictrisk <- function(object, newdata, times) {
  # Try several predict() interfaces for ranger
  ptemp <- NULL
  
  # 1) modern: new_data (sometimes used via tidymodels wrappers)
  ptemp <- tryCatch({
    predict(object, new_data = newdata, type = "response")$survival
  }, error = function(e) NULL)
  
  # 2) older: data
  if (is.null(ptemp)) {
    ptemp <- tryCatch({
      predict(object, data = newdata, type = "response")$survival
    }, error = function(e) NULL)
  }
  
  # 3) legacy: newdata
  if (is.null(ptemp)) {
    ptemp <- tryCatch({
      predict(object, newdata = newdata, type = "response")$survival
    }, error = function(e) NULL)
  }
  
  if (is.null(ptemp)) {
    stop("Could not call predict() on ranger object with any known interface")
  }
  
  # Log times and unique.death.times for debugging
  cat("    [ranger_predictrisk] times parameter:", times, "\n")
  cat("    [ranger_predictrisk] unique.death.times range:", 
      paste(range(object$unique.death.times, na.rm=TRUE), collapse=" to "), "\n")
  
  # Map requested eval time(s) to survival index
  pos <- prodlim::sindex(
    jump.times = object$unique.death.times,
    eval.times = times
  )
  
  cat("    [ranger_predictrisk] sindex pos:", paste(pos, collapse=", "), "\n")
  
  # survival matrix is n x T; handle times before first event (pos == 0)
  p <- cbind(1, ptemp)[, pos + 1, drop = FALSE]
  
  cat("    [ranger_predictrisk] Final risk matrix dim:", paste(dim(p), collapse="x"), "\n")
  
  # Return risk = 1 - survival at specified time(s)
  1 - p
}

# RSF Feature Selection with Permutation Importance and C-index
select_features_rsf <- function(data, n_predictors = 20, n_trees = 500, horizon = 1) {
  cat("  Running RSF feature selection (permutation importance)...\n")
  cat("  [RSF] Horizon parameter:", horizon, "\n")
  
  # Extract time and status before processing
  time_vec <- data$time
  status_vec <- data$status
  
  # Log time range to verify units
  cat("  [RSF] Time range:", paste(range(time_vec, na.rm=TRUE), collapse=" to "), "\n")
  cat("  [RSF] Time units check: If time is in years, horizon should be 1. If time is in days, horizon should be 365.\n")
  
  # Prepare data: remove ID, time, status for feature selection
  feature_data <- data %>%
    select(-any_of(c("ID", "ptid_e", "time", "status")))
  
  # Create recipe and prepare data
  recipe_prep <- make_recipe(data, dummy_code = FALSE) %>%
    prep()
  
  prepared_data <- juice(recipe_prep) %>%
    select(-any_of(c("ID", "ptid_e", "time", "status")))
  
  # Ensure time and status are available for RSF
  n_rows <- min(nrow(prepared_data), length(time_vec))
  
  # Create RSF data with time and status properly added
  # Remove any existing time/status columns from prepared_data first
  rsf_data <- prepared_data[1:n_rows, ] %>%
    select(-any_of(c("time", "status")))
  
  # Add time and status as new columns
  rsf_data$time <- time_vec[1:n_rows]
  rsf_data$status <- status_vec[1:n_rows]
  
  # Ensure time and status are numeric/integer
  rsf_data$time <- as.numeric(rsf_data$time)
  rsf_data$status <- as.integer(rsf_data$status)
  
  # Remove any rows with invalid survival data
  valid_rows <- !is.na(rsf_data$time) & !is.na(rsf_data$status) & 
                rsf_data$time > 0 & rsf_data$status %in% c(0, 1)
  rsf_data <- rsf_data[valid_rows, ]
  
  if (nrow(rsf_data) < 10) {
    stop("Not enough valid rows for RSF after filtering")
  }
  
  # Fit RSF with permutation importance
  rsf_model <- ranger(
    Surv(time, status) ~ .,
    data = rsf_data,
    num.trees = n_trees,
    importance = 'permutation',
    min.node.size = 20,
    splitrule = 'extratrees',
    num.random.splits = 10
  )
  
  # 1) Risk predictions at horizon using original-study ranger_predictrisk
  cat("  [RSF DEBUG] Calling ranger_predictrisk with horizon =", horizon, "\n")
  rsf_predictions <- tryCatch({
    risk_pred <- ranger_predictrisk(
      object  = rsf_model,
      newdata = rsf_data,
      times   = horizon
    )
    
    # Log raw prediction structure
    cat("  [RSF DEBUG] Raw prediction object:\n")
    cat("    Class:", paste(class(risk_pred), collapse=", "), "\n")
    cat("    Type:", typeof(risk_pred), "\n")
    if (is.matrix(risk_pred)) {
      cat("    Dimensions:", paste(dim(risk_pred), collapse="x"), "\n")
      cat("    First few values:", paste(head(risk_pred[, 1], 5), collapse=", "), "\n")
      cat("    Range:", paste(range(risk_pred[, 1], na.rm=TRUE), collapse=" to "), "\n")
    } else {
      cat("    Length:", length(risk_pred), "\n")
      cat("    First few values:", paste(head(risk_pred, 5), collapse=", "), "\n")
      cat("    Range:", paste(range(risk_pred, na.rm=TRUE), collapse=" to "), "\n")
    }
    
    # Extract as vector
    if (is.matrix(risk_pred)) {
      pred_vec <- as.numeric(risk_pred[, 1])
    } else {
      pred_vec <- as.numeric(risk_pred)
    }
    
    # Log extracted vector
    cat("  [RSF DEBUG] After extraction:\n")
    cat("    Class:", paste(class(pred_vec), collapse=", "), "\n")
    cat("    Length:", length(pred_vec), "\n")
    cat("    Any NA:", any(is.na(pred_vec)), "(", sum(is.na(pred_vec)), ")\n")
    cat("    Any Inf:", any(is.infinite(pred_vec)), "(", sum(is.infinite(pred_vec)), ")\n")
    cat("    Range:", paste(range(pred_vec, na.rm=TRUE), collapse=" to "), "\n")
    cat("    Summary:", paste(summary(pred_vec), collapse=", "), "\n")
    
    pred_vec
  }, error = function(e) {
    cat("  Warning: RSF risk prediction failed:", e$message, "\n")
    return(NULL)
  })
  
  # 2) C-index via riskRegression::Score (original study style)
  cindex_td <- NA_real_
  cindex_ti <- NA_real_
  if (!is.null(rsf_predictions)) {
    # Ensure predictions and data are aligned
    # Use original time_vec and status_vec (before recipe processing) to match CatBoost approach
    n_use <- min(length(rsf_predictions), length(time_vec), nrow(rsf_data))
    
    # Extract matching vectors (predictions are for rsf_data rows, which correspond to original data)
    # rsf_data was created from prepared_data[1:n_rows, ] with time_vec[1:n_rows] and status_vec[1:n_rows]
    # So we need to use the same indices
    rsf_time_vec <- time_vec[1:n_use]
    rsf_status_vec <- status_vec[1:n_use]
    rsf_pred_vec <- rsf_predictions[1:n_use]
    
    # Ensure no missing values (matching CatBoost approach)
    valid_idx <- !is.na(rsf_time_vec) & !is.na(rsf_status_vec) & 
                 !is.na(rsf_pred_vec) & 
                 is.finite(rsf_time_vec) & is.finite(rsf_pred_vec) &
                 rsf_time_vec > 0
    
    if (sum(valid_idx) < 10) {
      cat("  Warning: Too few valid observations for C-index\n")
    } else {
      # Build a clean scoring dataset from original vectors (like CatBoost does)
      # This ensures we use the same approach as CatBoost - clean vectors, no recipe artifacts
      score_data <- data.frame(
        time   = as.numeric(rsf_time_vec[valid_idx]),
        status = as.integer(rsf_status_vec[valid_idx]),
        row.names = NULL  # Ensure no row names
      )
      rsf_predictions_clean <- rsf_pred_vec[valid_idx]
      
      # Log what we're passing to Score()
      cat("  [RSF DEBUG] Before Score() call:\n")
      cat("    score_data rows:", nrow(score_data), "\n")
      cat("    predictions length:", length(rsf_predictions_clean), "\n")
      cat("    predictions class:", paste(class(rsf_predictions_clean), collapse=", "), "\n")
      pred_matrix <- as.matrix(rsf_predictions_clean)
      cat("    as.matrix() dim:", paste(dim(pred_matrix), collapse="x"), "\n")
      cat("    as.matrix() class:", paste(class(pred_matrix), collapse=", "), "\n")
      cat("    score_data$time range:", paste(range(score_data$time, na.rm=TRUE), collapse=" to "), "\n")
      cat("    score_data$status sum:", sum(score_data$status, na.rm=TRUE), "\n")
      cat("    horizon:", horizon, "\n")
      
      # Calculate both time-dependent and time-independent C-index
      cindex_result <- calculate_cindex(score_data$time, score_data$status, rsf_predictions_clean, horizon = horizon)
      cindex_ti <- cindex_result$cindex_ti
      
      # Try riskRegression::Score for time-dependent (matching original study)
      cindex_td <- tryCatch({
        evaluation <- riskRegression::Score(
          object  = list(RSF = pred_matrix),
          formula = survival::Surv(time, status) ~ 1,
          data    = score_data,  # Use clean data frame from original vectors (matching CatBoost)
          times   = horizon,
          summary = "risks",
          metrics = "auc",
          se.fit  = FALSE
        )
        
        auc_tab <- evaluation$AUC$score
        if ("times" %in% names(auc_tab)) {
          this_row <- which.min(abs(auc_tab$times - horizon))
        } else {
          this_row <- 1L
        }
        as.numeric(auc_tab$AUC[this_row])
      }, error = function(e) {
        cat("  Warning: Score() failed, using manual calculate_cindex():", e$message, "\n")
        # Fallback to manual time-dependent C-index calculation
        cindex_result$cindex_td
      })
    }
  }
    
    if (is.na(cindex_td)) {
      cat("  Warning: RSF time-dependent C-index is NA\n")
      cat("    Time range:", range(score_data$time, na.rm = TRUE), "\n")
      cat("    Status sum:", sum(score_data$status, na.rm = TRUE), "\n")
      cat("    Prediction range:", range(rsf_predictions, na.rm = TRUE), "\n")
    } else {
      cat("  RSF time-dependent C-index:", round(cindex_td, 4), "\n")
    }
    
    if (!is.na(cindex_ti)) {
      cat("  RSF time-independent C-index:", round(cindex_ti, 4), "\n")
    }
  } else {
    cat("  Warning: RSF predictions are NULL or empty\n")
  }
  
  # 3) Feature importance table
  importance_df <- tibble::enframe(rsf_model$variable.importance) %>%
    dplyr::arrange(dplyr::desc(value)) %>%
    dplyr::slice(1:n_predictors) %>%
    dplyr::rename(feature = name, importance = value)
  
  # Add both C-index columns
  importance_df$cindex_td <- cindex_td
  importance_df$cindex_ti <- cindex_ti
  
  cat("  RSF selected", nrow(importance_df), "features\n")
  
  return(importance_df)
}

# Compute CatBoost C-index using riskRegression::Score
catboost_cindex_score <- function(predictions, time, status, horizon) {
  
  # Dependencies
  if (!requireNamespace("riskRegression", quietly = TRUE))
    stop("riskRegression package not installed.")
  if (!requireNamespace("survival", quietly = TRUE))
    stop("survival package not installed.")
  
  # Convert CatBoost signed-time predictions to risk scores
  # CatBoost: higher predicted signed-time → longer survival → lower risk
  # So risk = -predictions
  risk_scores <- -as.numeric(predictions)
  
  # Log CatBoost risk score conversion
  cat("  [CatBoost DEBUG] Risk score conversion:\n")
  cat("    Original predictions range:", paste(range(predictions, na.rm=TRUE), collapse=" to "), "\n")
  cat("    Risk scores range:", paste(range(risk_scores, na.rm=TRUE), collapse=" to "), "\n")
  cat("    Risk scores length:", length(risk_scores), "\n")
  cat("    Risk scores class:", paste(class(risk_scores), collapse=", "), "\n")
  
  # Construct data frame for Score()
  score_data <- data.frame(
    time   = as.numeric(time),
    status = as.numeric(status)
  )
  
  # Log before Score() call
  cat("  [CatBoost DEBUG] Before Score() call:\n")
  cat("    score_data rows:", nrow(score_data), "\n")
  cat("    risk_scores length:", length(risk_scores), "\n")
  risk_matrix <- as.matrix(risk_scores)
  cat("    as.matrix() dim:", paste(dim(risk_matrix), collapse="x"), "\n")
  cat("    as.matrix() class:", paste(class(risk_matrix), collapse=", "), "\n")
  cat("    score_data$time range:", paste(range(score_data$time, na.rm=TRUE), collapse=" to "), "\n")
  cat("    score_data$status sum:", sum(score_data$status, na.rm=TRUE), "\n")
  cat("    horizon:", horizon, "\n")
  
  # Calculate both time-dependent and time-independent C-index
  cindex_result <- calculate_cindex(time, status, risk_scores, horizon = horizon)
  cindex_ti <- cindex_result$cindex_ti
  
  # Try riskRegression::Score for time-dependent (matching original study)
  cindex_td <- tryCatch({
    evaluation <- riskRegression::Score(
      object  = list(CatBoost = risk_matrix),  # must be n × 1 matrix
      formula = survival::Surv(time, status) ~ 1,
      data    = score_data,
      times   = horizon,
      summary = "risks",
      metrics = "auc",
      se.fit  = FALSE
    )
    
    auc_tab <- evaluation$AUC$score
    
    # If multiple rows (multiple times), pick the closest to horizon
    if ("times" %in% names(auc_tab)) {
      this_row <- which.min(abs(auc_tab$times - horizon))
    } else {
      this_row <- 1L
    }
    
    as.numeric(auc_tab$AUC[this_row])
    
  }, error = function(e) {
    # Fallback to calculate_cindex if Score() fails
    cat("  Warning: Score() failed, using manual calculate_cindex():", e$message, "\n")
    cindex_result$cindex_td
  })
  
  return(list(cindex_td = cindex_td, cindex_ti = cindex_ti))
}

# CatBoost Feature Importance
select_features_catboost <- function(data, n_predictors = 20, horizon = 1) {
  cat("  Running CatBoost feature importance...\n")
  
  # Check if CatBoost is available (self-contained)
  catboost_available <- requireNamespace("catboost", quietly = TRUE)
  
  if (!catboost_available) {
    warning("CatBoost package not available - skipping CatBoost feature importance")
    return(NULL)
  }
  
  # Base feature set: remove ID, ptid_e, time, status
  feature_data <- data %>%
    select(-any_of(c("ID", "ptid_e", "time", "status")))
  
  # Create recipe (no dummy coding for CatBoost)
  recipe_prep <- tryCatch({
    make_recipe(data, dummy_code = FALSE) %>% prep()
  }, error = function(e) {
    cat("  Warning: Recipe preparation failed, using raw data:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(recipe_prep)) {
    # Fallback: use cleaned raw features
    prepared_data <- feature_data
  } else {
    prepared_data <- juice(recipe_prep) %>%
      # drop IDs
      select(-any_of(c("ID", "ptid_e"))) %>%
      # IMPORTANT: drop any outcome columns so they are not used as predictors
      select(-any_of(c("time", "status")))
  }
  
  # Ensure we have matching rows
  n_rows <- min(nrow(prepared_data), nrow(data))
  prepared_data <- prepared_data[1:n_rows, , drop = FALSE]
  
  # Prepare time and status for CatBoost (signed-time label)
  # +time for events, -time for censored
  time_vec   <- data$time[1:n_rows]
  status_vec <- data$status[1:n_rows]
  signed_time <- ifelse(status_vec == 1, time_vec, -time_vec)
  
  # Convert character columns to factors for CatBoost
  prepared_data <- prepared_data %>%
    mutate(across(where(is.character), as.factor))
  
  # Identify categorical features (factors only, not characters)
  cat_features <- which(vapply(prepared_data, is.factor, logical(1)))
  cat_indices <- if (length(cat_features) > 0) {
    as.numeric(cat_features) - 1  # CatBoost uses 0-based indexing
  } else {
    NULL
  }
  
  # Create CatBoost pool
  train_pool <- tryCatch({
    if (is.null(cat_indices)) {
      # No categorical features - don't pass cat_features parameter
      catboost::catboost.load_pool(
        data  = prepared_data,
        label = signed_time
      )
    } else {
      # Has categorical features
      catboost::catboost.load_pool(
        data        = prepared_data,
        label       = signed_time,
        cat_features = cat_indices
      )
    }
  }, error = function(e) {
    cat("  Error creating CatBoost pool:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(train_pool)) {
    return(NULL)
  }
  
  # Train CatBoost model
  catboost_params <- list(
    loss_function  = "RMSE",  # Using signed-time as regression proxy
    depth          = 6,
    learning_rate  = 0.05,
    iterations     = 2000,
    l2_leaf_reg    = 3.0,
    random_seed    = 42,
    verbose        = 0  
  )
  
  catboost_model <- tryCatch({
    catboost::catboost.train(train_pool, params = catboost_params)
  }, error = function(e) {
    cat("  Error training CatBoost model:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(catboost_model)) {
    return(NULL)
  }
  
  # Get predictions for C-index calculation
  catboost_predictions <- tryCatch({
    pred_raw <- catboost::catboost.predict(catboost_model, train_pool)
    
    # Log CatBoost prediction structure
    cat("  [CatBoost DEBUG] Raw prediction object:\n")
    cat("    Class:", paste(class(pred_raw), collapse=", "), "\n")
    cat("    Type:", typeof(pred_raw), "\n")
    cat("    Length:", length(pred_raw), "\n")
    cat("    First few values:", paste(head(pred_raw, 5), collapse=", "), "\n")
    cat("    Range:", paste(range(pred_raw, na.rm=TRUE), collapse=" to "), "\n")
    cat("    Any NA:", any(is.na(pred_raw)), "(", sum(is.na(pred_raw)), ")\n")
    cat("    Any Inf:", any(is.infinite(pred_raw)), "(", sum(is.infinite(pred_raw)), ")\n")
    cat("    Summary:", paste(summary(pred_raw), collapse=", "), "\n")
    
    pred_raw
  }, error = function(e) {
    cat("  Warning: Could not get CatBoost predictions:", e$message, "\n")
    return(NULL)
  })
  
  # Calculate C-index using original study method (riskRegression::Score)
  # For consistency with RSF, use the same C-index calculation method
  cindex_td <- NA_real_
  cindex_ti <- NA_real_
  if (!is.null(catboost_predictions)) {
    # Convert horizon from years to days for Score() if needed
    # (Score() expects times in same units as time variable)
    # Since time is in years and horizon is in years, use as-is
    cindex_result <- catboost_cindex_score(
      predictions = catboost_predictions,  # signed-time
      time        = time_vec,
      status      = status_vec,
      horizon     = horizon
    )
    
    cindex_td <- cindex_result$cindex_td
    cindex_ti <- cindex_result$cindex_ti
    
    if (is.na(cindex_td)) {
      cat("  Warning: CatBoost time-dependent C-index calculation returned NA\n")
      cat("    Time range:", range(time_vec, na.rm = TRUE), "\n")
      cat("    Status sum:", sum(status_vec, na.rm = TRUE), "\n")
    } else {
      cat("  CatBoost time-dependent C-index:", round(cindex_td, 4), "\n")
    }
    
    if (!is.na(cindex_ti)) {
      cat("  CatBoost time-independent C-index:", round(cindex_ti, 4), "\n")
    }
  }
  
  # Extract feature importance
  importance_raw <- tryCatch({
    catboost::catboost.get_feature_importance(
      catboost_model,
      pool = train_pool,
      type = "FeatureImportance"
    )
  }, error = function(e) {
    cat("  Error extracting CatBoost importance:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(importance_raw)) {
    return(NULL)
  }
  
  # Create importance data frame
  importance_df <- data.frame(
    feature    = names(prepared_data),
    importance = as.numeric(importance_raw),
    stringsAsFactors = FALSE
  ) %>%
    arrange(desc(importance)) %>%
    slice(1:min(n_predictors, nrow(.))) %>%
    mutate(cindex_td = cindex_td, cindex_ti = cindex_ti)
  
  cat("  CatBoost selected", nrow(importance_df), "features\n")
  
  return(importance_df)
}

# AORSF Feature Importance
select_features_aorsf <- function(data, n_predictors = 20, n_trees = 100, horizon = 1) {
  cat("  Running AORSF feature importance...\n")
  
  # Check if AORSF is available (self-contained)
  aorsf_available <- requireNamespace("aorsf", quietly = TRUE)
  
  if (!aorsf_available) {
    warning("aorsf package not available - skipping AORSF feature importance")
    return(NULL)
  }
  
  # Extract time and status before processing
  time_vec <- data$time
  status_vec <- data$status
  
  # Prepare data: remove ID, time, status for feature selection
  feature_data <- data %>%
    select(-any_of(c("ID", "ptid_e", "time", "status")))
  
  # Create recipe and prepare data
  recipe_prep <- tryCatch({
    make_recipe(data, dummy_code = FALSE) %>% prep()
  }, error = function(e) {
    cat("  Warning: Recipe preparation failed, using raw data:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(recipe_prep)) {
    # Fallback: use cleaned raw features
    prepared_data <- feature_data
  } else {
    prepared_data <- juice(recipe_prep) %>%
      select(-any_of(c("ID", "ptid_e", "time", "status")))
  }
  
  # Ensure we have matching rows
  n_rows <- min(nrow(prepared_data), length(time_vec))
  
  # Create AORSF data with time and status properly added
  aorsf_data <- prepared_data[1:n_rows, , drop = FALSE] %>%
    select(-any_of(c("time", "status")))
  
  # Add time and status as new columns
  aorsf_data$time <- time_vec[1:n_rows]
  aorsf_data$status <- status_vec[1:n_rows]
  
  # Ensure time and status are numeric/integer
  aorsf_data$time <- as.numeric(aorsf_data$time)
  aorsf_data$status <- as.integer(aorsf_data$status)
  
  # Remove any rows with invalid survival data
  valid_rows <- !is.na(aorsf_data$time) & !is.na(aorsf_data$status) & 
                aorsf_data$time > 0 & aorsf_data$status %in% c(0, 1)
  aorsf_data <- aorsf_data[valid_rows, ]
  
  if (nrow(aorsf_data) < 10) {
    stop("Not enough valid rows for AORSF after filtering")
  }
  
  # Remove constant columns (AORSF requirement)
  constant_cols <- names(aorsf_data)[sapply(aorsf_data, function(x) {
    if (is.numeric(x)) {
      length(unique(na.omit(x))) == 1
    } else {
      length(unique(na.omit(x))) == 1
    }
  })]
  
  if (length(constant_cols) > 0) {
    cat("  Removing constant columns:", paste(constant_cols, collapse = ", "), "\n")
    aorsf_data <- aorsf_data %>% select(-all_of(constant_cols))
  }
  
  # Convert character columns to factors for AORSF
  aorsf_data <- aorsf_data %>%
    mutate(across(where(is.character), as.factor))
  
  # Fit AORSF model
  aorsf_model <- tryCatch({
    set.seed(42)
    aorsf::orsf(
      data = aorsf_data,
      formula = Surv(time, status) ~ .,
      n_tree = n_trees,
      na_action = 'impute_meanmode'
    )
  }, error = function(e) {
    cat("  Error fitting AORSF model:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(aorsf_model)) {
    return(NULL)
  }
  
  # Get predictions for C-index calculation
  aorsf_predictions <- tryCatch({
    risk_pred <- predict(aorsf_model, new_data = aorsf_data, pred_type = 'risk', pred_horizon = horizon)
    
    # Log AORSF prediction structure
    cat("  [AORSF DEBUG] Raw prediction object:\n")
    cat("    Class:", paste(class(risk_pred), collapse=", "), "\n")
    cat("    Type:", typeof(risk_pred), "\n")
    if (is.matrix(risk_pred)) {
      cat("    Dimensions:", paste(dim(risk_pred), collapse="x"), "\n")
      cat("    First few values:", paste(head(risk_pred[, 1], 5), collapse=", "), "\n")
      cat("    Range:", paste(range(risk_pred[, 1], na.rm=TRUE), collapse=" to "), "\n")
    } else {
      cat("    Length:", length(risk_pred), "\n")
      cat("    First few values:", paste(head(risk_pred, 5), collapse=", "), "\n")
      cat("    Range:", paste(range(risk_pred, na.rm=TRUE), collapse=" to "), "\n")
    }
    
    # Extract as vector
    if (is.matrix(risk_pred)) {
      pred_vec <- as.numeric(risk_pred[, 1])
    } else {
      pred_vec <- as.numeric(risk_pred)
    }
    
    # Log extracted vector
    cat("  [AORSF DEBUG] After extraction:\n")
    cat("    Class:", paste(class(pred_vec), collapse=", "), "\n")
    cat("    Length:", length(pred_vec), "\n")
    cat("    Any NA:", any(is.na(pred_vec)), "(", sum(is.na(pred_vec)), ")\n")
    cat("    Any Inf:", any(is.infinite(pred_vec)), "(", sum(is.infinite(pred_vec)), ")\n")
    cat("    Range:", paste(range(pred_vec, na.rm=TRUE), collapse=" to "), "\n")
    
    pred_vec
  }, error = function(e) {
    cat("  Warning: AORSF risk prediction failed:", e$message, "\n")
    return(NULL)
  })
  
  # Calculate C-index using riskRegression::Score (consistent with RSF and CatBoost)
  cindex_td <- NA_real_
  cindex_ti <- NA_real_
  if (!is.null(aorsf_predictions)) {
    # Ensure predictions and data are aligned
    n_use <- min(length(aorsf_predictions), nrow(aorsf_data))
    
    aorsf_time_vec <- aorsf_data$time[1:n_use]
    aorsf_status_vec <- aorsf_data$status[1:n_use]
    aorsf_pred_vec <- aorsf_predictions[1:n_use]
    
    # Ensure no missing values
    valid_idx <- !is.na(aorsf_time_vec) & !is.na(aorsf_status_vec) & 
                 !is.na(aorsf_pred_vec) & 
                 is.finite(aorsf_time_vec) & is.finite(aorsf_pred_vec) &
                 aorsf_time_vec > 0
    
    if (sum(valid_idx) < 10) {
      cat("  Warning: Too few valid observations for C-index\n")
    } else {
      # Build a clean scoring dataset
      score_data <- data.frame(
        time   = as.numeric(aorsf_time_vec[valid_idx]),
        status = as.integer(aorsf_status_vec[valid_idx]),
        row.names = NULL
      )
      aorsf_predictions_clean <- aorsf_pred_vec[valid_idx]
      
      # Log what we're passing to Score()
      cat("  [AORSF DEBUG] Before Score() call:\n")
      cat("    score_data rows:", nrow(score_data), "\n")
      cat("    predictions length:", length(aorsf_predictions_clean), "\n")
      pred_matrix <- as.matrix(aorsf_predictions_clean)
      cat("    as.matrix() dim:", paste(dim(pred_matrix), collapse="x"), "\n")
      cat("    score_data$time range:", paste(range(score_data$time, na.rm=TRUE), collapse=" to "), "\n")
      cat("    score_data$status sum:", sum(score_data$status, na.rm=TRUE), "\n")
      cat("    horizon:", horizon, "\n")
      
      # Calculate both time-dependent and time-independent C-index
      cindex_result <- calculate_cindex(score_data$time, score_data$status, aorsf_predictions_clean, horizon = horizon)
      cindex_ti <- cindex_result$cindex_ti
      
      # Try riskRegression::Score for time-dependent (matching original study)
      cindex_td <- tryCatch({
        evaluation <- riskRegression::Score(
          object  = list(AORSF = pred_matrix),
          formula = survival::Surv(time, status) ~ 1,
          data    = score_data,
          times   = horizon,
          summary = "risks",
          metrics = "auc",
          se.fit  = FALSE
        )
        
        auc_tab <- evaluation$AUC$score
        if ("times" %in% names(auc_tab)) {
          this_row <- which.min(abs(auc_tab$times - horizon))
        } else {
          this_row <- 1L
        }
        as.numeric(auc_tab$AUC[this_row])
      }, error = function(e) {
        cat("  Warning: Score() failed, using manual calculate_cindex():", e$message, "\n")
        # Fallback to manual time-dependent C-index calculation
        cindex_result$cindex_td
      })
    }
    
    if (is.na(cindex_td)) {
      cat("  Warning: AORSF time-dependent C-index is NA\n")
    } else {
      cat("  AORSF time-dependent C-index:", round(cindex_td, 4), "\n")
    }
    
    if (!is.na(cindex_ti)) {
      cat("  AORSF time-independent C-index:", round(cindex_ti, 4), "\n")
    }
  } else {
    cat("  Warning: AORSF predictions are NULL or empty\n")
  }
  
  # Extract feature importance using negate method (most common)
  importance_raw <- tryCatch({
    aorsf::orsf_vi_negate(aorsf_model)
  }, error = function(e) {
    cat("  Error extracting AORSF importance:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(importance_raw)) {
    return(NULL)
  }
  
  # Create importance data frame
  importance_df <- tibble::enframe(importance_raw, name = "feature", value = "importance") %>%
    dplyr::arrange(dplyr::desc(importance)) %>%
    dplyr::slice(1:min(n_predictors, nrow(.))) %>%
    dplyr::mutate(cindex_td = cindex_td, cindex_ti = cindex_ti)
  
  cat("  AORSF selected", nrow(importance_df), "features\n")
  
  return(importance_df)
}

# Main analysis function
analyze_time_period <- function(period_name, period_data) {
  cat("\n=== Analyzing:", period_name, "===\n")
  cat("  Sample size:", nrow(period_data), "patients\n")
  cat("  Event rate:", round(mean(period_data$status, na.rm = TRUE) * 100, 2), "%\n")
  
  if (nrow(period_data) < 100) {
    warning(paste("Sample size too small for", period_name, "- skipping"))
    return(NULL)
  }
  
  # Prepare data (filters to Wisotzkey variables only)
  prepared_data <- prepare_modeling_data(period_data)
  
  if (nrow(prepared_data) < 50) {
    warning(paste("Too few valid rows after preparation for", period_name, "- skipping"))
    return(NULL)
  }
  
  # Adjust n_predictors to available Wisotzkey variables
  # Count predictor variables (exclude time, status, ID columns)
  predictor_vars <- setdiff(names(prepared_data), c("time", "status", "ID", "ptid_e"))
  n_available <- length(predictor_vars)
  n_predictors_adj <- min(n_predictors, n_available)
  
  if (n_predictors_adj < n_predictors) {
    cat("  Note: Requested", n_predictors, "predictors but only", n_available, 
        "Wisotzkey variables available. Using", n_predictors_adj, "predictors.\n")
  }
  
  # RSF feature selection
  rsf_features <- tryCatch({
    select_features_rsf(prepared_data, n_predictors = n_predictors_adj, n_trees = n_trees_rsf, horizon = horizon)
  }, error = function(e) {
    cat("  ERROR in RSF feature selection:", e$message, "\n")
    return(NULL)
  })
  
  # CatBoost feature importance
  catboost_features <- tryCatch({
    select_features_catboost(prepared_data, n_predictors = n_predictors_adj, horizon = horizon)
  }, error = function(e) {
    cat("  ERROR in CatBoost feature importance:", e$message, "\n")
    return(NULL)
  })
  
  # AORSF feature importance
  aorsf_features <- tryCatch({
    select_features_aorsf(prepared_data, n_predictors = n_predictors_adj, n_trees = n_trees_aorsf, horizon = horizon)
  }, error = function(e) {
    cat("  ERROR in AORSF feature importance:", e$message, "\n")
    return(NULL)
  })
  
  # Extract C-index values (both time-dependent and time-independent)
  rsf_cindex_td <- if (!is.null(rsf_features) && "cindex_td" %in% names(rsf_features)) {
    rsf_features$cindex_td[1]
  } else {
    NA_real_
  }
  
  rsf_cindex_ti <- if (!is.null(rsf_features) && "cindex_ti" %in% names(rsf_features)) {
    rsf_features$cindex_ti[1]
  } else {
    NA_real_
  }
  
  catboost_cindex_td <- if (!is.null(catboost_features) && "cindex_td" %in% names(catboost_features)) {
    catboost_features$cindex_td[1]
  } else {
    NA_real_
  }
  
  catboost_cindex_ti <- if (!is.null(catboost_features) && "cindex_ti" %in% names(catboost_features)) {
    catboost_features$cindex_ti[1]
  } else {
    NA_real_
  }
  
  aorsf_cindex_td <- if (!is.null(aorsf_features) && "cindex_td" %in% names(aorsf_features)) {
    aorsf_features$cindex_td[1]
  } else {
    NA_real_
  }
  
  aorsf_cindex_ti <- if (!is.null(aorsf_features) && "cindex_ti" %in% names(aorsf_features)) {
    aorsf_features$cindex_ti[1]
  } else {
    NA_real_
  }
  
  # Combine results
  results <- list(
    period = period_name,
    n_patients = nrow(prepared_data),
    event_rate = mean(prepared_data$status, na.rm = TRUE),
    rsf_features = rsf_features,
    catboost_features = catboost_features,
    aorsf_features = aorsf_features,
    rsf_cindex_td = rsf_cindex_td,
    rsf_cindex_ti = rsf_cindex_ti,
    catboost_cindex_td = catboost_cindex_td,
    catboost_cindex_ti = catboost_cindex_ti,
    aorsf_cindex_td = aorsf_cindex_td,
    aorsf_cindex_ti = aorsf_cindex_ti
  )
  
  return(results)
}

# Run analysis for all time periods
cat("\n=== Defining Time Periods ===\n")
time_periods <- define_time_periods(phts_base)

cat("Original study (2010-2019):", nrow(time_periods$original), "patients\n")
cat("Full study (2010-2024):", nrow(time_periods$full), "patients\n")
cat("Full study without COVID (exclude 2020-2023):", nrow(time_periods$full_no_covid), "patients\n")

# Analyze each period
all_results <- list()
all_results$original <- analyze_time_period("original_study_2010_2019", time_periods$original)
all_results$full <- analyze_time_period("full_study_2010_2024", time_periods$full)
all_results$full_no_covid <- analyze_time_period("full_study_no_covid_2010_2024_excl_2020_2023", time_periods$full_no_covid)

# Save individual results
cat("\n=== Saving Results ===\n")
for (period_name in names(all_results)) {
  if (is.null(all_results[[period_name]])) next
  
  results <- all_results[[period_name]]
  
  # Save RSF features
  if (!is.null(results$rsf_features)) {
    rsf_file <- file.path(output_dir, paste0(period_name, "_rsf_top20.csv"))
    write_csv(results$rsf_features, rsf_file)
    cat("  Saved:", rsf_file, "\n")
  }
  
  # Save CatBoost features
  if (!is.null(results$catboost_features)) {
    catboost_file <- file.path(output_dir, paste0(period_name, "_catboost_top20.csv"))
    write_csv(results$catboost_features, catboost_file)
    cat("  Saved:", catboost_file, "\n")
  }
  
  # Save AORSF features
  if (!is.null(results$aorsf_features)) {
    aorsf_file <- file.path(output_dir, paste0(period_name, "_aorsf_top20.csv"))
    write_csv(results$aorsf_features, aorsf_file)
    cat("  Saved:", aorsf_file, "\n")
  }
}

# Create comparison tables
cat("\n=== Creating Comparison Tables ===\n")

# RSF comparison across periods
rsf_comparison <- map_dfr(names(all_results), function(period_name) {
  if (is.null(all_results[[period_name]]) || is.null(all_results[[period_name]]$rsf_features)) {
    return(NULL)
  }
  all_results[[period_name]]$rsf_features %>%
    mutate(period = period_name, rank = row_number()) %>%
    select(period, rank, feature, importance, cindex_td, cindex_ti)
})

if (nrow(rsf_comparison) > 0) {
  rsf_comparison_file <- file.path(output_dir, "rsf_comparison_all_periods.csv")
  write_csv(rsf_comparison, rsf_comparison_file)
  cat("  Saved:", rsf_comparison_file, "\n")
  
  # Create wide format comparison
  rsf_wide <- rsf_comparison %>%
    select(period, rank, feature) %>%
    pivot_wider(names_from = period, values_from = feature, values_fill = NA)
  
  rsf_wide_file <- file.path(output_dir, "rsf_comparison_wide.csv")
  write_csv(rsf_wide, rsf_wide_file)
  cat("  Saved:", rsf_wide_file, "\n")
}

# CatBoost comparison across periods
catboost_comparison <- map_dfr(names(all_results), function(period_name) {
  if (is.null(all_results[[period_name]]) || is.null(all_results[[period_name]]$catboost_features)) {
    return(NULL)
  }
  all_results[[period_name]]$catboost_features %>%
    mutate(period = period_name, rank = row_number()) %>%
    select(period, rank, feature, importance, cindex_td, cindex_ti)
})

if (nrow(catboost_comparison) > 0) {
  catboost_comparison_file <- file.path(output_dir, "catboost_comparison_all_periods.csv")
  write_csv(catboost_comparison, catboost_comparison_file)
  cat("  Saved:", catboost_comparison_file, "\n")
  
  # Create wide format comparison
  catboost_wide <- catboost_comparison %>%
    select(period, rank, feature) %>%
    pivot_wider(names_from = period, values_from = feature, values_fill = NA)
  
  catboost_wide_file <- file.path(output_dir, "catboost_comparison_wide.csv")
  write_csv(catboost_wide, catboost_wide_file)
  cat("  Saved:", catboost_wide_file, "\n")
}

# AORSF comparison across periods
aorsf_comparison <- map_dfr(names(all_results), function(period_name) {
  if (is.null(all_results[[period_name]]) || is.null(all_results[[period_name]]$aorsf_features)) {
    return(NULL)
  }
  all_results[[period_name]]$aorsf_features %>%
    mutate(period = period_name, rank = row_number()) %>%
    select(period, rank, feature, importance, cindex_td, cindex_ti)
})

if (nrow(aorsf_comparison) > 0) {
  aorsf_comparison_file <- file.path(output_dir, "aorsf_comparison_all_periods.csv")
  write_csv(aorsf_comparison, aorsf_comparison_file)
  cat("  Saved:", aorsf_comparison_file, "\n")
  
  # Create wide format comparison
  aorsf_wide <- aorsf_comparison %>%
    select(period, rank, feature) %>%
    pivot_wider(names_from = period, values_from = feature, values_fill = NA)
  
  aorsf_wide_file <- file.path(output_dir, "aorsf_comparison_wide.csv")
  write_csv(aorsf_wide, aorsf_wide_file)
  cat("  Saved:", aorsf_wide_file, "\n")
}

# Feature overlap analysis
cat("\n=== Feature Overlap Analysis ===\n")

# RSF overlap
if (nrow(rsf_comparison) > 0) {
  rsf_features_by_period <- rsf_comparison %>%
    group_by(period) %>%
    summarise(features = list(feature), .groups = 'drop')
  
  if (nrow(rsf_features_by_period) > 1) {
    # Find common features across all periods
    all_rsf_features <- Reduce(intersect, rsf_features_by_period$features)
    cat("RSF features common to all periods:", length(all_rsf_features), "\n")
    if (length(all_rsf_features) > 0) {
      cat("  ", paste(head(all_rsf_features, 10), collapse = ", "), "\n")
    }
    
    # Save overlap analysis
    overlap_file <- file.path(output_dir, "rsf_feature_overlap.csv")
    write_csv(data.frame(feature = all_rsf_features), overlap_file)
    cat("  Saved:", overlap_file, "\n")
  }
}

# CatBoost overlap
if (nrow(catboost_comparison) > 0) {
  catboost_features_by_period <- catboost_comparison %>%
    group_by(period) %>%
    summarise(features = list(feature), .groups = 'drop')
  
  if (nrow(catboost_features_by_period) > 1) {
    # Find common features across all periods
    all_catboost_features <- Reduce(intersect, catboost_features_by_period$features)
    cat("CatBoost features common to all periods:", length(all_catboost_features), "\n")
    if (length(all_catboost_features) > 0) {
      cat("  ", paste(head(all_catboost_features, 10), collapse = ", "), "\n")
    }
    
    # Save overlap analysis
    overlap_file <- file.path(output_dir, "catboost_feature_overlap.csv")
    write_csv(data.frame(feature = all_catboost_features), overlap_file)
    cat("  Saved:", overlap_file, "\n")
  }
}

# AORSF overlap
if (nrow(aorsf_comparison) > 0) {
  aorsf_features_by_period <- aorsf_comparison %>%
    group_by(period) %>%
    summarise(features = list(feature), .groups = 'drop')
  
  if (nrow(aorsf_features_by_period) > 1) {
    # Find common features across all periods
    all_aorsf_features <- Reduce(intersect, aorsf_features_by_period$features)
    cat("AORSF features common to all periods:", length(all_aorsf_features), "\n")
    if (length(all_aorsf_features) > 0) {
      cat("  ", paste(head(all_aorsf_features, 10), collapse = ", "), "\n")
    }
    
    # Save overlap analysis
    overlap_file <- file.path(output_dir, "aorsf_feature_overlap.csv")
    write_csv(data.frame(feature = all_aorsf_features), overlap_file)
    cat("  Saved:", overlap_file, "\n")
  }
}

# Summary statistics
cat("\n=== Summary Statistics ===\n")
summary_stats <- map_dfr(names(all_results), function(period_name) {
  if (is.null(all_results[[period_name]])) {
    return(data.frame(
      period = period_name,
      n_patients = NA,
      event_rate = NA,
      n_rsf_features = NA,
      n_catboost_features = NA,
      n_aorsf_features = NA,
      rsf_cindex_td = NA_real_,
      rsf_cindex_ti = NA_real_,
      catboost_cindex_td = NA_real_,
      catboost_cindex_ti = NA_real_,
      aorsf_cindex_td = NA_real_,
      aorsf_cindex_ti = NA_real_
    ))
  }
  results <- all_results[[period_name]]
  data.frame(
    period = period_name,
    n_patients = results$n_patients,
    event_rate = round(results$event_rate * 100, 2),
    n_rsf_features = ifelse(is.null(results$rsf_features), 0, nrow(results$rsf_features)),
    n_catboost_features = ifelse(is.null(results$catboost_features), 0, nrow(results$catboost_features)),
    n_aorsf_features = ifelse(is.null(results$aorsf_features), 0, nrow(results$aorsf_features)),
    rsf_cindex_td = round(ifelse(is.null(results$rsf_cindex_td), NA_real_, results$rsf_cindex_td), 4),
    rsf_cindex_ti = round(ifelse(is.null(results$rsf_cindex_ti), NA_real_, results$rsf_cindex_ti), 4),
    catboost_cindex_td = round(ifelse(is.null(results$catboost_cindex_td), NA_real_, results$catboost_cindex_td), 4),
    catboost_cindex_ti = round(ifelse(is.null(results$catboost_cindex_ti), NA_real_, results$catboost_cindex_ti), 4),
    aorsf_cindex_td = round(ifelse(is.null(results$aorsf_cindex_td), NA_real_, results$aorsf_cindex_td), 4),
    aorsf_cindex_ti = round(ifelse(is.null(results$aorsf_cindex_ti), NA_real_, results$aorsf_cindex_ti), 4)
  )
})

summary_file <- file.path(output_dir, "summary_statistics.csv")
write_csv(summary_stats, summary_file)
cat("  Saved:", summary_file, "\n")
print(summary_stats)

# Create combined C-index comparison table (both time-dependent and time-independent)
cat("\n=== Creating Combined C-index Comparison ===\n")

# Time-dependent C-index comparison
cindex_td_comparison <- summary_stats %>%
  select(period, rsf_cindex_td, catboost_cindex_td, aorsf_cindex_td) %>%
  pivot_longer(cols = c(rsf_cindex_td, catboost_cindex_td, aorsf_cindex_td),
               names_to = "method",
               values_to = "cindex") %>%
  mutate(
    method = case_when(
      method == "rsf_cindex_td" ~ "RSF",
      method == "catboost_cindex_td" ~ "CatBoost",
      method == "aorsf_cindex_td" ~ "AORSF",
      TRUE ~ method
    ),
    cindex_type = "time_dependent"
  )

# Time-independent C-index comparison
cindex_ti_comparison <- summary_stats %>%
  select(period, rsf_cindex_ti, catboost_cindex_ti, aorsf_cindex_ti) %>%
  pivot_longer(cols = c(rsf_cindex_ti, catboost_cindex_ti, aorsf_cindex_ti),
               names_to = "method",
               values_to = "cindex") %>%
  mutate(
    method = case_when(
      method == "rsf_cindex_ti" ~ "RSF",
      method == "catboost_cindex_ti" ~ "CatBoost",
      method == "aorsf_cindex_ti" ~ "AORSF",
      TRUE ~ method
    ),
    cindex_type = "time_independent"
  )

# Combine both
cindex_comparison <- bind_rows(cindex_td_comparison, cindex_ti_comparison)

cindex_comparison_file <- file.path(output_dir, "cindex_comparison_all_methods.csv")
write_csv(cindex_comparison, cindex_comparison_file)
cat("  Saved:", cindex_comparison_file, "\n")

# Create wide format C-index comparison (time-dependent)
cindex_td_wide <- cindex_td_comparison %>%
  select(period, method, cindex) %>%
  pivot_wider(names_from = method, values_from = cindex)

cindex_td_wide_file <- file.path(output_dir, "cindex_td_comparison_wide.csv")
write_csv(cindex_td_wide, cindex_td_wide_file)
cat("  Saved:", cindex_td_wide_file, "\n")

# Create wide format C-index comparison (time-independent)
cindex_ti_wide <- cindex_ti_comparison %>%
  select(period, method, cindex) %>%
  pivot_wider(names_from = method, values_from = cindex)

cindex_ti_wide_file <- file.path(output_dir, "cindex_ti_comparison_wide.csv")
write_csv(cindex_ti_wide, cindex_ti_wide_file)
cat("  Saved:", cindex_ti_wide_file, "\n")

# Create combined wide format
cindex_wide <- summary_stats %>%
  select(period, rsf_cindex_td, rsf_cindex_ti, catboost_cindex_td, catboost_cindex_ti, 
         aorsf_cindex_td, aorsf_cindex_ti)

cindex_wide_file <- file.path(output_dir, "cindex_comparison_wide.csv")
write_csv(cindex_wide, cindex_wide_file)
cat("  Saved:", cindex_wide_file, "\n")

cat("\n=== Analysis Complete ===\n")
cat("All results saved to:", output_dir, "\n")
cat("\nMethods compared:\n")
cat("  - RSF: Random Survival Forest with permutation importance\n")
cat("  - CatBoost: Gradient boosting with feature importance\n")
cat("  - AORSF: Accelerated Oblique Random Survival Forest with negate importance\n")
cat("\nAll three methods provide:\n")
cat("  - Top 20 feature rankings\n")
cat("  - Feature importance scores\n")
cat("  - C-index (Concordance Index) performance metrics\n")

