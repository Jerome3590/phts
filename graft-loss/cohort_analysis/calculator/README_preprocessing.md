# PHTS Model Preprocessing Pipeline

## Overview

This document describes the complete feature engineering and preprocessing pipeline used for PHTS (Pediatric Heart Transplant Society) model training. All preprocessing logic is consolidated in `preprocessing_pipeline.py`.

**Key Point**: `calculator_features.py` contains only feature **definitions** (lists of feature names). All actual preprocessing logic is in `preprocessing_pipeline.py` and `run_shap_ffa_workflow.py::prepare_calculator_features()`.

## Quick Start

```python
from preprocessing_pipeline import prepare_features_for_training, load_and_preprocess

# Option 1: Preprocess existing DataFrame
df_processed = prepare_features_for_training(df_raw)

# Option 2: Load and preprocess in one step
df = load_and_preprocess('data/phts_txpl_ml.sas7bdat', cohort='CHD')

# Option 3: Filter after preprocessing
from preprocessing_pipeline import filter_by_cohort
df_chd = filter_by_cohort(df_processed, 'CHD')
```

## Dataset Statistics

**Source File**: `phts_txpl_ml.sas7bdat`
- **Patients**: 5,835 total
- **Original Columns**: 476
- **After Preprocessing**: 501 columns (+25 derived features)

**Cohort Distribution**:
- CHD (Congenital Heart Disease): 2,845 patients (48.8%)
- Myocardio (Cardiomyopathy + Myocarditis): 2,914 patients (49.9%)
- Other diagnoses: 76 patients (1.3%)

**Country Distribution**:
- United States: 88.7%
- United Kingdom: 5.5%
- Canada: 4.1%
- Brazil: 1.7%

> **Note**: Country variables (`lscntry`, `Iscntry`) are excluded from models as leakage features (not modifiable), but all country records remain in the dataset - records are NOT filtered by country.

## Preprocessing Steps

The pipeline performs 10 major preprocessing steps in sequence:

### 1. Column Name Standardization
- Converts all column names to lowercase for consistency
- Ensures case-insensitive column access

### 2. Calculated Features: eGFR

**eGFR at Transplant** (`egfr_tx`)
- **Formula**: eGFR = 0.413 × height (cm) / creatinine (mg/dL) — Schwartz formula
- **PHTS units**: height in **inches**; we convert to cm (× 2.54) before applying the formula
- **Calculated for**: 5,727 patients (98.1%)
- **Units**: mL/min/1.73m²

**eGFR at Listing** (`egfr_listing`)
- Same formula using listing height (inches → cm) and creatinine
- **Calculated for**: 5,610 patients (96.1%)

```python
# Implementation (PHTS height_txpl is in inches)
mask = df["height_txpl"].notna() & df["txcreat_r"].notna() & (df["txcreat_r"] > 0)
height_cm = df.loc[mask, "height_txpl"] * 2.54
df.loc[mask, "egfr_tx"] = 0.413 * height_cm / df.loc[mask, "txcreat_r"]
```

### 3. Calculated Features: BMI

**BMI at Transplant** (`bmi_txpl`)
- **Formula**: BMI = 703 × weight (lb) / height (in)²
- **PHTS units**: weight in **lbs**, height in **inches**; 703 yields BMI in kg/m²
- **Calculated for**: 5,754 patients (98.6%)

```python
mask = df["weight_txpl"].notna() & df["height_txpl"].notna() & (df["height_txpl"] > 0)
df.loc[mask, "bmi_txpl"] = (df.loc[mask, "weight_txpl"] / (df.loc[mask, "height_txpl"] ** 2)) * 703
```

### 4. Age Conversion

**Age in Months** (`age_txpl_months`)
- Converts `age_txpl` (years) to months: `age * 12`
- Required for WHO growth curve calculations

### 5. eGFR Categories

**eGFR Clinical Categories** (`egfr_tx_cat`, `egfr_listing_cat`)

| Category | eGFR Range | CKD Stage | Description |
|----------|------------|-----------|-------------|
| severe | < 30 | Stage 4-5 | Severe kidney dysfunction |
| moderate | 30-60 | Stage 3 | Moderate kidney dysfunction |
| mild | 60-90 | Stage 2 | Mild kidney dysfunction |
| normal | ≥ 90 | Normal/Stage 1 | Normal or hyperfiltration |

