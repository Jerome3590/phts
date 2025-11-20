

# Unified train/test split function for all models
create_unified_train_test_split <- function(data, cohort_name, seed = 1997) {
  set.seed(seed)
  
  # Create reproducible random split
  n_total <- nrow(data)
  n_train <- floor(0.8 * n_total)
  
  # Create random indices
  all_indices <- 1:n_total
  train_indices <- sample(all_indices, size = n_train)
  test_indices <- setdiff(all_indices, train_indices)
  
  # Split the data
  train_data <- data[train_indices, ]
  test_data <- data[test_indices, ]
  
  # Store indices for other models to use
  split_info <- list(
    cohort = cohort_name,
    train_indices = train_indices,
    test_indices = test_indices,
    n_total = n_total,
    n_train = n_train,
    n_test = length(test_indices),
    seed = seed
  )
  
  cat("=== Unified Train/Test Split for", cohort_name, "===\n")
  cat("Total patients:", n_total, "\n")
  cat("Training set:", n_train, "patients\n")
  cat("Test set:", length(test_indices), "patients\n")
  cat("Split ratio:", round(n_train/n_total, 3), ":", round(length(test_indices)/n_total, 3), "\n")
  cat("Seed used:", seed, "\n")
  cat("=====================================\n\n")
  
  return(list(
    train_data = train_data,
    test_data = test_data,
    split_info = split_info
  ))
}

# clean for CatBoost
clean_survival_data_for_catboost <- function(data, time_col = "ev_time", status_col = "outcome") {
  
  # Check for problematic values
  cat("=== Data Quality Check ===\n")
  cat("Total rows:", nrow(data), "\n")
  cat("NaN in time:", sum(is.nan(data[[time_col]])), "\n")
  cat("NaN in status:", sum(is.nan(data[[status_col]])), "\n")
  cat("Inf in time:", sum(is.infinite(data[[time_col]])), "\n")
  cat("Negative time:", sum(data[[time_col]] < 0, na.rm = TRUE), "\n")
  cat("Zero time:", sum(data[[time_col]] == 0, na.rm = TRUE), "\n")
  cat("Missing time:", sum(is.na(data[[time_col]])), "\n")
  cat("Missing status:", sum(is.na(data[[status_col]])), "\n")
  
  # Clean the data
  cleaned_data <- data %>%
    # Remove rows with NaN or infinite values
    filter(!is.nan(!!sym(time_col))) %>%
    filter(!is.infinite(!!sym(time_col))) %>%
    filter(!is.nan(!!sym(status_col))) %>%
    filter(!is.infinite(!!sym(status_col))) %>%
    # Remove rows with negative or zero time
    filter(!!sym(time_col) > 0) %>%
    # Remove rows with missing values
    filter(!is.na(!!sym(time_col))) %>%
    filter(!is.na(!!sym(status_col))) %>%
    # Ensure status is binary (0 or 1)
    filter(!!sym(status_col) %in% c(0, 1))
  
  cat("Cleaned rows:", nrow(cleaned_data), "\n")
  cat("Rows removed:", nrow(data) - nrow(cleaned_data), "\n")
  
  return(cleaned_data)
}

# Clean for LASSO

nzv_cols <- function(df) {
  vapply(df, function(x) {
    ux <- unique(x)
    ux <- ux[!is.na(ux)]
    length(ux) < 2
  }, logical(1))
}


mode_level <- function(x) {
  ux <- na.omit(x)
  if (length(ux) == 0) return(NA)
  tab <- sort(table(ux), decreasing = TRUE)
  names(tab)[1]
}


impute_like <- function(df, like_df) {
  for (nm in names(df)) {
    if (is.numeric(df[[nm]])) {
      m <- median(like_df[[nm]], na.rm = TRUE)
      df[[nm]][is.na(df[[nm]])] <- m
    } else if (is.factor(df[[nm]])) {
      # ensure same levels; add "Other"
      base_lv <- levels(like_df[[nm]])
      if (!("Other" %in% base_lv)) base_lv <- c(base_lv, "Other")
      df[[nm]] <- factor(df[[nm]], levels = base_lv)
      # unseen -> NA -> "Other"
      df[[nm]][is.na(df[[nm]])] <- "Other"
    }
  }
  df
}


align_mm <- function(train_df, test_df) {
  Xtr <- model.matrix(~ . - 1, data = train_df)
  Xte <- model.matrix(~ . - 1, data = test_df)
  # pad/reorder test to train columns
  missing_in_test <- setdiff(colnames(Xtr), colnames(Xte))
  if (length(missing_in_test)) {
    Xte <- cbind(Xte, matrix(0, nrow(Xte), length(missing_in_test),
                             dimnames = list(NULL, missing_in_test)))
  }
  extra_in_test <- setdiff(colnames(Xte), colnames(Xtr))
  if (length(extra_in_test)) Xte <- Xte[, setdiff(colnames(Xte), extra_in_test), drop = FALSE]
  Xte <- Xte[, colnames(Xtr), drop = FALSE]
  list(Xtr = Xtr, Xte = Xte)
}

# Helper function to create comprehensive metrics for any model

create_survival_metrics <- function(cohort_name, model_name, concordance_obj) {
  
  # Check if the concordance object is valid
  if (is.null(concordance_obj) || !("concordance" %in% names(concordance_obj))) {
    warning(paste("Invalid concordance object for", model_name, cohort_name))
    return(NULL)
  }
  
  # Initialize the metrics list
  metrics <- list(
    Cohort = cohort_name,
    Model = model_name,
    C_Index = round(as.numeric(concordance_obj$concordance), 4)
    # AUC, Accuracy, F1, etc., are not calculated as they are for classification
  )
  
  return(metrics)
}


# Helper function to get top N features with normalized importance
get_top_features_normalized <- function(feature_df, cohort_name, model_name, n_features = 25) {
  if (nrow(feature_df) == 0) return(NULL)
  
  # Get top N features
  top_features <- feature_df %>%
    slice_head(n = n_features) %>%
    mutate(
      Cohort = cohort_name,
      Model = model_name,
      Rank = row_number()
    )
  
  # Normalize importance to 0-1 scale
  if ("importance" %in% colnames(top_features)) {
    top_features <- top_features %>%
      mutate(
        Normalized_Importance = (importance - min(importance)) / (max(importance) - min(importance))
      )
  } else if ("coefficient" %in% colnames(top_features)) {
    # For LASSO coefficients, use absolute values and normalize
    top_features <- top_features %>%
      mutate(
        importance = abs(coefficient),
        Normalized_Importance = (importance - min(importance)) / (max(importance) - min(importance))
      )
  }
  
  return(top_features)
}


# Helper function to create metrics summary table
create_metrics_summary <- function(metrics_list) {
  if (length(metrics_list) == 0) return(NULL)
  
  # Convert list of metrics to data frame
  metrics_df <- bind_rows(metrics_list)
  
  # Create summary by cohort and model
  summary_df <- metrics_df %>%
    group_by(Cohort, Model) %>%
    summarise(
      AUC = first(AUC),
      C_Index = first(C_Index),
      Accuracy = first(Accuracy),
      F1 = first(F1),
      Precision = first(Precision),
      Recall = first(Recall),
      Method = first(Method),
      .groups = 'drop'
    )
  
  return(list(
    full_metrics = metrics_df,
    summary = summary_df
  ))
}


