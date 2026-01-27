"""
Environment utilities for model training.
Functions for getting environment-specific configuration.
"""

import os


def get_xgb_cpu_nthread():
    """
    Get number of CPU threads for XGBoost.
    
    Returns:
        int: Number of threads to use. -1 means use all available threads.
        Can be overridden by XGBOOST_NTHREAD environment variable.
    """
    return int(os.environ.get('XGBOOST_NTHREAD', -1))
