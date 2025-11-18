source("scripts/00_setup.R")

phts_all <- readRDS(here::here('data', 'phts_all.rds'))

# Diagnostics: columns before recipe
dir.create(here::here('data','diagnostics'), showWarnings = FALSE, recursive = TRUE)
readr::write_lines(x = names(phts_all), file = here::here('data','diagnostics','columns_before.txt'))

final_features <- make_final_features(phts_all, n_predictors = 15)

# Build two parallel prep paths:
# 1) CatBoost/native categoricals (no dummy coding)
# 2) Encoded (dummy-coded categoricals) for learners that require numeric inputs

# 1) CatBoost/native categoricals
final_recipe_cat <- prep(make_recipe(phts_all, dummy_code = FALSE))
final_data_cat <- juice(final_recipe_cat)

# Drop single-level factor predictors (can cause downstream contrasts errors)
single_level_cat <- names(final_data_cat)[vapply(final_data_cat, function(x) is.factor(x) && length(levels(x)) < 2, logical(1))]
if(length(single_level_cat)){
  readr::write_lines(single_level_cat, here::here('data','diagnostics','dropped_single_level_factors_catboost.txt'))
  final_data_cat <- final_data_cat[setdiff(names(final_data_cat), single_level_cat)]
}

# Make column names unique and log mapping if any were duplicated
orig_names_cat <- names(final_data_cat)
uniq_names_cat <- make.unique(orig_names_cat)
if (!identical(orig_names_cat, uniq_names_cat)) {
  name_map_cat <- tibble::tibble(original = orig_names_cat, unique = uniq_names_cat)
  readr::write_csv(name_map_cat, here::here('data','diagnostics','name_map_after_recipe_catboost.csv'))
  names(final_data_cat) <- uniq_names_cat
}

# Diagnostics: columns after recipe
post_cols_cat <- tibble::tibble(
  name = names(final_data_cat),
  type = purrr::map_chr(final_data_cat, ~ class(.x)[1])
)
readr::write_csv(post_cols_cat, here::here('data','diagnostics','columns_after.csv'))
readr::write_csv(post_cols_cat, here::here('data','diagnostics','columns_after_catboost.csv'))
dupes_cat <- dplyr::count(post_cols_cat, name, name = 'count') %>% dplyr::filter(count > 1)
readr::write_csv(dupes_cat, here::here('data','diagnostics','columns_after_duplicates_catboost.csv'))
if('dtx_patient' %in% names(final_data_cat)){
  idx <- which(names(final_data_cat) == 'dtx_patient')
  readr::write_lines(paste(idx, collapse = ','), here::here('data','diagnostics','dtx_patient_positions_catboost.txt'))
}

# 2) Encoded (dummy-coded categoricals)
final_recipe_enc <- prep(make_recipe(phts_all, dummy_code = TRUE))
final_data_enc <- juice(final_recipe_enc)

single_level_enc <- names(final_data_enc)[vapply(final_data_enc, function(x) is.factor(x) && length(levels(x)) < 2, logical(1))]
if(length(single_level_enc)){
  readr::write_lines(single_level_enc, here::here('data','diagnostics','dropped_single_level_factors_encoded.txt'))
  final_data_enc <- final_data_enc[setdiff(names(final_data_enc), single_level_enc)]
}

# Make column names unique and log mapping for encoded
orig_names_enc <- names(final_data_enc)
uniq_names_enc <- make.unique(orig_names_enc)
if (!identical(orig_names_enc, uniq_names_enc)) {
  name_map_enc <- tibble::tibble(original = orig_names_enc, unique = uniq_names_enc)
  readr::write_csv(name_map_enc, here::here('data','diagnostics','name_map_after_recipe_encoded.csv'))
  names(final_data_enc) <- uniq_names_enc
}

# Diagnostics: columns after recipe (encoded)
post_cols_enc <- tibble::tibble(
  name = names(final_data_enc),
  type = purrr::map_chr(final_data_enc, ~ class(.x)[1])
)
readr::write_csv(post_cols_enc, here::here('data','diagnostics','columns_after_encoded.csv'))
dupes_enc <- dplyr::count(post_cols_enc, name, name = 'count') %>% dplyr::filter(count > 1)
readr::write_csv(dupes_enc, here::here('data','diagnostics','columns_after_duplicates_encoded.csv'))
if('dtx_patient' %in% names(final_data_enc)){
  idx <- which(names(final_data_enc) == 'dtx_patient')
  readr::write_lines(paste(idx, collapse = ','), here::here('data','diagnostics','dtx_patient_positions_encoded.txt'))
}

# prim_dx diagnostics and enforcement as factor if present (source)
if ('prim_dx' %in% names(phts_all)) {
  prim_dx_summary <- capture.output({
    cat('phts_all prim_dx levels =', if (is.factor(phts_all$prim_dx)) length(levels(phts_all$prim_dx)) else NA_integer_, '\n')
    print(utils::head(table(phts_all$prim_dx), 10))
  })
  readr::write_lines(prim_dx_summary, here::here('data','diagnostics','prim_dx_before.txt'))
}
if ('prim_dx' %in% names(final_data_cat)) {
  if (!is.factor(final_data_cat$prim_dx)) final_data_cat$prim_dx <- as.factor(final_data_cat$prim_dx)
  prim_dx_after_cat <- capture.output({
    cat('final_data_cat prim_dx levels =', length(levels(final_data_cat$prim_dx)), '\n')
    print(utils::head(table(final_data_cat$prim_dx), 10))
  })
  readr::write_lines(prim_dx_after_cat, here::here('data','diagnostics','prim_dx_after_catboost.txt'))
}

dir.create(here::here('data'), showWarnings = FALSE)
saveRDS(final_features, here::here('data', 'final_features.rds'))

# Backward-compatibility: keep original filenames pointing to CatBoost/native path
saveRDS(final_recipe_cat, here::here('data', 'final_recipe.rds'))
saveRDS(final_data_cat, here::here('data', 'final_data.rds'))

# Also save explicit variants for clarity
saveRDS(final_recipe_cat, here::here('data', 'final_recipe_catboost.rds'))
saveRDS(final_data_cat, here::here('data', 'final_data_catboost.rds'))
saveRDS(final_recipe_enc, here::here('data', 'final_recipe_encoded.rds'))
saveRDS(final_data_enc, here::here('data', 'final_data_encoded.rds'))

message("Saved: final_features.rds, final_recipe*.rds, final_data*.rds (catboost + encoded)")

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
  readr::write_csv(removal_log, here::here('data','diagnostics','removed_predictors_log.csv'))
  message(sprintf('Removal log written: %d entries (data/diagnostics/removed_predictors_log.csv)', nrow(removal_log)))
} else {
  message('Removal log: no removed predictors to record')
}

