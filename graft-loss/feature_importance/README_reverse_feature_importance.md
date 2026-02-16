# Reverse Feature Importance

We call this **Reverse** Feature Importance: instead of “which features drive the model’s prediction?”, we ask “which features drive *errors*?”—support and Intervention Rate (IR) over false positives, false negatives, and correct predictions.

**You can start from model predictions.** The pipeline only needs (1) predictions and (2) true labels to define error subsets (FP/FN/correct). Per-instance explanations (which features to use for support/IR) can then come from SHAP (e.g. top-k per instance), FFA rules, or any other explainer.

**Implementation alignment:** In the calculator SHAP/FFA workflow, Reverse FI uses the **same feature set and order** as the forward causal results: features that have rule firings on the test set, ordered by causal responsibility (rule frequency × SHAP importance). So `missed_predictions_drivers.json`, `missed_predictions_feature_profile.csv`, and the dashboard’s top causal factors all refer to the same features in a consistent order.

---

## Example: Computing IR for Missed Predictions

This example assumes:

- **Model predictions** (e.g. risk scores or binary $\hat{y}$) and **true labels** $y$ — so you can subset FP, FN, and correct.
- **Per-instance explanations**: the set of influential features for each instance (e.g. from SHAP top-k, AXP, or FFA rule firings).


### 1. Inputs and basic setup

```python
import numpy as np
import pandas as pd
from collections import Counter
from typing import List, Set, Dict
```

Assume you have **predictions** and **labels** (and optionally precomputed explanations):

```python
# y_true: numpy array of shape (n_samples,)
# y_pred: numpy array of shape (n_samples,)  [or risk_scores for survival]
# explanations: list of sets, explanations[i] = set of features for instance i
# feature_names: list of all feature names
#
# If you only have SHAP values (shap_values shape (n_samples, n_features)):
#   explanations = [set(np.array(feature_names)[np.argsort(np.abs(shap_values[i]))[-top_k:]]) for i in range(len(shap_values))]
```

```python
def get_error_masks(y_true: np.ndarray, y_pred: np.ndarray):
    fp_mask = (y_pred == 1) & (y_true == 0)
    fn_mask = (y_pred == 0) & (y_true == 1)
    correct_mask = (y_pred == y_true)
    return fp_mask, fn_mask, correct_mask
```


### 2. Support and IR definitions

For each subset $S$ (e.g., FP or FN), define:

- Support of feature $j$: proportion of instances in $S$ whose explanation includes $j$.
- Intervention Rate (IR) of feature $j$: proportion of instances in $S$ where toggling $j$ (add/remove) changes the explanation.

Here we stub an `intervene_on_feature` function that:

- Returns `True` if the explanation changes when the feature is added/removed.
- In your actual pipeline, this is where you apply the FFA intervention logic.

```python
def compute_support(explanations_subset: List[Set[str]], feature_names: List[str]) -> Dict[str, float]:
    n = len(explanations_subset)
    counts = Counter()
    for exp in explanations_subset:
        for f in exp:
            counts[f] += 1
    support = {f: counts[f] / n for f in feature_names}
    return support


def intervene_on_feature(instance_idx: int,
                         feature: str,
                         mode: str = "remove") -> bool:
    """
    Placeholder for FFA intervention:
    - mode='remove': remove feature from explanation basis, recompute explanation
    - mode='add': add feature to explanation basis, recompute explanation
    Returns True if the explanation changes in a way that crosses your predefined criterion.
    """
    # TODO: integrate with your FFA implementation / AXP engine
    raise NotImplementedError
```

Now compute IR for a given subset and intervention mode:

```python
def compute_ir_for_subset(indices: np.ndarray,
                          feature_names: List[str],
                          mode: str = "remove") -> Dict[str, float]:
    """
    indices: array of instance indices in S (e.g., FP or FN)
    mode: 'remove' for IR_-  or 'add' for IR_+
    """
    n = len(indices)
    counts = Counter({f: 0 for f in feature_names})

    for idx in indices:
        for f in feature_names:
            changed = intervene_on_feature(idx, f, mode=mode)
            if changed:
                counts[f] += 1

    ir = {f: counts[f] / n for f in feature_names}
    return ir
```


### 3. Putting it together for FP/FN vs Correct

```python
fp_mask, fn_mask, correct_mask = get_error_masks(y_true, y_pred)

fp_idx = np.where(fp_mask)[0]
fn_idx = np.where(fn_mask)[0]
correct_idx = np.where(correct_mask)[0]

# IR_- for FP (removal influence, hallucination risk)
ir_fp_remove = compute_ir_for_subset(fp_idx, feature_names, mode="remove")

# IR_+ for FN (addition influence, missing-signal risk)
ir_fn_add = compute_ir_for_subset(fn_idx, feature_names, mode="add")

# Optionally compute IR for correct predictions (for contrast)
ir_correct_remove = compute_ir_for_subset(correct_idx, feature_names, mode="remove")
ir_correct_add = compute_ir_for_subset(correct_idx, feature_names, mode="add")
```


