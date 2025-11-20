# CatBoost Parallelization Setup

This document outlines the parallelization configuration and setup for CatBoost models in the graft loss prediction pipeline.

## Overview

CatBoost (Categorical Boosting) is a gradient boosting library that handles categorical features natively and provides built-in parallelization through its C++ implementation. Unlike tree-based models that parallelize across trees, CatBoost parallelizes the gradient boosting process internally.

### Implementation Options

This pipeline uses the **Python CatBoost implementation** via subprocess integration. Two main approaches are available:

1. **Python Implementation** (Current): R calls Python script running CatBoost
2. **R Implementation** (Alternative): Direct R package integration

#### Python vs R Implementation Comparison

| Aspect | Python Implementation | R Implementation |
|--------|----------------------|------------------|
| **Survival Features** | ⭐⭐⭐⭐⭐ Full survival analysis support | ⭐⭐⭐ Limited survival features |
| **Integration Complexity** | ⭐⭐⭐ Subprocess overhead | ⭐⭐⭐⭐⭐ Native R integration |
| **Performance** | ⭐⭐⭐⭐ Minimal subprocess overhead | ⭐⭐⭐⭐⭐ Direct memory access |
| **Reliability** | ⭐⭐⭐⭐⭐ Mature, extensively tested | ⭐⭐⭐ R package may lag behind |
| **Documentation** | ⭐⭐⭐⭐⭐ Extensive survival examples | ⭐⭐ Limited survival documentation |
| **Debugging** | ⭐⭐⭐ Cross-language debugging | ⭐⭐⭐⭐⭐ Pure R debugging |
| **Deployment** | ⭐⭐⭐ Requires Python + CatBoost | ⭐⭐⭐⭐⭐ Single R environment |

**Current Choice: Python Implementation** - Selected for superior survival analysis capabilities and reliability, despite slightly more complex integration.

## Threading Configuration

### Thread Control Methods

CatBoost handles parallelization through:
1. **Internal C++ threading**: CatBoost manages its own thread pool
2. **Python process execution**: R calls Python script which runs CatBoost
3. **BLAS library control**: Prevent oversubscription by setting BLAS to single-threaded

### Default Settings (EC2 Optimized)

- `CATBOOST_MAX_THREADS=8`: CatBoost thread limit (EC2 safe, default: 8)
- `CATBOOST_TIMEOUT_MINUTES=30`: Training timeout protection
- `CATBOOST_ITERATIONS=2000`: Number of boosting rounds
- `CATBOOST_DEPTH=6`: Tree depth
- `CATBOOST_LEARNING_RATE=0.05`: Learning rate
- `OMP_NUM_THREADS=1`: OpenMP threads (CRITICAL: Always 1 to prevent oversubscription)
- `MKL_NUM_THREADS=1`: Intel MKL threads (CRITICAL: Always 1)
- `OPENBLAS_NUM_THREADS=1`: OpenBLAS threads (CRITICAL: Always 1)
- `VECLIB_MAXIMUM_THREADS=1`: Vector library threads (CRITICAL: Always 1)
- `NUMEXPR_NUM_THREADS=1`: NumExpr threads (CRITICAL: Always 1)

### Critical EC2 Configuration

- `CATBOOST_MAX_THREADS=8`: Safe thread limit to prevent threading conflicts on high-core instances
- **BLAS Threading**: All BLAS libraries are set to single-threaded (`=1`) to prevent double parallelization
- **Python Integration**: CatBoost runs via Python subprocess, isolated from R threading

## Pipeline Integration

### `configure_catboost_parallel()` Function

