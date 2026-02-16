# Calculator Models

> **🚀 Single model (top 15 features)**: The deployed calculator uses one model trained on the top 15 high causal/importance features only.
> - **Training**: `python train_python_models.py --top_features_only` → outputs to `Combined_top/`
> - **SHAP/FFA**: Run for `Combined_top`; then deploy. Dashboard and Lambda use `Combined_top` only (no Baseline/Extended).

This directory contains calculator training and the risk dashboard. The **deployed** calculator uses a single model (Combined_top, top 15 features). Legacy cohort-specific models (CHD, Combined, Myocardio) remain available for training.

> **📋 For detailed documentation, see [docs/calculator/](../../../docs/calculator/README.md)**

1. **CHD Model** - Congenital Heart Disease cohort only
2. **Combined Model** - All primary diagnoses
3. **Myocardio Model** - Cardiomyopathy and Myocarditis cohort only

## Quick Reference

- **Train top-features model** (for dashboard): `python train_python_models.py --top_features_only`
- **Train FULL variants** (calculator + R replication vars for C-index comparison): `python train_python_models.py --train-full-variants` → `Combined_FULL`, `CHD_FULL`, `Myocardio_FULL`
- **SHAP/FFA for Combined_top**: Run workflow for `Combined_top`; output to `outputs/shap_ffa/Combined_top/`
- **Dashboard**: `risk_dashboard/phts_dashboard.html` (single model: top 15 features)
- **Lambda**: `risk_dashboard/phts_lambda_function.py` (uses `Combined_top` only)

## Documentation

For comprehensive documentation, see **[docs/calculator/](../../../docs/calculator/README.md)**:

- **[SHAP + FFA Integration](../../../docs/calculator/README_shap_ffa.md)** - SHAP and Formal Feature Attribution workflow
- **[Final Models](../../../docs/calculator/README_final_models.md)** - Complete variable documentation and final model results
- **[Dashboard](../../../docs/calculator/README_dashboard.md)** - Risk dashboard user guide
- **[Deployment](../../../docs/calculator/README_deployment.md)** - AWS deployment guide
- **[Causal Analysis](../../../docs/calculator/README_causal_analysis.md)** - Causal analysis workflow
- **[Models](../../../docs/calculator/README_models.md)** - Model performance and risk calculation
- **[Architecture](../../../docs/calculator/README_architecture.md)** - System architecture

## Overview

Each model compares five different **survival models**:
- **Simple Calculator** - Cox regression with selected clinical features (baseline)
- **CatBoost-Cox** - Gradient boosting with categorical feature support (iterations=1200)
- **XGBoost-Cox** - Extreme gradient boosting (nrounds=400)
- **AORSF** - Accelerated Oblique Random Survival Forest (n_tree=100)
- **RSF** - Random Survival Forest using ranger (num.trees=500)

## Methodology

- **Monte Carlo Cross-Validation**: 25 random 80/20 train/test splits
- **Evaluation Metric**: C-index (Concordance) for time-to-event survival analysis
- **Feature Importance**: Aggregated across all MC-CV splits
- **Outcome Definition**: Time-to-event (graft loss) with censoring
- **Model Type**: Survival models (Cox regression) for time-to-event analysis

## Quick Start

1. **Train top-features model** (for the deployed calculator):
   ```bash
   python train_python_models.py --top_features_only
   ```
   Output: `outputs/models/Combined_top/`

2. **Run SHAP/FFA** for Combined_top, then **prepare Lambda** and deploy (see risk_dashboard READMEs).

3. **Deploy Dashboard**: See [docs/calculator/README_deployment.md](../../../docs/calculator/README_deployment.md)

   **Docker Setup (if needed):**
   ```bash
   # If you get "permission denied" errors with Docker:
   sudo usermod -aG docker $USER
   newgrp docker  # Or log out and back in
   docker ps      # Verify it works
   ```

## Directory Structure

```
calculator/
├── README.md                    # This file (quick reference)
├── train_python_models.py      # Model training script
├── run_shap_ffa_workflow.py    # SHAP/FFA analysis script
├── outputs/                     # Model outputs and results
│   ├── models/                  # Trained models
│   ├── shap_ffa/                # SHAP/FFA analysis results
│   └── risk_distributions/      # Risk score distributions
└── risk_dashboard/              # Dashboard and deployment files
    ├── phts_dashboard.html      # Frontend dashboard
    ├── phts_lambda_function.py  # Lambda API handler
    └── Dockerfile.phts          # Docker container for Lambda
```

## See Also

- **Main Project README**: [../../../README.md](../../../README.md)
- **Cohort Analysis README**: [../README.md](../README.md)
- **Full Documentation**: [docs/calculator/](../../../docs/calculator/README.md)
