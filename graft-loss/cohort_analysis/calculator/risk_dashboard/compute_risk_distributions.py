#!/usr/bin/env python3
"""
Compute risk score distributions for normalization.

This script:
1. Loads training data for each cohort
2. Loads trained models
3. Generates predictions on training data
4. Computes percentile distributions
5. Saves distributions to JSON files for use in Lambda
"""

import json
import sys
import os
from pathlib import Path
import numpy as np
import pandas as pd
from typing import Dict, List, Any, Optional

# Disable CatBoost verbose globally before importing
os.environ['CATBOOST_VERBOSE'] = '0'

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from catboost import CatBoostRegressor, Pool
    import xgboost as xgb
    # Disable XGBoost verbose globally
    os.environ['XGBOOST_VERBOSE'] = '0'
    MODEL_LIBS_AVAILABLE = True
except ImportError:
    MODEL_LIBS_AVAILABLE = False
    print("Warning: Model libraries not available")

def load_training_data(cohort: str) -> Optional[pd.DataFrame]:
    """
    Load training data for a cohort.
    
    Tries to load from SAS file and filter by cohort.
    """
    # Try to find the data file
    project_root = Path(__file__).parent.parent.parent.parent
    data_paths = [
        project_root / "graft-loss" / "data" / "phts_txpl_ml.sas7bdat",
        project_root / "data" / "phts_txpl_ml.sas7bdat",
        Path(__file__).parent.parent.parent.parent.parent / "graft-loss" / "data" / "phts_txpl_ml.sas7bdat",
    ]
    
    data_path = None
    for path in data_paths:
        if path.exists():
            data_path = path
            break
    
    if data_path is None:
        print(f"Warning: Cannot find phts_txpl_ml.sas7bdat. Will use placeholder distributions.")
        return None
    
    print(f"Loading data from: {data_path}")
    
    # Load SAS file
    try:
        import pyreadstat
        df, _ = pyreadstat.read_sas7bdat(str(data_path))
    except ImportError:
        try:
            df = pd.read_sas(str(data_path))
        except:
            print(f"Warning: Cannot load SAS file. Will use placeholder distributions.")
            return None
    
    # Filter by cohort
    if cohort == "CHD":
        prim_dx_col = df.get('PRIM_DX', df.get('prim_dx', None))
        if prim_dx_col is not None:
            df = df[prim_dx_col == "Congenital HD"]
    elif cohort == "Myocardio":
        prim_dx_col = df.get('PRIM_DX', df.get('prim_dx', None))
        if prim_dx_col is not None:
            df = df[prim_dx_col.isin(["Cardiomyopathy", "Myocarditis"])]
    # Combined uses all data
    
    print(f"Loaded {len(df)} rows for cohort {cohort}")
    return df

