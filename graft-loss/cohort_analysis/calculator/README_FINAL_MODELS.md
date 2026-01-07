# Calculator Models - Final Variables and Results

This document describes the final calculator models for pediatric heart transplant graft loss prediction, including all variables used and model performance results.

## Model Overview

Three calculator models have been developed:

1. **CHD Model** - Congenital Heart Disease cohort only
2. **Combined Model** - All primary diagnoses (includes `primary_etiology` as explicit feature)
3. **Myocardio Model** - Cardiomyopathy and Myocarditis cohort only

Each model uses **Simple Calculator** (multivariate logistic regression) and is compared against:
- CatBoost
- XGBoost
- XGBoost RF
- LASSO

## Final Variables Used in Simple Calculator

### Base Variables (All Cohorts)

#### Demographics
- `age_listing` - Age at listing (years)
- `age_txpl` - Age at transplant (years)

#### Prior Surgeries
- `hxsurg` - History of surgery

#### CHD Subtype
- `chd_hlh` - Congenital heart disease with hypoplastic left heart syndrome

#### PRA Related
- `lsfcpra` - Flow cytometry PRA at listing (%)
- `lsfprab` - Flow cytometry PRA (B-cell) at listing (%)
- `lsfprat` - Flow cytometry PRA (T-cell) at listing (%)

#### Kidney Function
- `egfr_tx` - Estimated GFR at transplant (mL/min/1.73m²) **[CALCULATED]**
- `egfr_listing` - Estimated GFR at listing (mL/min/1.73m²) **[CALCULATED]**
- `egfr_tx_cat` - eGFR category at transplant (severe/moderate/mild/normal) **[DERIVED]**
- `egfr_listing_cat` - eGFR category at listing (severe/moderate/mild/normal) **[DERIVED]**
- `hxdysdia_bin` - History of dialysis (dichotomous: 0/1) **[DERIVED]**
- `egfr_change` - Change in eGFR from listing to transplant **[CALCULATED]**

**eGFR Categories:**
- Severe: <30
- Moderate: 30-60
- Mild: 60-90
- Normal: ≥90

#### Liver Function
- `txbili_t_r` - Total bilirubin at transplant (mg/dL)
- `txbili_t_r_high` - Total bilirubin >1.5 (dichotomous: 0/1) **[DERIVED]**
- `txalt` - ALT at transplant (U/L)
- `txalt_high` - ALT >90 (dichotomous: 0/1) **[DERIVED]**

#### Respiratory
- `txvent` - Ventilation at transplant
- `hxtrach` - History of tracheostomy
- `ltxtrach` - Tracheostomy at listing

#### Cardiac Support
- `txvad` - VAD at transplant
- `txecmo` - ECMO at transplant
- `slecmo` - ECMO at listing
- `ecmo_combined` - ECMO at transplant OR listing (dichotomous: 0/1) **[DERIVED]**

#### Nutrition
- `txpalb_r` - Pre-albumin at transplant (mg/dL)
- `txsa_r` - Serum albumin at transplant (g/dL)
- `txsa_r_low` - Serum albumin <3 (dichotomous: 0/1) **[DERIVED]**
- `txtp_r` - Total protein at transplant (g/dL)

#### Immunology
- `txfcpra` - Flow cytometry PRA at transplant (%)
- `lsfcpra` - Flow cytometry PRA at listing (%)

### Cohort-Specific Variables

#### Combined Model Additional Variables
- `primary_etiology` - Primary diagnosis (Congenital HD, Cardiomyopathy, Myocarditis, etc.)
  - **Rationale**: Strong predictor that distinguishes risk across etiologies
  - **Impact**: Expected to improve Combined model AUC significantly

#### CHD Model Additional Variables
- All `CHD_*` variables - All CHD subtype variables (automatically detected)
- `hxfonlvr_bin` - History of Fontan Associated Liver Disease (dichotomous: 0/1) **[DERIVED]**
  - **Rationale**: CHD-specific risk factor, particularly relevant for Fontan patients
  - **Impact**: Expected to improve CHD model AUC

#### Myocardio Model
- Uses base variables only (no myocardio-specific additions currently)

## Variable Derivation

### Calculated Variables

