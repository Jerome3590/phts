cat("\n\n##############################################\n")
cat(sprintf("### STARTING STEP: 01_prepare_data.R [%s] ###\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("##############################################\n\n")
# Resource monitoring: log memory, CPU, and elapsed time
step_start_time <- Sys.time()
cat(sprintf("[Resource] Start: %s\n", format(step_start_time, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("[Resource] Memory used: %.2f MB\n", sum(gc()[,2])))
if (.Platform$OS.type == "unix" && file.exists("/proc/self/status")) {
  status <- readLines("/proc/self/status")
  rss <- as.numeric(gsub("[^0-9]", "", status[grep("VmRSS", status)]))
  cat(sprintf("[Resource] VmRSS: %.2f MB\n", rss/1024))
}

# Diagnostic output for debugging parallel execution and logging
cat("\n[01_prepare_data.R] Starting prepare data script\n")
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
log_file <- switch(Sys.getenv("DATASET_COHORT", unset = ""),
  original = "logs/orch_bg_original_study.log",
  full_with_covid = "logs/orch_bg_full_with_covid.log",
  full_without_covid = "logs/orch_bg_full_without_covid.log",
  "logs/orch_bg_unknown.log"
)
cat("Log file path: ", log_file, "\n")
cat("[01_prepare_data.R] Diagnostic output complete\n\n")

# Diagnostic: print threading and parallel info
cat(sprintf("[Diagnostic] OMP_NUM_THREADS: %s\n", Sys.getenv("OMP_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] MKL_NUM_THREADS: %s\n", Sys.getenv("MKL_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] OPENBLAS_NUM_THREADS: %s\n", Sys.getenv("OPENBLAS_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] NUMEXPR_NUM_THREADS: %s\n", Sys.getenv("NUMEXPR_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] VECLIB_MAXIMUM_THREADS: %s\n", Sys.getenv("VECLIB_MAXIMUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] parallel::detectCores(): %d\n", parallel::detectCores()))
cat(sprintf("[Diagnostic] parallel::detectCores(logical=FALSE): %d\n", parallel::detectCores(logical=FALSE)))
cat(sprintf("[Diagnostic] Sys.info()['nodename']: %s\n", Sys.info()[['nodename']]))

# Redirect output and messages to cohort log file
log_conn <- file(log_file, open = 'at')
sink(log_conn, split = TRUE)
sink(log_conn, type = 'message', append = TRUE)
on.exit({
  try(sink(type = 'message'))
  try(sink())
  try(close(log_conn))
}, add = TRUE)

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

# End of script resource monitoring
step_end_time <- Sys.time()
cat(sprintf("[Resource] End: %s\n", format(step_end_time, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("[Resource] Elapsed: %.2f sec\n", as.numeric(difftime(step_end_time, step_start_time, units = "secs"))))
cat(sprintf("[Resource] Memory used: %.2f MB\n", sum(gc()[,2])))

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

# Create derived variables that are commonly used (always create these)
safe_num <- function(x) suppressWarnings(as.double(x))

# BMI at transplant: weight(kg) / height(m)^2, converted from lbs/inches
if (all(c('weight_txpl','height_txpl') %in% names(phts_all)) && !'bmi_txpl' %in% names(phts_all)) {
  wt <- safe_num(phts_all$weight_txpl)
  ht <- safe_num(phts_all$height_txpl)
  phts_all$bmi_txpl <- ifelse(is.finite(wt) & is.finite(ht) & ht > 0, (wt/(ht^2))*703, NA_real_)
  message("Created bmi_txpl from weight_txpl and height_txpl")
}

# eGFR at transplant: simplified formula using height and creatinine
if (all(c('height_txpl','txcreat_r') %in% names(phts_all)) && !'egfr_tx' %in% names(phts_all)) {
  ht <- safe_num(phts_all$height_txpl)
  cr <- safe_num(phts_all$txcreat_r)
  phts_all$egfr_tx <- ifelse(is.finite(ht) & is.finite(cr) & cr > 0, 0.413 * ht / cr, NA_real_)
  message("Created egfr_tx from height_txpl and txcreat_r")
}

# Listing year: estimated from transplant year and age difference
if (all(c('txpl_year','age_txpl','age_listing') %in% names(phts_all)) && !'listing_year' %in% names(phts_all)) {
  a_tx <- safe_num(phts_all$age_txpl)
  a_ls <- safe_num(phts_all$age_listing)
  phts_all$listing_year <- as.integer(floor(phts_all$txpl_year - (a_tx - a_ls)))
  message("Created listing_year from txpl_year, age_txpl, and age_listing")
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
    message("Created pra_listing from lsfprat and lsfprab")
  }
}

# Restrict columns to Wisotzkey variable set using explicit mapping
wisotzkey_csv <- here::here('data', 'wisotzkey_variables.csv')
if (file.exists(wisotzkey_csv)) {
  suppressWarnings({
    wisotzkey_df <- tryCatch(readr::read_csv(wisotzkey_csv, show_col_types = FALSE), error = function(e) NULL)
  })
  if (!is.null(wisotzkey_df) && 'Variable Name' %in% names(wisotzkey_df)) {

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

dir.create(here::here('model_data'), showWarnings = FALSE)
saveRDS(phts_all, file = here::here('model_data', 'phts_all.rds'))
saveRDS(labels, file = here::here('model_data', 'labels.rds'))

message("Data prepared: model_data/phts_all.rds, model_data/labels.rds")

