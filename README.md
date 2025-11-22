# PHTS Graft Loss Prediction Pipeline

This repository contains a comprehensive analytical pipeline for predicting pediatric heart transplant graft loss using data from the Pediatric Heart Transplant Society (PHTS). The workflow replicates and extends the methodology from Wisotzkey et al. (2023), incorporating multiple survival modeling approaches with robust feature selection and evaluation.

## Overview

The PHTS Graft Loss Prediction Pipeline is a complete end-to-end analytical framework for:
- **Data preprocessing** and feature engineering from PHTS registry data
- **Feature selection** using multiple methods (RSF, CatBoost, AORSF)
- **Survival model fitting** with multiple algorithms
- **Model evaluation** using dual C-index calculations (time-dependent and time-independent)
- **Comprehensive reporting** with tables, figures, and documentation

## Project Structure

```mermaid
graph TB
    ROOT[phts] --> GL[graft-loss]
    ROOT --> CI[concordance_index]
    ROOT --> EDA[eda]
    ROOT --> LMTP[lmtp-workshop]
    ROOT --> DL[survival_analysis_deep_learning_asa]

    GL --> GL_feat[feature_importance]
    GL_feat --> GL_nb[graft_loss_feature_importance_20_MC_CV.ipynb]
    GL_feat --> GL_script[replicate_20_features_MC_CV.R]
    GL_feat --> GL_docs[MC-CV READMEs + outputs]

    GL --> GL_cohort[cohort_analysis]
    GL --> GL_surv[cohort_survival_analysis]
    GL --> GL_lasso[lasso]
    GL --> GL_uni[univariate_analysis]
    GL --> GL_unified[unified_cohort_survival_analysis]
```

## Workflow Overview

```mermaid
graph LR
    A[Data Preparation] --> B[Feature Selection]
    B --> C[Model Fitting]
    C --> D[Evaluation]
    D --> E[Output Generation]
    
    A --> A1[Clean PHTS Data]
    A --> A2[Create Features]
    A --> A3[Handle Missing Values]
    
    B --> B1[RSF Permutation]
    B --> B2[CatBoost Importance]
    B --> B3[AORSF Importance]
    
    C --> C1[RSF]
    C --> C2[CatBoost]
    C --> C3[AORSF]
    C --> C4[XGBoost]
    C --> C5[Cox PH]
    
    D --> D1[Time-Dependent C-index]
    D --> D2[Time-Independent C-index]
    D --> D3[Feature Importance]
    D --> D4[Calibration]
    
    E --> E1[Tables]
    E --> E2[Figures]
    E --> E3[Reports]
```

## Key Components

### 1. Feature Importance Analysis (`graft-loss/feature_importance/`)

Comprehensive Monte Carlo cross-validation feature-importance workflow replicating the original Wisotzkey study and extending it:

- **Notebook:** `graft_loss_feature_importance_20_MC_CV.ipynb`  
  - Runs RSF, CatBoost, and AORSF with stratified 75/25 train/test MC-CV splits.  
  - Supports 100-split development runs and 1000-split publication-grade runs.  
  - Evaluates time-dependent and Harrell C-index on held-out test data.

- **Script:** `replicate_20_features_MC_CV.R`  
  - Scripted version of the same MC-CV pipeline (for EC2 / batch runs).

- **Outputs (`graft-loss/feature_importance/outputs/`):**  
  - Top 20 features per method per period (`*_rsf_top20.csv`, `*_catboost_top20.csv`, `*_aorsf_top20.csv`).  
  - C-index comparison tables and summary statistics across methods and cohorts.

### 2. Concordance Index Implementation (`concordance_index/`)

Robust C-index calculation with manual implementation:

- **Time-Dependent C-index**: Matches `riskRegression::Score()` behavior for direct comparison with original study
- **Time-Independent C-index**: Standard Harrell's C-index for general discrimination assessment
- **Documentation**: Comprehensive README explaining methodology, issues, and validation
- **Test Files**: Extensive testing of `riskRegression::Score()` format requirements

