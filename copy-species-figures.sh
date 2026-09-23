#!/usr/bin/env sh
set -eu

source_dir="${SOURCE_DIR:-data/species_figs}"
target_dir="${TARGET_DIR:-_site/data/species_figs}"

if [ ! -d "$source_dir" ]; then
  exit 0
fi

mkdir -p "$target_dir"
cp -alu "$source_dir/." "$target_dir/"