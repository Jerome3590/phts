# Script Consolidation Summary

All scripts have been consolidated into `scripts/` directory to match EC2 file structure and eliminate duplicates.

## Consolidated Scripts

### R Scripts (`scripts/R/`)

All R scripts are now in `scripts/R/`:

- **`create_visualizations.R`** - Global feature importance visualizations
  - Removed from: `graft-loss/feature_importance/create_visualizations.R`
  
- **`create_visualizations_cohort.R`** - Clinical cohort visualizations  
  - Removed from: `graft-loss/clinical_feature_importance_by_cohort/create_visualizations.R`
  
- **`replicate_20_features_MC_CV.R`** - MC-CV replication script
  - Removed from: `graft-loss/clinical_feature_importance_by_cohort/replicate_20_features_MC_CV.R`
  
- **`check_variables.R`** - Variable validation
  - Removed from: `graft-loss/feature_importance/check_variables.R`
  
- **`check_cpbypass_iqr.R`** - CPBYPASS statistics
  - Removed from: `graft-loss/feature_importance/check_cpbypass_iqr.R`
  
- **`classification_helpers.R`** - Classification helper functions
  - Removed from: `graft-loss/cohort_analysis/classification_helpers.R`
  
- **`survival_helpers.R`** - Survival analysis helpers
  - Removed from: `graft-loss/cohort_survival_analysis/survival_helpers.R`

### Python Scripts (`scripts/py/`)

All Python scripts are now in `scripts/py/`:

- **`ffa_analysis.py`** - FFA analysis pipeline
  - Removed from: `graft-loss/cohort_analysis/ffa_analysis/ffa_analysis.py`
  
- **`catboost_axp_explainer.py`** - CatBoost explainer
  - Removed from: `graft-loss/cohort_analysis/ffa_analysis/catboost_axp_explainer.py`
  
- **`catboost_axp_explainer2.py`** - Alternative CatBoost explainer
  - Removed from: `graft-loss/cohort_analysis/ffa_analysis/catboost_axp_explainer2.py`

## Updated References

All references have been updated to point to `scripts/R/` or `scripts/py/`:

### Notebooks
- `graft-loss/feature_importance/graft_loss_feature_importance_20_MC_CV.ipynb` → `scripts/R/create_visualizations.R`
- `graft-loss/clinical_feature_importance_by_cohort/graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb` → `scripts/R/create_visualizations_cohort.R`

### Quarto Documents (.qmd)
- All `.qmd` files updated to use `scripts/R/` paths for helper scripts
- Python imports updated to use `scripts/py/` with path modification

### README Files
- All README files updated to reference `scripts/R/` paths

## Benefits

1. **Single Source of Truth**: Each script exists in only one location
2. **EC2 Compatibility**: Matches EC2 file structure exactly
3. **Easier Maintenance**: Updates only need to be made in one place
4. **Clear Organization**: All scripts organized by language in `scripts/`

## Migration Notes

- Original script files have been **deleted** (not moved) to prevent confusion
- All notebooks and documents have been updated to use the new paths
- Fallback paths removed from notebooks (scripts must be in `scripts/` directory)

