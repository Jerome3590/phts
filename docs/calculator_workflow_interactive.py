#!/usr/bin/env python3
"""
Interactive Calculator Workflow for VS Code Python Interactive Window

This script allows you to run the calculator model training and SHAP/FFA workflow
interactively using VS Code's Python Interactive window (Jupyter-like cells).

Usage in VS Code:
1. Open this file in VS Code
2. Select a Python interpreter with required packages installed
3. Click "Run Cell" above each # %% cell to execute step by step
4. Or use Ctrl+Enter to run the current cell

The script is organized into cells that can be run independently:
- Setup and configuration
- Model training
- SHAP/FFA analysis
- Results inspection

Reference: https://code.visualstudio.com/docs/python/jupyter-support-py
"""

# %%
# ============================================================================
# Cell 1: Setup and Imports
# ============================================================================
import sys
from pathlib import Path
import logging

# Add project paths
PROJECT_ROOT = Path(__file__).parent.parent
CALCULATOR_DIR = PROJECT_ROOT / "graft-loss" / "cohort_analysis" / "calculator"
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(CALCULATOR_DIR))

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

print("=" * 80)
print("PHTS Calculator Workflow - Interactive Mode")
print("=" * 80)
print(f"Project root: {PROJECT_ROOT}")
print(f"Calculator directory: {CALCULATOR_DIR}")
print("=" * 80)

# %%
# ============================================================================
# Cell 2: Configuration
# ============================================================================
# Configure your workflow here
COHORT = "Combined"  # Options: "Combined", "CHD", "Myocardio"
TOP_K = 10  # Number of top causal factors to extract
WEIGHT_CATBOOST = 0.6  # Weight for CatBoost importance
WEIGHT_XGBOOST = 0.4  # Weight for XGBoost importance

print(f"\nConfiguration:")
print(f"  Cohort: {COHORT}")
print(f"  Top K factors: {TOP_K}")
print(f"  CatBoost weight: {WEIGHT_CATBOOST}")
print(f"  XGBoost weight: {WEIGHT_XGBOOST}")

# %%
# ============================================================================
# Cell 3: Check Dependencies
# ============================================================================
print("\nChecking dependencies...")

try:
    import numpy as np
    import pandas as pd
    from catboost import CatBoostRegressor
    import xgboost as xgb
    import shap
    print("✓ All required packages are installed")
    print(f"  NumPy: {np.__version__}")
    print(f"  Pandas: {pd.__version__}")
    print(f"  XGBoost: {xgb.__version__}")
    print(f"  SHAP: {shap.__version__}")
except ImportError as e:
    print(f"✗ Missing dependency: {e}")
    print("  Please install: pip install numpy pandas catboost xgboost shap")

# %%
# ============================================================================
# Cell 4: Check Data Availability
# ============================================================================
print("\nChecking data availability...")

# Check for data file
data_file = PROJECT_ROOT / "graft-loss" / "data" / "phts_txpl_ml.sas7bdat"
if data_file.exists():
    print(f"✓ Data file found: {data_file}")
else:
    print(f"⚠ Data file not found: {data_file}")
    print("  You may need to download the data file first")

# Check calculator directory
if CALCULATOR_DIR.exists():
    print(f"✓ Calculator directory found: {CALCULATOR_DIR}")
else:
    print(f"✗ Calculator directory not found: {CALCULATOR_DIR}")

# %%
# ============================================================================
# Cell 5: Train Models (Step 1)
# ============================================================================
# Import training function
from train_python_models import train_models_for_cohort

print(f"\n{'=' * 80}")
print(f"Step 1: Training Models for {COHORT} Cohort")
print(f"{'=' * 80}")

# Train models
train_models_for_cohort(COHORT)

print(f"\n✓ Model training complete!")
print(f"  Models saved to: {CALCULATOR_DIR}/outputs/models/{COHORT}/")

# %%
# ============================================================================
# Cell 6: Check Training Results
# ============================================================================
import json

# Check best model
best_model_file = CALCULATOR_DIR / "outputs" / "models" / COHORT / "best_model.txt"
if best_model_file.exists():
    print(f"\nBest Model Information:")
    print("-" * 80)
    with open(best_model_file, 'r') as f:
        print(f.read())
