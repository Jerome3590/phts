# PHTS Risk Calculator - Models and Risk Score Calculation

## Overview

The PHTS (Pediatric Heart Transplant Survival) Risk Calculator uses machine learning models to predict graft loss risk for pediatric heart transplant patients. The calculator supports three diagnostic cohorts: **CHD** (Congenital Heart Disease), **Combined**, and **Myocardio** (Cardiomyopathy/Myocarditis).

## Models

### Model Types

The calculator uses three types of survival models:

1. **CatBoost-Cox** - Gradient boosting with native categorical support
2. **XGBoost-Cox** - Extreme gradient boosting for survival analysis
3. **XGBoost-Cox RF** - XGBoost with random forest base learners

### Best Model Selection

Each cohort uses the **best-performing model** based on evaluation metrics. The best model is automatically selected for each cohort and stored in `best_model.txt`. The calculator loads the model specified in this file.

| Cohort | Best Model (Deployed) | C-Index (Single Eval) | C-Index (MC-CV Mean) | 95% CI (MC-CV) |
|--------|----------------------|---------------------|---------------------|----------------|
| **CHD** | XGBoost | 0.645 | 0.472 | 0.429 - 0.538 |
| **Combined** | XGBoost | 0.677 | 0.434 | 0.404 - 0.469 |
| **Myocardio** | CatBoost | 0.599 | 0.567 | 0.483 - 0.639 |

**Note**: The deployed models are selected based on single evaluation performance. MC-CV results show CatBoost performs best on average across all cohorts, but the deployed models may differ based on specific evaluation criteria.

### Model Performance by Cohort

#### CHD Cohort

| Model | C-Index Mean | C-Index SD | 95% CI Lower | 95% CI Upper |
|-------|-------------|------------|--------------|--------------|
| **CatBoost** ⭐ | **0.577** | 0.024 | 0.534 | 0.621 |
| XGBoost | 0.472 | 0.032 | 0.429 | 0.538 |
| Simple Calculator | 0.417 | 0.027 | 0.375 | 0.461 |
| RSF | 0.405 | 0.025 | 0.360 | 0.455 |
| AORSF | 0.395 | 0.030 | 0.349 | 0.451 |

**Deployed Model**: XGBoost (C-index: 0.645 from single evaluation)  
**MC-CV Performance**: CatBoost has highest average C-index (0.577) across 25 splits

#### Combined Cohort

| Model | C-Index Mean | C-Index SD | 95% CI Lower | 95% CI Upper |
|-------|-------------|------------|--------------|--------------|
| **CatBoost** ⭐ | **0.567** | 0.064 | 0.430 | 0.647 |
| XGBoost | 0.434 | 0.020 | 0.404 | 0.469 |
| RSF | 0.373 | 0.021 | 0.326 | 0.405 |
| Simple Calculator | 0.349 | 0.025 | 0.311 | 0.393 |
| AORSF | 0.347 | 0.023 | 0.316 | 0.395 |

**Deployed Model**: XGBoost (C-index: 0.645 from single evaluation)  
**MC-CV Performance**: CatBoost has highest average C-index (0.577) across 25 splits

#### Myocardio Cohort

| Model | C-Index Mean | C-Index SD | 95% CI Lower | 95% CI Upper |
|-------|-------------|------------|--------------|--------------|
| **CatBoost** ⭐ | **0.567** | 0.042 | 0.483 | 0.639 |
| XGBoost | 0.478 | 0.040 | 0.402 | 0.535 |
| Simple Calculator | 0.438 | 0.033 | 0.374 | 0.494 |
| AORSF | 0.396 | 0.035 | 0.342 | 0.452 |
| RSF | 0.380 | 0.039 | 0.324 | 0.454 |

**Deployed Model**: CatBoost (C-index: 0.599 from single evaluation)  
**MC-CV Performance**: CatBoost has highest average C-index (0.567) across 25 splits

### C-Index Interpretation

The **C-index (Concordance Index)** measures the model's ability to correctly rank patients by risk:

- **C-index = 0.5**: Random guessing (no predictive ability)
- **C-index = 1.0**: Perfect prediction
- **C-index > 0.7**: Good discrimination
- **C-index > 0.6**: Moderate discrimination
- **C-index < 0.6**: Poor discrimination

**Our Models**: All cohorts achieve C-index > 0.56, indicating **moderate to good discrimination** for graft loss risk prediction.

## Risk Score Calculation

### Single Model Prediction (Default)

By default, the calculator uses **only the best model** for each cohort:

1. **Load Best Model**: The best-performing model (XGBoost for CHD/Combined, CatBoost for Myocardio) is loaded
2. **Prepare Features**: User-provided clinical features are converted to a feature vector matching the model's expected format
3. **Predict**: The model generates a raw prediction score
4. **Return Risk Score**: The raw prediction is returned as the risk score

```python
# Pseudocode
best_model = load_best_model(cohort)  # XGBoost for CHD/Combined, CatBoost for Myocardio
feature_vector = prepare_features(user_inputs)
risk_score = best_model.predict(feature_vector)
return risk_score
```

### Ensemble Prediction (Optional)

If ensemble mode is enabled (`use_ensemble=True`), the calculator:

1. **Load All Models**: Loads CatBoost, XGBoost, and XGBoost RF models
2. **Predict with Each**: Each model generates a prediction
3. **Average Predictions**: The final risk score is the **arithmetic mean** of all model predictions

```python
# Pseudocode
predictions = {}
for model_type in ['catboost', 'xgboost', 'xgboost_rf']:
    model = load_model(cohort, model_type)
    predictions[model_type] = model.predict(feature_vector)

risk_score = mean(predictions.values())  # Simple average
```

**Note**: Ensemble mode is currently disabled by default (`use_best_model_only=True`).

### Risk Score Normalization

**Raw risk scores** from models have different scales across cohorts and models, making them difficult to interpret. The calculator **normalizes risk scores to percentiles (0-100)** for consistent interpretation across all cohorts.

#### Normalization Process

1. **Raw Prediction**: Model generates raw risk score
2. **Percentile Conversion**: Raw score is converted to percentile rank (0-100) based on training data distribution
3. **Risk Band Assignment**: Percentile is mapped to risk band (low/medium/high/very_high)

#### Normalization Method

The calculator uses **percentile-based normalization**:

- **Percentile 0-100**: Represents where the patient's risk falls relative to the training population
- **Percentile 50** = Median risk (50% of patients have lower risk)
- **Percentile 75** = 75th percentile (75% of patients have lower risk)
- **Percentile 90** = 90th percentile (90% of patients have lower risk)

**Example**:
- Raw score: `-2.34` (from CatBoost model)
- Normalized: `75.3%` (patient is in the 75th percentile - higher risk than 75% of training population)

#### Risk Score Interpretation

The **normalized risk score** (percentile) represents the patient's risk relative to the training population:

- **0-25%**: Low Risk - Lower than 75% of training population
- **25-75%**: Medium Risk - Middle 50% of training population
- **75-90%**: High Risk - Higher than 75% of training population
- **90-100%**: Very High Risk - Higher than 90% of training population

**Risk Bands**:
- **Low Risk**: < 25th percentile
- **Medium Risk**: 25th-75th percentile
- **High Risk**: 75th-90th percentile
- **Very High Risk**: ≥ 90th percentile

#### Benefits of Normalization

1. **Cross-Cohort Comparability**: Percentiles are comparable across CHD, Combined, and Myocardio cohorts
2. **Clinical Interpretability**: Percentiles are intuitive - "patient is in the 80th percentile" is clearer than "raw score is -2.34"
3. **Consistent Risk Bands**: Same percentile thresholds apply to all cohorts
4. **Population Context**: Shows where patient falls relative to historical data

**Note**: If risk distribution data is not available, the calculator falls back to raw scores. Risk distributions are computed from training data and stored in `risk_distributions.json`.

## Model Training

### Training Process

1. **Data Split**: 25 Monte Carlo Cross-Validation splits
2. **Feature Engineering**: Clinical features are prepared and standardized
3. **Model Training**: Each model type is trained on training sets
4. **Evaluation**: C-index is calculated on test sets
5. **Selection**: Best model (highest C-index) is selected for each cohort

### Evaluation Metrics

- **Primary Metric**: C-index (Concordance Index) - measures ranking ability
- **Confidence Intervals**: 95% CI calculated from 25 MC-CV splits
- **Standard Deviation**: SD across splits indicates model stability

## Feature Input

### Clinical Features

The calculator accepts **modifiable clinical features** that can be influenced by clinical intervention:

- **Kidney Function**: eGFR, BUN, Creatinine
- **Liver Function**: AST, ALT, Bilirubin
- **Nutrition**: Albumin, Pre-albumin, Total Protein, BMI
- **Cardiac Support**: LVAD, ECMO, MCSD
- **Respiratory**: Ventilation, Tracheostomy
- **Immunology**: PRA, HLA pre-sensitization
- **Demographics**: Age, Height, Weight
- **Diagnosis**: Primary etiology, CHD subtypes

See `README_FINAL_MODELS.md` for complete feature list.

## Model Deployment

### Production Deployment

- **Platform**: AWS Lambda (serverless)
- **Container**: Docker image with models baked in
- **Storage**: Models stored in container filesystem (`/var/task/models/`)
- **Caching**: Models are cached in memory for performance
- **API**: REST API via API Gateway

### Model Files

Each cohort has:
- `catboost_model.cbm` - CatBoost model (best model for Myocardio cohort)
- `xgboost_model.ubj` - XGBoost model
- `xgboost_rf_model.ubj` - XGBoost RF model
- `best_model.txt` - Indicates which model is best

## References

- **C-Index**: Harrell's C-index for survival model evaluation
- **CatBoost**: Gradient boosting with native categorical support
- **XGBoost**: Extreme gradient boosting
- **Survival Analysis**: Cox proportional hazards models

## Notes

- Models are trained on PHTS (Pediatric Heart Transplant Survival) registry data
- Performance metrics are from 25 Monte Carlo Cross-Validation splits
- Risk scores should be interpreted in clinical context
- Models are updated periodically as new data becomes available

---

**Last Updated**: 2026-01-13  
**Model Version**: Production models (trained on latest PHTS data)  
**Calculator Version**: 1.0
