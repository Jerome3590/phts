# Cohort Risk Dashboard

Complete implementation of the AWS Lambda/S3-based cohort risk dashboard for pediatric heart transplant graft loss prediction.

## Directory Structure

```
dashboard/
├── lambda/                 # Lambda function code
│   ├── Dockerfile         # Container image definition
│   ├── lambda_function.py # Main Lambda handler
│   ├── requirements.txt   # Python dependencies
│   └── utils/            # Utility modules
│       ├── model_loader.py
│       └── predictor.py
├── frontend/              # Static website files
│   ├── index.html        # Main dashboard page
│   ├── app.js           # Application logic
│   ├── config.js        # API configuration
│   └── styles.css       # Styling
├── scripts/              # Deployment scripts
│   └── deploy.sh        # Main deployment script
└── README.md            # This file
```

## Quick Start

### 1. Prerequisites

- AWS CLI configured with appropriate permissions
- Docker installed
- Python 3.9+ (for local testing)
- Models prepared and uploaded to S3

### 2. Prepare Models

Before deploying, you need to convert R models to Python-compatible format and upload to S3:

```bash
# This script should be created based on your model format
python prepare_models.py --cohort CHD --cohort MyoCardio
```

### 3. Update Configuration

Edit `frontend/config.js` to set your API Gateway URL after deployment.

### 4. Deploy

```bash
# Make deployment script executable
chmod +x scripts/deploy.sh

# Run deployment
./scripts/deploy.sh
```

## Development

### Local Testing

#### Test Lambda Function

```bash
# Build image
cd lambda/
docker build -t graft-loss-cohort-dashboard:latest .

# Run locally with Lambda runtime interface emulator
docker run -p 9000:8080 \
  -e MODELS_BUCKET=uva-graft-loss-cohort-models \
  -e MODELS_PREFIX=models/ \
  graft-loss-cohort-dashboard:latest

# Test endpoint
curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d '{"path": "/metadata", "httpMethod": "GET"}'
```

#### Test Frontend

```bash
# Serve static files
cd frontend/
python -m http.server 8000

# Open http://localhost:8000
# Update config.js to point to local Lambda or API Gateway
```

## Deployment Steps

See [`../docs/README_dashboard_deployment.md`](../docs/README_dashboard_deployment.md) for complete deployment guide.

### Quick Deployment Checklist

1. ✅ Create S3 buckets (models + static site)
2. ✅ Create ECR repository
3. ✅ Create IAM roles and policies
4. ✅ Prepare and upload models to S3
5. ✅ Generate and upload metadata
6. ✅ Build and push Docker image to ECR
7. ✅ Create/update Lambda function
8. ✅ Create API Gateway REST API
9. ✅ Configure API Gateway resources and methods
10. ✅ Deploy API Gateway
11. ✅ Upload frontend to S3
12. ✅ Configure CloudFront (optional)
13. ✅ Update frontend config.js with API URL
14. ✅ Test endpoints

## API Endpoints

- `GET /metadata` - Get feature metadata and model information
- `POST /risk` - Calculate graft loss risk
- `POST /risk/comparison` - Compare risk scenarios

See [`../README_risk_dashboard.md`](../README_risk_dashboard.md) for detailed API documentation.

## Model Requirements

Models must be:
1. Converted to Python-compatible format (pickle, ONNX, or native format)
2. Uploaded to S3: `s3://uva-graft-loss-cohort-models/models/{cohort}/{model_name}.pkl`
3. Accompanied by metadata JSON: `s3://uva-graft-loss-cohort-models/models/metadata.json`

Metadata format:
```json
{
  "cohorts": ["CHD", "MyoCardio"],
  "features": {
    "txcreat_r": {
      "category": "Kidney Function",
      "type": "numeric",
      "range": [0.1, 10.0],
      "modifiability": "Partially Modifiable"
    }
  },
  "models": {
    "CHD": {
      "best_model": "catboost_cox",
      "c_index": 0.85,
      "c_index_ci": [0.82, 0.88]
    }
  }
}
```

## Troubleshooting

### Lambda Timeout
- Increase timeout in Lambda configuration
- Optimize model loading (use caching)
- Consider provisioned concurrency

### Model Loading Errors
- Verify S3 bucket permissions
- Check model file paths
- Verify model format compatibility

### CORS Errors
- Verify CORS headers in API Gateway
- Check browser console for specific errors
- Ensure OPTIONS method is configured

See deployment guide for more troubleshooting tips.

## Security Notes

- API Gateway should have authentication (API keys, IAM, or Cognito)
- S3 buckets should have appropriate bucket policies
- Lambda should have minimal IAM permissions
- Enable encryption for data at rest and in transit
- Consider VPC configuration for Lambda if accessing private resources

## Cost Estimation

- Lambda: ~$0.20 per 1M requests (512MB, 10s timeout)
- API Gateway: ~$3.50 per 1M requests
- S3: ~$0.023 per GB storage
- CloudFront: ~$0.085 per GB data transfer
- Estimated Monthly: $50-200 (depending on usage)

## Next Steps

1. Implement model conversion script (`prepare_models.py`)
2. Generate metadata script (`generate_metadata.py`)
3. Add authentication/authorization
4. Set up CI/CD pipeline
5. Add monitoring and alerting
6. Create API documentation (OpenAPI/Swagger)

