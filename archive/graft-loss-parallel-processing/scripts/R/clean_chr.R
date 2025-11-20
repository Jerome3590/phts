##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param x
##' @param case
##' @param set_to_na
clean_chr <- function(x, case = 'snake', set_to_na = ''){
  
  x[tolower(x) %in% tolower(set_to_na)] <- NA_character_
  
  ux <- unique(na.omit(x))
  ux_clean <- make_clean_names(ux, case = case)
  names(ux_clean) <- ux
  recode(x, !!!ux_clean)
  
}
