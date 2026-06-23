# PPUX Maintenance Analysis

**Date:** June 2025  
**Scope:** Production Lua (~80k lines across ~215 non-test files), with emphasis on maintainability and performance — not further controller splitting.

This document complements the existing short audit in [`MAINTENANCE_PATTERNS.md`](MAINTENANCE_PATTERNS.md) and the test plan in [`test/CRITICAL_TEST_COVERAGE_EXPANSION_PLAN.md`](test/CRITICAL_TEST_COVERAGE_EXPANSION_PLAN.md).

---

## Executive summary

PPUX is a well-structured LÖVE 11.5 NES art editor. Controller logic is already split thoughtfully (`core_controller.lua` wires ~12 mixins; input is spread across ~15 files). The remaining maintenance wins are **not** more controller files, but:

1. **Performance** — tile-edit invalidation rescans every window on every pixel stroke.
2. **Test gaps** — the ROM save pipeline has no dedicated unit tests despite corruption risk.
3. **Megamodules** — a handful of 1.8k–2.1k-line files still mix orchestration, rendering, menu building, and layout.
4. **Small deduplication** — repeated helpers (`setStatus`, `love.timer.getTime` guards) across many files.

---

## Project snapshot

| Area | Count / size | Notes |
|------|----------------|-------|
| Controllers | 99 files | Already granular; further splitting has diminishing returns |
| UI | 80 files | Windows, modals, toolbars |
| Unit tests | 102 files | Good input/clipboard/modal coverage |
| Largest production files | 2,107 / 2,080 / 2,013 lines | `core_controller_window_ops`, `core_controller_draw`, `window_controller` |

Positive patterns already in place: lazy image loading (`images.lua`), per-cell nametable canvas caching (`ppu_frame_window.lua`), window rendering mixins (`window_rendering_*.lua`), adaptive run-loop sleep (`love_run_loop.lua`), and prior palette multi-selection perf fix (noted in `todos.lua`).

---

## High-priority findings

### 1. Full-window scans on every CHR tile edit (performance)

**Where:** `controllers/chr/bank_canvas_support.lua` → `controllers/app/core_controller_invalidation.lua` → `controllers/app/tile_invalidation_index.lua`

Each pixel paint calls `invalidateTile`, which chains four invalidation passes. Nametable, static-art/pattern-table tile layers, and sprite refs now use a **lazy-rebuilt `(bank, tile) → consumers` index** (`tile_invalidation_index.lua`) instead of scanning every window on every stroke.

```20:35:controllers/chr/bank_canvas_support.lua
function M.invalidateTile(app, bankIdx, tileIndex)
  ...
  resolvedApp:invalidateChrBankTileCanvas(bankIdx, tileIndex)
  resolvedApp:invalidatePpuFrameNametableTile(bankIdx, tileIndex)
  resolvedApp:invalidatePpuFrameSpriteTilesForChrTile(bankIdx, tileIndex)
  resolvedApp:invalidateStaticAnimationTileLayerCanvasForChrTile(bankIdx, tileIndex)
```

**Index rebuild triggers:** `WM` structure generation bumps on window add/close; `markTileInvalidationIndexDirty()` on layer-item repopulation (`populateTileLayerItemsFromPatternTable`, `refreshNametableVisuals`, `invalidateConsumersUsingPatternTable`, project close).

**Correctness safeguards preserved:**
- Pattern-table **full-layer fallback** when a layer's ranges reference a tile but `layer.items` has no instance for that cell (same rule as before).
- Scan paths retained in `tile_invalidation_index.lua` for unit-test parity checks.
- Tests: `test/tests/unit/tile_invalidation_index.test.lua`.

**Impact:** Per paint stroke, invalidation is O(indexed consumers) instead of O(windows × layers × items). Rebuild cost is paid once per structural change, not per pixel.

---

### 2. ROM save pipeline lacks dedicated tests (correctness risk)

**Where:** `controllers/rom/save_controller.lua` (~174 lines)

Save orchestrates nametable write-back, sprite displacement, palette write-back, and final CHR/ROM assembly. Errors short-circuit with status messages but there is **no** `save_controller*.test.lua`; coverage is only indirect via `chr_backing_integration.test.lua`.

