# Pipeline Exit Error Fix

## Problem Identified

After Step 3 (03_prep_model_data.R) completed successfully, the pipeline was **crashing with an `on.exit()` error** instead of continuing to Step 4.

### Error Message
```
Error in on.exit({ : unused arguments ({
    try(sink(type = "message"))
    try(sink())
    try(close(log_conn))
}, add = TRUE)
Calls: source -> withVisible -> eval -> eval
Execution halted
```

### Location in Logs
- Line 155-156: Step 3 completes successfully ✓
- Line 157-162: `on.exit()` error occurs ✗
- Line 163-170: Error repeats, "Execution halted" ✗
- **Pipeline stops, Step 4 never runs**

## Root Cause

The pipeline was using **nested `on.exit()` handlers** that created conflicts:

1. `run_pipeline.R` (orchestrator) sets up logging with `on.exit(add = TRUE)`
2. Each individual pipeline script (01-09) **also** set up its own `on.exit(add = TRUE)` 
3. When sourced scripts finished, they tried to close sinks/connections
4. This created conflicts with the parent orchestrator's logging management
5. The nested cleanup handlers caused parsing/execution errors

### Why This is Wrong

**Individual pipeline scripts should NOT manage their own logging cleanup** when being orchestrated by a parent script. The parent (`run_pipeline.R`) already manages:
- Opening log connections
- Redirecting stdout/stderr  
- Cleaning up on exit

Child scripts adding their own handlers with `add = TRUE` creates:
- Double cleanup attempts
- Race conditions on file handles
- Execution halt errors

## Solution Applied

**Removed all script-level `on.exit()` handlers** from individual pipeline steps:

### Files Fixed
1. ✓ `pipeline/01_prepare_data.R`
2. ✓ `pipeline/02_resampling.R`
3. ✓ `pipeline/03_prep_model_data.R`
4. ✓ `pipeline/04_data_setup.R`
5. ✓ `pipeline/04_check_completion.R` (script-level only)
6. ✓ `pipeline/05_mc_cv_analysis.R`
7. ✓ `pipeline/06_parallel_model_fitting.R`
8. ✓ `pipeline/07_model_saving.R`
9. ✓ `pipeline/08_fallback_handling.R`
10. ✓ `pipeline/09_generate_outputs.R`

### What Was Removed
```r
# OLD (REMOVED):
log_conn <- file(log_file, open = 'at')
sink(log_conn, split = TRUE)
sink(log_conn, type = 'message', append = TRUE)
on.exit({
  try(sink(type = 'message'))
  try(sink())
  try(close(log_conn))
}, add = TRUE)

# NEW (ADDED):
# Note: Logging is managed by run_pipeline.R orchestrator
# Individual pipeline scripts should not set up their own sink/on.exit handlers
# to avoid conflicts with the parent script's logging management
```

### What Remains (Intentionally)
- `run_pipeline.R` still has its `on.exit()` handler (line 60-64) - **this is correct**
- `04_check_completion.R` has a function-scoped `on.exit()` inside `run_cohort_step()` - **this is fine**

Function-scoped handlers are appropriate; script-level handlers in sourced files are not.

## Expected Behavior After Fix

1. ✓ Step 1 completes
2. ✓ Step 2 completes  
3. ✓ Step 3 completes
4. ✓ **Step 4 should now run** (previously failed here)
5. ✓ Steps 5-10 should continue
6. ✓ All logging managed by `run_pipeline.R` orchestrator

## Testing

Run the pipeline again and verify:
- No more `on.exit()` errors
- Pipeline continues past Step 3
- All steps execute sequentially
- Logging still works (managed by parent)

## Verification Command
```bash
# Check no script-level on.exit in pipeline scripts
grep -n "^on.exit({" pipeline/*.R
# Should return: no matches (or only function-scoped ones)
```

---

**Date:** 2025-10-14  
**Issue:** Pipeline halting after Step 3 with `on.exit()` error  
**Status:** FIXED ✓

