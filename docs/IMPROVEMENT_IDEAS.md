# Improvement Ideas

This is a suggestions document, not a commitment list.

The split here is intentional:
- around `70%` is focused on new features and quality-of-life improvements
- around `30%` is focused on architecture and maintainability

## Product And QoL

### 1. Stronger Drag Preview For CHR And ROM Drops
- Show the exact drop footprint before mouse release.
- For tile windows, preview the occupied grid cells.
- For sprite windows, preview the exact pixel placement and `8x16` pairing result.
- Reuse the same invalid-drop reasons already present: `out of bounds` and `not enough area to drop`.

Why it helps:
- grouped drag-and-drop is already powerful, but the user still has to infer the final shape
- this reduces trial-and-error when moving larger selections

### 2. Optional `8x16` Selection Mode In CHR And ROM Windows
- When sprite mode is `8x16`, optionally let CHR/ROM selection visually operate in `8x16` units.
- Keep the current `8x8` behavior as a toggleable fallback.
- Surface the current selection mode in the toolbar so the user knows what drag semantics are active.

Why it helps:
- it matches how sprite users think in `8x16` projects
- it reduces mental conversion when dragging from source banks into sprite windows

### 3. Layer Usage Overlay In CHR And ROM Windows
- Add a mode that highlights all tiles used by the active layer, not only while holding `Space`.
- Offer filtering:
  - current layer
  - whole window
  - all open art windows
- Optionally show usage counts per tile.

Why it helps:
- bank browsing becomes much more informative
- it supports cleanup work and duplicate hunting

### 4. Selection Clipboard History
- Keep more than one copied selection in memory.
- Let the user cycle recent clipboard entries.
- Support both tile and sprite payloads, preserving relative layout.

Why it helps:
- repetitive art work often jumps between a few recurring pieces
- this is a real productivity multiplier compared to a single clipboard slot

### 5. Better Replace And Remap Tools
- Add commands such as:
  - replace tile ref `A` with tile ref `B` in active layer
  - replace palette number `X` with `Y`
  - replace all instances in current bank / current window / whole project
- Include preview counts before applying.

Why it helps:
- a lot of ROM art cleanup is bulk replacement work
- doing this one item at a time is expensive and error-prone

### 6. Background-Oriented Multi-Selection Actions For Tile Layers
- Keep tile layers focused on background / nametable composition, not sprite-style transforms.
- Add group actions that fit that workflow better:
  - nudge selection by grid cells
  - rectangular copy / cut / paste with overwrite rules
  - fill selected area with repeated tile pattern
  - replace tile ref `A` with tile ref `B` inside the selection
  - remap palette numbers inside the selection
- Avoid sprite-like flip / mirror actions here, since those imply sprite semantics rather than background layout editing.

Why it helps:
- tile windows would gain stronger composition tools without blurring the boundary between background editing and sprite editing
- this stays aligned with the intended role of tile layers in the project

### 7. Better Edit-Mode Feedback
- Show the active brush footprint under the cursor before painting.
- Display a small live hint near the status bar:
  - current brush size
  - current color index
  - current layer
  - whether duplicate sync is enabled

Why it helps:
- the editor already has a lot of implicit state
- this lowers mode confusion without adding more clicks

### 8. Selection Sets / Named Groups
- Let the user save a current selection as a named set.
- Support restore, overwrite, rename, and delete.
- Useful for recurring sprite groups, animation subsets, or bank cleanup passes.

Why it helps:
- users often revisit the same regions repeatedly during a session
- this avoids rebuilding the same selection by hand

### 9. Palette Workflow Improvements
- Add a palette history stack for recently picked colors.
- Show a small palette usage summary for the active layer.
- Add a quick “normalize to palette N” action for selected items.

Why it helps:
- palette work is one of the highest-friction areas in NES graphics editing
- these are small features with high practical payoff

### 10. Project-Level Search And Navigation
- Search by:
  - tile ref
  - bank number
  - palette number
  - window title
  - layer name
- Jump directly to matching windows or tiles.

Why it helps:
- the app is growing into a multi-window workspace
- users need faster ways to answer “where is this tile used?”

### 11. Guided Invalid Action Feedback
- Expand tooltip and status messages for blocked actions:
  - why the drop failed
  - which boundary was exceeded
  - what would make it valid
- Consider short “next action” hints in the status bar.

Why it helps:
- many editor actions already have good rules, but the user does not always see the reasoning
- this makes advanced behavior easier to learn

### 12. Session Recovery / Crash Restore
- Save lightweight autosnapshots of:
  - open windows
  - focus
  - current bank
  - unsaved edits state
- Offer restore on next launch after a crash.

Why it helps:
- this is one of the highest-value safety nets for a tool with many open windows and long editing sessions

### 13. Contextual Menus With Right Click
- Add context-sensitive menus and likely repurpose right click away from window dragging.
- The main benefit is discoverability: more actions become visible exactly where the user is working.

Suggested menus:

#### CHR / ROM Window
- `Copy Tile`
  Action: copy the clicked tile ref.
- `Copy Selection`
  Action: copy the current CHR/ROM multi-selection as a grouped tile payload.
- `Select Matching Refs In Open Windows`
  Action: highlight or select all open-window items that reference the clicked tile.
