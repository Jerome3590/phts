# Cohort Analysis Features Documentation

This document describes the variables used in the cohort analysis for graft loss prediction.

## Overview

- **Total Variables in PHTS Dataset**: 476
- **Clinical Features Kept**: 51  
  - 41 **modifiable / partially modifiable** clinical features
  - 10 **non-modifiable but clinically important context features** (age, surgical history, CHD HLH, immunology)
- **Variables Excluded**: 43 exact matches + variables with prefixes: dtx_, cc_, dcon, dpri, dsec, dmaj, sd

## Variables Kept (Clinical Features)

The cohort analysis focuses on **clinically actionable features** (modifiable or partially modifiable) and a small set of **non-modifiable but clinically important context features** that substantially improve risk stratification and are needed for the bedside calculator.

### Kidney Function (5 features)
- `txcreat_r` - Creatinine at transplant (mg/dL)
- `lcreat_r` - Creatinine at listing (mg/dL)
- `hxdysdia` - History of dialysis
- `hxrenins` - History of renal insufficiency
- `egfr_tx` - Estimated GFR at transplant (mL/min/1.73m²) **[CALCULATED]**

### Liver Function (9 features)
- `txast` - AST at transplant (U/L)
- `lsast` - AST at listing (U/L)
- `txalt` - ALT at transplant (U/L)
- `lsalt` - ALT at listing (U/L)
- `txbili_d_r` - Direct bilirubin at transplant (mg/dL)
- `lsbili_d_r` - Direct bilirubin at listing (mg/dL)
- `txbili_t_r` - Total bilirubin at transplant (mg/dL)
- `lsbili_t_r` - Total bilirubin at listing (mg/dL)
- `hxfonlvr` - History of Fontan liver disease

### Nutrition (12 features)
- `txpalb_r` - Pre-albumin at transplant (mg/dL)
- `lspalb_r` - Pre-albumin at listing (mg/dL)
- `txsa_r` - Serum albumin at transplant (g/dL)
- `lssab_r` - Serum albumin at listing (g/dL)
- `txtp_r` - Total protein at transplant (g/dL)
- `lstp_r` - Total protein at listing (g/dL)
- `hxfail` - History of failure to thrive
- `bmi_txpl` - BMI at transplant (kg/m²) **[CALCULATED]**
- `height_txpl` - Height at transplant (cm)
- `height_listing` - Height at listing (cm)
- `weight_txpl` - Weight at transplant (kg)
- `weight_listing` - Weight at listing (kg)

### Respiratory (4 features)
- `txvent` - Ventilation at transplant
- `slvent` - Ventilation at listing
- `ltxtrach` - Tracheostomy at listing
- `hxtrach` - History of tracheostomy

### Cardiac Support (7 features)
- `txvad` - VAD at transplant
- `slvad` - VAD at listing
- `slnomcsd` - Consider MCSD
- `txecmo` - ECMO at transplant
- `slecmo` - ECMO at listing
- `hxcpr` - History of CPR
- `hxshock` - History of shock

### Immunology (4 features)
- `hlatxpre` - HLA pre-sensitization
- `donspac` - Donor-specific crossmatch
- `txfcpra` - Flow cytometry PRA at transplant (%)
- `lsfcpra` - Flow cytometry PRA at listing (%)
 - `lsfprat` - Flow cytometry PRA (T-cell) at listing (%)

### Demographics & Clinical Context (6 features)
- `age_listing` - Age at listing (years) *(non-modifiable context)*
- `age_txpl` - Age at transplant (years) *(non-modifiable context)*
- `hxsurg` - History of surgery *(non-modifiable context)*
- `chd_hlh` - Congenital heart disease with hypoplastic left heart syndrome *(non-modifiable context)*
- `height_zscore_txpl` - Height-for-age z-score at transplant **[CALCULATED]**
- `weight_zscore_txpl` - Weight-for-age z-score at transplant **[CALCULATED]**

## Top Features from Feature Importance Analysis

Feature importance analysis was performed using multiple methods (RSF, CatBoost, AORSF) to identify the most predictive features for graft loss. The following sections summarize the top features discovered.

### Feature Importance Analysis (Full Dataset)

**Top 20 Features from RSF (Random Survival Forest)**:
1. `chd_hlh` - CHD HLH (Congenital Heart Disease - Hemophagocytic Lymphohistiocytosis)
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

**Top 20 Features from CatBoost**:
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

**Top 20 Features from AORSF (Accelerated Oblique Random Survival Forest)**:
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

