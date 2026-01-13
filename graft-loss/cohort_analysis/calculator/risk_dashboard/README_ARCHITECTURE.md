# PHTS Risk Calculator - Architecture

## Overview

The PHTS Risk Calculator uses a **serverless architecture** with static frontend hosting and container-based backend processing. This architecture provides scalability, cost-effectiveness, and ease of deployment.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    User's Browser                            │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  phts_dashboard.html (S3 Static Website)             │  │
│  │                                                       │  │
│  │  Features:                                            │  │
│  │  - Risk Calculator Tab                                │  │
│  │  - Causal Analysis Tab (with Chart.js)               │  │
│  │  - Real-time risk updates                             │  │
│  │  - Interactive factor controls                        │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ HTTPS (CORS enabled)
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  API Gateway (REST API)                     │
│                                                              │
│  Endpoints:                                                  │
│  - GET  /metadata  → Returns cohorts & causal factors      │
│  - POST /risk      → Calculates risk score                  │
│  - POST /causal    → Returns causal factor explanations    │
│  - OPTIONS /*      → CORS preflight                         │
│                                                              │
│  Features:                                                  │
│  - Lambda proxy integration                                 │
│  - CORS handling                                            │
│  - Request/response transformation                          │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Invokes
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              Lambda Function (Container)                    │
│                                                              │
│  Container Contents:                                         │
│  - Python 3.11 runtime                                      │
│  - Model libraries (CatBoost, XGBoost, NumPy, Pandas)     │
│  - Lambda function code (phts_lambda_function.py)          │
│  - Models (baked in at /var/task/models/)                  │
│  - Dashboard data (baked in at /var/task/dashboard_data/)  │
│  - Risk distributions (baked in at /var/task/risk_distributions/) │
│                                                              │
│  Configuration:                                             │
│  - Memory: 3008 MB                                          │
│  - Timeout: 60 seconds                                      │
│  - Handler: phts_lambda_function.lambda_handler             │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ (Fallback)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    S3 Bucket                                 │
│                                                              │
│  Storage:                                                    │
│  - Static HTML (jerome-dixon.io/uva/phts-risk-calculator/) │
│  - Models (fallback: models/{cohort}/)                     │
│  - Dashboard data (fallback: dashboard_data/{cohort}/)     │
│  - Risk distributions (fallback: risk_distributions/)     │
└─────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Frontend (S3 Static Website)

**Location:** `s3://jerome-dixon.io/uva/phts-risk-calculator/index.html`

**Technology:**
- Pure HTML/CSS/JavaScript (no build step)
- Chart.js (CDN) for visualizations
- Fetch API for HTTP requests

**Features:**
- **Risk Calculator Tab**: Form inputs, risk calculation, causal factors display
- **Causal Analysis Tab**: Interactive visualizations, factor controls, risk comparison
- Real-time API communication
- Baseline value loading
- Error handling and user feedback

**Communication:**
- Makes HTTP requests to API Gateway
- Handles CORS automatically
- Updates UI based on API responses

---

### 2. API Gateway

**Type:** REST API

**Endpoints:**

#### GET /metadata
- Returns available cohorts
- Returns causal factors for each cohort
- Returns API configuration
- Query parameter: `cohort` (optional)

#### POST /risk
- Calculates risk score from clinical features
- Returns normalized percentile, raw score, risk band
- Returns top causal factors
- Request body: `{cohort, features, use_ensemble}`

#### POST /causal
- Returns causal factor explanations
- Request body: `{cohort, top_k}`

**Integration:**
- Lambda proxy integration (passes full event to Lambda)
- CORS enabled for all methods
- OPTIONS methods for preflight requests

---

### 3. Lambda Function

**Type:** Container image (Docker)

**Base Image:** `public.ecr.aws/lambda/python:3.11`

**Container Structure:**
```
/var/task/
├── phts_lambda_function.py          # Main handler
├── models/                           # Baked-in models
│   ├── CHD/
│   │   ├── catboost_model.cbm
│   │   ├── xgboost_model.ubj
│   │   ├── xgboost_rf_model.ubj
│   │   ├── best_model.txt
│   │   └── final_model_json/
│   ├── Combined/
│   └── Myocardio/
├── dashboard_data/                   # Baked-in causal factors
│   ├── CHD/
│   │   ├── dashboard_data.json
│   │   └── top_causal_factors.csv
│   ├── Combined/
│   └── Myocardio/
└── risk_distributions/               # Baked-in distributions
    └── risk_distributions.json
```

**Dependencies:**
- `catboost` (with native categorical support)
- `xgboost` (survival models)
- `numpy`, `pandas` (data processing)
- `boto3` (S3 fallback)

**Model Loading Strategy:**
1. **Primary**: Load from container filesystem (`/var/task/models/`)
2. **Fallback**: Load from S3 if not found in container
3. **Caching**: Models cached in memory after first load

**Request Flow:**
1. Receive event from API Gateway
2. Extract method, path, and body
3. Route to appropriate handler (`handle_metadata`, `handle_risk`, `handle_causal`)
4. Load models/data (from container or S3)
5. Process request
6. Return response with CORS headers

---

### 4. Data Storage

#### ECR (Elastic Container Registry)
- Stores Docker images
- Image size: ~2.5 GB (includes models and dependencies)
- Versioning: Tagged as `latest`

#### S3 (Simple Storage Service)
- **Static Website**: HTML file
- **Models**: Fallback storage (if not in container)
- **Dashboard Data**: Fallback storage
- **Risk Distributions**: Fallback storage

---

## Request Flow

### Example: Calculate Risk

```
1. User enters clinical features in browser
   ↓
2. JavaScript collects form values
   ↓
3. POST request to API Gateway /risk endpoint
   POST https://API_ID.execute-api.REGION.amazonaws.com/prod/risk
   Body: {cohort: "Combined", features: {...}}
   ↓
4. API Gateway validates request and forwards to Lambda
   ↓
5. Lambda handler extracts event data
   ↓
6. Lambda loads model (from container or S3)
   ↓
7. Lambda prepares feature vector
   ↓
8. Lambda generates prediction
   ↓
9. Lambda normalizes risk score (percentile conversion)
   ↓
10. Lambda loads causal factors
   ↓
11. Lambda returns response with CORS headers
    {
      risk_score: 75.5,      // Normalized percentile
      raw_score: 2.345,      // Original prediction
      percentile: 75.5,      // Percentile rank
      risk_band: "high",     // Risk category
      top_causal_factors: [...]
    }
   ↓
12. API Gateway adds CORS headers and returns to browser
   ↓
13. JavaScript updates UI with results
```

---

## Data Flow

### Model Training → Deployment

```
Training Pipeline
  ↓
Models saved to: calculator/outputs/models/
  ↓
prepare_lambda_dir_phts.py copies to: lambda_dir_phts/models/
  ↓
Dockerfile copies to: /var/task/models/ (in container)
  ↓
Docker image pushed to: ECR
  ↓
Lambda function uses: Container filesystem (fast) or S3 (fallback)
```

### Causal Analysis → Dashboard

```
FFA Analysis
  ↓
Results saved to: calculator/outputs/shap_ffa/{cohort}/dashboard_data.json
  ↓
prepare_lambda_dir_phts.py copies to: lambda_dir_phts/dashboard_data/
  ↓
Dockerfile copies to: /var/task/dashboard_data/ (in container)
  ↓
Lambda loads and returns via /causal endpoint
  ↓
Frontend displays in Causal Analysis tab
```

---

## CORS Configuration

Since the HTML is on S3 and API is on API Gateway (different origins), CORS is required:

**Lambda Response Headers:**
```python
{
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token",
    "Access-Control-Max-Age": "3600",
    "Access-Control-Allow-Credentials": "false"
}
```

**Browser Preflight (OPTIONS):**
- API Gateway handles OPTIONS requests
- Returns CORS headers before actual request
- Browser validates and proceeds with actual request

---

## Security Architecture

### Current Configuration

1. **S3 Bucket**: Public read access for static website
2. **API Gateway**: Public access (no authentication)
3. **Lambda**: IAM role with least-privilege permissions
4. **CORS**: Allows all origins (`*`)

### Production Recommendations

1. **Restrict CORS**: Change to specific domain
   ```python
   "Access-Control-Allow-Origin": "https://jerome-dixon.io"
   ```

2. **API Authentication**: Add API keys or Cognito authentication

3. **Rate Limiting**: Configure throttling in API Gateway

4. **HTTPS**: Use CloudFront or API Gateway custom domain

5. **VPC**: Deploy Lambda in VPC if needed for private resources

---

## Scalability

### Lambda Scaling

- **Automatic**: Scales based on request volume
- **Concurrent Executions**: Up to account limit (default: 1000)
- **Cold Starts**: ~5-10 seconds (models loaded on first invocation)
- **Warm Starts**: ~100-500ms (models cached in memory)

### Performance Optimization

1. **Model Caching**: Models cached in memory after first load
2. **Container Images**: Models baked in (no S3 download needed)
3. **Provisioned Concurrency**: Eliminates cold starts (costs more)
4. **Memory Allocation**: 3008 MB provides faster CPU

---

## Monitoring

### CloudWatch Logs

- **Log Group**: `/aws/lambda/phts-risk-calculator`
- **Log Streams**: One per invocation
- **Retention**: 30 days (configurable)

### CloudWatch Metrics

- **Invocations**: Number of requests
- **Duration**: Execution time
- **Errors**: Failed invocations
- **Throttles**: Rate limit hits

### Custom Metrics

- Model loading time
- Prediction latency
- Error rates by cohort

---

## Cost Structure

### Lambda

- **Compute**: $0.0000166667 per GB-second
- **Requests**: $0.20 per 1M requests
- **Example**: 1000 requests/day, 2GB memory, 1s duration = ~$0.03/day

### API Gateway

- **REST API**: $3.50 per million requests
- **Data Transfer**: $0.09 per GB

### S3

- **Storage**: $0.023 per GB/month
- **Requests**: $0.005 per 1000 GET requests

### ECR

- **Storage**: $0.10 per GB/month
- **Data Transfer**: Free within same region

**Estimated Monthly Cost**: ~$10-20 for moderate usage

---

## Disaster Recovery

### Backup Strategy

1. **Models**: Versioned in ECR (tagged images)
2. **Code**: Versioned in Git
3. **Configuration**: Stored in deployment scripts

### Recovery Procedure

1. **Lambda**: Rollback to previous ECR image
2. **API Gateway**: Restore from CloudFormation/SAM template
3. **S3**: Restore from versioning (if enabled)
4. **HTML**: Restore from Git

---

## Future Enhancements

1. **CloudFront**: CDN for faster global access
2. **Custom Domain**: `phts.jerome-dixon.io`
3. **Authentication**: Cognito or API keys
4. **Monitoring**: X-Ray tracing, custom dashboards
5. **CI/CD**: Automated deployment pipeline
6. **Multi-Region**: Deploy to multiple regions for redundancy

---

## References

- [AWS Lambda Container Images](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)
- [API Gateway REST API](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-rest-api.html)
- [S3 Static Website Hosting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
- [CORS in API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-cors.html)

---

**Last Updated**: 2026-01-13  
**Architecture Version**: 1.0
