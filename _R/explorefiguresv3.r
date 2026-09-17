# =============================================================================
# explorefiguresv3.r
#
# Prototype / regression driver. The production helpers (RASTER_CONFIG,
# build_single_panel_figure, render_species_panels, etc.) live in
# _R/panel-figures.R — this file sources them, keeps the legacy faceted
# `build_family_kde_figure()` for visual QA, and writes:
#
#   - _test_temperature_kde_facet.png   (legacy faceted figure)
#   - _test_panel_<slug>.png            (a couple of single-panel PNGs to QA
#                                        the production builder)
#
# Usage: source() interactively with SPECIES set below.
# =============================================================================

source("_R/panel-figures.R")


# =============================================================================
# Test configuration — adjust to explore different species
# =============================================================================

DATA_DIR        <- "data"
RAST_DIR        <- file.path(DATA_DIR, "rast")
ALLCELL         <- file.path(DATA_DIR, "AllCellExposureSpXVar.rds")
SPECIES         <- "Hynobius_retardatus"
N_GRID          <- N_GRID_DEFAULT
PERIOD_BOUNDARY <- PERIOD_BOUNDARY_DEFAULT
N_CELL_LINES    <- N_CELL_LINES_DEFAULT


# =============================================================================
# Load species data
# =============================================================================

cat("Loading allcell data...\n")
allcell_all <- readRDS(ALLCELL)
allcell_sp  <- dplyr::filter(allcell_all, spName == SPECIES)
range_cells <- unique(allcell_sp$cell)
range_size  <- allcell_sp$rangeSize[1]
cat(sprintf("Species: %s | range: %d cells\n", SPECIES, range_size))
rm(allcell_all); gc()


# =============================================================================
# Legacy: build_family_kde_figure()
#
# Faceted multi-raster prototype kept for visual regression of the original
# look. Production code paths use build_single_panel_figure() from
# _R/panel-figures.R.
# =============================================================================

