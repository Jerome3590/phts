##' Ranger Parallel Processing Setup and Demo
##' 
##' This script demonstrates how to use the ranger parallel processing configuration
##' for optimal performance in the graft loss pipeline.

# Load required packages
suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(survival)
  library(ranger)
})

# Source the model utilities with ranger configuration
source(here("R", "utils", "model_utils.R"))

# Source the pipeline configuration
source(here("scripts", "config.R"))

cat("=== Ranger Parallel Processing Setup Demo ===\n\n")

# 1. Display system information
cat("1. System Information:\n")
print_ranger_system_info()

cat("\n2. Configuring Ranger for Parallel Processing:\n")

# 2. Configure ranger with optimal settings
ranger_config <- configure_ranger_parallel(
  use_all_cores = TRUE,
  target_utilization = 0.8,
  memory_efficient = FALSE,
  verbose = TRUE
)

cat("\n3. Testing Ranger Performance:\n")

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

cat(sprintf("Created sample dataset: %d rows, %d features\n", nrow(sample_data), ncol(sample_data) - 2))

# 4. Benchmark different thread configurations
cat("\n4. Benchmarking Thread Configurations:\n")

# Test with different thread counts
thread_configs <- c(1, 2, 4, 8, 0)  # 0 = all cores
benchmark_results <- benchmark_ranger_threads(
  formula = Surv(time, status) ~ .,
  data = sample_data,
  thread_configs = thread_configs,
  num_trees = 500,  # Smaller for faster demo
  n_runs = 2
)

print(benchmark_results)

# 5. Demonstrate optimal ranger usage
cat("\n5. Optimal Ranger Usage Examples:\n")

# Example 1: Basic parallel ranger
cat("Example 1: Basic parallel ranger\n")
model1 <- ranger_parallel(
  formula = Surv(time, status) ~ .,
  data = sample_data,
  config = ranger_config,
  num.trees = 1000,
  min.node.size = 10,
  splitrule = 'C'
)

cat(sprintf("Model 1 fitted with %d trees\n", model1$num.trees))

# Example 2: Feature selection with parallel processing
cat("\nExample 2: Feature selection with parallel processing\n")
selected_features <- select_rsf(
  trn = sample_data,
  n_predictors = 10,
  use_parallel = TRUE,
  num.trees = 250
)

cat(sprintf("Selected %d features: %s\n", length(selected_features), 
            paste(head(selected_features, 5), collapse = ", ")))

# Example 3: Memory-efficient mode
cat("\nExample 3: Memory-efficient mode\n")
memory_config <- configure_ranger_parallel(
  use_all_cores = TRUE,
  memory_efficient = TRUE,
  verbose = TRUE
)

model2 <- ranger_parallel(
  formula = Surv(time, status) ~ .,
  data = sample_data,
  config = memory_config,
  num.trees = 1000
)

cat(sprintf("Memory-efficient model fitted with %d trees\n", model2$num.trees))

# Example 4: Prediction with parallel processing
cat("\nExample 4: Prediction with parallel processing\n")
# Create test data
test_data <- sample_data[1:100, ]
predictions <- predict_ranger_parallel(
  object = model1,
  newdata = test_data,
  config = ranger_config
)

cat(sprintf("Generated predictions for %d test samples\n", nrow(test_data)))

# 6. Performance monitoring example
cat("\n6. Performance Monitoring:\n")
cat("Starting performance monitoring (will run for 30 seconds)...\n")

# Start monitoring (in a real scenario, this would run in background)
monitor_func <- monitor_ranger_performance(
  config = ranger_config,
  log_file = "logs/ranger_demo_performance.log",
  interval = 5
)

# Run monitoring for a short time
start_time <- Sys.time()
while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < 30) {
  monitor_func()
  Sys.sleep(5)
}

cat("Performance monitoring completed. Check logs/ranger_demo_performance.log for details.\n")

# 7. Integration with existing pipeline
cat("\n7. Integration with Existing Pipeline:\n")

# Show how to use with existing fit_rsf function
cat("Using updated fit_rsf function:\n")
model3 <- fit_rsf(
  trn = sample_data,
  vars = paste0("feature_", 1:20),
  use_parallel = TRUE,
  memory_efficient = FALSE
)

cat(sprintf("Pipeline-integrated model fitted with %d trees\n", model3$num.trees))

# 8. Environment variable management
cat("\n8. Environment Variable Management:\n")
cat("Current ranger environment variables:\n")
ranger_env_vars <- c(
  "R_RANGER_NUM_THREADS",
  "OMP_NUM_THREADS", 
  "MKL_NUM_THREADS",
  "OPENBLAS_NUM_THREADS",
  "VECLIB_MAXIMUM_THREADS",
  "NUMEXPR_NUM_THREADS"
)

for (var in ranger_env_vars) {
  value <- Sys.getenv(var, unset = "Not set")
  cat(sprintf("  %s = %s\n", var, value))
}

# 9. Best practices summary
cat("\n9. Best Practices Summary:\n")
cat("✓ Use configure_ranger_parallel() to set optimal thread count\n")
cat("✓ Set num.threads = 0 to use all available cores\n")
cat("✓ Use memory_efficient = TRUE for large datasets\n")
cat("✓ Set regularization_factor = 0 to enable multithreading\n")
cat("✓ Monitor performance with monitor_ranger_performance()\n")
cat("✓ Use ranger_parallel() for optimal parallel processing\n")
cat("✓ Set environment variables for consistent behavior\n")

cat("\n=== Demo Complete ===\n")
cat("Ranger parallel processing is now configured and ready for use!\n")