```python
df["egfr_tx_cat"] = pd.cut(
    df["egfr_tx"],
    bins=[-np.inf, 30, 60, 90, np.inf],
    labels=["severe", "moderate", "mild", "normal"],
    right=False
)
```

### 6. Dichotomous Variables (High/Low Thresholds)

These create binary indicators (0/1) for clinically significant thresholds:

| Variable | Threshold | Direction | Patients | Description |
|----------|-----------|-----------|----------|-------------|
| `txbili_t_r_high` | > 1.5 mg/dL | High | 833 (14.3%) | Elevated bilirubin |
| `txbun_r_high` | > 30 mg/dL | High | 603 (10.3%) | Elevated BUN (azotemia) |
| `txsa_r_low` | < 3 g/dL | Low | 754 (12.9%) | Low albumin (hypoalbuminemia) |
| `txalt_high` | > 90 U/L | High | 414 (7.1%) | Elevated ALT (hepatic dysfunction) |
| `donisch` | > 240 min | High | 1,827 (31.3%) | Prolonged ischemic time (>4 hours) |

**Special Note on DONISCH**:
- Originally continuous (minutes)
- Converted to binary: >240 min = 1, ≤240 min = 0
- Missing values default to 0 (assume ≤240 min)
- See `README_ready_to_run.md` for rationale

```python
# Example: Bilirubin
df["txbili_t_r_high"] = (df["txbili_t_r"] > 1.5).astype(int)

# DONISCH dichotomization
df["donisch"] = (df["donisch"] > 240).astype(int)
df.loc[df["donisch"].isna(), "donisch"] = 0
```

### 7. Combined/Composite Variables

These aggregate multiple related variables into single indicators:

#### ECMO Combined (`ecmo_combined`)
- **Definition**: Patient on ECMO at transplant OR at listing
- **Components**: `txecmo` OR `slecmo`
- **Patients**: 361 (6.2%)

#### VAD Combined (`vad_combined`)
- **Definition**: Ventricular assist device at transplant OR at listing
- **Components**: `txvad` OR `slvad`
- **Patients**: 1,802 (30.9%)

#### Ventilation Combined (`vent_combined`)
- **Definition**: Any ventilatory support
- **Components**: `txvent` OR `slvent` OR `ltxtrach` OR `hxtrach`
- **Patients**: 1,489 (25.5%)

#### CHD Laterality Disorder (`chd_lat`)
- **Definition**: Composite of CHD laterality abnormalities
- **Components**: 8 variables
  - `chd_dex` (Dextrocardia)
  - `chd_si` (Situs inversus)
  - `chd_heter` (Heterotaxy)
  - `chd_iivc` (Interrupted IVC)
  - `chd_bivc` (Bilateral SVC)
  - `chd_lsvc` (Left SVC)
  - `chd_raa` (Right atrial appendage abnormality)
  - `chd_avd` (Atrioventricular discordance)
- **Patients**: 179 (3.1%)
- **Logic**: Any = 1, None = 0

```python
# Example: VAD Combined
df["vad_combined"] = ((df["txvad"] == 1) | (df["slvad"] == 1)).astype(int)

# CHD Laterality
chd_lat_vars = ["chd_dex", "chd_si", "chd_heter", "chd_iivc", 
                "chd_bivc", "chd_lsvc", "chd_raa", "chd_avd"]
df["chd_lat"] = df[chd_lat_vars].any(axis=1).astype(int)
```

#### Other Binary Composites
- `hxfonlvr_bin`: History of Fontan-associated liver disease
- `hxdysdia_bin`: History of dialysis

### 8. Ratio Variables (Donor/Recipient Matching)

**Donor Weight Ratio** (`donor_weight_ratio`)
- **Formula**: (weight_donor / weight_txpl) × 100
- **Units**: Percentage
- **Calculated for**: 5,803 patients (99.5%)
- **Interpretation**: Donor size matching - values >100% indicate larger donor

