##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param phts_all
visualize_prim_dx <- function(phts_all) {

  data_prim_dx <- phts_all %>% 
    mutate( 
      prim_dx = fct_collapse(
        prim_dx,
        'Congenital heart\ndisease or other' = c('congenital_hd', 'other'),
        'Cardiomyopathy' = 'cardiomyopathy'
      )
    ) %>% 
    select(time, status, prim_dx)
      
  incidence <- cuminc(ftime   = data_prim_dx$time, 
                      fstatus = data_prim_dx$status,
                      group   = data_prim_dx$prim_dx,
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
                          lab_color = 'Primary diagnosis')

}
