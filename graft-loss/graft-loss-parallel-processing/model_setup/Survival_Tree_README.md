# Survival Trees & Ensemble Methods (Reference Guide)

This README provides an in-depth reference for the survival tree methods used in the graft loss pipeline: Random Survival Forest (RSF), Oblique Random Survival Forest (ORSF), Gradient-Boosted Survival Trees (XGBoost survival), and CatBoost (survival adaptation). It covers core concepts, splitting criteria, importance calculations, ensemble aggregation, and practical considerations.

---

## 1. Core Concepts of Survival Trees

Survival trees extend decision trees to right-censored time-to-event data.

Key differences from regression/classification trees:

- Target: (time, status) pairs instead of a single scalar or class.
- Censoring: Observations that have not experienced the event at last follow-up contribute partial information.
- Node prediction: Each terminal node estimates a survival function S(t) or cumulative hazard H(t).
- Split criteria: Must reflect separation of survival experiences (e.g., log-rank statistic) rather than impurity (Gini/variance).

Typical prediction workflows:

1. Grow many trees (each provides node-specific survival curves or risk estimates).
2. Aggregate (average cumulative hazards or survival curves) across trees.
3. For performance metrics (e.g., C-index at horizon t*), use risk scores derived from predicted survival / hazard summaries.

---

## 2. Generic Survival Tree Growth (Axis-Aligned)

At a node containing data D:

1. Candidate variables: Random subset (size mtry) or all features.
2. For each candidate variable X:
   - Enumerate candidate split points (e.g., midpoints between sorted unique values for numeric X; partitions for factors).
   - For each split X < c, partition D → (D_L, D_R).
   - Compute a survival heterogeneity statistic (e.g., log-rank test comparing Kaplan–Meier curves of D_L vs D_R).
3. Select the split with maximal statistic (or maximal decrease in node risk measure).
4. Recurse until stopping conditions:
   - Node size < min.node.size
   - No allowable split improves criterion
   - All outcomes identical or only one event time remains
5. Estimate node-level survival (KM or Nelson–Aalen based) and store it.

Axis-aligned means: each decision tests a single feature threshold (X_j < c).

---

## 3. Random Survival Forest (RSF)

RSF aggregates many axis-aligned survival trees grown on bootstrap samples.

Characteristics:

- Bootstrap sampling: Each tree sees a bootstrapped dataset; out-of-bag (OOB) rows serve for internal validation.
- Random feature subset at each split (mtry) → decorrelation.
- Splitting statistic: Log-rank test (most common) or alternatives (log-score, conservation-of-events).
- Node prediction: Cumulative hazard or survival curve; ensemble prediction = average cumulative hazard across trees.

Out-of-bag evaluation:

- For each observation, aggregate predictions only from trees where it was OOB → unbiased performance estimates (C-index, Brier score surrogate if implemented).

Permutation importance:

1. Record baseline OOB C-index.
2. Permute a feature’s values across OOB samples.
3. Recompute C-index with permuted data.
4. Importance = drop in performance.

Pros:

- Strong performance without heavy tuning.
- Naturally handles non-linearity and interactions.
- Produces full survival curves.

Cons:

- Axis-aligned splits may require deeper trees for complex boundaries.
- Permutation importance can dilute importance among correlated predictors.

---

## 4. Oblique Random Survival Forest (ORSF)

ORSF generalizes RSF by allowing oblique (linear combination) splits rather than single-feature thresholds.

Split form: w^T x < c

Key modifications:

- Candidate hyperplanes built from subsets of variables (e.g., through projection search or score-based filtering).
- A survival separation criterion (log-rank or partial likelihood proxy) evaluated on projected values.
- Potentially fewer levels needed to separate complex clusters.

Benefits:

- Captures linear interactions at split time → shallower trees.
- Can improve discrimination for datasets where outcomes vary along combined feature directions.

Trade-offs:

