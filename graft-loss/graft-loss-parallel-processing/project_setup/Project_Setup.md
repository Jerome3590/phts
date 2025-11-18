# ===================
# COMPREHENSIVE PARALLEL PROCESSING & PIPELINE SOLUTION
# ===================
# Complete solution for parallel processing, model passing mechanisms, and environment transitions

**⚠️ IMPORTANT**: See [DEVELOPMENT_RULES.md](DEVELOPMENT_RULES.md) for critical lessons learned and prevention rules to avoid regression.

## **🔍 Problem Analysis**

### **Original Issues:**
1. **Environment Variable Inheritance**: Only `DATASET_COHORT` was passed between steps
2. **Data File Conflicts**: All cohorts wrote to the same intermediate files
3. **Log File Conflicts**: All steps overwrote each other's log entries
4. **Missing Configuration**: Steps 4-8 needed additional environment variables
5. **Model Passing Complexity**: Large model objects couldn't be efficiently transferred between steps
6. **Parallel Processing Errors**: Common issues with `:=` operator, OpenMP, and function availability
7. **Monolithic Pipeline Structure**: Step 4 was a massive 1947-line monolithic file that was difficult to debug and maintain

### **Critical Dependencies:**
- Steps 4-8 require specific environment variables (MC_CV, USE_ENCODED, etc.)
- Each step saves intermediate results that the next step needs
- Parallel execution across cohorts must avoid file conflicts
- Log files must be step-specific and cohort-specific
- Models must be efficiently passed between Step 6 (fitting) and Step 7 (saving)
- Pipeline structure must be modular for better debugging and maintenance
- Parallel processing requires proper thread management and function availability

## **💡 Solution Architecture**

### **1. Environment Variable Management**
```r
# Enhanced cohort configuration with all required environment variables
cohorts_enhanced <- list(
  original = list(
    env = list(
      DATASET_COHORT = "original",
      MC_CV = "1",
      MC_TIMES = "20", 
      USE_ENCODED = "0",
      XGB_FULL = "0",
      USE_CATBOOST = "0",
      FINAL_MODEL_WORKERS = "4",
      FINAL_MODEL_PLAN = "multisession",
      MC_WORKER_THREADS = "8",
      # OpenMP and BLAS libraries (positive integers)
      OMP_NUM_THREADS = "1",
      MKL_NUM_THREADS = "1",
      OPENBLAS_NUM_THREADS = "1",
      VECLIB_MAXIMUM_THREADS = "1",
      NUMEXPR_NUM_THREADS = "1",
      # Package-specific variables (auto-detection)
      R_RANGER_NUM_THREADS = "0",
      XGBOOST_NTHREAD = "0",
      AORSF_NTHREAD = "0"
    ),
    log = file.path(getwd(), "logs/orch_bg_original_study.log")
  ),
  # ... other cohorts
)
```

### **2. Cohort-Specific File Paths**
```r
# Before: All cohorts write to the same files
data_setup_file <- here::here('model_data', 'data_setup.rds')  # CONFLICT!
models_file <- here::here('model_data', 'final_models.rds')    # CONFLICT!

# After: Each cohort gets its own subdirectory
data_setup_file <- get_cohort_path(here::here('model_data', 'data_setup.rds'), cohort_name)
models_file <- get_cohort_path(here::here('model_data', 'final_models.rds'), cohort_name)
# Results in: model_data/original/data_setup.rds
#             model_data/full_with_covid/data_setup.rds
#             model_data/full_without_covid/data_setup.rds
```

### **3. Step-Specific Log Files**
```r
# Before: All steps write to the same log file
log_file <- "logs/orch_bg_original_study.log"  # CONFLICT!

# After: Each step gets its own log file
log_file <- get_cohort_log_path("04_data_setup", cohort_name)
# Results in: logs/steps/original/04_data_setup_20251010_073308.log
#             logs/steps/full_with_covid/04_data_setup_20251010_073309.log
```

## **🏗️ Pipeline Structure Architecture**

### **Original Structure (Steps 0-5):**
- Step 0: Setup
- Step 1: Prepare Data  
- Step 2: Resampling
- Step 3: Prepare Model Data
- Step 4: Fit Model (MONOLITHIC - 1947 lines)
- Step 5: Generate Outputs

