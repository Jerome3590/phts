"""
Risk prediction utility using loaded models.
"""

from typing import Dict, Any, List
from utils.model_loader import ModelLoader
import numpy as np


class RiskPredictor:
    """Predicts graft loss risk using cohort-specific models."""
    
    def __init__(self, model_loader: ModelLoader):
        self.model_loader = model_loader
    
    def predict_risk(self, cohort: str, features: Dict[str, float]) -> Dict[str, Any]:
        """
        Predict graft loss risk for given features.
        
        Args:
            cohort: CHD or MyoCardio
            features: Dictionary of feature values
            
        Returns:
            Dictionary with risk score, contributions, recommendations
        """
        # Get best model for cohort
        model_name = self.model_loader.get_best_model_name(cohort)
        model = self.model_loader.load_model(cohort, model_name)
        metadata = self.model_loader.load_metadata()
        
        # Prepare feature vector
        feature_vector = self._prepare_features(features, metadata['features'])
        
        # Get prediction
        risk_score = self._predict(model, model_name, feature_vector)
        
        # Get feature contributions (SHAP values or feature importance)
        feature_contributions = self._get_feature_contributions(
            model, model_name, feature_vector, features, metadata['features']
        )
        
        # Generate recommendations
        recommendations = self._generate_recommendations(
            features, feature_contributions, metadata['features']
        )
        
        # Calculate confidence interval (simplified - would use proper CI from model)
        ci_lower = max(0, risk_score - 0.05)
        ci_upper = min(1, risk_score + 0.05)
        
        return {
            'cohort': cohort,
            'model': model_name,
            'risk_score': float(risk_score),
            'risk_percentile': self._calculate_percentile(risk_score, cohort),
            'confidence_interval': [ci_lower, ci_upper],
            'feature_contributions': feature_contributions,
            'recommendations': recommendations
        }
    
    def _prepare_features(self, features: Dict[str, float], metadata_features: Dict[str, Any]) -> np.ndarray:
        """Prepare feature vector from input features."""
        # Get feature order from metadata
        feature_order = sorted(metadata_features.keys())
        
        # Create feature vector
        feature_vector = []
        for feature in feature_order:
            value = features.get(feature, 0.0)
            # Normalize if needed (based on metadata ranges)
            if feature in metadata_features:
                feature_info = metadata_features[feature]
                if 'normalize' in feature_info:
                    # Apply normalization
                    value = (value - feature_info['mean']) / feature_info['std']
            feature_vector.append(value)
        
        return np.array(feature_vector).reshape(1, -1)
    
    def _predict(self, model: Any, model_name: str, feature_vector: np.ndarray) -> float:
        """Make prediction using model."""
        # Model-specific prediction logic
        if 'catboost' in model_name.lower():
            # CatBoost prediction
            import catboost
            if hasattr(model, 'predict'):
                pred = model.predict(feature_vector)
                # CatBoost Cox returns negative values for higher risk
                # Convert to risk score (0-1)
                return self._convert_to_risk_score(pred[0])
        elif 'xgboost' in model_name.lower():
            # XGBoost prediction
            pred = model.predict(feature_vector)
            return self._convert_to_risk_score(pred[0])
        elif 'rsf' in model_name.lower() or 'ranger' in model_name.lower():
            # Random Survival Forest prediction
            pred = model.predict(feature_vector)
            return float(pred[0])
        else:
            # Default: assume model has predict method
            pred = model.predict(feature_vector)
            return float(pred[0])
    
    def _convert_to_risk_score(self, raw_pred: float) -> float:
        """Convert raw prediction to risk score (0-1)."""
        # Apply sigmoid or other transformation
        import math
        return 1 / (1 + math.exp(-raw_pred))
    
    def _get_feature_contributions(
        self,
        model: Any,
        model_name: str,
        feature_vector: np.ndarray,
        features: Dict[str, float],
        metadata_features: Dict[str, Any]
    ) -> Dict[str, float]:
        """Get feature contributions to prediction."""
        # Simplified: use feature importance
        # In production, would use SHAP values for better interpretability
        
        contributions = {}
        
        if hasattr(model, 'feature_importances_'):
            importances = model.feature_importances_
            feature_order = sorted(metadata_features.keys())
            
            for i, feature in enumerate(feature_order):
                if i < len(importances):
                    contributions[feature] = float(importances[i])
        else:
            # Fallback: equal contributions
            for feature in features:
                contributions[feature] = 0.0
        
        return contributions
    
    def _generate_recommendations(
        self,
        features: Dict[str, float],
        contributions: Dict[str, float],
        metadata_features: Dict[str, Any]
    ) -> List[str]:
        """Generate clinical recommendations based on features and contributions."""
        recommendations = []
        
        # Sort features by contribution (highest risk contributors first)
        sorted_features = sorted(
            contributions.items(),
            key=lambda x: x[1],
            reverse=True
        )
        
        # Generate recommendations for top risk factors
        for feature, contrib in sorted_features[:5]:
            if feature in metadata_features:
                feature_info = metadata_features[feature]
                category = feature_info.get('category', '')
                modifiability = feature_info.get('modifiability', '')
                
                if modifiability in ['Modifiable', 'Partially Modifiable']:
                    if category == 'Kidney Function':
                        recommendations.append(f"Monitor and optimize kidney function ({feature})")
                    elif category == 'Liver Function':
                        recommendations.append(f"Monitor liver function ({feature})")
                    elif category == 'Nutrition':
                        recommendations.append(f"Optimize nutritional support ({feature})")
                    elif category == 'Respiratory':
                        recommendations.append(f"Consider respiratory support optimization ({feature})")
                    elif category == 'Cardiac':
                        recommendations.append(f"Review cardiac support status ({feature})")
                    elif category == 'Immunology':
                        recommendations.append(f"Review immunology status ({feature})")
        
        return recommendations[:3]  # Return top 3
    
    def _calculate_percentile(self, risk_score: float, cohort: str) -> int:
        """Calculate risk percentile (simplified - would use actual distribution)."""
        # Simplified: assume normal distribution
        # In production, would use actual risk score distribution from training data
        if risk_score < 0.2:
            return int(risk_score * 100)
        elif risk_score < 0.5:
            return int(20 + (risk_score - 0.2) / 0.3 * 50)
        else:
            return int(70 + (risk_score - 0.5) / 0.5 * 30)

