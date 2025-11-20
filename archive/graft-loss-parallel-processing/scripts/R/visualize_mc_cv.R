##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param mc_cv
visualize_mc_cv <- function(mc_cv) {

  ggdat <- mc_cv %>% 
    mutate(
      model = recode(
        model, 
        rsf = 'Standard random\nsurvival forest',
        orsf = 'Oblique random\nsurvival forest', 
        xgb = 'Gradient\nboosting',
        cph = 'Proportional\nhazards'
      ),
      ftr_selector = recode(
        ftr_selector,
        rsf = 'Predictors selected by permutation importance', 
        xgb = 'Predictors selected by contribution importance',
        cph = 'Predictors selected by stepwise importance'
      ),
    ) %>% 
    pivot_longer(cols = AUC:GND.pvalue) %>% 
    group_by(n_predictors, ftr_selector, model, name) %>% 
    summarize(
      across(
        .cols = value,
        .fns = list(
          est = ~median(.x, na.rm = T),
          lwr = ~quantile(.x, probs = 0.25, na.rm = T),
          upr = ~quantile(.x, probs = 0.75, na.rm = T)
        )
      )
    ) %>% 
    ungroup() %>% 
    filter(name %in% c('AUC', 'GND.pvalue')) %>% 
    mutate(
      model = fct_relevel(
        model, 
        'Oblique random\nsurvival forest', 
        'Standard random\nsurvival forest',
        'Gradient\nboosting',
        'Proportional\nhazards'
      )
    )
  
  gg_objects <- 
    split(ggdat, f = ggdat$name) %>% 
    map(
      ~ ggplot(.x) + 
        aes(x = n_predictors, 
            y = value_est,
            color = model)  + 
        geom_vline(xintercept = 20,
                   linetype = 2, 
                   color = 'black') + 
        geom_line() +
        geom_point() + 
        facet_wrap(~ftr_selector, ncol = 1) +
        theme_bw() + 
        theme(text = element_text(size = 12),
              panel.grid = element_blank()) + 
        labs(
          x = 'Number of predictor variables used in prediction model',
          color = 'Prediction model\ndeveloped using'
        ) +
        scale_color_manual(
          values = c('purple', 'forestgreen', 'orange', 'grey')
        ) + 
        scale_x_sqrt(breaks = c(5, 10, 15, 20, 35, 50, 75))
    )
  
  gg_objects$AUC <- gg_objects$AUC + 
    labs(y = 'Area underneath ROC curve')
  
  gg_objects$GND.pvalue <- gg_objects$GND.pvalue + 
    labs(y = 'P-value for miscalibration')
    
  gg_objects


}
