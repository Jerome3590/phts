# Cohort Risk Dashboard

**Production-ready risk assessment dashboard** for pediatric heart transplant graft loss prediction using cohort-specific models and modifiable clinical features.

## Quick Overview

The dashboard provides two main capabilities:

1. **Risk Assessment Dashboard** - Predict graft loss risk for CHD or MyoCardio cohorts using modifiable clinical features
2. **Risk Comparison Tool** - Compare risk scenarios by adjusting modifiable clinical features

## Core Components

- **`index.html`** - Frontend dashboard (HTML/JavaScript)
- **`lambda_function.py`** - AWS Lambda handler (API endpoints)
- **`prepare_models.py`** - Package R models for Lambda deployment (converts to Python-compatible format)
- **`generate_metadata.py`** - Extract valid feature ranges and categories for dropdowns
- **`Dockerfile`** - Container image for Lambda (ECR)
- **`requirements.txt`** - Python dependencies (including R runtime via rpy2 or converted models)

## Architecture

```
User Browser → S3 Static Site → API Gateway → Lambda (ECR) → Models/Data (S3)
```

### Data Flow

1. **Frontend (S3)**: Static HTML/JS dashboard served from S3
2. **API Gateway**: Routes requests to Lambda function
3. **Lambda (ECR)**: Loads cohort-specific models and makes predictions
4. **S3 Data**: Model files and metadata stored in `s3://uva-private-data-lake/graft-loss/cohort_analysis/models/`

## Key Features

- **Cohort-Specific Models**: Separate models for CHD and MyoCardio cohorts
- **Modifiable Clinical Features**: Focus on actionable features (renal, liver, nutrition, respiratory, cardiac, immunology)
- **Multiple Model Support**: RSF, AORSF, CatBoost-Cox, XGBoost-Cox, XGBoost-Cox RF
- **Best Model Selection**: Automatically uses best-performing model per cohort (by C-index)
- **Risk Stratification**: Provides risk scores with confidence intervals
- **Feature Importance**: Shows which modifiable features drive risk predictions

## Modifiable Clinical Features

The dashboard focuses on **clinically actionable features** organized by category:

### Kidney Function
- Creatinine (tx, listing)
- Dialysis history
- Renal insufficiency history
- eGFR

### Liver Function
- AST/ALT (tx, listing)
- Direct/Total bilirubin (tx, listing)
- Fontan liver disease history

### Nutrition
- Albumin (tx, listing)
- Protein levels
- Failure to thrive history
- BMI, height, weight (tx, listing)

### Respiratory
- Ventilation status (tx, listing)
- Tracheostomy history

### Cardiac Support
- VAD support (tx, listing)
- ECMO support (tx, listing)
- MCSD consideration
- CPR/Shock history

### Immunology
- HLA pre-sensitization
- Crossmatch status
- PRA levels (tx, listing)

## API Endpoints

### `GET /metadata`
Get valid feature ranges, categories, and model information.

**Response:**
```json
{
  "cohorts": ["CHD", "MyoCardio"],
  "features": {
    "txcreat_r": {
      "category": "Kidney Function",
      "type": "numeric",
      "range": [0.1, 10.0],
      "modifiability": "Partially Modifiable"
    },
    ...
  },
  "models": {
    "CHD": {
      "best_model": "CatBoost-Cox",
      "c_index": 0.85,
      "c_index_ci": [0.82, 0.88]
    },
    "MyoCardio": {
      "best_model": "XGBoost-Cox",
      "c_index": 0.87,
      "c_index_ci": [0.84, 0.90]
    }
  }
}
```

### `POST /risk`
Calculate graft loss risk for a patient.

**Request:**
```json
{
  "cohort": "CHD",
  "features": {
    "txcreat_r": 1.2,
    "txpalb_r": 3.5,
    "txvent": 0,
    "txvad": 1,
    ...
  }
}
```

**Response:**
```json
{
  "cohort": "CHD",
  "model": "CatBoost-Cox",
  "risk_score": 0.35,
  "risk_percentile": 65,
  "confidence_interval": [0.28, 0.42],
  "feature_contributions": {
    "txvad": 0.12,
    "txcreat_r": 0.08,
    "txpalb_r": -0.05,
    ...
  },
  "recommendations": [
    "Consider VAD optimization",
    "Monitor kidney function",
    "Optimize nutritional support"
  ]
}
```

### `POST /risk/comparison`
Compare risk scenarios by adjusting features.

**Request:**
```json
{
  "cohort": "CHD",
  "baseline_features": {
    "txcreat_r": 1.5,
    "txpalb_r": 3.0,
    ...
  },
  "intervention_features": {
    "txcreat_r": 1.2,
    "txpalb_r": 3.5,
    ...
  }
}
```

