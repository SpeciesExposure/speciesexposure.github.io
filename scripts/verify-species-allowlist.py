#!/usr/bin/env python3
"""Smoke-test the species allowlist without a full R/data build.

Checks:
  - config/species-allowlist.csv is readable and has a unique `species` column
  - name normalization (spaces → underscores)
  - asset basename → species key parsing used for pruning
  - optional: intersect with origin/gh-pages maps for before/after counts
"""

from __future__ import annotations

import csv
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWLIST = ROOT / "config" / "species-allowlist.csv"


def normalize_species_name(x: str) -> str:
    return re.sub(r"\s+", "_", x.strip())


def species_key_from_asset(basename: str) -> str | None:
    if basename.endswith("_map.json"):
        return basename[: -len("_map.json")]
    if basename.endswith("_polar.png"):
        return basename[: -len("_polar.png")]
    if "__" in basename:
        return basename.split("__", 1)[0]
    return None


def main() -> int:
    if not ALLOWLIST.is_file():
        print(f"FAIL: missing {ALLOWLIST}", file=sys.stderr)
        return 1

    with ALLOWLIST.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows or "species" not in rows[0]:
        print("FAIL: CSV must have a 'species' column", file=sys.stderr)
        return 1

    names = [normalize_species_name(r["species"]) for r in rows]
    unique = list(dict.fromkeys(names))
    if len(unique) != len(names):
        print(f"FAIL: duplicate species after normalize ({len(names)} → {len(unique)})")
        return 1
    if any(" " in n for n in unique):
        print("FAIL: spaces remain after normalize")
        return 1

    cases = {
        "Ablepharus_mahabharatus_map.json": "Ablepharus_mahabharatus",
        "Ablepharus_mahabharatus_polar.png": "Ablepharus_mahabharatus",
        "Ablepharus_mahabharatus__temperature__annual.png": "Ablepharus_mahabharatus",
    }
    for bn, expected in cases.items():
        got = species_key_from_asset(bn)
        if got != expected:
            print(f"FAIL: key({bn}) = {got!r}, expected {expected!r}")
            return 1

    print(f"OK: allowlist {ALLOWLIST} — {len(unique)} unique species")
    print(f"OK: normalize sample {rows[0]['species']!r} → {unique[0]!r}")
    print("OK: asset key parsing")

    try:
        maps = subprocess.check_output(
            [
                "git",
                "-C",
                str(ROOT),
                "ls-tree",
                "-r",
                "--name-only",
                "origin/gh-pages",
                "data/species_maps",
            ],
            text=True,
        ).splitlines()
    except subprocess.CalledProcessError:
        print("SKIP: origin/gh-pages maps not available for before/after count")
        return 0

    published = {
        Path(p).name[: -len("_map.json")]
        for p in maps
        if p.endswith("_map.json")
    }
    allow = set(unique)
    print(
        f"OK: gh-pages before={len(published)} maps; "
        f"after allowlist intersect={len(allow & published)}; "
        f"allow missing from published={len(allow - published)}"
    )
    if allow - published:
        print("WARN: some allowlisted species are not on gh-pages yet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
