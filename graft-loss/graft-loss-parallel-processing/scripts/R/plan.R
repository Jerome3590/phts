
# update methods: 
# emphasize that orsf does not make assumptions on linear relationships

# update table 2: change stub label to "risk factors"

# FORMAT FOR CIRCULATION

# TODO: 
# 1. Please provide a supplementary table for Appendix which lists all 
#    covariates included in the analysis.

# 2. Under Statistical analysis in Methods, you state that “We used 
#    partial dependence to estimate multivariable adjusted predicted risk 
#    as a function of each variable included in the final prediction model, 
#    separately”. I assume this refers to the methodology to create the risk 
#    estimates in Table 3.  Since this is a departure from the “standard” 
#    multivariable model in which other risk factors are either set to a 
#    specific value or to the mean of the cohort, the description  of 
#    “adjusting for other risk factors” needs to be amplified so that the 
#    reader can better understand the method of adjustment.

# 3. (done) Characteristics of patients were calculated as mean with 
#    standard deviation or percent in the overall population and 
#    stratified by transplant year.” Were any continuous variables 
#    expressed as median ( IQR)?

# 4. provide an intuitive RISK-UNADJUSTED display of that by 
#    showing stratified KM curves for some of the critical risk factors, 
#    stratified by quartile. This would be very useful for CPB times,   
#    showing  a KM curve for survival out to 1 year, stratified by 
#    the 4 quartiles.

# 5. Duration of CPB. Include the overall distribution of CPB times, 
#    then look at the duration of CPB in subsets expected to have prolonged 
#    times.  You might display characteristics which were associated with  
#    longer CPB times ( for example by quartiles).  The KM survival curves 
#    could be included here. These details are important to help understand 
#    whether longer CPB time is highly associated with certain patient 
#    groups. Did you look for an interaction with CHD, for example?  
#    Within the cohort of CHD, you could  provide estimates of risk in 
#    the 4 quartiles of CPB  and compare that to the same duration 
#    with CM patients.  

# 6. In Table 1, whenever possible it would be useful to also 
#    include characteristics that came into the final  risk factor 
#    model ( Table 2 and 3).  

# 7. Tables 2 and 3 need a title that indicates the OUTCOME Event that you are predicting. ( Risk factors for post-transplant mortality, etc.)  The “n” for the various cohort columns needs to be included.

# 8. Add N's to all tables.

# 9. Drop height and weight at listing

# 10. add footnote to table 3 defining ratio and difference

# 11. split table 3 into a main table (top 10) and supplement (11-20)

the_plan <- drake_plan(
  
  min_txpl_year = 2010,
  predict_horizon = 1,
  ntimes = 1000, # only used 500 currently
  
  phts_all = clean_phts(
    min_txpl_year = min_txpl_year,
    predict_horizon = predict_horizon,
    time = outcome_int_graft_loss,
    status = outcome_graft_loss,
    case = 'snake', 
    set_to_na = c("", "unknown", "missing")
  ), 
  
  labels = make_labels(colname_variable = 'variable', 
                       colname_label = 'label'),
  
  resamples = mc_cv_light(phts_all, ntimes = ntimes),

  # Slurm code is run between the resamples and mc_cv targets.
  
  mc_cv = load_mc_cv(),
  
  fig_mc_cv_vals = visualize_mc_cv(mc_cv),
  
  fig_mc_cv_inf = visualize_mc_cv_inference(mc_cv, 
                                            ftr_method = 'rsf',
                                            n_pred = 20),
  
  
  final_features = make_final_features(phts_all),
  
  top10_features = final_features$variables[1:10],
  other_features = final_features$variables[-c(1:10)],
  
  fig_prim_dx = visualize_prim_dx(phts_all),
  fig_cpbypass = visualize_cpbypass(phts_all),
  fig_txecmo = visualize_txecmo(phts_all),
  fig_hxsurg = visualize_hxsurg(phts_all),
  
  fig_final_features = visualize_final_features(fig_prim_dx,
                                                fig_cpbypass,
                                                fig_txecmo,
                                                fig_hxsurg),
  
  final_recipe = prep(make_recipe(phts_all, dummy_code = FALSE)),
  
  final_data = juice(final_recipe),
  
  final_model = fit_orsf(
    trn = final_data,
    vars = final_features$variables
  ),
  
  final_partial = make_final_partial(final_model = final_model, 
                                     final_data = final_data, 
                                     final_features = final_features),
  
  partial_cpbypass = make_partial_cpbypass(final_model,
                                           final_data),
  
  partial_table_data = make_partial_table_data(final_partial, labels),
  
  tbl_one = tabulate_characteristics(phts_all, 
                                     labels, 
                                     top10_features),
  
  tbl_predictor_smry = tabulate_predictor_smry(phts_all, labels),
  
  
  tbl_variables = tabulate_missingness(final_recipe, 
                                       phts_all, 
                                       final_features, 
                                       labels),
  
  tbl_partial_main = tabulate_partial_table_data(partial_table_data,
                                                 top10_features),
  
  tbl_partial_supp = tabulate_partial_table_data(partial_table_data,
                                                 other_features)
  
)

# fig_mc_cv_vals$AUC$data %>% 
#   dplyr::filter(ftr_selector == 'Predictors selected by permutation importance') %>% 
#   readr::write_rds("../../seminar - obliqueRSF/data_phts_auc.rds")
# 
# fig_mc_cv_vals$GND.pvalue$data %>% 
#   dplyr::filter(ftr_selector == 'Predictors selected by permutation importance') %>% 
#   readr::write_rds("../../seminar - obliqueRSF/data_phts_gnd.rds")

