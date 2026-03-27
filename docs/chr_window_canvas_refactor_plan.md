# CHR / ROM Window Canvas Refactor Plan

## Goal

Reduce the runtime cost of CHR / ROM source windows by replacing hundreds of per-tile drawable objects with a bank-sized GPU-backed canvas, while preserving:

- tile identity as `bank + tileIndex`
- drag and drop of `8x8` and `8x16` units
- pixel editing behavior
- compatibility with the rest of the editor

This plan is intentionally scoped to **CHR / ROM windows only** for the first pass.

## Current Problem

Today the CHR pipeline is object-heavy:

- `BankViewController.ensureBankTiles` creates `Tile` objects for all 512 tiles in a bank.
- Each `Tile` can own pixel arrays, `ImageData`, and `Image`.
- CHR / ROM windows rebuild layers full of tile items.
- Draw code iterates cell-by-cell and tile-by-tile.
- Brush edits mutate tile refs directly.
- Drag / selection logic assumes a tile item exists at each grid cell.

This keeps the mental model simple, but it makes CHR source windows expensive to build and draw. On lower-power machines, large visible windows such as PPU frame views already show the cost, and CHR windows contribute to the same general object-count problem.

## New Model

For CHR / ROM windows, the visible bank should stop being a grid of heavyweight `Tile` objects. Instead:

- one bank is rendered into one canvas
- CHR window cells become lightweight virtual views into that bank canvas
- drag / selection still works per logical tile
- edits still target `bank + tileIndex`

The CHR window becomes:

- **authoritative data source**: `appEditState.chrBanksBytes`
- **render cache**: one bank canvas, repainted when the current bank changes
- **interaction model**: virtual tile handles computed from grid position, not stored as full tile items

## Important Clarification About Shaders

Using shaders for rendering is a strong fit here.

Using shaders as the sole place where tile state lives, including pixel edit, flood fill, and persistence, is much riskier in LÖVE 11.4 because:

- there are no compute shaders
- GPU-side mutation requires ping-pong render passes and custom texture encoding
- reading edited data back for ROM save is awkward and expensive
- flood fill on the GPU is possible, but far more complex than the current CPU logic

### Recommended interpretation

For the first implementation:

- keep `chrBanksBytes` as the source of truth on CPU
- use shaders to render CHR bank canvases fast
- update only dirty tile regions or repaint the bank canvas on bank switch
- keep pixel edit logic authoritative on CPU

After that is stable, we can decide whether GPU-side edit passes are still worth the complexity.

## Proposed CHR Window Architecture

### 1. Introduce a CHR bank render cache

Add a dedicated controller or module, for example:

- `controllers/chr/bank_canvas_controller.lua`

Responsibilities:

- own one reusable canvas for the currently visible bank
- own any shader(s) needed to decode / colorize tile data
- expose `setBank(bankIdx)`
- expose `markTileDirty(bankIdx, tileIdx)`
- expose `repaintBank(bankIdx)`
- expose `draw(window, x, y, viewport)`

### 2. Keep bank data CPU-side

Continue storing CHR bytes in:

- `appEditState.chrBanksBytes`

That remains the canonical editable state used by:

- ROM save
- undo / redo
- duplicate sync
- brush tools
- PNG import

### 3. Stop populating CHR windows with 512 heavy tile items

Refactor `BankViewController.rebuildBankWindowItems` so that for CHR / ROM windows it:

- configures bank metadata
- sets current bank and order mode
- does **not** allocate a `Tile` object per visible cell
- prepares virtual lookup helpers instead

The CHR window should know:

- current bank
- tile count
- tile grouping mode (`normal` vs `oddEven`)
- bank canvas reference

But it should not need `layer.items[(row * cols) + col + 1] = tileRef` for normal rendering.

### 4. Add virtual tile handles

Introduce a lightweight tile reference structure for CHR-window interactions only, for example:

```lua
{
  kind = "chr_virtual_tile",
  bank = 3,
  tileIndex = 147,
  sourceRect = { x = 56, y = 72, w = 8, h = 8 },
  mode = "8x8",
}
```

This is enough for:

- selection
- tooltip / label display
- drag start
- drop payloads

If another window still needs a real `Tile` object, materialize it on demand from `bank + tileIndex` instead of prebuilding the whole bank.

### 5. Special-case CHR window drawing

Update `core_controller_draw.lua` so CHR / ROM windows do not go through the standard per-item tile draw path.

Instead:

- draw the bank canvas once
- clip to the window viewport
- draw overlays on top

Overlays still include:

- selection rectangles
- hovered tile highlight
- drag previews
- 8x16 grouping visuals
- toolbar labels

## Canvas Layout

The requested target is:

- one canvas per visible bank
- repaint the canvas when switching banks

There is one inconsistency to resolve before implementation:

- `512` physical `8x8` tiles implies `16 x 32` tiles
- that equals `128 x 256` pixels
- the requested `128 x 156` size does not map to `512` tiles

Until clarified, the safest assumption is:

- logical bank layout remains `16 x 32` tiles
- bank canvas size should match that layout exactly

