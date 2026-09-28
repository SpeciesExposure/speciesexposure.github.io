# Species Exposure Dashboard

A global interactive dashboard tracking how much of each species' geographic range has been exposed to extreme climate events—temperatures and precipitation outside the historical baseline.

## Overview

This dashboard uses ERA5 reanalysis data to quantify species exposure to climate extremes across their entire geographic range. It provides insights into which species, regions, and climate variables are most affected by extreme conditions.

**Explore the dashboard:** [Species Exposure Dashboard](https://speciesexposure.github.io/)

## What You Can Explore

- **Species Explorer** — Select any species to view its historical exposure time series, a polar summary of which climate variables have affected it most, and a map of its geographic range.

- **Hotspot Explorer** — Click any grid cell on the global map to see all species present there and how many are currently exposed to extreme conditions.

- **Shiny App** — For more flexible filtering and custom data exploration, download and run the full interactive Shiny app from [github.com/SpeciesExposure/exposureApp](https://github.com/SpeciesExposure/exposureApp).

## Data & Methods

### Climate Variables Tracked

Eight ERA5-derived extremes, covering both tails of temperature and precipitation at annual and seasonal timescales:

- High temperature (annual)
- Low temperature (annual)
- High temperature (warmest 3 months)
- Low temperature (coldest 3 months)
- High precipitation (annual)
- Low precipitation (annual)
- High precipitation (wettest 3 months)
- Low precipitation (driest 3 months)

### Data Sources

- **[ERA5 Reanalysis](https://www.ecmwf.int/en/forecasts/dataset/ecmwf-reanalysis-v5)** (ECMWF) — Climate variables on a 0.25° global grid, 1940–present
- **[IUCN Red List](https://www.iucnredlist.org/)** — Species range polygons and conservation status

### Spatial Resolution

0.25° (~28 km) global grid

## Installation & Usage

### Interactive Dashboard

The dashboard is hosted online and requires no installation:

1. Visit [speciesexposure.github.io](https://speciesexposure.github.io/)
2. Explore species and hotspots directly in your browser

### Local Shiny App

For custom filtering and advanced analysis, install the interactive Shiny app:

```r
install.packages(
  "https://github.com/SpeciesExposure/exposureApp/archive/refs/heads/main.tar.gz",
  repos = NULL,
  type = "source"
)

exposureApp::exposureApp()
```

### Build Locally

To build the dashboard locally:

```bash
git clone <this-repo>
cd exposureWeb
Rscript build.R
```

Or render only (after caches/figures exist):

```bash
quarto render index.qmd
```

Requirements:
- [Quarto](https://quarto.org/)
- R with packages: dplyr, ggplot2, plotly, leaflet, jsonlite, leaflet.extras, DT, terra

### Species allowlist (GitHub Pages size)

The static site only includes species listed in [`config/species-allowlist.csv`](config/species-allowlist.csv) (column `species`). The build applies this filter in `_R/db_01_prepare-data.R` and prunes stale per-species maps/figures so they are not republished.

To change the set later:

1. Edit `config/species-allowlist.csv` (or replace it with a new CSV that has a `species` column; spaces or underscores are fine).
2. Rebuild with `Rscript build.R`.

Overrides:

```bash
SPECIES_ALLOWLIST=/path/to/other.csv Rscript build.R   # custom list
SPECIES_ALLOWLIST=off Rscript build.R                  # all species in source data
DEV_N_SPECIES=10 Rscript build.R                       # first N after allowlist (dev)
```

## Project Structure

- `index.qmd` — Main dashboard definition (Quarto document)
- `_R/` — R scripts for data processing and figure generation
- `config/species-allowlist.csv` — Species included in the static dashboard build
- `data/` — Pre-computed cache files and source data
- `_site/` — Built dashboard output

## Related Projects

- **[SpeciesExposure/exposureApp](https://github.com/SpeciesExposure/exposureApp)** — Interactive Shiny app for local filtering and analysis
- **[cmerow/2025_Exposure](https://github.com/cmerow/2025_Exposure)** — Source code and documentation

## License

See the LICENSE file in the repository.

## Contact & Citation

For questions or citations, please refer to the [GitHub organization](https://github.com/SpeciesExposure).
