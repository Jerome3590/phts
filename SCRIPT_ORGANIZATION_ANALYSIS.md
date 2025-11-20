# R and Python Script Organization Analysis

## Current State

### R Scripts Distribution
- **Total R files in `graft-loss/`**: 260 files
- **Main active scripts**: `graft-loss/scripts/` (18 files)
- **Main utility functions**: `graft-loss/R/` (54 files)
- **Legacy/duplicate directory**: `graft-loss/graft-loss-parallel-processing/` (185+ R files)

### Python Scripts Distribution
- **Total Python files**: 10 files
- **Main Python script**: `graft-loss/scripts/py/catboost_survival.py`
- **Duplicate**: `graft-loss/graft-loss-parallel-processing/scripts/py/catboost_survival.py` (differs)
- **FFA analysis**: `graft-loss/cohort_analysis/ffa_analysis/` (3 files)

## Issues Identified

### 1. **Duplicate Python Script** ⚠️
**Problem**: Two versions of `catboost_survival.py` exist:
- `graft-loss/scripts/py/catboost_survival.py` (active/main)
- `graft-loss/graft-loss-parallel-processing/scripts/py/catboost_survival.py` (differs)

**Impact**: 
- Confusion about which version is current
- Risk of using outdated version
- Maintenance burden

**Recommendation**: 
- Compare both files to determine which is current
- Remove duplicate or consolidate into single source
- Update any references to point to correct location

### 2. **Large Legacy Directory** ⚠️⚠️
**Problem**: `graft-loss-parallel-processing/` contains:
- 185+ R files (many duplicates of `graft-loss/R/` and `graft-loss/scripts/`)
- Duplicate Python script
- Backup directory with 32 old R files
- Original study directory with 52 R files
- Multiple pipeline scripts

**Impact**:
- Confusion about which scripts are active
- Maintenance burden (updates needed in multiple places)
- Large repository size
- Risk of using outdated code

**Recommendation**:
- **Option A**: Archive `graft-loss-parallel-processing/` if it's truly legacy
  - Move to `archive/` or `legacy/` directory
  - Add README explaining it's archived
  - Update documentation to remove references
  
- **Option B**: If still needed, consolidate:
  - Identify unique functionality
  - Merge into main `graft-loss/scripts/` and `graft-loss/R/`
  - Remove duplicates
  - Update all references

### 3. **Scattered Helper Files** ⚠️
**Problem**: Multiple `helpers.R` files:
- `graft-loss/cohort_analysis/helpers.R` (10KB)
- `graft-loss/cohort_survival_analysis/helpers.R` (50KB)

**Impact**:
- Code duplication
- Inconsistent naming
- Hard to find shared utilities

**Recommendation**:
- Review contents of each `helpers.R`
- Extract shared functions to `graft-loss/R/utils/`
- Keep cohort-specific helpers in their respective directories but rename for clarity (e.g., `cohort_analysis_helpers.R`)

### 4. **Test Scripts Scattered** ⚠️
**Problem**: Test scripts in multiple locations:
- `concordance_index/test_*.R` (6 test files)
- `graft-loss/feature_importance/test_*.R` (2 test files)
- Possibly more in other directories

**Impact**:
- Hard to find all tests
- Inconsistent test organization
- Difficult to run comprehensive test suite

**Recommendation**:
- Create `tests/` directory at project root or `graft-loss/tests/`
- Organize by component:
  ```
  tests/
  ├── concordance_index/
  ├── feature_importance/
  └── pipeline/
  ```
- Or keep tests co-located with code (current approach) but document pattern

### 5. **Python Scripts Organization** ⚠️
**Problem**: Python scripts in multiple locations:
- Main script: `graft-loss/scripts/py/catboost_survival.py`
- FFA analysis: `graft-loss/cohort_analysis/ffa_analysis/*.py` (3 files)

**Impact**:
- Inconsistent organization
- Hard to find Python code