**Features Appearing in Multiple Models** (Most Consistent):
- `height_donor` - Appears in all 3 models
- `height_txpl` - Appears in all 3 models
- `age_listing` - Appears in 2 models (CatBoost, AORSF)
- `chd_hlh` - Appears in 2 models (RSF, AORSF)
- `hxsurg` - Appears in 2 models (RSF, AORSF)
- `lbun_r` - Appears in 2 models (RSF, AORSF)
- `lsbaosat` - Appears in 2 models (RSF, AORSF)
- `lsfprab` - Appears in 2 models (RSF, AORSF)
- `lsfprat` - Appears in 2 models (RSF, AORSF)
- `prim_dx` - Appears in 2 models (RSF, AORSF)
- `txecmo` - Appears in 2 models (RSF, AORSF)
- `txsa_r` - Appears in 2 models (RSF, AORSF)
- `txvent` - Appears in 2 models (RSF, AORSF)

### Cohort-Specific Top Features (Modifiable Clinical Features Only)

**CHD Cohort - Top 20 Features** (from cohort-specific MC-CV analysis):
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

**MyoCardio Cohort - Top 20 Features** (from cohort-specific MC-CV analysis):
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
15. `height_txpl` - Height at transplant
16. `weight_txpl` - Weight at transplant
17. `txpalb_r` - Pre-albumin at transplant
18. `lspalb_r` - Pre-albumin at listing
19. `txvent` - Ventilation at transplant
20. `txvad` - VAD at transplant

**Key Observations**:
- **Liver function markers** (`txast`, `txalt`, `lsast`, `lsalt`, bilirubin measures) are consistently important across cohorts
- **Nutrition markers** (`txsa_r`, `txtp_r`, `lstp_r`) are highly predictive, especially in MyoCardio cohort
- **Kidney function** (`txcreat_r`, `lcreat_r`) appears in top features for both cohorts
- **Cardiac support** (`txecmo`, `txvent`, `txvad`) is particularly important in CHD cohort
- **Growth parameters** (`height_txpl`, `weight_txpl`) are consistently important across analyses

### Important Features Excluded from Cohort Analysis

The following features were identified as important in the feature importance analysis but are **not included in the final cohort analysis feature set** because they are **non-modifiable** donor characteristics, diagnoses, demographics, or post-transplant complications. These features are documented here to provide transparency about what was considered but ultimately excluded.

#### Highly Important Excluded Features (Top Importance Scores)

**From CatBoost Analysis** (highest importance scores):
1. `dhxnone` - Donor history none (15.7 importance) - **Non-modifiable donor characteristic**
2. `dtoxo` - Donor toxoplasmosis (9.66 importance) - **Non-modifiable donor characteristic**
3. `txldpt` - Transplant LD/PT (7.81 importance) - **Non-modifiable transplant type**
4. `txdcd` - Transplant DCD (7.04 importance) - **Non-modifiable donor type**
5. `lsdcd` - Listing DCD (4.84 importance) - **Non-modifiable listing characteristic**
6. `age_txpl` - Age at transplant (3.98 importance) - **Non-modifiable demographic**
7. `age_listing` - Age at listing (3.57 importance) - **Non-modifiable demographic**
8. `txnomcsd` - Transplant no MCSD (2.97 importance) - **Non-modifiable transplant characteristic**

**From RSF Analysis**:
1. `prim_dx` - Primary diagnosis (0.00551 importance) - **Non-modifiable diagnostic variable**
2. `hxsurg` - History of surgery (0.00241 importance) - **Historical/non-modifiable**
3. `chd_hlh` - CHD HLH (0.00170 importance) - **Non-modifiable diagnostic variable**
4. `lsbaosat` - Listing baseline oxygen saturation (0.00167 importance) - **Baseline/non-modifiable**
5. `lsfprat` - Listing flow cytometry PRA (T) (0.00130 importance) - **Baseline immunology**

**From AORSF Analysis**:
1. `prim_dx` - Primary diagnosis (0.00319 importance) - **Non-modifiable diagnostic variable**
2. `hxsurg` - History of surgery (0.00221 importance) - **Historical/non-modifiable**
3. `chd_hlh` - CHD HLH (0.00191 importance) - **Non-modifiable diagnostic variable**
4. `lsbaosat` - Listing baseline oxygen saturation (0.00183 importance) - **Baseline/non-modifiable**

#### Complete List of Excluded Important Features

