# Model Worker Session Implementation Checklist

This checklist ensures consistent and complete implementation of models in parallel worker sessions. Use this as a template for each model type.

## Baseline: AORSF Implementation

## CPH Implementation (Reference: No Parallel Processing)

### ✅ 1. Model Task Definition
- [ ] Add model to `model_tasks` list in `scripts/04_fit_model.R`
- [ ] Define model name and fit function: `list(model = "AORSF", fit_func = "fit_aorsf")`
- [ ] Update progress messages to include new model
- [ ] Update worker count if needed (max 4 workers for 4 models)

### ✅ 2. Required Packages
- [ ] Add to `packages` list in `furrr::furrr_options()`
- [ ] AORSF: `"aorsf"` (already included)
- [ ] Verify package is loaded in worker session
- [ ] Check for any additional dependencies

### ✅ 3. Parallel Processing Configuration
- [ ] Model-specific configuration function: `configure_aorsf_parallel()`
- [ ] Conservative threading: `use_all_cores = FALSE, n_thread = threads_per_worker`
- [ ] Environment variables: `OMP_NUM_THREADS`, `MKL_NUM_THREADS`, etc.
- [ ] Model-specific parameters: `check_r_functions = TRUE` for AORSF

### ✅ 4. Performance Monitoring Setup
- [ ] Model-specific monitoring function: `setup_aorsf_performance_monitoring()`
- [ ] Performance log file: `{MODEL}_performance.log`
- [ ] Monitoring interval: 5 seconds
- [ ] Log monitoring status to main model log

### ✅ 5. Data Requirements
- [ ] Data source: `final_data` (original variables)
- [ ] Variable source: `original_vars` (not encoded)
- [ ] Data validation: Check data exists and has required columns
- [ ] Special requirements: None for AORSF

### ✅ 6. Model Fitting Function
- [ ] Function call: `fit_aorsf(trn = final_data, vars = original_vars, use_parallel = TRUE, check_r_functions = TRUE)`
- [ ] Parallel processing enabled: `use_parallel = TRUE`
- [ ] Model-specific parameters: `check_r_functions = TRUE` for AORSF
- [ ] Error handling: Wrapped in tryCatch

### ✅ 7. Model Saving Logic
- [ ] Model path: `file.path(models_dir, 'model_aorsf.rds')`
- [ ] Metadata logging: Class, type, object size
- [ ] File logging: Log to model log file
- [ ] Error handling: Check if save was successful

### ✅ 8. Required Functions in Globals
- [ ] Configuration function: `configure_aorsf_parallel`
- [ ] Fitting function: `fit_aorsf`
- [ ] Parallel wrapper: `aorsf_parallel`
- [ ] Prediction wrapper: `predict_aorsf_parallel`
- [ ] Helper functions: `get_aorsf_params`, `orsf`
- [ ] Performance monitoring: `monitor_aorsf_performance`, `benchmark_aorsf_threads`

### ✅ 9. Logging Implementation
- [ ] Main model log: `{MODEL}_final.log`
- [ ] Performance log: `{MODEL}_performance.log`
- [ ] Log directory: `logs/models/{cohort}/full/`
- [ ] Log tags: `[WORKER]`, `[PERF_MONITOR]`, `[PERF_SUMMARY]`
- [ ] Function availability tracking: `[FUNCTION_DIAG]`

### ✅ 10. Error Handling
- [ ] Model fitting errors: Wrapped in tryCatch
- [ ] Data loading errors: Check file existence
- [ ] Configuration errors: Graceful fallback
- [ ] Performance monitoring errors: Silent failure

---

## CPH Implementation (Reference: No Parallel Processing)

### ✅ 1. Model Task Definition
- [x] Add model to `model_tasks` list in `scripts/04_fit_model.R`
- [x] Define model name and fit function: `list(model = "CPH", fit_func = "fit_cph")`
- [x] Update progress messages to include new model
- [x] Update worker count: 4 workers for 4 models (ORSF, RSF, XGB, CPH)

### ✅ 2. Required Packages
- [x] Add to `packages` list in `furrr::furrr_options()`: `"survival"` (already included)
- [x] Verify package is loaded in worker session
- [x] Check for any additional dependencies: `riskRegression` for C-index

### ✅ 3. Parallel Processing Configuration
- [x] **No parallel processing** - CPH is single-threaded by design
- [x] **No configuration function** - not needed for CPH
- [x] **No environment variables** - not applicable
- [x] **No threading parameters** - single-threaded execution

### ✅ 4. Performance Monitoring Setup
- [x] Model-specific monitoring function: `setup_cph_performance_monitoring()`
- [x] Performance log file: `CPH_performance.log`
- [x] **No monitoring interval** - not needed for fast CPH fitting
- [x] Log monitoring status: "CPH model - no parallel processing monitoring needed"