### **New Modular Structure (Steps 0-9):**
- Step 0: Setup
- Step 1: Prepare Data  
- Step 2: Resampling
- Step 3: Prepare Model Data
- **Step 4: Data Setup and Preparation** (NEW)
- **Step 5: MC-CV Analysis** (NEW)
- **Step 6: Parallel Model Fitting** (NEW)
- **Step 7: Model Saving and Indexing** (NEW)
- **Step 8: Fallback Handling** (NEW)
- **Step 9: Generate Outputs** (formerly Step 5)

### **Benefits of Modularization:**
1. **Easier Debugging**: Each step has a single responsibility
2. **Better Error Handling**: Fallback strategies are isolated
3. **Parallel Execution**: Steps can be run independently
4. **Maintainability**: Much easier to modify individual components
5. **Testing**: Each step can be tested in isolation
6. **Resource Management**: Better control over memory and CPU usage

### **Pipeline File Structure:**
```
pipeline/
├── 00_setup.R
├── 01_prepare_data.R
├── 02_resampling.R
├── 03_prep_model_data.R
├── 04_data_setup.R          # NEW
├── 05_mc_cv_analysis.R      # NEW
├── 06_parallel_model_fitting.R  # NEW
├── 07_model_saving.R        # NEW
├── 08_fallback_handling.R   # NEW
└── 09_generate_outputs.R    # RENAMED from 05

scripts/R/
├── fit_models_parallel.R     # Data setup and parallel fitting
├── fit_models_fallback.R    # Fallback error handling
├── mc_cv_analysis.R         # MC-CV analysis
├── model_saving.R           # Model saving and indexing
└── 04_fit_model_main.R      # Original monolithic file (kept for reference)
```

### **Pipeline Usage Patterns:**
- **Sequential**: Run steps 4-8 individually for debugging
- **Parallel**: Use the notebook cells to run steps 4-8 in sequence
- **Fallback**: Step 8 automatically handles failures from step 6
- **Output**: Step 9 generates final outputs as before

## **🔧 Parallel Processing Architecture**

### **Core Components**

1. **Parallel Configuration Modules**: `R/ranger_parallel_config.R`, `R/xgboost_parallel_config.R`, `R/aorsf_parallel_config.R`
2. **Model Utilities**: `R/utils/model_utils.R` (consolidated functions)
3. **Pipeline Integration**: `scripts/04_fit_model.R` (step 4 model fitting)
4. **Global Configuration**: `scripts/config.R` (pipeline-wide settings)

### **Parallel Processing Levels**

1. **Package-Level Parallelization**: Individual packages use multiple threads
2. **Pipeline-Level Parallelization**: Multiple models fitted simultaneously
3. **MC-CV Parallelization**: Multiple cross-validation splits processed in parallel

### **Model Types Supported**

- **Ranger (RSF)**: Random Survival Forest using `ranger` package
- **XGBoost**: Extreme Gradient Boosting using `xgboost` and `xgboost.surv` packages  
- **aorsf (ORSF)**: Oblique Random Survival Forest using `aorsf` package

## **🔧 Model Passing Flow**

### **Step 6: Parallel Model Fitting**
```
┌─────────────────────────────────────────────────────────────┐
│                    PARALLEL WORKERS                         │
├─────────────────────────────────────────────────────────────┤
│ Worker 1: ORSF Model                                        │
│ ├─ Fits model using fit_orsf()                             │
│ ├─ Saves to: models/{cohort}/model_orsf.rds               │
│ └─ Returns: {model_name, path, size, success}             │
├─────────────────────────────────────────────────────────────┤
│ Worker 2: RSF Model                                        │
│ ├─ Fits model using fit_rsf()                             │
│ ├─ Saves to: models/{cohort}/model_rsf.rds                │
│ └─ Returns: {model_name, path, size, success}             │
├─────────────────────────────────────────────────────────────┤
│ Worker 3: XGB Model                                        │
│ ├─ Fits model using fit_xgb()                             │
│ ├─ Saves to: models/{cohort}/model_xgb.rds                │
│ └─ Returns: {model_name, path, size, success}             │
├─────────────────────────────────────────────────────────────┤
│ Worker 4: CPH Model                                        │
│ ├─ Fits model using fit_cph()                             │
│ ├─ Saves to: models/{cohort}/model_cph.rds                │
│ └─ Returns: {model_name, path, size, success}             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                MAIN PROCESS                                │
├─────────────────────────────────────────────────────────────┤
│ ├─ Collects metadata from all workers                     │
│ ├─ Creates final_models list with paths and metadata      │
│ ├─ Saves ORSF as final_model.rds for backward compatibility│
│ └─ Saves metadata to: model_data/{cohort}/final_models.rds │
└─────────────────────────────────────────────────────────────┘
```

