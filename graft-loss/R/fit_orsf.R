##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param trn
##' @param vars
##' @param tst
##' @param predict_horizon
fit_orsf <- function(trn,
                     vars,
                     tst = NULL,
                     predict_horizon = NULL) {
    # ORSF uses aorsf which relies on R's parallel/BLAS; threads capped via env in step 04.
  ntree <- suppressWarnings(as.integer(Sys.getenv("ORSF_NTREES", unset = "1000")))
  if (!is.finite(ntree) || ntree < 1) ntree <- 1000L
  model <- ORSF(trn[, c('time', 'status', vars)], ntree = ntree)
  
  if(is.null(tst)) return(model)
  
  if(is.null(predict_horizon)) stop("specify prediction horizon", call. = F)
  
  1 - predict(model,
              newdata = tst[, c('time', 'status', vars)],
              times = predict_horizon)
  
  
}
