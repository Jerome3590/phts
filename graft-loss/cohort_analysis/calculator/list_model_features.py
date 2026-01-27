#!/usr/bin/env python3
"""
List Final Model Features

This script extracts and lists all features used in the trained model.
Run this after training to see the exact feature set.
"""

import sys
from pathlib import Path
import json

# Add project paths
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
CALCULATOR_DIR = Path(__file__).parent
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(CALCULATOR_DIR))

def get_model_features(cohort: str = "Combined") -> list:
    """
    Get feature names from trained model.
    
    Args:
        cohort: Cohort name (default: Combined)
    
    Returns:
        List of feature names expected by the model
    """
    try:
        from catboost import CatBoostRegressor
        import xgboost as xgb
    except ImportError:
        print("Error: catboost and xgboost must be installed")
        return []
    
    models_dir = CALCULATOR_DIR / "outputs" / "models" / cohort
    
    if not models_dir.exists():
        print(f"Error: Model directory not found: {models_dir}")
        print("Please train models first: python train_python_models.py --cohort Combined")
        return []
    
    # Try CatBoost first
    catboost_path = models_dir / "catboost_model.cbm"
    if catboost_path.exists():
        print(f"Loading CatBoost model from: {catboost_path}")
        model = CatBoostRegressor()
        model.load_model(str(catboost_path))
        if hasattr(model, 'feature_names_'):
            return list(model.feature_names_)
    
    # Try XGBoost
    xgboost_path = models_dir / "xgboost_model.ubj"
    if xgboost_path.exists():
        print(f"Loading XGBoost model from: {xgboost_path}")
        model = xgb.Booster()
        model.load_model(str(xgboost_path))
        if hasattr(model, 'feature_names'):
            return list(model.feature_names)
    
    # Try XGBoost RF
    xgboost_rf_path = models_dir / "xgboost_rf_model.ubj"
    if xgboost_rf_path.exists():
        print(f"Loading XGBoost RF model from: {xgboost_rf_path}")
        model = xgb.Booster()
        model.load_model(str(xgboost_rf_path))
        if hasattr(model, 'feature_names'):
            return list(model.feature_names)
    
    print(f"Error: No model found in {models_dir}")
    return []


def categorize_features(features: list) -> dict:
    """
    Categorize features by type.
    
    Args:
        features: List of feature names
    
    Returns:
        Dictionary with categorized features
    """
    categories = {
        'derived_combined': [],
        'derived_dichotomous': [],
        'derived_ratios': [],
        'derived_calculated': [],
        'derived_categories': [],
        'demographics': [],
        'donor': [],
        'recipient_clinical': [],
        'recipient_lab': [],
        'recipient_support': [],
        'immunology': [],
        'other': []
    }
    
    for feat in features:
        feat_lower = feat.lower()
        
        # Derived combined variables
        if 'combined' in feat_lower or 'ecmo_combined' in feat_lower or 'vad_combined' in feat_lower or 'vent_combined' in feat_lower:
            categories['derived_combined'].append(feat)
        # Derived dichotomous
        elif '_high' in feat_lower or '_low' in feat_lower or '_bin' in feat_lower:
            categories['derived_dichotomous'].append(feat)
        # Derived ratios
        elif '_ratio' in feat_lower or '_change' in feat_lower:
            categories['derived_ratios'].append(feat)
        # Derived calculated
        elif feat_lower.startswith('egfr_') or feat_lower.startswith('bmi_'):
            categories['derived_calculated'].append(feat)
        # Derived categories
        elif '_cat' in feat_lower:
            categories['derived_categories'].append(feat)
        # Demographics
        elif any(x in feat_lower for x in ['age_', 'sex', 'race', 'weight_', 'height_', 'bmi_']):
            if 'donor' not in feat_lower:
                categories['demographics'].append(feat)
        # Donor variables
        elif 'donor' in feat_lower or 'donisch' in feat_lower or 'dtime' in feat_lower:
            categories['donor'].append(feat)
        # Recipient clinical
        elif any(x in feat_lower for x in ['hx', 'sec_dx', 'ter_dx', 'prim_dx', 'primary_etiology', 'chd_']):
            categories['recipient_clinical'].append(feat)
        # Recipient lab values
        elif any(x in feat_lower for x in ['tx', 'ls', 'l') and any(y in feat_lower for y in ['creat', 'bun', 'bili', 'alt', 'ast', 'alb', 'prot', 'chol', 'hdl', 'ldl', 'tg', 'bnp', 'crp']):
            categories['recipient_lab'].append(feat)
        # Support devices
        elif any(x in feat_lower for x in ['ecmo', 'vad', 'vent', 'trach']):
            categories['recipient_support'].append(feat)
        # Immunology
        elif any(x in feat_lower for x in ['pra', 'cpr', 'hla', 'abo']):
            categories['immunology'].append(feat)
        else:
            categories['other'].append(feat)
    
    return categories


def main():
    """Main function."""
    import argparse
    
    parser = argparse.ArgumentParser(description="List final model features")
    parser.add_argument("--cohort", type=str, default="Combined",
                       choices=["Combined", "CHD", "Myocardio"],
                       help="Cohort to list features for (default: Combined)")
    parser.add_argument("--output", type=str, help="Output file path (JSON)")
    parser.add_argument("--categorized", action="store_true", help="Show categorized features")
    
    args = parser.parse_args()
    
    print(f"\n{'='*80}")
    print(f"Final Model Features: {args.cohort}")
    print(f"{'='*80}\n")
    
    # Get features from model
    features = get_model_features(args.cohort)
    
    if not features:
        print("No features found. Please train models first.")
        return 1
    
    print(f"Total features: {len(features)}\n")
    
    # Show all features
    if not args.categorized:
        print("All Features (alphabetical):")
        print("-" * 80)
        for i, feat in enumerate(sorted(features), 1):
            print(f"{i:4d}. {feat}")
    else:
        # Categorize features
        categories = categorize_features(features)
        
        print("Features by Category:")
        print("-" * 80)
        
        for cat_name, cat_features in categories.items():
            if cat_features:
                print(f"\n{cat_name.replace('_', ' ').title()} ({len(cat_features)}):")
                for feat in sorted(cat_features):
                    print(f"  - {feat}")
        
        # Summary
        print(f"\n{'='*80}")
        print("Summary:")
        print("-" * 80)
        total_categorized = sum(len(v) for v in categories.values())
        print(f"Total categorized: {total_categorized}")
        print(f"Total features: {len(features)}")
        if total_categorized < len(features):
            print(f"Uncategorized: {len(features) - total_categorized}")
    
    # Save to file if requested
    if args.output:
        output_data = {
            'cohort': args.cohort,
            'total_features': len(features),
            'features': sorted(features),
            'categorized': categorize_features(features) if args.categorized else None
        }
        
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w') as f:
            json.dump(output_data, f, indent=2)
        print(f"\nFeatures saved to: {output_path}")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