### **Step 7: Model Saving**
```
┌─────────────────────────────────────────────────────────────┐
│                MODEL SAVING PROCESS                        │
├─────────────────────────────────────────────────────────────┤
│ ├─ Loads metadata from: model_data/{cohort}/final_models.rds│
│ ├─ Models are ALREADY SAVED to disk by workers             │
│ ├─ Creates comparison index                                │
│ ├─ Handles optional CatBoost fitting                      │
│ └─ Manages model artifacts and indexing                   │
└─────────────────────────────────────────────────────────────┘
```

## **📁 File Structure After Implementation**

### **Cohort-Specific Model Files:**
```
models/
├── original/
│   ├── model_orsf.rds      # ORSF model (saved by worker)
│   ├── model_rsf.rds       # RSF model (saved by worker)
│   ├── model_xgb.rds       # XGB model (saved by worker)
│   ├── model_cph.rds       # CPH model (saved by worker)
│   └── final_model.rds     # ORSF copy for backward compatibility
├── full_with_covid/
│   ├── model_orsf.rds
│   ├── model_rsf.rds
│   ├── model_xgb.rds
│   ├── model_cph.rds
│   └── final_model.rds
└── full_without_covid/
    ├── model_orsf.rds
    ├── model_rsf.rds
    ├── model_xgb.rds
    ├── model_cph.rds
    └── final_model.rds
```

### **Cohort-Specific Metadata Files:**
```
model_data/
├── original/
│   ├── data_setup.rds           # From Step 4
│   ├── mc_cv_results.rds        # From Step 5
│   ├── final_models.rds         # From Step 6 (metadata only)
│   └── model_fitting_error.rds  # From Step 6 (if error)
├── full_with_covid/
│   └── [same structure]
└── full_without_covid/
    └── [same structure]

logs/
├── steps/
│   ├── original/
│   │   ├── 04_data_setup_20251010_073308.log
│   │   ├── 05_mc_cv_analysis_20251010_073315.log
│   │   ├── 06_parallel_model_fitting_20251010_073320.log
│   │   ├── 07_model_saving_20251010_073325.log
│   │   └── 08_fallback_handling_20251010_073330.log
│   ├── full_with_covid/
│   │   └── [similar structure]
│   └── full_without_covid/
│       └── [similar structure]
└── orch_bg_*.log  # Main pipeline logs
```

## **🔧 Implementation Details**

### **Environment Transition Utilities (`scripts/R/environment_transition.R`)**

#### **Core Functions:**
1. **`get_cohort_path(base_path, cohort_name)`**
   - Creates cohort-specific subdirectories
   - Ensures directory structure exists
   - Returns cohort-specific file paths

2. **`get_cohort_log_path(step_name, cohort_name)`**
   - Creates step-specific log directories
   - Generates timestamped log files
   - Prevents log file conflicts

3. **`setup_step_environment(cohort_name, step_name)`**
   - Sets up all required environment variables
   - Handles step-specific configurations
   - Ensures proper inheritance

4. **`create_cohort_step_script(step_script, cohort_name)`**
   - Creates cohort-specific versions of step scripts
   - Replaces hardcoded paths with cohort-specific paths
   - Enables parallel execution without conflicts

### **Model Passing Implementation:**

#### **1. Models are Saved Within Workers (Not Transferred)**
```r
# Within each parallel worker:
model_path <- file.path(models_dir, 'model_orsf.rds')
saveRDS(model_result, model_path)  # Model saved directly to disk

# Return lightweight metadata (not the actual model):
return(list(
  model_name = "ORSF",
  model_path = model_path,        # Path to saved model
  model_size_mb = file_size_mb,
  elapsed_mins = elapsed,
  success = TRUE
))
```

#### **2. Metadata is Collected and Saved**
```r
# Main process collects metadata from all workers:
successful_models <- list()
for (result in final_models) {
  if (result$success) {
    successful_models[[result$model_name]] <- result
  }
}

# Save metadata (not models) to intermediate file:
final_models <- list(
  success = TRUE,
  results = successful_models,  # Contains paths and metadata
  final_orsf_path = final_orsf_path
)
saveRDS(final_models, models_file)  # model_data/{cohort}/final_models.rds
```

#### **3. Step 7 Loads Metadata and Processes Models**
```r
# Step 7 loads metadata from Step 6:
final_models <- readRDS(models_file)  # Contains paths, not actual models

# Models are already saved - Step 7 just processes them:
if (final_models$success) {
  # Handle optional CatBoost fitting
  final_models$results <- handle_catboost_fitting(data_setup, final_models$results)
  
  # Save results and create comparison index
  save_results <- save_model_results(final_models$results, data_setup$cohort_name)
}
```

