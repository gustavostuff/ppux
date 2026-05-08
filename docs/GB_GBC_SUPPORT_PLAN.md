# Plan: GB / GBC support in PPUX

## Test trace (one vertical at a time)

Ship and **verify** GB/GBC in this order - each step should be mergeable and testable before the next.

| Step | Focus | What "green" looks like |
|------|--------|-------------------------|
| **1** | **CHR (GB \| GBC) banks window** - pattern tiles, brush / pixel edits | Open a `.gb`/`.gbc`, see bank grid(s), paint pixels, undo/redo; **automated tests** for tile bytes <-> pixels (NES path unchanged). |
| **2** | **Drag / drop into Static art and Animation (sprite/tile) windows** | Drop PNG (or supported asset) onto those windows when a GB workspace is loaded; tiles resolve through **GB** 2bpp layout, not NES. |
| **3** | **ROM-backed windows** (tile view over raw ROM offsets, ROM palette bytes, etc.) | Defer until 1-2 are solid - those windows assume **file offsets** and NES-era workflows; GB needs stable offset rules (MBC, headers). |

The rest of this doc orbits **Step 1 first**: smallest surface that proves platform dispatch, backing, and the **Game Boy tile format** in the same UI patterns as NES CHR banks.

---

## Current NES-centric surface (repo reality)

- **Load path**: `rom_project_controller` -> `chr.parseINES` (16-byte iNES header, PRG/CHR layout, optional trainer) -> `ChrBackingController.configureFromParsedINES` -> `state.chrBanksBytes` as 8 KiB banks (`chr_backing_controller.lua`, `chr.lua`).
- **Tile I/O**: `chr.decodeTile` / `chr.setTilePixel` implement **NES 2bpp layout** (8 low bytes for the tile, then 8 high bytes - two **stacked** bitplanes).
- **ROM writeback**: `romsave.lua` -> `chr.replaceCHR` splices CHR using `meta.chr_start` / `meta.chr_end` / `meta.chr_size` from iNES. `rom_raw` mode patches bytes after the header via `ChrBackingController.rebuildROMFromBacking`.
- **Editor assumptions**: Pattern tables sized around **256 tiles per side** (brush / click validation), sprite space **256x256**, PPU-frame / nametable tooling and **Konami-style codecs** (`utils/nametable_utils.lua`, `db/*.lua`) are **game-specific NES RAM/ROM layouts**, not generic hardware.
- **Layouts**: `db/index.lua` keys **SHA-1 of the whole file** to hand-authored layouts (windows, ROM addresses, nametable ranges, patches).

GB/GBC work is **platform abstraction + parallel tile/ROM paths**, not a rewrite of NES code - keep existing NES functions and flows; add GB/GBC-specific ones and **thin glue** (router at load, dispatch for decode/set pixel).

---

## GB / GBC vs NES (what actually matters here)

On real hardware, the **LCD does not read the ROM file directly** - the CPU copies (or banks in) tile bytes into **VRAM**; the PPU fetches from there. For **Step 1**, you only need to edit **bytes that represent 8x8 tiles** in the same 2bpp sense as the console: *which* slice of the `.gb` file is "graphics" is game/MBC-specific, but the **encoding of one tile** is fixed by the hardware spec.

| Area | NES (today) | GB / GBC |
|------|-------------|----------|
| Container | iNES (`NES\x1a`), PRG + optional CHR | Usually **raw ROM** (no standard header like iNES); size 32 KiB-8 MiB+; **MBC** (memory bank controller) swaps which chunk of ROM is visible to the CPU - *same file, different window at runtime*. |
| On-screen tiles | PPU pattern tables + nametables | Games store **tile bitmaps in ROM** (often many banks) and **tile maps** elsewhere; maps may live in ROM or be built in **VRAM** - Step 3 territory. |
| 8x8 pixel encoding | NES CHR 2bpp | **GB 2bpp**: still 16 bytes per tile, but each **row** is a byte pair (bit planes **interleaved per line**). Same four color indices 0-3 per pixel; wrong layout = "snow" or diagonal garbage if you interpreted it as NES. |
| "CHR bank" | Natural 8 KiB CHR-ROM/RAM slices | **VRAM** holds up to **384 unique tiles** (two 256-tile windows overlap in real life - 192+192); ROM is often sliced mentally as **4 KiB** (128 tiles) or **8 KiB** (256 tiles) for tools. Step 1 can use **pseudo-banks** (fixed size over flat file) like today's `rom_raw` chunks. |
| Color | NES subpalettes | **DMG**: four fixed **grays** selected through palettes (BG/OBJ each pick from master shades). **GBC** adds **15-bit color** and per-tile **attributes** (palette id, bank, flip) - often **not** all in the same ROM byte as the tile pixels; Step 1 can still paint **2bpp indices** and use **project palettes** for preview. |
| Sprites | NES OAM | **40 sprites  x  4 bytes** in OAM; tiles still 8x8 or 8x16 - Step 2 when wiring drops to sprite windows. |
| Resolution / grids | 256x240 (tooling often 256x256) | Playfield **160x144**; not required for CHR bank painting, but useful context for later layout windows. |

**GBC** is not only "more colors": many games store **plain DMG-style 2bpp tiles in ROM** and use hardware to recolor - so a **DMG-tile-first** CHR window is still a valid GBC entry point.

---

## Step 1 - CHR banks window (test this first)

**Goal:** User loads `.gb` / `.gbc`, gets CHR-style bank windows, edits pixels with existing brush/undo machinery, backed by **GB tile bytes**.

