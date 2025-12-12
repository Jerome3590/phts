"""
Model loader utility for loading models from S3.
"""

import json
import pickle
import boto3
from typing import Dict, Any, Optional
from pathlib import Path
import os


class ModelLoader:
    """Loads and caches models from S3."""
    
    def __init__(self, s3_client: boto3.client, bucket: str, prefix: str):
        self.s3_client = s3_client
        self.bucket = bucket
        self.prefix = prefix
        self._models_cache: Dict[str, Any] = {}
        self._metadata_cache: Optional[Dict[str, Any]] = None
        self._local_cache_dir = Path('/tmp/models')
        self._local_cache_dir.mkdir(exist_ok=True)
    
    def load_model(self, cohort: str, model_name: str) -> Any:
        """
        Load a model from S3 (cached).
        
        Args:
            cohort: CHD or MyoCardio
            model_name: Model name (e.g., 'catboost_cox', 'xgboost_cox')
            
        Returns:
            Loaded model object
        """
        cache_key = f"{cohort}/{model_name}"
        
        # Check cache
        if cache_key in self._models_cache:
            return self._models_cache[cache_key]
        
        # Load from S3
        s3_key = f"{self.prefix}{cohort}/{model_name}.pkl"
        local_path = self._local_cache_dir / f"{cohort}_{model_name}.pkl"
        
        # Download if not exists locally
        if not local_path.exists():
            self.s3_client.download_file(self.bucket, s3_key, str(local_path))
        
        # Load model
        with open(local_path, 'rb') as f:
            model = pickle.load(f)
        
        # Cache
        self._models_cache[cache_key] = model
        
        return model
    
    def get_best_model_name(self, cohort: str) -> str:
        """
        Get the best model name for a cohort from metadata.
        
        Args:
            cohort: CHD or MyoCardio
            
        Returns:
            Best model name
        """
        metadata = self.load_metadata()
        return metadata['models'][cohort]['best_model']
    
    def load_metadata(self) -> Dict[str, Any]:
        """Load metadata from S3 (cached)."""
        if self._metadata_cache is not None:
            return self._metadata_cache
        
        # Load from S3
        s3_key = f"{self.prefix}metadata.json"
        local_path = self._local_cache_dir / "metadata.json"
        
        # Download if not exists locally
        if not local_path.exists():
            self.s3_client.download_file(self.bucket, s3_key, str(local_path))
        
        # Load metadata
        with open(local_path, 'r') as f:
            metadata = json.load(f)
        
        # Cache
        self._metadata_cache = metadata
        
        return metadata

