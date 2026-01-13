# PHTS Risk Calculator Deployment Notes

## S3 Location

**Bucket**: `jerome-dixon.io`  
**Prefix**: `uva/phts-risk-calculator/`

**Full S3 Path**: `s3://jerome-dixon.io/uva/phts-risk-calculator/`

## Directory Structure

```
s3://jerome-dixon.io/uva/phts-risk-calculator/
├── index.html                    # Main dashboard HTML
├── models/
│   ├── CHD/
│   │   ├── catboost_model.cbm
│   │   ├── xgboost_model.ubj
│   │   ├── xgboost_rf_model.ubj
│   │   ├── best_model.txt
│   │   └── final_model_json/
│   ├── Combined/
│   └── Myocardio/
└── dashboard_data/
    ├── CHD/
    │   └── dashboard_data.json
    ├── Combined/
    │   └── dashboard_data.json
    └── Myocardio/
        └── dashboard_data.json
```

## Deployment Steps

### 1. Prepare Models and Data

```bash
cd graft-loss/cohort_analysis/calculator/risk_dashboard
python prepare_models_for_lambda.py
```

This creates a `lambda_deploy/` directory with all necessary files.

### 2. Upload to S3

```bash
# Upload dashboard HTML
aws s3 cp phts_dashboard.html \
    s3://jerome-dixon.io/uva/phts-risk-calculator/index.html \
    --content-type "text/html"

# Upload models
aws s3 sync lambda_deploy/models/ \
    s3://jerome-dixon.io/uva/phts-risk-calculator/models/

# Upload dashboard data
aws s3 sync lambda_deploy/dashboard_data/ \
    s3://jerome-dixon.io/uva/phts-risk-calculator/dashboard_data/
```

### 3. Configure S3 Static Website Hosting

If the bucket already has website hosting configured, you may need to:

1. Go to S3 Console → `jerome-dixon.io` bucket
2. Properties → Static website hosting
3. Set index document to: `uva/phts-risk-calculator/index.html`
4. Set error document to: `uva/phts-risk-calculator/index.html`

### 4. Update Lambda Function

Update the Lambda function environment variables:

```bash
aws lambda update-function-configuration \
    --function-name phts-risk-calculator \
    --environment Variables="{PHTS_BUCKET=jerome-dixon.io,S3_PREFIX=uva/phts-risk-calculator}"
```

### 5. Update Frontend API URL

Edit `phts_dashboard.html` and update the `LAMBDA_API_URL`:

```javascript
const LAMBDA_API_URL = 'https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod';
```

Then re-upload:

```bash
aws s3 cp phts_dashboard.html \
    s3://jerome-dixon.io/uva/phts-risk-calculator/index.html \
    --content-type "text/html"
```

## Access URLs

### S3 Website Endpoint (if enabled)
```
http://jerome-dixon.io.s3-website-REGION.amazonaws.com/uva/phts-risk-calculator/
```

### CloudFront (Recommended for HTTPS)
If you have CloudFront configured for `jerome-dixon.io`:
```
https://jerome-dixon.io/uva/phts-risk-calculator/
```

### Direct S3 Access
```
https://jerome-dixon.io.s3.amazonaws.com/uva/phts-risk-calculator/index.html
```

## Lambda Function Configuration

**Environment Variables:**
- `PHTS_BUCKET`: `jerome-dixon.io`
- `S3_PREFIX`: `uva/phts-risk-calculator`
- `MODEL_BASE_PATH`: `/var/task/models` (for container images)
- `DASHBOARD_DATA_PATH`: `/var/task/dashboard_data` (for container images)

**S3 Paths Used by Lambda:**
- Models: `s3://jerome-dixon.io/uva/phts-risk-calculator/models/{cohort}/`
- Dashboard Data: `s3://jerome-dixon.io/uva/phts-risk-calculator/dashboard_data/{cohort}/dashboard_data.json`

## IAM Permissions

The Lambda function needs the following S3 permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::jerome-dixon.io/uva/phts-risk-calculator/*",
        "arn:aws:s3:::jerome-dixon.io"
      ],
      "Condition": {
        "StringLike": {
          "s3:prefix": "uva/phts-risk-calculator/*"
        }
      }
    }
  ]
}
```

## Quick Deploy Script

Use the automated deployment script:

```bash
export PHTS_BUCKET=jerome-dixon.io
export S3_PREFIX=uva/phts-risk-calculator
./deploy_phts_dashboard.sh
```

## Testing

After deployment, test the dashboard:

1. Open the dashboard URL
2. Select a cohort (e.g., "Combined")
3. Enter clinical feature values
4. Click "Calculate Risk"
5. Verify risk score and causal factors are displayed

## Troubleshooting

### Dashboard not loading
- Check S3 bucket permissions (public read for HTML)
- Verify index.html is at correct path
- Check CloudFront cache (if using CloudFront)

### Lambda errors
- Check CloudWatch logs for Lambda function
- Verify S3 paths in environment variables
- Ensure models are uploaded to correct S3 location
- Check IAM permissions for S3 access

### API errors
- Verify API Gateway endpoint URL in HTML
- Check CORS configuration in API Gateway
- Ensure Lambda function is deployed and configured
