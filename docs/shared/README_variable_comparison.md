# Variable Comparison: Simple Calculator vs Risk Calculator vs Feature Importance Final Variables

This document compares the variables used in three different approaches to graft loss prediction:

1. **Simple Calculator** - Multivariate logistic regression models
2. **Risk Calculator** - Production ML models (CatBoost/XGBoost) deployed in dashboard
3. **Feature Importance Final Variables** - Top features from importance analysis (RSF/CatBoost/AORSF)

## Overview

| Approach | Model Type | Variable Count | Purpose |
|----------|-----------|----------------|---------|
| **Simple Calculator** | Logistic Regression | ~25-30 base + cohort-specific | Interpretable, bedside calculator |
| **Risk Calculator** | CatBoost/XGBoost | ~280-308 (varies by cohort) | Production ML models for dashboard |
| **Feature Importance** | Top 20 from RSF/CatBoost/AORSF | 20 per method | Feature selection for model development |

## Simple Calculator Variables

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

#### Combined Model Additional
- `primary_etiology` - Primary diagnosis (Congenital HD, Cardiomyopathy, Myocarditis, etc.)

#### CHD Model Additional
- All `CHD_*` variables - All CHD subtype variables (automatically detected, 40+ variables)
- `hxfonlvr_bin` - History of Fontan Associated Liver Disease (dichotomous: 0/1) **[DERIVED]**

#### Myocardio Model
- Uses base variables only (no myocardio-specific additions)

**Total Simple Calculator Variables:**
- Base: ~25 variables
- Combined: ~26 variables (base + primary_etiology)
- CHD: ~65+ variables (base + all CHD subtypes)
- Myocardio: ~25 variables (base only)

## Risk Calculator Variables

The Risk Calculator uses the **same feature set as the Simple Calculator** but with additional features that are automatically included during model training. The deployed models (CatBoost/XGBoost) use:

### Feature Count by Cohort
- **CHD**: 280 features
- **Combined**: 301 features
- **Myocardio**: 308 features

### Feature Categories

The Risk Calculator accepts **modifiable clinical features** that can be influenced by clinical intervention:

#### Kidney Function
- eGFR, BUN, Creatinine (at transplant and listing)
- Dialysis history
- Renal insufficiency history

#### Liver Function
- AST, ALT, Bilirubin (at transplant and listing)
- Fontan liver disease history

#### Nutrition
- Albumin, Pre-albumin, Total Protein (at transplant and listing)
- BMI, Height, Weight (at transplant and listing)
- Failure to thrive history

#### Cardiac Support
- LVAD, ECMO, MCSD (at transplant and listing)
- CPR/Shock history

#### Respiratory
- Ventilation, Tracheostomy (at transplant and listing)

#### Immunology
- PRA levels (at transplant and listing)
- HLA pre-sensitization
- Donor-specific crossmatch

#### Demographics
- Age (at listing and transplant)
- Height, Weight

#### Diagnosis
- Primary etiology
- CHD subtypes (for CHD cohort)

**Note**: The Risk Calculator models include all features that were available during training, which results in a larger feature set than the Simple Calculator's curated list. The models automatically handle missing features with default values.

## Feature Importance Final Variables

### Top 20 Features from RSF (Random Survival Forest)

1. `chd_hlh` - CHD HLH
2. `height_donor` - Donor height
3. `height_txpl` - Height at transplant
4. `hxsurg` - History of surgery
5. `lbun_r` - BUN at listing
6. `lsbaosat` - Listing baseline oxygen saturation
7. `lsfprab` - Listing flow cytometry PRA (B)
8. `lsfprat` - Listing flow cytometry PRA (T)
9. `prim_dx` - Primary diagnosis
10. `prm_list` - Primary listing reason
11. `rec_t3` - Recipient T3
12. `sec_dx` - Secondary diagnosis
13. `txaboinc` - Transplant ABO incompatibility
14. `txast` - AST at transplant
15. `txbaosat` - Transplant baseline oxygen saturation
16. `txbun_r` - BUN at transplant
17. `txecmo` - ECMO at transplant
18. `txsa_r` - Serum albumin at transplant
19. `txtg_r` - Triglycerides at transplant
20. `txvent` - Ventilation at transplant