## Shader Strategy

### Preferred first pass

Use shader acceleration for draw, not for authoritative mutation.

Possible implementations:

1. Upload a bank texture that stores pre-expanded indexed pixels for the current bank.
2. Use a shader to map indices `0..3` to palette colors.
3. Render the whole bank canvas in one pass.

This already removes the expensive path of:

- hundreds of `Tile:draw()` calls
- hundreds of `Image` objects
- per-tile shader binding work

### More ambitious second pass

Use a shader to decode tile bytes directly from packed bank data.

That would reduce CPU-side expansion during repaint, but it adds more complexity in:

- byte packing format
- tile coordinate decoding in shader
- compatibility with LÖVE uniform / texture limits

### GPU-side editing as a later experiment

If we still want shader-side pixel edit and flood fill later, treat that as a separate research phase, not as part of the first migration.

## Interaction Changes

### Selection and hit testing

Replace item-based CHR hit testing with coordinate-based resolution:

- screen position -> grid cell
- grid cell -> logical tile index
- logical tile index -> virtual tile handle

This affects:

- `MouseClickController`
- `MouseTileDropController`
- `BrushController`
- tile label display
- selection overlays

### Drag and drop

On drag start from a CHR / ROM window:

- create a virtual payload based on `bank + tileIndex`
- include source rect from the bank canvas
- keep `8x16` grouping logic as a selection rule, not a storage rule

On drop into other windows:

- continue using `bank + tileIndex` semantics
- materialize a normal tile reference only if the destination code truly requires it

This keeps external window behavior stable while removing CHR-window object cost.

### Brush edits

Brush edits should change from:

- find item
- edit item pixels

to:

- resolve `bank + tileIndex + localPixelX + localPixelY`
- write to `chrBanksBytes`
- update undo / redo and duplicate sync
- mark the affected CHR bank tile dirty

If we repaint only on bank switch in v1, dirty tracking can simply set:

- `bankCanvasDirty = true`

If we want incremental updates later, dirty tracking can repaint only the affected tile region.

## Concrete Refactor Phases

### Phase 0. Baseline and guardrails

- measure current CHR bank rebuild time
- measure CHR window draw time
- measure object count / tile count assumptions
- add tests around CHR selection, drag, and edit behavior

### Phase 1. Introduce bank canvas rendering

- add `BankCanvasController`
- add one shader-backed bank render path
- let CHR / ROM windows draw from the bank canvas
- keep old tile objects temporarily for compatibility

This phase proves the rendering path before removing old state.

### Phase 2. Remove per-cell CHR tile ownership

- stop filling CHR layers with `Tile` objects
- switch CHR hit testing to virtual tile lookup
- switch CHR selection logic to virtual tile handles
- switch CHR label logic to computed tile indices

### Phase 3. Rework drag payloads

- allow CHR windows to start drag from virtual tile handles
- keep destination windows compatible
- materialize real tile refs only when needed

### Phase 4. Rework editing path

- route CHR brush edits through `chrBanksBytes`
- invalidate bank canvas on edit
- optionally repaint dirty tile regions
- keep duplicate sync and undo / redo behavior unchanged

### Phase 5. Cleanup

- make `tilesPool` lazy for non-CHR consumers
- remove CHR-window dependence on `Tile.image`
- remove unused per-tile CHR draw code from the CHR path

## Expected Wins

- far fewer draw calls in CHR / ROM windows
- far fewer `Image` / `ImageData` allocations
- lower rebuild cost when opening or switching banks
- simpler CHR-window render loop
- better FPS stability on average hardware

## Risks

- current controllers assume item-backed CHR cells in many places
- drag/drop may have hidden dependencies on real `Tile` objects
- brush tools currently read through tile refs
- selection overlay code may assume stack-backed cells
- if we repaint the whole bank too often, the gain may be smaller than expected

## Acceptance Criteria For The First Cut

- CHR / ROM windows no longer allocate 512 drawable tile objects per bank for rendering
- switching banks repaints one bank canvas and displays the correct tiles
- CHR selection still works in `8x8` and `8x16` modes
- dragging from CHR / ROM windows still works
- pixel edits still persist to ROM save
- undo / redo still works for CHR edits
- duplicate-tile sync still works
- no visible regression in palette rendering for CHR / ROM windows

## Recommendation

Implement the refactor as a **hybrid CPU-authoritative + shader-rendered CHR window** first.

That gets the performance win with much lower risk. If that works well, we can evaluate whether full GPU-side mutation is still worth doing.

## Open Questions

1. The requested canvas size is `128 x 156`, but `512` physical `8x8` tiles implies `128 x 256`. Which one should be treated as correct?
2. For the first implementation, is it acceptable to use shaders for fast rendering while keeping CPU bytes as the source of truth for pixel edits and flood fill?
3. When switching banks, should we keep only one live bank canvas, or cache the previous / next bank as well for smoother navigation?
4. When a CHR tile is dragged into another window, is on-demand materialization of a real `Tile` object acceptable at drag/drop time, as long as CHR windows themselves stay virtualized?
