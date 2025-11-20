##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param partial_table_data
tabulate_partial_table_data <- function(partial_table_data,
                                        features) {

  ft <- partial_table_data %>% 
    filter(variable %in% features) %>% 
    select(-variable) %>% 
    as_grouped_data(groups = 'label') %>% 
    as_flextable(hide_grouplabel = TRUE) %>% 
    add_header_row(
      values = c('', '1-year predicted risk for graft loss or mortality'),
      colwidths = c(1, 3)
    ) %>% 
    set_header_labels(
      value = 'Characteristic',
      prev = 'Risk (95% CI)',
      ratio = 'Ratio (95% CI)',
      diff = 'Difference (95% CI)'
    ) %>% 
    theme_box() %>% 
    width(width = 1.5) %>% 
    width(j = 1, width = 2) %>% 
    align(align = 'center', part = 'all') %>% 
    align(j = 1, align = 'left') %>% 
    font(fontname = 'Times New Roman', part = 'all') %>% 
    fontsize(size = 12, part = 'all')
  
  inline <- partial_table_data %>% 
    select(-label) %>% 
    mutate(
      value = str_replace(value, '(^[0-9])', 'p\\1'),
      value = str_remove(value, ' percentile'),
      value = str_replace_all(value, ' ', '_'),
      value = str_remove_all(value, '\\:_([0-9]+)$'),
      value = str_remove_all(value, '\\:_([0-9]+\\.[0-9]+)$'),
      value = str_remove(value, 'th$')
    ) %>% 
    as_inline(tbl_variables = c('variable', 'value'),
              tbl_values = c('prev', 'ratio', 'diff'))

  list(table = ft, inline = inline)
  
  
}