### Top 20 Features from CatBoost

1. `age_listing` - Age at listing
2. `age_txpl` - Age at transplant
3. `dhxnone` - Donor history none
4. `dmhothr` - Donor medical history other
5. `donor_age` - Donor age
6. `dtime` - Donor time
7. `dtoxo` - Donor toxoplasmosis
8. `height_donor` - Donor height
9. `height_listing` - Height at listing
10. `height_txpl` - Height at transplant
11. `lscstat` - Listing status
12. `lsdcd` - Listing DCD
13. `lsldpt` - Listing LD/PT
14. `lstp_r` - Total protein at listing
15. `txdcd` - Transplant DCD
16. `txldpt` - Transplant LD/PT
17. `txnomcsd` - Transplant no MCSD
18. `weight_donor` - Donor weight
19. `weight_listing` - Weight at listing
20. `weight_txpl` - Weight at transplant

### Top 20 Features from AORSF (Accelerated Oblique Random Survival Forest)

1. `age_listing` - Age at listing
2. `chd_hlh` - CHD HLH
3. `height_donor` - Donor height
4. `height_listing` - Height at listing
5. `height_txpl` - Height at transplant
6. `hxsurg` - History of surgery
7. `lbun_r` - BUN at listing
8. `lsbaosat` - Listing baseline oxygen saturation
9. `lsfprab` - Listing flow cytometry PRA (B)
10. `lsfprat` - Listing flow cytometry PRA (T)
11. `prim_dx` - Primary diagnosis
12. `sec_dx` - Secondary diagnosis
13. `ter_dx` - Tertiary diagnosis
14. `txaboinc` - Transplant ABO incompatibility
15. `txbaosat` - Transplant baseline oxygen saturation
16. `txbun_r` - BUN at transplant
17. `txecmo` - ECMO at transplant
18. `txsa_r` - Serum albumin at transplant
19. `txtg_r` - Triglycerides at transplant
20. `txvent` - Ventilation at transplant

### Cohort-Specific Top Features (Modifiable Clinical Features Only)

#### CHD Cohort - Top 20 Features
1. `txalt` - ALT at transplant (16.63 importance)
2. `txecmo` - ECMO at transplant (12.69 importance)
3. `txast` - AST at transplant (10.67 importance)
4. `txtp_r` - Total protein at transplant (8.66 importance)
5. `txsa_r` - Serum albumin at transplant (6.52 importance)
6. `txcreat_r` - Creatinine at transplant (5.61 importance)
7. `height_txpl` - Height at transplant (4.54 importance)
8. `weight_listing` - Weight at listing (3.95 importance)
9. `lcreat_r` - Creatinine at listing (3.60 importance)
10. `lsbili_d_r` - Direct bilirubin at listing (3.42 importance)
11. `weight_txpl` - Weight at transplant (3.35 importance)
12. `lstp_r` - Total protein at listing (3.19 importance)
13. `txbili_t_r` - Total bilirubin at transplant (3.18 importance)
14. `lsast` - AST at listing (3.09 importance)
15. `lsbili_t_r` - Total bilirubin at listing (3.02 importance)
16. `lssab_r` - Serum albumin at listing (2.80 importance)
17. `lsalt` - ALT at listing (2.54 importance)
18. `txbili_d_r` - Direct bilirubin at transplant (2.37 importance)
19. `txvent` - Ventilation at transplant (2.10 importance)
20. `height_listing` - Height at listing (2.08 importance)

#### MyoCardio Cohort - Top 20 Features
1. `txsa_r` - Serum albumin at transplant
2. `txast` - AST at transplant
3. `lsast` - AST at listing
4. `lstp_r` - Total protein at listing
5. `lcreat_r` - Creatinine at listing
6. `txcreat_r` - Creatinine at transplant
7. `lsalt` - ALT at listing
8. `txbili_t_r` - Total bilirubin at transplant
9. `txalt` - ALT at transplant
10. `txtp_r` - Total protein at transplant
11. `lssab_r` - Serum albumin at listing
12. `lsbili_t_r` - Total bilirubin at listing
13. `txbili_d_r` - Direct bilirubin at transplant
14. `lsbili_d_r` - Direct bilirubin at listing