### 4. Aggregation into a Feature Causal Profile DataFrame

```python
def build_feature_profile(feature_names: List[str],
                          ir_fp_remove: Dict[str, float],
                          ir_fn_add: Dict[str, float],
                          ir_correct_remove: Dict[str, float],
                          ir_correct_add: Dict[str, float]) -> pd.DataFrame:
    rows = []
    for f in feature_names:
        rows.append({
            "feature": f,
            "IR_-_FP": ir_fp_remove.get(f, 0.0),       # hallucination for positive errors
            "IR_+_FN": ir_fn_add.get(f, 0.0),          # missing-signal for negative errors
            "IR_-_Correct": ir_correct_remove.get(f, 0.0),
            "IR_+_Correct": ir_correct_add.get(f, 0.0)
        })
    df = pd.DataFrame(rows)
    return df

feature_profile = build_feature_profile(
    feature_names,
    ir_fp_remove,
    ir_fn_add,
    ir_correct_remove,
    ir_correct_add
)
```

From here you can:

- Sort by `IR_-_FP` or `IR_+_FN` to identify **dominant error drivers**.
- Plot side-by-side bars or line plots per feature for:
    - Correct vs FP (for IR\_-)
    - Correct vs FN (for IR\_+)


### 5. Adding simple confidence intervals (binomial)

If you treat each intervention outcome for feature $j$ as a Bernoulli trial (“changed explanation” vs “no change”), then for feature $j$:

- $\hat{p}_j = \text{IR}(j)$
- $n_j$ = number of trials (instances where you tested that feature in the subset)

A simple large-sample 95% CI:

$$
\hat{p}_j \pm 1.96 \sqrt{\frac{\hat{p}_j(1 - \hat{p}_j)}{n_j}}
$$

You could implement:

```python
from math import sqrt

def add_binomial_ci(ir: Dict[str, float], n: int, z: float = 1.96):
    ci_lower, ci_upper = {}, {}
    for f, p in ir.items():
        se = sqrt(p * (1 - p) / n)
        ci_lower[f] = max(0.0, p - z * se)
        ci_upper[f] = min(1.0, p + z * se)
    return ci_lower, ci_upper
```

Then attach these to your `feature_profile` for downstream filtering (e.g., only treating features as credible “error drivers” if their CIs do not overlap between Missed vs Correct).

If you share your current FFA/AXP implementation details (library, data structures), I can adapt this into concrete, drop-in code tailored to your stack.
<span style="display:none">[^1][^10][^11][^12][^13][^14][^15][^2][^3][^4][^5][^6][^7][^8][^9]</span>

<div align="center">⁂</div>

[^1]: https://pmc.ncbi.nlm.nih.gov/articles/PMC12366998/

[^2]: https://www.pnas.org/doi/10.1073/pnas.2213880120

[^3]: https://www.sciencedirect.com/science/article/pii/S0167876024000904

[^4]: https://www.osti.gov/servlets/purl/2422445

[^5]: https://pmc.ncbi.nlm.nih.gov/articles/PMC4099271/

[^6]: https://dspace.mit.edu/bitstream/handle/1721.1/35804/6-035Fall-2002/NR/rdonlyres/Electrical-Engineering-and-Computer-Science/6-035Computer-Language-EngineeringFall2002/2B101C4D-5218-41F8-8D09-0C7C2DB4798B/0/12-IR.pdf

[^7]: https://pmc.ncbi.nlm.nih.gov/articles/PMC6630113/

[^8]: https://www.imf.org/-/media/files/publications/wp/2025/english/wpiea2025109-print-pdf.pdf

[^9]: https://dl.acm.org/doi/pdf/10.1145/967900.968060

[^10]: https://www.youtube.com/watch?v=ftYdEm6pEkE

[^11]: https://pure.mpg.de/rest/items/item_3371244_5/component/file_3502318/content

[^12]: https://www.reddit.com/r/pathofexile/comments/l7xv38/add_influence_to_item/

[^13]: https://www.sigmaactuary.com/2016/07/25/understanding-confidence-intervals/

[^14]: https://www.wipo.int/edocs/mdocs/pct/en/pct_tco_vi/pct_tco_vi_9.pdf

[^15]: https://www.sciencedirect.com/science/article/pii/S1836955324000869