**Donor Size Ratio** (`donor_size_ratio`)
- **Formula**: (height_donor / height_txpl) × 100  
- **Units**: Percentage
- **Calculated for**: 5,718 patients (98.0%)
- **Interpretation**: Donor-recipient height matching

```python
mask = df["weight_txpl"].notna() & (df["weight_txpl"] > 0)
df.loc[mask, "donor_weight_ratio"] = (
    (df.loc[mask, "weight_donor"] / df.loc[mask, "weight_txpl"]) * 100
)
```

### 9. Change Variables

**eGFR Change** (`egfr_change`)
- **Formula**: egfr_tx - egfr_listing
- **Units**: mL/min/1.73m²
- **Calculated for**: 5,540 patients (94.9%)
- **Mean change**: +2.60 mL/min/1.73m²
- **Interpretation**: 
  - Positive = improvement from listing to transplant
  - Negative = decline from listing to transplant

```python
df["egfr_change"] = df["egfr_tx"] - df["egfr_listing"]
```

### 10. One-Hot Encoding: Secondary Diagnosis

**Secondary Diagnosis** (`sec_dx`)
- **Original**: Single categorical variable
- **After Processing**: 7 binary columns
- **Method**: One-hot encoding with case-insensitive matching

**Categories**:
1. `sec_dx_ARVD_C` - Arrhythmogenic right ventricular dysplasia/cardiomyopathy
2. `sec_dx_Dilated` - Dilated cardiomyopathy
3. `sec_dx_Hypertrophic` - Hypertrophic cardiomyopathy
4. `sec_dx_MIXED` - Mixed cardiomyopathy
5. `sec_dx_Other` - Other secondary diagnosis
6. `sec_dx_Restrictive` - Restrictive cardiomyopathy
7. `sec_dx_Unknown` - Unknown secondary diagnosis

```python
raw = df["sec_dx"].astype(str).str.strip()
for level in SEC_DX_LEVELS:
    col_name = f"sec_dx_{level.replace('/', '_').replace(' ', '_')}"
    df[col_name] = (raw.str.lower() == level.lower()).astype(int)
df = df.drop(columns=["sec_dx"])
```

## Complete Feature List

### Derived Features (27 total)

```python
from preprocessing_pipeline import get_derived_feature_names

derived_features = get_derived_feature_names()
# Returns: ['egfr_tx', 'egfr_listing', 'bmi_txpl', 'age_txpl_months',
#           'egfr_tx_cat', 'egfr_listing_cat', 
#           'txbili_t_r_high', 'txbun_r_high', 'txsa_r_low', 'txalt_high', 'donisch',
#           'ecmo_combined', 'vad_combined', 'vent_combined', 'chd_lat',
#           'hxfonlvr_bin', 'hxdysdia_bin',
#           'donor_weight_ratio', 'donor_size_ratio',
#           'egfr_change',
#           'sec_dx_ARVD_C', 'sec_dx_Dilated', 'sec_dx_Hypertrophic',
#           'sec_dx_MIXED', 'sec_dx_Other', 'sec_dx_Restrictive', 'sec_dx_Unknown']
```

## Cohort Filtering

The pipeline supports filtering by primary diagnosis:

```python
from preprocessing_pipeline import filter_by_cohort

# Filter to CHD cohort
df_chd = filter_by_cohort(df, 'CHD')  # 2,845 patients

# Filter to Myocardio cohort  
df_myocardio = filter_by_cohort(df, 'Myocardio')  # 2,914 patients

# No filter (Combined cohort)
df_combined = filter_by_cohort(df, 'Combined')  # 5,835 patients
```

**Cohort Definitions**:
- **CHD**: `PRIM_DX == "Congenital HD"`
- **Myocardio**: `PRIM_DX in ["Cardiomyopathy", "Myocarditis"]`
- **Combined**: All patients

## Preprocessing Constants

All thresholds and parameters are defined as constants:

