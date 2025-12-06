# ✅ Ready to Run: Clinical Cohort MC‑CV with Modifiable Features

**Scope:** How to run the **clinical cohort** Monte Carlo Cross‑Validation analysis on EC2 (or a workstation) using  
`graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb`.  

This workflow produces:

- **C‑index by cohort & model** (RSF, AORSF, CatBoost, XGBoost, XGBoost RF).  
- **Top modifiable clinical features** for the **best model in each cohort** (CHD vs MyoCardio).

---

## 🚀 Quick Start (EC2 + Jupyter)

### 1. Launch EC2 and SSH

```bash
# SSH into EC2
ssh -i your-key.pem ec2-user@your-ec2-ip

cd /path/to/phts
```

Make sure the PHTS `transplant.sas7bdat` data are available under `graft-loss/data/` (or wherever your helpers expect them).

### 2. Start Jupyter Notebook on EC2

```bash
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
```

On your **local machine**:

```bash
ssh -i your-key.pem -L 8888:localhost:8888 ec2-user@your-ec2-ip
```

Then open `http://localhost:8888` in your browser and navigate to:

- `graft-loss/clinical_feature_importance_by_cohort/graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb`

### 3. Choose Run Mode

In the configuration cell near the top of the notebook:

```r
DEBUG_MODE <- FALSE  # set to TRUE for smoke tests
```

Recommended:

- **Smoke test:** `DEBUG_MODE <- TRUE` (5 splits, very fast)  
- **Full cohort analysis:** `DEBUG_MODE <- FALSE`  
  - Global MC‑CV (period-based) + clinical cohort MC‑CV (Section 10.x)  
  - Or you can manually skip earlier cells if you only care about Section 10.x

### 4. Run the Notebook

In Jupyter:

- `Cell > Run All`

Expected runtime on a 32‑core EC2 instance:

- **Smoke test:** a few minutes.  
- **Full cohort MC‑CV (50 splits / cohort):** ~30–60 minutes depending on load.

---

## ⚙️ Key Settings (Cohort MC‑CV Section)

In Section **10.4** of the notebook:

```r
cohort_mc_n_splits   <- 50   # number of MC‑CV splits per cohort
cohort_mc_train_prop <- 0.80 # 80/20 train/test

methods_for_mc <- c(
  "RSF",        # Random Survival Forest (ranger)
  "AORSF",      # Accelerated Oblique Random Survival Forest
  "CatBoost",   # CatBoost with Cox loss
  "XGBoost",    # XGBoost-Cox boosting
  "XGBoost_RF"  # XGBoost-Cox RF mode
)
```

You can tune:

- `cohort_mc_n_splits` (e.g., 20 for quick dev runs, 100 for more stable estimates).  
- `methods_for_mc` (drop or add methods as needed).  

Parallelization:

- For EC2, you can use `future::plan(multisession, workers = 16–30)` to parallelize splits if memory allows.

---

## 📊 Outputs You Should See

All cohort clinical outputs live under:

```text
graft-loss/clinical_feature_importance_by_cohort/outputs/
```

Key files:

```text
cohort_model_cindex_modifiable_clinical.csv
cohort_model_cindex_mc_cv_modifiable_clinical.csv
best_clinical_features_by_cohort.csv
best_clinical_features_by_cohort_mc_cv.csv
```

These contain:

- **`cohort_model_cindex_mc_cv_modifiable_clinical.csv`**  
  - Columns: `Cohort`, `Model`, `C_Index_Mean`, `C_Index_SD`, `C_Index_CI_Lower`, `C_Index_CI_Upper`, `n_splits`.  
  - Rows: CHD × (RSF, AORSF, CatBoost, XGBoost, XGBoost RF), MyoCardio × same.

- **`best_clinical_features_by_cohort_mc_cv.csv`**  
  - Columns include: `Cohort`, `Model`, `feature`, `Base_Feature`, `importance`, `Category`, `Potential_Intervention`, `Modifiability`, `Rank`.  
  - Rows: MC‑CV–aggregated feature importance for the **best‑C‑index model in each cohort**.

---

## 👀 Monitoring on EC2

In a separate SSH session:

```bash
htop

watch -n 10 'ls -1 graft-loss/clinical_feature_importance_by_cohort/outputs/*.csv'
```

If you log output from R (e.g., running chunks via `Rscript` or using `sink()`), you can monitor:

```bash
tail -f cohort_mc_cv.log
grep -i "Best model for" cohort_mc_cv.log
```

You should see lines like:

```text
Best model for CHD : XGBoost (C-index = 0.78)
Best model for MyoCardio : AORSF (C-index = 0.76)
```

---

## ✅ Validation Checklist (Cohort Layer)

After the run:

1. **Files present**
   - Confirm the four key CSVs exist in `clinical_feature_importance_by_cohort/outputs/`.
2. **Reasonable C‑indices**
   - `C_Index_Mean` typically between **0.70 and 0.85**.  
   - Confidence intervals reasonably narrow (e.g., width < 0.10 for 50+ splits).
3. **Clinically sensible top features**
   - Top features should fall within expected domains:
     - Kidney function (`egfr_tx`, `txcreat_r`, `hxrenins`, …)  
     - Nutrition (`txsa_r`, `bmi_txpl`, `txtp_r`, …)  
     - Respiratory support (`txvent`, `slvent`, `hxtrach`, …)  
     - Cardiac support (`txecmo`, `txvad`, `slnomcsd`, `hxcpr`, …)  
     - Immunology (`txfcpra`, `lsfcpra`, `hlatxpre`, `donspac`, …)

If any of these checks fail (e.g., C‑indices near 1.0, or non-clinical leak variables showing up), revisit `README_validation_concordance_variables_leakage.md` and your feature list.

---

## 📚 Related Workflows

- **Global MC‑CV (period-based):**  
  - Notebook/script in `graft-loss/feature_importance/` (`graft_loss_feature_importance_20_MC_CV.ipynb`, `replicate_20_features_MC_CV.R`)  
  - Focus: Original/Full/Full‑No‑COVID periods, RSF/CatBoost/AORSF, all variables.

- **This clinical cohort MC‑CV (this folder):**  
  - Notebook: `graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb`  
  - Focus: CHD vs MyoCardio, **modifiable clinical features**, models RSF/AORSF/CatBoost/XGBoost/XGBoost RF.

Use the **global** pipeline for replication of the original study and overall feature importance, and the **cohort clinical** pipeline for **actionable, cohort‑specific clinical insights**.