else:
    print(f"⚠ Best model file not found: {best_model_file}")

# List available models
models_dir = CALCULATOR_DIR / "outputs" / "models" / COHORT
if models_dir.exists():
    print(f"\nAvailable model files:")
    for model_file in sorted(models_dir.glob("*.cbm")) + sorted(models_dir.glob("*.ubj")):
        size_mb = model_file.stat().st_size / (1024 * 1024)
        print(f"  {model_file.name} ({size_mb:.2f} MB)")

# %%
# ============================================================================
# Cell 7: Run SHAP + FFA Workflow (Step 2)
# ============================================================================
# Import workflow function
from run_shap_ffa_workflow import main as run_shap_ffa_main
import argparse

print(f"\n{'=' * 80}")
print(f"Step 2: Running SHAP + FFA Analysis for {COHORT} Cohort")
print(f"{'=' * 80}")

# Create arguments object (simulating command-line args)
class Args:
    def __init__(self):
        self.cohort = COHORT
        self.top_k = TOP_K
        self.weight_catboost = WEIGHT_CATBOOST
        self.weight_xgboost = WEIGHT_XGBOOST
        self.output_dir = None  # Use default
        self.use_xgboost_only = False

# Run workflow
args = Args()

# Note: The main function expects sys.argv, so we need to mock it
# For interactive use, we'll call the internal functions directly
print("Running SHAP + FFA workflow...")
print("(This may take several minutes)")

# We'll need to import and call the workflow functions directly
# For now, show how to run it via command line
print("\nTo run the full workflow, execute:")
print(f"  python {CALCULATOR_DIR}/run_shap_ffa_workflow.py --cohort {COHORT} --top-k {TOP_K}")

# %%
# ============================================================================
# Cell 8: Run SHAP/FFA via Command Line (Alternative)
# ============================================================================
import subprocess

print(f"\nRunning SHAP/FFA workflow via subprocess...")
print("(This will execute the full workflow)")

try:
    result = subprocess.run(
        [
            sys.executable,
            str(CALCULATOR_DIR / "run_shap_ffa_workflow.py"),
            "--cohort", COHORT,
            "--top-k", str(TOP_K),
            "--weight-catboost", str(WEIGHT_CATBOOST),
            "--weight-xgboost", str(WEIGHT_XGBOOST)
        ],
        cwd=str(CALCULATOR_DIR),
        capture_output=False,  # Show output in real-time
        text=True
    )
    
    if result.returncode == 0:
        print("\n✓ SHAP/FFA workflow completed successfully!")
    else:
        print(f"\n⚠ Workflow exited with code: {result.returncode}")
except Exception as e:
    print(f"\n✗ Error running workflow: {e}")

# %%
# ============================================================================
# Cell 9: Inspect Results
# ============================================================================
import pandas as pd

# Load dashboard data
dashboard_data_file = (
    CALCULATOR_DIR / "outputs" / "shap_ffa" / COHORT / "dashboard_data.json"
)

if dashboard_data_file.exists():
    print(f"\nLoading dashboard data from: {dashboard_data_file}")
    import json
    with open(dashboard_data_file, 'r') as f:
        dashboard_data = json.load(f)
    
    print(f"\nTop {TOP_K} Causal Factors:")
    print("-" * 80)
    top_factors = dashboard_data.get('top_causal_factors', [])[:TOP_K]
    for idx, factor in enumerate(top_factors, 1):
        importance = factor.get('causal_responsibility', 
                               factor.get('importance', 
                                         factor.get('combined_importance_norm', 0)))
        print(f"{idx:2d}. {factor['feature']:40s} "
              f"(Importance: {importance:.4f})")
    
    # Display summary
    if 'summary' in dashboard_data:
        print(f"\nSummary Statistics:")
        summary = dashboard_data['summary']
        for key, value in summary.items():
            print(f"  {key}: {value}")
else:
    print(f"⚠ Dashboard data not found: {dashboard_data_file}")
    print("  Run the SHAP/FFA workflow first (Cell 7 or 8)")

