# XGBoost Parallel Processing Setup

This document provides comprehensive guidance on setting up and using XGBoost with optimal parallel processing in the graft loss pipeline.

## Overview

XGBoost (Extreme Gradient Boosting) is designed to run in parallel, automatically enabling parallel computation on a single machine. This setup provides:

- **Automatic parallelization** with OpenMP support
- **Manual thread control** via `nthread` parameter
- **GPU acceleration** support
- **Memory-efficient parallel processing**
- **Performance monitoring and optimization**
- **Integration with existing pipeline functions**

## Key Features

### 1. Automatic Parallelization

XGBoost includes efficient tree learning algorithms and can automatically perform **parallel computation on a single machine**:

- **Speed Optimization**: Can be more than 10 times faster than existing gradient boosting packages
- **OpenMP Support**: Parallelization is automatically enabled if OpenMP is present
- **Single Machine**: Optimized for parallel computation on a single machine

### 2. Thread Control

The number of threads can be controlled through the `nthread` parameter:

- **Default behavior**: If `nthread` is not set, **all available threads are used** in training
- **Manual control**: Specify `nthread` in training and prediction functions
- **Data preparation**: `xgb.DMatrix` creation also accepts `nthread` parameter
- **Cross-validation**: `xgb.cv` includes `nthread` in the `params` list

### 3. Tree Construction Methods

XGBoost supports multiple tree construction methods for different use cases:

- **`auto`**: Automatically selects the best method
- **`hist`**: Histogram-based algorithm (CPU optimized)
- **`gpu_hist`**: GPU-accelerated histogram algorithm
- **`approx`**: Approximate algorithm for very large datasets

## Usage

### Basic Setup

```r
# Load the configuration
source("scripts/config.R")

# Configure XGBoost for parallel processing
xgboost_config <- configure_xgboost_parallel(
  use_all_cores = TRUE,
  target_utilization = 0.8,
  tree_method = 'auto',
  verbose = TRUE
)

# Use XGBoost with optimal settings
model <- xgboost_parallel(
  data = training_matrix,
  label = training_labels,
  config = xgboost_config,
  nrounds = 1000
)
```

### Advanced Configuration

```r
# Custom thread count and GPU acceleration
xgboost_config <- configure_xgboost_parallel(
  nthread = 8,
  target_utilization = 0.9,
  tree_method = 'gpu_hist',
  gpu_id = 0,
  verbose = TRUE
)
```

### Feature Selection

```r
# Parallel feature selection
selected_features <- select_xgb(
  trn = training_data,
  n_predictors = 20,
  use_parallel = TRUE,
  n_rounds = 250
)
```

### Performance Monitoring

```r
# Monitor performance during training
monitor_func <- monitor_xgboost_performance(
  config = xgboost_config,
  log_file = "logs/xgboost_performance.log",
  interval = 10
)

# Start monitoring (run in background)
monitor_func()
```

### Benchmarking

```r
# Benchmark different thread configurations
benchmark_results <- benchmark_xgboost_threads(
  data = training_matrix,
  label = training_labels,
  thread_configs = c(1, 2, 4, 8, 0),
  nrounds = 500,
  n_runs = 3
)
```

## Environment Variables

### Default Settings (EC2 Safe Configuration)

The setup automatically configures these environment variables for optimal EC2 performance:

- `XGBOOST_NTHREAD`: XGBoost thread count (capped at 16 via `XGB_MAX_THREADS=16`)
- `OMP_NUM_THREADS=1`: Single-threaded BLAS (prevents oversubscription)
- `MKL_NUM_THREADS=1`: Single-threaded Intel MKL
- `OPENBLAS_NUM_THREADS=1`: Single-threaded OpenBLAS
- `VECLIB_MAXIMUM_THREADS=1`: Single-threaded Vector library
- `NUMEXPR_NUM_THREADS=1`: Single-threaded NumExpr
- `CUDA_VISIBLE_DEVICES`: GPU device selection (for GPU acceleration)

### Critical EC2 Configuration

- `XGB_MAX_THREADS=16`: Safe thread limit to prevent threading conflicts on high-core instances
- **BLAS Threading**: All BLAS libraries are set to single-threaded (`=1`) to prevent double parallelization

## Pipeline Integration

### `configure_xgboost_parallel()` Function

