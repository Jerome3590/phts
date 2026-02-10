"""
Calculator Feature Definitions

This module defines the exact list of features that should be used for the risk calculator model.
Only features that can be derived from calculator user inputs should be included.
sec_dx is one-hot encoded in prepare_calculator_features into sec_dx_<level> columns.

End-to-end sec_dx mapping (all use same SEC_DX_LEVELS and column naming: sec_dx_{label with / and space -> _}):
  - Dashboard: user selects label (e.g. "Dilated") -> sends sec_dx: "Dilated" to API.
  - Lambda: prepare_features_for_inference converts sec_dx -> sec_dx_Dilated=1, others=0.
  - Training: top_causal_features "sec_dx" expanded via get_sec_dx_one_hot_columns(); data from prepare_calculator_features.
  - SHAP/FFA/results: feature importance, SHAP values, and FFA rules use same sec_dx_* column names.
"""

from typing import List, Set

# Single source of truth for sec_dx one-hot levels (train, test, SHAP/FFA, Lambda must match).
# Empty, None dropped; Other kept.
SEC_DX_LEVELS = [
    "ARVD/C", "Dilated", "Hypertrophic", "MIXED", "Other", "Restrictive", "Unknown"
]


def get_sec_dx_one_hot_columns() -> List[str]:
    """Column names for one-hot encoded sec_dx (must match run_shap_ffa_workflow._sec_dx_safe_col)."""
    return [
        f"sec_dx_{label.replace('/', '_').replace(' ', '_').strip()}"
        for label in SEC_DX_LEVELS
    ]


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
        # Note: lspalb_r moved to recommended features for consistency
        
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


def get_recommended_additional_features() -> List[str]:
    """
    Get recommended additional features that could improve model performance.
    
    These are calculator-accessible features that appear in previous model trees
    and have strong evidence of importance.
    """
    return [
        # BNP (Brain Natriuretic Peptide) - Cardiac biomarker
        "txbnp",
        "txpbnp_r",
        "lbnp",
        "lspbnp_r",
        
        # CRP (C-Reactive Protein) - Inflammatory marker
        "txcrp_r",
        "lcrp_r",
        
        # Secondary diagnosis - One-hot encoded (sec_dx_Dilated, sec_dx_Empty, ...)
        *get_sec_dx_one_hot_columns(),
        # Tertiary diagnosis - Comorbidity indicator
        "ter_dx",
        
        # Pre-albumin at listing (completeness - we have txpalb_r)
        "lspalb_r",
        
        # Lipid panel - Metabolic health indicator
        "txchol_r",
        "txtg_r",
        "txldl_r",
        "txhdl_r",
        "txvldl_r",
        
        # Oxygen saturation - Respiratory function
        "txbaosat",
        "txsvcsat",
        "lsbaosat",
        "lssvcsat",
    ]


def get_all_calculator_features(include_recommended: bool = False) -> Set[str]:
    """
    Get all calculator features (base + derived, optionally + recommended).
    
    Args:
        include_recommended: If True, include recommended additional features
        
    Returns:
        Set of all feature names that should be used for calculator model training.
    """
    base = get_calculator_base_features()
    derived = get_calculator_derived_features()
    features = set(base + derived)
    
    if include_recommended:
        recommended = get_recommended_additional_features()
        features.update(recommended)
    
    return features


def filter_to_calculator_features(df, feature_cols: List[str], include_recommended: bool = False) -> List[str]:
    """
    Filter feature columns to only include calculator features.
    
    Calculator features are those that:
    1. Can be provided directly by users in the calculator UI, OR
    2. Can be derived from user inputs (e.g., eGFR from height/creatinine)
    
    Args:
        df: DataFrame (for reference, not used currently)
        feature_cols: List of all available feature columns
        include_recommended: If True, include recommended additional features
        
    Returns:
        Filtered list of feature columns that are calculator features
    """
    calculator_features = get_all_calculator_features(include_recommended=include_recommended)
    
    # Filter to only calculator features (case-insensitive)
    calculator_features_lower = {f.lower() for f in calculator_features}
    filtered = [
        col for col in feature_cols 
        if col.lower() in calculator_features_lower
    ]
    
    # Also include any CHD subtype features (chd_* pattern) as they may be calculator inputs
    chd_features = [col for col in feature_cols if col.lower().startswith('chd_')]
    for chd_feat in chd_features:
        if chd_feat.lower() not in [f.lower() for f in filtered]:
            filtered.append(chd_feat)
    # Include sec_dx one-hot columns (sec_dx_* from prepare_calculator_features)
    sec_dx_one_hot = [col for col in feature_cols if col.lower().startswith('sec_dx_')]
    for col in sec_dx_one_hot:
        if col not in filtered:
            filtered.append(col)
    return filtered
