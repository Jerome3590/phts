## Original vs Updated Study Comparison

This document summarizes how our current implementation relates to:

- The **original bcjaeger/graft-loss study** and repository, and
- Our **earlier (flawed) replication script** that evaluated on training data.

It is adapted from the comparison section that previously lived in `REPLICATION_STUDY_1000_SPLITS.md`.

---

### 1. Original Study (bcjaeger/graft-loss)

From `ORIGINAL_REPO_VALIDATION_METHODOLOGY.md` and inspection of the original plan:

- **Validation design:**
  - Monte Carlo Cross-Validation with **500–1000** train/test splits.
  - **75/25** train/test ratio, stratified by outcome (`status`).
  - Models trained on the **train** portion only, evaluated on **held-out test** data.
- **Workflow:**
  - Managed via the `drake` package (dependency graph + caching).
  - MC-CV splits generated with `rsample::mc_cv()`.
  - Model fitting and scoring performed per split, with results aggregated across splits.
- **Reported performance:**
  - RSF / ORSF / AORSF C-index typically in the **0.72–0.76** range.
  - Confidence intervals derived from the distribution of C-index across splits.

In short: the original study already used **proper external validation** via MC‑CV.

---

### 2. Previous Replication Script (Training-Data Evaluation)

The earlier `replicate_20_features.R` script (now replaced by `replicate_20_features_MC_CV.R` and the notebook) deviated from the original design:

- **Validation flaw:**
  - No train/test split; models were fitted and evaluated on the **same full dataset**.
  - No resampling (single evaluation only).
  - No stratification by outcome.
- **Consequence:**
  - Time-dependent C-index for RSF/AORSF inflated to ~0.99 because the models were scored on their training data.
  - CatBoost appeared more realistic (~0.87), likely due to its internal regularization / ordered boosting.

This is the core problem documented in `ORIGINAL_REPO_VALIDATION_METHODOLOGY.md` and `README_mc_cv_update.md`: the previous script produced **over-optimistic** C-indexes that are not comparable to the original study.

---

### 3. Updated MC‑CV Replication (This Work)

The current notebook (`graft_loss_feature_importance_20_MC_CV.ipynb`) and script (`replicate_20_features_MC_CV.R`):

- **Restore the original design:**
  - Use `rsample::mc_cv()` with 75/25 train/test splits and outcome stratification.
  - For each split:
    - Fit RSF / CatBoost / AORSF on the **training** set.
    - Compute C-index on the **held-out test** set.
  - Aggregate mean, SD, and 95% CI across all successful splits.
- **Extend it:**
  - Allow configurable splits (100–1000) with 100‑split runs for development, 1000‑split runs for final replication.
  - Add robust C-index computation and leakage prevention.
  - Add parallel processing and EC2-optimized configuration.

---

### 4. Side‑by‑Side Summary

| Aspect                    | Original Study (bcjaeger)        | Old Script (`replicate_20_features.R`) | Updated MC‑CV Replication (this work)       |
|---------------------------|-----------------------------------|-----------------------------------------|---------------------------------------------|
| Resampling method         | MC‑CV with 500–1000 splits       | None                                    | MC‑CV with 100–1000 splits                  |
| Train/test split          | 75% train / 25% test             | None (100% train = 100% test)           | 75% train / 25% test                        |
| Stratification            | By outcome (`status`)            | N/A                                     | By outcome (`status`)                       |
| Evaluation data           | Held‑out test data               | Training data                           | Held‑out test data                          |
| C-index range (RSF/AORSF) | ~0.72–0.76 (realistic)           | ~0.99 (overfitting)                     | ~0.72–0.80 (realistic)                      |
| Confidence intervals      | Yes (via MC‑CV distribution)     | No                                      | Yes (via MC‑CV distribution)                |
| Implementation            | Drake + Slurm + MC‑CV pipeline   | Single monolithic R script              | Notebook + MC‑CV script + parallel EC2 run  |

**Bottom line:** the updated MC‑CV workflow is methodologically aligned with the original bcjaeger/graft-loss study and corrects the validation and leakage issues present in the older replication script.


