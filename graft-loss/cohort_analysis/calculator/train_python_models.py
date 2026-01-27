"""
Train CatBoost and XGBoost survival models in Python for SHAP/FFA analysis.

This script replaces the R-based model training with Python implementations
that are fully compatible with the Python SHAP and FFA explainers.
"""

import json
import logging
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Optional

import numpy as np
import pandas as pd
from catboost import CatBoostRegressor, Pool
import xgboost as xgb
from sklearn.model_selection import StratifiedShuffleSplit
from joblib import Parallel, delayed

try:
    from sksurv.metrics import concordance_index_censored
    HAS_SKSURV = True
except ImportError:
    HAS_SKSURV = False
    # Fallback C-index calculation
    def concordance_index_censored(event_indicator, event_time, estimate):
        """Simple C-index calculation without sksurv."""
        from itertools import combinations
        
        event_indicator = np.asarray(event_indicator, dtype=bool)
        event_time = np.asarray(event_time)
        estimate = np.asarray(estimate)
        
        # Get pairs of comparable observations
        n = len(event_time)
        concordant = 0
        comparable = 0
        
        for i, j in combinations(range(n), 2):
            # Comparable if:
            # - Both events: compare times
            # - i event, j censored: i.time < j.time
            # - i censored, j event: j.time < i.time
            # - Both censored: not comparable
            
            if event_indicator[i] and event_indicator[j]:
                # Both events: comparable
                comparable += 1
                if (event_time[i] < event_time[j] and estimate[i] > estimate[j]) or \
                   (event_time[i] > event_time[j] and estimate[i] < estimate[j]):
                    concordant += 1
            elif event_indicator[i] and not event_indicator[j]:
                # i event, j censored: comparable if i.time < j.time
                if event_time[i] < event_time[j]:
                    comparable += 1
                    if estimate[i] > estimate[j]:
                        concordant += 1
            elif not event_indicator[i] and event_indicator[j]:
                # i censored, j event: comparable if j.time < i.time
                if event_time[j] < event_time[i]:
                    comparable += 1
                    if estimate[j] > estimate[i]:
                        concordant += 1
        
        c_index = concordant / comparable if comparable > 0 else 0.0
        return c_index, comparable, concordant, 0, 0

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(Path(__file__).parent))

from run_shap_ffa_workflow import (
    load_calculator_data_for_shap,
    prepare_calculator_features
)

# Import feature importance functions
try:
    from scripts.py.feature_importance_model_utils import (
        get_importance_catboost,
        get_importance_xgboost
    )
except ImportError:
    # Fallback: try relative import
    sys.path.insert(0, str(PROJECT_ROOT / "scripts" / "py"))
    from feature_importance_model_utils import (
        get_importance_catboost,
        get_importance_xgboost
    )

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

CALCULATOR_DIR = Path(__file__).parent
OUTPUTS_DIR = CALCULATOR_DIR / "outputs"
MODELS_DIR = OUTPUTS_DIR / "models"


def get_survival_leakage_keywords(cohort: Optional[str] = None) -> List[str]:
    """
    Get list of keywords that indicate target leakage in survival models.
    Matches the R function get_survival_leakage_keywords().
    
    Args:
        cohort: Cohort name. For Combined model, primary_etiology is kept (not removed).
    """
    keywords = [
        # Identifiers and outcomes (handled separately in drop_cols)
        "transplant_year", "txpl_year",
        # Cohort-defining variables (should not be features - defines the cohort itself)
        "prim_dx", "PRIM_DX",  # Primary diagnosis defines cohorts (CHD, Myocardio, Combined)
        # Donor/survival variables and obvious leak sources
        "graft_loss", "int_graft_loss", "dtx_", "cc_", "isc_oth",
        "dcardiac", "dcon", "dpri", "dpricaus", "rec_", "papooth",
        "dneuro", "sdprathr", "int_dead", "listing_year", "cpathneg",
        "dcauseod",
        # Demographics (optional, keep if clinically needed)
        "race", "sex", "drace_b", "rrace_a", "hisp", "Iscntry", "lscntry",  # lscntry = listing country (not modifiable)
        # Transplant-specific variables often post-outcome or unclear timing
        "dreject", "dsecaccsEmpty", "dmajbldEmpty", "pishltgr1R",
        "drejectEmpty", "drejectHyperacute", "pishltgrEmpty", "pishltgr",
        "dmajbld", "dsecaccs", "dsecaccs_bin",
        # Clinical variables to exclude (timing/definition risk)
        "dx_cardiomyopathy", "deathspc", "dlist", "pmorexam", "patsupp",
        "concod", "pcadrem", "pcadrec", "pathero", "pdiffib", "dmalcanc",
        "alt_tx", "age_death", "pacuref",
        # Additional variables
        "lsvcma", "cpbypass"
    ]
    
    # For Combined model, keep primary_etiology (it's needed to distinguish etiologies)
    # For CHD and Myocardio models, remove it (cohort is already defined)
    if cohort != "Combined":
        keywords.append("primary_etiology")
    
    return keywords


def remove_leakage_predictors(
    df: pd.DataFrame,
    leak_keywords: Optional[List[str]] = None,
    drop_cols: Optional[List[str]] = None,
    drop_starts_with: Optional[List[str]] = None,
    time_col: str = "time",
    status_col: str = "status"
) -> pd.DataFrame:
    """
    Remove leakage predictors from dataframe.
    Matches the R function remove_leakage_predictors().
    
    Args:
        df: Input dataframe
        leak_keywords: Keywords to match (default: get_survival_leakage_keywords())
        drop_cols: Exact column names to drop (default: ["ptid_e", "ev_time", "ev_type", "outcome", "transplant_year"])
        drop_starts_with: Prefixes to drop (default: ["sd"])
        time_col: Name of time column (always kept)
        status_col: Name of status column (always kept)
        
    Returns:
        Dataframe with leakage predictors removed
    """
    if leak_keywords is None:
        leak_keywords = get_survival_leakage_keywords()
    if drop_cols is None:
        drop_cols = ["ptid_e", "ev_time", "ev_type", "outcome", "transplant_year"]
    if drop_starts_with is None:
        drop_starts_with = ["sd"]
    
    nm = list(df.columns)
    
    # Match by pattern (keywords)
    pattern = "|".join(leak_keywords) if leak_keywords else "^$"
    by_pattern = [bool(re.search(pattern, col)) for col in nm]
    
    # Match by prefix
    by_prefix = [False] * len(nm)
    if drop_starts_with:
        for pref in drop_starts_with:
            for i, col in enumerate(nm):
                if col.startswith(pref):
                    by_prefix[i] = True
    
    # Match by exact name
    by_exact = [col in drop_cols for col in nm]
    
    # Combine all matches
    drop_set = [col for i, col in enumerate(nm) if by_pattern[i] or by_prefix[i] or by_exact[i]]
    
    # Always keep time and status columns
    keep_set = [col for col in nm if col not in drop_set]
    
    logger.info(f"[LeakFilter] Dropping {len(drop_set)} columns; keeping {len(keep_set)} predictors")
    if drop_set:
        logger.info(f"[LeakFilter] Dropped: {', '.join(drop_set[:20])}" + 
                   (f" ... and {len(drop_set) - 20} more" if len(drop_set) > 20 else ""))
    
    return df[keep_set].copy()


