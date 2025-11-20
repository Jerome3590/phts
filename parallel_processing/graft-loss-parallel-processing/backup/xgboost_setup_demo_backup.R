##' XGBoost Parallel Processing Setup and Demo
##' 
##' This script demonstrates how to use the XGBoost parallel processing configuration
##' for optimal performance in the graft loss pipeline.

# Load required packages
suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(survival)
  library(xgboost)
  library(xgboost.surv)
})

# Source the model utilities with XGBoost configuration
source(here("R", "utils", "model_utils.R"))

# Source the pipeline configuration
source(here("scripts", "config.R"))

cat("=== XGBoost Parallel Processing Setup Demo ===\n\n")

# 1. Display system information
cat("1. System Information:\n")
print_xgboost_system_info()

cat("\n2. Configuring XGBoost for Parallel Processing:\n")

# 2. Configure XGBoost with optimal settings
xgboost_config <- configure_xgboost_parallel(
  use_all_cores = TRUE,
  target_utilization = 0.8,
  tree_method = 'auto',
  verbose = TRUE
)

cat("\n3. Testing XGBoost Performance:\n")

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

# Prepare data for XGBoost
trn_x <- as.matrix(sample_data[, paste0("feature_", 1:n_features)])
trn_y <- sample_data$time
censored <- sample_data$status == 0
trn_y[censored] <- trn_y[censored] * (-1)

cat(sprintf("Created sample dataset: %d rows, %d features\n", nrow(sample_data), n_features))

# 4. Benchmark different thread configurations
cat("\n4. Benchmarking Thread Configurations:\n")

# Test with different thread counts
thread_configs <- c(1, 2, 4, 8, 0)  # 0 = all cores
benchmark_results <- benchmark_xgboost_threads(
  data = trn_x,
  label = trn_y,
  thread_configs = thread_configs,
  nrounds = 500,  # Smaller for faster demo
  n_runs = 2
)

print(benchmark_results)

# 5. Demonstrate optimal XGBoost usage
cat("\n5. Optimal XGBoost Usage Examples:\n")

# Example 1: Basic parallel XGBoost
cat("Example 1: Basic parallel XGBoost\n")
model1 <- xgboost_parallel(
  data = trn_x,
  label = trn_y,
  config = xgboost_config,
  nrounds = 1000,
  eta = 0.01,
  max_depth = 3
)

cat(sprintf("Model 1 fitted with %d rounds\n", model1$nrounds))

# Example 2: Feature selection with parallel processing
cat("\nExample 2: Feature selection with parallel processing\n")
selected_features <- select_xgb(
  trn = sample_data,
  n_predictors = 10,
  use_parallel = TRUE,
  n_rounds = 250
)

cat(sprintf("Selected %d features: %s\n", length(selected_features), 
            paste(head(selected_features, 5), collapse = ", ")))

# Example 3: GPU acceleration (if available)
cat("\nExample 3: GPU acceleration (if available)\n")
gpu_config <- configure_xgboost_parallel(
  use_all_cores = TRUE,
  tree_method = 'gpu_hist',
  gpu_id = 0,  # Use first GPU
  verbose = TRUE
)

# Try GPU model (will fall back to CPU if GPU not available)
tryCatch({
  model2 <- xgboost_parallel(
    data = trn_x,
    label = trn_y,
    config = gpu_config,
    nrounds = 1000
  )
  cat(sprintf("GPU model fitted with %d rounds\n", model2$nrounds))
}, error = function(e) {
  cat("GPU not available, falling back to CPU\n")
  model2 <- xgboost_parallel(
    data = trn_x,
    label = trn_y,
    config = xgboost_config,
    nrounds = 1000
  )
  cat(sprintf("CPU model fitted with %d rounds\n", model2$nrounds))
})

# Example 4: Prediction with parallel processing
cat("\nExample 4: Prediction with parallel processing\n")
# Create test data
test_data <- trn_x[1:100, ]
predictions <- predict_xgboost_parallel(
  object = model1,
  new_data = test_data,
  config = xgboost_config,
  eval_times = 1.0
)

cat(sprintf("Generated predictions for %d test samples\n", nrow(test_data)))

# 6. Performance monitoring example
cat("\n6. Performance Monitoring:\n")
cat("Starting performance monitoring (will run for 30 seconds)...\n")

# Start monitoring (in a real scenario, this would run in background)
monitor_func <- monitor_xgboost_performance(
  config = xgboost_config,
  log_file = "logs/xgboost_demo_performance.log",
  interval = 5
)

# Run monitoring for a short time
start_time <- Sys.time()
while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < 30) {
  monitor_func()
  Sys.sleep(5)
}

cat("Performance monitoring completed. Check logs/xgboost_demo_performance.log for details.\n")

# 7. Integration with existing pipeline
cat("\n7. Integration with Existing Pipeline:\n")

# Show how to use with existing fit_xgb function
cat("Using updated fit_xgb function:\n")
model3 <- fit_xgb(
  trn = sample_data,
  vars = paste0("feature_", 1:20),
  use_parallel = TRUE,
  tree_method = 'auto'
)

cat(sprintf("Pipeline-integrated model fitted with %d rounds\n", model3$nrounds))

# 8. Environment variable management
cat("\n8. Environment Variable Management:\n")
cat("Current XGBoost environment variables:\n")
xgboost_env_vars <- c(
  "OMP_NUM_THREADS",
  "MKL_NUM_THREADS", 
  "OPENBLAS_NUM_THREADS",
  "VECLIB_MAXIMUM_THREADS",
  "NUMEXPR_NUM_THREADS",
  "XGBOOST_NTHREAD",
  "CUDA_VISIBLE_DEVICES"
)

for (var in xgboost_env_vars) {
  value <- Sys.getenv(var, unset = "Not set")
  cat(sprintf("  %s = %s\n", var, value))
}

# 9. Best practices summary
cat("\n9. Best Practices Summary:\n")
cat("✓ Use configure_xgboost_parallel() to set optimal thread count\n")
cat("✓ Set nthread = 0 to use all available cores\n")
cat("✓ Use tree_method = 'gpu_hist' for GPU acceleration\n")
cat("✓ Set tree_method = 'hist' for CPU optimization\n")
cat("✓ Monitor performance with monitor_xgboost_performance()\n")
cat("✓ Use xgboost_parallel() for optimal parallel processing\n")
cat("✓ Set environment variables for consistent behavior\n")

cat("\n=== Demo Complete ===\n")
cat("XGBoost parallel processing is now configured and ready for use!\n")