### 3. Exploratory Data Analysis (`eda/`)

Initial data exploration and feature importance analysis:

- `phts_eda.qmd`: Exploratory data analysis
- `phts_feature_importance.qmd`: Feature importance across methods

### 4. LASSO Analysis (`lasso/`)

LASSO-based survival analysis and scorecard models:

- `lasso_scorecard_model.qmd`: Scorecard model development
- `survival_analysis_lasso.qmd`: LASSO survival analysis
- `methods_comparison_README.qmd`: Comparison of methods

### 5. Parallel Processing Implementation (`graft-loss/graft-loss-parallel-processing/`)

**Development Strategy**: The pipeline is currently running in **unparallelized mode** for verification. Once the unparallelized version is verified, parallel processing implementations will be integrated.

**Current Status**:
- **Active Pipeline** (`graft-loss/scripts/`): Unparallelized mode (for verification)
- **Parallel Processing Code** (`graft-loss/graft-loss-parallel-processing/`): Ready for integration after verification

**Parallelization Strategies** (to be integrated):
- **furrr/future parallelization**: Parallel Monte Carlo CV splits
- **Orchestration-level parallelism**: Multiple dataset cohorts run as separate processes
- **Threading control**: Environment variables prevent CPU oversubscription
- **Parallel utilities**: Centralized configuration (`R/utils/parallel_utils.R`)

**See `PARALLEL_PROCESSING.md` for comprehensive documentation.**

## Pipeline Stages

### Stage 1: Environment Setup

- **`scripts/00_setup.R`**: Initializes project, loads libraries, sets global options
- **`scripts/packages.R`**: Package management and installation
- **`R/config.R`**: Centralized configuration system

### Stage 2: Data Preparation

- **`scripts/01_prepare_data.R`**: Cleans and preprocesses raw PHTS data
- **`R/clean_phts.R`**: Data cleaning functions
- **`R/make_final_features.R`**: Feature engineering
- **`R/make_labels.R`**: Survival outcome labeling

**Data Source**: `phts_txpl_ml.sas7bdat`
- **File**: `data/phts_txpl_ml.sas7bdat` (matches original study)
- **Censoring Implementation**: The original study's `clean_phts()` function includes proper censoring handling:
  - Sets event times of 0 to 1/365 (prevents invalid zero times for survival analysis)
  - Properly maintains censored observations (status = 0) throughout the analysis
  - Ensures consistent survival structure matching the original Wisotzkey study
- **Why this file**: The original study used `phts_txpl_ml.sas7bdat` specifically because it includes the censoring implementation needed for accurate survival modeling

**Data Coverage**: 2010-2024 (TXPL_YEAR)

**Filtering Options**:
- `EXCLUDE_COVID=1`: Excludes 2020-2023 (approximate COVID period)
- `ORIGINAL_STUDY=1`: Restricts to 2010-2019 (original study period)

### Stage 3: Resampling and Cross-Validation

- **`scripts/02_resampling.R`**: Sets up Monte Carlo cross-validation splits
- **`R/mc_cv_light.R`**: Multi-core CV implementation
- **`R/reuse_resamples.R`**: Split reuse across scenarios

**Monte Carlo CV**:
- Enable with `MC_CV=1`
- Control splits: `MC_MAX_SPLITS=1000`, `MC_START_AT=1`
- Split reuse: `REUSE_BASE_SPLITS=1` for paired comparisons

### Stage 4: Model Data Preparation

- **`scripts/03_prep_model_data.R`**: Prepares data for modeling
- **`R/make_recipe.R`**: Creates preprocessing recipes
- **`R/make_recipe_interpretable.R`**: Interpretable recipe variants

**Dual Data Paths**:
- **Native categoricals**: `final_data_catboost.rds` (for CatBoost, AORSF)
- **Encoded**: `final_data_encoded.rds` (for XGBoost, RSF with dummy coding)

### Stage 5: Model Fitting

