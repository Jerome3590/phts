# R Scripts Reorganization Plan

## Current State Analysis

### Script Distribution
- **Total R files**: 260
- **Main scripts** (`graft-loss/scripts/`): 17 files
- **Utility functions** (`graft-loss/R/`): 54 files
- **Legacy directory** (`graft-loss-parallel-processing/`): 185 files
- **Test scripts**: 11 files (scattered)

### Issues Identified

1. **Large Legacy Directory** (`graft-loss-parallel-processing/`)
   - 185 R files, many duplicates
   - Contains backup, original_study, and parallel processing implementations
   - Not actively referenced by main scripts
   - Contains useful documentation about parallel processing

2. **Test Scripts Scattered**
   - `graft-loss/feature_importance/test_*.R` (2 files)
   - `graft-loss/graft-loss-parallel-processing/test_*.R` (2 files)
   - `graft-loss/graft-loss-parallel-processing/backup/test_*.R` (7 files)
   - `concordance_index/test_*.R` (6 files)

3. **Empty Subdirectories**
   - `graft-loss/scripts/pipeline/` (empty)
   - `graft-loss/scripts/deployment/` (empty)
   - `graft-loss/scripts/utils/` (empty)

## Reorganization Strategy

### Phase 1: Archive Legacy Directory (Low Risk)
**Action**: Move `graft-loss-parallel-processing/` to `parallel_processing/` directory

**Rationale**:
- Not actively used by main scripts
- Contains historical/development code
- Preserves documentation and examples
- Reduces confusion about which scripts are active
- More descriptive name than "archive" (indicates parallel processing content)

**Steps**:
1. Create `parallel_processing/graft-loss-parallel-processing/`
2. Move entire directory
3. Add README explaining it's archived
4. Update main README to note archived location

### Phase 2: Organize Test Scripts (Medium Priority)
**Action**: Create `tests/` directory structure

**Structure**:
```
tests/
├── concordance_index/
│   └── test_*.R (6 files)
├── feature_importance/
│   └── test_*.R (2 files)
└── pipeline/
    └── test_*.R (from parallel-processing, if needed)
```

**Steps**:
1. Create `tests/` directory
2. Move test scripts from `concordance_index/` to `tests/concordance_index/`
3. Move test scripts from `feature_importance/` to `tests/feature_importance/`
4. Keep backup test scripts in archive

### Phase 3: Clean Up Empty Directories (Low Priority)
**Action**: Remove or populate empty subdirectories

**Options**:
- Remove empty directories if not needed
- Or document their intended purpose

## Detailed Plan

### Step 1: Archive graft-loss-parallel-processing

```bash
# Create archive directory
mkdir -p parallel_processing

# Move directory
git mv graft-loss/graft-loss-parallel-processing parallel_processing/

# Create archive README
```

### Step 2: Organize Test Scripts

```bash
# Create tests directory structure
mkdir -p tests/concordance_index
mkdir -p tests/feature_importance

# Move test scripts
git mv concordance_index/test_*.R tests/concordance_index/
git mv graft-loss/feature_importance/test_*.R tests/feature_importance/
```

### Step 3: Update References

- Update any documentation that references moved files
- Update README files
- Check for any hardcoded paths

## Benefits

1. **Clearer Structure**: Active scripts vs. archived code
2. **Better Organization**: Tests in dedicated directory
3. **Reduced Confusion**: No duplicate/legacy scripts in main directories
4. **Preserved History**: Archived code still accessible

## Risks and Mitigation

### Risk: Breaking References
- **Mitigation**: Check for references before moving
- **Mitigation**: Use `git mv` to preserve history
- **Mitigation**: Update documentation

### Risk: Losing Useful Code
- **Mitigation**: Archive instead of delete
- **Mitigation**: Add README explaining archive contents
- **Mitigation**: Can restore if needed

## Execution Order

1. ✅ Archive `graft-loss-parallel-processing/` (preserves everything)
2. ✅ Organize test scripts (improves structure)
3. ✅ Update documentation (maintains clarity)
4. ⏸️ Clean empty directories (optional, low priority)

