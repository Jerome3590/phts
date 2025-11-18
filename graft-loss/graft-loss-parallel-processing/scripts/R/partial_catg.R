##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param model
##' @param data
##' @param variable_name
##' @param variable_values
partial_catg <- function(model, data, variable_name, variable_values = NULL) {

  if(is.null(variable_values)){
    # exclude NA levels
    variable_values <- sort(unique(stats::na.omit(data[[variable_name]])))
  }

  # ensure at least two values; otherwise return a placeholder to be handled upstream
  if (length(variable_values) < 2) {
    return(enframe(variable_values) %>%
             mutate(variable = variable_name, .before = 1) %>%
             mutate(prediction = list(NA_real_)))
  }
  
  .partial(model, data, variable_name, variable_values)

}


