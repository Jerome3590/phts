# Python Scripts Organization

## Current Structure

### Main Python Scripts

```
graft-loss/
├── scripts/
│   └── py/
│       └── catboost_survival.py          # Main CatBoost survival model script
│
└── cohort_analysis/
    └── ffa_analysis/                      # Formal Feature Analysis (FFA) scripts
        ├── catboost_axp_explainer.py      # AXP explainer for CatBoost models
        ├── catboost_axp_explainer2.py     # Alternative AXP explainer version
        └── ffa_analysis.py                # FFA analysis pipeline
```

## Script Descriptions

### 1. `graft-loss/scripts/py/catboost_survival.py` ✅
**Purpose**: Main CatBoost survival model training script

**Functionality**:
- Trains CatBoost regression model using signed-time labels (survival proxy)
- Handles categorical features natively
- Generates predictions and feature importance
- Used by main pipeline (`graft-loss/scripts/04_fit_model.R`)

**Usage**: Called from R scripts via `system()` or `reticulate`

**Status**: **Active** - Used in production pipeline

### 2. `graft-loss/cohort_analysis/ffa_analysis/catboost_axp_explainer.py` ✅
**Purpose**: Formal Feature Analysis (FFA) explainer for CatBoost models

**Functionality**:
- AXP (Abductive eXplanation) based explanations
- Feature importance analysis
- Rule extraction and validation
- Used by `cohort_event_model_ffa.qmd` and `causal_analysis.qmd`

**Usage**: Imported as Python module (`from ffa_analysis.catboost_axp_explainer import ...`)

**Status**: **Active** - Used in cohort analysis notebooks

### 3. `graft-loss/cohort_analysis/ffa_analysis/catboost_axp_explainer2.py` ⚠️
**Purpose**: Alternative version of AXP explainer

**Status**: **Review needed** - Determine if this is a backup or alternative implementation

### 4. `graft-loss/cohort_analysis/ffa_analysis/ffa_analysis.py` ✅
**Purpose**: FFA analysis pipeline

**Functionality**:
- Orchestrates FFA workflow
- Handles data loading and processing
- Generates outputs and visualizations

**Status**: **Active** - Used in FFA workflow

## Changes Made

### Removed Duplicate
- ❌ **Removed**: `graft-loss/graft-loss-parallel-processing/scripts/py/catboost_survival.py`
  - **Reason**: Duplicate of main script with DEBUG statements
  - **Impact**: Only referenced in legacy/backup files
  - **Action**: Removed to eliminate confusion

## Organization Rationale

### Co-location Pattern
Python scripts are organized using a **co-location pattern**:
- **Main pipeline scripts** → `graft-loss/scripts/py/`
- **Analysis-specific scripts** → Co-located with their analysis (e.g., `ffa_analysis/` with cohort_analysis)

### Benefits
1. **Clear separation**: Main pipeline scripts vs. analysis-specific scripts
2. **Easy discovery**: Scripts are near where they're used
3. **Module imports**: FFA scripts can be imported as modules from their directory

## Recommendations

### ✅ Current Organization is Good
The current organization follows a logical pattern:
- Main pipeline Python script in dedicated `scripts/py/` directory
- Analysis-specific Python scripts co-located with their analysis

### Future Considerations

1. **Review `catboost_axp_explainer2.py`**:
   - Determine if it's needed or can be removed
   - If needed, document differences from main version

2. **Consider Python package structure** (if scripts grow):
   ```
   graft-loss/
   └── python/
       ├── __init__.py
       ├── catboost_survival.py
       └── ffa/
           ├── __init__.py
           ├── explainer.py
           └── analysis.py
   ```
   But this is only needed if scripts become more complex or shared.

3. **Document Python dependencies**:
   - Create `requirements.txt` or `environment.yml`
   - Document Python version requirements

## Summary

**Total Python Scripts**: 4 (after removing duplicate)
- **Main pipeline**: 1 script (`catboost_survival.py`)
- **FFA analysis**: 3 scripts (co-located with cohort_analysis)

**Organization Status**: ✅ **Well-organized**
- Clear separation between main pipeline and analysis scripts
- Co-location pattern makes scripts easy to find
- No unnecessary duplication

