# =============================================================================
# panel-figures.R
#
# Library: production helpers for building per-raster KDE timeseries figures
# (one figure per species x raster panel).
#
# This file has no script side effects. It defines:
#   - RASTER_CONFIG          : the 6-row raster catalogue (Temp + Precip)
#   - PANEL_SLUG_MAP         : raster_file -> "{family_slug}__{agg_slug}" slug
#                              used in PNG filenames and dashboard checkbox IDs
#   - extract_raster_values  : per-cell timeseries for one raster
#   - compute_var_kde_data   : KDE tile grid + historical ECDF
#   - compute_threshold      : per-raster up/lo exposure threshold
#   - rescale_pct_to_thresholds : aligns per-raster thresholds with global
#                                  color-scale discontinuities
#   - warp_legend_trans      : stretches the cap zones on the colorbar legend
#   - build_single_panel_figure : returns a patchwork (KDE + density) for ONE
#                                  raster, suitable for ggsave()
#   - render_species_panels  : writes the 6 per-species PNGs to out_dir
#
# Designed to be source()d by both:
#   - _R/explorefiguresv3.r   (prototype / regression PNG)
#   - _R/db_4_build-panel-figures.R   (production build pipeline)
# =============================================================================

suppressPackageStartupMessages({
  library(terra)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
  library(patchwork)
})


# =============================================================================
# Constants
# =============================================================================

N_GRID_DEFAULT          <- 300L
PERIOD_BOUNDARY_DEFAULT <- 2022L
N_CELL_LINES_DEFAULT    <- 200L

# Raster catalogue — one row per .tif file under data/rast/. A single raster
# can serve both an upper-extreme variable (up_var) and a lower-extreme
# variable (lo_var), or just one. See explorefiguresv3.r for full doc.
RASTER_CONFIG <- tibble::tribble(
  ~family,         ~raster_file,         ~label,           ~unit,       ~offset, ~up_var,             ~lo_var,             ~color_up,     ~color_lo,
  "Temperature",   "temp__3__max.tif",   "Warmest quarter","\u00b0C",   273.15,  "temp__3__max_up",   NA_character_,       "#f46d43",     NA_character_,
  "Temperature",   "temp__12.tif",       "Annual mean",    "\u00b0C",   273.15,  "temp__12_up",       "temp__12_lo",       "#d73027",     "#313695",
  "Temperature",   "temp__3__min.tif",   "Coldest quarter","\u00b0C",   273.15,  NA_character_,       "temp__3__min_lo",   NA_character_, "#74add1",
  "Precipitation", "precip__3__max.tif", "Seasonal max",   "mm",        0,       "precip__3__max_up", NA_character_,       "#a6d96a",     NA_character_,
  "Precipitation", "precip__12.tif",     "Annual",         "mm",        0,       "precip__12_up",     "precip__12_lo",     "#1a9641",     "#d9a427",
  "Precipitation", "precip__3__min.tif", "Seasonal min",   "mm",        0,       NA_character_,       "precip__3__min_lo", NA_character_, "#fdcc8a"
)

# Slug map: raster_file -> "{family_slug}__{agg_slug}" used in PNG filenames
# and as the stable ID for the dashboard's panel-selection checkbox grid.
# Naming convention: data/species_figs/{species}__{family}__{agg}.png
PANEL_SLUG_MAP <- c(
  "temp__3__max.tif"   = "temperature__seasonal_max",
  "temp__12.tif"       = "temperature__annual",
  "temp__3__min.tif"   = "temperature__seasonal_min",
  "precip__3__max.tif" = "precipitation__seasonal_max",
  "precip__12.tif"     = "precipitation__annual",
  "precip__3__min.tif" = "precipitation__seasonal_min"
)


# =============================================================================
# Helper: extract_raster_values()
# =============================================================================

extract_raster_values <- function(raster_file, range_cells, unit_offset,
                                  rast_dir) {
  r_path <- file.path(rast_dir, raster_file)
  if (!file.exists(r_path)) {
    message(sprintf("  [skip] Raster not found: %s", r_path))
    return(NULL)
  }
  r           <- terra::rast(r_path)
  layer_years <- as.integer(sub("^(WY|X)", "", names(r)))
  raw_mat     <- terra::extract(r, range_cells)

  as.data.frame(raw_mat) |>
    dplyr::mutate(cell = range_cells) |>
    tidyr::pivot_longer(cols = -cell, names_to = "layer", values_to = "raw_val") |>
    dplyr::mutate(
      year  = layer_years[match(layer, names(r))],
      value = raw_val - unit_offset
    ) |>
    dplyr::filter(!is.na(value)) |>
    dplyr::select(cell, year, value)
}


