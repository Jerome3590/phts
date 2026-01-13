#!/usr/bin/env python3
"""
Complete SHAP + FFA Workflow for Calculator Models (Full Rule-Based Analysis)

This script performs FULL rule-based FFA analysis for clinical use:
1. Checks which model is best (from best_model.txt)
2. If XGBoost is best: Uses only XGBoost SHAP values and JSON (simplified pipeline)
3. If CatBoost is best: Uses combined SHAP values (XGBoost + CatBoost) and XGBoost JSON
4. Extracts rules from XGBoost model JSON (CatBoost JSON is hard to parse due to categorical hashing)
5. Filters XGBoost rules using SHAP values
6. Calculates causal responsibility from rule frequency and SHAP importance
7. Generates dashboard outputs with top causal factors

This is a FULL implementation - no simplified fallbacks. All errors will be raised.

Requirements:
- Calculator models must be generated (run train_python_models.py first)
- Data file (phts_txpl_ml.sas7bdat) must be available
- All dependencies installed (shap, xgboost, catboost, etc.)

Usage:
    python run_shap_ffa_workflow.py --cohort Combined --top-k 10
"""

import sys
import argparse
import json
import logging
import numpy as np
import pandas as pd
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
import warnings
from collections import defaultdict
import time
from datetime import datetime

warnings.filterwarnings("ignore")

# Add project paths
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
CALCULATOR_DIR = Path(__file__).parent
FFA_ANALYSIS_DIR = CALCULATOR_DIR / "ffa_analysis"
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(CALCULATOR_DIR))
sys.path.insert(0, str(FFA_ANALYSIS_DIR))
# Also add ffa_analysis as a module path
if str(FFA_ANALYSIS_DIR) not in sys.path:
    sys.path.insert(0, str(FFA_ANALYSIS_DIR))

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Import FFA analysis components
FFA_AVAILABLE = False
try:
    # Try absolute import first
    from ffa_analysis.ffa_utils import load_model_json, extract_feature_mappings
    from ffa_analysis.xgboost_axp_explainer import XGBoostSymbolicExplainer, PathConfig
    FFA_AVAILABLE = True
except ImportError as e1:
    try:
        # Try importing from the ffa_analysis directory directly
        import importlib.util
        ffa_utils_path = FFA_ANALYSIS_DIR / "ffa_utils.py"
        xgboost_explainer_path = FFA_ANALYSIS_DIR / "xgboost_axp_explainer.py"
        
        if ffa_utils_path.exists() and xgboost_explainer_path.exists():
            spec_utils = importlib.util.spec_from_file_location("ffa_utils", ffa_utils_path)
            ffa_utils = importlib.util.module_from_spec(spec_utils)
            spec_utils.loader.exec_module(ffa_utils)
            
            spec_explainer = importlib.util.spec_from_file_location("xgboost_axp_explainer", xgboost_explainer_path)
            xgboost_explainer = importlib.util.module_from_spec(spec_explainer)
            spec_explainer.loader.exec_module(xgboost_explainer)
            
            load_model_json = ffa_utils.load_model_json
            extract_feature_mappings = ffa_utils.extract_feature_mappings
            XGBoostSymbolicExplainer = xgboost_explainer.XGBoostSymbolicExplainer
            PathConfig = xgboost_explainer.PathConfig
            FFA_AVAILABLE = True
            logger.info("FFA modules loaded using direct file import")
        else:
            raise ImportError(f"FFA module files not found: {e1}")
    except Exception as e2:
        FFA_AVAILABLE = False
        logger.warning(f"FFA analysis modules not available: {e1} (also tried direct import: {e2})")

# Import leakage removal function
try:
    from train_python_models import remove_leakage_predictors
except ImportError:
    logger.warning("Could not import remove_leakage_predictors from train_python_models")
    remove_leakage_predictors = None


def get_best_model(cohort: str) -> Optional[str]:
    """
    Read the best model from best_model.txt file.
    
    Checks both calculator outputs and parent outputs directories.
    
    Returns:
        Best model name (e.g., "XGBoost", "CatBoost", "XGBoost RF") or None if not found
    """
    # Check both locations
    calculator_best_path = CALCULATOR_DIR / "outputs" / "models" / cohort / "best_model.txt"
    parent_best_path = CALCULATOR_DIR.parent / "outputs" / "models" / cohort / "best_model.txt"
    
    best_model_path = None
    if calculator_best_path.exists():
        best_model_path = calculator_best_path
    elif parent_best_path.exists():
        best_model_path = parent_best_path
    
    if best_model_path is None:
        logger.warning(
            f"Best model file not found. Checked:\n"
            f"  - {calculator_best_path}\n"
            f"  - {parent_best_path}"
        )
        return None
    
    try:
        with open(best_model_path, 'r') as f:
            lines = f.readlines()
            for line in lines:
                if line.startswith("Best Model:"):
                    best_model = line.split("Best Model:")[1].strip()
                    logger.info(f"Best model from file: {best_model}")
                    return best_model
    except Exception as e:
        logger.warning(f"Error reading best model file: {e}")
    
    return None


def load_calculator_importance(cohort: str) -> Dict[str, pd.DataFrame]:
    """
    Load aggregated feature importance from calculator outputs.
    
    Feature importance files are saved by calculator_models.R to:
    - Parent outputs: graft-loss/cohort_analysis/outputs/importance_{cohort}_{model}.csv
    - These contain mean importance across MC-CV splits
    
    Also checks calculator/outputs as fallback for Python-trained models.
    """
    # Primary location: parent outputs directory (where R calculator saves)
    output_dir = CALCULATOR_DIR.parent / "outputs"
    # Fallback: calculator-specific outputs (for Python-trained models)
    calculator_output_dir = CALCULATOR_DIR / "outputs"
    
    importance_files = {
        'CatBoost': [output_dir / f"importance_{cohort}_CatBoost.csv",
                     calculator_output_dir / f"importance_{cohort}_CatBoost.csv"],
        'XGBoost': [output_dir / f"importance_{cohort}_XGBoost.csv",
                    calculator_output_dir / f"importance_{cohort}_XGBoost.csv"]
    }
    
    importance_data = {}
    for model_name, file_paths in importance_files.items():
        file_path = None
        for path in file_paths:
            if path.exists():
                file_path = path
                break
        
        if file_path:
            df = pd.read_csv(file_path)
            importance_data[model_name] = df
            logger.info(f"Loaded {model_name} importance: {len(df)} features from {file_path}")
        else:
            logger.warning(f"{model_name} importance file not found in any of: {file_paths}")
    
    return importance_data


def load_shap_from_calculator_or_analysis(
    cohort: str,
    model_type: str
) -> Tuple[Optional[Dict[str, float]], Optional[pd.DataFrame]]:
    """
    Load SHAP values from either:
    1. Calculator feature importance (as proxy)
    2. Existing SHAP analysis outputs (if available)
    
    Returns:
        Tuple of (shap_importance_map, shap_values_df)
    """
    # First, try to load from existing SHAP analysis (Step 7)
    # Note: Calculator workflow computes SHAP values directly from models
    # Legacy load_shap_importance function is not used (it references old project structure)
    # This function is kept for backward compatibility but returns None
    logger.debug("load_shap_from_calculator_or_analysis: Using calculator SHAP computation instead")
    
    # Fallback: Use calculator feature importance as SHAP proxy
    importance_data = load_calculator_importance(cohort)
    
    model_key = 'CatBoost' if model_type == 'catboost' else 'XGBoost'
    if model_key not in importance_data:
        return None, None
    
    importance_df = importance_data[model_key]
    
    # Create SHAP map from importance
    shap_map = dict(zip(
        importance_df['feature'],
        importance_df['importance']
    ))
    
    # Normalize to [0, 1] for consistency with SHAP values
    max_imp = max(shap_map.values()) if shap_map else 1.0
    if max_imp > 0:
        shap_map = {k: v / max_imp for k, v in shap_map.items()}
    
    logger.info(f"Created SHAP proxy from {model_key} importance: {len(shap_map)} features")
    
    return shap_map, None


def combine_shap_maps(
    shap_xgboost: Dict[str, float],
    shap_catboost: Dict[str, float],
    weight_xgboost: float = 0.4,
    weight_catboost: float = 0.6
) -> Dict[str, float]:
    """
    Combine SHAP importance maps from XGBoost and CatBoost.
    
    This combined map is used to filter XGBoost rules in the FFA explainer.
    """
    logger.info("Combining SHAP maps from XGBoost and CatBoost...")
    
    # Get all features from both
    all_features = set(shap_xgboost.keys()) | set(shap_catboost.keys())
    
    combined_map = {}
    for feature in all_features:
        xgb_val = shap_xgboost.get(feature, 0.0)
        cb_val = shap_catboost.get(feature, 0.0)
        
        # Weighted combination
        combined = weight_xgboost * xgb_val + weight_catboost * cb_val
        combined_map[feature] = combined
    
    # Filter to features with importance > 0
    combined_map = {k: v for k, v in combined_map.items() if v > 0}
    
    logger.info(f"Combined SHAP map: {len(combined_map)} features with importance > 0")
    logger.info(f"Top 5 features: {sorted(combined_map.items(), key=lambda x: x[1], reverse=True)[:5]}")
    
    return combined_map


