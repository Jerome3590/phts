##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param trn
##' @param vars
##' @param tst
##' @param predict_horizon
fit_cph <- function(trn, vars = NULL, tst, predict_horizon = NULL) {

  model <- safe_coxph(
    data = trn[, c(vars, 'time', 'status')],
    x = TRUE
  )
  
  if(is.null(tst)) return(model)
  
  if(is.null(predict_horizon)) stop("specify prediction horizon", call. = F)
  
  predictRisk(model, newdata = tst[, vars], times = predict_horizon)
  

}
