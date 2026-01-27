# Final Input Features for Retrained Model

**Date:** January 26, 2026  
**Model:** Combined (single model for all cohorts)  
**Status:** After retraining with new derived variables

## Overview

The retrained Combined model uses features that are:
1. **Derived/Calculated** from raw inputs (e.g., eGFR, BMI, ratios)
2. **Original** clinical variables from the dataset
3. **Filtered** to remove leakage predictors and constant columns

## Feature Processing Pipeline

### Step 1: Feature Engineering (`prepare_calculator_features()`)

Adds the following **derived variables**:

#### Calculated Variables
- `egfr_tx`: eGFR at transplant = `0.413 * height_txpl / txcreat_r`
- `egfr_listing`: eGFR at listing = `0.413 * height_listing / lcreat_r`
- `bmi_txpl`: BMI at transplant = `(weight_txpl / height_txpl²) * 703`
- `age_txpl_months`: Age at transplant in months = `age_txpl * 12`

#### eGFR Categories
- `egfr_tx_cat`: Category (severe/moderate/mild/normal) based on eGFR thresholds
- `egfr_listing_cat`: Category (severe/moderate/mild/normal) based on eGFR thresholds

#### Dichotomous Variables
- `txbili_t_r_high`: Total bilirubin > 1.5 (binary)
- `txbun_r_high`: BUN > 30 (binary)
- `txsa_r_low`: Albumin < 3 (binary)
- `txalt_high`: ALT > 90 (binary)
- `hxfonlvr_bin`: History of Fontan liver disease (binary)
- `hxdysdia_bin`: History of dialysis (binary)

#### Combined Support Variables
- `ecmo_combined`: `txecmo OR slecmo` ✅
- `vad_combined`: `txvad OR slvad` ✅ NEW
- `vent_combined`: `txvent OR slvent OR ltxtrach OR hxtrach` ✅ NEW

#### Donor-Recipient Ratios
- `donor_weight_ratio`: `(weight_donor / weight_txpl) * 100` ✅ NEW
- `donor_size_ratio`: `(height_donor / height_txpl) * 100` ✅ NEW

#### Change Variables
- `egfr_change`: `egfr_tx - egfr_listing`

### Step 2: Leakage Removal (`remove_leakage_predictors()`)

**Removes** the following types of variables:

#### Exact Column Names Removed
- `ptid_e` (patient ID)
- `ev_time` (event time - outcome)
- `ev_type` (event type - outcome)
- `outcome` (outcome variable)
- `transplant_year` (temporal leakage)

#### Pattern-Based Removal (Keywords)
- **Outcome variables**: `graft_loss`, `int_graft_loss`, `int_dead`, `dtx_`, `dcardiac`, `dcon`, `dpri`, `dpricaus`, `rec_`, `deathspc`
- **Post-transplant variables**: `dreject`, `dmajbld`, `dsecaccs`, `pishltgr`
- **Cohort-defining variables**: `prim_dx`, `PRIM_DX` (used for cohort definition, not prediction)
- **Temporal leakage**: `listing_year`, `transplant_year`, `txpl_year` (removed as feature, kept for splitting)
- **Demographics (optional)**: `race`, `sex`, `drace_b`, `rrace_a`, `hisp`, `Iscntry`, `lscntry`
- **Other leakage**: `cpbypass`, `lsvcma`, `cpathneg`, `dcauseod`, `alt_tx`, `age_death`, `dlist`, `pmorexam`, `patsupp`, `concod`, `pcadrem`, `pcadrec`, `pathero`, `pdiffib`, `dmalcanc`, `pacuref`

#### Prefix-Based Removal
- All columns starting with `sd` (standard deviation variables)

### Step 3: Feature Selection

**Excluded from features** (but used for other purposes):
- `time`: Survival time (outcome)
- `status`: Event indicator (outcome)
- `txpl_year`: Used for temporal splitting only (not a feature)

**Removed**:
- Constant columns (columns with < 2 unique values)

