# Species Exposure Dashboard - R environment
#
# Based on rocker/geospatial, which already includes the geospatial R stack used
# by this dashboard, including sf, terra, tidyverse, leaflet, knitr, rmarkdown,
# devtools, remotes, and system geospatial libraries.

FROM rocker/geospatial:latest

LABEL org.opencontainers.image.title="Species Exposure Dashboard"
LABEL org.opencontainers.image.source="https://github.com/cmerow/2025_Exposure"
LABEL org.opencontainers.image.description="R and Quarto environment for the Species Exposure Dashboard"

# AWS CLI v2, used to sync species figures to S3.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates less \
    && arch="$(uname -m)" \
    && case "$arch" in \
         x86_64) url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;; \
         aarch64) url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;; \
         *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "$url" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && rm -rf /var/lib/apt/lists/*

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