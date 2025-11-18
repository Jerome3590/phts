
##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @param min_txpl_year 
##' @param predict_horizon 
##' @param case 
##' @param set_to_na 
##'
##' @title

clean_phts <- function(
  min_txpl_year, 
  predict_horizon,
  time, 
  status,
  case = 'snake', 
  set_to_na = '') {
  
  time_quo <- enquo(time)
  status_quo <- enquo(status)

  # stored in private directory to prevent data leak
  sas_path_local <- here('data', 'transplant.sas7bdat')
  sas_path_external <- here('..', 'data', 'transplant.sas7bdat')
  sas_path <- if (file.exists(sas_path_local)) sas_path_local else sas_path_external
  out <- read_sas(sas_path) %>%
    filter(TXPL_YEAR >= min_txpl_year) %>% 
    # Keep LSFPRAT and LSFPRAB (PRA at listing) but drop other detailed PRA date fields
    {
      drop_these <- c(
        'LSPRA','LSCPRAT','LSCPRAB','LSPRADTE','LSPRDTET','LSPRDTEB',
        'LSFCPRA',               # keep LSFPRAT/LSFPRAB below
        'TXCPRA','CPRAT','CPRAB','TXPRADTE','CPRADTET','CPRADTEB',
        'TXFCPRA','FPRAT','FPRAB'
      )
      keep_back <- c('LSFPRAT','LSFPRAB')
      select(., -any_of(setdiff(drop_these, keep_back)))
  } %>%
    clean_names() %>%
    rename(
      outcome_int_graft_loss = int_graft_loss,
      outcome_graft_loss = graft_loss
    ) %>%
    mutate(
      ID = 1:n(),
      # prevent improper names if you one-hot encode
      across(
        .cols = where(is.character), 
        ~ clean_chr(.x, case = case, set_to_na = set_to_na)
      ),
      # set event times of 0 to something non-zero but still small
      across(
        .cols = any_of(c('outcome_waitlist_interval', 'outcome_int_graft_loss')),
        ~ replace(.x, list = .x == 0, values = 1/365)
      ),
      across(.cols = where(is.character), as.factor),
      # truncate survival data to match prediction horizon
      # outcome_int_graft_loss = pmin(outcome_int_graft_loss, predict_horizon + 1/365),
      # outcome_graft_loss = if_else(
      #   condition = outcome_int_graft_loss > predict_horizon, 
      #   true = 0, false = outcome_graft_loss 
      # ),
      prim_dx = if ('prim_dx' %in% names(.)) factor(prim_dx) else prim_dx,
      tx_mcsd = if ('txnomcsd' %in% names(.)) {
        if_else(txnomcsd == 'yes', 'no', 'yes')
      } else { tx_mcsd }
    ) %>% 
    rename(
      time = !!time_quo,
      status = !!status_quo
    ) %>% 
    select(
      -starts_with('outcome'),
      -any_of(c('txnomcsd','lbun_r'))
    )
  
  too_many_missing <- miss_var_summary(data = out) %>% 
    filter(pct_miss > 30) %>% 
    pull(variable)

  # Whitelist critical variables even if they exceed missingness threshold
  missing_whitelist <- c('tx_mcsd','chd_sv','lsfprat','lsfprab')
  drop_vars <- setdiff(too_many_missing, missing_whitelist)
  if (length(drop_vars)) out[, drop_vars] <- NULL
  
  
  # remove some variables that are collected at listing
  # and also at transplant, but don't need to be included
  # in both of the visits:
  
  out <- out %>% 
    select(-height_listing,
           -weight_listing)
  
  if (!dir.exists(here('data'))) dir.create(here('data'))
  write_rds(out, here('data', 'phts_all.rds'))
  
}
