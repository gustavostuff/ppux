#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")" || exit 1

if ! command -v love >/dev/null 2>&1; then
  echo "Error: 'love' command not found. Please install LÖVE2D first."
  exit 1
fi

SCENARIO="${1:-modals}"
SPEED="${2:-}"

if [ -n "$SPEED" ]; then
  exec love . --e2e "$SCENARIO" --e2e-speed "$SPEED"
else
  exec love . --e2e "$SCENARIO"
fi