def prepare_features_for_model(df: pd.DataFrame, model, model_type: str, cohort: Optional[str] = None) -> Optional[tuple]:
    """
    Prepare features from dataframe to match model's expected format.
    
    Returns tuple of (feature_matrix, feature_names) for XGBoost, or (feature_matrix, cat_features) for CatBoost.
    For CatBoost, cat_features is a list of indices of categorical features.
    """
    try:
        # Import feature preparation function
        from run_shap_ffa_workflow import prepare_calculator_features
        
        # Prepare features using the same logic as training
        df_prepared = prepare_calculator_features(df.copy())
        
        if model_type == 'catboost':
            # Get feature names from model
            if hasattr(model, 'feature_names_'):
                feature_names = model.feature_names_
            else:
                print(f"Warning: Cannot get feature names from CatBoost model")
                return None
            
            # Load feature metadata to determine correct feature types
            # This tells us which features are numeric vs binary (from saved metadata)
            feature_metadata = {}
            if cohort:
                try:
                    project_root = Path(__file__).parent.parent.parent
                    metadata_file = project_root / "calculator" / "outputs" / "shap_ffa" / cohort / "dashboard_data.json"
                    if metadata_file.exists():
                        import json
                        with open(metadata_file, 'r') as f:
                            dashboard_data = json.load(f)
                            feature_metadata = dashboard_data.get("feature_metadata", {})
                            print(f"  Loaded feature metadata for {len(feature_metadata)} features")
                except Exception as e:
                    print(f"  Warning: Could not load feature metadata: {e}")
            
            # Exclude lscntry (listing country) - not modifiable
            features_to_exclude = ['lscntry', 'Iscntry']
            
            X_df = pd.DataFrame(index=df_prepared.index)
            cat_feature_indices = []
            
            for idx, fname in enumerate(feature_names):
                # Skip excluded features
                if fname in features_to_exclude:
                    print(f"  Warning: Feature '{fname}' should have been excluded during training. Skipping.")
                    continue
                    
                if fname in df_prepared.columns:
                    col_data = df_prepared[fname].copy()
                    
                    # Use feature metadata to determine type (if available)
                    # If metadata says 'numeric', force to numeric (even if data looks categorical)
                    # If metadata says 'binary', treat as categorical (0/1)
                    if fname in feature_metadata:
                        feature_type = feature_metadata[fname]
                        if feature_type == 'numeric':
                            # Force to numeric (handles numeric-encoded categories)
                            col_data = pd.to_numeric(col_data, errors='coerce').fillna(0.0)
                            X_df[fname] = col_data
                            # Don't add to categorical features
                        elif feature_type == 'binary':
                            # Treat as categorical (0/1)
                            col_data = col_data.astype(str).fillna('')
                            cat_feature_indices.append(idx)
                            X_df[fname] = col_data
                        else:
                            # Unknown type, infer from data
                            is_categorical = (
                                col_data.dtype == 'object' or 
                                col_data.dtype.name == 'category' or
                                (col_data.dtype == 'bool')
                            )
                            if is_categorical:
                                col_data = col_data.astype(str).fillna('')
                                cat_feature_indices.append(idx)
                            else:
                                col_data = pd.to_numeric(col_data, errors='coerce').fillna(0.0)
                            X_df[fname] = col_data
                    else:
                        # No metadata - infer from data (fallback)
                        is_categorical = (
                            col_data.dtype == 'object' or 
                            col_data.dtype.name == 'category' or
                            (col_data.dtype == 'bool') or
                            (col_data.dtype == 'int64' and col_data.nunique() < 20)  # Low cardinality ints might be categorical
                        )
                        
                        if is_categorical:
                            col_data = col_data.astype(str).fillna('')
                            cat_feature_indices.append(idx)
                        else:
                            col_data = pd.to_numeric(col_data, errors='coerce').fillna(0.0)
                        
                        X_df[fname] = col_data
                else:
                    # Missing feature - default to numeric 0
                    X_df[fname] = 0.0
                    print(f"  Warning: Feature '{fname}' missing from data, using default")
            
            if len(X_df.columns) == 0:
                print(f"Warning: No matching features found in dataframe")
                return None
            
            # Return DataFrame for CatBoost (it handles categoricals natively)
            return (X_df, cat_feature_indices)
        else:  # XGBoost
            # XGBoost models need feature names - try to get from model JSON or use all numeric columns
            feature_names = None
            
            # Try to get feature names from model (if available)
            try:
                # XGBoost Booster may have feature names
                if hasattr(model, 'feature_names'):
                    feature_names = model.feature_names
            except:
                pass
            
            # If no feature names from model, try to load from model JSON
            if feature_names is None:
                # Try to load from model JSON file
                project_root = Path(__file__).parent.parent.parent
                models_dir = project_root / "calculator" / "outputs" / "models"
                json_file = models_dir / cohort / "final_model_json" / f"{cohort}_final_model_xgboost.json"
                if json_file.exists():
                    try:
                        with open(json_file, 'r') as f:
                            model_json = json.load(f)
                            # Extract feature names from model JSON
                            if 'learner' in model_json and 'feature_names' in model_json['learner']:
                                feature_names = model_json['learner']['feature_names']
                    except:
                        pass
            
            # If still no feature names, use all numeric columns
            if feature_names is None:
                numeric_cols = df_prepared.select_dtypes(include=[np.number]).columns.tolist()
                feature_names = numeric_cols
            
            if len(feature_names) == 0:
                print(f"Warning: No features found")
                return None
            
            # Prepare feature matrix - match exact feature order from model
            # XGBoost models require exact feature order and all features present
            X_list = []
            available_features = []
            missing_features = []
            
            for f in feature_names:
                if f in df_prepared.columns:
                    col_data = df_prepared[f]
                    # Convert to numeric if needed
                    if not pd.api.types.is_numeric_dtype(col_data):
                        col_data = pd.to_numeric(col_data, errors='coerce')
                    # Fill NaN with 0
                    col_data = col_data.fillna(0)
                    X_list.append(col_data.values)
                    available_features.append(f)
                else:
                    # Feature missing - add zeros
                    missing_features.append(f)
                    X_list.append(np.zeros(len(df_prepared)))
                    available_features.append(f)
            
            if len(missing_features) > 0:
                print(f"  Warning: {len(missing_features)} features missing from data, using zeros: {missing_features[:10]}")
            
            # Stack into matrix with exact feature order
            X = np.column_stack(X_list).astype(np.float32)
            return (X, feature_names)  # Return model's feature names, not just available ones
    except Exception as e:
        print(f"Error preparing features: {e}")
        import traceback
        traceback.print_exc()
        return None