- More computation per split evaluation.
- Harder interpretability (coefficients vs single-threshold rules).

Interpretation hint:

- Each oblique split defines a linear score; examining top coefficients can reveal contributing predictors.

---

## 5. Gradient-Boosted Survival Trees (XGBoost - Cox Objective)

Instead of bagging, XGBoost builds trees sequentially to minimize a differentiable loss (e.g., Cox partial negative log-likelihood).

Iteration m:

1. Compute gradients (g_i) and Hessians (h_i) of loss wrt current prediction f_{m-1}(x_i).
2. Grow a tree by choosing splits that maximize gain:
   Gain = (G_L^2 / (H_L + λ) + G_R^2 / (H_R + λ) - G_T^2 / (H_T + λ)) - γ
   - G_* = sum of gradients in node
   - H_* = sum of Hessians
   - λ = L2 regularization; γ = node (complexity) penalty
3. Add scaled tree: f_m(x) = f_{m-1}(x) + η * tree_m(x)

Risk score = final f_M(x). Higher risk implies shorter survival.

Survival curve (if needed) can be constructed via Breslow estimator using aggregated partial likelihood contributions, though many pipelines rely solely on risk ordering for C-index.

Pros:

- Strong predictive performance.
- Regularization (shrinkage, depth, subsampling) controls overfit.

Cons:

- Produces relative risk, not direct survival curve (extra step required).
- Interpretability lower without post-hoc methods (SHAP, gain charts).

---

## 6. CatBoost Survival Adaptation

CatBoost natively supports ordered boosting for categorical robustness. For survival (when not using a built-in survival objective), a common adaptation is to transform the outcome:

- Signed-time encoding (used in pipeline): positive times for events, negative for censored → model learns ranking signal.

Core elements:

- Oblivious (symmetric) trees: same split feature & threshold across all nodes at a given depth.
- Ordered target statistics for categorical encoding (avoid target leakage).
- Gradient boosting loop similar to XGBoost but with symmetric trees and CatBoost-specific loss/priors.

Importance:

- Based on total loss reduction contributions across splits.

Pros:

- Excellent categorical handling (especially high-cardinality with missing or rare levels).
- Symmetric trees can regularize and speed prediction.

Cons:

- Surrogate outcome transformation may not produce calibrated survival probabilities directly.
- Requires external calibration if absolute risk curves needed.

---

## 7. Survival Splitting Criteria Overview

| Criterion | Used In | Concept | Notes |
|----------|---------|--------|-------|
| Log-rank statistic | RSF / ORSF | Maximizes survival curve separation | Non-parametric; robust; ignores covariate interactions unless oblique |
| Partial likelihood gain | XGBoost (Cox) | Improves Cox partial log-likelihood | Differentiable; enables second-order optimization |
| Loss reduction (custom surrogate) | CatBoost (adapted) | Boosting objective decrease | Depends on transformation; calibration post-step needed |
| Pseudo log-likelihood / variants | ORSF (possible) | Alternative scoring for hyperplanes | Implementation-specific |

---

## 8. Importance Methods Compared

| Method | Models | Mechanism | Pros | Cons |
|--------|--------|-----------|------|------|
| Permutation drop in C-index | RSF, ORSF, (XGB optional) | Shuffle feature, measure performance loss | Model-agnostic, interaction-aware | Correlated feature masking; computational cost |
| Split gain (XGBoost) | XGBoost | Sum of gains where feature used | Fast, inherent | Inflated by many small splits; scale-dependent |
| Loss reduction (CatBoost) | CatBoost | Aggregate loss contribution | Native, consistent | Harder to compare cross-model |
| Union normalization (RSF+CatBoost) | Pipeline post-process | Min–max per model then average | Harmonizes disparate scales | Assumes comparable signal quality |

---

## 9. Pseudocode Snippets

### 9.1 Axis-Aligned Survival Tree Node Split

