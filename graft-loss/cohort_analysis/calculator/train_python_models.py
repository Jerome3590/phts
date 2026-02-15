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

# Import metrics for AUC and AU-PRC
try:
    from sklearn.metrics import roc_auc_score, average_precision_score
    HAS_SKLEARN_METRICS = True
except ImportError:
    HAS_SKLEARN_METRICS = False

# Standard model performance metrics for all models (top, wisotzkey, base, enhanced).
# Order: C-Index, Recall, AUC, AUC-PR. Used in mc_cv_model_metrics.csv, best_model.txt, and plots.
STANDARD_METRICS = ["C_Index_Mean", "Recall_Mean", "AUC_Mean", "AU_PRC_Mean"]
STANDARD_METRICS_DISPLAY = ["C-index", "Recall", "AUC", "AU-PRC"]


def calculate_survival_auc_auprc_recall(
    time_test: np.ndarray,
    status_test: np.ndarray,
    risk_scores: np.ndarray,
    time_horizon: float = 365.25  # Default: 1 year in days
) -> Tuple[float, float, float]:
    """
    Calculate AUC, AU-PRC, and Recall for survival models at a specific time horizon.
    
    Converts survival problem to binary classification:
    - Positive class: event occurred by time_horizon
    - Negative class: no event by time_horizon (censored or event after time_horizon)
    
    Args:
        time_test: Time to event or censoring (in days)
        status_test: Event indicator (1=event, 0=censored)
        risk_scores: Risk scores from model (higher = higher risk)
        time_horizon: Time horizon for binary classification (default: 365.25 days = 1 year)
        
    Returns:
        Tuple of (AUC, AU-PRC, Recall) or (np.nan, np.nan, np.nan) if calculation fails
    """
    if not HAS_SKLEARN_METRICS:
        return np.nan, np.nan, np.nan
    
    try:
        # Convert to binary classification problem at time_horizon
        # Positive: event occurred by time_horizon
        # Negative: no event by time_horizon (censored before time_horizon, or event after time_horizon)
        
        binary_labels = np.zeros(len(time_test), dtype=int)
        
        for i in range(len(time_test)):
            if status_test[i] == 1:  # Event occurred
                if time_test[i] <= time_horizon:
                    binary_labels[i] = 1  # Positive: event by time_horizon
                # else: event after time_horizon -> negative (0)
            else:  # Censored
                if time_test[i] > time_horizon:
                    # Censored after time_horizon: we don't know if event occurred
                    # Exclude from evaluation (set to NaN)
                    binary_labels[i] = np.nan
                # else: censored before time_horizon -> negative (0)
        
        # Remove NaN labels and corresponding risk scores
        valid_mask = ~np.isnan(binary_labels)
        if valid_mask.sum() < 2:
            logger.warning(f"Insufficient data for AUC/AU-PRC/Recall at time_horizon={time_horizon}")
            return np.nan, np.nan, np.nan
        
        binary_labels_clean = binary_labels[valid_mask].astype(int)
        risk_scores_clean = risk_scores[valid_mask]
        
        # Check if we have both classes
        if len(np.unique(binary_labels_clean)) < 2:
            logger.warning(f"Only one class present for AUC/AU-PRC/Recall at time_horizon={time_horizon}")
            return np.nan, np.nan, np.nan
        
        # Normalize risk scores to [0, 1] for probability interpretation
        # Higher risk = higher probability of event
        risk_min = risk_scores_clean.min()
        risk_max = risk_scores_clean.max()
        if risk_max > risk_min:
            risk_probs = (risk_scores_clean - risk_min) / (risk_max - risk_min)
        else:
            risk_probs = np.ones_like(risk_scores_clean) * 0.5
        
        # Calculate AUC (ROC-AUC)
        auc = roc_auc_score(binary_labels_clean, risk_probs)
        
        # Calculate AU-PRC (Average Precision)
        auprc = average_precision_score(binary_labels_clean, risk_probs)
        
        # Calculate Recall (Sensitivity) using optimal threshold
        # Use Youden's J statistic (maximizes TPR - FPR) for optimal threshold
        from sklearn.metrics import roc_curve
        fpr, tpr, thresholds = roc_curve(binary_labels_clean, risk_probs)
        youden_j = tpr - fpr
        optimal_idx = np.argmax(youden_j)
        optimal_threshold = thresholds[optimal_idx] if optimal_idx < len(thresholds) else np.median(risk_probs)
        
        # Fallback to F1-maximizing threshold if Youden's J doesn't work well
        # (e.g., if optimal threshold is at extreme values)
        if optimal_threshold <= 0.01 or optimal_threshold >= 0.99:
            # Use F1 score to find optimal threshold
            from sklearn.metrics import f1_score
            best_f1 = 0
            best_threshold = np.median(risk_probs)
            for thresh in np.linspace(0.1, 0.9, 81):  # Test thresholds from 0.1 to 0.9
                preds = (risk_probs >= thresh).astype(int)
                f1 = f1_score(binary_labels_clean, preds, zero_division=0)
                if f1 > best_f1:
                    best_f1 = f1
                    best_threshold = thresh
            optimal_threshold = best_threshold
        
        predictions = (risk_probs >= optimal_threshold).astype(int)
        
        # Recall = TP / (TP + FN)
        tp = np.sum((predictions == 1) & (binary_labels_clean == 1))
        fn = np.sum((predictions == 0) & (binary_labels_clean == 1))
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        
        return float(auc), float(auprc), float(recall)
        
    except Exception as e:
        logger.warning(f"Error calculating AUC/AU-PRC/Recall: {e}")
        return np.nan, np.nan, np.nan

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(Path(__file__).parent))

# Delay import of run_shap_ffa_workflow to avoid circular import
# These will be imported inside train_models_for_cohort function

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


