# Directory Structure Review

## Summary of Changes

The directory structure has been consolidated:

### Removed Directories:
- ❌ `graft-loss/clinical_feature_importance_by_cohort/` - Consolidated into `cohort_analysis`
- ❌ `graft-loss/cohort_survival_analysis/` - Removed (functionality consolidated)

### Removed Files:
- ❌ All `.qmd` files from `cohort_analysis/` (consolidated into notebook)
- ❌ All `.qmd` files from `cohort_survival_analysis/` (directory removed)

### Current Structure:

```
graft-loss/
├── cohort_analysis/
│   ├── graft_loss_clinical_cohort_analysis.ipynb  ← Consolidated notebook (dynamic survival/classification)
│   └── README_*.md (multiple README files)
├── feature_importance/
│   └── graft_loss_feature_importance_20_MC_CV.ipynb
├── unified_cohort_survival_analysis/
├── univariate_analysis/
└── lasso/
```

## Key Consolidation

**`graft-loss/cohort_analysis/graft_loss_clinical_cohort_analysis.ipynb`** now contains:
- ✅ Dynamic ANALYSIS_MODE (survival/classification)
- ✅ Section 10: Survival Analysis Mode (RSF, AORSF, CatBoost-Cox, XGBoost-Cox)
- ✅ Section 11: Classification Mode (LASSO, CatBoost, CatBoost RF, Traditional RF)
- ✅ MC-CV workflow for both modes
- ✅ Modifiable clinical features focus
- ✅ CHD vs MyoCardio cohort analysis

## Benefits

1. **Single Source of Truth**: One notebook for all cohort analysis
2. **Dynamic Mode Selection**: Easy switching between survival and classification
3. **Simplified Structure**: Fewer directories and files to maintain
4. **Consistent Workflow**: Same MC-CV structure for both modes

## Documentation Updates

- ✅ README.md updated to reflect new structure
- ✅ Pipeline summary table updated
- ✅ Mermaid diagram updated
- ✅ Outputs section updated

## Next Steps

- [ ] Verify notebook runs correctly in both modes
- [ ] Test outputs are generated correctly
- [ ] Update any remaining references in other documentation files

