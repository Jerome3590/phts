# Development Rules & Lessons Learned

## Overview
This document captures critical lessons learned from the parallel processing implementation to prevent regression and repeated fixes.

## Critical Rules

### 1. Environment Variable Setting
**NEVER use `rlang` operators without loading `rlang`**

❌ **WRONG**:
```r
Sys.setenv(!!var_name := value)
```

✅ **CORRECT**:
```r
do.call(Sys.setenv, setNames(list(value), var_name))
```

**Files affected**: All parallel config files, model_utils.R
**Reason**: `!!` and `:=` are `rlang` operators that cause "could not find function" errors

### 2. OpenMP Thread Configuration
**NEVER set OMP_NUM_THREADS=0**

❌ **WRONG**:
```r
OMP_NUM_THREADS = "0"  # Causes libgomp error
```

✅ **CORRECT**:
```r
# For OpenMP, use positive integer (1 if auto-detect desired)
omp_threads <- if (num_threads == 0) 1 else num_threads
OMP_NUM_THREADS = as.character(omp_threads)
```

**Files affected**: All parallel config files, config.R
**Reason**: OpenMP requires positive integers, not 0

### 3. Logging Architecture
**NEVER mix sink() and direct file writing**

❌ **WRONG**:
```r
sink(log_conn)  # Redirects all output
cat("message", file = early_log_file, append = TRUE)  # Direct file write
```

✅ **CORRECT**:
```r
sink(log_conn)  # Redirects all output
cat("message")  # Goes through sink()
```

**Files affected**: scripts/04_fit_model.R
**Reason**: Creates connection conflicts and "cannot open connection" errors

### 4. Function Availability in Parallel Workers
**ALWAYS include functions in furrr globals**

❌ **WRONG**:
```r
furrr::furrr_options(globals = list(data = data))
```

✅ **CORRECT**:
```r
furrr::furrr_options(
  globals = list(
    data = data,
    configure_aorsf_parallel = configure_aorsf_parallel,
    configure_ranger_parallel = configure_ranger_parallel,
    configure_xgboost_parallel = configure_xgboost_parallel,
    # ... all functions used in workers
  )
)
```

**Files affected**: scripts/04_fit_model.R, R/utils/model_utils.R
**Reason**: Workers can't access functions not in globals

### 4a. Scoping and Function Passing Rules
**CRITICAL: Workers run in isolated environments**

❌ **WRONG**:
```r
# Function defined in main session
my_function <- function(x) x * 2

# Worker tries to use it without globals
furrr::future_map(data, function(item) {
  my_function(item)  # ERROR: could not find function "my_function"
})
```

✅ **CORRECT**:
```r
# Function defined in main session
my_function <- function(x) x * 2

# Include in globals
furrr::future_map(data, function(item) {
  my_function(item)  # Works!
}, .options = furrr::furrr_options(
  globals = list(my_function = my_function)
))
```

**Alternative - Source in Worker**:
```r
furrr::future_map(data, function(item) {
  source("R/my_functions.R")  # Load functions in worker
  my_function(item)  # Now works
})
```

**Complete Globals Checklist**:
```r
furrr::furrr_options(
  globals = list(
    # Data objects
    final_data = final_data,
    original_vars = original_vars,
    
    # Configuration functions
    configure_aorsf_parallel = configure_aorsf_parallel,
    configure_ranger_parallel = configure_ranger_parallel,
    configure_xgboost_parallel = configure_xgboost_parallel,
    
    # Wrapper functions
    aorsf_parallel = aorsf_parallel,
    predict_aorsf_parallel = predict_aorsf_parallel,
    ranger_parallel = ranger_parallel,
    predict_ranger_parallel = predict_ranger_parallel,
    xgboost_parallel = xgboost_parallel,
    predict_xgboost_parallel = predict_xgboost_parallel,
    
    # Helper functions
    get_aorsf_params = get_aorsf_params,
    get_xgboost_params = get_xgboost_params,
    sgb_fit = sgb_fit,
    sgb_data = sgb_data,
    orsf = orsf,
    
    # Core model functions
    fit_orsf = fit_orsf,
    fit_rsf = fit_rsf,
    fit_xgb = fit_xgb,
    fit_cph = fit_cph,
    
    # Utility functions
    compute_model_performance = compute_model_performance,
    compute_feature_importance_batch = compute_feature_importance_batch,
    make_recipe = make_recipe,
    cindex = cindex,
    cindex_uno = cindex_uno,
    
    # Variables
    threads_per_worker = threads_per_worker,
    horizon = horizon,
    use_global_xgb = use_global_xgb,
    encoded_df = encoded_df,
    encoded_vars = encoded_vars
  )
)
```

