# Target Leakage Prevention

## Overview

This document describes the target leakage prevention strategy implemented in the feature importance analysis. Target leakage occurs when variables contain information that would not be available at prediction time, artificially inflating model performance.

## Summary

We exclude post-event and post-transplant variables that contain information about outcomes, complications, or events that occur after the prediction time point. This ensures that models only use information available at the time of transplant prediction.

## Excluded Variables

### 1. Identifiers
- `ptid_e`: Patient identifier

### 2. Outcome/Event Variables (Post-Event)
- `int_dead`, `int_death`: Death interval (post-event)
- `graft_loss`, `txgloss`: Graft loss indicator (outcome variable)
- `death`, `event`: Generic outcome indicators

### 3. Donor/Transplant Post-Event Variables
**All variables starting with `dtx_*`:**
- `dtx_patient`: Donor transplant patient status (post-event)
- Other `dtx_*` variables as applicable

**Rationale**: These variables describe donor/transplant status after the event occurs.

### 4. Cause of Death Variables (Post-Event)
- `dpricaus`: Primary cause of death (post-event, leaks outcome information)
- `deathspc`: Death specific cause (post-event)
- `concod`: Cause of death (post-event)

**Rationale**: These variables describe the cause of death, which is only known after the event occurs.

### 5. Age at Death Variables (Post-Event)
- `age_death`: Age at death (post-event, leaks outcome information)

**Rationale**: This variable is calculated at the time of death, which is post-event.

### 6. Patient Support/Status Variables (Post-Event)
- `patsupp`: Death: VAD/ECMO (post-event)
- `pmorexam`: Death: Post Mortem Exam (post-event)
- `papooth`: Death: Cardiac pathology: Other (post-event)
- `pacuref`: Death: Cardiac pathology: Acute rejection (post-event)
- `pishltgr`: Death: ACR grading (post-event)

**Rationale**: These variables describe post-mortem findings or post-event status, not available at prediction time.

### 7. Death: Cardiac Pathology Variables (Post-Event - Autopsy/Post-Mortem Findings)
- `pathero`: Death: Cardiac pathology: Graftatherosclerosis (post-event)
- `pcadrec`: Death: Cardiac pathology: CAD, recent infarction (post-event)
- `pcadrem`: Death: Cardiac pathology: CAD, remote infarction (post-event)
- `pdiffib`: Death: Cardiac pathology: Diffuse fibrosis, no acute rej (post-event)

**Rationale**: These variables describe cardiac pathology findings from autopsy/post-mortem examination, which are only available after death. They are determined at autopsy and would not be available at prediction time.

### 8. Pathology Variables (Post-Event)
- `cpathneg`: Death: Cardiac pathology: No cardiac pathology found (post-event)

**Rationale**: This variable describes post-mortem pathology findings, only available after death.

### 9. Donor Complication Variables (Post-Transplant)
**Exact variable names:**
- `dcardiac`: Donor cardiac complication (post-transplant)
- `dneuro`: Donor neurological complication (post-transplant)
- `dreject`: Donor rejection (post-transplant)
- `dsecaccs`: Donor secondary access (post-transplant)
- `dpriaccs`: Donor primary access (post-transplant)
- `dconmbld`: Donor complication major bleeding (post-transplant)
- `dconmal`: Donor complication malignancy (post-transplant)
- `dconcard`: Donor complication cardiac (post-transplant)
- `dconneur`: Donor complication neurological (post-transplant)
- `dconrej`: Donor complication rejection (post-transplant)
- `dmajbld`: Donor major bleeding (post-transplant)
- `dmalcanc`: Donor malignancy/cancer (post-transplant)

**Variables starting with prefixes:**
- `dcon*`: All donor complication variables (post-transplant)
- `dpri*`: All donor primary variables (post-transplant)
- `dsec*`: All donor secondary variables (post-transplant)
- `dmaj*`: All donor major variables (post-transplant)

**Rationale**: These variables describe complications that occur after transplant.

### 10. Complication Categories (Post-Event)
**All variables starting with `cc_*`:**
- `cc_other`: Complication category other
- `cc_ren`: Complication category renal
- `cc_infct`: Complication category infection
- `cc_fdws`: Complication category failure to thrive
- `cc_rej`: Complication category rejection
- `cc_card`: Complication category cardiac
- `cc_rspfl`: Complication category respiratory failure
- `cc_mjbld`: Complication category major bleeding

