##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param phts_all
make_final_features <- function(phts_all, 
                                n_trees = 500, 
                                n_predictors = 20,
                                use_hardcoded_features = TRUE) {

  if (use_hardcoded_features) {
    # Use predefined Wisotzkey variables for consistency
    # NOTE: tx_mcsd has underscore - this is the derived column created by clean_phts()
    wisotzkey_variables <- c(
      "prim_dx",           # Primary Etiology
      "tx_mcsd",           # MCSD at Transplant (with underscore - derived column!)
      "chd_sv",            # Single Ventricle CHD
      "hxsurg",            # Surgeries Prior to Listing
      "txsa_r",            # Serum Albumin at Transplant
      "txbun_r",           # BUN at Transplant
      "txecmo",            # ECMO at Transplant
      "txpl_year",         # Transplant Year
      "weight_txpl",       # Recipient Weight at Transplant
      "txalt",             # ALT at Transplant (cleaned name, not txalt_r)
      "bmi_txpl",          # BMI at Transplant (created from weight/height)
      "pra_listing",       # PRA at Listing (created from lsfprat)
      "egfr_tx",           # eGFR at Transplant (created from creatinine)
      "hxmed",             # Medical History at Listing
      "listing_year"       # Listing Year (created from txpl_year)
    )
    
    # Check which variables are actually available in the data
    available_vars <- intersect(wisotzkey_variables, colnames(phts_all))
    missing_vars <- setdiff(wisotzkey_variables, colnames(phts_all))
    
    if (length(missing_vars) > 0) {
      warning(sprintf("Missing Wisotzkey variables: %s", paste(missing_vars, collapse = ", ")))
    }
    
    cat(sprintf("[Progress] Using hardcoded Wisotzkey features: %d available, %d missing\n", 
                length(available_vars), length(missing_vars)))
    
    # Directly extract the variables we need - no recipes needed since we know exactly what we want
    # 1. Original variables (for CatBoost, ORSF, RSF, CPH) - just select the 15 Wisotzkey features
    # Handle the case where tx_mcsd is a nested data frame (with underscore!)
    if (is.data.frame(phts_all$tx_mcsd)) {
      # Extract the actual tx_mcsd variable from the nested data frame
      phts_all$tx_mcsd <- phts_all$tx_mcsd$tx_mcsd
    }
    
    pre_proc_ftr_selector <- phts_all %>% 
      select(all_of(available_vars))
    
    # 2. For XGBoost, we need to handle factor variables by creating dummy variables manually
    # This is much simpler than using recipes since we know exactly what we want
    pre_proc_ftr_encoded <- phts_all
    
    # Handle factor variables by creating dummy variables
    for (var in available_vars) {
      if (var %in% colnames(phts_all)) {
        if (is.factor(phts_all[[var]])) {
          # Create dummy variables for factors
          dummy_vars <- model.matrix(~ 0 + get(var), data = phts_all)
          colnames(dummy_vars) <- paste0(var, "_", levels(phts_all[[var]]))
          pre_proc_ftr_encoded <- cbind(pre_proc_ftr_encoded, dummy_vars)
        }
      }
    }
    
    # Get the processed terms for the available variables
    ftrs <- character(0)
    ftrs_as_variables <- character(0)
    
    for (var in available_vars) {
      if (var %in% colnames(phts_all)) {
        if (is.factor(phts_all[[var]])) {
          # For factors, find the dummy variables we just created
          dummy_cols <- colnames(pre_proc_ftr_encoded)[grepl(paste0("^", var, "_"), colnames(pre_proc_ftr_encoded))]
          ftrs <- c(ftrs, dummy_cols)
        } else {
          # For numeric variables, use the original variable name
          ftrs <- c(ftrs, var)
        }
        ftrs_as_variables <- c(ftrs_as_variables, var)
      }
    }
    
    # Remove duplicates
    ftrs_as_variables <- unique(ftrs_as_variables)
    
    cat(sprintf("[DEBUG] Found %d encoded terms for %d variables\n", length(ftrs), length(ftrs_as_variables)))
    if (length(ftrs) > 0) {
      cat(sprintf("[DEBUG] Encoded terms: %s\n", paste(head(ftrs, 10), collapse = ", ")))
      if (length(ftrs) > 10) cat("[DEBUG] ... and more\n")
    }
    
    # For hardcoded Wisotzkey features: KEEP ALL FEATURES regardless of variance
    # These are clinically validated predictors and should not be filtered
    if (length(ftrs) > 0) {
      # Check which terms actually exist in the encoded data
      existing_terms <- intersect(ftrs, colnames(pre_proc_ftr_encoded))
      if (length(existing_terms) < length(ftrs)) {
        missing_terms <- setdiff(ftrs, existing_terms)
        cat(sprintf("[WARNING] Some encoded terms not found: %s\n", paste(missing_terms, collapse = ", ")))
        ftrs <- existing_terms
      }
      
      # NO VARIANCE FILTERING for hardcoded Wisotzkey features
      # All 15 features are kept regardless of variance because they are clinically important
      cat(sprintf("[Progress] Using all %d hardcoded Wisotzkey terms (no variance filtering)\n", length(ftrs)))
    }
    
    # Create a dummy importance data frame for compatibility
    ftr_importance <- data.frame(
      name = ftrs,
      importance = rep(1.0, length(ftrs)),
      stringsAsFactors = FALSE
    )
    
  } else {
    # Original RSF-based feature selection
    pre_proc_ftr_selector <- phts_all %>% 
      make_recipe() %>% 
      prep() %>% 
      juice() %>% 
      select(-ID)
    
    # Exclude obvious outcome/leakage variables if present
    pre_proc_ftr_selector <- pre_proc_ftr_selector %>%
      dplyr::select(-tidyselect::any_of(c(
        # keep 'time' and 'status' for survival formula in select_rsf()
        # 'ID' is already removed above
        'int_dead','int_death','graft_loss','txgloss','death','event'
      )))
    
    ftr_importance <- select_rsf(trn = pre_proc_ftr_selector,
                                 n_predictors = n_predictors,
                                 num.trees = n_trees,
                                 return_importance = TRUE,
                                 use_parallel = TRUE)
    
    ftrs <- pull(ftr_importance, name)
    
    ftrs_as_variables <- ftrs %>% 
      str_split('\\.\\.') %>% 
      map_chr(~.x[1]) %>% 
      unique()
  }
  
  list(terms = ftrs,
       variables = ftrs_as_variables,
       importance = ftr_importance)

}