### 5. Thread Allocation Strategy
**NEVER exceed total cores with parallel workers**

❌ **WRONG**:
```r
# 3 workers × 25 threads = 75 threads on 32-core system
workers = 3
threads_per_worker = 25  # Competition!
```

✅ **CORRECT**:
```r
# 3 workers × 8 threads = 24 threads on 32-core system
workers = 3
threads_per_worker = 8  # Conservative allocation
```

**Files affected**: scripts/04_fit_model.R
**Reason**: Prevents thread competition and poor performance

### 6. File Sourcing Order
**ALWAYS source files before logging setup**

❌ **WRONG**:
```r
sink(log_conn)  # Logging active
source("config.R")  # May cause connection conflicts
```

✅ **CORRECT**:
```r
source("config.R")  # Source first
sink(log_conn)  # Then enable logging
```

**Files affected**: scripts/04_fit_model.R
**Reason**: Prevents connection conflicts during sourcing

### 7. Duplicate Function Definitions
**NEVER define the same function in multiple files**

❌ **WRONG**:
```r
# In model_utils.R
configure_aorsf_parallel <- function(...) { ... }

# In aorsf_parallel_config.R  
configure_aorsf_parallel <- function(...) { ... }  # Duplicate!
```

✅ **CORRECT**:
```r
# Only in aorsf_parallel_config.R
configure_aorsf_parallel <- function(...) { ... }

# In model_utils.R - just use the function
```

**Files affected**: R/utils/model_utils.R
**Reason**: Causes function conflicts and "no model fitted" errors

### 8. Package Parameter Validation
**ALWAYS verify parameter names match current package versions**

❌ **WRONG**:
```r
# Using outdated parameter names
params <- list(
  min_obs_in_leaf_node = 5,        # OLD: doesn't exist
  min_obs_to_split_node = 10,      # OLD: doesn't exist  
  oob_honest = TRUE,               # OLD: doesn't exist
  compute_oob_predictions = TRUE   # OLD: doesn't exist
)
```

✅ **CORRECT**:
```r
# Using current parameter names
params <- list(
  n_split = 10,                    # NEW: correct parameter
  oobag_fun = NULL,               # NEW: correct parameter
  sample_fraction = 1.0           # NEW: correct parameter
)
```

**Files affected**: R/aorsf_parallel_config.R, R/ranger_parallel_config.R, R/xgboost_parallel_config.R
**Reason**: Package APIs change between versions, causing "unrecognized arguments" errors

**Common Parameter Changes**:
- aorsf: `min_obs_in_leaf_node` → `n_split`
- aorsf: `oob_honest` → `oobag_fun`
- aorsf: `compute_oob_predictions` → `sample_fraction`
- ranger: `num.trees` → `num.trees` (stable)
- xgboost: `nrounds` → `nrounds` (stable)

**Critical Parameter Values**:
- aorsf: `sample_fraction = 1.0` → causes OOB error, use `0.8` instead
- aorsf: OOB predictions require `sample_fraction < 1` or `oobag_pred_type = 'none'`

**Prevention**:
1. Check package documentation before using parameters
2. Test parameter names with minimal examples
3. Use `args(package::function)` to verify parameters
4. Update parameter mappings when packages update

### 9. Function Scoping in Parallel Workers
**ALWAYS source functions before setting up globals for parallel workers**

❌ **WRONG**:
```r
# Set up globals with old function versions
globals = list(fit_rsf = fit_rsf)  # Old version without use_parallel
# Workers load new version with use_parallel
# Gets "unused argument" errors
```

✅ **CORRECT**:
```r
# Source latest functions before setting globals
source("R/fit_rsf.R")  # Load updated version
globals = list(fit_rsf = fit_rsf)  # Now captures updated version
```

**Root Cause**: Globals capture function at definition time, not execution time
**Files affected**: R/utils/model_utils.R (MC-CV section)
**Solution**: Source functions before setting up furrr globals

### 10. EC2 Package Version Mismatches
**EC2 may have different package versions with different parameter names**

❌ **WRONG**:
```r
# Local: ranger:::predict.ranger(object, data = newdata)
# EC2: ranger package expects new_data parameter
# Gets "newdata is unrecognized - did you mean new_data?" error
```