### ✅ 5. Data Requirements
- [x] Data source: `final_data` (original variables)
- [x] Variable source: `original_vars` (not encoded)
- [x] Data validation: Check data exists and has required columns
- [x] Special requirements: None for CPH

### ✅ 6. Model Fitting Function
- [x] Function call: `fit_cph(trn = final_data, vars = original_vars, tst = NULL)`
- [x] **No parallel processing** - single-threaded execution
- [x] Model-specific parameters: `tst = NULL` for final models
- [x] Error handling: Wrapped in tryCatch

### ✅ 7. Model Saving Logic
- [x] Model path: `file.path(models_dir, 'model_cph.rds')`
- [x] Metadata logging: Class, type, object size
- [x] File logging: Log to model log file
- [x] Error handling: Check if save was successful

### ✅ 8. Required Functions in Globals
- [x] **No configuration function** - not needed for CPH
- [x] **No parallel wrapper functions** - not applicable
- [x] **No helper functions** - not needed
- [x] Model fitting function: `fit_cph`

### ✅ 9. MC-CV Integration
- [x] Add to `model_types` in `run_mc()`: `c("ORSF","RSF","XGB","CPH")`
- [x] Add model fitting logic: `else if (model_type == "CPH")`
- [x] Add to globals in `run_mc()`: `fit_cph = fit_cph`
- [x] Add source call: `source(here::here("R", "fit_cph.R"))`

### ✅ 10. Model Comparison Integration
- [x] Add to supported models: `c('ORSF','RSF','XGB','CPH')`
- [x] Add prediction logic: Risk score calculation with `predict(..., type='risk')`
- [x] Add to partial dependence fallback: ORSF → RSF → CPH → fallback
- [x] Add C-index calculation: `cindex(te$time, te$status, as.numeric(score))`

### ✅ 11. Logging Setup
- [x] Model-specific log: `CPH_final.log`
- [x] Performance log: `CPH_performance.log`
- [x] Log directory: `logs/models/{cohort}/full/`
- [x] Log tags: `[WORKER]`, `[PERF_MONITOR]`, `[PERF_SUMMARY]`
- [x] Function availability tracking: `[FUNCTION_DIAG]`

### ✅ 12. Error Handling
- [x] Model fitting errors: Wrapped in tryCatch
- [x] Data loading errors: Check file existence
- [x] **No configuration errors** - not applicable
- [x] Performance monitoring errors: Silent failure

### ✅ 13. Completion Checking
- [x] Add to model counts: `cph_count <- length(grep("CPH_split", mc_models))`
- [x] Add to model breakdown: `ORSF: X, RSF: X, XGB: X, CPH: X`
- [x] Add to expected counts: Include CPH in incomplete warnings
- [x] Add to final model pattern: `model_(orsf|rsf|xgb|cph)`

### ✅ 14. Documentation
- [x] Create `CPH_PARALLEL_SETUP.md` - parallel setup documentation
- [x] Update `MODEL_IMPLEMENTATION_CHECKLIST.md` - add CPH section
- [x] Update `README.md` - add CPH to model list
- [x] Update `DEVELOPMENT_RULES.md` - add CPH-specific rules

---

## Template for New Models

### 1. Model Task Definition
- [ ] Add model to `model_tasks` list
- [ ] Define model name and fit function
- [ ] Update progress messages
- [ ] Update worker count if needed

### 2. Required Packages
- [ ] Add to `packages` list in `furrr::furrr_options()`
- [ ] Verify package is loaded in worker session
- [ ] Check for any additional dependencies

### 3. Parallel Processing Configuration
- [ ] Model-specific configuration function
- [ ] Conservative threading settings
- [ ] Environment variables
- [ ] Model-specific parameters

### 4. Performance Monitoring Setup
- [ ] Model-specific monitoring function
- [ ] Performance log file naming
- [ ] Monitoring interval
- [ ] Log monitoring status

### 5. Data Requirements
- [ ] Data source (original vs encoded)
- [ ] Variable source
- [ ] Data validation
- [ ] Special requirements (e.g., encoded data for XGBoost)

### 6. Model Fitting Function
- [ ] Function call with correct parameters
- [ ] Parallel processing enabled/disabled
- [ ] Model-specific parameters
- [ ] Error handling

### 7. Model Saving Logic
- [ ] Model path naming convention
- [ ] Metadata logging
- [ ] File logging
- [ ] Error handling

### 8. Required Functions in Globals
- [ ] Configuration function
- [ ] Fitting function
- [ ] Parallel wrapper functions
- [ ] Prediction wrapper functions
- [ ] Helper functions
- [ ] Performance monitoring functions