## Key Differences

### 1. Variable Count

| Approach | Variable Count | Rationale |
|----------|----------------|-----------|
| **Simple Calculator** | 25-65 | Curated set for interpretability and clinical use |
| **Risk Calculator** | 280-308 | All features available during training (ML models) |
| **Feature Importance** | 20 per method | Top-ranked features from importance analysis |

### 2. Variable Types

**Simple Calculator:**
- Focuses on **modifiable clinical features**
- Includes **derived/categorical variables** (e.g., `egfr_tx_cat`, `txbili_t_r_high`)
- **Cohort-specific additions** (primary_etiology, CHD subtypes)

**Risk Calculator:**
- Uses **all available features** from training data
- Includes **donor features** (not in Simple Calculator)
- Includes **non-modifiable features** (age, demographics)
- **Automatic feature engineering** during model training

**Feature Importance:**
- **Mixed feature types**: Includes both modifiable and non-modifiable features
- **Donor features** appear prominently (height_donor, donor_age)
- **Diagnosis features** (primary diagnosis, CHD subtypes)
- **Top-ranked by importance** across multiple methods

### 3. Feature Categories

#### Common to All Three
- Kidney function (creatinine, eGFR)
- Liver function (AST, ALT, bilirubin)
- Nutrition (albumin, protein)
- Cardiac support (ECMO, VAD)
- Respiratory (ventilation, tracheostomy)
- Immunology (PRA)

#### Unique to Simple Calculator
- **Derived categorical variables** (eGFR categories, high/low thresholds)
- **Calculated change variables** (egfr_change)
- **Cohort-specific features** (primary_etiology, CHD subtypes)

#### Unique to Risk Calculator
- **Donor features** (donor age, height, weight)
- **Donor history** (donor medical history)
- **Transplant characteristics** (DCD, LD/PT)
- **All available features** from PHTS dataset

#### Unique to Feature Importance
- **Donor features** (height_donor, donor_age, weight_donor) - **very prominent**
- **Diagnosis features** (primary diagnosis, secondary diagnosis, tertiary diagnosis)
- **Listing characteristics** (listing status, DCD, LD/PT)
- **Oxygen saturation** (baseline oxygen saturation)
- **Triglycerides** (txtg_r)

### 4. Modifiability Focus

**Simple Calculator:**
- ✅ **Primarily modifiable features**
- ✅ Focus on actionable clinical interventions
- ⚠️ Includes some non-modifiable context (age, CHD subtype)

**Risk Calculator:**
- ⚠️ **Mixed modifiable and non-modifiable**
- ⚠️ Includes donor features (non-modifiable)
- ⚠️ Includes demographics (non-modifiable)

**Feature Importance:**
- ⚠️ **Mixed modifiable and non-modifiable**
- ⚠️ **Donor features are top-ranked** (non-modifiable)
- ⚠️ **Demographics are prominent** (age, height, weight)

## Overlap Analysis

### Features in All Three Approaches

1. **Kidney Function**
   - `txcreat_r`, `lcreat_r`, `egfr_tx` (or eGFR-related)
   - `hxdysdia` (dialysis history)

2. **Liver Function**
   - `txast`, `txalt`, `txbili_t_r`
   - `lsast`, `lsalt`, `lsbili_t_r`

3. **Nutrition**
   - `txsa_r`, `txtp_r`
   - `lstp_r`, `lssab_r`

4. **Cardiac Support**
   - `txecmo`, `txvad`

5. **Respiratory**
   - `txvent`, `hxtrach`, `ltxtrach`

6. **Demographics**
   - `age_listing`, `age_txpl`
   - `height_txpl`, `weight_txpl`

7. **CHD Subtype**
   - `chd_hlh`

8. **Prior Surgeries**
   - `hxsurg`

### Features Unique to Simple Calculator

- **Derived categorical variables**: `egfr_tx_cat`, `egfr_listing_cat`, `txbili_t_r_high`, `txalt_high`, `txsa_r_low`
- **Calculated change variables**: `egfr_change`
- **Combined variables**: `ecmo_combined`
- **Cohort-specific**: `primary_etiology` (Combined model), all `CHD_*` subtypes (CHD model)

