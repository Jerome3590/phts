# PHTS Risk Calculator Dashboard

Interactive web-based risk calculator for Pediatric Heart Transplant Survival (PHTS) graft loss prediction.

## Overview

This dashboard allows clinicians to:
1. Enter patient clinical features
2. Calculate graft loss risk scores
3. View top causal factors from FFA analysis
4. Understand which clinical features drive risk predictions

## Architecture

### Components

1. **Frontend (S3 Static Website)**
   - `phts_dashboard.html` - Interactive web interface
   - Hosted on S3 with static website hosting enabled
   - Communicates with Lambda via API Gateway

2. **Backend (AWS Lambda)**
   - `phts_lambda_function.py` - API handler
   - Loads trained models (CatBoost, XGBoost, XGBoost RF)
   - Computes risk predictions
   - Returns causal factors from FFA analysis

3. **Data Storage (S3)**
   - Models: `s3://bucket/models/{cohort}/`
   - Dashboard data: `s3://bucket/dashboard_data/{cohort}/dashboard_data.json`

## Deployment

### Prerequisites

- AWS CLI configured
- Models trained and saved to `calculator/outputs/models/`
- Dashboard data generated: `calculator/outputs/shap_ffa/`

### Quick Deploy

```bash
cd graft-loss/cohort_analysis/calculator/risk_dashboard
chmod +x deploy_phts_dashboard.sh
./deploy_phts_dashboard.sh
```

### Manual Deployment

#### 1. Deploy Frontend to S3

```bash
# Create bucket
aws s3 mb s3://phts-calculator-dashboard

# Upload HTML
aws s3 cp phts_dashboard.html s3://phts-calculator-dashboard/index.html \
    --content-type "text/html"

# Enable static website hosting
aws s3 website s3://phts-calculator-dashboard \
    --index-document index.html

# Set public read access
aws s3api put-bucket-policy --bucket phts-calculator-dashboard \
    --policy file://bucket-policy.json
```

#### 2. Deploy Lambda Function

```bash
# Package Lambda function
zip -r lambda-deployment.zip phts_lambda_function.py

# Create Lambda function
aws lambda create-function \
    --function-name phts-risk-calculator \
    --runtime python3.11 \
    --role arn:aws:iam::ACCOUNT:role/phts-lambda-role \
    --handler phts_lambda_function.lambda_handler \
    --zip-file fileb://lambda-deployment.zip \
    --timeout 60 \
    --memory-size 3008 \
    --environment Variables="{PHTS_BUCKET=phts-calculator-dashboard}"
```

#### 3. Upload Models and Data

```bash
# Upload models
aws s3 sync ../outputs/models/ s3://phts-calculator-dashboard/models/

# Upload dashboard data
aws s3 sync ../outputs/shap_ffa/ s3://phts-calculator-dashboard/dashboard_data/
```

#### 4. Create API Gateway

```bash
# Create REST API
aws apigateway create-rest-api --name phts-calculator-api

# Create resource and method
# (Use AWS Console or CloudFormation for full setup)
```

## Configuration

### Environment Variables

- `PHTS_BUCKET`: S3 bucket name (default: `phts-calculator`)
- `MODEL_BASE_PATH`: Path to models in container (default: `/var/task/models`)
- `DASHBOARD_DATA_PATH`: Path to dashboard data (default: `/var/task/dashboard_data`)

### Lambda Function Settings

- **Runtime**: Python 3.11
- **Memory**: 3008 MB (for large models)
- **Timeout**: 60 seconds
- **Handler**: `phts_lambda_function.lambda_handler`

### Frontend Configuration

Update `LAMBDA_API_URL` in `phts_dashboard.html`:

```javascript
const LAMBDA_API_URL = 'https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod';
```

## API Endpoints

### GET /metadata

Returns available cohorts and causal factors.

**Query Parameters:**
- `cohort` (optional): Specific cohort to get data for

**Response:**
```json
{
  "available_cohorts": ["CHD", "Combined", "Myocardio"],
  "causal_factors_by_cohort": {
    "Combined": {
      "top_causal_factors": [...],
      "summary": {...}
    }
  }
}
```

### POST /risk

Calculate risk score from clinical features.

**Request Body:**
```json
{
  "cohort": "Combined",
  "features": {
    "egfr_tx": 60.0,
    "txbun_r": 20.0,
    "ltxtrach": 1,
    ...
  },
  "use_ensemble": false
}
```

**Response:**
```json
{
  "cohort": "Combined",
  "risk_score": 0.456,
  "risk_band": "medium",
  "model_info": {
    "model_used": "xgboost",
    "models_used": ["xgboost"],
    "ensemble": false
  },
  "top_causal_factors": [...],
  "timestamp": 1234567890
}
```

### POST /causal

Get causal factor explanations.

**Request Body:**
```json
{
  "cohort": "Combined",
  "top_k": 10
}
```

**Response:**
```json
{
  "cohort": "Combined",
  "top_causal_factors": [...],
  "summary": {...}
}
```

## Clinical Features

The dashboard accepts the following clinical features:

### Kidney Function
- `egfr_tx`: eGFR at transplant (mL/min/1.73m²)
- `txbun_r`: BUN at transplant (mg/dL)
- `txcreat_r`: Creatinine at transplant (mg/dL)

### Cardiac Support
- `ltxtrach`: Left Ventricular Assist Device (LVAD) - binary
- `txecmo`: ECMO at transplant - binary
- `txnomcsd`: Mechanical Circulatory Support Device - binary

### Diagnosis & Demographics
- `chd_papvr`: CHD: Partial Anomalous Pulmonary Venous Return - binary
- `chd_anom`: CHD: Anomaly - binary
- `donisch`: Donor Ischemic Time (hours)

### Lab Values
- `txsa_r`: Serum Albumin at transplant (g/dL)
- `txast`: AST at transplant (U/L)

## Risk Bands

- **Low**: Risk score < 0.3
- **Medium**: Risk score 0.3 - 0.7
- **High**: Risk score > 0.7

## Causal Factors

Top causal factors are displayed based on FFA analysis results:
- Feature name
- Causal responsibility score
- SHAP importance
- Rule frequency (if available)

## Troubleshooting

### Lambda Timeout

If Lambda times out:
1. Increase timeout to 60+ seconds
2. Increase memory (more memory = faster CPU)
3. Use model caching (already implemented)
4. Consider using Lambda Container Images for larger models

### Model Loading Errors

If models fail to load:
1. Verify models are uploaded to S3
2. Check IAM permissions for S3 access
3. Verify model file paths in Lambda code
4. Check Lambda logs in CloudWatch

### CORS Errors

If you see CORS errors:
1. Verify API Gateway CORS settings
2. Check Lambda response headers include CORS headers
3. Verify frontend URL matches allowed origins

## Security Considerations

1. **Public Access**: S3 bucket is public for static website hosting
2. **API Security**: Consider adding API keys or authentication
3. **Data Privacy**: Ensure no PHI is logged or stored
4. **HTTPS**: Use CloudFront for HTTPS access

## Cost Optimization

1. **Lambda**: Use provisioned concurrency for consistent performance
2. **S3**: Enable lifecycle policies for old model versions
3. **API Gateway**: Use caching for metadata endpoints
4. **CloudFront**: Cache static assets

## Next Steps

1. Add authentication/authorization
2. Implement CloudFront for HTTPS
3. Add more clinical features
4. Add risk visualization charts
5. Export results to PDF/CSV
6. Add patient comparison features
