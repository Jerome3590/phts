# Create visualization plots for feature importance and C-index analysis
# Updated to match MC-CV implementation output structure
# Creates: Feature importance heatmap, C-index heatmap, and C-index table
# 
# Usage: 
#   - As a function: source("scripts/R/create_visualizations.R"); run_visualizations()
#   - As a script: Rscript scripts/R/create_visualizations.R

library(tidyverse)
library(ggplot2)
library(here)

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
# Read MC-CV results
cindex_comparison <- read_csv(file.path(output_dir, "cindex_comparison_mc_cv.csv"))

# Read individual feature files for each method and period
periods <- c("original", "full", "full_no_covid")
methods <- c("rsf", "catboost", "aorsf")

# Load feature importance data
# Map lowercase method names to the format used in cindex_comparison
method_map <- c("rsf" = "RSF", "catboost" = "CatBoost", "aorsf" = "AORSF")

load_features <- function(period, method) {
  file_path <- file.path(output_dir, sprintf("%s_%s_top20.csv", period, method))
  if (file.exists(file_path)) {
    df <- read_csv(file_path) %>%
      mutate(period = period, method = method_map[[method]])
    cat(sprintf("✓ Loaded: %s\n", basename(file_path)))
    return(df)
  } else {
    warning(sprintf("File not found: %s", file_path))
    return(NULL)
  }
}

# Combine all feature files - read all 9 files (3 periods × 3 methods)
cat("\nLoading feature importance files...\n")
all_features <- map_df(periods, function(p) {
  map_df(methods, function(m) {
    load_features(p, m)
  })
}) %>%
  filter(!is.null(feature))

# Verify we loaded all expected files
expected_files <- length(periods) * length(methods)
loaded_count <- length(unique(paste(all_features$period, all_features$method)))
cat(sprintf("\nLoaded %d/%d expected feature files\n", loaded_count, expected_files))
cat(sprintf("Total features loaded: %d\n", nrow(all_features)))
cat(sprintf("Unique features: %d\n", length(unique(all_features$feature))))

# ============================================================================
# 1. FEATURE IMPORTANCE HEATMAP
# ============================================================================

cat("\nCreating feature importance heatmap...\n")

# Get all unique features across all methods and periods
all_unique_features <- unique(all_features$feature)

# Debug: Check what methods and periods are actually in the data
cat("\nDebug: Methods in all_features:", unique(all_features$method), "\n")
cat("Debug: Periods in all_features:", unique(all_features$period), "\n")
cat("Debug: Sample of all_features:\n")
print(head(all_features %>% select(feature, period, method, importance), 10))

# Create a matrix: features (rows) x cohort-method combinations (columns)
# For each feature, get its importance value (or 0 if not in top 20)
feature_matrix <- map_df(all_unique_features, function(feat) {
  map_df(periods, function(per) {
    map_df(methods, function(meth) {
      method_name <- method_map[[meth]]
      feat_data <- all_features %>%
        filter(feature == feat, period == per, method == method_name)
      
      importance_val <- if (nrow(feat_data) > 0) {
        feat_data$importance[1]
      } else {
        0
      }
      
      tibble(
        feature = feat,
        period = per,
        method = method_name,
        importance = importance_val
      )
    })
  })
}) %>%
  mutate(
    cohort_method = paste(period, method, sep = "_"),
    period = factor(period, levels = c("original", "full", "full_no_covid")),
    method = factor(method, levels = c("RSF", "CatBoost", "AORSF"))
  )

# Debug: Check feature_matrix before normalization
cat("\nDebug: Feature matrix summary (before normalization):\n")
cat("Methods in feature_matrix:", unique(feature_matrix$method), "\n")
cat("Non-zero importance values by method:\n")
print(feature_matrix %>% 
      group_by(method) %>% 
      summarise(n_nonzero = sum(importance > 0), 
                max_importance = max(importance), 
                mean_importance = mean(importance), 
                .groups = "drop"))

# Normalize importance values within each method-period combination
# This makes values comparable across different algorithms (RSF, CatBoost, AORSF)
feature_matrix <- feature_matrix %>%
  group_by(period, method) %>%
  mutate(
    importance_normalized = if (max(importance) > 0) {
      (importance - min(importance)) / (max(importance) - min(importance))
    } else {
      0
    }
  ) %>%
  ungroup()

cat("\nDebug: After normalization - importance range by method:\n")
print(feature_matrix %>% 
      group_by(method) %>% 
      summarise(min_imp = min(importance_normalized), 
                max_imp = max(importance_normalized), 
                mean_imp = mean(importance_normalized), 
                .groups = "drop"))

