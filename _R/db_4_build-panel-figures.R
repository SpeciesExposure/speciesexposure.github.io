# =============================================================================
# db_4_build-panel-figures.R
#
# Build per-species, per-raster panel PNGs into data/species_figs/.
# Each species produces up to 6 files: {species}__{family}__{agg}.png
# (see PANEL_SLUG_MAP in _R/panel-figures.R).
#
# Output filenames are stable and content-agnostic, so the dashboard can
# request them directly via `<img src="data/species_figs/${sp}__${slug}.png">`.
#
# Usage:
#   Rscript _R/db_4_build-panel-figures.R
#
# Environment variables (optional):
#   DATA_DIR        path to data dir         (default: data)
#   CACHE_DIR       path to write outputs    (default: data)
#   DEV_N_SPECIES   limit to first N species (default: all)
#   OVERWRITE_PANELS  "1" to re-render existing PNGs (default: skip-if-exists)
# =============================================================================

source("_R/panel-figures.R")


# =============================================================================
# 1. Paths and config
# =============================================================================

data_dir  <- Sys.getenv("DATA_DIR",  "data")
cache_dir <- Sys.getenv("CACHE_DIR", "data")
rast_dir  <- file.path(data_dir, "rast")
out_dir   <- file.path(cache_dir, "species_figs")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

allcell_path  <- file.path(data_dir, "AllCellExposureSpXVar.rds")
ts_cache_path <- file.path(data_dir, "species-timeseries-cache.rds")

for (p in c(allcell_path, ts_cache_path)) {
  if (!file.exists(p)) stop(sprintf("[panel-figs] Required file not found: %s", p))
}

overwrite_panels <- isTRUE(Sys.getenv("OVERWRITE_PANELS") == "1")


# =============================================================================
# 2. Load data (once, shared across all species)
# =============================================================================

cat("[panel-figs] Loading allcell data...\n")
allcell_df   <- readRDS(allcell_path)
allcell_list <- split(allcell_df, allcell_df$spName)
cat(sprintf("[panel-figs] allcell: %d species\n", length(allcell_list)))
rm(allcell_df); gc()

cat("[panel-figs] Loading timeseries cache to determine species roster...\n")
ts_cache    <- readRDS(ts_cache_path)
all_species <- names(ts_cache)
rm(ts_cache); gc()

# DEV MODE
dev_n <- suppressWarnings(as.integer(Sys.getenv("DEV_N_SPECIES", "")))
if (!is.na(dev_n) && dev_n > 0) {
  all_species <- head(all_species, dev_n)
  cat(sprintf("[panel-figs] DEV MODE: limiting to first %d species\n", dev_n))
}

cat(sprintf("[panel-figs] Building panel figures for %d species (overwrite=%s)\n",
            length(all_species), overwrite_panels))


# =============================================================================
# 3. Loop over species
# =============================================================================

t0 <- Sys.time()
n_ok   <- 0L
n_skip <- 0L
n_err  <- 0L

for (i in seq_along(all_species)) {
  sp <- all_species[i]
  allcell_sp <- allcell_list[[sp]]

  if (is.null(allcell_sp) || nrow(allcell_sp) == 0) {
    n_skip <- n_skip + 1L
    next
  }

  range_cells <- unique(allcell_sp$cell)

  # Cheap pre-skip: if all 6 PNGs already exist and overwrite is off,
  # don't even open the rasters.
  if (!overwrite_panels) {
    expected <- file.path(out_dir,
                          sprintf("%s__%s.png", sp, PANEL_SLUG_MAP))
    if (all(file.exists(expected))) {
      n_skip <- n_skip + 1L
      if (i %% 100L == 0L) {
        cat(sprintf("[panel-figs] (%d/%d) %s — all panels exist, skip\n",
                    i, length(all_species), sp))
      }
      next
    }
  }

  ok <- tryCatch({
    render_species_panels(
      species_name  = sp,
      range_cells   = range_cells,
      raster_config = RASTER_CONFIG,
      rast_dir      = rast_dir,
      out_dir       = out_dir,
      overwrite     = overwrite_panels
    )
    TRUE
  }, error = function(e) {
    message(sprintf("[panel-figs] [err] %s: %s", sp, e$message))
    FALSE
  })

  if (ok) n_ok <- n_ok + 1L else n_err <- n_err + 1L

  if (i %% 25L == 0L || i == length(all_species)) {
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    cat(sprintf("[panel-figs] (%d/%d) %s — ok=%d skip=%d err=%d (%.1fs)\n",
                i, length(all_species), sp, n_ok, n_skip, n_err, elapsed))
  }
}

cat(sprintf("\n[panel-figs] Done. ok=%d skip=%d err=%d total=%d in %.1fs\n",
            n_ok, n_skip, n_err, length(all_species),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
