# Jupyter Notebook Guide: MC-CV Implementation

**Notebook:** `graft_loss_feature_importance_20_MC_CV.ipynb`  
**Created:** November 21, 2025  
**Status:** Ready to use

---

## 📓 What's in the Notebook

A complete, runnable Jupyter notebook (R kernel) that implements Monte Carlo Cross-Validation for graft loss feature importance analysis.

### Notebook Structure

| Section | Cells | Purpose |
|---------|-------|---------|
| **1. Setup** | 2 | Load packages and configure parallel processing |
| **2. Helper Functions** | 2 | Data preparation and C-index calculation |
| **3. MC-CV Function** | 2 | Main cross-validation implementation |
| **4. Load Data** | 3 | Load PHTS data and define time periods |
| **5. Run Analysis** | 2 | Execute MC-CV for all methods/periods |
| **6. Save Results** | 3 | Create and save summary tables |
| **7. Sync to S3** | 1 | Upload results and code to S3 |
| **8. Visualize Results** | 1 | Create feature importance heatmaps, C-index heatmaps, and scaled bar charts |

**Total:** 15 code cells + 5 markdown cells = 20 cells

---

## 🚀 How to Use

### Option 1: Run All Cells

```r
# In Jupyter: Cell > Run All
# Or press: Shift + Enter repeatedly
```

**Time:** 2-9 hours depending on hardware

### Option 2: Run One Period at a Time

Edit Cell 13 to run just one period:

```r
# Run only original period
period_names <- c("original")  # Comment out others
method_names <- c("RSF", "CatBoost", "AORSF")
```

**Time:** ~40 min - 3 hours per period

### Option 3: Run One Method at a Time

```r
# Run only RSF
period_names <- c("original", "full", "full_no_covid")
method_names <- c("RSF")  # Comment out others
```

**Time:** ~20 min - 1.5 hours per method

---

## ⚡ Quick Start & Debug Mode (Consolidated)

For a higher-level “how do I actually run this, today?” view, the notebook works together with:

- `README_ready_to_run.md` – end-to-end commands for EC2 (script and notebook) with expected timelines.
- Debug mode: Set `DEBUG_MODE <- TRUE` in Cell 3 to run small, fast test jobs before committing to large MC‑CV runs.

### Quick Start (from `README_ready_to_run.md`, adapted to current notebook)

- **Development runs (100 splits, ~1–2 hours on 32-core EC2):**
  - In Cell 3 of the notebook, keep `n_mc_splits <- 100` and `n_workers <- 30`.
  - Run all cells; monitor `outputs/` for new `*_top20.csv` files.
- **Replication runs (1000 splits, longer):**

```r
# Cell 3 – change only for full replication
n_mc_splits <- 1000   # publication-quality run
n_workers   <- 30     # use 30 of 32 cores on EC2
```

Use tmux/screen or Jupyter-on-EC2 as outlined in `README_ready_to_run.md` if you expect multi-hour runtimes.

### Debug Mode

To smoke-test the full pipeline in 2–5 minutes:

```r
# In Cell 3 of the notebook
DEBUG_MODE  <- TRUE    # enables small, fast config
# Internally:
#  - n_mc_splits <- 5
#  - period_names <- "original"
#  - n_trees_rsf / n_trees_aorsf reduced
```

Use **Debug Mode** when:

- First setting up on a new machine/instance,
- After changing code or configuration,
- You want to confirm packages, data loading, and parallelization all work end-to-end.

Switch back to full analysis by setting `DEBUG_MODE <- FALSE` and restoring `n_mc_splits` to 100 (dev) or 1000 (replication).

---

## ⚙️ Configuration

### Cell 3: Main Configuration

```r
n_predictors <- 20     # Top 20 features
n_trees_rsf <- 500     # RSF trees
n_trees_aorsf <- 100   # AORSF trees
horizon <- 1           # 1-year prediction
n_mc_splits <- 500     # MC-CV splits ← CHANGE THIS
train_prop <- 0.75     # 75% training, 25% testing

# Parallel workers
n_workers <- max(1, parallel::detectCores() - 1)  ← CHANGE THIS
```

