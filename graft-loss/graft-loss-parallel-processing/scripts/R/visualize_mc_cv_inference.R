##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param xgb
##' @param step
visualize_mc_cv_inference <- function(mc_cv, 
                                      ftr_method = 'rsf',
                                      n_pred = 20) {
  
  mc_cv_inference_data <- mc_cv %>% 
    filter(n_predictors == n_pred,
           ftr_selector == ftr_method) 
  
  model_auc = stan_lmer(
    formula = AUC ~ model + (1 | resample_iteration), 
    data = mc_cv_inference_data, 
    iter = 4000
  )
  
  model_gnd <- stan_lmer(
    formula = GND.pvalue ~ model + (1 | resample_iteration),
    data = mc_cv_inference_data,
    iter = 4000
  )
  
  newdata = tibble(model = unique(mc_cv_inference_data$model))
  
  .colnames <- unique(newdata$model)
  if(length(.colnames) < 2){
    warning('visualize_mc_cv_inference: fewer than 2 models available; skipping contrasts and returning posterior summaries only.')
  }
  
  linpred_auc <- posterior_predict(
    object = model_auc, 
    re.form = NA, 
    newdata = newdata
  ) %>% 
    set_colnames(.colnames) %>% 
    as_tibble() %>% 
    mutate_all(as.numeric)
  
  linpred_gnd <- posterior_predict(
    object = model_gnd, 
    re.form = NA, 
    newdata = newdata
  ) %>% 
    set_colnames(.colnames) %>% 
    as_tibble() %>% 
    mutate_all(as.numeric)
  
  linpreds <- bind_rows(auc = linpred_auc, 
                        gnd = linpred_gnd,
                        .id = 'metric') %>% 
    pivot_longer(cols = -metric, names_to = 'model') %>% 
    group_by(metric, model) %>% 
    summarize(estimate = median(value)) %>% 
    rename(ref = model) %>% 
    mutate(
      exp = ref,
      label = if_else(
        metric == 'auc',
        table_glue("AUC: {100*estimate}"),
        table_glue("P: {estimate}")
  )
    )
  
  contrasts <- NULL
  if(length(.colnames) >= 2){
    contrasts <- bind_rows(auc = make_contrasts(linpred_auc),
                           gnd = make_contrasts(linpred_gnd),
                           .id = 'metric') %>%
      separate(contrast, into = c('ref', 'exp'), sep = '_minus_') %>%
      mutate(
        ref = factor(ref, levels = c('orsf', 'xgb', 'rsf', 'cph')),
        exp = factor(exp, levels = c('orsf', 'xgb', 'rsf', 'cph')),
        ref_nmr = as.numeric(ref),
        exp_nmr = as.numeric(exp)
      ) %>%
      select(-lower, -upper)
  }
  
  plot_data <- NULL
  if(!is.null(contrasts)){
    contrasts_auc <- contrasts %>%
      filter(metric == 'auc', ref_nmr > exp_nmr) %>%
      mutate(estimate = estimate * -1,
             prob_gt_0 = 1 - prob_gt_0) %>%
      select(-ends_with('nmr'))
    contrasts_cal <- contrasts %>%
      filter(metric == 'gnd', ref_nmr < exp_nmr) %>%
      select(-ends_with('nmr'))
    plot_data <- bind_rows(
      contrasts_auc,
      contrasts_cal
    ) %>%
      mutate(
        label = if_else(
          metric == 'auc',
          table_glue("Difference: {100*estimate}\nP({toupper(exp)} > {toupper(ref)}): {prob_gt_0}"),
          table_glue("Difference: {estimate}\nP({toupper(ref)} > {toupper(exp)}): {prob_gt_0}")
        ),
        prob_gt_0_numeric = prob_gt_0,
        prob_gt_0 = cut(x = prob_gt_0,
                        breaks = c(0.00, 0.50, 0.75, 0.95, 1),
                        labels = c("0 to 0.50",
                                   "> 0.50 to 0.75",
                                   "> 0.75 to 0.95",
                                   "> 0.95"))
  )
  }
  
  center_data <- linpreds %>%
    filter(metric == 'auc') %>%
    mutate(label = toupper(ref))
  
  inline_linpreds <- linpreds %>%
    mutate(estimate = round(estimate, 3)) %>%
    as_inline(tbl_variables = c('metric', 'ref'),
              tbl_value = 'estimate')
  
  inline_plot_data <- plot_data %>%
    mutate(estimate = round(estimate, 3),
           prob_gt_0_numeric = round(prob_gt_0_numeric, 3)) %>% 
    as_inline(tbl_variables = c("metric", "ref", "exp"),
              tbl_values = c("estimate", "prob_gt_0_numeric"))
  
  inline <- list(plot_center = inline_linpreds,
                 plot_sides = inline_plot_data)
  
  fig <- NULL
  if(!is.null(plot_data)){
    fig <- ggplot(plot_data) +
      aes(x = exp, y = ref, fill = prob_gt_0, label = label) +
      geom_tile() +
      geom_text(size = 3.5) +
      geom_text(data = filter(linpreds, metric == 'auc'),
                aes(x = exp, y = ref, label = label),
                inherit.aes = FALSE,
    hjust = 0.9,
    vjust = -2.5,
                size = 3.5) +
      geom_text(data = filter(linpreds, metric == 'gnd'),
                aes(x = exp, y = ref, label = label),
                inherit.aes = FALSE,
    hjust = -0.25,
    vjust = 3.3,
    size = 3.5) +
      geom_text(data = center_data,
                aes(x = exp, y = ref, label = label),
                inherit.aes = FALSE,
                size = 5) +
      theme_void() +
      labs(fill = 'Posterior probability') +
      theme(text = element_text(size = 12),
            legend.key.size = unit(1/2, 'in'),
            legend.position = 'top',
      legend.justification = 'center') +
      scale_fill_jama(alpha = 1/2)
  }
  
  list(
    inline = inline, 
    figure = fig,
    contrasts = contrasts
  )
  
}



