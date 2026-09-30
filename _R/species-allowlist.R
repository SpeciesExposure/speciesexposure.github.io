# =============================================================================
# species-allowlist.R
#
# Shared helpers for restricting the Species Explorer to an allowlist CSV.
# The Hotspot Explorer is not filtered by this list.
# Default list: config/species-allowlist.csv (column `species`).
#
# Environment variables:
#   SPECIES_ALLOWLIST
#     - unset / empty: use config/species-allowlist.csv if that file exists
#     - path to a CSV: use that file
#     - "off" / "none" / "0": disable allowlist filtering (all species in data)
#
# Species names in the CSV may use spaces ("Genus species"); data keys use
# underscores ("Genus_species"). Matching normalizes spaces → underscores.
# =============================================================================

normalize_species_name <- function(x) {
  x <- as.character(x)
  x <- trimws(x)
  gsub("[[:space:]]+", "_", x)
}

resolve_species_allowlist_path <- function(
    default_path = file.path("config", "species-allowlist.csv")
) {
  raw <- Sys.getenv("SPECIES_ALLOWLIST", unset = NA_character_)
  if (!is.na(raw)) {
    raw <- trimws(raw)
    if (raw %in% c("off", "none", "0")) {
      return(NULL)
    }
    if (nzchar(raw)) {
      return(raw)
    }
  }
  if (file.exists(default_path)) {
    return(default_path)
  }
  NULL
}

read_species_allowlist <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("[allowlist] File not found: %s", path))
  }
  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!"species" %in% names(df)) {
    stop(sprintf(
      "[allowlist] CSV must have a 'species' column (found: %s)",
      paste(names(df), collapse = ", ")
    ))
  }
  sp <- unique(normalize_species_name(df$species))
  sp <- sp[!is.na(sp) & nzchar(sp)]
  if (!length(sp)) {
    stop(sprintf("[allowlist] No species names found in: %s", path))
  }
  sp
}

# Restrict a species character vector to the allowlist.
# Returns list(species = ..., path = ..., n_before = ..., n_after = ...,
#              n_missing = ...).
apply_species_allowlist <- function(all_species, path = resolve_species_allowlist_path()) {
  all_species <- as.character(all_species)
  n_before <- length(all_species)
  if (is.null(path)) {
    return(list(
      species   = all_species,
      path      = NULL,
      n_before  = n_before,
      n_after   = n_before,
      n_missing = 0L,
      missing   = character(0)
    ))
  }

  allow <- read_species_allowlist(path)
  # Preserve allowlist order for species present in the data
  kept <- allow[allow %in% all_species]
  missing <- setdiff(allow, all_species)

  list(
    species   = kept,
    path      = path,
    n_before  = n_before,
    n_after   = length(kept),
    n_missing = length(missing),
    missing   = missing
  )
}

# Parse the species key from a static asset basename.
# Conventions: "{sp}_map.json", "{sp}_polar.png", "{sp}__{panel_slug}.png"
species_key_from_asset <- function(basename) {
  if (grepl("_map\\.json$", basename, perl = TRUE)) {
    return(sub("_map\\.json$", "", basename, perl = TRUE))
  }
  if (grepl("_polar\\.png$", basename, perl = TRUE)) {
    return(sub("_polar\\.png$", "", basename, perl = TRUE))
  }
  if (grepl("__", basename, fixed = TRUE)) {
    return(sub("__.*$", "", basename, perl = TRUE))
  }
  NA_character_
}

# Remove stale per-species static assets that are not in the active species set.
prune_species_static_assets <- function(
    species,
    dirs = c(
      file.path(Sys.getenv("CACHE_DIR", "data"), "species_figs"),
      file.path(Sys.getenv("CACHE_DIR", "data"), "species_maps")
    )
) {
  species_set <- unique(as.character(species))
  if (!length(species_set)) {
    return(invisible(0L))
  }
  n_removed <- 0L

  for (dir in dirs) {
    if (!dir.exists(dir)) next
    files <- list.files(dir, full.names = TRUE, recursive = FALSE)
    if (!length(files)) next

    keys <- vapply(basename(files), species_key_from_asset, character(1))
    drop <- files[is.na(keys) | !keys %in% species_set]
    if (length(drop)) {
      file.remove(drop)
      n_removed <- n_removed + length(drop)
      cat(sprintf(
        "[allowlist] Pruned %d stale file(s) from %s\n",
        length(drop), dir
      ))
    }
  }

  invisible(n_removed)
}
