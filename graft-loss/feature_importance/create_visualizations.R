#!/usr/bin/env Rscript
# Consolidated visualization + importance-weights script
# This file inlines the compute_rel_weights() helper and the visualization pipeline.

library(tidyverse)
library(ggplot2)
library(here)

# Helper: compute relative model weights from C-index
# Returns a tibble with columns: period, method, rel_weight
compute_rel_weights <- function(cindex_df) {
  cindex_df %>%
    dplyr::select(period, method, cindex_td_mean) %>%
    dplyr::group_by(period) %>%
    dplyr::mutate(
      best_cindex = max(cindex_td_mean, na.rm = TRUE),
      n_models = sum(!is.na(cindex_td_mean))
    ) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      rel_weight = ifelse(best_cindex > 0,
                          (cindex_td_mean / best_cindex) * n_models,
                          1)
    ) %>%
    dplyr::select(period, method, rel_weight)
}

run_visualizations <- function(output_dir = NULL) {
  # Determine outputs directory if not provided
  if (is.null(output_dir)) {
    if (dir.exists("outputs")) {
      output_dir <- "outputs"
    } else if (dir.exists(here("feature_importance", "outputs"))) {
      output_dir <- here("feature_importance", "outputs")
    } else if (dir.exists(here("graft-loss", "feature_importance", "outputs"))) {
      output_dir <- here("graft-loss", "feature_importance", "outputs")
    } else {
      stop("Cannot find outputs directory")
    }
  }
  plot_dir <- file.path(output_dir, "plots")

  # Clean existing plots directory to ensure fresh/clean visualizations
  if (dir.exists(plot_dir)) {
    plot_files <- list.files(plot_dir, full.names = TRUE, recursive = TRUE, include.dirs = FALSE)
    if (length(plot_files) > 0) {
      cat(sprintf("Cleaning %d existing plot files...\n", length(plot_files)))
      file.remove(plot_files)
    }
    cat("✓ Plots directory cleaned\n")
  }
  dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

  cat("Reading MC-CV results...\n")
  cindex_comparison <- readr::read_csv(file.path(output_dir, "cindex_comparison_mc_cv.csv"))

  periods <- c("original", "full", "full_no_covid")
  methods <- c("rsf", "catboost", "aorsf")
  method_map <- c("rsf" = "RSF", "catboost" = "CatBoost", "aorsf" = "AORSF")

  load_features <- function(period, method) {
    file_path <- file.path(output_dir, sprintf("%s_%s_top20.csv", period, method))
    if (file.exists(file_path)) {
      df <- readr::read_csv(file_path) %>%
        dplyr::mutate(period = period, method = method_map[[method]])
      cat(sprintf("✓ Loaded: %s\n", basename(file_path)))
      return(df)
    } else {
      warning(sprintf("File not found: %s", file_path))
      return(NULL)
    }
  }

  cat("\nLoading feature importance files...\n")
  all_features <- purrr::map_df(periods, function(p) {
    purrr::map_df(methods, function(m) {
      load_features(p, m)
    })
  }) %>%
    dplyr::filter(!is.null(feature))

  expected_files <- length(periods) * length(methods)
  loaded_count <- length(unique(paste(all_features$period, all_features$method)))
  cat(sprintf("\nLoaded %d/%d expected feature files\n", loaded_count, expected_files))
  cat(sprintf("Total features loaded: %d\n", nrow(all_features)))
  cat(sprintf("Unique features: %d\n", length(unique(all_features$feature))))

  # Build feature matrix
  all_unique_features <- unique(all_features$feature)
  feature_matrix <- purrr::map_df(all_unique_features, function(feat) {
    purrr::map_df(periods, function(per) {
      purrr::map_df(methods, function(meth) {
        method_name <- method_map[[meth]]
        feat_data <- all_features %>% dplyr::filter(feature == feat, period == per, method == method_name)
        importance_val <- if (nrow(feat_data) > 0) feat_data$importance[1] else 0
        tibble::tibble(feature = feat, period = per, method = method_name, importance = importance_val)
      })
    })
  }) %>%
    dplyr::mutate(
      cohort_method = paste(period, method, sep = "_"),
      period = factor(period, levels = c("original", "full", "full_no_covid")),
      method = factor(method, levels = c("RSF", "CatBoost", "AORSF"))
    )

  # Normalize and force non-negative
  feature_matrix <- feature_matrix %>%
    dplyr::mutate(importance = ifelse(is.na(importance), 0, importance)) %>%
    dplyr::group_by(period, method) %>%
    dplyr::mutate(
      importance = ifelse(importance < 0, 0, importance),
      total_imp = sum(importance),
      importance_normalized = ifelse(total_imp > 0, importance / total_imp, 1 / dplyr::n())
    ) %>%
    dplyr::select(-total_imp) %>%
    dplyr::ungroup()

  # Compute relative model weights
  algorithm_ranking <- compute_rel_weights(cindex_comparison)
  cat("Algorithm relative weights (by period):\n")
  print(algorithm_ranking)

  # Apply scaling
  feature_matrix <- feature_matrix %>%
    dplyr::left_join(algorithm_ranking, by = c("period", "method")) %>%
    dplyr::mutate(
      rel_weight = ifelse(is.na(rel_weight), 1, rel_weight),
      importance_scaled = importance_normalized * rel_weight,
      importance = importance_scaled
    ) %>%
    dplyr::select(-importance_scaled)

  # Heatmap
  feature_order <- feature_matrix %>% dplyr::group_by(feature) %>% dplyr::summarise(total_importance = sum(importance), .groups = "drop") %>% dplyr::arrange(desc(total_importance)) %>% dplyr::pull(feature)
  feature_matrix <- feature_matrix %>% dplyr::mutate(feature = factor(feature, levels = feature_order))
  feature_matrix <- feature_matrix %>% dplyr::mutate(
    cohort_label = dplyr::case_when(
      period == "original" ~ "Original",
      period == "full" ~ "Full",
      period == "full_no_covid" ~ "Full No COVID"
    ),
    cohort_method_label = paste(cohort_label, method, sep = "\n")
  )

  p1 <- ggplot(feature_matrix, aes(x = cohort_method_label, y = feature, fill = importance)) +
    geom_tile(color = "white", linewidth = 0.1) +
    scale_fill_gradient(low = "orange", high = "darkblue", name = "Importance") +
    labs(title = "Feature Importance Heatmap by Cohort and Algorithm", x = "Cohort × Algorithm", y = "Feature") +
    theme_minimal() + theme(axis.text.x = element_text(angle = 0, hjust = 0.5, size = 10), axis.text.y = element_text(size = 8))

  ggplot2::ggsave(file.path(plot_dir, "feature_importance_heatmap.png"), p1, width = 12, height = max(16, length(all_unique_features) * 0.3), dpi = 300, limitsize = FALSE)
  cat("✓ Saved: feature_importance_heatmap.png\n")

  # C-index heatmap
  cindex_heatmap_data <- dplyr::bind_rows(
    cindex_comparison %>% dplyr::select(period, method, cindex_td_mean) %>% dplyr::rename(cindex = cindex_td_mean) %>% dplyr::mutate(cindex_type = "Time-Dependent"),
    cindex_comparison %>% dplyr::select(period, method, cindex_ti_mean) %>% dplyr::rename(cindex = cindex_ti_mean) %>% dplyr::mutate(cindex_type = "Time-Independent")
  ) %>% dplyr::mutate(period = factor(period, levels = c("original", "full", "full_no_covid")), method = factor(method, levels = c("RSF", "CatBoost", "AORSF")), cohort_label = dplyr::case_when(period == "original" ~ "Original", period == "full" ~ "Full", period == "full_no_covid" ~ "Full No COVID"))

  p2 <- ggplot(cindex_heatmap_data, aes(x = method, y = cohort_label, fill = cindex)) +
    geom_tile(color = "white", linewidth = 0.5) +
    geom_text(aes(label = sprintf("%.3f", cindex)), color = "black", size = 4, fontface = "bold") +
    scale_fill_gradient2(low = "red", mid = "white", high = "green", midpoint = 0.5, name = "C-index") +
    facet_wrap(~cindex_type, ncol = 2) + labs(title = "Concordance Index Heatmap by Cohort and Algorithm (MC-CV)", x = "Algorithm", y = "Cohort") + theme_minimal()

  ggplot2::ggsave(file.path(plot_dir, "cindex_heatmap.png"), p2, width = 12, height = 6, dpi = 300)
  cat("✓ Saved: cindex_heatmap.png\n")

  # Scaled bar chart (sum across scaled normalized importances)
  scaled_feature_importance <- feature_matrix %>% dplyr::group_by(feature) %>% dplyr::summarise(total_scaled_importance = sum(importance_normalized * rel_weight, na.rm = TRUE), .groups = "drop") %>% dplyr::arrange(desc(total_scaled_importance)) %>% dplyr::slice_head(n = 20)
  scaled_feature_importance <- scaled_feature_importance %>% dplyr::mutate(feature = factor(feature, levels = rev(scaled_feature_importance$feature)))

  p3 <- ggplot(scaled_feature_importance, aes(x = feature, y = total_scaled_importance)) + geom_bar(stat = "identity", fill = "steelblue", alpha = 0.8) + coord_flip() + labs(title = "Scaled Feature Importance (Top 20 Features)", subtitle = "Importance scaled by algorithm performance (relative weight = model C-index / best model C-index)", x = "Feature", y = "Scaled Normalized Importance") + theme_minimal()

  ggplot2::ggsave(file.path(plot_dir, "scaled_feature_importance_bar_chart.png"), p3, width = 12, height = 10, dpi = 300)
  cat("✓ Saved: scaled_feature_importance_bar_chart.png\n")

  # C-index table
  cindex_table <- cindex_comparison %>% dplyr::mutate(period_label = dplyr::case_when(period == "original" ~ "Original", period == "full" ~ "Full", period == "full_no_covid" ~ "Full No COVID"), cindex_td_formatted = sprintf("%.3f (%.3f-%.3f)", cindex_td_mean, cindex_td_ci_lower, cindex_td_ci_upper), cindex_ti_formatted = sprintf("%.3f (%.3f-%.3f)", cindex_ti_mean, cindex_ti_ci_lower, cindex_ti_ci_upper)) %>% dplyr::select(period_label, method, cindex_td_formatted, cindex_ti_formatted, n_splits) %>% dplyr::arrange(period_label, method) %>% dplyr::rename(Cohort = period_label, Algorithm = method, `Time-Dependent C-index (95% CI)` = cindex_td_formatted, `Time-Independent C-index (95% CI)` = cindex_ti_formatted, `N Splits` = n_splits)

  readr::write_csv(cindex_table, file.path(plot_dir, "cindex_table.csv"))
  cat("✓ Saved: cindex_table.csv\n")

  cat("\nVisualization summary:\n")
  cat(sprintf("Plots saved to: %s\n", normalizePath(plot_dir)))
}

# Run when executed non-interactively (e.g., via `Rscript`).
# When this file is `source()`-d in an interactive notebook, it will not
# auto-run. Notebooks can call `compute_rel_weights()` or `run_visualizations()`
# explicitly as needed.
if (!interactive()) {
  run_visualizations()
}