# Time-fixing helpers
# Helper functions

create_classification_metrics <- function(
    probs,
    actual,
    cohort_name = "",
    model_name = "",
    threshold = 0.5
) {
  stopifnot(length(probs) == length(actual))
  
  # Clean rows
  idx <- !is.na(probs) & !is.na(actual)
  probs <- as.numeric(probs[idx])
  actual <- actual[idx]
  
  # Robust 0/1 coercion for 'actual'
  if (is.factor(actual)) actual <- as.character(actual)
  if (is.logical(actual)) actual <- as.integer(actual) else actual <- as.numeric(actual)
  
  # (Optional) sanity: ensure only 0/1 after coercion
  if (!all(actual %in% c(0, 1))) {
    warning("`actual` contains values outside {0,1} after coercion.")
  }
  
  # Thresholded predictions
  predictions <- ifelse(probs >= threshold, 1L, 0L)
  
  # Metrics
  accuracy  <- mean(predictions == actual)
  precision <- if (any(predictions == 1)) sum(predictions == 1 & actual == 1) / sum(predictions == 1) else 0
  recall    <- if (any(actual == 1))       sum(predictions == 1 & actual == 1) / sum(actual == 1)       else 0
  f1        <- if ((precision + recall) > 0) 2 * precision * recall / (precision + recall) else 0
  
  # ROC / AUC (coerce AUC to plain numeric to avoid bind_rows issues)
  auc_val <- tryCatch({
    roc_obj <- pROC::roc(factor(actual, levels = c(0, 1)), probs, quiet = TRUE)
    as.numeric(pROC::auc(roc_obj))
  }, error = function(e) NA_real_)
  
  # Brier score with numeric 0/1 actual
  brier <- mean((probs - actual)^2)
  
  # Count of predicted positives
  positive_preds <- sum(predictions)
  
  data.frame(
    Cohort = cohort_name,
    Model = model_name,
    Threshold = threshold,
    Accuracy = accuracy,
    Precision = precision,
    Recall = recall,
    F1 = f1,
    AUC = auc_val,                 # now plain numeric
    Brier_Score = brier,
    Predicted_Positives = positive_preds,
    stringsAsFactors = FALSE
  )
}


# Leakage control helpers

get_survival_leakage_keywords <- function() {
  c(
    # Identifiers and outcomes (handled separately in drop_cols)
    "transplant_year", "primary_etiology", "txpl_year",
    # Donor/survival variables and obvious leak sources
    "graft_loss", "int_graft_loss", "dtx_", "cc_", "isc_oth",
    "dcardiac", "dcon", "dpri", "dpricaus", "rec_", "papooth",
    "dneuro", "sdprathr", "int_dead", "listing_year", "cpathneg",
    "dcauseod",
    # Demographics (optional, keep if clinically needed)
    "race", "sex", "drace_b", "rrace_a", "hisp", "Iscntry",
    # Transplant-specific variables often post-outcome or unclear timing
    "dreject", "dsecaccsEmpty", "dmajbldEmpty", "pishltgr1R",
    "drejectEmpty", "drejectHyperacute", "pishltgrEmpty", "pishltgr",
    "dmajbld", "dsecaccs", "dsecaccs_bin",
    # Clinical variables to exclude (timing/definition risk)
    "dx_cardiomyopathy", "deathspc", "dlist", "pmorexam", "patsupp",
    "concod", "pcadrem", "pcadrec", "pathero", "pdiffib", "dmalcanc",
    "alt_tx", "age_death", "pacuref",
    # Additional variables
    "lsvcma", "cpbypass"
  )
}

remove_leakage_predictors <- function(
  df,
  leak_keywords = get_survival_leakage_keywords(),
  drop_cols = c("ptid_e", "ev_time", "ev_type", "outcome", "transplant_year"),
  drop_starts_with = c("sd")
) {
  nm <- names(df)
  pattern <- if (length(leak_keywords)) paste(leak_keywords, collapse = "|") else "^$"
  by_pattern <- grepl(pattern, nm)
  by_prefix <- rep(FALSE, length(nm))
  if (length(drop_starts_with)) {
    by_prefix <- Reduce(`|`, lapply(drop_starts_with, function(pref) startsWith(nm, pref)))
  }
  by_exact <- nm %in% drop_cols
  drop_set <- nm[by_pattern | by_prefix | by_exact]
  keep_set <- setdiff(nm, drop_set)
  cat("[LeakFilter] Dropping ", length(drop_set), " columns; keeping ", length(keep_set), " predictors\n", sep = "")
  if (length(drop_set)) cat("[LeakFilter] Dropped: ", paste(drop_set, collapse = ", "), "\n", sep = "")
  df[, keep_set, drop = FALSE]
}

assert_no_leakage_targets <- function(df, time_col = "time", status_col = "status") {
  if (time_col %in% names(df) && status_col %in% names(df)) {
    invisible(TRUE)
  } else {
    stop("Time/status columns missing after leakage filtering: ", time_col, "/", status_col)
  }
}

# C-index computation and logging

compute_c_index <- function(time, status, risk_scores) {
  # Clean lengths and NAs
  stopifnot(length(time) == length(status), length(status) == length(risk_scores))
  idx <- is.finite(time) & !is.na(status) & is.finite(risk_scores)
  time <- as.numeric(time[idx])
  status <- as.integer(status[idx])
  risk_scores <- as.numeric(risk_scores[idx])
  if (!length(time)) return(list(c_index = NA_real_, concordance = NULL, n = 0L))
  conc <- survival::concordance(survival::Surv(time, status) ~ risk_scores)
  list(c_index = as.numeric(conc$concordance), concordance = conc, n = length(time))
}

log_survival_cindex <- function(
  cohort_name,
  model_name,
  time,
  status,
  risk_scores,
  file = file.path("cohort_analysis", "survival_metrics.csv")
) {
  res <- compute_c_index(time, status, risk_scores)
  n_events <- sum(as.integer(status) == 1, na.rm = TRUE)
  row <- data.frame(
    Timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    Cohort = as.character(cohort_name),
    Model = as.character(model_name),
    N = as.integer(res$n),
    Events = as.integer(n_events),
    C_Index = round(as.numeric(res$c_index), 6),
    stringsAsFactors = FALSE
  )
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(file)) {
    readr::write_csv(row, file, append = TRUE)
  } else {
    readr::write_csv(row, file)
  }
  cat("[CIndex] ", cohort_name, " - ", model_name, ": C=", row$C_Index, ", N=", row$N, ", Events=", row$Events, " -> ", normalizePath(file, winslash = "/", mustWork = FALSE), "\n", sep = "")
  row
}


