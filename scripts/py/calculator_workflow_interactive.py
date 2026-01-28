#!/usr/bin/env python3
"""
Interactive Calculator Workflow for VS Code Python Interactive Window

This script allows you to run the calculator model training and SHAP/FFA workflow
interactively using VS Code's Python Interactive window (Jupyter-like cells).

The workflow follows the dual model strategy:
- Baseline Model (Combined_base): Base calculator features only
- Enhanced Model (Combined_enhanced): Base + recommended features

Usage in VS Code:
1. Open this file in VS Code
2. Select a Python interpreter with required packages installed
3. Click "Run Cell" above each # %% cell to execute step by step
4. Or use Ctrl+Enter to run the current cell

The script is organized into cells that can be run independently:
- Setup and configuration
- Baseline model training
- Enhanced model training
- Baseline SHAP/FFA analysis
- Enhanced SHAP/FFA analysis
- Results inspection (both models)
- Feature importance (both models)

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
PROJECT_ROOT = Path(__file__).parent.parent.parent
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
print("Model Strategy: Dual model implementation (Baseline + Enhanced)")
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
WEIGHT_CATBOOST = None  # None = auto-determined from best model C-index (recommended)
WEIGHT_XGBOOST = None  # None = auto-determined from best model C-index (recommended)
DEBUG_MODE = False  # Enable debug logging

print(f"\nConfiguration:")
print(f"  Cohort: {COHORT}")
print(f"  Top K factors: {TOP_K}")
print(f"  CatBoost weight: {WEIGHT_CATBOOST if WEIGHT_CATBOOST is not None else 'Auto-determined'}")
print(f"  XGBoost weight: {WEIGHT_XGBOOST if WEIGHT_XGBOOST is not None else 'Auto-determined'}")
print(f"  Debug mode: {DEBUG_MODE}")

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
# Cell 5: Train Baseline Model (Step 1)
# ============================================================================
# Import training function
from train_python_models import train_models_for_cohort

print(f"\n{'=' * 80}")
print(f"Step 1: Training Baseline Model for {COHORT} Cohort")
print(f"{'=' * 80}")
print(f"Model Variant: Baseline (base calculator features only)")
print(f"Output directory: outputs/models/Combined_base/")
print("-" * 80)

try:
    train_models_for_cohort(
        COHORT,
        include_recommended_features=False  # Baseline model uses base features only (creates Combined_base directory)
    )
    print(f"\n✓ Baseline model training complete!")
    print(f"  Output saved to: {CALCULATOR_DIR}/outputs/models/{COHORT}_base/")
except Exception as e:
    print(f"\n✗ Error training Baseline model: {e}")
    import traceback
    traceback.print_exc()

# %%
# ============================================================================
# Cell 6: Train Enhanced Model (Step 2)
# ============================================================================
print(f"\n{'=' * 80}")
print(f"Step 2: Training Enhanced Model for {COHORT} Cohort")
print(f"{'=' * 80}")
print(f"Model Variant: Enhanced (base + recommended features)")
print(f"Output directory: outputs/models/Combined_enhanced/")
print("-" * 80)

try:
    train_models_for_cohort(
        COHORT,
        include_recommended_features=True  # Enable enhanced features (creates Combined_enhanced directory)
    )
    print(f"\n✓ Enhanced model training complete!")
    print(f"  Output saved to: {CALCULATOR_DIR}/outputs/models/{COHORT}_enhanced/")
except Exception as e:
    print(f"\n✗ Error training Enhanced model: {e}")
    import traceback
    traceback.print_exc()

# %%
# ============================================================================
# Cell 7: Check Training Results (Both Models)
# ============================================================================
import json

print(f"\n{'=' * 80}")
print("Training Results Summary")
print(f"{'=' * 80}")

# Check both baseline and enhanced model directories
model_variants = [
    ("Baseline", f"{COHORT}_base"),
    ("Enhanced", f"{COHORT}_enhanced")
]

for variant_name, variant_dir in model_variants:
    print(f"\n{variant_name} Model ({variant_dir}):")
    print("-" * 80)
    
    best_model_file = CALCULATOR_DIR / "outputs" / "models" / variant_dir / "best_model.txt"
    if best_model_file.exists():
        print(f"✓ Best model file found")
        with open(best_model_file, 'r') as f:
            content = f.read()
            print(content)
    else:
        print(f"✗ Best model file not found: {best_model_file}")
    
    # List available models
    models_dir = CALCULATOR_DIR / "outputs" / "models" / variant_dir
    if models_dir.exists():
        model_files = list(models_dir.glob("*.cbm")) + list(models_dir.glob("*.ubj"))
        if model_files:
            print(f"\n  Model files:")
            for model_file in sorted(model_files):
                size_mb = model_file.stat().st_size / (1024 * 1024)
                print(f"    {model_file.name} ({size_mb:.2f} MB)")
        else:
            print(f"  ⚠ No model files found")

# %%
# ============================================================================
# Cell 8: Run SHAP/FFA for Baseline Model (Step 3)
# ============================================================================
import subprocess

print(f"\n{'=' * 80}")
print("Step 3: Running SHAP + FFA Analysis for Baseline Model")
print(f"{'=' * 80}")
print(f"Analyzing Baseline Combined model (Combined_base)...")
print(f"Output: outputs/shap_ffa/Combined_base/ (dashboard data for Baseline Model tab)")
print("-" * 80)

try:
    cmd = [
        sys.executable,
        str(CALCULATOR_DIR / "run_shap_ffa_workflow.py"),
        "--cohort", COHORT,
        "--model-variant", "base",  # Explicitly use baseline model
        "--top-k", str(TOP_K)
    ]
    
    # Only add weight arguments if manually specified
    if WEIGHT_CATBOOST is not None:
        cmd.extend(["--weight-catboost", str(WEIGHT_CATBOOST)])
    if WEIGHT_XGBOOST is not None:
        cmd.extend(["--weight-xgboost", str(WEIGHT_XGBOOST)])
    
    result = subprocess.run(
        cmd,
        cwd=str(CALCULATOR_DIR),
        capture_output=False,  # Show output in real-time
        text=True
    )
    
    if result.returncode == 0:
        print(f"\n✓ Baseline model SHAP/FFA analysis complete!")
        print(f"  Results saved to: {CALCULATOR_DIR}/outputs/shap_ffa/{COHORT}_base/")
    else:
        print(f"\n⚠ SHAP/FFA exited with code: {result.returncode}")
except Exception as e:
    print(f"\n✗ Error running SHAP/FFA: {e}")
    import traceback
    traceback.print_exc()

# %%
# ============================================================================
# Cell 9: Run SHAP/FFA for Enhanced Model (Step 4)
# ============================================================================
print(f"\n{'=' * 80}")
print("Step 4: Running SHAP + FFA Analysis for Enhanced Model")
print(f"{'=' * 80}")
print(f"Analyzing Enhanced Combined model (Combined_enhanced)...")
print(f"Output: outputs/shap_ffa/Combined_enhanced/ (dashboard data for Extended Model tab)")
print("-" * 80)

try:
    cmd = [
        sys.executable,
        str(CALCULATOR_DIR / "run_shap_ffa_workflow.py"),
        "--cohort", COHORT,
        "--model-variant", "enhanced",  # Explicitly use enhanced model
        "--top-k", str(TOP_K)
    ]
    
    # Only add weight arguments if manually specified
    if WEIGHT_CATBOOST is not None:
        cmd.extend(["--weight-catboost", str(WEIGHT_CATBOOST)])
    if WEIGHT_XGBOOST is not None:
        cmd.extend(["--weight-xgboost", str(WEIGHT_XGBOOST)])
    
    result = subprocess.run(
        cmd,
        cwd=str(CALCULATOR_DIR),
        capture_output=False,  # Show output in real-time
        text=True
    )
    
    if result.returncode == 0:
        print(f"\n✓ Enhanced model SHAP/FFA analysis complete!")
        print(f"  Results saved to: {CALCULATOR_DIR}/outputs/shap_ffa/{COHORT}_enhanced/")
    else:
        print(f"\n⚠ SHAP/FFA exited with code: {result.returncode}")
except Exception as e:
    print(f"\n✗ Error running SHAP/FFA: {e}")
    import traceback
    traceback.print_exc()

# %%
# ============================================================================
# Cell 10: Inspect Results (Both Models)
# ============================================================================
import json
import pandas as pd

print(f"\n{'=' * 80}")
print("Results Summary - Baseline and Enhanced Models")
print(f"{'=' * 80}")

# Check both model variants
model_variants = [
    ("Baseline", f"{COHORT}_base"),
    ("Enhanced", f"{COHORT}_enhanced")
]

for variant_name, variant_dir in model_variants:
    print(f"\n{'=' * 80}")
    print(f"{variant_name} Model ({variant_dir}) - Top {TOP_K} Causal Factors")
    print("=" * 80)
    
    dashboard_data_file = (
        CALCULATOR_DIR / "outputs" / "shap_ffa" / variant_dir / "dashboard_data.json"
    )
    
    if dashboard_data_file.exists():
        with open(dashboard_data_file, 'r') as f:
            dashboard_data = json.load(f)
        
        top_factors = dashboard_data.get('top_causal_factors', [])[:TOP_K]
        
        if top_factors:
            for idx, factor in enumerate(top_factors, 1):
                importance = factor.get('causal_responsibility', 
                                     factor.get('importance', 
                                               factor.get('combined_importance_norm', 0)))
                print(f"{idx:2d}. {factor['feature']:40s} "
                      f"(Importance: {importance:.4f})")
        else:
            print("  (No causal factors available)")
        
        # Display summary statistics
        if 'summary' in dashboard_data:
            print(f"\n  Summary Statistics:")
            summary = dashboard_data['summary']
            for key, value in summary.items():
                print(f"    {key}: {value}")
    else:
        print(f"⚠ Dashboard data not found for {variant_name} model")
        print(f"  Expected: {dashboard_data_file}")
        if variant_name == "Baseline":
            print("  Run SHAP/FFA analysis for baseline model first (Cell 8)")
        else:
            print("  Run SHAP/FFA analysis for enhanced model first (Cell 9)")

# %%
# ============================================================================
# Cell 11: Load and Display Feature Importance (Both Models)
# ============================================================================
print(f"\n{'=' * 80}")
print("Feature Importance Rankings - Baseline and Enhanced Models")
print("=" * 80)

# Check both model variants
model_variants = [
    ("Baseline", f"{COHORT}_base"),
    ("Enhanced", f"{COHORT}_enhanced")
]

for variant_name, variant_dir in model_variants:
    print(f"\n{'=' * 80}")
    print(f"{variant_name} Model ({variant_dir}) - Feature Importance")
    print("=" * 80)
    
    importance_files = list(
        (CALCULATOR_DIR / "outputs" / "models" / variant_dir).glob("importance_*.csv")
    )
    
    if importance_files:
        for imp_file in sorted(importance_files):
            model_name = imp_file.stem.replace(f"importance_{variant_dir}_", "")
            print(f"\n  {model_name}:")
            df = pd.read_csv(imp_file)
            print(f"    Total features: {len(df)}")
            print(f"    Top 10 features:")
            top10 = df.nlargest(10, 'importance')
            for idx, row in top10.iterrows():
                print(f"      {row['feature']:40s} {row['importance']:.4f}")
    else:
        print(f"⚠ No feature importance files found for {variant_name} model")
        if variant_name == "Baseline":
            print(f"  Train Baseline model first (Cell 5)")
        else:
            print(f"  Train Enhanced model first (Cell 6)")

# %%
# ============================================================================
# Cell 12: Create Comparison Summary
# ============================================================================
# Compare baseline vs enhanced models
print(f"\n{'=' * 80}")
print("Model Comparison Summary")
print(f"{'=' * 80}")

base_dashboard_file = (
    CALCULATOR_DIR / "outputs" / "shap_ffa" / f"{COHORT}_base" / "dashboard_data.json"
)
enhanced_dashboard_file = (
    CALCULATOR_DIR / "outputs" / "shap_ffa" / f"{COHORT}_enhanced" / "dashboard_data.json"
)

if base_dashboard_file.exists() and enhanced_dashboard_file.exists():
    with open(base_dashboard_file, 'r') as f:
        base_data = json.load(f)
    with open(enhanced_dashboard_file, 'r') as f:
        enhanced_data = json.load(f)
    
    base_factors = base_data.get('top_causal_factors', [])[:TOP_K]
    enhanced_factors = enhanced_data.get('top_causal_factors', [])[:TOP_K]
    
    print(f"\nTop {TOP_K} Causal Factors Comparison:")
    print("-" * 80)
    print(f"{'Rank':<6} {'Baseline Feature':<40} {'Enhanced Feature':<40}")
    print("-" * 80)
    
    # Get all unique features
    all_features = set()
    base_dict = {f['feature']: f.get('causal_responsibility', f.get('importance', 0)) for f in base_factors}
    enhanced_dict = {f['feature']: f.get('causal_responsibility', f.get('importance', 0)) for f in enhanced_factors}
    all_features.update(base_dict.keys())
    all_features.update(enhanced_dict.keys())
    
    # Sort by combined importance
    sorted_features = sorted(all_features, 
                           key=lambda x: (base_dict.get(x, 0) + enhanced_dict.get(x, 0)) / 2,
                           reverse=True)[:TOP_K]
    
    for rank, feature in enumerate(sorted_features, 1):
        base_imp = base_dict.get(feature, 0)
        enh_imp = enhanced_dict.get(feature, 0)
        base_str = f"{feature} ({base_imp:.4f})" if base_imp > 0 else "-"
        enh_str = f"{feature} ({enh_imp:.4f})" if enh_imp > 0 else "-"
        print(f"{rank:<6} {base_str:<40} {enh_str:<40}")
else:
    print("⚠ Cannot compare: Dashboard data missing for one or both models")
    if not base_dashboard_file.exists():
        print(f"  Missing: {base_dashboard_file}")
    if not enhanced_dashboard_file.exists():
        print(f"  Missing: {enhanced_dashboard_file}")

# %%
# ============================================================================
# Cell 13: Export Workflow Summary
# ============================================================================
# Create a summary of all results for both models
from datetime import datetime

print(f"\n{'=' * 80}")
print("Exporting Workflow Summary")
print(f"{'=' * 80}")

summary = {
    "workflow": "Calculator Model Training + SHAP/FFA Analysis",
    "model_strategy": "Dual Combined models (Baseline + Enhanced) for all cohorts",
    "timestamp": datetime.now().isoformat(),
    "configuration": {
        "cohort": COHORT,
        "top_k": TOP_K,
        "weight_catboost": WEIGHT_CATBOOST,
        "weight_xgboost": WEIGHT_XGBOOST,
        "debug_mode": DEBUG_MODE
    },
    "models": {
        "baseline": {},
        "enhanced": {}
    }
}

# Process both model variants
model_variants = [
    ("baseline", f"{COHORT}_base"),
    ("enhanced", f"{COHORT}_enhanced")
]

for variant_name, variant_dir in model_variants:
    variant_summary = {}
    
    # Best model
    best_model_file = CALCULATOR_DIR / "outputs" / "models" / variant_dir / "best_model.txt"
    if best_model_file.exists():
        with open(best_model_file, 'r') as f:
            content = f.read()
            lines = content.split('\n')
            for line in lines:
                if line.startswith("Best Model:"):
                    variant_summary["best_model"] = line.replace("Best Model: ", "").strip()
                elif line.startswith("C-index:"):
                    try:
                        variant_summary["c_index"] = float(line.replace("C-index: ", "").strip())
                    except:
                        pass
    
    # Dashboard data
    dashboard_file = CALCULATOR_DIR / "outputs" / "shap_ffa" / variant_dir / "dashboard_data.json"
    if dashboard_file.exists():
        with open(dashboard_file, 'r') as f:
            dashboard_data = json.load(f)
            variant_summary["top_factors_count"] = len(dashboard_data.get('top_causal_factors', []))
            if dashboard_data.get('top_causal_factors'):
                variant_summary["top_factor"] = dashboard_data['top_causal_factors'][0]['feature']
                variant_summary["top_factor_importance"] = dashboard_data['top_causal_factors'][0].get(
                    'causal_responsibility', 
                    dashboard_data['top_causal_factors'][0].get('importance', 0)
                )
            
            # List top 5 factors
            top5 = dashboard_data.get('top_causal_factors', [])[:5]
            variant_summary["top_5_factors"] = [
                {
                    "feature": f['feature'],
                    "importance": f.get('causal_responsibility', 
                                      f.get('importance', 
                                           f.get('combined_importance_norm', 0)))
                }
                for f in top5
            ]
    
    # Feature count
    feature_file = CALCULATOR_DIR / "outputs" / "models" / variant_dir / "feature_names.json"
    if feature_file.exists():
        with open(feature_file, 'r') as f:
            features = json.load(f)
            variant_summary["total_features"] = len(features)
    
    summary["models"][variant_name] = variant_summary

# Save summary
summary_file = CALCULATOR_DIR / "outputs" / "workflow_summary.json"
with open(summary_file, 'w') as f:
    json.dump(summary, f, indent=2)

print(f"\n✓ Workflow summary saved to: {summary_file}")
print("\nSummary:")
print(json.dumps(summary, indent=2))
