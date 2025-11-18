source("scripts/00_setup.R")

min_txpl_year <- 2010
predict_horizon <- 1

phts_all <- clean_phts(
  min_txpl_year = min_txpl_year,
  predict_horizon = predict_horizon,
  time = outcome_int_graft_loss,
  status = outcome_graft_loss,
  case = 'snake',
  set_to_na = c("", "unknown", "missing")
)

labels <- make_labels(colname_variable = 'variable', colname_label = 'label')

# Coverage logging and optional period exclusions
cov_before <- NA
if ("txpl_year" %in% names(phts_all)) {
  yrs <- phts_all$txpl_year
  yrs <- yrs[is.finite(yrs)]
  if (length(yrs)) {
    cov_before <- c(min = min(yrs), max = max(yrs))
    message(sprintf("Year coverage (pre-filter): %d-%d", cov_before[["min"]], cov_before[["max"]]))
  }
}

# Original study period filter (2010–2019) takes precedence over EXCLUDE_COVID
original_study <- tolower(Sys.getenv("ORIGINAL_STUDY", "0")) %in% c("1","true","yes","y")
if (original_study) {
  n0 <- nrow(phts_all)
  if ("txpl_year" %in% names(phts_all)) {
    phts_all <- dplyr::filter(phts_all, txpl_year >= 2010 & txpl_year <= 2019)
    n1 <- nrow(phts_all)
    message(sprintf("Original study period applied: kept years 2010-2019; rows kept=%d; removed=%d", n1, n0 - n1))
  } else {
    message("ORIGINAL_STUDY requested but 'txpl_year' not found; no rows filtered.")
  }
} else {
  # Optional COVID exclusion (approx by year)
  exclude_covid <- tolower(Sys.getenv("EXCLUDE_COVID", "0")) %in% c("1","true","yes","y")
  if (exclude_covid) {
  n0 <- nrow(phts_all)
  # Precise month-level exclusion not available in current dataset; approximate by year 2020-2023 inclusive
  if ("txpl_year" %in% names(phts_all)) {
    phts_all <- dplyr::filter(phts_all, !(txpl_year >= 2020 & txpl_year <= 2023))
    n1 <- nrow(phts_all)
    message(sprintf("COVID exclusion applied (approx): removed years 2020-2023; rows removed=%d; remaining=%d", n0 - n1, n1))
  } else {
    message("EXCLUDE_COVID requested but 'txpl_year' not found; no rows filtered.")
  }
  }
}

if (!is.na(cov_before)[1] && "txpl_year" %in% names(phts_all)) {
  yrs2 <- phts_all$txpl_year
  yrs2 <- yrs2[is.finite(yrs2)]
  if (length(yrs2)) {
    cov_after <- c(min = min(yrs2), max = max(yrs2))
    message(sprintf("Year coverage (post-filter): %d-%d", cov_after[["min"]], cov_after[["max"]]))
  }
}