```r
configure_catboost_parallel <- function(use_all_cores = TRUE, 
                                       max_threads = NULL, 
                                       target_utilization = 0.8,
                                       check_r_functions = TRUE,
                                       verbose = FALSE) {
  
  # Detect available cores
  available_cores <- tryCatch({
    as.numeric(future::availableCores())
  }, error = function(e) {
    parallel::detectCores(logical = TRUE)
  })
  
  # Apply EC2 safety limits
  if (is.null(max_threads)) {
    max_safe_threads <- as.numeric(Sys.getenv("CATBOOST_MAX_THREADS", unset = "8"))
    if (available_cores > max_safe_threads) {
      max_threads <- max_safe_threads
      message(sprintf("EC2 Safety: Capping CatBoost threads to %d (detected %d cores)", 
                     max_safe_threads, available_cores))
    } else {
      max_threads <- floor(available_cores * target_utilization)
    }
  }
  
  # CRITICAL: Set BLAS libraries to single-threaded
  catboost_env_vars <- list(
    CATBOOST_MAX_THREADS = as.character(max_threads),
    OMP_NUM_THREADS = "1",                    # Always 1
    MKL_NUM_THREADS = "1",                    # Always 1
    OPENBLAS_NUM_THREADS = "1",               # Always 1
    VECLIB_MAXIMUM_THREADS = "1",             # Always 1
    NUMEXPR_NUM_THREADS = "1"                 # Always 1
  )
  
  # Apply environment variables
  for (var_name in names(catboost_env_vars)) {
    Sys.setenv(setNames(catboost_env_vars[[var_name]], var_name))
  }
  
  return(config)
}
```

### MC-CV Processing (`R/utils/model_utils.R`)

```r
} else if (model_type == "CATBOOST") {
  cat(sprintf('[DEBUG] CATBOOST fitting - data dimensions: %d rows, %d vars\n', 
              nrow(trn_df), length(vars_native)), file = model_log, append = TRUE)
  
  # CRITICAL: Log process state before CatBoost fitting
  tryCatch({
    if (exists("log_process_info", mode = "function")) {
      log_process_info(model_log, "[PROCESS_PRE_CATBOOST]", include_children = TRUE, include_system = TRUE)
    }
  }, error = function(e) NULL)
  
  # Configure CatBoost parallel processing for MC-CV
  catboost_config <- configure_catboost_parallel(
    use_all_cores = TRUE,
    target_utilization = 0.8,
    check_r_functions = TRUE,
    verbose = FALSE
  )
  
  # Add timeout protection for CatBoost
  catboost_timeout_minutes <- as.numeric(Sys.getenv("CATBOOST_TIMEOUT_MINUTES", unset = "30"))
  if (requireNamespace("R.utils", quietly = TRUE)) {
    fitted_model <- R.utils::withTimeout({
      fit_catboost(trn = trn_df, vars = vars_native, use_parallel = TRUE)
    }, timeout = catboost_timeout_minutes * 60, onTimeout = "error")
  } else {
    fitted_model <- fit_catboost(trn = trn_df, vars = vars_native, use_parallel = TRUE)
  }
  
  # CRITICAL: Log process state after CatBoost fitting
  tryCatch({
    if (exists("log_process_info", mode = "function")) {
      log_process_info(model_log, "[PROCESS_POST_CATBOOST]", include_children = TRUE, include_system = TRUE)
    }
  }, error = function(e) NULL)
}
```

### Process Monitoring Integration

#### Log Output Examples

**Normal CatBoost Training:**
```
[PROCESS_PRE_CATBOOST] 2025-10-08 14:15:30 PID=12345 Cores=8/32 CPU=15.2% MEM=8.1% Threads=2 CurrentCore=7
[CATBOOST_INIT] Starting CatBoost model with 3501 observations, 21 predictors
[CATBOOST_INIT] Events: 987 (28.2%), Censored: 2514 (71.8%)
[CATBOOST_INIT] Events per predictor ratio: 47.00 (recommended: >10)
[CATBOOST_CONFIG] Using 8 threads (from CATBOOST_MAX_THREADS)
[CATBOOST_EXEC] Running CatBoost with 2000 iterations, depth 6, lr 0.050
[CATBOOST_EXEC] Categorical columns: prim_dx, race, hisp
[CATBOOST_SUCCESS] CatBoost training completed successfully
[CATBOOST_RESULTS] Model trained on 2801 samples, tested on 700 samples
[CATBOOST_RESULTS] Used 21 features, 3 categorical
[PROCESS_POST_CATBOOST] 2025-10-08 14:18:45 PID=12345 Cores=8/32 CPU=5.1% MEM=8.3% Threads=2 CurrentCore=12
```

