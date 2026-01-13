# Terminology Update: Age Bands → Primary Diagnosis

## Context

The PHTS calculator uses **diagnostic cohorts** based on **primary diagnosis (prim_dx)**, not age bands:
- **CHD**: Congenital Heart Disease
- **Combined**: All primary diagnoses
- **Myocardio**: Cardiomyopathy and Myocarditis

## Functions Updated

### `prim_dx_fname(cohort: str) -> str`
**New function** for PHTS calculator diagnostic cohorts:
- Returns the cohort name as-is (CHD, Combined, Myocardio)
- Used for file paths and naming in calculator workflow

### `age_band_to_fname(age_band: str) -> str`
**Legacy function** kept for backward compatibility:
- Handles age band format (e.g., "13-24" → "13_24")
- Also handles diagnostic cohorts (returns as-is if no dash)
- Used in legacy code paths that aren't part of calculator workflow

## Calculator Workflow

The calculator workflow (`_load_calculator_models`) uses:
- **Cohort name directly**: `calculator/outputs/models/{cohort}/`
- **No age_band needed**: Models are stored by diagnostic cohort only

## Legacy Code

Functions that still use `age_band_fname`:
- `_load_final_features()` - Legacy workflow
- `_load_best_models()` - Legacy workflow  
- `_load_best_xgboost_model()` - Legacy workflow
- `run_shap_analysis()` - Legacy workflow

These are **not used** by the calculator workflow, which uses `_load_calculator_models()` directly.

## Usage

For PHTS calculator:
```python
from shap_analysis.run_shap_analysis import _load_calculator_models, prim_dx_fname

# Load models by diagnostic cohort
cb_model, xgb_model = _load_calculator_models("CHD")

# Get filename-safe cohort name
fname = prim_dx_fname("CHD")  # Returns "CHD"
```

For legacy workflows (if needed):
```python
from shap_analysis.run_shap_analysis import age_band_to_fname

# Convert age band to filename
fname = age_band_to_fname("13-24")  # Returns "13_24"
```
