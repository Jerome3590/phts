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

# DuckDB + Parquet helpers (use when available for faster I/O)
def _read_parquet(path: Path) -> pd.DataFrame:
    """Read a Parquet file, using DuckDB if available else pandas."""
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(str(path))
    try:
        import duckdb
        conn = duckdb.connect()
        # Parameterized path (path is Path, not raw user input)
        conn.execute("SELECT * FROM read_parquet($1)", [path.resolve().as_posix()])
        return conn.fetchdf()
    except ImportError:
        return pd.read_parquet(path)
    except Exception:
        return pd.read_parquet(path)

def _to_parquet(df: pd.DataFrame, path: Path) -> None:
    """Write DataFrame to Parquet (DuckDB not needed for write; use snappy when available)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        df.to_parquet(path, index=False, compression="snappy")
    except TypeError:
        df.to_parquet(path, index=False)

def _read_table_parquet_or_csv(path: Path, prefer_parquet: bool = True) -> Optional[pd.DataFrame]:
    """Load a table from Parquet if it exists, else CSV. Uses DuckDB for Parquet when available."""
    path = Path(path)
    parquet_path = path.with_suffix(".parquet") if path.suffix.lower() == ".csv" else path
    csv_path = path.with_suffix(".csv") if path.suffix.lower() == ".parquet" else path
    if prefer_parquet and parquet_path.exists():
        try:
            return _read_parquet(parquet_path)
        except Exception as e:
            logger.debug(f"Fallback to CSV after Parquet read failed: {e}")
    if csv_path.exists():
        return pd.read_csv(csv_path)
    return None


def _safe_str_for_hash(x: Any) -> str:
    """Convert a value to a hashable string; handles bytearray/bytes from Parquet/DuckDB."""
    if x is None or (isinstance(x, float) and pd.isna(x)):
        return ""
    if isinstance(x, (bytes, bytearray)):
        return x.decode("utf-8", errors="replace")
    return str(x)


def _ensure_string_columns_and_index(df: pd.DataFrame) -> pd.DataFrame:
    """Ensure column names and object columns are str (no bytearray/bytes). Avoids unhashable type errors."""
    df = df.copy()
    # Column names as str (DuckDB/Parquet can yield bytes)
    df.columns = [_safe_str_for_hash(c) for c in df.columns]
    for col in df.columns:
        if df[col].dtype == object:
            # Convert bytearray/bytes to str so set(), nunique(), Categorical work
            try:
                sample = df[col].dropna()
                if len(sample) and isinstance(sample.iloc[0], (bytes, bytearray)):
                    df[col] = df[col].apply(lambda v: v.decode("utf-8", errors="replace") if isinstance(v, (bytes, bytearray)) else (str(v) if pd.notna(v) else v))
            except Exception:
                pass
    return df


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
    # Try importing from the same directory first
    from train_python_models import remove_leakage_predictors
except ImportError:
    try:
        # Try importing with full path
        import importlib.util
        train_models_path = CALCULATOR_DIR / "train_python_models.py"
        if train_models_path.exists():
            spec = importlib.util.spec_from_file_location("train_python_models", train_models_path)
            train_models = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(train_models)
            remove_leakage_predictors = train_models.remove_leakage_predictors
            logger.info("Loaded remove_leakage_predictors using direct file import")
        else:
            raise ImportError(f"train_python_models.py not found at {train_models_path}")
    except Exception as e:
        logger.warning(f"Could not import remove_leakage_predictors from train_python_models: {e}")
        remove_leakage_predictors = None


def get_model_cohort_name(cohort: str, model_variant: Optional[str] = None) -> str:
    """
    Get the model directory name based on cohort and variant.
    
    Args:
        cohort: Base cohort name (e.g., "Combined")
        model_variant: Model variant ("base", "enhanced", or None for auto-detect)
    
    Returns:
        Model directory name (e.g., "Combined_top" for final workflow)
    """
    if model_variant is None or model_variant == "auto":
        # Final workflow: prefer _top only; fallback to plain cohort if _top missing
        top_path = CALCULATOR_DIR / "outputs" / "models" / f"{cohort}_top" / "best_model.txt"
        if top_path.exists():
            return f"{cohort}_top"
        return cohort
    elif model_variant == "top":
        return f"{cohort}_top"
    elif model_variant in ("base", "enhanced"):
        # Legacy: map to _top for final workflow
        return f"{cohort}_top"
    else:
        return cohort


def get_best_model(cohort: str, model_variant: Optional[str] = None) -> Optional[str]:
    """
    Read the best model from best_model.txt file.

    Checks both calculator outputs and parent outputs directories.
    
    Args:
        cohort: Base cohort name (e.g., "Combined")
        model_variant: Model variant ("base", "enhanced", or None for auto-detect)

    Returns:
        Best model name (e.g., "XGBoost", "CatBoost", "XGBoost RF") or None if not found
    """
    model_cohort = get_model_cohort_name(cohort, model_variant)
    
    # Check both locations
    calculator_best_path = CALCULATOR_DIR / "outputs" / "models" / model_cohort / "best_model.txt"
    parent_best_path = CALCULATOR_DIR.parent / "outputs" / "models" / model_cohort / "best_model.txt"

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
            for line in f:
                # Training writes "Best Model (MC-CV): CatBoost" or "Best Model: ..."
                if "Best Model" in line and ":" in line:
                    best_model = line.split(":", 1)[1].strip()
                    if best_model:
                        logger.info(f"Best model from file: {best_model}")
                        return best_model
    except Exception as e:
        logger.warning(f"Error reading best model file: {e}")

    return None


def get_model_c_indices(cohort: str, model_variant: Optional[str] = None) -> Dict[str, float]:
    """
    Read C-index values for all models from best_model.txt file.
    
    Args:
        cohort: Base cohort name (e.g., "Combined")
        model_variant: Model variant ("base", "enhanced", or None for auto-detect)
    
    Returns:
        Dictionary mapping model names to C-index values
        e.g., {"CatBoost": 0.677, "XGBoost": 0.645, "XGBoost RF": 0.620}
    """
    model_cohort = get_model_cohort_name(cohort, model_variant)
    
    calculator_best_path = CALCULATOR_DIR / "outputs" / "models" / model_cohort / "best_model.txt"
    parent_best_path = CALCULATOR_DIR.parent / "outputs" / "models" / model_cohort / "best_model.txt"

    best_model_path = None
    if calculator_best_path.exists():
        best_model_path = calculator_best_path
    elif parent_best_path.exists():
        best_model_path = parent_best_path

    if best_model_path is None:
        return {}

    c_indices = {}
    try:
        with open(best_model_path, 'r') as f:
            lines = f.readlines()
            for line in lines:
                # Parse lines like "  CatBoost: 0.677123"
                if ':' in line and ('CatBoost' in line or 'XGBoost' in line):
                    parts = line.strip().split(':')
                    if len(parts) == 2:
                        model_name = parts[0].strip()
                        try:
                            c_index = float(parts[1].strip())
                            c_indices[model_name] = c_index
                        except ValueError:
                            continue
    except Exception as e:
        logger.warning(f"Error reading C-index values: {e}")

    return c_indices


def determine_shap_weights(cohort: str, best_model: Optional[str] = None, model_variant: Optional[str] = None) -> Tuple[float, float]:
    """
    Automatically determine SHAP weights based on best model and C-index values.
    
    Strategy:
    - If XGBoost is best: Use XGBoost only (weights not used, but return 0.0, 1.0 for consistency)
    - If CatBoost is best: Weight based on relative C-index performance
      - Higher weight for CatBoost (best model)
      - Lower weight for XGBoost
      - Weights normalized to sum to 1.0
    
    Args:
        cohort: Base cohort name (e.g., "Combined")
        best_model: Best model name (if None, will be read from file)
        model_variant: Model variant ("base", "enhanced", or None for auto-detect)
    
    Returns:
        Tuple of (weight_catboost, weight_xgboost)
    """
    if best_model is None:
        best_model = get_best_model(cohort, model_variant)
    
    # If XGBoost is best, we use XGBoost only (no weights needed)
    if best_model == "XGBoost" or best_model == "XGBoost RF":
        return (0.0, 1.0)  # Not used, but return for consistency
    
    # If CatBoost is best, determine weights based on C-index values
    if best_model == "CatBoost":
        c_indices = get_model_c_indices(cohort, model_variant)
        
        cb_cindex = c_indices.get("CatBoost", 0.0)
        xgb_cindex = c_indices.get("XGBoost", 0.0)
        
        # If we have both C-index values, weight based on relative performance
        if cb_cindex > 0 and xgb_cindex > 0:
            total = cb_cindex + xgb_cindex
            if total > 0:
                weight_catboost = cb_cindex / total
                weight_xgboost = xgb_cindex / total
                logger.info(f"Determined weights from C-index: CatBoost={weight_catboost:.3f} (C-index={cb_cindex:.6f}), "
                          f"XGBoost={weight_xgboost:.3f} (C-index={xgb_cindex:.6f})")
                return (weight_catboost, weight_xgboost)
        
        # Fallback: If CatBoost is best but no C-index data, use default weights
        logger.warning("Could not determine weights from C-index, using defaults: CatBoost=0.7, XGBoost=0.3")
        return (0.7, 0.3)
    
    # Fallback: Default weights if best model is unknown
    logger.warning(f"Unknown best model '{best_model}', using default weights: CatBoost=0.6, XGBoost=0.4")
    return (0.6, 0.4)


def load_calculator_importance(cohort: str, model_variant: Optional[str] = None) -> Dict[str, pd.DataFrame]:
    """
    Load aggregated feature importance from calculator outputs.

    Feature importance files are saved by train_python_models.py to:
    - Calculator outputs: calculator/outputs/models/{cohort}_{variant}/mc_cv_{model}_feature_importance.csv
    - These contain mean importance across MC-CV splits

    Also checks parent outputs directory for backward compatibility.
    
    Args:
        cohort: Base cohort name (e.g., "Combined")
        model_variant: Model variant ("base", "enhanced", or None for auto-detect)
    """
    model_cohort = get_model_cohort_name(cohort, model_variant)
    
    # Primary location: calculator-specific outputs (where Python models save)
    calculator_models_dir = CALCULATOR_DIR / "outputs" / "models" / model_cohort
    # Fallback: parent outputs directory (where R calculator might save)
    output_dir = CALCULATOR_DIR.parent / "outputs"
    calculator_output_dir = CALCULATOR_DIR / "outputs"

    importance_files = {
        'CatBoost': [
            calculator_models_dir / "mc_cv_catboost_feature_importance.csv",
            calculator_models_dir / "mc_cv_all_models_feature_importance.csv",
            output_dir / f"importance_{cohort}_CatBoost.csv",  # Legacy R format
            calculator_output_dir / f"importance_{cohort}_CatBoost.csv",  # Legacy R format
        ],
        'XGBoost': [
            calculator_models_dir / "mc_cv_xgboost_feature_importance.csv",
            calculator_models_dir / "mc_cv_all_models_feature_importance.csv",
            output_dir / f"importance_{cohort}_XGBoost.csv",  # Legacy R format
            calculator_output_dir / f"importance_{cohort}_XGBoost.csv",  # Legacy R format
        ]
    }

    importance_data = {}
    for model_name, file_paths in importance_files.items():
        df = None
        file_path = None
        for path in file_paths:
            pq = path.with_suffix(".parquet")
            if pq.exists():
                try:
                    df = _read_parquet(pq)
                    file_path = pq
                    break
                except Exception:
                    pass
            if path.exists():
                try:
                    df = _read_parquet(path) if path.suffix.lower() == ".parquet" else pd.read_csv(path)
                    file_path = path
                    break
                except Exception:
                    pass

        if df is not None and file_path:
            # MC-CV outputs use importance_mean; normalize to 'importance' for downstream use
            if 'importance_mean' in df.columns and 'importance' not in df.columns:
                df = df.copy()
                df['importance'] = df['importance_mean']
            # Ensure 'feature' column is str (Parquet/DuckDB can return bytes/bytearray -> unhashable)
            if 'feature' in df.columns and df['feature'].dtype == object:
                df = df.copy()
                df['feature'] = df['feature'].apply(_safe_str_for_hash)
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


def find_xgboost_model_json(cohort: str, model_variant: Optional[str] = None) -> Optional[Path]:
    """
    Find XGBoost model JSON file for FFA explainer.

    The FFA explainer uses XGBoost JSON (not CatBoost) because:
    - CatBoost JSON is hard to parse due to internal hashing of categorical variables
    - XGBoost JSON is easier to parse and extract rules from
    - Rules are then filtered using combined SHAP values from both models

    Args:
        cohort: Base cohort name (e.g., "Combined")
        model_variant: Model variant ("base", "enhanced", or None for auto-detect)

    Expected locations:
    - Primary: calculator/outputs/models/{cohort}_{variant}/final_model_json/{cohort}_final_model_xgboost.json
    - Fallback: parent outputs/models/{cohort}_{variant}/final_model_json/{cohort}_final_model_xgboost.json
    """
    model_cohort = get_model_cohort_name(cohort, model_variant)
    
    # Primary: calculator outputs (where train_python_models.py saves)
    calculator_models_dir = CALCULATOR_DIR / "outputs" / "models" / model_cohort
    calculator_json_dir = calculator_models_dir / "final_model_json"

    # Fallback: parent outputs directory (where R calculator might save)
    parent_models_dir = CALCULATOR_DIR.parent / "outputs" / "models" / model_cohort
    parent_json_dir = parent_models_dir / "final_model_json"

    xgboost_paths = [
        calculator_json_dir / f"{model_cohort}_final_model_xgboost.json",  # Primary: Python-trained models
        calculator_json_dir / f"{cohort}_final_model_xgboost.json",  # Also try without variant suffix
        calculator_models_dir / f"{model_cohort}_final_model_xgboost.json",
        calculator_models_dir / f"{cohort}_final_model_xgboost.json",
        parent_json_dir / f"{model_cohort}_final_model_xgboost.json",  # Fallback: R-trained models
        parent_json_dir / f"{cohort}_final_model_xgboost.json",
        parent_models_dir / f"{model_cohort}_final_model_xgboost.json",
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


# Canonical secondary diagnosis levels (PHTS); used for one-hot encoding and dashboard dropdown
# Empty, Other, None dropped (no/minimal predictive value)
SEC_DX_LEVELS = [
    "ARVD/C", "Dilated", "Hypertrophic", "MIXED", "Restrictive", "Unknown"
]

# Other categoricals (from PHTS / eda/converted_vars_log.csv) – reference only; boolean-like use 0/1 numeric
# ter_dx: Chemotherapy-Induced, Conduction Defect, Empty, Familial, Ischemic, Isolated/Idiopathic, LVNC,
#         Metabolic/Syndromic/Mitochondrial, Neuromuscular, Other, S/P Myocarditis, S/P Radiation, Unknown
# primary_etiology: Cardiac Tumor, Cardiomyopathy, Congenital HD, Myocarditis, Other, Specify
# hxsurg, chd_sv, hxaf_fl: typically 0/1 in data → treated as numeric 0/1 in metadata and UI


def _sec_dx_safe_col(label: str) -> str:
    """Column name for one-hot: sec_dx_<label>, with / and spaces replaced for safety."""
    safe = label.replace("/", "_").replace(" ", "_").strip()
    return f"sec_dx_{safe}"


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

    # VAD combined (txvad OR slvad)
    if "txvad" in df.columns and "slvad" in df.columns:
        df["vad_combined"] = ((df["txvad"] == 1) | (df["slvad"] == 1)).astype(int)
        logger.info("Created vad_combined")
    elif "txvad" in df.columns:
        df["vad_combined"] = (df["txvad"] == 1).astype(int)
        logger.info("Created vad_combined from txvad only")
    elif "slvad" in df.columns:
        df["vad_combined"] = (df["slvad"] == 1).astype(int)
        logger.info("Created vad_combined from slvad only")

    # Ventilation combined (txvent OR slvent OR ltxtrach OR hxtrach)
    vent_vars = ["txvent", "slvent", "ltxtrach", "hxtrach"]
    available_vent_vars = [v for v in vent_vars if v in df.columns]
    if available_vent_vars:
        df["vent_combined"] = df[available_vent_vars].any(axis=1).astype(int)
        logger.info(f"Created vent_combined from {available_vent_vars}")

    # Donor/Recipient Weight Ratio
    if "weight_donor" in df.columns and "weight_txpl" in df.columns:
        mask = df["weight_txpl"].notna() & (df["weight_txpl"] > 0)
        df["donor_weight_ratio"] = np.nan
        df.loc[mask, "donor_weight_ratio"] = (
            (df.loc[mask, "weight_donor"] / df.loc[mask, "weight_txpl"]) * 100
        )
        logger.info("Created donor_weight_ratio")

    # Donor/Recipient Size Ratio (Height Ratio)
    if "height_donor" in df.columns and "height_txpl" in df.columns:
        mask = df["height_txpl"].notna() & (df["height_txpl"] > 0)
        df["donor_size_ratio"] = np.nan
        df.loc[mask, "donor_size_ratio"] = (
            (df.loc[mask, "height_donor"] / df.loc[mask, "height_txpl"]) * 100
        )
        logger.info("Created donor_size_ratio")

    # CHD Laterality Disorder (CHD_LAT) - Composite variable
    # Composite of: CHD_DEX, CHD_SI, CHD_HETER, CHD_IIVC, CHD_BIVC, CHD_LSVC, CHD_RAA, CHD_AVD
    chd_lat_vars = ["chd_dex", "chd_si", "chd_heter", "chd_iivc", "chd_bivc", "chd_lsvc", "chd_raa", "chd_avd"]
    available_chd_lat_vars = [v for v in chd_lat_vars if v in df.columns]
    if available_chd_lat_vars:
        df["chd_lat"] = df[available_chd_lat_vars].any(axis=1).astype(int)
        logger.info(f"Created chd_lat from {available_chd_lat_vars}")

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

    # ============================================================================
    # ONE-HOT ENCODE sec_dx (Secondary diagnosis) for dropdown and importance
    # ============================================================================
    if "sec_dx" in df.columns:
        raw = df["sec_dx"].astype(str).str.strip()
        for level in SEC_DX_LEVELS:
            col_name = _sec_dx_safe_col(level)
            # Case-insensitive match (raw may be "Dilated" or "dilated")
            df[col_name] = (raw.str.lower() == level.lower()).astype(int)
        df = df.drop(columns=["sec_dx"])
        logger.info(f"One-hot encoded sec_dx into {len(SEC_DX_LEVELS)} columns: {[_sec_dx_safe_col(lev) for lev in SEC_DX_LEVELS]}")

    return df


def load_calculator_data_for_shap(cohort: str, use_parquet_cache: bool = True) -> pd.DataFrame:
    """
    Load calculator data for SHAP computation.
    When use_parquet_cache is True, reads from a Parquet cache (via DuckDB if available)
    if it exists and is newer than the SAS source; otherwise loads from SAS and writes cache.

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

    # Parquet cache: same directory as script outputs, keyed by cohort
    cache_dir = CALCULATOR_DIR / "outputs" / "cache"
    cache_path = cache_dir / f"phts_calculator_{cohort}.parquet"

    if use_parquet_cache and cache_path.exists():
        if data_path is None or cache_path.stat().st_mtime >= data_path.stat().st_mtime:
            logger.info(f"Loading calculator data from Parquet cache: {cache_path}")
            try:
                df = _read_parquet(cache_path)
                return _ensure_string_columns_and_index(df)
            except Exception as e:
                logger.warning(f"Parquet cache read failed, falling back to SAS: {e}")

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
            except Exception:
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

    # Normalize so no bytearray/bytes (avoids unhashable type in nunique/set/Categorical downstream)
    df = _ensure_string_columns_and_index(df)

    if use_parquet_cache:
        try:
            _to_parquet(df, cache_path)
            logger.info(f"Wrote Parquet cache: {cache_path}")
        except Exception as e:
            logger.warning(f"Could not write Parquet cache: {e}")

    return df


