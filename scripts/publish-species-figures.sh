#!/usr/bin/env sh
set -eu

force_push=false
if [ "${1:-}" = "--force-push" ]; then
  force_push=true
  shift
fi
if [ "$#" -ne 0 ]; then
  echo "Usage: $0 [--force-push]" >&2
  exit 2
fi

root_dir=$(git rev-parse --show-toplevel)
source_dir="$root_dir/data/species_figs"
worktree_dir="$root_dir/.quarto/figures-worktree"
branch=figures

if [ ! -d "$source_dir" ]; then
  echo "Figure directory not found: $source_dir" >&2
  exit 1
fi
if ! find "$source_dir" -mindepth 2 -maxdepth 2 -type f -name '*.png' -print -quit | grep -q .; then
  echo "No sharded PNG files found under $source_dir" >&2
  exit 1
fi

git -C "$root_dir" fetch origin "$branch" >/dev/null 2>&1 || true
if [ -e "$worktree_dir" ]; then
  git -C "$root_dir" worktree remove --force "$worktree_dir" 2>/dev/null || rm -rf "$worktree_dir"
fi
git -C "$root_dir" worktree prune

if git -C "$root_dir" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  git -C "$root_dir" worktree add --force -B "$branch" "$worktree_dir" "origin/$branch"
else
  git -C "$root_dir" worktree add --detach "$worktree_dir" HEAD
  git -C "$worktree_dir" checkout --orphan "$branch"
  find "$worktree_dir" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
fi

target_dir="$worktree_dir/data/species_figs"
rm -rf "$target_dir"
mkdir -p "$target_dir"
find "$source_dir" -mindepth 1 -maxdepth 1 -type d -exec cp -al {} "$target_dir" \;

file_count=$(find "$target_dir" -type f -name '*.png' | wc -l | tr -d ' ')
printf '{"file_count":%s,"published_at":"%s"}\n' "$file_count" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$worktree_dir/figures-manifest.json"

git -C "$worktree_dir" add -A
if git -C "$worktree_dir" diff --cached --quiet; then
  echo "Figures branch is already current."
  exit 0
fi
git -C "$worktree_dir" -c user.email="build@local" -c user.name="build" commit -m "Update species figures"

if [ "$force_push" = true ]; then
  echo "WARNING: force-pushing the figures branch."
  git -C "$worktree_dir" push --force origin "$branch"
else
  git -C "$worktree_dir" push origin "$branch"
fi