build_family_kde_figure <- function(family_name, raster_config, range_cells,
                                    n_grid          = N_GRID,
                                    period_boundary = PERIOD_BOUNDARY,
                                    n_cell_lines    = N_CELL_LINES,
                                    rast_dir        = RAST_DIR) {

  fam_cfg    <- dplyr::filter(raster_config, family == family_name)
  unit_label <- fam_cfg$unit[1]
  cat(sprintf("[%s] Processing %d rasters...\n", family_name, nrow(fam_cfg)))

  rast_data <- list()
  for (i in seq_len(nrow(fam_cfg))) {
    cfg  <- fam_cfg[i, ]
    vals <- extract_raster_values(cfg$raster_file, range_cells, cfg$offset, rast_dir)
    if (!is.null(vals)) rast_data[[cfg$raster_file]] <- vals
  }

  present <- names(rast_data)
  if (length(present) == 0) {
    message(sprintf("[%s] No rasters found — skipping.", family_name))
    return(NULL)
  }
  cat(sprintf("[%s] Loaded %d/%d rasters.\n", family_name, length(present), nrow(fam_cfg)))

  kde_list    <- list()
  range_list  <- list()
  thresh_rows <- list()

  for (rfile in present) {
    cfg     <- dplyr::filter(fam_cfg, raster_file == rfile)
    vals    <- rast_data[[rfile]]
    kde_res <- compute_var_kde_data(vals, n_grid, period_boundary)

    t_up     <- if (!is.na(cfg$up_var)) compute_threshold(vals, "up", period_boundary) else NA_real_
    t_lo     <- if (!is.na(cfg$lo_var)) compute_threshold(vals, "lo", period_boundary) else NA_real_
    t_up_pct <- if (!is.na(t_up)) kde_res$hist_ecdf(t_up) else NA_real_
    t_lo_pct <- if (!is.na(t_lo)) kde_res$hist_ecdf(t_lo) else NA_real_

    kde_list[[rfile]] <- kde_res$tiles |>
      dplyr::mutate(
        raster_id   = cfg$label,
        display_pct = rescale_pct_to_thresholds(pct_range, t_lo_pct, t_up_pct)
      )

    range_list[[rfile]] <- kde_res$range_lines |>
      dplyr::mutate(raster_id = cfg$label)

    if (!is.na(t_up)) {
      thresh_rows[[paste0(rfile, "_up")]] <- tibble::tibble(
        raster_id  = cfg$label,
        threshold  = t_up,
        direction  = "up",
        color      = cfg$color_up,
        thresh_lbl = sprintf("99th percentile upper (%.1f %s)", t_up, unit_label),
        text_vjust = -0.4
      )
      cat(sprintf("  %s [up]: threshold = %.2f %s (CDF pct = %.3f)\n",
                  cfg$label, t_up, unit_label, t_up_pct))
    }

    if (!is.na(t_lo)) {
      thresh_rows[[paste0(rfile, "_lo")]] <- tibble::tibble(
        raster_id  = cfg$label,
        threshold  = t_lo,
        direction  = "lo",
        color      = cfg$color_lo,
        thresh_lbl = sprintf("1st percentile lower (%.1f %s)", t_lo, unit_label),
        text_vjust = 1.4
      )
      cat(sprintf("  %s [lo]: threshold = %.2f %s (CDF pct = %.3f)\n",
                  cfg$label, t_lo, unit_label, t_lo_pct))
    }
  }

  set.seed(42)
  cell_sample <- sample(range_cells, min(n_cell_lines, length(range_cells)))
  seg_list    <- list()

  for (rfile in present) {
    cfg   <- dplyr::filter(fam_cfg, raster_file == rfile)
    vals  <- dplyr::filter(rast_data[[rfile]], cell %in% cell_sample)
    t_up  <- if (!is.na(cfg$up_var)) thresh_rows[[paste0(rfile, "_up")]]$threshold else NA_real_
    t_lo  <- if (!is.na(cfg$lo_var)) thresh_rows[[paste0(rfile, "_lo")]]$threshold else NA_real_

    segs <- vals |>
      dplyr::arrange(cell, year) |>
      dplyr::group_by(cell) |>
      dplyr::mutate(
        year_end   = dplyr::lead(year),
        val_end    = dplyr::lead(value),
        exposed_up = !is.na(t_up) & value > t_up,
        exposed_lo = !is.na(t_lo) & value < t_lo,
        exp_color  = dplyr::case_when(
          exposed_up ~ cfg$color_up,
          exposed_lo ~ cfg$color_lo,
          TRUE       ~ NA_character_
        )
      ) |>
      dplyr::filter(!is.na(year_end)) |>
      dplyr::ungroup() |>
      dplyr::mutate(raster_id = cfg$label)

    seg_list[[rfile]] <- segs
  }

  label_order  <- dplyr::filter(fam_cfg, raster_file %in% present)$label

  tiles_df    <- dplyr::bind_rows(kde_list) |>
    dplyr::mutate(raster_id = factor(raster_id, levels = label_order))
  envelope_df <- dplyr::bind_rows(range_list) |>
    dplyr::mutate(raster_id = factor(raster_id, levels = label_order))
  segs_df     <- dplyr::bind_rows(seg_list) |>
    dplyr::mutate(raster_id = factor(raster_id, levels = label_order))
  thresh_df   <- dplyr::bind_rows(thresh_rows) |>
    dplyr::mutate(raster_id = factor(raster_id, levels = label_order))

  segs_normal  <- dplyr::filter(segs_df,  is.na(exp_color))
  segs_exposed <- dplyr::filter(segs_df, !is.na(exp_color))

  cdf_cols <- c("#08306b", "#08306b",
                "#74add1", "#ffffbf", "#fdae61",
                "#67000d", "#67000d")
  cdf_vals <- c(0, 0.0999, 0.1001, 0.5, 0.8999, 0.9001, 1)

  p_kde <- ggplot(tiles_df, aes(fill = display_pct)) +
    geom_rect(aes(xmin = year - 0.5, xmax = year + 0.5,
                  ymin = ymin, ymax = ymax)) +
    geom_segment(
      data        = segs_normal,
      aes(x = year, xend = year_end, y = value, yend = val_end),
      inherit.aes = FALSE,
      colour = "black", alpha = 0.10, linewidth = 0.20
    ) +
    geom_segment(
      data        = segs_exposed,
      aes(x = year, xend = year_end, y = value, yend = val_end,
          colour = I(exp_color)),
      inherit.aes = FALSE,
      alpha = 0.55, linewidth = 0.35
    ) +
    geom_hline(
      data        = thresh_df,
      aes(yintercept = threshold, colour = I(color)),
      linetype    = "dashed", linewidth = 0.55,
      inherit.aes = FALSE
    ) +
    geom_text(
      data        = thresh_df,
      aes(x = -Inf, y = threshold,
          label = thresh_lbl,
          vjust = text_vjust),
      hjust       = -0.03, size = 2.6, colour = "grey25",
      inherit.aes = FALSE
    ) +
    facet_grid(rows = vars(raster_id), scales = "free_y", switch = "y") +
    scale_fill_gradientn(
      name    = "Position vs. historical thresholds",
      colours = cdf_cols,
      values  = cdf_vals,
      trans   = warp_legend_trans(),
      limits  = c(0, 1),
      breaks  = c(0, 0.01, 0.5, 0.99, 1),
      labels  = c("Min", "1%", "Median", "99%", "Max")
    ) +
    guides(fill = guide_colorbar(direction = "horizontal", title.position = "top",
                                 barwidth = 13, barheight = 0.5,
                                 label.theme = element_text(angle = 45, hjust = 1, size = 8))) +
    scale_x_continuous(name = "Year",
                       breaks = seq(1950, 2030, by = 10), expand = c(0, 0)) +
    scale_y_continuous(
      name   = paste0("Value (", unit_label, ")"),
      expand = c(0.05, 0.05)
    ) +
    theme_minimal(base_size = 11) +
    theme(
      strip.background   = element_rect(fill = "grey93", colour = "grey72"),
      strip.text         = element_text(size = 9, face = "bold"),
      strip.text.y.left  = element_text(angle = 90),
      strip.placement    = "outside",
      axis.text.x        = element_text(angle = 45, hjust = 1, size = 8),
      panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3),
      panel.grid.major.y = element_blank(),
      panel.grid.minor   = element_blank(),
      legend.position    = "bottom"
    )

  DENS_ADJUST  <- 0.5
  dens_rows    <- list()
  last_yr_lbl  <- min(vapply(rast_data, function(d) max(d$year), integer(1)))

  for (rfile in present) {
    cfg          <- dplyr::filter(fam_cfg, raster_file == rfile)
    vals         <- rast_data[[rfile]]
    hist_vals    <- vals$value[vals$year <= period_boundary]
    rast_last_yr <- max(vals$year)
    recent_vals  <- vals$value[vals$year == rast_last_yr]
    if (length(hist_vals) < 2 || length(recent_vals) < 2) next

    dh <- density(hist_vals,   adjust = DENS_ADJUST, n = 256)
    dr <- density(recent_vals, adjust = DENS_ADJUST, n = 256)

    dens_rows[[rfile]] <- dplyr::bind_rows(
      tibble::tibble(
        value     = dh$x,
        density   = dh$y / max(dh$y),
        period    = sprintf("1941\u2013%d", period_boundary),
        raster_id = cfg$label
      ),
      tibble::tibble(
        value     = dr$x,
        density   = dr$y / max(dr$y),
        period    = as.character(last_yr_lbl),
        raster_id = cfg$label
      )
    )
  }

  row_y_ranges <- tiles_df |>
    dplyr::group_by(raster_id) |>
    dplyr::summarise(v_lo = min(ymin), v_hi = max(ymax), .groups = "drop")

  anchor_rows <- dplyr::bind_rows(
    dplyr::transmute(row_y_ranges, raster_id = as.character(raster_id),
                     value = v_lo, density = 0, period = NA_character_),
    dplyr::transmute(row_y_ranges, raster_id = as.character(raster_id),
                     value = v_hi, density = 0, period = NA_character_)
  )

  dens_df <- dplyr::bind_rows(dens_rows) |>
    dplyr::bind_rows(anchor_rows) |>
    dplyr::mutate(
      raster_id = factor(raster_id, levels = label_order),
      period    = factor(period, levels = c(
        sprintf("1941\u2013%d", period_boundary), as.character(last_yr_lbl)
      ))
    )

  period_cols <- setNames(
    c("grey45", "#7b2d8b"),
    c(sprintf("1941\u2013%d", period_boundary), as.character(last_yr_lbl))
  )

  p_dens <- ggplot(dens_df, aes(x = value, y = density,
                                colour = period, fill = period)) +
    geom_area(alpha = 0.32, position = "identity", linewidth = 0.55) +
    geom_vline(
      data        = thresh_df,
      aes(xintercept = threshold, colour = I(color)),
      linetype    = "dashed", linewidth = 0.45,
      inherit.aes = FALSE
    ) +
    facet_grid(rows = vars(raster_id), scales = "free") +
    coord_flip() +
    scale_colour_manual(values = period_cols, name = NULL, na.translate = FALSE,
                        guide = "none") +
    scale_fill_manual(values   = period_cols, name = NULL, na.translate = FALSE,
                      guide = guide_legend(override.aes = list(colour = NA))) +
    scale_x_continuous(labels = NULL, name = NULL,
                       expand = c(0, 0)) +
    scale_y_continuous(name = "Density", breaks = c(0, 0.5, 1), expand = c(0, 0)) +
    theme_minimal(base_size = 10) +
    theme(
      strip.text      = element_blank(),
      panel.grid      = element_blank(),
      legend.position = "bottom"
    )

  p_kde + p_dens +
    patchwork::plot_layout(widths = c(4, 1), guides = "collect") +
    patchwork::plot_annotation(
      title    = sprintf("%s \u2014 %s distribution",
                         gsub("_", " ", SPECIES), family_name),
      subtitle = sprintf(
        "Background = historical CDF percentile (1941\u2013%d)  |  Range: %d cells  |  %d cell trajectories subsampled",
        period_boundary, length(range_cells), min(n_cell_lines, length(range_cells))
      ),
      theme = theme(
        plot.title       = element_text(face = "italic", size = 13),
        plot.subtitle    = element_text(size = 8.5, colour = "grey45"),
        legend.position  = "bottom",
        legend.direction = "horizontal"
      )
    )
}


