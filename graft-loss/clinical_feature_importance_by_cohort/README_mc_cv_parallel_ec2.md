## MC-CV, Parallelization, and EC2 for Clinical Cohort Analysis

**Scope:** How the *cohort* clinical-feature workflow uses Monte Carlo Cross-Validation (MC‑CV), parallel processing, and EC2 for efficient runs.  
**Canonical notebook:** `graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb`  

This notebook focuses on **modifiable clinical features** and **etiology-specific cohorts**:

- **Cohorts:**
  - `CHD`: `primary_etiology == "Congenital HD"`
  - `MyoCardio`: `primary_etiology %in% c("Cardiomyopathy", "Myocarditis")`
- **Models per cohort:**
  - **RSF (ranger)**
  - **AORSF**
  - **CatBoost (Cox loss)**
  - **XGBoost-Cox (boosting mode)**
  - **XGBoost-Cox (Random Forest mode, many parallel trees)**

All of these are run **inside-cohort MC‑CV**, using only **modifiable clinical features** (renal, liver, nutrition, respiratory, hemodynamic support, immunology).

---

### 1. Monte Carlo Cross-Validation (MC‑CV) by Cohort

- **Goal:** Estimate model performance within each clinical cohort (CHD, MyoCardio) using repeated, stratified train/test splits that respect event rates.

- **Key cohort MC‑CV settings (in the notebook’s Section 10.4):**

```r
# Per-cohort MC‑CV (modifiable clinical features only)
cohort_mc_n_splits   <- if (exists("DEBUG_MODE") && DEBUG_MODE) 5 else 50
cohort_mc_train_prop <- 0.80   # 80% train, 20% test

methods_for_mc <- c(
  "RSF",         # Random Survival Forest (ranger)
  "AORSF",       # Accelerated Oblique Random Survival Forest
  "CatBoost",    # CatBoost with Cox loss
  "XGBoost",     # XGBoost-Cox boosting
  "XGBoost_RF"   # XGBoost-Cox RF mode (num_parallel_tree)
)
```

- **Behaviour:**
  - For each cohort separately (CHD, MyoCardio):
    - Use `rsample::mc_cv()` with `prop = cohort_mc_train_prop` and `strata = status` to create **many stratified 80/20 train/test splits**.
    - For each split and each method:
      - Fit the model on the **training** data (time/status + modifiable features only).
      - Predict risk scores on the **held-out test** data.
      - Compute C‑index on the **test** set.
    - Aggregate mean, SD, and 95% CI across all successful splits per `(cohort, model)`.
  - After MC‑CV completes:
    - Pick the **best model per cohort** by mean C‑index.
    - Aggregate feature importance across splits for that best model and map features back to clinical domains (renal, liver, nutrition, etc.).

**Outputs written by this section (in `clinical_feature_importance_by_cohort/outputs/`):**

- `cohort_model_cindex_mc_cv_modifiable_clinical.csv`  
  – MC‑CV C‑index summary per cohort × model.
- `best_clinical_features_by_cohort_mc_cv.csv`  
  – Aggregated feature importance for the **best model in each cohort**, annotated with:
  - `Category` (e.g., Kidney Function, Nutrition, Respiratory),
  - `Potential_Intervention`,
  - `Modifiability`.

---

### 2. Parallelization Strategy

Inside the **global** (period-based) MC‑CV section, the notebook already uses `future` and `furrr`. The **cohort MC‑CV section** reuses model wrappers that are parallel-friendly but, by default, runs *serially* across splits to keep memory predictable on modest machines.

If you want to parallelize the **cohort MC‑CV** as well:

```r
library(future)
library(furrr)

plan(multisession, workers = n_workers)

mc_results <- future_map(
  seq_len(cohort_mc_n_splits),
  function(i) {
    split <- mc_splits$splits[[i]]
    train_data <- rsample::analysis(split)
    test_data  <- rsample::assessment(split)
    # Fit RSF / AORSF / CatBoost / XGBoost / XGBoost RF here
  },
  .options = furrr_options(
    seed     = TRUE,
    packages = c(
      "dplyr", "purrr", "rsample", "tibble",
      "survival", "ranger", "aorsf",
      "catboost", "xgboost"
    )
  )
)

plan(sequential)
```

**Important notes:**

- **CatBoost:** keep `thread_count = 1` and `logging_level = "Silent"` inside each worker to avoid logger/thread-safety issues.
- **XGBoost:** the wrappers use `objective = "survival:cox"` and treat the event indicator as a weight; this is safe under parallelism.
- Always ensure the **same train/test split indices** are used across models so C‑indices remain comparable.

---

### 3. EC2 Usage Patterns

For cohort-level clinical analysis you generally do **fewer splits** than the global 3‑period pipeline (50–100 instead of 1000), so runtimes are substantially lower.

**Recommended EC2 settings for cohort MC‑CV:**

```r
cohort_mc_n_splits   <- 50   # default in notebook
cohort_mc_train_prop <- 0.80
n_workers            <- 16   # or 30 on a 32‑core instance
```

Rough guidance on runtimes (per full cohort MC‑CV run, 2 cohorts × 5 models):

- 16 cores, 50 splits: **~30–60 minutes**.
- 30 cores, 50 splits: **~20–40 minutes**.
- 30 cores, 100 splits: **~45–90 minutes**.

**Monitoring on EC2:**

```bash
htop                                # CPU usage by R processes
watch -n 10 'ls -1 graft-loss/clinical_feature_importance_by_cohort/outputs/*.csv'
tail -f cohort_mc_cv.log           # if you tee notebook/script output to a log
```

---

### 4. How This Fits with the Global MC‑CV Pipeline

You now have **two complementary MC‑CV layers**:

- **Global (period-based) MC‑CV** in `graft-loss/feature_importance/`  
  – 3 periods (Original, Full, Full‑No‑COVID), methods RSF/CatBoost/AORSF, all variables, outputs under `graft-loss/feature_importance/outputs/`.

- **Clinical cohort MC‑CV** in this folder (`clinical_feature_importance_by_cohort/`)  
  – Two clinical cohorts (CHD vs MyoCardio), models RSF/AORSF/CatBoost/XGBoost/XGBoost‑RF, **modifiable clinical features only**, outputs under `clinical_feature_importance_by_cohort/outputs/`.

Use:

- The **global pipeline** when you want publication-aligned replication and overall feature importance across time periods.
- The **clinical cohort pipeline** when you want **cohort-specific**, **actionable** clinical predictors for decision support (e.g., which renal, nutrition, or support-device variables drive risk in CHD vs MyoCardio).


