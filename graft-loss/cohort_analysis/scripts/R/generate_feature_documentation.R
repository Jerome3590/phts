#!/usr/bin/env Rscript
# Generate feature documentation for cohort analysis
# This script analyzes the cohort analysis features and generates README_cohort_analysis_features.md

library(tidyverse)
library(readr)
library(here)

# Define modifiable features (from cohort analysis notebooks)
modifiable_features <- c(
  # Kidney Function
  "txcreat_r", "lcreat_r", "hxdysdia", "hxrenins", "egfr_tx",
  # Liver Function
  "txast", "lsast", "txalt", "lsalt", "txbili_d_r", "lsbili_d_r",
  "txbili_t_r", "lsbili_t_r", "hxfonlvr",
  # Nutrition
  "txpalb_r", "lspalb_r", "txsa_r", "lssab_r", "txtp_r", "lstp_r",
  "hxfail", "bmi_txpl", "height_txpl", "height_listing",
  "weight_txpl", "weight_listing",
  # Respiratory
  "txvent", "slvent", "ltxtrach", "hxtrach",
  # Cardiac
  "txvad", "slvad", "slnomcsd", "txecmo", "slecmo", "hxcpr", "hxshock",
  # Immunology
  "hlatxpre", "donspac", "txfcpra", "lsfcpra"
)

# Define excluded variables (from prepare_modeling_data function)
exclude_exact <- c(
  "ID", "ptid_e", "int_dead", "int_death", "graft_loss", "txgloss", "death", "event",
  "dpricaus", "deathspc", "concod", "age_death", "dlist", "txpl_year",
  "rrace_b", "rrace_a", "rrace_ai", "rrace_pi", "rrace_o", "rrace_un", "race",
  "patsupp", "pmorexam", "papooth", "pacuref", "pishltgr",
  "pathero", "pcadrec", "pcadrem", "pdiffib", "cpathneg",
  "dcardiac", "dneuro", "dreject", "dsecaccs", "dpriaccs",
  "dconmbld", "dconmal", "dconcard", "dconneur", "dconrej",
  "dmajbld", "dmalcanc"
)

exclude_prefixes <- c("dtx_", "cc_", "dcon", "dpri", "dsec", "dmaj", "sd")

# Load actual data to calculate IQRs
cat("Loading PHTS data...\n")
data_path <- here("data", "phts_txpl_ml.sas7bdat")
if (!file.exists(data_path)) {
  # Try alternative path
  data_path <- here("..", "data", "phts_txpl_ml.sas7bdat")
}

if (!file.exists(data_path)) {
  cat("Warning: Data file not found\n")
  cat("Will generate README with feature lists only (no IQRs)\n")
  phts_data <- NULL
} else {
  phts_data <- haven::read_sas(data_path)
  # Convert variable names to uppercase to match data (data has uppercase names)
  names(phts_data) <- toupper(names(phts_data))
  cat("Loaded", nrow(phts_data), "rows,", ncol(phts_data), "columns\n")
}

# Calculate IQRs for numerical variables
calculate_iqr <- function(var_name, data) {
  if (is.null(data) || !var_name %in% names(data)) {
    return(list(var = var_name, q1 = NA, median = NA, q3 = NA, iqr = NA))
  }
  
  var_data <- data[[var_name]]
  if (!is.numeric(var_data)) {
    return(list(var = var_name, q1 = NA, median = NA, q3 = NA, iqr = NA))
  }
  
  var_data <- var_data[!is.na(var_data) & is.finite(var_data)]
  if (length(var_data) == 0) {
    return(list(var = var_name, q1 = NA, median = NA, q3 = NA, iqr = NA))
  }
  
  q1 <- quantile(var_data, 0.25, na.rm = TRUE)
  median_val <- median(var_data, na.rm = TRUE)
  q3 <- quantile(var_data, 0.75, na.rm = TRUE)
  iqr <- q3 - q1
  
  return(list(
    var = var_name,
    q1 = as.numeric(q1),
    median = as.numeric(median_val),
    q3 = as.numeric(q3),
    iqr = as.numeric(iqr)
  ))
}

# Calculate IQRs for all numerical modifiable features
cat("\nCalculating IQRs for numerical variables...\n")
# Convert modifiable_features to uppercase to match data variable names
modifiable_features_upper <- toupper(modifiable_features)
iqr_results <- map_dfr(modifiable_features_upper, ~calculate_iqr(.x, phts_data))
# Convert back to lowercase for display
iqr_results <- iqr_results %>%
  mutate(var = tolower(var))

# Filter to only variables with valid IQRs
iqr_results <- iqr_results %>%
  filter(!is.na(median))

