# Wisotzkey Variable Mapping to Original Dataset

## Summary

Found the mapping of Wisotzkey variables to original dataset column names in multiple locations. This document consolidates the mappings and clarifies any discrepancies.

## Primary Mapping Source

**File**: `graft-loss/cohort_analysis/phts_dataset.qmd` (lines 188-204)

```r
wisotzkey_name_map <- c(
  "primary_etiology"               = "prim_dx",
  "mcsd_at_transplant"             = "txmcsd",        # Note: NO underscore in mapping
  "single_ventricle_chd"           = "chd_sv",
  "surgeries_prior_to_listing"     = "hxsurg",
  "serum_albumin_at_transplant"    = "txsa_r",
  "bun_at_transplant"              = "txbun_r",
  "ecmo_at_transplant"             = "txecmo",
  "transplant_year"                = "txpl_year",
  "recipient_weight_at_transplant" = "weight_txpl",
  "alt_at_transplant"              = "txalt",
  "bmi_at_transplant"              = "bmi_txpl",     # computed
  "pra_max_at_listing"             = "lsfprat",      # fallback: use lsfprab if missing
  "egfr_at_transplant"             = "egfr_tx",      # computed from height/creatinine
  "medical_history_at_listing"     = "hxmed",
  "listing_year"                   = "listing_year"  # computed from txpl_year, age_listing, age_txpl
)
```

## Raw SAS to Cleaned Name Mapping

**File**: `graft-loss/graft-loss-parallel-processing/README.md` (lines 192-203)

| Wisotzkey Feature | Raw SAS Name | Cleaned Name | Notes |
|-------------------|--------------|--------------|-------|
| Primary Etiology | `PRIM_DX` | `prim_dx` | After `janitor::clean_names()` |
| MCSD at Transplant | `TXNOMCSD` | `txnomcsd` → `tx_mcsd` | Inverted logic: 'yes' = no support; **WITH underscore** |
| Single Ventricle CHD | `CHD_SV` | `chd_sv` | |
| Surgeries Prior to Listing | `HXSURG` | `hxsurg` | |
| Serum Albumin at Transplant | `TXSA_R` | `txsa_r` | |
| BUN at Transplant | `TXBUN_R` | `txbun_r` | |
| ECMO at Transplant | `TXECMO` | `txecmo` | |
| Transplant Year | `TXPL_YEAR` | `txpl_year` | |
| Recipient Weight at Transplant | `WEIGHT_TXPL` | `weight_txpl` | |
| ALT at Transplant | `TXALT` | `txalt` | Not `txalt_r` |
| BMI at Transplant | — | `bmi_txpl` | Computed (US formula) |
| PRA at Listing | `LSFPRAT` | `lsfprat` → `pra_listing` | T-cell PRA at listing |
| eGFR at Transplant | — | `egfr_tx` | Computed (Schwartz) |
| Medical History at Listing | `HXMED` | `hxmed` | |
| Listing Year | — | `listing_year` | Computed from ages |

## Important Discrepancies and Notes

### 1. MCSD Variable Name (`tx_mcsd` vs `txmcsd`)

**Issue**: The mapping shows `txmcsd` (no underscore), but the code uses `tx_mcsd` (with underscore).

**Resolution**: 
- The raw SAS file has `TX_MCSD` (with underscore)
- After `janitor::clean_names()`, it becomes `tx_mcsd` (with underscore)
- The codebase was updated to use `tx_mcsd` (with underscore) - see `TX_MCSD_COLUMN_NAME_FIX.md`
- **Current code uses**: `tx_mcsd` (with underscore) ✅

**Derivation**:
```r
tx_mcsd = if ('txnomcsd' %in% names(.)) {
  if_else(txnomcsd == 'yes', 0, 1)  # 'yes' = no support, so 0; otherwise 1
} else if ('txmcsd' %in% names(.)) {
  txmcsd
} else {
  NA_real_
}
```

### 2. PRA Variable Name (`pra_listing` vs `lsfprat`)

**Issue**: The mapping shows `lsfprat`, but the code expects `pra_listing`.

**Resolution**:
- Raw SAS has `LSFPRAT` (PRA T-cell at listing)
- After cleaning: `lsfprat`
- Code creates: `pra_listing = lsfprat` (or `lsfprab` as fallback)
- **Current code uses**: `pra_listing` (created from `lsfprat`) ✅

