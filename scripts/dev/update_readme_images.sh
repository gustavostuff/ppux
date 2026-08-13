#!/usr/bin/env bash
# Regenerate all scripted README images.
#
# Usage (from repo root or anywhere):
#   ./scripts/dev/update_readme_images.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

SCRIPTS=(
  scripts/dev/capture_toolbar_readme_images.sh
  scripts/dev/capture_source_links_readme_images.sh
  scripts/dev/capture_palettes_readme_images.sh
  scripts/dev/capture_mode_indicator_readme_images.sh
  scripts/dev/update_windows_system_table_icons.sh
)

for script in "${SCRIPTS[@]}"; do
  if [[ ! -f "$script" ]]; then
    echo "Error: missing $script" >&2
    exit 1
  fi
  if [[ ! -x "$script" ]]; then
    echo "Error: $script is not executable" >&2
    exit 1
  fi
done

for script in "${SCRIPTS[@]}"; do
  echo
  echo "======== $(basename "$script") ========"
  "./$script"
done

echo
echo "All README images updated."
