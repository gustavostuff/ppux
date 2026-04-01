#!/bin/bash

# Run tests for nes-art-editor-v3
# This script navigates to the test directory and runs the LÖVE2D test framework

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR/test" || exit 1

# Check if love is available
if ! command -v love &> /dev/null; then
    echo "Error: 'love' command not found. Please install LÖVE2D first."
    echo "Visit https://love2d.org/ for installation instructions."
    exit 1
fi

# Run all tests by default, or a single matching test file when a filter is provided.
if [ -n "$1" ]; then
    love . -- "$1"
else
    love .
fi
