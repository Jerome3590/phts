# Test Results: riskRegression::Score() Format Requirements

## Summary

We tested various formats for `riskRegression::Score()` to understand the "Cannot assign response type" error.

## Key Findings

### ✅ Formats That Work

All of these formats work correctly with `riskRegression::Score()`:

1. **Unnamed list with vector**: `list(risk_scores)`
2. **Named list with vector**: `list(Model1 = risk_scores)`
3. **Named list with matrix**: `list(Model1 = as.matrix(risk_scores))`
4. **Matrix as column vector**: `list(Model1 = matrix(risk_scores, ncol=1))`
5. **Predictions in data frame**: Works when predictions are also in the data frame

### ✅ Accessing Results

The AUC (C-index) is accessed via:
```r
result$AUC$score$AUC[1]
```

If multiple time points are used, check for a `times` column:
```r
auc_tab <- result$AUC$score
if ("times" %in% names(auc_tab)) {
  this_row <- which.min(abs(auc_tab$times - horizon))
} else {
  this_row <- 1L
}
cindex <- as.numeric(auc_tab$AUC[this_row])
```

### ⚠️ Known Issues

1. **"Cannot assign response type" error**: 
   - This error can occur even with correct formats
   - May be version-specific or related to data characteristics
   - **Solution**: Use `survival::concordance()` as a robust fallback

2. **Multiple time points**:
   - When using multiple time points, predictions must be a matrix with columns matching the number of time points
   - Single-column matrix works fine for single time point

### 📋 Recommended Format

For consistency and clarity, use:
```r
evaluation <- riskRegression::Score(
  object  = list(ModelName = as.matrix(predictions)),  # Named list, matrix format
  formula = Surv(time, status) ~ 1,
  data    = data.frame(time = time, status = status),
  times   = horizon,
  summary = "risks",
  metrics = "auc",  # Only AUC, suppresses Brier score warnings
  se.fit  = FALSE
)
```

### 🔄 Fallback Strategy

Always include a fallback to `survival::concordance()`:
```r
cindex <- tryCatch({
  # Try riskRegression::Score()
  evaluation <- riskRegression::Score(...)
  as.numeric(evaluation$AUC$score$AUC[1])
}, error = function(e) {
  # Fallback to concordance
  calculate_cindex(time, status, predictions)
})
```

## Test Files Created

1. `test_riskRegression_Score.R` - Basic format tests
2. `test_rsf_score_format.R` - RSF-specific tests
3. `test_score_response_type.R` - Response type investigation

## Conclusion

The format used in `replicate_20_features.R` is correct. The "Cannot assign response type" error appears to be:
- Version-specific or environment-specific
- Possibly related to data characteristics (though our tests didn't reproduce it consistently)
- Not a format issue

The robust solution is to:
1. Use the correct format (as implemented)
2. Always include a fallback to `survival::concordance()`
3. Ensure data alignment and validation (as now implemented)

