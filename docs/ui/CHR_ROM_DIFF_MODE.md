# CHR / ROM window diff mode (design doc)

Visual “git-like” diff for **CHR-backed windows** (`kind == "chr"`), including the **ROM tile browser** (`RomWindow`), which shares the same behavior. ROM size stays fixed; we do **not** model inserted or deleted regions—only **per-tile** change highlighting.

## User-visible behavior

- User toggles **diff mode** with the CHR toolbar button **`icon_diff_mode`** (`images.icons.actions.icon_diff_mode`). When on, the button uses the same green fill style as other active toggles.
- While active, the CHR canvas shows **50% opacity** overlays on each 8×8 grid cell:
  - **RGB (0, 1, 0)** on cells whose **CHR tile data** differs from the baseline.
  - **Black** on cells that match the baseline.
- **Granularity**: one **8×8** CHR tile equals **16 raw bytes** in NES planar layout. If **any** of those bytes differ from baseline, treat the whole **cell** as changed (green). No per-pixel outlining inside the tile.
- **8×16 (odd/even layout)**: the ROM editor lays out CHR in vertical pairs forming one **8×16 “item.”** If **either** half (top or bottom 8×8 in that pair/column) has any byte difference, apply the **same** tint to **both** 8×8 grid cells—so one visible “sprite strip” stays one semantic unit.

## Baseline (“what we compare against”)

- Use **`appEditState.originalChrBanksBytes`**, a clone taken when the CHR banks are prepared at **ROM parse / load** (see `rom_project_controller` and analogous paths).
- **Meaning**: “changed since **this ROM was loaded** in the current session,” not “against git HEAD” or “against last disk save.”
- If **last-save baseline** is ever desired, that would be a separate choice: updating `originalChrBanksBytes` (or introducing a sibling field) **on successful save**, with explicit UX so users know which baseline is active.

## Technical: change detection

- For bank index `b` and CHR tile index `t` ∈ `0 … 511`, compare **`chrBanksBytes[b]`** vs **`originalChrBanksBytes[b]`** over the 16-byte range starting at **`t * 16 + 1`** (1-based table indexing, consistent with existing code such as `buildEditsFromChrDiff` in `controllers/game_art/edits_controller.lua`).
- Missing or shorter baseline bank: behavior should stay **consistent with existing revert/diff helpers** (e.g. treat missing bytes as zero or hide diff—implementation must align with revert semantics).
- **8×16 grouping**: derive tile indices from the same **grid position → tile index** mapping as **`bank_canvas_controller`** (`mapIndexForOrder` for `normal` vs `oddEven`). For odd/even, combine the two rows of a vertical pair into one logical “metatile”: `changed_metatile = changed(top_half) OR changed(bottom_half)`.

## Technical: rendering

- Preserve the existing flow: **`BankCanvasController`** builds the decoded tile image; **palette shader** applies as today.
- **Diff overlay**: after drawing the CHR **image** (with the palette shader), **release the shader** and draw semi-transparent rectangles per grid cell in **bank pixel space** so overlays are not remapped by the CHR palette shader. Colors: unchanged → **black** at **50%** alpha; changed → **RGB (0, 1, 0)** at **50%** alpha (multiplied by layer opacity when applicable).
- **Performance**: recomputes per tile from `originalChrBanksBytes` vs `chrBanksBytes` each frame while diff is on (512 × 16 byte compares per bank; cheap). Optional future: cache by bank with invalidation on tile/bank dirty.

## Implementation map

- Window flag: `ChrBankWindow.showChrDiffMode` (default `false`). `RomWindow` inherits it.
- Overlay logic: `controllers/chr/chr_diff_overlay.lua`.
- Canvas: `BankCanvasController:drawWindowImage` / `drawWindowDiffOverlay` and `drawCanvasOnlyImage` / `drawCanvasOnlyDiffOverlay`; `core_controller_draw.drawChrBankLayer` and `chr_canvas_only_mode` apply shader only around the image pass.
- Toolbar: `user_interface/toolbars/chr_toolbar.lua` (`diffModeButton`, `updateDiffModeButton`).

## Canvas-only CHR mode

- **`chr_canvas_only_mode`** should honor the focused window’s diff flag so full-screen CHR view matches tiled windows.

## Out of scope (for this doc)

- Nametable/PPU/frame diff, palette-window-only ROM edits as a separate tint layer (CHR diff uses **CHR bytes**, not rendered colors after arbitrary palette swaps unless we explicitly extend semantics).
- Git integration or labeled snapshots (“compare to commit”).

## Testing (recommended)

- **Unit**: two synthetic banks (original vs current); assert tile-level changed flags; assert **odd/even** coupling (change only bottom half bytes → **both** rows tinted for that column).
- **Smoke**: toggle diff with no baseline / empty project—no crashes; predictable fallback.

## Status

Implemented: toolbar toggle, overlay drawing (window + canvas-only), tests in `test/tests/unit/chr_diff_overlay.test.lua`.
