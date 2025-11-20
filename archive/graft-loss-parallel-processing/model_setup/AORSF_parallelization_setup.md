# ORSF (Oblique Random Survival Forest) Parallel Processing Setup

This document provides comprehensive guidance on setting up and using ORSF (Oblique Random Survival Forest) with optimal parallel processing in the graft loss pipeline. ORSF uses the `aorsf` package for accelerated oblique random forests.

## Overview

The ORSF model can be used in parallel processing through the use of multithreading. This setup provides:

- **Thread capping for EC2 safety** (prevents oversubscription)
- **BLAS/OpenMP conflict resolution** (single-threaded BLAS)
- **Environment variable management**
- **Process and core utilization monitoring**
- **Integration with existing pipeline functions**

## Key Features

### 1. Parallelization in Model Fitting

The `orsf()` function accepts an integer input for `n_thread`:

- **Functionality**: The `n_thread` argument specifies the number of threads to use while **growing trees**, **computing predictions**, and **computing importance**
- **Default Behavior**: The default value for `n_thread` is `0`, which allows a suitable number of threads to be used based on availability

### 2. Parallelization in Post-Fit Computations

The ability to use multiple threads extends to interpretation and prediction functions:

- **Individual Conditional Expectations (ICE)**: Functions like `orsf_ice_oob`, `orsf_ice_inb`, and `orsf_ice_new` accept the `n_thread` argument
- **Partial Dependence (PD)**: Functions like `orsf_pd_oob`, `orsf_pd_inb`, and `orsf_pd_new` also accept `n_thread`
- **Variable Importance (VI)**: The `orsf_vi` family of functions accepts `n_thread`
- **Variable Interactions**: The `orsf_vint` function accepts `n_thread`

### 3. Critical Limitation on Thread Usage

**Important**: If a user-supplied **R function** is set to be called from the package's C++ core, the `n_thread` parameter **will automatically be set to 1**:

- **Reason**: Attempting to run R functions in multiple threads simultaneously can cause the R session to crash
- **Detection**: The setup includes functions to detect and warn about R function limitations
- **Recommendation**: Avoid custom R functions when maximum parallelism is needed

## Usage

### Basic Setup

```r
# Load the configuration
source("scripts/config.R")

# Configure aorsf for parallel processing
aorsf_config <- configure_aorsf_parallel(
  use_all_cores = TRUE,
  target_utilization = 0.8,
  check_r_functions = TRUE,
  verbose = TRUE
)

# Use aorsf with optimal settings
model <- aorsf_parallel(
  data = training_data,
  formula = Surv(time, status) ~ .,
  config = aorsf_config,
  n_tree = 1000
)
```

### Advanced Configuration

```r
# Custom thread count with R function checking
aorsf_config <- configure_aorsf_parallel(
  n_thread = 8,
  target_utilization = 0.9,
  check_r_functions = TRUE,
  verbose = TRUE
)
```

### R Function Limitation Handling

```r
# Check for R functions that limit threading
limitation_info <- check_aorsf_r_functions(custom_functions = list(my_custom_function))
if (limitation_info$has_r_functions) {
  cat("Warning: R functions detected - threading limited to 1 thread\n")
}
```

### Performance Monitoring

```r
# Monitor performance during training
monitor_func <- monitor_aorsf_performance(
  config = aorsf_config,
  log_file = "logs/aorsf_performance.log",
  interval = 10
)

# Start monitoring (run in background)
monitor_func()
```

### Benchmarking

```r
# Benchmark different thread configurations
benchmark_results <- benchmark_aorsf_threads(
  data = training_data,
  formula = Surv(time, status) ~ .,
  thread_configs = c(1, 2, 4, 8, 0),
  n_tree = 1000,
  n_runs = 3
)
```

## Environment Variables

The setup automatically configures these environment variables:

- `OMP_NUM_THREADS`: OpenMP threads
- `MKL_NUM_THREADS`: Intel MKL threads
- `OPENBLAS_NUM_THREADS`: OpenBLAS threads
- `VECLIB_MAXIMUM_THREADS`: Vector library threads
- `NUMEXPR_NUM_THREADS`: NumExpr threads
- `AORSF_NTHREAD`: aorsf-specific thread control

## Pipeline Integration

### Updated Functions

The following functions have been updated to use optimal parallel processing:

- `fit_orsf()`: Oblique Random Survival Forest fitting
- `aorsf_parallel()`: General aorsf with parallel config
- `predict_aorsf_parallel()`: Parallel prediction

### Environment Variable Overrides

The pipeline respects these environment variables:

- `MC_WORKER_THREADS`: Override thread count for workers
- `ORSF_NTREES`: Number of trees for ORSF models
- `AORSF_NTHREAD`: Direct aorsf thread control