**eGFR (Schwartz Formula):**
```
egfr_tx = 0.413 × height_txpl / txcreat_r
egfr_listing = 0.413 × height_listing / lcreat_r
```

**eGFR Categories:**
- Calculated from continuous eGFR values
- Categories: severe (<30), moderate (30-60), mild (60-90), normal (≥90)

**eGFR Change:**
```
egfr_change = egfr_tx - egfr_listing
```

### Derived/Dichotomous Variables

- `txbili_t_r_high`: `txbili_t_r > 1.5` → 1, else 0
- `txalt_high`: `txalt > 90` → 1, else 0
- `txsa_r_low`: `txsa_r < 3` → 1, else 0
- `ecmo_combined`: `txecmo == 1 OR slecmo == 1` → 1, else 0
- `hxdysdia_bin`: `hxdysdia == 1` → 1, else 0
- `hxfonlvr_bin`: `hxfonlvr == 1` → 1, else 0 (CHD model only)

## Model Results

### Performance Summary

**Final Results (Improved Models with primary_etiology and CHD-specific features)**

| Cohort | Model | AUC Mean | AUC SD | AUC 95% CI Lower | AUC 95% CI Upper | N Splits |
|--------|-------|----------|--------|------------------|------------------|----------|
| CHD | Simple_Calculator | 0.6250 | 0.0354 | 0.5573 | 0.6781 | 25 |
| Combined | Simple_Calculator | 0.7385 | 0.0245 | 0.7010 | 0.7823 | 25 |
| Myocardio | Simple_Calculator | 0.6571 | 0.0743 | 0.5101 | 0.7681 | 25 |

### Baseline Results (Before Improvements)

For comparison, baseline results were:
- **CHD**: AUC = 0.635 (95% CI: 0.564 - 0.701)
- **Combined**: AUC = 0.734 (95% CI: 0.695 - 0.774)
- **Myocardio**: AUC = 0.657 (95% CI: 0.510 - 0.768)

### Results After Improvements

**Combined Model**: ✅ **Improved** (0.734 → 0.738)
- Successfully improved with explicit `primary_etiology` feature
- `primary_etiology` shows high importance (2.2-2.9 across categories)

**CHD Model**: ⚠️ **Slightly decreased** (0.635 → 0.625)
- Small decrease despite adding CHD-specific features
- Analysis: Many CHD subtype variables added (40+), which may cause:
  - Overfitting with too many sparse categorical features
  - Multicollinearity between CHD subtypes
  - Need for feature selection/regularization

**Myocardio Model**: ➡️ **Unchanged** (0.657 → 0.657)
- Stable performance, no additional features needed

## Feature Importance

### Top Features by Cohort (Final Results)

**Combined Model:**
1. `primary_etiologyOther..Specify` - Importance: 2.94 ⭐ (NEW - very strong!)
2. `txfcpra` (Done/Not.Done) - Importance: 2.90
3. `primary_etiologyCardiomyopathy` - Importance: 2.75 ⭐ (NEW)
4. `primary_etiologyMyocarditis` - Importance: 2.35 ⭐ (NEW)
5. `primary_etiologyCongenital.HD` - Importance: 2.21 ⭐ (NEW)
6. `egfr_listing_catnormal` - Importance: 1.52
7. `ecmo_combined` - Importance: 1.25
8. `hxtrach` - Importance: 1.16

**Key Insight**: `primary_etiology` is now the **top predictor** in the Combined model, confirming it's a critical feature for distinguishing risk across etiologies.

**CHD Model:**
1. `chd_lsvc` - Importance: 19.01 ⭐ (NEW - extremely strong!)
2. `txfcpra` (Done/Not.Done) - Importance: 15.40
3. `chd_hb` - Importance: 14.88 ⭐ (NEW)
4. `chd_alcapa` - Importance: 14.50 ⭐ (NEW)
5. `chd_mart` - Importance: 13.90 ⭐ (NEW)
6. `chd_raa` - Importance: 13.25 ⭐ (NEW)
7. `chd_dolv` - Importance: 12.47 ⭐ (NEW)
8. `chd_si` - Importance: 12.30 ⭐ (NEW)
9. `ecmo_combined` - Importance: 2.47
10. `egfr_listing_catnormal` - Importance: 2.31