```text
function grow_node(data D):
  if stopping(D): return leaf(D)
  best_stat = -Inf; best_split = NULL
  for v in candidate_variables(D):
    for c in candidate_thresholds(D, v):
      (D_L, D_R) = partition(D, v < c)
      if invalid(D_L, D_R): continue
      stat = logrank_statistic(D_L, D_R)
      if stat > best_stat:
        best_stat = stat; best_split = (v, c)
  if best_split is NULL: return leaf(D)
  return node(best_split, 
              left = grow_node(D_L), 
              right = grow_node(D_R))
```

### 9.2 Oblique Split Selection (Conceptual)

```text
function best_oblique_split(D):
  vars_subset = sample_variables(D)
  candidate_dirs = generate_linear_combinations(vars_subset)
  best = None; best_stat = -Inf
  for w in candidate_dirs:
    z = project(D.X, w)  # scalar scores
    for c in candidate_thresholds(z):
      (D_L, D_R) = partition_on_projection(D, z < c)
      stat = survival_separation(D_L, D_R) # log-rank or similar
      if stat > best_stat:
        best_stat = stat; best = (w, c)
  return best
```

### 9.3 Gradient Boost (Cox)

```text
initialize f(x) = 0
for m in 1..M:
  compute gradients g_i and Hessians h_i for all i
  tree_m = fit_tree_using_gain(g, h)
  f(x) = f(x) + eta * tree_m(x)
return f
```

---

## 10. Ensemble Aggregation

| Model | Aggregation | Output Type | Notes |
|-------|-------------|-------------|-------|
| RSF | Mean cumulative hazard across trees | Survival curve / risk | May back-transform to survival: S(t)=exp(-H(t)) |
| ORSF | Same as RSF | Survival curve / risk | Oblique splits alter partition shapes only |
| XGBoost | Sum of tree leaf scores | Log-risk (linear predictor) | Convert to relative risk: exp(score) |
| CatBoost | Sum of symmetric tree leaf scores | Risk score | Interpretation monotonic with hazard |

---

## 11. Calibration & Risk Translation

If absolute survival probabilities are required from boosting models:

1. Estimate baseline cumulative hazard H0(t) using Breslow with risk scores.
2. Individual hazard: H_i(t) = H0(t) * exp(score_i).
3. Survival: S_i(t) = exp(-H_i(t)).

For CatBoost with signed-time surrogate, an additional mapping (e.g., isotonic regression on predicted risk vs observed KM at landmark times) can approximate calibration.

---

## 12. Practical Guidelines

| Scenario | Recommendation |
|----------|----------------|
| Many categorical predictors | Prefer CatBoost (retain native encoding) + ORSF for complementary view |
| Strong linear interactions suspected | ORSF likely to reduce tree depth |
| Need speed + solid baseline | RSF (ranger) first, then layer others |
| Strict ranking metric focus (C-index) | Boosted Cox (XGBoost) often excels |
| Communicating to clinicians | Use RSF permutation importance & partial dependence for transparency |

---

## 13. Common Pitfalls & Mitigations

| Pitfall | Effect | Mitigation |
|---------|-------|------------|
| Correlated predictors reduce permutation importance | Underestimates true relevance | Grouping / conditional permutation |
| Overfitting boosted trees | Inflated apparent C-index | Use early stopping / shrinkage / depth limits |
| Sparse high-cardinality categories encoded naively | Noise, overfit | CatBoost ordered encoding or target-statistics with restrictions |
| Inconsistent feature spaces across splits | Unstable importance | Use global encoded matrix (as in pipeline) |
| Misinterpreting risk scores as probabilities | Overconfidence | Calibrate or derive baseline hazard |

---

## 14. Mermaid: Method Relationships

```mermaid
graph LR
  A[Survival Data (time,status,X)] --> B[RSF]
  A --> C[ORSF]
  A --> D[XGBoost Cox]
  A --> E[CatBoost (Survival Adaptation)]
  B --> F[Permutation FI]
  C --> F
  D --> G[Gain-based Metrics]
  E --> H[Internal Loss Importance]
  F --> I[Union Normalization]
  H --> I
  G --> I
  I[Consolidated Feature Insight]
```

