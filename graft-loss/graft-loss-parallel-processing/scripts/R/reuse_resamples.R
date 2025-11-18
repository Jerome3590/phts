#' Reuse base resample splits across filtered datasets
#'
#' @param data A data.frame with an ID column
#' @param base_id_splits list of integer or character vectors of patient IDs (test indices) from base run
#' @param min_test_n minimal number of test rows to retain split
#' @param min_test_events minimal number of events (status==1) required in test set
#' @param status_col name of status column
#' @return list of integer vectors (row indices relative to `data`) suitable as testing rows
reuse_resamples <- function(data,
                             base_id_splits,
                             min_test_n = 25,
                             min_test_events = 1,
                             status_col = 'status') {
  stopifnot('ID' %in% names(data))
  id_map <- setNames(seq_len(nrow(data)), data$ID)
  out <- list()
  kept <- 0L
  for (i in seq_along(base_id_splits)) {
    ids <- base_id_splits[[i]]
    # map ids present in subset
    present <- id_map[as.character(ids)]
    present <- present[!is.na(present)]
    if (length(present) >= min_test_n) {
      tst_df <- data[present, , drop = FALSE]
      events <- sum(tst_df[[status_col]] == 1, na.rm = TRUE)
      if (events >= min_test_events) {
        kept <- kept + 1L
        out[[kept]] <- present
      }
    }
  }
  class(out) <- c('list')
  out
}