# Determine algorithm ranking by C-index for each period
# Best algorithm gets scale factor 3, second best gets 2, third gets 1
cat("\nDetermining algorithm ranking by C-index for scaling...\n")
algorithm_ranking <- cindex_comparison %>%
  select(period, method, cindex_td_mean) %>%
  group_by(period) %>%
  arrange(desc(cindex_td_mean)) %>%
  mutate(
    rank = row_number(),
    scale_factor = case_when(
      rank == 1 ~ 3,  # Best algorithm
      rank == 2 ~ 2,  # Second best algorithm
      rank == 3 ~ 1   # Third algorithm (no scaling)
    )
  ) %>%
  ungroup() %>%
  select(period, method, scale_factor)

cat("Algorithm ranking and scale factors:\n")
print(algorithm_ranking)

# Apply scaling to normalized feature importance
feature_matrix <- feature_matrix %>%
  left_join(algorithm_ranking, by = c("period", "method")) %>%
  mutate(
    importance_scaled = importance_normalized * scale_factor,
    importance = importance_scaled  # Use scaled values for heatmap
  ) %>%
  select(-importance_scaled)

cat("\nDebug: After scaling - importance range by method:\n")
print(feature_matrix %>% 
      group_by(method) %>% 
      summarise(min_imp = min(importance), 
                max_imp = max(importance), 
                mean_imp = mean(importance), 
                .groups = "drop"))

# Create heatmap
# Order features by total importance across all cohort-method combinations
feature_order <- feature_matrix %>%
  group_by(feature) %>%
  summarise(total_importance = sum(importance), .groups = "drop") %>%
  arrange(desc(total_importance)) %>%
  pull(feature)

feature_matrix <- feature_matrix %>%
  mutate(feature = factor(feature, levels = feature_order))

# Create cohort_method labels with better formatting
feature_matrix <- feature_matrix %>%
  mutate(
    cohort_label = case_when(
      period == "original" ~ "Original",
      period == "full" ~ "Full",
      period == "full_no_covid" ~ "Full No COVID"
    ),
    cohort_method_label = paste(cohort_label, method, sep = "\n")
  )

p1 <- ggplot(feature_matrix, aes(x = cohort_method_label, y = feature, fill = importance)) +
  geom_tile(color = "white", linewidth = 0.1) +
  scale_fill_gradient(low = "orange", high = "darkblue",
                      name = "Importance") +
  labs(title = "Feature Importance Heatmap by Cohort and Algorithm",
       x = "Cohort × Algorithm", y = "Feature") +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 0, hjust = 0.5, size = 10),
    axis.text.y = element_text(size = 8),
    axis.title = element_text(size = 12, face = "bold"),
    plot.title = element_text(size = 14, face = "bold", hjust = 0.5),
    legend.position = "right",
    panel.grid = element_blank()
  )

ggsave(file.path(plot_dir, "feature_importance_heatmap.png"), p1, 
       width = 12, height = max(16, length(all_unique_features) * 0.3), dpi = 300, limitsize = FALSE)
cat("✓ Saved: feature_importance_heatmap.png\n")

# ============================================================================
# 2. C-INDEX HEATMAP
# ============================================================================

cat("\nCreating C-index heatmap...\n")

# Prepare data for C-index heatmap (both time-dependent and time-independent)
cindex_heatmap_data <- bind_rows(
  cindex_comparison %>%
    select(period, method, cindex_td_mean) %>%
    rename(cindex = cindex_td_mean) %>%
    mutate(cindex_type = "Time-Dependent"),
  cindex_comparison %>%
    select(period, method, cindex_ti_mean) %>%
    rename(cindex = cindex_ti_mean) %>%
    mutate(cindex_type = "Time-Independent")
) %>%
  mutate(
    period = factor(period, levels = c("original", "full", "full_no_covid")),
    method = factor(method, levels = c("RSF", "CatBoost", "AORSF")),
    cohort_label = case_when(
      period == "original" ~ "Original",
      period == "full" ~ "Full",
      period == "full_no_covid" ~ "Full No COVID"
    )
  )

p2 <- ggplot(cindex_heatmap_data, aes(x = method, y = cohort_label, fill = cindex)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = sprintf("%.3f", cindex)), color = "black", size = 4, fontface = "bold") +
  scale_fill_gradient2(low = "red", mid = "white", high = "green",
                       midpoint = 0.5,
                       name = "C-index") +
  facet_wrap(~cindex_type, ncol = 2) +
  labs(title = "Concordance Index Heatmap by Cohort and Algorithm (MC-CV)",
       x = "Algorithm", y = "Cohort") +
  theme_minimal() +
  theme(
    axis.text = element_text(size = 11),
    axis.title = element_text(size = 12, face = "bold"),
    plot.title = element_text(size = 14, face = "bold", hjust = 0.5),
    legend.position = "right",
    strip.text = element_text(size = 12, face = "bold"),
    panel.grid = element_blank()
  )