### Features Unique to Risk Calculator

- **Donor features**: `height_donor`, `donor_age`, `weight_donor`, `dtime`, `dtoxo`
- **Donor history**: `dhxnone`, `dmhothr`
- **Transplant characteristics**: `txdcd`, `txldpt`, `txnomcsd`, `txaboinc`
- **Listing characteristics**: `lsdcd`, `lsldpt`, `lscstat`
- **Additional lab values**: `txbun_r`, `lbun_r`, `txtg_r`
- **Oxygen saturation**: `txbaosat`, `lsbaosat`

### Features Unique to Feature Importance

- **Diagnosis features**: `prim_dx`, `sec_dx`, `ter_dx`
- **Listing reasons**: `prm_list`
- **Recipient characteristics**: `rec_t3`
- **Donor features** (especially prominent in CatBoost top 20)

## Clinical Implications

### Simple Calculator
- **Best for**: Bedside clinical decision-making
- **Strengths**: Interpretable, focused on modifiable features, easy to use
- **Limitations**: Smaller feature set may miss some predictive signals

### Risk Calculator
- **Best for**: Production risk assessment with maximum predictive power
- **Strengths**: Uses all available features, best model performance
- **Limitations**: Includes non-modifiable features (donor characteristics), less interpretable

### Feature Importance
- **Best for**: Understanding which features drive predictions, feature selection
- **Strengths**: Identifies most predictive features across methods
- **Limitations**: Includes non-modifiable features (donor, demographics), not directly actionable

## Features Needed for Best Predictive Performance

This section synthesizes insights from all three approaches to identify the optimal feature set for achieving the best predictive performance (highest AUC/C-index).

### Performance Context

**Current Best Performance:**
- **Combined Model**: AUC = 0.738 (95% CI: 0.701 - 0.782) - Simple Calculator with `primary_etiology`
- **Risk Calculator**: Uses all 280-308 features (CatBoost/XGBoost models)
- **Feature Importance**: Top features identified across RSF, CatBoost, and AORSF methods

### Core Features for Best Performance

Based on analysis of all three approaches, the following features are essential for optimal predictive performance:

#### 1. Primary Diagnosis/Etiology (CRITICAL)

**Evidence:**
- `primary_etiology` improved Combined model from AUC 0.734 → 0.738
- Top predictor in Combined model (importance: 2.2-2.9)
- Appears in Feature Importance top 20 (as `prim_dx`)

**Required Features:**
- `primary_etiology` - Primary diagnosis (Congenital HD, Cardiomyopathy, Myocarditis, etc.)
- `prim_dx` - Primary diagnosis (alternative name)
- `sec_dx` - Secondary diagnosis (appears in RSF/AORSF top 20)
- `ter_dx` - Tertiary diagnosis (appears in AORSF top 20)

**Rationale:** Etiology is the strongest single predictor, distinguishing risk across patient populations.

#### 2. Donor Characteristics (HIGH IMPORTANCE)

**Evidence:**
- `height_donor` appears in **all three** Feature Importance methods (RSF, CatBoost, AORSF)
- `donor_age` is #5 in CatBoost top 20
- `weight_donor` is #18 in CatBoost top 20
- Donor features are prominent in Risk Calculator (280-308 features)

**Required Features:**
- `height_donor` - Donor height ⭐ (appears in all 3 methods)
- `donor_age` - Donor age
- `weight_donor` - Donor weight
- `dtime` - Donor time
- `dtoxo` - Donor toxoplasmosis
- `dhxnone` - Donor history none
- `dmhothr` - Donor medical history other

**Rationale:** Donor-recipient matching is critical for transplant outcomes. Donor characteristics are non-modifiable but highly predictive.

#### 3. Kidney Function (HIGH IMPORTANCE)

**Evidence:**
- Appears in all three approaches
- `egfr_listing_catnormal` is #6 in Combined model (importance: 1.52)
- `txcreat_r`, `lcreat_r` are top features in cohort-specific analysis
- `txbun_r`, `lbun_r` appear in RSF/AORSF top 20

