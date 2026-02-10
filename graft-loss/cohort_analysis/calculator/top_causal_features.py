"""
Top features from SHAP/FFA causal importance (final workflow).

Used to train the single model (Combined_top) on only these features.
Limited to features with demonstrated high importance or high causality:
- Top 10 by average importance: sec_dx, donor_age, txalt, lbun_r, txbun_r,
  egfr_change, chd_sv, donor_size_ratio, hxsurg, lsbaosat
- Next five: bmi_txpl, lstp_r, egfr_tx, donor_weight_ratio, txsa_r
Expand only when new SHAP/FFA runs provide a clear ranked list for additional features.

Note: "sec_dx" is expanded at train time to one-hot columns (sec_dx_ARVD/C, sec_dx_Dilated, ...)
via get_sec_dx_one_hot_columns() so the model matches prepare_calculator_features and the dashboard.
"""

from typing import List

# Top 15 (logical); sec_dx is expanded to sec_dx_* one-hot at train time → 20 actual features
TOP_CAUSAL_FEATURES: List[str] = [
    "sec_dx",
    "donor_age",
    "txalt",
    "lbun_r",
    "txbun_r",
    "egfr_change",
    "chd_sv",
    "donor_size_ratio",
    "hxsurg",
    "lsbaosat",
    "bmi_txpl",
    "lstp_r",
    "egfr_tx",
    "donor_weight_ratio",
    "txsa_r",
]


def get_top_causal_features() -> List[str]:
    """Return the list of top causal/importance features for reduced model training."""
    return list(TOP_CAUSAL_FEATURES)
