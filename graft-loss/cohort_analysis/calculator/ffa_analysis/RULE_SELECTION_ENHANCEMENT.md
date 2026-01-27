# Rule Selection Enhancement: Capturing Rules SHAP Might Miss

## Problem Statement

SHAP-based rule filtering is excellent for identifying globally important rules, but it may miss:

1. **Rare but important rules**: Rules that appear infrequently but are critical for specific cases
2. **Context-dependent rules**: Rules important only in certain combinations or subgroups
3. **Coverage gaps**: Rules that cover different parts of the feature space but have lower SHAP scores
4. **Low-frequency high-impact rules**: Rules with low global frequency but high predictive power when they do match

## Current Strategy (Before Enhancement)

Our rule selection uses a **3-set union approach**:

1. **First 100 rules** - Common patterns (frequency-based, but only first 100)
2. **Random 100 rules** - Diversity (random sampling)
3. **SHAP-filtered rules** - Top 300 OR 10th percentile (importance-based)
   - Also ensures all features with SHAP > 0 are represented

**Limitation**: This may miss rare rules that are important for specific subgroups.

## Enhancement: Additional Selection Strategies

We've added two new methods to complement SHAP-based filtering:

### 1. Frequency-Based Filtering (`_filter_rules_by_frequency_impact`)

**Purpose**: Capture rare but potentially important rules that SHAP might miss.

**Strategy**:
- Identify rules with **low frequency** (rare rules)
- Include rules that match at least `min_frequency` instances (default: 1)
- Select top-K rarest rules (default: 50)
- These rules might be important for specific patient subgroups

**When to use**: 
- In `explain_dataset()` where we have multiple instances
- When we want to ensure rare but important patterns are captured

**Example**:
```python
# Compute rule frequencies across dataset
rule_frequencies = explainer._compute_rule_frequency(
    rule_ids=matched_rules,
    X_sample=X_test,
    predictions=y_pred,
    target_class=1
)

# Get rare rules (low frequency but still match some instances)
rare_rules = explainer._filter_rules_by_frequency_impact(
    rule_ids=matched_rules,
    rule_frequencies=rule_frequencies,
    min_frequency=1,  # Must match at least 1 instance
    top_k_rare=50      # Top 50 rarest rules
)
```

### 2. Coverage-Diversity Filtering (`_filter_rules_by_coverage_diversity`)

**Purpose**: Ensure rules cover different parts of the feature space, not just the same instances.

**Strategy**:
- Greedy selection: Pick rules that cover the most **uncovered instances**
- Maximizes instance coverage diversity
- Prevents all selected rules from matching the same instances

**When to use**:
- In `explain_dataset()` to ensure diverse coverage
- When we want to avoid redundant rules (all matching same instances)

**Example**:
```python
# Get diverse rules that cover different instances
diverse_rules = explainer._filter_rules_by_coverage_diversity(
    rule_ids=matched_rules,
    X_sample=X_test,
    predictions=y_pred,
    target_class=1,
    max_rules=50  # Maximum diverse rules to return
)
```

## Enhanced Rule Selection Strategy

### Updated 5-Set Union Approach

When we have instance data (in `explain_dataset`), we can now use:

1. **First 100 rules** - Common patterns
2. **Random 100 rules** - Diversity
3. **SHAP-filtered rules** - Top 300 OR 10th percentile (importance-based)
4. **Rare rules** - Top 50 rarest rules (frequency-based) ⭐ NEW
5. **Coverage-diverse rules** - Top 50 rules maximizing instance coverage ⭐ NEW

**Union of all 5 sets** = Comprehensive rule coverage

## Implementation Status

### ✅ Completed

- Added `_compute_rule_frequency()` method
- Added `_filter_rules_by_frequency_impact()` method
- Added `_filter_rules_by_coverage_diversity()` method
- **Integrated into `explain_dataset()`** - Precomputes rare and diverse rules for each class
- **Updated `_compute_axp()`** - Uses precomputed rare and diverse rules when available
- Added configuration options: `enable_rare_rules`, `enable_diverse_rules`, `max_rare_rules`, `max_diverse_rules`

### How It Works

1. **Precomputation Phase** (in `explain_dataset()`):
   - For each class (0 and 1), compute rule frequencies across all instances
   - Select top-K rarest rules (default: 50)
   - Select top-K most diverse rules by coverage (default: 50)
   - Store in `self._rare_rules_by_class` and `self._diverse_rules_by_class`

2. **Rule Selection Phase** (in `_compute_axp()`):
   - When computing AXP for an instance, check if rare/diverse rules are precomputed
   - Filter precomputed rules to only those that match the current instance
   - Include in the 5-set union: first 100 + random 100 + SHAP-filtered + rare + diverse

3. **Usage**:
```python
# Default: Both rare and diverse rules enabled
df_explanations = explainer.explain_dataset(
    X=X_test,
    predictions=y_pred,
    enable_rare_rules=True,      # Include rare rules
    enable_diverse_rules=True,   # Include diverse rules
    max_rare_rules=50,           # Max rare rules per class
    max_diverse_rules=50         # Max diverse rules per class
)

# Disable if needed (for faster execution)
df_explanations = explainer.explain_dataset(
    X=X_test,
    predictions=y_pred,
    enable_rare_rules=False,     # Skip rare rule computation
    enable_diverse_rules=False   # Skip diverse rule computation
)
```

## Benefits

1. **Comprehensive Coverage**: Captures both common and rare patterns
2. **Subgroup-Specific Rules**: Identifies rules important for specific patient subgroups
3. **Diverse Explanations**: Ensures explanations cover different parts of feature space
4. **Complementary to SHAP**: SHAP finds globally important rules; frequency/diversity finds locally important rules

## Trade-offs

- **Computation Cost**: Frequency and coverage computation requires iterating through instances
- **Rule Count**: May increase total rule count (but still bounded by max limits)
- **Performance**: Additional filtering steps add overhead, but bounded by max_rules limits

## Recommendations

1. **Use in `explain_dataset()`**: Where we have multiple instances to compute frequencies
2. **Keep limits conservative**: Top 50 rare + top 50 diverse = manageable overhead
3. **Monitor rule counts**: Ensure total rules stay within ~300-500 range for AXP computation
4. **Validate results**: Compare explanations with/without rare/diverse rules to ensure they add value

## Next Steps

1. Integrate frequency-based and coverage-diversity filtering into `explain_dataset()`
2. Add configuration options to enable/disable these strategies
3. Add logging to track how many rare/diverse rules are selected
4. Validate that rare rules actually improve explanation quality