## Best Practices

### 1. Thread Configuration

- **Use auto-detection**: Set `n_thread = 0` for optimal performance
- **Target utilization**: Use 80-90% of available cores
- **R function awareness**: Check for R functions that limit threading

### 2. R Function Limitations

- **Avoid custom R functions**: When maximum parallelism is needed
- **Single-threaded fallback**: Use `n_thread = 1` when R functions are required
- **Detection**: Use `check_aorsf_r_functions()` to identify limitations

### 3. Performance Optimization

- **Tree count**: 1000-2000 for most applications
- **Monitoring**: Use performance monitoring for long-running tasks
- **Benchmarking**: Test different configurations for your specific use case

### 4. Memory Management

- **Large datasets**: Monitor memory usage with large datasets
- **Tree complexity**: Balance tree count with available memory
- **Parallel overhead**: Consider overhead vs. benefit for small datasets

## Troubleshooting

### Common Issues

1. **Thread detection fails**: Falls back to 4 cores
2. **R function crashes**: Automatically limits to single thread
3. **Memory issues**: Reduce tree count or use fewer threads
4. **Environment variables**: Check with `get_aorsf_system_info()`

### Debugging

```r
# Check system information
print_aorsf_system_info()

# Verify configuration
aorsf_config <- configure_aorsf_parallel(verbose = TRUE)

# Test with small dataset
test_model <- aorsf_parallel(
  data = small_data,
  formula = Surv(time, status) ~ .,
  config = aorsf_config,
  n_tree = 100
)
```

## Performance Tips

### 1. Optimal Settings

- **Threads**: Use `n_thread = 0` for auto-detection
- **Trees**: 1000-2000 for most applications
- **R functions**: Avoid when maximum parallelism is needed
- **Monitoring**: Use performance monitoring for long runs

### 2. Large Datasets

- **Chunking**: Process data in chunks if memory limited
- **Tree count**: Reduce tree count for very large datasets
- **Monitoring**: Use performance monitoring for long runs

### 3. Parallel Pipeline

- **Worker threads**: Set `MC_WORKER_THREADS` appropriately
- **Load balancing**: Distribute work evenly across workers
- **Resource monitoring**: Monitor CPU and memory usage

## Examples

### Complete Workflow

```r
# 1. Setup
source("scripts/config.R")
aorsf_config <- configure_aorsf_parallel(use_all_cores = TRUE)

# 2. Model training
model <- fit_orsf(
  trn = training_data,
  vars = selected_vars,
  use_parallel = TRUE
)

# 3. Prediction
predictions <- predict_aorsf_parallel(
  object = model,
  new_data = test_data,
  config = aorsf_config,
  times = 1.0
)
```

### Performance Benchmarking

```r
# Benchmark different configurations
benchmark_results <- benchmark_aorsf_threads(
  data = training_data,
  formula = Surv(time, status) ~ .,
  thread_configs = c(1, 2, 4, 8, 16, 0),
  n_tree = 1000,
  n_runs = 5
)

# Find optimal configuration
optimal_threads <- benchmark_results$threads[which.max(benchmark_results$speedup)]
cat(sprintf("Optimal thread count: %d\n", optimal_threads))
```

### R Function Limitation Handling

```r
# Check for R functions that limit threading
custom_functions <- list(
  custom_oob_error = function(y_mat, s_vec) mean(y_mat[, 1]),
  custom_split_function = function(x, y) x > median(x)
)

limitation_info <- check_aorsf_r_functions(custom_functions)
if (limitation_info$has_r_functions) {
  # Use single-threaded configuration
  aorsf_config <- configure_aorsf_parallel(n_thread = 1)
} else {
  # Use parallel configuration
  aorsf_config <- configure_aorsf_parallel(use_all_cores = TRUE)
}
```

## Files

- `R/aorsf_parallel_config.R`: Standalone aorsf configuration module
- `R/utils/model_utils.R`: Updated model utilities with aorsf functions
- `R/fit_orsf.R`: Updated ORSF fitting function
- `scripts/config.R`: Pipeline configuration with aorsf defaults
- `scripts/aorsf_setup_demo.R`: Comprehensive demo script

## Dependencies

- `aorsf`: Accelerated Oblique Random Forests
- `future`: Parallel processing
- `parallel`: Core parallel functionality
- `survival`: Survival analysis
- `dplyr`: Data manipulation

## References

- [aorsf Package Documentation](https://cran.r-project.org/package=aorsf)
- [aorsf GitHub Repository](https://github.com/bcjaeger/aorsf)
- [Parallel Processing in R](https://cran.r-project.org/web/views/HighPerformanceComputing.html)