def train_catboost_survival(
    X_train: pd.DataFrame,
    y_train: np.ndarray,  # Signed time: +time for events, -time for censored
    X_test: pd.DataFrame,
    y_test: np.ndarray,
    time_test: np.ndarray,
    status_test: np.ndarray,
    feature_names: List[str],
    cohort_name: str,
    output_dir: Path
) -> Tuple[CatBoostRegressor, float]:
    """
    Train CatBoost survival model with Cox regression.
    
    Args:
        X_train: Training features
        y_train: Signed time labels (+time for events, -time for censored)
        X_test: Test features
        y_test: Signed time labels for test
        time_test: Actual time values for C-index calculation
        status_test: Event indicators for C-index calculation
        feature_names: List of feature names
        cohort_name: Name of cohort
        output_dir: Directory to save model
        
    Returns:
        Tuple of (trained_model, c_index)
    """
    logger.info(f"Training CatBoost survival model for {cohort_name}...")
    logger.info(f"  Training data: {X_train.shape}, Test data: {X_test.shape}")
    
    # CatBoost parameters matching R implementation
    params = {
        'loss_function': 'Cox',
        'eval_metric': 'Cox',
        'iterations': 1200,
        'depth': 4,
        'learning_rate': 0.1,
        'thread_count': 1,
        'logging_level': 'Silent'
    }
    
    # Identify categorical features
    cat_features = []
    for i, col in enumerate(X_train.columns):
        if X_train[col].dtype == 'object' or X_train[col].dtype.name == 'category':
            cat_features.append(i)
    
    if cat_features:
        logger.info(f"  Found {len(cat_features)} categorical features")
    
    # Create CatBoost pools
    train_pool = Pool(
        data=X_train,
        label=y_train,
        cat_features=cat_features if cat_features else None
    )
    
    test_pool = Pool(
        data=X_test,
        label=y_test,
        cat_features=cat_features if cat_features else None
    )
    
    # Train model
    model = CatBoostRegressor(**params)
    model.fit(
        train_pool,
        eval_set=test_pool,
        # Don't use verbose parameter - logging_level='Silent' in params handles it
        use_best_model=True
    )
    
    # Predict risk scores (higher = higher risk)
    risk_scores = model.predict(X_test)
    
    # Calculate C-index
    c_index, _, _, _, _ = concordance_index_censored(
        status_test.astype(bool),
        time_test,
        risk_scores
    )
    
    logger.info(f"  CatBoost C-index: {c_index:.6f}")
    
    # Save model
    model_path = output_dir / "catboost_model.cbm"
    model.save_model(str(model_path))
    logger.info(f"  Saved CatBoost model to {model_path}")
    
    return model, c_index


def train_xgboost_survival(
    X_train: pd.DataFrame,
    y_train: np.ndarray,  # Signed time: +time for events, -time for censored
    X_test: pd.DataFrame,
    y_test: np.ndarray,
    time_test: np.ndarray,
    status_test: np.ndarray,
    feature_names: List[str],
    cohort_name: str,
    output_dir: Path
) -> Tuple[xgb.Booster, float]:
    """
    Train XGBoost survival model with Cox regression.
    
    Args:
        X_train: Training features
        y_train: Signed time labels (+time for events, -time for censored)
        X_test: Test features
        y_test: Signed time labels for test
        time_test: Actual time values for C-index calculation
        status_test: Event indicators for C-index calculation
        feature_names: List of feature names
        cohort_name: Name of cohort
        output_dir: Directory to save model
        
    Returns:
        Tuple of (trained_model, c_index)
    """
    logger.info(f"Training XGBoost survival model for {cohort_name}...")
    logger.info(f"  Training data: {X_train.shape}, Test data: {X_test.shape}")
    
    # XGBoost parameters matching R implementation
    params = {
        'objective': 'survival:cox',
        'eval_metric': 'cox-nloglik',
        'eta': 0.05,
        'max_depth': 4,
        'subsample': 0.8,
        'colsample_bytree': 0.8,
        'tree_method': 'hist'
    }
    
    # Convert to numpy arrays
    X_train_arr = X_train.values.astype(np.float32)
    X_test_arr = X_test.values.astype(np.float32)
    
    # Create DMatrix objects
    dtrain = xgb.DMatrix(X_train_arr, label=y_train)
    dtest = xgb.DMatrix(X_test_arr, label=y_test)
    
    # Set feature names
    dtrain.feature_names = feature_names
    dtest.feature_names = feature_names
    
    # Train model
    model = xgb.train(
        params=params,
        dtrain=dtrain,
        num_boost_round=400,
        evals=[(dtrain, 'train'), (dtest, 'eval')],
        early_stopping_rounds=25,
        verbose_eval=100
    )
    
    # Predict risk scores (higher = higher risk)
    risk_scores = model.predict(dtest)
    
    # Calculate C-index
    c_index, _, _, _, _ = concordance_index_censored(
        status_test.astype(bool),
        time_test,
        risk_scores
    )
    
    logger.info(f"  XGBoost C-index: {c_index:.6f}")
    
    # Save model binary
    model_binary_path = output_dir / "xgboost_model.ubj"
    model.save_model(str(model_binary_path))
    logger.info(f"  Saved XGBoost binary to {model_binary_path}")
    
    # Save model JSON for FFA explainer
    json_dir = output_dir / "final_model_json"
    json_dir.mkdir(parents=True, exist_ok=True)
    
    # Get tree dumps in text format (as expected by FFA explainer)
    # Use dump_format="text" to get plain text dumps that the explainer can parse
    tree_dumps = model.get_dump(with_stats=True, dump_format='text')
    
    # Ensure tree_dumps is a list of strings
    if isinstance(tree_dumps, str):
        # If single string, split by newlines that indicate tree boundaries
        # XGBoost dumps are typically separated by empty lines or "booster[0]", "booster[1]", etc.
        tree_dumps = [tree_dumps]  # For now, treat as single tree
    elif not isinstance(tree_dumps, list):
        tree_dumps = list(tree_dumps)
    
    # Create JSON structure for FFA explainer
    model_json = {
        'model_type': 'xgboost',
        'trees': tree_dumps,  # List of tree dump strings
        'feature_names': feature_names
    }
    
    json_path = json_dir / f"{cohort_name}_final_model_xgboost.json"
    with open(json_path, 'w') as f:
        json.dump(model_json, f, indent=2)
    logger.info(f"  Saved XGBoost JSON to {json_path} (with {len(feature_names)} feature names)")
    
    return model, c_index


