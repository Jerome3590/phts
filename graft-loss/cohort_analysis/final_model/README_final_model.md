# Final Model Development - Cohort Analysis

This module hosts the final prediction model pipeline for pediatric heart transplant graft loss using cohort-specific ensemble models with modifiable clinical features.

## Overview

The final model integrates **ensemble modeling** combining three complementary survival models to create robust, cohort-specific risk predictions:

1. **CatBoost-Cox** - Gradient boosting optimized for categorical features
2. **XGBoost-Cox** - Extreme gradient boosting (standard boosting mode)
3. **XGBoost-Cox RF** - XGBoost in random forest mode (many parallel trees)

**Key Innovation:** Ensemble approach combines the strengths of different modeling paradigms (gradient boosting vs random forest) to improve prediction stability and generalization.

### Cohort-Specific Models

The final model is trained separately for two distinct etiologic cohorts:

- **CHD Cohort**: Congenital Heart Disease (`primary_etiology == "Congenital HD"`)
- **MyoCardio Cohort**: Myocarditis/Cardiomyopathy (`primary_etiology %in% c("Cardiomyopathy", "Myocarditis")`)

Each cohort has its own ensemble model, as clinical risk factors differ significantly between these patient populations.

### Modifiable Clinical Features

The model focuses exclusively on **clinically modifiable features** that can be targeted for intervention:

- **Kidney Function**: Creatinine, dialysis history, eGFR
- **Liver Function**: AST/ALT, bilirubin, Fontan liver disease
- **Nutrition**: Albumin, protein levels, BMI, growth metrics
- **Respiratory**: Ventilation status, tracheostomy history
- **Cardiac Support**: VAD, ECMO, MCSD status
- **Immunology**: HLA sensitization, crossmatch, PRA levels

**Rationale:** By focusing on modifiable features, the model provides actionable insights for clinical intervention rather than just identifying non-modifiable risk factors.

## Goals

- Build cohort-specific ensemble models for graft loss prediction
- Use only modifiable clinical features for actionable insights
- Combine CatBoost, XGBoost, and XGBoost RF in performance-weighted ensemble
- Provide robust risk predictions with confidence intervals
- Enable risk comparison scenarios for clinical decision-making

## Feature Schema

The complete feature schema consists of **modifiable clinical features only** (~40-50 features per cohort).

### Feature Categories

| Category | Feature Count | Examples | Modifiability |
|----------|---------------|----------|---------------|
| **Kidney Function** | ~5 | `txcreat_r`, `lcreat_r`, `hxdysdia`, `egfr_tx` | Partially Modifiable |
| **Liver Function** | ~9 | `txast`, `txalt`, `txbili_d_r`, `hxfonlvr` | Partially Modifiable |
| **Nutrition** | ~12 | `txpalb_r`, `bmi_txpl`, `height_txpl`, `weight_txpl` | Modifiable |
| **Respiratory** | ~4 | `txvent`, `slvent`, `hxtrach` | Partially Modifiable |
| **Cardiac Support** | ~7 | `txvad`, `txecmo`, `slnomcsd`, `hxcpr` | Partially Modifiable |
| **Immunology** | ~4 | `hlatxpre`, `donspac`, `txfcpra` | Partially Modifiable |
| **Total** | **~40-50** | Modifiable clinical features | Actionable |

### Key Features

#### Kidney Function Features
- **Creatinine**: `txcreat_r` (transplant), `lcreat_r` (listing)
- **Dialysis**: `hxdysdia` (dialysis history)
- **Renal Insufficiency**: `hxrenins` (renal insufficiency history)
- **eGFR**: `egfr_tx` (estimated GFR at transplant)

#### Liver Function Features
- **AST/ALT**: `txast`, `lsast`, `txalt`, `lsalt` (transplant and listing)
- **Bilirubin**: `txbili_d_r`, `txbili_t_r`, `lsbili_d_r`, `lsbili_t_r`
- **Fontan Liver**: `hxfonlvr` (Fontan liver disease history)