---

## 15. References & Further Reading

- Ishwaran, H., Kogalur, U., Blackstone, E., Lauer, M. (2008). Random survival forests.
- Breiman, L. (2001). Random forests.
- Cox, D. R. (1972). Regression models and life tables.
- Wright, M. N., Ziegler, A. (2017). Ranger: A fast implementation of random forests.
- CatBoost Documentation (Yandex): Ordered boosting & categorical handling.
- Friedman, J. H. (2001). Greedy function approximation (gradient boosting).

---

## 16. Extension Ideas

- Add SHAP-based global importance for boosted models.
- Implement conditional permutation importance to address correlated predictors.
- Add calibration layer (e.g., isotonic regression) for boosted risk scores.
- Explore time-dependent AUC and dynamic C-index metrics.

---

> End of base Survival Tree Reference section


## 17. Mapping: "Fit Trees" vs "Growing Trees" in Our Pipeline

The phrases appear in logs/comments conceptually—here is how they map to concrete operations:

| Conceptual Term | Meaning | Where It Happens (Scripts / Functions) | Granularity | Output Artifacts |
|-----------------|---------|----------------------------------------|-------------|------------------|
| Growing Trees (Construction) | Building individual tree structures via recursive splitting (bagging, oblique search, boosting) | `R/fit_rsf.R` (RSF); `R/fit_orsf.R` (ORSF); internal loops inside `fit_xgb.R` (boost iterations); CatBoost Python script (`scripts/py/catboost_survival.py`) | Per-tree / per-boosting-iteration | In-memory model objects; intermediate split statistics |
| Fitting Trees (Model Assembly) | Orchestrating data prep, feature selection, hyper-parameter driven training calls, and persisting models | `scripts/04_fit_model.R` orchestrator; `fit_final_orsf.R` for final export; `make_final_features.R` preceding variable selection | Per model family / per resample split | `data/models/model_*.rds`, CatBoost `.cbm`, MC metrics CSVs |
| Feature Selection Phase | RSF-based permutation feature filtering before model fitting | `R/make_final_features.R` → calls `select_rsf.R` | Pre-model global step | `data/final_features.rds` (terms & variables) |
| Full-Feature Overrides | Bypass selection to expose entire feature space | Environment flags (`ORSF_FULL`, `XGB_FULL`, `CATBOOST_USE_FULL`) parsed in `scripts/04_fit_model.R` | Training session level | Adjusted `model_vars` / encoded variable sets |
| Monte Carlo Split Execution | Repeated (grow + fit) across resamples for performance distribution | Loop inside `run_mc()` in `scripts/04_fit_model.R` | Per split × model | `model_mc_metrics_*.csv`, `model_mc_importance_*.csv` |
| Importance Aggregation | Combine per-split raw importances and normalize | Post-loop segment of `run_mc()` | After all splits | `model_mc_importance_union_rsf_catboost_*.csv` |

Simplified lifecycle:

1. Data & Feature Space: `scripts/03_prep_model_data.R` prepares dual (native + encoded) datasets; `make_final_features.R` selects predictors.
2. Growing: Each call to `fit_orsf()`, `fit_rsf()`, boosting iteration in `fit_xgb()`, or CatBoost's internal symmetric tree builder grows trees.
3. Fitting: `scripts/04_fit_model.R` coordinates which growth procedures run, with which variables, and under which resample indices.
4. Post-Fit Evaluation: C-index computation, permutation FI, union importance, persistence.

Mnemonic: Growing = structural recursion inside an algorithm; Fitting = pipeline-level orchestration and consolidation of grown structures into a deployable model artifact.

---

## 18. Model Evaluation & Selection Methodology

We evaluate competing survival models along multiple consistent dimensions to select a primary model or adjudicate ties.