**Rationale**: Complication categories are typically recorded post-event.

### 11. SD Variables (Post-Event)
**All variables starting with `sd*`:**
- `sdprathr`: SD variable (post-event)
- `sdprag10`: SD variable (post-event)
- `sdinods`: SD variable (post-event)

**Rationale**: These variables are excluded in `survival_helpers.R` (see line 308: `drop_starts_with = c("sd")`).

## Implementation

The exclusion logic is implemented in `prepare_modeling_data()` function in `scripts/R/replicate_20_features_MC_CV.R`:

```r
# Exact variable names to exclude
exclude_exact <- c(
  "ptid_e",  # Patient ID
  # Outcome/leakage variables
  "int_dead", "int_death", "graft_loss", "txgloss", "death", "event",
  # Cause of death variables
  "dpricaus", "deathspc", "concod",
  # Age at death
  "age_death",
    # Patient support/status (post-event)
    "patsupp", "pmorexam", "papooth", "pacuref", "pishltgr",
    # Death: Cardiac pathology (post-event - autopsy/post-mortem findings)
    "pathero", "pcadrec", "pcadrem", "pdiffib",
    # Pathology (post-event)
    "cpathneg",
  # Donor complications
  "dcardiac", "dneuro", "dreject", "dsecaccs", "dpriaccs",
  "dconmbld", "dconmal", "dconcard", "dconneur", "dconrej",
  "dmajbld", "dmalcanc"
)

# Variable prefixes to exclude
exclude_prefixes <- c(
  "dtx_",   # Donor/transplant post-event
  "cc_",    # Complication categories
  "dcon",   # Donor complications
  "dpri",   # Donor primary
  "dsec",   # Donor secondary
  "dmaj",   # Donor major
  "sd"      # SD variables
)

# Collect all variables matching prefixes
exclude_by_prefix <- character(0)
for (prefix in exclude_prefixes) {
  exclude_by_prefix <- c(exclude_by_prefix, 
                         names(data)[startsWith(names(data), prefix)])
}

# Combine all exclusions
exclude_all <- unique(c(exclude_exact, exclude_by_prefix))
```

## Impact on Current Results

### Before Exclusion

Looking at the current top 20 features (from previous runs with leakage):

**RSF Top Features** (with leakage):
- Rank 1: `dtx_patient` ❌ (excluded)
- Rank 2: `dpricaus` ❌ (excluded)
- Rank 3: `age_death` ❌ (excluded)
- Rank 4: `patsupp` ❌ (excluded)
- Rank 5: `pmorexam` ❌ (excluded)
- Rank 6: `deathspc` ❌ (excluded)
- Rank 7: `sdprag10` ❌ (excluded - sd prefix)
- Rank 8: `cc_other` ❌ (excluded - cc_ prefix)
- Rank 9: `dcardiac` ❌ (excluded)
- Rank 10: `cc_ren` ❌ (excluded - cc_ prefix)
- Rank 11: `concod` ❌ (excluded)
- Rank 13: `papooth` ❌ (excluded)
- Rank 15: `cpathneg` ❌ (excluded)
- Rank 18: `dreject` ❌ (excluded)
- Rank 19: `dconmbld` ❌ (excluded)
- Rank 20: `pacuref` ❌ (excluded)

**AORSF Top Features** (with leakage):
- Rank 1: `dtx_patient` ❌ (excluded)
- Rank 2: `dpricaus` ❌ (excluded)
- Rank 3: `dcardiac` ❌ (excluded)
- Rank 4: `dneuro` ❌ (excluded)
- Rank 5: `dconneur` ❌ (excluded)
- Rank 6: `dreject` ❌ (excluded)
- Rank 7: `dconmbld` ❌ (excluded)
- Rank 8: `dconmal` ❌ (excluded)
- Rank 9: `patsupp` ❌ (excluded)
- Rank 10: `pishltgr` ❌ (excluded)
- Rank 11: `dsecaccs` ❌ (excluded)
- Rank 12: `deathspc` ❌ (excluded)
- Rank 13: `dpriaccs` ❌ (excluded)
- Rank 14: `pmorexam` ❌ (excluded)
- Rank 15: `sdprathr` ❌ (excluded - sd prefix)
- Rank 16: `dconcard` ❌ (excluded)
- Rank 17: `cc_other` ❌ (excluded - cc_ prefix)
- Rank 18: `dconrej` ❌ (excluded)
- Rank 19: `dmajbld` ❌ (excluded)
- Rank 20: `sdinods` ❌ (excluded - sd prefix)

