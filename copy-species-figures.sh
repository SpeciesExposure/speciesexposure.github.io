#!/usr/bin/env sh
set -eu

source_dir="${SOURCE_DIR:-data/species_figs}"
target_dir="${TARGET_DIR:-_site/data/species_figs}"

if [ ! -d "$source_dir" ]; then
  exit 0
fi

if [ -L "$target_dir" ]; then
  rm "$target_dir"
fi

mkdir -p "$target_dir"
find "$source_dir" -mindepth 1 -maxdepth 1 -type d -exec cp -alu {} "$target_dir" \;