| Feature | RSF Importance | CatBoost Importance | AORSF Importance | Reason for Exclusion |
|---------|----------------|---------------------|------------------|---------------------|
| `age_listing` | - | 3.57 | 0.000539 | Non-modifiable demographic |
| `age_txpl` | - | 3.98 | - | Non-modifiable demographic |
| `chd_hlh` | 0.00170 | - | 0.00191 | Non-modifiable diagnostic |
| `dhxnone` | - | 15.7 | - | Non-modifiable donor characteristic |
| `dmhothr` | - | 1.74 | - | Non-modifiable donor characteristic |
| `donor_age` | - | 1.35 | - | Non-modifiable donor characteristic |
| `dtime` | - | 1.02 | - | Non-modifiable donor characteristic |
| `dtoxo` | - | 9.66 | - | Non-modifiable donor characteristic |
| `height_donor` | 0.000622 | 1.27 | 0.000572 | Non-modifiable donor characteristic |
| `hxsurg` | 0.00241 | - | 0.00221 | Historical/non-modifiable |
| `lbun_r` | 0.000756 | - | 0.000626 | Not in modifiable features list* |
| `lscstat` | - | 1.51 | - | Non-modifiable listing status |
| `lsdcd` | - | 4.84 | - | Non-modifiable listing characteristic |
| `lsfprab` | 0.00102 | - | 0.000825 | Not in modifiable features list* |
| `lsfprat` | 0.00130 | - | 0.000987 | Not in modifiable features list* |
| `lsbaosat` | 0.00167 | - | 0.00183 | Baseline/non-modifiable |
| `lsldpt` | - | 1.21 | - | Non-modifiable listing characteristic |
| `prim_dx` | 0.00551 | - | 0.00319 | Non-modifiable diagnostic |
| `prm_list` | 0.000586 | - | - | Non-modifiable listing reason |
| `rec_t3` | 0.000865 | - | - | Non-modifiable recipient characteristic |
| `sec_dx` | 0.000612 | - | 0.000698 | Non-modifiable diagnostic |
| `ter_dx` | - | - | 0.000567 | Non-modifiable diagnostic |
| `txaboinc` | 0.000552 | - | 0.000662 | Non-modifiable transplant characteristic |
| `txbaosat` | 0.000988 | - | 0.00120 | Baseline/non-modifiable |
| `txbun_r` | 0.00123 | - | 0.00122 | Not in modifiable features list* |
| `txdcd` | - | 7.04 | - | Non-modifiable transplant characteristic |
| `txldpt` | - | 7.81 | - | Non-modifiable transplant type |
| `txnomcsd` | - | 2.97 | - | Non-modifiable transplant characteristic |
| `txtg_r` | 0.000556 | - | 0.000584 | Not in modifiable features list* |
| `weight_donor` | - | 1.54 | - | Non-modifiable donor characteristic |

\* *These features (`lbun_r`, `lsfprab`, `lsfprat`, `txbun_r`, `txtg_r`) are clinical measurements but were not included in the modifiable features list used for cohort analysis. They may represent baseline measurements or were excluded for other methodological reasons.*

#### Reasons for Exclusion

1. **Donor Characteristics** (non-modifiable): `height_donor`, `weight_donor`, `donor_age`, `dhxnone`, `dmhothr`, `dtime`, `dtoxo`
2. **Diagnostic Variables** (non-modifiable): `prim_dx`, `sec_dx`, `ter_dx`, `chd_hlh`
3. **Demographics** (non-modifiable): `age_listing`, `age_txpl`
4. **Transplant/Listing Characteristics** (non-modifiable): `txdcd`, `txldpt`, `lsdcd`, `lsldpt`, `txnomcsd`, `txaboinc`, `lscstat`, `prm_list`
5. **Historical Variables** (non-modifiable): `hxsurg`
6. **Baseline Measurements** (non-actionable at time of prediction): `lsbaosat`, `txbaosat`
7. **Clinical Measurements Not in Modifiable List**: `lbun_r`, `lsfprab`, `lsfprat`, `txbun_r`, `txtg_r`, `rec_t3`

**Note**: The updated cohort analysis uses a **hybrid feature set**:
- A core of **modifiable / partially modifiable clinical features** (labs, organ function, hemodynamics, nutrition, immunology)
- A small set of **non-modifiable context features** (age, CHD HLH, surgical history, PRA at listing, WHO growth metrics) that are critical for risk interpretation and are surfaced in the calculator UI, even though they are not targets for intervention.

## Variables Dropped

### Exact Matches Excluded

The following variables are explicitly excluded:

