# Preprocessing and Performance Alignment with README_ready_to_run

This document traces alignment between the **calculator** pipeline (Python, cohort-based) and the **reference** pipeline described in `graft-loss/cohort_analysis/README_ready_to_run.md` (R-based 1000-split MC-CV feature importance replication) where concordance index is reported as **~0.74** (RSF, Original period).

---

## Reference pipeline (README_ready_to_run)

- **Script**: `scripts/R/replicate_20_features_MC_CV.R` (sources `clean_phts.R`, `make_final_features.R` from graft-loss or graft-loss-parallel-processing).
- **Preprocessing** (applied before modeling):
  1. **CPBYPASS**: Removed from the dataset (excluded from all modeling).
  2. **DONISCH**: Converted from continuous (minutes) to **dichotomous**: `donisch = 1` if donor ischemic time **> 4 hours (>240 min)**, `donisch = 0` if ≤ 4 hours. Variable name remains `donisch`.
- **Configuration**: 1000 MC-CV splits, **75/25** train/test, top **20** predictors, periods Original (2010–2019), Full (2010–2024), Full No COVID.
- **C-index**: R computes both time-independent (Harrell’s) and time-dependent (e.g. riskRegression::Score). The README table (e.g. RSF 0.74, CatBoost 0.82, AORSF 0.76) is from this pipeline.

---

## Calculator pipeline alignment

### Preprocessing

| Item | Reference (README) | Calculator | Status |
|------|--------------------|------------|--------|
| **CPBYPASS** | Removed from dataset | Dropped via leakage keywords in `train_python_models.get_survival_leakage_keywords()` (pattern `"cpbypass"`) | ✅ Aligned |
| **DONISCH** | Dichotomous: >240 min = 1, ≤240 = 0 | **Training**: `run_shap_ffa_workflow.prepare_calculator_features()` converts continuous `donisch` (minutes) to binary (>240 → 1, else 0; missing → 0). **Inference**: `phts_lambda_function.prepare_features_for_inference()` converts user input (minutes) to same binary. | ✅ Aligned |

- **Where DONISCH is applied**
  - **Training**: `graft-loss/cohort_analysis/calculator/run_shap_ffa_workflow.py`, in the “DICHOTOMOUS VARIABLES” section of `prepare_calculator_features()`. If `donisch` exists and any value > 1 (minutes), it is replaced with 0/1; missing set to 0.
  - **Inference**: `graft-loss/cohort_analysis/calculator/risk_dashboard/phts_lambda_function.py`, in `prepare_features_for_inference()`. Raw donor ischemic time (minutes) is converted to 0/1 using threshold `DONISCH_DEFAULT_MINUTES` (240); missing → 0.

### Performance (C-index) calculation

| Aspect | Reference (R) | Calculator (Python) | Note |
|--------|----------------|---------------------|------|
| **Metric** | Harrell’s concordance (time-independent); also time-dependent (riskRegression) | Harrell’s concordance via `sksurv.metrics.concordance_index_censored(event_indicator, event_time, estimate)` | Same concept for time-independent C-index |
| **Where** | `replicate_20_features_MC_CV.R`: `calculate_cindex()` (and survival helpers) | `train_python_models.py`: `concordance_index_censored(status_test, time_test, risk_scores)` on **test** set per split | Both evaluate on held-out test data |

So for **time-independent C-index**, the calculator and the R replication use the same definition (Harrell’s concordance on test risk scores). Any reported difference in C-index is not due to a different formula but to data scope, splits, and feature set (below).

---

## Differences that can influence reported C-index

These do **not** affect preprocessing or the C-index *definition*, but they do affect **which** C-index you see (e.g. ~0.74 vs calculator values).

| Difference | Reference | Calculator | Effect |
|------------|-----------|------------|--------|
| **MC-CV splits** | 1000 | 25 (default) | Fewer splits → more variance in mean C-index; 0.74 is from 1000 splits. |
| **Train/test proportion** | 75/25 | 80/20 | Slightly different train/test sizes and thus different test C-index distribution. |
| **Split type** | Random stratified 75/25 | Stratified 80/20 (by status) then **temporal** split for final model (by `txpl_year`) | Calculator uses temporal holdout for final model; R uses random splits only. |
| **Feature set** | Top **20** predictors per period | Top **15** per cohort + Wisotzkey set | Different number and possibly different predictors. |
| **Cohort / period** | Time periods: Original (2010–2019), Full (2010–2024), Full No COVID | Clinical cohorts: **CHD**, **Myocardio**, **Combined** | Different subsets of data and outcome mix; C-index is cohort-specific in calculator. |
| **Models** | RSF, CatBoost, AORSF | CatBoost, XGBoost, XGBoost RF | Different algorithms; RSF ~0.74 is not directly comparable to XGBoost RF. |

So the **~0.74** figure is for **RSF**, **Original period (2010–2019)**, **1000 splits**, **75/25**, **top 20** features. The calculator reports C-index per **cohort** (CHD, Myocardio, Combined), with **25** splits, **80/20**, and **top 15** (and Wisotzkey), using **CatBoost/XGBoost**-family models. Aligning preprocessing (DONISCH, CPBYPASS) and C-index definition improves comparability; the remaining differences above explain why the numeric C-index values can differ.

---

## FULL model variants (C-index vs cohort segregation)

To test whether lower C-index is due to **cohort segregation** vs **feature restriction**, the calculator supports **FULL** variants that use the same cohorts but an expanded feature set aligned with the R top-20:

- **Feature set**: Calculator (base + derived + recommended) **plus** R replication variables: `durcarst`, `hxrenins`, `ltg_r`, `rec_t3`, `txaboinc`, `txtdsxm`.
- **Outputs**: `Combined_FULL`, `CHD_FULL`, `Myocardio_FULL` (saved under `outputs/models/<cohort>_FULL/`).
- **Usage**:
  - Single cohort: `python train_python_models.py --cohort Combined --full` (and similarly for `CHD`, `Myocardio`).
  - All three FULL variants: `python train_python_models.py --train-full-variants`.

Compare C-index in `mc_cv_model_metrics.csv` for each cohort’s base/enhanced vs `_FULL` to see how much is due to adding these variables vs segregating by cohort.

---

## Summary

- **Preprocessing**: Calculator now matches README on **CPBYPASS** (excluded) and **DONISCH** (dichotomous >240 min = 1, else 0) in both training and inference.
- **C-index**: Same **time-independent (Harrell’s)** notion; R and Python both evaluate on test data per split.
- **Why C-index can still differ**: Different number of splits (1000 vs 25), train fraction (75/25 vs 80/20), cohort/period definition (Original/Full vs CHD/Myocardio/Combined), feature count (20 vs 15), and models (RSF/CatBoost/AORSF vs CatBoost/XGBoost/XGBoost RF). To approximate the ~0.74 setting in the calculator you would need to align those choices (e.g. 75/25, more splits, same period/cohort and feature set as in the R replication).
