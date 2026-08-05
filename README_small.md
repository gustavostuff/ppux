![](img/readme_images/logo_v2.png)

An NES/Famicom Graphics Studio. Mod classic games or build new Homebrew assets.

<img src="img/readme_images/app_example_new.png" alt="">

![Version](https://img.shields.io/badge/version-0.2.0_(beta)-6366F1?style=flat)
[![Donate](https://img.shields.io/badge/Donate-ff69b4?style=flat&logo=githubsponsors&logoColor=white)](https://ko-fi.com/tavuntu)

Edit graphics in game-context (as the player sees them), no tile puzzle solving.

PPUX uses an in-app [database](#database) plus project files to understand banks, palettes, sprite layouts, animations, and other ROM-specific structures. You drop an NES ROM and everything is assembled for you, ready to be edited.

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
  - [Lua project mapping](#lua-project-mapping)
  - [Sketch canvas & Gallery ROM](#sketch-canvas--gallery-rom)
  - [PPU frame & OAM](#ppu-frame--oam)
  - [ROM palette & patches](#rom-palette--patches)
- [Development](#development)
- [Notes](#notes)

## Basic Usage

### Getting started

After dropping a ROM into the window, PPUX opens a default layout, a DB layout, or a `*.lua` / `*.ppux` user project if one exists.

* Open a project from the app toolbar or with `Ctrl + O`.
* Start a **sketch-only** workspace (no game ROM) to work from scratch. See [Sketch canvas & Gallery ROM](#sketch-canvas--gallery-rom).
* ROMs without a DB entry still work. DB entries are curated starting points. Coordinate new DB work via the [DB contribution tracker](https://docs.google.com/spreadsheets/d/1uxwTMG9cmv7juRGnYeg7M8aFsWqMgMWwBduhdpviIm4/edit?gid=1408935396#gid=1408935396).

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
| OAM Animation          | <img src="img/readme_images/windows_system_table/icon_oam_animated_window.gif" alt="OAM Animation taskbar icon">         | ROM-backed sprite animation, **requires a linked Pattern table** window for sprite CHR. Each sprite is created from a real ROM address (OAM)     |
| Global palette         | <img src="img/readme_images/windows_system_table/icon_palette_window.png" alt="Global palette taskbar icon">             | Global palette window for items without an assigned ROM palette (cycle them with PgUp/PgDown)                                                         |
| ROM palette            | <img src="img/readme_images/windows_system_table/icon_rom_palette_window.png" alt="ROM palette taskbar icon">            | ROM palette editor: **ROM** role (addresses) or **Sketch** role (free 4x4 for sketch canvases)                                                   |
| PPU Frame              | <img src="img/readme_images/windows_system_table/icon_ppu_frame_window.png" alt="PPU Frame taskbar icon">                | ROM-backed nametable and sprite view. It **also** requires pattern table links for rendering                                                     |
| Pattern table          | <img src="img/readme_images/windows_system_table/icon_pattern_table_window.png" alt="Pattern table taskbar icon">        | Sub-set of CHR/ROM items, intended to mimic the actual pattern tables assembled in game run-time                                                 |
| Sketch canvas          | <img src="img/readme_images/windows_system_table/sketch_canvas_window.png" alt="Sketch canvas taskbar icon">             | Free 256x240 background paint canvas. It packs into a linked **Pattern table**. See [Sketch canvas & Gallery ROM](#sketch-canvas--gallery-rom)   |

### Toolbars

#### App toolbar

The App toolbar sits at the top and hosts global quick actions. It also reserves space for status text on the right.

<img src="img/readme_images/toolbars/app_toolbar.png" alt="App toolbar">

1. **New window** - opens the new window creation flow (`Ctrl + N`).
2. **Open project** - `Ctrl + O`.
3. **Save options** - `Ctrl + S` (save / export flows).
4. **Copy** - copies the current selection (`Ctrl + C` in **tile mode** only). Works on tile or sprite layers where clipboard is allowed. Blocked on PPU Frame and OAM Animation sprite layers.
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
15. **Generate gallery ROM** - builds an interactive `.nes` gallery ROM from packed **Sketch canvas** windows (see [Sketch canvas & Gallery ROM](#sketch-canvas--gallery-rom)).
16. **Relocation pointer calculator** - helper for nametable **`relocateTo`** workflows: turns a ROM file offset into little-endian pointer bytes for `romPatches` (see [PPU frame & OAM](#ppu-frame--oam)).

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

Logical **ranges** are built by dragging tiles from **CHR Banks** or **ROM Banks** onto the pattern table canvas. Ranges must add up to **256** tiles for a complete map. When a **Sketch canvas** owns the pattern table, CHR/ROM drops are blocked and the catalog comes from Generate.

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
3. **Remove layer** - `-` key. Refuses when only one frame remains (button stays visible).
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

* **Global palette** - fallback for content with no ROM palette linked.
* **ROM palette** (`4x4`) - when creating one, choose a role: **ROM** (ROM addresses) or **Sketch** (free colors for Sketch canvas only).

|                | Normal mode | Compact mode |
|----------------|-------------|--------------|
| Global palette | <img src="img/readme_images/palettes_table/global_palette_normal.png" alt="Global palette normal mode"> | <img src="img/readme_images/palettes_table/global_palette_compact.png" alt="Global palette compact mode"> |
| ROM palette    | <img src="img/readme_images/palettes_table/rom_palette_normal.png" alt="ROM palette normal mode"> | <img src="img/readme_images/palettes_table/rom_palette_compact.png" alt="ROM palette compact mode"> |

Link by right-dragging a connect handle (palette or destination), or use left-click menus. Sketch canvases only accept **sketch-mode** palettes. Other layout windows use **ROM**-role palettes. Linked windows also show small squares on the chrome edge. Click to focus the linked window(s).

### Main controls

- `Ctrl + 1/2/3`: app window 1x / 2x / 3x of the 640x360 canvas.
- `Page Up` / `Page Down`: cycle active **global** palette.
- `Ctrl + F`: fullscreen. `Ctrl + N`: New Window. `Ctrl + S`: save options.
- `Tab`: toggle Tile / Edit mode.
- `Space`: highlight sprites on the active sprite layer.
- `Ctrl + G`: cycle layer grids. `Ctrl + R`: toggle shader coloring on the focused layer.
- Right/middle-click drag to move windows. Use the taskbar to focus and manage them.

### Tile mode

<img src="img/readme_images/tile_mode_indicator.png" alt="">

Selection, drag/drop, and tile-level editing. Multi-select with `Ctrl` / `Shift`. `Ctrl + A` selects all. Arrows move among occupied cells. `Shift + Up/Down` switches layers in multi-layer windows. `1` to `4` assign palette indices where supported. `H` / `V` mirror sprites.

### Edit mode

<img src="img/readme_images/edit_mode_indicator.png" alt="">

Pixel painting. Left-click paints. `Shift + click` draws a line. `R` rectangle fill. `G` / right-click sample. `F` flood fill. `1` to `4` choose color. `Alt + 1/2/3/4` or `Ctrl + Alt + wheel` for brush size. On **Sketch canvas**, `C` + click masks a color and `S` toggles region select (rectangular selection, unless shift is used before the click).

### PNG drops

Drop a PNG onto a window (or the focused window if the pointer is over empty space).

* **Sprite import** (Static Art / Animation / OAM, or PPU Frame with the **sprite** layer active): at most 4 colors including transparency. Size must align to `8x8` or `8x16`. Frames fill sprites left-to-right, top-to-bottom.
* **PPU Frame nametable unscramble**: when not treated as sprite import, matching a PNG against CHR/ROM patterns to rebuild the screen layout.
* CHR/ROM banks: import into the selected tile (or top-left). Not supported yet for regular Static/Animation tile windows.

Notes:

* The unscramble functionality needs an update and might not be working properly. Right now it matches the PNG patterns against the CHR/ROM banks window, but it should do it against the linked pattern table window.
* On CHR and ROM bank windows, dropping a PNG imports the image into the selected tile position, or the top-left if nothing is selected.

## Advanced

### Database

DB entries match ROM SHA-1 and open a tailored workspace (windows, banks, palettes, arrangement). No entry means the default layout. User projects override DB defaults. Track coverage and in-progress games in the [DB contribution tracker sheet](https://docs.google.com/spreadsheets/d/1uxwTMG9cmv7juRGnYeg7M8aFsWqMgMWwBduhdpviIm4/edit?gid=1408935396#gid=1408935396).

### Lua project mapping

Projects are Lua tables (`kind = "project"`) with `windows`, `edits`, and related fields. Save once from the UI and grow the generated `*.lua` / `*.ppux` file by creating new windows, assembling layouts, etc. PPUX never overwrites the base ROM. Edits go to `<rom>_edited.nes`. Keep the base ROM, edited ROM, and project in the same folder.

### Sketch canvas & Gallery ROM

Sketch canvases are a free 256x240 paint buffer that packs into a nametable + pattern table catalog.

| Mode | After Generate | Behavior |
| --- | --- | --- |
| **Edit** | Free paint | Pixel tools. Paint is the source of truth |
| **Tile** | Packed view | Composed from the linked nametable tile pool. Tiles rearranging and attribute bytes edit (keys 1-4) |

**Generate gallery ROM** (app toolbar) builds a CNROM `<rom>_gallery.nes` from packed sketch canvases (up to 16 slides), using each slide's linked sketch palette and attributes. Needs **ca65/ld65** (cc65).

### PPU frame & OAM

`ppu_frame` windows combine a compressed-nametable **tile** layer with optional ROM-backed **sprite** (OAM) overlay. Link **Pattern table** windows for CHR. Saving persists layer state and nametable diffs.

If a compressed stream may grow past its ROM range, set **`relocateTo`** and patch the game's pointer with `romPatches` (use the Relocation pointer calculator for little-endian bytes).

**Byte budget** (`noOverflowSupported = true`): some games pack streams tightly (TMNT II), others leave headroom (Contra J). PPUX warns when the stream exceeds budget.

<img src="img/readme_images/nametable_bytes_tmnt.png" alt="Nametable title screen TMNT II">

<img src="img/readme_images/nametable_bytes_contra.png" alt="Nametable title screen Contra">

Codecs today: Konami-style (`konami.lua`) and Zelda II PPU macros (`zelda2.lua`).

`oam_animation` windows are ROM-backed sprite animations (each layer = one hardware frame). Link a Pattern table, then add sprites with OAM start addresses. Shared `startAddr` values sync with PPU Frame sprite layers.

### ROM palette & patches

**ROM**-role `rom_palette` cells map to ROM addresses (`romColors[row][col]`). Double-click assigns an address. **Sketch**-role palettes are free colors (no address double-click). Other windows can reference a palette by `winId` instead of repeating hex.

`romPatches` apply small byte patches before windows build (not a full ROM-hacking suite). Each entry needs a `reason`. Forms: single `address`+`value`, contiguous `addresses.from`/`to`+`values`, or parallel `addresses`/`values` lists.

```lua
{
  address = 0x009A36,
  reason = "Indoors, idle pose, change tile index in right leg",
  value = 0x70
}
```

## Development

```bat
scripts\windows\build_windows.bat
```

```bash
./scripts/unix/build_linux_appimage.sh
./scripts/unix/run_unit_tests.sh
./scripts/unix/run_e2e_tests.sh
```

Windows E2E: `scripts\windows\run_e2e_tests.bat`. Unit tests are Linux-only for now.

## Notes

The UI renders to a **640x360** canvas (16:9) for crisp integer scaling (`Ctrl + 1/2/3` for 1x / 720p / 1080p). **Settings > Appearance** controls canvas scale (keep aspect / pixel-perfect / stretch), filter (sharp / soft / CRT), window-link visibility, and detached toolbars.

Built with [LÖVE](https://love2d.org/) 11.5. A custom `love.run` loop tightens input/frame pacing during interactive strokes.
