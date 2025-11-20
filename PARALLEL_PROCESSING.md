# Parallel Processing Documentation

## Overview

The PHTS Graft Loss Prediction Pipeline uses multiple forms of parallel processing to accelerate model fitting, resampling, and orchestration. This document describes all parallelization strategies, configuration options, and best practices.

## Parallelization Strategies

### 1. furrr/future Parallelization (Monte Carlo CV)

**Location**: `graft-loss/scripts/04_fit_model.R`

**Purpose**: Parallel execution of Monte Carlo cross-validation splits

**Implementation**:
- Uses `furrr::future_map` to process multiple CV splits simultaneously
- Backend configured via `future::plan` (multicore or multisession)
- Optimal chunk size calculated based on number of workers
- All model saving performed inside worker functions for robustness

**Code Example**:
```r
# Configure parallel backend
workers_env <- suppressWarnings(as.integer(Sys.getenv('MC_SPLIT_WORKERS', unset = '0')))
if (!is.finite(workers_env) || workers_env < 1) {
  cores <- tryCatch(as.numeric(future::availableCores()), 
                    error = function(e) parallel::detectCores(logical = TRUE))
  workers <- max(1L, floor(cores * 0.80))
} else {
  workers <- workers_env
}

# Set up future plan
if (future::supportsMulticore()) {
  future::plan(future::multicore, workers = workers)
} else {
  future::plan(future::multisession, workers = workers)
}

# Parallel execution with optimal chunking
chunk_size <- max(1L, ceiling(length(split_idx) / workers))
res_list <- furrr::future_map(
  split_idx, 
  process_split,
  .options = furrr::furrr_options(
    seed = TRUE,
    chunk_size = chunk_size,
    scheduling = 1.0  # Optimal for compute-intensive tasks
  )
)
```

**Environment Variables**:
- `MC_SPLIT_WORKERS`: Number of workers for parallel CV splits (auto-detected if not set)

### 2. Parallel Backend Utilities

**Location**: `graft-loss/R/utils/parallel_utils.R`

**Purpose**: Centralized parallel processing configuration

**Key Functions**:

#### `setup_parallel_backend()`
Configures optimal parallel processing backend with EC2 compatibility.

**Parameters**:
- `workers`: Number of workers (auto-detected if NULL)
- `target_utilization`: Target CPU utilization (default 0.8 = 80%)
- `force_backend`: Force specific backend ("multicore" or "multisession")

**Features**:
- Auto-detects cores using multiple fallback methods
- EC2-compatible core detection
- Automatic backend selection (multicore → multisession → parallel)
- Respects `MC_SPLIT_WORKERS` environment variable

**Usage**:
```r
source(file.path("R", "utils", "parallel_utils.R"))
config <- setup_parallel_backend()
# Returns: list(backend = "multicore", workers = 8, utilization = 0.8)
```

#### `parallel_map_optimal()`
Parallel map with optimal chunking for better performance.

**Parameters**:
- `.x`: Input vector/list
- `.f`: Function to apply
- `.workers`: Number of workers (auto-detected if NULL)
- `.chunk_size`: Chunk size (auto-calculated if NULL)
- `.scheduling`: Scheduling parameter for furrr (default 1.0)

**Usage**:
```r
results <- parallel_map_optimal(
  .x = split_indices,
  .f = process_split,
  .workers = 8
)
```

### 3. Orchestration-Level Parallelism

**Location**: `graft-loss/scripts/run_three_datasets.R`

**Purpose**: Run multiple dataset cohorts in parallel as separate R processes

**Implementation**:
- Launches three separate R processes (one per cohort)
- Each process runs full pipeline independently
- Uses system calls with environment variables for isolation
- Resource allocation: ~25% of cores per dataset

**Cohorts**:
1. **Original Study** (2010-2019): `ORIGINAL_STUDY=1`
2. **Full Dataset with COVID** (2010-2024): `EXCLUDE_COVID=0`
3. **Full Dataset without COVID** (2010-2019, excluding 2020+): `EXCLUDE_COVID=1`

**Code Example**:
```r
# Calculate optimal workers per dataset
parallel_config <- setup_parallel_backend()
cores <- parallel_config$workers
per_dataset_cores <- max(1L, floor(cores * 0.25))

# Launch each dataset in background with resource limits
for (nm in names(runs)) {
  env_vec <- c(
    sprintf("MC_WORKER_THREADS=%d", per_dataset_cores),
    "OMP_NUM_THREADS=1",
    "OPENBLAS_NUM_THREADS=1",
    # ... other thread limits
  )
  system2(rscript, args = c("scripts/run_pipeline.R"), 
          env = env_vec, wait = FALSE)
}
```