def train_xgboost_rf_survival(
    X_train: pd.DataFrame,
    y_train: np.ndarray,  # Signed time: +time for events, -time for censored
    X_test: pd.DataFrame,
    y_test: np.ndarray,
    time_test: np.ndarray,
    status_test: np.ndarray,
    feature_names: List[str],
    cohort_name: str,
    output_dir: Path
) -> Tuple[xgb.Booster, float]:
    """
    Train XGBoost Random Forest survival model with Cox regression.
    
    Args:
        X_train: Training features
        y_train: Signed time labels (+time for events, -time for censored)
        X_test: Test features
        y_test: Signed time labels for test
        time_test: Actual time values for C-index calculation
        status_test: Event indicators for C-index calculation
        feature_names: List of feature names
        cohort_name: Name of cohort
        output_dir: Directory to save model
        
    Returns:
        Tuple of (trained_model, c_index)
    """
    logger.info(f"Training XGBoost Random Forest survival model for {cohort_name}...")
    logger.info(f"  Training data: {X_train.shape}, Test data: {X_test.shape}")
    
    # XGBoost RF parameters
    # RF mode: build multiple trees in parallel, no sequential boosting
    params = {
        'objective': 'survival:cox',
        'eval_metric': 'cox-nloglik',
        'eta': 1.0,  # No learning rate in RF mode (each tree is independent)
        'max_depth': 6,
        'subsample': 0.8,  # Row sampling
        'colsample_bytree': 1.0,  # Use all features per tree (typical for RF)
        'tree_method': 'hist',
        'num_parallel_tree': 500  # Number of trees to build in parallel
    }
    
    # Convert to numpy arrays
    X_train_arr = X_train.values.astype(np.float32)
    X_test_arr = X_test.values.astype(np.float32)
    
    # Create DMatrix objects
    dtrain = xgb.DMatrix(X_train_arr, label=y_train)
    dtest = xgb.DMatrix(X_test_arr, label=y_test)
    
    # Set feature names
    dtrain.feature_names = feature_names
    dtest.feature_names = feature_names
    
    # Train model (RF mode: num_boost_round=1, all trees built in parallel)
    model = xgb.train(
        params=params,
        dtrain=dtrain,
        num_boost_round=1,  # RF mode: all trees built in one round
        evals=[(dtrain, 'train'), (dtest, 'eval')],
        verbose_eval=False  # RF doesn't have multiple rounds to show
    )
    
    # Predict risk scores (higher = higher risk)
    risk_scores = model.predict(dtest)
    
    # Calculate C-index
    c_index, _, _, _, _ = concordance_index_censored(
        status_test.astype(bool),
        time_test,
        risk_scores
    )
    
    logger.info(f"  XGBoost RF C-index: {c_index:.6f}")
    
    # Save model binary
    model_binary_path = output_dir / "xgboost_rf_model.ubj"
    model.save_model(str(model_binary_path))
    logger.info(f"  Saved XGBoost RF binary to {model_binary_path}")
    
    # Save model JSON for FFA explainer
    json_dir = output_dir / "final_model_json"
    json_dir.mkdir(parents=True, exist_ok=True)
    
    # Get tree dumps in text format
    tree_dumps = model.get_dump(with_stats=True, dump_format='text')
    
    # Ensure tree_dumps is a list of strings
    if isinstance(tree_dumps, str):
        tree_dumps = [tree_dumps]
    elif not isinstance(tree_dumps, list):
        tree_dumps = list(tree_dumps)
    
    # Create JSON structure for FFA explainer
    model_json = {
        'model_type': 'xgboost_rf',
        'trees': tree_dumps,
        'feature_names': feature_names
    }
    
    json_path = json_dir / f"{cohort_name}_final_model_xgboost_rf.json"
    with open(json_path, 'w') as f:
        json.dump(model_json, f, indent=2)
    logger.info(f"  Saved XGBoost RF JSON to {json_path} (with {len(feature_names)} feature names)")
    
    return model, c_index


def prepare_survival_labels(
    time: np.ndarray,
    status: np.ndarray
) -> np.ndarray:
    """
    Convert survival data to signed time labels for Cox regression.
    
    For Cox regression in CatBoost/XGBoost:
    - Events (status=1): use positive time
    - Censored (status=0): use negative time
    
    Args:
        time: Time to event or censoring
        status: Event indicator (1=event, 0=censored)
        
    Returns:
        Signed time array
    """
    signed_time = np.where(status == 1, time, -time)
    return signed_time.astype(np.float32)