# =============================================================================
# Helper: compute_var_kde_data()
# =============================================================================

compute_var_kde_data <- function(val_long, n_grid = N_GRID_DEFAULT,
                                 period_boundary = PERIOD_BOUNDARY_DEFAULT) {
  range_lines <- val_long |>
    dplyr::group_by(year) |>
    dplyr::summarise(val_min = min(value), val_max = max(value), .groups = "drop")

  val_range <- range(val_long$value)
  grid_vals <- seq(val_range[1], val_range[2], length.out = n_grid)
  grid_step <- diff(grid_vals)[1]
  all_years <- sort(unique(val_long$year))

  hist_ecdf <- stats::ecdf(val_long$value[val_long$year <= period_boundary])

  tiles <- tidyr::expand_grid(year = all_years, val_mid = grid_vals) |>
    dplyr::mutate(pct_range = hist_ecdf(val_mid)) |>
    dplyr::left_join(range_lines, by = "year") |>
    dplyr::filter(val_mid >= val_min - grid_step / 2,
                  val_mid <= val_max + grid_step / 2) |>
    dplyr::mutate(
      ymin = pmax(val_mid - grid_step / 2, val_min),
      ymax = pmin(val_mid + grid_step / 2, val_max)
    )

  list(tiles = tiles, hist_ecdf = hist_ecdf, range_lines = range_lines)
}


# =============================================================================
# Helper: compute_threshold()
# =============================================================================

compute_threshold <- function(val_long, direction,
                              period_boundary = PERIOD_BOUNDARY_DEFAULT) {
  hist <- dplyr::filter(val_long, year <= period_boundary)
  q    <- if (direction == "up") 0.99 else 0.01

  hist |>
    dplyr::group_by(cell) |>
    dplyr::summarise(cell_extreme = quantile(value, q), .groups = "drop") |>
    dplyr::summarise(val = quantile(cell_extreme, q)) |>
    dplyr::pull(val)
}


# =============================================================================
# Helper: rescale_pct_to_thresholds()
# =============================================================================

rescale_pct_to_thresholds <- function(pct, t_lo_pct, t_up_pct) {
  has_lo <- !is.na(t_lo_pct) && t_lo_pct > 0
  has_up <- !is.na(t_up_pct) && t_up_pct < 1

  lo_cap_hi <- 0.0099
  mid_lo    <- 0.0101
  mid_hi    <- 0.9899
  up_cap_lo <- 0.9901

  if (has_lo && has_up) {
    dplyr::case_when(
      pct <= t_lo_pct ~ pct / t_lo_pct * lo_cap_hi,
      pct >= t_up_pct ~ up_cap_lo + (pct - t_up_pct) / (1 - t_up_pct) *
                                    (1 - up_cap_lo),
      TRUE            ~ mid_lo + (pct - t_lo_pct) / (t_up_pct - t_lo_pct) *
                                  (mid_hi - mid_lo)
    )
  } else if (has_up) {
    dplyr::case_when(
      pct >= t_up_pct ~ up_cap_lo + (pct - t_up_pct) / (1 - t_up_pct) *
                                    (1 - up_cap_lo),
      TRUE            ~ mid_lo + pct / t_up_pct * (mid_hi - mid_lo)
    )
  } else if (has_lo) {
    dplyr::case_when(
      pct <= t_lo_pct ~ pct / t_lo_pct * lo_cap_hi,
      TRUE            ~ mid_lo + (pct - t_lo_pct) / (1 - t_lo_pct) *
                                  (mid_hi - mid_lo)
    )
  } else {
    pct
  }
}


# =============================================================================
# Helper: warp_legend_trans()
# =============================================================================

warp_legend_trans <- function() {
  scales::trans_new(
    name      = "warp_legend",
    transform = function(x) {
      out <- x
      lo  <- !is.na(x) & x <= 0.01
      hi  <- !is.na(x) & x >= 0.99
      md  <- !is.na(x) & !lo & !hi
      out[lo] <- x[lo] * 10
      out[hi] <- 0.9 + (x[hi] - 0.99) * 10
      out[md] <- 0.1 + (x[md] - 0.01) * 0.8 / 0.98
      out
    },
    inverse   = function(y) {
      out <- y
      lo  <- !is.na(y) & y <= 0.1
      hi  <- !is.na(y) & y >= 0.9
      md  <- !is.na(y) & !lo & !hi
      out[lo] <- y[lo] / 10
      out[hi] <- 0.99 + (y[hi] - 0.9) / 10
      out[md] <- 0.01 + (y[md] - 0.1) * 0.98 / 0.8
      out
    }
  )
}


