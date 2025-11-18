##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param linpred
make_contrasts <- function(linpred) {

  rslt_contrast <- tibble(contrast = character(), 
                          estimate = double(),
                          lower = double(),
                          upper = double(),
                          prob_gt_0 = double())
  
  grid <- expand.grid(
    m1 = names(linpred),
    m2 = names(linpred),
    stringsAsFactors = FALSE
  ) %>% 
    as_tibble()
  
  for(i in seq(nrow(grid))){
    
    m1 <- linpred[, grid$m1[i], drop = TRUE]
    m2 <- linpred[, grid$m2[i], drop = TRUE]
    
    rslt_contrast <- rslt_contrast %>% 
      add_row(
        contrast = paste(grid$m1[i], grid$m2[i], sep = '_minus_'),
        estimate = median(m1 - m2),
        lower = quantile(m1 - m2, probs = 0.025),
        upper = quantile(m1 - m2, probs = 0.975),
        prob_gt_0 = mean(m1 - m2 > 0)
      )
    
  }
  
  rslt_contrast
  

}
