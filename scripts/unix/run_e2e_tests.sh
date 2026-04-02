#!/bin/bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ABORT_ALL_FLAG="/tmp/ppux_e2e_abort_all.flag"
rm -f "$ABORT_ALL_FLAG"

SCENARIOS=(
  "default_action_delay"
  "modals"
  "boot_and_drag"
  "animation_playback"
  "tile_edit_roundtrip"
  "brush_paint_tools"
  "new_window_variants"
  "palette_shader_preview"
  "static_sprite_ops"
  "undo_redo_events"
  "palette_edit_roundtrip"
  "rom_palette_link_interactions"
  "save_reload_persistence"
  "submenu_positions"
  "context_menus_and_submenus"
  "window_resize_and_hover_priority"
  "modal_navigation_keyboard_only"
  "text_field_variants"
)
pass_count=0
fail_count=0

for scenario in "${SCENARIOS[@]}"; do
  echo "Running visual E2E scenario: ${scenario}"
  "$SCRIPT_DIR/run_e2e_demo.sh" "$scenario"
  status=$?

  if [[ -f "$ABORT_ALL_FLAG" ]]; then
    echo "ABORTED ALL VISUAL E2E SCENARIOS"
    rm -f "$ABORT_ALL_FLAG"
    exit 130
  fi

  if [[ $status -eq 0 ]]; then
    echo "PASS: ${scenario}"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: ${scenario} (exit ${status})"
    fail_count=$((fail_count + 1))
  fi
done

echo
echo "Visual E2E summary: ${pass_count} passed, ${fail_count} failed"

if [[ $fail_count -gt 0 ]]; then
  exit 1
fi
