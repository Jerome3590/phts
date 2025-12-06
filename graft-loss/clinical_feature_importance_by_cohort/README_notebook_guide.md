# Jupyter Notebook Guide: Clinical Cohort MC‑CV (Modifiable Features)

**Notebook:** `graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb`  
**Scope:** Etiology‑specific survival models (CHD vs MyoCardio) using **modifiable clinical features only**, with **Monte Carlo Cross‑Validation** and multiple algorithms (RSF, AORSF, CatBoost, XGBoost, XGBoost RF).

---

## 📓 What the Notebook Does

This notebook extends the original graft‑loss MC‑CV pipeline with a **clinical, cohort‑focused layer**:

1. Loads and cleans the PHTS transplant dataset (2010+).  
2. Constructs survival variables (`time`, `status`) consistent with the original Wisotzkey/bcjaeger definitions.  
3. Defines **two etiologic cohorts**:
   - **CHD**: `primary_etiology == "Congenital HD"`
   - **MyoCardio**: `primary_etiology %in% c("Cardiomyopathy", "Myocarditis")`
4. Defines a vetted set of **modifiable clinical features** (renal, liver, nutrition, respiratory, hemodynamic support, immunology).  
5. Fits **per‑cohort survival models** using only these clinical features:
   - RSF (ranger)
   - AORSF
   - CatBoost (Cox)
   - XGBoost‑Cox (boosting)
   - XGBoost‑Cox (RF‑mode via `num_parallel_tree`)  
6. Runs **MC‑CV within each cohort** (many 80/20 stratified splits) and aggregates C‑index and feature importance.  
7. Exports:
   - **C‑index by cohort & model**  
   - **Top clinical features** (with Category, Potential Intervention, Modifiability) for the **best model per cohort**.

The global 3‑period MC‑CV (Original / Full / Full‑No‑COVID) is still present near the top of the notebook and writes outputs under `graft-loss/feature_importance/outputs/`. Section **10.x** adds the **cohort + clinical feature** workflow described here.

---

## 🧱 Notebook Structure (High Level)

| Section | Purpose |
|--------|---------|
| **1. Setup & Configuration** | Load packages; configure parallelism, DEBUG mode, paths |
| **2. Helper Functions** | Data prep, leakage filtering, C‑index helpers, model wrappers |
| **3–7. Global MC‑CV (period-based)** | Original/Full/Full‑No‑COVID MC‑CV with RSF/CatBoost/AORSF |
| **8–9. Visualization & S3** | Heatmaps, bar charts, and optional S3 sync / EC2 shutdown |
| **10.1 Modifiable Clinical Features** | Define actionable feature list and clinical domains |
| **10.2 Cohort Survival Models (single 80/20 split)** | Fit all 5 models per cohort on modifiable features only |
| **10.3 Top Clinical Features (best model per cohort, single split)** | Extract ranked feature list for best model |
| **10.4 MC‑CV by Cohort (mod. features only)** | Repeated 80/20 MC‑CV within each cohort (RSF, AORSF, CatBoost, XGBoost, XGBoost RF) |

You primarily interact with **Section 10.x** when your goal is:

- “What are the **best modifiable clinical predictors** for graft loss **by etiology cohort**?”

---

## 🚀 How to Use (Cohort Clinical Feature Workflow)

### Option A – Quick smoke test (DEBUG mode)

Use this before long EC2 runs to check data, packages, and modeling loops:

```r
# In the configuration cell near the top
DEBUG_MODE <- TRUE
```

Effects:

- Global MC‑CV: drops to a small number of splits and may restrict to a single period.  
- Cohort MC‑CV (Section 10.4): `cohort_mc_n_splits <- 5` rather than 50.  

Steps:

1. Open the notebook: `graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb`.  
2. Set `DEBUG_MODE <- TRUE`.  
3. Run all cells.  
4. Confirm that:
   - `clinical_feature_importance_by_cohort/outputs/` contains the cohort CSV outputs.

### Option B – Full cohort MC‑CV run (recommended)

For standard analysis on EC2 or a powerful workstation:

```r
# Keep DEBUG_MODE FALSE
DEBUG_MODE <- FALSE

# In Section 10.4
cohort_mc_n_splits   <- 50   # can increase to 100 if desired
cohort_mc_train_prop <- 0.80
```

Then:

1. Run the notebook from top to bottom (`Cell > Run All`).  
2. Allow the global MC‑CV to finish (optional if you only care about cohorts).  
3. Ensure that Section 10.4 runs to completion; look for the message:  
   `✓ Saved cohort MC-CV metrics and best-feature tables to: clinical_feature_importance_by_cohort/outputs`.