**Response:**
```json
{
  "baseline_risk": 0.42,
  "intervention_risk": 0.35,
  "risk_reduction": 0.07,
  "relative_risk_reduction": 16.7,
  "feature_changes": {
    "txcreat_r": {"baseline": 1.5, "intervention": 1.2, "impact": -0.04},
    "txpalb_r": {"baseline": 3.0, "intervention": 3.5, "impact": -0.03}
  }
}
```

## Quick Start

### 1. Prepare Models for Deployment

```bash
# Convert R models to Python-compatible format
python prepare_models.py --cohort CHD --cohort MyoCardio

# This will:
# - Load models from outputs/
# - Convert to ONNX or pickle format
# - Upload to S3: s3://uva-private-data-lake/graft-loss/cohort_analysis/models/
```

### 2. Generate Metadata

```bash
# Extract feature ranges and valid values
python generate_metadata.py --output metadata.json

# Upload to S3
aws s3 cp metadata.json s3://uva-private-data-lake/graft-loss/cohort_analysis/metadata/
```

### 3. Build Docker Container

```bash
# Build Lambda container image
docker build -t graft-loss-cohort-dashboard:latest .

# Tag for ECR
docker tag graft-loss-cohort-dashboard:latest \
  <account-id>.dkr.ecr.<region>.amazonaws.com/graft-loss-cohort-dashboard:latest
```

### 4. Deploy to AWS

```bash
# Push to ECR
aws ecr get-login-password --region <region> | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com
docker push <account-id>.dkr.ecr.<region>.amazonaws.com/graft-loss-cohort-dashboard:latest

# Deploy Lambda function (see deployment guide)
./deploy.sh
```

## Deployment Guide

See [`docs/cohort_analysis/README_dashboard_deployment.md`](../docs/cohort_analysis/README_dashboard_deployment.md) for complete deployment instructions including:

- **Architecture Setup**: VPC, IAM roles, S3 buckets
- **Lambda Configuration**: Memory, timeout, environment variables
- **API Gateway Setup**: CORS, authentication, rate limiting
- **S3 Static Site**: CloudFront distribution, custom domain
- **Security**: IAM policies, encryption, access controls
- **Monitoring**: CloudWatch logs, metrics, alarms

## Model Information

### Model Performance (from MC-CV)

Models are evaluated using Monte Carlo Cross-Validation with 50-100 splits:

- **CHD Cohort Best Model**: Typically CatBoost-Cox or XGBoost-Cox
  - C-index: ~0.80-0.85 (95% CI)
  - Features: Top modifiable clinical features vary by model

- **MyoCardio Cohort Best Model**: Typically XGBoost-Cox or RSF
  - C-index: ~0.82-0.87 (95% CI)
  - Features: Different feature importance patterns than CHD

### Model Storage

Models are stored in S3:
```
s3://uva-private-data-lake/graft-loss/cohort_analysis/models/
├── CHD/
│   ├── catboost_cox.model
│   ├── xgboost_cox.model
│   └── metadata.json
└── MyoCardio/
    ├── xgboost_cox.model
    ├── rsf.model
    └── metadata.json
```

## Development

### Local Testing

```bash
# Start local API server
python -m flask run --port 5000

# Or use Lambda runtime interface emulator
docker run -p 9000:8080 graft-loss-cohort-dashboard:latest
```

### Frontend Development

```bash
# Serve static files locally
cd frontend/
python -m http.server 8000

# Open http://localhost:8000
```

## Security Considerations

- **Authentication**: API Gateway with IAM or API keys
- **Encryption**: All data encrypted in transit (HTTPS) and at rest (S3 SSE)
- **Access Control**: IAM policies restrict S3 bucket access
- **PHI Handling**: No patient identifiers stored; only aggregated risk scores
- **Audit Logging**: CloudWatch logs all API requests

## Monitoring

- **CloudWatch Metrics**: Request count, latency, error rate
- **CloudWatch Logs**: Lambda execution logs, API Gateway access logs
- **Alarms**: Set up for high error rates or latency spikes
- **Dashboard**: CloudWatch dashboard for real-time monitoring

## Cost Estimation

- **Lambda**: ~$0.20 per 1M requests (assuming 512MB, 10s timeout)
- **API Gateway**: ~$3.50 per 1M requests
- **S3**: ~$0.023 per GB storage + $0.005 per 1K requests
- **CloudFront**: ~$0.085 per GB data transfer
- **Estimated Monthly Cost**: ~$50-200 depending on usage

## Support

For issues or questions:
- **Documentation**: See `docs/cohort_analysis/` for detailed guides
- **Model Questions**: Check `graft_loss_clinical_cohort_analysis.ipynb` notebook
- **Deployment Issues**: See deployment guide in `docs/cohort_analysis/README_dashboard_deployment.md`