### 9. Logging Implementation
- [ ] Main model log naming
- [ ] Performance log naming
- [ ] Log directory structure
- [ ] Log tags and formatting
- [ ] Function availability tracking

### 10. Function Signature Validation
- [ ] **Critical function parameter validation**
- [ ] **Default parameter checking**
- [ ] **Function compatibility verification**
- [ ] **Parameter type validation**
- [ ] **Required vs optional parameter identification**

### 11. Process and Core Utilization Monitoring
- [ ] **Process monitoring at task start**: `[PROCESS_START_{MODEL}]` log entry
- [ ] **Pre-fitting monitoring**: `[PROCESS_PRE_{MODEL}]` before model fitting call
- [ ] **Post-fitting monitoring**: `[PROCESS_POST_{MODEL}]` after model fitting completion
- [ ] **Threading conflict detection**: Automatic detection and logging of conflicts
- [ ] **Resource utilization tracking**: CPU usage, memory, core assignments, thread counts
- [ ] **Background pipeline monitoring**: System-wide resource monitoring during execution
- [ ] **Process monitoring integration**: Source `R/utils/process_monitor.R` and call `log_process_info()`
- [ ] **Error handling**: Wrap monitoring calls in `tryCatch()` to prevent monitoring failures from breaking model fitting

### 12. MC-CV Data Quality Diagnostics
- [ ] **Initial data logging**: `[{MODEL}_INIT]` log entry with dataset dimensions
- [ ] **Event ratio checking**: Log events per predictor ratio (recommended: >10)
- [ ] **Variable quality screening**: Check for zero variance, single levels, small sample sizes
- [ ] **MC-CV specific issues**: Detect problems that arise from data splitting
- [ ] **Separation detection**: Identify perfect/quasi-separation in categorical variables
- [ ] **Cross-tabulation logging**: Log problematic variable × outcome relationships
- [ ] **Consistent logging format**: Use standardized format across all models (ORSF, RSF, XGB, CPH)
- [ ] **Issue categorization**: Classify issues as zero variance, single level, small levels, separation
- [ ] **Variable preservation**: Use `make_recipe_mc_cv()` to skip NZV filtering that can drop valid variables
- [ ] **Variable preservation logging**: Log original vs. post-recipe variable counts and any dropped variables

### 13. Error Handling
- [ ] Model fitting errors
- [ ] Data loading errors
- [ ] Configuration errors
- [ ] Performance monitoring errors
- [ ] **Function signature errors**
- [ ] **Process monitoring errors**

---

## Model-Specific Implementation Notes

### AORSF (Oblique Random Survival Forest)
- **Data**: `final_data` (original variables)
- **Parallel**: Yes, with `check_r_functions = TRUE`
- **Special**: R function limitation checking

### RSF (Random Survival Forest)
- **Data**: `final_data` (original variables)
- **Parallel**: Yes, with `memory_efficient = FALSE`
- **Special**: Uses ranger package

### XGBoost
- **Data**: `final_data_encoded.rds` (encoded variables)
- **Variables**: `final_features$terms` (encoded)
- **Parallel**: Yes, with `tree_method = 'auto'`
- **Special**: Requires encoded data, different data source

### CPH (Cox Proportional Hazards)
- **Data**: `final_data` (original variables)
- **Parallel**: No (single-threaded)
- **Special**: No parallel processing, basic monitoring only

---

## Validation Checklist

Before considering a model fully implemented:

- [ ] Model appears in `model_tasks` list
- [ ] Model has dedicated worker session logic
- [ ] All required functions are in `globals`
- [ ] Performance monitoring is configured
- [ ] Model saving logic is implemented
- [ ] Error handling is comprehensive
- [ ] Logging is consistent with other models
- [ ] Model-specific requirements are met
- [ ] No syntax errors in implementation
- [ ] Model can be fitted successfully in worker session

---

## Common Pitfalls to Avoid

1. **Missing Functions in Globals**: Ensure all required functions are passed to workers
2. **Data Source Mismatch**: Use correct data source (original vs encoded)
3. **Variable Source Mismatch**: Use correct variable names (original vs encoded)
4. **Missing Error Handling**: Wrap all operations in appropriate tryCatch blocks
5. **Inconsistent Logging**: Use same log tags and format as other models
6. **Missing Performance Monitoring**: Include performance monitoring for parallel models
7. **Incorrect Threading**: Use conservative threading (8 threads per worker)
8. **Missing Model Saving**: Implement proper model saving with metadata logging
9. **Package Dependencies**: Ensure all required packages are in the packages list
10. **Function Scoping**: Source functions before setting globals to get latest versions

---

## Testing Checklist

After implementing a new model:

- [ ] Test model fitting in isolation
- [ ] Test model fitting in worker session
- [ ] Verify performance monitoring works
- [ ] Check log files are created correctly
- [ ] Verify model saving works
- [ ] Test error handling scenarios
- [ ] Check function availability diagnostics
- [ ] Verify parallel processing configuration
- [ ] Test with different data sizes
- [ ] Verify memory usage is reasonable

---

## Error-Driven Checklist Refinement

### Learning from Model Logging Errors

As we encounter errors in model logging, use them to refine this checklist:

#### Common Error Patterns to Track:

1. **Function Not Found Errors**
   - **Error**: `could not find function "function_name"`
   - **Checklist Update**: Add function to Required Functions in Globals section
   - **Prevention**: Ensure all model-specific functions are in globals list

2. **Package Loading Errors**
   - **Error**: `there is no package called 'package_name'`
   - **Checklist Update**: Add package to Required Packages section
   - **Prevention**: Verify package is in packages list and installed

3. **Data Source Errors**
   - **Error**: `object 'data_object' not found` or `file not found`
   - **Checklist Update**: Add data validation to Data Requirements section
   - **Prevention**: Check data exists before using, add file existence checks

4. **Scoping Errors**
   - **Error**: `object 'variable' not found` in worker context
   - **Checklist Update**: Add variable to globals or ensure proper scoping
   - **Prevention**: Pass all required variables through globals

5. **Parameter Mismatch Errors**
   - **Error**: `unused argument` or `unrecognized arguments`
   - **Checklist Update**: Update Model Fitting Function section with correct parameters
   - **Prevention**: Verify function signatures match expected parameters

6. **Performance Monitoring Errors**
   - **Error**: `could not find function "monitor_*_performance"`
   - **Checklist Update**: Add performance monitoring functions to globals
   - **Prevention**: Include all monitoring functions in Required Functions section

7. **Logging Connection Errors**
   - **Error**: `cannot open the connection` or `file not found`
   - **Checklist Update**: Add log directory creation to Logging Implementation section
   - **Prevention**: Ensure log directories exist before opening files

8. **Threading/Parallel Errors**
   - **Error**: `libgomp: Invalid value for environment variable`
   - **Checklist Update**: Add environment variable validation to Parallel Processing section
   - **Prevention**: Set positive integer values for OpenMP variables

### Error Documentation Template

When encountering a new error pattern:

```
## Error Pattern: [Error Type]
- **Error Message**: [Exact error message]
- **Model**: [Which model was affected]
- **Context**: [Where in the code it occurred]
- **Root Cause**: [Why it happened]
- **Solution**: [How it was fixed]
- **Checklist Update**: [What to add to checklist]
- **Prevention**: [How to prevent in future]
```

---

## Documented Error Patterns (From Our Implementation)

### Error Pattern: Function Not Found in Worker Context
- **Error Message**: `could not find function "configure_aorsf_parallel"`
- **Model**: All models (ORSF, RSF, XGB, CPH)
- **Context**: Worker sessions during parallel model fitting
- **Root Cause**: Functions not passed to worker globals
- **Solution**: Added all required functions to `furrr::furrr_options(globals = list(...))`
- **Checklist Update**: Added "Required Functions in Globals" section
- **Prevention**: Always include model-specific functions in globals list

### Error Pattern: Package Parameter Name Mismatch
- **Error Message**: `unrecognized arguments: min_obs_in_leaf_node, min_obs_to_split_node`
- **Model**: AORSF
- **Context**: Model fitting with outdated parameter names
- **Root Cause**: Package version mismatch between local and EC2
- **Solution**: Updated parameter names to match current package version
- **Checklist Update**: Added parameter validation to Model Fitting Function section
- **Prevention**: Always verify parameter names match current package version

### Error Pattern: R Function Scoping Issues
- **Error Message**: `could not find function ":="`
- **Model**: All models
- **Context**: Environment variable setting in parallel config functions
- **Root Cause**: Using `rlang` operator without loading `rlang`
- **Solution**: Replaced `!!var_name :=` with `do.call(Sys.setenv, setNames(...))`
- **Checklist Update**: Added function scoping rules to Common Pitfalls
- **Prevention**: Avoid `rlang` operators without explicit `rlang` loading

### Error Pattern: OpenMP Threading Configuration
- **Error Message**: `libgomp: Invalid value for environment variable OMP_NUM_THREADS: 0`
- **Model**: All parallel models
- **Context**: Environment variable setting for parallel processing
- **Root Cause**: OpenMP expects positive integer, not 0
- **Solution**: Set `OMP_NUM_THREADS = 1` when package thread count is 0
- **Checklist Update**: Added environment variable validation to Parallel Processing section
- **Prevention**: Always set positive integer values for OpenMP variables

