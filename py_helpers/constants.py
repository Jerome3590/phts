# Environment-aware defaults
import os

# AWS configuration
S3_BUCKET = "uva-private-data-lake"
PROJECT_FOLDER = "phts"
MAX_RETRIES = 3
RETRY_DELAY = 2
AWS_REGION = "us-east-1"

# Email configuration
NOTIFICATION_EMAIL = "jerome@mushinsolutions.com" 

# Processing Configuration
LOCK_TIMEOUT_HOURS = 6  # Hours before considering a lock stale
DEFAULT_SAMPLE_RATIO = 5  # Default 5x controls per positive case

# Bloom filter configuration
BLOOM_FILTER_FALSE_POSITIVE_RATIO = 0.01  # 1% false positive ratio
DICTIONARY_SIZE_LIMIT_PERCENT = 10  # 10% of row group size (enables Bloom filters)