# Harrell and Uno time-dependent concordance utilities
compute_concordance_pair <- function(
    train_time,
    train_status,
    test_time,
    test_status,
    risk,
    tau = NULL
) {
  # Harrell's C on test set
  harrell <- tryCatch({
    as.numeric(
      survival::concordance(
        survival::Surv(as.numeric(test_time), as.integer(test_status)) ~ as.numeric(risk)
      )$concordance
    )
  }, error = function(e) NA_real_)

  # Uno's time-dependent C requires survAUC
  if (is.null(tau)) tau <- tryCatch(stats::quantile(test_time, 0.9, na.rm = TRUE), error = function(e) NA_real_)
  uno <- tryCatch({
    if (!requireNamespace("survAUC", quietly = TRUE)) stop("survAUC missing")
    survAUC::UnoC(
      survival::Surv(as.numeric(train_time), as.integer(train_status)),
      survival::Surv(as.numeric(test_time),  as.integer(test_status)),
      marker = as.numeric(risk),
      tau = as.numeric(tau)
    )$C
  }, error = function(e) NA_real_)

  list(harrell = harrell, uno = uno, tau = tau)
}


# Helper function to create calibration plot
create_calibration_plot <- function(predictions, actual, cohort_name, model_name) {
  # Ensure inputs are numeric
  predictions <- as.numeric(predictions)
  actual <- as.numeric(actual)
  
  # Remove any NA values
  valid_idx <- !is.na(predictions) & !is.na(actual)
  predictions <- predictions[valid_idx]
  actual <- actual[valid_idx]
  
  if (length(predictions) == 0) {
    return(NULL)
  }
  
  # Create calibration plot data
  n_bins <- min(10, length(unique(predictions)))
  if (n_bins > 1) {
    bins <- cut(predictions, breaks = n_bins, include.lowest = TRUE)
    
    cal_data <- data.frame(
      bin = levels(bins),
      predicted = sapply(levels(bins), function(level) {
        mean(predictions[bins == level])
      }),
      observed = sapply(levels(bins), function(level) {
        mean(actual[bins == level])
      }),
      count = sapply(levels(bins), function(level) {
        sum(bins == level)
      })
    )
    
    # Create the plot
    p <- ggplot(cal_data, aes(x = predicted, y = observed)) +
      geom_point(aes(size = count), alpha = 0.7) +
      geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "red") +
      geom_line(aes(x = predicted, y = predicted), color = "blue", alpha = 0.5) +
      scale_size_continuous(range = c(2, 8)) +
      labs(
        title = paste("Calibration Plot:", cohort_name, "-", model_name),
        x = "Predicted Probability",
        y = "Observed Probability",
        size = "Sample Size"
      ) +
      theme_minimal() +
      theme(plot.title = element_text(hjust = 0.5))
    
    return(p)
  } else {
    return(NULL)
  }
}


# Helper function to get top N features with normalized importance
get_top_features_normalized <- function(feature_df, cohort_name, model_name, n_features = 25) {
  if (nrow(feature_df) == 0) return(NULL)
  
  # Get top N features
  top_features <- feature_df %>%
    slice_head(n = n_features) %>%
    mutate(
      Cohort = cohort_name,
      Model = model_name,
      Rank = row_number()
    )
  
  # Normalize importance to 0-1 scale
  if ("importance" %in% colnames(top_features)) {
    top_features <- top_features %>%
      mutate(
        Normalized_Importance = (importance - min(importance)) / (max(importance) - min(importance))
      )
  } else if ("coefficient" %in% colnames(top_features)) {
    # For LASSO coefficients, use absolute values and normalize
    top_features <- top_features %>%
      mutate(
        importance = abs(coefficient),
        Normalized_Importance = (importance - min(importance)) / (max(importance) - min(importance))
      )
  }
  
  return(top_features)
}


calculate_calibration_metrics <- function(predictions, actual) {
  # Ensure inputs are numeric and clean
  predictions <- as.numeric(predictions)
  actual <- as.numeric(actual)
  
  valid_idx <- !is.na(predictions) & !is.na(actual)
  predictions <- predictions[valid_idx]
  actual <- actual[valid_idx]
  
  if (length(predictions) < 2 || length(unique(actual)) < 2) {
    return(data.frame(
      Calibration_Slope = NA_real_,
      Calibration_Intercept = NA_real_,
      Calibration_Brier = NA_real_
    ))
  }
  
  # Calibration model
  cal_model <- glm(actual ~ predictions, family = binomial(link = "logit"))
  
  # Metrics
  slope <- coef(cal_model)[2]
  intercept <- coef(cal_model)[1]
  brier <- mean((predictions - actual)^2)
  
  data.frame(
    Calibration_Slope = slope,
    Calibration_Intercept = intercept,
    Calibration_Brier = brier
  )
}


create_metrics_summary <- function(metrics_list) {
  if (length(metrics_list) == 0) return(NULL)
  
  # Ensure optional cols exist, then coerce types so bind_rows() can't fail
  ensure_cols <- function(df, cols) {
    miss <- setdiff(cols, names(df))
    if (length(miss)) df[miss] <- NA_real_
    df
  }
  
  normalize_metrics <- function(df) {
    df <- ensure_cols(df, c("Calibration_Slope", "Calibration_Intercept", "Calibration_Brier"))
    dplyr::mutate(
      df,
      # character keys
      Cohort  = as.character(Cohort),
      Model   = as.character(Model),
      # numerics
      Threshold          = suppressWarnings(as.numeric(Threshold)),
      Accuracy           = suppressWarnings(as.numeric(Accuracy)),
      Precision          = suppressWarnings(as.numeric(Precision)),
      Recall             = suppressWarnings(as.numeric(Recall)),
      F1                 = suppressWarnings(as.numeric(F1)),
      AUC                = suppressWarnings(as.numeric(AUC)),   
      Brier_Score        = suppressWarnings(as.numeric(Brier_Score)),
      Predicted_Positives = suppressWarnings(as.integer(Predicted_Positives)),
      Calibration_Slope      = suppressWarnings(as.numeric(Calibration_Slope)),
      Calibration_Intercept  = suppressWarnings(as.numeric(Calibration_Intercept)),
      Calibration_Brier      = suppressWarnings(as.numeric(Calibration_Brier))
    )
  }
  
  metrics_df <- metrics_list |>
    lapply(normalize_metrics) |>
    dplyr::bind_rows()
  
  summary_df <- metrics_df |>
    dplyr::group_by(Cohort, Model) |>
    dplyr::summarise(
      AUC                 = dplyr::first(AUC),
      Brier_Score         = dplyr::first(Brier_Score),
      Accuracy            = dplyr::first(Accuracy),
      F1                  = dplyr::first(F1),
      Precision           = dplyr::first(Precision),
      Recall              = dplyr::first(Recall),
      Calibration_Slope       = dplyr::first(Calibration_Slope),
      Calibration_Intercept   = dplyr::first(Calibration_Intercept),
      Calibration_Brier       = dplyr::first(Calibration_Brier),
      .groups = "drop"
    )
  
  list(full_metrics = metrics_df, summary = summary_df)
}


# Data directory resolver and unified loader for survival variables

