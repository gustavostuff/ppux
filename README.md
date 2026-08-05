![](img/readme_images/logo_v2.png)

An NES/Famicom Graphics Studio. Mod classic games or build new Homebrew assets.

<img src="img/readme_images/app_example_new.png" alt="">

![Version](https://img.shields.io/badge/version-0.2.0_(beta)-6366F1?style=flat)
[![Donate](https://img.shields.io/badge/Donate-ff69b4?style=flat&logo=githubsponsors&logoColor=white)](https://ko-fi.com/tavuntu)

Edit graphics in game-context (as the player sees them), no tile puzzle solving.

PPUX uses an in-app [database](#database) plus project files to understand banks, palettes, sprite layouts, animations, and other ROM-specific structures. You drop an NES ROM and eveything is assembled for you, ready to be edited. That is the goal of PPUX.

- [Basic Usage](#basic-usage)
  - [Getting started](#getting-started)
  - [Windows system](#windows-system)
  - [Toolbars](#toolbars)
  - [Palette windows](#palette-windows)
  - [Main controls](#main-controls)
  - [Tile mode](#tile-mode)
  - [Edit mode](#edit-mode)
  - [PNG drops](#png-drops)
- [Advanced](#advanced)
  - [Database](#database)
  - [DB contribution tracker](#db-contribution-tracker)
  - [Lua project mapping](#lua-project-mapping)
  - [Sketch canvas windows](#sketch-canvas-windows)
  - [Gallery ROM](#gallery-rom)
  - [PPU frame windows](#ppu-frame-windows)
  - [Byte budget for PPU Frame windows](#byte-budget-for-ppu-frame-windows)
  - [PPU frame editing notes](#ppu-frame-editing-notes)
  - [Current nametable codec coverage](#current-nametable-codec-coverage)
  - [OAM animation windows](#oam-animation-windows)
  - [ROM palette windows](#rom-palette-windows)
  - [Window references between entries](#window-references-between-entries)
  - [ROM patches](#rom-patches)
- [Development](#development)
  - [Build packages](#build-packages)
  - [Unit testing](#unit-testing)
  - [E2E testing](#e2e-testing)
- [Notes](#notes)
  - [Display resolution](#display-resolution)
  - [Canvas scale and filter](#canvas-scale-and-filter)
  - [Built with LÖVE](#built-with-löve)
  - [Custom `love.run` loop](#custom-loverun-loop)

## Basic Usage

### Getting started

After dropping a ROM into the window, PPUX will either:

1. Open a default layout.
2. Open a DB layout.
3. Open a *.lua or *.ppux user project (if any).

Notes:

* You can open a project from the app toolbar or with `Ctrl + O`.
* You can also start a **sketch-only** workspace (no game ROM required), to work on graphics "from scratch" (see [Sketch canvas windows](#sketch-canvas-windows) and [Gallery ROM](#gallery-rom) sections).

If a ROM has no DB entry yet, it can still be used normally. DB entries are just curated starting points. Any user can "pick" a game and start working on a user project that can be used for a new DB entry Pull Request. [See this section](#db-contribution-tracker).

### Windows system

Windows are the main work areas in PPUX. Some are source windows, some are layout windows, and some are ROM-backed helper windows.

| Window                 | Taskbar icon                                                                                                             | Description                                                                                                                                      |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------|
| CHR Banks              | <img src="img/readme_images/windows_system_table/icon_chr_window.png" alt="CHR Banks taskbar icon">                      | Primary source window for normal CHR bank data                                                                                                   |
| ROM Banks              | <img src="img/readme_images/windows_system_table/icon_rom_window.png" alt="ROM Banks taskbar icon">                      | Same as CHR Banks, but loads the whole ROM                                                                                                       |
| Static Art (tiles)     | <img src="img/readme_images/windows_system_table/icon_static_tile_window.png" alt="Static Art tiles taskbar icon">       | Single-layer tile composition window for mockups and UI pieces                                                                                   |
| Animation (tiles)      | <img src="img/readme_images/windows_system_table/icon_animated_tile_window.gif" alt="Animation tiles taskbar icon">      | Tile animation window where each layer acts as a frame                                                                                           |
| Static Art (sprites)   | <img src="img/readme_images/windows_system_table/icon_static_sprite_window.png" alt="Static Art sprites taskbar icon">   | Single-layer sprite composition window with pixel-level placement                                                                                |
| Animation (sprites)    | <img src="img/readme_images/windows_system_table/icon_animated_sprite_window.gif" alt="Animation sprites taskbar icon">  | Sprite animation window for frame-by-frame sprite layouts                                                                                        |
| OAM Animation          | <img src="img/readme_images/windows_system_table/icon_oam_animated_window.gif" alt="OAM Animation taskbar icon">         | ROM-backed sprite animation, **requires a linked Pattern table** window for sprite CHR and each sprite is created from a real ROM address (OAM)  |
| Global palette         | <img src="img/readme_images/windows_system_table/icon_palette_window.png" alt="Global palette taskbar icon">             | Global palette window for items without an assigned ROM palette (cycle with PgUp/PgDown)                                                         |
| ROM palette            | <img src="img/readme_images/windows_system_table/icon_rom_palette_window.png" alt="ROM palette taskbar icon">            | ROM palette editor: **ROM** role (addresses) or **Sketch** role (free 4x4 for sketch canvases)                                                   |
| PPU Frame              | <img src="img/readme_images/windows_system_table/icon_ppu_frame_window.png" alt="PPU Frame taskbar icon">                | ROM-backed nametable and sprite view. It **also** requires pattern table links for rendering                                                     |
| Pattern table          | <img src="img/readme_images/windows_system_table/icon_pattern_table_window.png" alt="Pattern table taskbar icon">        | Sub-set of CHR/ROM items, intended to mimic the actual pattern tables assembled in game run-time                                                 |
| Sketch canvas          | <img src="img/readme_images/windows_system_table/sketch_canvas_window.png" alt="Sketch canvas taskbar icon">             | Free 256x240 background paint canvas. It packs into a linked **Pattern table**; see [Sketch canvas windows](#sketch-canvas-windows)              |

### Toolbars

#### App toolbar

The App toolbar sits at the top and hosts global quick actions. It also reserves space for status text on the right.

<img src="img/readme_images/toolbars/app_toolbar.png" alt="App toolbar">

1. **New window** - opens the new window creation flow (`Ctrl + N`).
2. **Open project** - `Ctrl + O`.
3. **Save options** - `Ctrl + S` (save / export flows).
4. **Copy** - copies the current selection (`Ctrl + C` in **tile mode** only; works on tile or sprite layers where clipboard is allowed; blocked on PPU Frame and OAM Animation sprite layers).
5. **Cut** - `Ctrl + X` (for now, tile mode only for keyboard shortcuts).
6. **Paste** - `Ctrl + V` (for now, tile mode only for keyboard shortcuts).
7. **Zoom out** - zooms in the focused window.
8. **Zoom in** - zooms out the focused window.
9. **Mirror X** - toggles horizontal mirror preview in the **focused** window. Shortcut: **`M`**.
10. **Always on top** - toggles whether the **focused** window stays above others. Also available from the window's title-bar menu.
11. **Add column to the right** - on grid-resizable layout windows only. Hold **Shift** to switch the same control to **Remove last column** (tooltip updates).
12. **Add row below** - Same as the previous one, but for rows.
13. **Clone focused window** - duplicate the current window's kind and state where supported.
14. **Reference PNG** - add or remove a reference image on eligible **layout** windows. **`Alt + R`** toggles visibility while a reference is attached.
15. **Generate gallery ROM** - builds an interactive `.nes` gallery ROM from packed **Sketch canvas** windows (see [Gallery ROM](#gallery-rom)).
16. **Relocation pointer calculator** - helper for nametable **`relocateTo`** workflows: turns a ROM file offset into little-endian pointer bytes for `romPatches` (see [PPU frame windows](#ppu-frame-windows)).

#### CHR Banks toolbar

<img src="img/readme_images/toolbars/chr_banks_toolbar.png" alt="CHR Banks specialized toolbar">

1. **Previous bank** - `Left` key.
2. **Next bank** - `Right` key.
3. **Open base ROM folder** - opens your OS file manager on the folder that contains the loaded base ROM.
4. **Tile layout (8x8 / 8x16)** - straight `8x8` rows vs paired `8x16` layout - **`Ctrl + M`**.
5. **Diff vs loaded CHR** - toggles "git-like" overlays on the bank canvas: compares current CHR tile bytes against the original ROM bytes. Shortcut: D.
6. **Sync duplicate tiles** - ON: identical tiles edit together. OFF: independent cells.

#### ROM Banks toolbar

<img src="img/readme_images/toolbars/rom_banks_toolbar.png" alt="ROM Banks specialized toolbar">

Same strip as CHR Banks, excluding **Sync duplicate tiles** (a full-ROM surface makes that unsafe).

#### Pattern table toolbar

<img src="img/readme_images/toolbars/pattern_table_toolbar.png" alt="Pattern table specialized toolbar">

1. **Tile layout (8x8 / 8x16)** - straight `8x8` rows vs paired `8x16` layout - **`Ctrl + M`**.
2. **Pattern table link (source)** - left-click for a menu: jump to linked consumer layer(s), or remove all links from this pattern table.

Logical **ranges** are built by dragging tiles from **CHR Banks** or **ROM Banks** windows onto the pattern table canvas (not a toolbar button). Ranges must add up to **256** tiles for a complete map.

When a **Sketch canvas** owns the pattern table, CHR/ROM drops are blocked and the catalog is filled from the sketch pattern generation mechanism.

#### Sketch canvas toolbar

<img src="img/readme_images/toolbars/sketch_canvas_toolbar.png" alt="Sketch canvas specialized toolbar">

1. **Palette link handle** - right-drag onto a **sketch-mode** ROM palette (or left-click for a menu). Turns **green** when linked. Needed for live multi-palette preview and Gallery ROM colors.
2. **Pattern table link** - left-click to link, jump to, or unlink a **Pattern table**.
3. **Tolerance (- / value / +)** - pixel-diff grouping for Generate (0-32). When linked, changing tolerance live-regenerates the pattern table.
4. **Generate** - packs the paint canvas into up to 256 unique patterns and applies them to the linked pattern table. Highlights when pixels changed since the last pack.
5. **Export CHR** - writes a 4KB CHR bank (256 tiles) beside the project/ROM folder (needs a successful Generate).
6. **Export nametable** - writes a 1024-byte `.nam` (960 tiles + 64 attribute bytes).

#### Static Art (tiles and sprites) toolbar

<img src="img/readme_images/toolbars/static_tiles_toolbar.png" alt="Static Art tiles/sprites specialized toolbar">

1. **Palette link handle** - right-drag onto a **ROM palette** window, or from the ROM palette's handle onto this window. Left-click to link via a menu.

#### Animation toolbar (for both sprites and tiles)

<img src="img/readme_images/toolbars/animation_tile_toolbar.png" alt="Animation tiles specialized toolbar">

1. **Previous layer** - `Shift` + `Down` key.
2. **Next layer** - `Shift` + `Up` key.
3. **Remove layer** - `-` key; refuses when only one frame remains (button stays visible).
4. **Add layer** - `+` key.
5. **Copy from previous layer** - Copies everything, including palette links to individual items.
6. **Play / Pause** - `P` key, layer switching is blocked while playing.
7. **Frame delay** - `Shift` + `Left` or `Shift` + `Right` adjusts delay for all frames. Status bar shows the current value.
8. **Palette link handle** - Same ROM palette linking behavior as [Static Art](#static-art-tiles-and-sprites-toolbar).


#### OAM Animation toolbar

<img src="img/readme_images/toolbars/oam_animation.png" alt="OAM Animation specialized toolbar">

1. **Previous layer** - `Shift` + `Down` key.
2. **Next layer** - `Shift` + `Up` key.
3. **Remove layer** - `-` key, refuses when only one frame remains.
4. **Add layer** - `+` key.
5. **Add sprite** - visible when the active layer is a sprite layer.
6. **Toggle origin guides** - toggles dotted reference lines, this is user defined, not something that comes from ROM data.
7. **Copy from previous layer** - Copies everything, including palette links to individual items.
8. **Play / Pause** - `P` key, layer switching is blocked while playing.
9. **Frame delay** - `Shift` + `Left` / `Shift` + `Right` adjusts delay for all frames. Status bar shows the current value.
10. **Pattern table link** - left-click for a menu to link or unlink a **Pattern table** window for **all frames** at once (**required** for sprite CHR).
11. **Palette link handle** - Same ROM palette linking behavior as [Static Art](#static-art-tiles-and-sprites-toolbar).

**Shift + right-drag** on the canvas moves sprite `originX` / `originY` (same as PPU Frame sprite layers).

#### Global palette toolbar

<img src="img/readme_images/toolbars/global_palette.png" alt="Global palette specialized toolbar">

1. **Previous grouped slot** (when Grouped palettes is enabled).
2. **Next grouped slot** (when Grouped palettes is enabled).
3. **Compact / normal view** - Changes the window's size, basically.
4. **Set as active palette** - for painting where no ROM palette applies (when there are multiple global palettes, use PgUp/PgDown to cycle through them).

#### ROM palette toolbar

<img src="img/readme_images/toolbars/rom_palette.png" alt="ROM palette specialized toolbar">

1. **Previous grouped slot** (when Grouped palettes is enabled).
2. **Next grouped slot** (when Grouped palettes is enabled).
3. **Compact / normal view** - Changes the window's size, basically.
4. **Palette link handle (source)** - right-drag to link layers onto destinations, or left-click for a menu.

#### PPU Frame toolbar

<img src="img/readme_images/toolbars/ppu_frame_sprite_layer_toolbar.png" alt="PPU Frame toolbar">

1. **Previous layer** - `Shift` + `Down` key.
2. **Next layer** - `Shift` + `Up` key.
3. **Nametable range** - Set compressed nametable **start/end** ROM addresses (the range/stream of bytes used to build a given pattern table).
4. **Add sprite** - Adds a sprite (creates a sprite layer first, if there is none).
5. **Pattern table link** - left-click for a menu with separate **background** and **sprites** submenus to link **Pattern table** windows (**required** for nametable and sprite CHR).
6. **Toggle origin guides** - hidden until a sprite layer exists, it toggles dotted reference lines on sprite layers.

### Palette windows

Palette windows are the palette editors/viewers used by the app.

There are 2 kinds:

* `Global palette`: the fallback palette for content that does not have a ROM palette linked to it. Use this for mockups, freeform art, and anything with no specific in-game palette assigned.
* `ROM palette`: a `4x4` palette window. When you create one, PPUX asks for a **role**:
  * **ROM** - backed by ROM addresses (in-game palette editing).
  * **Sketch** - not tied to ROM addresses, linked only to **Sketch canvas** windows.

|                | Normal mode | Compact mode |
|----------------|-------------|--------------|
| Global palette | <img src="img/readme_images/palettes_table/global_palette_normal.png" alt="Global palette normal mode"> | <img src="img/readme_images/palettes_table/global_palette_compact.png" alt="Global palette compact mode"> |
| ROM palette    | <img src="img/readme_images/palettes_table/rom_palette_normal.png" alt="ROM palette normal mode"> | <img src="img/readme_images/palettes_table/rom_palette_compact.png" alt="ROM palette compact mode"> |

**Creating a link**

* Drag (right-drag) from a **ROM palette** window's connect handle and release over a destination window, **or**:
* Drag (right-drag) from a **destination** window's connect handle (**Static Art**, **Animation** tiles/sprites, **OAM Animation**, **Sketch canvas**, etc.) and release over a matching **ROM palette** window, **or**:
* Use left-click for contextual menus (**Link To Palette**, **Remove ROM palette link**, **Jump to linked palette**, etc).

Sketch canvases only accept **sketch-mode** palettes; other layout windows use **ROM**-role palettes.

**On-canvas connection handles**

Linked ROM palette / pattern-table windows also show small **squares** on the left edge of the window chrome (or bellow, if collapsed). Hover shows the link lines (depending on **Settings -> Appearance -> Window links**). Click a connected square to **focus and raise** the linked window(s).

### Main controls

- `Ctrl + 1/2/3`: set the **app window** to 1x, 2x, or 3x integer scale of the 640x360 canvas (e.g. 1280x720, 1920x1080).
- `Page Up` / `Page Down`: cycle which **global** (**non-ROM**) palette is active (ROM palette windows are not cycled). When **Grouped palettes** is on, the grouped **global** slot (which palette is shown) stays in sync.
- `Ctrl + F`: toggle fullscreen.
- `Ctrl + N`: open `New Window`.
- `Ctrl + S`: open save options.
- `Tab`: toggle `Tile` / `Edit` mode.
- `Space`: Highlihts all sprites in the active sprite layer.
- `Ctrl + G`: Cycle through different layer grids.
- `Ctrl + R`: toggle shader rendering for the focused layer, ON by default (patterns are shader-colored, app-wide). When disabled, it shows gray values matching the pixel color code: 0, 1, 2 or 3.
- In `ppu_frame` and `oam_animation` windows, clipboard actions (Ctrl + C/V/X) are blocked **on sprite** layers, because of reasons I'm too lazy to explain.
- `Right click` or `middle click` drag: move windows.
- taskbar: focus, restore, and manage windows.

### Tile mode

<img src="img/readme_images/tile_mode_indicator.png" alt="">

Tile mode is for selection, drag, drop and tile-level editing in general.

- Left click to select.
- `Ctrl + click` or `Shift + drag` for multi-selection.
- `Ctrl + A` to select all.
- `Delete` / `Backspace` to remove selection where supported.
- arrows to move tile selections among **occupied** cells.
- `Shift + Up/Down` to switch layers in **multi-layer** windows (animations, PPU Frame, OAM Animation, etc.): **`Up` = next layer, `Down` = previous**. **Static Art** windows stay single-layer and do not use layer switching shortcuts.
- `Ctrl + Up/Down` to change inactive-layer opacity.
- `1` to `4` to assign palette numbers to selected tiles/sprites where supported.
- `H` / `V` to mirror selected sprites in a given sprite layer.
- Bank windows: `Left/Right` switch banks, **`Ctrl + M`** toggles `8x8` / `8x16` layout, **`M`** toggles **Mirror X**, `D` toggles **diff vs loaded CHR**.

### Edit mode

<img src="img/readme_images/edit_mode_indicator.png" alt="">

Edit mode is for pixel-level editing.

- Left click to paint.
- `Shift + click` draws a line from the last painted/clicked point.
- `R` toggles the rectangle fill tool.
- Hold `G` and left click to grab a color.
- **Right-click** also picks the color under the cursor.
- Hold `F` and left click to flood fill.
- On a **Sketch canvas**: hold **`C`** and left-click to mask all pixels of the clicked color, hold **`C`** and right-click to clear the mask.
- On a **Sketch canvas**: **`S`** toggles the pixel select tool (drag for a rectangle; **Shift+drag** for freeform).
- `1` to `4` to choose the active color.
- `Alt + 1/2/3/4` to change brush size presets.
- `Ctrl + Alt + mouse wheel` also changes brush size.
- `Ctrl + R` toggles shader rendering for the focused layer.
- `Ctrl + G` toggles the focused window grid.

### PNG drops

You can drag and drop a PNG directly into PPUX. The drop is always applied to the window **under the mouse**. If the pointer is not over any window, the **focused** window is used as the drop target instead.

**Sprite** PNG import (Static Art, Animation, OAM Animation, or **PPU Frame with the sprite layer active**):

* **Static Art**, **Animation**, and **OAM Animation**: a window qualifies if it has **any** sprite layer.
* **PPU Frame**: a window qualifies for sprite import only when the **active layer** is the **sprite** layer. If the active layer is the **tile** layer, the drop is **not** treated as a sprite import.
* If you have selected sprites, PPUX imports into those sprites in selection order.
* If no sprites are selected, PPUX imports into the layer's sprites from first to last.
* The PNG must use at most 4 total colors including transparency, or at most 3 non-transparent colors.
* The PNG dimensions must align to the current sprite mode: `8x8` sprites require multiples of `8x8`, and `8x16` sprites require multiples of `8x16`.
* The image is split into sprite-sized frames from left to right, top to bottom.
* Fully transparent frames are skipped.
* When importing into an unselected sprite layer, PPUX also repositions sprites to match the frame grid automatically.

PPU Frame windows (nametable unscramble):

* When the drop is **not** handled as sprite import, dropping on a **`ppu_frame`** window **under the mouse** runs the **nametable unscramble** flow for that screen: it matches the PNG against the current patterns in CHR/ROM and tries to build the nametable layout automatically. This is a powerful/time-saving piece of functionality but it's hard to explain exactly how it works, video tutorials will probably be more useful (video tutorials are a To-Do).

Notes:

* The unscramble functionality needs an update and might not be working properly. Right now it matches the PNG patterns against the CHR/ROM banks window, but it should do it against the linked pattern table window.
* On CHR and ROM bank windows, dropping a PNG imports the image into the selected tile position, or the top-left if nothing is selected.
* PNG drops aren't currently supported for regular Tiles windows (static or animated).

## Advanced

### Database

The DB lets PPUX recognize specific ROMs and open a tailored starting workspace automatically.

DB entries are matched by ROM SHA-1 and can define open windows, relevant CHR banks, palette windows, ROM-backed views, and the initial workspace arrangement. If no DB entry exists, PPUX falls back to a default layout. User projects (*.lua and *.ppux) take priority over DB defaults.

Coverage might change frequently, use the [DB contribution tracker](#db-contribution-tracker) for the current status and in-progress entries.

### DB contribution tracker

The [DB contribution tracker sheet](https://docs.google.com/spreadsheets/d/1uxwTMG9cmv7juRGnYeg7M8aFsWqMgMWwBduhdpviIm4/edit?gid=1408935396#gid=1408935396) is a shared place to track which games already have DB coverage, which ones are in progress, pending, etc. Use it to coordinate contributions, avoid duplicate effort, and leave notes about the current status of a game-specific DB entry.

### Lua project mapping

Lua project files are plain Lua tables returned from `<rom>.lua`:

```lua
return {
  kind = "project",
  projectVersion = 1,
  currentBank = 1,
  focusedWindowId = "bank",
  edits = {},
  windows = {}
}
```

The most important fields are probably `windows` and `edits`. For `windows`, common fields include `kind`, `id`, `title`, `x/y/z`, `zoom`, workspace size, viewport size, scroll position, and layer state. For edits, the data stores per-bank, per-tile pixel edits applied on top of the source ROM data, using a compact compressed format.

The recommended workflow is to save once from the UI, use the generated project (*.lua or *.ppux) as the template, then create windows, layouts, edits, etc, and keep the project growing as you wish (either for personal use, for sharing or even for a new DB entry PR).

Notes:

* PPUX never overwrites the original ROM, pixel edits and other byte changes (like patches, palette color changes, etc) are written into `<rom>_edited.nes`.
* Project files are saved either as `<rom>.lua` and `<rom>.ppux`.
* `*.ppux` files are just zlib-compressed versions of Lua project files, useful when you want smaller files or prefer not to keep the project contents easily readable.
* Understand `<rom>` as the actual file name for the ROM you're working on (aka base ROM), it can contain spaces and dots.

Best practice: keep the base ROM, edited ROM, and project files in the same folder.

### Sketch canvas windows

Sketch canvases are for **creating NES background art** from zero, on a free 256x240 paint buffer (32x30 tiles of 8x8), then packing that paint into a real nametable + pattern table catalog.

Note: The pixel art tools available for Sketch Canvas windows are not available (not fully) for other kinds of windows, but this will be addressed. The UI still needs work too (toolbar icons, binary save flow, etc).

#### Paint vs packed (Tile) view

| Mode | After Generate | Behavior |
| --- | --- | --- |
| **Edit** | Free paint | Pixel brush, fill, select, color mask. Paint is the source of truth |
| **Tile** | Packed view | Screen is composed from the current (linked) nametable tile pool. Painting is blocked. Select tiles, rearrange, remove, and change attributes.

#### Edit-mode tools exclusive (for now) to Sketch Canvas windows:

* **`S`** - pixel selection tool (rectangle; **Shift+drag** freeform).
* Hold **`C` + left-click** - same-color paint mask (only that color paints/fills). Hold **`C` + right-click** to clear.

#### Export

From the sketch toolbar (after Generate):

* **Export CHR** -> 4KB bank (256 tiles).
* **Export nametable** -> 1024 bytes (960 tile indices + 64 attribute bytes).

The binary files land next to the open project or ROM folder.

### Gallery ROM

**Generate gallery ROM** on the app toolbar (NES cartridge icon) builds a CNROM gallery `.nes` from every **packed** sketch canvas in window order (up to 16 slides).

1. Confirm modal lists the slides that will be included.
2. PPUX copies the gallery template into a writable cache, writes CHR/nametable/palette binaries, assembles with **ca65/ld65** (cc65), and saves `{stem}_gallery.nes` beside your project/ROM.
3. A result modal shows the output path or an error.

Each slide includes the linked sketch palette (or a default brown ramp) and the sketch attribute table.

### PPU frame windows

`ppu_frame` windows are structured screen views: a **tile** layer backed by compressed nametable data in ROM, plus an optional **sprite** overlay that tracks real OAM bytes. Link **Pattern table** windows from the toolbar so the tile layer, sprite layer, or both can resolve CHR through shared **`patternTable.ranges`**. The same **Pattern table** window can be linked from multiple PPU frames or OAM animation windows.

Use **New Window > PPU Frame** and the toolbar actions or right-click menus to edit nametables and sprites. Saving the project persists layer state and nametable diffs.

When a compressed nametable may grow past its original ROM range, set **`relocateTo`** on the nametable layer so PPUX writes the stream to a new file offset, and patch the game's read pointer with `romPatches`. The app toolbar **Relocation pointer calculator** converts a `relocateTo` file offset into the little-endian `lo`/`hi` bytes for that patch. That said, you need to manually find the ROM location of the original table pointers, so you can patch them to the new values.

In other words, if there is empty/wasted space in the ROM, and this space can contain nametable data, maybe even with space to spare, then you might want to move the byte stream there and make the game logic read the data from there instead (the table pointer change). This is why `relocateTo` exists. That said, it's an advanced topic that might be better explained via a video tutorial.

### Byte budget for PPU Frame windows

PPU Frame tile layers support `noOverflowSupported = true`. This means the compressed nametable stream should stay within its original ROM byte budget.

Why it matters: some games leave safe free space after the stream, and some do not.

TMNT II is a good example of this: compressed byte ranges are packed tightly, so PPUX reads one nametable from a defined range while the next nametable begins immediately after it:

<img src="img/readme_images/nametable_bytes_tmnt.png" alt="Nametable title screen TMNT II">

Contra (J) example, where the byte "buffer" has plenty of space:

<img src="img/readme_images/nametable_bytes_contra.png" alt="Nametable title screen Contra">

PPUX warns when the compressed stream goes over budget and clears the warning if it returns to a valid size.

Note: some games might fall into both cases: they might have nametable data that has space to grow, and also nametable data that is tightly packed.

### Current nametable codec coverage

PPUX currently includes nametable codec implementations for Konami-style streams (`konami.lua`) and Zelda II PPU macro streams (`zelda2.lua`). New codecs and DB entries for different games/styles will be added as the app development progresses.

### OAM animation windows

`oam_animation` windows are ROM-backed sprite animations: **each layer is one hardware frame** of sprites tied to real OAM bytes. Like PPU frames, they **require** a linked **Pattern table** window for sprite CHR. Multiple animation or PPU windows can share the same pattern table.

**Creating/editing from the UI**

1. Open **New Window** and choose **OAM Animation**.
2. Link a **Pattern table** window from the toolbar, then use **Add sprite** and the frame/layer controls to build each frame. **OAM start address** is set in the add-sprite modal, CHR comes from the linked pattern table.
3. Frames can be **played** from the toolbar like other animation windows.
4. Items that share a `startAddr` **sync** with **PPU Frame** sprite layers (and other OAM windows) so OAM edits stay consistent everywhere that references the same bytes.
5. **Origin** and **origin guides** behave like PPU Frame sprite layers: **Shift + right-click drag** moves `originX` / `originY` and the dotted-line button toggles guides.

**Project file sketch:**

```lua
{
  kind = "oam_animation",
  id = "oam_animation_01",
  layers = {
    [1] = {
      kind = "sprite",
      linkedPatternTableWindowId = "pattern_table_oam_01",
      mode = "8x16",
      items = {
        { startAddr = 0x0095FA },
        ...
      }
    },
    ...
  }
}
```

Important fields are frame timing (`delaysPerLayer`), sprite frames (`layers`), local origin, palette source, and ROM-backed `startAddr` entries.

### ROM palette windows

`rom_palette` windows are `4x4` palette editors. **ROM**-role windows are backed by ROM addresses. **Sketch**-role windows hold free colors for [Sketch canvas](#sketch-canvas-windows).

Use the **connect button** on the ROM palette toolbar to right-drag links onto layers, and **left-click** it for source-side management (**Jump to linked layer**, **Remove all links**). Toggle **compact mode** from the same toolbar when you want a denser view. Destination windows still use their own connect handle plus the contextual **Link To Palette** / **Remove ROM palette link** entries documented in [Palette windows](#palette-windows).

Example (ROM-role addresses):

```lua
{
  kind = "rom_palette",
  paletteData = {
    romColors = {
      [1] = { 0x01F688, 0x0112ED, 0x0112EE, 0x0112EF },
      [2] = { 0x01F688, 0x0112F0, 0x0112F1, 0x0112F2 },
      [3] = { 0x01F688, 0x0112ED, 0x0112EE, 0x011243 },
      [4] = { 0x01F688, 0x0112F0, 0x0112F1, 0x011252 },
    }
  }
}
```

So each `romColors[row][col]` stores a ROM address for a given palette color. The first column is the universal background color, usually one single "shared" ROM address. On cells that are not directly editable, **double-click** opens the ROM address assignment flow described in the in-app status hint.

### Window references between entries

Some windows refer to other windows by `id`, for example:

```lua
paletteData = {
  winId = "rom_palette_02"
}
```

The referenced window should exist elsewhere in the same `windows` array for correct palette resolution; missing IDs may fall back to inline palette data in legacy projects.

### ROM patches

PPUX can apply small ROM patches from project data before windows are built (so the user is already working on top of "patched" ROM).

This is meant for targeted graphics-related setup such as forcing a game state or changing a small byte sequence. It is not a replacement for a full ROM hacking workflow.

Patches live on the project table as an array, `romPatches`. Each entry must include a **`reason`** string (non-empty description). Every value written is a **single byte** (0-255). Addresses are **unsigned integers** (0 or positive).

Use one of 3 different forms:

#### 1. Single byte (`address` + `value`)

One ROM address, one new byte.

```lua
{
  address = 0x009A36,
  reason = "Indoors, idle pose, change tile index in right leg",
  value = 0x70
}
```

#### 2. Contiguous range (`addresses.from` / optional `addresses.to` + `values`)

If `addresses.to` is omitted, it is derived from `addresses.from` and the number of entries in `values` (`to = from + #values - 1`). If you include `to`, the inclusive byte count must match `#values` (i.e. `to = from + #values - 1`).

```lua
{
  addresses = {
    from = 0x01F626,
    to = 0x01F62D
  },
  reason = "Change blinking letters in title screen (Player 1)",
  values = {
    0xCA, 0xFA, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
  }
}
```

#### 3. Address list (useful for non-contiguous values)

`addresses[1]` gets `values[1]`, `addresses[2]` gets `values[2]`, etc. The two lists must have the same length. Addresses do not need to be consecutive.

```lua
{
  addresses = {
    0x009A71,
    0x009A7B,
    0x009B00
  },
  reason = "Prepare sprite for 'on-the-ground' indoor sprites",
  values = {
    0x05,
    0x8A,
    0x00
  }
}
```

## Development

### Build packages

To build a packaged Windows app from Windows, run:

```bat
scripts\windows\build_windows.bat
```

The packaged Windows app will be created as `build\<version>\PPUX-<version>-win64.zip` (along with `build\<version>\PPUX.love`).

To build a packaged Linux app from Linux, run:

```bash
./scripts/unix/build_linux_appimage.sh
```

The packaged Linux app will be created as `build/<version>/PPUX-<version>-x86_64.AppImage`.

### Unit testing

PPUX includes a unit test suite, but right now it can only be executed from Linux:

```bash
./scripts/unix/run_unit_tests.sh
```

### E2E testing

PPUX also includes visible end-to-end test scenarios that boot the real app, this one should run ok in both Linux and Windows.

```bash
./scripts/unix/run_e2e_tests.sh
```

Or, on Windows:

```bat
scripts\windows\run_e2e_tests.bat
```

Single scenario example:

```bash
./scripts/unix/run_e2e_demo.sh modals
```

## Notes

### Display resolution

The entire UI is rendered to a **640x360** canvas (16:9). That base size is deliberate: it scales to common monitor resolutions with **integer pixel multiples** and no fuzzy fractional upscaling:

- **2x** - 720p (1280x720)
- **3x** - 1080p (1920x1080)
- **4x** - 1440p (2560x1440)
- **6x** - 4K (3840x2160)

Every UI pixel stays crisp when the OS window is sized to those integer multiples. Use **`Ctrl + 1/2/3`** to snap the app window to 1x, 2x, or 3x scale (640x360, 1280x720, 1920x1080), or resize freely. **Settings -> Appearance -> Canvas scale** controls how the workspace fits inside the window when it is not an exact multiple (see below).

### Canvas scale and filter

Open **Settings** from the taskbar menu (**Appearance** tab) to control how the 640x360 workspace is presented on screen. These options persist across **sessions only**.

**Canvas scale** - how the workspace fits the OS window:

- **Keep aspect** - scale uniformly to fill the window while preserving 16:9 (default)
- **Pixel-perfect** - integer scaling only; may letterbox, but keeps UI pixels sharp
- **Stretch** - fill the window on both axes; can distort if the window is not 16:9

**Canvas filter** - how scaled pixels are sampled:

- **Sharp** - nearest-neighbor filtering for crisp pixels (default)
- **Soft** - linear filtering for a smoother upscale
- **CRT** - barrel distortion and scanlines over the workspace (works best at 1080p and higher)

Other **Appearance** options:

- **Window links** - when to show on-canvas ROM palette / pattern-table link lines and left-edge connection handles (`never`, **`on_hover`** default, `always`, `auto_hide`)
- **Separate toolbar** - detach specialized toolbars from window headers

### Built with LÖVE

PPUX is built with [LÖVE](https://love2d.org/) 11.5, the open-source 2D framework for Lua. Rendering, input, windowing, and the custom UI all run on top of it.

### Custom `love.run` loop

Instead of LÖVE's default main loop, PPUX uses a custom `love.run` implementation. It keeps the familiar update/draw flow, but can run with lower latency during interactive frames (e.g., when the user is dragging the brush), where per-frame mouse polling and tighter frame pacing make strokes feel more responsive. When that mode is off, the loop falls back to calmer pacing closer to stock LÖVE behavior.
