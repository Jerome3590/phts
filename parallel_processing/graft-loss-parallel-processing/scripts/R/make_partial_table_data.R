##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param partial_final
##' @param labels
make_partial_table_data <- function(partial_final, labels) {

  label_vec <- deframe(labels$variables)
  
  map_dfr(.x = partial_final, 
          .f = .partial_table_data, 
          labels = labels) %>% 
    mutate(label = recode(variable, !!!label_vec))
    

}

.partial_table_data <- function(.x, labels){
  
  switch(
    class(.x$value)[1],
    'factor' = make_partial_table_data_catg(.x, labels$categories),
    'character' = make_partial_table_data_catg(.x, labels$categories),
    'numeric' = make_partial_table_data_ctns(.x)
  )
  
}


make_partial_table_data_catg <- function(.x, label_data){
  
  label_vec <- deframe(label_data)
  
  output <- .x %>% 
    transmute(
      variable, 
      value = dplyr::recode(value, !!!label_vec, .default = as.character(value)),
      prev = table_glue("{100*est_prev} ({100*lwr_prev}, {100*upr_prev})"),
      ratio = table_glue("{est_ratio} ({lwr_ratio}, {upr_ratio})"),
      diff = table_glue("{100*est_diff} ({100*lwr_diff}, {100*upr_diff})")
    )
  
  output$ratio[1] <- "1 (Reference)"
  output$diff[1] <- "0 (Reference)"
  
  output
  
}

make_partial_table_data_ctns <- function(.x){
  
  output <- .x %>% 
    mutate(
      name = str_replace(name, '\\%', 'th percentile')
    ) %>% 
    transmute(
      variable, 
      value = table_glue("{name}: {value}"),
      prev = table_glue("{100*est_prev} ({100*lwr_prev}, {100*upr_prev})"),
      ratio = table_glue("{est_ratio} ({lwr_ratio}, {upr_ratio})"),
      diff = table_glue("{100*est_diff} ({100*lwr_diff}, {100*upr_diff})")
    )
  
  output$ratio[1] <- "1 (Reference)"
  output$diff[1] <- "0 (Reference)"
  
  output
  
}