resolve_phts_data_dir <- function(default_dir = "C:/Projects/phts/data") {
  # 1) Environment variable takes precedence
  env_dir <- Sys.getenv("PHTS_DATA_DIR", unset = NA_character_)
  if (!is.na(env_dir) && nzchar(env_dir) && dir.exists(env_dir)) {
    return(normalizePath(env_dir, winslash = "/", mustWork = TRUE))
  }
  # 2) Provided default directory
  if (!is.na(default_dir) && nzchar(default_dir) && dir.exists(default_dir)) {
    return(normalizePath(default_dir, winslash = "/", mustWork = TRUE))
  }
  # 3) Fallback to project-relative ../data
  proj_fallback <- tryCatch({
    p <- here::here("..", "data")
    if (dir.exists(p)) normalizePath(p, winslash = "/", mustWork = TRUE) else NA_character_
  }, error = function(e) NA_character_)
  if (!is.na(proj_fallback)) return(proj_fallback)
  stop("Could not locate PHTS data directory. Set PHTS_DATA_DIR or ensure data directory exists.")
}

load_phts_transplant_dataset <- function(data_dir = NULL) {
  dir_path <- if (is.null(data_dir)) resolve_phts_data_dir() else data_dir
  tx_path <- file.path(dir_path, "transplant.sas7bdat")
  if (!file.exists(tx_path)) {
    stop(sprintf("File not found: %s", tx_path))
  }
  cat("[Loader] Using data directory:", dir_path, "\n")
  cat("[Loader] Reading:", basename(tx_path), "\n")
  tx <- haven::read_sas(tx_path)
  n_before <- nrow(tx)
  tx <- janitor::clean_names(tx)
  # Construct survival variables without dropping censored rows
  tx <- dplyr::mutate(
    tx,
    ev_time = pmin(int_dead, int_graft_loss, na.rm = TRUE),
    ev_type = pmax(dtx_patient, graft_loss, na.rm = TRUE)
  )
  n_after <- nrow(tx)
  cat(sprintf("[Loader] Rows loaded: %d -> %d (no row drops)\n", n_before, n_after))
  # Return with ev_time/ev_type available; keep original columns
  tx
}


# Time-fixing helpers

compute_censored_time_median <- function(df, time_col = "ev_time", status_col = "outcome") {
  # Median among censored rows with valid (>0) times; fallback to overall; then tiny epsilon
  med <- df |>
    dplyr::filter(.data[[status_col]] == 0L, is.finite(.data[[time_col]]), .data[[time_col]] > 0) |>
    dplyr::summarise(med = stats::median(.data[[time_col]], na.rm = TRUE)) |>
    dplyr::pull(med)
  if (!is.finite(med) || is.na(med)) {
    med <- df |>
      dplyr::filter(is.finite(.data[[time_col]]), .data[[time_col]] > 0) |>
      dplyr::summarise(med = stats::median(.data[[time_col]], na.rm = TRUE)) |>
      dplyr::pull(med)
  }
  if (!is.finite(med) || is.na(med)) med <- 1 / (365.25 * 24 * 60) # ~1 minute in years
  med
}

fix_non_positive_times <- function(df, time_col = "ev_time", status_col = "outcome") {
  med_cen <- compute_censored_time_median(df, time_col = time_col, status_col = status_col)
  out <- df |>
    dplyr::mutate(
      .ev_time_replaced = .data[[status_col]] == 0L & is.finite(.data[[time_col]]) & .data[[time_col]] <= 0,
      "{time_col}" := dplyr::if_else(
        .data[[status_col]] == 0L & (is.na(.data[[time_col]]) | .data[[time_col]] <= 0),
        med_cen,
        .data[[time_col]]
      )
    )
  cat("[TimeFix] Replaced ", sum(out$.ev_time_replaced, na.rm = TRUE),
      " censored non-positive ", time_col, " values with median = ", med_cen, "\n", sep = "")
  out
}

# Lasso Helper Functions

nzv_cols <- function(df) {
  vapply(df, function(x) {
    ux <- unique(x)
    ux <- ux[!is.na(ux)]
    length(ux) < 2
  }, logical(1))
}


mode_level <- function(x) {
  ux <- na.omit(x)
  if (length(ux) == 0) return(NA)
  tab <- sort(table(ux), decreasing = TRUE)
  names(tab)[1]
}


impute_like <- function(df, like_df) {
  for (nm in names(df)) {
    if (is.numeric(df[[nm]])) {
      m <- median(like_df[[nm]], na.rm = TRUE)
      df[[nm]][is.na(df[[nm]])] <- m
    } else if (is.factor(df[[nm]])) {
      # ensure same levels; add "Other"
      base_lv <- levels(like_df[[nm]])
      if (!("Other" %in% base_lv)) base_lv <- c(base_lv, "Other")
      df[[nm]] <- factor(df[[nm]], levels = base_lv)
      # unseen -> NA -> "Other"
      df[[nm]][is.na(df[[nm]])] <- "Other"
    }
  }
  df
}


align_mm <- function(train_df, test_df) {
  Xtr <- model.matrix(~ . - 1, data = train_df)
  Xte <- model.matrix(~ . - 1, data = test_df)
  # pad/reorder test to train columns
  missing_in_test <- setdiff(colnames(Xtr), colnames(Xte))
  if (length(missing_in_test)) {
    Xte <- cbind(Xte, matrix(0, nrow(Xte), length(missing_in_test),
                             dimnames = list(NULL, missing_in_test)))
  }
  extra_in_test <- setdiff(colnames(Xte), colnames(Xtr))
  if (length(extra_in_test)) Xte <- Xte[, setdiff(colnames(Xte), extra_in_test), drop = FALSE]
  Xte <- Xte[, colnames(Xtr), drop = FALSE]
  list(Xtr = Xtr, Xte = Xte)
}


# LASSO-Cox wrapper

