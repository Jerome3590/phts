## MC-CV, Parallelization, and EC2 Overview

**Scope:** How the updated graft-loss workflow combines Monte Carlo cross-validation (MC-CV), robust parallel processing, and an EC2-optimized configuration.  
**Canonical notebook:** `graft_loss_feature_importance_20_MC_CV.ipynb`  
**Canonical script:** `replicate_20_features_MC_CV.R`

---

### 1. Monte Carlo Cross-Validation (MC-CV)

- **Goal:** Replace single-shot, training-data evaluation with repeated, stratified train/test splits that match the original bcjaeger/graft-loss methodology.
- **Key settings (publication-quality run):**

```r
n_predictors <- 20      # Top 20 features
n_trees_rsf  <- 500     # RSF trees
n_trees_aorsf<- 100     # AORSF trees
horizon      <- 1       # 1-year prediction
n_mc_splits  <- 1000    # 1000 MC-CV splits (publication grade)
train_prop   <- 0.75    # 75% training, 25% testing
```

- **Behaviour:**
  - Uses `rsample::mc_cv()` to create `n_mc_splits` stratified 75/25 train/test splits.
  - Trains models on the **training** portion only.
  - Evaluates C-index on the **held-out test** portion.
  - Aggregates mean, SD, and 95% CI across all successful splits.

For full methodological details, see `README_original_vs_updated_study.md`.

---

### 2. Parallelization with `furrr` / `future`

- **Goal:** Run many MC-CV splits in parallel while keeping workers stable and memory-safe on a 32‑core EC2 instance.
- **Core pattern inside the notebook/script:**

```r
plan(multisession, workers = n_workers)

with_progress({
  p <- progressor(steps = n_mc_splits)

  results <- future_map(
    split_ids,
    function(split_id) {
      p()
      # 1) Extract train/test data from mc_splits
      # 2) Fit RSF / CatBoost / AORSF on train
      # 3) Predict on test
      # 4) Compute C-index on test
    },
    .options = furrr_options(
      seed     = TRUE,
      packages = c(
        "dplyr", "purrr", "tibble", "rsample",
        "ranger", "aorsf", "catboost",
        "riskRegression", "prodlim"
      )
    )
  )
})

plan(sequential)
```

- **Key fixes :**
  - `options(future.globals.maxSize = 20 * 1024^3)` to allow sending the large `mc_splits` object to workers (about 11 GB for 1000 splits).
  - Explicit `packages = c(...)` in `furrr_options()` so each worker loads the same modeling and scoring packages.
  - Single‑threaded CatBoost inside each worker (`thread_count = 1`, `logging_level = "Silent"`) to avoid logger thread-safety issues.
  - Streamed logging via `flush.console()` at key milestones so Jupyter and scripts show progress continuously.

These fixes ensure stable parallel processing on EC2 instances with large memory requirements.

---

### 3. EC2-Optimized Configuration (32 cores, 1 TB RAM)

- **Goal:** Use a single, large EC2 instance instead of a Slurm cluster, but retain the original scale (1000 splits, 3 periods, 3 methods).
- **Recommended EC2 settings :**

```r
n_mc_splits <- 1000   # extended / publication-level run
n_workers   <- 30     # use 30 of 32 cores
```

- **Typical runtimes on this hardware (for 1000 splits):**
  - **Quick dev run (100 splits):** ~1–2 hours total.
  - **Full 1000-split replication:** roughly 10–20 hours depending on CatBoost stability and data size.
  - For shorter working sessions, the notebook now defaults to **100 splits**, with 1000 reserved for final replication.

- **Operational recipes:**
  - Use `tmux` or `screen` to keep long runs alive.
  - Monitor progress via:

    ```bash
    watch -n 60 'ls -1 graft-loss/feature_importance/outputs/*.csv 2>/dev/null | wc -l'
    ps aux | grep workRSOCK | grep -v grep | wc -l
    htop
    ```

  - Confirm that the 9 `*_top20.csv` feature files plus the 2 summary CSVs appear in `outputs/`.

See `README_ready_to_run.md` for full EC2 usage examples, including nohup and tmux patterns.

---

### 4. How These Pieces Fit Together

- **MC-CV** defines the statistical design (many stratified train/test splits, proper validation).
- **Parallelization** with `future`/`furrr` makes the MC-CV feasible at scale (hundreds–thousands of splits).
- **EC2 optimization** ensures the parallel MC-CV run finishes in hours rather than days by:
  - Using ~30 workers,
  - Raising `future.globals.maxSize`,
  - Allowing large in‑memory `mc_splits` objects.

If you only read one “infrastructure” document, this one plus `README_original_vs_updated_study.md` give you the big picture; the other READMEs provide deeper technical and operational detail.


