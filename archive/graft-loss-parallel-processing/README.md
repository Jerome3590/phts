# Parallelization in the Pipeline

This project uses several forms of parallel processing to accelerate model fitting, resampling, and orchestration. Below is a summary of all locations and types of parallelization in the codebase:

## 1. furrr/future Parallelization

- **scripts/04_fit_model.R**: Uses `furrr::future_map` and related functions to fit models and run Monte Carlo cross-validation splits in parallel. The parallel plan is set up using `future::plan` or the utility `setup_parallel_backend()` from `R/utils/parallel_utils.R`. All model saving is performed inside the worker function to ensure robustness.
- **scripts/04_furrr_fit_test.R**: Contains a test harness for parallel model fitting using `future.apply::future_lapply` and `furrr`, with explicit plan setup and worker PID checks.

## 2. Parallel Backend Utilities

- **R/utils/parallel_utils.R**: Provides functions for robust parallel backend setup (`setup_parallel_backend`, `configure_explicit_parallel`) and is sourced by main scripts to ensure consistent parallel configuration.

## 3. Orchestration-Level Parallelism

- **scripts/run_pipeline.R**: Launches three separate R processes in parallel (one per data cohort) using system calls and environment variables. Each process runs the full pipeline for a different cohort.

## 4. Other Parallel/Threaded Operations

- **foreach**, **parallel**, and **future.apply**: Used in some scripts (e.g., slurm helpers, install scripts) for parallel loops or dynamic parallelism.
- **Threading control**: Scripts set environment variables like `OMP_NUM_THREADS`, `MC_WORKER_THREADS`, etc., to avoid CPU oversubscription.

## Best Practices Followed

- All functions and objects needed in parallel workers are defined at the top level or sourced before parallel execution.
- All model saving (e.g., `saveRDS`) is performed inside the worker function, not after, to ensure models are not lost.
- The `.options` argument in furrr/future calls is used to export required packages and globals.
- Parallel plan setup is always performed before any parallel map/apply call.
- No reliance on super assignment (`<<-`) for objects needed in parallel workers.

See comments in `scripts/04_fit_model.R` and the checklist above for more details.

## 5. Logging System

The pipeline uses a **unified logging system** to track execution across all steps and cohorts:

### Log File Structure

All pipeline steps write to cohort-specific log files using the `orch_bg_` naming convention:

- **`logs/orch_bg_original_study.log`** - Original cohort execution
- **`logs/orch_bg_full_with_covid.log`** - Full dataset with COVID period
- **`logs/orch_bg_full_without_covid.log`** - Full dataset without COVID period

### Logging Components

| Component | Purpose | Log Content |
|-----------|---------|-------------|
| **Pipeline Steps** (01-05) | Step execution | Diagnostic info, progress, errors |
| **Model Fitting** | Individual models | Fitting progress, parameters, results, function availability |
| **Parallel Workers** | MC-CV execution | Worker-specific logs per split, function diagnostics |
| **Progress Tracking** | Real-time updates | JSON-based progress metrics |

### Logging Format

All pipeline steps follow a consistent logging format:

```r
# Log file selection
log_file <- switch(Sys.getenv("DATASET_COHORT", unset = ""),
  original = "logs/orch_bg_original_study.log",
  full_with_covid = "logs/orch_bg_full_with_covid.log",
  full_without_covid = "logs/orch_bg_full_without_covid.log",
  "logs/orch_bg_unknown.log"
)

# Standard diagnostic output
cat(sprintf("\n[%s] Starting %s script\n", script_name, step_name))
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
cat("Log file path: ", log_file, "\n")
cat(sprintf("[Diagnostic] Cores available: %d\n", future::availableCores()))
cat("[%s] Diagnostic output complete\n\n", script_name)
```

### Log File Locations

```text
logs/
├── orch_bg_original_study.log          # Original cohort
├── orch_bg_full_with_covid.log         # Full with COVID
├── orch_bg_full_without_covid.log      # Full without COVID
├── models/
│   └── {cohort}/
│       └── full/
│           ├── ORSF_split001.log       # Individual model logs
│           ├── RSF_split001.log
│           └── XGB_split001.log
└── progress/
    └── pipeline_progress.json          # Real-time progress
```

### Function Availability Tracking

Individual model logs include comprehensive function availability diagnostics to debug parallel worker issues:

```text
[FUNCTION_DIAG] Checking function availability for ORSF model...
[FUNCTION_DIAG] Required functions: fit_orsf, configure_aorsf_parallel, get_aorsf_params, orsf, aorsf_parallel, predict_aorsf_parallel
[FUNCTION_DIAG] Available functions: fit_orsf, configure_aorsf_parallel, get_aorsf_params, orsf
[FUNCTION_DIAG] Missing functions: aorsf_parallel, predict_aorsf_parallel
[FUNCTION_DIAG] WARNING: 2 functions missing - model fitting may fail!
```

**What it tracks**:
- **Required functions** for each model type (ORSF, RSF, XGB, CPH)
- **Available functions** in the worker session
- **Missing functions** that could cause failures
- **Success/failure status** for function availability

**Model-specific function requirements**:
- **ORSF**: `fit_orsf`, `configure_aorsf_parallel`, `get_aorsf_params`, `orsf`, `aorsf_parallel`, `predict_aorsf_parallel`
- **RSF**: `fit_rsf`, `configure_ranger_parallel`, `get_ranger_params`, `ranger_parallel`, `predict_ranger_parallel`, `ranger_predictrisk`
- **XGB**: `fit_xgb`, `configure_xgboost_parallel`, `get_xgboost_params`, `xgboost_parallel`, `predict_xgboost_parallel`, `sgb_fit`, `sgb_data`
- **CPH**: `fit_cph`

### Monitoring

- **Real-time monitoring**: `tail -f logs/orch_bg_{cohort}.log`
- **Progress tracking**: `cat logs/progress/pipeline_progress.json`
- **Resource monitoring**: `scripts/resource_monitor.R`
- **Function diagnostics**: `grep "FUNCTION_DIAG" logs/models/{cohort}/full/*.log`

---
# Graft Loss Analytical Pipeline

This repository contains an analytical pipeline for predicting graft loss, implemented in R. The workflow is organized into several stages, each with dedicated scripts and functions. Below is a summary of each step in the analysis:

## 1. Environment Setup

- **environment_setup.R**: Installs and loads required R packages and sets up the computational environment.
- **scripts/install.R** / **scripts/packages.R**: Additional scripts for package management.

## 2. Data Preparation

