cat("\n\n##############################################\n")
cat(sprintf("### STARTING STEP: 02_resampling.R [%s] ###\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
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
cat("\n[02_resampling.R] Starting resampling script\n")
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")
log_file <- switch(Sys.getenv("DATASET_COHORT", unset = ""),
	original = "logs/orch_bg_original_study.log",
	full_with_covid = "logs/orch_bg_full_with_covid.log",
	full_without_covid = "logs/orch_bg_full_without_covid.log",
	"logs/orch_bg_unknown.log"
)
cat("Log file path: ", log_file, "\n")
cat("[02_resampling.R] Diagnostic output complete\n\n")

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
# Note: Logging is managed by run_pipeline.R orchestrator
# Individual pipeline scripts should not set up their own sink/on.exit handlers
# to avoid conflicts with the parent script's logging management

source("pipeline/00_setup.R")

min_txpl_year <- 2010
predict_horizon <- 1
ntimes <- as.integer(Sys.getenv("MC_TIMES", "25"))

phts_all <- readRDS(here::here('model_data', 'phts_all.rds'))

# CRITICAL DEBUG: Check data before resampling
cat("\n[DEBUG] ===== PRE-RESAMPLING CHECKS =====\n")
cat(sprintf("[DEBUG] phts_all dimensions: %d x %d\n", nrow(phts_all), ncol(phts_all)))
cat(sprintf("[DEBUG] ntimes (resamples): %d\n", ntimes))
cat(sprintf("[DEBUG] Required columns present:\n"))
cat(sprintf("[DEBUG]   - time: %s\n", 'time' %in% names(phts_all)))
cat(sprintf("[DEBUG]   - status: %s\n", 'status' %in% names(phts_all)))
cat(sprintf("[DEBUG]   - ID: %s\n", 'ID' %in% names(phts_all)))
if ('status' %in% names(phts_all)) {
  cat(sprintf("[DEBUG] Status summary: %s\n", paste(table(phts_all$status), collapse = " / ")))
}
cat("[DEBUG] =====================================\n\n")
flush.console()

# If reusing base splits, attempt to load base ID list and map to current data
reuse <- tolower(Sys.getenv('REUSE_BASE_SPLITS', unset = '0')) %in% c('1','true','yes','y')
base_ids_path <- here::here('model_data','resamples_ids_full.rds')

if (reuse && file.exists(base_ids_path)) {
	cat("[Progress] REUSE_BASE_SPLITS=1: loading base ID splits from", base_ids_path, "\n")
	flush.console()
	tryCatch({
		base_id_splits <- readRDS(base_ids_path)
		if (!'ID' %in% names(phts_all)) stop('Cannot reuse splits: ID column missing in current dataset.')
		if (!exists('reuse_resamples')) source(here::here('scripts','R','reuse_resamples.R'))
		testing_rows <- reuse_resamples(phts_all, base_id_splits)
		saveRDS(testing_rows, here::here('model_data','resamples.rds'))
		cat(sprintf("[Progress] ✓ Reused base splits mapped to current dataset: model_data/resamples.rds (%d splits)\n", length(testing_rows)))
	}, error = function(e) {
		cat(sprintf("[ERROR] Failed to reuse base splits: %s\n", conditionMessage(e)))
		cat("[ERROR] Falling back to fresh generation...\n")
		reuse <<- FALSE
	})
}

if (!reuse) {
	# Fresh generation (base case or no reuse requested)
	cat("[Progress] Generating fresh resamples with mc_cv_light...\n")
	flush.console()
	tryCatch({
		resamples_start_time <- Sys.time()
		resamples <- mc_cv_light(phts_all, ntimes = ntimes)
		resamples_end_time <- Sys.time()
		
		saveRDS(resamples, file = here::here('model_data', 'resamples.rds'))
		cat(sprintf("[Progress] ✓ Resamples saved: model_data/resamples.rds (%.2f seconds)\n", 
		           as.numeric(difftime(resamples_end_time, resamples_start_time, units = "secs"))))
		
		# Verify the file was saved
		if (file.exists(here::here('model_data', 'resamples.rds'))) {
			cat(sprintf("[Progress] ✓ Verified: resamples.rds exists (%.2f MB)\n", 
			           file.size(here::here('model_data', 'resamples.rds'))/1024/1024))
		} else {
			cat("[ERROR] ✗ resamples.rds was not saved!\n")
		}
		
	}, error = function(e) {
		cat(sprintf("[ERROR] ✗ mc_cv_light failed: %s\n", conditionMessage(e)))
		cat(sprintf("[ERROR] Traceback: %s\n", paste(sys.calls(), collapse = " -> ")))
		stop("Resampling failed - cannot proceed to next step")
	})
	
	# If this is the full (unfiltered) dataset and we have ID column, persist ID-based test splits for reuse
	if ('ID' %in% names(phts_all)) {
		# mc_cv_light output assumed to be list of test index vectors (row positions)
		base_id_splits <- lapply(resamples, function(idx) phts_all$ID[idx])
		saveRDS(base_id_splits, here::here('model_data','resamples_ids_full.rds'))
		message('Saved base ID splits: model_data/resamples_ids_full.rds (', length(base_id_splits),' splits)')
	}
}

# End of script resource monitoring
step_end_time <- Sys.time()
cat(sprintf("[Resource] End: %s\n", format(step_end_time, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("[Resource] Elapsed: %.2f sec\n", as.numeric(difftime(step_end_time, step_start_time, units = "secs"))))
cat(sprintf("[Resource] Memory used: %.2f MB\n", sum(gc()[,2])))

cat("\n")
cat(paste(rep("=", 60), collapse = ""))
cat("\n[SUCCESS] ✓ Step 02 (Resampling) completed successfully!\n")
cat(paste(rep("=", 60), collapse = ""))
cat("\n")
flush.console()