### **Updated Pipeline Steps:**

#### **Step 4: Data Setup**
```r
# Load environment transition utilities
source(here::here("scripts", "R", "environment_transition.R"))

# Save data setup for next steps (cohort-specific)
data_setup_file <- get_cohort_path(here::here('model_data', 'data_setup.rds'), cohort_name)
saveRDS(data_setup, data_setup_file)
```

#### **Step 5: MC-CV Analysis**
```r
# Load data setup from previous step (cohort-specific)
data_setup_file <- get_cohort_path(here::here('model_data', 'data_setup.rds'), cohort_name)
data_setup <- readRDS(data_setup_file)

# Save MC-CV results for next steps (cohort-specific)
mc_cv_file <- get_cohort_path(here::here('model_data', 'mc_cv_results.rds'), cohort_name)
saveRDS(mc_cv_results, mc_cv_file)
```

#### **Steps 6-8: Similar Pattern**
- Each step loads from cohort-specific paths
- Each step saves to cohort-specific paths
- Environment variables are properly inherited
- Models are saved directly to disk by workers

## **🚨 Common Parallel Processing Issues and Solutions**

### **Issue 1: `:=` Operator Error**

**Error**: `could not find function ":="`

**Cause**: The `rlang` package's `!!` operator was being used with `:=` in `Sys.setenv()` calls, but `rlang` wasn't loaded.

**Solution**: Replace `rlang`-dependent syntax with base R syntax.

**Before (problematic)**:
```r
Sys.setenv(!!var_name := ranger_env_vars[[var_name]])
```

**After (fixed)**:
```r
do.call(Sys.setenv, setNames(list(ranger_env_vars[[var_name]]), var_name))
```

**Files Updated**: `R/utils/model_utils.R`, all parallel configuration functions

### **Issue 2: "all arguments must be named" Error**

**Error**: `all arguments must be named`

**Cause**: `Sys.setenv(var_name, value)` doesn't work when `var_name` is a string variable.

**Solution**: Use `do.call()` and `setNames()` for dynamic variable names.

**Before (problematic)**:
```r
Sys.setenv(var_name, ranger_env_vars[[var_name]])
```

**After (fixed)**:
```r
do.call(Sys.setenv, setNames(list(ranger_env_vars[[var_name]]), var_name))
```

**Files Updated**: `R/utils/model_utils.R`, all parallel configuration functions

### **Issue 3: OpenMP Invalid Value Error**

**Error**: `libgomp: Invalid value for environment variable OMP_NUM_THREADS: 0`

**Cause**: OpenMP expects positive integers (≥ 1) but we were setting `OMP_NUM_THREADS = 0` for auto-detection.

**Solution**: Use two-tier approach - set OpenMP to positive integers while allowing packages to use auto-detection.

**Code Example**:
```r
# For OpenMP, use a positive integer (1 if num_threads is 0 for auto-detection)
omp_threads <- if (num_threads == 0) 1 else num_threads
ranger_env_vars <- list(
  R_RANGER_NUM_THREADS = as.character(num_threads),  # Package can use 0
  OMP_NUM_THREADS = as.character(omp_threads),       # OpenMP gets positive integer
  MKL_NUM_THREADS = as.character(omp_threads),
  OPENBLAS_NUM_THREADS = as.character(omp_threads),
  VECLIB_MAXIMUM_THREADS = as.character(omp_threads),
  NUMEXPR_NUM_THREADS = as.character(omp_threads)
)
```

**Files Updated**: `R/utils/model_utils.R`, `scripts/config.R`

### **Issue 4: "could not find function" Error**

**Error**: `could not find function "configure_ranger_parallel"`

**Cause**: Parallel processing configuration functions weren't available in worker processes.

**Solution**: Add all parallel processing functions to the `globals` list in `furrr::furrr_options()`.