**CatBoost Top Features** (with leakage):
- Rank 3: `age_death` ❌ (excluded)
- Most other features appear to be pre-transplant (e.g., `txpl_year`, `age_txpl`, `bmi_txpl`)

### Expected Impact After Exclusion

1. **RSF/AORSF**: Will lose many top-ranked features (likely 10-18 out of top 20)
2. **C-index**: Should drop significantly from current suspiciously high values (~0.998) to more realistic levels (similar to CatBoost's 0.88-0.90 range)
3. **Feature Consistency**: Should improve consistency between methods
4. **Wisotzkey Identification**: Should work better once leakage variables are removed

## Verification Checklist

After running the updated script, verify:

1. ✅ **Exclusion Logging**: Check console output for messages like:
   ```
   Excluding X leakage variables:
     Exact matches: Y variables
     Prefix matches: Z variables
       dtx_*: A variables (e.g., dtx_patient, ...)
       cc_*: B variables (e.g., cc_other, cc_ren, ...)
       ...
   ```

2. ✅ **No Leakage Variables in Top Features**: Verify that:
   - No `cc_*`, `dcon*`, `dpri*`, `dsec*`, `dmaj*`, `sd*` variables in top features
   - No `patsupp`, `pmorexam`, `deathspc`, `concod`, `papooth`, `cpathneg`, `pacuref`, `pishltgr` in top features
   - No `dtx_*`, `dpricaus`, `age_death` in top features

3. ✅ **C-index Values**: C-indexes should be:
   - More realistic (not near 1.0)
   - Consistent across methods (RSF, CatBoost, AORSF)
   - Similar to CatBoost's baseline (0.88-0.90 range)

4. ✅ **Feature Name Consistency**: Feature names should be consistent across RSF, CatBoost, and AORSF

5. ✅ **Wisotzkey Identification**: RSF and AORSF should now successfully identify Wisotzkey variables in their top 20 features

## Related Files

- **Implementation**: `scripts/R/replicate_20_features_MC_CV.R` (function `prepare_modeling_data()`)
- **Reference**: `scripts/R/survival_helpers.R` (function `get_survival_leakage_keywords()`)
- **Notebook**: `graft-loss/feature_importance/graft_loss_feature_importance_20.ipynb` (Cell 7 - needs manual update)

## Notes

- `prim_dx` (primary etiology/diagnosis) is **NOT** excluded - this is a pre-transplant variable and is valid for prediction
- The exclusion logic uses `startsWith()` to catch all variables with problematic prefixes, ensuring comprehensive coverage
- All excluded variables are logged to console for transparency
- The exclusion strategy matches the leakage prevention approach used in `survival_helpers.R` and other cohort analysis scripts

## Rationale

### Why These Variables Cause Data Leakage

1. **Post-Event Variables**: Variables like `dpricaus`, `age_death`, `deathspc` describe events that occur after the outcome, allowing the model to "see into the future"

2. **Post-Transplant Complications**: Variables describing donor complications (`dcardiac`, `dneuro`, `dreject`, etc.) occur after transplant and may be correlated with outcomes

3. **Complication Categories**: `cc_*` variables categorize complications that occur post-event

4. **Unclear Timing**: Variables like `patsupp`, `pmorexam` have unclear timing and may contain post-event information

### Impact on Model Performance

Using these variables artificially inflates model performance because:
- They contain direct or indirect information about the outcome
- They would not be available at prediction time in a real-world scenario
- They create a false sense of model accuracy

By excluding these variables, we ensure that:
- Models only use information available at the time of transplant
- Performance metrics reflect realistic predictive ability
- Results are generalizable to real-world prediction scenarios
