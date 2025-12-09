# Global Feature Importance Analysis

Comprehensive Monte Carlo Cross-Validation (MC-CV) feature importance workflow replicating and extending the original Wisotzkey study.

## Overview

This notebook (`graft_loss_feature_importance_20_MC_CV.ipynb`) implements global feature selection using multiple methods across three time periods:

- **Original**: 2010-2019 (matches publication)
- **Full**: 2010-2024 (all available data)
- **Full No COVID**: 2010-2024 excluding 2020-2023

## Methods

- **RSF (Random Survival Forest)**: Permutation importance
- **CatBoost**: Gradient boosting with gain-based importance
- **AORSF (Accelerated Oblique Random Survival Forest)**: Negate importance

## MC-CV Configuration

- **Development**: 100 splits (~1-2 hours on EC2)
- **Publication**: 1000 splits (~10-20 hours on EC2)
- **Train/Test Split**: 75/25 stratified by outcome
- **Evaluation**: C-index with 95% confidence intervals

## Quick Start

1. Set `DEBUG_MODE <- FALSE` for full analysis (or `TRUE` for quick test)
2. Set `n_mc_splits <- 100` for development or `1000` for publication
3. Run the notebook from top to bottom
4. Results saved to `outputs/` directory

## Outputs

- `outputs/plots/` - Feature importance visualizations
- `outputs/cindex_table.csv` - C-index table with confidence intervals
- `outputs/top_20_features_*.csv` - Top 20 features per method and period

## Documentation

For detailed documentation, see:
- **[Notebook Guide](docs/feature_importance/README_notebook_guide.md)** - Detailed notebook walkthrough
- **[Ready to Run](docs/feature_importance/README_ready_to_run.md)** - Execution instructions
- **[MC-CV Parallel EC2](docs/feature_importance/README_mc_cv_parallel_ec2.md)** - EC2 deployment guide
- **[Original vs Updated Study](docs/feature_importance/README_original_vs_updated_study.md)** - Methodology comparison
- **[Target Leakage](docs/feature_importance/README_target_leakage.md)** - Leakage prevention
- **[Validation & Leakage](docs/feature_importance/README_validation_concordance_variables_leakage.md)** - Validation procedures

## Scripts

Visualization scripts are in `scripts/R/`:
- `create_visualizations.R` - Creates feature importance visualizations
- `replicate_20_features_MC_CV.R` - MC-CV replication script

