## Original vs Updated Study Comparison

This document summarizes how our current implementation relates to:

- The **original bcjaeger/graft-loss study** and repository, and

---

### 1. Original Study (bcjaeger/graft-loss)

From inspection of the original plan:

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

In short: the original study used proper external validation via MC‑CV with Cox, XGBoost, and AORSF.

**Original algorithms used (explicit):**

- **Cox proportional hazards** (standard survival regression / baseline comparator)
- **XGBoost** (gradient-boosted trees, applied in a survival/predictive setting)
- **RSF (Random Survival Forest)** and variants **ORSF / AORSF** (random/oblique/adaptive survival forests used for comparison)



### 2. Updated MC‑CV Replication (This Work)

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

### Modifications: XGBoost → CatBoost and Dual Concordance Testing

We replaced the original study's use of **XGBoost** with **CatBoost** in our replication for the following practical reasons:

- **Categorical handling:** CatBoost natively handles categorical features without manual one-hot encoding, which reduces leakage risk and preprocessing complexity.
- **Robustness / determinism:** CatBoost provides more deterministic behavior across runs and environments (less sensitive to default seed/hyperparameter differences), which helps reproducible MC‑CV runs.
- **Performance for tabular data:** In our experiments CatBoost produced competitive or better predictive performance on the tabular PHTS data and integrates well with our parallel/EC2 runs.
- **Practical integration:** CatBoost's R bindings and `catboost` binary options (CPU/GPU) made it straightforward to swap into existing training loops that previously called `xgboost`-based pipelines.

Where we applied this change:

- Notebooks: `graft-loss/feature_importance/graft_loss_feature_importance.ipynb` (and the MC‑CV notebook `graft_loss_feature_importance_20_MC_CV.ipynb`) now fit **CatBoost** models instead of XGBoost in the per-split fitting step.
- Scripts: replication scripts that previously invoked XGBoost were updated to call the CatBoost training/evaluation helpers.

Dual concordance-index testing (why and what we changed):

- We added a robust, multi-fallback concordance-index routine to ensure consistent scoring across environments. The routine attempts in order:
  1. `survival::concordance()` (Harrell-style),
  2. `survival::survConcordance()`,
  3. `riskRegression::Score()` (if available and applicable),
  4. A sampled pure‑R Harrell pairwise estimator (final fallback, max sample = 2000) to avoid O(n^2) blowup.
- Tests and artifacts:
  - `graft-loss/feature_importance/test_calculate_cindex.R` — full test exercising the multi-method implementation (may invoke compiled package code paths).
  - `graft-loss/feature_importance/test_calculate_cindex_safe.R` — safe test that runs only the pure‑R sampled Harrell fallback (no compiled packages required).
  - `graft-loss/feature_importance/README_concordance_index.md` — notes explaining the concordance-index logic, observed behavior (including the segmentation fault observed in one execution when compiled package calls crashed in the runner), and recommended remediation (rebuild/reinstall compiled packages in the execution environment).

Practical effect: the pipeline now consistently reports a concordance estimate even when compiled package calls (e.g., `riskRegression::Score`) fail, and the training pipeline uses CatBoost as the tree‑based learner instead of XGBoost.

### Final feature importance: normalization and scaling by best model

The final feature-importance score used in our reporting is computed by combining per-model importance vectors across MC‑CV splits and scaling them by relative model performance so that better models contribute proportionally more to the final ranking. The high-level recipe we implemented is:

- Per split and per model:
  - Extract raw feature importance (model-provided importance or permutation importance as implemented for each learner).
  - Force non-negative values (replace negative importances with 0) and normalize the vector to unit-sum: imp_norm = imp_raw / sum(imp_raw) (if sum is zero, fall back to uniform weights).
  - Compute model performance weights:
  - For each model, compute its mean held-out C-index across MC‑CV splits (model_mean_cindex).
  - Identify the best-performing model (best_model_mean_cindex = max(model_mean_cindex)).
  - Compute a relative model weight: rel_weight_model = (model_mean_cindex / best_model_mean_cindex) * N_models (so the best model is scaled to have weight equal to the number of models for that period).
- Scale and aggregate:
  - For each split, scale that model's `imp_norm` by `rel_weight_model` to get `imp_scaled`.
  - Sum the `imp_scaled` vectors across models to produce a split-level aggregated importance vector `imp_split`.
  - Aggregate `imp_split` across MC‑CV splits (mean or median recommended) to produce `imp_aggregate`.
  - Final normalization: `imp_final = imp_aggregate / sum(imp_aggregate)` to yield a unit-sum final importance vector.

Pseudo-code (conceptual):

```r
for each split in MC_CV:
  for each model in models:
    imp_raw = extract_importance(model, split)
    imp_raw[imp_raw < 0] = 0
    imp_norm = imp_raw / sum(imp_raw)  # if sum==0 -> uniform
    rel_w = (model_mean_cindex[model] / best_model_mean_cindex) * N_models
    imp_scaled = imp_norm * rel_w
  imp_split = sum_over_models(imp_scaled)
imp_aggregate = mean_over_splits(imp_split)
imp_final = imp_aggregate / sum(imp_aggregate)
```

Notes and implementation choices:

- We normalize per-model importances to unit-sum so that feature contributions are comparable across heterogeneous importance metrics (e.g., CatBoost gain vs RSF permutation).
- Scaling by relative model performance (C-index) emphasizes features from models that actually predict well on held-out data; we use the mean C-index across splits for stability.
- Aggregation across splits uses the mean by default; if importance distributions are skewed we recommend the median as a robust alternative.
- After `imp_final` is produced we often present the top-N features (e.g., top‑20) and optionally threshold or smooth small weights for visualization.

## Interpretation: what the scaled bar chart represents

- The final scaled bar chart (`scaled_feature_importance_bar_chart.png`) shows a single aggregated score per feature computed by summing each feature's per-model, per-period importance after two transformations:
  1. per-model importance vectors are forced non-negative and normalized to unit-sum (so different importance metrics are comparable), and
  2. each normalized vector is scaled by the model's relative performance weight (rel_weight = model_mean_cindex / best_model_mean_cindex, scaled so the best model ≈ N_models).
- The plotted value for each feature is therefore the sum across all cohort × algorithm cells of (normalized_importance × rel_weight). Higher bars indicate a feature that consistently contributed important signal across models and periods, especially in better-performing models. This is an additive, across-model measure (not a max or simple average).
- Use this chart to identify features that receive broad, weighted support from multiple algorithms and cohorts. If you want a different aggregation (e.g., max or mean), update `create_visualizations.R` accordingly — the code uses `sum(...)` by default.

Files / helpers involved:

- Notebooks: `graft-loss/feature_importance/graft_loss_feature_importance.ipynb`, `graft_loss_feature_importance_20_MC_CV.ipynb`.
- Replication script: `replicate_20_features_MC_CV.R` (per-split fitting and scoring).
- Importance helpers: model-specific importance extractors (CatBoost importance, RSF/ranger importance, permutation routines in notebooks/scripts).


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

**Bottom line:** The updated MC‑CV workflow is methodologically aligned with the original bcjaeger/graft-loss study and adds more visibility to target leakage and concordance risk calculation.