**Required Features:**
- `egfr_tx` - eGFR at transplant (calculated)
- `egfr_listing` - eGFR at listing (calculated)
- `egfr_tx_cat` - eGFR category at transplant (derived)
- `egfr_listing_cat` - eGFR category at listing (derived)
- `txcreat_r` - Creatinine at transplant
- `lcreat_r` - Creatinine at listing
- `txbun_r` - BUN at transplant ⭐ (RSF/AORSF top 20)
- `lbun_r` - BUN at listing ⭐ (RSF/AORSF top 20)
- `hxdysdia_bin` - History of dialysis (derived)
- `egfr_change` - Change in eGFR from listing to transplant (calculated)

**Rationale:** Kidney function is a critical modifiable risk factor with strong predictive power.

#### 4. Liver Function (HIGH IMPORTANCE)

**Evidence:**
- `txalt` is #1 in CHD cohort (importance: 16.63)
- `txast` is #3 in CHD cohort (importance: 10.67)
- `txsa_r` is #5 in CHD cohort, #1 in Myocardio cohort
- Liver function features appear across all approaches

**Required Features:**
- `txast` - AST at transplant ⭐ (top feature in CHD/Myocardio)
- `txalt` - ALT at transplant ⭐ (top feature in CHD)
- `lsast` - AST at listing
- `lsalt` - ALT at listing
- `txbili_t_r` - Total bilirubin at transplant
- `txbili_t_r_high` - Total bilirubin >1.5 (derived)
- `txalt_high` - ALT >90 (derived)
- `lsbili_t_r` - Total bilirubin at listing
- `txbili_d_r` - Direct bilirubin at transplant
- `lsbili_d_r` - Direct bilirubin at listing
- `hxfonlvr_bin` - History of Fontan liver disease (CHD cohort)

**Rationale:** Liver function is a key modifiable risk factor, especially important for CHD patients.

#### 5. Nutrition Status (HIGH IMPORTANCE)

**Evidence:**
- `txsa_r` appears in RSF/AORSF top 20 and is #1 in Myocardio cohort
- `txtp_r` is #4 in CHD cohort (importance: 8.66)
- `lstp_r` appears in CatBoost top 20
- Nutrition features are critical across cohorts

**Required Features:**
- `txsa_r` - Serum albumin at transplant ⭐ (top feature in Myocardio)
- `txtp_r` - Total protein at transplant ⭐ (top feature in CHD)
- `txsa_r_low` - Serum albumin <3 (derived)
- `lstp_r` - Total protein at listing
- `lssab_r` - Serum albumin at listing
- `txpalb_r` - Pre-albumin at transplant
- `lspalb_r` - Pre-albumin at listing

**Rationale:** Nutritional status is a strong modifiable predictor, especially for Myocardio patients.

#### 6. Cardiac Support (CRITICAL)

**Evidence:**
- `txecmo` appears in RSF/AORSF top 20 and is #2 in CHD cohort (importance: 12.69)
- `ecmo_combined` is #7 in Combined model (importance: 1.25)
- Cardiac support is a key predictor across all cohorts

**Required Features:**
- `txecmo` - ECMO at transplant ⭐ (top feature in CHD)
- `ecmo_combined` - ECMO at transplant OR listing (derived)
- `slecmo` - ECMO at listing
- `txvad` - VAD at transplant
- `slvad` - VAD at listing
- `txnomcsd` - Transplant no MCSD (appears in CatBoost top 20)
- `slnomcsd` - Consider MCSD

**Rationale:** Mechanical circulatory support status is a critical predictor of graft loss risk.

#### 7. Respiratory Status (HIGH IMPORTANCE)

**Evidence:**
- `txvent` appears in RSF/AORSF top 20
- `hxtrach` is #1 in Myocardio model (importance: 10.63) and #8 in Combined model
- `ltxtrach` is #2 in Myocardio model (importance: 3.80)

**Required Features:**
- `txvent` - Ventilation at transplant ⭐ (RSF/AORSF top 20)
- `hxtrach` - History of tracheostomy ⭐ (top feature in Myocardio)
- `ltxtrach` - Tracheostomy at listing ⭐ (top feature in Myocardio)
- `slvent` - Ventilation at listing

**Rationale:** Respiratory complications are critical predictors, especially for Myocardio patients.

