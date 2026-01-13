"""Test XGBoost tree parsing with the actual explainer."""
import json
import logging
import sys
from pathlib import Path

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(Path(__file__).parent))

from ffa_analysis.xgboost_axp_explainer import XGBoostSymbolicExplainer, PathConfig

# Set up logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def test_tree_parsing():
    """Test tree parsing with actual model JSON."""
    
    # Load the JSON
    json_path = Path("outputs/models/Combined/final_model_json/Combined_final_model_xgboost.json")
    if not json_path.exists():
        logger.error(f"JSON file not found: {json_path}")
        return
    
    logger.info(f"Loading JSON from: {json_path}")
    with open(json_path, 'r') as f:
        model_json = json.load(f)
    
    logger.info(f"JSON loaded: {len(model_json.get('trees', []))} trees, "
                f"{len(model_json.get('feature_names', []))} feature names")
    
    # Initialize explainer
    output_dir = Path("outputs/test_parsing")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    path_config = PathConfig(
        model_path=str(json_path),
        data_dir=str(output_dir),
        output_dir=str(output_dir),
        tree_rules_path=None,
        age_band=None
    )
    
    # Create dummy SHAP data (required by explainer)
    import pandas as pd
    import numpy as np
    
    # Dummy SHAP importance map
    dummy_shap_map = {}
    if "feature_names" in model_json:
        for i, feat_name in enumerate(model_json["feature_names"]):
            dummy_shap_map[feat_name] = 1.0 / (i + 1)  # Decreasing importance
    
    # Dummy SHAP values DataFrame (10 instances)
    dummy_shap_df = pd.DataFrame(
        np.random.randn(10, len(model_json.get("feature_names", []))),
        columns=model_json.get("feature_names", [])
    )
    
    explainer = XGBoostSymbolicExplainer(
        path_config=path_config,
        shap_importance_map=dummy_shap_map,
        shap_values_df=dummy_shap_df
    )
    
    # Set feature names (as dict, matching the workflow)
    if "feature_names" in model_json and model_json["feature_names"]:
        explainer.feature_names = {
            i: name for i, name in enumerate(model_json["feature_names"])
        }
        logger.info(f"Set {len(explainer.feature_names)} feature names on explainer")
        logger.info(f"Feature names type: {type(explainer.feature_names)}")
        logger.info(f"First 5 features: {list(explainer.feature_names.items())[:5]}")
    
    # Test parsing first tree manually
    logger.info("\n" + "="*80)
    logger.info("Testing manual parsing of first tree...")
    logger.info("="*80)
    
    if "trees" in model_json and len(model_json["trees"]) > 0:
        first_tree = model_json["trees"][0]
        logger.info(f"First tree type: {type(first_tree)}")
        logger.info(f"First tree length: {len(first_tree) if isinstance(first_tree, str) else 'N/A'}")
        
        # Try parsing the first tree
        try:
            parsed_tree = explainer._parse_xgboost_tree_dump(first_tree)
            logger.info(f"Parsed tree type: {type(parsed_tree)}")
            logger.info(f"Parsed tree keys: {list(parsed_tree.keys()) if isinstance(parsed_tree, dict) else 'N/A'}")
            logger.info(f"Parsed tree empty: {not parsed_tree}")
            
            if parsed_tree:
                logger.info("✓ First tree parsed successfully!")
                if "feature" in parsed_tree:
                    feat_idx = parsed_tree["feature"]
                    feat_name = explainer.feature_names.get(feat_idx, f"f{feat_idx}")
                    logger.info(f"  Root feature: {feat_name} (index {feat_idx})")
                    logger.info(f"  Root threshold: {parsed_tree.get('threshold', 'N/A')}")
            else:
                logger.error("✗ First tree parsing returned empty result")
        except Exception as e:
            logger.error(f"✗ Error parsing first tree: {e}", exc_info=True)
    
    # Now test fit_from_model_json
    logger.info("\n" + "="*80)
    logger.info("Testing fit_from_model_json (full parsing)...")
    logger.info("="*80)
    
    try:
        explainer.model_json = model_json
        explainer.fit_from_model_json(model_json)
        
        logger.info(f"\nResults:")
        logger.info(f"  Rules created: {len(explainer.rule_clauses)}")
        logger.info(f"  Rule predictions: {len(explainer.rule_predictions)}")
        logger.info(f"  Condition ID map: {len(explainer.condition_id_map)}")
        logger.info(f"  ID condition map: {len(explainer.id_condition_map)}")
        logger.info(f"  Feature names: {len(explainer.feature_names) if explainer.feature_names else 0}")
        
        if len(explainer.rule_clauses) > 0:
            logger.info(f"\n✓ Successfully parsed trees and created {len(explainer.rule_clauses)} rules!")
            logger.info(f"  First 3 rule clauses:")
            for i, rule in enumerate(explainer.rule_clauses[:3]):
                logger.info(f"    Rule {i+1}: {rule}")
        else:
            logger.error("✗ No rules were created!")
            logger.error("  This indicates tree parsing failed")
            
    except Exception as e:
        logger.error(f"✗ Error in fit_from_model_json: {e}", exc_info=True)

if __name__ == "__main__":
    test_tree_parsing()