**CatBoost with Threading Issues:**
```
[PROCESS_PRE_CATBOOST] 2025-10-08 14:20:15 PID=12346 Cores=32/32 CPU=95.2% MEM=12.1% Threads=24 CurrentCore=15
[THREADING_CONFLICT] 2025-10-08 14:20:16 Detected conflicts: High CPU (95.2%) with many threads (24)
[CATBOOST_ERROR] Python script failed with output: RuntimeError: Thread pool exhausted
[ERROR] CATBOOST fitting failed after 1205.3 seconds: CatBoost execution failed
```

## Environment Variables

### CatBoost-Specific Variables

- **`CATBOOST_MAX_THREADS=8`**: Maximum threads for CatBoost training (default: 8)
  - Prevents threading conflicts on high-core EC2 instances
  - Can be increased on dedicated machines with fewer parallel workers
  
- **`CATBOOST_TIMEOUT_MINUTES=30`**: Timeout for CatBoost model fitting (default: 30 minutes)
  - CatBoost typically completes in 5-15 minutes for most datasets
  - Prevents infinite hangs due to Python process issues
  
- **`CATBOOST_ITERATIONS=2000`**: Number of boosting iterations (default: 2000)
  - Controls model complexity and training time
  - More iterations = better performance but longer training
  
- **`CATBOOST_DEPTH=6`**: Tree depth (default: 6)
  - Controls individual tree complexity
  - Deeper trees = more complex interactions but risk of overfitting
  
- **`CATBOOST_LEARNING_RATE=0.05`**: Learning rate (default: 0.05)
  - Controls step size in gradient descent
  - Lower values = more stable training but require more iterations

### Python Integration Variables

- **`PYTHON_CMD=python3`**: Python executable to use (default: python3)
  - Must have CatBoost library installed: `pip install catboost`
  - Can specify full path if needed: `/usr/bin/python3`

### Threading Safety Variables (Critical)

- **`OMP_NUM_THREADS=1`**: OpenMP threading (ALWAYS 1)
- **`MKL_NUM_THREADS=1`**: Intel MKL threading (ALWAYS 1)  
- **`OPENBLAS_NUM_THREADS=1`**: OpenBLAS threading (ALWAYS 1)
- **`VECLIB_MAXIMUM_THREADS=1`**: Vector library threading (ALWAYS 1)
- **`NUMEXPR_NUM_THREADS=1`**: NumExpr threading (ALWAYS 1)

## Troubleshooting

### EC2-Specific Threading Issues

#### Threading Oversubscription Analysis

**Before EC2 Fixes (Problematic):**
```
Available cores: 32
CatBoost threads: auto (tries to use all 32 cores)
BLAS threads: auto (8+ threads per BLAS operation)
Total theoretical threads: 32 + (32 × 8) = 288+ threads
Result: Massive oversubscription, Python process hangs
```

**After EC2 Fixes (Corrected):**
```
Available cores: 32
CatBoost threads: 8 (capped by CATBOOST_MAX_THREADS)
BLAS threads: 1 (all BLAS libraries single-threaded)
Total threads: 8 + 1 = 9 threads per worker
Result: Manageable threading, stable performance
```

#### Conflict Detection

Threading conflicts are detected when:
- **High CPU usage** (>90%) with many threads (>16)
- **High system load** (load average > 1.5 × cores)
- **Python subprocess hangs** for >5 minutes
- **Memory usage spikes** unexpectedly

#### Expected Configuration Output

**Correct Threading Configuration:**
```
EC2 Safety: Capping CatBoost threads to 8 (detected 32 cores)
=== CatBoost Parallel Configuration ===
Available cores: 32
CatBoost threads: 8
Target utilization: 80.0%
Environment variables set:
  CATBOOST_MAX_THREADS = 8
  OMP_NUM_THREADS = 1
  MKL_NUM_THREADS = 1
  OPENBLAS_NUM_THREADS = 1
  VECLIB_MAXIMUM_THREADS = 1
  NUMEXPR_NUM_THREADS = 1
=====================================
```

