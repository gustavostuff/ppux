# README audit report

**Date:** 2026-06-17  
**Scope:** Full pass of [`README.md`](../README.md) against current code (toolbars, input, windows, palettes, PPU/OAM, pattern tables, development notes).  
**Method:** Manual review plus spot-checks in `controllers/`, `user_interface/`, and `test/`.

This document lists **incorrect or outdated** README content and **gaps** (features in code not documented). It does **not** modify `README.md`.

---

## Summary

| Severity | Count | Examples |
|----------|------:|----------|
| Critical (broken or misleading) | 4 | Missing `#undo-and-redo` section; `Space` described as hold-not-toggle; `Ctrl+1/2/3` mislabeled as app scale |
| Moderate (behavior incomplete or stale) | 12 | Clipboard edit-mode rules; ROM palette menu items; OAM playback blocking scope |
| Minor (wording / UI nuance) | 10 | “right click” vs right-drag; remove-layer button always visible |
| Stale counts / maintenance | 2 | Unit test count; E2E scenario list drift |
| Undocumented features (gaps) | 6 | Window link lines setting, separate toolbar, pattern-table remove range |

Most toolbar **button order** and **window-type** descriptions are accurate after recent pattern-table README updates.

---

## Critical

### 1. Broken link: `#undo-and-redo`

