##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param phts_all
visualize_cpbypass <- function(phts_all) {

  breaks <- c(0, 180, 500)
  
  data_cpbypass <- phts_all %>% 
    mutate(cpbypass = cut(cpbypass, breaks=breaks, include.lowest=T,
                          labels = c("< 3 hours", "3+ hours"))) %>%
    select(time, status, cpbypass)
  
  incidence <- cuminc(ftime   = data_cpbypass$time, 
                      fstatus = data_cpbypass$status,
                      group   = data_cpbypass$cpbypass,
                      cencode = 0)
  
  data_gg <- incidence[-length(incidence)] %>% 
    map_dfr(~as.data.frame(.x[c('time', 'est', 'var')]),
            .id = 'name') %>% 
    mutate(name = str_remove(name, ' [0-9]$'),
           ci_lwr = est + sqrt(var) * qnorm(0.025),
           ci_upr = est + sqrt(var) * qnorm(0.975),
           name = fct_reorder2(name, .x = time, .y = est))
  
  n_cats <- length(unique(data_gg$name))
  colors <- c("purple", "orange", "grey")
  
  plot_pred_variable_smry(data_gg, n_cats, colors,
                          legend_position = c(0.3, 0.8), 
                          lab_color = 'Cardiopulmonary bypass time')

}
