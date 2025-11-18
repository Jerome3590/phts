##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @param trn 
##' @param tst 
##' @param return_fit 
##' @param predict_horizon 
##' @param n_predictors 
##'
##' @title
fit_rsf <- function(trn,
                    vars,
                    tst = NULL,
                    predict_horizon = NULL) {
  # Threading: honor MC_WORKER_THREADS (default 1)
  threads <- suppressWarnings(as.integer(Sys.getenv("MC_WORKER_THREADS", unset = "1")))
  if (!is.finite(threads) || threads < 1) threads <- 1L
  
  ntree <- suppressWarnings(as.integer(Sys.getenv("RSF_NTREES", unset = "1000")))
  if (!is.finite(ntree) || ntree < 1) ntree <- 1000L
  model <- ranger(
    formula = Surv(time, status) ~ .,
    data = trn[, c('time', 'status', vars)],
    num.trees = ntree,
    min.node.size = 10,
    splitrule = 'C',
    num.threads = threads
  )
  
  if(is.null(tst)) return(model)
  
  if(is.null(predict_horizon)) stop("specify prediction horizon", call. = F)
  
  ranger_predictrisk(model, 
                     newdata = tst, 
                     times = predict_horizon)

}


