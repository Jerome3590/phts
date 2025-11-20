resolve_scenario <- function() {
  # High-level bundled scenario logic.
  # User can set SCENARIO to a named bundle OR use granular flags.
  # If SCENARIO is set, it will populate / override specific env vars unless they are explicitly provided.
  scen <- Sys.getenv('SCENARIO', unset = '')
  if (!nzchar(scen)) return(invisible(list(source = 'none')))
  scen_lower <- tolower(scen)

  # Keep track of what we set so we can report it.
  applied <- list()

  # Helper: set env var only if not already explicitly set by user.
  set_if_missing <- function(var, value) {
    if (!nzchar(Sys.getenv(var, unset = ''))) return(Sys.setenv(structure(value, names = var)))
  }

  # Define scenario bundles.
  # Each element lists key/value env pairs to enforce, using canonical flag names.
  bundles <- list(
    'original_study_fullcats' = list(ORIGINAL_STUDY = '1', EXCLUDE_COVID = '0', CATBOOST_USE_FULL = '1'),
    'covid_exclusion_full'    = list(EXCLUDE_COVID = '1', ORIGINAL_STUDY = '0', CATBOOST_USE_FULL = '1'),
    'full_all_full'           = list(EXCLUDE_COVID = '0', ORIGINAL_STUDY = '0', CATBOOST_USE_FULL = '1', XGB_FULL = '1', ORSF_FULL = '1'),
    'original_plus_xgb'       = list(ORIGINAL_STUDY = '1', XGB_FULL = '1'),
    'original_plus_all'       = list(ORIGINAL_STUDY = '1', CATBOOST_USE_FULL = '1', XGB_FULL = '1', ORSF_FULL = '1'),
    'full_catboost_xgb'       = list(CATBOOST_USE_FULL = '1', XGB_FULL = '1'),
    'full_minimal'            = list(CATBOOST_USE_FULL = '0', XGB_FULL = '0', ORSF_FULL = '0')
  )

  if (!scen_lower %in% names(bundles)) {
    warning(sprintf('SCENARIO="%s" not recognized. No bundle applied.', scen))
    return(invisible(list(source = 'unrecognized', scenario = scen)))
  }

  kv <- bundles[[scen_lower]]
  for (nm in names(kv)) {
    # Do not overwrite if user explicitly set the variable already.
    if (!nzchar(Sys.getenv(nm, unset = ''))) next
    Sys.setenv(structure(kv[[nm]], names = nm))
    applied[[nm]] <- kv[[nm]]
  }
  message(sprintf('Scenario "%s" applied. Variables set (only if previously unset): %s', scen, paste(sprintf('%s=%s', names(applied), applied), collapse = ', ')))
  invisible(c(list(source = 'scenario', scenario = scen), applied))
}

# Convenience: call on load so any subsequent sourcing of step scripts sees resolved flags.
try(resolve_scenario(), silent = TRUE)
