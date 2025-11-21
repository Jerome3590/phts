# Create visualization plots for feature importance and C-index analysis
# This script creates plots comparing methods and cohorts

library(tidyverse)
library(ggplot2)
library(gridExtra)

# Set output directory
output_dir <- "graft-loss/feature_importance/outputs"
plot_dir <- file.path(output_dir, "plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

# Read data
summary_stats <- read_csv(file.path(output_dir, "summary_statistics.csv"))
cindex_td <- read_csv(file.path(output_dir, "cindex_td_comparison_wide.csv"))
cindex_ti <- read_csv(file.path(output_dir, "cindex_ti_comparison_wide.csv"))
rsf_features <- read_csv(file.path(output_dir, "rsf_comparison_all_periods.csv"))
catboost_features <- read_csv(file.path(output_dir, "catboost_comparison_all_periods.csv"))
aorsf_features <- read_csv(file.path(output_dir, "aorsf_comparison_all_periods.csv"))

# 1. C-index Comparison Plot
cindex_long <- bind_rows(
  cindex_td %>% mutate(cindex_type = "Time-Dependent") %>%
    pivot_longer(cols = c(RSF, CatBoost, AORSF), names_to = "method", values_to = "cindex"),
  cindex_ti %>% mutate(cindex_type = "Time-Independent") %>%
    pivot_longer(cols = c(RSF, CatBoost, AORSF), names_to = "method", values_to = "cindex")
)

p1 <- ggplot(cindex_long, aes(x = period, y = cindex, fill = method)) +
  geom_bar(stat = "identity", position = "dodge") +
  facet_wrap(~cindex_type, scales = "free_y") +
  labs(title = "C-index Comparison Across Methods and Cohorts",
       x = "Cohort", y = "C-index", fill = "Method") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(plot_dir, "cindex_comparison.png"), p1, width = 12, height = 6, dpi = 300)

# 2. Feature Importance Top 10 Comparison
plot_top_features <- function(feature_df, method_name, cohort_name) {
  feature_df %>%
    filter(period == cohort_name) %>%
    slice_head(n = 10) %>%
    ggplot(aes(x = reorder(feature, importance), y = importance)) +
    geom_bar(stat = "identity", fill = "steelblue") +
    coord_flip() +
    labs(title = paste(method_name, "-", cohort_name, "- Top 10 Features"),
         x = "Feature", y = "Importance") +
    theme_minimal()
}

# Create plots for each method and cohort
for (cohort in c("original", "full", "full_no_covid")) {
  p_rsf <- plot_top_features(rsf_features, "RSF", cohort)
  p_catboost <- plot_top_features(catboost_features, "CatBoost", cohort)
  p_aorsf <- plot_top_features(aorsf_features, "AORSF", cohort)
  
  p_combined <- grid.arrange(p_rsf, p_catboost, p_aorsf, ncol = 3)
  ggsave(file.path(plot_dir, paste0("top10_features_", cohort, ".png")), 
         p_combined, width = 18, height = 6, dpi = 300)
}

# 3. Feature Stability Across Cohorts
get_top10_features <- function(feature_df, method_name) {
  feature_df %>%
    group_by(period) %>%
    slice_head(n = 10) %>%
    select(period, feature, importance) %>%
    mutate(method = method_name)
}

all_top10 <- bind_rows(
  get_top10_features(rsf_features, "RSF"),
  get_top10_features(catboost_features, "CatBoost"),
  get_top10_features(aorsf_features, "AORSF")
)

# Count how many times each feature appears in top 10 across cohorts
feature_stability <- all_top10 %>%
  group_by(method, feature) %>%
  summarise(n_cohorts = n(), .groups = "drop") %>%
  arrange(method, desc(n_cohorts))

p2 <- ggplot(feature_stability %>% filter(n_cohorts >= 2), 
             aes(x = reorder(feature, n_cohorts), y = n_cohorts, fill = method)) +
  geom_bar(stat = "identity", position = "dodge") +
  facet_wrap(~method, scales = "free_y") +
  coord_flip() +
  labs(title = "Feature Stability: Features Appearing in Top 10 Across Multiple Cohorts",
       x = "Feature", y = "Number of Cohorts", fill = "Method") +
  theme_minimal()

ggsave(file.path(plot_dir, "feature_stability.png"), p2, width = 14, height = 8, dpi = 300)

# 4. C-index Changes Across Cohorts
cindex_changes <- bind_rows(
  cindex_td %>% mutate(cindex_type = "Time-Dependent") %>%
    pivot_longer(cols = c(RSF, CatBoost, AORSF), names_to = "method", values_to = "cindex"),
  cindex_ti %>% mutate(cindex_type = "Time-Independent") %>%
    pivot_longer(cols = c(RSF, CatBoost, AORSF), names_to = "method", values_to = "cindex")
) %>%
  mutate(period = factor(period, levels = c("original", "full", "full_no_covid")))

p3 <- ggplot(cindex_changes, aes(x = period, y = cindex, color = method, group = method)) +
  geom_line(size = 1.2) +
  geom_point(size = 3) +
  facet_wrap(~cindex_type, scales = "free_y") +
  labs(title = "C-index Changes Across Cohorts",
       x = "Cohort", y = "C-index", color = "Method") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(plot_dir, "cindex_changes.png"), p3, width = 12, height = 6, dpi = 300)

# 5. Feature Importance Comparison (Top 5)
plot_top5_comparison <- function(feature_df, method_name) {
  feature_df %>%
    group_by(period) %>%
    slice_head(n = 5) %>%
    mutate(rank = row_number()) %>%
    ggplot(aes(x = factor(rank), y = importance, fill = period)) +
    geom_bar(stat = "identity", position = "dodge") +
    labs(title = paste(method_name, "- Top 5 Features Comparison"),
         x = "Rank", y = "Importance", fill = "Cohort") +
    theme_minimal()
}

p_rsf_top5 <- plot_top5_comparison(rsf_features, "RSF")
p_catboost_top5 <- plot_top5_comparison(catboost_features, "CatBoost")
p_aorsf_top5 <- plot_top5_comparison(aorsf_features, "AORSF")

p_top5_combined <- grid.arrange(p_rsf_top5, p_catboost_top5, p_aorsf_top5, ncol = 1)
ggsave(file.path(plot_dir, "top5_comparison.png"), p_top5_combined, width = 10, height = 12, dpi = 300)

cat("Plots saved to:", plot_dir, "\n")
cat("Created plots:\n")
cat("  1. cindex_comparison.png - C-index comparison across methods and cohorts\n")
cat("  2. top10_features_*.png - Top 10 features for each cohort\n")
cat("  3. feature_stability.png - Feature stability across cohorts\n")
cat("  4. cindex_changes.png - C-index changes across cohorts\n")
cat("  5. top5_comparison.png - Top 5 features comparison\n")