### Error Pattern: Data Source Mismatch
- **Error Message**: `newdata is unrecognized - did you mean new_data?`
- **Model**: RSF (ranger)
- **Context**: Prediction function parameter names
- **Root Cause**: Package version mismatch between local and EC2
- **Solution**: Added backward compatibility with `tryCatch` for both parameter names
- **Checklist Update**: Added backward compatibility to Data Requirements section
- **Prevention**: Implement backward compatibility for parameter names

### Error Pattern: R Version Compatibility
- **Error Message**: `ReadItem: unknown type 0, perhaps written by later version of R`
- **Model**: All models (MC-CV data loading)
- **Context**: Loading `resamples.rds` file
- **Root Cause**: File created with newer R version than EC2
- **Solution**: Added `tryCatch` fallback to recreate data on the fly
- **Checklist Update**: Added R version compatibility to Data Requirements section
- **Prevention**: Always provide fallback data creation for version mismatches

### Error Pattern: Logging Connection Conflicts
- **Error Message**: `cannot open the connection`
- **Model**: All models
- **Context**: Logging setup and file operations
- **Root Cause**: Mixing `sink()` with direct file operations
- **Solution**: Removed direct file operations, rely solely on `sink()`
- **Checklist Update**: Added logging connection handling to Logging Implementation section
- **Prevention**: Use consistent logging approach (either `sink()` or direct file operations)

### Error Pattern: Function Availability in Workers
- **Error Message**: `unused argument (use_parallel = TRUE)`
- **Model**: RSF in MC-CV workers
- **Context**: Function scoping in parallel workers
- **Root Cause**: Globals captured old function version without `use_parallel` parameter
- **Solution**: Source functions before setting globals to get latest versions
- **Checklist Update**: Added function scoping rules to Required Functions section
- **Prevention**: Always source functions before setting globals

### Error Pattern: Out-of-Bag Predictions Configuration
- **Error Message**: `cannot compute out-of-bag predictions if no samples are out-of-bag`
- **Model**: AORSF
- **Context**: Model fitting with OOB predictions enabled
- **Root Cause**: `sample_fraction = 1.0` means no samples left for OOB
- **Solution**: Set `sample_fraction = 0.8` to leave samples for OOB
- **Checklist Update**: Added parameter validation to Model Fitting Function section
- **Prevention**: Always validate parameter values for model requirements

### Continuous Improvement Process

1. **Monitor Logs**: Regularly check model logs for errors
2. **Categorize Errors**: Group similar errors together
3. **Update Checklist**: Add new requirements based on errors
4. **Test Prevention**: Verify checklist updates prevent errors
5. **Document Patterns**: Keep track of recurring error patterns
6. **Share Knowledge**: Update team on new checklist items

### Error Prevention Checklist

Before implementing any model:

- [ ] Review recent error logs for similar models
- [ ] Check if error patterns apply to new model
- [ ] Verify all functions from error logs are included
- [ ] Test with minimal data first
- [ ] Check function availability diagnostics
- [ ] Verify all required packages are available
- [ ] Test error handling scenarios
- [ ] Review globals list for completeness

### Error Recovery Checklist

When errors occur:

- [ ] Check model-specific log file for detailed error
- [ ] Check function availability diagnostics
- [ ] Verify all required functions are in globals
- [ ] Check data sources and variables
- [ ] Verify package loading
- [ ] Check parallel processing configuration
- [ ] Review error handling implementation
- [ ] Update checklist based on error pattern
- [ ] Test fix with minimal data
- [ ] Verify fix works in full pipeline

---

## Function Signature Validation Framework

### Critical Requirement: Comprehensive Function Signature Checks

**Lesson Learned**: Function existence ≠ Function compatibility. The CPH parameter issue demonstrated that checking if functions exist is insufficient - we must validate function signatures and parameter compatibility.

### ✅ Enhanced Function Diagnostics Implementation

#### 1. Function Signature Validation Categories

**A. Parameter Default Validation**
- Check if required parameters have default values
- Identify missing defaults that could cause runtime failures
- Validate parameter types and expected values

**B. Function Compatibility Verification**
- Verify function can be called with expected parameters
- Check parameter names match expected usage
- Validate return types and structures

**C. Model-Specific Signature Requirements**
- Document expected function signatures for each model
- Validate against actual function definitions
- Check for version compatibility issues

#### 2. Implementation in Function Diagnostics

```r
# Enhanced signature validation for critical functions
if (model_type == "MODEL_NAME" && "function_name" %in% available_functions) {
  tryCatch({
    # Check function signature
    func_formals <- formals(function_name)
    critical_param <- func_formals$parameter_name
    
    if (missing(critical_param) || is.name(critical_param)) {
      cat(sprintf('[FUNCTION_DIAG] WARNING: %s parameter has no default - may cause failures\n', 
                  "parameter_name"), file = model_log, append = TRUE)
    } else {
      cat(sprintf('[FUNCTION_DIAG] %s signature validated - parameter has default\n', 
                  "function_name"), file = model_log, append = TRUE)
    }
  }, error = function(e) {
    cat(sprintf('[FUNCTION_DIAG] Could not validate %s signature: %s\n', 
                "function_name", e$message), file = model_log, append = TRUE)
  })
}
```