**Code Example**:
```r
.options = furrr::furrr_options(
  seed = TRUE,
  packages = c("here", "recipes", "dplyr", "readr", "survival", "rsample", 
               "ranger", "aorsf", "obliqueRSF", "xgboost", "xgboost.surv", 
               "riskRegression"),
  globals = list(
    # Include parallel processing configuration functions
    configure_ranger_parallel = configure_ranger_parallel,
    configure_xgboost_parallel = configure_xgboost_parallel,
    configure_aorsf_parallel = configure_aorsf_parallel,
    # Include parallel processing wrapper functions
    ranger_parallel = ranger_parallel,
    predict_ranger_parallel = predict_ranger_parallel,
    xgboost_parallel = xgboost_parallel,
    predict_xgboost_parallel = predict_xgboost_parallel,
    aorsf_parallel = aorsf_parallel,
    predict_aorsf_parallel = predict_aorsf_parallel,
    # Include helper functions
    get_xgboost_params = get_xgboost_params,
    sgb_fit = sgb_fit,
    sgb_data = sgb_data,
    get_aorsf_params = get_aorsf_params,
    orsf = orsf,
    # Include core model functions
    fit_orsf = fit_orsf,
    fit_rsf = fit_rsf,
    fit_xgb = fit_xgb,
    # ... other required functions and data
  )
)
```

**Files Updated**: `R/utils/model_utils.R`, `scripts/04_fit_model.R`

### **Issue 5: "unused arguments" Error**

**Error**: `unused arguments (use_parallel = TRUE, check_r_functions = TRUE)`

**Cause**: Model fitting functions were updated to include parallel processing parameters, but the updated functions weren't available in workers.

**Solution**: Ensure all updated model functions are included in worker globals and properly loaded.

**Code Example**:
```r
# Updated fit_orsf function signature
fit_orsf <- function(trn,
                     vars,
                     tst = NULL,
                     predict_horizon = NULL,
                     use_parallel = TRUE,
                     n_thread = NULL,
                     check_r_functions = TRUE) {
  # ... implementation
}

# Updated fit_rsf function signature  
fit_rsf <- function(trn,
                    vars,
                    tst = NULL,
                    predict_horizon = NULL,
                    use_parallel = TRUE,
                    num_threads = NULL,
                    memory_efficient = FALSE) {
  # ... implementation
}

# Updated fit_xgb function signature
fit_xgb <- function(trn,
                    vars,
                    tst = NULL,
                    predict_horizon = NULL,
                    use_parallel = TRUE,
                    nthread = NULL,
                    tree_method = 'auto',
                    gpu_id = NULL) {
  # ... implementation
}
```

**Files Updated**: `R/fit_orsf.R`, `R/fit_rsf.R`, `R/fit_xgb.R`

## **🔧 Parallel Processing Configuration**

### **Ranger Configuration**

```r
# Configure ranger parallel processing
ranger_config <- configure_ranger_parallel(
  num_threads = NULL,           # NULL = auto-detect
  use_all_cores = TRUE,         # Use all available cores
  target_utilization = 0.8,     # Use 80% of cores
  memory_efficient = FALSE,     # Full memory mode
  verbose = TRUE
)

# Use with ranger
model <- ranger_parallel(
  formula = Surv(time, status) ~ .,
  data = training_data,
  config = ranger_config,
  num.trees = 1000,
  min.node.size = 10,
  splitrule = 'C'
)
```

### **XGBoost Configuration**

```r
# Configure XGBoost parallel processing
xgb_config <- configure_xgboost_parallel(
  nthread = NULL,               # NULL = auto-detect
  use_all_cores = TRUE,         # Use all available cores
  target_utilization = 0.8,     # Use 80% of cores
  tree_method = 'auto',         # Auto-detect best tree method
  gpu_id = NULL,                # NULL = CPU only
  verbose = TRUE
)

# Use with XGBoost
model <- xgboost_parallel(
  data = training_matrix,
  label = training_labels,
  config = xgb_config,
  nrounds = 500,
  eta = 0.01,
  max_depth = 3,
  objective = "survival:cox"
)
```

### **aorsf Configuration**

```r
# Configure aorsf parallel processing
aorsf_config <- configure_aorsf_parallel(
  n_thread = NULL,              # NULL = auto-detect
  use_all_cores = TRUE,         # Use all available cores
  target_utilization = 0.8,     # Use 80% of cores
  check_r_functions = TRUE,     # Check for R function limitations
  verbose = TRUE
)

# Use with aorsf
model <- aorsf_parallel(
  data = training_data,
  formula = Surv(time, status) ~ .,
  config = aorsf_config,
  n_tree = 1000
)
```

## **🚀 Usage Examples**

### **Pipeline Execution Patterns**

