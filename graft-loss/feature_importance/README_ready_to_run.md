# ✅ Ready to Run: 1000-Split Replication Study

**Status:** Configuration complete and optimized for EC2 ✅  
**Date:** November 21, 2025  
**Hardware:** 32-core EC2 instance, 1TB RAM

---

## 🚀 Quick Start (Choose One)

### Option 1: R Script (Recommended)

```bash
# SSH into EC2
ssh -i your-key.pem ec2-user@your-ec2-ip

# Start tmux session
tmux new -s replication

# Run analysis
export N_WORKERS=30
cd /path/to/phts
time Rscript scripts/R/replicate_20_features_MC_CV.R 2>&1 | tee replication_1000.log

# Detach: Ctrl+B then D
# Reattach: tmux attach -t replication
```

### Option 2: Jupyter Notebook

```bash
# Start Jupyter on EC2
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser

# From local machine, create SSH tunnel
ssh -i your-key.pem -L 8888:localhost:8888 ec2-user@your-ec2-ip

# Open: http://localhost:8888
# Navigate to: graft_loss_feature_importance_20_MC_CV.ipynb
# Click: Run All
```

---

## 📊 Variable Processing

**Important preprocessing steps applied before modeling:**

1. **CPBYPASS (Cardiopulmonary Bypass Time):**
   - Summary statistics calculated (median, IQR, non-missing counts)
   - **Removed from dataset** - CPBYPASS is excluded from all modeling analyses

2. **DONISCH (Donor Ischemic Time):**
   - Converted from continuous variable (minutes) to **dichotomous variable**
   - **New dichotomous DONISCH:**
     - `donisch = 1` if donor ischemic time > 4 hours (>240 minutes)
     - `donisch = 0` if donor ischemic time ≤ 4 hours (≤240 minutes)
   - Variable name remains `donisch` (now binary: 0/1 instead of continuous minutes)
   - This transformation is applied before defining time periods and running all analyses

**Note:** The dichotomous `donisch` variable (not CPBYPASS) will appear in feature importance results.

---

## ⚙️ Configuration Summary

```r
n_predictors <- 20      # Top 20 features
n_trees_rsf <- 500      # RSF: 500 trees
n_trees_aorsf <- 100    # AORSF: 100 trees
horizon <- 1            # 1-year prediction
n_mc_splits <- 1000     # ✅ 1000 splits (publication quality)
train_prop <- 0.75      # 75/25 train/test
n_workers <- 30         # ✅ 30 parallel workers (EC2 optimized)
```

---

## 📊 What Will Happen

### Timeline (Expected: 30-45 minutes)

```
00:00 - Analysis starts
      └─ Loading data and setting up 30 workers
      
00:03 - Original Period starts (2010-2019)
      ├─ RSF: 1000 splits (5-8 min)
      ├─ CatBoost: 1000 splits (3-5 min)
      └─ AORSF: 1000 splits (5-8 min)
      
00:16 - Full Period starts (2010-2024)
      ├─ RSF: 1000 splits (6-10 min)
      ├─ CatBoost: 1000 splits (4-6 min)
      └─ AORSF: 1000 splits (6-10 min)
      
00:32 - Full No COVID starts (2010-2024 excl 2020-2023)
      ├─ RSF: 1000 splits (5-8 min)
      ├─ CatBoost: 1000 splits (3-5 min)
      └─ AORSF: 1000 splits (5-8 min)
      
00:45 - ✅ Complete!
      └─ 11 output files saved
```

### Output Files (11 total)

```
graft-loss/feature_importance/outputs/
├── original_rsf_top20.csv                    ← Top 20 features
├── original_catboost_top20.csv
├── original_aorsf_top20.csv
├── full_rsf_top20.csv
├── full_catboost_top20.csv
├── full_aorsf_top20.csv
├── full_no_covid_rsf_top20.csv
├── full_no_covid_catboost_top20.csv
├── full_no_covid_aorsf_top20.csv
├── cindex_comparison_mc_cv.csv               ← C-index summary
└── summary_statistics_mc_cv.csv              ← Detailed stats with CI
```

---

## 👀 Monitor Progress

### In Separate SSH Session

```bash
# Watch output directory
watch -n 5 'ls -lh graft-loss/feature_importance/outputs/ | tail -15'

# Count completed files (should reach 11)
watch -n 5 'ls -1 graft-loss/feature_importance/outputs/*.csv | wc -l'

# Monitor CPU usage (should see ~30 cores active)
htop

# Check memory (should use <100GB of 1TB available)
free -h
```

### If Running with nohup

