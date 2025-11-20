##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param predicted_risk
##' @param predict_horizon
##' @param score_data
##' @param fit_label
fit_evaluation <- function(predicted_risk, 
                           predict_horizon, 
                           score_data){
  
  evaluation <- Score(
    object = list(predicted_risk),
    formula = Surv(time, status) ~ 1, 
    summary = 'IPA',
    data = score_data, 
    times = predict_horizon, 
    se.fit = FALSE
  )
  
  do_over <- TRUE
  too_few_groups <- FALSE
  group_count <- 10
  
  while(do_over){
    
    # cut2 imported from Hmisc
    groups = as.numeric(cut2(predicted_risk, g = group_count))
    
    status_before_horizon <- score_data$status
    status_before_horizon[score_data$time < predict_horizon] <- 0
    
    group_event_counts <- 
      table(groups = groups, status = status_before_horizon) %>% 
      as_tibble() %>% 
      filter(status == 1)
    
    if(all(group_event_counts$n > 5)){
      do_over <- FALSE
    }
    
    group_count <- group_count - 1
    
    if(group_count == 1){
      too_few_groups <- TRUE
      do_over <- FALSE
    } 
    
  }
  
  if(too_few_groups){
    
    GND_fail <- TRUE
    GND.result <- NULL
    
    
  } else {
    
    GND.result <- try(GND.calib(
      pred = predicted_risk,
      tvar = score_data$time,
      out = score_data$status,
      cens.t = predict_horizon,
      groups = groups,
      adm.cens = predict_horizon
    ), silent = TRUE)
    
    GND_fail <- inherits(GND.result, 'try-error')
    
  }
  
  
  AUC <- evaluation$AUC$score$AUC
  IPA <- evaluation$Brier$score$IPA[2]
  
  if(GND_fail){
    
    GND.chisq <- NA_real_
    GND.pvalue <- NA_real_
    
  } else {
    
    GND.chisq <- GND.result['chi2gw']
    GND.pvalue <- GND.result['pvalgw']
    
  }

  tibble(
    AUC = AUC, 
    IPA = IPA, 
    GND.chisq = GND.chisq, 
    GND.pvalue = GND.pvalue
  )
  
}
