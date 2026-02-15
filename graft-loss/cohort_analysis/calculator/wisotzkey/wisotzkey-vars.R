make_wisotzkey_data <- function(df){  
  df %>% 
    filter(
      PRIM_DX %in% c("Congenital HD", "Cardiomyopathy") # Myocarditis
    ) %>%
    #: manual calculation
    mutate(
      BMI_TXPL = 703 * WEIGHT_TXPL / (HEIGHT_TXPL)^2,
      eGFR_TXPL = 0.413 * (HEIGHT_TXPL*2.54) / pmax(TXCREAT_R, .001) 
    ) %>% 
    transmute(
      
      #: outcomes
      outcome,
      
      #: Diagnosis
      # PRIM_DX,
      CHD = 1*(PRIM_DX == "Congenital HD"),
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