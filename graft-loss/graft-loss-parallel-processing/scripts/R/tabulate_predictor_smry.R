##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param phts_all
##' @param labels
tabulate_predictor_smry <- function(phts_all, labels) {

  tbl_data <- phts_all %>% 
    select(-ID, -starts_with('rrace'), -time, -status) %>%
    map_chr(class) %>% 
    enframe(name = 'variable', value = 'type') %>% 
    mutate(
      type = recode(
        type,
        'integer' = 'Continuous',
        'numeric' = 'Continuous',
        'factor' = 'Categorical',
        'character' = 'Categorical')
    ) %>% 
    left_join(labels$variables) %>% 
    mutate(label = str_remove(label, 'F[0-9] ')) %>%
    split(.$type) %>% 
    map(select, -type)
  
  ft_catg <- tbl_data$Categorical %>% 
    mutate(smry = map_chr(variable, catg_fun, data = phts_all)) %>% 
    flextable(col_keys = c('label', 'smry')) %>% 
    theme_box() %>% 
    set_header_labels(
      label = 'Categorical predictor variable',
      smry = 'Count (percent)'
    ) %>% 
    width(j = 'smry', width = 2.5) %>% 
    width(j = 'label', width = 3)
  
  ft_ctns <- tbl_data$Continuous %>% 
    mutate(
      smry_msd = map_chr(variable, mnsd_fun, data = phts_all),
      smry_mqr = map_chr(variable, miqr_fun, data = phts_all)
    ) %>% 
    flextable(col_keys = c('label', 'smry_msd', 'smry_mqr')) %>% 
    theme_box() %>% 
    set_header_labels(
      label = 'Categorical predictor variable',
      smry_msd = 'Mean\n(standard deviation)',
      smry_mqr = 'Median\n(25th, 75th percentile)'
    ) %>% 
    width(j = 'label', width = 2) %>% 
    width(j = c('smry_msd', 'smry_mqr'), width = 2) %>% 
    align(j = c('smry_msd', 'smry_mqr'),
          align = 'center', 
          part = 'all')
  
  
  list(continuous = ft_ctns,
       categorical = ft_catg)
    

}

catg_fun <- function(x, data){
  
  .x <- data[[x]]
  
  counts <- table(.x)
  props <- 100 * prop.table(counts)
  
  names(counts) <- str_replace_all(names(counts), '_', ' ')
  
  tbl_values <- rep(NA_character_, length(counts))
  
  for(i in seq_along(tbl_values)){
    tbl_values[i] <- table_glue(
      "- {capitalize(names(counts)[i])}: {counts[i]} ({props[i]}%)"
    )
  }
  
  paste(tbl_values, collapse = '\n')
  
}

mnsd_fun <- function(x, data, na.rm = TRUE){
  
  .x <- data[[x]]
  
  .mean <- mean(.x, na.rm = na.rm)
  .sd <- sd(.x, na.rm = na.rm)
  
  table_glue("{.mean}\n({.sd})")
  
}

miqr_fun <- function(x, data, na.rm = TRUE){
  
  .x <- data[[x]]
  
  .median <- median(.x, na.rm = na.rm)
  .upr <- quantile(.x, probs = 3/4, na.rm = na.rm)
  .lwr <- quantile(.x, probs = 1/4, na.rm = na.rm)
  
  table_glue("{.median}\n({.lwr}, {.upr})")
  
}

miss_fun <- function(x, data){
  
  x_na <- is.na(x)
  n_miss <- sum(x_na)
  p_miss <- mean(x_na)
  
  table_glue("{n_miss} ({p_miss})")
  
}