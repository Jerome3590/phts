# Dashboard Baseline Defaults

## Overview

The dashboard now includes baseline/default values that are preloaded when the page loads. This improves user experience by:
1. Allowing users to test the calculator immediately
2. Providing reference values for typical/normal ranges
3. Making it easier to see how the calculator works

## Baseline Values

### Kidney Function
- **eGFR at Transplant**: `90.0` mL/min/1.73m² (normal range)
- **BUN at Transplant**: `15.0` mg/dL (normal range)
- **Creatinine at Transplant**: `0.8` mg/dL (normal range)

### Cardiac Support
- **LVAD**: `No` (0) - default
- **ECMO at Transplant**: `No` (0) - default
- **Mechanical Circulatory Support Device**: `No` (0) - default

### Diagnosis & Demographics
- **CHD: Partial Anomalous Pulmonary Venous Return**: `No` (0) - default
- **CHD: Anomaly**: `No` (0) - default
- **Donor Ischemic Time**: `4.0` hours (typical range)

### Lab Values
- **Serum Albumin at Transplant**: `3.8` g/dL (normal range)
- **AST at Transplant**: `25.0` U/L (normal range)

## Implementation

1. **Default Values in HTML**: Input fields have `value` attributes set to baseline values
2. **Load Baseline Function**: JavaScript function `loadBaseline()` that sets all fields to baseline
3. **Auto-load on Page Load**: Baseline values are automatically loaded when the page loads
4. **Load Baseline Button**: Button to reload baseline values at any time

## User Actions

- **Calculate Risk**: Uses current form values (including defaults)
- **Clear Form**: Clears all values
- **Load Baseline Values**: Resets all fields to baseline defaults

## Rationale

Baseline values are set to:
- **Normal/healthy ranges** for lab values (eGFR, BUN, creatinine, albumin, AST)
- **Typical values** for clinical parameters (donor ischemic time)
- **"No" (0)** for binary features (cardiac support, CHD features) - representing absence of risk factors

This allows users to:
1. See a baseline risk score immediately
2. Modify values to see how they affect risk
3. Understand what "normal" values look like

---

**Date**: 2026-01-13
**Status**: ✅ Implemented - Baseline values preloaded on page load