✅ **CORRECT**:
```r
# Use backward compatible approach
ptemp <- tryCatch({
  ranger:::predict.ranger(object, new_data = newdata, ...)
}, error = function(e) {
  # Fallback for older versions
  ranger:::predict.ranger(object, data = newdata, ...)
})
```

**Common parameter changes**:
- `ranger`: `data` → `new_data` in predict.ranger
- `aorsf`: `min_obs_in_leaf_node` → `n_split`
- `aorsf`: `oob_honest` → `oobag_fun`

**Prevention**:
1. Test on EC2 after package updates
2. Use parameter names from latest package versions
3. Document parameter changes in development rules

### 11. R Version Compatibility Issues
**RDS files created with newer R versions can't be read by older versions**

❌ **WRONG**:
```r
# Create file locally with R 4.3.0
saveRDS(data, "file.rds")
# Try to read on EC2 with R 4.1.0
data <- readRDS("file.rds")  # Error: unknown type 0
```

✅ **CORRECT**:
```r
# Add fallback for R version mismatch
tryCatch({
  data <- readRDS("file.rds")
}, error = function(e) {
  # Recreate data if R version mismatch
  data <- create_data_fallback()
})
```

**Common issues**:
- `resamples.rds` created with newer R version
- `final_data.rds` compatibility issues
- `final_features.rds` version conflicts

**Prevention**:
1. Use `tryCatch` around all `readRDS` calls
2. Provide fallback data creation methods
3. Document R version requirements

### 12. Unified Logging System
**ALWAYS use the unified orch_bg_ logging system for all pipeline steps**

❌ **WRONG**:
```r
# Create individual log files per step
log_file <- file.path("logs", "models", cohort_name, "orchestrator.log")
log_file <- file.path("logs", "step04", "model_fitting.log")
```

✅ **CORRECT**:
```r
# Use unified orch_bg_ logging system (matches all pipeline steps)
log_file <- switch(Sys.getenv("DATASET_COHORT", unset = ""),
  original = "logs/orch_bg_original_study.log",
  full_with_covid = "logs/orch_bg_full_with_covid.log",
  full_without_covid = "logs/orch_bg_full_without_covid.log",
  "logs/orch_bg_unknown.log"
)
```

**Unified Log Files**:
- `logs/orch_bg_original_study.log` - Original cohort
- `logs/orch_bg_full_with_covid.log` - Full with COVID cohort
- `logs/orch_bg_full_without_covid.log` - Full without COVID cohort

**Consistent Format**:
```r
cat(sprintf("\n[%s] Starting %s script\n", script_name, step_name))
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
cat("Log file path: ", log_file, "\n")
cat(sprintf("[Diagnostic] Cores available: %d\n", future::availableCores()))
cat("[%s] Diagnostic output complete\n\n", script_name)
```

**Files using unified logging**: 01_prepare_data.R, 02_resampling.R, 03_prep_model_data.R, 04_fit_model.R, 05_generate_outputs.R

**Function Availability Tracking**:
- Individual model logs include `[FUNCTION_DIAG]` sections
- Tracks required vs available functions in worker sessions
- Identifies missing functions that could cause failures
- Helps debug scoping issues in parallel workers

**Example log output**:
```
[FUNCTION_DIAG] Checking function availability for ORSF model...
[FUNCTION_DIAG] Required functions: fit_orsf, configure_aorsf_parallel, get_aorsf_params, orsf, aorsf_parallel, predict_aorsf_parallel
[FUNCTION_DIAG] Available functions: fit_orsf, configure_aorsf_parallel, get_aorsf_params, orsf
[FUNCTION_DIAG] Missing functions: aorsf_parallel, predict_aorsf_parallel
[FUNCTION_DIAG] WARNING: 2 functions missing - model fitting may fail!
```

### 13. Parameter Name Consistency
**ALWAYS ensure parameter name consistency between function calls**

❌ **WRONG**:
```r
# select_rsf uses dot notation
select_rsf(trn = data, n_predictors = 10, num.trees = 500, min.node.size = 20)

# But ranger_parallel expects underscore notation
ranger_parallel(formula, data, config, num.trees = 500, min.node.size = 20)  # Error!
```

✅ **CORRECT**:
```r
# Convert parameter names in wrapper functions
ranger_parallel <- function(formula, data, config, ...) {
  dots <- list(...)
  
  # Map dot-notation to underscore notation
  if (!is.null(dots$num.trees)) dots$num_trees <- dots$num.trees
  if (!is.null(dots$min.node.size)) dots$min_node_size <- dots$min.node.size
  if (!is.null(dots$num.random.splits)) dots$num_random_splits <- dots$num.random.splits
  if (!is.null(dots$write.forest)) dots$write_forest <- dots$write.forest
  
  # Remove dot-notation parameters
  dots <- dots[!names(dots) %in% c("num.trees", "min.node.size", "num.random.splits", "write.forest")]
  
  # Get optimal parameters
  params <- do.call(get_ranger_params, c(list(config = config), dots))
  # ...
}
```