run_lasso_cox <- function(train_df, test_df, time_col = "time", status_col = "status", cohort_name = "", model_name = "LASSO (Survival)", alpha = 0.5) {
  # Build response
  y_train <- survival::Surv(train_df[[time_col]], train_df[[status_col]])
  y_test  <- survival::Surv(test_df[[time_col]],  test_df[[status_col]])

  # One-hot encode predictors with model.matrix and align columns
  train_pred_df <- dplyr::select(train_df, -dplyr::all_of(c(time_col, status_col)))
  test_pred_df  <- dplyr::select(test_df,  -dplyr::all_of(c(time_col, status_col)))

  # Ensure characters are factors for proper one-hot encoding
  train_pred_df <- dplyr::mutate(train_pred_df, dplyr::across(where(is.character), as.factor))
  test_pred_df  <- dplyr::mutate(test_pred_df,  dplyr::across(where(is.character), as.factor))

  # Winsorize numeric predictors based on training quantiles to reduce outlier leverage
  winsorize <- function(x, lo, hi) {
    x[x < lo] <- lo
    x[x > hi] <- hi
    x
  }
  if (ncol(train_pred_df) > 0) {
    num_cols <- vapply(train_pred_df, is.numeric, logical(1))
    if (any(num_cols)) {
      q_lo <- vapply(train_pred_df[, num_cols, drop = FALSE], function(v) stats::quantile(v, probs = 0.001, na.rm = TRUE, names = FALSE, type = 7), numeric(1))
      q_hi <- vapply(train_pred_df[, num_cols, drop = FALSE], function(v) stats::quantile(v, probs = 0.999, na.rm = TRUE, names = FALSE, type = 7), numeric(1))
      for (nm in names(q_lo)) {
        train_pred_df[[nm]] <- winsorize(train_pred_df[[nm]], q_lo[[nm]], q_hi[[nm]])
        if (nm %in% names(test_pred_df)) {
          test_pred_df[[nm]] <- winsorize(test_pred_df[[nm]], q_lo[[nm]], q_hi[[nm]])
        }
      }
    }
  }

  Xtr <- model.matrix(~ . - 1, data = train_pred_df)
  Xte <- model.matrix(~ . - 1, data = test_pred_df)

  # Align test to train columns
  missing_in_test <- setdiff(colnames(Xtr), colnames(Xte))
  if (length(missing_in_test)) {
    Xte <- cbind(Xte, matrix(0, nrow(Xte), length(missing_in_test), dimnames = list(NULL, missing_in_test)))
  }
  extra_in_test <- setdiff(colnames(Xte), colnames(Xtr))
  if (length(extra_in_test)) {
    Xte <- Xte[, setdiff(colnames(Xte), extra_in_test), drop = FALSE]
  }
  # Reorder test columns to match train
  Xte <- Xte[, colnames(Xtr), drop = FALSE]

  # Remove constant and near-zero variance columns from train and mirror to test
  nunique <- apply(Xtr, 2, function(v) length(unique(stats::na.omit(v))))
  sdv <- apply(Xtr, 2, function(v) stats::sd(v, na.rm = TRUE))
  keep <- (nunique > 1) & (sdv > 1e-8)
  if (any(!keep)) {
    Xtr <- Xtr[, keep, drop = FALSE]
    Xte <- Xte[, colnames(Xtr), drop = FALSE]
  }

  # Drop duplicate columns (exact duplicates) to avoid rank issues
  if (ncol(Xtr) > 1) {
    sig <- apply(Xtr, 2, function(col) paste0(as.integer(round(col, 12)), collapse = ","))
    dup <- duplicated(sig)
    if (any(dup)) {
      Xtr <- Xtr[, !dup, drop = FALSE]
      Xte <- Xte[, colnames(Xtr), drop = FALSE]
    }
  }

  set.seed(1997)
  cv <- glmnet::cv.glmnet(
    x = Xtr,
    y = y_train,
    family = "cox",
    alpha = alpha,
    nfolds = 5,
    type.measure = "C",
    standardize = TRUE,
    lambda.min.ratio = 1e-02,
    maxit = 1e+06
  )
  lambda_use <- if (!is.null(cv$lambda.min)) cv$lambda.min else cv$lambda.1se
  cat("[LASSO] Optimal lambda:", round(lambda_use, 6), "\n")

  model <- glmnet::glmnet(
    x = Xtr,
    y = y_train,
    family = "cox",
    alpha = alpha,
    lambda = lambda_use,
    standardize = TRUE,
    maxit = 1e+06
  )

  # Fallback: if empty model, try lambda.1se
  coefs_tmp <- tryCatch(as.matrix(glmnet::coef.glmnet(model, s = lambda_use)), error = function(e) NULL)
  if (is.null(coefs_tmp) || all(coefs_tmp == 0)) {
    if (!is.null(cv$lambda.1se)) {
      lambda_use <- cv$lambda.1se
      model <- glmnet::glmnet(
        x = Xtr,
        y = y_train,
        family = "cox",
        alpha = alpha,
        lambda = lambda_use,
        standardize = TRUE,
        maxit = 1e+06
      )
    }
  }

  risk_scores <- as.numeric(stats::predict(model, newx = Xte, s = lambda_use))
  conc <- survival::concordance(y_test ~ risk_scores)
  log_survival_cindex(cohort_name, model_name, test_df[[time_col]], test_df[[status_col]], risk_scores)

  # Non-zero coefficients
  coefs <- as.matrix(glmnet::coef.glmnet(model, s = lambda_use))
  nonzero <- data.frame(
    feature = rownames(coefs),
    coefficient = as.numeric(coefs[, 1]),
    stringsAsFactors = FALSE
  )
  nonzero <- dplyr::filter(nonzero, feature != "(Intercept)", coefficient != 0)
  nonzero <- dplyr::arrange(nonzero, dplyr::desc(abs(coefficient)))

  list(
    model = model,
    cv = cv,
    lambda_min = lambda_use,
    risk_scores = risk_scores,
    concordance = conc,
    nonzero_coefs = nonzero
  )
}


# AORSF wrapper

run_aorsf <- function(train_df, test_df, time_col = "time", status_col = "status", cohort_name = "", model_name = "AORSF", n_tree = 100) {
  # Prepare data
  train_prep <- train_df |>
    dplyr::mutate(
      dplyr::across(where(is.character), as.factor),
      dplyr::across(where(is.logical), as.factor)
    ) |>
    # Drop helper/temporary columns (e.g., .ev_time_replaced)
    dplyr::select(-dplyr::starts_with("."))
  test_prep <- test_df |>
    dplyr::mutate(
      dplyr::across(where(is.character), as.factor),
      dplyr::across(where(is.logical), as.factor)
    ) |>
    dplyr::select(-dplyr::starts_with("."))

  # Remove constant columns based on train and mirror to test
  constant_cols <- names(train_prep)[sapply(train_prep, function(x) length(unique(stats::na.omit(x))) == 1)]
  if (length(constant_cols) > 0) {
    train_prep <- dplyr::select(train_prep, -dplyr::all_of(constant_cols))
    test_prep  <- dplyr::select(test_prep,  -dplyr::all_of(constant_cols))
  }

  # Ensure both sets share exact same columns
  common_features <- intersect(colnames(train_prep), colnames(test_prep))
  train_prep <- train_prep[, common_features, drop = FALSE]
  test_prep  <- test_prep[, common_features, drop = FALSE]

  # Train AORSF
  model <- aorsf::orsf(
    data = train_prep,
    formula = stats::as.formula(paste0("survival::Surv(", time_col, ", ", status_col, ") ~ .")),
    na_action = 'impute_meanmode',
    n_tree = n_tree
  )

  # Predict risk scores
  risk_scores <- as.numeric(stats::predict(model, new_data = test_prep, pred_type = 'risk'))
  conc <- survival::concordance(survival::Surv(test_df[[time_col]], test_df[[status_col]]) ~ risk_scores)
  log_survival_cindex(cohort_name, model_name, test_df[[time_col]], test_df[[status_col]], risk_scores)

  # Variable importance
  vi <- tryCatch({ aorsf::orsf_vi_negate(model) }, error = function(e) NULL)
  vi_df <- NULL
  if (!is.null(vi)) {
    vi_df <- data.frame(
      feature = names(vi),
      importance = as.numeric(vi),
      stringsAsFactors = FALSE
    ) |>
      dplyr::filter(importance > 0) |>
      dplyr::arrange(dplyr::desc(importance))
  }

  list(model = model, risk_scores = risk_scores, concordance = conc, vi = vi_df)
}