- `ID`
- `ptid_e`
- `int_dead`
- `int_death`
- `graft_loss`
- `txgloss`
- `death`
- `event`
- `dpricaus`
- `deathspc`
- `concod`
- `age_death`
- `dlist`
- `txpl_year`
- `rrace_b`
- `rrace_a`
- `rrace_ai`
- `rrace_pi`
- `rrace_o`
- `rrace_un`
- `race`
- `patsupp`
- `pmorexam`
- `papooth`
- `pacuref`
- `pishltgr`
- `pathero`
- `pcadrec`
- `pcadrem`
- `pdiffib`
- `cpathneg`
- `dcardiac`
- `dneuro`
- `dreject`
- `dsecaccs`
- `dpriaccs`
- `dconmbld`
- `dconmal`
- `dconcard`
- `dconneur`
- `dconrej`
- `dmajbld`
- `dmalcanc`

### Prefix-Based Exclusions

All variables starting with the following prefixes are excluded:

- `dtx_*`
- `cc_*`
- `dcon*`
- `dpri*`
- `dsec*`
- `dmaj*`
- `sd*`

### Reasons for Exclusion

1. **Outcome/Leakage Variables**: Variables that directly indicate the outcome (e.g., `graft_loss`, `death`, `int_death`)
2. **Donor-Specific Variables**: Variables related to donor characteristics (e.g., `dtx_*`, `dcon*`, `dpri*`, `dsec*`)
3. **Identifier Variables**: Patient identifiers (e.g., `ID`, `ptid_e`)
4. **Non-Modifiable Variables**: Variables that cannot be changed through clinical intervention (e.g., `race`, `txpl_year`)
5. **Complication Variables**: Post-transplant complications that occur after the prediction timepoint

## Interquartile Range (IQR) for Numerical Variables

### Continuous Numerical Variables

The following table shows the IQR (25th percentile, median, 75th percentile) for continuous numerical variables:

| Variable | Q1 (25th) | Median | Q3 (75th) | IQR |
|----------|-----------|--------|-----------|-----|
| `txcreat_r` | 0.29 | 0.41 | 0.63 | 0.34 |
| `lcreat_r` | 0.30 | 0.43 | 0.63 | 0.33 |
| `txast` | 28.00 | 38.00 | 61.00 | 33.00 |
| `lsast` | 26.00 | 36.00 | 52.00 | 26.00 |
| `txalt` | 18.00 | 27.00 | 41.00 | 23.00 |
| `lsalt` | 18.00 | 27.00 | 42.00 | 24.00 |
| `txbili_d_r` | 0.10 | 0.20 | 0.40 | 0.30 |
| `lsbili_d_r` | 0.10 | 0.20 | 0.40 | 0.30 |
| `txbili_t_r` | 0.34 | 0.60 | 1.10 | 0.76 |
| `lsbili_t_r` | 0.40 | 0.70 | 1.17 | 0.77 |
| `txpalb_r` | 13.88 | 18.00 | 22.90 | 9.02 |
| `lspalb_r` | 12.40 | 16.80 | 21.50 | 9.10 |
| `txsa_r` | 3.30 | 3.80 | 4.20 | 0.90 |
| `lssab_r` | 3.10 | 3.60 | 4.10 | 1.00 |
| `txtp_r` | 5.70 | 6.50 | 7.20 | 1.50 |
| `lstp_r` | 5.40 | 6.20 | 7.00 | 1.60 |
| `height_txpl` | 27.56 | 41.81 | 60.24 | 32.68 |
| `height_listing` | 25.24 | 40.55 | 59.84 | 34.60 |
| `weight_txpl` | 17.64 | 39.02 | 100.09 | 82.45 |
| `weight_listing` | 14.50 | 35.49 | 97.00 | 82.50 |

### Binary Features (0/1)

The following table shows the percentage of patients with value 1 for binary features:

| Variable | % with Value 1 | Category | Description |
|----------|----------------|----------|-------------|
| `slnomcsd` | 76.9% | Cardiac | Consider MCSD (most common) |
| `txvad` | 31.2% | Cardiac | VAD at transplant |
| `hxfail` | 22.1% | Nutrition | History of failure to thrive |
| `slvent` | 20.5% | Respiratory | Ventilation at listing |
| `txvent` | 14.9% | Respiratory | Ventilation at transplant |
| `slvad` | 14.2% | Cardiac | VAD at listing |
| `hlatxpre` | 15.5% | Immunology | HLA pre-sensitization |
| `hxcpr` | 10.9% | Cardiac | History of CPR |
| `donspac` | 8.5% | Immunology | Donor-specific crossmatch |
| `slecmo` | 4.1% | Cardiac | ECMO at listing |
| `hxrenins` | 3.9% | Kidney Function | History of renal insufficiency |
| `hxfonlvr` | 3.9% | Liver Function | History of Fontan liver disease |
| `txecmo` | 3.4% | Cardiac | ECMO at transplant |
| `hxshock` | 3.8% | Cardiac | History of shock |
| `hxtrach` | 2.1% | Respiratory | History of tracheostomy |
| `ltxtrach` | 1.5% | Respiratory | Tracheostomy at listing |

