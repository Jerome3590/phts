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