# %%
# ============================================================================
# Cell 10: Load and Display Feature Importance
# ============================================================================
# Load feature importance files
importance_files = list(
    (CALCULATOR_DIR / "outputs" / "models" / COHORT).glob("importance_*.csv")
)

if importance_files:
    print(f"\nFeature Importance Files Found:")
    print("-" * 80)
    
    for imp_file in sorted(importance_files):
        print(f"\n{imp_file.name}:")
        df = pd.read_csv(imp_file)
        print(f"  Total features: {len(df)}")
        print(f"  Top 5 features:")
        top5 = df.nlargest(5, 'importance')
        for idx, row in top5.iterrows():
            print(f"    {row['feature']:40s} {row['importance']:.4f}")
else:
    print("⚠ No feature importance files found")
    print("  Train models first (Cell 5)")

# %%
# ============================================================================
# Cell 11: Quick Model Training (All Cohorts)
# ============================================================================
# Train models for all cohorts
COHORTS = ["Combined", "CHD", "Myocardio"]

print(f"\n{'=' * 80}")
print("Training Models for All Cohorts")
print(f"{'=' * 80}")

for cohort in COHORTS:
    print(f"\nTraining {cohort} model...")
    try:
        train_models_for_cohort(cohort)
        print(f"✓ {cohort} model training complete")
    except Exception as e:
        print(f"✗ Error training {cohort} model: {e}")

print(f"\n{'=' * 80}")
print("All model training complete!")
print(f"{'=' * 80}")

# %%
# ============================================================================
# Cell 12: Quick SHAP/FFA for All Cohorts
# ============================================================================
# Run SHAP/FFA for all cohorts
COHORTS = ["Combined", "CHD", "Myocardio"]

print(f"\n{'=' * 80}")
print("Running SHAP/FFA Analysis for All Cohorts")
print(f"{'=' * 80}")

for cohort in COHORTS:
    print(f"\nRunning SHAP/FFA for {cohort}...")
    try:
        result = subprocess.run(
            [
                sys.executable,
                str(CALCULATOR_DIR / "run_shap_ffa_workflow.py"),
                "--cohort", cohort,
                "--top-k", str(TOP_K)
            ],
            cwd=str(CALCULATOR_DIR),
            capture_output=False,
            text=True
        )
        
        if result.returncode == 0:
            print(f"✓ {cohort} SHAP/FFA complete")
        else:
            print(f"⚠ {cohort} SHAP/FFA exited with code: {result.returncode}")
    except Exception as e:
        print(f"✗ Error running SHAP/FFA for {cohort}: {e}")

print(f"\n{'=' * 80}")
print("All SHAP/FFA analysis complete!")
print(f"{'=' * 80}")

# %%
# ============================================================================
# Cell 13: Export Results Summary
# ============================================================================
# Create a summary of all results
import json
from pathlib import Path

output_dir = CALCULATOR_DIR / "outputs"
summary = {
    "cohorts": {},
    "timestamp": pd.Timestamp.now().isoformat()
}

for cohort in ["Combined", "CHD", "Myocardio"]:
    cohort_summary = {}
    
    # Best model
    best_model_file = output_dir / "models" / cohort / "best_model.txt"
    if best_model_file.exists():
        with open(best_model_file, 'r') as f:
            content = f.read()
            cohort_summary["best_model"] = content.split('\n')[0].replace("Best Model: ", "")
    
    # Dashboard data
    dashboard_file = output_dir / "shap_ffa" / cohort / "dashboard_data.json"
    if dashboard_file.exists():
        with open(dashboard_file, 'r') as f:
            dashboard_data = json.load(f)
            cohort_summary["top_factors_count"] = len(dashboard_data.get('top_causal_factors', []))
            if dashboard_data.get('top_causal_factors'):
                cohort_summary["top_factor"] = dashboard_data['top_causal_factors'][0]['feature']
    
    summary["cohorts"][cohort] = cohort_summary

# Save summary
summary_file = output_dir / "workflow_summary.json"
with open(summary_file, 'w') as f:
    json.dump(summary, f, indent=2)

print(f"\n✓ Workflow summary saved to: {summary_file}")
print("\nSummary:")
print(json.dumps(summary, indent=2))
