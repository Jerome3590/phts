##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param final_model
##' @param final_data
##' @param final_features
make_final_partial <- function(
  final_model,
  final_data,
  final_features,
  variables = final_features$variables,
  n_boots = 200,
  max_levels = 5,
  numeric_probs = c(0.25, 0.5, 0.75)
) {

  vars <- intersect(variables, names(final_data))

  # Helper to coerce prediction outputs to a numeric vector
  to_num_vec <- function(p) {
    if (is.null(p)) return(NA_real_)
    if (is.list(p) && length(p) == 1) p <- p[[1]]
    if (is.matrix(p)) return(as.numeric(p[, 1]))
    if (is.data.frame(p)) return(as.numeric(p[[1]]))
    suppressWarnings(as.numeric(p))
  }

  # per-variable timeout in seconds to avoid stalling entire run
  var_timeout <- 90

  results <- purrr::imap(
    .x = vars,
    .f = function(var_name, idx) {
      message(sprintf("[make_final_partial] %s/%s: %s", idx, length(vars), var_name))

      x <- final_data[[var_name]]

      # Choose a small grid of values to evaluate
      if (is.numeric(x)) {
        # If numeric binary (exactly two unique observed values), evaluate both levels
        ux <- sort(unique(stats::na.omit(x)))
        if (length(ux) == 2L) {
          variable_values <- ux
        } else {
          variable_values <- unique(stats::quantile(x, probs = numeric_probs, na.rm = TRUE))
        }
        # ensure at least two distinct values
        if (length(variable_values) < 2) {
          message(sprintf("[make_final_partial] skipping %s: <2 numeric grid points", var_name))
          return(NULL)
        }
      } else {
        # For categorical/text, limit to most frequent non-missing levels
        lvls <- sort(table(stats::na.omit(x)), decreasing = TRUE) %>% names()
        if (length(lvls) > max_levels) lvls <- lvls[seq_len(max_levels)]
        # ensure at least two levels
        if (length(lvls) < 2) {
          message(sprintf("[make_final_partial] skipping %s: <2 categorical levels", var_name))
          return(NULL)
        }
        variable_values <- lvls
      }

      # Compute partial predictions safely with a per-variable timeout
      out <- tryCatch({
        R.utils::withTimeout({
          pr <- partial(
            model = final_model,
            data = final_data,
            variable_name = var_name,
            variable_values = variable_values
          )
          # Coerce predictions to numeric vectors before bootstrapping
          pr <- pr %>% mutate(prediction = purrr::map(prediction, to_num_vec))
          # Reference is the first scenario's numeric vector
          pr <- pr %>%
            mutate(
              tmp = list(prediction[[1]]),
              boot_results = purrr::map2(tmp, prediction, ~ partial_boot(.x, .y, n_boots = n_boots)),
              name = as.character(name),
              across(where(is.factor), as.factor)
            ) %>%
            unnest_wider(boot_results) %>%
            select(-prediction, -tmp)
          pr
        }, timeout = var_timeout, onTimeout = "error")
      }, error = function(e) {
        message(sprintf("[make_final_partial] WARNING: failed on %s with error: %s", var_name, conditionMessage(e)))
        # Return a minimal row per value with NAs so upstream can continue
        tibble::tibble(
          variable = var_name,
          name = as.character(variable_values),
          lwr_prev = NA_real_, upr_prev = NA_real_, est_prev = NA_real_,
          lwr_ratio = NA_real_, upr_ratio = NA_real_, est_ratio = NA_real_,
          lwr_diff = NA_real_, upr_diff = NA_real_, est_diff = NA_real_
        )
      })
      out
    }
  )

  purrr::compact(results)

}
