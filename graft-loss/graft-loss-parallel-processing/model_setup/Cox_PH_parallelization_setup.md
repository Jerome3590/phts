# CPH (Cox Proportional Hazards) Parallel Processing Setup

## Overview

This document outlines the parallel processing configuration for CPH (Cox Proportional Hazards) models in our survival analysis pipeline. Unlike ORSF, RSF, and XGBoost, CPH models do not have built-in parallel processing capabilities, but we maintain consistent configuration patterns for monitoring and integration.

## CPH Model Characteristics

### No Built-in Parallelization
- **CPH models** (Cox Proportional Hazards) are **semi-parametric regression models**
- **No internal parallelization** - they use standard maximum likelihood estimation
- **Single-threaded execution** by design
- **Fast fitting** - typically completes in seconds, not minutes

### Performance Profile
- **Fitting time**: 1-10 seconds (very fast)
- **Memory usage**: Low (linear in sample size)
- **CPU usage**: Single-threaded
- **Scalability**: Excellent for large datasets

## Configuration Functions

### `configure_cph_parallel()`

```r
configure_cph_parallel <- function(use_all_cores = TRUE, 
                                  n_thread = NULL, 
                                  target_utilization = 0.8,
                                  check_r_functions = TRUE,
                                  verbose = FALSE) {
  # CPH models are single-threaded by design
  config <- list(
    model_type = "CPH",
    n_thread = 1,  # Always single-threaded
    use_all_cores = FALSE,  # Not applicable
    target_utilization = NA,  # Not applicable
    check_r_functions = FALSE,  # Not applicable
    parallel_enabled = FALSE,  # CPH is inherently single-threaded
    timestamp = Sys.time()
  )
  
  if (verbose) {
    message("=== CPH Parallel Configuration ===")
    message("Available cores: ", parallel::detectCores())
    message("CPH threads: 1 (single-threaded by design)")
    message("Target utilization: N/A")
    message("Parallel processing: disabled (CPH is inherently single-threaded)")
    message("=====================================")
  }
  
  return(config)
}
```

**Purpose**: Provides consistent configuration interface for CPH models
**Parameters**:
- `use_all_cores`: Not applicable for CPH (ignored)
- `n_thread`: Not applicable for CPH (always 1)
- `target_utilization`: Not applicable for CPH (ignored)
- `check_r_functions`: Not applicable for CPH (ignored)
- `verbose`: Whether to print configuration details
**Returns**: CPH configuration (minimal, for consistency)

### `setup_cph_performance_monitoring()`

```r
setup_cph_performance_monitoring <- function(log_dir) {
  performance_log <- file.path(log_dir, 'CPH_performance.log')
  
  # Create performance log file
  if (!dir.exists(log_dir)) {
    dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
  }
  
  list(
    model_type = "CPH",
    performance_log = performance_log,
    interval = NA,  # No monitoring needed
    monitoring_active = FALSE  # CPH doesn't have parallel processing
  )
}
```

**Purpose**: Sets up performance monitoring infrastructure for CPH models
**Parameters**:
- `log_dir`: Directory for performance logs
**Returns**: Monitoring configuration (minimal for CPH)

### `log_performance_summary()` (Generic)

```r
log_performance_summary <- function(model_type, elapsed_time, memory_before, memory_after, 
                                   threads_used, performance_log, model_log) {
  # ... implementation handles CPH along with other models
}
```

**Purpose**: Logs performance summary for CPH models
**Note**: `threads_used` will be 1 for CPH models

## Integration Points

### 1. Model Fitting (`scripts/04_fit_model.R`)

```r
} else if (task$fit_func == "fit_cph") {
  # Set up CPH-specific performance monitoring (no parallel processing)
  monitor_info <- setup_cph_performance_monitoring(log_dir = log_dir)
  
  try(cat(sprintf('[PERF_MONITOR] CPH model - no parallel processing monitoring needed\n'), 
          file = model_log, append = TRUE), silent = TRUE)
  
  model_result <- fit_cph(trn = final_data, vars = original_vars, tst = NULL)
}
```

### 2. MC-CV Processing (`R/utils/model_utils.R`)

```r
} else if (model_type == "CPH") {
  cat(sprintf('[DEBUG] CPH fitting - data dimensions: %d rows, %d vars\n', nrow(trn_df), length(vars_native)), file = model_log, append = TRUE)
  
  # CRITICAL: Log process state before CPH fitting
  tryCatch({
    if (exists("log_process_info", mode = "function")) {
      log_process_info(model_log, "[PROCESS_PRE_CPH]", include_children = TRUE, include_system = TRUE)
    }
  }, error = function(e) NULL)
  
  tryCatch({
    fitted_model <- fit_cph(trn = trn_df, vars = vars_native, tst = NULL)
    cat(sprintf('[DEBUG] CPH fitting - returned object of class: %s\n', paste(class(fitted_model), collapse = ", ")), file = model_log, append = TRUE)
    
    # CRITICAL: Log process state after CPH fitting
    tryCatch({
      if (exists("log_process_info", mode = "function")) {
        log_process_info(model_log, "[PROCESS_POST_CPH]", include_children = True, include_system = TRUE)
      }
    }, error = function(e) NULL)
  }, error = function(e) {
    cat(sprintf('[ERROR] CPH fitting failed: %s\n', e$message), file = model_log, append = TRUE)
    fitted_model <<- NULL
  })
}
```

### 3. Model Comparison (`scripts/05_generate_outputs.R`)

