##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param final_model
##' @param final_fata
make_partial_cpbypass <- function(final_model, final_data) {
  # Compute robust quantiles for cpbypass; remove NA and non-finite values
  x <- suppressWarnings(as.numeric(final_data$cpbypass))
  x <- x[is.finite(x)]
  # Use middle quantiles to avoid extreme tails; ignore NAs explicitly
  q <- stats::quantile(x, probs = seq(0.2, 0.8, length.out = 15), na.rm = TRUE, names = FALSE)
  # Keep unique, finite, sorted values
  variable_values <- sort(unique(q[is.finite(q)]))
  # Ensure we have at least two grid points; if not, fallback to median ± IQR endpoints when available
  if (length(variable_values) < 2 && length(x) >= 3) {
    qs <- stats::quantile(x, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, names = FALSE)
    variable_values <- sort(unique(qs[is.finite(qs)]))
  }
  # Final guard: if still <2 points, just return a minimal scaffold handled upstream
  if (length(variable_values) < 2) {
    variable_values <- unique(stats::na.omit(x))[1:min(2, length(unique(stats::na.omit(x))))]
  }

  .partial(
    model = final_model,
    data = final_data,
    variable_name = 'cpbypass',
    variable_values = variable_values
  )
}