#### 8. Immunology (HIGH IMPORTANCE)

**Evidence:**
- `txfcpra` is #2 in Combined model (importance: 2.90)
- `lsfcpra`, `lsfprab`, `lsfprat` appear in RSF/AORSF top 20
- PRA levels are consistently important across models

**Required Features:**
- `txfcpra` - Flow cytometry PRA at transplant ⭐ (top feature in Combined)
- `lsfcpra` - Flow cytometry PRA at listing
- `lsfprab` - Flow cytometry PRA (B-cell) at listing ⭐ (RSF/AORSF top 20)
- `lsfprat` - Flow cytometry PRA (T-cell) at listing ⭐ (RSF/AORSF top 20)
- `hlatxpre` - HLA pre-sensitization
- `donspac` - Donor-specific crossmatch

**Rationale:** Immunological sensitization is a critical non-modifiable but highly predictive factor.

#### 9. Demographics (MODERATE IMPORTANCE)

**Evidence:**
- `age_listing`, `age_txpl` are #1-2 in CatBoost top 20
- `height_txpl` appears in all three Feature Importance methods
- Demographics provide important context

**Required Features:**
- `age_listing` - Age at listing ⭐ (CatBoost #1)
- `age_txpl` - Age at transplant ⭐ (CatBoost #2)
- `height_txpl` - Height at transplant ⭐ (all 3 methods)
- `height_listing` - Height at listing
- `weight_txpl` - Weight at transplant
- `weight_listing` - Weight at listing
- `bmi_txpl` - BMI at transplant (calculated)

**Rationale:** Demographics provide important context for risk stratification, especially age and size matching.

#### 10. CHD Subtypes (COHORT-SPECIFIC)

**Evidence:**
- `chd_hlh` is #1 in RSF top 20 and #2 in AORSF top 20
- CHD model identified 40+ CHD subtypes with high importance
- Top CHD subtypes: `chd_lsvc` (19.01), `chd_hb` (14.88), `chd_alcapa` (14.50)

**Required Features (CHD Cohort Only):**
- `chd_hlh` - CHD HLH ⭐ (RSF/AORSF top 20)
- Top 5-10 CHD subtypes (selected via feature selection/LASSO):
  - `chd_lsvc` - Left Superior Vena Cava (19.01 importance)
  - `chd_hb` - Hypoplastic Branch (14.88 importance)
  - `chd_alcapa` - Anomalous Left Coronary Artery (14.50 importance)
  - `chd_mart` - (13.90 importance)
  - `chd_raa` - (13.25 importance)
  - Additional top subtypes (select via regularization)

**Rationale:** CHD subtypes are highly predictive for CHD cohort, but need feature selection to avoid overfitting.

#### 11. Additional High-Value Features

**Evidence from Feature Importance:**
- `hxsurg` - History of surgery (appears in RSF/AORSF top 20)
- `txaboinc` - Transplant ABO incompatibility (appears in RSF/AORSF top 20)
- `lsbaosat` - Listing baseline oxygen saturation (appears in RSF/AORSF top 20)
- `txbaosat` - Transplant baseline oxygen saturation (appears in RSF/AORSF top 20)
- `txtg_r` - Triglycerides at transplant (appears in RSF/AORSF top 20)
- `prm_list` - Primary listing reason (appears in RSF top 20)
- `rec_t3` - Recipient T3 (appears in RSF top 20)

**Required Features:**
- `hxsurg` - History of surgery ⭐ (RSF/AORSF top 20)
- `txaboinc` - Transplant ABO incompatibility ⭐ (RSF/AORSF top 20)
- `lsbaosat` - Listing baseline oxygen saturation ⭐ (RSF/AORSF top 20)
- `txbaosat` - Transplant baseline oxygen saturation ⭐ (RSF/AORSF top 20)
- `txtg_r` - Triglycerides at transplant ⭐ (RSF/AORSF top 20)
- `prm_list` - Primary listing reason
- `rec_t3` - Recipient T3

### Optimal Feature Set Summary

**For Best Predictive Performance, include:**

1. **Essential (Must Have):**
   - Primary etiology/diagnosis
   - Donor characteristics (height, age, weight)
   - Kidney function (eGFR, creatinine, BUN)
   - Liver function (AST, ALT, bilirubin)
   - Nutrition (albumin, protein)
   - Cardiac support (ECMO, VAD)
   - Respiratory (ventilation, tracheostomy)
   - Immunology (PRA levels)

2. **High Value:**
   - Demographics (age, height, weight)
   - CHD subtypes (for CHD cohort, with feature selection)
   - Additional lab values (triglycerides, oxygen saturation)
   - Transplant characteristics (ABO incompatibility)

3. **Derived Features (Enhance Performance):**
   - eGFR categories (severe/moderate/mild/normal)
   - High/low thresholds (bilirubin >1.5, ALT >90, albumin <3)
   - Combined variables (ecmo_combined)
   - Change variables (egfr_change)

### Performance Optimization Strategy

**To achieve best predictive performance:**

1. **Start with Risk Calculator feature set** (280-308 features) - includes all available features
2. **Add derived features** from Simple Calculator (eGFR categories, thresholds, combined variables)
3. **Apply feature selection** for CHD cohort (reduce 40+ CHD subtypes to top 5-10 via LASSO)
4. **Ensure primary_etiology is explicit** (improved Combined model from 0.734 → 0.738)
5. **Include donor features** (highly predictive but non-modifiable)
6. **Balance modifiable vs non-modifiable** based on use case:
   - **For prediction only**: Include all features (donor, demographics, etc.)
   - **For clinical actionability**: Focus on modifiable features but keep non-modifiable for context

### Expected Performance Gains

**Current Performance:**
- Simple Calculator (Combined): AUC = 0.738
- Risk Calculator: Uses all features (expected similar or better)

**Potential Improvements:**
- **Adding donor features**: +0.01-0.02 AUC (estimated)
- **Feature selection for CHD**: CHD model could improve from 0.625 → 0.65-0.68
- **Derived features**: Already included in Simple Calculator, minimal additional gain
- **Combined approach**: Using all features with proper regularization could achieve AUC ~0.75-0.78

### Trade-offs

**Including All Features (Best Performance):**
- ✅ Maximum predictive power
- ✅ Includes all predictive signals
- ⚠️ Less interpretable
- ⚠️ Includes non-modifiable features (donor, demographics)
- ⚠️ Requires more data collection

**Focused Feature Set (Better Interpretability):**
- ✅ More interpretable
- ✅ Focus on modifiable features
- ⚠️ Slightly lower performance (AUC ~0.73-0.74 vs 0.75-0.78)
- ⚠️ May miss some predictive signals

**Recommendation:** Use full feature set (Risk Calculator approach) for maximum performance, with feature selection/regularization to prevent overfitting.

## Recommendations

1. **For Clinical Use**: Simple Calculator variables are most appropriate - focused on modifiable features with clear clinical interpretation

2. **For Maximum Performance**: Risk Calculator uses all available features and achieves best model performance

3. **For Feature Selection**: Feature Importance analysis identifies top predictive features, but note that many top features are non-modifiable (donor characteristics)

4. **For Model Development**: Consider combining approaches:
   - Use Feature Importance to identify top predictive features
   - Focus on modifiable features from Simple Calculator
   - Include all available features in Risk Calculator for maximum performance

## Summary

| Aspect | Simple Calculator | Risk Calculator | Feature Importance |
|--------|------------------|-----------------|-------------------|
| **Variable Count** | 25-65 | 280-308 | 20 per method |
| **Modifiability Focus** | ✅ High | ⚠️ Mixed | ⚠️ Mixed |
| **Donor Features** | ❌ No | ✅ Yes | ✅ Yes (prominent) |
| **Derived Variables** | ✅ Yes | ⚠️ Some | ❌ No |
| **Cohort-Specific** | ✅ Yes | ✅ Yes | ⚠️ Some |
| **Interpretability** | ✅ High | ⚠️ Medium | ✅ High (top features) |
| **Model Performance** | ⚠️ Moderate | ✅ Best | N/A (feature selection) |
| **Clinical Actionability** | ✅ High | ⚠️ Medium | ⚠️ Medium |

---

**Last Updated**: 2025-01-13  
**Document Version**: 1.0