def load_model(cohort: str, model_type: str, models_dir: Path, return_file_path: bool = False):
    """
    Load a trained model.
    
    Args:
        cohort: Cohort name
        model_type: Model type ('catboost', 'xgboost', 'xgboost_rf')
        models_dir: Directory containing models
        return_file_path: If True, return tuple of (model, file_path) for CatBoost
    """
    model_path = models_dir / cohort
    
    if model_type == 'catboost':
        model_file = model_path / "catboost_model.cbm"
        if model_file.exists():
            # Load CatBoost model - don't set verbose/logging_level here
            # The model file itself contains the training parameters
            model = CatBoostRegressor()
            model.load_model(str(model_file))
            if return_file_path:
                return (model, model_file)
            return model
    elif model_type in ['xgboost', 'xgboost_rf']:
        model_file = model_path / f"{model_type}_model.ubj"
        if model_file.exists():
            model = xgb.Booster()
            model.load_model(str(model_file))
            return model
    
    return None

def get_best_model_type(cohort: str, models_dir: Path) -> str:
    """Get best model type from best_model.txt."""
    best_model_file = models_dir / cohort / "best_model.txt"
    if best_model_file.exists():
        with open(best_model_file, 'r') as f:
            for line in f:
                if line.startswith("Best Model:"):
                    best_model = line.split("Best Model:")[1].strip()
                    if "XGBoost RF" in best_model:
                        return "xgboost_rf"
                    elif "XGBoost" in best_model:
                        return "xgboost"
                    elif "CatBoost" in best_model:
                        return "catboost"
    return "xgboost"  # default

def compute_percentiles(scores: np.ndarray) -> Dict[str, float]:
    """Compute percentile statistics."""
    if len(scores) == 0:
        return {}
    
    scores_clean = scores[np.isfinite(scores)]
    if len(scores_clean) == 0:
        return {}
    
    return {
        'min': float(np.min(scores_clean)),
        'max': float(np.max(scores_clean)),
        'mean': float(np.mean(scores_clean)),
        'median': float(np.median(scores_clean)),
        'std': float(np.std(scores_clean)),
        'p5': float(np.percentile(scores_clean, 5)),
        'p10': float(np.percentile(scores_clean, 10)),
        'p25': float(np.percentile(scores_clean, 25)),
        'p50': float(np.percentile(scores_clean, 50)),
        'p75': float(np.percentile(scores_clean, 75)),
        'p90': float(np.percentile(scores_clean, 90)),
        'p95': float(np.percentile(scores_clean, 95)),
    }

