source("scripts/00_setup.R")

min_txpl_year <- 2010
predict_horizon <- 1
ntimes <- 1000

phts_all <- readRDS(here::here('data', 'phts_all.rds'))

# If reusing base splits, attempt to load base ID list and map to current data
reuse <- tolower(Sys.getenv('REUSE_BASE_SPLITS', unset = '0')) %in% c('1','true','yes','y')
base_ids_path <- here::here('data','resamples_ids_full.rds')

if (reuse && file.exists(base_ids_path)) {
	message('REUSE_BASE_SPLITS=1: loading base ID splits from ', base_ids_path)
	base_id_splits <- readRDS(base_ids_path)
	if (!'ID' %in% names(phts_all)) stop('Cannot reuse splits: ID column missing in current dataset.')
	if (!exists('reuse_resamples')) source(here::here('R','reuse_resamples.R'))
	testing_rows <- reuse_resamples(phts_all, base_id_splits)
	saveRDS(testing_rows, here::here('data','resamples.rds'))
	message('Reused base splits mapped to current dataset: data/resamples.rds (', length(testing_rows),' splits)')
} else {
	# Fresh generation (base case or no reuse requested)
	resamples <- mc_cv_light(phts_all, ntimes = ntimes)
	saveRDS(resamples, file = here::here('data', 'resamples.rds'))
	message('Resamples saved: data/resamples.rds')
	# If this is the full (unfiltered) dataset and we have ID column, persist ID-based test splits for reuse
	if (!reuse && 'ID' %in% names(phts_all)) {
		# mc_cv_light output assumed to be list of test index vectors (row positions)
		base_id_splits <- lapply(resamples, function(idx) phts_all$ID[idx])
		saveRDS(base_id_splits, here::here('data','resamples_ids_full.rds'))
		message('Saved base ID splits: data/resamples_ids_full.rds (', length(base_id_splits),' splits)')
	}
}