- **`scripts/04_fit_model.R`**: Fits multiple survival models
- **`R/fit_rsf.R`**: Random Survival Forest (ranger)
- **`R/fit_orsf.R`**: Oblique Random Survival Forest (aorsf)
- **`R/fit_xgb.R`**: XGBoost Survival
- **`R/fit_cph.R`**: Cox Proportional Hazards

**Models Available**:
- **RSF**: Random Survival Forest with permutation importance
- **AORSF**: Accelerated Oblique Random Survival Forest (matches original study)
- **CatBoost**: Gradient boosting with native categorical handling
- **XGBoost**: Gradient boosting with encoded features
- **Cox PH**: Traditional survival regression

**Model Selection**: Standardized heuristic based on C-index, stability, and interpretability

### Stage 6: Model Evaluation

- **`scripts/05_generate_outputs.R`**: Generates performance metrics and visualizations
- **`R/fit_evaluation.R`**: Model evaluation functions
- **`R/GND_calibration.R`**: Calibration assessment
- **`R/visualize_*.R`**: Visualization functions

**Evaluation Metrics**:
- **Time-Dependent C-index**: At 1-year horizon (matches original study)
- **Time-Independent C-index**: Harrell's C-index (general discrimination)
- **Calibration**: Gronnesby-Borgan test
- **Feature Importance**: Multiple methods (permutation, negate, gain-based)

## Feature Selection Methods

### Workflow Alignment with Original Repository

