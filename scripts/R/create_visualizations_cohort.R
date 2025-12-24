#!/usr/bin/env Rscript
# Consolidated visualization + importance-weights script
# This file inlines the compute_rel_weights() helper and the visualization pipeline.

library(tidyverse)
library(ggplot2)
library(plotly)
library(here)

# Helper: safely save HTML widget (handles Windows file locking issues)
# This prevents temporary files with random suffixes from being left behind
save_widget_safely <- function(widget, file, selfcontained = TRUE) {
  # Remove any existing temp files with random suffixes
  file_dir <- dirname(file)
  file_base <- basename(file)
  file_pattern <- paste0("^", gsub("\\.", "\\\\.", file_base), "\\.[A-F0-9]{8}$")
  temp_files <- list.files(file_dir, pattern = file_pattern, full.names = TRUE)
  if (length(temp_files) > 0) {
    tryCatch({
      file.remove(temp_files)
      cat("  Cleaned up", length(temp_files), "temporary file(s)\n")
    }, error = function(e) {
      # Ignore errors when cleaning up
    })
  }
  
  # Save to a temporary file first, then rename (avoids file locking issues)
  temp_file <- tempfile(fileext = ".html", tmpdir = file_dir)
  
  # Try selfcontained first, fall back to FALSE if pandoc is not available
  save_result <- tryCatch({
    htmlwidgets::saveWidget(
      widget,
      file = temp_file,
      selfcontained = selfcontained
    )
    TRUE
  }, error = function(e) {
    if (grepl("pandoc", e$message, ignore.case = TRUE) && selfcontained) {
      cat("  Warning: pandoc not available, using selfcontained = FALSE\n")
      htmlwidgets::saveWidget(
        widget,
        file = temp_file,
        selfcontained = FALSE
      )
      TRUE
    } else {
      stop(e)
    }
  })
  
  # Rename temp file to final name
  if (file.exists(temp_file)) {
    # Remove target file if it exists
    if (file.exists(file)) {
      file.remove(file)
    }
    file.rename(temp_file, file)
  } else {
    stop("Failed to create HTML widget file")
  }
}

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
  # Prefer here::here-based paths so it works on both Windows and Linux
  # when the project is opened from either the repo root or the
  # cohort_analysis subdirectory.
  if (is.null(output_dir)) {
    # Here root for this project is typically '.../graft-loss/cohort_analysis'
    # so here(\"outputs\", \"survival\") is the canonical survival outputs dir.
    survival_dir_here <- here::here("outputs", "survival")
    generic_dir_here  <- here::here("outputs")

    if (dir.exists(file.path(survival_dir_here, "summary"))) {
      output_dir <- survival_dir_here
    } else if (dir.exists(survival_dir_here)) {
      output_dir <- survival_dir_here
    } else if (dir.exists(generic_dir_here)) {
      output_dir <- generic_dir_here
    } else if (dir.exists("outputs/survival/summary")) {
      # Fallback to working-directory-relative paths if here() is not aligned
      output_dir <- "outputs/survival"
    } else if (dir.exists("outputs/summary")) {
      output_dir <- "outputs"
    } else {
      current_dir <- getwd()
      stop(
        "Cannot find outputs directory. Tried:\n  - ",
        survival_dir_here, "\n  - ", generic_dir_here,
        "\n  - outputs/survival (relative to ", current_dir, ")",
        "\nMake sure you're running from the cohort_analysis project (here() root) ",
        "and have run Sections 6.3-6.4 first."
      )
    }
  }
  # Summary directory for combined cohort comparisons
  summary_dir <- file.path(output_dir, "summary")
  plot_dir_summary <- file.path(summary_dir, "plots")
  dir.create(plot_dir_summary, showWarnings = FALSE, recursive = TRUE)

  # Clean existing plots directories to ensure fresh/clean visualizations
  if (dir.exists(plot_dir_summary)) {
    plot_files <- list.files(plot_dir_summary, full.names = TRUE, recursive = TRUE, include.dirs = FALSE)
    if (length(plot_files) > 0) {
      cat(sprintf("→ Cleaning %d existing plot files...\n", length(plot_files)))
      file.remove(plot_files)
    }
    cat("✓ Summary plots directory cleaned\n")
  }

  cat("→ Reading cohort MC-CV results...\n")
  cindex_cohort_path <- file.path(summary_dir, "cohort_model_cindex_mc_cv_modifiable_clinical.csv")
  best_feat_path     <- file.path(summary_dir, "best_clinical_features_by_cohort_mc_cv.csv")

  if (!file.exists(cindex_cohort_path)) {
    stop("Expected cohort C-index file 'cohort_model_cindex_mc_cv_modifiable_clinical.csv' not found in: ", summary_dir)
  }
  if (!file.exists(best_feat_path)) {
    stop("Expected best-features file 'best_clinical_features_by_cohort_mc_cv.csv' not found in: ", summary_dir)
  }

  cindex_cohort <- readr::read_csv(cindex_cohort_path)
  best_features <- readr::read_csv(best_feat_path)

  # Prepare feature matrix: Cohort × Model × Feature
  # NOTE: We intentionally do NOT normalize importance within each Cohort×Model here.
  #       This preserves real differences in total feature contribution between cohorts
  #       and avoids forcing total contribution to be ~equal across cohorts.
  feature_matrix <- best_features %>%
    dplyr::select(Cohort, Model, feature, importance) %>%
    # Remove NA features (both actual NA and string "NA")
    dplyr::filter(!is.na(feature) & feature != "NA" & feature != "" & !is.na(Cohort) & !is.na(Model)) %>%
    dplyr::mutate(
      Cohort = as.character(Cohort),
      Model  = as.character(Model),
      importance = as.numeric(importance)
    ) %>%
    dplyr::mutate(
      importance = ifelse(is.na(importance) | importance < 0, 0, importance)
    )

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
      # Scale raw importance by relative model weight (based on C-index),
      # without per-model normalization. This lets cohorts with stronger
      # overall signal (or more dominant models) contribute more total mass.
      importance_scaled = importance * rel_weight,
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

  ggplot2::ggsave(file.path(plot_dir_summary, "feature_importance_heatmap.png"), p1,
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

  ggplot2::ggsave(file.path(plot_dir_summary, "cindex_heatmap.png"), p2,
                  width = 10, height = 4, dpi = 300)
  cat("✓ Saved: cindex_heatmap.png\n")

  # ------------------------
  # Scaled bar chart (Top 20 clinical features) - grouped by cohort
  # ------------------------
  cat("\n→ Creating scaled feature importance bar chart (by cohort)...\n")
  
  # Calculate scaled importance by cohort and feature
  scaled_feature_importance_by_cohort <- feature_matrix %>%
    dplyr::group_by(Cohort, feature) %>%
    dplyr::summarise(
      scaled_importance = sum(importance, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    # Drop missing / placeholder feature or cohort values so they don't appear in plots
    dplyr::filter(
      !is.na(feature),
      feature != "NA",
      feature != "",
      !is.na(Cohort)
    )
  
  # Get top 20 features across all cohorts (by total importance)
  top_features <- scaled_feature_importance_by_cohort %>%
    dplyr::group_by(feature) %>%
    dplyr::summarise(
      total_scaled_importance = sum(scaled_importance, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::arrange(desc(total_scaled_importance)) %>%
    dplyr::slice_head(n = 20) %>%
    dplyr::pull(feature)
  
  # Get all unique cohorts
  all_cohorts <- unique(scaled_feature_importance_by_cohort$Cohort)
  
  # Filter to top features and ensure all cohort-feature combinations exist
  scaled_feature_importance <- scaled_feature_importance_by_cohort %>%
    dplyr::filter(feature %in% top_features) %>%
    # Complete the data to ensure all cohort-feature combinations exist
    tidyr::complete(Cohort = all_cohorts, feature = top_features, fill = list(scaled_importance = 0)) %>%
    dplyr::mutate(
      feature = factor(feature, levels = rev(top_features)),
      Cohort = factor(Cohort)
    ) %>%
    # Final safety filter to drop any NA / placeholder feature labels before plotting
    dplyr::filter(!is.na(feature) & feature != "NA" & feature != "")

  # Ensure Cohort is a factor for proper grouping
  scaled_feature_importance <- scaled_feature_importance %>%
    dplyr::mutate(Cohort = factor(Cohort))
  
  # Create a side-by-side grouped bar chart: features on the y-axis,
  # cohorts staggered alongside each other (wider bars for visibility).
  # Colors are aligned with the heatmap palette:
  # - CHD: orange
  # - MyoCardio: royal blue
  p3 <- ggplot(
    scaled_feature_importance,
    aes(x = feature, y = scaled_importance, fill = Cohort)
  ) +
    geom_col(
      position = position_dodge(width = 0.9),
      width = 0.8,
      alpha = 0.9
    ) +
    coord_flip() +
    scale_fill_manual(
      values = c(
        "CHD" = "orange",
        "MyoCardio" = "royalblue3"
      ),
      name = "Cohort"
    ) +
    labs(
      title = "Scaled Clinical Feature Importance by Cohort (Top 20 Features)",
      subtitle = "Importance scaled by cohort/model performance (MC-CV C-index)",
      x = "Feature",
      y = "Scaled Normalized Importance"
    ) +
    theme_minimal() +
    theme(
      legend.position = "right",
      axis.text.y = element_text(size = 8)
    )

  ggplot2::ggsave(file.path(plot_dir_summary, "scaled_feature_importance_bar_chart.png"), p3,
                  width = 14, height = 10, dpi = 300)
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

  readr::write_csv(cindex_table, file.path(plot_dir_summary, "cindex_table.csv"))
  cat("✓ Saved: cindex_table.csv\n")

  # ------------------------
  # Sankey diagram 1: combined cohorts → features (raw importance)
  # ------------------------
  sankey_data <- best_features %>%
    # Remove NA features (both actual NA and string "NA")
    dplyr::filter(!is.na(feature) & feature != "NA" & feature != "" & !is.na(Cohort)) %>%
    dplyr::group_by(Cohort, feature) %>%
    dplyr::summarise(
      value = sum(importance, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::filter(!is.na(value) & value > 0)

  if (nrow(sankey_data) > 0) {
    cat("\n→ Creating cohort clinical feature Sankey diagram (raw importance)...\n")
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
        title = "Cohorts → Modifiable Clinical Features (MC-CV best models, raw importance)",
        font = list(size = 10)
      )

    # Save HTML widget (using safe save to avoid Windows temp file issues)
    save_widget_safely(
      sankey_plot,
      file = file.path(plot_dir_summary, "cohort_clinical_feature_sankey.html"),
      selfcontained = TRUE
    )
    cat("✓ Saved: cohort_clinical_feature_sankey.html\n")
  } else {
    cat("⚠ No data available to generate cohort Sankey diagram.\n")
  }

  # ------------------------
  # Sankey diagram 2: normalized feature importance by cohort
  # For this workflow we normalize raw best-model importance to [0, 1]
  # within each cohort (no C-index scaling), so flows show relative
  # contribution of features for each cohort.
  # ------------------------
  cat("\n→ Creating normalized feature importance Sankey diagram (no C-index scaling)...\n")
  
  sankey_scaled_data <- best_features %>%
    # Keep only valid features/cohorts
    dplyr::filter(!is.na(feature) & feature != "NA" & feature != "" & !is.na(Cohort)) %>%
    # Aggregate raw (non-negative) importance across the best model's MC-CV splits
    dplyr::mutate(importance = as.numeric(importance)) %>%
    dplyr::mutate(importance = ifelse(is.na(importance) | importance < 0, 0, importance)) %>%
    dplyr::group_by(Cohort, feature) %>%
    dplyr::summarise(
      raw_importance = sum(importance, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    # Normalize within each cohort so that sum(feature) = 1
    dplyr::group_by(Cohort) %>%
    dplyr::mutate(
      total_raw = sum(raw_importance, na.rm = TRUE),
      scaled_importance = dplyr::if_else(total_raw > 0, raw_importance / total_raw, 0)
    ) %>%
    dplyr::ungroup() %>%
    dplyr::filter(!is.na(scaled_importance) & scaled_importance > 0) %>%
    dplyr::arrange(desc(scaled_importance))

  if (nrow(sankey_scaled_data) > 0) {
    # Get top features for clarity (top 30 features)
    top_features_scaled <- sankey_scaled_data %>%
      dplyr::group_by(feature) %>%
      dplyr::summarise(total_scaled = sum(scaled_importance), .groups = "drop") %>%
      dplyr::arrange(desc(total_scaled)) %>%
      dplyr::slice_head(n = 30) %>%
      dplyr::pull(feature)
    
    sankey_scaled_data <- sankey_scaled_data %>%
      dplyr::filter(feature %in% top_features_scaled)
    
    all_nodes_scaled <- unique(c(sankey_scaled_data$Cohort, sankey_scaled_data$feature))
    
    links_scaled <- sankey_scaled_data %>%
      dplyr::mutate(
        source = match(Cohort, all_nodes_scaled) - 1,
        target = match(feature, all_nodes_scaled) - 1,
        # Link colors by cohort, aligned with heatmap / bar chart palette
        # CHD       -> orange (low color)
        # MyoCardio -> darkblue (high color)
        link_color = dplyr::case_when(
          Cohort == "CHD" ~ "rgba(255,165,0,0.4)",     # orange
          Cohort == "MyoCardio" ~ "rgba(0,0,139,0.4)", # darkblue
          TRUE ~ "rgba(128,128,128,0.3)"               # fallback
        )
      )
    
    # Node colors:
    # - Cohort nodes fixed at the palette extremes (orange = CHD, darkblue = MyoCardio)
    # - Feature nodes use a gradient from orange -> darkblue based on the
    #   fraction of their normalized importance coming from MyoCardio vs CHD.
    #   0   -> all CHD (orange)
    #   0.5 -> balanced (mid color)
    #   1   -> all MyoCardio (darkblue)
    is_cohort_node <- all_nodes_scaled %in% unique(sankey_scaled_data$Cohort)

    feature_mix <- sankey_scaled_data %>%
      dplyr::group_by(feature) %>%
      dplyr::summarise(
        contrib_CHD = sum(dplyr::if_else(Cohort == "CHD", scaled_importance, 0), na.rm = TRUE),
        contrib_Myo = sum(dplyr::if_else(Cohort == "MyoCardio", scaled_importance, 0), na.rm = TRUE),
        total       = contrib_CHD + contrib_Myo,
        frac_myo    = dplyr::if_else(total > 0, contrib_Myo / total, 0),
        .groups     = "drop"
      )
    mix_map <- stats::setNames(feature_mix$frac_myo, feature_mix$feature)

    node_values <- ifelse(
      is_cohort_node,
      NA_real_,
      as.numeric(mix_map[all_nodes_scaled])
    )
    node_values[is.na(node_values)] <- 0

    pal <- grDevices::colorRamp(c("orange", "darkblue"))
    cols <- pal(node_values)
    feature_colors <- grDevices::rgb(cols[, 1], cols[, 2], cols[, 3], maxColorValue = 255)

    node_colors <- ifelse(
      all_nodes_scaled == "CHD", "orange",
      ifelse(
        all_nodes_scaled == "MyoCardio", "darkblue",
        feature_colors
      )
    )
    
    sankey_scaled_plot <- plot_ly(
      type = "sankey",
      orientation = "h",
      node = list(
        label = all_nodes_scaled,
        pad = 15,
        thickness = 20,
        line = list(color = "black", width = 0.5),
        color = node_colors
      ),
      link = list(
        source = links_scaled$source,
        target = links_scaled$target,
        value = links_scaled$scaled_importance,
        color = links_scaled$link_color
      )
    ) %>%
      layout(
        title = list(
          text = "Scaled Normalized Feature Importance Contribution by Cohort (Top 30 Features)<br><sub>Flow width represents scaled normalized importance (importance × model performance weight)</sub>",
          font = list(size = 12)
        ),
        font = list(size = 10)
      )
    
    # Save HTML widget (using safe save to avoid Windows temp file issues)
    save_widget_safely(
      sankey_scaled_plot,
      file = file.path(plot_dir_summary, "cohort_scaled_feature_importance_sankey.html"),
      selfcontained = TRUE
    )
    cat("✓ Saved: cohort_scaled_feature_importance_sankey.html\n")
    
    # Also create a summary table of scaled contributions
    scaled_contribution_summary <- sankey_scaled_data %>%
      dplyr::group_by(Cohort) %>%
      dplyr::summarise(
        total_contribution = sum(scaled_importance, na.rm = TRUE),
        n_features = dplyr::n_distinct(feature),
        .groups = "drop"
      ) %>%
      dplyr::mutate(
        contribution_pct = 100 * total_contribution / sum(total_contribution, na.rm = TRUE)
      ) %>%
      dplyr::arrange(desc(total_contribution))
    
    readr::write_csv(scaled_contribution_summary, 
                     file.path(plot_dir_summary, "cohort_scaled_contribution_summary.csv"))
    cat("✓ Saved: cohort_scaled_contribution_summary.csv\n")
  } else {
    cat("⚠ No data available to generate scaled normalized Sankey diagram.\n")
  }

  cat("\n========================================\n")
  cat("Visualization Summary\n")
  cat("========================================\n")
  cat(sprintf("Combined cohort comparison plots saved to: %s\n", normalizePath(plot_dir_summary)))
}

# Run when executed non-interactively (e.g., via `Rscript`).
# When this file is `source()`-d in an interactive notebook, it will not
# auto-run. Notebooks can call `compute_rel_weights()` or `run_visualizations()`
# explicitly as needed.
if (!interactive()) {
  run_visualizations()
}