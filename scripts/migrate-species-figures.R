#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
apply_changes <- "--apply" %in% args
remove_flat <- "--remove-flat" %in% args
unknown_args <- setdiff(args, c("--apply", "--remove-flat"))
if (length(unknown_args)) {
  stop("Unknown argument(s): ", paste(unknown_args, collapse = ", "))
}
if (remove_flat && !apply_changes) {
  stop("--remove-flat requires --apply")
}

root_dir <- Sys.getenv("FIGURES_DIR", "data/species_figs")
if (!dir.exists(root_dir)) stop("Figure directory not found: ", root_dir)

figure_species <- function(filename) {
  suffix <- "(_polar|_kde|__(temperature|precipitation)__(seasonal_max|annual|seasonal_min))\\.png$"
  species <- sub(suffix, "", filename)
  if (identical(species, filename) || !nzchar(species)) return(NA_character_)
  species
}

flat_files <- list.files(root_dir, pattern = "\\.png$", full.names = TRUE, recursive = FALSE)
if (!length(flat_files)) {
  message("No flat PNG files found; nothing to migrate.")
  quit(status = 0)
}

filenames <- basename(flat_files)
species <- vapply(filenames, figure_species, character(1))
if (anyNA(species)) {
  bad <- filenames[is.na(species)]
  stop("Unrecognized figure filename(s): ", paste(head(bad, 10L), collapse = ", "))
}

shards <- substr(tolower(species), 1L, 2L)
shards[nchar(shards) < 2L] <- paste0(shards[nchar(shards) < 2L], "_")
targets <- file.path(root_dir, shards, filenames)
existing <- file.exists(targets)

if (any(existing & file.info(flat_files)$size != file.info(targets)$size)) {
  stop("Existing target differs in size: ", targets[which(existing & file.info(flat_files)$size != file.info(targets)$size)[1L]])
}

message(sprintf("Flat PNGs: %d; already sharded: %d", length(flat_files), sum(existing)))
if (!apply_changes) {
  message("Dry run only. Re-run with --apply to create sharded hard links.")
  quit(status = 0)
}

for (index in which(!existing)) {
  dir.create(dirname(targets[index]), recursive = TRUE, showWarnings = FALSE)
  if (!file.link(flat_files[index], targets[index])) {
    if (!file.copy(flat_files[index], targets[index], copy.date = TRUE)) {
      stop("Failed to copy: ", flat_files[index])
    }
  }
}

if (!all(file.exists(targets))) stop("Migration verification failed: missing target files")
if (!identical(unname(file.info(flat_files)$size), unname(file.info(targets)$size))) {
  stop("Migration verification failed: file sizes differ")
}

if (remove_flat) {
  if (!all(file.remove(flat_files))) stop("Failed to remove one or more flat source files")
}

message(sprintf("Migration complete: %d sharded PNGs", length(targets)))