### 4. Threading Control

**Purpose**: Avoid CPU oversubscription by controlling inner-model threading

**Environment Variables**:
- `MC_WORKER_THREADS`: Threads per worker (default: 1)
- `OMP_NUM_THREADS`: OpenMP threads (default: 1)
- `OPENBLAS_NUM_THREADS`: OpenBLAS threads (default: 1)
- `MKL_NUM_THREADS`: Intel MKL threads (default: 1)
- `VECLIB_MAXIMUM_THREADS`: Accelerate framework threads (default: 1)
- `NUMEXPR_NUM_THREADS`: NumExpr threads (default: 1)

**Rationale**: When using parallel workers, each worker should use single-threaded BLAS/OpenMP to avoid oversubscription. For example, with 8 parallel workers, each using 4 threads, you'd have 32 threads competing for 8 cores.

**Configuration**:
```r
# Set in scripts/04_fit_model.R
worker_threads <- suppressWarnings(as.integer(Sys.getenv("MC_WORKER_THREADS", unset = "1")))
Sys.setenv(
  OMP_NUM_THREADS = as.character(worker_threads),
  OPENBLAS_NUM_THREADS = as.character(worker_threads),
  MKL_NUM_THREADS = as.character(worker_threads),
  # ... other thread limits
)
```

**Model-Specific Threading**:
- **RSF (ranger)**: Honors `MC_WORKER_THREADS` via `num.threads` parameter
- **XGBoost**: Honors `MC_WORKER_THREADS` via `nthread` parameter
- **ORSF**: Uses single-threaded mode per worker

## Best Practices

### 1. Function Availability in Workers

**Problem**: Parallel workers need access to all functions and objects.

**Solution**:
- Define all functions at top level or source before parallel execution
- Use `.options` argument in furrr to export packages and globals
- Never rely on super assignment (`<<-`) for objects needed in workers

**Example**:
```r
# ✅ Good: Source functions before parallel execution
source(file.path("R", "fit_rsf.R"))
source(file.path("R", "fit_orsf.R"))

# ✅ Good: Use .options to export packages
furrr::future_map(
  .x = splits,
  .f = process_split,
  .options = furrr::furrr_options(
    seed = TRUE,
    packages = c("ranger", "aorsf", "xgboost")
  )
)
```

### 2. Model Saving in Workers

**Problem**: Models saved after parallel execution may be lost if workers fail.

**Solution**: Always save models inside worker functions.

**Example**:
```r
process_split <- function(split_idx) {
  # ... fit model ...
  
  # ✅ Good: Save inside worker
  saveRDS(model, file.path(outdir, paste0("model_split_", split_idx, ".rds")))
  
  return(list(metrics = metrics))
}

# ❌ Bad: Saving after parallel execution
results <- furrr::future_map(splits, process_split)
saveRDS(results, "models.rds")  # May lose individual models
```

### 3. Parallel Plan Setup

**Problem**: Parallel plan must be set before any parallel map/apply call.

**Solution**: Always set plan explicitly before parallel execution.

**Example**:
```r
# ✅ Good: Explicit plan setup
if (future::supportsMulticore()) {
  future::plan(future::multicore, workers = 8)
} else {
  future::plan(future::multisession, workers = 8)
}

# Then use parallel functions
results <- furrr::future_map(splits, process_split)
```

### 4. Resource Management

**Problem**: CPU oversubscription reduces performance.

**Solution**: 
- Use `MC_WORKER_THREADS=1` when using parallel workers
- Calculate optimal workers: `floor(cores * 0.8)`
- For orchestration-level parallelism: `floor(cores * 0.25)` per dataset

**Example**:
```r
# Detect cores
cores <- future::availableCores()

# For parallel CV splits: use 80% of cores
workers_cv <- floor(cores * 0.80)

# For orchestration: use 25% per dataset
workers_per_dataset <- floor(cores * 0.25)
```

## Environment Variables Summary

| Variable | Purpose | Default | Used In |
|----------|---------|---------|---------|
| `MC_SPLIT_WORKERS` | Workers for parallel CV splits | Auto-detected (80% cores) | `04_fit_model.R` |
| `MC_WORKER_THREADS` | Threads per worker (BLAS/OpenMP) | 1 | All model fitting scripts |
| `OMP_NUM_THREADS` | OpenMP threads | 1 | All scripts |
| `OPENBLAS_NUM_THREADS` | OpenBLAS threads | 1 | All scripts |
| `MKL_NUM_THREADS` | Intel MKL threads | 1 | All scripts |
| `MC_CV` | Enable Monte Carlo CV | 0 | `04_fit_model.R` |
| `MC_MAX_SPLITS` | Maximum CV splits | 1000 | `04_fit_model.R` |