### Recommended Settings

| Scenario | n_mc_splits | n_workers | Time |
|----------|-------------|-----------|------|
| **Quick test** | 25 | 2 | 15-30 min |
| **Standard** | 100 | 4-8 | 45-90 min |
| **Full (recommended)** | 500 | 8-16 | 2-4 hours |
| **Publication quality** | 1000 | 16-32 | 4-8 hours |

---

## 📊 Expected Output

### Console Output

```
=== Running MC-CV for RSF (original) ===
Splits: 500 | Train: 75% | Test: 25%
[Progress bar: 100%]
Successful splits: 485 / 500

--- Results for RSF (original) ---
Time-Dependent C-Index: 0.7456 ± 0.0234 (95% CI: 0.7010 - 0.7902)
Time-Independent C-Index: 0.7589 ± 0.0198 (95% CI: 0.7201 - 0.7977)
Top 5 features: cpbypass, dlist, prim_dx, txecmo, sec_dx
```

### Output Files

Created in `graft-loss/feature_importance/outputs/`:

```
original_rsf_top20.csv
original_catboost_top20.csv
original_aorsf_top20.csv
full_rsf_top20.csv
full_catboost_top20.csv
full_aorsf_top20.csv
full_no_covid_rsf_top20.csv
full_no_covid_catboost_top20.csv
full_no_covid_aorsf_top20.csv
cindex_comparison_mc_cv.csv
summary_statistics_mc_cv.csv
```

### Visualization Files

Created in `graft-loss/feature_importance/outputs/plots/`:

```
feature_importance_heatmap.png          # Feature importance by cohort and algorithm (scaled by C-index)
cindex_heatmap.png                      # Concordance index by cohort and algorithm
scaled_feature_importance_bar_chart.png # Bar chart of scaled feature importance (top 20 features)
cindex_table.csv                        # Concordance index table with confidence intervals
```

**Note:** Feature importance values in the heatmap are normalized within each method-period combination, then scaled by algorithm performance:
- **Best C-index algorithm:** ×3 scaling factor
- **Second best C-index algorithm:** ×2 scaling factor  
- **Third algorithm:** ×1 (no scaling)

The scaled bar chart aggregates scaled importance values across all periods and algorithms to show the top 20 most important features overall.

---

## 🐛 Troubleshooting

### Issue: Kernel crashes / Out of memory

**Solution:**
```r
# Cell 3: Reduce splits and workers
n_mc_splits <- 100  # Instead of 500
n_workers <- 2      # Instead of detectCores() - 1
```

### Issue: Package not found

**Solution:**
```r
# Install missing packages
install.packages(c("rsample", "furrr", "future", "progressr"))
install.packages("aorsf")
install.packages("catboost")
```

### Issue: Progress bar not showing

**Expected** - progress bar requires interactive session. In batch mode, it shows percentage updates.

### Issue: Some splits fail

**Normal** - as long as >400/500 splits succeed, results are valid. Failed splits are automatically excluded.

### Issue: Very slow

**Solutions:**
1. Increase `n_workers` (more parallel processing)
2. Reduce `n_mc_splits` (fewer splits)
3. Run one period at a time
4. Run on HPC/cloud instance

---

## 📈 Interpreting Results

### Cell 15: C-Index Comparison Table

```r
# period    method   cindex_td_mean  cindex_td_sd  cindex_ti_mean  cindex_ti_sd
# original  RSF      0.7456          0.0234        0.7589          0.0198
# original  CatBoost 0.8234          0.0187        0.8312          0.0165
# original  AORSF    0.7623          0.0213        0.7734          0.0189
```

**Interpretation:**
- **Mean:** Average C-index across 500 splits
- **SD:** Standard deviation (lower = more stable)
- **CI:** 95% confidence interval for true C-index
- **Overlapping CIs:** Models not significantly different
- **Non-overlapping CIs:** One model significantly better

