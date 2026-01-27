"""
Calculator Feature Definitions

This module defines the exact list of features that should be used for the risk calculator model.
Only features that can be derived from calculator user inputs should be included.
"""

from typing import List, Set


def get_calculator_base_features() -> List[str]:
    """
    Get base features that users can provide directly in the calculator.
    
    These are the raw inputs that users enter in the calculator UI.
    """
    return [
        # Primary diagnosis
        "primary_etiology",
        
        # Demographics
        "age_txpl",
        "age_listing",
        "weight_txpl",
        "height_txpl",
        "weight_listing",
        "height_listing",
        
        # Clinical history
        "hxsurg",
        "hxdysdia",
        "hxfonlvr",
        
        # Cardiac support devices (at transplant)
        "txecmo",
        "txvad",
        "txvent",
        "slecmo",
        "slvad",
        "slvent",
        "ltxtrach",
        "hxtrach",
        
        # Renal function
        "txcreat_r",
        "lcreat_r",
        "txbun_r",
        "lbun_r",
        
        # Liver function
        "txalt",
        "lsalt",
        "txast",
        "lsast",
        "txbili_d_r",
        "lsbili_d_r",
        "txbili_t_r",
        "lsbili_t_r",
        
        # Nutrition
        "txsa_r",
        "lssab_r",
        "txtp_r",
        "lstp_r",
        
        # Immunology
        "txfcpra",
        "lsfcpra",
        
        # Donor characteristics
        "donor_age",
        "donor_weight",
        "weight_donor",
        "donor_height",
        "height_donor",
        "donisch",
        
        # CHD subtypes (for chd_lat composite)
        "chd_dex",
        "chd_si",
        "chd_heter",
        "chd_iivc",
        "chd_bivc",
        "chd_lsvc",
        "chd_raa",
        "chd_avd",
    ]


def get_calculator_derived_features() -> List[str]:
    """
    Get derived features that are calculated from base features.
    
    These are automatically created during feature engineering.
    """
    return [
        # Combined support variables
        "ecmo_combined",
        "vad_combined",
        "vent_combined",
        
        # Calculated variables
        "egfr_tx",
        "egfr_listing",
        "bmi_txpl",
        "age_txpl_months",
        
        # eGFR categories
        "egfr_tx_cat",
        "egfr_listing_cat",
        
        # Dichotomous variables
        "txbili_t_r_high",
        "txbun_r_high",
        "txsa_r_low",
        "txalt_high",
        "hxfonlvr_bin",
        "hxdysdia_bin",
        
        # Ratios
        "donor_weight_ratio",
        "donor_size_ratio",
        
        # Composite variables
        "chd_lat",
        
        # Change variables
        "egfr_change",
    ]


def get_all_calculator_features() -> Set[str]:
    """
    Get all calculator features (base + derived).
    
    Returns:
        Set of all feature names that should be used for calculator model training.
    """
    base = get_calculator_base_features()
    derived = get_calculator_derived_features()
    return set(base + derived)


def filter_to_calculator_features(df, feature_cols: List[str]) -> List[str]:
    """
    Filter feature columns to only include calculator features.
    
    Args:
        df: DataFrame (for reference, not used currently)
        feature_cols: List of all available feature columns
        
    Returns:
        Filtered list of feature columns that are calculator features
    """
    calculator_features = get_all_calculator_features()
    
    # Filter to only calculator features (case-insensitive)
    calculator_features_lower = {f.lower() for f in calculator_features}
    filtered = [
        col for col in feature_cols 
        if col.lower() in calculator_features_lower
    ]
    
    return filtered