### R Implementation Alternative

#### Potential R CatBoost Integration

If you prefer to use the R CatBoost package instead of Python, here's how it could be implemented:

```r
# Alternative R implementation function
fit_catboost_r <- function(trn, vars = NULL, tst = NULL, predict_horizon = NULL, 
                          use_parallel = TRUE, iterations = 2000, depth = 6, 
                          learning_rate = 0.05, l2_leaf_reg = 3.0) {
  
  # Check if R CatBoost package is available
  if (!requireNamespace("catboost", quietly = TRUE)) {
    stop("CatBoost R package not installed. Install with: install.packages('catboost')")
  }
  
  # Prepare data for R CatBoost
  predictor_vars <- if (!is.null(vars)) vars else setdiff(names(trn), c('time', 'status'))
  
  # Create signed-time labels (survival proxy)
  y_train <- ifelse(trn$status == 1, trn$time, -trn$time)
  X_train <- trn[, predictor_vars, drop = FALSE]
  
  # Detect categorical features
  cat_features <- which(sapply(X_train, function(x) is.factor(x) || is.character(x))) - 1  # 0-indexed
  
  # Configure CatBoost parameters
  params <- list(
    loss_function = 'RMSE',
    depth = depth,
    learning_rate = learning_rate,
    iterations = iterations,
    l2_leaf_reg = l2_leaf_reg,
    random_seed = 42,
    verbose = FALSE,
    thread_count = if (use_parallel) as.numeric(Sys.getenv("CATBOOST_MAX_THREADS", "8")) else 1
  )
  
  # Train model
  model <- catboost::catboost.train(
    pool = catboost::catboost.load_pool(X_train, label = y_train, cat_features = cat_features),
    params = params
  )
  
  return(model)
}

# Hybrid approach function
fit_catboost <- function(..., use_r_implementation = FALSE) {
  if (use_r_implementation && requireNamespace("catboost", quietly = TRUE)) {
    cat("[CATBOOST_CONFIG] Using R CatBoost implementation\n")
    return(fit_catboost_r(...))
  } else {
    cat("[CATBOOST_CONFIG] Using Python CatBoost implementation\n")
    return(fit_catboost_python(...))  # Current implementation
  }
}
```

#### R Implementation Advantages

- **Simpler deployment**: No Python dependencies
- **Better debugging**: Pure R error messages and stack traces
- **Direct memory access**: No CSV serialization overhead
- **Native R integration**: Seamless with R data structures

#### R Implementation Limitations

- **Limited survival features**: R package may lack advanced survival analysis capabilities
- **Feature lag**: R package often behind Python version in features and optimizations
- **Less documentation**: Fewer survival analysis examples and tutorials
- **Potential instability**: R package may be less mature for survival use cases

#### Migration Path

To switch to R implementation:

1. **Install R CatBoost package**:
   ```r
   install.packages("catboost")
   ```

2. **Set environment variable**:
   ```r
   Sys.setenv(USE_R_CATBOOST = "1")
   ```

3. **Update fit_catboost.R** with hybrid approach above

4. **Test thoroughly** - survival analysis capabilities may differ

### Enhanced Error Handling and Debugging

The current implementation includes comprehensive error handling with specific guidance:

```r
# Enhanced error handling in fit_catboost.R
tryCatch({
  result <- system2(python_cmd, args = cmd_args, stdout = TRUE, stderr = TRUE)
  
  # Check exit status with specific error guidance
  exit_status <- attr(result, "status")
  if (!is.null(exit_status) && exit_status != 0) {
    # Provide specific error guidance based on output
    if (any(grepl("ModuleNotFoundError.*catboost", result, ignore.case = TRUE))) {
      stop("CatBoost not installed. Run: pip install catboost")
    } else if (any(grepl("MemoryError", result, ignore.case = TRUE))) {
      stop("Insufficient memory for CatBoost training. Try reducing dataset size.")
    } else if (any(grepl("FileNotFoundError", result, ignore.case = TRUE))) {
      stop("Python executable not found. Check PYTHON_CMD environment variable.")
    }
  }
  
  # Log Python output for debugging
  if (length(result) > 0) {
    debug_output <- head(result, 5)
    cat("[CATBOOST_DEBUG] Python output (first 5 lines):\n")
    cat(paste(debug_output, collapse = "\n"), "\n")
  }
  
}, error = function(e) {
  # Additional debugging information
  cat(sprintf("[CATBOOST_DEBUG] Python command: %s\n", python_cmd))
  cat(sprintf("[CATBOOST_DEBUG] Working directory: %s\n", getwd()))
  cat(sprintf("[CATBOOST_DEBUG] Train file exists: %s\n", file.exists(train_file)))
  cat(sprintf("[CATBOOST_DEBUG] Test file exists: %s\n", file.exists(test_file)))
  cat(sprintf("[CATBOOST_DEBUG] Python script exists: %s\n", file.exists(python_script)))
})
```

