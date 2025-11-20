##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param phts_all
visualize_hxsurg <- function(phts_all) {

  incidence <- cuminc(ftime   = phts_all$time, 
                      fstatus = phts_all$status,
                      group   = phts_all$hxsurg,
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
                          lab_color = 'Surgeries prior\nto listing',
                          legend_position = c(.15, .75), 
                          legend_direction = 'vertical')

}
