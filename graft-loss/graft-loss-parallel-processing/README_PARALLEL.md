# Parallel Processing Implementation: graft-loss-parallel-processing

## Status: PARALLEL PROCESSING CODE (To Be Integrated)

This directory contains parallel processing implementations that will be integrated into the main pipeline **after** the unparallelized version is verified and working correctly.

**Current Workflow**:
1. ✅ **Phase 1 (Current)**: Run pipeline in unparallelized mode (`graft-loss/scripts/`) to verify correctness
2. ⏳ **Phase 2 (Next)**: Integrate parallel processing from this directory
3. ⏳ **Phase 3**: Verify parallelized version produces same results as unparallelized version

## Development Strategy

**Current Approach**:
1. ✅ **Phase 1**: Run pipeline in unparallelized mode to verify correctness
2. ⏳ **Phase 2**: Integrate parallel processing from this directory
3. ⏳ **Phase 3**: Verify parallelized version produces same results

## Contents

- **scripts/R/**: Parallel processing implementations and utilities
- **original_study/**: Original study replication scripts
- **backup/**: Backup versions of scripts
- **model_setup/**: Model setup documentation
- **pipeline/**: Pipeline orchestration scripts
- **README.md**: Parallel processing documentation

## Current Active Code

The active (unparallelized) pipeline code is in:
- `graft-loss/scripts/` - Main pipeline scripts (unparallelized)
- `graft-loss/R/` - Utility functions

## Parallel Processing Code

The parallel processing implementations are in:
- `graft-loss/graft-loss-parallel-processing/scripts/R/` - Parallel processing functions
- `graft-loss/graft-loss-parallel-processing/pipeline/` - Parallel pipeline scripts

## Integration Plan

Once the unparallelized pipeline is verified:
1. Review parallel processing implementations in this directory
2. Integrate parallel utilities into `graft-loss/R/utils/`
3. Update main pipeline scripts to use parallel processing
4. Verify parallelized version produces identical results

## Documentation

- **Main Parallel Processing Guide**: `PARALLEL_PROCESSING.md` (root level)
- **This Directory's README**: `README.md` (comprehensive parallel processing documentation)