#### 3. Model-Specific Signature Requirements

**ORSF Model Functions:**
- `fit_orsf(trn, vars, use_parallel = TRUE, check_r_functions = TRUE)`
- All parameters should have defaults except `trn` and `vars`

**RSF Model Functions:**
- `fit_rsf(trn, vars, use_parallel = TRUE)`
- All parameters should have defaults except `trn` and `vars`

**XGB Model Functions:**
- `fit_xgb(trn, vars, use_parallel = TRUE, tree_method = 'auto')`
- All parameters should have defaults except `trn` and `vars`

**CPH Model Functions:**
- `fit_cph(trn, vars = NULL, tst = NULL, predict_horizon = NULL)`
- **CRITICAL**: All parameters must have defaults (learned from CPH failure)

#### 4. Signature Validation Checklist

For each model implementation:

- [ ] **Document expected function signatures**
- [ ] **Identify critical parameters that need defaults**
- [ ] **Implement signature validation in function diagnostics**
- [ ] **Test function calls with expected parameters**
- [ ] **Verify error handling for signature mismatches**
- [ ] **Add signature validation to model-specific diagnostics**

#### 5. Common Signature Issues to Check

**Missing Default Parameters:**
```r
# BAD: Will fail if called with parameter = NULL
function_name <- function(param1, param2, critical_param) { ... }

# GOOD: Has default value
function_name <- function(param1, param2, critical_param = NULL) { ... }
```

**Parameter Name Mismatches:**
```r
# Check if function expects 'newdata' vs 'new_data'
# Check if function expects 'times' vs 'eval_times'
# Validate parameter names match usage in worker calls
```

**Return Type Validation:**
```r
# Verify function returns expected object type
# Check if function returns model object vs predictions
# Validate return structure matches downstream usage
```

#### 6. Automated Signature Validation

**Implementation Template:**
```r
validate_model_function_signature <- function(model_type, func_name, expected_params) {
  tryCatch({
    if (!exists(func_name, mode = "function")) {
      return(list(valid = FALSE, error = "Function not found"))
    }
    
    func_formals <- formals(get(func_name))
    
    # Check each expected parameter
    for (param in expected_params) {
      param_name <- param$name
      param_required_default <- param$needs_default
      
      if (param_required_default && (missing(func_formals[[param_name]]) || 
                                   is.name(func_formals[[param_name]]))) {
        return(list(
          valid = FALSE, 
          error = sprintf("Parameter %s needs default value", param_name)
        ))
      }
    }
    
    return(list(valid = TRUE, error = NULL))
  }, error = function(e) {
    return(list(valid = FALSE, error = e$message))
  })
}
```

#### 7. Integration with Existing Diagnostics

**Enhanced Function Diagnostics Flow:**
1. Check function existence (current)
2. **NEW**: Validate function signatures
3. **NEW**: Check parameter compatibility
4. **NEW**: Verify expected return types
5. Log comprehensive diagnostics
6. Provide actionable error messages

#### 8. Error Pattern Documentation

**Function Signature Error Pattern:**
- **Error Message**: `argument "parameter" is missing, with no default`
- **Model**: Any model with missing parameter defaults
- **Context**: Function calls in parallel workers
- **Root Cause**: Function signature lacks required default values
- **Solution**: Add default values to function parameters
- **Checklist Update**: Add signature validation requirement
- **Prevention**: Implement comprehensive signature validation

#### 9. Testing Framework for Signatures

**Signature Testing Checklist:**
- [ ] Test function calls with all expected parameter combinations
- [ ] Test function calls with NULL values for optional parameters
- [ ] Test function calls with missing optional parameters
- [ ] Verify error messages are informative
- [ ] Test signature validation diagnostics
- [ ] Verify compatibility across R versions

#### 10. Continuous Signature Monitoring

**Ongoing Validation:**
- [ ] Add signature validation to CI/CD pipeline
- [ ] Monitor function signature changes in package updates
- [ ] Validate signatures before deploying to production
- [ ] Document signature requirements for new models
- [ ] Update validation when adding new functions

### Implementation Priority

**High Priority (Immediate):**
1. ✅ CPH signature validation (completed)
2. Add signature validation for all model fitting functions
3. Implement automated signature checking
4. Update function diagnostics with signature validation

**Medium Priority:**
1. Add signature validation for helper functions
2. Implement return type validation
3. Add parameter type checking
4. Create signature testing framework

**Low Priority:**
1. Add signature validation for utility functions
2. Implement cross-version compatibility checking
3. Create automated signature documentation
4. Add signature change detection

