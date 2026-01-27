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
        "txpalb_r",
        "lspalb_r",
        
        # Immunology
        "txfcpra",
        "lsfcpra",
        "lsfprab",
        "lsfprat",
        
        # Donor characteristics
        "donor_age",
        "donor_weight",
        "weight_donor",
        "donor_height",
        "height_donor",
        "donisch",
        
        # CHD subtypes (for chd_lat composite and individual CHD features)
        # These are used to create chd_lat composite and may be used individually
        "chd_dex",
        "chd_si",
        "chd_heter",
        "chd_iivc",
        "chd_bivc",
        "chd_lsvc",
        "chd_raa",
        "chd_avd",
        # Additional CHD subtypes that may be calculator inputs
        "chd_hlh",
        "chd_hrh",
        "chd_vsd",
        "chd_ahih",
        "chd_avsep",
        "chd_ctga",
        "chd_anom",
        "chd_dilv",
        "chd_ebst",
        "chd_lvotoas",
        "chd_mstn",
        "chd_pa",
        "chd_patr",
        "chd_tapvr",
        "chd_papvr",
        "chd_tof",
        "chd_tga",
        "chd_triat",
        "chd_tart",
        "chd_unk",
        "chd_aspl",
        "chd_pspl",
        "chd_sv",
        "chd_patrd",
        "chd_alcapa",
        "chd_aa",
        "chd_ar",
        "chd_dolv",
        "chd_hb",
        "chd_mart",
        "chd_ma",
        "chd_mr",
        "chd_ps",
        "chd_shone",
        "chd_tr",
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
    
    Calculator features are those that:
    1. Can be provided directly by users in the calculator UI, OR
    2. Can be derived from user inputs (e.g., eGFR from height/creatinine)
    
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
    
    # Also include any CHD subtype features (chd_* pattern) as they may be calculator inputs
    # This ensures we don't miss any CHD subtypes that users can select
    chd_features = [col for col in feature_cols if col.lower().startswith('chd_')]
    for chd_feat in chd_features:
        if chd_feat.lower() not in [f.lower() for f in filtered]:
            filtered.append(chd_feat)
    
    return filtered