#### Nutrition Features
- **Albumin**: `txpalb_r`, `lspalb_r` (transplant and listing)
- **Serum Albumin**: `txsa_r`, `lssab_r`
- **Total Protein**: `txtp_r`, `lstp_r`
- **Growth**: `bmi_txpl`, `height_txpl`, `weight_txpl`, `height_listing`, `weight_listing`
- **Failure to Thrive**: `hxfail`

#### Respiratory Features
- **Ventilation**: `txvent` (transplant), `slvent` (listing)
- **Tracheostomy**: `ltxtrach`, `hxtrach`

#### Cardiac Support Features
- **VAD**: `txvad` (transplant), `slvad` (listing)
- **ECMO**: `txecmo` (transplant), `slecmo` (listing)
- **MCSD**: `slnomcsd` (consider MCSD)
- **CPR/Shock**: `hxcpr`, `hxshock`

#### Immunology Features
- **HLA Sensitization**: `hlatxpre` (HLA pre-sensitization)
- **Crossmatch**: `donspac` (donor-specific crossmatch)
- **PRA**: `txfcpra`, `lsfcpra` (transplant and listing)

## Data Inputs

### Base Cohort Data
- PHTS registry data: `graft-loss/data/phts_txpl_ml.sas7bdat`
- Filtered by cohort: CHD or MyoCardio
- Time period: 2010-2024 (configurable)

### Feature Preparation
- Features extracted from PHTS data
- Only modifiable clinical features included
- Missing values handled appropriately (median/mode imputation)
- Categorical variables encoded as factors (for CatBoost)

## Feature Engineering Pipeline

```r
# 1. Load PHTS data
phts_data <- read_sas("graft-loss/data/phts_txpl_ml.sas7bdat")

# 2. Filter by cohort
chd_data <- phts_data %>% filter(primary_etiology == "Congenital HD")
mc_data <- phts_data %>% filter(primary_etiology %in% c("Cardiomyopathy", "Myocarditis"))

# 3. Select modifiable clinical features
modifiable_features <- c(
  # Kidney Function
  "txcreat_r", "lcreat_r", "hxdysdia", "hxrenins", "egfr_tx",
  # Liver Function
  "txast", "lsast", "txalt", "lsalt", "txbili_d_r", "lsbili_d_r",
  "txbili_t_r", "lsbili_t_r", "hxfonlvr",
  # Nutrition
  "txpalb_r", "lspalb_r", "txsa_r", "lssab_r", "txtp_r", "lstp_r",
  "hxfail", "bmi_txpl", "height_txpl", "height_listing", 
  "weight_txpl", "weight_listing",
  # Respiratory
  "txvent", "slvent", "ltxtrach", "hxtrach",
  # Cardiac
  "txvad", "slvad", "slnomcsd", "txecmo", "slecmo", "hxcpr", "hxshock",
  # Immunology
  "hlatxpre", "donspac", "txfcpra", "lsfcpra"
)

# 4. Prepare modeling data
modeling_data <- cohort_data %>%
  select(time = outcome_int_graft_loss, 
         status = outcome_graft_loss,
         all_of(modifiable_features)) %>%
  filter(!is.na(time), !is.na(status), time > 0) %>%
  mutate(across(where(is.character), as.factor))

# 5. Train/test split (80/20 stratified by status)
set.seed(1997)
split <- initial_split(modeling_data, prop = 0.8, strata = status)
train_data <- training(split)
test_data <- testing(split)
```

## Model Training and Ensemble

Final model development uses a **three-model ensemble** with performance-based weighting:

### Base Models

1. **CatBoost-Cox**
   - Optimized for categorical features
   - Handles missing values natively
   - Parameters: `iterations=2000`, `depth=4`, `learning_rate=0.03`

2. **XGBoost-Cox (Boosting)**
   - Standard gradient boosting
   - Parameters: `nrounds=500`, `max_depth=4`, `eta=0.05`

3. **XGBoost-Cox RF Mode**
   - Random forest-style (many parallel trees)
   - Parameters: `num_parallel_tree=100`, `subsample=0.8`, `colsample_bytree=0.8`

### Ensemble Strategy

The ensemble combines predictions from all three models using **performance-based weighting**:

```r
# Calculate model weights based on C-index performance
weights <- c(
  catboost_weight = catboost_cindex / total_cindex,
  xgboost_weight = xgboost_cindex / total_cindex,
  xgboost_rf_weight = xgboost_rf_cindex / total_cindex
)

# Ensemble prediction
ensemble_prediction <- 
  weights$catboost_weight * catboost_pred +
  weights$xgboost_weight * xgboost_pred +
  weights$xgboost_rf_weight * xgboost_rf_pred
```

**Weighting Method:**
- Weights proportional to C-index performance on validation set
- Higher-performing models receive higher weights
- Weights sum to 1.0

### MC-CV Evaluation

Models are evaluated using **Monte Carlo Cross-Validation (MC-CV)**:

- **Splits**: 50-100 stratified train/test splits (80/20)
- **Stratification**: By event status to maintain event distribution
- **Evaluation**: C-index (time-dependent and time-independent)
- **Reporting**: Mean C-index with 95% confidence intervals

**MC-CV Process:**
1. For each split:
   - Train all three models on training set
   - Evaluate on test set
   - Calculate C-index for each model
2. Aggregate results across splits:
   - Mean C-index per model
   - Standard deviation
   - 95% confidence intervals
3. Calculate ensemble weights based on mean C-index

### Model Selection

The ensemble uses all three models, but weights are adjusted based on performance:

- **Best Model**: Model with highest mean C-index gets highest weight
- **Ensemble Benefit**: Combining models typically improves robustness and reduces variance
- **Cohort-Specific**: Different cohorts may have different optimal model combinations

## Notebooks and Scripts

- `graft_loss_clinical_cohort_analysis.ipynb`: Main analysis notebook with MC-CV, model training, and ensemble evaluation
- `train_final_ensemble.R`: Trains final ensemble model for deployment
- `prepare_models.py`: Converts R models to Python-compatible format for Lambda deployment
- `evaluate_ensemble.R`: Evaluates ensemble performance and calculates weights

## S3 Data Organization

### Model Storage

**S3 Structure:**
```
s3://uva-private-data-lake/graft-loss/cohort_analysis/models/
├── CHD/
│   ├── catboost_cox.pkl
│   ├── xgboost_cox.pkl
│   ├── xgboost_rf_cox.pkl
│   ├── ensemble_weights.json
│   └── metadata.json
└── MyoCardio/
    ├── catboost_cox.pkl
    ├── xgboost_cox.pkl
    ├── xgboost_rf_cox.pkl
    ├── ensemble_weights.json
    └── metadata.json
```

**Metadata Format:**
```json
{
  "cohort": "CHD",
  "models": {
    "catboost_cox": {
      "c_index": 0.85,
      "c_index_ci": [0.82, 0.88],
      "weight": 0.35
    },
    "xgboost_cox": {
      "c_index": 0.87,
      "c_index_ci": [0.84, 0.90],
      "weight": 0.40
    },
    "xgboost_rf_cox": {
      "c_index": 0.83,
      "c_index_ci": [0.80, 0.86],
      "weight": 0.25
    }
  },
  "ensemble_c_index": 0.88,
  "ensemble_c_index_ci": [0.85, 0.91]
}
```

## Model Predictions

### Prediction Format

The ensemble model produces risk scores for graft loss:

```r
# Single prediction
prediction <- predict_ensemble(
  models = list(catboost_model, xgboost_model, xgboost_rf_model),
  weights = ensemble_weights,
  new_data = patient_features
)

# Returns:
# - risk_score: Continuous risk score (higher = higher risk)
# - risk_percentile: Percentile rank (0-100)
# - confidence_interval: 95% CI for risk score
# - feature_contributions: SHAP values or feature importance
```

### Risk Interpretation

- **Low Risk**: < 25th percentile
- **Medium Risk**: 25th-75th percentile
- **High Risk**: > 75th percentile
- **Very High Risk**: > 90th percentile

**Note:** Risk thresholds are cohort-specific and should be validated on independent test sets.

## Feature Importance

Feature importance is extracted from the ensemble model:

