# Calculator Models - Run Status

## Current Run: Survival Models

**Started**: [Running now]  
**Log File**: `calculator_run_survival.log`

## Models Running

1. **Simple Calculator** (Cox regression - baseline)
2. **CatBoost-Cox** (iterations = 1200)
3. **XGBoost-Cox** (nrounds = 400)
4. **AORSF** (n_tree = 100)
5. **RSF** (num.trees = 500)

## Configuration

- **MC-CV Splits**: 25 per cohort
- **Train/Test Split**: 80/20
- **Cohorts**: CHD, Combined, Myocardio
- **Total Model Fits**: 25 splits × 3 cohorts × 5 models = **375 model fits**
- **Evaluation**: C-index (concordance)

## Expected Runtime

- **Estimated Time**: 1-2 hours on multi-core machine
- **Parallel Workers**: Auto-detected (typically 16-18)

## Parameters (Matched to Original)

- CatBoost: iterations = 1200, depth = 4, learning_rate = 0.1
- XGBoost: nrounds = 400, eta = 0.05, max_depth = 4
- AORSF: n_tree = 100
- RSF: num.trees = 500

## Monitoring

```bash
# Check progress
tail -f calculator_run_survival.log

# Check results
cat ../outputs/calculator_models_summary.csv
```

## Expected Outputs

- `outputs/calculator_models_summary.csv` - Complete results with C-index
- `outputs/best_models_by_cohort.csv` - Best model per cohort
- `outputs/importance_[COHORT]_[MODEL].csv` - Feature importance for each model

---

*Status: Running in background*
