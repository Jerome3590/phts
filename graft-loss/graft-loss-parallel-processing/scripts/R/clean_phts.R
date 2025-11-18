
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
  
  # Ensure rlang is available for tidy evaluation helpers
  if (!requireNamespace("rlang", quietly = TRUE)) {
    stop("Package 'rlang' is required by clean_phts() but is not installed. Please install it and try again.")
  }

  # Accept either unquoted column names or character names for compatibility
  # with different call sites. Use rlang::ensym which will turn a bare name
  # into a symbol and a character string into a symbol with the same name.
  time_sym <- rlang::ensym(time)
  status_sym <- rlang::ensym(status)

  # Diagnostic output to help debug 'closure to character' issues
  # Print the raw arguments as received and any bound object types
  try({
    cat(sprintf("[clean_phts] raw 'time' arg (deparse): %s\n", paste(deparse(substitute(time)), collapse = "")))
    cat(sprintf("[clean_phts] raw 'status' arg (deparse): %s\n", paste(deparse(substitute(status)), collapse = "")))
    cat(sprintf("[clean_phts] typeof(time): %s\n", typeof(time)))
    cat(sprintf("[clean_phts] typeof(status): %s\n", typeof(status)))
    # If symbol or name resolves to an object in the caller, print its type
    time_name <- tryCatch(as.character(rlang::as_name(time_sym)), error = function(e) NA)
    status_name <- tryCatch(as.character(rlang::as_name(status_sym)), error = function(e) NA)
    if (!is.na(time_name) && exists(time_name, envir = parent.frame(), inherits = TRUE)) {
      obj <- get(time_name, envir = parent.frame(), inherits = TRUE)
      cat(sprintf("[clean_phts] Found object named '%s' in caller: typeof=%s\n", time_name, typeof(obj)))
    } else {
      cat(sprintf("[clean_phts] No object named '%s' found in caller env\n", time_name))
    }
    if (!is.na(status_name) && exists(status_name, envir = parent.frame(), inherits = TRUE)) {
      obj <- get(status_name, envir = parent.frame(), inherits = TRUE)
      cat(sprintf("[clean_phts] Found object named '%s' in caller: typeof=%s\n", status_name, typeof(obj)))
    } else {
      cat(sprintf("[clean_phts] No object named '%s' found in caller env\n", status_name))
    }
  }, silent = TRUE)

  # stored in private directory to prevent data leak
  sas_path_local <- here('data', 'transplant.sas7bdat')
  sas_path_external <- here('..', 'data', 'transplant.sas7bdat')
  sas_path <- if (file.exists(sas_path_local)) sas_path_local else sas_path_external
  
  # Add diagnostics for EC2
  cat(sprintf("[clean_phts] SAS file path: %s\n", sas_path))
  cat(sprintf("[clean_phts] File exists: %s\n", file.exists(sas_path)))
  cat(sprintf("[clean_phts] File size: %s bytes\n", file.size(sas_path)))
  cat(sprintf("[clean_phts] File permissions: %s\n", file.access(sas_path, 4))) # 4 = read permission
  
  # Try to read SAS file with error handling and fallback
  out <- tryCatch({
    data <- read_sas(sas_path)
    cat(sprintf("[clean_phts] Successfully read SAS file: %d rows, %d columns\n", nrow(data), ncol(data)))
    data
  }, error = function(e) {
    cat(sprintf("[clean_phts] Error reading SAS file: %s\n", e$message))
    
    # Try alternative reading methods for EC2
    cat("[clean_phts] Attempting alternative SAS reading methods...\n")
    
    # Method 1: Try with different encoding
    tryCatch({
      data <- read_sas(sas_path, encoding = "UTF-8")
      cat("[clean_phts] Success with UTF-8 encoding\n")
      return(data)
    }, error = function(e2) {
      cat(sprintf("[clean_phts] UTF-8 encoding failed: %s\n", e2$message))
    })
    
    # Method 2: Try with different catalog file
    tryCatch({
      data <- read_sas(sas_path, catalog_file = NULL)
      cat("[clean_phts] Success without catalog file\n")
      return(data)
    }, error = function(e2) {
      cat(sprintf("[clean_phts] No catalog file failed: %s\n", e2$message))
    })
    
    # Method 3: Try with different haven options
    tryCatch({
      options(haven.show_progress = FALSE)
      data <- read_sas(sas_path)
      cat("[clean_phts] Success with progress disabled\n")
      return(data)
    }, error = function(e2) {
      cat(sprintf("[clean_phts] Progress disabled failed: %s\n", e2$message))
    })
    
    # If all methods fail, provide detailed error
    stop(sprintf("All SAS reading methods failed for '%s'. Original error: %s", sas_path, e$message))
  })
  
  # Process the data
  cat("[clean_phts] Starting data processing pipeline...\n")
  
  out <- out %>%
    filter(TXPL_YEAR >= min_txpl_year) %>% 
    # Keep LSFPRAT and LSFPRAB (PRA at listing) but drop other detailed PRA date fields
    {
      cat("[clean_phts] Filtering PRA columns...\n")
      drop_these <- c(
        'LSPRA','LSCPRAT','LSCPRAB','LSPRADTE','LSPRDTET','LSPRDTEB',
        'LSFCPRA',               # keep LSFPRAT/LSFPRAB below
        'TXCPRA','CPRAT','CPRAB','TXPRADTE','CPRADTET','CPRADTEB',
        'TXFCPRA','FPRAT','FPRAB'
      )
      keep_back <- c('LSFPRAT','LSFPRAB')
      select(., -any_of(setdiff(drop_these, keep_back)))
  } %>%
    {
      cat("[clean_phts] Running clean_names()...\n")
      clean_names(.)
    } %>%
    {
      cat("[clean_phts] Starting mutate() transformations...\n")
      mutate(.,
      ID = 1:n(),
      # prevent improper names if you one-hot encode
      across(
        .cols = where(is.character), 
        ~ clean_chr(.x, case = case, set_to_na = set_to_na)
      ),
      # set event times of 0 to something non-zero but still small
      across(
        .cols = any_of(c('outcome_waitlist_interval', 'int_graft_loss')),
        ~ replace(.x, list = .x == 0, values = 1/365)
      ),
      across(.cols = where(is.character), as.factor),
      # truncate survival data to match prediction horizon
      # int_graft_loss = pmin(int_graft_loss, predict_horizon + 1/365),
      # graft_loss = if_else(
      #   condition = int_graft_loss > predict_horizon, 
      #   true = 0, false = graft_loss 
      # ),
      prim_dx = if ('prim_dx' %in% names(.)) factor(prim_dx) else prim_dx,
      # Create tx_mcsd (with underscore) as derived column
      tx_mcsd = if ('txnomcsd' %in% names(.)) {
        # Convert txnomcsd (no mechanical support) to tx_mcsd (mechanical support indicator)
        if_else(txnomcsd == 'yes', 0, 1)  # 'yes' = no support, so 0; otherwise 1
      } else if ('txmcsd' %in% names(.)) { 
        # Use existing txmcsd column and rename to tx_mcsd
        txmcsd
      } else {
        NA_real_  # Column not found
      }
    )
    } %>%
    {
      cat("[clean_phts] Completed mutate() transformations\n")
      cat(sprintf("[clean_phts] Data dimensions after mutate: %d x %d\n", nrow(.), ncol(.)))
      cat(sprintf("[clean_phts] Column names include time/status columns: time=%s, status=%s\n", 
                  as.character(time_sym) %in% names(.), 
                  as.character(status_sym) %in% names(.)))
      .
    } %>%
    {
      cat(sprintf("[clean_phts] Renaming %s -> time and %s -> status...\n", 
                  as.character(time_sym), as.character(status_sym)))
      rename(.,
        # Rename to final 'time' and 'status' column names using the symbols
        time = !!time_sym,
        status = !!status_sym
      )
    } %>% 
    {
      cat("[clean_phts] Completed rename()\n")
      cat(sprintf("[clean_phts] Final column selection...\n"))
      select(.,
        -any_of(c('txnomcsd','lbun_r'))
      )
    }
  
  cat("[clean_phts] Data processing pipeline completed successfully\n")
  cat(sprintf("[clean_phts] Final data dimensions: %d x %d\n", nrow(out), ncol(out)))
  
  too_many_missing <- miss_var_summary(data = out) %>% 
    filter(pct_miss > 30) %>% 
    pull(variable)

  # Whitelist critical variables even if they exceed missingness threshold
  missing_whitelist <- c('tx_mcsd','txmcsd','chd_sv','lsfprat','lsfprab')  # Include both tx_mcsd and txmcsd for compatibility
  drop_vars <- setdiff(too_many_missing, missing_whitelist)
  if (length(drop_vars)) {
    cat(sprintf("[clean_phts] Dropping %d variables with >30%% missing data\n", length(drop_vars)))
    out[, drop_vars] <- NULL
  }
  
  cat("[clean_phts] Removing redundant listing variables...\n")
  
  # remove some variables that are collected at listing
  # and also at transplant, but don't need to be included
  # in both of the visits:
  
  out <- out %>% 
    select(-any_of(c('height_listing', 'weight_listing')))
  
  if (!dir.exists(here('model_data'))) {
    cat("[clean_phts] Creating model_data directory...\n")
    dir.create(here('model_data'))
  }
  
  cat("[clean_phts] Saving data in dual format (RDS + CSV)...\n")
  
  # Save in dual format (RDS + CSV) for robustness
  tryCatch({
    source(here::here("scripts", "R", "utils", "dual_format_io.R"))
    if (exists("save_dual_format", mode = "function")) {
      save_dual_format(out, here('model_data', 'phts_all'))
      cat("[clean_phts] Saved using dual format\n")
    } else {
      # Fallback to RDS only
      write_rds(out, here('model_data', 'phts_all.rds'))
      cat("[clean_phts] Saved as RDS only (dual format not available)\n")
    }
  }, error = function(e) {
    # Fallback to RDS only if dual format fails
    write_rds(out, here('model_data', 'phts_all.rds'))
    cat(sprintf("[clean_phts] Dual format save failed, used RDS only: %s\n", e$message))
  })
  
  cat(sprintf("[clean_phts] Successfully completed! Returning data with %d rows and %d columns\n", 
              nrow(out), ncol(out)))
  
  # Return the data
  return(out)
}