# CatBoost-Cox wrapper

run_catboost_cox <- function(
  train_df,
  test_df,
  time_col = "ev_time",
  status_col = "outcome",
  cohort_name = "",
  model_name = "CatBoost",
  params = list(loss_function = 'Cox', eval_metric = 'Cox', iterations = 2000, depth = 4, verbose = 500)
) {
  stopifnot(time_col %in% names(train_df), status_col %in% names(train_df))
  stopifnot(time_col %in% names(test_df),  status_col %in% names(test_df))

  # Drop leakage predictors and identifiers; keep raw time/status for evaluation
  tr <- remove_leakage_predictors(train_df)
  te <- remove_leakage_predictors(test_df)

  # Signed-time labels (+time for events, −time for censored)
  eps <- .Machine$double.eps
  tr_final_time <- suppressWarnings(as.numeric(train_df[[time_col]]))
  te_final_time <- suppressWarnings(as.numeric(test_df[[time_col]]))
  tr_final_time[!is.finite(tr_final_time) | tr_final_time <= 0] <- eps
  te_final_time[!is.finite(te_final_time) | te_final_time <= 0] <- eps
  tr_status <- as.integer(train_df[[status_col]])
  te_status <- as.integer(test_df[[status_col]])
  tr_labels <- ifelse(tr_status == 1L, tr_final_time, -tr_final_time)
  te_labels <- ifelse(te_status == 1L, te_final_time, -te_final_time)

  # Prepare features (drop outcome/time columns if they are present after filtering)
  drop_cols <- intersect(c("ptid_e", time_col, status_col, "final_time", "catboost_label"), names(tr))
  tr_x <- tr[, setdiff(names(tr), drop_cols), drop = FALSE]
  te_x <- te[, setdiff(names(te), drop_cols), drop = FALSE]

  # Convert characters to factors
  tr_x <- dplyr::mutate(tr_x, dplyr::across(where(is.character), as.factor))
  te_x <- dplyr::mutate(te_x, dplyr::across(where(is.character), as.factor))

  # Synchronize factor levels from train to test
  for (col in names(tr_x)) {
    if (is.factor(tr_x[[col]])) {
      lv <- levels(tr_x[[col]])
      te_x[[col]] <- factor(te_x[[col]], levels = lv)
    }
  }

  # Build CatBoost pools
  train_pool <- catboost::catboost.load_pool(data = tr_x, label = tr_labels)
  test_pool  <- catboost::catboost.load_pool(data = te_x, label = te_labels)

  # Fit model
  model <- catboost::catboost.train(learn_pool = train_pool, test_pool = test_pool, params = params)

  # Predict; invert sign so higher = higher risk
  preds <- catboost::catboost.predict(model, test_pool)
  risk_scores <- -1 * as.numeric(preds)

  # Concordance using observed time/status from test_df
  conc <- survival::concordance(survival::Surv(te_final_time, te_status) ~ risk_scores)
  log_survival_cindex(cohort_name, model_name, te_final_time, te_status, risk_scores)

  # Feature importance
  fi <- catboost::catboost.get_feature_importance(model, pool = train_pool)
  fi_df <- as.data.frame(fi)
  fi_df <- fi_df |>
    dplyr::mutate(feature = rownames(fi_df)) |>
    dplyr::rename(importance = V1) |>
    dplyr::filter(importance > 0) |>
    dplyr::select(feature, importance) |>
    dplyr::arrange(dplyr::desc(importance))

  list(model = model, risk_scores = risk_scores, concordance = conc, importance = fi_df)
}


# Random Survival Forest (ranger) wrapper

run_rsf_ranger <- function(
  train_df,
  test_df,
  time_col = "time",
  status_col = "status",
  cohort_name = "",
  model_name = "RSF (ranger)",
  num.trees = 500,
  mtry = NULL,
  min.node.size = NULL
) {
  # Prepare data: factorize characters/logicals; drop helper columns; impute NAs
  train_prep <- train_df |>
    dplyr::mutate(
      dplyr::across(where(is.character), as.factor),
      dplyr::across(where(is.logical), as.factor)
    ) |>
    dplyr::select(-dplyr::starts_with("."))
  test_prep <- test_df |>
    dplyr::mutate(
      dplyr::across(where(is.character), as.factor),
      dplyr::across(where(is.logical), as.factor)
    ) |>
    dplyr::select(-dplyr::starts_with("."))

  # Impute missing values compatible with ranger splitrule=logrank
  if (ncol(train_prep) > 0) {
    # Numeric: median
    num_cols <- vapply(train_prep, is.numeric, logical(1))
    if (any(num_cols)) {
      medians <- vapply(train_prep[, num_cols, drop = FALSE], function(v) stats::median(v, na.rm = TRUE), numeric(1))
      for (nm in names(medians)) {
        m <- medians[[nm]]
        if (!is.finite(m)) m <- 0
        train_prep[[nm]][is.na(train_prep[[nm]])] <- m
        if (nm %in% names(test_prep)) test_prep[[nm]][is.na(test_prep[[nm]])] <- m
      }
    }
    # Factor: add "Missing" level; align levels
    fac_cols <- vapply(train_prep, is.factor, logical(1))
    if (any(fac_cols)) {
      for (nm in names(train_prep)[fac_cols]) {
        tr_vals <- as.character(train_prep[[nm]])
        tr_vals[is.na(tr_vals)] <- "Missing"
        train_prep[[nm]] <- factor(tr_vals)
        lv <- levels(train_prep[[nm]])
        if (!("Missing" %in% lv)) lv <- c(lv, "Missing")
        train_prep[[nm]] <- factor(train_prep[[nm]], levels = lv)
        if (nm %in% names(test_prep)) {
          te_vals <- as.character(test_prep[[nm]])
          te_vals[is.na(te_vals) | !(te_vals %in% lv)] <- "Missing"
          test_prep[[nm]] <- factor(te_vals, levels = lv)
        }
      }
    }
  }

  # Remove constant columns based on train
  constant_cols <- names(train_prep)[sapply(train_prep, function(x) length(unique(stats::na.omit(x))) == 1)]
  if (length(constant_cols) > 0) {
    train_prep <- dplyr::select(train_prep, -dplyr::all_of(constant_cols))
    test_prep  <- dplyr::select(test_prep,  -dplyr::all_of(constant_cols))
  }

  # Align columns
  common_features <- intersect(colnames(train_prep), colnames(test_prep))
  train_prep <- train_prep[, common_features, drop = FALSE]
  test_prep  <- test_prep[, common_features, drop = FALSE]

  # Build formula
  frm <- stats::as.formula(paste0("survival::Surv(", time_col, ", ", status_col, ") ~ ."))

  # Fit ranger RSF
  model <- ranger::ranger(
    formula = frm,
    data = train_prep,
    num.trees = num.trees,
    mtry = mtry,
    min.node.size = min.node.size,
    importance = "impurity",
    splitrule = "logrank",
    respect.unordered.factors = "partition",
    seed = 1997
  )

  # Predict survival curves and reduce to a scalar risk (1 - S at last timepoint)
  pred <- predict(model, data = test_prep, type = "response")
  if (!is.null(pred$survival)) {
    risk_scores <- 1 - pred$survival[, ncol(pred$survival)]
  } else if (!is.null(pred$chf)) {
    # Fallback: cumulative hazard as risk
    risk_scores <- as.numeric(pred$chf[, ncol(pred$chf)])
  } else if (!is.null(pred$predictions)) {
    # Some ranger versions store survival in predictions
    mat <- pred$predictions
    risk_scores <- 1 - mat[, ncol(mat)]
  } else {
    risk_scores <- rep(NA_real_, nrow(test_prep))
  }

  # Concordance
  conc <- survival::concordance(survival::Surv(test_df[[time_col]], test_df[[status_col]]) ~ risk_scores)
  log_survival_cindex(cohort_name, model_name, test_df[[time_col]], test_df[[status_col]], risk_scores)

  # Importance
  vi <- tryCatch(model$variable.importance, error = function(e) NULL)
  vi_df <- NULL
  if (!is.null(vi)) {
    vi_df <- data.frame(feature = names(vi), importance = as.numeric(vi), stringsAsFactors = FALSE) |>
      dplyr::arrange(dplyr::desc(importance))
  }

  list(model = model, risk_scores = risk_scores, concordance = conc, importance = vi_df)
}