### Good C-Index Values

| Range | Interpretation |
|-------|----------------|
| 0.50-0.60 | Poor |
| 0.60-0.70 | Fair |
| 0.70-0.75 | Acceptable |
| 0.75-0.80 | Good |
| 0.80-0.85 | Excellent |
| 0.85-0.90 | Outstanding |
| >0.95 | Suspicious (likely overfitting) |

---

## 🔄 Comparing with Old Results

### Old Notebook (Training Data Leakage)

```r
# From graft_loss_feature_importance_20.ipynb
RSF C-index:    0.9987  ← Unrealistic!
AORSF C-index:  0.9961  ← Unrealistic!
CatBoost:       0.8703  ← More realistic
```

### New Notebook (MC-CV)

```r
# From graft_loss_feature_importance_20_MC_CV.ipynb
RSF C-index:    0.75 ± 0.02 (95% CI: 0.71-0.79)  ← Realistic!
AORSF C-index:  0.76 ± 0.02 (95% CI: 0.72-0.80)  ← Realistic!
CatBoost:       0.82 ± 0.02 (95% CI: 0.78-0.86)  ← Consistent!
```

**Key Differences:**
- ✅ Lower C-indexes (MORE trustworthy)
- ✅ Confidence intervals provided
- ✅ Values comparable to published literature
- ✅ Proper validation on unseen data

---

## 💡 Tips for Best Results

### 1. Start Small, Scale Up

```r
# First run: Test with 25 splits
n_mc_splits <- 25
# If successful, increase to 500
n_mc_splits <- 500
```

### 2. Save Intermediate Results

After each period completes, results are automatically saved. If notebook crashes, you can restart from the next period.

### 3. Monitor Resources

```r
# Check memory usage
gc()

# Check parallel workers
future::nbrOfWorkers()
```

### 4. Run Overnight

For full analysis (500 splits, all periods), run overnight or over lunch break.

### 5. Use HPC if Available

```bash
# Submit as batch job on SLURM
sbatch --mem=32G --cpus-per-task=16 run_notebook.sh
```

---

## 📚 Additional Resources

### Related Files
- **R Script version:** `replicate_20_features_MC_CV.R`
- **Usage guide:** See `README_ready_to_run.md` and `README_mc_cv_parallel_ec2.md`
- **Technical details:** See `README_original_vs_updated_study.md`

### Key Concepts
- **Monte Carlo Cross-Validation:** Randomly split data many times
- **Stratification:** Maintain outcome distribution in splits
- **Parallel Processing:** Run splits simultaneously for speed
- **Confidence Intervals:** Uncertainty quantification for C-index

### References
- Original study: Wisotzkey et al. (2023) Pediatric Transplantation
- MC-CV methodology: Molinaro et al. (2005) Bioinformatics
- Original repository: https://github.com/bcjaeger/graft-loss

---

## ✅ Checklist Before Running

- [ ] R kernel installed in Jupyter
- [ ] All packages installed (rsample, furrr, future, etc.)
- [ ] Data file available (phts_txpl_ml.sas7bdat)
- [ ] Sufficient memory (recommend 16+ GB)
- [ ] Sufficient time allocated (2-9 hours)
- [ ] Output directory writable
- [ ] Parallel processing configured

---

## 🎯 Quick Start (TL;DR)

1. **Open notebook:** `graft_loss_feature_importance_20_MC_CV.ipynb`
2. **Run Cell 1-3:** Setup and configuration
3. **Optional:** Reduce `n_mc_splits` to 25 for quick test
4. **Run All Cells:** Cell > Run All
5. **Wait:** 2-9 hours (or 15 min for quick test)
6. **Check outputs:** `outputs/` directory
7. **Review results:** Cell 15-16 show summary tables

**Expected Result:** C-indexes of 0.70-0.85 with 95% confidence intervals, based on proper validation.

---

**Status:** Ready to use  
**Recommended for:** Production analysis, publication-quality results  
**Advantage over old notebook:** Proper validation, realistic C-indexes, confidence intervals