This framework ensures that function signature issues are caught during diagnostics rather than causing silent failures in parallel workers.

---

## MC-CV Data Quality Diagnostics Framework

Monte Carlo Cross Validation can introduce data quality issues that don't appear in full-dataset fitting. This framework provides comprehensive diagnostics to identify and log these issues.

### Common MC-CV Issues

#### **1. Sample Size Reduction Effects**
- **Reduced stability**: Smaller training sets reduce statistical power
- **Events per predictor ratio**: May drop below recommended threshold (>10)
- **Rare event sampling**: Rare categories may have 0-2 cases in training splits

#### **2. Perfect/Quasi-Separation**
- **Definition**: When a predictor perfectly or nearly perfectly predicts the outcome
- **MC-CV impact**: More likely in smaller training sets
- **Example**: All patients with `rare_condition=1` have `status=1` in a particular split

#### **3. Variable Quality Issues**
- **Zero variance**: Variables become constant in training splits
- **Single levels**: Categorical variables lose levels due to sampling
- **Small sample sizes**: Categories with <5 observations become unstable

#### **4. Feature Selection Instability**
- **Selection bias**: Variables selected on full data may not be stable in subsets
- **Correlation changes**: Variable relationships may differ between splits
- **Overfitting indicators**: Variables that work on full data but fail in splits

#### **5. Recipe NZV Filtering Issues**
- **Problem**: `step_nzv()` can inappropriately drop variables in MC-CV splits
- **Root cause**: Variables valid in full dataset may become near-zero variance in small training splits
- **Impact**: Models receive fewer variables than expected (e.g., 5 instead of 21 for RSF)
- **Solution**: Use `make_recipe_mc_cv()` that skips NZV filtering for MC-CV
- **Detection**: Log original vs. post-recipe variable counts

### Expected Log Output

#### **Normal Split (No Issues)**
```
[DEBUG] Variable preservation - Original: 21, After recipe: 21
[ORSF_INIT] Starting ORSF model with 3501 observations, 21 predictors
[ORSF_INIT] Events: 987 (28.2%), Censored: 2514 (71.8%)
[ORSF_INIT] Events per predictor ratio: 47.00 (recommended: >10)
[ORSF_INIT] No obvious MC-CV data issues detected
```

#### **Problematic Split**
```
[WARNING] Recipe dropped 16 variables: rare_complication, low_freq_category, sparse_indicator, ...
[DEBUG] Variable preservation - Original: 21, After recipe: 5
[CPH_INIT] Starting CPH model with 3501 observations, 5 predictors
[CPH_INIT] Events: 987 (28.2%), Censored: 2514 (71.8%)
[CPH_INIT] Events per predictor ratio: 197.40 (recommended: >10)
[CPH_INIT] Potential MC-CV issues detected in 3 variables:
[CPH_INIT] - rare_complication (small levels: yes)
[CPH_INIT] - donor_age_extreme (zero variance)
[CPH_INIT] - center_volume (single level)

[CPH_DEBUG] SEPARATION DETECTED in 'rare_complication':
       0    1
  no 2510  985
  yes   4    2
```

## Process and Core Utilization Monitoring Framework

### Overview

Comprehensive process monitoring system designed to detect and diagnose threading conflicts on high-core EC2 instances. This framework tracks CPU usage, core assignments, memory utilization, and threading patterns in real-time.

### Implementation Requirements

#### 1. Process Monitoring Integration

**Required Files:**
- `R/utils/process_monitor.R` - Core monitoring utility functions
- Integration in `R/utils/model_utils.R` at model fitting points

**Required Functions:**
```r
# Source monitoring functions
source(here::here("R", "utils", "process_monitor.R"))

# Log process state
log_process_info(model_log, "[PROCESS_PRE_{MODEL}]", include_children = TRUE, include_system = TRUE)
```

#### 2. Model-Specific Monitoring Points

**For Each Model Type (ORSF, RSF, XGB, CPH):**

**Task Start Monitoring:**
```r
# At beginning of compute_task_internal()
log_process_info(model_log, sprintf("[PROCESS_START_%s]", model_type), 
                include_children = TRUE, include_system = TRUE)
```

**Pre-Fitting Monitoring:**
```r
# Immediately before fit_{model}() call
tryCatch({
  if (exists("log_process_info", mode = "function")) {
    log_process_info(model_log, "[PROCESS_PRE_{MODEL}]", include_children = TRUE, include_system = TRUE)
  }
}, error = function(e) NULL)
```

**Post-Fitting Monitoring:**
```r
# Immediately after fit_{model}() call
tryCatch({
  if (exists("log_process_info", mode = "function")) {
    log_process_info(model_log, "[PROCESS_POST_{MODEL}]", include_children = TRUE, include_system = TRUE)
  }
}, error = function(e) NULL)
```

