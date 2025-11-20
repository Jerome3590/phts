# ORSF (Oblique Random Survival Forest) Parallel Processing Setup

This document provides comprehensive guidance on setting up and using ORSF (aorsf package) with optimal parallel processing in the graft loss pipeline.

## Overview

The ORSF package (aorsf) is designed for parallel processing and uses multiple threads for both training and prediction. This setup provides:

- **Automatic thread detection and configuration**
- **Environment variable management**
- **Memory-efficient parallel processing**
- **Performance monitoring and optimization**
- **Integration with existing pipeline functions**
- **EC2 threading conflict prevention**

## Key Features

### 1. Parallel Processing Configuration

ORSF uses C++ implementation with OpenMP for parallel processing across all platforms. Key benefits:

- **Speed Optimization**: Efficient implementation of oblique random survival forests
- **Multithreading**: Utilizes parallelization for growing trees
- **High-Dimensional Data**: Particularly suited for large datasets
- **Memory Efficient**: Optimized memory usage during training

### 2. Thread Control

The number of threads can be controlled through multiple methods (in order of precedence):

1. `n_thread` parameter in `aorsf()` function calls
2. Environment variable `AORSF_NTHREAD`
3. R options: `options(aorsf.n_thread = N)`

### 3. EC2 Safety Settings

- **Default threads**: Auto-detect (0)
- **EC2 Safe threads**: Capped at 16 threads (via `ORSF_MAX_THREADS=16`)
- **All cores**: Set `n_thread = 0` to use all available cores (capped on EC2)
- **BLAS threading**: Always single-threaded (`OMP_NUM_THREADS = 1`)
- **Environment variables**: Automatically set for optimal performance and EC2 safety

## Usage

### Basic Setup

```r
# Load the configuration
source("scripts/config.R")

# Configure ORSF for parallel processing
orsf_config <- configure_aorsf_parallel(
  use_all_cores = TRUE,
  target_utilization = 0.8,
  check_r_functions = TRUE,
  verbose = TRUE
)

# Use ORSF with optimal settings
model <- fit_orsf(
  trn = training_data,
  vars = selected_vars,
  use_parallel = TRUE,
  check_r_functions = TRUE
)
```

### Advanced Configuration

```r
# Custom thread count (EC2 safe)
orsf_config <- configure_aorsf_parallel(
  n_thread = 16,  # Will be capped at 16 on EC2
  target_utilization = 0.9,
  check_r_functions = TRUE,
  verbose = TRUE
)
```

### R Function Compatibility

```r
# When using R functions in ORSF (limits threading)
orsf_config <- configure_aorsf_parallel(
  use_all_cores = TRUE,
  check_r_functions = TRUE,  # Detects R function usage
  verbose = TRUE
)
# Will automatically limit to single thread if R functions detected
```

## Environment Variables

The setup automatically configures these environment variables:

- `AORSF_NTHREAD`: Number of threads for ORSF (capped at 16 on EC2)
- `OMP_NUM_THREADS`: OpenMP threads (always 1 to prevent oversubscription)
- `MKL_NUM_THREADS`: Intel MKL threads (always 1 to prevent oversubscription)
- `OPENBLAS_NUM_THREADS`: OpenBLAS threads (always 1 to prevent oversubscription)
- `VECLIB_MAXIMUM_THREADS`: Vector library threads (always 1 to prevent oversubscription)
- `NUMEXPR_NUM_THREADS`: NumExpr threads (always 1 to prevent oversubscription)

**Critical EC2 Configuration:**
- `ORSF_MAX_THREADS=16`: Maximum threads for ORSF (prevents threading conflicts)
- `TASK_TIMEOUT_MINUTES=45`: Individual task timeout protection

## Pipeline Integration

### Updated Functions

The following functions have been updated to use optimal parallel processing:

- `fit_orsf()`: ORSF model fitting with parallel configuration
- `configure_aorsf_parallel()`: Parallel configuration with EC2 safety
- `aorsf_parallel()`: General ORSF with parallel config (if implemented)

### Environment Variable Overrides

The pipeline respects these environment variables:

- `ORSF_MAX_THREADS`: Override maximum thread count (default: 16)
- `ORSF_NTREES`: Number of trees for ORSF models
- `AORSF_NTHREAD`: Direct ORSF thread control

## Best Practices

### 1. Thread Configuration

- **Use capped cores**: Set `ORSF_MAX_THREADS=16` for EC2 instances with >16 cores
- **Target utilization**: Use 80% of available cores when not capped
- **R function check**: Enable `check_r_functions = TRUE` for automatic detection

### 2. R Function Limitations

- **Single-threaded mode**: When R functions are detected in ORSF calls
- **Performance impact**: Consider trade-offs between R functions and speed
- **Alternative**: Use built-in ORSF functions when possible

### 3. Memory Management

- **Standard mode**: Fast but uses more memory
- **Large datasets**: Monitor memory usage during training
- **EC2 optimization**: 1TB RAM allows for large models