# =============================================================================
# Test 1: Legacy faceted Temperature figure (visual regression)
# =============================================================================

cat("\n--- Test 1: Legacy faceted Temperature figure ---\n")
fig_temp_facet <- build_family_kde_figure(
  family_name   = "Temperature",
  raster_config = RASTER_CONFIG,
  range_cells   = range_cells
)

if (!is.null(fig_temp_facet)) {
  out_path <- "_test_temperature_kde_facet.png"
  ggplot2::ggsave(out_path, fig_temp_facet,
                  width = 14, height = 11, dpi = 110, bg = "white")
  cat(sprintf("Saved: %s\n", out_path))
}


# =============================================================================
# Test 2: Single-panel production builder (smoke test for db_4 pipeline)
# Writes the 6 PNGs to ./ with the "_test_panel_" prefix so they don't
# collide with real species_figs/.
# =============================================================================

cat("\n--- Test 2: Single-panel production builder ---\n")
test_panel_dir <- "."
written <- render_species_panels(
  species_name  = SPECIES,
  range_cells   = range_cells,
  raster_config = RASTER_CONFIG,
  rast_dir      = RAST_DIR,
  out_dir       = test_panel_dir,
  overwrite     = TRUE
)
# Rename to "_test_panel_<slug>.png" so test outputs are obvious / ignorable.
for (p in written) {
  base <- basename(p)
  new  <- file.path(test_panel_dir,
                    sub(paste0("^", SPECIES, "__"), "_test_panel_", base))
  if (p != new) file.rename(p, new)
  cat(sprintf("Saved: %s\n", new))
}