**Derivation**:
```r
if (!"pra_listing" %in% names(out) && "lsfprat" %in% names(out)) {
  out$pra_listing <- out$lsfprat
} else if (!"pra_listing" %in% names(out) && "lsfprab" %in% names(out)) {
  out$pra_listing <- out$lsfprab  # Fallback
}
```

### 3. Computed Variables

Three variables are **computed** (not directly from raw SAS):

1. **`bmi_txpl`**: 
   ```r
   bmi_txpl = (weight_txpl / (height_txpl^2)) * 703  # US formula
   ```

2. **`egfr_tx`**: 
   ```r
   egfr_tx = 0.413 * height_txpl / txcreat_r  # Pediatric Schwartz formula
   ```

3. **`listing_year`**: 
   ```r
   listing_year = floor(txpl_year - (age_txpl - age_listing))
   # Fallback: txpl_year - 1
   ```

## Current Code Implementation

**File**: `graft-loss/feature_importance/replicate_20_features.R` (lines 64-80)

```r
wisotzkey_variables <- c(
  "prim_dx",           # Primary Etiology
  "tx_mcsd",           # MCSD at Transplant (with underscore - derived column!)
  "chd_sv",            # Single Ventricle CHD
  "hxsurg",            # Surgeries Prior to Listing
  "txsa_r",            # Serum Albumin at Transplant
  "txbun_r",           # BUN at Transplant
  "txecmo",            # ECMO at Transplant
  "txpl_year",         # Transplant Year
  "weight_txpl",       # Recipient Weight at Transplant
  "txalt",             # ALT at Transplant (cleaned name, not txalt_r)
  "bmi_txpl",          # BMI at Transplant (created from weight/height)
  "pra_listing",       # PRA at Listing (created from lsfprat) - may be lsfprat in some datasets
  "egfr_tx",           # eGFR at Transplant (created from creatinine)
  "hxmed",             # Medical History at Listing
  "listing_year"       # Listing Year (created from txpl_year)
)
```

## Alternative Name Handling

The code handles alternative names for some variables:

**File**: `graft-loss/feature_importance/replicate_20_features.R` (lines 385-388)

```r
wisotzkey_alternatives <- list(
  "pra_listing" = c("pra_listing", "lsfprat", "lsfprab"),  # PRA at listing
  "tx_mcsd" = c("tx_mcsd", "txmcsd")  # MCSD at transplant
)
```

This allows the code to find Wisotzkey variables even if they're named differently in the dataset.

## Verification Checklist

When checking if Wisotzkey variables are present in the dataset:

1. ✅ **Direct matches**: Check if exact names exist (e.g., `prim_dx`, `chd_sv`, `hxsurg`)
2. ✅ **Alternative names**: Check alternatives for `pra_listing` (`lsfprat`, `lsfprab`) and `tx_mcsd` (`txmcsd`)
3. ✅ **Computed variables**: Verify that `bmi_txpl`, `egfr_tx`, and `listing_year` are created during data loading
4. ✅ **Derived variables**: Verify that `tx_mcsd` is created from `txnomcsd` or `txmcsd`

## Key Files

- **Mapping definition**: `graft-loss/cohort_analysis/phts_dataset.qmd` (lines 188-204)
- **Raw SAS mapping**: `graft-loss/graft-loss-parallel-processing/README.md` (lines 192-203)
- **Current implementation**: `graft-loss/feature_importance/replicate_20_features.R` (lines 64-80)
- **MCSD fix documentation**: `graft-loss/graft-loss-parallel-processing/TX_MCSD_COLUMN_NAME_FIX.md`

## Summary

The Wisotzkey variables map to cleaned column names (after `janitor::clean_names()`) with the following key points:

1. Most variables map directly from raw SAS names (e.g., `PRIM_DX` → `prim_dx`)
2. `tx_mcsd` is derived from `txnomcsd` (inverted logic) or `txmcsd`
3. `pra_listing` is created from `lsfprat` (or `lsfprab` as fallback)
4. Three variables are computed: `bmi_txpl`, `egfr_tx`, `listing_year`
5. The code handles alternative names for `pra_listing` and `tx_mcsd` to ensure compatibility