Our feature selection workflow **matches the original repository** ([bcjaeger/graft-loss](https://github.com/bcjaeger/graft-loss)):

1. **Feature Selection from ALL Variables**: Uses all available variables (not pre-filtered to Wisotzkey variables)
2. **Recipe Preprocessing**: Applies `make_recipe()` → `prep()` → `juice()` with median/mode imputation
3. **Top 20 Selection**: Selects top 20 features using permutation importance (RSF) or feature importance (CatBoost, AORSF)
4. **Wisotzkey Identification**: After selecting top 20, identifies which of those features are Wisotzkey variables (15 core variables from original study)

This workflow ensures:
- **Unbiased feature selection**: Not constrained to pre-defined variable set
- **Reproducibility**: Matches original study methodology exactly
- **Transparency**: Clear identification of Wisotzkey overlap in selected features

**Key Implementation Details**:
- **Data Source**: Uses `phts_txpl_ml.sas7bdat` (matches original study) with proper censoring implementation
- **Censoring Handling**: Event times of 0 are set to 1/365 to prevent invalid survival times
- Excludes outcome/leakage variables (`int_dead`, `int_death`, `graft_loss`, `txgloss`, `death`, `event`)
- Uses `dummy_code = FALSE` for recipe preprocessing (preserves categorical structure)
- Applies same RSF parameters as original: `num.trees = 500`, `importance = 'permutation'`, `splitrule = 'extratrees'`

### RSF Permutation Importance

- **Method**: Random Survival Forest with permutation importance
- **Parameters**: `num.trees = 500`, `importance = 'permutation'`, `splitrule = 'extratrees'`, `num.random.splits = 10`, `min.node.size = 20`
- **Use**: Matches original Wisotzkey study methodology and repository implementation
- **Output**: Top 20 features ranked by permutation importance

### CatBoost Feature Importance

- **Method**: CatBoost gradient boosting with signed-time labels
- **Parameters**: `iterations = 2000`, `depth = 6`, `learning_rate = 0.05`
- **Use**: Captures non-linear relationships and interactions
- **Output**: Top 20 features ranked by gain-based importance

### AORSF Feature Importance

- **Method**: Accelerated Oblique Random Survival Forest (negate method)
- **Parameters**: `n_tree = 100`, `na_action = 'impute_meanmode'`
- **Use**: Matches original study's final model approach
- **Output**: Top 20 features ranked by negate importance

## C-index Calculation

### Dual Implementation

The pipeline calculates **both** time-dependent and time-independent C-indexes for comprehensive evaluation:

#### Time-Dependent C-index

- **Method**: Matches `riskRegression::Score()` behavior
- **Evaluation**: At specific time horizon (default: 1 year)
- **Logic**: Compares patients with events before horizon vs patients at risk at horizon
- **Use**: Direct comparison with original study (~0.74)

#### Time-Independent C-index (Harrell's C)

- **Method**: Standard Harrell's C-index formula
- **Evaluation**: Uses all comparable pairs regardless of time
- **Logic**: Pairwise comparisons where one patient has event and another has later time
- **Use**: General measure of discrimination across entire follow-up

### Implementation Details

- **Primary**: Attempts `riskRegression::Score()` for time-dependent (matching original study)
- **Fallback**: Manual calculation if `Score()` fails
- **Always Calculates**: Time-independent C-index using manual Harrell's C
- **Consistency**: All three methods (RSF, CatBoost, AORSF) use same approach

See `concordance_index/concordance_index_README.md` for detailed documentation.

## Time Period Analysis

The pipeline supports analysis across multiple time periods:

### Original Study Period (2010-2019)

- **Set**: `ORIGINAL_STUDY=1`
- **Matches**: Original Wisotzkey et al. (2023) publication
- **Use**: Direct replication and comparison

### Full Study Period (2010-2024)

- **Default**: All available data
- **Use**: Maximum sample size and contemporary analysis

### COVID-Excluded Period (2010-2024 excluding 2020-2023)

- **Set**: `EXCLUDE_COVID=1`
- **Use**: Sensitivity analysis excluding COVID-affected years

## Quick Start

### Basic Pipeline Run

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" graft-loss/scripts/run_pipeline.R
```

### Original Study Period

```bash
ORIGINAL_STUDY=1 "/c/Program Files/R/R-4.5.1/bin/Rscript.exe" graft-loss/scripts/run_pipeline.R
```

### Monte Carlo Cross-Validation

```bash
MC_CV=1 MC_MAX_SPLITS=1000 USE_CATBOOST=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" graft-loss/scripts/run_pipeline.R
```

### Feature Importance Replication

```r
# From R console or RStudio
source("graft-loss/feature_importance/replicate_20_features.R")
```

This runs RSF, CatBoost, and AORSF feature selection across all three time periods and generates comprehensive comparison tables.

## Output Structure

### Model Artifacts (`graft-loss/data/models/`)

- `model_orsf.rds`, `model_rsf.rds`, `model_xgb.rds`: Fitted models
- `model_comparison_index.csv`: Model metadata and data variants
- `model_mc_metrics_*.csv`: Monte Carlo CV metrics per split
- `model_mc_summary_*.csv`: Aggregated MC CV summaries
- `model_mc_importance_*.csv`: Feature importance across splits
- `final_model_choice.csv`: Selected model with rationale

### Feature Importance Outputs (`graft-loss/feature_importance/outputs/`)

- `*_rsf_top20.csv`: RSF top 20 features (with both C-index types)
- `*_catboost_top20.csv`: CatBoost top 20 features (with both C-index types)
- `*_aorsf_top20.csv`: AORSF top 20 features (with both C-index types)
- `*_comparison_all_periods.csv`: Features ranked across periods
- `*_comparison_wide.csv`: Wide format comparisons
- `cindex_comparison_all_methods.csv`: Combined C-index comparison
- `summary_statistics.csv`: Sample sizes, event rates, C-indexes

### Documentation (`graft-loss/doc/`)

- `predicting_graft_loss.Rmd`: Main manuscript/report
- `jacc.csl`, `refs.bib`: Citation style and bibliography

## Key Features

### Robust C-index Calculation

- **Dual Implementation**: Both time-dependent and time-independent
- **Reliable Fallback**: Manual calculation when `riskRegression::Score()` fails
- **Comprehensive Documentation**: See `concordance_index/concordance_index_README.md`

### Multiple Feature Selection Methods

- **RSF**: Permutation importance (original study method)
- **CatBoost**: Gain-based importance
- **AORSF**: Negate importance (original study's final model)

### Comprehensive Model Comparison

- **Multiple Algorithms**: RSF, AORSF, CatBoost, XGBoost, Cox PH
- **Multiple Time Periods**: Original study, full period, COVID-excluded
- **Multiple Metrics**: Time-dependent and time-independent C-indexes

### Reproducible Workflow

- **Environment Variables**: Control all aspects via flags
- **Logging**: Comprehensive pipeline logs with timestamps
- **Progress Tracking**: JSON progress file for monitoring
- **Split Reuse**: Paired comparisons across scenarios

### Parallel Processing

- **Multiple Strategies**: furrr/future, orchestration-level, and threading control
- **Auto-Configuration**: Automatic worker detection and backend selection
- **Resource Management**: Prevents CPU oversubscription via environment variables
- **EC2-Compatible**: Robust core detection and backend fallbacks for cloud environments

**See `PARALLEL_PROCESSING.md` for detailed documentation.**

## Environment Variables

### Data Filtering

- `EXCLUDE_COVID=1`: Exclude 2020-2023
- `ORIGINAL_STUDY=1`: Restrict to 2010-2019

### Model Selection

- `USE_CATBOOST=1`: Include CatBoost in analysis
- `USE_ENCODED=1`: Use encoded (dummy-coded) data variant
- `CATBOOST_USE_FULL=1`: CatBoost uses all features (default)
- `ORSF_FULL=1`: ORSF uses all features
- `XGB_FULL=1`: XGBoost uses all features

### Monte Carlo CV

- `MC_CV=1`: Enable Monte Carlo cross-validation
- `MC_MAX_SPLITS=1000`: Maximum number of splits
- `MC_START_AT=1`: Starting split index (for resuming)
- `REUSE_BASE_SPLITS=1`: Reuse splits across scenarios
- `MC_XGB_USE_GLOBAL=1`: Use global encoded matrix for XGB (default)
- `MC_SPLIT_WORKERS`: Number of workers for parallel CV splits (auto-detected if not set)
- `MC_WORKER_THREADS`: Threads per worker for BLAS/OpenMP (default: 1)

**See `PARALLEL_PROCESSING.md` for detailed parallel processing documentation.**

### Scenarios

- `SCENARIO=original_study_fullcats`: Original period + full CatBoost features
- `SCENARIO=covid_exclusion_full`: Exclude COVID + full CatBoost
- `SCENARIO=full_all_full`: Full dataset + all models full features

## Recent Updates

### Project Reorganization

- **Feature Importance**: Moved to `graft-loss/feature_importance/`
- **Concordance Index**: New `concordance_index/` directory with documentation
- **EDA**: Organized into `eda/` directory
- **LASSO**: Organized into `lasso/` directory

### Enhanced Feature Selection

- **Added AORSF**: Now includes AORSF alongside RSF and CatBoost
- **Dual C-index**: Both time-dependent and time-independent calculations
- **Comprehensive Comparison**: Across three methods and three time periods

### Improved Documentation

- **Feature Importance README**: Comprehensive guide for `replicate_20_features.R`
- **Concordance Index README**: Detailed explanation of C-index implementation
- **Parallel Processing Documentation**: Complete guide to parallelization strategies (`PARALLEL_PROCESSING.md`)
- **Updated Pipeline README**: Reflects latest structure and capabilities

## Requirements

- **R**: Version 4.5.1 or higher
- **R Packages**: See `graft-loss/scripts/packages.R` for complete list
- **Python** (optional): For CatBoost integration (`python`, `catboost`, `pandas`, `numpy`)
- **Data**: PHTS registry data files (contact repository maintainer for access)

## References

- Wisotzkey et al. (2023). Risk factors for 1-year allograft loss in pediatric heart transplant. *Pediatric Transplantation*.

## Contact

For questions or issues, please refer to the documentation in each component directory or review the inline code comments.

---

**Note**: The pipeline is modular; each script can be run independently or as part of the full workflow. For detailed usage, refer to the README files in each component directory and the inline comments within scripts.

