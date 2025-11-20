# Ranger Parallel Processing Setup

This document provides comprehensive guidance on setting up and using ranger with optimal parallel processing in the graft loss pipeline.

## Overview

The ranger package is explicitly designed for parallel processing and uses multiple threads for both training and prediction. This setup provides:

- **Automatic thread detection and configuration**
- **Environment variable management**
- **Memory-efficient parallel processing**
- **Performance monitoring and optimization**
- **Integration with existing pipeline functions**

## Key Features

### 1. Parallel Processing Configuration

Ranger uses C++ implementation with standard thread libraries for parallel processing across all platforms. Key benefits:

- **Speed Optimization**: Known as a fast implementation of random forests
- **Multithreading**: Utilizes parallelization for growing trees
- **High-Dimensional Data**: Particularly suited for large datasets
- **Memory Efficient**: Even standard mode is very memory efficient

### 2. Thread Control

The number of threads can be controlled through multiple methods (in order of precedence):

1. `num.threads` parameter in `ranger()` or `predict()` function calls
2. Environment variable `R_RANGER_NUM_THREADS`
3. R options: `options(ranger.num.threads = N)`
4. R options: `options(Ncpus = N)`

### 3. Default Settings

- **Default threads**: 2 threads
- **EC2 Safe threads**: Capped at 16 threads (via `RSF_MAX_THREADS=16`)
- **All cores**: Set `num.threads = 0` to use all available cores (capped on EC2)
- **BLAS threading**: Always single-threaded (`OMP_NUM_THREADS = 1`)
- **Environment variables**: Automatically set for optimal performance and EC2 safety

## Usage

### Basic Setup

```r
# Load the configuration
source("scripts/config.R")

# Configure ranger for parallel processing
ranger_config <- configure_ranger_parallel(
  use_all_cores = TRUE,
  target_utilization = 0.8,
  memory_efficient = FALSE,
  verbose = TRUE
)

# Use ranger with optimal settings
model <- ranger_parallel(
  formula = Surv(time, status) ~ .,
  data = training_data,
  config = ranger_config,
  num.trees = 1000
)
```

### Advanced Configuration

```r
# Custom thread count
ranger_config <- configure_ranger_parallel(
  num_threads = 8,
  target_utilization = 0.9,
  memory_efficient = TRUE,
  regularization_factor = 0.1,  # Disables multithreading
  verbose = TRUE
)
```

### Feature Selection

```r
# Parallel feature selection
selected_features <- select_rsf(
  trn = training_data,
  n_predictors = 20,
  use_parallel = TRUE,
  num.trees = 250
)
```

### Performance Monitoring

```r
# Monitor performance during training
monitor_func <- monitor_ranger_performance(
  config = ranger_config,
  log_file = "logs/ranger_performance.log",
  interval = 10
)

# Start monitoring (run in background)
monitor_func()
```

### Benchmarking

```r
# Benchmark different thread configurations
benchmark_results <- benchmark_ranger_threads(
  formula = Surv(time, status) ~ .,
  data = training_data,
  thread_configs = c(1, 2, 4, 8, 0),
  num_trees = 1000,
  n_runs = 3
)
```

## Environment Variables

The setup automatically configures these environment variables:

- `R_RANGER_NUM_THREADS`: Number of threads for ranger (capped at 16 on EC2)
- `OMP_NUM_THREADS`: OpenMP threads (always 1 to prevent oversubscription)
- `MKL_NUM_THREADS`: Intel MKL threads (always 1 to prevent oversubscription)
- `OPENBLAS_NUM_THREADS`: OpenBLAS threads (always 1 to prevent oversubscription)
- `VECLIB_MAXIMUM_THREADS`: Vector library threads (always 1 to prevent oversubscription)
- `NUMEXPR_NUM_THREADS`: NumExpr threads (always 1 to prevent oversubscription)

**Critical EC2 Configuration:**
- `RSF_MAX_THREADS=16`: Maximum threads for ranger (prevents threading conflicts)
- `RSF_TIMEOUT_MINUTES=30`: Timeout protection with fallback to single-thread

## Pipeline Integration

### Updated Functions

The following functions have been updated to use optimal parallel processing:

- `fit_rsf()`: Random Survival Forest fitting
- `select_rsf()`: Feature selection
- `ranger_parallel()`: General ranger with parallel config
- `predict_ranger_parallel()`: Parallel prediction

