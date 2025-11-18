##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param model
##' @param data
##' @param variable_name
##' @param variable_values
partial_ctns <- function(model, data, variable_name, variable_values = NULL) {

  if(is.null(variable_values)){
    
    variable_values <- quantile(data[[variable_name]],
                                probs = c(0.25, 0.50, 0.75))
    
  }

  .partial(model, data, variable_name, variable_values)

}