```r
configure_xgboost_parallel <- function(use_all_cores = TRUE, 
                                      nthread = NULL, 
                                      target_utilization = 0.8,
                                      tree_method = 'auto',
                                      check_r_functions = TRUE,
                                      verbose = FALSE) {
  
  available_cores <- future::availableCores()
  
  # EC2 Safety: Cap threads to prevent oversubscription
  if (use_all_cores) {
    max_safe_threads <- as.numeric(Sys.getenv("XGB_MAX_THREADS", unset = "16"))
    if (available_cores > max_safe_threads) {
      nthread <- max_safe_threads
      message(sprintf("EC2 Safety: Capping XGBoost threads to %d (detected %d cores)", 
                     max_safe_threads, available_cores))
    } else {
      nthread <- 0  # Use all cores if under the safety limit
    }
  }
  
  # CRITICAL: Set BLAS libraries to single-threaded
  xgboost_env_vars <- list(
    XGBOOST_NTHREAD = as.character(nthread),
    OMP_NUM_THREADS = "1",                    # Always 1
    MKL_NUM_THREADS = "1",                    # Always 1
    OPENBLAS_NUM_THREADS = "1",               # Always 1
    VECLIB_MAXIMUM_THREADS = "1",             # Always 1
    NUMEXPR_NUM_THREADS = "1"                 # Always 1
  )
  
  # Apply environment variables
  for (var_name in names(xgboost_env_vars)) {
    Sys.setenv(setNames(xgboost_env_vars[[var_name]], var_name))
  }
  
  config <- list(
    model_type = "XGBoost",
    nthread = nthread,
    tree_method = tree_method,
    use_all_cores = use_all_cores,
    target_utilization = target_utilization,
    available_cores = available_cores,
    env_vars = xgboost_env_vars
  )
  
  if (verbose) {
    cat("=== XGBoost Parallel Configuration ===\n")
    cat(sprintf("Available cores: %d\n", available_cores))
    cat(sprintf("XGBoost threads: %s\n", if(nthread == 0) "all cores" else nthread))
    cat(sprintf("Target utilization: %.1f%%\n", target_utilization * 100))
    cat(sprintf("Tree method: %s\n", tree_method))
    cat("Environment variables set:\n")
    for (var_name in names(xgboost_env_vars)) {
      cat(sprintf("  %s = %s\n", var_name, xgboost_env_vars[[var_name]]))
    }
    cat("=====================================\n")
  }
  
  return(config)
}
```

### Process Monitoring Integration

XGBoost models are integrated with the process monitoring system:

#### 1. MC-CV Processing (`R/utils/model_utils.R`)

```r
} else if (model_type == "XGB") {
  # Configure XGBoost parallel processing
  xgb_config <- configure_xgboost_parallel(
    use_all_cores = TRUE,
    target_utilization = 0.8,
    verbose = FALSE
  )
  
  # CRITICAL: Log process state before XGB fitting
  tryCatch({
    if (exists("log_process_info", mode = "function")) {
      log_process_info(model_log, "[PROCESS_PRE_XGB_PRIMARY]", include_children = TRUE, include_system = TRUE)
    }
  }, error = function(e) NULL)
  
  tryCatch({
    fitted_model <- fit_xgb(trn = trn_df, vars = vars_encoded, tst = NULL)
    # ... (model processing) ...
    
    # CRITICAL: Log process state after XGB fitting
    tryCatch({
      if (exists("log_process_info", mode = "function")) {
        log_process_info(model_log, "[PROCESS_POST_XGB_PRIMARY]", include_children = TRUE, include_system = TRUE)
      }
    }, error = function(e) NULL)
  }, error = function(e) {
    # Fallback processing with monitoring
    tryCatch({
      if (exists("log_process_info", mode = "function")) {
        log_process_info(model_log, "[PROCESS_PRE_XGB_FALLBACK1]", include_children = TRUE, include_system = TRUE)
      }
    }, error = function(e) NULL)
    
    # ... (fallback logic) ...
    
    tryCatch({
      if (exists("log_process_info", mode = "function")) {
        log_process_info(model_log, "[PROCESS_POST_XGB_FALLBACK1]", include_children = TRUE, include_system = TRUE)
      }
    }, error = function(e) NULL)
  })
}
```

#### 2. Log Output Examples

```
[PROCESS_PRE_XGB_PRIMARY] 2025-10-08 10:15:30 PID=12345 Cores=16/32 CPU=15.2% MEM=8.1% Threads=4 CurrentCore=7 Affinity=0-31 Load=2.45,1.89,1.23 SysMem=950.2GB/1024.0GB
  Child PID=12346 CPU=45.3% MEM=2.1% Threads=16 Core=12 Cmd=R
  Thread TID=12345 CPUTime=1250 Processor=7

[PROCESS_POST_XGB_PRIMARY] 2025-10-08 10:16:45 PID=12345 Cores=16/32 CPU=12.1% MEM=7.8% Threads=4 CurrentCore=7 Affinity=0-31 Load=1.85,1.65,1.15 SysMem=945.8GB/1024.0GB
```