## Performance Optimization

### Optimal Worker Configuration

**For Monte Carlo CV**:
- **Workers**: `floor(cores * 0.80)` (leaves 20% for system)
- **Threads per worker**: 1 (avoids oversubscription)
- **Chunk size**: `ceiling(n_splits / workers)` (balanced load)

**For Orchestration**:
- **Workers per dataset**: `floor(cores * 0.25)` (3 datasets × 25% = 75% total)
- **Threads per worker**: 1
- **Total utilization**: ~75% (leaves 25% for system)

### EC2-Specific Considerations

**Core Detection**:
- Uses `future::availableCores()` as primary method
- Falls back to `parallel::detectCores()` if future unavailable
- Ultimate fallback: Linux `/proc/cpuinfo` parsing

**Backend Selection**:
- Prefers `multicore` (faster, lower memory overhead)
- Falls back to `multisession` on Windows or if multicore unavailable
- Ultimate fallback: basic `parallel` package

## Monitoring and Debugging

### Logging

**Cohort-Specific Logs**:
- `logs/orch_bg_original_study.log`
- `logs/orch_bg_full_with_covid.log`
- `logs/orch_bg_full_without_covid.log`

**Model-Specific Logs**:
- `logs/models/{cohort}/full/ORSF_split001.log`
- `logs/models/{cohort}/full/RSF_split001.log`
- `logs/models/{cohort}/full/XGB_split001.log`

### Progress Tracking

**JSON Progress File**:
- `logs/progress/pipeline_progress.json`
- Updated after each split completion
- Contains: splits completed, last split number, timestamp

### Function Availability Diagnostics

Parallel workers log function availability to help debug failures:

```
[FUNCTION_DIAG] Checking function availability for ORSF model...
[FUNCTION_DIAG] Required functions: fit_orsf, configure_aorsf_parallel, ...
[FUNCTION_DIAG] Available functions: fit_orsf, configure_aorsf_parallel, ...
[FUNCTION_DIAG] Missing functions: aorsf_parallel, predict_aorsf_parallel
```

### Monitoring Commands

```bash
# Real-time log monitoring
tail -f logs/orch_bg_original_study.log

# Check progress
cat logs/progress/pipeline_progress.json

# Check function diagnostics
grep "FUNCTION_DIAG" logs/models/original_study/full/*.log

# Monitor resource usage
Rscript scripts/ec2_diagnostics.R
```

## Troubleshooting

### Common Issues

1. **"Cannot find function" errors in workers**
   - **Solution**: Source all required functions before parallel execution
   - **Check**: Use function availability diagnostics in logs

2. **CPU oversubscription (slow performance)**
   - **Solution**: Set `MC_WORKER_THREADS=1` and all thread environment variables to 1
   - **Check**: Monitor CPU usage with `htop` or `top`

3. **Memory issues with many workers**
   - **Solution**: Reduce `MC_SPLIT_WORKERS` or use `multisession` backend
   - **Check**: Monitor memory with `free -h` or `htop`

4. **Models not saved**
   - **Solution**: Ensure model saving happens inside worker functions
   - **Check**: Verify files exist in `data/models/` after execution

## References

- **Archived Documentation**: `parallel_processing/graft-loss-parallel-processing/README.md` (comprehensive historical documentation)
- **Utility Functions**: `graft-loss/R/utils/parallel_utils.R` (roxygen documentation)
- **Main Implementation**: `graft-loss/scripts/04_fit_model.R` (inline comments)
- **Orchestration**: `graft-loss/scripts/run_three_datasets.R` (orchestration-level parallelism)

## Quick Reference

### Enable Parallel Processing

```bash
# Set environment variables
export MC_CV=1
export MC_SPLIT_WORKERS=8  # Optional: auto-detected if not set
export MC_WORKER_THREADS=1

# Run pipeline
Rscript scripts/run_pipeline.R
```

### Run Multiple Cohorts in Parallel

```bash
# Run orchestrator (launches 3 parallel processes)
Rscript scripts/run_three_datasets.R
```

### Check Parallel Configuration

```r
# In R console
source("graft-loss/R/utils/parallel_utils.R")
config <- setup_parallel_backend()
print(config)
# Output: list(backend = "multicore", workers = 8, utilization = 0.8)
```