- **scripts/00_setup.R**: Initializes the project, loads libraries, and sets global options.
- **scripts/01_prepare_data.R**: Cleans and preprocesses raw data, including feature engineering and handling missing values.
- **R/clean_phts.R**, **R/make_final_features.R**, **R/make_labels.R**: Functions for data cleaning, feature creation, and label assignment.

Data coverage: the source dataset spans transplant years 2010–2024 (TXPL_YEAR). The preparation step filters by `min_txpl_year` (default 2010). You can optionally exclude the COVID-affected period when preparing data.

### Wisotzkey Variables and Derived Features

This project uses the 15 Wisotzkey variables as defined in the original study ([bcjaeger/graft-loss](https://github.com/bcjaeger/graft-loss)). Variable names and derivation formulas are documented in `data/wisotzkey_variables.csv` and `phts_eda.qmd`.

**Core Variables** (from raw data):
1. `prim_dx` - Primary Etiology
2. `txmcsd` - MCSD at Transplant (derived from `txnomcsd`, **NO underscore**)
3. `chd_sv` - Single Ventricle CHD
4. `hxsurg` - Surgeries Prior to Listing
5. `txsa_r` - Serum Albumin at Transplant
6. `txbun_r` - BUN at Transplant
7. `txecmo` - ECMO at Transplant
8. `txpl_year` - Transplant Year
9. `weight_txpl` - Recipient Weight at Transplant (lbs)
10. `txalt` - ALT at Transplant
11. `hxmed` - Medical History at Listing

**Derived Variables** (computed in `pipeline/01_prepare_data.R`):

12. **BMI at Transplant** (`bmi_txpl`):
    ```r
    bmi_txpl = (weight_txpl / (height_txpl^2)) * 703
    ```
    - **IMPORTANT**: Uses US formula with 703 conversion factor
    - Input units: weight in pounds, height in inches
    - Reference: `phts_eda.qmd` line 95

13. **eGFR at Transplant** (`egfr_tx`):
    ```r
    egfr_tx = 0.413 * height_txpl / txcreat_r
    ```
    - Pediatric Schwartz formula
    - Handles division by zero (sets to NA if `txcreat_r <= 0`)
    - Reference: `phts_eda.qmd` line 96

14. **PRA at Listing** (`pra_listing`):
    ```r
    pra_listing = lsfprat
    ```
    - Maps from `lsfprat` (PRA T-cell at listing)
    - Reference: `phts_eda.qmd` line 120

15. **Listing Year** (`listing_year`):
    ```r
    listing_year = floor(txpl_year - (age_txpl - age_listing))
    ```
    - Calculated from age difference between transplant and listing
    - Fallback: `txpl_year - 1` if age variables unavailable
    - Reference: `phts_eda.qmd` line 97

### Variable Name Mapping

The pipeline uses cleaned column names after `janitor::clean_names()`. Key mappings from raw SAS data:

| Wisotzkey Feature | Raw SAS Name | Cleaned Name | Notes |
|-------------------|--------------|--------------|-------|
| MCSD at Transplant | `TXNOMCSD` | `txnomcsd` → `txmcsd` | Inverted logic: 'yes' = no support; **NO underscore** |
| PRA at Listing | `LSFPRAT` | `lsfprat` → `pra_listing` | T-cell PRA at listing |
| ALT at Transplant | `TXALT` | `txalt` | Not `txalt_r` |
| BMI at Transplant | — | `bmi_txpl` | Computed (US formula) |
| eGFR at Transplant | — | `egfr_tx` | Computed (Schwartz) |
| Listing Year | — | `listing_year` | Computed from ages |

**Reference Files:**
- Variable descriptions: `data/wisotzkey_variables.csv`
- Original implementation: `phts_eda.qmd` (lines 88-124)
- Data preparation: `pipeline/01_prepare_data.R` (lines 143-180)
- Variable mapping: `scripts/R/make_final_features.R` (lines 14-30)

Exclude COVID period (approximate, by year):

- COVID period approximated as 2020–2023 (month-level dates are not available in prepared data; see notes below).
- Set environment variable `EXCLUDE_COVID=1` to remove rows from those years during `01_prepare_data.R`.



Example (Linux/EC2 bash):

- Without exclusion: `Rscript scripts/run_pipeline.R`
- With exclusion: `EXCLUDE_COVID=1 Rscript scripts/run_pipeline.R`


The pipeline log will print `EXCLUDE_COVID` and pre/post year coverage.

Notes:

- If month-level transplant dates become available in the prepared dataset, refine the exclusion to March 2020 through May 2023 precisely.
- You can reproduce the original study period (2010–2019) by setting `ORIGINAL_STUDY=1`. This filter takes precedence over `EXCLUDE_COVID`.

## 3. Resampling and Cross-Validation

- **scripts/02_resampling.R**: Sets up resampling strategies (e.g., cross-validation, bootstrapping) for model evaluation.
- **R/mc_cv_light.R**, **R/load_mc_cv.R**: Functions for multi-core cross-validation and loading CV results.

## 4. Model Preparation

- **scripts/03_prep_model_data.R**: Prepares data for modeling, including splitting into training and test sets and creating model matrices.
- **R/make_recipe.R**, **R/make_recipe_interpretable.R**: Functions for creating preprocessing recipes for models.

This step now produces two parallel, saved datasets/recipes:

- CatBoost/native categoricals (no dummy coding): `data/final_recipe_catboost.rds`, `data/final_data_catboost.rds` and for backward-compat, `data/final_recipe.rds`, `data/final_data.rds`.
- Encoded (dummy-coded categoricals) for learners requiring numeric inputs: `data/final_recipe_encoded.rds`, `data/final_data_encoded.rds`.

## 5. Model Fitting

- **scripts/04_fit_model.R**: Fits various predictive models to the data.
- **R/fit_cph.R**, **R/fit_rsf.R**, **R/fit_orsf.R**, **R/fit_xgb.R**: Functions for fitting Cox proportional hazards, random survival forests, oblique random survival forests, and XGBoost models.
- **R/fit_step.R**, **R/fit_final_orsf.R**: Stepwise and final model fitting routines.

Selecting input variant at fit-time:

- Default: uses CatBoost/native-categorical variant (`final_data.rds`).
- To force encoded inputs (dummy-coded categoricals), set `USE_ENCODED=1` when running step 04 (or the full runner). This will load `final_data_encoded.rds` instead.



Example (Linux/EC2 bash):

- Default (native categoricals):
  - `Rscript scripts/04_fit_model.R`

- Encoded (dummy-coded):
  - `USE_ENCODED=1 Rscript scripts/04_fit_model.R`


Model comparison:

- Step 04 now fits multiple model families for side-by-side comparison and saves them under `data/models/`:
  - ORSF: `data/models/model_orsf.rds` (also saved as `data/final_model.rds` for backward compatibility)
  - RSF (ranger): `data/models/model_rsf.rds`
  - XGBoost survival (sgb): `data/models/model_xgb.rds`
  - Optional CatBoost and CatBoost+RF variants can be toggled via env vars (see below).
- An index CSV is written to `data/models/model_comparison_index.csv` listing saved models and data variant used.

### Model Selection Heuristic (Standardized)

Primary discrimination metric: mean Monte Carlo C-index on the full dataset label (or single-split test C-index in exploratory `MC_CV=0` mode, treated as preliminary).

Tie / practical equivalence (overlapping 95% C-index CIs within an absolute difference ≤ 0.005):

1. Prefer lower split-wise SD (stability).
2. Prefer broader clinically interpretable feature signal (importance dispersion across plausible predictors, not dominance by one synthetic artifact).
3. If still tied: domain/clinical interpretability consensus (no deployment-simplicity tie-breaker).

Implementation notes:

- Step 05 computes per-model MC summaries and applies this heuristic; selection is written to `data/models/final_model_choice.csv` (future enhancement: add a machine-readable rationale JSON).
- Union importance (RSF + CatBoost) is supportive evidence only—not a direct ranking criterion.
- Single-fit mode (`MC_CV=0`) should not be used for final publication selection; escalate to MC mode.
Artifacts documenting the decision (step 05):

- `data/models/model_selection_summary.csv` / `.md` (ranked manuscript-ready table)
- `data/models/model_selection_rationale.json` (heuristic path + tie-break rule applied)
- `data/models/final_model_choice.csv` (updated with `heuristic_<rule>` chosen_reason)

CatBoost-specific handling:

- If CatBoost (Python) is the selected model after applying the heuristic, we retain CatBoost for performance reporting and use the best available R-native model (ORSF/RSF/XGB/CPH) only for artifacts that require a native R object (e.g., partial dependence plots). CSV exports from the Python helper (predictions, feature importance) drive downstream R analyses. The final choice is logged in `data/models/final_model_choice.csv`.

Cross-reference: Extended rationale in `Updated_Pipeline_README.md` (§15a) and theoretical context in `Survival_Tree_README.md` (§18.5).

Optional models (advanced, requires extra packages/config):

- CatBoost survival: set `USE_CATBOOST=1` (requires the `catboost` R package; survival objective wiring pending—script will acknowledge the flag and skip if unavailable).
- CatBoost+Random Forest: set `USE_CATBOOST_RF=1` to train an RSF on CatBoost-derived features (pending implementation; skipped if unavailable).

## 6. Model Evaluation

- **R/fit_evaluation.R**, **R/plot_pred_variable_smry.R**: Functions for evaluating model performance and summarizing predictions.
- **R/GND_calibration.R**: Assesses model calibration.
- **R/select_cph.R**, **R/select_rsf.R**, **R/select_xgb.R**: Model selection utilities.

## 7. Output Generation

- **scripts/05_generate_outputs.R**: Generates tables, figures, and other outputs for reporting.
- **R/tabulate_characteristics.R**, **R/tabulate_missingness.R**, **R/tabulate_predictor_smry.R**: Functions for creating summary tables.
- **R/visualize_***: Multiple scripts for visualizing results (e.g., feature importance, calibration, partial dependence).

## 8. Documentation

- **doc/predicting_graft_loss.Rmd**: R Markdown file for manuscript and report generation.
- **doc/jacc.csl**, **doc/refs.bib**: Citation style and bibliography files.

## 9. SLURM Integration

- **slurm/slurm_clean.R**, **slurm/slurm_run.R**: Scripts for running and managing jobs on SLURM clusters.

## 10. Utility Functions

- **R/**: Contains additional utility functions for data cleaning, plotting, and analysis.

---

**Note:**

- The pipeline is modular; each script can be run independently or as part of a workflow.
- For detailed usage, refer to the comments within each script and the R Markdown documentation.

## Changes from the original project

The following updates were introduced to make runs more reproducible, easier to debug, and to support COVID-era sensitivity analyses:

- COVID exclusion option (approximate): Data preparation (`scripts/01_prepare_data.R`) now supports excluding COVID-affected years using an environment variable. Set `EXCLUDE_COVID=1` to drop 2020–2023 during preparation. This is an approximate exclusion by year because the prepared dataset currently exposes transplant year (`txpl_year`) but not month-level transplant dates. If a precise date becomes available, the window can be refined to March 2020 through May 2023.
- Year coverage surfaced in logs: Step `01_prepare_data.R` logs pre- and post-filter transplant year coverage, and the pipeline header logs the `EXCLUDE_COVID` flag. The README also documents observed source coverage (2010–2024).
- Robust pipeline runner: `scripts/run_pipeline.R` executes steps 00–05 sequentially with per-step timestamps, durations, and captured warnings/errors. It writes a detailed log to `logs/pipeline_<timestamp>.log` and a machine-readable summary to `logs/pipeline_<timestamp>_summary.csv` to quickly identify where failures occur.
- Hardened partial dependence computation: Functions under `R/` were made resilient to single-level categorical variables and degenerate numeric grids. Variables with fewer than two usable values are skipped with an informative message, preventing contrasts-related errors during predictions.
- Binning policy clarification: We only apply numeric binning (e.g., quantiles) where needed for visualization/partial effects. We do not manually bin categorical predictors; instead we rely on model-native handling when applicable (e.g., CatBoost, if/when used). This keeps feature encoding consistent with the learner’s capabilities and avoids information loss from manual binning.

- Dual prep paths for categorical handling: We now save both a CatBoost-friendly dataset (categoricals left as character/factor with no dummy recoding) and an encoded dataset (dummy-coded categoricals). By default, fitting uses the native-categorical dataset; set `USE_ENCODED=1` to select the encoded path for learners that require numeric inputs.

### Compare performance with and without COVID years

Run the full pipeline with the following variants and compare the resulting diagnostics/metrics from step 05:

- Full data (no exclusion):
  - `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R`
- Excluding COVID years (approx 2020–2023):
  - `EXCLUDE_COVID=1 "/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R`
- Original-study period (2010–2019):
  - `ORIGINAL_STUDY=1 "/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R`

Each run will record the `EXCLUDE_COVID` value and year coverage in the logs, and the summary CSV will indicate whether any step raised warnings/errors. You can then compare the artifacts produced in `data/outputs/` and any performance summaries generated in step 05.

### Reproduce original study period (2010–2019)

- Apply the original window during data prep:
  - `ORIGINAL_STUDY=1 "/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R`
- This filter keeps rows with `txpl_year` in 2010–2019 and overrides `EXCLUDE_COVID` if both are set.

### Full Monte Carlo Cross-Validation (MC CV)

Step `04_fit_model.R` can run full Monte Carlo CV across the resamples created in step 02. Controls are via environment variables:

- Enable MC CV: set `MC_CV=1`
- Optional: start split index (1-based): `MC_START_AT=1`
- Optional: max number of splits to run: `MC_MAX_SPLITS=25`
- Optional: include Python CatBoost in MC loop: `USE_CATBOOST=1` (see requirements below)

Outputs when MC_CV=1:

- Full dataset:
  - Per-split metrics: `data/models/model_mc_metrics_full.csv` (columns: `split, model, cindex`)
  - Aggregated summary: `data/models/model_mc_summary_full.csv`
- Original study dataset (2010–2019):
  - Per-split metrics: `data/models/model_mc_metrics_original.csv`
  - Aggregated summary: `data/models/model_mc_summary_original.csv`

Notes:

- Models evaluated per split: ORSF, RSF (ranger), XGB survival, CPH (Cox); CatBoost (Python) if `USE_CATBOOST=1`.
- In MC mode, we do not save single-fit model artifacts (`model_*.rds`) for each split to avoid large I/O; instead we compute metrics on the fly and write the summary files above.
- The runner logs `MC_CV`, `MC_START_AT`, and `MC_MAX_SPLITS` at the top of each run.

Feature importance aggregation and normalized tables:

- Per-split FI (if enabled) and aggregated FI are written by step 04:
  - Per-split FI: `data/models/model_mc_importance_splits_full.csv`, `data/models/model_mc_importance_splits_original.csv`
  - Aggregated FI: `data/models/model_mc_importance_full.csv`, `data/models/model_mc_importance_original.csv`
- Step 05 produces simple, normalized FI views (0–1 within each model) and occurrence counts:
  - `data/models/model_mc_importance_normalized.csv` (columns: dataset, model, feature, n_splits, mean_importance, normalized_importance)
  - `data/models/model_mc_importance_by_model.csv` (columns: dataset, model, total_features, total_feature_occurrences)

Example (Windows bash):

- Run MC CV on first 50 splits with CatBoost enabled:
  - `USE_CATBOOST=1 MC_CV=1 MC_MAX_SPLITS=50 "/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R`
  - To start at split 101 and run 50 splits: add `MC_START_AT=101`

### CatBoost (Python) requirements

CatBoost integration uses a small Python helper `scripts/py/catboost_survival.py` that treats signed time (positive=event, negative=censored) as a regression proxy for survival risk.

Requirements:

- Python 3 available on PATH as `python`
- `pip install catboost pandas numpy`

Usage:

- Single-split (non-MC mode): set `USE_CATBOOST=1` and run step 04 or the full pipeline. The script will use the first resample split if available (else a reproducible 80/20 split), save artifacts under `data/models/catboost/`, and append to `data/models/model_comparison_index.csv`. Step 05 will include CatBoost in the single-split C-index comparison.
- MC mode: set `USE_CATBOOST=1 MC_CV=1` and CatBoost will run per split, writing per-split predictions transiently and contributing C-index rows in `model_mc_metrics.csv` (no per-split model artifacts retained).

CatBoost-selected workflow (CSV handoff to R):

- When CatBoost remains the selected model after applying the heuristic (i.e., leads the primary metric and no tie-break overrides), step 05 records this in `data/models/final_model_choice.csv` and proceeds using CatBoost for performance reporting. For partial dependence plots (which require R-native objects), step 05 automatically uses the best available R-native model instead.
- The Python helper emits CSV artifacts that R can import for analysis:
  - Predictions: `data/models/catboost/catboost_predictions.csv` (aligned to the evaluation split)
  - Feature importance: `data/models/catboost/catboost_importance.csv`
- You can read these CSVs in R (e.g., with `readr::read_csv`) for tables/figures that reference the CatBoost-selected model.

Step 05 also emits convenience CSVs when CatBoost artifacts are present:

- Top features with normalized importance (0–1): `data/models/catboost/catboost_top_features.csv`
- Prediction summary stats: `data/models/catboost/catboost_predictions_summary.csv`

### XGBoost preprocessing (no fail-fast)

XGBoost survival now relies on upfront preprocessing rather than failing early for non-numeric predictors:

- Step 03 produces an encoded dataset (`final_data_encoded.rds`) containing only numeric predictors via the recipe dummy-coding pipeline.
- Step 04 always fits XGB using this encoded dataset; the model comparison index marks `use_encoded=1` for XGB.
- The `fit_xgb` function still accepts native-categorical data but will coerce any residual non-numeric columns to integer codes (factor/character level indices) and emit an informational message, avoiding abrupt termination.

Why this change:

- Eliminates mid-pipeline failures caused by overlooked categorical variables.
- Centralizes encoding in a single reproducible place (step 03), making feature space explicit and inspectable.
- Simplifies `04_fit_model.R` by removing conditional auto-encode fallback logic.

Recommendations:

- For strict reproducibility, rely on `final_data_encoded.rds` (default behavior for XGB now). Inspect `data/diagnostics/columns_after_encoded.csv` if you need to audit the encoded feature set.
- If you prefer experimenting with alternative encoding schemes, modify `make_recipe()` or duplicate it (e.g., `make_recipe_xgb()`) and regenerate step 03 artifacts.
- Avoid interpreting integer codes from the coercion path as ordinal; they are arbitrary level indices. Use the encoded dataset for any downstream feature importance narratives.

Restoring fail-fast (optional): If you want the pipeline to stop when non-numeric predictors are encountered, reintroduce a guard in `R/fit_xgb.R` where the coercion message is logged.

### Monte Carlo CV: XGB encoding strategy

By default (`MC_XGB_USE_GLOBAL=1`), Monte Carlo CV reuses the globally pre-encoded dataset (`final_data_encoded.rds`) for every split when training XGBoost. This ensures:

- Stable feature space across splits (no drift in dummy column presence/order when a level is absent in a training fold).
- Faster execution (no per-split recipe prep/bake for XGB).
- Simplified feature importance aggregation (same column universe each split).

Potential trade-off: Using a globally prepared encoded matrix introduces a very small degree of preprocessing look-ahead (levels observed across the full dataset are retained even if absent in a split’s training portion). For high-cardinality categoricals with rare levels, this means some all-zero columns may appear in a particular split. Empirically, the bias impact is negligible relative to the stability benefits, especially for tree-based boosting. If you require strict per-split isolation of feature engineering, set:

```bash
MC_XGB_USE_GLOBAL=0
```json

In that case the pipeline falls back to per-split dummy encoding (previous behavior) and columns can vary across splits; feature importance aggregation then reflects only encountered columns.

Original study subset: The same logic applies; when `MC_XGB_USE_GLOBAL=1`, a dedicated encoded matrix for the 2010–2019 subset is constructed once and reused across its CV splits.

Recommendation: Keep the global setting (`MC_XGB_USE_GLOBAL=1`) for production runs to maximize reproducibility and comparability. Use the per-split mode only for methodological sensitivity checks.

### Reusing identical MC CV splits across scenarios

When comparing Full vs Original Study (2010–2019) vs COVID-Excluded (drop 2020–2023) scenarios, using a shared Monte Carlo split design improves comparability (paired-like evaluation). The pipeline supports this via ID-based split reuse.

Mechanism:

- First full-data run (without filters) generates `model_data/resamples.rds` and now also saves `model_data/resamples_ids_full.rds` (list of test-set patient ID vectors for each split) if an `ID` column is present.
- For subsequent scenario runs set `REUSE_BASE_SPLITS=1`; step 02 maps each base split's patient IDs onto the filtered dataset, dropping any split whose test set becomes too small or event-free (thresholds: min 25 rows, at least 1 event; configurable in `reuse_resamples.R`).
- Resulting mapped splits are saved again as `model_data/resamples.rds` and used normally by step 04.

Environment flags summary for reuse:

- `REUSE_BASE_SPLITS=1`: activate mapping instead of regenerating splits.
- `ORIGINAL_STUDY=1`: restrict to 2010–2019 (overrides COVID exclusion).
- `EXCLUDE_COVID=1`: remove 2020–2023 (ignored if `ORIGINAL_STUDY=1`).
- `MC_CV=1 MC_MAX_SPLITS=1000`: enable 1000-way MC CV.
- `USE_CATBOOST=1`: include CatBoost.
- `MC_XGB_USE_GLOBAL=1`: global encoded XGB feature space.

Recommended three-run workflow (generate base splits once, then reuse):

1. Full dataset (base splits creation)

```bash
MC_CV=1 MC_MAX_SPLITS=1000 MC_XGB_USE_GLOBAL=1 USE_CATBOOST=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R
```json

1. Original study (2010–2019) reusing base splits

```bash
ORIGINAL_STUDY=1 REUSE_BASE_SPLITS=1 MC_CV=1 MC_MAX_SPLITS=1000 \
MC_XGB_USE_GLOBAL=1 USE_CATBOOST=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R
```

1. COVID-excluded (drop 2020–2023) reusing base splits

```bash
EXCLUDE_COVID=1 REUSE_BASE_SPLITS=1 MC_CV=1 MC_MAX_SPLITS=1000 \
MC_XGB_USE_GLOBAL=1 USE_CATBOOST=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R
```

Notes / caveats:

- Some base splits may shrink after filtering; these are discarded if they fall below thresholds, so the number of usable splits may be < 1000 for filtered scenarios (inspect log messages).
- If you require exactly 1000 valid splits in each filtered scenario, consider regenerating dedicated splits inside each scenario (do NOT set `REUSE_BASE_SPLITS`) or relax thresholds in `reuse_resamples()`.
- Pairwise statistical comparisons (e.g., paired t-tests on per-split C-index deltas) are valid only across the subset of splits retained in both scenarios.
- To audit retained split counts, check logs from step 02 and the number of rows in `model_mc_metrics_*.csv` per model.

Configuration adjustment:

- Change minimum test size or event threshold by editing `R/reuse_resamples.R` (`min_test_n`, `min_test_events`).

This reuse strategy balances reproducibility and fair comparison across temporal or policy-based cohort definitions without regenerating stochastic resampling structures.

### Running the pipeline: foreground vs background (logging & monitoring)

Long Monte Carlo CV runs (e.g., 1000 splits with CatBoost) can be executed either in the foreground (interactive console output) or in the background (detached with logs written to a file). This section explains both modes, how to monitor progress, and how to stop or resume.

#### Foreground mode (interactive output)

Pros: Immediate visibility of progress and messages.  
Cons: Ties up the terminal session; accidental terminal closure aborts the run.

Example (original-study 1000 splits with CatBoost and global XGB encoding):

```bash
ORIGINAL_STUDY=1 MC_CV=1 MC_MAX_SPLITS=1000 USE_CATBOOST=1 MC_XGB_USE_GLOBAL=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R
```

#### Background mode (log to file)

Pros: Frees the terminal; durable log file; can tail from multiple shells.  
Cons: No live output unless you tail the log.

```bash
ORIGINAL_STUDY=1 MC_CV=1 MC_MAX_SPLITS=1000 USE_CATBOOST=1 MC_XGB_USE_GLOBAL=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R \
> logs/original_study_mc_1000.log 2>&1 &
```

Note: The `&` backgrounds the process; `> file 2>&1` redirects stdout and stderr to the log.

#### Monitoring a background run

Tail live:

```bash
tail -f logs/original_study_mc_1000.log
```

Show last 40 lines periodically (if `watch` available):

```bash
watch -n 30 'tail -n 40 logs/original_study_mc_1000.log'
```

Current step (search most recent STEP START):

```bash
grep '\[STEP START' logs/original_study_mc_1000.log | tail -n 1
```

Counting completed splits for a model (example ORSF) once metrics file exists:

```bash
grep -c ',orsf,' data/models/model_mc_metrics_original.csv
```

Disk usage sanity check:

```bash
du -sh data/models
```

#### Gracefully stopping a background run

List Rscript processes:

```bash
ps -W | grep -i Rscript
```

Terminate (Windows):

```bash
taskkill //PID <PID> //F
```

Or via POSIX kill (if supported):

```bash
kill -9 <PID>
```

Confirm stopped:

```bash
ps -W | grep -i Rscript || echo "No active Rscript"
```

#### Resuming / continuing a large MC CV run

If the run stops partway (e.g., after 350 splits), you can resume from the next index by setting `MC_START_AT` and ensuring `resamples.rds` still has the original resample list:

```bash
ORIGINAL_STUDY=1 MC_CV=1 MC_START_AT=351 MC_MAX_SPLITS=1000 USE_CATBOOST=1 MC_XGB_USE_GLOBAL=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R
```

Implementation detail: The current pipeline design assumes idempotent per-split metric appends; if the metrics file already contains earlier split indices, resumed splits will append new rows. Deduplication (if needed) can be performed afterward using `dplyr::distinct(split, model, .keep_all = TRUE)`.

#### Choosing a mode

| Scenario | Recommendation |
|----------|----------------|
| Short exploratory (<=25 splits) | Foreground |
| Long production (>=200 splits) | Background with log tail |
| Remote / unstable shell | Background + periodic checksum of log size |

#### Common pitfalls

- Forgetting to tail the log → appears “stuck” though running.  
- Closing terminal in foreground mode → aborts run mid-split.  
- Overwriting logs accidentally → use unique filenames (e.g., include timestamp).  
- Resuming with wrong `MC_START_AT` → duplicate or skipped splits. Inspect the highest `split` value in metrics CSV first.

#### Quick helper (optional alias)

You can add a convenience alias in your bash profile (adjust path as needed):

```bash
alias run_orig_mc_bg='ORIGINAL_STUDY=1 MC_CV=1 MC_MAX_SPLITS=1000 USE_CATBOOST=1 MC_XGB_USE_GLOBAL=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/run_pipeline.R > logs/original_study_mc_1000_$(date +%Y%m%d_%H%M%S).log 2>&1 &'
```

Then launch with:

```bash
run_orig_mc_bg
```

This foreground/background guidance should reduce confusion about “missing” terminal output and standardize long-run monitoring practices.

### Live machine-readable progress (pipeline + MC CV)

In addition to log output, the pipeline now writes a lightweight JSON progress artifact you can poll or parse programmatically:

Path: `data/progress/pipeline_progress.json`

Schema (fields may appear as they become relevant):

```json
{
  "timestamp": ISO8601 string,
  "current_step": "04_fit_model" | etc.,
  "step_index": integer (1-based),
  "total_steps": 6,
  "step_names": ["00_setup", ..., "05_generate_outputs"],
  "status": "running" | "success" | "error",
  "mc": {
     "dataset_label": "full" | "original" | ...,
     "split_done": n_completed_splits,
     "split_total": configured_total_or_max,
     "percent": 0–100 numeric,
     "elapsed_sec": seconds_since_mc_started,
     "avg_sec_per_split": rolling_mean_seconds,
     "eta_sec": estimated_seconds_remaining
  },
  "note": optional string
}
```

Updates occur:

- At the start and end of every pipeline step (scripts/run_pipeline.R)
- After each Monte Carlo split inside step 04 (`run_mc`) when `MC_CV=1`

Quick view helper:

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/show_progress.R
```

Example JSON while MC CV is mid-run (illustrative):

```json
{
  "timestamp": "2025-02-12T14:33:21-0500",
  "current_step": "04_fit_model",
  "step_index": 5,
  "total_steps": 6,
  "step_names": ["00_setup","01_prepare_data","02_resampling","03_prep_model_data","04_fit_model","05_generate_outputs"],
  "status": "running",
  "mc": {
    "dataset_label": "full",
    "split_done": 240,
    "split_total": 1000,
    "percent": 24.0,
    "elapsed_sec": 5821.4,
    "avg_sec_per_split": 24.3,
    "eta_sec": 18570.2
  }
}
```

Monitoring strategies using the progress file:

- Plain cat: `cat data/progress/pipeline_progress.json`
- Pretty print in R: `Rscript -e "jsonlite::prettify(readLines('data/progress/pipeline_progress.json'))"`
- Parse percent in bash: `jq -r '.mc.percent' data/progress/pipeline_progress.json` (if `jq` installed)
- Watch loop (POSIX): `watch -n 30 'grep percent data/progress/pipeline_progress.json'`

Error handling:

- If a step ends with an error, `status` will be `error`; the file remains so downstream monitors can detect failure.
- During rapid writes (immediately after a split), a very brief read race might yield a partially written file; the helper script handles this by retrying (current implementation exits gracefully—rerun after a second).

Integration notes:

- The JSON overwrites atomically via a temporary file rename to minimize partial reads.
- Downstream dashboards / SLURM job monitors can parse `percent` + `eta_sec` to display progress bars.
- Extensible: additional keys (e.g., memory stats) can be added later without breaking existing consumers.

Disable / reduce writes (future option): if you need to reduce I/O on extremely high split counts, an interval environment variable (e.g., `PROGRESS_WRITE_EVERY`) could be added; not yet implemented.

When MC_CV=0 (single-fit exploratory mode) the `mc` block is absent; only step-level entries appear.

### Note on 25-split tri-scenario runs

We previously provided a Windows-only helper script to automate three independent 25-split MC CV runs. To reduce complexity, that helper has been removed. When you want a 25-split run:

- Use the central driver notebook (`graft_loss_three_datasets.ipynb`) to orchestrate Steps 01–05 and render results; or
- Run the R scripts directly with `MC_CV=1` and `MC_MAX_SPLITS=25` for your chosen cohort label(s).

This removal does not change how metrics are computed. Uno’s 1-year C-index and Harrell’s C are identical; only the number of splits affects the variance and confidence intervals of aggregated summaries.

#### New: CatBoost full feature option and RSF+CatBoost union importance

CatBoost now has an environment-controlled option to bypass the RSF-selected feature subset and train on *all* available native predictors (excluding only `time`, `status`, and `ID`). This avoids upstream feature pruning biasing CatBoost’s internal split finding and feature importance.

Environment variable:

- `CATBOOST_USE_FULL=1` (default if unset): Use the full native feature set from `final_data.rds`.
- `CATBOOST_USE_FULL=0`: Revert to the RSF-selected subset (`final_features$variables`).

Rationale:

- RSF-driven selection collapses dummy-level terms to variable names; if only one dummy indicator survived selection for a categorical variable, CatBoost would see that category as a single collapsed feature — reducing diversity of categorical signals.
- Allowing CatBoost its full native feature space lets its ordered boosting and native categorical handling explore interactions without pre-elimination side-effects.

Logging:

- Step 04 logs either `CatBoost: using full native feature set (N variables)` or `CatBoost: using selected feature subset (M variables)`.

#### RSF (Ranger) + CatBoost union feature importance (MC CV)

When Monte Carlo CV (`MC_CV=1`) runs include both RSF (`RSF`) and CatBoost (`CatBoostPy`) models, step 04 now emits a *union* importance table aggregating their signals:

Artifacts (per dataset label: `full`, `original`, etc.):

- Base per-model aggregated FI: `data/models/model_mc_importance_<label>.csv`
- Union file: `data/models/model_mc_importance_union_rsf_catboost_<label>.csv`
- Top 50 union slice: `data/models/model_mc_importance_union_rsf_catboost_top50_<label>.csv`

Computation details:

1. Extract mean importances per feature for RSF and CatBoost.
2. Normalize each model’s mean importance to [0,1] independently:
   - If all importances identical (degenerate range), they are assigned 1.
3. Perform a full outer join (set union) on feature names.
4. Compute `combined_score = mean(available normalized scores)` — if a feature exists in only one model, its combined score equals that model’s normalized score.
5. Rank descending by `combined_score` (ties get the same rank via `min_rank`).

Columns in union file:

- `feature` – feature name
- `rsf_mean`, `cb_mean` – raw mean importances (may be NA if absent in that model)
- `rsf_norm`, `cb_norm` – per-model [0,1] scaled importances
- `combined_score` – average of available normalized scores
- `combined_rank` – rank (1 = most important by combined metric)

Use cases:

- Present a consensus feature importance that leverages both a traditional ensemble (RSF) and gradient boosting with native categorical splits (CatBoost).
- Detect features uniquely highlighted by one model (look for NA in the other model’s mean column but high combined score).

Interpretation notes:

- Normalization per model prevents one model’s raw scale from dominating the combined score.
- A feature exclusive to one model can still rank highly if that model assigns strong relative importance.
- For strict comparability across time windows (e.g., full vs original), compare `combined_score` distributions or overlap in top-ranked features.

Disabling union output:

- Omit either model (unset `USE_CATBOOST` or skip RSF permutation importance) and the union file will not be generated; a log message indicates why.

Future extensions (not yet implemented):

- Weighted combination (e.g., weight by model mean C-index) instead of simple average.
- Stability-adjusted scores incorporating split-wise variance or presence frequency.

### Full-feature model flags

These flags allow individual models to bypass the RSF-selected feature subset and use the complete available predictor set.

| Model | Flag variants (any accepted) | Default if unset | Effect |
|-------|------------------------------|------------------|--------|
| ORSF (oblique RF) | `ORSF_FULL`, `AORSF_FULL`, `ORSF_USE_FULL`, `AORSF_USE_FULL` | OFF | Use all (native or encoded) predictors instead of `final_features` subset. |
| XGBoost | `XGB_FULL`, `XGB_USE_FULL` | OFF | Use every encoded predictor column (minus time/status). |
| CatBoost | `CATBOOST_USE_FULL`, `CATBOOST_FULL` | ON | Use all native predictors (minus time/status/ID). |

Notes:

- CatBoost defaults to full features because its native categorical handling benefits from full exposure.
- ORSF and XGBoost keep subset defaults to preserve runtime and feature importance stability; enable their full mode for sensitivity analyses.
- All flags treat `1,true,TRUE,yes,y` (case-insensitive) as ON.

### Scenario bundles (SCENARIO)

Instead of setting multiple flags manually, set `SCENARIO` to a bundle name. Bundles only set variables that were previously unset (manual environment assignments take precedence). Implemented in `R/scenario_controller.R`.

Current bundles:

| SCENARIO | Description | Variables set (if missing) |
|----------|-------------|----------------------------|
| `original_study_fullcats` | Original 2010–2019 window + full CatBoost features | `ORIGINAL_STUDY=1`, `EXCLUDE_COVID=0`, `CATBOOST_USE_FULL=1` |
| `covid_exclusion_full` | Exclude 2020–2023 + full CatBoost features | `EXCLUDE_COVID=1`, `ORIGINAL_STUDY=0`, `CATBOOST_USE_FULL=1` |
| `full_all_full` | Full dataset + all models full features | `EXCLUDE_COVID=0`, `ORIGINAL_STUDY=0`, `CATBOOST_USE_FULL=1`, `XGB_FULL=1`, `ORSF_FULL=1` |
| `original_plus_xgb` | Original window + XGBoost full features | `ORIGINAL_STUDY=1`, `XGB_FULL=1` |
| `original_plus_all` | Original window + all models full features | `ORIGINAL_STUDY=1`, `CATBOOST_USE_FULL=1`, `XGB_FULL=1`, `ORSF_FULL=1` |
| `full_catboost_xgb` | Full dataset + CatBoost & XGB full features | `CATBOOST_USE_FULL=1`, `XGB_FULL=1` |
| `full_minimal` | Full dataset with all full-feature modes disabled | `CATBOOST_USE_FULL=0`, `XGB_FULL=0`, `ORSF_FULL=0` |

### Precedence rules

1. If you export an explicit env var (e.g., `XGB_FULL=0`) before running, the scenario bundle will not override it.
2. Scenario variables are resolved very early (sourced in `scripts/00_setup.R`).
3. You can still override after scenario resolution by re-exporting a variable before invoking step scripts.

### Examples

Full dataset, all models full features, 25 MC splits:

```bash
SCENARIO=full_all_full MC_CV=1 MC_MAX_SPLITS=25 USE_CATBOOST=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/04_fit_model.R
```

Original study window, only XGBoost full features, CatBoost disabled:

```bash
SCENARIO=original_plus_xgb USE_CATBOOST=0 MC_CV=1 MC_MAX_SPLITS=10 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/04_fit_model.R
```

Force CatBoost subset (even though scenario would enable full):

```bash
SCENARIO=full_all_full CATBOOST_USE_FULL=0 USE_CATBOOST=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/04_fit_model.R
```

Minimal full-dataset baseline vs full-all sensitivity (two runs):

```bash
# Baseline subset features
SCENARIO=full_minimal MC_CV=1 MC_MAX_SPLITS=50 USE_CATBOOST=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/04_fit_model.R
# All models full feature space
SCENARIO=full_all_full MC_CV=1 MC_MAX_SPLITS=50 USE_CATBOOST=1 \
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/04_fit_model.R
```

### Recommended usage

- Use scenario bundles for reproducible, named configurations in scripts / SLURM submissions.
- Pair each published result set with the exact `SCENARIO` and any overridden flags in a run log.
- For methodological appendices, compare performance deltas between `full_minimal` and `full_all_full` to quantify sensitivity to feature pruning.

---

## Partial dependence: binary numeric handling

`R/make_final_partial.R` now treats numeric binary predictors (exactly two unique observed values after removing NAs) as two-level variables for partial dependence. Instead of using numeric quantiles—which can collapse to a single value for rare binaries—the function evaluates both observed levels. If only one level is present in the data, the variable is skipped with an informative message. This improves interpretability for variables like `dtx_patient` without changing model fitting.

## Parallel execution (explicit plans)

We now select the parallel backend explicitly via the `MC_PLAN` environment variable:

- `MC_PLAN=cluster` (default): explicit PSOCK cluster using parallelly::makeClusterPSOCK (cross‑platform reliable)
- `MC_PLAN=multisession`: uses future::multisession
- `MC_PLAN=multicore`: uses future::multicore (Linux/macOS only)

Tune worker/process counts with:
- `MC_SPLIT_WORKERS` – number of workers (defaults to ~80% of available cores)
- `MC_WORKER_THREADS` – per‑worker BLAS/OMP thread cap (default 1)

Quick parallel sanity test:

```r
Sys.setenv(MC_SPLIT_WORKERS = "12", MC_WORKER_THREADS = "1")
source("scripts/04_furrr_fit_test.R")
```

If you see only one PID in the output, set `MC_PLAN=cluster` explicitly:

```r
Sys.setenv(MC_PLAN = "cluster")
source("scripts/04_furrr_fit_test.R")
```

The pipeline scripts `scripts/04_fit_model.R` and `scripts/04_fit2_model.R` use the same explicit plan logic and preload required packages on workers to avoid per‑task library overhead.

## Recommended Linux/EC2 settings (32 cores, 1TB RAM)

- MC_PLAN: multicore (Linux only, lowest overhead)
- MC_WORKER_THREADS: 1 (prevents BLAS/OMP oversubscription)
- MC_SPLIT_WORKERS per cohort: 8 (total 24 for 3 cohorts)

**Example launch for each cohort (in separate R sessions/terminals):**

```r
# Cohort A
Sys.setenv(DATASET_COHORT="full_with_covid", MC_PLAN="multicore", MC_SPLIT_WORKERS="8", MC_WORKER_THREADS="1")
source("scripts/04_fit_model.R")

# Cohort B
Sys.setenv(DATASET_COHORT="original", MC_PLAN="multicore", MC_SPLIT_WORKERS="8", MC_WORKER_THREADS="1")
source("scripts/04_fit_model.R")

# Cohort C
Sys.setenv(DATASET_COHORT="full_without_covid", MC_PLAN="multicore", MC_SPLIT_WORKERS="8", MC_WORKER_THREADS="1")
source("scripts/04_fit_model.R")
```

**Notes:**

- With 32 cores, using 8 workers per cohort (total 24) leaves headroom for OS and I/O, maximizing throughput without oversaturating CPU.
- MC_WORKER_THREADS=1 is critical for best performance and stability.
- If you observe memory pressure, you can safely increase MC_SPLIT_WORKERS (RAM is not a bottleneck at 1TB).
- If you need to throttle CPU usage, reduce MC_SPLIT_WORKERS per cohort.
- For non-Linux systems, use MC_PLAN="multisession" instead of "multicore".
- For very large datasets, monitor RAM usage with `htop` or `free -g`.

## 6. Continuous Improvement Process

The pipeline uses a **feedback-driven approach** to continuously improve model implementation and prevent regression errors.

### Error-Driven Development

Our implementation process is guided by real-world errors encountered during model fitting and logging:

1. **Monitor Model Logs**: All model fitting generates detailed logs in `logs/models/{cohort}/full/`
2. **Capture Error Patterns**: Document recurring error types and their solutions
3. **Update Implementation Checklist**: Refine `MODEL_WORKER_IMPLEMENTATION_CHECKLIST.md` based on errors
4. **Prevent Regression**: Use checklist to avoid repeating the same errors

### Implementation Checklist

We maintain a comprehensive checklist for implementing models in parallel worker sessions:

- **`MODEL_WORKER_IMPLEMENTATION_CHECKLIST.md`**: Complete implementation guide
- **AORSF Baseline**: Reference implementation for all other models
- **Error Patterns**: Documented solutions for 9+ common error types
- **Prevention Rules**: Proactive measures to avoid known issues

### Documented Error Patterns

Our checklist includes solutions for these common error patterns:

| Error Type | Example | Solution | Prevention |
|------------|---------|----------|------------|
| **Function Not Found** | `could not find function "configure_aorsf_parallel"` | Add to globals list | Include all required functions in globals |
| **Parameter Mismatch** | `unrecognized arguments: min_obs_in_leaf_node` | Update parameter names | Verify package version compatibility |
| **Scoping Issues** | `could not find function ":="` | Avoid rlang operators | Use base R alternatives |
| **Threading Errors** | `libgomp: Invalid value for OMP_NUM_THREADS: 0` | Set positive integers | Validate environment variables |
| **Data Source Mismatch** | `newdata is unrecognized - did you mean new_data?` | Add backward compatibility | Implement tryCatch fallbacks |
| **R Version Issues** | `ReadItem: unknown type 0` | Recreate data on the fly | Provide fallback data creation |
| **Logging Conflicts** | `cannot open the connection` | Use consistent logging | Avoid mixing sink() and file operations |
| **Function Availability** | `unused argument (use_parallel = TRUE)` | Source functions before globals | Get latest function versions |
| **Model Configuration** | `cannot compute out-of-bag predictions` | Validate parameter values | Check model requirements |
| **Parameter Name Mismatch** | `unused arguments (num.trees = 500, min.node.size = 20)` | Convert parameter names in wrapper functions | Ensure parameter name consistency |

### Continuous Improvement Workflow

```
Model Logging Errors → Categorize Patterns → Update Checklist → Test Prevention → Document Solutions
```

### Quality Assurance

Before implementing any new model:

- [ ] Review recent error logs for similar models
- [ ] Check if error patterns apply to new model
- [ ] Verify all functions from error logs are included
- [ ] Test with minimal data first
- [ ] Use function availability diagnostics
- [ ] Follow the implementation checklist

### Knowledge Sharing

- **Development Rules**: `DEVELOPMENT_RULES.md` contains lessons learned
- **Implementation Checklist**: `MODEL_WORKER_IMPLEMENTATION_CHECKLIST.md` provides step-by-step guidance
- **Error Documentation**: Each error pattern includes root cause, solution, and prevention
- **Team Updates**: New checklist items and error patterns are shared with the team

This process ensures that our parallel processing implementation becomes more robust and error-free over time, with each error contributing to better prevention strategies for future development.