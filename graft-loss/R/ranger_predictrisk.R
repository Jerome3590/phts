##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param object
##' @param newdata
##' @param times
##' @param ...
ranger_predictrisk <- function (object, newdata, times, ...) {
  
  ptemp <- ranger:::predict.ranger(object, data = newdata, 
                                   importance = "none")$survival
  
  pos <- prodlim::sindex(jump.times = object$unique.death.times,
                         eval.times = times)
  
  p <- cbind(1, ptemp)[, pos + 1, drop = FALSE]
  
  if (NROW(p) != NROW(newdata) || NCOL(p) != length(times))
    stop(
      paste(
        "\nPrediction matrix has wrong dimensions:\nRequested newdata x times: ",
        NROW(newdata),
        " x ",
        length(times),
        "\nProvided prediction matrix: ",
        NROW(p),
        " x ",
        NCOL(p),
        "\n\n",
        sep = ""
      )
    )
  # return risk instead of survival prob
  1 - p
}