### Environment Variable Overrides

The pipeline respects these environment variables:

- `MC_WORKER_THREADS`: Override thread count for workers
- `RSF_NTREES`: Number of trees for RSF models
- `R_RANGER_NUM_THREADS`: Direct ranger thread control

## Best Practices

### 1. Thread Configuration

- **Use all cores**: Set `num.threads = 0` for maximum performance
- **Target utilization**: Use 80-90% of available cores
- **Memory considerations**: Enable `memory_efficient = TRUE` for large datasets

### 2. Regularization

- **Disables multithreading**: When `regularization_factor > 0`
- **Single-threaded**: Automatically falls back to 1 thread
- **Performance impact**: Consider trade-offs between regularization and speed

### 3. Memory Management

- **Standard mode**: Fast but uses more memory
- **Memory efficient**: Slower but uses less memory
- **Large datasets**: Use `save.memory = TRUE` for very large datasets

### 4. Monitoring

- **Performance logs**: Use `monitor_ranger_performance()` for long-running tasks
- **Benchmarking**: Test different configurations for your specific use case
- **System info**: Use `get_ranger_system_info()` to check configuration

## EC2 High-Core Instance Issues (CRITICAL)

### Threading Conflict Problem

**Root Cause**: On EC2 instances with many cores (e.g., 32 cores), ranger can hang when trying to use all available cores while the pipeline is already using cores for parallel processing.

**The Issue**: 
- Pipeline uses `furrr::future_map` with multiple workers (e.g., 4 workers using ~25 cores)
- RSF tasks call `ranger()` with `num.threads = 0` (use all cores)
- Ranger tries to grab all 32 cores, but many are already in use by other workers
- This creates a **threading conflict** causing ranger to hang indefinitely

### EC2-Specific Fixes Implemented

#### 1. Thread Safety Cap
```r
# In configure_ranger_parallel()
max_safe_threads <- as.numeric(Sys.getenv("RSF_MAX_THREADS", unset = "16"))
if (available_cores > max_safe_threads) {
  num_threads <- max_safe_threads
  message(sprintf("EC2 Safety: Capping ranger threads to %d (detected %d cores)", 
                 max_safe_threads, available_cores))
}
```

#### 2. Timeout Protection with Fallback
```r
# In ranger_parallel()
timeout_minutes <- as.numeric(Sys.getenv("RSF_TIMEOUT_MINUTES", unset = "30"))

tryCatch({
  result <- R.utils::withTimeout({
    do.call(ranger::ranger, params)
  }, timeout = timeout_minutes * 60, onTimeout = "error")
}, error = function(e) {
  if (grepl("timeout|time.*out", e$message, ignore.case = TRUE)) {
    # Retry with conservative settings
    params$num.threads <- 1
    if (params$num.trees > 500) params$num.trees <- 500
    do.call(ranger::ranger, params)
  }
})
```

#### 3. Task Isolation
```r
# In model_utils.R
chunk_size <- 1  # Each task runs independently
# Prevents hanging RSF from blocking CPH tasks
```

### Environment Variables for EC2

**Critical EC2 Controls:**
- `RSF_MAX_THREADS=16` - Safe thread limit (default: 16, prevents conflicts)
- `RSF_TIMEOUT_MINUTES=30` - Ranger timeout with fallback (default: 30 min)
- `TASK_TIMEOUT_MINUTES=45` - Individual task timeout (default: 45 min)

**Threading Strategy:**
- **Pipeline level**: Uses ~80% of cores for parallel workers (e.g., 4 workers × ~6 cores each = 24 cores)
- **Ranger level**: Uses remaining cores (capped at 16) per task to avoid conflicts
- **Fallback**: Single-threaded mode if timeout occurs

### EC2 Threading Architecture

```
EC2 Instance: 32 cores total
├── Pipeline Workers (4 workers): ~24 cores
│   ├── Worker 1: ~6 cores → RSF task (uses max 16 ranger threads)
│   ├── Worker 2: ~6 cores → XGB task  
│   ├── Worker 3: ~6 cores → CPH task
│   └── Worker 4: ~6 cores → ORSF task
└── System/OS: ~8 cores reserved
```

**Key Insight**: The conflict occurs when ranger tries to use `num.threads = 0` (all 32 cores) while pipeline workers are already using most cores. The fix caps ranger at 16 threads maximum, leaving headroom for the parallel workers.