- `Show Usage In Current Bank`
  Action: enable a temporary usage overlay for the clicked tile or selection.
- `Mark As Drag Source`
  Action: optional explicit mode for keyboard-friendly drag workflows later.
- `Open Replace/Remap`
  Action: open a dialog for replacing that tile ref in current layer / window / project.

#### Static Tile Window / Animation Tile Window
- `Cut`
  Action: cut the selected tile cells to clipboard.
- `Copy`
  Action: copy the selected tile cells.
- `Paste`
  Action: paste at the clicked anchor cell.
- `Delete`
  Action: clear the selected tile cells.
- `Nudge Left / Right / Up / Down`
  Action: move the selected block by one cell.
- `Replace Tile Ref...`
  Action: replace one tile ref with another inside the current selection or active layer.
- `Remap Palette...`
  Action: bulk-change palette numbers for the selection or layer.
- `Fill With Repeated Pattern`
  Action: repeat the clipboard or current selection across the selected rectangle.
- `Select All Matching Tile Refs`
  Action: select all cells in the window that use the clicked tile ref.

#### Static Sprite Window / Animation Sprite Window
- `Cut`
  Action: cut selected sprites.
- `Copy`
  Action: copy selected sprites.
- `Paste`
  Action: paste at the clicked anchor position.
- `Delete`
  Action: remove selected sprites.
- `Bring Forward`
  Action: move selected sprites one step up in draw order.
- `Send Backward`
  Action: move selected sprites one step down in draw order.
- `Mirror Horizontal`
  Action: toggle horizontal mirror on the selected sprites.
- `Mirror Vertical`
  Action: toggle vertical mirror on the selected sprites.
- `Assign Palette 1-4`
  Action: set palette number on the selection.
- `Select Matching Tile Refs`
  Action: select sprites using the same tile refs as the clicked sprite.

#### PPU Frame Window
- `Copy Tile`
  Action: copy the clicked nametable tile ref.
- `Paste Tile`
  Action: paste to the clicked cell.
- `Replace Tile Ref...`
  Action: replace a tile ref in the current nametable selection.
- `Remap Palette / Attribute...`
  Action: bulk-update attribute assignments where supported.
- `Reveal In CHR / ROM Window`
  Action: focus the active bank window and highlight the matching source tile.

#### Generic Window Background / Header Area
- `Rename Window`
  Action: rename the current window.
- `Duplicate Window`
  Action: create a copy of the window layout and content references.
- `Reset Zoom`
  Action: restore default zoom level.
- `Minimize`
  Action: minimize the window to the taskbar.
- `Close`
  Action: close the window.

Why it helps:
- advanced actions become easier to discover
- it reduces shortcut overload
- it makes window-specific features feel more intentional
- it creates a clean place for future bulk actions without bloating toolbars

## Architecture And Maintainability

### 1. Continue Extracting Behavior Out Of `window.lua`
- Keep `window.lua` focused on generic window state and drawing primitives.
- Move feature-specific overlay logic into small controllers, as already started with space highlight behavior.
- Candidate extractions:
  - selection overlay controller
  - tile overlay controller
  - sprite overlay controller
  - drag bounds / viewport clamp controller

Why it helps:
- `window.lua` is carrying too many responsibilities
- smaller controllers are easier to test in isolation

### 2. Build Shared Test Helpers For Mock Windows And Mock App State
- Create reusable test factories for:
  - tile windows
  - sprite windows
  - CHR/ROM windows
  - app state with `tilesPool`, `chrBanksBytes`, undo stack, and status hooks
- Reduce duplicated hand-written mocks across tests.

Why it helps:
- current tests work, but they pay a lot of setup cost per file
- this will make regressions faster to cover

### 3. Formalize Window Capability And Interaction Contracts
- Expand `window_capabilities.lua` or adjacent modules into a more explicit contract layer.
- Define shared capability checks for:
  - accepts grouped tile drop
  - supports edit mode painting
  - supports layer-wide highlight
  - supports marquee selection
  - supports palette assignment

Why it helps:
- several controllers currently infer behavior from `kind`, `flags`, or ad hoc checks
- explicit capability contracts reduce branching drift

### 4. Separate “Intent Resolution” From “Mutation”
- For more input flows, first resolve a structured action, then apply it.
- Example pattern:
  - resolve drop target and validation result
  - resolve paint hit and pixel target
  - resolve selection action
  - then mutate state only if resolution succeeds

Why it helps:
- easier unit tests
- clearer invalid-state handling
- lower risk of half-applied interactions

### 5. Add Small Data Models For Cross-Window Operations
- Standardize payload structures for:
  - grouped tile drag data
  - selection rectangles
  - highlight models
  - clipboard entries
- Prefer a few stable schemas over many ad hoc tables.

Why it helps:
- cross-window features are becoming more common
- stable payload shapes reduce hidden coupling

## Suggested Near-Term Focus

If prioritizing for impact, this order is reasonable:

1. stronger drag preview for grouped drops
2. optional `8x16` selection mode in CHR/ROM windows
3. layer usage overlay in CHR/ROM windows
4. contextual menus with right click
5. better replace/remap tools
6. continue extracting feature logic out of `window.lua`