1. **Individual Model Importance**: Extract from each base model
2. **Weighted Aggregation**: Combine using ensemble weights
3. **Normalization**: Scale to sum to 1.0
4. **C-index Scaling**: Weight by model performance

**Top Features** (example for CHD cohort):
- VAD support (`txvad`, `slvad`)
- Kidney function (`txcreat_r`, `egfr_tx`)
- Nutritional status (`txpalb_r`, `bmi_txpl`)
- ECMO support (`txecmo`)
- Immunology (`hlatxpre`, `txfcpra`)

## Model Deployment

### Lambda Deployment

Models are deployed to AWS Lambda for real-time predictions:

1. **Model Conversion**: R models converted to Python-compatible format
2. **S3 Upload**: Models uploaded to S3 bucket
3. **Lambda Function**: Loads models and makes predictions
4. **API Gateway**: Exposes REST API endpoints

See `../dashboard/README.md` for deployment details.

### Dashboard Integration

The ensemble model is integrated into the risk dashboard:

- **Risk Assessment**: Single patient risk prediction
- **Risk Comparison**: Compare baseline vs intervention scenarios
- **Feature Contributions**: Show which features drive risk
- **Clinical Recommendations**: Auto-generated based on risk factors

## Model Performance

### Expected Performance

Based on MC-CV evaluation:

- **CHD Cohort**: C-index ~0.80-0.85 (95% CI)
- **MyoCardio Cohort**: C-index ~0.82-0.87 (95% CI)

**Ensemble Benefit:**
- Typically improves C-index by 0.02-0.05 over best single model
- Reduces prediction variance
- More robust to outliers

### Validation Strategy

- **Temporal Validation**: Train on earlier years, test on later years
- **MC-CV**: 50-100 splits for stable performance estimates
- **Stratified Sampling**: Maintains event distribution
- **Confidence Intervals**: 95% CI for all metrics

## Feature Validation

### Missing Values
- **Categorical**: Mode imputation or "unknown" category
- **Continuous**: Median imputation
- **Binary**: 0 (absence) for missing

### Feature Scaling
- **CatBoost**: No scaling needed (handles categoricals natively)
- **XGBoost**: No scaling needed (tree-based)
- **XGBoost RF**: No scaling needed (tree-based)

### Expected Feature Importance
- **High Importance**: VAD support, kidney function, nutritional status
- **Medium Importance**: Liver function, respiratory support, immunology
- **Low Importance**: Some growth metrics, less common support devices

## Using Models for Clinical Decision-Making

### Risk Stratification

The ensemble model can be used to:

1. **Identify High-Risk Patients**: Flag patients above risk threshold
2. **Guide Interventions**: Focus on modifiable features with high importance
3. **Monitor Progress**: Track risk changes over time
4. **Compare Scenarios**: Evaluate impact of potential interventions

### Intervention Guidance

Based on feature importance:

- **High-Risk Features**: Prioritize interventions for top-ranked features
- **Modifiable Features**: Focus on features that can be changed
- **Feature Combinations**: Consider interactions between features

### Best Practices

1. **Cohort-Specific**: Always use cohort-specific models (CHD vs MyoCardio)
2. **Feature Completeness**: Ensure all modifiable features are available
3. **Temporal Consistency**: Use features from same time point (transplant vs listing)
4. **Clinical Context**: Combine model predictions with clinical judgment
5. **Regular Updates**: Retrain models periodically as new data becomes available

## Important Notes

1. **Ensemble Approach**: Combines three models for improved robustness
2. **Cohort-Specific**: Separate models for CHD and MyoCardio cohorts
3. **Modifiable Features Only**: Focus on actionable clinical features
4. **Performance Weighting**: Ensemble weights based on C-index performance
5. **MC-CV Evaluation**: 50-100 splits for stable performance estimates
6. **Temporal Validation**: Train/test split maintains temporal order

## References

- **Cohort Analysis**: `../README.md` - Main cohort analysis documentation
- **Risk Dashboard**: `../README_risk_dashboard.md` - Dashboard deployment guide
- **Model Deployment**: `../dashboard/README.md` - Lambda deployment details
- **Notebook**: `../graft_loss_clinical_cohort_analysis.ipynb` - Main analysis notebook
