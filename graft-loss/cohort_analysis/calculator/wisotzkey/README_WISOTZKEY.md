# Wisotzkey-vars models (cohort versions)

Same SAS dataset as the calculator pipeline (`phts_txpl_ml.sas7bdat`). Wisotzkey et al. variable set is built per cohort (CHD, Myocardio, Combined) and can be used to train **Wisotzkey-variant** survival models.

## Reference

Wisotzkey et al. (2023). Risk factors for 1-year allograft loss in pediatric heart transplant. *Pediatric Transplantation*.

## Variables used (Wisotzkey feature set)

| Variable | Description |
|----------|-------------|
| **CHD** | 1 = Congenital HD, 0 = Cardiomyopathy/Myocarditis |
| **TXMCSD** | Mechanical circulatory support device at transplant |
| **CHD_SV** | CHD: Single ventricle |
| **HXSURG** | Prior heart surgeries |
| **HXMED** | Medical history at listing |
| **ALBUMIN_UNDER_3** | Serum albumin at transplant < 3 g/dL |
| **BUN_UNDER_15** | BUN at transplant < 15 mg/dL |
| **eGFR_UNDER_60** | eGFR at transplant < 60 (Schwartz formula) |
| **TXECMO** | ECMO at transplant |
| **YR_UNDER_2015** | Transplant year < 2015 |
| **WEIGHT_UNDER_75** | Weight at transplant < 75 kg |
| **BMI_UNDER_18** | BMI at transplant < 18 |
| **ALT_UNDER_30** | ALT at transplant < 30 U/L (or missing) |
| **ALT_OVER_50** | ALT at transplant ≥ 50 U/L |

Derived in code: `BMI_TXPL = 703 * WEIGHT_TXPL / HEIGHT_TXPL²`, `eGFR_TXPL = 0.413 * (HEIGHT_TXPL*2.54) / max(TXCREAT_R, 0.001)`.

## Data and R script

- **Python**: `wisotzkey_data.py` in the calculator directory builds Wisotzkey vars from the same SAS file and exposes `WISOTZKEY_FEATURES`, `make_wisotzkey_data()`, `make_wisotzkey_data_for_training()`, `load_wisotzkey_data_for_training()`.
- **R**: `scripts/R/wisotzkey-vars.R` and this folder’s `wisotzkey-vars.R` define `make_wisotzkey_data(df, cohort)` and `make_wisotzkey_data_by_cohort(df, out_dir)` for CHD, Myocardio, Combined.

## Training Wisotzkey models (one per cohort)

From the calculator directory:

```bash
# CHD cohort
python train_python_models.py --cohort CHD --wisotzkey_vars_only

# Myocardio cohort
python train_python_models.py --cohort Myocardio --wisotzkey_vars_only

# Combined cohort
python train_python_models.py --cohort Combined --wisotzkey_vars_only
```

Outputs: `outputs/models/CHD_wisotzkey/`, `outputs/models/Myocardio_wisotzkey/`, `outputs/models/Combined_wisotzkey/` (same MC-CV and best-model structure as the top-15 calculator models).

## Total model variants

- **Top-15 causal (calculator)**: `CHD_top`, `Myocardio_top`, `Combined_top` — 3 models (same input feature set).
- **Wisotzkey-vars**: `CHD_wisotzkey`, `Myocardio_wisotzkey`, `Combined_wisotzkey` — 3 models (Wisotzkey variable set).

**Total: 6 cohort models** (3 top + 3 Wisotzkey). Compare both sets with:

```bash
python compare_top_vs_wisotzkey.py
python compare_top_vs_wisotzkey.py --output outputs/model_comparison_top_vs_wisotzkey.csv
```