#### 3. Threading Conflict Detection

**Automatic Detection:**
```r
# Check for threading conflicts
conflicts <- detect_threading_conflicts()
if (conflicts$has_conflicts) {
  cat(sprintf('[THREADING_CONFLICT] %s Detected conflicts: %s\n',
              format(Sys.time(), '%Y-%m-%d %H:%M:%S'),
              paste(conflicts$indicators, collapse = "; ")),
      file = model_log, append = TRUE)
}
```

**Detection Criteria:**
- High CPU usage (>90%) with many threads (>20)
- System load ratio > 1.5 (load / available cores)
- Multiple child processes with >50% CPU each
- Total child CPU usage > 80% of available cores

#### 4. Background Pipeline Monitoring

**Pipeline-Level Monitoring:**
```r
# Start background monitoring for entire pipeline
pipeline_log <- here::here('logs', 'pipeline_process_monitor.log')
log_process_info(pipeline_log, "[PIPELINE_START]", include_children = TRUE, include_system = TRUE)

# Start background monitoring daemon
monitor_pid <- start_process_monitor(pipeline_log, interval_seconds = 30, duration_minutes = 0)
```

#### 5. Log Output Format

**Process Information Logs:**
```
[PROCESS_PRE_RSF] 2025-10-08 10:15:30 PID=12345 Cores=16/32 CPU=15.2% MEM=8.1% Threads=4 CurrentCore=7 Affinity=0-31 Load=2.45,1.89,1.23 SysMem=950.2GB/1024.0GB
  Child PID=12346 CPU=45.3% MEM=2.1% Threads=16 Core=12 Cmd=R
  Thread TID=12345 CPUTime=1250 Processor=7
```

**Threading Conflict Alerts:**
```
[THREADING_CONFLICT] 2025-10-08 10:16:15 Detected conflicts: High CPU (95.2%) with many threads (24); High load ratio (2.85) - load 91.20 on 32 cores
```

#### 6. Error Handling Requirements

**Monitoring Error Protection:**
```r
# All monitoring calls must be wrapped in tryCatch
tryCatch({
  # Monitoring code here
}, error = function(e) {
  # Log monitoring error but don't fail the model fitting
  cat(sprintf('[PROCESS_LOG_ERROR] Failed to log process info: %s\n', e$message),
      file = model_log, append = TRUE)
})
```

#### 7. Platform Support

**Linux/Unix (Full Support):**
- CPU usage via `ps`
- Core affinity via `taskset`
- Thread details via `/proc/pid/task/`
- System load via `uptime`
- Memory info via `/proc/meminfo`

**Windows (Basic Support):**
- Process info via `wmic`
- Memory usage tracking
- Thread count monitoring

#### 8. Environment Variables

**Process Monitoring Controls:**
- `RSF_MAX_THREADS=16` - Cap ranger threads (prevents conflicts)
- `RSF_TIMEOUT_MINUTES=30` - Ranger timeout protection
- `TASK_TIMEOUT_MINUTES=45` - Individual task timeout
- `PROCESS_MONITOR_INTERVAL=30` - Background monitoring interval

#### 9. Integration Checklist

**For Each New Model:**
- [ ] Add `[PROCESS_START_{MODEL}]` at task initialization
- [ ] Add `[PROCESS_PRE_{MODEL}]` before model fitting call
- [ ] Add `[PROCESS_POST_{MODEL}]` after model fitting completion
- [ ] Wrap all monitoring calls in `tryCatch()` blocks
- [ ] Test monitoring on high-core instances (EC2)
- [ ] Verify threading conflict detection works
- [ ] Check log output format and completeness

#### 10. Troubleshooting

**Common Issues:**
- Missing `[PROCESS_POST_{MODEL}]` logs indicate hanging
- High load ratios indicate threading conflicts
- Missing child process info suggests monitoring failures

**Debugging Commands:**
```bash
# Check for completed model fittings
grep "PROCESS_POST_" logs/models/original/full/*.log

# Check for threading conflicts
grep "THREADING_CONFLICT" logs/models/original/full/*.log

# Monitor system resources
tail -f logs/pipeline_process_monitor.log
```

### Benefits

1. **Early Detection**: Catch threading conflicts before they cause hangs
2. **Resource Optimization**: Monitor actual core and memory usage
3. **Debugging Aid**: Detailed logs for troubleshooting pipeline issues
4. **Performance Tuning**: Data-driven optimization of thread limits
5. **EC2 Compatibility**: Specifically designed for high-core cloud instances

This monitoring framework provides complete visibility into threading and resource usage patterns, enabling detection and prevention of the conflicts that cause model fitting to hang on high-core EC2 instances.