```r
} else if (mname %in% c('CPH')) {
  mdl <- readRDS(mfile)
  horizon <- 1
  score <- tryCatch({
    # CPH models use predict() with type='risk'
    risk_scores <- predict(mdl, newdata = te[, c('time','status', final_features$variables), drop = FALSE], type='risk')
    # Convert to survival probability at horizon
    1 - exp(-risk_scores * horizon)
  }, error = function(e) {
    # Fallback: use linear predictor
    suppressWarnings(as.numeric(predict(mdl, newdata = te[, c('time','status', final_features$variables), drop = FALSE])))
  })
  rows[[length(rows)+1]] <- data.frame(model=mname, cindex=cindex(te$time, te$status, as.numeric(score)))
}
```

## Performance Monitoring

### What We Monitor
- **Fitting time**: Elapsed time for model fitting
- **Memory usage**: Before and after fitting
- **Model size**: Object size after fitting
- **Success/failure**: Error handling and logging

### What We Don't Monitor
- **Thread usage**: CPH is single-threaded
- **CPU utilization**: Not applicable
- **Parallel efficiency**: Not applicable

### Log Output Example

```
[PERF_MONITOR] CPH model - no parallel processing monitoring needed
[WORKER] Starting CPH model fitting
[WORKER] Memory before fitting: 245.2 MB
[WORKER] Model fitting started at: 2025-10-03 12:45:30
[WORKER] Fitting CPH model with 21 variables on 5835 rows
[WORKER] Model fitting completed at: 2025-10-03 12:45:32 (0.03 minutes)
[WORKER] Memory after fitting: 245.8 MB (delta: 0.6 MB)
[WORKER] ✓ Model saved successfully: model_cph.rds
[WORKER]   File size: 0.12 MB
[WORKER]   Save time: 0.01 seconds
```

## Environment Variables

### CPH-Specific Variables
- **`CPH_TIMEOUT_MINUTES=5`**: Timeout for CPH model fitting (default: 5 minutes)
  - CPH models should complete in seconds, not minutes
  - This timeout prevents infinite loops in `safe_coxph` when handling problematic data
  - Can be increased if legitimate models need more time

### No Threading Variables
Unlike other models, CPH doesn't require thread configuration:
- **No `CPH_NTHREAD`** - not applicable (single-threaded)
- **No `OMP_NUM_THREADS`** - not used by CPH
- **No parallel backend** - single-threaded execution

### Standard Variables
- `DATASET_COHORT`: Cohort identifier
- `MC_CV`: Enable/disable MC-CV mode
- `MC_TIMES`: Number of MC-CV splits

## File Structure

### Model Files
```
models/{cohort}/
├── model_cph.rds              # Final CPH model
├── CPH_split001.rds           # MC-CV split models
├── CPH_split002.rds
├── ...
└── CPH_split020.rds
```

### Log Files
```
logs/models/{cohort}/full/
├── CPH_final.log              # Final model fitting log
├── CPH_performance.log        # Performance monitoring log
└── CPH_split001.log           # MC-CV split logs
```

## Usage Examples

### Basic CPH Fitting

```r
# Load data
final_data <- readRDS('model_data/final_data.rds')
original_vars <- c('age_txpl', 'sex', 'race', 'prim_dx', 'txbun_r')

# Fit CPH model
cph_model <- fit_cph(trn = final_data, vars = original_vars, tst = NULL)

# Save model
saveRDS(cph_model, 'models/original/model_cph.rds')
```

### Performance Monitoring

```r
# Set up monitoring
monitor_info <- setup_cph_performance_monitoring(log_dir = 'logs/models/original/full')

# Log performance summary
log_performance_summary(
  model_type = "CPH",
  elapsed_time = 0.5,  # minutes
  memory_before = 245.2,
  memory_after = 245.8,
  threads_used = 1,    # Always 1 for CPH
  performance_log = monitor_info$performance_log,
  model_log = "logs/models/original/full/CPH_final.log"
)
```

## Troubleshooting

### Common Issues

1. **Function not found**: Ensure `fit_cph` is in globals
2. **Missing tst parameter**: Always pass `tst = NULL` for final models
3. **Memory issues**: Rare for CPH due to low memory usage
4. **Slow fitting**: Check data quality and variable selection

### Debug Commands

```r
# Check function availability
exists("fit_cph", mode = "function")

# Check model class
class(fitted_model)

# Check memory usage
gc()

# Check log files
list.files("logs/models/original/full/", pattern = "CPH")
```

## Integration Checklist

- [x] **Model fitting logic** in `scripts/04_fit_model.R`
- [x] **MC-CV processing** in `R/utils/model_utils.R`
- [x] **Performance monitoring** functions
- [x] **Model comparison** in `scripts/05_generate_outputs.R`
- [x] **Completion checking** in `scripts/04_check_completion.R`
- [x] **Globals configuration** for parallel workers
- [x] **Source calls** for function loading
- [x] **Error handling** and logging
- [x] **File structure** consistency

## Notes

- **CPH is the baseline model** - fastest and most interpretable
- **No parallelization needed** - already optimal performance
- **Consistent interface** - follows same patterns as other models
- **Reliable fallback** - rarely fails due to simplicity
- **Clinical interpretability** - coefficients have direct meaning

## Related Documentation

- [DEVELOPMENT_RULES.md](DEVELOPMENT_RULES.md) - Development guidelines
- [MODEL_IMPLEMENTATION_CHECKLIST.md](MODEL_IMPLEMENTATION_CHECKLIST.md) - Implementation checklist
- [README.md](README.md) - Project overview
- [AORSF_PARALLEL_SETUP.md](AORSF_PARALLEL_SETUP.md) - ORSF parallel setup
- [RANGER_PARALLEL_SETUP.md](RANGER_PARALLEL_SETUP.md) - Ranger parallel setup
- [XGBOOST_PARALLEL_SETUP.md](XGBOOST_PARALLEL_SETUP.md) - XGBoost parallel setup