# XGBoost-Cox wrapper

run_xgb_cox <- function(
  train_df,
  test_df,
  time_col = "time",
  status_col = "status",
  cohort_name = "",
  model_name = "XGBoost-Cox",
  params = list(objective = 'survival:cox', eval_metric = 'cox-nloglik', eta = 0.05, max_depth = 4, subsample = 0.8, colsample_bytree = 0.8),
  nrounds = 500,
  early_stopping_rounds = 25
) {
  # Build numeric matrices
  x_train <- model.matrix(~ . - 1, data = dplyr::select(train_df, -dplyr::all_of(c(time_col, status_col))))
  x_test  <- model.matrix(~ . - 1, data = dplyr::select(test_df,  -dplyr::all_of(c(time_col, status_col))))
  # Align columns
  missing_in_test <- setdiff(colnames(x_train), colnames(x_test))
  if (length(missing_in_test)) {
    x_test <- cbind(x_test, matrix(0, nrow(x_test), length(missing_in_test), dimnames = list(NULL, missing_in_test)))
  }
  extra_in_test <- setdiff(colnames(x_test), colnames(x_train))
  if (length(extra_in_test)) x_test <- x_test[, setdiff(colnames(x_test), extra_in_test), drop = FALSE]
  x_test <- x_test[, colnames(x_train), drop = FALSE]

  time_train <- as.numeric(train_df[[time_col]])
  status_train <- as.numeric(train_df[[status_col]])
  time_test <- as.numeric(test_df[[time_col]])
  status_test <- as.numeric(test_df[[status_col]])

  dtrain <- xgboost::xgb.DMatrix(data = x_train, label = time_train)
  dtest  <- xgboost::xgb.DMatrix(data = x_test,  label = time_test)
  # Use event indicator as weights to emphasize events
  xgboost::setinfo(dtrain, 'weight', status_train)
  xgboost::setinfo(dtest,  'weight', status_test)

  set.seed(1997)
  watchlist <- list(train = dtrain, eval = dtest)
  model <- xgboost::xgb.train(
    params = params,
    data = dtrain,
    nrounds = nrounds,
    watchlist = watchlist,
    verbose = 0,
    early_stopping_rounds = early_stopping_rounds
  )

  # Risk scores (higher = higher risk)
  risk_scores <- as.numeric(predict(model, dtest))
  conc <- survival::concordance(survival::Surv(time_test, status_test) ~ risk_scores)
  log_survival_cindex(cohort_name, model_name, time_test, status_test, risk_scores)

  # Feature importance by gain
  imp <- tryCatch({
    xgboost::xgb.importance(feature_names = colnames(x_train), model = model)
  }, error = function(e) NULL)
  imp_df <- NULL
  if (!is.null(imp) && nrow(imp) > 0) {
    imp_df <- imp |>
      dplyr::transmute(feature = Feature, importance = Gain) |>
      dplyr::arrange(dplyr::desc(importance))
  }

  list(model = model, risk_scores = risk_scores, concordance = conc, importance = imp_df)
}

# Export utilities for Deep Survival (pycox)

export_pycox_dataset <- function(
  train_df,
  test_df,
  time_col = "time",
  status_col = "status",
  out_dir,
  zero_variance_drop = TRUE
) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # Remove identifiers and ensure no leakage columns
  x_train_df <- dplyr::select(train_df, -dplyr::any_of(c("ptid_e", time_col, status_col)))
  x_test_df  <- dplyr::select(test_df,  -dplyr::any_of(c("ptid_e", time_col, status_col)))

  # Convert characters to factors; build one-hot design matrices
  x_train_df <- dplyr::mutate(x_train_df, dplyr::across(where(is.character), as.factor))
  x_test_df  <- dplyr::mutate(x_test_df,  dplyr::across(where(is.character), as.factor))

  Xtr <- model.matrix(~ . - 1, data = x_train_df)
  Xte <- model.matrix(~ . - 1, data = x_test_df)

  # Align test columns to train
  missing_in_test <- setdiff(colnames(Xtr), colnames(Xte))
  if (length(missing_in_test)) {
    Xte <- cbind(Xte, matrix(0, nrow(Xte), length(missing_in_test), dimnames = list(NULL, missing_in_test)))
  }
  extra_in_test <- setdiff(colnames(Xte), colnames(Xtr))
  if (length(extra_in_test)) Xte <- Xte[, setdiff(colnames(Xte), extra_in_test), drop = FALSE]
  Xte <- Xte[, colnames(Xtr), drop = FALSE]

  # Optionally drop zero-variance predictors (over entire train)
  if (zero_variance_drop) {
    nzv <- apply(Xtr, 2, function(v) length(unique(v)) > 1)
    Xtr <- Xtr[, nzv, drop = FALSE]
    Xte <- Xte[, nzv, drop = FALSE]
  }

  ytr <- data.frame(duration = as.numeric(train_df[[time_col]]), event = as.integer(train_df[[status_col]]))
  yte <- data.frame(duration = as.numeric(test_df[[time_col]]),  event = as.integer(test_df[[status_col]]))

  # Write CSVs
  readr::write_csv(as.data.frame(Xtr), file.path(out_dir, "X_train.csv"))
  readr::write_csv(as.data.frame(Xte), file.path(out_dir, "X_test.csv"))
  readr::write_csv(ytr, file.path(out_dir, "y_train.csv"))
  readr::write_csv(yte, file.path(out_dir, "y_test.csv"))

  cat("[pycox export] Wrote dataset to ", normalizePath(out_dir, winslash = "/", mustWork = FALSE), "\n", sep = "")
  invisible(list(X_train = Xtr, X_test = Xte, y_train = ytr, y_test = yte))
}

# Calibration and Brier at fixed horizon (IPCW)

km_censor_surv <- function(time, status) {
  # status: 1=event, 0=censored/no event
  survfit(Surv(time, as.integer(status == 0)) ~ 1)
}