# =============================================================================
# build_single_panel_figure()
#
# Build the KDE + density side-by-side patchwork for ONE raster of ONE species.
# Returns a patchwork object (ggplot-class), or NULL if the raster is missing
# or has too few values to build a KDE.
#
# Arguments:
#   cfg_row         single row of RASTER_CONFIG (tibble with 1 row)
#   range_cells     integer vector of terra cell indices for the focal species
#   species_name    character; for title text (underscores → spaces)
#   rast_dir        directory containing the .tif files
#   n_grid          KDE grid resolution
#   period_boundary last year of historical baseline
#   n_cell_lines    max number of cell trajectories to subsample
# =============================================================================

build_single_panel_figure <- function(cfg_row, range_cells, species_name,
                                      rast_dir,
                                      n_grid          = N_GRID_DEFAULT,
                                      period_boundary = PERIOD_BOUNDARY_DEFAULT,
                                      n_cell_lines    = N_CELL_LINES_DEFAULT) {

  stopifnot(is.data.frame(cfg_row), nrow(cfg_row) == 1)
  cfg        <- cfg_row
  unit_label <- cfg$unit

  # --- 1. Extract values ---------------------------------------------------
  vals <- extract_raster_values(cfg$raster_file, range_cells, cfg$offset, rast_dir)
  if (is.null(vals) || nrow(vals) < 2) return(NULL)


  # --- 2. KDE tiles + thresholds -------------------------------------------
  kde_res  <- compute_var_kde_data(vals, n_grid, period_boundary)

  t_up     <- if (!is.na(cfg$up_var)) compute_threshold(vals, "up", period_boundary) else NA_real_
  t_lo     <- if (!is.na(cfg$lo_var)) compute_threshold(vals, "lo", period_boundary) else NA_real_
  t_up_pct <- if (!is.na(t_up)) kde_res$hist_ecdf(t_up) else NA_real_
  t_lo_pct <- if (!is.na(t_lo)) kde_res$hist_ecdf(t_lo) else NA_real_

  tiles_df <- kde_res$tiles |>
    dplyr::mutate(display_pct = rescale_pct_to_thresholds(pct_range, t_lo_pct, t_up_pct))

  thresh_rows <- list()
  if (!is.na(t_up)) {
    thresh_rows$up <- tibble::tibble(
      threshold  = t_up, direction = "up", color = cfg$color_up,
      thresh_lbl = sprintf("99th percentile upper (%.1f %s)", t_up, unit_label),
      text_vjust = -0.4
    )
  }
  if (!is.na(t_lo)) {
    thresh_rows$lo <- tibble::tibble(
      threshold  = t_lo, direction = "lo", color = cfg$color_lo,
      thresh_lbl = sprintf("1st percentile lower (%.1f %s)", t_lo, unit_label),
      text_vjust = 1.4
    )
  }
  thresh_df <- if (length(thresh_rows)) dplyr::bind_rows(thresh_rows) else NULL


  # --- 3. Subsampled cell trajectories -------------------------------------
  set.seed(42)
  cell_sample <- sample(range_cells, min(n_cell_lines, length(range_cells)))
  segs_df <- vals |>
    dplyr::filter(cell %in% cell_sample) |>
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
    dplyr::ungroup()

  segs_normal  <- dplyr::filter(segs_df,  is.na(exp_color))
  segs_exposed <- dplyr::filter(segs_df, !is.na(exp_color))


  # --- 4. Color scale (matches explorefiguresv3.r exactly) -----------------
  cdf_cols <- c("#08306b", "#08306b",
                "#74add1", "#ffffbf", "#fdae61",
                "#67000d", "#67000d")
  cdf_vals <- c(0, 0.0999, 0.1001, 0.5, 0.8999, 0.9001, 1)


  # --- 5. KDE heatmap panel ------------------------------------------------
  p_kde <- ggplot(tiles_df, aes(fill = display_pct)) +
    geom_rect(aes(xmin = year - 0.5, xmax = year + 0.5,
                  ymin = ymin, ymax = ymax)) +
    geom_segment(
      data = segs_normal,
      aes(x = year, xend = year_end, y = value, yend = val_end),
      inherit.aes = FALSE,
      colour = "black", alpha = 0.10, linewidth = 0.20
    ) +
    geom_segment(
      data = segs_exposed,
      aes(x = year, xend = year_end, y = value, yend = val_end,
          colour = I(exp_color)),
      inherit.aes = FALSE,
      alpha = 0.55, linewidth = 0.35
    )

  if (!is.null(thresh_df)) {
    p_kde <- p_kde +
      geom_hline(
        data = thresh_df,
        aes(yintercept = threshold, colour = I(color)),
        linetype = "dashed", linewidth = 0.55, inherit.aes = FALSE
      ) +
      geom_text(
        data = thresh_df,
        aes(x = -Inf, y = threshold, label = thresh_lbl, vjust = text_vjust),
        hjust = -0.03, size = 2.6, colour = "grey25", inherit.aes = FALSE
      )
  }

  p_kde <- p_kde +
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
    scale_y_continuous(name = paste0("Value (", unit_label, ")"),
                       expand = c(0, 0)) +
    theme_minimal(base_size = 11) +
    theme(
      axis.text.x        = element_text(angle = 45, hjust = 1, size = 8),
      panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3),
      panel.grid.major.y = element_blank(),
      panel.grid.minor   = element_blank(),
      legend.position    = "bottom"
    )


  # --- 6. Density side panel -----------------------------------------------
  DENS_ADJUST  <- 0.5
  hist_vals    <- vals$value[vals$year <= period_boundary]
  rast_last_yr <- max(vals$year)
  recent_vals  <- vals$value[vals$year == rast_last_yr]

  if (length(hist_vals) < 2 || length(recent_vals) < 2) {
    # Skip density panel if insufficient data; return just the KDE heatmap.
    y_floor_fb <- if (cfg$family == "Precipitation") 0 else NA_real_
    raw_lo_fb  <- min(tiles_df$ymin)
    raw_hi_fb  <- max(tiles_df$ymax)
    if (!is.na(y_floor_fb)) raw_lo_fb <- max(raw_lo_fb, y_floor_fb)
    p_kde_only <- p_kde + coord_cartesian(
      ylim = c(raw_lo_fb, raw_hi_fb), expand = FALSE
    )
    return(
      p_kde_only +
        patchwork::plot_annotation(
          title    = sprintf("%s \u2014 %s: %s",
                             gsub("_", " ", species_name),
                             cfg$family, cfg$label),
          subtitle = sprintf("Range: %d cells", length(range_cells)),
          theme = theme(plot.title       = element_text(face = "italic", size = 12),
                        plot.subtitle    = element_text(size = 8.5, colour = "grey45"),
                        legend.position  = "bottom",
                        legend.direction = "horizontal")
        )
    )
  }

  dh <- density(hist_vals,   adjust = DENS_ADJUST, n = 256)
  dr <- density(recent_vals, adjust = DENS_ADJUST, n = 256)

  hist_period_lbl <- sprintf("1941\u2013%d", period_boundary)
  last_period_lbl <- as.character(rast_last_yr)

  dens_df <- dplyr::bind_rows(
    tibble::tibble(value = dh$x, density = dh$y / max(dh$y),
                   period = hist_period_lbl),
    tibble::tibble(value = dr$x, density = dr$y / max(dr$y),
                   period = last_period_lbl)
  )

  # --- Shared display y-range -------------------------------------------
  # Compute a single y-window from the actual measured data (NOT the KDE
  # smoothing tails, which extend well past the data and otherwise blow
  # out the axis). Then clip at 0 for non-negative variables (precipitation).
  # Both panels use this exact range so tiles, segments and densities line up.
  y_floor <- if (cfg$family == "Precipitation") 0 else NA_real_

  data_vals <- c(tiles_df$ymin, tiles_df$ymax, segs_df$value,
                 thresh_df$threshold)
  data_min  <- min(data_vals, na.rm = TRUE)
  data_max  <- max(data_vals, na.rm = TRUE)

  if (!is.na(y_floor)) {
    # Floored variables (e.g. precip): bottom is hard-pinned at max(min, floor),
    # no padding below. Top gets symmetric padding only above.
    y_disp_lo <- max(y_floor, data_min)
    pad       <- 0.03 * (data_max - y_disp_lo)
    y_disp_hi <- data_max + pad
  } else {
    pad       <- 0.03 * (data_max - data_min)
    y_disp_lo <- data_min - pad
    y_disp_hi <- data_max + pad
  }

  # Density curve is NOT pre-filtered — coord_cartesian on the density panel
  # clips smoothly at the shared display window so smoothing tails just fade
  # off rather than getting hard-truncated mid-curve.
  dens_df <- dens_df |>
    dplyr::mutate(period = factor(period, levels = c(hist_period_lbl, last_period_lbl)))

  p_kde <- p_kde + coord_cartesian(ylim = c(y_disp_lo, y_disp_hi), expand = FALSE)

  period_cols <- setNames(c("grey45", "#7b2d8b"), c(hist_period_lbl, last_period_lbl))

  p_dens <- ggplot(dens_df, aes(x = value, y = density,
                                colour = period, fill = period)) +
    geom_area(alpha = 0.32, position = "identity", linewidth = 0.55)

  if (!is.null(thresh_df)) {
    p_dens <- p_dens +
      geom_vline(
        data = thresh_df,
        aes(xintercept = threshold, colour = I(color)),
        linetype = "dashed", linewidth = 0.45, inherit.aes = FALSE
      )
  }

  p_dens <- p_dens +
    coord_flip(xlim = c(y_disp_lo, y_disp_hi), ylim = c(0, 1), expand = FALSE) +
    scale_colour_manual(values = period_cols, name = NULL, na.translate = FALSE,
                        guide = "none") +
    scale_fill_manual(values = period_cols, name = NULL, na.translate = FALSE,
                      guide = guide_legend(override.aes = list(colour = NA))) +
    scale_x_continuous(labels = NULL, name = NULL) +
    scale_y_continuous(name = "Density", breaks = c(0, 0.5, 1)) +
    theme_minimal(base_size = 10) +
    theme(panel.grid = element_blank(), legend.position = "bottom")


  # --- 7. Combine ----------------------------------------------------------
  p_kde + p_dens +
    patchwork::plot_layout(widths = c(4, 1), guides = "collect") +
    patchwork::plot_annotation(
      title    = sprintf("%s \u2014 %s: %s",
                         gsub("_", " ", species_name),
                         cfg$family, cfg$label),
      subtitle = sprintf(
        "Background = historical CDF percentile (1941\u2013%d)  |  Range: %d cells",
        period_boundary, length(range_cells)
      ),
      theme = theme(
        plot.title       = element_text(face = "italic", size = 12),
        plot.subtitle    = element_text(size = 8.5, colour = "grey45"),
        legend.position  = "bottom",
        legend.direction = "horizontal"
      )
    )
}