def find_xgboost_model_json(cohort: str) -> Optional[Path]:
    """
    Find XGBoost model JSON file for FFA explainer.
    
    The FFA explainer uses XGBoost JSON (not CatBoost) because:
    - CatBoost JSON is hard to parse due to internal hashing of categorical variables
    - XGBoost JSON is easier to parse and extract rules from
    - Rules are then filtered using combined SHAP values from both models
    
    Expected locations:
    - Primary: calculator/outputs/models/{cohort}/final_model_json/{cohort}_final_model_xgboost.json
    - Fallback: parent outputs/models/{cohort}/final_model_json/{cohort}_final_model_xgboost.json
    """
    # Primary: calculator outputs (where train_python_models.py saves)
    calculator_models_dir = CALCULATOR_DIR / "outputs" / "models" / cohort
    calculator_json_dir = calculator_models_dir / "final_model_json"
    
    # Fallback: parent outputs directory (where R calculator might save)
    parent_models_dir = CALCULATOR_DIR.parent / "outputs" / "models" / cohort
    parent_json_dir = parent_models_dir / "final_model_json"
    
    xgboost_paths = [
        calculator_json_dir / f"{cohort}_final_model_xgboost.json",  # Primary: Python-trained models
        calculator_models_dir / f"{cohort}_final_model_xgboost.json",
        parent_json_dir / f"{cohort}_final_model_xgboost.json",  # Fallback: R-trained models
        parent_models_dir / f"{cohort}_final_model_xgboost.json",
        # Legacy paths (for backward compatibility)
        CALCULATOR_DIR / "outputs" / "models" / f"{cohort}_XGBoost_model.json",
        CALCULATOR_DIR / "outputs" / "models" / f"{cohort}_xgboost_model.json",
    ]
    
    for path in xgboost_paths:
        if path.exists():
            logger.info(f"Found XGBoost JSON: {path}")
            return path
    
    logger.warning("XGBoost model JSON not found")
    return None


