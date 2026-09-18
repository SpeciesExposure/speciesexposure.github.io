# Species Exposure Dashboard - R environment
#
# Based on rocker/geospatial, which already includes the geospatial R stack used
# by this dashboard, including sf, terra, tidyverse, leaflet, knitr, rmarkdown,
# devtools, remotes, and system geospatial libraries.

FROM rocker/geospatial:latest

LABEL org.opencontainers.image.title="Species Exposure Dashboard"
LABEL org.opencontainers.image.source="https://github.com/cmerow/2025_Exposure"
LABEL org.opencontainers.image.description="R and Quarto environment for the Species Exposure Dashboard"

# Additional packages used by build.R, index.qmd, and the project helper scripts.
RUN install2.r --error --skipinstalled \
    qs2 \
    plotly \
    DT \
    leaflet.extras \
    patchwork \
    base64enc \
    scales \
    raster \
    jsonlite \
    quarto \
    languageserver \
    && rm -rf /tmp/downloaded_packages