### Step 4: Final Processing

- **Fill NaN**: All missing values filled with 0
- **Categorical encoding**: Object/categorical columns converted to numeric codes
- **Feature order**: Features are ordered alphabetically (for consistency)

## Final Feature Set

The final feature set includes:

### ✅ New Derived Features (Added in Retraining)

1. **`vad_combined`**: VAD at transplant or listing (binary)
2. **`vent_combined`**: Mechanical ventilation at transplant or listing (binary)
3. **`donor_weight_ratio`**: Donor/recipient weight ratio (percentage)
4. **`donor_size_ratio`**: Donor/recipient height ratio (percentage)

### ✅ Existing Derived Features

1. **`ecmo_combined`**: ECMO at transplant or listing (binary)
2. **`egfr_tx`**: eGFR at transplant (calculated)
3. **`egfr_listing`**: eGFR at listing (calculated)
4. **`egfr_tx_cat`**: eGFR category at transplant
5. **`egfr_listing_cat`**: eGFR category at listing
6. **`egfr_change`**: Change in eGFR from listing to transplant
7. **`bmi_txpl`**: BMI at transplant (calculated)
8. **`txbili_t_r_high`**: High total bilirubin (binary)
9. **`txbun_r_high`**: High BUN (binary)
10. **`txsa_r_low`**: Low albumin (binary)
11. **`txalt_high`**: High ALT (binary)
12. **`hxfonlvr_bin`**: History of Fontan liver disease (binary)
13. **`hxdysdia_bin`**: History of dialysis (binary)

### ✅ Original Clinical Features

All original clinical variables from the dataset that:
- Are not leakage predictors
- Are not constant
- Are not outcome variables

**Categories include:**
- Demographics (age, weight, height)
- Donor characteristics (donor_age, donor_weight, donor_height, donisch, etc.)
- Recipient clinical history (hxsurg, hxmed, etc.)
- Lab values at transplant (tx*) and listing (ls*)
- Support devices (txecmo, txvad, txvent, etc.)
- Immunology (txfcpra, lsfcpra, etc.)
- Primary/secondary/tertiary diagnoses (if not used for cohort definition)

## Getting the Exact Feature List

To get the **exact** list of features for a trained model:

```bash
cd graft-loss/cohort_analysis/calculator
python list_model_features.py --cohort Combined
```

Or with categorization:

```bash
python list_model_features.py --cohort Combined --categorized
```

Or save to file:

```bash
python list_model_features.py --cohort Combined --output outputs/model_features.json
```

## Feature Count

The exact number of features depends on:
- Available variables in the dataset
- Which variables pass leakage filtering
- Which variables are constant (removed)

**Typical range**: 150-200 features

## Validation

After training, validate that features match:

```bash
python validate_features.py --cohort Combined
```

This will:
- Load the trained model
- Re-run feature preparation
- Compare model features vs training features
- Report any mismatches

## Key Points

1. **All derived variables** (`vad_combined`, `vent_combined`, `donor_weight_ratio`, `donor_size_ratio`) are now included
2. **Leakage variables** are removed (outcomes, post-transplant events, etc.)
3. **Constant columns** are removed (no variance)
4. **Feature order** is consistent (alphabetical)
5. **Missing values** are filled with 0
6. **Categorical variables** are encoded as numeric

## For Inference (Lambda Function)

The Lambda function (`prepare_features_for_inference()`) creates the same derived variables from user inputs:

1. `vad_combined` from `txvad` OR `slvad`
2. `vent_combined` from `txvent` OR `slvent` OR `ltxtrach` OR `hxtrach`
3. `ecmo_combined` from `txecmo` OR `slecmo`
4. `donor_weight_ratio` from `weight_donor` and `weight_txpl`
5. `donor_size_ratio` from `height_donor` and `height_txpl`
6. `egfr_tx` from `height_txpl` and `txcreat_r` (if not provided)

This ensures **feature alignment** between training and inference.

---

**Last Updated:** January 26, 2026
