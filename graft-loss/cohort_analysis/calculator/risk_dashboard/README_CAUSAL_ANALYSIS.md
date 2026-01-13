# Causal Analysis Dashboard

## Overview

The Causal Analysis tab provides an interactive interface for exploring how causal factors affect patient risk in real-time. This feature allows clinicians and researchers to:

- Visualize the importance and causal responsibility of top factors
- Experiment with different factor values to see their impact on risk
- Understand which factors have the greatest influence on graft loss risk

## Features

### 1. Visualizations

#### Importance Chart
- **Bar chart** showing the top 10 causal factors by importance score
- Importance scores represent the combined impact of each factor on risk prediction
- Higher bars indicate factors with greater influence on risk

#### Causal Responsibility Chart
- **Bar chart** showing causal responsibility scores (0-1 scale)
- Causal responsibility measures how much each factor contributes to the outcome
- Values closer to 1.0 indicate stronger causal relationships

### 2. Interactive Controls

The dashboard provides interactive controls for the **top 15 causal factors**:

- **Numeric Features**: 
  - Range slider for easy adjustment
  - Number input for precise values
  - Sliders and inputs are synchronized
  
- **Binary Features**:
  - Dropdown menu (Yes/No or 0/1)
  - Represents presence/absence of a factor

### 3. Real-Time Risk Recalculation

When you adjust any causal factor:

1. The dashboard automatically calls the `/risk` API endpoint
2. Risk is recalculated with the updated feature values
3. Results update immediately without page refresh
4. Risk comparison panel shows the impact of changes

### 4. Risk Comparison Panel

Shows three key metrics:

- **Baseline Risk**: Risk score calculated from current form values (or baseline defaults)
- **Current Risk**: Risk score after modifying causal factors
- **Risk Change**: 
  - Absolute difference (e.g., +5.2%)
  - Percentage change (e.g., +12.5% increase)
  - Color-coded: Green (decrease), Red (increase), Gray (no change)

## Usage

### Step 1: Select Cohort
Choose the cohort from the dropdown:
- **Combined**: All patients
- **CHD**: Congenital Heart Disease
- **Myocardio**: Cardiomyopathy/Myocarditis

### Step 2: View Causal Factors
The dashboard automatically loads:
- Top 20 causal factors for the selected cohort
- Visualizations showing importance and responsibility
- Interactive controls for top 15 factors

### Step 3: Adjust Factors
1. Use sliders or inputs to modify factor values
2. Watch the risk score update in real-time
3. Compare baseline vs. current risk in the comparison panel

### Step 4: Analyze Impact
- Identify which factors have the greatest impact on risk
- Experiment with different combinations of factor values
- Understand how interventions might affect patient outcomes

## Technical Details

### Data Sources

- **Causal Factors**: Loaded from `/causal` API endpoint
  - Returns top K causal factors (default: 20)
  - Includes importance, causal responsibility, SHAP importance
  - Based on Formal Feature Attribution (FFA) analysis

- **Risk Calculation**: Uses `/risk` API endpoint
  - Calculates risk with updated feature values
  - Returns normalized percentile (0-100)
  - Includes risk band classification

### API Endpoints

#### GET /causal
```json
POST /causal
{
  "cohort": "Combined",
  "top_k": 20
}
```

Response:
```json
{
  "cohort": "Combined",
  "top_causal_factors": [
    {
      "feature": "ltxtrach",
      "importance": 0.092,
      "causal_responsibility": 1.0,
      "shap_importance": 1.0,
      "combined_importance": 0.092
    },
    ...
  ],
  "summary": {...}
}
```

#### POST /risk
```json
POST /risk
{
  "cohort": "Combined",
  "features": {
    "egfr_tx": 60.0,
    "txbun_r": 25.0,
    ...
  },
  "use_ensemble": false
}
```

Response:
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

## Causal Factor Metrics

### Importance Score
- **Combined importance** from multiple sources (SHAP, FFA, model-based)
- Higher values indicate greater influence on risk prediction
- Normalized across all factors

### Causal Responsibility
- Measures **causal contribution** to the outcome
- Range: 0.0 to 1.0
- Values closer to 1.0 indicate stronger causal relationships
- Based on counterfactual analysis

### SHAP Importance
- **SHapley Additive exPlanations** importance
- Measures average marginal contribution across all feature combinations
- Provides model-agnostic feature importance

## Best Practices

1. **Start with Baseline**: Use baseline/default values to establish a reference point
2. **Adjust One Factor at a Time**: Isolate the impact of individual factors
3. **Compare Scenarios**: Use the comparison panel to see how interventions might affect risk
4. **Consider Clinical Context**: Factor values should be clinically realistic
5. **Review Multiple Factors**: Some factors may interact, so consider combinations

## Limitations

- **Top 15 Factors Only**: Controls are provided for top 15 factors; all factors are shown in charts
- **Real-Time Calculation**: Each adjustment triggers an API call; rapid changes may cause delays
- **Feature Availability**: Not all causal factors may have corresponding form inputs
- **Model Limitations**: Risk predictions are based on trained models and may not capture all clinical scenarios

## Future Enhancements

- [ ] Support for factor interactions (combinations of factors)
- [ ] Historical tracking of risk changes
- [ ] Export functionality for scenario analysis
- [ ] Additional visualization types (scatter plots, heatmaps)
- [ ] Sensitivity analysis tools

## References

- **Formal Feature Attribution (FFA)**: Symbolic logic extraction from gradient-boosted models
- **SHAP Values**: SHapley Additive exPlanations for model interpretability
- **Causal Responsibility**: Counterfactual analysis for causal inference

## Support

For questions or issues with the Causal Analysis dashboard:
1. Check the browser console for error messages
2. Verify API connectivity (see Risk Calculator tab)
3. Ensure cohort data is available
4. Review API documentation in `README_DASHBOARD.md`

---

**Last Updated**: 2026-01-13  
**Causal Analysis Version**: 1.0
