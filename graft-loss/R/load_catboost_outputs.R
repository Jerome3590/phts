# Utilities for loading CatBoost outputs from CSV and summarizing in R

#' Read CatBoost predictions CSV
#' @return tibble with columns: row_id (if present), prediction
read_catboost_predictions <- function(path = here::here('data','models','catboost','catboost_predictions.csv')) {
  if (!file.exists(path)) return(NULL)
  df <- readr::read_csv(path, show_col_types = FALSE)
  # Ensure required column
  if (!'prediction' %in% names(df)) return(NULL)
  tibble::as_tibble(df)
}

#' Read CatBoost feature importances CSV
#' @return tibble with columns: feature, importance
read_catboost_importance <- function(path = here::here('data','models','catboost','catboost_importance.csv')) {
  if (!file.exists(path)) return(NULL)
  df <- readr::read_csv(path, show_col_types = FALSE)
  if (!all(c('feature','importance') %in% names(df))) return(NULL)
  tibble::as_tibble(df)
}

#' Normalize importances 0-1 per model (single model here)
#' @param fi tibble with columns feature, importance
#' @param top_n number of features to keep
#' @return tibble with feature, importance, normalized_importance
normalize_and_topn_importance <- function(fi, top_n = 20) {
  if (is.null(fi) || !nrow(fi)) return(NULL)
  rng <- range(fi$importance, na.rm = TRUE)
  if (!is.finite(rng[1]) || !is.finite(rng[2])) return(NULL)
  if (rng[2] > rng[1]) {
    fi$normalized_importance <- (fi$importance - rng[1]) / (rng[2] - rng[1])
  } else {
    fi$normalized_importance <- ifelse(!is.na(fi$importance), 1.0, NA_real_)
  }
  fi <- fi[order(-fi$normalized_importance, fi$feature), ]
  utils::head(fi, top_n)
}

#' Summarize predictions with simple stats
#' @param preds tibble with column prediction
#' @return tibble with count, mean, sd, min, p25, median, p75, max
summarize_predictions <- function(preds) {
  if (is.null(preds) || !nrow(preds) || !'prediction' %in% names(preds)) return(NULL)
  x <- preds$prediction
  tibble::tibble(
    n = length(x),
    mean = mean(x, na.rm = TRUE),
    sd = stats::sd(x, na.rm = TRUE),
    min = min(x, na.rm = TRUE),
    p25 = stats::quantile(x, 0.25, na.rm = TRUE, names = FALSE),
    median = stats::median(x, na.rm = TRUE),
    p75 = stats::quantile(x, 0.75, na.rm = TRUE, names = FALSE),
    max = max(x, na.rm = TRUE)
  )
}
