# Calculator Models

> **🚀 Python Workflow Available**: For a fully Python-based workflow (training + SHAP/FFA), see:
> - **Training**: `python train_python_models.py --cohort Combined`
> - **SHAP/FFA**: `python run_shap_ffa_workflow.py --cohort Combined --top-k 10`
> 
> The R implementation (`calculator_models.R`) is still available for users who prefer R.

This directory contains three calculator models for pediatric heart transplant graft loss prediction:

> **📋 For detailed documentation, see [docs/calculator/](../../../docs/calculator/README.md)**

1. **CHD Model** - Congenital Heart Disease cohort only
2. **Combined Model** - All primary diagnoses
3. **Myocardio Model** - Cardiomyopathy and Myocarditis cohort only

## Quick Reference

- **Training Models**: `python train_python_models.py --cohort <Cohort>`
- **SHAP/FFA Analysis**: `python run_shap_ffa_workflow.py --cohort <Cohort> --top-k 20`
- **Dashboard Location**: `risk_dashboard/phts_dashboard.html`
- **Lambda Function**: `risk_dashboard/phts_lambda_function.py`

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

1. **Train Models**: 
   ```bash
   python train_python_models.py --cohort Combined
   python train_python_models.py --cohort CHD
   python train_python_models.py --cohort Myocardio
   ```

2. **Run SHAP/FFA Analysis**:
   ```bash
   python run_shap_ffa_workflow.py --cohort Combined --top-k 20
   ```

3. **Deploy Dashboard**: See [docs/calculator/README_deployment.md](../../../docs/calculator/README_deployment.md)

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