### Common Issues and Solutions

#### Issue 1: Python Script Not Found
```
[CATBOOST_ERROR] CatBoost Python script not found: scripts/py/catboost_survival.py
[CATBOOST_DEBUG] Python script exists: FALSE
```
**Solution**: Ensure `scripts/py/catboost_survival.py` exists and is executable.

#### Issue 2: CatBoost Library Not Installed
```
[CATBOOST_ERROR] Python script failed with exit code: 1
[CATBOOST_ERROR] Output: ModuleNotFoundError: No module named 'catboost'
```
**Solution**: Install CatBoost: `pip install catboost`

#### Issue 3: Python Executable Not Found
```
[CATBOOST_ERROR] Python script failed with exit code: 127
[CATBOOST_ERROR] Output: FileNotFoundError: python3: command not found
[CATBOOST_DEBUG] Python command: python3
```
**Solution**: Install Python 3 or set `PYTHON_CMD` environment variable to correct path.

#### Issue 4: Threading Conflicts
```
[ERROR] CATBOOST fitting timed out after 1800.0 seconds (30.0 minutes)
[ERROR] CATBOOST timeout - check CATBOOST_MAX_THREADS=16
[THREADING_CONFLICT] Detected conflicts: High CPU (95.2%) with many threads (24)
```
**Solution**: Reduce `CATBOOST_MAX_THREADS` to 4-8 on high-core instances.

#### Issue 5: Memory Issues
```
[CATBOOST_ERROR] Python script failed with exit code: 1
[CATBOOST_ERROR] Output: MemoryError: Unable to allocate 8.5GB array
[CATBOOST_DEBUG] Train file exists: TRUE
```
**Solution**: Reduce dataset size, increase available memory, or use data sampling.

#### Issue 6: Data File Issues
```
[CATBOOST_ERROR] Python script failed with exit code: 1
[CATBOOST_DEBUG] Train file exists: FALSE
[CATBOOST_DEBUG] Working directory: /path/to/project
```
**Solution**: Check file permissions and disk space. Ensure temporary directory is writable.

### Verification Commands

Check threading configuration:
```bash
echo "CATBOOST_MAX_THREADS: $CATBOOST_MAX_THREADS"
echo "OMP_NUM_THREADS: $OMP_NUM_THREADS"
echo "Python version: $(python3 --version)"
python3 -c "import catboost; print(f'CatBoost version: {catboost.__version__}')"
```

Monitor CatBoost process:
```bash
# During training, check Python processes
ps aux | grep python | grep catboost
# Check thread count
ps -eLf | grep python | wc -l
```

## Integration Checklist

### ✅ **Threading Configuration**
- [ ] `configure_catboost_parallel()` called in main setup
- [ ] `CATBOOST_MAX_THREADS=8` environment variable set
- [ ] BLAS libraries set to single-threaded (`OMP_NUM_THREADS=1`)
- [ ] Thread capping message appears in logs
- [ ] No threading conflicts detected

### ✅ **Process Monitoring**
- [ ] `[PROCESS_PRE_CATBOOST]` logs before fitting
- [ ] `[PROCESS_POST_CATBOOST]` logs after fitting
- [ ] Process monitoring integrated in `compute_task_internal()`
- [ ] Threading conflict detection active
- [ ] Background monitoring captures CatBoost processes

