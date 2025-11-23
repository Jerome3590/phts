## Validation, Concordance Index, Variable Mapping, and Target Leakage

This document ties together three closely related pieces of the updated workflow:

- **C-index / validation implementation** (how we compute performance robustly),
- **Wisotzkey variable mapping** (how study variables map to dataset columns),
- **Target leakage prevention** (which variables are excluded and why).

---

### 1. Concordance Index and Validation

The updated `calculate_cindex()` implementation in the notebook and supporting tests:

- Tries robust, package-based approaches (e.g., `riskRegression::Score`) when possible.
- Falls back to safer methods when package-level issues occur.
- Guards against NA results and keeps the MC-CV pipeline running even if one scoring method fails.

Conceptually:

- **Time-independent C-index (Harrell’s)** is computed by pairwise comparison of event times and risk scores.
- **Time-dependent C-index** is derived via `riskRegression::Score` when available, falling back to the time-independent estimate if needed.
- For MC-CV:
  - C-index is computed on the **test** portion for each split.
  - We then aggregate mean, SD, and 95% CI across all successful splits.

For detailed implementation notes and test harnesses, see `README_concordance_index.md`.

---

### 2. Wisotzkey Variable Mapping

The Wisotzkey et al. study defines a set of clinically important variables. Our pipeline:

- Maps these study variables to **cleaned column names** after `janitor::clean_names()`.
- Handles **multiple source names** and **derived variables**.

Key points from `README_wisotzkey_variable_mapping.md`:

- Most variables map directly, e.g.:
  - `PRIM_DX` → `prim_dx` (primary etiology),
  - `CHD_SV` → `chd_sv` (single ventricle CHD).
- Note: `TXPL_YEAR` → `txpl_year` is excluded from modeling (see exclusion rationale below).
- Several variables are **derived or re-coded**:
  - `tx_mcsd` is created from `txnomcsd` or `txmcsd` (MCSD at transplant) with inverted logic.
  - `pra_listing` is derived from `lsfprat` / `lsfprab`.
  - `bmi_txpl`, `egfr_tx`, and `listing_year` are computed from weight/height/creatinine and ages.
- The pipeline uses a small **alias table** so that if, for example, `pra_listing` is missing but `lsfprat` or `lsfprab` exist, the correct variable is still constructed.

This ensures:

- Consistent feature naming across notebooks, scripts, and cohorts.
- Direct comparability to the original Wisotzkey feature set.

For full tables and code snippets, see `README_wisotzkey_variable_mapping.md`.

---

### 3. Target Leakage Prevention

To prevent inflated performance, we explicitly **exclude** variables that:

- Encode post-event or post-transplant outcomes,
- Depend on information that would not be available at prediction time,
- Are clearly autopsy/pathology or complication descriptors.

From `README_target_leakage.md`, the exclusion strategy in `prepare_modeling_data()`:

- Drops specific leakage variables (e.g., `graft_loss`, `txgloss`, `int_dead`, `dpricaus`, `age_death`, `dlist` (Death: Listed/relisted), many post-mortem and donor complication fields).
- Drops non-predictive temporal/administrative variables:
  - `txpl_year` (transplant year): This is an administrative/temporal variable that reflects when the transplant occurred, not a clinical predictor. Including it can lead to:
    - **Overfitting to era effects**: Models may learn spurious associations with specific years rather than true clinical predictors
    - **Poor generalizability**: Models trained on specific time periods may not generalize to future transplants
    - **Confounding**: Year effects are better handled through proper cohort stratification (e.g., Original vs Full periods) rather than as a feature
    - **Non-clinical relevance**: Transplant year is not a modifiable clinical factor that would inform patient care decisions
- Drops entire **prefix families**:
  - `dtx_` (donor/transplant post-event),
  - `cc_` (complication categories),
  - `dcon`, `dpri`, `dsec`, `dmaj` (donor complications),
  - `sd` (SD-derived variables known to be leakage-prone).

Effect on models:

- Removes many obviously informational but invalid predictors (especially for RSF/AORSF).
- Brings C-index values down from unrealistic ~0.99 to the realistic 0.70–0.85 range.
- Aligns top features more closely with Wisotzkey’s clinically plausible variables.

For exact exclusion lists and rationale, see `README_target_leakage.md`.

---

### 4. How These Pieces Work Together

- **Variable mapping** guarantees that we are modeling on the correct, clinically-interpretable covariates.
- **Target leakage prevention** guarantees that those covariates are restricted to information available at prediction time.
- **Robust C-index / validation** guarantees that performance metrics are computed on truly unseen data and remain stable across many MC-CV splits.

Together, they form the backbone of a **trustworthy, replication-grade analysis**:

- Correct variables in,
- Leaky variables out,
- Performance estimated fairly.