def train_single_split_models(
    split_idx: int,
    X_train: pd.DataFrame,
    y_train: np.ndarray,
    X_test: pd.DataFrame,
    y_test: np.ndarray,
    time_test: np.ndarray,
    status_test: np.ndarray,
    feature_names: List[str],
    cohort_name: str,
    output_dir: Path
) -> Dict:
    """
    Train all three models (CatBoost, XGBoost, XGBoost RF) for a single MC-CV split.
    Also computes feature importances for each model.
    
    Returns:
        Dictionary with model results, C-index values, and feature importances
    """
    results = {
        'split': split_idx,
        'catboost_cindex': None,
        'xgboost_cindex': None,
        'xgboost_rf_cindex': None,
        'catboost_importance': None,
        'xgboost_importance': None,
        'xgboost_rf_importance': None,
        'status': 'error'
    }
    
    try:
        # Train CatBoost
        cb_model, cb_cindex = train_catboost_survival(
            X_train=X_train,
            y_train=y_train,
            X_test=X_test,
            y_test=y_test,
            time_test=time_test,
            status_test=status_test,
            feature_names=feature_names,
            cohort_name=cohort_name,
            output_dir=output_dir / f"split_{split_idx}"
        )
        results['catboost_cindex'] = cb_cindex
        
        # Get CatBoost feature importance
        try:
            cb_importance = get_importance_catboost(
                cb_model, 
                feature_names, 
                X_test=X_test, 
                y_test=status_test  # Use status for importance calculation
            )
            results['catboost_importance'] = cb_importance
        except Exception as e:
            logger.warning(f"Could not compute CatBoost importance for split {split_idx}: {e}")
            results['catboost_importance'] = pd.DataFrame({'feature': feature_names, 'importance': 0.0})
        
        # Train XGBoost
        xgb_model, xgb_cindex = train_xgboost_survival(
            X_train=X_train,
            y_train=y_train,
            X_test=X_test,
            y_test=y_test,
            time_test=time_test,
            status_test=status_test,
            feature_names=feature_names,
            cohort_name=cohort_name,
            output_dir=output_dir / f"split_{split_idx}"
        )
        results['xgboost_cindex'] = xgb_cindex
        
        # Get XGBoost feature importance
        try:
            xgb_importance = get_importance_xgboost(
                xgb_model,
                feature_names,
                X_test=X_test,
                y_test=status_test  # Use status for importance calculation
            )
            # Extract importance column (may be 'importance' or 'gain_importance')
            if 'importance' in xgb_importance.columns:
                xgb_importance = xgb_importance[['feature', 'importance']].copy()
            else:
                xgb_importance = xgb_importance[['feature', 'gain_importance']].copy()
                xgb_importance = xgb_importance.rename(columns={'gain_importance': 'importance'})
            results['xgboost_importance'] = xgb_importance
        except Exception as e:
            logger.warning(f"Could not compute XGBoost importance for split {split_idx}: {e}")
            results['xgboost_importance'] = pd.DataFrame({'feature': feature_names, 'importance': 0.0})
        
        # Train XGBoost RF
        xgb_rf_model, xgb_rf_cindex = train_xgboost_rf_survival(
            X_train=X_train,
            y_train=y_train,
            X_test=X_test,
            y_test=y_test,
            time_test=time_test,
            status_test=status_test,
            feature_names=feature_names,
            cohort_name=cohort_name,
            output_dir=output_dir / f"split_{split_idx}"
        )
        results['xgboost_rf_cindex'] = xgb_rf_cindex
        
        # Get XGBoost RF feature importance (same as XGBoost)
        try:
            xgb_rf_importance = get_importance_xgboost(
                xgb_rf_model,
                feature_names,
                X_test=X_test,
                y_test=status_test  # Use status for importance calculation
            )
            # Extract importance column
            if 'importance' in xgb_rf_importance.columns:
                xgb_rf_importance = xgb_rf_importance[['feature', 'importance']].copy()
            else:
                xgb_rf_importance = xgb_rf_importance[['feature', 'gain_importance']].copy()
                xgb_rf_importance = xgb_rf_importance.rename(columns={'gain_importance': 'importance'})
            results['xgboost_rf_importance'] = xgb_rf_importance
        except Exception as e:
            logger.warning(f"Could not compute XGBoost RF importance for split {split_idx}: {e}")
            results['xgboost_rf_importance'] = pd.DataFrame({'feature': feature_names, 'importance': 0.0})
        
        results['status'] = 'success'
        logger.info(f"Split {split_idx}: CatBoost={cb_cindex:.6f}, XGBoost={xgb_cindex:.6f}, XGBoost RF={xgb_rf_cindex:.6f}")
        
    except Exception as e:
        logger.error(f"Error in split {split_idx}: {e}", exc_info=True)
        results['error'] = str(e)
    
    return results


