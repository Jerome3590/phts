#' Filter data to a single cohort by primary diagnosis.
#' @param df Data frame with PRIM_DX (or prim_dx) column.
#' @param cohort One of "CHD", "Myocardio", "Combined".
#' @return Filtered df (same columns).
filter_cohort_prim_dx <- function(df, cohort = "Combined") {
  prim_dx <- df[["PRIM_DX"]]
  if (is.null(prim_dx)) prim_dx <- df[["prim_dx"]]
  if (is.null(prim_dx)) return(df)
  if (cohort == "CHD") {
    return(df[prim_dx == "Congenital HD", , drop = FALSE])
  }
  if (cohort == "Myocardio") {
    return(df[prim_dx %in% c("Cardiomyopathy", "Myocarditis"), , drop = FALSE])
  }
  if (cohort == "Combined") {
    return(df[prim_dx %in% c("Congenital HD", "Cardiomyopathy", "Myocarditis"), , drop = FALSE])
  }
  df
}

#' Build Wisotzkey-et-al. variable set from calculator-style data.
#' @param df Data frame with PRIM_DX/prim_dx and required lab/demographic columns.
#' @param cohort One of "CHD", "Myocardio", "Combined". Filters to that cohort before building vars.
#' @return Data frame with outcome and Wisotzkey variables only.
make_wisotzkey_data <- function(df, cohort = "Combined") {
  prim_dx_col <- if ("PRIM_DX" %in% names(df)) "PRIM_DX" else "prim_dx"
  df %>%
    filter_cohort_prim_dx(cohort) %>%
    mutate(
      .prim_dx = .data[[prim_dx_col]],
      BMI_TXPL = 703 * WEIGHT_TXPL / (HEIGHT_TXPL)^2,
      eGFR_TXPL = 0.413 * (HEIGHT_TXPL*2.54) / pmax(TXCREAT_R, .001)
    ) %>%
    transmute(
      outcome,
      CHD = 1*(.prim_dx == "Congenital HD"),
      TXMCSD = coalesce(TXMCSD, 0),
      CHD_SV = coalesce(CHD_SV, 0),  # CHD: Single Ventricle     
      HXSURG = coalesce(HXSURG, 0),   # prior heart surgeries
      HXMED = coalesce(HXMED, 0),   # Medical history at time of Listing
      
      #: Nutrition:
      ALBUMIN_UNDER_3 = case_when(TXSA_R < 3 ~ 1, .default = 0),  # transplant serum albumin (normal varies by age) [3.5, 5.5]
      
      #: Kidney
      BUN_UNDER_15 = case_when(TXBUN_R < 15 ~ 1, .default = 0),      # Transplant Lab: BUN mg/dL
      eGFR_UNDER_60 = case_when(eGFR_TXPL < 60 ~ 1, .default = 0),    # eGFR_LISTING, eGFR_change
      
      
      #: Life Support
      TXECMO = coalesce(TXECMO, 0),
      
      #: Year 
      YR_UNDER_2015 = 1*(TXPL_YEAR < 2015),
      
      #: Demographics
      WEIGHT_UNDER_75 = 1*(WEIGHT_TXPL < 75),
      BMI_UNDER_18 = case_when(BMI_TXPL < 18 ~ 1, 
                               is.na(BMI_TXPL) ~ 0, 
                               .default = 0),
      
      #: Liver
      ALT_UNDER_30 = case_when(TXALT < 30 ~ 1, is.na(TXALT) ~ 1, .default = 0),       # Transplant Lab: ALT U/L    
      ALT_OVER_50  = case_when(TXALT >= 50 ~ 1, .default = 0),
      
      # MISSING: PRA MAX LIST
    )
}

#' Create Wisotzkey-vars datasets for all cohorts (CHD, Myocardio, Combined).
#' @param df Data frame with PRIM_DX/prim_dx and required columns (see make_wisotzkey_data).
#' @param out_dir Optional directory path to write CSV files: wisotzkey_CHD.csv, wisotzkey_Myocardio.csv, wisotzkey_Combined.csv. If NULL, no files are written.
#' @return Named list of data frames: CHD, Myocardio, Combined.
make_wisotzkey_data_by_cohort <- function(df, out_dir = NULL) {
  cohorts <- c("CHD", "Myocardio", "Combined")
  out <- setNames(
    lapply(cohorts, function(cohort) make_wisotzkey_data(df, cohort = cohort)),
    cohorts
  )
  if (!is.null(out_dir) && (dir.exists(out_dir) || dir.create(out_dir, recursive = TRUE))) {
    for (cohort in cohorts) {
      path <- file.path(out_dir, paste0("wisotzkey_", cohort, ".csv"))
      utils::write.csv(out[[cohort]], path, row.names = FALSE)
      message("Wrote ", path)
    }
  }
  out
}