```python
# Donor ischemic time
DONISCH_THRESHOLD_MINUTES = 240  # 4 hours

# Lab value thresholds
BILIRUBIN_HIGH_THRESHOLD = 1.5   # mg/dL
BUN_HIGH_THRESHOLD = 30          # mg/dL
ALBUMIN_LOW_THRESHOLD = 3        # g/dL
ALT_HIGH_THRESHOLD = 90          # U/L

# eGFR categories
EGFR_CATEGORIES = {
    'severe': (0, 30),
    'moderate': (30, 60),
    'mild': (60, 90),
    'normal': (90, float('inf'))
}

# Secondary diagnosis levels
SEC_DX_LEVELS = [
    "ARVD/C", "Dilated", "Hypertrophic", "MIXED", 
    "Other", "Restrictive", "Unknown"
]
```

## Usage Examples

### Example 1: Basic Preprocessing

```python
import pandas as pd
from preprocessing_pipeline import prepare_features_for_training

# Load raw data
df_raw = pd.read_sas('data/phts_txpl_ml.sas7bdat')

# Apply preprocessing
df_processed = prepare_features_for_training(df_raw, verbose=True)

print(f"Original shape: {df_raw.shape}")
print(f"Processed shape: {df_processed.shape}")
# Output: Original shape: (5835, 476)
#         Processed shape: (5835, 501)
```

### Example 2: Load and Preprocess in One Step

```python
from preprocessing_pipeline import load_and_preprocess

# Load and preprocess CHD cohort
df_chd = load_and_preprocess(
    'data/phts_txpl_ml.sas7bdat',
    cohort='CHD',
    verbose=True
)

print(f"CHD cohort size: {len(df_chd)}")
# Output: CHD cohort size: 2845
```

### Example 3: Apply to New Data

```python
from preprocessing_pipeline import prepare_features_for_training

# Load new data
df_new = pd.read_csv('new_patient_data.csv')

# Apply same preprocessing
df_new_processed = prepare_features_for_training(df_new, verbose=False)

# Use in model
predictions = model.predict(df_new_processed[feature_names])
```

### Example 4: Inspect Derived Features

```python
from preprocessing_pipeline import get_derived_feature_names

# Get all derived feature names
derived = get_derived_feature_names()

# Check which are present in dataframe
missing = [f for f in derived if f not in df.columns]
present = [f for f in derived if f in df.columns]

print(f"Present: {len(present)}/{len(derived)}")
print(f"Missing: {missing}")
```

## Integration with Model Training

The preprocessing pipeline is used in multiple locations:

### 1. Training Models (`run_shap_ffa_workflow.py`)
```python
from run_shap_ffa_workflow import prepare_calculator_features

df_train = prepare_calculator_features(df_raw)
X_train = df_train[feature_names]
```

### 2. Lambda Function Inference (`phts_lambda_function.py`)
```python
from phts_lambda_function import prepare_features_for_inference

# Single patient inference
features = prepare_features_for_inference(user_input)
prediction = model.predict(features)
```

### 3. Risk Distribution Computation (`compute_risk_distributions.py`)
```python
from compute_risk_distributions import prepare_features_for_model

X, cat_features = prepare_features_for_model(df, model, 'catboost', cohort)
predictions = model.predict(X)
```

### 4. Wisotzkey Model (`wisotzkey_data.py`)
```python
from wisotzkey_data import make_wisotzkey_data

# Special preprocessing for Wisotzkey et al. model
df_wisotzkey = make_wisotzkey_data(df, cohort)
```

## Validation and Testing

### Run Built-in Tests

```bash
python preprocessing_pipeline.py
```

**Test Output**:
```
================================================================================
PHTS Preprocessing Pipeline
================================================================================

1. Derived Features:
Total derived features: 27

2. Preprocessing Constants:
DONISCH_THRESHOLD_MINUTES: 240
BILIRUBIN_HIGH_THRESHOLD: 1.5 mg/dL
...

3. Testing with Data:
Found data file: C:\Projects\phts\graft-loss\data\phts_txpl_ml.sas7bdat
Loading and preprocessing...
Calculated egfr_tx for 5727 patients using Schwartz formula
...
Final preprocessed data shape: (5835, 501)
```

### Validate Feature Completeness

```python
from preprocessing_pipeline import prepare_features_for_training, get_derived_feature_names

df_processed = prepare_features_for_training(df_raw)
expected = get_derived_feature_names()
actual = [f for f in expected if f in df_processed.columns]

assert len(actual) == len(expected), f"Missing features: {set(expected) - set(actual)}"
print(f"✓ All {len(expected)} derived features present")
```