**Note**: Binary features are coded as 0 (absent) or 1 (present). The percentage indicates the proportion of patients with the feature present (value = 1).

## Mapping to Transplant Data Dictionary

**Note**: The data dictionary file `Contents_Transplant.docx` (or `PHTSVariable.pdf`) contains detailed descriptions of all PHTS variables.

### Key Variable Mappings

| PHTS Variable | Data Dictionary Reference | Description |
|---------------|---------------------------|-------------|
| `txcreat_r` | Creatinine (Transplant) | Serum creatinine at time of transplant |
| `lcreat_r` | Creatinine (Listing) | Serum creatinine at time of listing |
| `egfr_tx` | **[CALCULATED]** | Estimated GFR calculated as: `0.413 * height_txpl / txcreat_r` |
| `txast` | AST (Transplant) | Aspartate aminotransferase at transplant |
| `txalt` | ALT (Transplant) | Alanine aminotransferase at transplant |
| `txbili_d_r` | Direct Bilirubin (Transplant) | Direct bilirubin at transplant |
| `txbili_t_r` | Total Bilirubin (Transplant) | Total bilirubin at transplant |
| `txpalb_r` | Pre-albumin (Transplant) | Pre-albumin at transplant |
| `txsa_r` | Serum Albumin (Transplant) | Serum albumin at transplant |
| `txtp_r` | Total Protein (Transplant) | Total protein at transplant |
| `bmi_txpl` | **[CALCULATED]** | BMI calculated as: `(weight_txpl / height_txpl^2) * 703` |
| `height_txpl` | Height (Transplant) | Patient height at transplant (cm) |
| `weight_txpl` | Weight (Transplant) | Patient weight at transplant (kg) |
| `txvent` | Ventilation (Transplant) | Mechanical ventilation at transplant |
| `txvad` | VAD (Transplant) | Ventricular assist device at transplant |
| `txecmo` | ECMO (Transplant) | Extracorporeal membrane oxygenation at transplant |
| `hlatxpre` | HLA Pre-sensitization | HLA antibody pre-sensitization status |
| `txfcpra` | Flow Cytometry PRA (Transplant) | Flow cytometry panel reactive antibody at transplant (%) |

**For complete variable descriptions, refer to the PHTS Data Dictionary (`PHTSVariable.pdf` or `Contents_Transplant.docx`).**

## Calculated Variables

### eGFR Calculation
Estimated Glomerular Filtration Rate (eGFR) is calculated using the Schwartz formula:

```r
egfr_tx = 0.413 * height_txpl / txcreat_r
```

Where:
- `height_txpl` is height at transplant in cm
- `txcreat_r` is serum creatinine at transplant in mg/dL
- The constant 0.413 is the Schwartz constant for pediatric patients

### BMI Calculation
Body Mass Index (BMI) is calculated as:

```r
bmi_txpl = (weight_txpl / height_txpl^2) * 703
```

Where:
- `weight_txpl` is weight at transplant in kg
- `height_txpl` is height at transplant in cm
- The factor 703 converts from kg/cm² to kg/m²

### WHO Growth Curve Calculations

WHO growth curve calculations (z-scores and percentiles) for height and weight have been implemented.

**Implementation**: The calculations are available in `scripts/calculate_who_zscore.R` and can be called via `scripts/calculate_derived_features.R`.

**Requirements**:
- Age (in months or years - will be converted to months)
- Sex (1 = male, 2 = female, or "M"/"F")
- Height at transplant (`height_txpl`) in cm
- Weight at transplant (`weight_txpl`) in kg

**Output Variables**:
- `height_zscore_txpl` - Height-for-age z-score
- `height_percentile_txpl` - Height-for-age percentile
- `weight_zscore_txpl` - Weight-for-age z-score
- `weight_percentile_txpl` - Weight-for-age percentile

**Note**: The implementation uses the `zscorer` R package if available, otherwise falls back to a placeholder implementation. For production use, install the `zscorer` package:
```r
install.packages("zscorer")
```

The calculations use:
- WHO Child Growth Standards for children < 5 years (0-60 months)
- WHO Growth Reference for children 5-19 years (61-228 months)