ggsave(file.path(plot_dir, "cindex_heatmap.png"), p2, width = 12, height = 6, dpi = 300)
cat("✓ Saved: cindex_heatmap.png\n")

# ============================================================================
# 3. SCALED FEATURE IMPORTANCE BAR CHART
# ============================================================================

cat("\nCreating scaled feature importance bar chart...\n")

# Aggregate scaled importance by feature across all periods and methods
# Sum the scaled importance values for each feature
scaled_feature_importance <- feature_matrix %>%
  group_by(feature) %>%
  summarise(
    total_scaled_importance = sum(importance_normalized * scale_factor, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(total_scaled_importance)) %>%
  # Get top 20 features
  slice_head(n = 20)

# Order features by total scaled importance
scaled_feature_importance <- scaled_feature_importance %>%
  mutate(feature = factor(feature, levels = rev(scaled_feature_importance$feature)))

p3 <- ggplot(scaled_feature_importance, aes(x = feature, y = total_scaled_importance)) +
  geom_bar(stat = "identity", fill = "steelblue", alpha = 0.8) +
  coord_flip() +
  labs(
    title = "Scaled Feature Importance (Top 20 Features)",
    subtitle = "Importance scaled by algorithm performance: Best C-index (×3), Second best (×2), Third (×1)",
    x = "Feature",
    y = "Scaled Normalized Importance"
  ) +
  theme_minimal() +
  theme(
    axis.text = element_text(size = 10),
    axis.title = element_text(size = 12, face = "bold"),
    plot.title = element_text(size = 14, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 11, hjust = 0.5),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank()
  )

ggsave(file.path(plot_dir, "scaled_feature_importance_bar_chart.png"), p3, 
       width = 12, height = 10, dpi = 300)
cat("✓ Saved: scaled_feature_importance_bar_chart.png\n")

# ============================================================================
# 4. C-INDEX TABLE
# ============================================================================

cat("\nCreating C-index table...\n")

# Create formatted table with both C-index types and confidence intervals
cindex_table <- cindex_comparison %>%
  mutate(
    period_label = case_when(
      period == "original" ~ "Original",
      period == "full" ~ "Full",
      period == "full_no_covid" ~ "Full No COVID"
    ),
    # Format C-index with CI
    cindex_td_formatted = sprintf("%.3f (%.3f-%.3f)", 
                                  cindex_td_mean, cindex_td_ci_lower, cindex_td_ci_upper),
    cindex_ti_formatted = sprintf("%.3f (%.3f-%.3f)", 
                                   cindex_ti_mean, cindex_ti_ci_lower, cindex_ti_ci_upper)
  ) %>%
  select(period_label, method, cindex_td_formatted, cindex_ti_formatted, n_splits) %>%
  arrange(period_label, method) %>%
  rename(
    Cohort = period_label,
    Algorithm = method,
    `Time-Dependent C-index (95% CI)` = cindex_td_formatted,
    `Time-Independent C-index (95% CI)` = cindex_ti_formatted,
    `N Splits` = n_splits
  )

# Save as CSV
write_csv(cindex_table, file.path(plot_dir, "cindex_table.csv"))
cat("✓ Saved: cindex_table.csv\n")

# Also create a formatted text table for display
cat("\n========================================\n")
cat("Concordance Index Table\n")
cat("========================================\n")
print(cindex_table)
cat("\n")

# Save summary
cat("\n========================================\n")
cat("Visualization Summary\n")
cat("========================================\n")
cat("Plots saved to:", plot_dir, "\n")
cat("Created visualizations:\n")
cat("  1. feature_importance_heatmap.png - Feature importance by cohort and algorithm (scaled by C-index)\n")
cat("  2. cindex_heatmap.png - Concordance index by cohort and algorithm\n")
cat("  3. scaled_feature_importance_bar_chart.png - Bar chart of scaled feature importance (top 20)\n")
cat("  4. cindex_table.csv - Concordance index table with confidence intervals\n")
cat("\nAll visualizations use MC-CV results with 95% confidence intervals.\n")
cat("Feature importance values are normalized within each method-period combination,\n")
cat("then scaled by algorithm performance: Best C-index algorithm (×3), Second best (×2), Third (×1).\n")
}

# Run when executed non-interactively (e.g., via `Rscript`).
# When this file is `source()`-d in an interactive notebook, it will not
# auto-run. Notebooks can call `run_visualizations()` explicitly as needed.
if (!interactive()) {
  run_visualizations()
}