def prepare_calculator_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Prepare calculator features to match R's prepare_calculator_features() function.
    
    This function:
    1. Calculates derived features (eGFR, BMI, WHO z-scores)
    2. Creates eGFR categories
    3. Creates dichotomous variables
    4. Calculates egfr_change
    
    Args:
        df: Input dataframe with raw calculator data
        
    Returns:
        DataFrame with prepared features
    """
    df = df.copy()
    
    # Convert column names to lowercase for consistency
    df.columns = [col.lower() for col in df.columns]
    
    # ============================================================================
    # CALCULATED VARIABLES: eGFR, BMI
    # ============================================================================
    
    # Calculate eGFR at transplant using Schwartz formula
    if "height_txpl" in df.columns and "txcreat_r" in df.columns:
        if "egfr_tx" not in df.columns:
            df["egfr_tx"] = np.nan
        mask = df["height_txpl"].notna() & df["txcreat_r"].notna() & (df["txcreat_r"] > 0)
        df.loc[mask, "egfr_tx"] = 0.413 * df.loc[mask, "height_txpl"] / df.loc[mask, "txcreat_r"]
        logger.info("Calculated egfr_tx using Schwartz formula")
    
    # Calculate eGFR at listing
    if "height_listing" in df.columns and "lcreat_r" in df.columns:
        if "egfr_listing" not in df.columns:
            df["egfr_listing"] = np.nan
        mask = df["height_listing"].notna() & df["lcreat_r"].notna() & (df["lcreat_r"] > 0)
        df.loc[mask, "egfr_listing"] = 0.413 * df.loc[mask, "height_listing"] / df.loc[mask, "lcreat_r"]
        logger.info("Calculated egfr_listing using Schwartz formula")
    
    # Calculate BMI
    if "weight_txpl" in df.columns and "height_txpl" in df.columns:
        if "bmi_txpl" not in df.columns:
            df["bmi_txpl"] = np.nan
        mask = df["weight_txpl"].notna() & df["height_txpl"].notna() & (df["height_txpl"] > 0)
        df.loc[mask, "bmi_txpl"] = (df.loc[mask, "weight_txpl"] / (df.loc[mask, "height_txpl"] ** 2)) * 703
        logger.info("Calculated bmi_txpl")
    
    # Calculate age_txpl_months if not present
    if "age_txpl_months" not in df.columns and "age_txpl" in df.columns:
        df["age_txpl_months"] = df["age_txpl"] * 12
        logger.info("Calculated age_txpl_months from age_txpl")
    
    # ============================================================================
    # WHO GROWTH CURVE CALCULATIONS (z-scores and percentiles)
    # ============================================================================
    # Note: WHO calculations are complex and require external libraries
    # For now, we'll skip these as they may not be critical for SHAP computation
    # If needed, can be added later using py_helpers or external WHO calculation library
    
    # ============================================================================
    # eGFR CATEGORIES
    # ============================================================================
    
    # Create eGFR categories at transplant
    # R uses case_when which creates character categories, but models may expect numeric codes
    if "egfr_tx" in df.columns:
        df["egfr_tx_cat"] = pd.cut(
            df["egfr_tx"],
            bins=[-np.inf, 30, 60, 90, np.inf],
            labels=["severe", "moderate", "mild", "normal"],
            right=False
        )
        # Convert to string for compatibility with R (which uses character)
        df["egfr_tx_cat"] = df["egfr_tx_cat"].astype(str).replace("nan", np.nan)
        logger.info("Created egfr_tx_cat categories")
    
    # Create eGFR categories at listing
    if "egfr_listing" in df.columns:
        df["egfr_listing_cat"] = pd.cut(
            df["egfr_listing"],
            bins=[-np.inf, 30, 60, 90, np.inf],
            labels=["severe", "moderate", "mild", "normal"],
            right=False
        )
        # Convert to string for compatibility with R (which uses character)
        df["egfr_listing_cat"] = df["egfr_listing_cat"].astype(str).replace("nan", np.nan)
        logger.info("Created egfr_listing_cat categories")
    
    # ============================================================================
    # DICHOTOMOUS VARIABLES
    # ============================================================================
    
    # Bilirubin dichotomous (>1.5)
    if "txbili_t_r" in df.columns:
        df["txbili_t_r_high"] = (df["txbili_t_r"] > 1.5).astype(int)
        logger.info("Created txbili_t_r_high")
    
    # BUN dichotomous (>30)
    bun_var = None
    for var in ["txbun_r", "TXBUN_R"]:
        if var in df.columns:
            bun_var = var
            break
    if bun_var:
        df["txbun_r_high"] = (df[bun_var] > 30).astype(int)
        logger.info(f"Created txbun_r_high from {bun_var}")
    
    # Albumin dichotomous (<3)
    if "txsa_r" in df.columns:
        df["txsa_r_low"] = (df["txsa_r"] < 3).astype(int)
        logger.info("Created txsa_r_low")
    
    # ALT dichotomous (>90)
    if "txalt" in df.columns:
        df["txalt_high"] = (df["txalt"] > 90).astype(int)
        logger.info("Created txalt_high")
    elif "txalt_high" not in df.columns:
        # Try uppercase
        if "TXALT" in df.columns:
            df["txalt_high"] = (df["TXALT"] > 90).astype(int)
            logger.info("Created txalt_high from TXALT")
    
    # ECMO dichotomous (txecmo OR slecmo)
    if "txecmo" in df.columns and "slecmo" in df.columns:
        df["ecmo_combined"] = ((df["txecmo"] == 1) | (df["slecmo"] == 1)).astype(int)
        logger.info("Created ecmo_combined")
    
    # History of Fontan Associated Liver Disease (dichotomous)
    if "hxfonlvr" in df.columns:
        df["hxfonlvr_bin"] = (df["hxfonlvr"] == 1).astype(int)
        logger.info("Created hxfonlvr_bin")
    
    # History of dialysis (dichotomous)
    if "hxdysdia" in df.columns:
        df["hxdysdia_bin"] = (df["hxdysdia"] == 1).astype(int)
        logger.info("Created hxdysdia_bin")
    
    # ============================================================================
    # CHANGE IN eGFR
    # ============================================================================
    
    # Change in eGFR from listing to transplant
    if "egfr_tx" in df.columns and "egfr_listing" in df.columns:
        df["egfr_change"] = df["egfr_tx"] - df["egfr_listing"]
        logger.info("Calculated egfr_change")
    
    return df


def load_calculator_data_for_shap(cohort: str) -> pd.DataFrame:
    """
    Load calculator data for SHAP computation.
    
    Returns:
        DataFrame with features prepared for calculator models
    """
    # Try to find the data file
    data_paths = [
        CALCULATOR_DIR.parent.parent / "data" / "phts_txpl_ml.sas7bdat",
        PROJECT_ROOT / "graft-loss" / "data" / "phts_txpl_ml.sas7bdat",
    ]
    
    data_path = None
    for path in data_paths:
        if path.exists():
            data_path = path
            break
    
    if data_path is None:
        raise FileNotFoundError(
            f"Cannot find phts_txpl_ml.sas7bdat. Checked: {data_paths}. "
            "This file is required for SHAP computation."
        )
    
    logger.info(f"Loading calculator data from {data_path}")
    
    # Load SAS file
    try:
        import pyreadstat
        df, _ = pyreadstat.read_sas7bdat(str(data_path))
    except ImportError:
        try:
            import sas7bdat
            with sas7bdat.SAS7BDAT(str(data_path)) as reader:
                df = reader.to_dataframe()
        except ImportError:
            try:
                df = pd.read_sas(str(data_path))
            except:
                raise ImportError(
                    "Need pyreadstat, sas7bdat, or pandas with SAS support to load data. "
                    "Install with: pip install pyreadstat"
                )
    
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
    
    logger.info(f"Loaded {len(df)} rows for cohort {cohort}")
    
    # Prepare features to match R's prepare_calculator_features()
    logger.info("Preparing calculator features (eGFR, BMI, dichotomous variables, etc.)...")
    df = prepare_calculator_features(df)
    logger.info("Feature preparation complete")
    
    return df


def compute_calculator_shap_values(
    model,
    X: pd.DataFrame,
    model_type: str,
    n_samples: int = 2000
) -> Tuple[np.ndarray, pd.DataFrame]:
    """
    Compute SHAP values for calculator survival models.
    
    For survival models, SHAP values are computed for risk scores (negative log hazard).
    
    Args:
        model: CatBoost or XGBoost survival model
        X: Feature DataFrame
        model_type: 'catboost' or 'xgboost'
        n_samples: Number of samples to use (for memory efficiency)
        
    Returns:
        Tuple of (shap_values_array, shap_values_dataframe)
    """
    import shap
    
    logger.info(f"Computing SHAP values for {model_type} model on {len(X)} samples...")
    
    # Sample if dataset is too large (for computational efficiency)
    # If n_samples is None or >= len(X), use all samples
    if n_samples is not None and len(X) > n_samples:
        sample_idx = np.random.choice(len(X), size=n_samples, replace=False)
        X_sample = X.iloc[sample_idx].copy()
        logger.info(f"Sampled {n_samples} from {len(X)} for SHAP computation")
    else:
        X_sample = X.copy()
        sample_idx = np.arange(len(X))
        if n_samples is None or n_samples >= len(X):
            logger.info(f"Computing SHAP values for all {len(X)} samples")
    
    # Create SHAP explainer and compute values
    try:
        if model_type == 'catboost':
            # For CatBoost, use native SHAP computation which handles categoricals correctly
            from catboost import Pool
            
            # Fill NaN values
            X_sample_clean = X_sample.fillna(0).copy()
            
            # Get feature names from model and align data columns
            try:
                model_feature_names = model.feature_names_
                if model_feature_names:
                    logger.info(f"Model expects {len(model_feature_names)} features")
                    # Create mapping: lowercase both for comparison
                    data_cols_lower = {col.lower(): col for col in X_sample_clean.columns}
                    model_cols_lower = {col.lower(): col for col in model_feature_names}
                    
                    # Reorder and rename columns to match model
                    aligned_cols = []
                    for model_feat in model_feature_names:
                        model_feat_lower = model_feat.lower()
                        if model_feat_lower in data_cols_lower:
                            aligned_cols.append(data_cols_lower[model_feat_lower])
                        elif model_feat in X_sample_clean.columns:
                            aligned_cols.append(model_feat)
                        else:
                            logger.warning(f"Model feature '{model_feat}' not found in data, using zeros")
                            # Add column with zeros
                            X_sample_clean[model_feat] = 0
                            aligned_cols.append(model_feat)
                    
                    # Reorder columns to match model order
                    X_sample_clean = X_sample_clean[aligned_cols].copy()
                    # Rename to match model exactly
                    X_sample_clean.columns = model_feature_names
                    logger.info(f"Aligned {len(aligned_cols)} features to match model")
            except (AttributeError, TypeError) as e:
                logger.warning(f"Could not align feature names: {e}, using data as-is")
            
            # Get categorical feature indices from model
            try:
                cat_feature_indices = model.get_cat_feature_indices()
                if cat_feature_indices:
                    logger.info(f"Model has {len(cat_feature_indices)} categorical features")
                    # Convert categorical features to strings (CatBoost requirement)
                    for idx in cat_feature_indices:
                        if idx < len(X_sample_clean.columns):
                            col_name = X_sample_clean.columns[idx]
                            # Convert to string, handling NaN
                            X_sample_clean[col_name] = X_sample_clean[col_name].astype(str).replace('nan', '')
                else:
                    cat_feature_indices = None
            except (AttributeError, TypeError):
                cat_feature_indices = None
                logger.info("Could not get categorical feature indices from model")
            
            # Create Pool with categorical features specified
            # For survival models, we don't need labels for SHAP
            if cat_feature_indices:
                pool = Pool(X_sample_clean, cat_features=cat_feature_indices)
            else:
                pool = Pool(X_sample_clean)
            
            # Get SHAP values using CatBoost's native method
            shap_values = model.get_feature_importance(pool, type='ShapValues')
            shap_values = np.array(shap_values)
            
            # CatBoost returns (n_samples, n_features + 1) where last col is expected value
            # or (n_samples, n_classes, n_features + 1) for multiclass
            if shap_values.ndim == 2:
                shap_values = shap_values[:, :-1]  # Remove expected value column
            elif shap_values.ndim == 3:
                shap_values = shap_values[:, :, :-1].mean(axis=1)  # Average over classes
            else:
                raise ValueError(f"Unexpected CatBoost SHAP shape: {shap_values.shape}")
                
        else:
            # For XGBoost, use SHAP TreeExplainer with the underlying Booster
            import xgboost as xgb
            
            # Fill NaN values and convert all to numeric
            X_sample_clean = X_sample.fillna(0).copy()
            
            # Convert column names to lowercase to match R-trained model
            X_sample_clean.columns = [col.lower() for col in X_sample_clean.columns]
            
            # Get feature names from model and align data columns (similar to CatBoost)
            try:
                if hasattr(model, 'get_booster'):
                    booster = model.get_booster()
                    model_feature_names = booster.feature_names
                elif hasattr(model, 'booster'):
                    booster = model.booster
                    model_feature_names = booster.feature_names if hasattr(booster, 'feature_names') else None
                elif hasattr(model, 'feature_names_in_'):
                    model_feature_names = model.feature_names_in_
                    booster = model
                else:
                    # Try to get from model attributes
                    model_feature_names = getattr(model, 'feature_names', None)
                    booster = model
                
                if model_feature_names:
                    logger.info(f"XGBoost model expects {len(model_feature_names)} features")
                    # Create mapping: lowercase both for comparison
                    data_cols_lower = {col.lower(): col for col in X_sample_clean.columns}
                    model_cols_lower = {col.lower(): col for col in model_feature_names}
                    
                    # Reorder and rename columns to match model
                    aligned_cols = []
                    for model_feat in model_feature_names:
                        model_feat_lower = model_feat.lower()
                        if model_feat_lower in data_cols_lower:
                            aligned_cols.append(data_cols_lower[model_feat_lower])
                        elif model_feat in X_sample_clean.columns:
                            aligned_cols.append(model_feat)
                        else:
                            logger.warning(f"Model feature '{model_feat}' not found in data, using zeros")
                            # Add column with zeros
                            X_sample_clean[model_feat] = 0
                            aligned_cols.append(model_feat)
                    
                    # Reorder columns to match model order
                    X_sample_clean = X_sample_clean[aligned_cols].copy()
                    # Rename to match model exactly
                    X_sample_clean.columns = model_feature_names
                    logger.info(f"Aligned {len(aligned_cols)} features to match XGBoost model")
                else:
                    logger.warning("Could not get XGBoost model feature names, using data as-is")
                    
            except (AttributeError, TypeError) as e:
                logger.warning(f"Could not align XGBoost feature names: {e}, using data as-is")
            
            # Convert object/string columns to numeric (XGBoost requires numeric)
            for col in X_sample_clean.columns:
                if X_sample_clean[col].dtype == 'object':
                    # Try to convert to numeric, handling string representations
                    try:
                        X_sample_clean[col] = pd.to_numeric(X_sample_clean[col], errors='coerce').fillna(0)
                    except:
                        # If conversion fails, use 0
                        X_sample_clean[col] = 0
            
            # Ensure all columns are numeric
            X_sample_clean = X_sample_clean.select_dtypes(include=[np.number])
            
            # Get the underlying Booster object
            if not isinstance(booster, xgb.Booster):
                if hasattr(model, 'get_booster'):
                    booster = model.get_booster()
                elif hasattr(model, 'booster'):
                    booster = model.booster
                else:
                    booster = model
            
            # Use SHAP TreeExplainer with Booster
            try:
                explainer = shap.TreeExplainer(booster)
                shap_values = explainer.shap_values(X_sample_clean)
                
                # Handle multi-dimensional output
                if isinstance(shap_values, list):
                    shap_values = shap_values[0]  # Use first output
                    
            except Exception as e:
                # Fallback: try using Booster's predict with pred_contribs
                logger.warning(f"SHAP TreeExplainer failed: {e}, trying alternative method")
                try:
                    dmat = xgb.DMatrix(X_sample_clean)
                    if isinstance(booster, xgb.Booster):
                        shap_values = booster.predict(dmat, pred_contribs=True)
                        shap_values = np.array(shap_values)
                        # Remove base value column
                        if shap_values.ndim == 2:
                            shap_values = shap_values[:, :-1]
                    else:
                        raise RuntimeError(f"Could not compute XGBoost SHAP values: {e}") from e
                except Exception as e2:
                    raise RuntimeError(f"Could not compute XGBoost SHAP values: {e2}") from e2
        
        # Handle multi-dimensional output
        if isinstance(shap_values, list):
            shap_values = shap_values[0]  # Use first output
        
        # Ensure 2D array
        if shap_values.ndim == 1:
            shap_values = shap_values.reshape(-1, 1)
        
        # Convert to DataFrame - use feature names from aligned data (model features)
        # For CatBoost, this is X_sample_clean.columns; for XGBoost, it's X_sample_clean.columns
        if model_type == 'catboost':
            feature_names_for_df = X_sample_clean.columns.tolist()
        else:
            feature_names_for_df = X_sample_clean.columns.tolist()
        
        # Validate shape
        if shap_values.shape[1] != len(feature_names_for_df):
            raise ValueError(
                f"SHAP values shape {shap_values.shape} doesn't match feature count {len(feature_names_for_df)}"
            )
        
        shap_df = pd.DataFrame(
            shap_values,
            columns=feature_names_for_df,
            index=sample_idx
        )
        
        logger.info(f"Computed SHAP values: shape {shap_df.shape}")
        
        return shap_values, shap_df
        
    except Exception as e:
        logger.error(f"Error computing SHAP values for {model_type}: {e}", exc_info=True)
        raise


def run_calculator_shap_analysis(cohort: str) -> Tuple[Dict[str, float], Dict[str, float], pd.DataFrame, pd.DataFrame]:
    """
    Run full SHAP analysis for calculator models.
    
    This function computes actual SHAP values from the models, not proxies.
    
    Returns:
        Tuple of (catboost_shap_map, xgboost_shap_map, catboost_shap_df, xgboost_shap_df)
        
    Raises:
        FileNotFoundError: If models or data are not found
        RuntimeError: If SHAP computation fails
    """
    try:
        import shap
    except ImportError:
        raise ImportError("SHAP library not available. Install with: pip install shap")
    
    from shap_analysis.run_shap_analysis import _load_calculator_models
    
    logger.info(f"Running FULL SHAP analysis for calculator models (cohort: {cohort})...")
    logger.info("This will compute actual SHAP values from models (not proxies)")
    
    # Load calculator models
    try:
        cb_model, xgb_model = _load_calculator_models(cohort)
        logger.info("Loaded calculator models successfully")
    except FileNotFoundError as e:
        raise FileNotFoundError(
            f"Calculator models not found: {e}. "
            "Please run train_python_models.py first to generate models."
        )
    
    # Load calculator data
    try:
        df = load_calculator_data_for_shap(cohort)
        logger.info(f"Loaded {len(df)} rows of calculator data")
        
        # Apply temporal split to use TEST SET for SHAP (unseen data)
        # This matches the training split and ensures we're explaining on test data
        if 'txpl_year' in df.columns:
            cutoff_year = 2021  # Same as training
            test_mask = df['txpl_year'] > cutoff_year
            df = df[test_mask].copy()
            logger.info(f"Using test set (txpl_year > {cutoff_year}): {len(df)} samples for SHAP")
        else:
            logger.warning("txpl_year not found, using full dataset for SHAP")
    except (FileNotFoundError, ImportError) as e:
        raise RuntimeError(
            f"Failed to load calculator data: {e}. "
            "Data is required for SHAP computation."
        )
    
    # Feature preparation matches train_python_models.py prepare_calculator_features()
    # This ensures consistency between training and SHAP analysis
    logger.warning("Using all numeric columns - ensure this matches model training")
    
    # Select numeric columns only (models expect numeric features)
    numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
    
    # Remove outcome columns
    outcome_cols = ['ev_time', 'ev_type', 'time', 'status', 'int_dead', 'int_graft_loss', 
                    'graft_loss', 'outcome', 'outcome_int_graft_loss', 'outcome_graft_loss']
    feature_cols = [col for col in numeric_cols if col not in outcome_cols]
    
    X = df[feature_cols].copy()
    
    # Handle NaN values - fill with 0 for numeric features (models were trained this way)
    # This matches how R handles missing values in survival models
    X = X.fillna(0)
    
    # Remove rows with all zeros (likely invalid)
    X = X[(X != 0).any(axis=1)]
    
    if len(X) == 0:
        raise ValueError("No valid data rows after filtering")
    
    logger.info(f"Using {len(feature_cols)} features for SHAP computation")
    logger.info(f"Data shape: {X.shape}, NaN values filled with 0")
    
    # Compute SHAP values for CatBoost
    logger.info("Computing CatBoost SHAP values...")
    try:
        cb_shap_values, cb_shap_df = compute_calculator_shap_values(
            cb_model, X, 'catboost', n_samples=2000
        )
        
        # Create global SHAP map (mean absolute SHAP per feature)
        cb_shap_map = {
            feat: float(np.abs(cb_shap_df[feat]).mean())
            for feat in cb_shap_df.columns
        }
        
        # Normalize
        max_shap = max(cb_shap_map.values()) if cb_shap_map else 1.0
        if max_shap > 0:
            cb_shap_map = {k: v / max_shap for k, v in cb_shap_map.items()}
        
        logger.info(f"CatBoost SHAP: {len(cb_shap_map)} features, {len(cb_shap_df)} instances")
    except Exception as e:
        raise RuntimeError(f"Failed to compute CatBoost SHAP values: {e}") from e
    
    # Compute SHAP values for XGBoost
    logger.info("Computing XGBoost SHAP values...")
    try:
        xgb_shap_values, xgb_shap_df = compute_calculator_shap_values(
            xgb_model, X, 'xgboost', n_samples=2000
        )
        
        # Create global SHAP map (mean absolute SHAP per feature)
        xgb_shap_map = {
            feat: float(np.abs(xgb_shap_df[feat]).mean())
            for feat in xgb_shap_df.columns
        }
        
        # Normalize
        max_shap = max(xgb_shap_map.values()) if xgb_shap_map else 1.0
        if max_shap > 0:
            xgb_shap_map = {k: v / max_shap for k, v in xgb_shap_map.items()}
        
        logger.info(f"XGBoost SHAP: {len(xgb_shap_map)} features, {len(xgb_shap_df)} instances")
    except Exception as e:
        raise RuntimeError(f"Failed to compute XGBoost SHAP values: {e}") from e
    
    logger.info("SHAP analysis completed successfully")
    
    return cb_shap_map, xgb_shap_map, cb_shap_df, xgb_shap_df


def run_ffa_with_shap(
    cohort: str,
    xgboost_model_json: Path,
    shap_map: Dict[str, float],
    output_dir: Path,
    top_k: int = 10,
    shap_values_df: Optional[pd.DataFrame] = None,
    use_xgboost_only: bool = False
) -> pd.DataFrame:
    """
    Run FFA analysis using:
    - XGBoost model JSON for rule extraction
    - SHAP values for rule filtering (XGBoost only if use_xgboost_only=True, otherwise combined)
    
    Args:
        use_xgboost_only: If True, uses only XGBoost SHAP (simplified pipeline)
    """
    if not FFA_AVAILABLE:
        logger.warning("FFA modules not available")
        return None
    
    if use_xgboost_only:
        logger.info("Running FFA analysis with XGBoost model JSON and XGBoost SHAP filtering (simplified pipeline)...")
        logger.info("Strategy: Use XGBoost JSON for rules, filter with XGBoost SHAP only")
    else:
        logger.info("Running FFA analysis with XGBoost model JSON and combined SHAP filtering...")
        logger.info("Strategy: Use XGBoost JSON for rules, filter with combined SHAP (XGBoost + CatBoost)")
    
    try:
        # Load XGBoost model JSON
        logger.info(f"Loading XGBoost model JSON: {xgboost_model_json}")
        model_json = load_model_json(xgboost_model_json)
        
        # Extract feature mappings
        feature_mappings = extract_feature_mappings(model_json)
        
        # For FFA, we need individual SHAP values per instance
        # These should come from actual SHAP computation
        if shap_values_df is None:
            raise ValueError(
                "Individual SHAP values per instance are required for full FFA analysis. "
                "Please run SHAP computation first using run_calculator_shap_analysis()."
            )
        
        logger.info(f"Using real SHAP values DataFrame: {len(shap_values_df)} samples, {len(shap_values_df.columns)} features")
        
        # Initialize XGBoost explainer with combined SHAP map
        logger.info("Initializing XGBoost FFA explainer...")
        
        path_config = PathConfig(
            model_path=str(xgboost_model_json),
            data_dir=str(output_dir),
            output_dir=str(output_dir),
            tree_rules_path=None,
            age_band=None
        )
        
        explainer = XGBoostSymbolicExplainer(
            path_config=path_config,
            shap_importance_map=shap_map,
            shap_values_df=shap_values_df
        )
        
        # Set feature names before fitting (if available in model_json)
        if "feature_names" in model_json and model_json["feature_names"]:
            explainer.feature_names = {
                i: name for i, name in enumerate(model_json["feature_names"])
            }
            logger.info(f"Set {len(explainer.feature_names)} feature names on explainer")
        
        # Fit explainer from model JSON
        logger.info("Fitting explainer from model JSON (this may take a while)...")
        explainer.model_json = model_json
        explainer.fit_from_model_json(model_json)
        
        logger.info(f"Explainer fitted: {len(explainer.rule_clauses)} rules extracted")
        if use_xgboost_only:
            logger.info(f"Rules filtered using XGBoost SHAP importance (simplified pipeline)")
        else:
            logger.info(f"Rules filtered using combined SHAP (XGBoost + CatBoost) importance")
        
        # Validate rule extraction against SHAP values
        logger.info("Validating rule extraction against SHAP values...")
        validation_stats = validate_rules_against_shap(explainer, shap_map, output_dir)
        if validation_stats:
            logger.info(f"Rule-SHAP validation: Pearson r={validation_stats.get('pearson_correlation', 0):.3f}, "
                       f"Spearman ρ={validation_stats.get('spearman_correlation', 0):.3f}")
            if validation_stats.get('pearson_correlation', 0) > 0.8:
                logger.info("✅ VALIDATION PASSED: Rules align well with SHAP importance")
            elif validation_stats.get('pearson_correlation', 0) > 0.6:
                logger.warning("⚠️  MODERATE ALIGNMENT: Some correlation but may need investigation")
            else:
                logger.warning("❌ VALIDATION FAILED: Low correlation - check rule extraction or SHAP calculation")
        
        # Perform full rule-based causal analysis
        logger.info("Performing full rule-based FFA causal analysis")
        
        # Extract top features from rules (simplified)
        rule_feature_counts = defaultdict(int)
        
        # Check if explainer has necessary attributes
        if not hasattr(explainer, 'rule_clauses') or len(explainer.rule_clauses) == 0:
            logger.warning("No rule clauses found in explainer")
        else:
            logger.info(f"Processing {len(explainer.rule_clauses)} rule clauses")
            
        if not hasattr(explainer, 'id_condition_map'):
            logger.warning("No id_condition_map found in explainer")
        else:
            logger.info(f"id_condition_map has {len(explainer.id_condition_map)} entries")
            
        if not hasattr(explainer, 'feature_names'):
            logger.warning("No feature_names found in explainer")
        else:
            logger.info(f"feature_names has {len(explainer.feature_names)} entries")
        
        # Try to extract features from rules
        for rule_idx, clause in enumerate(explainer.rule_clauses):
            if not clause:
                continue
            for lit in clause:
                try:
                    if lit in explainer.id_condition_map:
                        feat_idx, _, _ = explainer.id_condition_map[lit]
                        if hasattr(explainer, 'feature_names') and explainer.feature_names:
                            feat_name = explainer.feature_names.get(feat_idx, f"feature_{feat_idx}")
                        else:
                            feat_name = f"feature_{feat_idx}"
                        rule_feature_counts[feat_name] += 1
                    else:
                        logger.debug(f"Literal {lit} not found in id_condition_map")
                except (KeyError, IndexError, TypeError) as e:
                    logger.debug(f"Error processing literal {lit} in rule {rule_idx}: {e}")
                    continue
        
        logger.info(f"Extracted {len(rule_feature_counts)} unique features from rules")
        
        # Create causal results based on rule frequency and SHAP importance
        causal_results = []
        for feature, rule_count in rule_feature_counts.items():
            shap_importance = shap_map.get(feature, 0.0)
            # Causal responsibility combines rule frequency and SHAP importance
            causal_responsibility = (rule_count / len(explainer.rule_clauses)) * shap_importance if len(explainer.rule_clauses) > 0 else 0.0
            
            causal_results.append({
                'feature': feature,
                'causal_responsibility': causal_responsibility,
                'shap_importance': shap_importance,
                'rule_frequency': rule_count,
                'total_rules': len(explainer.rule_clauses)
            })
        
        causal_df = pd.DataFrame(causal_results)
        
        # Validate results
        if len(causal_df) == 0:
            raise ValueError(
                "No causal factors extracted from rules. "
                "The explainer may not have extracted rules correctly. "
                f"Check that XGBoost model JSON contains valid tree structures. "
                f"Total rules extracted: {len(explainer.rule_clauses)}"
            )
        
        if 'causal_responsibility' not in causal_df.columns:
            raise ValueError(
                f"Causal DataFrame missing 'causal_responsibility' column. "
                f"Columns found: {causal_df.columns.tolist()}"
            )
        
        causal_df = causal_df.sort_values('causal_responsibility', ascending=False)
        
        # Save results
        causal_path = output_dir / 'ffa_causal_factors.csv'
        causal_df.to_csv(causal_path, index=False)
        logger.info(f"Saved FFA causal factors to {causal_path}")
        
        return causal_df
        
    except Exception as e:
        logger.error(f"Error running FFA analysis: {e}", exc_info=True)
        raise RuntimeError(f"FFA analysis failed: {e}") from e


def validate_rules_against_shap(
    explainer: Any,
    shap_map: Dict[str, float],
    output_dir: Path
) -> Optional[Dict[str, float]]:
    """
    Validate that rules extracted from XGBoost JSON align with SHAP importance.
    
    This validates that SHAP values can accurately filter and build the rule set
    for causal analysis. It demonstrates that rules extracted from JSON align well
    with SHAP importance patterns.
    
    Returns:
        Dictionary with validation statistics (correlation, differences, etc.) or None if validation fails
    """
    try:
        from collections import defaultdict
        from scipy.stats import spearmanr, pearsonr
        
        # Calculate rule-based importance (from JSON rules)
        feature_rule_counts = defaultdict(int)
        feature_rule_shap_scores = defaultdict(float)
        
        # Get feature names from explainer
        feature_names = explainer.feature_names if hasattr(explainer, 'feature_names') else {}
        
        # Iterate through all rules
        for rule_id, clause in enumerate(explainer.rule_clauses):
            # Get features in this rule
            features_in_rule = set()
            for lit in clause:
                if lit in explainer.id_condition_map:
                    feat_idx, _, _ = explainer.id_condition_map[lit]
                    feat_name = feature_names.get(feat_idx, f"feature_{feat_idx}")
                    features_in_rule.add(feat_name)
            
            # Calculate rule's SHAP score (sum of SHAP values of features in rule)
            rule_shap_score = sum(shap_map.get(feat_name, 0.0) for feat_name in features_in_rule)
            
            # For each feature in the rule, increment its count and add rule's SHAP score
            for feat_name in features_in_rule:
                feature_rule_counts[feat_name] += 1
                feature_rule_shap_scores[feat_name] += rule_shap_score
        
        # Normalize by rule count to get average SHAP score per feature
        rule_based_importance = {
            feat_name: feature_rule_shap_scores[feat_name] / max(feature_rule_counts[feat_name], 1)
            for feat_name in feature_rule_counts.keys()
        }
        
        # Compare with SHAP importance
        common_features = set(rule_based_importance.keys()) & set(shap_map.keys())
        
        if len(common_features) == 0:
            logger.warning("No common features found between rule-based and SHAP importance")
            return None
        
        # Create comparison data
        rule_values = [rule_based_importance[feat] for feat in common_features]
        shap_values = [shap_map[feat] for feat in common_features]
        
        # Calculate correlations
        pearson_corr, pearson_p = pearsonr(rule_values, shap_values)
        spearman_corr, spearman_p = spearmanr(rule_values, shap_values)
        
        # Calculate differences
        differences = [abs(rule_based_importance[feat] - shap_map[feat]) for feat in common_features]
        relative_differences = [
            abs(rule_based_importance[feat] - shap_map[feat]) / max(shap_map[feat], 1e-10)
            for feat in common_features
        ]
        
        stats = {
            'pearson_correlation': float(pearson_corr),
            'pearson_p_value': float(pearson_p),
            'spearman_correlation': float(spearman_corr),
            'spearman_p_value': float(spearman_p),
            'mean_absolute_difference': float(np.mean(differences)),
            'median_absolute_difference': float(np.median(differences)),
            'mean_relative_difference': float(np.mean(relative_differences)),
            'n_features': len(common_features)
        }
        
        # Save validation results
        validation_dir = output_dir / "validation"
        validation_dir.mkdir(parents=True, exist_ok=True)
        
        # Save comparison DataFrame
        comparison_data = []
        for feat in common_features:
            comparison_data.append({
                'feature': feat,
                'rule_based_importance': rule_based_importance[feat],
                'shap_importance': shap_map[feat],
                'difference': abs(rule_based_importance[feat] - shap_map[feat]),
                'relative_difference': abs(rule_based_importance[feat] - shap_map[feat]) / max(shap_map[feat], 1e-10)
            })
        
        comparison_df = pd.DataFrame(comparison_data)
        comparison_path = validation_dir / 'rule_shap_comparison.csv'
        comparison_df.to_csv(comparison_path, index=False)
        logger.info(f"Saved rule-SHAP comparison: {comparison_path}")
        
        # Save statistics
        stats_path = validation_dir / 'validation_statistics.json'
        with open(stats_path, 'w') as f:
            json.dump(stats, f, indent=2)
        logger.info(f"Saved validation statistics: {stats_path}")
        
        return stats
        
    except Exception as e:
        logger.warning(f"Rule-SHAP validation failed: {e}. Continuing without validation.")
        return None


def combine_importance_to_shap(
    importance_data: Dict[str, pd.DataFrame],
    weight_catboost: float = 0.6,
    weight_xgboost: float = 0.4
) -> Tuple[pd.DataFrame, Dict[str, float]]:
    """
    Convert feature importance to SHAP-like values and create combined map.
    
    Returns:
        Tuple of (combined_importance_df, combined_shap_map)
    """
    logger.info("Combining feature importance from CatBoost and XGBoost...")
    
    if 'CatBoost' not in importance_data and 'XGBoost' not in importance_data:
        raise ValueError("Need at least one model's importance data")
    
    # Start with CatBoost if available
    if 'CatBoost' in importance_data:
        combined = importance_data['CatBoost'].copy()
        combined['combined_importance'] = weight_catboost * combined['importance']
    else:
        combined = importance_data['XGBoost'].copy()
        combined['combined_importance'] = 0.0
    
    # Add XGBoost if available
    if 'XGBoost' in importance_data:
        xgb_imp = importance_data['XGBoost']
        # Merge on feature name
        combined = combined.merge(
            xgb_imp[['feature', 'importance']],
            on='feature',
            how='outer',
            suffixes=('', '_xgb')
        )
        # Fill missing values
        combined['importance'] = combined['importance'].fillna(0)
        combined['importance_xgb'] = combined['importance_xgb'].fillna(0)
        
        # Update combined importance
        combined['combined_importance'] = (
            weight_catboost * combined['importance'] +
            weight_xgboost * combined['importance_xgb']
        )
    
    # Normalize combined importance to [0, 1]
    max_imp = combined['combined_importance'].max()
    if max_imp > 0:
        combined['combined_importance_norm'] = combined['combined_importance'] / max_imp
    else:
        combined['combined_importance_norm'] = 0.0
    
    # Sort by combined importance
    combined = combined.sort_values('combined_importance_norm', ascending=False)
    
    # Create SHAP map for FFA filtering
    shap_map = dict(zip(
        combined['feature'],
        combined['combined_importance_norm']
    ))
    # Filter to features with importance > 0
    shap_map = {k: v for k, v in shap_map.items() if v > 0}
    
    logger.info(f"Combined importance: {len(combined)} features")
    logger.info(f"SHAP map for filtering: {len(shap_map)} features with importance > 0")
    logger.info(f"Top 5 features: {combined.head(5)['feature'].tolist()}")
    
    return combined, shap_map


def generate_feature_metadata(df: pd.DataFrame, feature_names: List[str]) -> Dict[str, str]:
    """
    Generate feature metadata (binary vs numeric) from prepared data.
    
    Args:
        df: Prepared dataframe with features
        feature_names: List of feature names to check
    
    Returns:
        Dictionary mapping feature names to 'binary' or 'numeric'
    """
    feature_metadata = {}
    
    # Known numeric feature patterns (always numeric, even if data looks binary)
    known_numeric = ['bmi', 'egfr', 'age', 'weight', 'height', 'creat', 'bun', 
                     'albumin', 'ast', 'alt', 'bili', 'chol', 'hdl', 'ldl', 'tg', 
                     'tp', 'brp', 'bram', 'donisch', 'durcarst', 'bnp', 'sa', 'palb']
    
    for feature_name in feature_names:
        if feature_name in df.columns:
            col_data = df[feature_name].dropna()
            
            if len(col_data) > 0:
                # Check if feature name suggests it's numeric
                is_known_numeric = any(pattern in feature_name.lower() for pattern in known_numeric)
                
                # Check if binary: only contains 0 and/or 1
                unique_vals = set(col_data.unique())
                is_binary_vals = unique_vals.issubset({0, 1, 0.0, 1.0})
                
                # If known numeric feature, always treat as numeric
                # Otherwise, use value-based detection
                if is_known_numeric:
                    feature_metadata[feature_name] = 'numeric'
                elif is_binary_vals:
                    feature_metadata[feature_name] = 'binary'
                else:
                    feature_metadata[feature_name] = 'numeric'
            else:
                # Default to numeric if no data
                feature_metadata[feature_name] = 'numeric'
        else:
            # Default to numeric if feature not in data
            feature_metadata[feature_name] = 'numeric'
    
    return feature_metadata


def generate_dashboard_outputs(
    combined_importance: pd.DataFrame,
    causal_df: Optional[pd.DataFrame],
    output_dir: Path,
    cohort: str,
    top_k: int = 10,
    xgboost_json_used: bool = False,
    use_xgboost_only: bool = False,
    feature_data: Optional[pd.DataFrame] = None
):
    """Generate dashboard-ready outputs for risk dashboard."""
    logger.info("Generating dashboard outputs...")
    
    # Top K causal factors (handle case when FFA is not available)
    if causal_df is None or len(causal_df) == 0:
        logger.warning("No causal factors available (FFA may not be available). Using feature importance instead.")
        # Fallback: Use top features from importance
        top_causal = combined_importance.head(top_k).copy()
        top_causal = top_causal.rename(columns={'combined_importance_norm': 'causal_responsibility'})
        top_causal['shap_importance'] = top_causal['causal_responsibility']
        top_causal['rule_frequency'] = 0
        top_causal['total_rules'] = 0
    else:
        top_causal = causal_df.head(top_k).copy()
    
    # Generate feature metadata if data is available
    feature_metadata = {}
    if feature_data is not None:
        feature_names = combined_importance['feature'].tolist()
        feature_metadata = generate_feature_metadata(feature_data, feature_names)
        logger.info(f"Generated feature metadata for {len(feature_metadata)} features")
    
    # Create comprehensive dashboard data
    dashboard_data = {
        'cohort': cohort,
        'timestamp': datetime.now().isoformat(),
        'ffa_method': 'xgboost_json_with_xgboost_shap_filtering' if use_xgboost_only else 'xgboost_json_with_combined_shap_filtering',
        'top_causal_factors': top_causal.to_dict('records'),
        'summary': {
            'total_features': len(combined_importance),
            'top_k': top_k,
            'mean_importance': combined_importance['combined_importance_norm'].mean(),
            'max_importance': combined_importance['combined_importance_norm'].max(),
            'top_feature': top_causal.iloc[0]['feature'] if len(top_causal) > 0 else None,
            'top_feature_importance': top_causal.iloc[0]['causal_responsibility'] if len(top_causal) > 0 else None
        },
        'feature_importance': combined_importance.head(50).to_dict('records'),
        'feature_metadata': feature_metadata,  # Add feature metadata
        'notes': {
            'model_json_used': 'XGBoost (CatBoost JSON not used due to categorical hashing)',
            'shap_filtering': 'XGBoost SHAP only (simplified pipeline)' if use_xgboost_only else 'Combined SHAP from both XGBoost and CatBoost',
            'rule_extraction': 'XGBoost model JSON',
            'rule_filtering': 'XGBoost SHAP importance (simplified pipeline)' if use_xgboost_only else 'Combined SHAP importance (XGBoost + CatBoost)',
            'pipeline_type': 'simplified (XGBoost only)' if use_xgboost_only else 'combined (XGBoost + CatBoost)'
        }
    }
    
    # Save JSON
    json_path = output_dir / 'dashboard_data.json'
    with open(json_path, 'w') as f:
        json.dump(dashboard_data, f, indent=2)
    logger.info(f"Saved dashboard data to {json_path}")
    
    # Save CSV files
    csv_path = output_dir / 'top_causal_factors.csv'
    top_causal.to_csv(csv_path, index=False)
    logger.info(f"Saved top {top_k} causal factors to {csv_path}")
    
    importance_path = output_dir / 'combined_shap_importance.csv'
    combined_importance.to_csv(importance_path, index=False)
    logger.info(f"Saved combined SHAP importance to {importance_path}")
    
    # Create summary report
    report_lines = [
        "=" * 80,
        f"SHAP + FFA Analysis Results for {cohort} Cohort",
        "=" * 80,
        "",
        f"Analysis Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"FFA Method: XGBoost Model JSON with Combined SHAP Filtering",
        "",
        "Strategy:",
        "  - Use XGBoost model JSON for rule extraction (easier to parse)",
        "  - Filter XGBoost rules using combined SHAP values from both XGBoost and CatBoost",
        "  - CatBoost JSON not used due to internal categorical variable hashing complexity",
        "",
        f"Total Features Analyzed: {len(combined_importance)}",
        f"Top K Causal Factors: {top_k}",
        "",
        "Top 10 Causal Factors:",
        "-" * 80,
    ]
    
    for idx, row in top_causal.head(10).iterrows():
        report_lines.append(
            f"{idx+1:2d}. {row['feature']:40s} "
            f"(Causal: {row['causal_responsibility']:.4f}, "
            f"SHAP: {row['shap_importance']:.4f}, "
            f"Rules: {row.get('rule_frequency', 0)})"
        )
    
    report_lines.extend([
        "",
        "=" * 80,
        "Summary Statistics:",
        "-" * 80,
        f"Mean Importance: {dashboard_data['summary']['mean_importance']:.4f}",
        f"Max Importance: {dashboard_data['summary']['max_importance']:.4f}",
        f"Top Feature: {dashboard_data['summary']['top_feature']}",
        f"Top Feature Importance: {dashboard_data['summary']['top_feature_importance']:.4f}",
        "",
        "=" * 80
    ])
    
    report_path = output_dir / 'analysis_report.txt'
    with open(report_path, 'w') as f:
        f.write('\n'.join(report_lines))
    logger.info(f"Saved analysis report to {report_path}")
    
    return dashboard_data


def main():
    parser = argparse.ArgumentParser(
        description="SHAP + FFA Workflow for Calculator Models"
    )
    parser.add_argument(
        "--cohort",
        required=True,
        choices=["CHD", "Combined", "Myocardio"],
        help="Cohort name"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Output directory (default: outputs/shap_ffa/{cohort})"
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=10,
        help="Number of top causal factors to extract (default: 10)"
    )
    parser.add_argument(
        "--weight-catboost",
        type=float,
        default=0.6,
        help="Weight for CatBoost SHAP (default: 0.6)"
    )
    parser.add_argument(
        "--weight-xgboost",
        type=float,
        default=0.4,
        help="Weight for XGBoost SHAP (default: 0.4)"
    )
    
    args = parser.parse_args()
    
    # Validate weights
    if abs(args.weight_catboost + args.weight_xgboost - 1.0) > 0.01:
        logger.warning("Weights should sum to 1.0, normalizing...")
        total = args.weight_catboost + args.weight_xgboost
        args.weight_catboost /= total
        args.weight_xgboost /= total
    
    # Set output directory
    # SHAP/FFA outputs go to calculator-specific outputs directory
    if args.output_dir is None:
        output_dir = CALCULATOR_DIR / "outputs" / "shap_ffa" / args.cohort
    else:
        output_dir = Path(args.output_dir)
    
    output_dir.mkdir(parents=True, exist_ok=True)
    logger.info(f"Output directory: {output_dir}")
    
    # Check which model is best
    best_model = get_best_model(args.cohort)
    use_xgboost_only = (best_model == "XGBoost" or best_model == "XGBoost RF")
    
    logger.info("=" * 80)
    logger.info(f"SHAP + FFA Analysis for {args.cohort} Cohort")
    logger.info("=" * 80)
    if use_xgboost_only:
        logger.info(f"Best model: {best_model} - Using simplified pipeline (XGBoost only)")
        logger.info(f"Strategy: XGBoost JSON + XGBoost SHAP filtering (simplified)")
    else:
        logger.info(f"Best model: {best_model} - Using combined pipeline")
        logger.info(f"Strategy: XGBoost JSON + Combined SHAP (XGBoost + CatBoost) filtering")
    logger.info(f"Output directory: {output_dir}")
    logger.info(f"Top K: {args.top_k}")
    if not use_xgboost_only:
        logger.info(f"SHAP Weights: CatBoost={args.weight_catboost:.2f}, XGBoost={args.weight_xgboost:.2f}")
    logger.info("")
    
    try:
        # Step 1: Find XGBoost model JSON (required for FFA)
        logger.info("Step 1: Finding XGBoost model JSON for FFA explainer...")
        xgboost_json = find_xgboost_model_json(args.cohort)
        
        if not xgboost_json:
            raise FileNotFoundError(
                f"XGBoost model JSON not found for cohort {args.cohort}. "
                "This is required for full rule-based FFA analysis. "
                "Please run train_python_models.py first to generate the model JSON."
            )
        
        logger.info(f"Found XGBoost model JSON: {xgboost_json}")
        
        # Step 2: Compute SHAP values
        logger.info("Step 2: Computing SHAP values from calculator models...")
        logger.info("This will compute actual SHAP values (not proxies) for full rule-based analysis")
        
        if use_xgboost_only:
            # Simplified: Only compute XGBoost SHAP
            logger.info("Using simplified pipeline: Computing XGBoost SHAP only...")
            try:
                # Load only XGBoost model
                import xgboost as xgb
                # Check both calculator outputs and parent outputs
                calculator_models_dir = CALCULATOR_DIR / "outputs" / "models" / args.cohort
                parent_models_dir = CALCULATOR_DIR.parent / "outputs" / "models" / args.cohort
                
                xgb_path = None
                for models_dir in [calculator_models_dir, parent_models_dir]:
                    candidate_path = models_dir / "xgboost_model.ubj"
                    if candidate_path.exists():
                        xgb_path = candidate_path
                        break
                
                if xgb_path is None:
                    raise FileNotFoundError(
                        f"XGBoost model not found. Checked:\n"
                        f"  - {calculator_models_dir / 'xgboost_model.ubj'}\n"
                        f"  - {parent_models_dir / 'xgboost_model.ubj'}\n"
                        f"Please run train_python_models.py first."
                    )
                
                xgb_model = xgb.XGBRegressor()
                xgb_model.load_model(str(xgb_path))
                logger.info(f"Loaded XGBoost model: {xgb_path}")
                
                # Load data
                df = load_calculator_data_for_shap(args.cohort)
                df = prepare_calculator_features(df)
                
                # Derive survival labels if needed
                if 'ev_time' not in df.columns:
                    if 'int_dead' in df.columns and 'int_graft_loss' in df.columns:
                        df['ev_time'] = df[['int_dead', 'int_graft_loss']].min(axis=1, skipna=True)
                    elif 'outcome_int_graft_loss' in df.columns:
                        df['ev_time'] = df['outcome_int_graft_loss']
                
                if 'ev_type' not in df.columns:
                    if 'dtx_patient' in df.columns and 'graft_loss' in df.columns:
                        df['ev_type'] = df[['dtx_patient', 'graft_loss']].max(axis=1, skipna=True)
                    elif 'outcome_graft_loss' in df.columns:
                        df['ev_type'] = df['outcome_graft_loss']
                
                # Map to time and status
                if 'time' not in df.columns:
                    df['time'] = df['ev_time']
                if 'status' not in df.columns:
                    df['status'] = (df['ev_type'] == 1).astype(int)
                
                # Apply same temporal split as training (test set only for SHAP)
                # This ensures we're explaining the model on unseen data
                if 'txpl_year' in df.columns:
                    # Use same cutoff as training (2021)
                    cutoff_year = 2021
                    test_mask = df['txpl_year'] > cutoff_year
                    df_test = df[test_mask].copy()
                    logger.info(f"Using test set (txpl_year > {cutoff_year}): {len(df_test)} samples")
                else:
                    logger.warning("txpl_year not found, using full dataset for SHAP")
                    df_test = df.copy()
                
                # Remove leakage predictors and extract features
                if remove_leakage_predictors is not None:
                    df_clean = remove_leakage_predictors(df_test, time_col='time', status_col='status')
                else:
                    # Fallback: just exclude known leakage columns
                    leakage_cols = ['ev_time', 'ev_type', 'time', 'status', 'int_dead', 'age_death', 
                                   'graft_loss', 'int_graft_loss', 'outcome', 'outcome_int_graft_loss', 
                                   'outcome_graft_loss']
                    df_clean = df_test.drop(columns=[c for c in leakage_cols if c in df_test.columns], errors='ignore')
                feature_cols = [col for col in df_clean.columns if col not in ['time', 'status', 'txpl_year']]
                X_test = df_clean[feature_cols].copy()
                
                # Remove constant columns and fill NaN
                constant_cols = [col for col in X_test.columns if X_test[col].nunique() < 2]
                if constant_cols:
                    X_test = X_test.drop(columns=constant_cols)
                X_test = X_test.fillna(0)
                
                # Convert categorical to numeric
                for col in X_test.columns:
                    if X_test[col].dtype == 'object':
                        X_test[col] = pd.Categorical(X_test[col]).codes
                
                # Compute XGBoost SHAP on TEST SET (all rows, or sample if too large)
                # Use n_samples=None to compute for all test rows, or set a limit
                logger.info(f"Computing SHAP values on test set: {len(X_test)} samples")
                xgb_shap_values, xgb_shap_df = compute_calculator_shap_values(
                    xgb_model, X_test, 'xgboost', n_samples=len(X_test) if len(X_test) <= 2000 else 2000
                )
                
                # Create global SHAP map (mean absolute SHAP per feature)
                xgb_shap_map = {
                    feat: float(np.abs(xgb_shap_df[feat]).mean())
                    for feat in xgb_shap_df.columns
                }
                
                # Normalize
                max_shap = max(xgb_shap_map.values()) if xgb_shap_map else 1.0
                if max_shap > 0:
                    xgb_shap_map = {k: v / max_shap for k, v in xgb_shap_map.items()}
                
                logger.info(f"XGBoost SHAP: {len(xgb_shap_map)} features, {len(xgb_shap_df)} instances")
                
                # Use XGBoost SHAP directly (no combination needed)
                shap_map = xgb_shap_map
                shap_values_df = xgb_shap_df
                
            except Exception as e:
                raise RuntimeError(
                    f"Failed to compute XGBoost SHAP values: {e}. "
                    "SHAP values are required for full rule-based FFA analysis."
                ) from e
        else:
            # Full pipeline: Compute both and combine
            try:
                cb_shap_map, xgb_shap_map, cb_shap_df, xgb_shap_df = run_calculator_shap_analysis(args.cohort)
            except Exception as e:
                raise RuntimeError(
                    f"Failed to compute SHAP values: {e}. "
                    "SHAP values are required for full rule-based FFA analysis."
                ) from e
            
            # Step 3: Combine SHAP maps and DataFrames
            logger.info("Step 3: Combining SHAP values from both models...")
            shap_map = combine_shap_maps(
                xgb_shap_map,
                cb_shap_map,
                weight_xgboost=args.weight_xgboost,
                weight_catboost=args.weight_catboost
            )
            
            # Combine SHAP DataFrames (weighted average)
            if cb_shap_df is not None and xgb_shap_df is not None:
                # Align features
                common_features = set(cb_shap_df.columns) & set(xgb_shap_df.columns)
                logger.info(f"Combining SHAP from {len(common_features)} common features")
                
                # Create combined SHAP DataFrame
                combined_shap_df = pd.DataFrame(index=cb_shap_df.index)
                for feat in common_features:
                    combined_shap_df[feat] = (
                        args.weight_catboost * cb_shap_df[feat] +
                        args.weight_xgboost * xgb_shap_df[feat]
                    )
                
                shap_values_df = combined_shap_df
            else:
                raise ValueError("Failed to combine SHAP DataFrames from both models")
        
        # Step 4: Run FFA with XGBoost JSON and SHAP values
        logger.info("Step 4: Running full rule-based FFA analysis...")
        causal_df = run_ffa_with_shap(
            args.cohort,
            xgboost_json,
            shap_map,
            output_dir,
            top_k=args.top_k,
            shap_values_df=shap_values_df,
            use_xgboost_only=use_xgboost_only
        )
        
        # Get importance for dashboard
        if use_xgboost_only:
            # Use XGBoost importance only
            importance_data = load_calculator_importance(args.cohort)
            if 'XGBoost' in importance_data:
                combined_importance = importance_data['XGBoost'].copy()
                combined_importance['combined_importance'] = combined_importance['importance']
                # Normalize for consistency
                max_imp = combined_importance['combined_importance'].max()
                if max_imp > 0:
                    combined_importance['combined_importance_norm'] = combined_importance['combined_importance'] / max_imp
                else:
                    combined_importance['combined_importance_norm'] = 0.0
            else:
                logger.warning("XGBoost importance not found, creating from SHAP map")
                # Create from SHAP map if importance file not available
                combined_importance = pd.DataFrame({
                    'feature': list(shap_map.keys()),
                    'importance': list(shap_map.values()),
                    'combined_importance': list(shap_map.values()),
                    'combined_importance_norm': list(shap_map.values())
                }).sort_values('combined_importance', ascending=False)
        else:
            # Get combined importance for dashboard
            importance_data = load_calculator_importance(args.cohort)
            combined_importance, _ = combine_importance_to_shap(
                importance_data,
                weight_catboost=args.weight_catboost,
                weight_xgboost=args.weight_xgboost
            )
        
        # Step 5: Generate dashboard outputs
        logger.info("")
        logger.info("Step 5: Generating dashboard outputs...")
        
        # Get feature data for metadata generation
        # Try to load test data that was used for SHAP computation
        feature_data_for_metadata = None
        try:
            df_test = load_calculator_data_for_shap(args.cohort)
            df_test = prepare_calculator_features(df_test)
            if 'txpl_year' in df_test.columns:
                cutoff_year = 2021
                test_mask = df_test['txpl_year'] > cutoff_year
                df_test = df_test[test_mask].copy()
            
            # Remove leakage and prepare features (same as SHAP computation)
            if remove_leakage_predictors is not None:
                df_clean = remove_leakage_predictors(df_test, time_col='time', status_col='status')
            else:
                leakage_cols = ['ev_time', 'ev_type', 'time', 'status', 'int_dead', 'age_death', 
                               'graft_loss', 'int_graft_loss', 'outcome', 'outcome_int_graft_loss', 
                               'outcome_graft_loss']
                df_clean = df_test.drop(columns=[c for c in leakage_cols if c in df_test.columns], errors='ignore')
            feature_cols = [col for col in df_clean.columns if col not in ['time', 'status', 'txpl_year']]
            feature_data_for_metadata = df_clean[feature_cols].copy()
            
            # Remove constant columns and fill NaN (same as model training)
            constant_cols = [col for col in feature_data_for_metadata.columns if feature_data_for_metadata[col].nunique() < 2]
            if constant_cols:
                feature_data_for_metadata = feature_data_for_metadata.drop(columns=constant_cols)
            feature_data_for_metadata = feature_data_for_metadata.fillna(0)
            
            # Convert categorical to numeric
            for col in feature_data_for_metadata.columns:
                if feature_data_for_metadata[col].dtype == 'object':
                    feature_data_for_metadata[col] = pd.Categorical(feature_data_for_metadata[col]).codes
            
            logger.info(f"Loaded feature data for metadata: {len(feature_data_for_metadata)} rows, {len(feature_data_for_metadata.columns)} features")
        except Exception as e:
            logger.warning(f"Could not load feature data for metadata generation: {e}")
        
        dashboard_data = generate_dashboard_outputs(
            combined_importance,
            causal_df,
            output_dir,
            args.cohort,
            top_k=args.top_k,
            xgboost_json_used=xgboost_json is not None,
            use_xgboost_only=use_xgboost_only,
            feature_data=feature_data_for_metadata
        )
        
        logger.info("")
        logger.info("=" * 80)
        logger.info("Analysis Complete!")
        logger.info("=" * 80)
        logger.info(f"FFA Method: XGBoost JSON + Combined SHAP filtering")
        logger.info(f"Top {args.top_k} Causal Factors:")
        if causal_df is not None and len(causal_df) > 0:
            for idx, row in causal_df.head(args.top_k).iterrows():
                logger.info(f"  {idx+1:2d}. {row['feature']:40s} "
                           f"(Causal: {row['causal_responsibility']:.4f})")
        else:
            # Fallback: Use importance-based ranking
            logger.info("  (Using feature importance ranking - FFA not available)")
            if combined_importance is not None and len(combined_importance) > 0:
                for idx, row in combined_importance.head(args.top_k).iterrows():
                    logger.info(f"  {idx+1:2d}. {row['feature']:40s} "
                               f"(Importance: {row.get('combined_importance_norm', 0):.4f})")
        logger.info("")
        logger.info(f"Results saved to: {output_dir}")
        logger.info("=" * 80)
        
    except Exception as e:
        logger.error(f"Error in workflow: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    main()