**README (lines 253, 294):** `Ctrl + Z` / `Ctrl + Y` → “see [Undo and redo](#undo-and-redo)”.

**Code:** No `### Undo and redo` section exists in `README.md`.

**Suggested update:** Add a section (e.g. under **Main controls** or **Advanced**) summarizing undoable events from `controllers/input_support/undo_redo_controller.lua`: paint strokes, tile/sprite drags, palette links and color edits, pattern-table link/append, PPU nametable range, animation window state, grid resize, CHR revert, window create/rename/minimize/close, nametable unscramble, etc. Document **`Ctrl+Y`** for redo (no `Ctrl+Shift+Z` in code).

---

### 2. `Space` mapping highlight — toggle, not hold

**README (line 250):** “`Space` **(hold)** … Release `Space` to turn off.”

**Code:** `keyboard_window_shortcuts_controller.handleSpaceHighlightToggle` flips `spaceHighlightActive` on each keypress (`core_controller_lifecycle.lua`).

**Suggested update:** “`Space`: toggle mapping highlight on/off.”

---

### 3. `Ctrl + 1/2/3` — focused **window zoom**, not app/canvas scale

**README (line 244):** “change **app scale**”.  
**README (line 645):** “switch between 1×, 2×, and 3× **window scale**” in the **Display resolution** section (alongside 720p/1080p integer multiples).

**Code:** `handleWindowZoom` calls `focus:setZoomLevel(1|2|3)` on the **focused layout window** (`keyboard_window_shortcuts_controller.lua`). OS presentation scale is **Settings → Appearance → Canvas scale** (`resolution_controller.lua`).

**Suggested update:**
- Main controls: “`Ctrl + 1/2/3`: set **focused window** content zoom to 1×, 2×, or 3× (palette windows and collapsed headers skipped).”
- Display resolution: remove `Ctrl+1/2/3` from that section or clarify it does **not** change how the 640×360 canvas fits the monitor; point to Settings for that.

---

### 4. ROM palette source menu — “Move All Links To” not in UI

**README (line 475):** Right-click connect menu includes **“Move All Links To”**.

**Code:** `_buildPaletteLinkSourceContextMenuItems` only exposes **“Jump to linked layer”** and **“Remove all links”** (`core_controller_window_ops.lua`). `PaletteLinkController.moveAllLinksToPalette` exists but is not wired to a menu item.

**Suggested update:** Remove “Move All Links To” from the documented menu, or implement and ship the menu entry first.

---

## Moderate

### 5. Mapping highlight — PPU Frame tile layer excluded

**README (line 250):** Works when a “non-CHR/ROM layout window” is focused.

**Code:** `Window:canShowSpaceHighlight` returns false for PPU Frame when `layer.kind ~= "sprite"` (`window_rendering_selection.lua`).

**Suggested update:** Add: “On **PPU Frame**, mapping highlight applies on the **sprite** layer only, not the nametable tile layer.”

---

### 6. Clipboard shortcuts — tile mode only (keyboard)

**README (lines 254, 265–268):** Lists `Ctrl+C/X/V` without mode qualifier.

**Code:** `keyboard_clipboard_controller` returns false for copy/cut/paste when `ctx.getMode() == "edit"`.

**Suggested update:** “Clipboard shortcuts work in **tile mode** only (not while painting in edit mode).” Note: app-toolbar Copy/Cut/Paste buttons use `getActionAvailability()` and are **not** edit-mode gated — worth calling out if documenting toolbar vs keyboard.

---

### 7. App toolbar — Copy description

**README (line 111):** “copies the selected items (**Tile mode only**)”.

**Code:** Keyboard copy is tile-mode-only; toolbar copy is not edit-gated. Copy works on **sprite** layers in static art / animation windows, not only tiles. OAM and PPU Frame sprite layers are blocked (`restrictionMessage`).

**Suggested update:** Clarify tile-mode keyboard rule, sprite vs tile layers, and OAM/PPU sprite restrictions.

---

### 8. App toolbar — ROM load gating

**README (lines 106–121):** Implies full quick-button strip when “ROM (or project workspace) loaded”.

**Code:** Only **Open project** is shown without a loaded ROM; other quick buttons require `hasLoadedROM()` (`app_top_toolbar_controller.lua`).

**Suggested update:** “With no ROM loaded, only **Open project** appears; the rest of the strip appears after a ROM or project workspace is loaded.”

---

### 9. OAM animation — playback blocks layer **switching**, not all edits

**README (line 444):** “layer edits are blocked while playback is running.”

**Code:** `keyboard_navigation_controller` and animation toolbar block **prev/next layer** when `isPlaying`; no general paint/edit guard.

**Suggested update:** “Layer **switching** (`Shift+Up/Down`, toolbar prev/next) is blocked during playback.”

---

### 10. OAM sprite add — bank/tile no longer required in modal

**README (line 443):** “ROM addresses and **tiles** are chosen inside the modals.”

**Code:** `showPpuFrameAddSpriteModal` sets `chrFieldsHidden = true` for OAM (`core_controller_ppu_frame.lua`); modal shows **OAM start** only. CHR bank/tile fields remain for PPU Frame sprite add when not hidden.

**Suggested update:** For OAM: “**OAM start address** is set in the add-sprite modal; CHR comes from the linked pattern table (no per-sprite bank/tile fields).” Align with `todos.lua` note about pattern-table mapping.

---

### 11. Project file sketches — `bank` / `tile` on sprite items

**README (lines 420, 460):** Example items include `bank` and `tile`.

**Code:** Still supported for resolution/display when present, but OAM add flow no longer requires them when a pattern table is linked. Fields may be omitted or derived from pattern-table logical indices going forward.

**Suggested update:** Mark `bank`/`tile` as optional / legacy in examples, or show minimal `{ startAddr = … }` for OAM with linked pattern table.

---

### 12. PNG drops — ROM required

**README (lines 296–320):** No prerequisite stated.

**Code:** `RomProjectController.handleFileDropped` rejects PNG import with “Open a ROM before importing PNGs.”

**Suggested update:** Add bullet: “Requires a loaded ROM (or project workspace with ROM backing).”

---

### 13. Palette windows — keys `1–4` scope

**README (line 226):** “Palette row numbers `1` to `4` … select the row used by layers.”

**Code:** On layout windows in **tile mode**, `1–4` assign palette **numbers** to tiles/sprites (`handlePaletteNumberAssignment`). In **edit mode**, `1–4` select paint color index. Not used when a palette window itself is focused.

**Suggested update:** Move/clarify under Tile mode and Edit mode; don’t imply palette-window focus behavior.

---

### 14. Global palette — arrow keys need active palette

**README (lines 228–229):** Arrow / wheel color editing.

**Code:** `handlePaletteKeys` requires `activePalette` for **global** palettes; ROM palettes work without that step.

**Suggested update:** “For **global** palettes, use **Set as active palette** (toolbar) before keyboard color editing.”

---

### 15. Window references — “must exist”

**README (line 505):** Referenced window “must exist” in `windows` array.

**Code:** Missing `winId` falls back to inline `paletteData` or nil resolution (`shader_palette_controller.lua`) — no hard error.

**Suggested update:** “Should exist for correct palette resolution; missing IDs may fall back to inline palette data in legacy projects.”

---

### 16. ROM Banks toolbar — keyboard shortcuts understated

**README (line 138):** Only documents `Ctrl+M` and `M`.

**Code:** ROM bank windows use the same `ChrToolbar` and `handleChrBankKeys` as CHR Banks: **`Left`/`Right`** bank nav, **`D`** diff toggle.

**Suggested update:** Match CHR Banks keyboard list (minus sync duplicate tiles).

---

## Minor

### 17. Animation toolbar — Remove layer visibility

**README (line 161):** “only when more than one frame exists.”

**Code:** Button always visible; `_onRemoveLayer` shows “Cannot remove the last layer” (`animation_toolbar.lua`). Same for `-` key.

**Suggested update:** “`-` / Remove layer — refuses when only one frame remains (button stays visible).”

---

### 18. OAM toolbar — origin guides vs canvas drag

**README (line 177):** Item 6 describes **Shift + right-drag** under “Toggle origin guides.”

**Code:** Toolbar button **toggles** guide visibility; Shift+RMB drag is separate (`sprite_origin_drag_controller.lua`).

**Suggested update:** Split into two bullets (toggle button vs canvas drag), as in PPU frame editing notes.

---

### 19. OAM / PPU — origin controls hidden without sprite layer

**README:** OAM lists origin guides; PPU says guides on sprite layers.

**Code:** `updateOriginButtons` **hides** origin/add-sprite controls when active layer is not sprite (`animation_toolbar.lua`, `ppu_frame_toolbar.lua`).

**Suggested update:** “Visible only when a **sprite** layer exists and is relevant to the active layer.”

---

### 20. ROM palette toolbar — “right click” vs right-**drag**

**README (line 199):** “right click to drag link.”

**Code:** Tooltip: “right-**drag** to link layers”; palette link drag uses mouse button 2 (`paletteLinkHandle`).

**Suggested update:** “right-**drag** … left-click for menu.”

---

### 21. Pattern table link (source) — consumer wording

**README (line 145):** Names only PPU Frame / OAM Animation.

**Code:** Any linked consumer layer counts (`getLinkedConsumersForPatternTable`).

**Suggested update:** “linked consumer layer(s)” (PPU tile/sprite, OAM frames, etc.).

---

### 22. PPU Frame pattern table link — separate BG/sprite menus

**README (line 209):** Single menu to link tile, sprite, or both.

**Code:** Context menu has **“Link background pattern table”** and **“Link sprites pattern table”** submenus (`core_controller_window_ops.lua`).

**Suggested update:** Optional: mention separate submenus for tile vs sprite pattern tables (can link different pattern table windows).

---

### 23. Tile mode — arrow key selection

**README (line 269):** “arrows to move tile selections.”

**Code:** Navigation skips empty cells (`handleTileSelectionNavigation`).

**Suggested update:** “…among **occupied** cells.”

---

### 24. App toolbar — Reference PNG eligibility

**README (line 121):** No window-type caveat.

**Code:** `ReferenceBackgroundController.isEligibleWindow` excludes CHR/ROM banks and palettes; button disabled when focus ineligible.

**Suggested update:** “Supported on eligible **layout** windows only (not CHR/ROM banks or palette windows).”

---

### 25. App toolbar — grid resize eligibility

**README (lines 118–119):** Add/remove column/row.

**Code:** Enabled only when `WindowGridResizeController.isGridResizeWindow(focus)`.

**Suggested update:** Note grid-resizable window kinds only.

---

### 26. Palette destination menu labels

**README (line 240):** “Link to palette” / “Remove ROM palette link.”

**Code:** Menu text is **“Link To Palette”** / **“Remove ROM palette link”** (casing).

**Suggested update:** Match in-app strings or say “wording may vary slightly.”

---

## Stale maintenance lines

### 27. Unit test count

**README (line 630):** “All **748** unit tests passing.”

**Code (2026-06-17):** `rg '^\s*it\(' test/tests` → **794** `it()` blocks (includes e2e tests loaded in `test/main.lua`).

**Suggested update:** Re-run `./scripts/unix/run_unit_tests.sh` and update the count, or automate the badge from CI.

---

### 28. E2E scenario list vs README

**README (line 632):** “All **24** E2E tests passing.”

**Code:** `scripts/unix/run_e2e_tests.sh` lists **24** scenarios — count matches.

**Note:** Builder modules define additional scenarios not in the default suite (e.g. `clipboard_intra_inter_paths`, `rom_palette_links`). E2E scenario `ppu_toolbar_pattern_ranges` still opens **Add tile range** via `showPpuFramePatternRangeModal` API — that modal is **not** exposed on the pattern-table toolbar (ranges are drag-drop only). Scenario may be testing API/legacy path, not user-facing toolbar.

---

## Undocumented features (gaps, not necessarily wrong)

These are implemented but absent or thin in README:

| Feature | Where in code | Suggested README home |
|---------|---------------|------------------------|
| **Window link lines** (`never` / `on_hover` / `always` / `auto_hide`) | Settings → Appearance (`core_controller_save_settings.lua`) | Notes or Palette/Toolbars: on-canvas pivot handles and dotted link lines |
| **Separate toolbar** (detached from window header) | Settings | Toolbars intro |
| **Pattern table: Remove tile range** | Context menu on pattern table cells (`core_controller_ppu_chr_menus.lua`) | Pattern table toolbar or Advanced |
| **Pattern table: no clipboard cut/paste** | `keyboard_clipboard_controller` restriction | Pattern table section |
| **Jump to linked palette** (destination) | Palette link destination menu | Palette windows |
| **PPU Frame: no add/remove layer toolbar** | By design (`ppu_frame_toolbar.lua`) | Optional note under PPU Frame toolbar |

---

## Sections verified as largely accurate

- **Getting started** — ROM drag, project priority, `Ctrl+O` (matches `rom_project_controller` / app toolbar).
- **Windows system table** — window kinds and pattern-table requirements align with `WindowCaps` and link gates.
- **CHR Banks toolbar** — button order, shortcuts `Left`/`Right`, `Ctrl+M`, `M`, `D`, sync duplicates (`chr_toolbar.lua`).
- **Pattern table toolbar** (recent) — layout + source link button; drag-drop ranges (`pattern_table_toolbar.lua`, `applyChrTileGroupToPatternTableWindow`).
- **Static Art / Animation / OAM / PPU toolbars** — button order matches `static_art_toolbar.lua`, `animation_toolbar.lua`, `ppu_frame_toolbar.lua` (default single-row OAM).
- **Global / ROM palette toolbars** — grouped slots, compact, active palette, link handle (`palette_toolbar.lua`, `rom_palette_toolbar.lua`).
- **Palette linking** — right-drag + menus (`palette_link_controller.lua`).
- **Tab** tile/edit toggle, **Ctrl+F** fullscreen, **Ctrl+G/R** grid/shader, layer **Up=next / Down=prev**, PNG routing rules, PPU unscramble path, byte budget / konami codec, ROM patches schema, build/test script paths, 640×360 canvas + Settings canvas scale/filter, LÖVE 11.5.

---

## Suggested update priority

1. Add **Undo and redo** section; fix broken anchors.  
2. Fix **`Space`** (toggle) and **`Ctrl+1/2/3`** (focused window zoom vs canvas scale).  
3. Fix **ROM palette** menu list (remove Move All Links To).  
4. Tighten **OAM** playback + sprite-add wording; **clipboard** tile-mode note.  
5. Refresh **unit test count**; optional pass on E2E scenario names vs pattern-table UX.  
6. Document **Settings** features (window links, separate toolbar) when ready for users.

---

*Generated for maintainers; re-run this audit after major toolbar, pattern-table, or input changes.*
