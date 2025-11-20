cat("\n\n##############################################\n")
cat(sprintf("### STARTING STEP: 03_prep_model_data.R [%s] ###\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
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
cat("\n[03_prep_model_data.R] Starting prep model data script\n")
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
log_file <- switch(Sys.getenv("DATASET_COHORT", unset = ""),
  original = "logs/orch_bg_original_study.log",
  full_with_covid = "logs/orch_bg_full_with_covid.log",
  full_without_covid = "logs/orch_bg_full_without_covid.log",
  "logs/orch_bg_unknown.log"
)
cat("Log file path: ", log_file, "\n")
cat("[03_prep_model_data.R] Diagnostic output complete\n\n")

# Diagnostic: print threading and parallel info
cat(sprintf("[Diagnostic] OMP_NUM_THREADS: %s\n", Sys.getenv("OMP_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] MKL_NUM_THREADS: %s\n", Sys.getenv("MKL_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] OPENBLAS_NUM_THREADS: %s\n", Sys.getenv("OPENBLAS_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] NUMEXPR_NUM_THREADS: %s\n", Sys.getenv("NUMEXPR_NUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] VECLIB_MAXIMUM_THREADS: %s\n", Sys.getenv("VECLIB_MAXIMUM_THREADS", unset = "unset")))
cat(sprintf("[Diagnostic] parallel::detectCores(): %d\n", parallel::detectCores()))
cat(sprintf("[Diagnostic] parallel::detectCores(logical=FALSE): %d\n", parallel::detectCores(logical=FALSE)))
cat(sprintf("[Diagnostic] Sys.info()['nodename']: %s\n", Sys.info()[['nodename']]))

# Note: Logging is managed by run_pipeline.R orchestrator
# Individual pipeline scripts should not set up their own sink/on.exit handlers
# to avoid conflicts with the parent script's logging management

source("pipeline/00_setup.R")

# Read phts_simple.rds which contains the derived Wisotzkey features
# (bmi_txpl, egfr_tx, listing_year, pra_listing) created in Step 1
phts_all <- readRDS(here::here('model_data', 'phts_simple.rds'))
cat(sprintf("[DEBUG] Loaded phts_simple.rds: %d rows, %d cols\n", nrow(phts_all), ncol(phts_all)))

# Diagnostics: columns before recipe
dir.create(here::here('model_data','diagnostics'), showWarnings = FALSE, recursive = TRUE)
readr::write_lines(x = names(phts_all), file = here::here('model_data','diagnostics','columns_before.txt'))

final_features <- make_final_features(phts_all, n_predictors = 15, use_hardcoded_features = TRUE)

# Log the feature selection results
cat(sprintf("[Progress] Feature selection completed:\n"))
cat(sprintf("[Progress]   Selected %d predictor variables\n", length(final_features$variables)))
cat(sprintf("[Progress]   Selected %d terms (including dummy variables)\n", length(final_features$terms)))
cat(sprintf("[Progress]   Top 5 variables: %s\n", paste(head(final_features$variables, 5), collapse = ", ")))

# Build two parallel prep paths:
# 1) CatBoost/native categoricals (no dummy coding)
# 2) Encoded (dummy-coded categoricals) for learners that require numeric inputs

# 1) CatBoost/native categoricals
final_recipe_cat <- prep(make_recipe(phts_all, dummy_code = FALSE))
final_data_cat <- juice(final_recipe_cat)

# Drop single-level factor predictors (can cause downstream contrasts errors)
single_level_cat <- names(final_data_cat)[vapply(final_data_cat, function(x) is.factor(x) && length(levels(x)) < 2, logical(1))]
if(length(single_level_cat)){
  readr::write_lines(single_level_cat, here::here('model_data','diagnostics','dropped_single_level_factors_catboost.txt'))
  final_data_cat <- final_data_cat[setdiff(names(final_data_cat), single_level_cat)]
}

# Make column names unique and log mapping if any were duplicated

# End of script resource monitoring
step_end_time <- Sys.time()
cat(sprintf("[Resource] End: %s\n", format(step_end_time, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("[Resource] Elapsed: %.2f sec\n", as.numeric(difftime(step_end_time, step_start_time, units = "secs"))))
cat(sprintf("[Resource] Memory used: %.2f MB\n", sum(gc()[,2])))
orig_names_cat <- names(final_data_cat)
uniq_names_cat <- make.unique(orig_names_cat)
if (!identical(orig_names_cat, uniq_names_cat)) {
  name_map_cat <- tibble::tibble(original = orig_names_cat, unique = uniq_names_cat)
  readr::write_csv(name_map_cat, here::here('model_data','diagnostics','name_map_after_recipe_catboost.csv'))
  names(final_data_cat) <- uniq_names_cat
}

# Diagnostics: columns after recipe
post_cols_cat <- tibble::tibble(
  name = names(final_data_cat),
  type = purrr::map_chr(final_data_cat, ~ class(.x)[1])
)
readr::write_csv(post_cols_cat, here::here('model_data','diagnostics','columns_after.csv'))
readr::write_csv(post_cols_cat, here::here('model_data','diagnostics','columns_after_catboost.csv'))
dupes_cat <- dplyr::count(post_cols_cat, name, name = 'count') %>% dplyr::filter(count > 1)
readr::write_csv(dupes_cat, here::here('model_data','diagnostics','columns_after_duplicates_catboost.csv'))
if('dtx_patient' %in% names(final_data_cat)){
  idx <- which(names(final_data_cat) == 'dtx_patient')
  readr::write_lines(paste(idx, collapse = ','), here::here('model_data','diagnostics','dtx_patient_positions_catboost.txt'))
}

# 2) Encoded (dummy-coded categoricals)
final_recipe_enc <- prep(make_recipe(phts_all, dummy_code = TRUE))
final_data_enc <- juice(final_recipe_enc)

single_level_enc <- names(final_data_enc)[vapply(final_data_enc, function(x) is.factor(x) && length(levels(x)) < 2, logical(1))]
if(length(single_level_enc)){
  readr::write_lines(single_level_enc, here::here('model_data','diagnostics','dropped_single_level_factors_encoded.txt'))
  final_data_enc <- final_data_enc[setdiff(names(final_data_enc), single_level_enc)]
}

# Make column names unique and log mapping for encoded
orig_names_enc <- names(final_data_enc)
uniq_names_enc <- make.unique(orig_names_enc)
if (!identical(orig_names_enc, uniq_names_enc)) {
  name_map_enc <- tibble::tibble(original = orig_names_enc, unique = uniq_names_enc)
  readr::write_csv(name_map_enc, here::here('model_data','diagnostics','name_map_after_recipe_encoded.csv'))
  names(final_data_enc) <- uniq_names_enc
}

# Diagnostics: columns after recipe (encoded)
post_cols_enc <- tibble::tibble(
  name = names(final_data_enc),
  type = purrr::map_chr(final_data_enc, ~ class(.x)[1])
)
readr::write_csv(post_cols_enc, here::here('model_data','diagnostics','columns_after_encoded.csv'))
dupes_enc <- dplyr::count(post_cols_enc, name, name = 'count') %>% dplyr::filter(count > 1)
readr::write_csv(dupes_enc, here::here('model_data','diagnostics','columns_after_duplicates_encoded.csv'))
if('dtx_patient' %in% names(final_data_enc)){
  idx <- which(names(final_data_enc) == 'dtx_patient')
  readr::write_lines(paste(idx, collapse = ','), here::here('model_data','diagnostics','dtx_patient_positions_encoded.txt'))
}

# prim_dx diagnostics and enforcement as factor if present (source)
if ('prim_dx' %in% names(phts_all)) {
  prim_dx_summary <- capture.output({
    cat('phts_all prim_dx levels =', if (is.factor(phts_all$prim_dx)) length(levels(phts_all$prim_dx)) else NA_integer_, '\n')
    print(utils::head(table(phts_all$prim_dx), 10))
  })
  readr::write_lines(prim_dx_summary, here::here('model_data','diagnostics','prim_dx_before.txt'))
}
if ('prim_dx' %in% names(final_data_cat)) {
  if (!is.factor(final_data_cat$prim_dx)) final_data_cat$prim_dx <- as.factor(final_data_cat$prim_dx)
  prim_dx_after_cat <- capture.output({
    cat('final_data_cat prim_dx levels =', length(levels(final_data_cat$prim_dx)), '\n')
    print(utils::head(table(final_data_cat$prim_dx), 10))
  })
  readr::write_lines(prim_dx_after_cat, here::here('model_data','diagnostics','prim_dx_after_catboost.txt'))
}

dir.create(here::here('model_data'), showWarnings = FALSE)

# Load dual format utility for robust saving
dual_format_available <- FALSE
tryCatch({
  source(here::here("scripts", "R", "utils", "dual_format_io.R"))
  dual_format_available <- exists("save_dual_format", mode = "function")
}, error = function(e) {
  message("Dual format utility not available, using RDS only")
})

# Save final_features (metadata - save as both formats)
if (dual_format_available) {
  tryCatch({
    # Convert to data frame for CSV compatibility
    features_df <- data.frame(
      variable = final_features$variables,
      stringsAsFactors = FALSE
    )
    save_dual_format(features_df, here::here('model_data', 'final_features'))
  }, error = function(e) {
    saveRDS(final_features, here::here('model_data', 'final_features.rds'))
    warning("Failed to save final_features in dual format, used RDS only")
  })
} else {
  saveRDS(final_features, here::here('model_data', 'final_features.rds'))
}

# Save data files in dual format
if (dual_format_available) {
  # Main data files (backward-compatibility)
  tryCatch({
    save_dual_format(final_data_cat, here::here('model_data', 'final_data'))
  }, error = function(e) {
    saveRDS(final_data_cat, here::here('model_data', 'final_data.rds'))
    warning("Failed to save final_data in dual format, used RDS only")
  })
  
  # Explicit variants for clarity
  tryCatch({
    save_dual_format(final_data_cat, here::here('model_data', 'final_data_catboost'))
  }, error = function(e) {
    saveRDS(final_data_cat, here::here('model_data', 'final_data_catboost.rds'))
  })
  
  tryCatch({
    save_dual_format(final_data_enc, here::here('model_data', 'final_data_encoded'))
  }, error = function(e) {
    saveRDS(final_data_enc, here::here('model_data', 'final_data_encoded.rds'))
  })
} else {
  # Fallback to RDS only
  saveRDS(final_data_cat, here::here('model_data', 'final_data.rds'))
  saveRDS(final_data_cat, here::here('model_data', 'final_data_catboost.rds'))
  saveRDS(final_data_enc, here::here('model_data', 'final_data_encoded.rds'))
}

# Recipes are R-specific objects, keep as RDS only
saveRDS(final_recipe_cat, here::here('model_data', 'final_recipe.rds'))
saveRDS(final_recipe_cat, here::here('model_data', 'final_recipe_catboost.rds'))

# Create CSV versions for CatBoost and cross-platform compatibility
cat("[Progress] Creating CSV versions for CatBoost...\n")
tryCatch({
  # Main final data CSV
  final_data_csv <- here::here('model_data', 'final_data.csv')
  readr::write_csv(final_data_cat, final_data_csv)
  cat(sprintf("[Progress] ✓ Saved: %s (%d rows, %d cols)\n", 
             final_data_csv, nrow(final_data_cat), ncol(final_data_cat)))
  
  # CatBoost-specific CSV (same as main for now)
  final_data_catboost_csv <- here::here('model_data', 'final_data_catboost.csv')
  readr::write_csv(final_data_cat, final_data_catboost_csv)
  cat(sprintf("[Progress] ✓ Saved: %s (%d rows, %d cols)\n", 
             final_data_catboost_csv, nrow(final_data_cat), ncol(final_data_cat)))
  
  # Encoded data CSV (for XGBoost if needed)
  final_data_encoded_csv <- here::here('model_data', 'final_data_encoded.csv')
  readr::write_csv(final_data_enc, final_data_encoded_csv)
  cat(sprintf("[Progress] ✓ Saved: %s (%d rows, %d cols)\n", 
             final_data_encoded_csv, nrow(final_data_enc), ncol(final_data_enc)))
  
}, error = function(e) {
  cat(sprintf("[ERROR] Failed to create CSV files: %s\n", e$message))
  warning("CSV creation failed, but RDS files are still available")
})
saveRDS(final_recipe_enc, here::here('model_data', 'final_recipe_encoded.rds'))

message("Saved: final_features.rds, final_recipe*.rds, final_data*.rds, final_data*.csv (catboost + encoded)")

# ----------------------------------------------------------------------------
# Combined removal log (single-level factors, NZV from recipe steps)
# ----------------------------------------------------------------------------

removal_log <- tibble::tibble()

# Single-level factors (native)
if (exists('single_level_cat') && length(single_level_cat)) {
  removal_log <- dplyr::bind_rows(removal_log, tibble::tibble(
    variable = single_level_cat,
    path = 'catboost',
    reason = 'single_level_factor'
  ))
}

# Single-level factors (encoded)
if (exists('single_level_enc') && length(single_level_enc)) {
  removal_log <- dplyr::bind_rows(removal_log, tibble::tibble(
    variable = single_level_enc,
    path = 'encoded',
    reason = 'single_level_factor'
  ))
}

# Attempt to extract removed predictors from recipe NZV step
extract_nzv <- function(rc, path_label){
  try({
    steps <- rc$steps
    for(st in steps){
      if(inherits(st, 'step_nzv')){
        # st$terms stores selectors; after prep, st$removals has removed names
        if(!is.null(st$removals) && length(st$removals)){
          return(tibble::tibble(variable = st$removals, path = path_label, reason = 'near_zero_variance'))
        }
      }
    }
    NULL
  }, silent = TRUE)
}

nzv_cat <- extract_nzv(final_recipe_cat, 'catboost')
nzv_enc <- extract_nzv(final_recipe_enc, 'encoded')
if(!is.null(nzv_cat)) removal_log <- dplyr::bind_rows(removal_log, nzv_cat)
if(!is.null(nzv_enc)) removal_log <- dplyr::bind_rows(removal_log, nzv_enc)

if(nrow(removal_log)){
  removal_log <- dplyr::distinct(removal_log)
  readr::write_csv(removal_log, here::here('model_data','diagnostics','removed_predictors_log.csv'))
  message(sprintf('Removal log written: %d entries (model_data/diagnostics/removed_predictors_log.csv)', nrow(removal_log)))
} else {
  message('Removal log: no removed predictors to record')
}