def train_models_for_cohort(cohort: str, n_mc_splits: int = 25, train_prop: float = 0.8, n_jobs: int = 1):
    """
    Train CatBoost, XGBoost (Gradient Boosting), and XGBoost Random Forest models for a cohort
    using Monte Carlo Cross-Validation (MC-CV) with 25 splits.
    
    For each of 25 stratified train/test splits:
    1. Trains all three models on the training set
    2. Evaluates each model on the test set using C-index
    3. Aggregates results across all splits
    4. Selects the best model based on mean C-index
    
    After MC-CV evaluation, trains the best model on the full temporal 80/20 split
    for final model deployment.
    
    Args:
        cohort: Cohort name (e.g., "Combined", "CHD", "Myocardio")
        n_mc_splits: Number of MC-CV splits (default: 25)
        train_prop: Training proportion for MC-CV splits (default: 0.8)
        n_jobs: Number of parallel jobs for MC-CV (default: 1)
    """
    logger.info(f"\n{'='*80}")
    logger.info(f"Training models for cohort: {cohort}")
    logger.info(f"{'='*80}\n")
    
    # Load and prepare data
    logger.info("Loading calculator data...")
    df = load_calculator_data_for_shap(cohort)
    logger.info(f"Loaded {len(df)} rows")
    
    # Prepare features
    df = prepare_calculator_features(df)
    
    # Derive survival labels from raw data (matching R code logic)
    # R code: ev_time = pmin(int_dead, int_graft_loss, na.rm = TRUE)
    #         ev_type = pmax(dtx_patient, graft_loss, na.rm = TRUE)
    if 'ev_time' not in df.columns:
        if 'int_dead' in df.columns and 'int_graft_loss' in df.columns:
            # ev_time = minimum of int_dead and int_graft_loss (earliest event)
            df['ev_time'] = df[['int_dead', 'int_graft_loss']].min(axis=1, skipna=True)
            logger.info("Derived ev_time from int_dead and int_graft_loss")
        elif 'outcome_int_graft_loss' in df.columns:
            df['ev_time'] = df['outcome_int_graft_loss']
            logger.info("Using outcome_int_graft_loss as ev_time")
        else:
            raise ValueError(
                f"Cannot derive ev_time. Need int_dead and int_graft_loss, or outcome_int_graft_loss. "
                f"Available columns: {[c for c in df.columns if 'dead' in c.lower() or 'graft' in c.lower() or 'time' in c.lower()][:10]}"
            )
    
    if 'ev_type' not in df.columns:
        if 'dtx_patient' in df.columns and 'graft_loss' in df.columns:
            # ev_type = maximum of dtx_patient and graft_loss (1 if either is 1)
            df['ev_type'] = df[['dtx_patient', 'graft_loss']].max(axis=1, skipna=True)
            logger.info("Derived ev_type from dtx_patient and graft_loss")
        elif 'outcome_graft_loss' in df.columns:
            df['ev_type'] = df['outcome_graft_loss']
            logger.info("Using outcome_graft_loss as ev_type")
        else:
            raise ValueError(
                f"Cannot derive ev_type. Need dtx_patient and graft_loss, or outcome_graft_loss. "
                f"Available columns: {[c for c in df.columns if 'dtx' in c.lower() or 'graft' in c.lower() or 'outcome' in c.lower()][:10]}"
            )
    
    # Fix non-positive times (set to small positive value if <= 0)
    # This matches R's fix_non_positive_times function
    if (df['ev_time'] <= 0).any():
        n_fixed = (df['ev_time'] <= 0).sum()
        df.loc[df['ev_time'] <= 0, 'ev_time'] = 0.1  # Small positive value
        logger.info(f"Fixed {n_fixed} non-positive ev_time values")
    
    # Map to time and status columns (standardize naming)
    if 'time' not in df.columns:
        df['time'] = df['ev_time']
    
    if 'status' not in df.columns:
        # ev_type: 1 = event, 0 = censored
        df['status'] = (df['ev_type'] == 1).astype(int)
    
    # Filter valid data
    df = df[
        df['time'].notna() & 
        df['status'].notna() & 
        (df['time'] > 0) & 
        (df['status'].isin([0, 1]))
    ].copy()
    
    logger.info(f"Valid survival data: {len(df)} rows")
    
    # Preserve txpl_year for temporal splitting (before leakage removal)
    # Note: txpl_year is a leakage variable but we need it for temporal split
    txpl_year_values = df['txpl_year'].values if 'txpl_year' in df.columns else None
    
    # Remove leakage predictors (matches R remove_leakage_predictors)
    # Pass cohort to get correct leakage keywords (keeps primary_etiology for Combined)
    leak_keywords = get_survival_leakage_keywords(cohort=cohort)
    df_clean = remove_leakage_predictors(df, leak_keywords=leak_keywords, time_col='time', status_col='status')
    
    # Re-add txpl_year if it was removed (needed for temporal split, but not as a feature)
    if txpl_year_values is not None and 'txpl_year' not in df_clean.columns:
        df_clean['txpl_year'] = txpl_year_values
    
    # Extract features (exclude time/status columns and txpl_year)
    feature_cols = [col for col in df_clean.columns if col not in ['time', 'status', 'txpl_year']]
    
    X = df_clean[feature_cols].copy()
    time = df_clean['time'].values
    status = df_clean['status'].values
    
    # Remove constant columns
    constant_cols = []
    for col in X.columns:
        unique_vals = X[col].dropna().unique()
        if len(unique_vals) < 2:
            constant_cols.append(col)
    
    if constant_cols:
        logger.info(f"Removing {len(constant_cols)} constant columns")
        X = X.drop(columns=constant_cols)
        feature_cols = [col for col in feature_cols if col not in constant_cols]
    
    # Fill NaN values
    X = X.fillna(0)
    
    # Convert categorical to numeric (simple encoding for now)
    for col in X.columns:
        if X[col].dtype == 'object':
            X[col] = pd.Categorical(X[col]).codes
    
    logger.info(f"Final feature matrix: {X.shape}")
    
    # Prepare signed time labels for full dataset (for MC CV splits)
    y_all = prepare_survival_labels(time, status)
    
    # Create output directory
    cohort_output_dir = MODELS_DIR / cohort
    cohort_output_dir.mkdir(parents=True, exist_ok=True)
    mc_cv_output_dir = cohort_output_dir / "mc_cv"
    mc_cv_output_dir.mkdir(parents=True, exist_ok=True)
    
    # ============================================================================
    # MONTE CARLO CROSS-VALIDATION (25 splits)
    # ============================================================================
    logger.info("\n" + "="*80)
    logger.info("MONTE CARLO CROSS-VALIDATION")
    logger.info("="*80)
    logger.info(f"Creating {n_mc_splits} stratified train/test splits...")
    
    # Create stratified splits (stratified by status to maintain event distribution)
    sss = StratifiedShuffleSplit(n_splits=n_mc_splits, test_size=1-train_prop, random_state=42)
    split_indices = []
    for train_idx, test_idx in sss.split(X, status):
        split_indices.append({
            'train_idx': train_idx,
            'test_idx': test_idx
        })
    
    logger.info(f"Created {len(split_indices)} MC-CV splits")
    logger.info(f"  Training proportion: {train_prop:.1%}")
    logger.info(f"  Test proportion: {1-train_prop:.1%}")
    
    # Run MC-CV splits in parallel
    logger.info(f"\nRunning MC-CV with {n_jobs} parallel jobs...")
    logger.info("Training all three models (CatBoost, XGBoost, XGBoost RF) on each split...")
    
    mc_cv_results = Parallel(n_jobs=n_jobs, verbose=10)(
        delayed(train_single_split_models)(
            split_idx=i,
            X_train=X.iloc[split_indices[i]['train_idx']].copy(),
            y_train=y_all[split_indices[i]['train_idx']],
            X_test=X.iloc[split_indices[i]['test_idx']].copy(),
            y_test=y_all[split_indices[i]['test_idx']],
            time_test=time[split_indices[i]['test_idx']],
            status_test=status[split_indices[i]['test_idx']],
            feature_names=feature_cols,
            cohort_name=cohort,
            output_dir=mc_cv_output_dir
        )
        for i in range(len(split_indices))
    )
    
    # Filter successful splits
    successful_results = [r for r in mc_cv_results if r['status'] == 'success']
    failed_results = [r for r in mc_cv_results if r['status'] == 'error']
    
    logger.info(f"\nMC-CV Results: {len(successful_results)}/{len(mc_cv_results)} splits successful")
    if failed_results:
        logger.warning(f"  {len(failed_results)} splits failed")
        for r in failed_results[:3]:  # Show first 3 errors
            logger.warning(f"    Split {r['split']}: {r.get('error', 'Unknown error')}")
    
    if len(successful_results) == 0:
        raise ValueError("No successful MC-CV splits. Cannot proceed with model selection.")
    
    # ============================================================================
    # AGGREGATE MODEL METRICS (C-index across splits)
    # ============================================================================
    logger.info("\n" + "="*80)
    logger.info("AGGREGATING MODEL METRICS")
    logger.info("="*80)
    
    # Collect C-index values for each model
    cb_cindices = [r['catboost_cindex'] for r in successful_results if r['catboost_cindex'] is not None]
    xgb_cindices = [r['xgboost_cindex'] for r in successful_results if r['xgboost_cindex'] is not None]
    xgb_rf_cindices = [r['xgboost_rf_cindex'] for r in successful_results if r['xgboost_rf_cindex'] is not None]
    
    # Calculate statistics for each model
    def calc_stats(cindices, model_name):
        if len(cindices) == 0:
            return {
                'mean': np.nan,
                'std': np.nan,
                'ci_lower': np.nan,
                'ci_upper': np.nan,
                'n_splits': 0
            }
        cindices_arr = np.array(cindices)
        return {
            'mean': float(np.mean(cindices_arr)),
            'std': float(np.std(cindices_arr)),
            'ci_lower': float(np.percentile(cindices_arr, 2.5)),
            'ci_upper': float(np.percentile(cindices_arr, 97.5)),
            'n_splits': len(cindices)
        }
    
    cb_stats = calc_stats(cb_cindices, 'CatBoost')
    xgb_stats = calc_stats(xgb_cindices, 'XGBoost')
    xgb_rf_stats = calc_stats(xgb_rf_cindices, 'XGBoost RF')
    
    # Create metrics DataFrame
    metrics_df = pd.DataFrame([
        {
            'Model': 'CatBoost',
            'C_Index_Mean': cb_stats['mean'],
            'C_Index_SD': cb_stats['std'],
            'C_Index_CI_Lower': cb_stats['ci_lower'],
            'C_Index_CI_Upper': cb_stats['ci_upper'],
            'n_splits': cb_stats['n_splits']
        },
        {
            'Model': 'XGBoost',
            'C_Index_Mean': xgb_stats['mean'],
            'C_Index_SD': xgb_stats['std'],
            'C_Index_CI_Lower': xgb_stats['ci_lower'],
            'C_Index_CI_Upper': xgb_stats['ci_upper'],
            'n_splits': xgb_stats['n_splits']
        },
        {
            'Model': 'XGBoost RF',
            'C_Index_Mean': xgb_rf_stats['mean'],
            'C_Index_SD': xgb_rf_stats['std'],
            'C_Index_CI_Lower': xgb_rf_stats['ci_lower'],
            'C_Index_CI_Upper': xgb_rf_stats['ci_upper'],
            'n_splits': xgb_rf_stats['n_splits']
        }
    ])
    
    # Save metrics
    metrics_path = cohort_output_dir / "mc_cv_model_metrics.csv"
    metrics_df.to_csv(metrics_path, index=False)
    logger.info(f"Saved MC-CV metrics to: {metrics_path}")
    
    # Print summary
    logger.info("\nMC-CV Model Performance Summary:")
    for _, row in metrics_df.iterrows():
        logger.info(f"  {row['Model']:15s}: C-index = {row['C_Index_Mean']:.6f} ± {row['C_Index_SD']:.6f} "
                   f"(95% CI: {row['C_Index_CI_Lower']:.6f} - {row['C_Index_CI_Upper']:.6f}) "
                   f"[{int(row['n_splits'])} splits]")
    
    # Determine best model based on mean C-index
    best_model_row = metrics_df.loc[metrics_df['C_Index_Mean'].idxmax()]
    best_model_name = best_model_row['Model']
    best_c_index = best_model_row['C_Index_Mean']
    
    logger.info(f"\nBest Model: {best_model_name} (Mean C-index: {best_c_index:.6f})")
    
    # ============================================================================
    # AGGREGATE FEATURE IMPORTANCES
    # ============================================================================
    logger.info("\n" + "="*80)
    logger.info("AGGREGATING FEATURE IMPORTANCES")
    logger.info("="*80)
    
    # Collect feature importances for each model across all splits
    model_importances = {
        'CatBoost': [],
        'XGBoost': [],
        'XGBoost RF': []
    }
    
    for r in successful_results:
        if r['catboost_importance'] is not None:
            imp = r['catboost_importance'].copy()
            imp['split'] = r['split']
            model_importances['CatBoost'].append(imp)
        
        if r['xgboost_importance'] is not None:
            imp = r['xgboost_importance'].copy()
            imp['split'] = r['split']
            model_importances['XGBoost'].append(imp)
        
        if r['xgboost_rf_importance'] is not None:
            imp = r['xgboost_rf_importance'].copy()
            imp['split'] = r['split']
            model_importances['XGBoost RF'].append(imp)
    
    # Aggregate feature importances for each model
    aggregated_importances = {}
    for model_name, importance_list in model_importances.items():
        if len(importance_list) == 0:
            logger.warning(f"No feature importances collected for {model_name}")
            continue
        
        # Combine all splits
        all_importance = pd.concat(importance_list, ignore_index=True)
        
        # Aggregate by feature
        aggregated = all_importance.groupby('feature').agg({
            'importance': ['mean', 'std', 'count']
        }).reset_index()
        
        # Flatten column names
        aggregated.columns = ['feature', 'importance_mean', 'importance_std', 'importance_count']
        
        # Sort by mean importance
        aggregated = aggregated.sort_values('importance_mean', ascending=False)
        aggregated['Model'] = model_name
        
        aggregated_importances[model_name] = aggregated
        logger.info(f"  {model_name}: Aggregated {len(aggregated)} features from {len(importance_list)} splits")
    
    # Save aggregated feature importances
    for model_name, agg_df in aggregated_importances.items():
        imp_path = cohort_output_dir / f"mc_cv_{model_name.lower().replace(' ', '_')}_feature_importance.csv"
        agg_df.to_csv(imp_path, index=False)
        logger.info(f"  Saved {model_name} feature importance to: {imp_path}")
    
    # Combine all models for visualization
    if aggregated_importances:
        all_importance_df = pd.concat(aggregated_importances.values(), ignore_index=True)
        all_importance_path = cohort_output_dir / "mc_cv_all_models_feature_importance.csv"
        all_importance_df.to_csv(all_importance_path, index=False)
        logger.info(f"  Saved combined feature importance to: {all_importance_path}")
    
    # ============================================================================
    # CREATE VISUALIZATIONS
    # ============================================================================
    logger.info("\n" + "="*80)
    logger.info("CREATING VISUALIZATIONS")
    logger.info("="*80)
    
    try:
        import matplotlib
        matplotlib.use('Agg')  # Non-interactive backend
        import matplotlib.pyplot as plt
        import seaborn as sns
        
        plots_dir = cohort_output_dir / "plots"
        plots_dir.mkdir(parents=True, exist_ok=True)
        
        # 1. C-index Heatmap
        logger.info("Creating C-index heatmap...")
        fig, ax = plt.subplots(figsize=(8, 4))
        cindex_matrix = metrics_df.pivot_table(
            values='C_Index_Mean',
            index='Model',
            columns=None
        )
        # For single cohort, create a simple bar chart
        ax.bar(metrics_df['Model'], metrics_df['C_Index_Mean'], 
               yerr=metrics_df['C_Index_SD'], capsize=5, alpha=0.7)
        ax.set_ylabel('C-index (Mean ± SD)')
        ax.set_xlabel('Model')
        ax.set_title(f'Model Performance Comparison ({cohort})')
        ax.grid(axis='y', alpha=0.3)
        plt.tight_layout()
        cindex_plot_path = plots_dir / "cindex_comparison.png"
        plt.savefig(cindex_plot_path, dpi=300, bbox_inches='tight')
        plt.close()
        logger.info(f"  Saved C-index comparison to: {cindex_plot_path}")
        
        # 2. Feature Importance Heatmap (if we have aggregated importances)
        if aggregated_importances:
            logger.info("Creating feature importance heatmap...")
            
            # Get top N features (e.g., top 30)
            top_n = 30
            all_features = all_importance_df.groupby('feature')['importance_mean'].sum().sort_values(ascending=False)
            top_features = all_features.head(top_n).index.tolist()
            
            # Create matrix: features (rows) × models (columns)
            heatmap_data = []
            for model_name in ['CatBoost', 'XGBoost', 'XGBoost RF']:
                if model_name in aggregated_importances:
                    model_df = aggregated_importances[model_name]
                    for feat in top_features:
                        feat_data = model_df[model_df['feature'] == feat]
                        if len(feat_data) > 0:
                            heatmap_data.append({
                                'feature': feat,
                                'Model': model_name,
                                'importance': feat_data['importance_mean'].iloc[0]
                            })
                        else:
                            heatmap_data.append({
                                'feature': feat,
                                'Model': model_name,
                                'importance': 0.0
                            })
            
            if heatmap_data:
                heatmap_df = pd.DataFrame(heatmap_data)
                
                # Normalize importance within each model for visualization
                for model_name in heatmap_df['Model'].unique():
                    mask = heatmap_df['Model'] == model_name
                    max_imp = heatmap_df.loc[mask, 'importance'].max()
                    if max_imp > 0:
                        heatmap_df.loc[mask, 'importance_normalized'] = heatmap_df.loc[mask, 'importance'] / max_imp
                    else:
                        heatmap_df.loc[mask, 'importance_normalized'] = 0.0
                
                # Create pivot table for heatmap
                pivot_data = heatmap_df.pivot_table(
                    values='importance_normalized',
                    index='feature',
                    columns='Model',
                    fill_value=0.0
                )
                
                # Sort features by total importance
                feature_order = heatmap_df.groupby('feature')['importance'].sum().sort_values(ascending=False).index
                pivot_data = pivot_data.reindex(feature_order)
                
                # Create heatmap
                fig, ax = plt.subplots(figsize=(10, max(12, len(top_features) * 0.4)))
                sns.heatmap(
                    pivot_data,
                    annot=False,
                    cmap='YlOrRd',
                    cbar_kws={'label': 'Normalized Importance'},
                    ax=ax,
                    linewidths=0.5
                )
                ax.set_title(f'Feature Importance Heatmap by Model ({cohort}, Top {top_n} Features)', fontsize=14, fontweight='bold')
                ax.set_xlabel('Model', fontsize=12)
                ax.set_ylabel('Feature', fontsize=12)
                plt.tight_layout()
                heatmap_path = plots_dir / "feature_importance_heatmap.png"
                plt.savefig(heatmap_path, dpi=300, bbox_inches='tight')
                plt.close()
                logger.info(f"  Saved feature importance heatmap to: {heatmap_path}")
        
    except ImportError:
        logger.warning("Matplotlib/Seaborn not available. Skipping visualizations.")
        logger.warning("  Install with: pip install matplotlib seaborn")
    except Exception as e:
        logger.warning(f"Error creating visualizations: {e}", exc_info=True)
    
    # ============================================================================
    # TRAIN FINAL MODEL ON TEMPORAL SPLIT
    # ============================================================================
    logger.info("\n" + "="*80)
    logger.info("TRAINING FINAL MODEL (Temporal 80/20 Split)")
    logger.info("="*80)
    logger.info("Training best model ({}) on full temporal split for deployment...".format(best_model_name))
    
    # Create temporal split for final model
    if 'txpl_year' in df_clean.columns:
        year_counts = df_clean['txpl_year'].value_counts().sort_index()
        cumsum = year_counts.cumsum()
        target = int(len(df_clean) * 0.8)
        
        cutoff_year = None
        for year, count in cumsum.items():
            if count >= target:
                cutoff_year = int(year)
                break
        
        if cutoff_year is None:
            cutoff_year = 2021
            logger.warning(f"Could not find cutoff year, using {cutoff_year}")
        
        train_mask = df_clean['txpl_year'] <= cutoff_year
        test_mask = df_clean['txpl_year'] > cutoff_year
        
        logger.info(f"Temporal split: Train (≤{cutoff_year}): {train_mask.sum()} samples, "
                   f"Test (>{cutoff_year}): {test_mask.sum()} samples")
        
        X_train_final = X[train_mask].copy()
        X_test_final = X[test_mask].copy()
        time_train_final = time[train_mask]
        time_test_final = time[test_mask]
        status_train_final = status[train_mask]
        status_test_final = status[test_mask]
    else:
        logger.warning("txpl_year not found, using full dataset")
        X_train_final = X
        X_test_final = X
        time_train_final = time
        time_test_final = time
        status_train_final = status
        status_test_final = status
    
    y_train_final = prepare_survival_labels(time_train_final, status_train_final)
    y_test_final = prepare_survival_labels(time_test_final, status_test_final)
    
    # Train the best model on temporal split
    if best_model_name == 'CatBoost':
        final_model, final_cindex = train_catboost_survival(
            X_train=X_train_final,
            y_train=y_train_final,
            X_test=X_test_final,
            y_test=y_test_final,
            time_test=time_test_final,
            status_test=status_test_final,
            feature_names=feature_cols,
            cohort_name=cohort,
            output_dir=cohort_output_dir
        )
    elif best_model_name == 'XGBoost':
        final_model, final_cindex = train_xgboost_survival(
            X_train=X_train_final,
            y_train=y_train_final,
            X_test=X_test_final,
            y_test=y_test_final,
            time_test=time_test_final,
            status_test=status_test_final,
            feature_names=feature_cols,
            cohort_name=cohort,
            output_dir=cohort_output_dir
        )
    else:  # XGBoost RF
        final_model, final_cindex = train_xgboost_rf_survival(
            X_train=X_train_final,
            y_train=y_train_final,
            X_test=X_test_final,
            y_test=y_test_final,
            time_test=time_test_final,
            status_test=status_test_final,
            feature_names=feature_cols,
            cohort_name=cohort,
            output_dir=cohort_output_dir
        )
    
    logger.info(f"Final {best_model_name} model C-index (temporal split): {final_cindex:.6f}")
    
    # Also train all three models for SHAP/FFA analysis (as before)
    logger.info("\nTraining all three models for SHAP/FFA analysis...")
    
    cb_model, cb_cindex = train_catboost_survival(
        X_train=X_train_final,
        y_train=y_train_final,
        X_test=X_test_final,
        y_test=y_test_final,
        time_test=time_test_final,
        status_test=status_test_final,
        feature_names=feature_cols,
        cohort_name=cohort,
        output_dir=cohort_output_dir
    )
    
    xgb_model, xgb_cindex = train_xgboost_survival(
        X_train=X_train_final,
        y_train=y_train_final,
        X_test=X_test_final,
        y_test=y_test_final,
        time_test=time_test_final,
        status_test=status_test_final,
        feature_names=feature_cols,
        cohort_name=cohort,
        output_dir=cohort_output_dir
    )
    
    xgb_rf_model, xgb_rf_cindex = train_xgboost_rf_survival(
        X_train=X_train_final,
        y_train=y_train_final,
        X_test=X_test_final,
        y_test=y_test_final,
        time_test=time_test_final,
        status_test=status_test_final,
        feature_names=feature_cols,
        cohort_name=cohort,
        output_dir=cohort_output_dir
    )
    
    # Save best model info
    best_model_path = cohort_output_dir / "best_model.txt"
    with open(best_model_path, 'w') as f:
        f.write(f"Best Model (MC-CV): {best_model_name}\n")
        f.write(f"MC-CV Mean C-index: {best_c_index:.6f}\n")
        f.write(f"MC-CV 95% CI: [{best_model_row['C_Index_CI_Lower']:.6f}, {best_model_row['C_Index_CI_Upper']:.6f}]\n")
        f.write(f"MC-CV SD: {best_model_row['C_Index_SD']:.6f}\n")
        f.write(f"MC-CV n_splits: {int(best_model_row['n_splits'])}\n")
        f.write(f"\nTemporal Split Results:\n")
        f.write(f"  CatBoost: {cb_cindex:.6f}\n")
        f.write(f"  XGBoost: {xgb_cindex:.6f}\n")
        f.write(f"  XGBoost RF: {xgb_rf_cindex:.6f}\n")
        f.write(f"\nMC-CV Model Performance (all models):\n")
        for _, row in metrics_df.iterrows():
            f.write(f"  {row['Model']}: {row['C_Index_Mean']:.6f} ± {row['C_Index_SD']:.6f} "
                   f"(95% CI: {row['C_Index_CI_Lower']:.6f} - {row['C_Index_CI_Upper']:.6f}) "
                   f"[{int(row['n_splits'])} splits]\n")
    
    logger.info(f"\n{'='*80}")
    logger.info("TRAINING COMPLETE")
    logger.info(f"{'='*80}")
    logger.info(f"Best Model (MC-CV): {best_model_name}")
    logger.info(f"MC-CV Mean C-index: {best_c_index:.6f}")
    logger.info(f"\nAll outputs saved to: {cohort_output_dir}")
    logger.info(f"  - MC-CV metrics: {metrics_path}")
    logger.info(f"  - Feature importances: {cohort_output_dir / 'mc_cv_*_feature_importance.csv'}")
    logger.info(f"  - Visualizations: {plots_dir}")
    logger.info(f"  - Final models: {cohort_output_dir}")


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Train Python survival models")
    parser.add_argument("--cohort", type=str, default="Combined",
                       choices=["Combined", "CHD", "Myocardio"],
                       help="Cohort to train models for (default: Combined - single model for all cohorts)")
    parser.add_argument("--n_mc_splits", type=int, default=25,
                       help="Number of Monte Carlo cross-validation splits (default: 25)")
    parser.add_argument("--train_prop", type=float, default=0.8,
                       help="Training proportion for MC-CV splits (default: 0.8)")
    parser.add_argument("--n_jobs", type=int, default=1,
                       help="Number of parallel jobs for MC-CV (default: 1)")
    
    args = parser.parse_args()
    
    # Always train Combined model (single model for all cohorts)
    if args.cohort != "Combined":
        logger.warning(f"Requested cohort '{args.cohort}' but using Combined model for all cohorts. Training Combined model.")
    
    train_models_for_cohort(
        cohort="Combined",
        n_mc_splits=args.n_mc_splits,
        train_prop=args.train_prop,
        n_jobs=args.n_jobs
    )