### Updated Functions

The following functions have been updated to use optimal parallel processing:

- `fit_xgb()`: XGBoost model fitting with EC2-safe threading
- `select_xgb()`: Feature selection with process monitoring
- `xgboost_parallel()`: General XGBoost with parallel config
- `predict_xgboost_parallel()`: Parallel prediction
- `configure_xgboost_parallel()`: EC2-optimized configuration

### Environment Variable Overrides

The pipeline respects these environment variables:

- `MC_WORKER_THREADS`: Override thread count for workers
- `XGB_NROUNDS`: Number of boosting rounds
- `XGB_MAX_THREADS=16`: Cap XGBoost threads (EC2 safety)
- `XGBOOST_NTHREAD`: Direct XGBoost thread control (auto-capped by XGB_MAX_THREADS)

## Best Practices

### 1. Thread Configuration (EC2 Optimized)

- **EC2 Safe Threading**: Threads are capped at 16 (configurable via `XGB_MAX_THREADS`) on high-core instances
- **Single-threaded BLAS**: All BLAS libraries use 1 thread to prevent oversubscription
- **Target utilization**: Use 80-90% of available cores within safety limits
- **Memory considerations**: Monitor memory usage with large datasets

### 2. Tree Construction Methods

- **`auto`**: Best for most use cases (automatically selects optimal method)
- **`hist`**: Best for CPU-only environments
- **`gpu_hist`**: Best for GPU-accelerated training
- **`approx`**: Best for very large datasets where memory is limited

### 3. GPU Acceleration

- **CUDA support**: Requires CUDA-enabled XGBoost installation
- **GPU memory**: Ensure sufficient GPU memory for dataset size
- **Fallback**: Always provide CPU fallback for production systems

### 4. Monitoring

- **Performance logs**: Use `monitor_xgboost_performance()` for long-running tasks
- **Benchmarking**: Test different configurations for your specific use case
- **System info**: Use `get_xgboost_system_info()` to check configuration

## Troubleshooting

### Common Issues

1. **Thread detection fails**: Falls back to 4 cores
2. **Memory issues**: Reduce `nrounds` or use `approx` tree method
3. **GPU not available**: Falls back to CPU automatically
4. **Environment variables**: Check with `get_xgboost_system_info()`

### EC2-Specific Threading Issues

#### **Threading Oversubscription (Before Fixes)**
```
XGBoost trying to use ALL 32 cores + BLAS using additional threads = 64+ threads
Result: Massive performance degradation and potential hanging
```

#### **Threading Conflicts Detection**
```bash
# Check for threading conflicts in logs
grep "THREADING_CONFLICT" logs/models/original/full/XGB_*.log

# Check if XGB completed successfully
grep "PROCESS_POST_XGB" logs/models/original/full/XGB_*.log
```

#### **Expected EC2 Configuration Output**
```
EC2 Safety: Capping XGBoost threads to 16 (detected 32 cores)
=== XGBoost Parallel Configuration ===
Available cores: 32
XGBoost threads: 16
Target utilization: 80.0%
Environment variables set:
  XGBOOST_NTHREAD = 16
  OMP_NUM_THREADS = 1
  MKL_NUM_THREADS = 1
  OPENBLAS_NUM_THREADS = 1
  VECLIB_MAXIMUM_THREADS = 1
  NUMEXPR_NUM_THREADS = 1
=====================================
```

#### **Verification Commands**
```bash
# Verify thread capping is working
grep "EC2 Safety: Capping XGBoost threads" logs/orch_bg_original_study.log

# Check BLAS threading is single-threaded
grep "OMP_NUM_THREADS = 1" logs/orch_bg_original_study.log

# Monitor XGBoost process utilization
grep "PROCESS_.*_XGB" logs/models/original/full/XGB_*.log
```

### Debugging

```r
# Check system information
print_xgboost_system_info()

# Verify configuration
xgboost_config <- configure_xgboost_parallel(verbose = TRUE)

# Test with small dataset
test_model <- xgboost_parallel(
  data = small_matrix,
  label = small_labels,
  config = xgboost_config,
  nrounds = 100
)
```

## Performance Tips

### 1. Optimal Settings (EC2 Optimized)

- **Threads**: Capped at 16 threads on EC2 (via `XGB_MAX_THREADS=16`)
- **BLAS Threading**: Single-threaded BLAS libraries (`OMP_NUM_THREADS=1`)
- **Tree method**: Use `auto` for automatic optimization
- **Rounds**: 500-2000 for most applications
- **Learning rate**: 0.01-0.1 depending on dataset size

### 2. Large Datasets