**Impact:** Regressions in ordering, error handling, or partial-failure behavior could corrupt exported ROMs silently or leave inconsistent state.

**Direction:** Unit tests for each branch (nametable failure, sprite error, palette write-back, raw vs edited CHR path) as outlined in `CRITICAL_TEST_COVERAGE_EXPANSION_PLAN.md` §1. Small, high-value win with no architectural change.

---

### 3. `core_controller_draw.lua` — orchestration and rendering still coupled (2,080 lines)

**Status:** Partially addressed — window content drawing, shadows, and `drawWindows`/`drawNormalWindow` extracted to `controllers/app/core_controller_window_content_draw.lua` (~1,400 lines). `core_controller_draw.lua` now coordinates frame draw, edit brush previews, modals/toasts/HUD, and delegates workspace window rendering via mixin methods.

**Remaining in `core_controller_draw.lua`:** frame `draw()` loop, edit-mode brush/shape previews, palette link drag overlay calls, modal/toast/HUD overlays, status line.

**Mixes (historical):** frame draw loop, per-window tile/layer rendering, palette shaders, shadow blur pipeline, CRT lens chrome, brush shape previews, HUD overlays.

Window chrome/grid/selection remain in `user_interface/windows_system/window_rendering_*.lua`.

**Impact:** Content vs overlay concerns are separated; further splits (e.g. brush preview helpers) are optional.

**Direction (if needed):** Optional follow-up: extract edit brush preview block to `core_controller_edit_preview_draw.lua`.

---

### 4. `core_controller_window_ops.lua` — menu and ops sprawl (2,107 lines)

**Mixes:** new-window modal wiring, grid resize/clone, mosaic/collapse actions, multiple context-menu builders (window header, empty space, palette link source/dest, PPU tile), coordinate transforms, palette/pattern link focus routing.

**Impact:** Hard to find or safely extend a single menu action; similar menu-building patterns repeat across sections.

**Direction:** Extract **context-menu builder modules** (pure data + callback wiring) into `user_interface/context_menus/` or similar. The app-core mixin stays one file but delegates menu construction. Aligns with the list-driven direction already started in `MAINTENANCE_PATTERNS.md` §1–2.

---

### 5. `window_controller.lua` — factory and layout algorithm in one place (2,013 lines)

**Mixes:** z-order/focus, hit-testing, window-creation factory (all window kinds), mosaic/batch layout, palette stacking, toolbar wiring.

**Impact:** Window creation from the New Window modal and mosaic layout are distinct concerns sharing one file with runtime window management.

**Direction:** Extract **window creation factory** and **mosaic layout** into standalone modules (similar to `controllers/game_art/window_factory_controller.lua` which already exists at 960 lines). `window_controller.lua` keeps focus, z-order, and delegation.

---

### 6. Palette link rendering scans all windows six times per draw path

**Where:** `controllers/palette/palette_link_render_controller.lua` — six separate `wm:getWindows()` loops (lines 192, 209, 272, 414, 428, 479), invoked from the draw path via palette proxy drawing inside `drawNormalWindow`.

**Impact:** Multiplies window-iteration cost during frames that draw palette link overlays.

**Direction:** Single pass per frame (or cached until window set / link topology changes) building lookup tables for source/dest windows. Low-risk refactor within the existing render controller. ✅ Done (`buildPaletteLinkLookup()`; hover/focus link queries use pre-built buckets).

---

## Medium-priority findings (brief)