**Files affected**: ranger_parallel_config.R, select_rsf.R, make_final_features.R
**Reason**: Parameter name mismatches cause "unused arguments" errors

### 14. EC2 File Synchronization
**ALWAYS sync local changes to EC2 before testing**

❌ **WRONG**:
```r
# Make local changes to R/fit_rsf.R
# Run on EC2 without uploading
# Gets "unused argument" errors
```

✅ **CORRECT**:
```r
# Make local changes to R/fit_rsf.R
# Upload to EC2: scp R/fit_rsf.R ec2:/path/to/R/fit_rsf.R
# Then run on EC2
```

**Files affected**: All R files, especially R/fit_*.R, R/*_parallel_config.R
**Reason**: EC2 runs old versions of files, causing signature mismatches

**Workaround**:
- Use default parameter values instead of explicit parameters
- Make functions backward compatible with old signatures
- Document which files need to be synced after changes

## File-Specific Rules

### scripts/04_fit_model.R
- Source parallel config files BEFORE logging setup
- Use conservative threading (8 threads per worker)
- Include all functions in furrr globals
- Use sink() for all logging, no direct file writes

### R/utils/model_utils.R
- NO duplicate parallel processing functions
- Only general utility functions
- Include all required functions in furrr globals

### Parallel Config Files (R/*_parallel_config.R)
- Use `do.call(Sys.setenv, setNames(...))` for environment variables
- Set OMP_NUM_THREADS to positive integers only
- Handle auto-detection with fallback to 1

### scripts/config.R
- Set OMP_NUM_THREADS to positive integers
- Use conservative thread allocation

## Testing Checklist

Before deploying changes:
- [ ] No `:=` operators without `rlang`
- [ ] No `OMP_NUM_THREADS=0`
- [ ] No mixing of sink() and direct file writes
- [ ] All worker functions in furrr globals
- [ ] Thread allocation doesn't exceed cores
- [ ] No duplicate function definitions
- [ ] Source files before logging setup
- [ ] Package parameters match current API versions
- [ ] Test parameter names with minimal examples

## Common Error Patterns

| Error | Cause | Fix |
|-------|-------|-----|
| `could not find function ":="` | rlang operator without rlang | Use `do.call(Sys.setenv, setNames(...))` |
| `libgomp: Invalid value for OMP_NUM_THREADS: 0` | OpenMP gets 0 | Set to positive integer |
| `cannot open the connection` | Mixed logging approaches | Use only sink() |
| `could not find function "configure_*_parallel"` | Missing from globals | Add to furrr globals |
| `no model fitted` | Duplicate functions | Remove duplicates |
| `unused argument (use_parallel = TRUE)` | Missing wrapper functions | Add to globals |
| `could not find function "my_function"` | Function not in globals | Add to furrr globals |
| `object 'xgb_full_flag' not found` | Variable not in globals | Add to furrr globals |
| `unused argument (check_r_functions = TRUE)` | Function not available in worker | Add to globals or source in worker |
| `unrecognized arguments: min_obs_in_leaf_node` | Outdated parameter names | Update to current package API |
| `unrecognized arguments: oob_honest` | Outdated parameter names | Update to current package API |
| `cannot compute out-of-bag predictions` | sample_fraction = 1.0 | Use sample_fraction < 1 or oobag_pred_type = 'none' |

## Scoping-Specific Error Patterns

| Error | Cause | Fix |
|-------|-------|-----|
| `could not find function "fit_orsf"` | Model function not in globals | Add `fit_orsf = fit_orsf` to globals |
| `could not find function "configure_aorsf_parallel"` | Config function not in globals | Add to globals |
| `object 'threads_per_worker' not found` | Variable not in globals | Add to globals |
| `could not find function "sgb_fit"` | Helper function not in globals | Add to globals |
| `unused argument (use_parallel = TRUE)` | Wrapper function not in globals | Add wrapper functions to globals |

## Debugging Scoping Issues

### Quick Debugging Steps

1. **Check if function exists in worker**:
```r
furrr::future_map(data, function(item) {
  cat("Available functions:", ls(), "\n")
  cat("Function exists:", exists("my_function"), "\n")
})
```

2. **Test function availability**:
```r
furrr::future_map(data, function(item) {
  tryCatch({
    my_function(item)
  }, error = function(e) {
    cat("Error:", e$message, "\n")
    cat("Available:", ls(), "\n")
  })
})
```

3. **Verify globals are passed**:
```r
furrr::future_map(data, function(item) {
  cat("Globals available:", names(environment()), "\n")
})
```

### Common Scoping Mistakes

1. **Forgetting to add new functions to globals**
2. **Adding functions but not variables**
3. **Adding functions but not their dependencies**
4. **Using `source()` in workers without error handling**
5. **Assuming functions are available from packages**

### Best Practices

1. **Always test worker functions locally first**
2. **Use `exists()` checks in workers**
3. **Include all dependencies in globals**
4. **Document which functions need to be in globals**
5. **Use consistent naming for globals lists**

## Prevention Strategy

1. **Code Review**: Check for these patterns before merging
2. **Automated Testing**: Add tests for these specific issues
3. **Documentation**: Keep this file updated with new lessons
4. **Consistency**: Apply fixes across all similar code patterns
5. **Scoping Checklist**: Verify all worker functions are in globals

## Current Configuration Status

### Working Components ✅
- Parallel config functions loading successfully
- OpenMP thread configuration fixed
- Conservative threading (8 threads per worker) implemented
- Logging architecture working
- File sourcing order correct

### Current Issues 🔧
- File synchronization: Local changes not automatically synced to EC2
- Function signature mismatches between local and EC2 versions
- Need to upload updated R files to EC2 after local changes

### Environment Variables Set
```
R_RANGER_NUM_THREADS = 0
OMP_NUM_THREADS = 1
MKL_NUM_THREADS = 1
OPENBLAS_NUM_THREADS = 1
VECLIB_MAXIMUM_THREADS = 1
NUMEXPR_NUM_THREADS = 1
```

## 14. CPH Model Implementation Rules

### CPH-Specific Considerations
**CPH (Cox Proportional Hazards) models are fundamentally different from tree-based models**

#### No Parallel Processing
- **CPH is single-threaded by design** - no internal parallelization
- **No configuration functions needed** - unlike ORSF, RSF, XGBoost
- **No environment variables** - not applicable
- **Fast execution** - typically 1-10 seconds, not minutes

#### Implementation Pattern
```r
# CPH model fitting (no parallel processing)
} else if (task$fit_func == "fit_cph") {
  # Set up CPH-specific performance monitoring (no parallel processing)
  monitor_info <- setup_cph_performance_monitoring(log_dir = log_dir)
  
  try(cat(sprintf('[PERF_MONITOR] CPH model - no parallel processing monitoring needed\n'), 
          file = model_log, append = TRUE), silent = TRUE)
  
  model_result <- fit_cph(trn = final_data, vars = original_vars, tst = NULL)
}
```

#### Required Parameters
- **Always pass `tst = NULL`** for final model fitting
- **Use `original_vars`** (not encoded variables)
- **No parallel processing flags** - not applicable

#### Performance Monitoring
- **Monitor fitting time** - typically very fast
- **Monitor memory usage** - usually low
- **No thread monitoring** - single-threaded
- **Log "no parallel processing needed"** message

#### Error Patterns
| Error | Cause | Solution |
|-------|-------|----------|
| `could not find function "fit_cph"` | Missing from globals | Add `fit_cph = fit_cph` to globals |
| `unused argument (tst = NULL)` | Function signature mismatch | Check `fit_cph` function definition |
| `object 'fit_cph' not found` | Missing source call | Add `source(here::here("R", "fit_cph.R"))` |

#### Testing Checklist
- [ ] CPH model appears in MC-CV processing
- [ ] CPH split models are saved (`CPH_split001.rds`, etc.)
- [ ] CPH final model is saved (`model_cph.rds`)
- [ ] CPH appears in model comparison metrics
- [ ] CPH can be used for partial dependence plots
- [ ] Performance monitoring logs correctly
- [ ] No parallel processing errors

#### Documentation Files
- `CPH_PARALLEL_SETUP.md` - Complete setup documentation
- `MODEL_IMPLEMENTATION_CHECKLIST.md` - CPH implementation checklist
- `README.md` - Updated model list
- `DEVELOPMENT_RULES.md` - This section

## Last Updated
2025-01-02 - Initial creation based on parallel processing implementation
2025-01-03 - Added CPH model implementation rules
