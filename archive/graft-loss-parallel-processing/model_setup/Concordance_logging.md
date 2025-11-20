# Enhanced Concordance Error Logging

## Overview

The `cindex()` and `cindex_uno()` functions in `R/utils/model_utils.R` have been enhanced with comprehensive error handling and detailed logging to help diagnose concordance computation failures.

## Features Added

### 1. Robust Error Handling
- **Input validation**: Checks for empty vectors, mismatched lengths
- **Missing data handling**: Removes NAs and validates remaining data
- **Event validation**: Ensures there are events (status=1) in the data
- **Score validation**: Handles cases with identical risk scores
- **Graceful degradation**: Returns `NA_real_` with warnings instead of crashing

### 2. Detailed Data Logging
When `DEBUG_CINDEX=1` is set, the functions will log:
- **Input summary**: Sample sizes, data ranges, event counts
- **Missing data breakdown**: Counts of missing values by variable
- **Cleaned data summary**: Data after removing missing values
- **Attempt logging**: What computation is being attempted
- **Error details**: Complete data dump when errors occur
- **Sample data**: First 5 values of each variable for small datasets

## Usage

### Debug Logging (Enabled by Default)
Debug logging is **currently enabled by default** until successful pipeline completion.

To explicitly enable (if needed):
```bash
# In bash/terminal
export DEBUG_CINDEX=1

# Or in R
Sys.setenv(DEBUG_CINDEX = "1")
```

### Disable Debug Logging
```bash
# In bash/terminal
export DEBUG_CINDEX=0

# Or in R
Sys.setenv(DEBUG_CINDEX = "0")
```

## Example Output

### Normal Operation (DEBUG_CINDEX=1)
```
[DEBUG] cindex input summary: n=150, time range=[0.50, 365.25], status sum=45, score range=[0.1234, 0.8765]
[DEBUG] cindex attempting concordance: n=150, events=45, unique_scores=147
```

### Error Case (DEBUG_CINDEX=1)
```
Warning: cindex: No events (status=1) in the data - n=150, all status values: 0
```

### Detailed Error Case (DEBUG_CINDEX=1)
```
Warning: cindex: Error in concordance computation: No (non-missing) observations
[ERROR] cindex failed with data summary:
  Original lengths - time: 150, status: 150, score: 150
  Time: min=0.5000, max=365.2500, na_count=0
  Status: values=0, na_count=0
  Score: min=0.1234, max=0.8765, na_count=0, unique_count=1
  Sample data (n=5): time=12.50,24.75,36.00,48.25,60.50, status=0,0,0,0,0, score=0.5000,0.5000,0.5000,0.5000,0.5000
```

## Benefits

1. **Faster Debugging**: Immediately see what data caused the concordance failure
2. **Data Quality Insights**: Understand patterns in missing data or problematic subsets
3. **Production Safety**: Warnings instead of crashes allow pipeline to continue
4. **Minimal Performance Impact**: Debug logging only when enabled
5. **Comprehensive Coverage**: Both Harrell's and Uno's C-index functions covered

## Integration with Parallel Processing

The enhanced logging works seamlessly with your parallel processing pipeline:
- Each worker logs independently to its own log files
- Debug output appears in the appropriate model/split log files
- No interference between parallel workers
- Warnings are captured in the main pipeline logs

## Troubleshooting Common Issues

### "No events (status=1) in the data"
- **Cause**: All subjects are censored (status=0)
- **Solution**: Check data filtering, ensure events are present in splits

### "All risk scores are identical"
- **Cause**: Model predictions are constant (no discrimination)
- **Solution**: Check model fitting, feature selection, or data preprocessing

### "No valid (non-missing) observations"
- **Cause**: All data is missing after removing NAs
- **Solution**: Check prediction pipeline, ensure valid scores are generated

## Files Modified

- `R/utils/model_utils.R`: Enhanced `cindex()` and `cindex_uno()` functions
- This documentation file

## Environment Variables

- `DEBUG_CINDEX`: Set to "1", "true", "yes", or "y" to enable detailed logging
- **Current Default: "1" (enabled)** until successful pipeline completion
- Set to "0" to disable for production use
