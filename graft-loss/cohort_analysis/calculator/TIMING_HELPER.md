# Workflow Step Timing

This document describes how to add timing/logging to workflow steps, **aligned with the mermaid chart workflow**.

## Timing Helper Function

The timing helper is already added to the notebook (cell after configuration). It supports optional sub-steps that align with the mermaid chart nodes.

```python
# Timing helper for workflow steps (aligned with mermaid chart workflow)
import time
from contextlib import contextmanager

@contextmanager
def step_timer(step_name, sub_steps=None):
    """
    Context manager to time workflow steps with logging.
    
    Aligns with mermaid chart workflow:
    - Training: Temporal Split → Train Models → Select Best Model → Final Model
    - SHAP/FFA: Extract Rules → Compute SHAP → Apply Rules → Calculate Frequencies → Causal Responsibility
    
    Args:
        step_name: Main step name (e.g., "Step 1: Train Top Model")
        sub_steps: Optional list of sub-steps that align with mermaid chart nodes
    """
    # ... (implementation in notebook)
```

## Usage Examples

### Basic Usage

```python
with step_timer("Step 1: Train Top Model"):
    train_models_for_cohort(...)
```

### With Sub-steps (Aligned with Mermaid Chart)

**Training Step:**
```python
with step_timer(
    "Step 1: Train Top Model",
    sub_steps=[
        "Temporal Split (80/20)",
        "Train Models (CatBoost, XGBoost, XGBoost RF)",
        "Select Best Model (by C-index, then AU-PRC)",
        "Final Model (Trained on Train Set)"
    ]
):
    train_models_for_cohort(...)
```

**SHAP/FFA Step:**
```python
with step_timer(
    "Step 3: SHAP/FFA Analysis (Top Model)",
    sub_steps=[
        "Extract Rules (from XGBoost JSON)",
        "Compute SHAP Values (on Test Set Only)",
        "Apply Rules to Test Set (Count Rule Firings)",
        "Combine SHAP Values (XGBoost + CatBoost if needed)",
        "Calculate Rule Frequencies (from Test Set)",
        "SHAP Importance (per Feature)",
        "Causal Responsibility (rule_freq × SHAP_importance)",
        "Top K Causal Factors (for Dashboard)"
    ]
):
    # Run SHAP/FFA workflow
    subprocess.run([...])
```

## Steps That Need Timing (Aligned with Mermaid Chart)

### Training Steps (Mermaid: Training Data → Temporal Split → Train Models → Select Best → Final Model)

1. **Step 1: Train Top Model (Combined_top)**
   - Sub-steps: Temporal Split (80/20) → Train Models → Select Best Model → Final Model
   - Already has timing, wrap with step_timer

### SHAP/FFA Steps (Mermaid: Extract Rules → Compute SHAP → Apply Rules → Causal Responsibility)

2. **Step 2: SHAP/FFA Analysis (Top Model)**
   - Sub-steps: Extract Rules → Compute SHAP (Test Set) → Apply Rules (Test Set) → Calculate Frequencies → Causal Responsibility → Top K Factors
   - Add timing with sub-steps

### Deployment Steps

5. **Step 1: Prepare Lambda Directory** - Add timing
6. **Step 2: Build Docker Image** - Add timing
7. **Step 3: Update Lambda Function** - Add timing
8. **Step 4: Verify API Gateway** - Add timing (quick, but still useful)
9. **Step 5: Upload HTML to S3** - Add timing

## Mermaid Chart Alignment

The timing helper is designed to align with the mermaid chart workflow shown in the notebook:

```
Training: Temporal Split → Train Models → Select Best Model → Final Model
SHAP/FFA: Extract Rules → Compute SHAP → Apply Rules → Calculate Frequencies → Causal Responsibility
```

When using `sub_steps`, the timing output will show these sub-steps, making it clear how each step maps to the mermaid chart nodes.