### ✅ **Python Integration**
- [ ] `scripts/py/catboost_survival.py` exists and is executable
- [ ] CatBoost library installed (`pip install catboost`)
- [ ] Python executable accessible (`python3` or custom `PYTHON_CMD`)
- [ ] Temporary file handling works correctly
- [ ] JSON output parsing functional

### ✅ **Performance & Error Handling**
- [ ] Timeout protection active (`CATBOOST_TIMEOUT_MINUTES`)
- [ ] Memory monitoring before/after fitting
- [ ] Error messages are informative
- [ ] Model artifacts saved correctly
- [ ] Prediction interface functional

### ✅ **MC-CV Data Quality**
- [ ] `[CATBOOST_INIT]` diagnostics logged
- [ ] Events per predictor ratio calculated
- [ ] Variable quality screening performed
- [ ] Categorical variable detection working
- [ ] Poor split handling implemented

## Files

### Core Implementation
- **`R/fit_catboost.R`**: Main CatBoost fitting function
- **`R/catboost_parallel_config.R`**: Threading configuration
- **`scripts/py/catboost_survival.py`**: Python CatBoost implementation
- **`R/load_catboost_outputs.R`**: Result loading utilities

### Integration Points
- **`R/utils/model_utils.R`**: MC-CV pipeline integration
- **`scripts/04_fit_model.R`**: Main orchestration script
- **`R/utils/process_monitor.R`**: Process monitoring utilities

### Documentation
- **`model_setup/Model_Implementation_Checklist.md`**: Implementation guidelines
- **`model_setup/Updated_Pipeline_README.md`**: Pipeline overview
- **This document**: CatBoost-specific setup and troubleshooting

## Performance Characteristics

### Expected Training Times (EC2 32-core)
- **Small datasets** (<1000 obs): 30 seconds - 2 minutes
- **Medium datasets** (1000-5000 obs): 2-10 minutes  
- **Large datasets** (>5000 obs): 10-25 minutes

### Memory Usage
- **Base R process**: ~200MB
- **CatBoost training**: 2-5x dataset size
- **Model artifacts**: 1-10MB per model

### Threading Efficiency
- **Optimal threads**: 4-8 on high-core instances
- **CPU utilization**: 60-80% during training
- **Memory efficiency**: Better than tree-based models due to categorical handling

## Advantages over RSF

### Technical Advantages

1. **Native categorical handling**: No need for dummy encoding, handles categorical variables directly
2. **Better parallelization**: Internal C++ threading more stable than Ranger's approach
3. **Robust training**: Less prone to hanging or memory issues that plagued RSF
4. **Superior performance**: Often achieves better predictive accuracy on survival tasks
5. **Gradient boosting**: Different algorithm class provides model diversity vs tree-based models
6. **Production ready**: Mature library with extensive optimization and battle-testing

### Implementation Advantages

7. **Enhanced error handling**: Comprehensive error detection with specific guidance
8. **Better debugging**: Detailed diagnostic information for troubleshooting
9. **Flexible deployment**: Choice between Python (current) or R implementation
10. **Timeout protection**: Built-in safeguards against infinite hangs
11. **Process monitoring**: Full integration with pipeline monitoring system
12. **Threading safety**: EC2-optimized configuration prevents conflicts

### Survival Analysis Advantages

13. **Signed-time approach**: Well-established method for survival modeling with gradient boosting
14. **Robust to censoring**: Handles censored observations effectively
15. **Feature importance**: Built-in feature importance for survival analysis
16. **Hyperparameter tuning**: Extensive hyperparameter options for optimization

### Why CatBoost Replaced RSF

The decision to replace RSF with CatBoost was driven by:

- **RSF threading conflicts**: Unsolvable hanging issues on high-core EC2 instances
- **Better categorical handling**: CatBoost's native support vs RSF's dummy encoding requirements
- **Superior reliability**: CatBoost's mature Python implementation vs RSF's R threading issues
- **Enhanced performance**: Better predictive accuracy and faster training times
- **Algorithm diversity**: Gradient boosting complements tree-based models (ORSF) better than another tree model (RSF)
