##' aorsf Parallel Processing Setup and Demo
##' 
##' This script demonstrates how to use the aorsf parallel processing configuration
##' for optimal performance in the graft loss pipeline.

# Load required packages
suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(survival)
  library(aorsf)
})

# Source the model utilities with aorsf configuration
source(here("R", "utils", "model_utils.R"))

# Source the pipeline configuration
source(here("scripts", "config.R"))

cat("=== aorsf Parallel Processing Setup Demo ===\n\n")

# 1. Display system information
cat("1. System Information:\n")
print_aorsf_system_info()

cat("\n2. Configuring aorsf for Parallel Processing:\n")

# 2. Configure aorsf with optimal settings
aorsf_config <- configure_aorsf_parallel(
  use_all_cores = TRUE,
  target_utilization = 0.8,
  check_r_functions = TRUE,
  verbose = TRUE
)

cat("\n3. Testing aorsf Performance:\n")

# 3. Create sample data for testing
set.seed(42)
n_samples <- 1000
n_features <- 50

# Generate synthetic survival data
sample_data <- data.frame(
  time = rexp(n_samples, rate = 0.1),
  status = rbinom(n_samples, 1, 0.3)
)

# Add random features
for (i in 1:n_features) {
  sample_data[[paste0("feature_", i)]] <- rnorm(n_samples)
}

# Add some signal
sample_data$time <- sample_data$time * (1 + 0.5 * sample_data$feature_1 + 0.3 * sample_data$feature_2)
sample_data$status <- as.numeric(sample_data$time < quantile(sample_data$time, 0.7))

cat(sprintf("Created sample dataset: %d rows, %d features\n", nrow(sample_data), n_features))

# 4. Benchmark different thread configurations
cat("\n4. Benchmarking Thread Configurations:\n")

# Test with different thread counts
thread_configs <- c(1, 2, 4, 8, 0)  # 0 = auto-detect
benchmark_results <- benchmark_aorsf_threads(
  data = sample_data,
  formula = Surv(time, status) ~ .,
  thread_configs = thread_configs,
  n_tree = 500,  # Smaller for faster demo
  n_runs = 2
)

print(benchmark_results)

# 5. Demonstrate optimal aorsf usage
cat("\n5. Optimal aorsf Usage Examples:\n")

# Example 1: Basic parallel aorsf
cat("Example 1: Basic parallel aorsf\n")
model1 <- aorsf_parallel(
  data = sample_data,
  formula = Surv(time, status) ~ .,
  config = aorsf_config,
  n_tree = 1000
)

cat(sprintf("Model 1 fitted with %d trees\n", model1$n_tree))

# Example 2: Custom parameters with parallel processing
cat("\nExample 2: Custom parameters with parallel processing\n")
custom_config <- configure_aorsf_parallel(
  n_thread = 4,
  target_utilization = 0.9,
  check_r_functions = FALSE,
  verbose = TRUE
)

model2 <- aorsf_parallel(
  data = sample_data,
  formula = Surv(time, status) ~ .,
  config = custom_config,
  n_tree = 1000,
  mtry = 10,
  min_obs_in_leaf_node = 10,
  oob_honest = TRUE
)

cat(sprintf("Model 2 fitted with %d trees and custom parameters\n", model2$n_tree))

# Example 3: R function limitation demonstration
cat("\nExample 3: R function limitation demonstration\n")
# Create a custom R function that would limit threading
custom_oob_error <- function(y_mat, s_vec) {
  # This is a dummy function that would limit aorsf to single thread
  mean(y_mat[, 1])
}

# Check for R function limitations
limitation_info <- check_aorsf_r_functions(custom_functions = list(custom_oob_error))
cat(sprintf("R function limitation detected: %s\n", limitation_info$has_r_functions))
cat(sprintf("Recommendation: %s\n", limitation_info$recommendation))

# Example 4: Prediction with parallel processing
cat("\nExample 4: Prediction with parallel processing\n")
# Create test data
test_data <- sample_data[1:100, ]
predictions <- predict_aorsf_parallel(
  object = model1,
  new_data = test_data,
  config = aorsf_config,
  times = 1.0
)

cat(sprintf("Generated predictions for %d test samples\n", nrow(test_data)))

# 6. Performance monitoring example
cat("\n6. Performance Monitoring:\n")
cat("Starting performance monitoring (will run for 30 seconds)...\n")

# Start monitoring (in a real scenario, this would run in background)
monitor_func <- monitor_aorsf_performance(
  config = aorsf_config,
  log_file = "logs/aorsf_demo_performance.log",
  interval = 5
)

# Run monitoring for a short time
start_time <- Sys.time()
while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < 30) {
  monitor_func()
  Sys.sleep(5)
}

cat("Performance monitoring completed. Check logs/aorsf_demo_performance.log for details.\n")

# 7. Integration with existing pipeline
cat("\n7. Integration with Existing Pipeline:\n")

# Show how to use with existing fit_orsf function
cat("Using updated fit_orsf function:\n")
model3 <- fit_orsf(
  trn = sample_data,
  vars = paste0("feature_", 1:20),
  use_parallel = TRUE,
  check_r_functions = TRUE
)

cat(sprintf("Pipeline-integrated model fitted with %d trees\n", model3$n_tree))

# 8. Environment variable management
cat("\n8. Environment Variable Management:\n")
cat("Current aorsf environment variables:\n")
aorsf_env_vars <- c(
  "OMP_NUM_THREADS",
  "MKL_NUM_THREADS", 
  "OPENBLAS_NUM_THREADS",
  "VECLIB_MAXIMUM_THREADS",
  "NUMEXPR_NUM_THREADS",
  "AORSF_NTHREAD"
)

for (var in aorsf_env_vars) {
  value <- Sys.getenv(var, unset = "Not set")
  cat(sprintf("  %s = %s\n", var, value))
}

# 9. Best practices summary
cat("\n9. Best Practices Summary:\n")
cat("✓ Use configure_aorsf_parallel() to set optimal thread count\n")
cat("✓ Set n_thread = 0 to use aorsf's auto-detection\n")
cat("✓ Check for R functions that limit threading\n")
cat("✓ Use aorsf_parallel() for optimal parallel processing\n")
cat("✓ Monitor performance with monitor_aorsf_performance()\n")
cat("✓ Set environment variables for consistent behavior\n")
cat("✓ Avoid custom R functions when maximum parallelism is needed\n")

cat("\n=== Demo Complete ===\n")
cat("aorsf parallel processing is now configured and ready for use!\n")
