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

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

CALCULATOR_DIR = Path(__file__).parent
OUTPUTS_DIR = CALCULATOR_DIR / "outputs"
MODELS_DIR = OUTPUTS_DIR / "models"


def get_survival_leakage_keywords() -> List[str]:
    """
    Get list of keywords that indicate target leakage in survival models.
    Matches the R function get_survival_leakage_keywords().
    """
    return [
        # Identifiers and outcomes (handled separately in drop_cols)
        "transplant_year", "primary_etiology", "txpl_year",
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


def train_models_for_cohort(cohort: str):
    """
    Train CatBoost, XGBoost (Gradient Boosting), and XGBoost Random Forest models for a cohort.
    
    Evaluates all three models and reports which performs best, while saving all three
    for SHAP/FFA analysis (matching R calculator approach).
    
    Args:
        cohort: Cohort name (e.g., "Combined", "CHD", "Myocardio")
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
    df_clean = remove_leakage_predictors(df, time_col='time', status_col='status')
    
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
    
    # Create ordered 80/20 split by year (temporal split)
    # Train on earlier years, test on later years
    if 'txpl_year' in df_clean.columns:
        # Find cutoff year for 80/20 split
        year_counts = df_clean['txpl_year'].value_counts().sort_index()
        cumsum = year_counts.cumsum()
        target = int(len(df_clean) * 0.8)
        
        cutoff_year = None
        for year, count in cumsum.items():
            if count >= target:
                cutoff_year = int(year)
                break
        
        if cutoff_year is None:
            # Fallback: use 2021 as cutoff
            cutoff_year = 2021
            logger.warning(f"Could not find cutoff year, using {cutoff_year}")
        
        train_mask = df_clean['txpl_year'] <= cutoff_year
        test_mask = df_clean['txpl_year'] > cutoff_year
        
        logger.info(f"Temporal split: Train (≤{cutoff_year}): {train_mask.sum()} samples, "
                   f"Test (>{cutoff_year}): {test_mask.sum()} samples")
        
        X_train = X[train_mask].copy()
        X_test = X[test_mask].copy()
        time_train = time[train_mask]
        time_test = time[test_mask]
        status_train = status[train_mask]
        status_test = status[test_mask]
    else:
        # Fallback: use full dataset if txpl_year not available
        logger.warning("txpl_year not found, using full dataset for both train and test")
        X_train = X
        X_test = X
        time_train = time
        time_test = time
        status_train = status
        status_test = status
    
    # Prepare signed time labels
    y_train = prepare_survival_labels(time_train, status_train)
    y_test = prepare_survival_labels(time_test, status_test)
    
    # Create output directory
    cohort_output_dir = MODELS_DIR / cohort
    cohort_output_dir.mkdir(parents=True, exist_ok=True)
    
    # Train CatBoost
    logger.info("\n" + "="*80)
    logger.info("Training CatBoost")
    logger.info("="*80)
    cb_model, cb_cindex = train_catboost_survival(
        X_train=X_train,
        y_train=y_train,
        X_test=X_test,
        y_test=y_test,
        time_test=time_test,
        status_test=status_test,
        feature_names=feature_cols,
        cohort_name=cohort,
        output_dir=cohort_output_dir
    )
    
    # Train XGBoost (Gradient Boosting)
    logger.info("\n" + "="*80)
    logger.info("Training XGBoost (Gradient Boosting)")
    logger.info("="*80)
    xgb_model, xgb_cindex = train_xgboost_survival(
        X_train=X_train,
        y_train=y_train,
        X_test=X_test,
        y_test=y_test,
        time_test=time_test,
        status_test=status_test,
        feature_names=feature_cols,
        cohort_name=cohort,
        output_dir=cohort_output_dir
    )
    
    # Train XGBoost Random Forest
    logger.info("\n" + "="*80)
    logger.info("Training XGBoost Random Forest")
    logger.info("="*80)
    xgb_rf_model, xgb_rf_cindex = train_xgboost_rf_survival(
        X_train=X_train,
        y_train=y_train,
        X_test=X_test,
        y_test=y_test,
        time_test=time_test,
        status_test=status_test,
        feature_names=feature_cols,
        cohort_name=cohort,
        output_dir=cohort_output_dir
    )
    
    logger.info("\n" + "="*80)
    logger.info("Training Complete")
    logger.info("="*80)
    logger.info(f"CatBoost C-index: {cb_cindex:.6f}")
    logger.info(f"XGBoost C-index: {xgb_cindex:.6f}")
    logger.info(f"XGBoost RF C-index: {xgb_rf_cindex:.6f}")
    
    # Compare models and identify best
    model_results = {
        "CatBoost": cb_cindex,
        "XGBoost": xgb_cindex,
        "XGBoost RF": xgb_rf_cindex
    }
    
    best_model_name = max(model_results, key=model_results.get)
    best_c_index = model_results[best_model_name]
    
    logger.info("\n" + "="*80)
    logger.info("Model Comparison")
    logger.info("="*80)
    logger.info(f"Best Model: {best_model_name} (C-index: {best_c_index:.6f})")
    logger.info(f"\nAll models saved to: {cohort_output_dir}")
    logger.info("  (All models saved for SHAP/FFA analysis, matching R calculator approach)")
    
    # Save best model info to file
    best_model_path = cohort_output_dir / "best_model.txt"
    with open(best_model_path, 'w') as f:
        f.write(f"Best Model: {best_model_name}\n")
        f.write(f"C-index: {best_c_index:.6f}\n")
        f.write(f"\nAll Model Results:\n")
        for model_name, c_idx in sorted(model_results.items(), key=lambda x: x[1], reverse=True):
            f.write(f"  {model_name}: {c_idx:.6f}\n")
    logger.info(f"  Best model info saved to: {best_model_path}")


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Train Python survival models")
    parser.add_argument("--cohort", type=str, default="Combined",
                       choices=["Combined", "CHD", "Myocardio"],
                       help="Cohort to train models for (default: Combined - single model for all cohorts)")
    
    args = parser.parse_args()
    
    # Always train Combined model (single model for all cohorts)
    if args.cohort != "Combined":
        logger.warning(f"Requested cohort '{args.cohort}' but using Combined model for all cohorts. Training Combined model.")
    
    train_models_for_cohort("Combined")