| Finding | Location | Note |
|---------|----------|------|
| **`core_controller_save_settings.lua` (1,834 lines)** mixes save/export orchestration with settings `_apply*` side effects | `controllers/app/` | ✅ Split: `core_controller_save_settings.lua` (~544 lines, save/recent/quit/modals) + `core_controller_settings_apply.lua` (~1,293 lines); `core_controller_settings_apply.test.lua` covers key `_apply*` paths |
| **Duplicated `setStatus(ctx, text)` helper** | 10+ input/toolbar files | ✅ Centralized in `utils/status_helpers.lua` |
| **Modal routing special cases despite registry** | `core_controller_input.lua` vs `core_controller_shared.lua` | ✅ Centralized in `core_controller_shared.lua`: `dispatchTopModal*`, `dispatchModalWheel`, `routeModalTextInput`, `APP_MODAL_TEXTINPUT_ROUTES`, `MODAL_WHEEL_HANDLER_KEYS`; input delegates to shared helpers |
| **`undo_redo_controller.lua` (1,860 lines)** | `controllers/input_support/` | Large but cohesive; consider extracting undo *command types* into a table/registry if it keeps growing, not more controllers |
| **Large monolithic test files** | `keyboard_input.test.lua` (2,325 lines), `mouse_input_tile_drag_copy.test.lua` (1,300 lines) | Valuable coverage but expensive to maintain; shared fixtures would reduce duplication |
| **E2E gaps** | per `CRITICAL_TEST_COVERAGE_EXPANSION_PLAN.md` | Save-and-reload golden path, Open Project happy/invalid paths, OAM sprite scenarios |
| **Untested modules** | `bank_canvas_controller`, `window_link_visual_controller`, `window_factory_controller` | Indirect coverage only; medium regression risk |
| **`ppu_frame_window.lua` (1,655 lines)** | model + canvas cache + codec | Canvas caching is good; model and invalidation logic could be separated if this file keeps growing |
| **`settings_modal.lua` (1,227 lines)** | tab layout + field defs + apply callbacks | Same pattern as save_settings — UI definition vs runtime apply |

---

## Low-priority findings (brief)

| Finding | Note |
|---------|------|
| **`love.timer.getTime` duck-check wrappers** in ~15 production files | ✅ `utils/love_compat.lua` — timer, keyboard modifiers, mouse, clipboard, graphics/window size, `getOS`/`openURL`; `katsudo` / special `getTimeOr(0)` cases keep distinct fallbacks |
| **Dynamic `require()` in draw/paint hot paths** | e.g. `BrushController` required inside `tryDrawGenericEditShapePreview` in `core_controller_draw.lua:1575`; Lua caches modules but hoisting to file top is cleaner where circular deps allow |
| **Dev-only artifacts** | `scratch/temp_contra_pattern_table_windows.lua`, `text_field_demo_modal.lua`, `icon_bbox_audit/` — not shipped; document or relocate to avoid confusion |
| **`todos.lua`** | Changelog/TODO notes, not loaded at runtime — fine as informal doc, or merge into release notes |
| **Mixed module export styles** | Mixin `return function(X)` vs `local M = {}; return M` — both work; document preferred convention |
| **Manual test registration** | New tests must be added to `test/main.lua` per `UNIT_TESTING.md` — easy to forget |
| **Conservative nametable fallback** | Full-layer repaint when pattern-table range matching fails item hit test (`core_controller_invalidation.lua:95–98`) — correct but can over-invalidate |

---

## Suggested order of work

1. **Add `save_controller` unit tests** — smallest change, highest correctness payoff. ✅ Done (`save_controller.test.lua`).
2. **Tile invalidation index** — measurable perf improvement during painting. ✅ Done (`tile_invalidation_index.lua` + tests).
3. **Extract window content drawing from `core_controller_draw.lua`** — reduces the largest mixed-responsibility file without more controller splits. ✅ Done (`core_controller_window_content_draw.lua`).
4. **Centralize `setStatus` + optional `love_compat.getTime()`** — low-risk dedup across 10+ files. ✅ Done (`utils/status_helpers.lua`, `utils/love_compat.lua`; input/toolbar `setStatus` helpers and `nowSeconds` duck-checks migrated; `katsudo.lua` / `ui_pulse.lua` kept for distinct fallback semantics).
5. **Extract context-menu builders from `core_controller_window_ops.lua`** — readability win, no architectural churn. ✅ Done (`core_controller_context_menus.lua`; `window_ops` keeps show/hide orchestration and `_afterPatternTableLinkChange`).
6. **Single-pass palette link window lookup** — incremental draw-path optimization. ✅ Done (`palette_link_render_controller.buildPaletteLinkLookup`).

---

## What not to do

- **Avoid splitting app-core or input into more controller files.** The mixin layout in `core_controller.lua` is appropriate for this codebase size.
- **Avoid splitting `undo_redo_controller` or input handlers further** unless a clearly isolated subsystem emerges (e.g. a self-contained codec).
- Prefer **helper modules, menu builders, render extractors, and indexes** over new controller layers.