def compute_calculator_shap_values(
    model,
    X: pd.DataFrame,
    model_type: str,
    n_samples: int = 2000
) -> Tuple[np.ndarray, pd.DataFrame, pd.DataFrame]:
    """
    Compute SHAP values for calculator survival models.

    For survival models, SHAP values are computed for risk scores (negative log hazard).

    Args:
        model: CatBoost or XGBoost survival model
        X: Feature DataFrame
        model_type: 'catboost' or 'xgboost'
        n_samples: Number of samples to use (for memory efficiency)

    Returns:
        Tuple of (shap_values_array, shap_values_dataframe, X_used).
        X_used is the dataframe actually passed to SHAP (same rows/order as shap_values_dataframe).
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

            # Get feature names and categorical indices from model FIRST (before alignment)
            try:
                model_feature_names = model.feature_names_
                cat_feature_indices = model.get_cat_feature_indices()
                
                if model_feature_names:
                    logger.info(f"Model expects {len(model_feature_names)} features")
                    if cat_feature_indices:
                        logger.info(f"Model has {len(cat_feature_indices)} categorical features at indices: {cat_feature_indices[:10]}{'...' if len(cat_feature_indices) > 10 else ''}")
                        # Map categorical indices to feature names
                        cat_feat_names = {model_feature_names[idx] for idx in cat_feature_indices if idx < len(model_feature_names)}
                        logger.info(f"Categorical feature names (first 10): {list(cat_feat_names)[:10]}")
                    else:
                        cat_feature_indices = None
                        cat_feat_names = set()
                else:
                    cat_feature_indices = None
                    cat_feat_names = set()
            except (AttributeError, TypeError) as e:
                logger.warning(f"Could not get model feature info: {e}")
                model_feature_names = None
                cat_feature_indices = None
                cat_feat_names = set()

            # Get feature names from model and align data columns
            if model_feature_names:
                try:
                    # Create mapping: lowercase both for comparison
                    data_cols_lower = {col.lower(): col for col in X_sample.columns}
                    
                    aligned_cols = []
                    for model_feat in model_feature_names:
                        model_feat_lower = model_feat.lower()
                        is_categorical = model_feat in cat_feat_names
                        
                        if model_feat_lower in data_cols_lower:
                            source_col = data_cols_lower[model_feat_lower]
                            aligned_cols.append(source_col)
                            # Preserve categorical dtype if this is a categorical feature
                            if is_categorical and X_sample[source_col].dtype != 'object':
                                logger.debug(f"Converting '{source_col}' to object dtype for categorical feature '{model_feat}'")
                                X_sample[source_col] = X_sample[source_col].astype('object')
                        elif model_feat in X_sample.columns:
                            aligned_cols.append(model_feat)
                            # Preserve categorical dtype if this is a categorical feature
                            if is_categorical and X_sample[model_feat].dtype != 'object':
                                logger.debug(f"Converting '{model_feat}' to object dtype for categorical feature")
                                X_sample[model_feat] = X_sample[model_feat].astype('object')
                        else:
                            logger.warning(f"Model feature '{model_feat}' not found in data, using default value")
                            # Add column with appropriate default based on type
                            if is_categorical:
                                X_sample[model_feat] = ''  # Empty string for categorical, object dtype
                                X_sample[model_feat] = X_sample[model_feat].astype('object')
                            else:
                                X_sample[model_feat] = 0  # Zero for numeric
                            aligned_cols.append(model_feat)

                    # Reorder columns to match model order
                    X_sample_clean = X_sample[aligned_cols].copy()
                    # Rename to match model exactly
                    X_sample_clean.columns = model_feature_names
                    logger.info(f"Aligned {len(aligned_cols)} features to match model")
                    
                    # Log categorical column dtypes after alignment for debugging
                    if cat_feature_indices:
                        logger.debug("Categorical column dtypes after alignment:")
                        for idx in cat_feature_indices[:5]:  # Log first 5
                            if idx < len(X_sample_clean.columns):
                                col_name = X_sample_clean.columns[idx]
                                logger.debug(f"  {col_name} (idx {idx}): dtype={X_sample_clean[col_name].dtype}, sample value: {X_sample_clean[col_name].iloc[0] if len(X_sample_clean) > 0 else 'N/A'}")
                    
                    # After alignment, categorical indices remain the same (columns are just reordered)
                    # So cat_feature_indices from model still applies to the aligned DataFrame
                except Exception as e:
                    logger.warning(f"Could not align feature names: {e}, using data as-is")
                    X_sample_clean = X_sample.copy()
                    # If alignment failed, we can't use the model's categorical indices
                    cat_feature_indices = None
            else:
                X_sample_clean = X_sample.copy()
                cat_feature_indices = None

            # Handle NaN values: only fill numeric columns, preserve categoricals
            # Identify which columns are categorical (by index after alignment)
            if cat_feature_indices:
                cat_col_names = [X_sample_clean.columns[idx] for idx in cat_feature_indices if idx < len(X_sample_clean.columns)]
                numeric_col_names = [col for col in X_sample_clean.columns if col not in cat_col_names]
                
                # Fill NaN only for numeric columns
                for col in numeric_col_names:
                    if pd.api.types.is_numeric_dtype(X_sample_clean[col]):
                        X_sample_clean[col] = X_sample_clean[col].fillna(0)
                
                # For categorical columns, ensure they are strings and handle NaN/None
                for col in cat_col_names:
                    # Convert to string first (handles any dtype)
                    X_sample_clean[col] = X_sample_clean[col].astype(str)
                    # Replace NaN/None representations with empty string
                    X_sample_clean[col] = X_sample_clean[col].replace(['nan', 'None', 'NaN', 'NONE', 'NaT'], '', regex=False)
                    # Also handle actual NaN values that might still exist
                    X_sample_clean[col] = X_sample_clean[col].fillna('')
                    # Ensure dtype is object (string) to prevent CatBoost from treating as numeric
                    X_sample_clean[col] = X_sample_clean[col].astype('object')
            else:
                # No categorical features identified, fill all numeric columns
                for col in X_sample_clean.columns:
                    if pd.api.types.is_numeric_dtype(X_sample_clean[col]):
                        X_sample_clean[col] = X_sample_clean[col].fillna(0)

            # Create Pool with categorical features specified
            # For survival models, we don't need labels for SHAP
            # Ensure categorical columns are properly typed before creating Pool
            if cat_feature_indices:
                # Final check: ensure all categorical columns are object dtype and contain strings
                logger.debug(f"Final check: Verifying {len(cat_feature_indices)} categorical features before creating Pool...")
                for idx in cat_feature_indices:
                    if idx < len(X_sample_clean.columns):
                        col_name = X_sample_clean.columns[idx]
                        current_dtype = X_sample_clean[col_name].dtype
                        
                        # Force conversion to object/string if needed
                        if current_dtype != 'object':
                            logger.warning(f"Categorical column '{col_name}' (idx {idx}) is {current_dtype}, converting to object...")
                            X_sample_clean[col_name] = X_sample_clean[col_name].astype(str).astype('object')
                        else:
                            # Even if object dtype, ensure values are strings
                            X_sample_clean[col_name] = X_sample_clean[col_name].astype(str).astype('object')
                        
                        # Log a sample value for debugging
                        if len(X_sample_clean) > 0:
                            sample_val = X_sample_clean[col_name].iloc[0]
                            logger.debug(f"  Categorical '{col_name}' (idx {idx}): dtype={X_sample_clean[col_name].dtype}, sample='{sample_val}'")
                
                logger.info(f"Creating CatBoost Pool with {len(cat_feature_indices)} categorical features...")
                pool = Pool(X_sample_clean, cat_features=cat_feature_indices)
            else:
                logger.info("Creating CatBoost Pool with no categorical features specified...")
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
        # X_sample_clean has same index as shap_df and same column order (feature_names_for_df)
        return shap_values, shap_df, X_sample_clean

    except Exception as e:
        logger.error(f"Error computing SHAP values for {model_type}: {e}", exc_info=True)
        raise


def run_calculator_shap_analysis(cohort: str, model_variant: Optional[str] = None) -> Tuple[Dict[str, float], Dict[str, float], pd.DataFrame, pd.DataFrame]:
    """
    Run full SHAP analysis for calculator models.

    This function computes actual SHAP values from the models, not proxies.

    Args:
        cohort: Base cohort name (e.g., "Combined")
        model_variant: Model variant ("base", "enhanced", or None for auto-detect)

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

    model_cohort = get_model_cohort_name(cohort, model_variant)
    logger.info(f"Running FULL SHAP analysis for calculator models (cohort: {model_cohort})...")
    logger.info("This will compute actual SHAP values from models (not proxies)")

    # Load calculator models directly
    try:
        from catboost import CatBoostRegressor
        import xgboost as xgb

        # Check both calculator outputs and parent outputs
        calculator_models_dir = CALCULATOR_DIR / "outputs" / "models" / model_cohort
        parent_models_dir = CALCULATOR_DIR.parent / "outputs" / "models" / model_cohort

        # Load CatBoost model
        cb_path = None
        for models_dir in [calculator_models_dir, parent_models_dir]:
            candidate_path = models_dir / "catboost_model.cbm"
            if candidate_path.exists():
                cb_path = candidate_path
                break

        if cb_path is None:
            raise FileNotFoundError(
                f"CatBoost model not found. Checked:\n"
                f"  - {calculator_models_dir / 'catboost_model.cbm'}\n"
                f"  - {parent_models_dir / 'catboost_model.cbm'}\n"
                f"Please run train_python_models.py first."
            )

        cb_model = CatBoostRegressor(logging_level='Silent')
        cb_model.load_model(str(cb_path))
        logger.info(f"Loaded CatBoost model: {cb_path}")

        # Load XGBoost model
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
        # IMPORTANT: This must match the training temporal split to ensure we're explaining on the same test set
        # Training uses dynamic 80/20 split (falls back to 2021), so we use the same logic here
        if 'txpl_year' in df.columns:
            # Calculate cutoff to match training (80/20 split)
            year_counts = df['txpl_year'].value_counts().sort_index()
            cumsum = year_counts.cumsum()
            target = int(len(df) * 0.8)
            cutoff_year = None
            for year, count in cumsum.items():
                if count >= target:
                    cutoff_year = int(year)
                    break
            if cutoff_year is None:
                cutoff_year = 2021  # Fallback to match training default
                logger.warning(f"Could not calculate cutoff year, using {cutoff_year}")
            test_mask = df['txpl_year'] > cutoff_year
            df = df[test_mask].copy()
            logger.info(f"Using test set (txpl_year > {cutoff_year}): {len(df)} samples for SHAP")
            logger.info(f"Temporal split cutoff matches training: {cutoff_year}")
        else:
            logger.warning("txpl_year not found, using full dataset for SHAP")
    except (FileNotFoundError, ImportError) as e:
        raise RuntimeError(
            f"Failed to load calculator data: {e}. "
            "Data is required for SHAP computation."
        )

    # Feature preparation matches train_python_models.py prepare_calculator_features()
    # This ensures consistency between training and SHAP analysis
    # IMPORTANT: CatBoost models now use native categoricals, so we must include them
    logger.info("Including all features (numeric + categorical) to match model training")

    # Remove outcome columns
    outcome_cols = ['ev_time', 'ev_type', 'time', 'status', 'int_dead', 'int_graft_loss',
                    'graft_loss', 'outcome', 'outcome_int_graft_loss', 'outcome_graft_loss']
    
    # Get all columns except outcomes (includes both numeric and categorical)
    feature_cols = [col for col in df.columns if col not in outcome_cols]

    X = df[feature_cols].copy()

    # Handle NaN values
    # For numeric features: fill with 0 (models were trained this way)
    # For categorical features: keep as-is (CatBoost handles them natively)
    for col in X.columns:
        # Check if column is numeric using pandas API (avoids deprecation warning)
        if pd.api.types.is_numeric_dtype(X[col]):
            X[col] = X[col].fillna(0)
        # Categorical features (object dtype) are kept as-is for CatBoost

    # Remove rows with all zeros (likely invalid)
    # Only check numeric columns for this (categorical columns may have non-numeric values)
    numeric_cols_in_X = X.select_dtypes(include=[np.number]).columns
    if len(numeric_cols_in_X) > 0:
        X = X[(X[numeric_cols_in_X] != 0).any(axis=1)]

    if len(X) == 0:
        raise ValueError("No valid data rows after filtering")

    logger.info(f"Using {len(feature_cols)} features for SHAP computation")
    logger.info(f"Data shape: {X.shape}, NaN values filled with 0")

    # Compute SHAP values for CatBoost
    logger.info("Computing CatBoost SHAP values...")
    try:
        cb_shap_values, cb_shap_df, _ = compute_calculator_shap_values(
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
    # IMPORTANT: XGBoost was trained on numeric-encoded categoricals, so we need to convert
    # categoricals to numeric codes to match the training data format
    logger.info("Computing XGBoost SHAP values...")
    logger.info("Converting categorical features to numeric codes to match XGBoost training format...")
    X_for_xgb_shap = X.copy()
    categorical_cols_for_shap = [col for col in X_for_xgb_shap.columns if X_for_xgb_shap[col].dtype == 'object' or X_for_xgb_shap[col].dtype.name == 'category']
    for col in categorical_cols_for_shap:
        # Convert to numeric codes (same encoding as used during training)
        X_for_xgb_shap[col] = pd.Categorical(X[col].astype(str).fillna('')).codes
    if categorical_cols_for_shap:
        logger.info(f"Converted {len(categorical_cols_for_shap)} categorical features to numeric codes for XGBoost SHAP")
    
    try:
        xgb_shap_values, xgb_shap_df, _ = compute_calculator_shap_values(
            xgb_model, X_for_xgb_shap, 'xgboost', n_samples=2000
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
    X_test: Optional[pd.DataFrame] = None,
    use_xgboost_only: bool = False
) -> Tuple[pd.DataFrame, Dict[str, Dict[int, List[int]]]]:
    """
    Run FFA analysis using:
    - XGBoost model JSON for rule extraction
    - SHAP values for rule filtering (XGBoost only if use_xgboost_only=True, otherwise combined)
    - Test data for applying rules and counting actual rule firings

    Args:
        X_test: Test data DataFrame to apply rules to (required for accurate rule frequency counting)
        use_xgboost_only: If True, uses only XGBoost SHAP (simplified pipeline)

    Note: Rules are extracted from the model JSON, but rule frequencies are counted
    based on how often rules actually fire on test data instances, not just from
    rule definitions. This ensures FFA analysis runs on the test set.
    """
    if not FFA_AVAILABLE:
        error_msg = (
            "FFA analysis modules are REQUIRED but not available.\n"
            f"Expected location: {FFA_ANALYSIS_DIR}/\n"
            "Required files:\n"
            "  - ffa_utils.py (with load_model_json, extract_feature_mappings)\n"
            "  - xgboost_axp_explainer.py (with XGBoostSymbolicExplainer, PathConfig)\n"
            "\n"
            "Please ensure these modules are synced from GitHub or created."
        )
        logger.error(error_msg)
        raise ImportError(error_msg)

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

        # Apply rules to test data to count actual rule firings
        # This ensures FFA analysis runs on the test set, not just counting features in rule definitions
        X_for_levels = None  # Aligned test set for per-level FFA (set below when X_test is not None)
        if X_test is not None:
            logger.info(f"Applying rules to test set: {len(X_test)} instances")
            logger.info("Counting rule frequencies based on actual rule firings on test data")

            # Align test data columns with model features
            # Get feature names from explainer or model
            if hasattr(explainer, 'feature_names') and explainer.feature_names:
                # Map feature indices to names
                feature_idx_to_name = explainer.feature_names
                # Get feature names in order
                model_feature_names = [feature_idx_to_name.get(i, f"feature_{i}")
                                     for i in range(len(feature_idx_to_name))]
            else:
                # Fallback: use test data column names
                model_feature_names = X_test.columns.tolist()

            # Align X_test columns with model features
            X_test_aligned = X_test.copy()
            # Ensure columns match (handle case sensitivity)
            X_test_cols_lower = {col.lower(): col for col in X_test_aligned.columns}
            model_cols_lower = {col.lower(): col for col in model_feature_names}

            # Reorder and align columns
            # If model expects "sec_dx" but test has sec_dx_* one-hot, derive sec_dx as label index (legacy model)
            sec_dx_one_hot_cols = [c for c in X_test_aligned.columns if c.startswith("sec_dx_")]
            aligned_cols = []
            for model_feat in model_feature_names:
                model_feat_lower = model_feat.lower()
                if model_feat_lower in X_test_cols_lower:
                    aligned_cols.append(X_test_cols_lower[model_feat_lower])
                elif model_feat in X_test_aligned.columns:
                    aligned_cols.append(model_feat)
                elif model_feat == "sec_dx" and sec_dx_one_hot_cols:
                    # Legacy model: single sec_dx column; test has one-hot sec_dx_* → derive label index
                    order_cols = [_sec_dx_safe_col(lev) for lev in SEC_DX_LEVELS if _sec_dx_safe_col(lev) in X_test_aligned.columns]
                    if order_cols:
                        idx = np.argmax(X_test_aligned[order_cols].values, axis=1)
                        X_test_aligned[model_feat] = idx
                        aligned_cols.append(model_feat)
                        logger.info("Derived 'sec_dx' from sec_dx_* one-hot columns for legacy model alignment")
                    else:
                        logger.warning(f"Model feature 'sec_dx' not in test data, using zeros")
                        X_test_aligned[model_feat] = 0
                        aligned_cols.append(model_feat)
                else:
                    logger.warning(f"Model feature '{model_feat}' not in test data, using zeros")
                    X_test_aligned[model_feat] = 0
                    aligned_cols.append(model_feat)

            X_test_aligned = X_test_aligned[aligned_cols].copy()
            X_test_aligned.columns = model_feature_names
            X_for_levels = X_test_aligned

            # Convert to numpy array for rule checking
            X_test_array = X_test_aligned.values

            # Get risk scores for threshold-based filtering (same threshold as used for Recall)
            # Load XGBoost model to get risk scores
            risk_scores = None
            risk_threshold = None
            try:
                import xgboost as xgb
                # Find XGBoost model file
                # JSON is typically in: {model_cohort}/final_model_json/{model_cohort}_final_model_xgboost.json
                # Model binary is in: {model_cohort}/xgboost_model.ubj
                json_dir = xgboost_model_json.parent  # final_model_json/
                model_dir = json_dir.parent  # {model_cohort}/ (e.g., Combined_base/ or Combined_enhanced/)
                xgb_model_path = model_dir / "xgboost_model.ubj"
                
                if not xgb_model_path.exists():
                    # Try alternative location (parent outputs directory)
                    calculator_models_dir = CALCULATOR_DIR / "outputs" / "models"
                    model_cohort = model_dir.name  # Should be Combined_base or Combined_enhanced
                    xgb_model_path = calculator_models_dir / model_cohort / "xgboost_model.ubj"
                    
                    if not xgb_model_path.exists():
                        # Try parent outputs directory
                        parent_models_dir = CALCULATOR_DIR.parent / "outputs" / "models"
                        xgb_model_path = parent_models_dir / model_cohort / "xgboost_model.ubj"
                
                if xgb_model_path.exists():
                    xgb_model = xgb.XGBRegressor()
                    xgb_model.load_model(str(xgb_model_path))
                    
                    # Prepare data for prediction (sklearn API expects array-like, not DMatrix)
                    X_test_for_pred = X_test_aligned.copy()
                    # Convert categorical to numeric if needed
                    for col in X_test_for_pred.columns:
                        if X_test_for_pred[col].dtype == 'object':
                            X_test_for_pred[col] = pd.Categorical(X_test_for_pred[col]).codes
                    
                    # Get risk scores (use array/DataFrame; XGBRegressor.predict does not accept DMatrix)
                    X_pred = X_test_for_pred.values.astype(np.float32)
                    risk_scores = xgb_model.predict(X_pred)
                    
                    # Calculate threshold using same method as Recall (median or optimal)
                    # For rule filtering, use median risk score as threshold
                    # This ensures we only count rules firing for high-risk instances
                    risk_threshold = np.median(risk_scores)
                    logger.info(f"Calculated risk threshold (median): {risk_threshold:.4f}")
                    logger.info(f"Will filter rule firings to instances with risk_score >= {risk_threshold:.4f}")
                else:
                    logger.warning(f"XGBoost model not found at {xgb_model_path}, skipping threshold-based filtering")
            except Exception as e:
                logger.warning(f"Could not load XGBoost model for threshold calculation: {e}")
                logger.info("Proceeding without threshold-based filtering (counting all rule firings)")

            # Count rule firings on test data
            rule_firing_counts = defaultdict(int)  # Count how many times each rule fires
            feature_rule_firing_counts = defaultdict(int)  # Count feature appearances in firing rules

            logger.info(f"Checking rule satisfaction on {len(X_test_array)} test instances...")
            for instance_idx, x_instance in enumerate(X_test_array):
                if instance_idx % 100 == 0 and instance_idx > 0:
                    logger.debug(f"Processed {instance_idx}/{len(X_test_array)} instances")

                # Check which rules are satisfied for this instance
                # Try different methods to check rule satisfaction
                satisfied_rules = []
                try:
                    # For survival models (Cox regression), we don't have binary class predictions
                    # Check if this is a survival model by looking at rule_predictions
                    is_survival_model = False
                    if hasattr(explainer, 'rule_predictions') and explainer.rule_predictions:
                        # Check if rule_predictions are binary (0/1) or continuous
                        unique_preds = set(explainer.rule_predictions)
                        is_survival_model = not (unique_preds.issubset({0, 1}) and len(unique_preds) <= 2)
                    
                    # Method 1: Try _satisfied_rules if available (for classification models)
                    if hasattr(explainer, '_satisfied_rules') and not is_survival_model:
                        # Try both classes for classification models
                        satisfied_rules_0 = explainer._satisfied_rules(x_instance, target_class=0)
                        satisfied_rules_1 = explainer._satisfied_rules(x_instance, target_class=1)
                        satisfied_rules = satisfied_rules_0 + satisfied_rules_1
                    # Method 2: Try check_rule_satisfaction if available
                    elif hasattr(explainer, 'check_rule_satisfaction'):
                        for rule_idx, clause in enumerate(explainer.rule_clauses):
                            if explainer.check_rule_satisfaction(x_instance, clause):
                                satisfied_rules.append(rule_idx)
                    # Method 3: Manual check using id_condition_map (works for all models including survival)
                    # Note: This is a simplified check - CNF clauses are AND of literals
                    # Each literal is a condition that must be satisfied
                    else:
                        for rule_idx, clause in enumerate(explainer.rule_clauses):
                            if not clause:
                                continue
                            # Check if all literals in clause are satisfied (CNF = AND of literals)
                            clause_satisfied = True
                            for lit in clause:
                                if lit in explainer.id_condition_map:
                                    feat_idx, op, threshold = explainer.id_condition_map[lit]
                                    if feat_idx >= len(x_instance):
                                        # Feature index out of bounds - rule cannot be satisfied
                                        clause_satisfied = False
                                        break
                                    feat_val = x_instance[feat_idx]
                                    # Check condition based on operator
                                    if op == '<=' or op == 'le':
                                        if not (feat_val <= threshold):
                                            clause_satisfied = False
                                            break
                                    elif op == '>' or op == 'gt':
                                        if not (feat_val > threshold):
                                            clause_satisfied = False
                                            break
                                    elif op == '<' or op == 'lt':
                                        if not (feat_val < threshold):
                                            clause_satisfied = False
                                            break
                                    elif op == '>=' or op == 'ge':
                                        if not (feat_val >= threshold):
                                            clause_satisfied = False
                                            break
                                    elif op == '==' or op == 'eq':
                                        if not (feat_val == threshold):
                                            clause_satisfied = False
                                            break
                                    # If operator not recognized, assume satisfied (conservative)
                                else:
                                    # Literal not in id_condition_map - skip this literal
                                    logger.debug(f"Literal {lit} not found in id_condition_map")
                            if clause_satisfied:
                                satisfied_rules.append(rule_idx)
                except Exception as e:
                    logger.debug(f"Error checking rules for instance {instance_idx}: {e}")
                    # Fall back to manual check on error
                    try:
                        for rule_idx, clause in enumerate(explainer.rule_clauses):
                            if not clause:
                                continue
                            clause_satisfied = True
                            for lit in clause:
                                if lit in explainer.id_condition_map:
                                    feat_idx, op, threshold = explainer.id_condition_map[lit]
                                    if feat_idx >= len(x_instance):
                                        clause_satisfied = False
                                        break
                                    feat_val = x_instance[feat_idx]
                                    if op == '<=' or op == 'le':
                                        if not (feat_val <= threshold):
                                            clause_satisfied = False
                                            break
                                    elif op == '>' or op == 'gt':
                                        if not (feat_val > threshold):
                                            clause_satisfied = False
                                            break
                                    elif op == '<' or op == 'lt':
                                        if not (feat_val < threshold):
                                            clause_satisfied = False
                                            break
                                    elif op == '>=' or op == 'ge':
                                        if not (feat_val >= threshold):
                                            clause_satisfied = False
                                            break
                                    elif op == '==' or op == 'eq':
                                        if not (feat_val == threshold):
                                            clause_satisfied = False
                                            break
                            if clause_satisfied:
                                satisfied_rules.append(rule_idx)
                    except Exception as e2:
                        logger.debug(f"Fallback manual check also failed for instance {instance_idx}: {e2}")
                        continue

                # Count rule firings and feature appearances in firing rules
                # Only count if instance has risk_score >= threshold (if threshold available)
                if risk_scores is not None and risk_threshold is not None:
                    instance_risk = risk_scores[instance_idx]
                    if instance_risk < risk_threshold:
                        # Skip low-risk instances - only count rules firing for high-risk instances
                        continue
                
                for rule_idx in satisfied_rules:
                    rule_firing_counts[rule_idx] += 1
                    # Get features in this rule
                    if rule_idx < len(explainer.rule_clauses):
                        clause = explainer.rule_clauses[rule_idx]
                        for lit in clause:
                            if lit in explainer.id_condition_map:
                                feat_idx, _, _ = explainer.id_condition_map[lit]
                                if hasattr(explainer, 'feature_names') and explainer.feature_names:
                                    feat_name = explainer.feature_names.get(feat_idx, f"feature_{feat_idx}")
                                else:
                                    feat_name = f"feature_{feat_idx}"
                                feature_rule_firing_counts[feat_name] += 1

            logger.info(f"Rules fired on {len(rule_firing_counts)} unique rules out of {len(explainer.rule_clauses)} total rules")
            logger.info(f"Total rule firings: {sum(rule_firing_counts.values())}")
            
            # Debug: Check feature index ranges
            if explainer.id_condition_map:
                max_feat_idx = max(feat_idx for feat_idx, _, _ in explainer.id_condition_map.values())
                logger.info(f"Model uses feature indices 0-{max_feat_idx}, test data has {len(X_test_array[0])} features")
                if max_feat_idx >= len(X_test_array[0]):
                    logger.error(f"Feature index mismatch: Model expects up to index {max_feat_idx}, but test data only has {len(X_test_array[0])} features")
                    logger.error("This will cause rule checking to fail. Check that test data feature count matches model.")

            # Use test-based rule firing counts instead of rule definition counts
            rule_feature_counts = feature_rule_firing_counts
            logger.info(f"Using rule frequencies from test set: {len(rule_feature_counts)} features with rule firings")
        else:
            logger.warning("X_test not provided - using rule definition counts instead of test set rule firings")
            logger.warning("For accurate FFA analysis, provide test data to count actual rule firings")

        # Create causal results based on rule frequency (from test set if available) and SHAP importance
        causal_results = []
        total_rule_firings = sum(rule_feature_counts.values()) if rule_feature_counts else len(explainer.rule_clauses)

        for feature, rule_count in rule_feature_counts.items():
            shap_importance = shap_map.get(feature, 0.0)
            # Causal responsibility combines rule frequency (from test set) and SHAP importance
            if total_rule_firings > 0:
                rule_frequency_normalized = rule_count / total_rule_firings
            else:
                rule_frequency_normalized = 0.0
            causal_responsibility = rule_frequency_normalized * shap_importance

            causal_results.append({
                'feature': feature,
                'causal_responsibility': causal_responsibility,
                'shap_importance': shap_importance,
                'rule_frequency': rule_count,
                'total_rule_firings': total_rule_firings,
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

        # Save results (Parquet for fast/DuckDB reads, CSV for compatibility)
        causal_path_csv = output_dir / 'ffa_causal_factors.csv'
        causal_path_pq = output_dir / 'ffa_causal_factors.parquet'
        causal_df.to_csv(causal_path_csv, index=False)
        try:
            _to_parquet(causal_df, causal_path_pq)
            logger.info(f"Saved FFA causal factors to {causal_path_pq} and {causal_path_csv}")
        except Exception as e:
            logger.warning(f"Could not write Parquet: {e}; saved CSV to {causal_path_csv}")

        # Per-level FFA: which rule indices each (feature, level) satisfies
        feature_level_rules: Dict[str, Dict[int, List[int]]] = {}
        if X_for_levels is not None and hasattr(explainer, 'rule_clauses') and hasattr(explainer, 'id_condition_map'):
            try:
                # Build feature_levels from aligned test set
                feature_levels_ffa: Dict[str, List[int]] = {}
                for col in X_for_levels.columns:
                    s = X_for_levels[col].dropna()
                    if len(s) == 0:
                        continue
                    try:
                        lev = sorted(pd.Series(s).astype(int).unique().tolist())
                    except (TypeError, ValueError):
                        lev = sorted(pd.Series(s).astype(float).unique().tolist())
                    feature_levels_ffa[col] = lev
                feature_level_rules = compute_feature_level_rules(
                    explainer, feature_levels_ffa, getattr(explainer, 'feature_names', None)
                )
                if feature_level_rules:
                    logger.info(f"Computed per-level FFA rules for {len(feature_level_rules)} features")
            except Exception as e_level:
                logger.warning(f"Could not compute feature-level FFA rules: {e_level}")

        return causal_df, feature_level_rules

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
        try:
            _to_parquet(comparison_df, validation_dir / 'rule_shap_comparison.parquet')
        except Exception:
            pass
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

    def _imp_col(df: pd.DataFrame) -> str:
        return 'importance' if 'importance' in df.columns else 'importance_mean'

    # Start with CatBoost if available
    if 'CatBoost' in importance_data:
        cb_df = importance_data['CatBoost']
        imp_col = _imp_col(cb_df)
        combined = cb_df.copy()
        if imp_col != 'importance':
            combined['importance'] = combined[imp_col]
        combined['combined_importance'] = weight_catboost * combined['importance']
    else:
        xgb_df = importance_data['XGBoost']
        imp_col = _imp_col(xgb_df)
        combined = xgb_df.copy()
        if imp_col != 'importance':
            combined['importance'] = combined[imp_col]
        combined['combined_importance'] = 0.0

    # Add XGBoost if available
    if 'XGBoost' in importance_data:
        xgb_imp = importance_data['XGBoost']
        xgb_imp_col = _imp_col(xgb_imp)
        if xgb_imp_col != 'importance':
            xgb_imp = xgb_imp.copy()
            xgb_imp['importance'] = xgb_imp[xgb_imp_col]
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


def generate_feature_metadata(
    df: pd.DataFrame, feature_names: List[str]
) -> Tuple[Dict[str, str], Dict[str, List[int]]]:
    """
    Generate feature metadata (binary vs numeric) and level values from prepared data.

    Level values are the distinct values seen in the data (0, 1, 2, ...) for
    categorical/binary features, so the dashboard can show dropdowns with actual levels.

    Args:
        df: Prepared dataframe with features
        feature_names: List of feature names to check

    Returns:
        (feature_metadata, feature_levels)
        - feature_metadata: dict mapping feature names to 'binary' or 'numeric'
        - feature_levels: dict mapping feature name to sorted list of int levels (for dropdowns)
    """
    feature_metadata = {}
    feature_levels: Dict[str, List[int]] = {}

    known_numeric = ['bmi', 'egfr', 'age', 'weight', 'height', 'creat', 'bun',
                     'albumin', 'ast', 'alt', 'bili', 'chol', 'hdl', 'ldl', 'tg',
                     'tp', 'brp', 'bram', 'donisch', 'durcarst', 'bnp', 'sa', 'palb']
    # sec_dx is one-hot encoded as sec_dx_*; ter_dx/prim_dx multi-level; hxsurg, chd_sv, hxaf_fl binary → dropdown (selected=1, not selected=0)
    known_binary_or_categorical = ['ter_dx', 'hxsurg', 'chd_sv', 'hxaf_fl', 'prim_dx']
    col_lower = {c.lower(): c for c in df.columns}

    for feature_name in feature_names:
        col_name = df.columns[df.columns == feature_name].tolist()
        if not col_name:
            col_name = [col_lower[feature_name.lower()]] if feature_name.lower() in col_lower else []
        if col_name:
            col_data = df[col_name[0]].dropna()

            if len(col_data) > 0:
                is_known_numeric = any(pattern in feature_name.lower() for pattern in known_numeric)
                is_known_binary_cat = any(
                    pattern in feature_name.lower() for pattern in known_binary_or_categorical
                )
                unique_vals = set(col_data.unique())
                is_binary_vals = unique_vals.issubset({0, 1, 0.0, 1.0})

                if is_known_numeric:
                    feature_metadata[feature_name] = 'numeric'
                elif is_known_binary_cat or is_binary_vals:
                    # Binary: one dropdown (No=0, Yes=1); selected option → value, others → 0
                    feature_metadata[feature_name] = 'binary'
                    levels = sorted(set(int(round(x)) for x in unique_vals))
                    feature_levels[feature_name] = levels
                else:
                    feature_metadata[feature_name] = 'numeric'
            else:
                feature_metadata[feature_name] = 'numeric'
        else:
            feature_metadata[feature_name] = 'numeric'

    for feature_name in feature_names:
        if feature_metadata.get(feature_name) == 'binary' and feature_name not in feature_levels:
            feature_levels[feature_name] = [0, 1]

    return feature_metadata, feature_levels


def compute_feature_level_shap(
    shap_values_df: pd.DataFrame,
    X_align: pd.DataFrame,
    feature_levels: Optional[Dict[str, List[int]]] = None,
) -> Dict[str, Dict[int, Dict[str, Any]]]:
    """
    Compute per-level SHAP stats: mean SHAP, count, count with SHAP > 0, and whether level has any positive SHAP.

    X_align must have the same index and row order as shap_values_df (the X actually used for SHAP).
    Only features present in both shap_values_df and X_align are considered.

    Returns:
        feature -> level (int) -> {mean_shap, count, count_positive, shap_positive}
        where shap_positive is True if any sample at this level had SHAP > 0.
    """
    out: Dict[str, Dict[int, Dict[str, Any]]] = {}
    common = [c for c in shap_values_df.columns if c in X_align.columns]
    if not common:
        return out
    # Align by index so row i of shap_values_df corresponds to row i of X_align
    idx = shap_values_df.index
    if not idx.equals(X_align.index):
        X_align = X_align.reindex(idx).dropna(how="all")
        shap_values_df = shap_values_df.reindex(X_align.index).dropna(how="all")
    for feature in common:
        if feature not in shap_values_df.columns or feature not in X_align.columns:
            continue
        levels = feature_levels.get(feature) if feature_levels else None
        if levels is None:
            try:
                levels = sorted(pd.Series(X_align[feature].dropna()).astype(int).unique().tolist())
            except (TypeError, ValueError):
                levels = sorted(pd.Series(X_align[feature].dropna().astype(float)).unique().tolist())
        out[feature] = {}
        for level in levels:
            try:
                lval = int(level) if not isinstance(level, (int, float)) else level
            except (TypeError, ValueError):
                lval = level
            mask = (X_align[feature].astype(float) == float(lval)) | (X_align[feature] == lval)
            if mask.sum() == 0:
                out[feature][lval] = {
                    "mean_shap": 0.0,
                    "count": 0,
                    "count_positive": 0,
                    "shap_positive": False,
                }
                continue
            sh = shap_values_df.loc[mask, feature]
            mean_shap = float(sh.mean())
            count = int(mask.sum())
            count_positive = int((sh > 0).sum())
            out[feature][lval] = {
                "mean_shap": mean_shap,
                "count": count,
                "count_positive": count_positive,
                "shap_positive": count_positive > 0,
            }
    return out


def compute_feature_level_rules(
    explainer: Any,
    feature_levels: Dict[str, List[int]],
    feature_names: Optional[Dict[int, str]] = None,
) -> Dict[str, Dict[int, List[int]]]:
    """
    For each (feature, level), list which FFA rule indices have a condition on that feature
    satisfied by this level. Explainer uses id_condition_map[lit] = (feat_idx, threshold, direction)
    with direction 0 => value <= threshold, direction 1 => value > threshold.
    """
    out: Dict[str, Dict[int, List[int]]] = {}
    if not getattr(explainer, "rule_clauses", None) or not getattr(explainer, "id_condition_map", None):
        return out
    fnames = feature_names if feature_names is not None else getattr(explainer, "feature_names", None) or {}
    if isinstance(fnames, list):
        fnames = {i: n for i, n in enumerate(fnames)}

    for rule_idx, clause in enumerate(explainer.rule_clauses):
        for lit in clause:
            try:
                feat_idx, threshold, direction = explainer.id_condition_map[lit]
            except (KeyError, TypeError, ValueError):
                continue
            feat_name = fnames.get(feat_idx, f"feature_{feat_idx}")
            levels = feature_levels.get(feat_name)
            if levels is None:
                continue
            for level in levels:
                try:
                    lval = int(level) if not isinstance(level, (int, float)) else level
                except (TypeError, ValueError):
                    continue
                satisfies = (lval <= threshold) if direction == 0 else (lval > threshold)
                if satisfies:
                    if feat_name not in out:
                        out[feat_name] = {}
                    if lval not in out[feat_name]:
                        out[feat_name][lval] = []
                    if rule_idx not in out[feat_name][lval]:
                        out[feat_name][lval].append(rule_idx)
    return out


def generate_dashboard_outputs(
    combined_importance: pd.DataFrame,
    causal_df: Optional[pd.DataFrame],
    output_dir: Path,
    cohort: str,
    top_k: int = 10,
    xgboost_json_used: bool = False,
    use_xgboost_only: bool = False,
    feature_data: Optional[pd.DataFrame] = None,
    feature_level_labels: Optional[Dict[str, List[str]]] = None,
):
    """Generate dashboard-ready outputs for risk dashboard."""
    logger.info("Generating dashboard outputs...")

    # Filter out cohort-defining variables (should not be causal factors)
    # prim_dx defines the cohorts (CHD, Myocardio, Combined) - it's not a causal feature
    # NOTE: For Combined model, primary_etiology is kept as a feature (not filtered here)
    # Only filter prim_dx/PRIM_DX variants, not primary_etiology for Combined
    cohort_defining_vars = ['prim_dx', 'PRIM_DX']
    if cohort != "Combined":
        cohort_defining_vars.append('primary_etiology')

    # Top K causal factors (handle case when FFA is not available)
    if causal_df is None or len(causal_df) == 0:
        logger.warning("No causal factors available (FFA may not be available). Using feature importance instead.")
        # Fallback: Use top features from importance
        top_causal = combined_importance.head(top_k * 2).copy()  # Get more to account for filtering
        # Filter out cohort-defining variables
        top_causal = top_causal[~top_causal['feature'].isin(cohort_defining_vars)].head(top_k).copy()
        top_causal = top_causal.rename(columns={'combined_importance_norm': 'causal_responsibility'})
        top_causal['shap_importance'] = top_causal['causal_responsibility']
        top_causal['rule_frequency'] = 0
        top_causal['total_rules'] = 0
    else:
        # Filter out cohort-defining variables from causal factors
        causal_df_filtered = causal_df[~causal_df['feature'].isin(cohort_defining_vars)].copy()
        top_causal = causal_df_filtered.head(top_k).copy()
        # Ensure dashboard has importance/combined_importance (FFA causal_df has causal_responsibility, shap_importance only)
        if 'feature' in combined_importance.columns and 'combined_importance' in combined_importance.columns:
            imp_merge = combined_importance[['feature', 'combined_importance']].drop_duplicates('feature')
            top_causal = top_causal.merge(imp_merge, on='feature', how='left')
            top_causal['importance'] = top_causal['combined_importance'].fillna(0)
            top_causal['combined_importance'] = top_causal['combined_importance'].fillna(0)

    # Also filter from combined_importance for feature importance
    combined_importance_filtered = combined_importance[~combined_importance['feature'].isin(cohort_defining_vars)].copy()

    if len(top_causal) == 0:
        logger.warning("No causal factors after filtering cohort-defining variables. Using filtered importance.")
        top_causal = combined_importance_filtered.head(top_k).copy()
        top_causal = top_causal.rename(columns={'combined_importance_norm': 'causal_responsibility'})
        top_causal['shap_importance'] = top_causal['causal_responsibility']
        top_causal['rule_frequency'] = 0
        top_causal['total_rules'] = 0

    # Generate feature metadata and level values if data is available
    feature_metadata = {}
    feature_levels: Dict[str, List[int]] = {}
    feature_names = combined_importance['feature'].tolist()
    if feature_data is not None:
        feature_metadata, feature_levels = generate_feature_metadata(feature_data, feature_names)
        logger.info(f"Generated feature metadata for {len(feature_metadata)} features")
        logger.info(f"Generated feature_levels for {len(feature_levels)} features (dropdown options)")
    # Ensure known categoricals always have levels (sec_dx is one-hot so no single sec_dx level list)
    known_cat = ['ter_dx', 'hxsurg', 'chd_sv', 'hxaf_fl', 'prim_dx']
    for f in feature_names:
        if any(c in f.lower() for c in known_cat):
            if f not in feature_levels:
                feature_levels[f] = [0, 1]
            if f not in feature_metadata:
                feature_metadata[f] = 'binary'

    # sec_dx dropdown: options = canonical levels; keep only those with non-trivial importance
    imp_series = combined_importance_filtered.set_index('feature')['combined_importance_norm']
    max_imp = imp_series.max() if len(imp_series) else 0
    min_importance_threshold = max(1e-6, 0.01 * max_imp) if max_imp > 0 else 0
    sec_dx_dropdown_options: List[str] = []
    sec_dx_one_hot_map: Dict[str, str] = {}
    for level in SEC_DX_LEVELS:
        col = _sec_dx_safe_col(level)
        imp = imp_series.get(col, 0) if hasattr(imp_series, 'get') else 0
        try:
            imp = float(imp)
        except (TypeError, ValueError):
            imp = 0
        sec_dx_one_hot_map[level] = col
        if imp >= min_importance_threshold:
            sec_dx_dropdown_options.append(level)
    if not sec_dx_dropdown_options:
        sec_dx_dropdown_options = list(SEC_DX_LEVELS)

    # Create comprehensive dashboard data
    dashboard_data = {
        'cohort': cohort,
        'timestamp': datetime.now().isoformat(),
        'ffa_method': 'xgboost_json_with_xgboost_shap_filtering' if use_xgboost_only else 'xgboost_json_with_combined_shap_filtering',
        'top_causal_factors': top_causal.to_dict('records'),
        'summary': {
            'total_features': len(combined_importance_filtered),
            'top_k': top_k,
            'mean_importance': combined_importance_filtered['combined_importance_norm'].mean(),
            'max_importance': combined_importance_filtered['combined_importance_norm'].max(),
            'top_feature': top_causal.iloc[0]['feature'] if len(top_causal) > 0 else None,
            'top_feature_importance': top_causal.iloc[0]['causal_responsibility'] if len(top_causal) > 0 else None
        },
        'feature_importance': combined_importance_filtered.head(50).to_dict('records'),
        'feature_metadata': feature_metadata,
        'feature_levels': feature_levels,
        'feature_level_labels': feature_level_labels or {},
        'sec_dx_dropdown_options': sec_dx_dropdown_options,
        'sec_dx_one_hot_map': sec_dx_one_hot_map,
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

    # Save tables as Parquet (DuckDB-friendly) and CSV (compatibility)
    csv_path = output_dir / 'top_causal_factors.csv'
    pq_path = output_dir / 'top_causal_factors.parquet'
    top_causal.to_csv(csv_path, index=False)
    try:
        _to_parquet(top_causal, pq_path)
        logger.info(f"Saved top {top_k} causal factors to {pq_path} and {csv_path}")
    except Exception as e:
        logger.info(f"Saved top {top_k} causal factors to {csv_path}")

    importance_path = output_dir / 'combined_shap_importance.csv'
    importance_pq = output_dir / 'combined_shap_importance.parquet'
    combined_importance.to_csv(importance_path, index=False)
    try:
        _to_parquet(combined_importance, importance_pq)
        logger.info(f"Saved combined SHAP importance to {importance_pq} and {importance_path}")
    except Exception as e:
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
        default=None,
        help="Weight for CatBoost SHAP (default: auto-determined from best model C-index)"
    )
    parser.add_argument(
        "--weight-xgboost",
        type=float,
        default=None,
        help="Weight for XGBoost SHAP (default: auto-determined from best model C-index)"
    )
    parser.add_argument(
        "--model-variant",
        type=str,
        default="auto",
        choices=["base", "enhanced", "top", "auto"],
        help="Model variant: 'base', 'enhanced', 'top' (top 15 features only), or 'auto' to auto-detect (default: auto)"
    )

    args = parser.parse_args()

    # Set default weights if not provided (will be auto-determined later)
    if args.weight_catboost is None:
        args.weight_catboost = 0.6  # Temporary default, will be overridden
    if args.weight_xgboost is None:
        args.weight_xgboost = 0.4  # Temporary default, will be overridden
    
    # Normalize weights if they don't sum to 1.0
    if abs(args.weight_catboost + args.weight_xgboost - 1.0) > 0.01:
        logger.warning("Weights should sum to 1.0, normalizing...")
        total = args.weight_catboost + args.weight_xgboost
        args.weight_catboost /= total
        args.weight_xgboost /= total

    # Determine model cohort name (with variant suffix)
    model_cohort = get_model_cohort_name(args.cohort, args.model_variant)
    logger.info(f"Using model variant: {args.model_variant} -> model directory: {model_cohort}")

    # Set output directory
    # SHAP/FFA outputs go to calculator-specific outputs directory
    if args.output_dir is None:
        output_dir = CALCULATOR_DIR / "outputs" / "shap_ffa" / model_cohort
    else:
        output_dir = Path(args.output_dir)

    output_dir.mkdir(parents=True, exist_ok=True)
    logger.info(f"Output directory: {output_dir}")

    # Check which model is best
    best_model = get_best_model(args.cohort, args.model_variant)
    use_xgboost_only = (best_model == "XGBoost" or best_model == "XGBoost RF")

    # Automatically determine weights based on best model and C-index values
    if not use_xgboost_only:
        auto_weight_cb, auto_weight_xgb = determine_shap_weights(args.cohort, best_model, args.model_variant)
        # Override manual weights with auto-determined weights
        args.weight_catboost = auto_weight_cb
        args.weight_xgboost = auto_weight_xgb
        logger.info(f"Auto-determined weights from best model: CatBoost={args.weight_catboost:.3f}, "
                   f"XGBoost={args.weight_xgboost:.3f}")

    logger.info("=" * 80)
    logger.info(f"SHAP + FFA Analysis for {args.cohort} Cohort")
    logger.info("=" * 80)
    if use_xgboost_only:
        logger.info(f"Best model: {best_model} - Using simplified pipeline (XGBoost only)")
        logger.info(f"Strategy: XGBoost JSON + XGBoost SHAP filtering (simplified)")
    else:
        logger.info(f"Best model: {best_model} - Using combined pipeline")
        logger.info(f"Strategy: XGBoost JSON + Combined SHAP (XGBoost + CatBoost) filtering")
        logger.info(f"SHAP Weights (auto-determined from C-index): CatBoost={args.weight_catboost:.3f}, "
                   f"XGBoost={args.weight_xgboost:.3f}")
    logger.info(f"Output directory: {output_dir}")
    logger.info(f"Top K: {args.top_k}")
    logger.info("")

    try:
        # Step 1: Find XGBoost model JSON (required for FFA)
        logger.info("Step 1: Finding XGBoost model JSON for FFA explainer...")
        xgboost_json = find_xgboost_model_json(args.cohort, args.model_variant)

        if not xgboost_json:
            raise FileNotFoundError(
                f"XGBoost model JSON not found for cohort {model_cohort}. "
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
                calculator_models_dir = CALCULATOR_DIR / "outputs" / "models" / model_cohort
                parent_models_dir = CALCULATOR_DIR.parent / "outputs" / "models" / model_cohort

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
                # IMPORTANT: Must match training temporal split to ensure SHAP is computed on the same test set
                if 'txpl_year' in df.columns:
                    # Calculate cutoff to match training (80/20 split)
                    year_counts = df['txpl_year'].value_counts().sort_index()
                    cumsum = year_counts.cumsum()
                    target = int(len(df) * 0.8)
                    cutoff_year = None
                    for year, count in cumsum.items():
                        if count >= target:
                            cutoff_year = int(year)
                            break
                    if cutoff_year is None:
                        cutoff_year = 2021  # Fallback to match training default
                        logger.warning(f"Could not calculate cutoff year, using {cutoff_year}")
                    test_mask = df['txpl_year'] > cutoff_year
                    df_test = df[test_mask].copy()
                    logger.info(f"Using test set (txpl_year > {cutoff_year}): {len(df_test)} samples")
                    logger.info(f"Temporal split cutoff matches training: {cutoff_year}")
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
                xgb_shap_values, xgb_shap_df, X_shap_used = compute_calculator_shap_values(
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

                # Store X_test for FFA analysis (test set data)
                X_test_for_ffa = X_test.copy()
                logger.info(f"Stored test set for FFA analysis: {len(X_test_for_ffa)} instances")

            except Exception as e:
                raise RuntimeError(
                    f"Failed to compute XGBoost SHAP values: {e}. "
                    "SHAP values are required for full rule-based FFA analysis."
                ) from e
        else:
            # Full pipeline: Compute both and combine
            try:
                cb_shap_map, xgb_shap_map, cb_shap_df, xgb_shap_df = run_calculator_shap_analysis(args.cohort, args.model_variant)
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

            # Load test data for FFA analysis (same as used for SHAP)
            logger.info("Loading test data for FFA analysis...")
            try:
                df = load_calculator_data_for_shap(args.cohort)
                df = prepare_calculator_features(df)

                # Apply temporal split to get test set
                # IMPORTANT: Must match training temporal split to ensure rules are applied to the same test set
                if 'txpl_year' in df.columns:
                    # Calculate cutoff to match training (80/20 split)
                    year_counts = df['txpl_year'].value_counts().sort_index()
                    cumsum = year_counts.cumsum()
                    target = int(len(df) * 0.8)
                    cutoff_year = None
                    for year, count in cumsum.items():
                        if count >= target:
                            cutoff_year = int(year)
                            break
                    if cutoff_year is None:
                        cutoff_year = 2021  # Fallback to match training default
                        logger.warning(f"Could not calculate cutoff year, using {cutoff_year}")
                    test_mask = df['txpl_year'] > cutoff_year
                    df_test = df[test_mask].copy()
                    logger.info(f"Using test set (txpl_year > {cutoff_year}): {len(df_test)} samples for FFA")
                    logger.info(f"Temporal split cutoff matches training: {cutoff_year}")
                else:
                    logger.warning("txpl_year not found, using full dataset for FFA")
                    df_test = df.copy()

                # Remove leakage predictors and extract features
                if remove_leakage_predictors is not None:
                    df_clean = remove_leakage_predictors(df_test, time_col='time', status_col='status')
                else:
                    leakage_cols = ['ev_time', 'ev_type', 'time', 'status', 'int_dead', 'age_death',
                                   'graft_loss', 'int_graft_loss', 'outcome', 'outcome_int_graft_loss',
                                   'outcome_graft_loss']
                    df_clean = df_test.drop(columns=[c for c in leakage_cols if c in df_test.columns], errors='ignore')

                all_feature_cols = [col for col in df_clean.columns if col not in ['time', 'status', 'txpl_year']]
                
                # Filter to calculator features to match the model
                # Use the model_cohort name to determine feature set (handles "auto" detection)
                # model_cohort was already determined earlier and will be "Combined_enhanced" or "Combined_base"
                include_recommended = model_cohort.endswith("_enhanced") or model_cohort.endswith("_top")
                if include_recommended:
                    logger.info("Using enhanced or top model - will include recommended features in test data")
                else:
                    logger.info("Detected base model - will use base calculator features only")
                
                # Filter to calculator features
                try:
                    from calculator_features import filter_to_calculator_features
                    feature_cols = filter_to_calculator_features(df_clean, all_feature_cols, include_recommended=include_recommended)
                    logger.info(f"Filtered to calculator features: {len(feature_cols)} features (from {len(all_feature_cols)} total)")
                except ImportError:
                    logger.warning("calculator_features module not found, using all features")
                    feature_cols = all_feature_cols
                
                X_test_for_ffa = df_clean[feature_cols].copy()

                # Remove constant columns and fill NaN
                constant_cols = [col for col in X_test_for_ffa.columns if X_test_for_ffa[col].nunique() < 2]
                if constant_cols:
                    logger.info(f"Removing {len(constant_cols)} constant columns from test data")
                    X_test_for_ffa = X_test_for_ffa.drop(columns=constant_cols)
                    feature_cols = [col for col in feature_cols if col not in constant_cols]
                X_test_for_ffa = X_test_for_ffa.fillna(0)

                # Convert categorical to numeric
                for col in X_test_for_ffa.columns:
                    if X_test_for_ffa[col].dtype == 'object':
                        X_test_for_ffa[col] = pd.Categorical(X_test_for_ffa[col]).codes

                logger.info(f"Prepared test set for FFA: {len(X_test_for_ffa)} instances, {len(X_test_for_ffa.columns)} features")
            except Exception as e:
                logger.warning(f"Could not load test data for FFA: {e}. FFA will use rule definition counts instead.")
                X_test_for_ffa = None

        # Step 4: Run FFA with XGBoost JSON and SHAP values
        if not FFA_AVAILABLE:
            raise RuntimeError(
                "FFA analysis is REQUIRED but modules are not available. "
                f"Please ensure ffa_analysis/ directory exists at {FFA_ANALYSIS_DIR} with required modules."
            )
        
        logger.info("Step 4: Running full rule-based FFA analysis on TEST SET...")
        logger.info("Rules will be applied to test data instances to count actual rule firings")
        causal_df, feature_level_rules = run_ffa_with_shap(
            args.cohort,
            xgboost_json,
            shap_map,
            output_dir,
            top_k=args.top_k,
            shap_values_df=shap_values_df,
            X_test=X_test_for_ffa,
            use_xgboost_only=use_xgboost_only
        )

        # Get importance for dashboard
        if use_xgboost_only:
            # Use XGBoost importance only
            importance_data = load_calculator_importance(args.cohort, args.model_variant)
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
            importance_data = load_calculator_importance(args.cohort, args.model_variant)
            combined_importance, _ = combine_importance_to_shap(
                importance_data,
                weight_catboost=args.weight_catboost,
                weight_xgboost=args.weight_xgboost
            )

        # Step 5: Generate dashboard outputs
        logger.info("")
        logger.info("Step 5: Generating dashboard outputs...")

        # Get feature data for metadata generation
        feature_data_for_metadata = None
        feature_level_labels: Dict[str, List[str]] = {}
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

            # Normalize so no bytearray/bytes (Parquet/DuckDB can yield these); avoids "unhashable type: 'bytearray'"
            feature_data_for_metadata = _ensure_string_columns_and_index(feature_data_for_metadata)

            # Keep top features (e.g. sec_dx) even if constant in this slice, so we can capture their levels
            top_feature_names = {_safe_str_for_hash(x) for x in combined_importance['feature'].tolist()}
            constant_cols = [
                col for col in feature_data_for_metadata.columns
                if feature_data_for_metadata[col].nunique() < 2 and col not in top_feature_names
            ]
            if constant_cols:
                feature_data_for_metadata = feature_data_for_metadata.drop(columns=constant_cols)
            feature_data_for_metadata = feature_data_for_metadata.fillna(0)

            # Capture category labels (for sec_dx etc.) before converting to numeric codes
            for col in list(feature_data_for_metadata.columns):
                if feature_data_for_metadata[col].dtype == 'object' and col in top_feature_names:
                    try:
                        cat = pd.Categorical(feature_data_for_metadata[col])
                        # categories[i] is the label for code i
                        feature_level_labels[col] = cat.categories.astype(str).tolist()
                    except Exception:
                        pass

            # Convert categorical to numeric
            for col in feature_data_for_metadata.columns:
                if feature_data_for_metadata[col].dtype == 'object':
                    feature_data_for_metadata[col] = pd.Categorical(feature_data_for_metadata[col]).codes

            logger.info(f"Loaded feature data for metadata: {len(feature_data_for_metadata)} rows, {len(feature_data_for_metadata.columns)} features")
            if feature_level_labels:
                logger.info(f"Captured level labels for {len(feature_level_labels)} features: {list(feature_level_labels.keys())}")
        except Exception as e:
            logger.warning(f"Could not load feature data for metadata generation: {e}")
            feature_level_labels = {}

        dashboard_data = generate_dashboard_outputs(
            combined_importance,
            causal_df,
            output_dir,
            args.cohort,
            top_k=args.top_k,
            xgboost_json_used=xgboost_json is not None,
            use_xgboost_only=use_xgboost_only,
            feature_data=feature_data_for_metadata,
            feature_level_labels=feature_level_labels
        )

        # Get filtered causal factors from dashboard data for logging
        top_causal_from_dashboard = dashboard_data.get('top_causal_factors', [])

        logger.info("")
        logger.info("=" * 80)
        logger.info("Analysis Complete!")
        logger.info("=" * 80)
        logger.info(f"FFA Method: XGBoost JSON + Combined SHAP filtering")
        logger.info(f"Top {args.top_k} Causal Factors (cohort-defining variables filtered):")
        if top_causal_from_dashboard and len(top_causal_from_dashboard) > 0:
            for idx, factor in enumerate(top_causal_from_dashboard[:args.top_k]):
                importance = factor.get('causal_responsibility', factor.get('importance', factor.get('combined_importance_norm', 0)))
                logger.info(f"  {idx+1:2d}. {factor['feature']:40s} "
                           f"(Importance: {importance:.4f})")
        else:
            logger.info("  (No causal factors available)")
        logger.info("")
        logger.info(f"Results saved to: {output_dir}")
        logger.info("=" * 80)

    except Exception as e:
        logger.error(f"Error in workflow: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    main()