## Key Differences from R Pipeline

While the Python preprocessing (`preprocessing_pipeline.py`) closely mirrors the R version (`calculate_derived_features.R`), there are some differences:

| Feature | Python | R |
|---------|--------|---|
| WHO z-scores | Not implemented | Implemented (WHO anthro package) |
| BMI percentiles | Not calculated | Calculated |
| Column naming | Lowercase | Mixed case |
| Missing handling | `.fillna(0)` for some | Various strategies |
| eGFR formula | Schwartz formula | Same |
| One-hot encoding | `sec_dx_*` columns | Same approach |

## Missing Value Handling

The pipeline handles missing values differently by feature type:

| Feature Type | Strategy | Example |
|-------------|----------|---------|
| Calculated (eGFR, BMI) | Only calculate when both inputs present | `egfr_tx` requires height AND creatinine |
| Dichotomous | Only evaluate when source present | `txbili_t_r_high` only if `txbili_t_r` exists |
| Combined | Treat missing as 0 | `vad_combined`: missing txvad = 0 |
| DONISCH | Missing = 0 (assume ≤240 min) | Conservative assumption |
| Ratios | Only calculate when denominator > 0 | Avoid division by zero |

**Important**: The pipeline does NOT impute missing values. Models must handle missing data separately (e.g., CatBoost handles natively, XGBoost may require median/mode imputation).

## Performance Notes

**Processing Time**: ~0.2 seconds for full dataset (5,835 patients)

**Memory**: Minimal increase (~20% due to 25 new columns)

**Optimization Tips**:
- Use `verbose=False` in production
- Cache preprocessed data with `_to_parquet()` helper
- Process cohorts separately to reduce memory

## Dependencies

```python
# Required
import numpy as np
import pandas as pd

# Optional (for loading SAS files)
import pyreadstat  # Recommended
# OR
import sas7bdat    # Alternative
```

**Install**:
```bash
pip install numpy pandas pyreadstat
```

## Related Documentation

- **Feature Definitions**: `calculator_features.py`
- **Model Training**: `README_ready_to_run.md`
- **Feature Importance**: `README_shap_ffa.md`
- **Dashboard**: `README_dashboard.md`
- **Original vs Updated Study**: `README_original_vs_updated_study.md`
- **Validation**: `README_validation_concordance_variables_leakage.md`

## File Locations

```
graft-loss/cohort_analysis/calculator/
├── preprocessing_pipeline.py          # Main preprocessing module (THIS FILE)
├── calculator_features.py             # Feature definitions only
├── run_shap_ffa_workflow.py          # Training workflow (calls preprocessing)
├── risk_dashboard/
│   ├── phts_lambda_function.py       # Inference preprocessing
│   └── compute_risk_distributions.py # Risk distribution preprocessing
└── wisotzkey_data.py                 # Wisotzkey model preprocessing
```

## Troubleshooting

### Issue: "ModuleNotFoundError: No module named 'numpy'"
**Solution**: Install dependencies
```bash
pip install numpy pandas pyreadstat
```

### Issue: "PRIM_DX column not found"
**Solution**: Ensure data contains primary diagnosis column (case-insensitive)

### Issue: "Missing features after preprocessing"
**Solution**: Check input data has required columns
```python
required = ['height_txpl', 'txcreat_r', 'weight_txpl', 'sec_dx']
missing = [col for col in required if col.lower() not in df.columns]
print(f"Missing columns: {missing}")
```

### Issue: "Division by zero in ratio calculation"
**Solution**: Pipeline automatically handles this - ratios only calculated when denominator > 0

### Issue: "Different results between Python and R"
**Solution**: Check:
1. Column name casing (Python uses lowercase)
2. Missing value handling (Python may differ)
3. WHO z-scores (not implemented in Python)

## Contact & Support

For questions about preprocessing:
1. Check this README
2. Review `preprocessing_pipeline.py` docstrings
3. Run built-in tests: `python preprocessing_pipeline.py`
4. Validate against training data

---

**Last Updated**: February 17, 2026  
**Version**: 1.0  
**Author**: PHTS Modeling Team
