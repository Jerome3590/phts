##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param model
##' @param data
##' @param variable_name
##' @param variable_values
partial <- function(model, data, variable_name, variable_values = NULL) {
  
  variable <- data[[variable_name]]
  variable_unique_count <- length(unique(na.omit(variable)))
  
  if(variable_unique_count <= 3)
    return(partial_catg(model, data, variable_name, variable_values))
  
  if(is.numeric(variable)) 
    return(partial_ctns(model, data, variable_name, variable_values))
  
  if(is.factor(variable) || is.character(variable))
    return(partial_catg(model, data, variable_name, variable_values))
  
  stop("unsupported type", call. = FALSE)
  
}

##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param model
##' @param data
##' @param variable_name
##' @param variable_values
.partial <- function(model, data, variable_name, variable_values){

  # guard: need at least two values to form contrasts sensibly
  if (length(variable_values) < 2) {
    return(enframe(variable_values) %>%
             mutate(variable = variable_name, .before = 1) %>%
             mutate(prediction = list(NA_real_)))
  }

  original <- data[[variable_name]]
  n_rows <- nrow(data)
  n_vals <- length(variable_values)

  # Build a single stacked data.frame with an index for each scenario
  build_stack <- function(vals) {
    # replicate data n_vals times without deep copy of columns where possible
    df <- data[rep(seq_len(n_rows), times = n_vals), , drop = FALSE]
    # assign scenario id
    df$.__scenario_id__. <- rep(seq_len(n_vals), each = n_rows)
    # set variable according to scenario, preserving type
    if (is.factor(original)) {
      df[[variable_name]] <- factor(
        rep(vals, each = n_rows),
        levels = levels(original)
      )
    } else if (is.character(original)) {
      df[[variable_name]] <- rep(as.character(vals), each = n_rows)
    } else {
      df[[variable_name]] <- rep(vals, each = n_rows)
    }
    df[[variable_name]] <- type.convert(df[[variable_name]], as.is = TRUE)
    df
  }

  df_stack <- build_stack(variable_values)

  # Vectorized prediction over the entire stack
  safe_predict_vec <- function(df) {
    out <- tryCatch({
      p <- predict(model, newdata = df, times = 1)
      # normalize to numeric vector of risk; if p are survival probabilities, use 1 - p
      if (is.list(p) && !is.null(p$predictions)) p <- p$predictions
      if (is.matrix(p)) p <- p[, 1, drop = TRUE]
      p <- suppressWarnings(as.numeric(p))
      # If predictions look like survival probs (0..1), convert to risk
      if (all(is.finite(p))) {
        # heuristic: if in [0,1], treat as survival prob
        if (min(p, na.rm = TRUE) >= 0 && max(p, na.rm = TRUE) <= 1) {
          p <- 1 - p
        }
      }
      p
    }, error = function(e) {
      # fallback without times
      p <- tryCatch(predict(model, newdata = df), error = function(e2) NA_real_)
      if (is.list(p) && !is.null(p$predictions)) p <- p$predictions
      if (is.matrix(p)) p <- p[, 1, drop = TRUE]
      suppressWarnings(as.numeric(p))
    })
    out
  }

  p_vec <- safe_predict_vec(df_stack)

  # Split back into list of length(variable_values), each length n_rows
  # Guard against length mismatches
  if (length(p_vec) != nrow(df_stack)) {
    # return NAs to match expected structure
    preds <- replicate(n_vals, rep(NA_real_, n_rows), simplify = FALSE)
  } else {
    preds <- split(p_vec, df_stack$.__scenario_id__.)
  }

  enframe(variable_values) %>%
    mutate(variable = variable_name, .before = 1) %>%
    mutate(prediction = preds)

}