Expected cohort outputs:

- `cohort_model_cindex_mc_cv_modifiable_clinical.csv`  
- `best_clinical_features_by_cohort_mc_cv.csv`

---

## ⚙️ Key Configuration Knobs (Cohort Section)

Within Section **10.1–10.4**, the most relevant parameters are:

```r
# 10.1: modifiable clinical feature set
actionable_features <- tribble(
  ~Feature,  ~Category, ~Potential_Intervention, ~Modifiability,
  # e.g.
  "txcreat_r", "Kidney Function", "Monitor kidney function", "Partially Modifiable",
  "egfr_tx",   "Kidney Function", "eGFR-based intervention", "Partially Modifiable",
  "txsa_r",    "Nutrition",       "Albumin-based nutrition", "Modifiable",
  ...
)

# 10.2: cohorts and outcome
cohorts <- list(
  CHD       = tx %>% filter(primary_etiology == "Congenital HD"),
  MyoCardio = tx %>% filter(primary_etiology %in% c("Cardiomyopathy", "Myocarditis"))
)

# 10.4: MC‑CV settings
cohort_mc_n_splits   <- 50      # number of MC‑CV splits per cohort
cohort_mc_train_prop <- 0.80    # 80/20 train/test
methods_for_mc <- c("RSF", "AORSF", "CatBoost", "XGBoost", "XGBoost_RF")
```

You can safely adjust:

- `cohort_mc_n_splits` (e.g., 20 for quick dev runs, 100 for more stable C‑Is).  
- `cohort_mc_train_prop` (if you want 70/30 instead of 80/20).  
- Methods included (drop or add methods from `methods_for_mc`).

---

## 📊 Expected Output (Cohort Clinical View)

### Console snippets

You should see messages like:

```text
========================================
Cohort: CHD
========================================
  Fitting RSF (ranger)...
  Fitting AORSF...
  Fitting CatBoost (Cox)...
  Fitting XGBoost-Cox (boosting)...
  Fitting XGBoost-Cox (RF mode)...
  Best model for CHD : XGBoost (C-index = 0.78)

----------------------------------------
MC-CV for cohort: MyoCardio
----------------------------------------
  Method: RSF
    ...
  Method: XGBoost_RF
    ...
✓ Saved cohort MC-CV metrics and best-feature tables to: clinical_feature_importance_by_cohort/outputs
```

### Output CSVs

Created under `graft-loss/clinical_feature_importance_by_cohort/outputs/`:

```text
cohort_model_cindex_modifiable_clinical.csv
cohort_model_cindex_mc_cv_modifiable_clinical.csv
best_clinical_features_by_cohort.csv
best_clinical_features_by_cohort_mc_cv.csv
```

Use:

- `cohort_model_cindex_mc_cv_modifiable_clinical.csv` to compare **C‑index across RSF / AORSF / CatBoost / XGBoost / XGBoost RF** by cohort.  
- `best_clinical_features_by_cohort_mc_cv.csv` to review **Top modifiable features** per cohort, annotated with:
  - `Category` (Kidney Function, Nutrition, Respiratory, Cardiac, Immunology, …)
  - `Potential_Intervention`
  - `Modifiability`

---

## 🔍 Interpreting Cohort Results

- **C‑index:**  
  - Values in the **0.70–0.85** range are realistic for survival models in this context.  
  - Compare **mean C‑index** and **95% CI** across models to pick a cohort‑specific “best model” (the notebook already records this).

- **Best model per cohort:**  
  - May differ between CHD and MyoCardio (e.g., AORSF best in CHD, XGBoost RF best in MyoCardio).  
  - Focus on the model with the highest **mean C‑index** and reasonably narrow CI.

- **Top modifiable features:**  
  - Look for features that are both:
    - Modifiable in practice (nutrition, organ function, support devices), and  
    - High in ranked importance (top‑10 / top‑25 for the best model).  
  - These are prime candidates for **clinical actionability** and further investigation.

---

## 📚 Related Files

- `README_original_vs_updated_study.md` – Original vs updated study and model set (including XGBoost).  
- `README_mc_cv_parallel_ec2.md` – Details on MC‑CV, parallelization, and EC2 usage for both global and cohort workflows.  
- `README_validation_concordance_variables_leakage.md` – C‑index, variable mapping, and leakage rationale.  

Use this notebook when you want **cohort‑specific, clinically actionable insights**; use the global `graft-loss/feature_importance` notebook and script when you need **period‑wide replication and publication‑grade MC‑CV across all variables**.