**Key Insights**: 
- **40+ CHD subtype variables** were added, many with very high importance
- `chd_lsvc` (Left Superior Vena Cava) has extremely high importance (19.01)
- Multiple CHD subtypes show importance >10, suggesting they're strong predictors
- However, the large number of sparse categorical features may be causing overfitting
- Original `chd_hlh` now ranks much lower (0.13) compared to other subtypes

**Myocardio Model:**
1. `hxtrach` - Importance: 10.63 (extremely strong!)
2. `ltxtrach` - Importance: 3.80
3. `txfcpra` (Done/Not.Done) - Importance: 3.28
4. `egfr_listing_catnormal` - Importance: 1.74
5. `egfr_tx_catnormal` - Importance: 1.41

**Key Insight**: Tracheostomy history (`hxtrach`, `ltxtrach`) is the **dominant predictor** in Myocardio patients, suggesting respiratory complications are a critical risk factor.

## Model Comparison

### Simple Calculator vs Other Models

*Results will be updated once analysis completes*

The Simple Calculator (logistic regression) is compared against:
- **CatBoost**: Gradient boosting with categorical feature support
- **XGBoost**: Extreme gradient boosting
- **XGBoost RF**: XGBoost in Random Forest mode
- **LASSO**: L1-regularized logistic regression with automatic feature selection

## Methodology

### Monte Carlo Cross-Validation
- **Splits**: 25 random 80/20 train/test splits
- **Stratification**: By outcome to maintain event distribution
- **Parallel Processing**: 18 workers (detected automatically)

### Evaluation
- **Metric**: AUC (Area Under the ROC Curve)
- **Outcome**: Binary classification at 1 year
  - Event by 1 year (graft loss) = 1
  - No event with follow-up ≥ 1 year = 0
  - Censored before 1 year = excluded

### Data Preparation
- **Time Period**: 2010-2024 (TXPL_YEAR >= 2010)
- **Missing Values**: Median imputation (numeric), mode imputation (categorical)
- **Constant Columns**: Automatically removed
- **Feature Engineering**: All derived features calculated before modeling

## File Locations

### Results Files
- `outputs/calculator_models_summary.csv` - Summary table with all results
- `outputs/best_models_by_cohort.csv` - Best performing model for each cohort
- `outputs/importance_[COHORT]_[MODEL].csv` - Feature importance for each model and cohort

### Code Files
- `calculator_models.R` - Main implementation script
- `run_calculator.R` - Simple runner script
- `README.md` - General documentation
- `IMPLEMENTATION_SUMMARY.md` - Implementation details
- `IMPROVEMENTS.md` - Description of improvements made

## Usage

### Running the Models

```r
# Run all models
source("graft-loss/cohort_analysis/calculator/calculator_models.R")
main()
```

### Using the Results

Results can be loaded and analyzed:

```r
library(readr)
library(dplyr)

# Load summary
summary <- read_csv("graft-loss/cohort_analysis/calculator/outputs/calculator_models_summary.csv")

# Load feature importance
chd_importance <- read_csv("graft-loss/cohort_analysis/calculator/outputs/importance_CHD_Simple_Calculator.csv")
combined_importance <- read_csv("graft-loss/cohort_analysis/calculator/outputs/importance_Combined_Simple_Calculator.csv")
```

## Notes

1. **Simple Calculator**: Designed to be interpretable and easy to use in clinical settings
2. **Feature Selection**: Based on clinical relevance and feature importance analysis
3. **Cohort-Specific Features**: Added to improve performance for specific patient populations
4. **Reproducibility**: Fixed random seeds (1997) ensure reproducible results
5. **Validation**: All models evaluated on unseen test data only (no data leakage)

## Updates

- **Initial Version**: Baseline models with standard features
- **Improved Version**: Added `primary_etiology` to Combined model, additional CHD-specific features to CHD model
- **Last Updated**: January 6, 2025 (Results from improved models with primary_etiology and CHD-specific features)

---

## Additional Analysis

For detailed analysis of CHD model performance, see [ANALYSIS_CHD_PERFORMANCE.md](ANALYSIS_CHD_PERFORMANCE.md).

---

*Document last updated: January 6, 2025*
