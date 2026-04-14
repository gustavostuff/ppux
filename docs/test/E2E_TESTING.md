# E2E Testing

In PPUX, E2E means visual tests that run the real app and let you watch a full workflow play out.

## Running E2E tests

Run the visual scenario suite:

```bash
./scripts/unix/run_e2e_tests.sh
```

On Windows:

```bat
scripts\windows\run_e2e_tests.bat
```

Run one scenario directly:

```bash
./scripts/unix/run_e2e_demo.sh modals
```

On Windows:

```bat
scripts\windows\run_e2e_demo.bat modals
```

While a visual E2E scenario is running, press `Esc` to pause it and open an `Abort:` modal with `Current`, `All`, and `Continue`.

You can also pass an optional speed multiplier:

```bash
./scripts/unix/run_e2e_demo.sh modals 2
```

## Where E2E tests live

- scenario list: `scripts/unix/run_e2e_tests.sh` and `scripts/windows/run_e2e_tests.bat`
- single-scenario launcher: `scripts/unix/run_e2e_demo.sh` and `scripts/windows/run_e2e_demo.bat`
- visual scenario definitions: `test/e2e_visible/scenarios.lua`
- visual timing config: `test/e2e_visual_config.lua`

## How visual E2E works

Visual scenarios are named flows made of small steps such as:

- pause
- move mouse
- mouse down / mouse up
- drag
- key press
- assertions on timing or visible state

The real app is booted, the scenario runs on top of it, and an overlay shows the active scenario and speed.

## Adding a new visual E2E scenario

1. Add a scenario to `test/e2e_visible/scenarios.lua`.
2. Compose it from small visual steps.
3. Run it with `./scripts/unix/run_e2e_demo.sh <scenario>` (or `scripts\windows\run_e2e_demo.bat <scenario>`).
4. If it should be part of the standard suite, add it to `scripts/unix/run_e2e_tests.sh` and `scripts/windows/run_e2e_tests.bat`.

## Good patterns

- keep each scenario focused on one workflow
- use stable window titles or IDs when targeting windows
- keep motions readable when the scenario is meant for manual watching
- use pauses only where they help readability
- prefer extending existing helpers in the visual runner instead of ad-hoc event code

## Useful examples

- `modals`
- `boot_and_drag`
- `animation_playback`
- `brush_paint_lines`
- `palette_edit_roundtrip`
- `save_reload_persistence`
- `context_menus_and_submenus`
- `window_resize_and_hover_priority`
- `modal_navigation_keyboard_only`
- `clipboard_matrix`
- `ppu_toolbar_ranges_setup`
- `ppu_toolbar_pattern_ranges`
- `ppu_toolbar_sprite_and_mode_controls`

## Clipboard scenario matrix

`clipboard_matrix` should cover this expected behavior:

- tile window copy/cut/paste with single and multi-selection payloads
- sprite window copy/cut/paste on supported sprite layers
- CHR same-window copy/cut/paste with before/after pixel assertions
- restricted sprite-layer clipboard paths in `ppu_frame` and `oam_animation`
- context-menu paste visibility + invocation on compatible tile contexts
- cursor anchor in-bounds behavior (top-left pivot for copied bounds)
- out-of-bounds shift-to-fit behavior for left/right/top/bottom edge pastes
- oversized payload cancellation (no partial clip/drop)