def generate_predictions(model, X, model_type: str, feature_names: Optional[List[str]] = None, cat_features: Optional[List[int]] = None, model_file: Optional[Path] = None, df_prepared: Optional[pd.DataFrame] = None) -> np.ndarray:
    """
    Generate predictions from model.
    
    Args:
        model: Trained model
        X: Feature matrix (numpy array for XGBoost, DataFrame for CatBoost)
        model_type: 'catboost' or 'xgboost' or 'xgboost_rf'
        feature_names: Feature names for XGBoost
        cat_features: List of categorical feature indices for CatBoost
        df_prepared: Original prepared dataframe (for CatBoost retry with feature fixes)
    """
    try:
        if model_type == 'catboost':
            # CatBoost: Try prediction, catch feature type errors and fix them automatically
            max_retries = 50  # Allow up to 50 feature fixes (many numeric-encoded categories)
            retry_count = 0
            X_working = X.copy() if isinstance(X, pd.DataFrame) else X
            cat_features_working = cat_features.copy() if cat_features else []
            
            while retry_count < max_retries:
                try:
                    pool = Pool(
                        data=X_working,
                        cat_features=cat_features_working if cat_features_working else None
                    )
                    predictions = model.predict(pool)
                    return np.array(predictions).flatten()
                except Exception as e:
                    error_msg = str(e)
                    # Check if it's a feature type mismatch error
                    if "is Float in model but marked different" in error_msg or ("Feature" in error_msg and "Float" in error_msg):
                        # Extract feature name from error message
                        # Format: "Feature FEATURE_NAME is Float in model but marked different in the dataset"
                        import re
                        match = re.search(r'Feature (\w+) is Float', error_msg)
                        if match:
                            problematic_feature = match.group(1)
                            print(f"  Retry {retry_count + 1}: Feature '{problematic_feature}' type mismatch, forcing to numeric")
                            
                            # Force this feature to numeric
                            if isinstance(X_working, pd.DataFrame) and problematic_feature in X_working.columns:
                                X_working[problematic_feature] = pd.to_numeric(X_working[problematic_feature], errors='coerce').fillna(0.0)
                                # Remove from categorical features if present
                                feature_idx = X_working.columns.get_loc(problematic_feature)
                                if feature_idx in cat_features_working:
                                    cat_features_working.remove(feature_idx)
                                retry_count += 1
                                continue
                        # If we can't extract feature name or fix it, break
                        print(f"  Could not fix feature type error: {error_msg}")
                        break
                    else:
                        # Not a feature type error, re-raise
                        raise
            
            # If we exhausted retries, raise the last error
            raise Exception(f"Failed after {max_retries} retries fixing feature type mismatches")
        else:  # XGBoost
            # XGBoost: X should be a numpy array (all numeric)
            if feature_names is not None and len(feature_names) == X.shape[1]:
                dmatrix = xgb.DMatrix(X, feature_names=feature_names)
            else:
                dmatrix = xgb.DMatrix(X)
            predictions = model.predict(dmatrix)
        
        return np.array(predictions).flatten()
    except Exception as e:
        print(f"Error generating predictions: {e}")
        import traceback
        traceback.print_exc()
        return np.array([])

