# Parallel Processing Implementation: graft-loss-parallel-processing

## Status: ACTIVE - Parallel Processing Code

This directory contains parallel processing implementations and utilities for the graft loss prediction pipeline. The code here is used to parallelize the pipeline after initial verification in unparallelized mode.

**Location**: `graft-loss/graft-loss-parallel-processing/`

## Purpose

This directory contains:
- **Parallel processing implementations**: Enhanced versions of pipeline scripts with parallelization
- **Model-specific parallel configs**: Parallel configuration for RSF, AORSF, XGBoost, CatBoost, Cox PH
- **Orchestration scripts**: Scripts for running multiple cohorts in parallel
- **Documentation**: Comprehensive parallel processing setup guides

## Development Workflow

1. **Unparallelized Mode**: First, run the main pipeline (`graft-loss/scripts/`) in unparallelized mode to verify everything works
2. **Parallelization**: Then use the parallel processing implementations in this directory to accelerate execution

## Contents

- **scripts/R/**: Parallel processing implementations and utilities
  - Model-specific parallel configurations (RSF, AORSF, XGBoost, CatBoost, Cox PH)
  - Parallel model fitting functions
  - Resource monitoring and process management
  
- **pipeline/**: Enhanced pipeline scripts with parallelization
  - Parallel versions of main pipeline steps
  - Orchestration scripts for multi-cohort execution
  
- **model_setup/**: Model-specific parallelization documentation
  - Setup guides for each model type
  - Best practices and troubleshooting
  
- **original_study/**: Original study replication scripts
  - Scripts for replicating the original Wisotzkey study
  
- **backup/**: Backup versions of scripts
  - Historical versions preserved for reference

## Relationship to Main Pipeline

**Main Pipeline** (`graft-loss/scripts/`):
- Runs in unparallelized mode by default
- Used for initial verification and development
- Simpler, easier to debug

**Parallel Processing** (`parallel_processing/graft-loss-parallel-processing/`):
- Enhanced versions with parallelization
- Used for production runs and large-scale analysis
- Optimized for performance and resource utilization

## Usage

After verifying the pipeline works in unparallelized mode:

1. Review parallel processing documentation in `model_setup/`
2. Configure parallel backend using utilities in `scripts/R/utils/`
3. Run parallelized pipeline using scripts in `pipeline/`

## Documentation

- **`README.md`**: Comprehensive parallel processing documentation
- **`model_setup/`**: Model-specific parallelization guides
- **`PARALLEL_PROCESSING.md`** (root): Main parallel processing documentation

## Current Active Code

The active pipeline code is in:
- `graft-loss/scripts/` - Main pipeline scripts (unparallelized)
- `graft-loss/R/` - Utility functions
- `graft-loss/graft-loss-parallel-processing/` - Parallel processing implementations

