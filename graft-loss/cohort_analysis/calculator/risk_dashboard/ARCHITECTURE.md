# PHTS Dashboard Architecture: S3 + Lambda Interaction

## Overview

The PHTS Risk Calculator uses a **serverless architecture** where:
- **Frontend (HTML/JS)** is hosted on S3 as a static website
- **Backend (Lambda)** processes API requests via API Gateway
- **Communication** happens via HTTP REST API calls

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    User's Browser                            │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  phts_dashboard.html (S3 Static Website)             │  │
│  │                                                       │  │
│  │  JavaScript:                                         │  │
│  │  - Collects form inputs                              │  │
│  │  - Makes fetch() calls to API Gateway                │  │
│  │  - Displays results                                  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ HTTPS
                          │ (CORS enabled)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  API Gateway (REST API)                     │
│                                                              │
│  Endpoints:                                                  │
│  - GET  /metadata  → Returns cohorts & causal factors      │
│  - POST /risk      → Calculates risk score                  │
│  - POST /causal    → Returns causal factor explanations    │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Invokes
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              Lambda Function (Container)                    │
│                                                              │
│  - Loads models from /var/task/models/ (baked in)           │
│  - Loads dashboard data from /var/task/dashboard_data/      │
│  - Processes requests                                       │
│  - Returns JSON responses                                   │
└─────────────────────────────────────────────────────────────┘
```

## Request Flow

### 1. User Opens Dashboard

```
User → S3 Website URL
     → Downloads index.html
     → Browser renders HTML/JS
```

**S3 URL**: `https://jerome-dixon.io/uva/phts-risk-calculator/index.html`

### 2. User Enters Data and Clicks "Calculate Risk"

**JavaScript Code** (in `phts_dashboard.html`):

```javascript
async function calculateRisk() {
  const cohort = getCohort();  // e.g., "Combined"
  const features = collectFeatures();  // {egfr_tx: 60.0, ...}
  
  // Make HTTP request to API Gateway
  const response = await fetch(`${LAMBDA_API_URL}/risk`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      cohort: cohort,
      features: features,
      use_ensemble: false
    })
  });
  
  const data = await response.json();
  displayResults(data);  // Update UI with results
}
```

**HTTP Request**:
```
POST https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/prod/risk
Content-Type: application/json

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

### 3. API Gateway Receives Request

API Gateway:
- Validates request
- Forwards to Lambda function
- Handles CORS headers
- Manages authentication (if configured)

### 4. Lambda Function Processes Request

**Lambda Handler** (`phts_lambda_function.py`):

```python
def lambda_handler(event, context):
    method = event.get("httpMethod")  # "POST"
    path = event.get("path")          # "/risk"
    body = json.loads(event.get("body", "{}"))
    
    if method == "POST" and path.endswith("/risk"):
        return handle_risk(event)
    
def handle_risk(event):
    body = json.loads(event.get("body", "{}"))
    cohort = body.get("cohort")
    features = body.get("features")
    
    # Load model from container filesystem
    model = load_model(cohort, "xgboost")
    
    # Predict risk
    result = predict_risk_survival(cohort, features)
    
    # Load causal factors
    dashboard_data = load_dashboard_data(cohort)
    
    # Return response
    return _response(200, {
        "risk_score": result['risk_score'],
        "risk_band": "medium",
        "top_causal_factors": dashboard_data['top_causal_factors']
    })
```

**Lambda Response**:
```python
{
    "statusCode": 200,
    "headers": {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",  # CORS
        "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type"
    },
    "body": json.dumps({
        "cohort": "Combined",
        "risk_score": 0.456,
        "risk_band": "medium",
        "top_causal_factors": [...]
    })
}
```

### 5. API Gateway Returns Response

API Gateway:
- Receives Lambda response
- Adds CORS headers
- Returns to browser

**HTTP Response**:
```
HTTP/1.1 200 OK
Content-Type: application/json
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET,POST,OPTIONS