### 4. Monitoring

- **Performance logs**: Monitor ORSF training time and resource usage
- **Threading conflicts**: Watch for `[THREADING_CONFLICT]` in logs
- **Process monitoring**: Use `[PROCESS_PRE_ORSF]` and `[PROCESS_POST_ORSF]` logs

## Troubleshooting

### Common Issues

1. **Thread detection fails**: Falls back to single thread
2. **R function conflicts**: Automatically limits to 1 thread
3. **Memory issues**: Monitor system memory during training
4. **EC2 Threading conflicts**: ORSF hangs trying to use all cores
5. **Task timeout**: ORSF tasks exceed time limits

### Debugging

```r
# Check system information
cat("Available cores:", parallel::detectCores(), "\n")
cat("ORSF max threads:", Sys.getenv("ORSF_MAX_THREADS", "16"), "\n")

# Verify configuration
orsf_config <- configure_aorsf_parallel(verbose = TRUE)
# Should show: "EC2 Safety: Capping ORSF threads to 16"

# Test with small dataset
test_model <- fit_orsf(
  trn = small_data,
  vars = selected_vars,
  use_parallel = TRUE,
  check_r_functions = TRUE
)
```

### Signs of Threading Conflicts

**Symptoms:**
- ORSF tasks start but never complete (hang indefinitely)
- High CPU usage but no progress in logs
- Log timestamps show tasks started but no completion

**Log Patterns to Watch:**
```
[PROCESS_PRE_ORSF] 2025-10-08 10:15:30 PID=12345 Cores=16/32 CPU=15.2%
(no PROCESS_POST_ORSF entry - task hung)
[THREADING_CONFLICT] High load ratio (2.85) - load 91.20 on 32 cores
```

## Performance Tips

### 1. Optimal Settings

- **Threads**: Use 16 threads max on EC2 (via `ORSF_MAX_THREADS=16`)
- **Trees**: 1000-2000 for most applications (via `ORSF_NTREES`)
- **Memory**: Monitor usage with large datasets
- **R functions**: Avoid when possible for better threading

### 2. Large Datasets

- **Memory monitoring**: Watch for memory pressure during training
- **Thread limits**: Reduce threads if memory becomes constrained
- **Batch processing**: Consider data splitting for very large datasets

### 3. EC2 Optimization

- **Thread capping**: Always use `ORSF_MAX_THREADS=16` on high-core instances
- **Resource monitoring**: Monitor CPU and memory usage
- **Timeout protection**: Use `TASK_TIMEOUT_MINUTES=45` for safety

## Examples

### Complete Workflow

```r
# 1. Setup
source("scripts/config.R")
orsf_config <- configure_aorsf_parallel(
  use_all_cores = TRUE,
  check_r_functions = TRUE,
  verbose = TRUE
)

# 2. Model training
model <- fit_orsf(
  trn = training_data,
  vars = selected_vars,
  use_parallel = TRUE,
  check_r_functions = TRUE
)

# 3. Prediction
predictions <- predict(
  model,
  newdata = test_data,
  pred_horizon = 1
)
```

### EC2 Configuration Check

```r
# Verify EC2-safe configuration
cat("Available cores:", parallel::detectCores(), "\n")
cat("ORSF max threads:", Sys.getenv("ORSF_MAX_THREADS", "16"), "\n")

# Should show capped threads on EC2
orsf_config <- configure_aorsf_parallel(use_all_cores = TRUE, verbose = TRUE)
# Expected: "EC2 Safety: Capping ORSF threads to 16 (detected 32 cores)"
```

## Files

- `R/aorsf_parallel_config.R`: ORSF parallel configuration module
- `R/fit_orsf.R`: ORSF fitting function with parallel support
- `scripts/04_fit_model.R`: Pipeline integration with ORSF configuration

## Dependencies

- `aorsf`: Oblique Random Survival Forest implementation
- `future`: Parallel processing framework
- `parallel`: Core parallel functionality
- `survival`: Survival analysis

## References

- [aorsf Package Documentation](https://cran.r-project.org/package=aorsf)
- [aorsf GitHub Repository](https://github.com/ropensci/aorsf)
- [Parallel Processing in R](https://cran.r-project.org/web/views/HighPerformanceComputing.html)

## Expected Configuration Output

```
EC2 Safety: Capping ORSF threads to 16 (detected 32 cores)
=== aorsf Parallel Configuration ===
Available cores: 32
aorsf threads: 16
Target utilization: 80.0%
R function limitation: FALSE
Environment variables set:
  OMP_NUM_THREADS = 1
  MKL_NUM_THREADS = 1
  OPENBLAS_NUM_THREADS = 1
  VECLIB_MAXIMUM_THREADS = 1
  NUMEXPR_NUM_THREADS = 1
  AORSF_NTHREAD = 16
=====================================
```

This configuration ensures optimal ORSF performance on EC2 instances while preventing threading conflicts and oversubscription.
