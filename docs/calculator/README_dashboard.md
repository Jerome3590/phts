# PHTS Risk Calculator - Dashboard User Guide

## Overview

The PHTS Risk Calculator Dashboard is an interactive web application for calculating graft loss risk in pediatric heart transplant patients. The dashboard provides two main interfaces:

1. **Risk Calculator Tab**: Calculate risk scores from clinical features
2. **Causal Analysis Tab**: Explore how causal factors affect risk in real-time

## Access

**Production URL**: `https://jerome-dixon.io/uva/phts-risk-calculator/`

## Risk Calculator Tab

### Purpose

Calculate patient-specific graft loss risk scores based on clinical features.

### How to Use

1. **Select Cohort**: Choose from CHD, Combined, or Myocardio
2. **Enter Clinical Features**: Fill in patient clinical values
3. **Click "Calculate Risk"**: Get risk score and causal factors
4. **Review Results**: See normalized percentile, risk band, and top causal factors

### Clinical Features

The dashboard accepts the following clinical features:

### Kidney Function
- **eGFR at Transplant** (`egfr_tx`): mL/min/1.73m², Normal range 60-120
- **BUN at Transplant** (`txbun_r`): mg/dL, Normal range 7-20
- **Creatinine at Transplant** (`txcreat_r`): mg/dL, Normal range 0.5-1.2

### Cardiac Support
- **LVAD** (`ltxtrach`): Yes/No (binary)
- **ECMO at Transplant** (`txecmo`): Yes/No (binary)
- **Mechanical Circulatory Support Device** (`txnomcsd`): Yes/No (binary)

### Diagnosis & Demographics
- **CHD: Partial Anomalous Pulmonary Venous Return** (`chd_papvr`): Yes/No (binary)
- **CHD: Anomaly** (`chd_anom`): Yes/No (binary)
- **Donor Ischemic Time** (`donisch`): hours, Typical range 2-6

### Lab Values
- **Serum Albumin at Transplant** (`txsa_r`): g/dL, Normal range 3.5-5.0
- **AST at Transplant** (`txast`): U/L, Normal range 10-40

**Note**: See `README_FINAL_MODELS.md` in the calculator directory for the complete feature list.

### Baseline Values

The dashboard includes baseline/default values that represent typical healthy ranges:
- **eGFR**: 90.0 mL/min/1.73m²
- **BUN**: 15.0 mg/dL
- **Creatinine**: 0.8 mg/dL
- **Albumin**: 3.8 g/dL
- **AST**: 25.0 U/L
- **Binary features**: All set to "No" (0)

Click "Load Baseline Values" to reset all fields to defaults.

### Results Display

#### Risk Score
- **Normalized Percentile** (0-100%): Patient's risk relative to training population
- **Raw Score**: Original model prediction
- **Risk Band**: Low, Medium, High, or Very High

#### Top Causal Factors
- List of top 10 factors driving the risk prediction
- Shows feature name and importance score
- Factors are ranked by causal responsibility

### Risk Score Interpretation

- **0-25%**: Low Risk - Lower than 75% of training population
- **25-75%**: Medium Risk - Middle 50% of training population
- **75-90%**: High Risk - Higher than 75% of training population
- **90-100%**: Very High Risk - Higher than 90% of training population

---

## Causal Analysis Tab

### Purpose

Explore how causal factors affect patient risk through interactive visualizations and real-time risk updates.

### Features

#### 1. Visualizations

**Importance Chart**:
- Bar chart showing top 10 causal factors by importance
- Higher bars = greater influence on risk

**Causal Responsibility Chart**:
- Bar chart showing causal responsibility scores (0-1 scale)
- Values closer to 1.0 = stronger causal relationships

#### 2. Interactive Controls

**Top 15 Causal Factors** with adjustable controls:
- **Numeric Features**: Range slider + number input (synchronized)
- **Binary Features**: Dropdown menu (Yes/No)

#### 3. Real-Time Risk Updates

- Adjust any factor value
- Risk recalculates automatically
- Results update immediately (no page refresh)

#### 4. Risk Comparison Panel

Shows:
- **Baseline Risk**: From current form values (or defaults)
- **Current Risk**: After modifying factors
- **Risk Change**: Absolute difference and percentage change
- **Color Coding**: Green (decrease), Red (increase), Gray (no change)

### How to Use

1. **Select Cohort**: Choose cohort from dropdown
2. **View Causal Factors**: Charts and controls load automatically
3. **Adjust Factors**: Use sliders/inputs to modify values
4. **Observe Changes**: Watch risk update in real-time
5. **Compare Scenarios**: Use comparison panel to see impact

### Best Practices

1. **Start with Baseline**: Use baseline values as reference point
2. **Adjust One at a Time**: Isolate impact of individual factors
3. **Compare Scenarios**: Use comparison panel to see intervention effects
4. **Consider Clinical Context**: Use realistic factor values
5. **Review Multiple Factors**: Some factors may interact

---

## API Endpoints

The dashboard communicates with the backend via REST API:

### GET /metadata
Returns available cohorts and causal factors.

### POST /risk
Calculates risk score from clinical features.

**Request:**
```json
{
  "cohort": "Combined",
  "features": {
    "egfr_tx": 60.0,
    "txbun_r": 20.0,
    ...
  },
  "use_ensemble": false
}
```

**Response:**
```json
{
  "cohort": "Combined",
  "risk_score": 75.5,
  "raw_score": 2.345,
  "percentile": 75.5,
  "risk_band": "high",
  "top_causal_factors": [...]
}
```

### POST /causal
Returns causal factor explanations.

**Request:**
```json
{
  "cohort": "Combined",
  "top_k": 20
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

---

## Browser Compatibility

- **Chrome/Edge**: Fully supported
- **Firefox**: Fully supported
- **Safari**: Fully supported
- **Mobile**: Responsive design works on tablets and phones

---

## Troubleshooting

### "NetworkError when attempting to fetch resource"

**Possible Causes:**
1. API Gateway not deployed
2. CORS configuration issue
3. Network connectivity problem

**Solutions:**
1. Check browser console for specific error
2. Verify API Gateway is accessible
3. Check CORS headers in API response

### Risk Score Not Updating

**Possible Causes:**
1. API call failed
2. Invalid feature values
3. Model loading error

**Solutions:**
1. Check browser console for errors
2. Verify all required features are entered
3. Check API Gateway logs

### Causal Analysis Not Loading

**Possible Causes:**
1. Causal data not available for cohort
2. API endpoint error
3. JavaScript error

**Solutions:**
1. Try different cohort
2. Check browser console
3. Verify API is accessible

---

## Keyboard Shortcuts

- **Tab**: Navigate between form fields
- **Enter**: Submit form (when focus is on Calculate button)
- **Esc**: Clear error messages

---

## Data Privacy

- **No Data Storage**: Patient data is not stored or logged
- **Client-Side Only**: All calculations happen via API calls
- **No Cookies**: Dashboard does not use cookies or local storage
- **HTTPS**: All communication is encrypted

---

## Support

For issues or questions:
1. Check browser console for error messages
2. Verify API connectivity (see Risk Calculator tab)
3. Review this documentation
4. Check deployment status in `README_DEPLOYMENT.md`

---

**Last Updated**: 2026-01-13  
**Dashboard Version**: 1.0
