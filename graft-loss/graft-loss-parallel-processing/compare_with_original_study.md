# Comparison with Original Study (bcjaeger/graft-loss)

## Repository: https://github.com/bcjaeger/graft-loss

### Key Files to Examine:
1. **`packages.R`** - Dependencies and versions
2. **`_drake.R`** - Main workflow orchestration
3. **`R/` folder** - Core analysis scripts
4. **`doc/` folder** - Documentation and methodology

### Critical Comparison Points:

#### 1. Data Preprocessing
- [ ] **Missing data handling**: Median imputation vs other methods
- [ ] **Variable transformations**: Log, sqrt, standardization
- [ ] **Outlier handling**: Winsorization, removal criteria
- [ ] **Feature engineering**: Interactions, polynomial terms

#### 2. Model Implementations
- [ ] **AORSF parameters**: n_tree, mtry, node_size, split_rule
- [ ] **CatBoost parameters**: iterations, depth, learning_rate, l2_leaf_reg
- [ ] **LASSO parameters**: alpha, lambda selection method
- [ ] **Cross-validation**: folds, repeats, stratification

#### 3. C-index Calculation
- [ ] **Package used**: survival::concordance vs riskRegression vs survcomp
- [ ] **Time-dependent vs Harrell's C-index**
- [ ] **Handling of tied predictions**
- [ ] **Bootstrap confidence intervals**

#### 4. Cohort Definitions
- [ ] **Inclusion/exclusion criteria**
- [ ] **Time period definitions**
- [ ] **Outcome definitions** (graft loss criteria)
- [ ] **Censoring rules**

#### 5. Variable Selection
- [ ] **15 Wisotzkey variables** - exact same set?
- [ ] **Variable coding** (binary, categorical, continuous)
- [ ] **Reference categories** for factors
- [ ] **Missing value indicators**

### Current Status:
- ✅ **Variables**: Using same 15 Wisotzkey variables
- ✅ **Imputation**: Added median imputation
- ✅ **Derived variables**: Calculated BMI, eGFR, PRA, Listing Year
- ❌ **C-index gap**: Still 0.66-0.67 vs 0.74 (gap of ~0.08-0.09)

### Next Steps:
1. Clone/download the original repository
2. Compare each critical component systematically
3. Identify specific differences causing the C-index gap
4. Implement corrections to match original methodology