#### **Sequential Execution (Debugging)**
```r
# Run steps individually for debugging
run_step_local("STEP 4: Data Setup", "pipeline/04_data_setup.R", cohorts_enhanced)
run_step_local("STEP 5: MC-CV Analysis", "pipeline/05_mc_cv_analysis.R", cohorts_enhanced)
run_step_local("STEP 6: Parallel Model Fitting", "pipeline/06_parallel_model_fitting.R", cohorts_enhanced)
run_step_local("STEP 7: Model Saving", "pipeline/07_model_saving.R", cohorts_enhanced)
run_step_local("STEP 8: Fallback Handling", "pipeline/08_fallback_handling.R", cohorts_enhanced)
```

#### **Parallel Execution (Production)**
```r
# Run steps 4-8 in parallel across cohorts
steps_4_8 <- c(
  "pipeline/04_data_setup.R",
  "pipeline/05_mc_cv_analysis.R", 
  "pipeline/06_parallel_model_fitting.R",
  "pipeline/07_model_saving.R",
  "pipeline/08_fallback_handling.R"
)

run_step_local("STEPS 4-8: Modular Model Fitting", steps_4_8, cohorts_enhanced)
```

#### **Fallback Handling**
```r
# Step 8 automatically handles failures from step 6
# If step 6 fails, step 8 will attempt alternative model fitting strategies
# This ensures the pipeline continues even if some models fail
```

#### **Complete Pipeline Execution**
```r
# Run the entire pipeline from start to finish
# Steps 0-3: Data preparation (unchanged)
# Steps 4-8: Modular model fitting (new structure)
# Step 9: Generate outputs (renamed from step 5)
```

### **Custom Environment Variables**
```r
# Override specific environment variables for testing
cohorts_test <- cohorts_enhanced
cohorts_test$original$env$MC_TIMES <- "5"  # Reduce MC-CV splits for testing
cohorts_test$original$env$FINAL_MODEL_WORKERS <- "2"  # Reduce workers for testing

run_step_local("STEP 6: Parallel Model Fitting", "pipeline/06_parallel_model_fitting.R", cohorts_test)
```

### **Basic Model Fitting**

```r
# Load configuration
source("scripts/config.R")

# Fit models with parallel processing
rsf_model <- fit_rsf(trn = training_data, vars = selected_vars, use_parallel = TRUE)
xgb_model <- fit_xgb(trn = training_data, vars = selected_vars, use_parallel = TRUE)
orsf_model <- fit_orsf(trn = training_data, vars = selected_vars, use_parallel = TRUE)
```

### **Custom Configuration**

```r
# Custom ranger configuration
ranger_config <- configure_ranger_parallel(
  num_threads = 4,
  target_utilization = 0.9,
  memory_efficient = TRUE
)

# Custom XGBoost configuration with GPU
xgb_config <- configure_xgboost_parallel(
  nthread = 8,
  tree_method = 'gpu_hist',
  gpu_id = 0
)

# Custom aorsf configuration
aorsf_config <- configure_aorsf_parallel(
  n_thread = 6,
  check_r_functions = FALSE
)
```

### **Performance Monitoring**

```r
# Monitor ranger performance
ranger_config <- configure_ranger_parallel(use_all_cores = TRUE)
monitor_func <- monitor_ranger_performance(ranger_config)
monitor_func()  # Run in background

# Monitor XGBoost performance
xgb_config <- configure_xgboost_parallel(use_all_cores = TRUE)
monitor_func <- monitor_xgboost_performance(xgb_config)
monitor_func()  # Run in background

# Monitor aorsf performance
aorsf_config <- configure_aorsf_parallel(use_all_cores = TRUE)
monitor_func <- monitor_aorsf_performance(aorsf_config)
monitor_func()  # Run in background
```

### **Benchmarking**

```r
# Benchmark ranger with different thread counts
ranger_results <- benchmark_ranger_threads(
  data = training_data,
  formula = Surv(time, status) ~ .,
  thread_configs = c(1, 2, 4, 8, 16),
  n_tree = 1000,
  n_runs = 3
)

# Benchmark XGBoost with different thread counts
xgb_results <- benchmark_xgboost_threads(
  data = training_matrix,
  label = training_labels,
  thread_configs = c(1, 2, 4, 8, 16),
  nrounds = 500,
  n_runs = 3
)

# Benchmark aorsf with different thread counts
aorsf_results <- benchmark_aorsf_threads(
  data = training_data,
  formula = Surv(time, status) ~ .,
  thread_configs = c(1, 2, 4, 8, 16),
  n_tree = 1000,
  n_runs = 3
)
```

## **📊 Model Passing Summary**

### **What Gets Passed:**
1. **Model Files**: Saved directly to disk by workers (`models/{cohort}/model_*.rds`)
2. **Metadata**: Paths, sizes, timing, success status (`model_data/{cohort}/final_models.rds`)
3. **Error Info**: Error messages and timestamps (`model_data/{cohort}/model_fitting_error.rds`)