## Troubleshooting

### Common Issues

1. **Thread detection fails**: Falls back to 4 cores
2. **Memory issues**: Enable `memory_efficient = TRUE`
3. **Regularization conflicts**: Automatically disables multithreading
4. **Environment variables**: Check with `get_ranger_system_info()`
5. **EC2 Threading conflicts**: Ranger hangs trying to use cores already in use by pipeline workers
6. **Task blocking**: Hanging ranger tasks prevent other models from running

### EC2-Specific Debugging

```r
# Check for threading conflicts
cat("Available cores:", parallel::detectCores(), "\n")
cat("Pipeline workers:", Sys.getenv("MC_SPLIT_WORKERS", "4"), "\n")
cat("RSF max threads:", Sys.getenv("RSF_MAX_THREADS", "16"), "\n")

# Monitor for hanging tasks
system("ps aux | grep R")  # Check for stuck R processes
system("top -p $(pgrep R)")  # Monitor CPU usage

# Test ranger threading
ranger_config <- configure_ranger_parallel(verbose = TRUE)
# Should show: "EC2 Safety: Capping ranger threads to 16"
```

### Signs of Threading Conflicts

**Symptoms:**
- RSF tasks start but never complete (hang indefinitely)
- CPH tasks never start (blocked by hanging RSF)
- High CPU usage but no progress in logs
- Log timestamps show tasks started but no completion

**Log Patterns to Watch:**
```
[DEBUG] XGB Fallback 1: fit_xgb returned: xgb.Booster  ✓ (XGB completes)
[LOG OPEN] cohort=original label=full model=RSF split=1  ← (RSF starts)
(no completion log for RSF)                             ← (RSF hangs)
(no CPH logs at all)                                    ← (CPH blocked)
```

### Debugging

```r
# Check system information
print_ranger_system_info()

# Verify configuration
ranger_config <- configure_ranger_parallel(verbose = TRUE)

# Test with small dataset
test_model <- ranger_parallel(
  formula = Surv(time, status) ~ .,
  data = small_data,
  config = ranger_config,
  num.trees = 100
)
```

## Performance Tips

### 1. Optimal Settings

- **Threads**: Use 80% of available cores
- **Trees**: 1000-2000 for most applications
- **Memory**: Use standard mode unless memory constrained
- **Importance**: Set to 'none' for faster training

### 2. Large Datasets

- **Chunking**: Process data in chunks if memory limited
- **Memory efficient**: Enable for datasets > 1GB
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
ranger_config <- configure_ranger_parallel(use_all_cores = TRUE)

# 2. Feature selection
selected_vars <- select_rsf(
  trn = training_data,
  n_predictors = 20,
  use_parallel = TRUE
)

# 3. Model training
model <- fit_rsf(
  trn = training_data,
  vars = selected_vars,
  use_parallel = TRUE
)

# 4. Prediction
predictions <- predict_ranger_parallel(
  object = model,
  newdata = test_data,
  config = ranger_config
)
```

### Performance Benchmarking

```r
# Benchmark different configurations
benchmark_results <- benchmark_ranger_threads(
  formula = Surv(time, status) ~ .,
  data = training_data,
  thread_configs = c(1, 2, 4, 8, 16, 0),
  num_trees = 1000,
  n_runs = 5
)

# Find optimal configuration
optimal_threads <- benchmark_results$threads[which.max(benchmark_results$speedup)]
cat(sprintf("Optimal thread count: %d\n", optimal_threads))
```

## Files

- `R/ranger_parallel_config.R`: Standalone ranger configuration module
- `R/utils/model_utils.R`: Updated model utilities with ranger functions
- `R/fit_rsf.R`: Updated RSF fitting function
- `R/select_rsf.R`: Updated feature selection function
- `scripts/config.R`: Pipeline configuration with ranger defaults
- `scripts/ranger_setup_demo.R`: Comprehensive demo script

## Dependencies

- `ranger`: Random Forest implementation
- `future`: Parallel processing
- `parallel`: Core parallel functionality
- `survival`: Survival analysis
- `dplyr`: Data manipulation

## References

- [Ranger Package Documentation](https://cran.r-project.org/package=ranger)
- [Ranger GitHub Repository](https://github.com/imbs-hl/ranger)
- [Parallel Processing in R](https://cran.r-project.org/web/views/HighPerformanceComputing.html)