### 18.1 Performance Metrics

| Metric | Implementation | Where Computed | Notes |
|--------|----------------|----------------|-------|
| Concordance Index (C-index) | `survival::concordance(Surv ~ score)` | Within `run_mc()` loop for each split & model | Primary discrimination metric; higher is better |
| Mean C-index (Monte Carlo) | Mean across splits | `model_mc_summary_*.csv` | Central tendency of performance |
| Split-wise Variability (SD) | Standard deviation across splits | `model_mc_summary_*.csv` | Stability indicator |
| 95% CI (t-based) | Mean ± t * SD/sqrt(n) | `model_mc_summary_*.csv` columns `ci_lower`, `ci_upper` | Overlap used to flag practical equivalence |
| (Optional) OOB C-index | RSF-internal (non-MC single fit) | Single-fit path (if MC off) | Fast approximate when MC_CV=0 |

Future (not yet implemented but compatible): time-dependent AUC, Brier score, calibration curves.

### 18.2 Resampling Design

- Monte Carlo CV with stratified sampling on `status` (see `scripts/02_resampling.R`).
- Each split: approx 75% training, 25% testing (prop = 3/4 default).
- `MC_START_AT`, `MC_MAX_SPLITS` allow partial reruns or continuation.
- Two label scopes if enabled: (a) Full dataset; (b) Original-study temporal window (2010–2019) rebuilt with its own feature selection for historical comparability.

### 18.3 Feature Space Consistency

- RSF-derived selection applied globally before MC to reduce leakage.
- Boosted models (XGB) can operate on a stable encoded matrix (`MC_XGB_USE_GLOBAL=1`) ensuring identical feature layout across splits.
- Full-feature overrides test upper-bound discrimination vs parsimony of selected subset.

### 18.4 Importance Synthesis

1. Raw permutation importance (Δ C-index) per split/model (ORSF, RSF, XGB optional subset).
2. CatBoost internal loss importance per split when enabled.
3. Aggregation: mean & SD per feature/model across splits.
4. Union normalization (RSF + CatBoost): min–max scale each model’s mean importance to [0,1]; average available; rank combined.

Purpose: Mitigate model-specific scaling differences and highlight robust cross-algorithm signals.

### 18.5 Model Selection Heuristic

Primary: Highest mean C-index on full dataset MC summary.

Tie / Practical Equivalence (overlapping 95% CIs within 0.005 absolute difference):

1. Prefer model with lower SD (stability).
2. Prefer model with broader clinically interpretable FI (not dominated by a single synthetic feature).
3. If still tied: defer to clinical interpretability consensus (feature stability and plausibility).

### 18.6 Single-Fit Mode (MC_CV=0)

Used for rapid iteration or preliminary diagnostics:

- Trains one instance each of ORSF, RSF, XGB (and optionally CatBoost).
- Writes `model_comparison_index.csv` for downstream tabulation.
- No resample variance → interpret with caution; escalate to MC mode for final reporting.

### 18.7 Reproducibility Measures

- Seed control embedded in resample generation (`rsample::mc_cv`).
- Session info snapshots saved as `logs/sessionInfo_step04_*.txt`.
- Environment flags recorded implicitly in logs (recommend exporting them explicitly in future enhancement).

### 18.8 Potential Enhancements

| Enhancement | Rationale | Path |
|-------------|-----------|------|
| Add time-dependent AUC | Capture discrimination dynamics over time | Extend evaluation step with `timeROC` or `survAUC` |
| Add Brier score / IBS | Incorporate calibration & accuracy | Compute per split; summarize like C-index |
| Landmark calibration plots | Visual clinical interpretability | Generate after union importance |
| SHAP for boosted models | Local explanation consistency | Integrate Python SHAP on XGB & CatBoost |
| Conditional permutation FI | Reduce correlation masking | Implement grouped or conditional shuffles |

---

End of Survival Tree Reference