### **What Does NOT Get Passed:**
1. **Actual Model Objects**: Too large for memory transfer between steps
2. **Raw Model Data**: Models are serialized to disk immediately
3. **Training Data**: Only metadata about the fitting process

### **Benefits of This Approach:**
1. **Memory Efficient**: No large model objects in memory between steps
2. **Parallel Safe**: Each cohort has isolated files
3. **Fault Tolerant**: Models are saved immediately, not lost on failure
4. **Scalable**: Can handle large models without memory issues
5. **Debuggable**: Easy to inspect individual model files

## **🔍 Monitoring and Debugging**

### **Check Environment Variables**
```r
# Verify environment variables are set correctly
cat("DATASET_COHORT:", Sys.getenv("DATASET_COHORT"), "\n")
cat("MC_CV:", Sys.getenv("MC_CV"), "\n")
cat("FINAL_MODEL_WORKERS:", Sys.getenv("FINAL_MODEL_WORKERS"), "\n")
```

### **Check File Paths**
```r
# Verify cohort-specific files exist
cohort_name <- Sys.getenv("DATASET_COHORT")
data_file <- get_cohort_path(here::here('model_data', 'data_setup.rds'), cohort_name)
cat("Data file:", data_file, "\n")
cat("Exists:", file.exists(data_file), "\n")
```

### **Check Model Files Exist:**
```r
cohort_name <- Sys.getenv("DATASET_COHORT")
models_dir <- here::here('models', cohort_name)
model_files <- c('model_orsf.rds', 'model_rsf.rds', 'model_xgb.rds', 'model_cph.rds', 'final_model.rds')

for (file in model_files) {
  path <- file.path(models_dir, file)
  cat(sprintf("%s: %s (%.2f MB)\n", file, 
              if (file.exists(path)) "EXISTS" else "MISSING",
              if (file.exists(path)) file.size(path)/1024/1024 else 0))
}
```

### **Check Metadata File:**
```r
cohort_name <- Sys.getenv("DATASET_COHORT")
metadata_file <- get_cohort_path(here::here('model_data', 'final_models.rds'), cohort_name)

if (file.exists(metadata_file)) {
  metadata <- readRDS(metadata_file)
  cat("Metadata loaded successfully\n")
  cat(sprintf("Success: %s\n", metadata$success))
  cat(sprintf("Models: %s\n", paste(names(metadata$results), collapse = ", ")))
} else {
  cat("Metadata file not found\n")
}
```

### **Check Log Files**
```r
# Verify step-specific log files
log_file <- get_cohort_log_path("04_data_setup", cohort_name)
cat("Log file:", log_file, "\n")
cat("Exists:", file.exists(log_file), "\n")
```

## **📋 Best Practices**

### **1. Thread Configuration**

- **Use auto-detection**: Set thread parameters to `NULL` or `0` for optimal performance
- **Target utilization**: Use 80-90% of available cores to leave headroom
- **Environment overrides**: Use `MC_WORKER_THREADS` to control worker threads

### **2. Memory Management**

- **Ranger**: Use `memory_efficient = TRUE` for large datasets
- **XGBoost**: Choose appropriate `tree_method` based on dataset size
- **aorsf**: Monitor for R function limitations that require single-threading

### **3. Error Handling**

- **R function limitations**: aorsf automatically limits to single thread when R functions are detected
- **OpenMP compatibility**: Always use positive integers for OpenMP environment variables
- **Worker function availability**: Ensure all required functions are in worker globals

### **4. Performance Optimization**

- **Parallel levels**: Use both package-level and pipeline-level parallelization
- **Resource monitoring**: Use performance monitoring for long-running tasks
- **Benchmarking**: Test different configurations for your specific use case

## **🔍 Troubleshooting Checklist**

### **Common Issues**

1. **`:=` operator error**: Check for `rlang` dependency issues
2. **"all arguments must be named"**: Use `do.call()` with `setNames()`
3. **OpenMP invalid value**: Use positive integers for OpenMP variables
4. **"could not find function"**: Add functions to worker globals
5. **"unused arguments"**: Ensure updated functions are available in workers

### **Debugging Steps**

1. **Check function availability**: Verify all functions are in worker globals
2. **Check environment variables**: Ensure OpenMP variables are positive integers
3. **Check package loading**: Verify all required packages are loaded
4. **Check worker logs**: Look for specific error messages in worker logs
5. **Test locally**: Run functions outside of parallel context first