def main():
    """Compute risk distributions for all cohorts."""
    # Paths
    project_root = Path(__file__).parent.parent.parent
    models_dir = project_root / "calculator" / "outputs" / "models"
    output_dir = project_root / "calculator" / "outputs" / "risk_distributions"
    output_dir.mkdir(parents=True, exist_ok=True)
    
    cohorts = ["CHD", "Combined", "Myocardio"]
    
    print("Computing risk score distributions for normalization...")
    print(f"Models directory: {models_dir}")
    print(f"Output directory: {output_dir}")
    print()
    
    if not MODEL_LIBS_AVAILABLE:
        print("ERROR: Model libraries not available. Cannot compute distributions.")
        return
    
    all_distributions = {}
    
    for cohort in cohorts:
        print(f"Processing {cohort} cohort...")
        
        # Get best model type
        best_model_type = get_best_model_type(cohort, models_dir)
        print(f"  Best model: {best_model_type}")
        
        # Use the best model type for distribution computation
        # For Myocardio, prefer CatBoost if available (even if not best) to get proper distribution
        # Now that lscntry is excluded and retry mechanism handles numeric-encoded categories, CatBoost should work
        model_type_to_use = best_model_type
        if cohort == "Myocardio":
            # Try CatBoost first for Myocardio (user preference)
            catboost_model = load_model(cohort, 'catboost', models_dir)
            if catboost_model is not None:
                print(f"  Using CatBoost for Myocardio distribution computation")
                model_type_to_use = 'catboost'
                model = catboost_model
            else:
                print(f"  CatBoost not available, using best model: {best_model_type}")
        
        # Load model (for CatBoost, also get file path for reload if needed)
        model_file = None
        if model_type_to_use == 'catboost':
            result = load_model(cohort, model_type_to_use, models_dir, return_file_path=True)
            if isinstance(result, tuple):
                model, model_file = result
            else:
                model = result
        else:
            model = load_model(cohort, model_type_to_use, models_dir)
        
        if model is None:
            # For Myocardio, try XGBoost as fallback if CatBoost fails
            if cohort == "Myocardio" and best_model_type == 'catboost':
                print(f"  CatBoost failed, trying XGBoost for distribution computation...")
                model_type_to_use = 'xgboost'
                model = load_model(cohort, model_type_to_use, models_dir)
                if model is None:
                    print(f"  Warning: Could not load any model for {cohort}")
                    continue
            else:
                print(f"  Warning: Could not load {best_model_type} model for {cohort}")
                continue
        
        # Try to load training data
        df = load_training_data(cohort)
        
        if df is not None and len(df) > 0:
            # Prepare features (use model_type_to_use, not best_model_type)
            # Also prepare df_prepared for CatBoost retry mechanism
            from run_shap_ffa_workflow import prepare_calculator_features
            df_prepared = prepare_calculator_features(df.copy())
            
            result = prepare_features_for_model(df, model, model_type_to_use, cohort=cohort)
            
            if result is not None:
                if model_type_to_use == 'catboost':
                    X, cat_features = result
                    feature_names = None
                else:
                    X, feature_names = result
                    cat_features = None
                
                if X is not None and len(X) > 0:
                    # Generate predictions
                    print(f"  Generating predictions on {len(X)} samples using {model_type_to_use} model...")
                    # Pass model_file and df_prepared for CatBoost to enable retry with feature fixes
                    df_prepared_for_retry = df_prepared if model_type_to_use == 'catboost' else None
                    predictions = generate_predictions(model, X, model_type_to_use, feature_names, cat_features, model_file if model_type_to_use == 'catboost' else None, df_prepared_for_retry)
                
                if len(predictions) > 0:
                    # Compute percentiles
                    percentiles = compute_percentiles(predictions)
                    
                    if percentiles:
                        # Store distribution
                        all_distributions[cohort] = {
                            'model_type': model_type_to_use,  # Use actual model used, not best_model_type
                            'percentiles': percentiles,
                            'n_samples': len(predictions),
                            'note': f'Computed from training data using {model_type_to_use} model' + (' (fallback from CatBoost)' if cohort == 'Myocardio' and best_model_type == 'catboost' and model_type_to_use != 'catboost' else '')
                        }
                        
                        print(f"  [OK] Percentiles computed: min={percentiles['min']:.3f}, max={percentiles['max']:.3f}, median={percentiles['median']:.3f}")
                        print(f"     Samples: {len(predictions)}")
                        continue
        
        # Fallback: Use placeholder distribution if data not available
        print(f"  [WARNING] Using placeholder distribution (training data not available)")
        
        # Typical survival model risk scores range from negative to positive values
        # Use model_type_to_use (may be XGBoost fallback for Myocardio)
        if model_type_to_use == 'catboost':
            # CatBoost Cox typically outputs negative values (higher risk = more negative)
            default_scores = np.random.normal(-2.0, 1.5, 1000)
        else:  # XGBoost
            # XGBoost Cox outputs can vary
            default_scores = np.random.normal(0.0, 1.0, 1000)
        
        # Compute percentiles
        percentiles = compute_percentiles(default_scores)
        
        # Store distribution
        all_distributions[cohort] = {
            'model_type': best_model_type,
            'percentiles': percentiles,
            'n_samples': 1000,
            'note': 'Placeholder distribution - should be computed from actual training data'
        }
        
        print(f"  Percentiles computed: min={percentiles['min']:.3f}, max={percentiles['max']:.3f}, median={percentiles['median']:.3f}")
        print()
    
    # Save distributions
    output_file = output_dir / "risk_distributions.json"
    with open(output_file, 'w') as f:
        json.dump(all_distributions, f, indent=2)
    
    print(f"[OK] Risk distributions saved to: {output_file}")
    print()
    
    # Check if any distributions are placeholders
    placeholder_count = sum(1 for d in all_distributions.values() if 'placeholder' in d.get('note', '').lower())
    if placeholder_count > 0:
        print(f"[WARNING] {placeholder_count} cohort(s) using placeholder distributions.")
        print("   To compute real distributions:")
        print("   1. Ensure phts_txpl_ml.sas7bdat is available")
        print("   2. Install pyreadstat: pip install pyreadstat")
        print("   3. Fix feature name mismatches between model and data")
        print("   4. Re-run this script")
    else:
        print("[OK] All distributions computed from training data!")

if __name__ == "__main__":
    main()