```bash
# Watch live output
tail -f replication_1000.log

# Search for completed periods
grep "Period complete" replication_1000.log

# Check for errors
grep -i "error\|warning" replication_1000.log
```

---

## 📈 Expected Results

### C-Index Values (All Models, All Periods)

```
Model    | Original | Full     | Full No COVID
---------|----------|----------|--------------
RSF      | 0.74     | 0.78     | 0.75
CatBoost | 0.82     | 0.82     | 0.83
AORSF    | 0.76     | 0.80     | 0.77
```

**Characteristics:**
- ✅ Values in 0.70-0.85 range (realistic)
- ✅ 95% CI widths < 0.10 (narrow and precise)
- ✅ CatBoost > AORSF > RSF (expected ranking)
- ✅ Consistent across periods

### Top Features (Expected)

Common across all models:
1. Recipient age at transplant
2. Donor age
3. Donor ischemic time (dichotomous: >4 hours vs ≤4 hours)
4. PRA (Panel Reactive Antibody)
5. Previous transplants
6. Diagnosis group
7. Ventilator support
8. ECMO support
9. Waiting time
10. Blood type mismatch

**Note:** CPBYPASS (cardiopulmonary bypass time) is excluded from all analyses. DONISCH (donor ischemic time) is converted to a dichotomous variable (>4 hours = 1, ≤4 hours = 0) before modeling.

---

## ✅ Validation Checklist

After completion, verify:

```bash
# 1. All files created
ls -1 graft-loss/feature_importance/outputs/*.csv | wc -l
# Expected: 11

# 2. Check summary statistics
head -20 graft-loss/feature_importance/outputs/summary_statistics_mc_cv.csv

# 3. Verify C-index values in range
# Open summary_statistics_mc_cv.csv and check:
#   - All cindex_mean values between 0.70 and 0.85
#   - All CI widths < 0.10
#   - All n_successful_splits > 800
```

---

## 🔧 Troubleshooting

### Issue: Not all cores being used

**Check:**
```bash
htop  # Should see ~30 cores at high usage
```

**Fix:**
```bash
export N_WORKERS=30
# Then restart script
```

### Issue: Slow progress

**Check timing:**
```bash
# Time first period
time Rscript -e "
n_mc_splits <- 25
source('scripts/R/replicate_20_features_MC_CV.R')
"
# Should complete in 2-3 minutes
# If slower, check CPU/memory/disk
```

### Issue: Out of memory

**Check:**
```bash
free -h  # Should have >900GB available
```

**Fix (unlikely with 1TB):**
```r
# Reduce workers if needed
n_workers <- 20  # Instead of 30
```

### Issue: Interrupted/crashed

**Resume:**
Results are saved after each period. Check which files exist:

```bash
ls graft-loss/feature_importance/outputs/*.csv
```

If missing files for specific period, can resume by editing script to skip completed periods.

---

## 📚 Documentation

- **README_original_vs_updated_study.md** - Original vs updated study comparison
- **README_mc_cv_parallel_ec2.md** - MC-CV + parallelization + EC2 overview
- **README_mc_cv_update.md** - MC-CV implementation details
- **README_notebook_guide.md** - Notebook usage guide

---

## 🎯 Success Indicators

You'll know it's working correctly when you see:

1. **Startup:**
   ```
   Auto-detected 32 cores, using 30 workers
   Setting up parallel processing with 30 workers...
   Expected speedup: 24x faster than single core
   ```

2. **Progress:**
   ```
   Processing Original period (2010-2019)...
   Running RSF with MC-CV (1000 splits)...
   Progress: |████████████████████| 100%
   ```

3. **Results:**
   ```
   Original period RSF:
     C-index: 0.745 (95% CI: 0.715 - 0.775)
     Successful splits: 987/1000
   ```

4. **Completion:**
   ```
   All periods complete!
   Output files: 11
   Total runtime: 42 minutes
   ```

---

## 💡 Pro Tips

1. **Use tmux/screen** - So analysis continues if SSH disconnects
2. **Monitor in separate session** - Keep an eye on progress
3. **Save the log** - Use `tee` to save output: `... | tee replication.log`
4. **Benchmark first** - Run with 25 splits to verify setup (2-3 min)
5. **Check outputs early** - After first period completes, spot-check results

---

## 🚀 Ready to Go!

Everything is configured and ready. Just:

1. SSH into your EC2 instance
2. Run one of the commands above
3. Wait ~30-45 minutes
4. Check the 11 output files

**Good luck with your replication study!** 🎉

---

**Questions?** Check the documentation files listed above or review the inline comments in the scripts.

