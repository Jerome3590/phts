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
  # Try multiple predict.ranger parameter names to remain compatible across ranger versions.
  # Collect error messages for diagnostics if all attempts fail.
  ptemp <- NULL
  err_msgs <- character(0)

  # 1) Preferred modern interface: new_data
  ptemp <- tryCatch({
    ranger:::predict.ranger(object, new_data = newdata, importance = "none")$survival
  }, error = function(e) {
    err_msgs <<- c(err_msgs, paste0("new_data: ", e$message)); NULL
  })

  # 2) Older interface: data
  if (is.null(ptemp)) {
    ptemp <- tryCatch({
      ranger:::predict.ranger(object, data = newdata, importance = "none")$survival
    }, error = function(e) {
      err_msgs <<- c(err_msgs, paste0("data: ", e$message)); NULL
    })
  }

  # 3) Legacy interface: newdata
  if (is.null(ptemp)) {
    ptemp <- tryCatch({
      ranger:::predict.ranger(object, newdata = newdata, importance = "none")$survival
    }, error = function(e) {
      err_msgs <<- c(err_msgs, paste0("newdata: ", e$message)); NULL
    })
  }

  if (is.null(ptemp)) {
    stop(sprintf("ranger_predictrisk: unable to call predict.ranger using any known arg names. Attempts: %s",
                 paste(err_msgs, collapse = " | ")))
  }
  
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
