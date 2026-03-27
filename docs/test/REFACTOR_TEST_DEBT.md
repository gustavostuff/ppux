# Refactor Test Debt (Tracking)

This is a running checklist for refactors that changed structure/dispatch behavior
but do not yet have dedicated tests.

## Input routing / tracing

- [x] `INPUT_ROUTE` logging in `user_input/keyboard_input.lua`
  - Added tests for matched handler (`group` + `handler`) and `unhandled` route logging.
- [x] `INPUT_ROUTE` logging in `user_input/mouse_input.lua`
  - Added tests for `mousepressed` / `mousereleased` / `wheelmoved` route labels.
  - Added test to confirm no route logging on `mousemoved`.

## PNG color mapping shared module

- [x] `controllers/png_palette_mapping_controller.lua` unit tests
  - Added coverage for `buildBrightnessRankMap` ordering/clamping/tie-break stability.
  - Added coverage for `buildPaletteBrightnessRemap` (4-slot and visible-slot cases).
  - Added `imageHasTransparency` and `rgbKeyFromFloats` tests.

## Game art controller decomposition

- [x] `controllers/game_art_window_builder_controller.lua` direct tests
  - Palette activation fallback (last palette becomes active)
  - `romTileViewMode` upgrades `kind="chr"` layout entries to ROM window behavior
  - Focus restoration by `focusedWindowId`
- [x] `controllers/game_art_rom_patch_controller.lua` direct tests
  - (Current coverage exists via `game_art_controller_rom_patches.test.lua`, but add direct module tests after façade split)
- [x] `controllers/game_art_edits_controller.lua` direct tests
  - Added coverage for RLE roundtrip, tile/pixel range expansion, and `applyEdits` string + legacy formats.
- [x] `controllers/game_art_layout_io_controller.lua` direct tests
  - Added basic coverage for `decodeUserDefinedCodes`, layout save/load, and project save/load.
  - Remaining deeper coverage: `snapshotLayout(...)` edge cases (palette normalization, removed tile purge, focus restoration).

## CHR backing abstraction

- [x] `controllers/chr_backing_controller.lua` direct tests
  - Added coverage for `chr_rom` vs `rom_raw` setup, pseudo-bank split/header skip, ROM rebuild, and legacy field compatibility.
- [x] Broader integration coverage for `chrBacking` in save/load orchestration
  - Added tests for `save_controller.saveEdited(...)` selecting `saveRawROM` by backing mode.
  - Added tests for `rom_project_controller.loadROM(...)` default fallback creating `RomWindow` from backing mode.

## Input controller decompositions

- [x] `user_input/keyboard_debug_controller.lua` tests
  - `F9`, `Ctrl+F9`, `F7`, and debug `9` routing behavior
- [x] `user_input/keyboard_art_actions_controller.lua` tests
  - tile rotation handler delegation/duplicate sync behavior (unit-level)
  - palette assignment handler routing for sprite vs tile layers
- [x] `user_input/mouse_*_controller.lua` extracted modules integration smoke tests
  - `mouse_click_controller` routing precedence
  - `mouse_wheel_controller` precedence (`Ctrl+Alt` brush size vs zoom/scroll)
