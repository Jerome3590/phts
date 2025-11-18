##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title

make_model_final <- function(phts_all) {


  model <- fit_orsf(trn = pre_proc_ftr_selector, vars = ftrs)
  
  variable_name <- 'cpbypass'
  variable_values <- quantile(pre_proc_ftr_selector[[variable_name]],
                              probs = seq(0.1, 0.9, by = 0.1))
  
  partial <- enframe(variable_values) %>% 
    mutate(variable = variable_name, .before = 1) %>% 
    mutate(prediction = list(NULL))
  
  for(v in seq_along(variable_values)){
    
    trn_pd <- pre_proc_ftr_selector[, ftrs]
    trn_pd[[variable_name]] <- variable_values[v]
    partial$prediction[[v]] <- predict(model, newdata = trn_pd, times = 1)
    
  }
  
  partial %>% 
    mutate(mean = map_dbl(prediction, ~1-median(.x)))
  
  pre_proc_ftr_selector %>% 
    filter(cpbypass > 224) %>% 
    mutate(
      status = if_else(
        status == 1 & time < 1, 
        status, 
        0
      ),
      time = if_else(status == 0, pmin(time, 1), time)
    ) %>% 
    select(time, status) %>% 
    summarize(incidence = sum(status)/sum(time))
  
  
  partial_cats <- phts_all %>% 
    select(all_of(ftrs_as_variables)) %>% 
    select(where(is.factor)) %>% 
    map(levels) %>% 
    enframe(value = 'label') %>% 
    unnest(cols = label) %>% 
    mutate(variable = paste(name, label, sep = '..'),
           .before = label)
  
  partial <- pre_proc_interpretable$steps[[4]]$objects %>% 
    map('breaks') %>% 
    enframe() %>% 
    unnest_wider(value) %>% 
    mutate(
      # cut-point values
      ...1 = map_dbl(name, ~min(phts_all[[.x]], na.rm = TRUE)),
      ...4 = map_dbl(name, ~max(phts_all[[.x]], na.rm = TRUE)),
      bin1 = table_glue("{...1} to <{...2}"),
      bin2 = table_glue("{...2} to <{...3}"),
      bin3 = table_glue("{...3} to <{...4}")
    ) %>% 
    select(name, starts_with('bin')) %>% 
    pivot_longer(cols = starts_with('bin'),
                 names_to = 'bin',
                 values_to = 'label') %>% 
    mutate(variable = glue("{name}..{bin}"),
           .before = label) %>% 
    select(-bin) %>% 
    bind_rows(partial_cats) %>% 
    mutate(values = list(NULL))
  
  counter <- 1 
  
  for(.name in unique(partial$name)) {
    
    for(.variable in unique(partial$variable[partial$name == .name])){
      
      hot_column <- .variable
      
      cold_columns <- setdiff(
        unique(partial$variable[partial$name == .name]),
        .variable
      )
      
      trn_pd <- trn_interpretable
      trn_pd[, hot_column] <- 1
      trn_pd[, cold_columns] <- 0
      
      partial$values[[counter]] <- as.numeric(
        1 - predict(model, newdata = trn_pd, times = 1)
      )
      
      counter <- counter + 1
      
    }
    
  }
  
  boot_median_ratio <- function(numerator, denominator, n_boots){
    
    results <- matrix(0, nrow = n_boots, ncol = length(numerator))
    
    for(i in seq(n_boots)){
      
      boot_index <- sample(x = 1:length(numerator), 
                           size = length(numerator),
                           replace = TRUE)
      
      results[i, ] <- map_dbl(
        .x = numerator,
        .f = ~ median(.x[boot_index]) / median(denominator[boot_index])
      )
      
    }
    
    tibble(
      lwr = apply(results, 2, quantile, probs = 0.025),
      est = apply(results, 2, quantile, probs = 0.500),
      upr = apply(results, 2, quantile, probs = 0.975),
    )

  }
  
  partial %>% 
    group_by(name) %>% 
    summarize(
      label = label,
      boot_vals = boot_median_ratio(numerator = values, 
                                    denominator = values[[1]],
                                    n_boots = 5000)
    ) 
  
  cph_ftrs <- partial %>% 
    group_by(name) %>% 
    slice(-1) %>% 
    pull(variable) %>% 
    intersect(names(trn_interpretable))
  
  cph <- coxph(Surv(time, status) ~ ., 
               data = trn_interpretable[, c('time', 'status', cph_ftrs)])
  
  
}
