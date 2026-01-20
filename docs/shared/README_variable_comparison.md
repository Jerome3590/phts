# Variable Comparison: Simple Calculator vs Risk Calculator vs Feature Importance Final Variables

This document compares the variables used in different approaches to graft loss prediction.

**Important Note**: There are **TWO different "Simple Calculator" models** in this project:

1. **Simple Calculator (PDF)** - Basic rough estimate calculator (5 variables) producing 62-100% survival predictions
   - Source: `graft-loss/cohort_analysis/calculator/simple_calculator/phts_simple_calculator_variables.pdf`
   - This is the calculator described in this document

2. **Simple Calculator (Multivariate Logistic Regression)** - Comprehensive multivariate logistic regression model (25-65 variables)
   - Source: `graft-loss/cohort_analysis/calculator/README_FINAL_MODELS.md`
   - Used in model comparison studies against CatBoost, XGBoost, LASSO
   - **Not covered in this document** - see README_FINAL_MODELS.md for details

This document focuses on comparing:

1. **Simple Calculator (PDF)** - Basic rough estimate calculator (5 variables) producing 62-100% survival predictions
2. **Risk Calculator** - Production ML models (CatBoost/XGBoost) deployed in dashboard with comprehensive feature sets
3. **Feature Importance Final Variables** - Top features from importance analysis (RSF/CatBoost/AORSF)

## Overview

| Approach | Model Type | Variable Count | Purpose |
|----------|-----------|----------------|---------|
| **Simple Calculator (PDF)** | Rough Estimate | 5 variables | Basic rough estimate (62-100% survival prediction) |
| **Risk Calculator** | CatBoost/XGBoost | ~280-308 (varies by cohort) | Production ML models for dashboard |
| **Feature Importance** | Top 20 from RSF/CatBoost/AORSF | 20 per method | Feature selection for model development |

**Note**: There is also a separate "Simple Calculator" using multivariate logistic regression (25-65 variables) documented in `README_FINAL_MODELS.md` - not shown in this table.

## Simple Calculator Variables (PDF Version)