get_Ghat <- function(km_fit, times_vec) {
  s <- summary(km_fit, times = times_vec, extend = TRUE)
  out <- as.numeric(s$surv)
  out[!is.finite(out) | is.na(out)] <- 1
  out
}

brier_ipcw <- function(prob_event_tau, time, status, tau) {
  # prob_event_tau: predicted P(T<=tau, event)
  stopifnot(length(prob_event_tau) == length(time), length(status) == length(time))
  km_c <- km_censor_surv(time, status)
  G_tau <- get_Ghat(km_c, tau)
  G_ti  <- get_Ghat(km_c, pmin(time, tau))
  Y1 <- (time <= tau & status == 1)
  Y0 <- (time > tau)
  term1 <- ifelse(G_ti > 0, (0 - prob_event_tau)^2 * Y1 / G_ti, 0)
  term0 <- ifelse(G_tau > 0, (1 - prob_event_tau)^2 * Y0 / G_tau, 0)
  mean(term1 + term0, na.rm = TRUE)
}

calibration_table <- function(prob_event_tau, time, status, tau, n_bins = 10) {
  df <- data.frame(prob = prob_event_tau, time = time, status = status)
  df$bin <- cut(df$prob, breaks = quantile(df$prob, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE), include.lowest = TRUE)
  agg <- df |>
    dplyr::group_by(bin) |>
    dplyr::summarise(
      n = dplyr::n(),
      pred = mean(prob, na.rm = TRUE),
      # observed via KM: 1 - S(tau)
      obs = {
        fit <- survival::survfit(survival::Surv(time, status) ~ 1, data = dplyr::cur_data_all())
        s_tau <- get_Ghat(fit, tau)[1]
        1 - s_tau
      },
      .groups = 'drop'
    )
  agg
}

ipcw_prob_from_scores <- function(risk_scores, time, status, tau, n_bins = 20) {
  # Bin scores and compute IPCW-weighted event probability per bin
  stopifnot(length(risk_scores) == length(time), length(status) == length(time))
  km_c <- km_censor_surv(time, status)
  G_tau <- get_Ghat(km_c, tau)
  G_ti  <- get_Ghat(km_c, pmin(time, tau))
  # Labels and weights per IPCW theory
  y1 <- as.integer(time <= tau & status == 1)
  y0 <- as.integer(time > tau)
  w  <- y1 / pmax(G_ti, .Machine$double.eps) + y0 / pmax(G_tau, .Machine$double.eps)
  y_star <- y1  # contribution for numerator handled via weights
  # Create bins
  brks <- quantile(risk_scores, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE)
  # Avoid duplicates
  brks[duplicated(brks)] <- brks[duplicated(brks)] + 1e-12
  bins <- cut(risk_scores, breaks = brks, include.lowest = TRUE)
  df <- data.frame(bin = bins, y1 = y1, y0 = y0, w = w, risk = risk_scores)
  agg <- df |>
    dplyr::group_by(bin) |>
    dplyr::summarise(
      n = dplyr::n(),
      # Weighted event probability: E_ipcw[Y(τ)=1 | bin]
      p_hat = sum((y1 / pmax(G_ti, .Machine$double.eps)), na.rm = TRUE) /
              sum(((y1 / pmax(G_ti, .Machine$double.eps)) + (y0 / pmax(G_tau, .Machine$double.eps))), na.rm = TRUE),
      risk_mid = mean(risk, na.rm = TRUE),
      .groups = 'drop'
    )
  # Map back to observations
  bin_to_p <- setNames(agg$p_hat, agg$bin)
  prob_vec <- bin_to_p[as.character(bins)]
  list(prob = as.numeric(prob_vec), table = agg)
}



# Unified train/test split function for all models
create_unified_train_test_split <- function(data, cohort_name, seed = 1997) {
  set.seed(seed)
  
  # Create reproducible random split
  n_total <- nrow(data)
  n_train <- floor(0.8 * n_total)
  
  # Create random indices
  all_indices <- 1:n_total
  train_indices <- sample(all_indices, size = n_train)
  test_indices <- setdiff(all_indices, train_indices)
  
  # Split the data
  train_data <- data[train_indices, ]
  test_data <- data[test_indices, ]
  
  # Store indices for other models to use
  split_info <- list(
    cohort = cohort_name,
    train_indices = train_indices,
    test_indices = test_indices,
    n_total = n_total,
    n_train = n_train,
    n_test = length(test_indices),
    seed = seed
  )
  
  cat("=== Unified Train/Test Split for", cohort_name, "===\n")
  cat("Total patients:", n_total, "\n")
  cat("Training set:", n_train, "patients\n")
  cat("Test set:", length(test_indices), "patients\n")
  cat("Split ratio:", round(n_train/n_total, 3), ":", round(length(test_indices)/n_total, 3), "\n")
  cat("Seed used:", seed, "\n")
  cat("=====================================\n\n")
  
  return(list(
    train_data = train_data,
    test_data = test_data,
    split_info = split_info
  ))
}

# Persistent split helpers

.split_dir_path <- function() {
  # Save under project path cohort_analysis/splits
  p <- tryCatch(here::here("cohort_analysis", "splits"), error = function(e) NA_character_)
  if (is.na(p)) p <- file.path("cohort_analysis", "splits")
  if (!dir.exists(p)) dir.create(p, recursive = TRUE, showWarnings = FALSE)
  normalizePath(p, winslash = "/", mustWork = FALSE)
}

get_or_create_unified_split <- function(data, cohort_name, seed = 1997) {
  split_dir <- .split_dir_path()
  key <- gsub("[^A-Za-z0-9]+", "_", cohort_name)
  f <- file.path(split_dir, paste0("split_", key, ".rds"))
  if (file.exists(f)) {
    s <- readRDS(f)
    cat("[Split] Loaded saved split for ", cohort_name, " from ", f, "\n", sep = "")
    return(s)
  }
  s <- create_unified_train_test_split(data, cohort_name = cohort_name, seed = seed)
  saveRDS(s, f)
  cat("[Split] Saved split for ", cohort_name, " to ", f, "\n", sep = "")
  s
}

# Requires: install.packages("survAUC")
compute_concordance_pair <- function(train_time, train_status,
                                     test_time, test_status,
                                     risk, tau = NULL) {
  if (!requireNamespace("survAUC", quietly = TRUE)) {
    stop("Please install survAUC: install.packages('survAUC')", call. = FALSE)
  }
  # Harrell’s C on TEST
  harrell <- as.numeric(
    survival::concordance(survival::Surv(test_time, test_status) ~ as.numeric(risk))$concordance
  )
  # Uno’s time-dependent C at tau (needs TRAIN and TEST)
  if (is.null(tau)) tau <- stats::quantile(test_time, 0.9, na.rm = TRUE)
  uno <- tryCatch(
    survAUC::UnoC(
      survival::Surv(train_time, train_status),
      survival::Surv(test_time, test_status),
      marker = as.numeric(risk),
      tau = tau
    )$C,
    error = function(e) NA_real_
  )
  list(harrell = harrell, uno = uno, tau = tau)
}