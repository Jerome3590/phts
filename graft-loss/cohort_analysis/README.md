# Clinical Cohort Analysis

**Key Feature:** Cohort-specific analysis with modifiable clinical features for CHD vs MyoCardio cohorts.

Dynamic analysis pipeline supporting both survival analysis and event classification with Monte Carlo Cross-Validation (MC-CV).

## Overview

This notebook (`graft_loss_clinical_cohort_analysis.ipynb`) implements cohort-specific analysis using **modifiable clinical features** for two etiologic cohorts:
- **CHD**: Congenital Heart Disease (`primary_etiology == "Congenital HD"`)
- **MyoCardio**: Myocarditis/Cardiomyopathy (`primary_etiology %in% c("Cardiomyopathy", "Myocarditis")`)

## Dynamic Mode Selection

Set `ANALYSIS_MODE` at the top of the notebook:

```r
ANALYSIS_MODE <- "survival"  # or "classification"
```

### Survival Analysis Mode (`ANALYSIS_MODE = "survival"`)

- **Models**: RSF (ranger), AORSF, CatBoost-Cox, XGBoost-Cox (boosting), XGBoost-Cox RF mode
- **Evaluation**: C-index with 95% CI across MC-CV splits
- **Features**: Modifiable clinical features only (renal, liver, nutrition, respiratory, support devices, immunology)

### Event Classification Mode (`ANALYSIS_MODE = "classification"`)

- **Models**: CatBoost (classification), CatBoost RF (classification), Traditional RF (classification), XGBoost (classification), XGBoost RF (classification)
- **Target**: Binary classification at 1 year (event by 1 year vs no event with follow-up >= 1 year)
- **Evaluation**: AUC, Brier Score, Accuracy, Precision, Recall, F1 with 95% CI across MC-CV splits

## Quick Start

1. Set `ANALYSIS_MODE` to desired mode ("survival" or "classification")
2. Set `DEBUG_MODE <- FALSE` for full analysis (or `TRUE` for quick test)
3. Run the notebook from top to bottom
4. Results saved to `outputs/` directory

## Outputs

All outputs are saved to `graft-loss/cohort_analysis/outputs/` and synced to `s3://uva-private-data-lake/graft-loss/cohort_analysis/`.

- **Survival Mode**: 
  - `outputs/survival/cohort_model_cindex_mc_cv_modifiable_clinical.csv`
  - `outputs/survival/best_clinical_features_by_cohort_mc_cv.csv`
  - `outputs/survival/summary/plots/` - Visualizations (heatmaps, Sankey diagrams, bar charts)
  - `outputs/survival/CHD/` and `outputs/survival/MyoCardio/` - Cohort-specific results

- **Classification Mode**: 
  - `outputs/classification_mc_cv/cohort_classification_metrics_mc_cv.csv`

## Results Summary

### Survival Analysis Results (50 MC-CV Splits)

**Best Performing Model: CatBoost** consistently outperformed all other models across both cohorts.

#### CHD Cohort (Congenital Heart Disease)
- **CatBoost**: C-index = **0.558** (95% CI: 0.507 - 0.606)
- **XGBoost**: C-index = 0.466 (95% CI: 0.396 - 0.517)
- **RSF**: C-index = 0.443 (95% CI: 0.401 - 0.500)
- **XGBoost RF**: C-index = 0.445 (95% CI: 0.386 - 0.499)
- **AORSF**: C-index = 0.421 (95% CI: 0.381 - 0.473)

**Top Modifiable Clinical Features (CHD):**
1. Liver function (ALT, AST) - Liver function monitoring
2. ECMO support - Cardiac support device
3. Nutrition markers (total protein, serum albumin) - Nutritional support
4. Kidney function (creatinine) - Renal monitoring
5. Growth parameters (height, weight) - Growth monitoring

#### MyoCardio Cohort (Myocarditis/Cardiomyopathy)
- **CatBoost**: C-index = **0.539** (95% CI: 0.479 - 0.596)
- **XGBoost**: C-index = 0.443 (95% CI: 0.384 - 0.509)
- **RSF**: C-index = 0.442 (95% CI: 0.372 - 0.494)
- **XGBoost RF**: C-index = 0.437 (95% CI: 0.383 - 0.500)
- **AORSF**: C-index = 0.415 (95% CI: 0.355 - 0.472)

**Top Modifiable Clinical Features (MyoCardio):**
1. Liver function markers - Liver function monitoring
2. Nutrition and growth parameters - Nutritional support
3. Kidney function - Renal monitoring
4. Respiratory support (ventilation) - Ventilation management
5. Cardiac support devices (VAD, ECMO) - Hemodynamic support

### Key Findings

1. **Model Performance**: CatBoost achieved the highest C-index for both cohorts, demonstrating superior predictive performance for graft loss risk using modifiable clinical features.

2. **Cohort Differences**: While CatBoost performed best in both cohorts, the CHD cohort showed slightly higher discriminative ability (C-index 0.558 vs 0.539).

3. **Feature Categories**: Liver function, nutrition markers, and kidney function consistently ranked among the top modifiable features across both cohorts, highlighting their importance for post-transplant risk assessment.

4. **Clinical Relevance**: The identified modifiable features represent actionable targets for clinical intervention, including:
   - **Kidney Function**: Creatinine monitoring, eGFR-based intervention, dialysis management
   - **Liver Function**: ALT/AST monitoring, bilirubin assessment
   - **Nutrition**: Albumin, protein intake optimization, growth support
   - **Cardiac Support**: VAD, ECMO management
   - **Respiratory**: Ventilation weaning plans

5. **Robustness**: All models were evaluated using 50 Monte Carlo Cross-Validation splits (80/20 train/test), providing robust, publication-quality estimates with 95% confidence intervals.

### Visualizations

Comprehensive visualizations are available in `outputs/survival/summary/plots/`:
- **C-index Heatmap**: Model performance comparison across cohorts
- **Feature Importance Heatmap**: Top features by cohort and model
- **Scaled Feature Importance Bar Chart**: Normalized importance weighted by model performance
- **Sankey Diagrams**: Interactive flow diagrams showing feature contributions by cohort

## Documentation

For detailed documentation, see:
- **[Notebook Guide](docs/cohort_analysis/README_notebook_guide.md)** - Detailed notebook walkthrough
- **[Ready to Run](docs/cohort_analysis/README_ready_to_run.md)** - Execution instructions
- **[MC-CV Parallel EC2](docs/cohort_analysis/README_mc_cv_parallel_ec2.md)** - EC2 deployment guide
- **[Original vs Updated Study](docs/cohort_analysis/README_original_vs_updated_study.md)** - Methodology comparison
- **[Validation & Leakage](docs/shared/README_validation_concordance_variables_leakage.md)** - Validation procedures (shared)

## Scripts

Visualization scripts are in `scripts/R/`:
- `create_visualizations_cohort.R` - Creates cohort-specific visualizations

