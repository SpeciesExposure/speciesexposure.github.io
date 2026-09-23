#!/usr/bin/env sh
set -eu

source_dir="$(pwd)/data/species_figs"
target_dir="_site/data/species_figs"

if [ ! -d "$source_dir" ]; then
  exit 0
fi

mkdir -p "$(dirname "$target_dir")"
if [ -d "$target_dir" ] && [ ! -L "$target_dir" ]; then
  exit 0
fi

rm -f "$target_dir"
ln -s "$source_dir" "$target_dir"