### Implementation sketch (minimal NES touch)

- **`platform`** (`nes` \| `gb` \| `gbc`) on `appEditState`, set from extension (and optional `.gbc` -> `gbc`) when iNES magic is absent.
- **Load router** in `rom_project_controller` / `parseROM`: NES -> unchanged `chr.parseINES`; GB -> **flat ROM** metadata (size, optional `dataOffset` default 0), **no** `replaceCHR` in Step 1 if you defer "Export edited ROM" - project save + in-memory banks can be enough to call Step 1 done.
- **`chr.lua`**: add `decodeTileGB` / `setTilePixelGB` (+ tests in `test/tests/unit/chr.test.lua` or sibling file). NES `decodeTile` stays as-is.
- **Dispatch layer**: one small helper (e.g. `chr.decodeTileForPlatform(platform, ...)`) used by bank canvas / brush paths when `platform ~= "nes"`. *Avoid* editing every NES call site twice - centralize at the boundaries that already own `app` or `state`.
- **Backing**: reuse **pseudo-banks** over the whole file (`ChrBackingController` pattern: 4 KiB or 8 KiB slices, `mode = rom_raw`-like). *Tiles in ROM are still just bytes in order* - MBC only matters when the CPU **maps** addresses; for a static file viewer, contiguous pseudo-banks are a deliberate simplification until Step 3.
- **256-tile UI assumptions**: either map two 256-tile "pages" onto consecutive GB bank tiles, or relax validation for GB only (`mouse_click_controller`, brush bounds) - whatever matches how bank windows are instantiated for NES today (`bank_view_controller`, pattern table builder).

### Automated tests (Step 1 exit criteria)

1. **Unit**: GB tile encode/decode round-trip for several tiles (all indices, single pixel flips).
2. **Unit / integration**: `configureFromParsed...`-style path for **gb** produces `chrBanksBytes`; first tile decodes to expected pixels given a **fixture** (tiny synthesized ROM string: known 16-byte tile at offset 0).
3. **Optional smoke**: harness loads GB fixture and asserts a bank window exists and `setTilePixelGB` mutates the right bytes (if UI harness is cheap); otherwise manual QA checklist for PR.

### Explicitly later (not Step 1)

- Full **Export edited .gb** with MBC-correct persistence.
- DB layouts, nametable codecs, ROM palette windows.
- GBC **VRAM attribute** editing in CHR (usually not in the same 16-byte tile blob).

---

## Step 2 - Static + Animation windows (drag / drop)

**Goal:** After CHR banks work, **the same** static art and animation workflows accept drops using **GB** tile encoding when `platform` is gb/gbc.

- **Routing**: PNG / image import and tile allocation paths (`mouse_tile_drop_controller`, `png_import_controller`, sprite hydration) must call **platform-aware** decode/set, not NES-only `chr.decodeTile`.
- **Palette mapping**: NES brightness heuristics may not map cleanly to DMG's four indices - define a simple rule (e.g. luminance -> 0-3) or reuse project palette slots; *GBC RGB* can wait.
- **Tests**: drop builder in `test/e2e_visible` or unit tests on "import produces correct GB tile bytes in pool" without full UI if faster.

---

## Step 3 - ROM-backed windows (later)

**Goal:** Windows that interpret **absolute file offsets** (ROM tile view, palette bytes in cart, etc.) behave for GB: stable **offset <-> bank** story, optional MBC metadata, GBC-specific ROM regions if needed.

- Highest coupling to **per-game** layout and **MBC**; keep out of Step 1-2 to avoid blocking the CHR vertical.

---

## Proposed architecture direction (cross-cutting)

Introduce **`platform` / `romFormat`** and **branch or small strategy table** for: parse metadata, tile codec, CHR backing, save/export (when enabled), UI caps, optional `sha1 + platform` DB keys.

Avoid long-term `if gb` sprawl - prefer `require("platform.gb")` handlers or a single dispatch module.

---

## Deferred workstream checklist (after the trace)

Use this as a backlog once Steps 1-3 are moving:

- **Detection refinements**: size heuristics, header nibble for CGB flag (optional).
- **Project files**: persist `platform` in `.ppux` / `.lua` so reopen is deterministic.
- **Save / export**: `RomSave` branches - flat splice for GB; `_edited.gb`; IPS/BPS optional.
- **Game art DB**: new SHA entries; GB-specific layouts.
- **PNG / shaders**: GBC 15-bit preview, shader paths gated by platform.
- **UX copy**: "Parsing iNES..." -> neutral strings when GB loads.

---

## Risks and non-goals (be explicit early)

- **MBC**: Pseudo-banks show **file offsets**; what the game **maps** at runtime can differ - fine for art iteration, misleading if labeled "what the PPU sees" without Step 3.
- **GBC attrs in RAM**: Full in-game frame without a layout codec usually needs **VRAM dumps**, not ROM-only.
- **SHA-1 / DB**: Same ROM with different dump padding -> different hash; document for future GB `db/` entries.

---

## Rough effort signal (not a schedule)

- **Step 1**: moderate - router, GB `chr`, backing glue, bank UI guards, tests; NES mostly untouched.
- **Step 2**: moderate - import/drop/sprite pipeline audit + tests.
- **Step 3**: large - per-title offsets and MBC awareness, same long tail as NES ROM-backed tooling.

This matches the codebase: PPUX is a **ROM-layout-aware art tool** built on NES CHR and iNES; GB/GBC lands fastest by **proving CHR banks + GB tile bytes first**, then widening drop targets, then ROM-specialized windows.