**Recommendation**:
- **Option A**: Consolidate all Python scripts:
  ```
  graft-loss/
  └── scripts/
      └── py/
          ├── catboost_survival.py
          └── ffa_analysis/
              ├── catboost_axp_explainer.py
              ├── catboost_axp_explainer2.py
              └── ffa_analysis.py
  ```
  
- **Option B**: Keep Python scripts co-located with related R code (current approach) but document pattern

### 6. **Utility Organization** ✅
**Good**: `graft-loss/R/utils/` is well-organized:
- `data_utils.R`
- `model_utils.R`
- `parallel_utils.R`

**Recommendation**: Continue this pattern for new utilities

## Recommended Organization Structure

### Ideal Structure

```
graft-loss/
├── scripts/                    # Main pipeline scripts (executables)
│   ├── 00_setup.R
│   ├── 01_prepare_data.R
│   ├── 02_resampling.R
│   ├── 03_prep_model_data.R
│   ├── 04_fit_model.R
│   ├── 05_generate_outputs.R
│   ├── run_pipeline.R
│   ├── config.R
│   ├── packages.R
│   ├── py/                     # Python scripts
│   │   └── catboost_survival.py
│   ├── pipeline/               # Pipeline orchestration
│   ├── deployment/             # Deployment scripts
│   └── utils/                  # Script-level utilities
│
├── R/                          # R utility functions (library)
│   ├── utils/                  # Organized utility modules
│   │   ├── data_utils.R
│   │   ├── model_utils.R
│   │   └── parallel_utils.R
│   ├── clean_phts.R
│   ├── fit_*.R
│   ├── make_*.R
│   └── ... (other utilities)
│
├── tests/                      # Test scripts (optional)
│   ├── concordance_index/
│   ├── feature_importance/
│   └── pipeline/
│
├── cohort_analysis/            # Cohort-specific analysis
│   ├── helpers.R              # Rename to cohort_analysis_helpers.R
│   └── ffa_analysis/          # Keep Python scripts here if related
│
└── cohort_survival_analysis/  # Cohort survival analysis
    └── helpers.R              # Rename to cohort_survival_helpers.R
```

## Action Items (Priority Order)

### High Priority
1. **Resolve duplicate Python script**
   - Compare `graft-loss/scripts/py/catboost_survival.py` vs `graft-loss-parallel-processing/scripts/py/catboost_survival.py`
   - Determine which is current
   - Remove duplicate or consolidate

2. **Address `graft-loss-parallel-processing/` directory**
   - Determine if it's still needed
   - If legacy: archive it
   - If needed: consolidate unique functionality

### Medium Priority
3. **Rename scattered `helpers.R` files**
   - `cohort_analysis/helpers.R` → `cohort_analysis_helpers.R`
   - `cohort_survival_analysis/helpers.R` → `cohort_survival_helpers.R`

4. **Document Python script organization pattern**
   - Decide on co-location vs consolidation
   - Update README with pattern

### Low Priority
5. **Consider test organization**
   - Evaluate if `tests/` directory would help
   - Or document current co-location pattern

## Current Organization Assessment

### ✅ What's Working Well
- Main pipeline scripts (`scripts/`) are clearly numbered and organized
- Utility functions (`R/utils/`) are well-organized into modules
- Python scripts have dedicated `py/` subdirectory in scripts
- Clear separation between scripts (executables) and R functions (library)

### ⚠️ What Needs Improvement
- Duplicate Python script needs resolution
- Large legacy directory needs archiving or consolidation
- Scattered helper files need renaming for clarity
- Test scripts could be better organized (or pattern documented)

## Summary

**Overall Assessment**: The main structure (`scripts/` and `R/`) is well-organized, but there are organizational issues with:
1. Duplicate files (Python script)
2. Legacy directory (`graft-loss-parallel-processing/`)
3. Scattered helper files

**Recommendation**: Address the duplicate Python script and legacy directory first, as these have the highest impact on maintainability and confusion.

