#!/usr/bin/env Rscript
# Consolidated visualization + importance-weights script
# This file inlines the compute_rel_weights() helper and the visualization pipeline.

library(tidyverse)
library(ggplot2)
library(plotly)
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
  # Each notebook runs from its own directory, so outputs/ should be relative to cwd
  if (is.null(output_dir)) {
    current_dir <- getwd()
    if (dir.exists("outputs")) {
      output_dir <- "outputs"
    } else {
      stop("Cannot find outputs directory. Expected 'outputs/' relative to current working directory: ", current_dir,
           "\nMake sure you're running the notebook from its directory (e.g., clinical_feature_importance_by_cohort/)")
    }
  }
  plot_dir <- file.path(output_dir, "plots")

  # Clean existing plots directory to ensure fresh/clean visualizations
  if (dir.exists(plot_dir)) {
    plot_files <- list.files(plot_dir, full.names = TRUE, recursive = TRUE, include.dirs = FALSE)
    if (length(plot_files) > 0) {
      cat(sprintf("→ Cleaning %d existing plot files...\n", length(plot_files)))
      file.remove(plot_files)
    }
    cat("✓ Plots directory cleaned\n")
  }
  dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

  cat("→ Reading cohort MC-CV results...\n")
  cindex_cohort_path <- file.path(output_dir, "cohort_model_cindex_mc_cv_modifiable_clinical.csv")
  best_feat_path     <- file.path(output_dir, "best_clinical_features_by_cohort_mc_cv.csv")

  if (!file.exists(cindex_cohort_path)) {
    stop("Expected cohort C-index file 'cohort_model_cindex_mc_cv_modifiable_clinical.csv' not found in: ", output_dir)
  }
  if (!file.exists(best_feat_path)) {
    stop("Expected best-features file 'best_clinical_features_by_cohort_mc_cv.csv' not found in: ", output_dir)
  }

  cindex_cohort <- readr::read_csv(cindex_cohort_path)
  best_features <- readr::read_csv(best_feat_path)

  # Prepare feature matrix: Cohort × Model × Feature
  feature_matrix <- best_features %>%
    dplyr::select(Cohort, Model, feature, importance) %>%
    dplyr::mutate(
      Cohort = as.character(Cohort),
      Model  = as.character(Model),
      importance = as.numeric(importance)
    ) %>%
    dplyr::mutate(importance = ifelse(is.na(importance), 0, importance)) %>%
    dplyr::group_by(Cohort, Model) %>%
    dplyr::mutate(
      importance = ifelse(importance < 0, 0, importance),
      total_imp = sum(importance),
      importance_normalized = ifelse(total_imp > 0, importance / total_imp, 1 / dplyr::n())
    ) %>%
    dplyr::select(-total_imp) %>%
    dplyr::ungroup()

  # Relative weights per cohort/model using cohort C-index file
  algorithm_ranking <- cindex_cohort %>%
    dplyr::select(Cohort, Model, C_Index_Mean) %>%
    dplyr::group_by(Cohort) %>%
    dplyr::mutate(
      best_cindex = max(C_Index_Mean, na.rm = TRUE),
      n_models = sum(!is.na(C_Index_Mean))
    ) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      rel_weight = ifelse(best_cindex > 0,
                          (C_Index_Mean / best_cindex) * n_models,
                          1)
    ) %>%
    dplyr::select(Cohort, Model, rel_weight)

  cat("Algorithm relative weights (by clinical cohort):\n")
  print(algorithm_ranking)

  feature_matrix <- feature_matrix %>%
    dplyr::left_join(algorithm_ranking, by = c("Cohort", "Model")) %>%
    dplyr::mutate(
      rel_weight = ifelse(is.na(rel_weight), 1, rel_weight),
      importance_scaled = importance_normalized * rel_weight,
      importance = importance_scaled
    ) %>%
    dplyr::select(-importance_scaled)

  # ------------------------
  # Heatmap: feature vs Cohort×Model
  # ------------------------
  cat("\n→ Creating feature importance heatmap...\n")
  all_unique_features <- unique(feature_matrix$feature)
  feature_order <- feature_matrix %>%
    dplyr::group_by(feature) %>%
    dplyr::summarise(total_importance = sum(importance), .groups = "drop") %>%
    dplyr::arrange(desc(total_importance)) %>%
    dplyr::pull(feature)

  feature_matrix <- feature_matrix %>%
    dplyr::mutate(
      feature = factor(feature, levels = feature_order),
      cohort_method_label = paste(Cohort, Model, sep = "\n")
    )

  p1 <- ggplot(feature_matrix, aes(x = cohort_method_label, y = feature, fill = importance)) +
    geom_tile(color = "white", linewidth = 0.1) +
    scale_fill_gradient(low = "orange", high = "darkblue", name = "Importance") +
    labs(title = "Clinical Feature Importance by Cohort and Model (MC-CV)",
         x = "Cohort × Model", y = "Feature") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 0, hjust = 0.5, size = 10),
          axis.text.y = element_text(size = 8))

  ggplot2::ggsave(file.path(plot_dir, "feature_importance_heatmap.png"), p1,
                  width = 12,
                  height = max(16, length(all_unique_features) * 0.3),
                  dpi = 300,
                  limitsize = FALSE)
  cat("✓ Saved: feature_importance_heatmap.png\n")

  # ------------------------
  # C-index heatmap (cohort × model)
  # ------------------------
  cat("\n→ Creating C-index heatmap...\n")
  cindex_heatmap_data <- cindex_cohort %>%
    dplyr::select(Cohort, Model, C_Index_Mean) %>%
    dplyr::rename(cindex = C_Index_Mean)

  p2 <- ggplot(cindex_heatmap_data, aes(x = Model, y = Cohort, fill = cindex)) +
    geom_tile(color = "white", linewidth = 0.5) +
    geom_text(aes(label = sprintf("%.3f", cindex)), color = "black",
              size = 4, fontface = "bold") +
    scale_fill_gradient2(low = "red", mid = "white", high = "green",
                         midpoint = 0.5, name = "C-index") +
    labs(title = "Concordance Index by Clinical Cohort and Model (MC-CV)",
         x = "Model", y = "Cohort") +
    theme_minimal()

  ggplot2::ggsave(file.path(plot_dir, "cindex_heatmap.png"), p2,
                  width = 10, height = 4, dpi = 300)
  cat("✓ Saved: cindex_heatmap.png\n")

  # ------------------------
  # Scaled bar chart (Top 20 clinical features)
  # ------------------------
  cat("\n→ Creating scaled feature importance bar chart...\n")
  scaled_feature_importance <- feature_matrix %>%
    dplyr::group_by(feature) %>%
    dplyr::summarise(
      total_scaled_importance = sum(importance_normalized * rel_weight, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::arrange(desc(total_scaled_importance)) %>%
    dplyr::slice_head(n = 20)

  scaled_feature_importance <- scaled_feature_importance %>%
    dplyr::mutate(feature = factor(feature, levels = rev(scaled_feature_importance$feature)))

  p3 <- ggplot(scaled_feature_importance, aes(x = feature, y = total_scaled_importance)) +
    geom_bar(stat = "identity", fill = "steelblue", alpha = 0.8) +
    coord_flip() +
    labs(
      title = "Scaled Clinical Feature Importance (Top 20 Features)",
      subtitle = "Importance scaled by cohort/model performance (MC-CV C-index)",
      x = "Feature",
      y = "Scaled Normalized Importance"
    ) +
    theme_minimal()

  ggplot2::ggsave(file.path(plot_dir, "scaled_feature_importance_bar_chart.png"), p3,
                  width = 12, height = 10, dpi = 300)
  cat("✓ Saved: scaled_feature_importance_bar_chart.png\n")

  # ------------------------
  # C-index summary table
  # ------------------------
  cat("\n→ Creating C-index table...\n")
  if (all(c("C_Index_CI_Lower", "C_Index_CI_Upper") %in% names(cindex_cohort))) {
    cindex_table <- cindex_cohort %>%
      dplyr::mutate(
        C_Index_Formatted = sprintf("%.3f (%.3f-%.3f)",
                                    C_Index_Mean,
                                    C_Index_CI_Lower,
                                    C_Index_CI_Upper)
      ) %>%
      dplyr::select(
        Cohort,
        Model,
        C_Index_Formatted,
        n_splits
      ) %>%
      dplyr::rename(
        `C-index (95% CI)` = C_Index_Formatted,
        `N Splits` = n_splits
      )
  } else {
    # Fallback if CI columns are missing
    cindex_table <- cindex_cohort %>%
      dplyr::select(
        Cohort,
        Model,
        C_Index_Mean,
        n_splits
      ) %>%
      dplyr::rename(
        `C-index` = C_Index_Mean,
        `N Splits` = n_splits
      )
  }

  readr::write_csv(cindex_table, file.path(plot_dir, "cindex_table.csv"))
  cat("✓ Saved: cindex_table.csv\n")

  # ------------------------
  # Sankey diagram: combined cohorts → features
  # ------------------------
  sankey_data <- best_features %>%
    dplyr::group_by(Cohort, feature) %>%
    dplyr::summarise(
      value = sum(importance, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::filter(!is.na(value) & value > 0)

  if (nrow(sankey_data) > 0) {
    cat("\n→ Creating cohort clinical feature Sankey diagram...\n")
    all_nodes <- unique(c(sankey_data$Cohort, sankey_data$feature))

    links <- sankey_data %>%
      dplyr::mutate(
        source = match(Cohort, all_nodes) - 1,
        target = match(feature, all_nodes) - 1
      )

    sankey_plot <- plot_ly(
      type = "sankey",
      orientation = "h",
      node = list(
        label = all_nodes,
        pad = 15,
        thickness = 20,
        line = list(color = "black", width = 0.5)
      ),
      link = list(
        source = links$source,
        target = links$target,
        value = links$value
      )
    ) %>%
      layout(
        title = "Cohorts → Modifiable Clinical Features (MC-CV best models)",
        font = list(size = 10)
      )

    # Save HTML widget
    htmlwidgets::saveWidget(
      sankey_plot,
      file = file.path(plot_dir, "cohort_clinical_feature_sankey.html"),
      selfcontained = TRUE
    )
    cat("✓ Saved: cohort_clinical_feature_sankey.html\n")
  } else {
    cat("⚠ No data available to generate cohort Sankey diagram.\n")
  }

  cat("\n========================================\n")
  cat("Visualization Summary\n")
  cat("========================================\n")
  cat(sprintf("Plots saved to: %s\n", normalizePath(plot_dir)))
}

# Run when executed non-interactively (e.g., via `Rscript`).
# When this file is `source()`-d in an interactive notebook, it will not
# auto-run. Notebooks can call `compute_rel_weights()` or `run_visualizations()`
# explicitly as needed.
if (!interactive()) {
  run_visualizations()
}