# Restrict columns to Wisotzkey variable set using explicit mapping and derived fields
wisotzkey_csv <- here::here('data', 'wisotzkey_variables.csv')
if (file.exists(wisotzkey_csv)) {
  suppressWarnings({
    wisotzkey_df <- tryCatch(readr::read_csv(wisotzkey_csv, show_col_types = FALSE), error = function(e) NULL)
  })
  if (!is.null(wisotzkey_df) && 'Variable Name' %in% names(wisotzkey_df)) {
    # Derived variables commonly used by the Wisotzkey set
    safe_num <- function(x) suppressWarnings(as.double(x))
    if (all(c('weight_txpl','height_txpl') %in% names(phts_all)) && !'bmi_txpl' %in% names(phts_all)) {
      wt <- safe_num(phts_all$weight_txpl)
      ht <- safe_num(phts_all$height_txpl)
      phts_all$bmi_txpl <- ifelse(is.finite(wt) & is.finite(ht) & ht > 0, (wt/(ht^2))*703, NA_real_)
    }
    if (all(c('height_txpl','txcreat_r') %in% names(phts_all)) && !'egfr_tx' %in% names(phts_all)) {
      ht <- safe_num(phts_all$height_txpl)
      cr <- safe_num(phts_all$txcreat_r)
      phts_all$egfr_tx <- ifelse(is.finite(ht) & is.finite(cr) & cr > 0, 0.413 * ht / cr, NA_real_)
    }
    if (all(c('txpl_year','age_txpl','age_listing') %in% names(phts_all)) && !'listing_year' %in% names(phts_all)) {
      a_tx <- safe_num(phts_all$age_txpl)
      a_ls <- safe_num(phts_all$age_listing)
      phts_all$listing_year <- as.integer(floor(phts_all$txpl_year - (a_tx - a_ls)))
    }

  # PRA max at listing: combine both sources using max, clamp to [0,100], and add a thresholded category
  # - If both sources NA, pra_listing stays NA (and category NA)
  # - If one source missing, we use the available one
  # - Category follows Wisotzkey (<5 vs ≥5%)
    if (!'pra_listing' %in% names(phts_all)) {
      n_rows <- nrow(phts_all)
      pra1 <- if ('lsfprat' %in% names(phts_all)) safe_num(phts_all$lsfprat) else rep(NA_real_, n_rows)
      pra2 <- if ('lsfprab' %in% names(phts_all)) safe_num(phts_all$lsfprab) else rep(NA_real_, n_rows)
      if (any(is.finite(pra1)) || any(is.finite(pra2))) {
        combined <- pmax(pra1, pra2, na.rm = TRUE)
        # pmax with na.rm=TRUE yields -Inf if both are NA; convert to NA
        combined[is.infinite(combined)] <- NA_real_
        # Clamp out-of-range values to NA and log a summary
        oob <- which(is.finite(combined) & (combined < 0 | combined > 100))
        if (length(oob)) {
          message(sprintf("PRA: %d values outside [0,100] set to NA.", length(oob)))
          combined[oob] <- NA_real_
        }
        phts_all$pra_listing <- combined
        # Thresholded category at 5%
        phts_all$pra_listing_cat <- factor(
          ifelse(is.na(combined), NA_character_, ifelse(combined < 5, "<5", "\u22655")),
          levels = c("<5", "\u22655")
        )
      }
    }

    # Normalize incoming names and build explicit map
    normalize_key <- function(x) {
      x <- tolower(x)
      x <- gsub("[^a-z0-9]+", "_", x)
      x <- gsub("_+", "_", x)
      trimws(x, which = 'both', whitespace = "_")
    }
    desired_keys <- unique(normalize_key(wisotzkey_df[["Variable Name"]]))

    wisotzkey_name_map <- c(
      "primary_etiology"               = "prim_dx",
      "mcsd_at_transplant"             = "tx_mcsd",
      "single_ventricle_chd"           = "chd_sv",
      "surgeries_prior_to_listing"     = "hxsurg",
      "serum_albumin_at_transplant"    = "txsa_r",
      "bun_at_transplant"              = "txbun_r",
      "ecmo_at_transplant"             = "txecmo",
      "transplant_year"                = "txpl_year",
      "recipient_weight_at_transplant" = "weight_txpl",
      "alt_at_transplant"              = "txalt",
      "bmi_at_transplant"              = "bmi_txpl",
      "pra_max_at_listing"             = "pra_listing",
      "egfr_at_transplant"             = "egfr_tx",
      "medical_history_at_listing"     = "hxmed",
      "listing_year"                   = "listing_year"
    )

    resolve_candidates <- function(key) {
      if (!key %in% names(wisotzkey_name_map)) return(character(0))
      wisotzkey_name_map[[key]]
    }

  # Essentials for modeling and reporting (Table 1 needs these demographics)
  essentials <- c('time','status','ID','txpl_year','age_txpl','sex','race','hisp')
    keep <- essentials
    missing <- character(0)
    added <- character(0)
    for (k in desired_keys) {
      cands <- resolve_candidates(k)
      if (!length(cands)) { missing <- c(missing, k); next }
      found <- cands[cands %in% names(phts_all)]
      if (length(found)) { keep <- c(keep, found[[1]]); added <- c(added, found[[1]]) } else { missing <- c(missing, k) }
    }
  # Also keep raw PRA fields and derived category if present for auditability
  keep <- c(keep, intersect(c('lsfprat','lsfprab','pra_listing_cat'), names(phts_all)))
    keep <- unique(keep)
    keep <- keep[keep %in% names(phts_all)]
    n_before <- ncol(phts_all)
    phts_all <- dplyr::select(phts_all, dplyr::all_of(keep))
    n_after <- ncol(phts_all)
    message(sprintf("Wisotzkey mapping filter applied: kept %d/%d columns (incl. essentials). Added: %s",
                    n_after, n_before, paste(setdiff(keep, essentials), collapse=", ")))
    if (length(missing)) {
      message(sprintf("Wisotzkey mapping: %d requested variables not found or unmapped: %s",
                      length(unique(missing)), paste(unique(missing), collapse=", ")))
    }
  } else {
    message("Wisotzkey filter: CSV found but missing 'Variable Name' column; skipping column filter.")
  }
} else {
  message("Wisotzkey filter: data/wisotzkey_variables.csv not found; skipping column filter.")
}

dir.create(here::here('data'), showWarnings = FALSE)
saveRDS(phts_all, file = here::here('data', 'phts_all.rds'))
saveRDS(labels, file = here::here('data', 'labels.rds'))

message("Data prepared: data/phts_all.rds, data/labels.rds")

