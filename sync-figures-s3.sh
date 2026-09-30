#!/usr/bin/env sh
# Sync project images to S3 and drop any copy under _site/ so GitHub Pages
# does not receive the figure tree.
set -eu

bucket="${FIGURE_BUCKET:-species-exposure}"
cache_control="public, max-age=86400"

if [ ! -f config/figure-base-url.txt ]; then
  echo "config/figure-base-url.txt is missing" >&2
  exit 1
fi

base_url=$(tr -d '[:space:]' < config/figure-base-url.txt)
base_url=${base_url%/}
domain=${base_url#https://}
domain=${domain#http://}

if [ ! -d data/species_figs ]; then
  echo "data/species_figs not found" >&2
  exit 1
fi

# Dashboard URLs are flat: species_figs/{species}_polar.png and
# species_figs/{species}__{slug}.png. Prefix folders (ab/, ac/, ...) are
# duplicate copies of those files, so they are not uploaded.
echo "Syncing species figures to s3://${bucket}/species_figs"
aws s3 sync data/species_figs "s3://${bucket}/species_figs" \
  --exclude "*" \
  --include "*.png" \
  --exclude "*/*" \
  --cache-control "${cache_control}" \
  --delete

if [ -d img ]; then
  echo "Syncing img to s3://${bucket}/img"
  aws s3 sync img "s3://${bucket}/img" \
    --exclude "*" \
    --include "*.png" \
    --cache-control "${cache_control}" \
    --delete
fi

# Best-effort. The sync user may not be allowed to list or invalidate
# distributions. Objects remain usable and refresh within max-age.
dist_id="${CLOUDFRONT_DISTRIBUTION_ID:-}"
if [ -z "${dist_id}" ]; then
  dist_id=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?DomainName=='${domain}'].Id | [0]" \
    --output text 2>/dev/null || true)
fi
if [ -n "${dist_id}" ] && [ "${dist_id}" != "None" ] && [ "${dist_id}" != "null" ]; then
  echo "Invalidating CloudFront ${dist_id}"
  aws cloudfront create-invalidation \
    --distribution-id "${dist_id}" \
    --paths "/species_figs/*" "/img/*" \
    || echo "CloudFront invalidation failed; cached objects refresh within a day." >&2
else
  echo "Skipping CloudFront invalidation (distribution id unavailable). Cached objects refresh within a day." >&2
fi

if [ -e _site/data/species_figs ]; then
  echo "Removing _site/data/species_figs so it is not published to GitHub Pages"
  rm -rf _site/data/species_figs
fi
if [ -e _site/img/shinyApp.png ]; then
  rm -f _site/img/shinyApp.png
fi