# =============================================================================
# render_species_panels()
#
# Build & write all 6 per-panel PNGs for a single species.
#
# Output filenames: {out_dir}/{species}__{slug}.png  where slug comes from
# PANEL_SLUG_MAP (e.g. "Hynobius_retardatus__temperature__annual.png").
#
# Arguments:
#   species_name    character (underscored, matching allcell$spName)
#   range_cells     integer vector of terra cell indices
#   raster_config   defaults to RASTER_CONFIG
#   rast_dir        directory containing the .tif files
#   out_dir         directory to write PNGs into (created if missing)
#   width, height   PNG dimensions in inches (default 7 x 4 @ dpi 110)
#   dpi             PNG resolution
#   overwrite       FALSE = skip panels whose PNG already exists
#   ...             passed through to build_single_panel_figure()
#
# Returns: character vector of file paths written (or already present when
#          overwrite=FALSE).
# =============================================================================

render_species_panels <- function(species_name, range_cells,
                                  raster_config = RASTER_CONFIG,
                                  rast_dir,
                                  out_dir,
                                  width  = 7,
                                  height = 4,
                                  dpi    = 220,
                                  overwrite = FALSE,
                                  ...) {

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  written <- character()

  for (i in seq_len(nrow(raster_config))) {
    cfg_row  <- raster_config[i, ]
    slug     <- PANEL_SLUG_MAP[[cfg_row$raster_file]]
    if (is.null(slug) || is.na(slug)) {
      message(sprintf("  [skip] No slug for raster %s", cfg_row$raster_file))
      next
    }
    out_path <- file.path(out_dir, sprintf("%s__%s.png", species_name, slug))

    if (!overwrite && file.exists(out_path)) {
      written <- c(written, out_path)
      next
    }

    fig <- tryCatch(
      build_single_panel_figure(cfg_row, range_cells, species_name,
                                rast_dir = rast_dir, ...),
      error = function(e) {
        message(sprintf("  [err] %s / %s: %s",
                        species_name, slug, e$message))
        NULL
      }
    )
    if (is.null(fig)) next

    ggplot2::ggsave(out_path, plot = fig,
                    width = width, height = height, dpi = dpi, bg = "white")
    written <- c(written, out_path)
  }

  written
}