# Generate README content
readme_content <- paste0(
  "# Cohort Analysis Features Documentation\n\n",
  "This document describes the variables used in the cohort analysis for graft loss prediction.\n\n",
  "## Overview\n\n",
  "- **Total Variables in PHTS Dataset**: ", ifelse(is.null(phts_data), "N/A", ncol(phts_data)), "\n",
  "- **Modifiable Clinical Features Kept**: ", length(modifiable_features), "\n",
  "- **Variables Excluded**: ", length(exclude_exact), " exact matches + variables with prefixes: ", paste(exclude_prefixes, collapse = ", "), "\n\n",
  "## Variables Kept (Modifiable Clinical Features)\n\n",
  "The cohort analysis uses only **modifiable clinical features** that can be influenced by clinical intervention.\n\n",
  "### Kidney Function (5 features)\n",
  "- `txcreat_r` - Creatinine at transplant (mg/dL)\n",
  "- `lcreat_r` - Creatinine at listing (mg/dL)\n",
  "- `hxdysdia` - History of dialysis\n",
  "- `hxrenins` - History of renal insufficiency\n",
  "- `egfr_tx` - Estimated GFR at transplant (mL/min/1.73m²) **[CALCULATED]**\n\n",
  "### Liver Function (9 features)\n",
  "- `txast` - AST at transplant (U/L)\n",
  "- `lsast` - AST at listing (U/L)\n",
  "- `txalt` - ALT at transplant (U/L)\n",
  "- `lsalt` - ALT at listing (U/L)\n",
  "- `txbili_d_r` - Direct bilirubin at transplant (mg/dL)\n",
  "- `lsbili_d_r` - Direct bilirubin at listing (mg/dL)\n",
  "- `txbili_t_r` - Total bilirubin at transplant (mg/dL)\n",
  "- `lsbili_t_r` - Total bilirubin at listing (mg/dL)\n",
  "- `hxfonlvr` - History of Fontan liver disease\n\n",
  "### Nutrition (12 features)\n",
  "- `txpalb_r` - Pre-albumin at transplant (mg/dL)\n",
  "- `lspalb_r` - Pre-albumin at listing (mg/dL)\n",
  "- `txsa_r` - Serum albumin at transplant (g/dL)\n",
  "- `lssab_r` - Serum albumin at listing (g/dL)\n",
  "- `txtp_r` - Total protein at transplant (g/dL)\n",
  "- `lstp_r` - Total protein at listing (g/dL)\n",
  "- `hxfail` - History of failure to thrive\n",
  "- `bmi_txpl` - BMI at transplant (kg/m²) **[CALCULATED]**\n",
  "- `height_txpl` - Height at transplant (cm)\n",
  "- `height_listing` - Height at listing (cm)\n",
  "- `weight_txpl` - Weight at transplant (kg)\n",
  "- `weight_listing` - Weight at listing (kg)\n\n",
  "### Respiratory (4 features)\n",
  "- `txvent` - Ventilation at transplant\n",
  "- `slvent` - Ventilation at listing\n",
  "- `ltxtrach` - Tracheostomy at listing\n",
  "- `hxtrach` - History of tracheostomy\n\n",
  "### Cardiac Support (7 features)\n",
  "- `txvad` - VAD at transplant\n",
  "- `slvad` - VAD at listing\n",
  "- `slnomcsd` - Consider MCSD\n",
  "- `txecmo` - ECMO at transplant\n",
  "- `slecmo` - ECMO at listing\n",
  "- `hxcpr` - History of CPR\n",
  "- `hxshock` - History of shock\n\n",
  "### Immunology (4 features)\n",
  "- `hlatxpre` - HLA pre-sensitization\n",
  "- `donspac` - Donor-specific crossmatch\n",
  "- `txfcpra` - Flow cytometry PRA at transplant (%)\n",
  "- `lsfcpra` - Flow cytometry PRA at listing (%)\n\n",
  "## Variables Dropped\n\n",
  "### Exact Matches Excluded\n\n",
  "The following variables are explicitly excluded:\n\n",
  paste0("- `", exclude_exact, "`", collapse = "\n"), "\n\n",
  "### Prefix-Based Exclusions\n\n",
  "All variables starting with the following prefixes are excluded:\n\n",
  paste0("- `", exclude_prefixes, "*`", collapse = "\n"), "\n\n",
  "### Reasons for Exclusion\n\n",
  "1. **Outcome/Leakage Variables**: Variables that directly indicate the outcome (e.g., `graft_loss`, `death`, `int_death`)\n",
  "2. **Donor-Specific Variables**: Variables related to donor characteristics (e.g., `dtx_*`, `dcon*`, `dpri*`, `dsec*`)\n",
  "3. **Identifier Variables**: Patient identifiers (e.g., `ID`, `ptid_e`)\n",
  "4. **Non-Modifiable Variables**: Variables that cannot be changed through clinical intervention (e.g., `race`, `txpl_year`)\n",
  "5. **Complication Variables**: Post-transplant complications that occur after the prediction timepoint\n\n",
  "## Interquartile Range (IQR) for Numerical Variables\n\n",
  "The following table shows the IQR (25th percentile, median, 75th percentile) for each numerical variable:\n\n",
  "| Variable | Q1 (25th) | Median | Q3 (75th) | IQR |\n",
  "|----------|-----------|--------|-----------|-----|\n",
  paste0(
    "| `", iqr_results$var, "` | ",
    ifelse(is.na(iqr_results$q1), "N/A", sprintf("%.2f", iqr_results$q1)), " | ",
    ifelse(is.na(iqr_results$median), "N/A", sprintf("%.2f", iqr_results$median)), " | ",
    ifelse(is.na(iqr_results$q3), "N/A", sprintf("%.2f", iqr_results$q3)), " | ",
    ifelse(is.na(iqr_results$iqr), "N/A", sprintf("%.2f", iqr_results$iqr)), " |\n",
    collapse = ""
  ), "\n",
  "## Mapping to Transplant Data Dictionary\n\n",
  "**Note**: The data dictionary file `Contents_Transplant.docx` (or `PHTSVariable.pdf`) contains detailed descriptions of all PHTS variables.\n\n",
  "### Key Variable Mappings\n\n",
  "| PHTS Variable | Data Dictionary Reference | Description |\n",
  "|---------------|---------------------------|-------------|\n",
  "| `txcreat_r` | Creatinine (Transplant) | Serum creatinine at time of transplant |\n",
  "| `lcreat_r` | Creatinine (Listing) | Serum creatinine at time of listing |\n",
  "| `egfr_tx` | **[CALCULATED]** | Estimated GFR calculated as: `0.413 * height_txpl / txcreat_r` |\n",
  "| `txast` | AST (Transplant) | Aspartate aminotransferase at transplant |\n",
  "| `txalt` | ALT (Transplant) | Alanine aminotransferase at transplant |\n",
  "| `txbili_d_r` | Direct Bilirubin (Transplant) | Direct bilirubin at transplant |\n",
  "| `txbili_t_r` | Total Bilirubin (Transplant) | Total bilirubin at transplant |\n",
  "| `txpalb_r` | Pre-albumin (Transplant) | Pre-albumin at transplant |\n",
  "| `txsa_r` | Serum Albumin (Transplant) | Serum albumin at transplant |\n",
  "| `txtp_r` | Total Protein (Transplant) | Total protein at transplant |\n",
  "| `bmi_txpl` | **[CALCULATED]** | BMI calculated as: `(weight_txpl / height_txpl^2) * 703` |\n",
  "| `height_txpl` | Height (Transplant) | Patient height at transplant (cm) |\n",
  "| `weight_txpl` | Weight (Transplant) | Patient weight at transplant (kg) |\n",
  "| `txvent` | Ventilation (Transplant) | Mechanical ventilation at transplant |\n",
  "| `txvad` | VAD (Transplant) | Ventricular assist device at transplant |\n",
  "| `txecmo` | ECMO (Transplant) | Extracorporeal membrane oxygenation at transplant |\n",
  "| `hlatxpre` | HLA Pre-sensitization | HLA antibody pre-sensitization status |\n",
  "| `txfcpra` | Flow Cytometry PRA (Transplant) | Flow cytometry panel reactive antibody at transplant (%) |\n",
  "\n",
  "**For complete variable descriptions, refer to the PHTS Data Dictionary (`PHTSVariable.pdf` or `Contents_Transplant.docx`).**\n\n",
  "## Calculated Variables\n\n",
  "### eGFR Calculation\n",
  "Estimated Glomerular Filtration Rate (eGFR) is calculated using the Schwartz formula:\n\n",
  "```r\n",
  "egfr_tx = 0.413 * height_txpl / txcreat_r\n",
  "```\n\n",
  "Where:\n",
  "- `height_txpl` is height at transplant in cm\n",
  "- `txcreat_r` is serum creatinine at transplant in mg/dL\n",
  "- The constant 0.413 is the Schwartz constant for pediatric patients\n\n",
  "### BMI Calculation\n",
  "Body Mass Index (BMI) is calculated as:\n\n",
  "```r\n",
  "bmi_txpl = (weight_txpl / height_txpl^2) * 703\n",
  "```\n\n",
  "Where:\n",
  "- `weight_txpl` is weight at transplant in kg\n",
  "- `height_txpl` is height at transplant in cm\n",
  "- The factor 703 converts from kg/cm² to kg/m²\n\n",
  "### WHO Growth Curve Calculations\n",
  "\n",
  "**Note**: WHO growth curve calculations (z-scores and percentiles) for height and weight are planned for future implementation.\n\n",
  "These calculations will use:\n",
  "- WHO Child Growth Standards for children < 5 years\n",
  "- WHO Growth Reference for children 5-19 years\n",
  "- Age, sex, height, and weight to calculate z-scores and percentiles\n\n"
)

# Write README
readme_path <- here("README_cohort_analysis_features.md")
writeLines(readme_content, readme_path)
cat("\n✓ README generated at:", readme_path, "\n")

