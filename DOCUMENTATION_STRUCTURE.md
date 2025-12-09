# Documentation Structure

## Overview

All documentation has been centralized into the `docs/` folder, with one root README per analysis workflow.

## Structure

```
docs/
├── README.md                          # Documentation index
├── cohort_analysis/                   # Clinical cohort analysis docs
│   ├── README_mc_cv_parallel_ec2.md
│   ├── README_notebook_guide.md
│   ├── README_original_vs_updated_study.md
│   ├── README_ready_to_run.md
│   └── README_validation_concordance_variables_leakage.md
├── feature_importance/                # Global feature importance docs
│   ├── README_graft_loss.md
│   ├── README_mc_cv_parallel_ec2.md
│   ├── README_notebook_guide.md
│   ├── README_original_vs_updated_study.md
│   ├── README_ready_to_run.md
│   ├── README_target_leakage.md
│   └── README_validation_concordance_variables_leakage.md
└── scripts/                           # Scripts and standards docs
    ├── CONSOLIDATION_SUMMARY.md
    ├── LOGGING_STANDARDS.md
    └── OUTPUTS_PLOTS_STANDARDIZATION.md
```

## Root READMEs

Each analysis workflow has one root README that provides:
- Quick overview
- Quick start instructions
- Links to detailed documentation in `docs/`

### Workflow Root READMEs

- `graft-loss/cohort_analysis/README.md` - Clinical cohort analysis
- `graft-loss/feature_importance/README.md` - Global feature importance
- `scripts/README.md` - Scripts directory overview

## Benefits

1. **Centralized Documentation**: All detailed docs in one place
2. **Clean Workflow Directories**: Only essential READMEs in workflow folders
3. **Easy Navigation**: Clear structure with index file
4. **Maintainable**: Easy to find and update documentation

## Usage

- **Quick Start**: Check the root README in each workflow directory
- **Detailed Docs**: See `docs/README.md` for full documentation index
- **Standards**: See `docs/scripts/` for coding standards and conventions