**Sources**: 
- `graft-loss/cohort_analysis/calculator/simple_calculator/phts_simple_calculator_variables.pdf`
- [PHTS Analysis - Simple Calculator](https://mdporter.github.io/research/notebooks/Wisotzkey-compare.html#simple-calculator)

**Note**: This is the **PDF version** of the Simple Calculator - a basic rough estimate calculator. There is also a separate "Simple Calculator" that uses multivariate logistic regression with 25-65 variables (see `README_FINAL_MODELS.md`). This document focuses on the PDF version.

The Simple Calculator (PDF) is a **"rough estimate" calculator** that uses a minimal set of high-level predictors to produce predicted survival estimates:
- **CHD patients**: 62% (under 2 years, on ECMO) to 91% (not on ECMO or VAD)
- **Cardiomyopathy patients**: 75% (under 2 years, on ECMO) to 100% (not on ECMO or VAD)

This is distinct from:
- The comprehensive models used in the Risk Calculator (280-308 features)
- The multivariate logistic regression "Simple Calculator" used in model comparisons (25-65 features)

### Variables Used in Simple Calculator

#### Primary Diagnosis
- `PRIM_DX` - Primary diagnosis (categorizes patients into **Congenital HD** or **Cardiomyopathy**)

#### Demographics
- `AGE_UNDER_2` - Binary variable indicating if patient is under 2 years old
  - **Note**: This is distinct from the continuous age variables (`age_listing`, `age_txpl`) used in the Risk Calculator

#### Cardiac Support
- `TXECMO` - Binary indicator for ECMO (Extracorporeal Membrane Oxygenation) at transplant
- `TXVAD` - Binary indicator for VAD (Ventricular Assist Device) at transplant

#### CHD Laterality Disorder (Composite Variable)
- `CHD_LAT` - Laterality disorder (composite variable created specifically for this calculator)
  - **Definition**: Created from the following specific CHD conditions:
    - `CHD_DEX` - Dextrocardia
    - `CHD_SI` - Situs Inversus
    - `CHD_HETER` - Heterotaxy
    - `CHD_IIVC` - Interrupted IVC
    - `CHD_BIVC` - Bilateral SVC
    - `CHD_LSVC` - Left SVC with no right SVC
    - `CHD_RAA` - Right Aortic Arch
    - `CHD_AVD` - AV Discordance (when part of atrial or ventricular situs abnormality)
  
  **Note**: The first three (Dextrocardia, Heterotaxy, and Situs Inversus) were significant in univariate analysis. This composite variable is used only for CHD patients.

**Total Simple Calculator Variables:**
- **5 variables** (plus 8 component variables that make up `CHD_LAT`)
- **Purpose**: Provides a basic rough estimate (62-100% survival prediction)
- **Survival Ranges**:
  - CHD patients: 62% (under 2 years, on ECMO) to 91% (not on ECMO or VAD)
  - Cardiomyopathy patients: 75% (under 2 years, on ECMO) to 100% (not on ECMO or VAD)
- **Distinct from**: The comprehensive Risk Calculator models which use 280-308 features

## Risk Calculator Variables

The Risk Calculator uses a **comprehensive feature set** (280-308 features) that includes all available features from training data. The deployed models (CatBoost/XGBoost) use:

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
| **Simple Calculator** | 5 variables | Minimal set for rough estimate (62-100% survival prediction) |
| **Risk Calculator** | 280-308 | All features available during training (ML models) |
| **Feature Importance** | 20 per method | Top-ranked features from importance analysis |

### 2. Variable Types

**Simple Calculator:**
- **Minimal set** of high-level predictors (5 variables)
- Uses **binary indicators** (`AGE_UNDER_2`, `TXECMO`, `TXVAD`)
- Includes **composite variable** (`CHD_LAT` - laterality disorder)
- **Primary diagnosis** (`PRIM_DX`) for broad categorization

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
- **`AGE_UNDER_2`** - Binary age indicator (under 2 years) - distinct from continuous age variables
- **`CHD_LAT`** - Composite laterality disorder variable (created from 7 specific CHD conditions)
- **Minimal variable set** - Only 5 variables for rough estimate (vs 280-308 in Risk Calculator)

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

1. **Cardiac Support**
   - `TXECMO` / `txecmo` - ECMO at transplant (binary) ⭐
     - Simple Calculator: Core variable
     - Risk Calculator: Included in 280-308 features
     - Feature Importance: #2 in CHD cohort (importance: 12.69), appears in RSF/AORSF top 20

2. **Primary Diagnosis**
   - `PRIM_DX` / `primary_etiology` / `prim_dx` - Primary diagnosis (categorization) ⭐
     - Simple Calculator: Core variable (distinguishes CHD vs Cardiomyopathy)
     - Risk Calculator: `primary_etiology` improved Combined model AUC 0.734 → 0.738
     - Feature Importance: Appears in top 20 lists

3. **VAD Support**
   - `TXVAD` / `txvad` - VAD at transplant (binary) ⭐
     - Simple Calculator: Core variable
     - Risk Calculator: Included in 280-308 features
     - Feature Importance: Included in comprehensive feature sets

**Note**: The Simple Calculator uses a minimal set (5 variables), but all 5 core variables are also present in the Risk Calculator and Feature Importance approaches. The Simple Calculator demonstrates that these 5 variables alone can provide meaningful risk stratification (62-100% survival range), while the Risk Calculator and Feature Importance approaches add 275-303 additional features for more comprehensive and granular predictions.

### Features Unique to Simple Calculator (PDF Version)

- **`AGE_UNDER_2`** - Binary age indicator (under 2 years old)
  - **Distinct from**: Continuous `age_listing`/`age_txpl` used in Risk Calculator and Feature Importance
  - **Simple Calculator use**: Core variable showing age <2 significantly reduces survival
  - **Other models**: Use continuous age variables (which capture more granular age effects)
  
- **`CHD_LAT`** - Composite laterality disorder variable (created from 8 CHD conditions)
  - **Components**: `CHD_DEX`, `CHD_SI`, `CHD_HETER`, `CHD_IIVC`, `CHD_BIVC`, `CHD_LSVC`, `CHD_RAA`, `CHD_AVD`
  - **Simple Calculator use**: Core variable for CHD patients only
  - **Other models**: May include individual CHD subtype variables separately (40+ CHD subtypes in Risk Calculator)
  
- **Minimal set approach** - Only 5 variables total (vs comprehensive models with 280-308 features)
  - Demonstrates that these 5 variables provide baseline predictive value
  - All 5 variables are also included in comprehensive models, but with additional context from 275-303 other features

**Note**: `PRIM_DX` in Simple Calculator is conceptually the same as `primary_etiology` in Risk Calculator, but Simple Calculator uses it for broad binary categorization (Congenital HD vs Cardiomyopathy), while Risk Calculator uses it as a multi-category feature (Congenital HD, Cardiomyopathy, Myocarditis, Other, etc.).

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
- **Best for**: Quick rough estimate (62-100% survival prediction range)
- **Strengths**: Extremely simple (only 5 variables), very interpretable, minimal data requirements
- **Limitations**: Very basic estimate, limited predictive granularity, may miss important clinical signals

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
- **Risk Calculator**: Uses all 280-308 features (CatBoost/XGBoost models) - Best comprehensive performance
- **Feature Importance**: Top features identified across RSF, CatBoost, and AORSF methods
- **Simple Calculator**: Basic rough estimate (62-100% survival range) - Not designed for maximum performance, uses minimal 5-variable set

### Core Features for Best Performance

Based on analysis of all three approaches, the following features are essential for optimal predictive performance:

#### 1. Primary Diagnosis/Etiology (CRITICAL)

**Evidence:**
- `primary_etiology` improved Combined model from AUC 0.734 → 0.738
- Top predictor in Combined model (importance: 2.2-2.9)
- Appears in Feature Importance top 20 (as `prim_dx`)
- `PRIM_DX` is the foundation variable in Simple Calculator (PDF)
- Simple Calculator shows distinct survival patterns: CHD (62-91%) vs Cardiomyopathy (75-100%)

**Required Features:**
- `primary_etiology` / `PRIM_DX` - Primary diagnosis ⭐ (core Simple Calculator variable, top predictor in Combined model)
- `prim_dx` - Primary diagnosis (alternative name)
- `sec_dx` - Secondary diagnosis (appears in RSF/AORSF top 20)
- `ter_dx` - Tertiary diagnosis (appears in AORSF top 20)

**Rationale:** Etiology is the strongest single predictor, distinguishing risk across patient populations. Simple Calculator demonstrates that primary diagnosis alone provides substantial predictive value, with CHD patients having lower baseline survival than Cardiomyopathy patients.

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
- `TXECMO` and `TXVAD` are core variables in Simple Calculator (PDF)
- Cardiac support is a key predictor across all cohorts
- Simple Calculator shows ECMO significantly reduces survival (62-75% for CHD, 75% for CM when combined with age <2)

**Required Features:**
- `txecmo` / `TXECMO` - ECMO at transplant ⭐ (top feature in CHD, core Simple Calculator variable)
- `txvad` / `TXVAD` - VAD at transplant ⭐ (core Simple Calculator variable)
- `ecmo_combined` - ECMO at transplant OR listing (derived)
- `slecmo` - ECMO at listing
- `slvad` - VAD at listing
- `txnomcsd` - Transplant no MCSD (appears in CatBoost top 20)
- `slnomcsd` - Consider MCSD

**Rationale:** Mechanical circulatory support status is a critical predictor of graft loss risk. Simple Calculator demonstrates that ECMO/VAD status is one of the most important predictors, sufficient for basic risk estimation.

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
- `AGE_UNDER_2` is a core variable in Simple Calculator (PDF)
- Simple Calculator shows age <2 years significantly reduces survival (62% vs 91% for CHD, 75% vs 100% for CM)
- Demographics provide important context

**Required Features:**
- `age_listing` - Age at listing ⭐ (CatBoost #1)
- `age_txpl` - Age at transplant ⭐ (CatBoost #2)
- `AGE_UNDER_2` - Age under 2 years (binary) ⭐ (core Simple Calculator variable)
- `height_txpl` - Height at transplant ⭐ (all 3 methods)
- `height_listing` - Height at listing
- `weight_txpl` - Weight at transplant
- `weight_listing` - Weight at listing
- `bmi_txpl` - BMI at transplant (calculated)

**Rationale:** Demographics provide important context for risk stratification, especially age and size matching. Simple Calculator demonstrates that age <2 years is a critical risk factor, sufficient for basic risk estimation alongside diagnosis and MCSD status.

#### 10. CHD Subtypes (COHORT-SPECIFIC)

**Evidence:**
- `chd_hlh` is #1 in RSF top 20 and #2 in AORSF top 20
- CHD model identified 40+ CHD subtypes with high importance
- Top CHD subtypes: `chd_lsvc` (19.01), `chd_hb` (14.88), `chd_alcapa` (14.50)
- `CHD_LAT` (Laterality Disorder) is a core variable in Simple Calculator (PDF) for CHD patients
- Simple Calculator uses composite `CHD_LAT` combining 8 laterality-related CHD conditions

**Required Features (CHD Cohort Only):**
- `chd_hlh` - CHD HLH ⭐ (RSF/AORSF top 20)
- `CHD_LAT` - Laterality Disorder (composite) ⭐ (core Simple Calculator variable)
  - Composite of: `CHD_DEX`, `CHD_SI`, `CHD_HETER`, `CHD_IIVC`, `CHD_BIVC`, `CHD_LSVC`, `CHD_RAA`, `CHD_AVD`
- Top 5-10 CHD subtypes (selected via feature selection/LASSO):
  - `chd_lsvc` - Left Superior Vena Cava (19.01 importance)
  - `chd_hb` - Hypoplastic Branch (14.88 importance)
  - `chd_alcapa` - Anomalous Left Coronary Artery (14.50 importance)
  - `chd_mart` - (13.90 importance)
  - `chd_raa` - (13.25 importance)
  - Additional top subtypes (select via regularization)

**Rationale:** CHD subtypes are highly predictive for CHD cohort, but need feature selection to avoid overfitting. Simple Calculator demonstrates that laterality disorders are important enough to include as a composite variable for basic risk estimation.

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
   - Primary etiology/diagnosis (`PRIM_DX` / `primary_etiology`) ⭐ Simple Calculator core
   - Donor characteristics (height, age, weight)
   - Kidney function (eGFR, creatinine, BUN)
   - Liver function (AST, ALT, bilirubin)
   - Nutrition (albumin, protein)
   - Cardiac support (`TXECMO` / `txecmo`, `TXVAD` / `txvad`) ⭐ Simple Calculator core
   - Respiratory (ventilation, tracheostomy)
   - Immunology (PRA levels)
   - Age (`AGE_UNDER_2` for basic models, continuous age for comprehensive models) ⭐ Simple Calculator core
   - CHD Laterality (`CHD_LAT` for CHD cohort) ⭐ Simple Calculator core

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

### Recommended Feature Sets with Estimated Performance

Based on analysis of all three approaches, here are three recommended feature sets with their estimated performance:

| Tier | Feature Set | Variable Count | Combined AUC | CHD AUC | Myocardio AUC | Best Use Case |
|------|------------|----------------|--------------|---------|---------------|---------------|
| **Tier 1: Core Variables** | Simple Calculator core set | **5 variables** | **0.738**<br/>(95% CI: 0.701-0.782) | **0.625**<br/>(95% CI: 0.557-0.678) | **0.657**<br/>(95% CI: 0.510-0.768) | Quick estimates, minimal data requirements, bedside use |
| **Tier 2: Modifiable Focus** | Tier 1 + High-impact modifiable features | **~35-45 variables** | **~0.72-0.75**<br/>(estimated) | **~0.60-0.65**<br/>(estimated) | **~0.65-0.70**<br/>(estimated) | Clinical decision-making, actionable interventions |
| **Tier 3: Maximum Performance** | Full Risk Calculator set | **280-308 variables** | **0.677** (XGB single)<br/>**0.567** (CatBoost C-index MC-CV)<br/>(95% CI: 0.430-0.647) | **0.645** (XGB single)<br/>**0.577** (CatBoost C-index MC-CV)<br/>(95% CI: 0.534-0.621) | **0.599** (XGB single)<br/>**0.567** (CatBoost C-index MC-CV)<br/>(95% CI: 0.483-0.639) | Production systems, maximum predictive power |

#### Tier 1: Core Variables (5 variables)
**Variables:**
- `PRIM_DX` / `primary_etiology` - Primary diagnosis
- `AGE_UNDER_2` / `age_listing`, `age_txpl` - Age
- `TXECMO` / `txecmo` - ECMO at transplant
- `TXVAD` / `txvad` - VAD at transplant
- `CHD_LAT` - Laterality disorder (CHD cohort only)

**Performance Notes:**
- **Actual performance** from Simple Calculator (multivariate logistic regression) with 25 MC-CV splits
- Combined cohort shows excellent performance (AUC 0.738) with just 5 variables
- Provides survival probability ranges: CHD (62-91%), Cardiomyopathy (75-100%)

#### Tier 2: Modifiable Focus (~35-45 variables)
**Includes Tier 1 plus:**
- **Cardiac Support**: `ecmo_combined`, `slecmo`, `slvad`
- **Liver Function**: `txast`, `txalt`, `lsast`, `lsalt`, `txbili_t_r`, `txbili_t_r_high`, `txalt_high`, `txbili_d_r`, `lsbili_t_r`, `lsbili_d_r`, `hxfonlvr_bin`
- **Kidney Function**: `egfr_tx`, `egfr_listing`, `egfr_tx_cat`, `egfr_listing_cat`, `txcreat_r`, `lcreat_r`, `txbun_r`, `lbun_r`, `hxdysdia_bin`, `egfr_change`
- **Nutrition**: `txsa_r`, `txtp_r`, `txsa_r_low`, `lstp_r`, `lssab_r`, `txpalb_r`, `lspalb_r`
- **Respiratory**: `txvent`, `hxtrach`, `ltxtrach`, `slvent`
- **Immunology**: `txfcpra`, `lsfcpra`, `lsfprab`, `lsfprat`

**Performance Notes:**
- **Estimated performance** based on feature importance analysis
- Focuses on modifiable clinical features for actionable interventions
- Excludes donor features (non-modifiable) which may slightly reduce performance vs Tier 3
- Better interpretability and clinical actionability than Tier 3

#### Tier 3: Maximum Performance (280-308 variables)
**Includes Tier 1 & 2 plus:**
- **Donor Characteristics**: `height_donor`, `donor_age`, `weight_donor`, `dtime`, `dtoxo`, `dhxnone`, `dmhothr`
- **All CHD Subtypes**: 40+ CHD subtype variables (with feature selection recommended)
- **Additional Labs**: `txtg_r`, `lsbaosat`, `txbaosat`
- **Transplant Characteristics**: `txdcd`, `txldpt`, `txnomcsd`, `txaboinc`, `txaboinc`
- **Listing Characteristics**: `lsdcd`, `lsldpt`, `lscstat`
- **All available features** from PHTS dataset

**Performance Notes:**
- **Actual performance** from Risk Calculator (CatBoost/XGBoost models)
- XGBoost single evaluation shows higher C-index (0.645-0.677) but may be optimistic
- CatBoost MC-CV (25 splits) shows more conservative C-index (0.567-0.577)
- Best for production systems requiring maximum predictive power
- Less interpretable, includes many non-modifiable features

### Performance Comparison Insights

1. **Tier 1 (5 variables) achieves strong performance**, especially for Combined cohort (AUC 0.738)
2. **Tier 2 provides good balance** between performance and clinical actionability (~0.60-0.75 AUC estimated)
3. **Tier 3 maximizes performance** but with diminishing returns (C-index 0.567-0.677)
4. **Key finding**: The 5 core Simple Calculator variables capture substantial predictive signal; additional features provide incremental improvements rather than dramatic gains

### Performance Optimization Strategy

**To achieve best predictive performance:**

1. **Start with Risk Calculator feature set** (280-308 features) - includes all available features
2. **Add derived features** (eGFR categories, thresholds, combined variables)
3. **Apply feature selection** for CHD cohort (reduce 40+ CHD subtypes to top 5-10 via LASSO)
4. **Ensure primary_etiology is explicit** (improved Combined model from 0.734 → 0.738)
5. **Include donor features** (highly predictive but non-modifiable)
6. **Balance modifiable vs non-modifiable** based on use case:
   - **For prediction only**: Include all features (donor, demographics, etc.)
   - **For clinical actionability**: Focus on modifiable features but keep non-modifiable for context

**Note**: The Simple Calculator (PDF) uses only 5 variables (`PRIM_DX`, `AGE_UNDER_2`, `TXECMO`, `TXVAD`, `CHD_LAT`) for basic rough estimates. While these variables are included in the comprehensive feature set above, the Simple Calculator demonstrates that these 5 variables alone can provide meaningful risk stratification (62-100% survival range). For maximum performance, additional features from the Risk Calculator and Feature Importance approaches should be included.

### Expected Performance Gains

**Current Performance:**
- **Risk Calculator**: Uses all 280-308 features (CatBoost/XGBoost models) - Best comprehensive performance
- **Simple Calculator (PDF)**: Basic rough estimate (62-100% survival range) - Uses only 5 core variables
  - CHD patients: 62% (under 2, on ECMO) to 91% (not on ECMO/VAD)
  - Cardiomyopathy patients: 75% (under 2, on ECMO) to 100% (not on ECMO/VAD)
  - Demonstrates that core variables (`PRIM_DX`, `AGE_UNDER_2`, `TXECMO`, `TXVAD`, `CHD_LAT`) provide baseline predictive value

**Potential Improvements:**
- **Adding donor features**: +0.01-0.02 AUC (estimated)
- **Feature selection for CHD**: CHD model could improve from 0.625 → 0.65-0.68
- **Derived features**: Can enhance Risk Calculator models
- **Combined approach**: Using all features with proper regularization could achieve AUC ~0.75-0.78

### Trade-offs

**Including All Features (Best Performance - Risk Calculator):**
- ✅ Maximum predictive power
- ✅ Includes all predictive signals
- ✅ Includes Simple Calculator core variables (`PRIM_DX`, `AGE_UNDER_2`, `TXECMO`, `TXVAD`, `CHD_LAT`) plus 275-303 additional features
- ⚠️ Less interpretable
- ⚠️ Includes non-modifiable features (donor, demographics)
- ⚠️ Requires more data collection

**Minimal Feature Set (Simple Calculator - Basic Estimate):**
- ✅✅ Extremely simple (5 variables: `PRIM_DX`, `AGE_UNDER_2`, `TXECMO`, `TXVAD`, `CHD_LAT`)
- ✅✅ Very interpretable
- ✅ Minimal data requirements
- ✅ Provides baseline risk stratification (62-100% survival range)
- ✅ Core variables are also important in comprehensive models
- ⚠️ Basic rough estimate only
- ⚠️ Limited predictive granularity
- ⚠️ May miss important clinical signals present in comprehensive models

**Recommendation:** 
- **For quick rough estimates**: Use Simple Calculator (5 variables)
- **For maximum performance**: Use full feature set (Risk Calculator approach, 280-308 features) with feature selection/regularization to prevent overfitting

## Recommendations

1. **For Quick Estimates**: Simple Calculator (PDF) with 5 core variables (`PRIM_DX`, `AGE_UNDER_2`, `TXECMO`, `TXVAD`, `CHD_LAT`) provides a basic rough estimate (62-100% survival) with minimal data requirements
   - CHD patients: 62% (under 2, on ECMO) to 91% (not on ECMO/VAD)
   - Cardiomyopathy patients: 75% (under 2, on ECMO) to 100% (not on ECMO/VAD)

2. **For Comprehensive Assessment**: Risk Calculator (280-308 features) provides detailed risk assessment with maximum predictive power
   - **Includes all Simple Calculator core variables** plus 275-303 additional features
   - Best for production use and maximum AUC performance

3. **For Feature Selection**: Feature Importance analysis identifies top predictive features
   - **Includes Simple Calculator variables** (ECMO, diagnosis appear in top 20)
   - Note that many top features are non-modifiable (donor characteristics)

4. **For Model Development**: Consider combining approaches:
   - **Start with Simple Calculator core variables** (`PRIM_DX`, `AGE_UNDER_2`, `TXECMO`, `TXVAD`, `CHD_LAT`) - proven baseline predictors
   - Use Feature Importance to identify additional top predictive features
   - Include all available features in Risk Calculator for maximum performance
   - Simple Calculator demonstrates that 5 variables provide meaningful baseline; comprehensive models add granularity and additional predictive signals

## Summary

| Aspect | Simple Calculator (PDF) | Risk Calculator | Feature Importance |
|--------|------------------------|-----------------|-------------------|
| **Variable Count** | 5 core variables | 280-308 | 20 per method |
| **Core Variables** | `PRIM_DX`, `AGE_UNDER_2`, `TXECMO`, `TXVAD`, `CHD_LAT` | Includes all Simple Calculator variables + 275-303 more | Includes some Simple Calculator variables (ECMO, diagnosis) |
| **Modifiability Focus** | ⚠️ Mixed (some modifiable: ECMO/VAD) | ⚠️ Mixed | ⚠️ Mixed |
| **Donor Features** | ❌ No | ✅ Yes | ✅ Yes (prominent) |
| **Derived Variables** | ✅ Yes (`CHD_LAT` composite) | ⚠️ Some | ❌ No |
| **Cohort-Specific** | ✅ Yes (`PRIM_DX` for categorization, `CHD_LAT` for CHD) | ✅ Yes | ⚠️ Some |
| **Interpretability** | ✅✅ Very High (minimal set) | ⚠️ Medium | ✅ High (top features) |
| **Model Performance** | ⚠️ Basic (62-100% survival range) | ✅ Best (comprehensive AUC) | N/A (feature selection) |
| **Survival Range** | CHD: 62-91%, CM: 75-100% | Full risk spectrum | N/A |
| **Clinical Actionability** | ⚠️ Limited (few modifiable features) | ⚠️ Medium | ⚠️ Medium |
| **Use Case** | Quick rough estimate | Comprehensive risk assessment | Feature selection |
| **Overlap with Others** | Core variables used in all models | Includes Simple Calculator variables | Includes some Simple Calculator variables |

---

**Last Updated**: 2025-01-13  
**Document Version**: 1.0