def check_training_complete(cohort_output_dir: Path, n_mc_splits: int) -> bool:
    """
    Check if all training outputs are complete and training can be skipped.

    Args:
        cohort_output_dir: Output directory for the cohort (e.g., outputs/models/Combined_base)
        n_mc_splits: Expected number of MC-CV splits

    Returns:
        True if all outputs are complete, False otherwise
    """
    if not cohort_output_dir.exists():
        return False

    mc_cv_output_dir = cohort_output_dir / "mc_cv"
    plots_dir = cohort_output_dir / "plots"

    # Check MC-CV models for all splits
    required_splits = set(range(n_mc_splits))
    found_splits = set()

    for split_dir in mc_cv_output_dir.glob("split_*"):
        try:
            split_num = int(split_dir.name.split("_")[1])
            if split_num in required_splits:
                # Check for all three model files
                catboost_model = split_dir / "catboost_model.cbm"
                xgboost_model = split_dir / "xgboost_model.ubj"
                xgboost_rf_model = split_dir / "xgboost_rf_model.ubj"

                # Check for JSON models (at least one should exist)
                json_dir = split_dir / "final_model_json"
                json_files = list(json_dir.glob("*.json")) if json_dir.exists() else []

                if catboost_model.exists() and xgboost_model.exists() and xgboost_rf_model.exists() and len(json_files) > 0:
                    found_splits.add(split_num)
        except (ValueError, IndexError):
            continue

    if len(found_splits) < n_mc_splits:
        logger.info(f"MC-CV incomplete: {len(found_splits)}/{n_mc_splits} splits found")
        return False

    # Check aggregated outputs
    required_files = [
        cohort_output_dir / "mc_cv_model_metrics.csv",
        cohort_output_dir / "mc_cv_catboost_feature_importance.csv",
        cohort_output_dir / "mc_cv_xgboost_feature_importance.csv",
        cohort_output_dir / "mc_cv_xgboost_rf_feature_importance.csv",
        cohort_output_dir / "mc_cv_all_models_feature_importance.csv",
        cohort_output_dir / "best_model.txt",
    ]

    for file_path in required_files:
        if not file_path.exists():
            logger.info(f"Missing aggregated output: {file_path.name}")
            return False

    # Check final models (temporal split)
    final_models = [
        cohort_output_dir / "catboost_model.cbm",
        cohort_output_dir / "xgboost_model.ubj",
        cohort_output_dir / "xgboost_rf_model.ubj",
    ]

    for model_path in final_models:
        if not model_path.exists():
            logger.info(f"Missing final model: {model_path.name}")
            return False

    # Check final model JSON files
    final_json_dir = cohort_output_dir / "final_model_json"
    if not final_json_dir.exists():
        logger.info("Missing final_model_json directory")
        return False

    final_json_files = list(final_json_dir.glob("*.json"))
    if len(final_json_files) == 0:
        logger.info("No JSON files in final_model_json directory")
        return False

    # Check visualizations (optional but good to have)
    # We'll check for at least one plot to ensure visualizations ran
    if plots_dir.exists():
        plot_files = list(plots_dir.glob("*.png"))
        if len(plot_files) == 0:
            logger.info("No visualization plots found (optional, but expected)")
            # Don't fail on missing plots - they're optional

    logger.info(f"All training outputs complete for {cohort_output_dir.name}")
    return True


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
    output_dir: Path,
    cat_feature_indices: List[int] = None  # Optional: pre-identified categorical feature indices
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
        cat_feature_indices: Optional list of categorical feature indices (if features were pre-encoded)
        
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
    # If cat_feature_indices provided, use those (for pre-encoded categoricals)
    # Otherwise, check for object/category dtype
    if cat_feature_indices is not None:
        cat_features = cat_feature_indices
        logger.info(f"  Using {len(cat_features)} pre-identified categorical features (indices: {cat_features[:10]}{'...' if len(cat_features) > 10 else ''})")
    else:
        cat_features = []
        for i, col in enumerate(X_train.columns):
            if X_train[col].dtype == 'object' or X_train[col].dtype.name == 'category':
                cat_features.append(i)
        if cat_features:
            logger.info(f"  Found {len(cat_features)} categorical features by dtype check")
    
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
    output_dir.mkdir(parents=True, exist_ok=True)
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
    output_dir.mkdir(parents=True, exist_ok=True)
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
    output_dir.mkdir(parents=True, exist_ok=True)
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
    output_dir: Path,
    cat_feature_indices: List[int] = None,  # Optional: categorical feature indices
    X_train_xgb: pd.DataFrame = None,  # Optional: XGBoost version with numeric-encoded categoricals
    X_test_xgb: pd.DataFrame = None,  # Optional: XGBoost version with numeric-encoded categoricals
    time_horizon: float = 365.25  # Default: 1 year in days for AUC/AU-PRC
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
        'catboost_auc': None,
        'xgboost_auc': None,
        'xgboost_rf_auc': None,
        'catboost_auprc': None,
        'xgboost_auprc': None,
        'xgboost_rf_auprc': None,
        'catboost_recall': None,
        'xgboost_recall': None,
        'xgboost_rf_recall': None,
        'catboost_importance': None,
        'xgboost_importance': None,
        'xgboost_rf_importance': None,
        'status': 'error'
    }
    
    try:
        # Train CatBoost
        # Pass categorical feature indices if provided
        cb_model, cb_cindex = train_catboost_survival(
            X_train=X_train,
            y_train=y_train,
            X_test=X_test,
            y_test=y_test,
            time_test=time_test,
            status_test=status_test,
            feature_names=feature_names,
            cohort_name=cohort_name,
            output_dir=output_dir / f"split_{split_idx}",
            cat_feature_indices=cat_feature_indices
        )
        results['catboost_cindex'] = cb_cindex
        
        # Calculate AUC, AU-PRC, and Recall for CatBoost
        cb_risk_scores = cb_model.predict(X_test)
        cb_auc, cb_auprc, cb_recall = calculate_survival_auc_auprc_recall(time_test, status_test, cb_risk_scores)
        results['catboost_auc'] = cb_auc
        results['catboost_auprc'] = cb_auprc
        results['catboost_recall'] = cb_recall
        
        # Get CatBoost feature importance
        # For survival models, use signed time labels (y_test) for importance calculation
        # CatBoost's get_feature_importance works with the same label format used for training
        # Pass categorical feature indices so CatBoost knows which features are categorical
        try:
            cb_importance = get_importance_catboost(
                cb_model, 
                feature_names, 
                X_test=X_test, 
                y_test=y_test,  # Use signed time labels (same format as training)
                cat_feature_indices=cat_feature_indices  # Pass categorical feature indices
            )
            results['catboost_importance'] = cb_importance
        except Exception as e:
            logger.warning(f"Could not compute CatBoost importance for split {split_idx}: {e}")
            results['catboost_importance'] = pd.DataFrame({'feature': feature_names, 'importance': 0.0})
        
        # Train XGBoost (use numeric-encoded version if provided)
        X_train_xgb_use = X_train_xgb if X_train_xgb is not None else X_train
        X_test_xgb_use = X_test_xgb if X_test_xgb is not None else X_test
        xgb_model, xgb_cindex = train_xgboost_survival(
            X_train=X_train_xgb_use,
            y_train=y_train,
            X_test=X_test_xgb_use,
            y_test=y_test,
            time_test=time_test,
            status_test=status_test,
            feature_names=feature_names,
            cohort_name=cohort_name,
            output_dir=output_dir / f"split_{split_idx}"
        )
        results['xgboost_cindex'] = xgb_cindex
        
        # Calculate AUC, AU-PRC, and Recall for XGBoost
        xgb_test_dmatrix = xgb.DMatrix(X_test_xgb_use.values.astype(np.float32))
        xgb_test_dmatrix.feature_names = feature_names
        xgb_risk_scores = xgb_model.predict(xgb_test_dmatrix)
        xgb_auc, xgb_auprc, xgb_recall = calculate_survival_auc_auprc_recall(time_test, status_test, xgb_risk_scores)
        results['xgboost_auc'] = xgb_auc
        results['xgboost_auprc'] = xgb_auprc
        results['xgboost_recall'] = xgb_recall
        
        # Get XGBoost feature importance
        # For survival models, we need to use a custom C-index scorer
        # XGBoost Booster needs DMatrix, so we'll create a wrapper
        try:
            # Create custom C-index scorer for survival that handles XGBoost DMatrix
            def cindex_scorer(model_or_pred, X_or_pred, y):
                """Custom scorer using C-index for survival models."""
                # Handle both XGBoost (model_or_pred is None, X_or_pred is predictions)
                # and other models (model_or_pred is model, X_or_pred is X)
                if model_or_pred is None:
                    # XGBoost case: X_or_pred is already predictions
                    risk_scores = X_or_pred
                else:
                    # Other models: need to predict
                    risk_scores = model_or_pred.predict(X_or_pred)
                
                # y is signed time labels (+time for events, -time for censored)
                # Extract time and status
                time_vals = np.abs(y)
                status_vals = (y > 0).astype(int)
                
                # Calculate C-index
                c_index, _, _, _, _ = concordance_index_censored(
                    status_vals.astype(bool),
                    time_vals,
                    risk_scores
                )
                return c_index
            
            xgb_importance = get_importance_xgboost(
                xgb_model,
                feature_names,
                X_test=X_test_xgb_use,
                y_test=y_test,  # Use signed time labels
                scoring=cindex_scorer
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
        
        # Train XGBoost RF (use numeric-encoded version if provided)
        xgb_rf_model, xgb_rf_cindex = train_xgboost_rf_survival(
            X_train=X_train_xgb_use,
            y_train=y_train,
            X_test=X_test_xgb_use,
            y_test=y_test,
            time_test=time_test,
            status_test=status_test,
            feature_names=feature_names,
            cohort_name=cohort_name,
            output_dir=output_dir / f"split_{split_idx}"
        )
        results['xgboost_rf_cindex'] = xgb_rf_cindex
        
        # Calculate AUC, AU-PRC, and Recall for XGBoost RF
        xgb_rf_test_dmatrix = xgb.DMatrix(X_test_xgb_use.values.astype(np.float32))
        xgb_rf_test_dmatrix.feature_names = feature_names
        xgb_rf_risk_scores = xgb_rf_model.predict(xgb_rf_test_dmatrix)
        xgb_rf_auc, xgb_rf_auprc, xgb_rf_recall = calculate_survival_auc_auprc_recall(time_test, status_test, xgb_rf_risk_scores)
        results['xgboost_rf_auc'] = xgb_rf_auc
        results['xgboost_rf_auprc'] = xgb_rf_auprc
        results['xgboost_rf_recall'] = xgb_rf_recall
        
        # Get XGBoost RF feature importance (same as XGBoost)
        try:
            # Create custom C-index scorer for survival that handles XGBoost DMatrix
            def cindex_scorer(model_or_pred, X_or_pred, y):
                """Custom scorer using C-index for survival models."""
                # Handle both XGBoost (model_or_pred is None, X_or_pred is predictions)
                # and other models (model_or_pred is model, X_or_pred is X)
                if model_or_pred is None:
                    # XGBoost case: X_or_pred is already predictions
                    risk_scores = X_or_pred
                else:
                    # Other models: need to predict
                    risk_scores = model_or_pred.predict(X_or_pred)
                
                # y is signed time labels (+time for events, -time for censored)
                # Extract time and status
                time_vals = np.abs(y)
                status_vals = (y > 0).astype(int)
                
                # Calculate C-index
                c_index, _, _, _, _ = concordance_index_censored(
                    status_vals.astype(bool),
                    time_vals,
                    risk_scores
                )
                return c_index
            
            xgb_rf_importance = get_importance_xgboost(
                xgb_rf_model,
                feature_names,
                X_test=X_test_xgb_use,
                y_test=y_test,  # Use signed time labels
                scoring=cindex_scorer
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
        logger.info(f"Split {split_idx}: CatBoost C-index={cb_cindex:.6f} AUC={cb_auc:.4f} AU-PRC={cb_auprc:.4f} Recall={cb_recall:.4f}, "
                   f"XGBoost C-index={xgb_cindex:.6f} AUC={xgb_auc:.4f} AU-PRC={xgb_auprc:.4f} Recall={xgb_recall:.4f}, "
                   f"XGBoost RF C-index={xgb_rf_cindex:.6f} AUC={xgb_rf_auc:.4f} AU-PRC={xgb_rf_auprc:.4f} Recall={xgb_rf_recall:.4f}")
        
    except Exception as e:
        logger.error(f"Error in split {split_idx}: {e}", exc_info=True)
        results['error'] = str(e)
    
    return results


def train_models_for_cohort(
    cohort: str,
    n_mc_splits: int = 25,
    train_prop: float = 0.8,
    n_jobs: int = 1,
    time_horizon: float = 365.25,
    include_recommended_features: bool = False,
    top_feature_names: Optional[List[str]] = None,
    use_wisotzkey_vars_only: bool = False,
    force: bool = True,
):
    """
    Train CatBoost, XGBoost (Gradient Boosting), and XGBoost Random Forest models for a cohort
    using Monte Carlo Cross-Validation (MC-CV) with 25 splits.
    
    For each of 25 stratified train/test splits:
    1. Trains all three models on the training set
    2. Evaluates each model on the test set using C-index
    3. Aggregates results across all splits
    4. Selects the best model based on mean C-index (primary), then AU-PRC (tiebreaker)
    
    After MC-CV evaluation, trains the best model on the full temporal 80/20 split
    for final model deployment.
    
    Args:
        cohort: Cohort name (e.g., "Combined", "CHD", "Myocardio")
        n_mc_splits: Number of MC-CV splits (default: 25)
        train_prop: Training proportion for MC-CV splits (default: 0.8)
        n_jobs: Number of parallel jobs for MC-CV (default: 1)
        include_recommended_features: If True, use base + recommended features (Extended).
        top_feature_names: If set, train only on these features (top causal/importance from SHAP/FFA).
            Output is saved to cohort_top (e.g. Combined_top). Data is loaded with recommended
            features so that top features like sec_dx, lsbaosat are available.
        use_wisotzkey_vars_only: If True, train on Wisotzkey et al. variable set (same SAS data).
            Output: cohort_wisotzkey. Use with top-15 models for comparison.
        force: If True (default), re-run training even when outputs exist. If False, skip when outputs exist (idempotent).
    """
    logger.info(f"\n{'='*80}")
    logger.info(f"Training models for cohort: {cohort}")
    logger.info(f"{'='*80}")
    logger.info(f"MC-CV Configuration:")
    logger.info(f"  - Number of splits: {n_mc_splits}")
    logger.info(f"  - Training proportion: {train_prop:.1%}")
    logger.info(f"  - Parallel jobs: {n_jobs}")
    logger.info(f"  - Time horizon for AUC/AU-PRC/Recall: {time_horizon} days")
    logger.info("")

    if use_wisotzkey_vars_only:
        from wisotzkey_data import load_wisotzkey_data_for_training, WISOTZKEY_FEATURES
        logger.info("Loading Wisotzkey-vars data (same SAS dataset as calculator pipeline)...")
        df = load_wisotzkey_data_for_training(cohort)
        df_clean = df[
            df["time"].notna()
            & df["status"].notna()
            & (df["time"] > 0)
            & (df["status"].isin([0, 1]))
        ].copy()
        feature_cols = [f for f in WISOTZKEY_FEATURES if f in df_clean.columns]
        missing = set(WISOTZKEY_FEATURES) - set(feature_cols)
        if missing:
            raise ValueError(f"Wisotzkey data missing columns: {missing}")
        logger.info(f"Valid survival data: {len(df_clean)} rows (Wisotzkey vars: {len(feature_cols)} features)")
        if "txpl_year" not in df_clean.columns:
            df_clean["txpl_year"] = 2020
    else:
        from run_shap_ffa_workflow import (
            load_calculator_data_for_shap,
            prepare_calculator_features
        )
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

        if (df['ev_time'] <= 0).any():
            n_fixed = (df['ev_time'] <= 0).sum()
            df.loc[df['ev_time'] <= 0, 'ev_time'] = 0.1
            logger.info(f"Fixed {n_fixed} non-positive ev_time values")

        if 'time' not in df.columns:
            df['time'] = df['ev_time']
        if 'status' not in df.columns:
            df['status'] = (df['ev_type'] == 1).astype(int)

        df = df[
            df['time'].notna() & df['status'].notna() & (df['time'] > 0) & (df['status'].isin([0, 1]))
        ].copy()
        logger.info(f"Valid survival data: {len(df)} rows")

        txpl_year_values = df['txpl_year'].values if 'txpl_year' in df.columns else None
        leak_keywords = get_survival_leakage_keywords(cohort=cohort)
        df_clean = remove_leakage_predictors(df, leak_keywords=leak_keywords, time_col='time', status_col='status')
        if txpl_year_values is not None and 'txpl_year' not in df_clean.columns:
            df_clean['txpl_year'] = txpl_year_values

        all_feature_cols = [col for col in df_clean.columns if col not in ['time', 'status', 'txpl_year']]
        from calculator_features import filter_to_calculator_features
        use_recommended_for_filter = include_recommended_features or (top_feature_names is not None)
        feature_cols = filter_to_calculator_features(df_clean, all_feature_cols, include_recommended=use_recommended_for_filter)

        if top_feature_names is not None:
            from calculator_features import get_sec_dx_one_hot_columns
            expanded_top = []
            for f in top_feature_names:
                if f == "sec_dx":
                    expanded_top.extend(get_sec_dx_one_hot_columns())
                else:
                    expanded_top.append(f)
            if "sec_dx" in top_feature_names:
                logger.info(f"Expanded sec_dx to one-hot columns: {get_sec_dx_one_hot_columns()}")
            missing = set(expanded_top) - set(feature_cols)
            if missing:
                sec_dx_missing = [c for c in missing if c.startswith("sec_dx_")]
                if sec_dx_missing:
                    for col in sec_dx_missing:
                        df_clean[col] = 0
                    feature_cols = list(feature_cols) + sec_dx_missing
                    logger.info(f"Added missing sec_dx one-hot columns (as 0): {sec_dx_missing}")
                other_missing = missing - set(sec_dx_missing)
                if other_missing:
                    logger.warning(f"Top features not in data (dropped): {other_missing}")
            feature_cols = [f for f in expanded_top if f in feature_cols]
            logger.info(f"Restricted to top causal/importance features: {len(feature_cols)} features")
        else:
            feature_set_name = "calculator features (with recommended)" if include_recommended_features else "base calculator features"
            logger.info(f"Filtered to {feature_set_name}: {len(feature_cols)} features (from {len(all_feature_cols)} total)")
        if len(feature_cols) < len(all_feature_cols):
            removed = set(all_feature_cols) - set(feature_cols)
            logger.info(f"Removed {len(removed)} non-calculator features (e.g., {', '.join(list(removed)[:10])}...)")

        if include_recommended_features and top_feature_names is None:
            from calculator_features import get_recommended_additional_features
            recommended = get_recommended_additional_features()
            included_recommended = [f for f in recommended if f in feature_cols]
            if included_recommended:
                logger.info(f"Included {len(included_recommended)} recommended additional features: {', '.join(included_recommended[:10])}{'...' if len(included_recommended) > 10 else ''}")
        if top_feature_names is not None:
            logger.info(f"Top features for training: {', '.join(feature_cols)}")
    
    X = df_clean[feature_cols].copy()
    time = df_clean['time'].values
    status = df_clean['status'].values
    
    # Remove constant columns (keep sec_dx_* one-hot columns so model always has same feature set for inference)
    from calculator_features import get_sec_dx_one_hot_columns
    sec_dx_cols_keep = set(get_sec_dx_one_hot_columns())
    constant_cols = []
    for col in X.columns:
        if col in sec_dx_cols_keep:
            continue  # never drop one-hot sec_dx_* so dashboard/inference feature set is stable
        unique_vals = X[col].dropna().unique()
        if len(unique_vals) < 2:
            constant_cols.append(col)
    
    if constant_cols:
        logger.info(f"Removing {len(constant_cols)} constant columns (sec_dx_* one-hot kept for stable feature set)")
        X = X.drop(columns=constant_cols)
        feature_cols = [col for col in feature_cols if col not in constant_cols]
    
    # Fill NaN values
    X = X.fillna(0)
    
    # Identify categorical features
    # CatBoost can handle categoricals natively, but XGBoost needs numeric encoding
    # We'll keep native categoricals for CatBoost and create a numeric version for XGBoost
    categorical_cols = []
    for col in X.columns:
        if X[col].dtype == 'object' or X[col].dtype.name == 'category':
            categorical_cols.append(col)
    
    # Store categorical feature indices for CatBoost (using native categoricals)
    cat_feature_indices_final = []
    for i, col in enumerate(X.columns):
        if col in categorical_cols:
            cat_feature_indices_final.append(i)
    
    # Create a copy for XGBoost with numeric-encoded categoricals
    # CatBoost will use the original X with native categoricals
    X_for_xgb = X.copy()
    for col in categorical_cols:
        # Convert to string first (handles NaN), then to categorical codes
        X_for_xgb[col] = pd.Categorical(X[col].astype(str).fillna('')).codes
    
    logger.info(f"Final feature matrix: {X.shape}")
    if categorical_cols:
        logger.info(f"  Identified {len(categorical_cols)} categorical features: {categorical_cols[:5]}{'...' if len(categorical_cols) > 5 else ''}")
        logger.info(f"  CatBoost will use native categoricals (indices: {cat_feature_indices_final[:10]}{'...' if len(cat_feature_indices_final) > 10 else ''})")
        logger.info(f"  XGBoost will use numeric-encoded categoricals")
    logger.info(f"Total features after leakage removal and constant column removal: {len(feature_cols)}")
    
    # Log feature categories for visibility
    derived_features = [f for f in feature_cols if any(x in f.lower() for x in ['combined', '_ratio', 'egfr_', 'bmi_', '_high', '_low', '_bin', '_cat', '_change'])]
    logger.info(f"  - Derived features (combined, ratios, calculated, dichotomous): {len(derived_features)}")
    logger.info(f"  - Original clinical features: {len(feature_cols) - len(derived_features)}")
    
    # Prepare signed time labels for full dataset (for MC CV splits)
    y_all = prepare_survival_labels(time, status)
    
    # Create output directory (with suffix for top / wisotzkey / enhanced / base)
    if use_wisotzkey_vars_only:
        feature_suffix = "_wisotzkey"
    elif top_feature_names is not None:
        feature_suffix = "_top"
    else:
        feature_suffix = "_enhanced" if include_recommended_features else "_base"
    cohort_output_dir = MODELS_DIR / f"{cohort}{feature_suffix}"
    cohort_output_dir.mkdir(parents=True, exist_ok=True)
    mc_cv_output_dir = cohort_output_dir / "mc_cv"
    mc_cv_output_dir.mkdir(parents=True, exist_ok=True)
    
    # ============================================================================
    # IDEMPOTENCY CHECK: Skip training if all outputs already exist (unless --force)
    # ============================================================================
    logger.info("\n" + "="*80)
    logger.info("CHECKING FOR EXISTING OUTPUTS (IDEMPOTENCY CHECK)")
    logger.info("="*80)
    
    if not force and check_training_complete(cohort_output_dir, n_mc_splits):
        logger.info(f"\n✓ All training outputs already complete for {cohort_output_dir.name}")
        logger.info(f"  Skipping model training. Outputs found:")
        logger.info(f"    - MC-CV models: {n_mc_splits} splits with all 3 models")
        logger.info(f"    - Aggregated metrics and feature importances")
        logger.info(f"    - Final models (temporal split)")
        logger.info(f"    - Best model info")
        logger.info(f"\n  To retrain, run without --no-force or delete the output directory: {cohort_output_dir}")
        logger.info("="*80)
        return
    
    if force:
        logger.info("Force re-train: ignoring existing outputs")
    else:
        logger.info(f"Training outputs incomplete or missing. Proceeding with training...")
    logger.info("="*80)
    
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
            X_train=X.iloc[split_indices[i]['train_idx']].copy(),  # Native categoricals for CatBoost
            y_train=y_all[split_indices[i]['train_idx']],
            X_test=X.iloc[split_indices[i]['test_idx']].copy(),  # Native categoricals for CatBoost
            y_test=y_all[split_indices[i]['test_idx']],
            time_test=time[split_indices[i]['test_idx']],
            status_test=status[split_indices[i]['test_idx']],
            feature_names=feature_cols,
            cohort_name=cohort,
            output_dir=mc_cv_output_dir,
            cat_feature_indices=cat_feature_indices_final,
            X_train_xgb=X_for_xgb.iloc[split_indices[i]['train_idx']].copy() if 'X_for_xgb' in locals() else None,  # Numeric-encoded for XGBoost
            X_test_xgb=X_for_xgb.iloc[split_indices[i]['test_idx']].copy() if 'X_for_xgb' in locals() else None  # Numeric-encoded for XGBoost
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
    
    # Collect AUC values for each model
    cb_aucs = [r['catboost_auc'] for r in successful_results if r['catboost_auc'] is not None and not np.isnan(r['catboost_auc'])]
    xgb_aucs = [r['xgboost_auc'] for r in successful_results if r['xgboost_auc'] is not None and not np.isnan(r['xgboost_auc'])]
    xgb_rf_aucs = [r['xgboost_rf_auc'] for r in successful_results if r['xgboost_rf_auc'] is not None and not np.isnan(r['xgboost_rf_auc'])]
    
    # Collect AU-PRC values for each model
    cb_auprcs = [r['catboost_auprc'] for r in successful_results if r['catboost_auprc'] is not None and not np.isnan(r['catboost_auprc'])]
    xgb_auprcs = [r['xgboost_auprc'] for r in successful_results if r['xgboost_auprc'] is not None and not np.isnan(r['xgboost_auprc'])]
    xgb_rf_auprcs = [r['xgboost_rf_auprc'] for r in successful_results if r['xgboost_rf_auprc'] is not None and not np.isnan(r['xgboost_rf_auprc'])]
    
    # Collect Recall values for each model
    cb_recalls = [r['catboost_recall'] for r in successful_results if r['catboost_recall'] is not None and not np.isnan(r['catboost_recall'])]
    xgb_recalls = [r['xgboost_recall'] for r in successful_results if r['xgboost_recall'] is not None and not np.isnan(r['xgboost_recall'])]
    xgb_rf_recalls = [r['xgboost_rf_recall'] for r in successful_results if r['xgboost_rf_recall'] is not None and not np.isnan(r['xgboost_rf_recall'])]
    
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
    
    # Calculate statistics for AUC
    cb_auc_stats = calc_stats(cb_aucs, 'CatBoost')
    xgb_auc_stats = calc_stats(xgb_aucs, 'XGBoost')
    xgb_rf_auc_stats = calc_stats(xgb_rf_aucs, 'XGBoost RF')
    
    # Calculate statistics for AU-PRC
    cb_auprc_stats = calc_stats(cb_auprcs, 'CatBoost')
    xgb_auprc_stats = calc_stats(xgb_auprcs, 'XGBoost')
    xgb_rf_auprc_stats = calc_stats(xgb_rf_auprcs, 'XGBoost RF')
    
    # Calculate statistics for Recall
    cb_recall_stats = calc_stats(cb_recalls, 'CatBoost')
    xgb_recall_stats = calc_stats(xgb_recalls, 'XGBoost')
    xgb_rf_recall_stats = calc_stats(xgb_rf_recalls, 'XGBoost RF')
    
    # Create metrics DataFrame with all metrics
    metrics_df = pd.DataFrame([
        {
            'Model': 'CatBoost',
            'C_Index_Mean': cb_stats['mean'],
            'C_Index_SD': cb_stats['std'],
            'C_Index_CI_Lower': cb_stats['ci_lower'],
            'C_Index_CI_Upper': cb_stats['ci_upper'],
            'AUC_Mean': cb_auc_stats['mean'],
            'AUC_SD': cb_auc_stats['std'],
            'AUC_CI_Lower': cb_auc_stats['ci_lower'],
            'AUC_CI_Upper': cb_auc_stats['ci_upper'],
            'AU_PRC_Mean': cb_auprc_stats['mean'],
            'AU_PRC_SD': cb_auprc_stats['std'],
            'AU_PRC_CI_Lower': cb_auprc_stats['ci_lower'],
            'AU_PRC_CI_Upper': cb_auprc_stats['ci_upper'],
            'Recall_Mean': cb_recall_stats['mean'],
            'Recall_SD': cb_recall_stats['std'],
            'Recall_CI_Lower': cb_recall_stats['ci_lower'],
            'Recall_CI_Upper': cb_recall_stats['ci_upper'],
            'n_splits': cb_stats['n_splits']
        },
        {
            'Model': 'XGBoost',
            'C_Index_Mean': xgb_stats['mean'],
            'C_Index_SD': xgb_stats['std'],
            'C_Index_CI_Lower': xgb_stats['ci_lower'],
            'C_Index_CI_Upper': xgb_stats['ci_upper'],
            'AUC_Mean': xgb_auc_stats['mean'],
            'AUC_SD': xgb_auc_stats['std'],
            'AUC_CI_Lower': xgb_auc_stats['ci_lower'],
            'AUC_CI_Upper': xgb_auc_stats['ci_upper'],
            'AU_PRC_Mean': xgb_auprc_stats['mean'],
            'AU_PRC_SD': xgb_auprc_stats['std'],
            'AU_PRC_CI_Lower': xgb_auprc_stats['ci_lower'],
            'AU_PRC_CI_Upper': xgb_auprc_stats['ci_upper'],
            'Recall_Mean': xgb_recall_stats['mean'],
            'Recall_SD': xgb_recall_stats['std'],
            'Recall_CI_Lower': xgb_recall_stats['ci_lower'],
            'Recall_CI_Upper': xgb_recall_stats['ci_upper'],
            'n_splits': xgb_stats['n_splits']
        },
        {
            'Model': 'XGBoost RF',
            'C_Index_Mean': xgb_rf_stats['mean'],
            'C_Index_SD': xgb_rf_stats['std'],
            'C_Index_CI_Lower': xgb_rf_stats['ci_lower'],
            'C_Index_CI_Upper': xgb_rf_stats['ci_upper'],
            'AUC_Mean': xgb_rf_auc_stats['mean'],
            'AUC_SD': xgb_rf_auc_stats['std'],
            'AUC_CI_Lower': xgb_rf_auc_stats['ci_lower'],
            'AUC_CI_Upper': xgb_rf_auc_stats['ci_upper'],
            'AU_PRC_Mean': xgb_rf_auprc_stats['mean'],
            'AU_PRC_SD': xgb_rf_auprc_stats['std'],
            'AU_PRC_CI_Lower': xgb_rf_auprc_stats['ci_lower'],
            'AU_PRC_CI_Upper': xgb_rf_auprc_stats['ci_upper'],
            'Recall_Mean': xgb_rf_recall_stats['mean'],
            'Recall_SD': xgb_rf_recall_stats['std'],
            'Recall_CI_Lower': xgb_rf_recall_stats['ci_lower'],
            'Recall_CI_Upper': xgb_rf_recall_stats['ci_upper'],
            'n_splits': xgb_rf_stats['n_splits']
        }
    ])
    
    # Save metrics
    metrics_path = cohort_output_dir / "mc_cv_model_metrics.csv"
    metrics_df.to_csv(metrics_path, index=False)
    logger.info(f"Saved MC-CV metrics to: {metrics_path}")
    
    # Print summary (same order for all models: C-index, Recall, AUC, AU-PRC)
    logger.info("\nMC-CV Model Performance Summary (C-index, Recall, AUC, AU-PRC):")
    for _, row in metrics_df.iterrows():
        logger.info(f"  {row['Model']:15s}:")
        logger.info(f"    C-index = {row['C_Index_Mean']:.6f} ± {row['C_Index_SD']:.6f} "
                   f"(95% CI: {row['C_Index_CI_Lower']:.6f} - {row['C_Index_CI_Upper']:.6f})")
        _r = row.get('Recall_Mean', np.nan)
        if not np.isnan(_r):
            logger.info(f"    Recall  = {_r:.6f} ± {row.get('Recall_SD', np.nan):.6f} "
                       f"(95% CI: {row.get('Recall_CI_Lower', np.nan):.6f} - {row.get('Recall_CI_Upper', np.nan):.6f})")
        _a = row.get('AUC_Mean', np.nan)
        if not np.isnan(_a):
            logger.info(f"    AUC     = {_a:.6f} ± {row.get('AUC_SD', np.nan):.6f} "
                       f"(95% CI: {row.get('AUC_CI_Lower', np.nan):.6f} - {row.get('AUC_CI_Upper', np.nan):.6f})")
        _p = row.get('AU_PRC_Mean', np.nan)
        if not np.isnan(_p):
            logger.info(f"    AU-PRC  = {_p:.6f} ± {row.get('AU_PRC_SD', np.nan):.6f} "
                       f"(95% CI: {row.get('AU_PRC_CI_Lower', np.nan):.6f} - {row.get('AU_PRC_CI_Upper', np.nan):.6f})")
        logger.info(f"    [{int(row['n_splits'])} splits]")
    
    # Determine best model: first by C-index, then by AU-PRC as tiebreaker
    max_c_index = metrics_df['C_Index_Mean'].max()
    candidates = metrics_df[metrics_df['C_Index_Mean'] == max_c_index].copy()
    
    if len(candidates) > 1:
        # Multiple models tied for best C-index - use AU-PRC as tiebreaker
        logger.info(f"\nMultiple models tied for best C-index ({max_c_index:.6f}). Using AU-PRC as tiebreaker...")
        # Filter out NaN AU-PRC values
        candidates_with_auprc = candidates[candidates['AU_PRC_Mean'].notna()]
        if len(candidates_with_auprc) > 0:
            best_model_row = candidates_with_auprc.loc[candidates_with_auprc['AU_PRC_Mean'].idxmax()]
            logger.info(f"  Selected {best_model_row['Model']} based on AU-PRC: {best_model_row['AU_PRC_Mean']:.6f}")
        else:
            # No AU-PRC available - use first candidate (arbitrary tiebreak)
            best_model_row = candidates.iloc[0]
            logger.info(f"  No AU-PRC available. Selected {best_model_row['Model']} (first candidate)")
    else:
        # Single best model by C-index
        best_model_row = candidates.iloc[0]
    
    best_model_name = best_model_row['Model']
    best_c_index = best_model_row['C_Index_Mean']
    best_auprc = best_model_row.get('AU_PRC_Mean', np.nan)
    
    if not np.isnan(best_auprc):
        logger.info(f"\nBest Model: {best_model_name} (Mean C-index: {best_c_index:.6f}, Mean AU-PRC: {best_auprc:.6f})")
    else:
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
    
    # Combine all models for visualization (long table: one row per feature per model)
    if aggregated_importances:
        all_importance_df = pd.concat(aggregated_importances.values(), ignore_index=True)
        all_importance_path = cohort_output_dir / "mc_cv_all_models_feature_importance.csv"
        all_importance_df.to_csv(all_importance_path, index=False)
        logger.info(f"  Saved combined feature importance to: {all_importance_path}")
    
    # Aggregate feature importance across all models (one row per feature: mean ± std over CatBoost, XGBoost, XGBoost RF)
    aggregated_all_models_df = None
    if aggregated_importances:
        # Each model has feature, importance_mean, importance_std, importance_count, Model
        rows = []
        all_features = set()
        for agg_df in aggregated_importances.values():
            all_features.update(agg_df['feature'].tolist())
        for feat in all_features:
            means = []
            for model_name, agg_df in aggregated_importances.items():
                row = agg_df[agg_df['feature'] == feat]
                if len(row) > 0:
                    means.append(row['importance_mean'].iloc[0])
            if means:
                rows.append({
                    'feature': feat,
                    'importance_mean': float(np.mean(means)),
                    'importance_std': float(np.std(means)) if len(means) > 1 else 0.0,
                    'n_models': len(means),
                })
        if rows:
            aggregated_all_models_df = pd.DataFrame(rows).sort_values('importance_mean', ascending=False)
            agg_path = cohort_output_dir / "mc_cv_aggregated_feature_importance.csv"
            aggregated_all_models_df.to_csv(agg_path, index=False)
            logger.info(f"  Saved aggregated feature importance (all models) to: {agg_path}")
    
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
        
        # 1. C-index Comparison
        if 'C_Index_Mean' in metrics_df.columns and not metrics_df['C_Index_Mean'].isna().all():
            try:
                logger.info("Creating C-index comparison plot...")
                valid_cindex = metrics_df.dropna(subset=['C_Index_Mean'])
                if len(valid_cindex) > 0:
                    fig, ax = plt.subplots(figsize=(8, 4))
                    yerr = valid_cindex['C_Index_SD'] if 'C_Index_SD' in valid_cindex.columns else None
                    ax.bar(valid_cindex['Model'], valid_cindex['C_Index_Mean'], 
                           yerr=yerr, capsize=5, alpha=0.7)
                    ax.set_ylabel('C-index (Mean ± SD)')
                    ax.set_xlabel('Model')
                    ax.set_title(f'Model Performance Comparison - C-index ({cohort})')
                    ax.grid(axis='y', alpha=0.3)
                    plt.tight_layout()
                    cindex_plot_path = plots_dir / "cindex_comparison.png"
                    plt.savefig(cindex_plot_path, dpi=300, bbox_inches='tight')
                    plt.close()
                    logger.info(f"  Saved C-index comparison to: {cindex_plot_path}")
                else:
                    logger.warning("No valid C-index data for plotting")
            except Exception as e:
                logger.warning(f"Error creating C-index comparison plot: {e}", exc_info=True)
        else:
            logger.warning("C_Index_Mean column not found or all NaN, skipping C-index plot")
        
        # 2. AUC Comparison
        if 'AUC_Mean' in metrics_df.columns and not metrics_df['AUC_Mean'].isna().all():
            try:
                logger.info("Creating AUC comparison plot...")
                valid_auc = metrics_df.dropna(subset=['AUC_Mean'])
                if len(valid_auc) > 0:
                    fig, ax = plt.subplots(figsize=(8, 4))
                    yerr = valid_auc['AUC_SD'] if 'AUC_SD' in valid_auc.columns else None
                    ax.bar(valid_auc['Model'], valid_auc['AUC_Mean'], 
                           yerr=yerr, capsize=5, alpha=0.7, color='green')
                    ax.set_ylabel('AUC (Mean ± SD)')
                    ax.set_xlabel('Model')
                    ax.set_title(f'Model Performance Comparison - AUC ({cohort})')
                    ax.grid(axis='y', alpha=0.3)
                    plt.tight_layout()
                    auc_plot_path = plots_dir / "auc_comparison.png"
                    plt.savefig(auc_plot_path, dpi=300, bbox_inches='tight')
                    plt.close()
                    logger.info(f"  Saved AUC comparison to: {auc_plot_path}")
                else:
                    logger.warning("No valid AUC data for plotting")
            except Exception as e:
                logger.warning(f"Error creating AUC comparison plot: {e}", exc_info=True)
        else:
            logger.warning("AUC_Mean column not found or all NaN, skipping AUC plot")
        
        # 3. AU-PRC Comparison
        if 'AU_PRC_Mean' in metrics_df.columns and not metrics_df['AU_PRC_Mean'].isna().all():
            try:
                logger.info("Creating AU-PRC comparison plot...")
                valid_auprc = metrics_df.dropna(subset=['AU_PRC_Mean'])
                if len(valid_auprc) > 0:
                    fig, ax = plt.subplots(figsize=(8, 4))
                    yerr = valid_auprc['AU_PRC_SD'] if 'AU_PRC_SD' in valid_auprc.columns else None
                    ax.bar(valid_auprc['Model'], valid_auprc['AU_PRC_Mean'], 
                           yerr=yerr, capsize=5, alpha=0.7, color='orange')
                    ax.set_ylabel('AU-PRC (Mean ± SD)')
                    ax.set_xlabel('Model')
                    ax.set_title(f'Model Performance Comparison - AU-PRC ({cohort})')
                    ax.grid(axis='y', alpha=0.3)
                    plt.tight_layout()
                    auprc_plot_path = plots_dir / "auprc_comparison.png"
                    plt.savefig(auprc_plot_path, dpi=300, bbox_inches='tight')
                    plt.close()
                    logger.info(f"  Saved AU-PRC comparison to: {auprc_plot_path}")
                else:
                    logger.warning("No valid AU-PRC data for plotting")
            except Exception as e:
                logger.warning(f"Error creating AU-PRC comparison plot: {e}", exc_info=True)
        else:
            logger.warning("AU_PRC_Mean column not found or all NaN, skipping AU-PRC plot")
        
        # 4. Recall Comparison
        if 'Recall_Mean' in metrics_df.columns and not metrics_df['Recall_Mean'].isna().all():
            try:
                logger.info("Creating Recall comparison plot...")
                valid_recall = metrics_df.dropna(subset=['Recall_Mean'])
                if len(valid_recall) > 0:
                    fig, ax = plt.subplots(figsize=(8, 4))
                    yerr = valid_recall['Recall_SD'] if 'Recall_SD' in valid_recall.columns else None
                    ax.bar(valid_recall['Model'], valid_recall['Recall_Mean'], 
                           yerr=yerr, capsize=5, alpha=0.7, color='blue')
                    ax.set_ylabel('Recall (Mean ± SD)')
                    ax.set_xlabel('Model')
                    ax.set_title(f'Model Performance Comparison - Recall ({cohort})')
                    ax.grid(axis='y', alpha=0.3)
                    plt.tight_layout()
                    recall_plot_path = plots_dir / "recall_comparison.png"
                    plt.savefig(recall_plot_path, dpi=300, bbox_inches='tight')
                    plt.close()
                    logger.info(f"  Saved Recall comparison to: {recall_plot_path}")
                else:
                    logger.warning("No valid Recall data for plotting")
            except Exception as e:
                logger.warning(f"Error creating Recall comparison plot: {e}", exc_info=True)
        else:
            logger.warning("Recall_Mean column not found or all NaN, skipping Recall plot")
        
        # 5. Combined Metrics Heatmap (same order for all models: C-Index, Recall, AUC, AU-PRC)
        logger.info("Creating combined metrics heatmap...")
        try:
            available_metrics = [m for m in STANDARD_METRICS if m in metrics_df.columns and not metrics_df[m].isna().all()]
            
            if available_metrics and len(available_metrics) > 0:
                # Verify metrics_df has the required columns
                if 'Model' not in metrics_df.columns:
                    logger.warning("metrics_df missing 'Model' column, skipping heatmap")
                else:
                    heatmap_data = metrics_df.set_index('Model')[available_metrics].T
                    # Use display names for y-axis (C-index, Recall, AUC, AU-PRC)
                    name_map = dict(zip(STANDARD_METRICS, STANDARD_METRICS_DISPLAY, strict=True))
                    heatmap_data = heatmap_data.rename(index=name_map)
                    # Normalize each metric to [0, 1] for visualization
                    # After transposing, rows are metrics and columns are models
                    heatmap_data_norm = heatmap_data.copy()
                    for metric in heatmap_data.index:  # Iterate over row index (metrics)
                        row = heatmap_data.loc[metric]
                        if row.max() > row.min():
                            heatmap_data_norm.loc[metric] = (row - row.min()) / (row.max() - row.min())
                        else:
                            heatmap_data_norm.loc[metric] = 0.5
            
                    fig, ax = plt.subplots(figsize=(8, 6))
                    sns.heatmap(
                        heatmap_data_norm,
                        annot=heatmap_data,  # Show actual values
                        fmt='.4f',
                        cmap='YlOrRd',
                        cbar_kws={'label': 'Normalized Value'},
                        ax=ax,
                        linewidths=0.5
                    )
                    ax.set_title(f'Model Performance Metrics Heatmap ({cohort})', fontsize=14, fontweight='bold')
                    ax.set_xlabel('Model', fontsize=12)
                    ax.set_ylabel('Metric', fontsize=12)
                    plt.tight_layout()
                    metrics_heatmap_path = plots_dir / "model_metrics_heatmap.png"
                    plt.savefig(metrics_heatmap_path, dpi=300, bbox_inches='tight')
                    plt.close()
                    logger.info(f"  Saved metrics heatmap to: {metrics_heatmap_path}")
            else:
                logger.warning(f"No available metrics for heatmap. Expected columns: {STANDARD_METRICS}, found: {list(metrics_df.columns)}")
        except Exception as e:
            logger.warning(f"Error creating metrics heatmap: {e}", exc_info=True)
        
        # 6. Feature Importance Heatmap (if we have aggregated importances)
        if aggregated_importances and 'all_importance_df' in locals() and len(all_importance_df) > 0:
            try:
                logger.info("Creating feature importance heatmap...")
                
                # Get top N features (e.g., top 30)
                top_n = 30
                if 'importance_mean' in all_importance_df.columns:
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
                    else:
                        logger.warning("No heatmap data generated")
                else:
                    logger.warning("importance_mean column not found in all_importance_df")
            except Exception as e:
                logger.warning(f"Error creating feature importance heatmap: {e}", exc_info=True)
        else:
            logger.warning("No aggregated importances available, skipping feature importance heatmap")
        
        # 7. Aggregated feature importance (all models) bar chart
        if aggregated_all_models_df is not None and len(aggregated_all_models_df) > 0:
            try:
                logger.info("Creating aggregated feature importance bar chart...")
                top_n = 25
                plot_df = aggregated_all_models_df.head(top_n)
                fig, ax = plt.subplots(figsize=(10, max(6, len(plot_df) * 0.25)))
                yerr = plot_df['importance_std'] if 'importance_std' in plot_df.columns else None
                ax.barh(range(len(plot_df)), plot_df['importance_mean'], xerr=yerr, capsize=2, alpha=0.8)
                ax.set_yticks(range(len(plot_df)))
                ax.set_yticklabels(plot_df['feature'], fontsize=9)
                ax.invert_yaxis()
                ax.set_xlabel('Mean importance (across CatBoost, XGBoost, XGBoost RF)', fontsize=11)
                ax.set_title(f'Aggregated Feature Importance - All Models ({cohort}, Top {top_n})', fontsize=14, fontweight='bold')
                plt.tight_layout()
                agg_plot_path = plots_dir / "aggregated_feature_importance.png"
                plt.savefig(agg_plot_path, dpi=300, bbox_inches='tight')
                plt.close()
                logger.info(f"  Saved aggregated feature importance plot to: {agg_plot_path}")
            except Exception as e:
                logger.warning(f"Error creating aggregated feature importance plot: {e}", exc_info=True)

    except ImportError:
        logger.warning("Matplotlib/Seaborn not available. Skipping visualizations.")
        logger.warning("  Install with: pip install matplotlib seaborn")
    except Exception as e:
        logger.warning(f"Error in visualization section: {e}", exc_info=True)
        # Continue execution - visualizations are optional
    
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
        
        X_train_final = X[train_mask].copy()  # Native categoricals for CatBoost
        X_test_final = X[test_mask].copy()  # Native categoricals for CatBoost
        X_train_final_xgb = X_for_xgb[train_mask].copy() if 'X_for_xgb' in locals() else X_train_final  # Numeric-encoded for XGBoost
        X_test_final_xgb = X_for_xgb[test_mask].copy() if 'X_for_xgb' in locals() else X_test_final  # Numeric-encoded for XGBoost
        time_train_final = time[train_mask]
        time_test_final = time[test_mask]
        status_train_final = status[train_mask]
        status_test_final = status[test_mask]
    else:
        logger.warning("txpl_year not found, using full dataset")
        X_train_final = X  # Native categoricals for CatBoost
        X_test_final = X  # Native categoricals for CatBoost
        X_train_final_xgb = X_for_xgb if 'X_for_xgb' in locals() else X  # Numeric-encoded for XGBoost
        X_test_final_xgb = X_for_xgb if 'X_for_xgb' in locals() else X  # Numeric-encoded for XGBoost
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
            X_train=X_train_final_xgb,  # Use numeric-encoded version for XGBoost
            y_train=y_train_final,
            X_test=X_test_final_xgb,  # Use numeric-encoded version for XGBoost
            y_test=y_test_final,
            time_test=time_test_final,
            status_test=status_test_final,
            feature_names=feature_cols,
            cohort_name=cohort,
            output_dir=cohort_output_dir
        )
    else:  # XGBoost RF
        final_model, final_cindex = train_xgboost_rf_survival(
            X_train=X_train_final_xgb,  # Use numeric-encoded version for XGBoost RF
            y_train=y_train_final,
            X_test=X_test_final_xgb,  # Use numeric-encoded version for XGBoost RF
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
        X_train=X_train_final_xgb,  # Use numeric-encoded version for XGBoost
        y_train=y_train_final,
        X_test=X_test_final_xgb,  # Use numeric-encoded version for XGBoost
        y_test=y_test_final,
        time_test=time_test_final,
        status_test=status_test_final,
        feature_names=feature_cols,
        cohort_name=cohort,
        output_dir=cohort_output_dir
    )
    
    xgb_rf_model, xgb_rf_cindex = train_xgboost_rf_survival(
        X_train=X_train_final_xgb,  # Use numeric-encoded version for XGBoost RF
        y_train=y_train_final,
        X_test=X_test_final_xgb,  # Use numeric-encoded version for XGBoost RF
        y_test=y_test_final,
        time_test=time_test_final,
        status_test=status_test_final,
        feature_names=feature_cols,
        cohort_name=cohort,
        output_dir=cohort_output_dir
    )
    
    # Save best model info (same four metrics for all models: C-Index, Recall, AUC, AU-PRC)
    best_model_path = cohort_output_dir / "best_model.txt"
    with open(best_model_path, 'w') as f:
        f.write(f"Best Model (MC-CV): {best_model_name}\n")
        f.write(f"Selection Criteria: C-index (primary), AU-PRC (tiebreaker)\n")
        f.write(f"Standard metrics (all models): C-index, Recall, AUC, AU-PRC\n")
        f.write(f"\nBest model MC-CV metrics:\n")
        f.write(f"  C-index: {best_c_index:.6f} (95% CI: [{best_model_row['C_Index_CI_Lower']:.6f}, {best_model_row['C_Index_CI_Upper']:.6f}], SD: {best_model_row['C_Index_SD']:.6f})\n")
        _v = best_model_row.get('Recall_Mean', np.nan)
        f.write(f"  Recall:  {_v:.6f} ± {best_model_row.get('Recall_SD', np.nan):.6f}\n" if not np.isnan(_v) else "  Recall:  N/A\n")
        _v = best_model_row.get('AUC_Mean', np.nan)
        f.write(f"  AUC:     {_v:.6f} ± {best_model_row.get('AUC_SD', np.nan):.6f}\n" if not np.isnan(_v) else "  AUC:     N/A\n")
        _v = best_model_row.get('AU_PRC_Mean', np.nan)
        f.write(f"  AU-PRC:  {_v:.6f} ± {best_model_row.get('AU_PRC_SD', np.nan):.6f}\n" if not np.isnan(_v) else "  AU-PRC:  N/A\n")
        f.write(f"  n_splits: {int(best_model_row['n_splits'])}\n")
        f.write(f"\nTemporal Split Results:\n")
        f.write(f"  CatBoost: {cb_cindex:.6f}\n")
        f.write(f"  XGBoost: {xgb_cindex:.6f}\n")
        f.write(f"  XGBoost RF: {xgb_rf_cindex:.6f}\n")
        f.write(f"\nMC-CV Model Performance (all models) - C-index, Recall, AUC, AU-PRC:\n")
        for _, row in metrics_df.iterrows():
            f.write(f"  {row['Model']}:\n")
            f.write(f"    C-index: {row['C_Index_Mean']:.6f} ± {row['C_Index_SD']:.6f} (95% CI: {row['C_Index_CI_Lower']:.6f} - {row['C_Index_CI_Upper']:.6f})\n")
            _r = row.get('Recall_Mean', np.nan)
            f.write(f"    Recall:  {_r:.6f} ± {row.get('Recall_SD', np.nan):.6f}\n" if not np.isnan(_r) else "    Recall:  N/A\n")
            _a = row.get('AUC_Mean', np.nan)
            f.write(f"    AUC:     {_a:.6f} ± {row.get('AUC_SD', np.nan):.6f}\n" if not np.isnan(_a) else "    AUC:     N/A\n")
            _p = row.get('AU_PRC_Mean', np.nan)
            f.write(f"    AU-PRC:  {_p:.6f} ± {row.get('AU_PRC_SD', np.nan):.6f}\n" if not np.isnan(_p) else "    AU-PRC:  N/A\n")
            f.write(f"    [{int(row['n_splits'])} splits]\n")
    
    logger.info(f"\n{'='*80}")
    logger.info("TRAINING COMPLETE")
    logger.info(f"{'='*80}")
    logger.info(f"Best Model (MC-CV): {best_model_name}")
    logger.info(f"Selection Criteria: C-index (primary), AU-PRC (tiebreaker)")
    logger.info(f"MC-CV Mean C-index: {best_c_index:.6f}")
    if not np.isnan(best_auprc):
        logger.info(f"MC-CV Mean AU-PRC: {best_auprc:.6f}")
    logger.info(f"\nAll outputs saved to: {cohort_output_dir}")
    logger.info(f"  - MC-CV metrics: {metrics_path}")
    logger.info(f"  - Feature importances: {cohort_output_dir / 'mc_cv_*_feature_importance.csv'} (per-model + mc_cv_aggregated_feature_importance.csv)")
    logger.info(f"  - Visualizations: {plots_dir}")
    logger.info(f"  - Final models: {cohort_output_dir}")


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Train Python survival models")
    parser.add_argument("--cohort", type=str, default="Combined",
                       choices=["Combined", "CHD", "Myocardio"],
                       help="Cohort to train (one model per cohort; with --top_features_only output is e.g. CHD_top, Combined_top)")
    parser.add_argument("--n_mc_splits", type=int, default=25,
                       help="Number of Monte Carlo cross-validation splits (default: 25)")
    parser.add_argument("--train_prop", type=float, default=0.8,
                       help="Training proportion for MC-CV splits (default: 0.8)")
    parser.add_argument("--n_jobs", type=int, default=1,
                       help="Number of parallel jobs for MC-CV (default: 1)")
    parser.add_argument("--include_recommended", action="store_true",
                       help="Include recommended additional features (BNP, CRP, sec_dx/ter_dx, etc.)")
    parser.add_argument("--top_features_only", action="store_true",
                       help="Train only on top causal/importance features from SHAP/FFA (output: {cohort}_top)")
    parser.add_argument("--wisotzkey_vars_only", action="store_true",
                       help="Train on Wisotzkey et al. variable set only (output: {cohort}_wisotzkey; compare with _top models)")
    parser.add_argument("--top_features_file", type=str, default=None,
                       help="CSV/JSON file with 'feature' or 'variable' column for top features (used with --top_features_only; default: built-in list)")
    parser.add_argument("--force", action="store_true", default=True,
                       help="Re-run training even when outputs exist (default: True)")
    parser.add_argument("--no-force", action="store_true", dest="no_force",
                       help="Skip training if outputs already exist (idempotent)")
    
    args = parser.parse_args()
    if getattr(args, "no_force", False):
        args.force = False
    
    # Allow force via environment (e.g. TRAIN_FORCE=1 for scripts/CI)
    import os
    if os.environ.get("TRAIN_FORCE", "").strip().lower() in ("1", "true", "yes"):
        args.force = True
        logger.info("Force re-train enabled via TRAIN_FORCE")
    
    top_feature_names = None
    if args.top_features_only:
        if args.top_features_file and Path(args.top_features_file).exists():
            p = Path(args.top_features_file)
            if p.suffix.lower() == ".csv":
                top_df = pd.read_csv(p)
                col = "feature" if "feature" in top_df.columns else "variable"
                if col not in top_df.columns and len(top_df.columns) > 0:
                    col = top_df.columns[0]
                top_feature_names = top_df[col].astype(str).str.strip().tolist()
            else:
                with open(p, "r") as f:
                    data = json.load(f)
                top_feature_names = data if isinstance(data, list) else data.get("features", data.get("feature", []))
            logger.info(f"Loaded {len(top_feature_names)} top features from {args.top_features_file}")
        else:
            from top_causal_features import get_top_causal_features
            top_feature_names = get_top_causal_features()
            logger.info(f"Using built-in top causal features: {len(top_feature_names)} features")

    feature_set_name = "top causal/importance features only" if top_feature_names else ("enhanced (with recommended features)" if args.include_recommended else "base calculator")
    logger.info(f"\n{'='*80}")
    logger.info(f"Training with {feature_set_name} feature set")
    logger.info(f"{'='*80}")
    
    if args.wisotzkey_vars_only:
        logger.info("Using Wisotzkey et al. variable set (wisotzkey_data.WISOTZKEY_FEATURES)")
    train_models_for_cohort(
        cohort=args.cohort,
        n_mc_splits=args.n_mc_splits,
        train_prop=args.train_prop,
        n_jobs=args.n_jobs,
        include_recommended_features=args.include_recommended,
        top_feature_names=top_feature_names,
        use_wisotzkey_vars_only=args.wisotzkey_vars_only,
        force=args.force
    )