{
  "cohort": "Combined",
  "risk_score": 0.456,
  "risk_band": "medium",
  "top_causal_factors": [...]
}
```

### 6. Browser Updates UI

**JavaScript** updates the page:
```javascript
function displayResults(data) {
  // Update risk score
  document.getElementById('risk-value').textContent = data.risk_score.toFixed(3);
  document.getElementById('risk-band').textContent = data.risk_band.toUpperCase();
  
  // Display causal factors
  data.top_causal_factors.forEach((factor, index) => {
    // Create and append factor elements
  });
}
```

## CORS (Cross-Origin Resource Sharing)

Since the HTML is on S3 and API is on API Gateway (different origins), CORS is required:

**Lambda Response Headers**:
```python
"Access-Control-Allow-Origin": "*"  # Allows S3 website
"Access-Control-Allow-Methods": "GET,POST,OPTIONS"
"Access-Control-Allow-Headers": "Content-Type"
```

**Browser Preflight** (OPTIONS request):
```
OPTIONS /risk
Origin: https://jerome-dixon.io
Access-Control-Request-Method: POST
```

## API Endpoints

### GET /metadata

**Request** (from browser):
```javascript
fetch(`${LAMBDA_API_URL}/metadata?cohort=Combined`)
```

**Response**:
```json
{
  "cohort": "Combined",
  "available_cohorts": ["CHD", "Combined", "Myocardio"],
  "causal_factors": [...],
  "summary": {...}
}
```

### POST /risk

**Request** (from browser):
```javascript
fetch(`${LAMBDA_API_URL}/risk`, {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    cohort: "Combined",
    features: {...}
  })
})
```

**Response**:
```json
{
  "cohort": "Combined",
  "risk_score": 0.456,
  "risk_band": "medium",
  "model_info": {...},
  "top_causal_factors": [...]
}
```

### POST /causal

**Request** (from browser):
```javascript
fetch(`${LAMBDA_API_URL}/causal`, {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    cohort: "Combined",
    top_k: 10
  })
})
```

## Configuration

### Frontend (HTML)

Update `LAMBDA_API_URL` in `phts_dashboard.html`:

```javascript
const LAMBDA_API_URL = 'https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod';
```

### API Gateway Setup

1. **Create REST API**
2. **Create Resources** (`/metadata`, `/risk`, `/causal`)
3. **Create Methods** (GET for `/metadata`, POST for `/risk` and `/causal`)
4. **Integrate with Lambda** (Lambda Proxy Integration)
5. **Enable CORS** (or rely on Lambda CORS headers)
6. **Deploy API** to a stage (e.g., `prod`)

### Lambda Function

- **Handler**: `phts_lambda_function.lambda_handler`
- **Timeout**: 60 seconds
- **Memory**: 3008 MB
- **Environment Variables**:
  - `PHTS_BUCKET`: `jerome-dixon.io`
  - `S3_PREFIX`: `uva/phts-risk-calculator`

## Security Considerations

1. **CORS**: Currently allows all origins (`*`). For production, restrict to your domain:
   ```python
   "Access-Control-Allow-Origin": "https://jerome-dixon.io"
   ```

2. **API Keys**: Consider adding API key authentication for production

3. **Rate Limiting**: Configure throttling in API Gateway

4. **HTTPS**: Use CloudFront or API Gateway custom domain for HTTPS

## Troubleshooting

### CORS Errors

**Symptom**: Browser console shows CORS error

**Fix**:
1. Verify Lambda returns CORS headers
2. Check API Gateway CORS configuration
3. Ensure OPTIONS method is configured

### 502 Bad Gateway

**Symptom**: API Gateway returns 502

**Fix**:
1. Check Lambda function logs in CloudWatch
2. Verify Lambda function is deployed
3. Check Lambda timeout (increase if needed)

### 403 Forbidden

**Symptom**: API Gateway returns 403

**Fix**:
1. Check API Gateway resource policy
2. Verify Lambda permissions
3. Check API key (if configured)

## Testing

### Test from Browser Console

```javascript
// Test metadata endpoint
fetch('https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod/metadata?cohort=Combined')
  .then(r => r.json())
  .then(console.log);

// Test risk endpoint
fetch('https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod/risk', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    cohort: "Combined",
    features: {egfr_tx: 60.0}
  })
})
  .then(r => r.json())
  .then(console.log);
```

### Test with curl

```bash
# Test metadata
curl "https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod/metadata?cohort=Combined"

# Test risk
curl -X POST "https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod/risk" \
  -H "Content-Type: application/json" \
  -d '{"cohort":"Combined","features":{"egfr_tx":60.0}}'
```