## **📁 Files Reference**

### **Core Files**

- `R/utils/model_utils.R` - Consolidated parallel processing utilities
- `R/ranger_parallel_config.R` - Ranger-specific parallel configuration
- `R/xgboost_parallel_config.R` - XGBoost-specific parallel configuration
- `R/aorsf_parallel_config.R` - aorsf-specific parallel configuration
- `scripts/config.R` - Global pipeline configuration
- `scripts/04_fit_model.R` - Step 4 model fitting with parallel processing
- `scripts/R/environment_transition.R` - Environment transition utilities

### **Model Files**

- `R/fit_rsf.R` - Ranger model fitting with parallel processing
- `R/fit_xgb.R` - XGBoost model fitting with parallel processing
- `R/fit_orsf.R` - aorsf model fitting with parallel processing
- `R/select_rsf.R` - Ranger feature selection with parallel processing
- `R/select_xgb.R` - XGBoost feature selection with parallel processing

### **Demo Files**

- `scripts/ranger_setup_demo.R` - Ranger parallel processing demo
- `scripts/xgboost_setup_demo.R` - XGBoost parallel processing demo
- `scripts/aorsf_setup_demo.R` - aorsf parallel processing demo

## **⚡ Performance Characteristics**

### **Ranger (RSF)**

- **Parallelization**: Parallel tree building
- **Thread Control**: `num.threads` parameter
- **Default Threads**: 2 (can be overridden)
- **Memory**: Built-in memory efficiency options
- **Limitations**: None

### **XGBoost**

- **Parallelization**: Sequential boosting, parallel tree building
- **Thread Control**: `nthread` parameter
- **Default Threads**: All available (auto-detect)
- **Memory**: Tree method dependent
- **Limitations**: None
- **GPU Support**: Available with `tree_method = 'gpu_hist'`

### **aorsf (ORSF)**

- **Parallelization**: Parallel tree building
- **Thread Control**: `n_thread` parameter
- **Default Threads**: Auto-detect (0)
- **Memory**: Efficient by design
- **Limitations**: R functions limit to single thread
- **Auto-detection**: Built-in optimal thread detection

## **✅ Benefits**

1. **No File Conflicts**: Each cohort has its own data files
2. **Proper Environment Inheritance**: All required variables are passed through
3. **Step Isolation**: Each step has its own log files
4. **Parallel Safety**: Steps can run in parallel without interference
5. **Memory Efficient**: Models are saved to disk, not passed in memory
6. **Fault Tolerant**: Models are saved immediately, not lost on failure
7. **Debugging Friendly**: Easy to trace issues to specific steps/cohorts
8. **Scalable**: Easy to add new cohorts or steps
9. **Maintainable**: Clear separation of concerns
10. **Robust Error Handling**: Comprehensive solutions for common parallel processing issues
11. **Modular Pipeline**: Replaced monolithic 1947-line step with focused, single-responsibility steps
12. **Better Testing**: Each step can be tested in isolation
13. **Resource Management**: Better control over memory and CPU usage per step
14. **Fallback Strategies**: Isolated error handling and recovery mechanisms

## **✅ Final Answer**

**Complete Solution for Parallel Processing Pipeline:**

1. **Models are NOT passed in memory** - they're saved directly to disk by parallel workers
2. **Only metadata is passed** - paths, sizes, timing, and success status
3. **Step 7 loads the metadata** and processes the already-saved model files
4. **Cohort-specific paths** ensure no conflicts in parallel execution
5. **Models are immediately persistent** - no risk of losing them between steps
6. **Environment variables are properly inherited** across all steps
7. **Log files are step-specific and cohort-specific** for better debugging
8. **Common parallel processing issues are resolved** with comprehensive error handling
9. **Multiple parallelization levels** provide optimal performance
10. **Robust configuration system** handles all model types efficiently
11. **Modular pipeline structure** replaces monolithic 1947-line step with focused, maintainable components
12. **Fallback handling** ensures pipeline continues even when individual models fail
13. **Single-responsibility steps** make debugging, testing, and maintenance much easier
14. **Resource management** provides better control over memory and CPU usage per step

This comprehensive solution ensures that the modularized pipeline steps can run in parallel across cohorts without any environment transition issues, model passing problems, or parallel processing errors! 🚀

For additional help, refer to the individual model setup documents:
- `RANGER_PARALLEL_SETUP.md`
- `XGBOOST_PARALLEL_SETUP.md`
- `AORSF_PARALLEL_SETUP.md`
