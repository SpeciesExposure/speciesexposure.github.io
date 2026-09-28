species_figure_path <- function(root_dir, species_name, filename) {
  shard <- substr(tolower(species_name), 1L, 2L)
  if (nchar(shard) < 2L) shard <- paste0(shard, "_")
  file.path(root_dir, shard, filename)
}