- **Chunking**: Process data in chunks if memory limited
- **Approximate method**: Use `tree_method = 'approx'` for very large datasets
- **Monitoring**: Use performance monitoring for long runs

### 3. Parallel Pipeline

- **Worker threads**: Set `MC_WORKER_THREADS` appropriately
- **Load balancing**: Distribute work evenly across workers
- **Resource monitoring**: Monitor CPU, memory, and GPU usage

## Examples

### Complete Workflow

```r
# 1. Setup
source("scripts/config.R")
xgboost_config <- configure_xgboost_parallel(use_all_cores = TRUE)

# 2. Feature selection
selected_vars <- select_xgb(
  trn = training_data,
  n_predictors = 20,
  use_parallel = TRUE
)

# 3. Model training
model <- fit_xgb(
  trn = training_data,
  vars = selected_vars,
  use_parallel = TRUE
)

# 4. Prediction
predictions <- predict_xgboost_parallel(
  object = model,
  new_data = test_matrix,
  config = xgboost_config,
  eval_times = 1.0
)
```

### Performance Benchmarking

```r
# Benchmark different configurations
benchmark_results <- benchmark_xgboost_threads(
  data = training_matrix,
  label = training_labels,
  thread_configs = c(1, 2, 4, 8, 16, 0),
  nrounds = 1000,
  n_runs = 5
)

# Find optimal configuration
optimal_threads <- benchmark_results$threads[which.max(benchmark_results$speedup)]
cat(sprintf("Optimal thread count: %d\n", optimal_threads))
```

### GPU Acceleration

```r
# Check GPU availability
gpu_info <- check_xgboost_gpu()
if (gpu_info$cuda_available) {
  # Use GPU acceleration
  gpu_config <- configure_xgboost_parallel(
    tree_method = 'gpu_hist',
    gpu_id = 0
  )
  
  model <- xgboost_parallel(
    data = training_matrix,
    label = training_labels,
    config = gpu_config
  )
} else {
  # Fall back to CPU
  cpu_config <- configure_xgboost_parallel(tree_method = 'hist')
  model <- xgboost_parallel(
    data = training_matrix,
    label = training_labels,
    config = cpu_config
  )
}
```

## Integration Checklist

### ✅ **Threading Configuration**
- [ ] `configure_xgboost_parallel()` called in main setup
- [ ] `XGB_MAX_THREADS=16` environment variable set
- [ ] BLAS libraries set to single-threaded (`OMP_NUM_THREADS=1`)
- [ ] Thread capping message appears in logs
- [ ] No threading conflicts detected

### ✅ **Process Monitoring**
- [ ] `[PROCESS_PRE_XGB_PRIMARY]` logged before fitting
- [ ] `[PROCESS_POST_XGB_PRIMARY]` logged after successful fitting
- [ ] `[PROCESS_PRE_XGB_FALLBACK1]` logged for fallback attempts
- [ ] `[PROCESS_POST_XGB_FALLBACK1]` logged after fallback completion
- [ ] Process monitoring wrapped in `tryCatch()` to prevent failures

### ✅ **Performance Verification**
- [ ] XGBoost uses exactly 16 threads on 32-core EC2
- [ ] No BLAS oversubscription (all BLAS threads = 1)
- [ ] Models complete without hanging
- [ ] CPU utilization stays within reasonable bounds
- [ ] Memory usage is stable

### ✅ **Error Handling**
- [ ] Fallback mechanisms work for encoding failures
- [ ] Process monitoring errors don't break model fitting
- [ ] Threading conflicts are detected and logged
- [ ] Timeout protection (if implemented)

## Files

- `R/xgboost_parallel_config.R`: Standalone XGBoost configuration module with EC2 fixes
- `R/utils/model_utils.R`: Updated model utilities with XGBoost functions and process monitoring
- `R/fit_xgb.R`: Updated XGBoost fitting function with threading safety
- `R/select_xgb.R`: Updated feature selection function
- `scripts/config.R`: Pipeline configuration with XGBoost defaults
- `scripts/04_fit_model.R`: Main script with XGBoost configuration integration
- `scripts/xgboost_setup_demo.R`: Comprehensive demo script

## Dependencies

- `xgboost`: XGBoost implementation
- `xgboost.surv`: Survival analysis extension
- `future`: Parallel processing
- `parallel`: Core parallel functionality
- `survival`: Survival analysis
- `dplyr`: Data manipulation

## References

- [XGBoost Documentation](https://xgboost.readthedocs.io/)
- [XGBoost GitHub Repository](https://github.com/dmlc/xgboost)
- [XGBoost R Package](https://cran.r-project.org/package=xgboost)
- [Parallel Processing in R](https://cran.r-project.org/web/views/HighPerformanceComputing.html)
