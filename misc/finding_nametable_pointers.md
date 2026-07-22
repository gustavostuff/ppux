Note: this doc is AI-generated, and has been manually verified

# Finding nametable stream pointers (FCEUX)

Goal: locate the **2-byte little-endian pointer in ROM** that tells the game where a compressed nametable stream starts (the bytes you later overwrite in `romPatches`).

You already know the **file** offset of the stream from PPUX / a hex editor (e.g. `0x01255B`). This guide is for finding **where the game stores the pointer to that data**.

ROM file offsets: **6 hex digits**. CPU/PPU addresses: **4 hex digits**.

---

## Short answer to your idea

Yes. In FCEUX you can break when a specific tile index is written to a specific nametable cell:

1. Convert (col, row) → PPU address.
2. Add a **PPU Write** breakpoint on that address.
3. Condition on the tile value — typically `A == #A0` when the upload does `STA …` with the tile in the accumulator (what you’ll see in the Breakpoints list as Cond).

When it hits, you are inside (or just after) the upload/decode routine. From there you trace **back** to the code that loaded the stream pointer — that load site (or a table it indexes) is what you patch.

---

## 1. PPU address from grid position

Nametable 0, 32×30 tiles (Contra title/cutscene style):

```
ppu = $2000 + (row * 32) + col
```

Examples (0-based col/row):

| Cell | PPU address |
|---|---|
| (0, 0) | `$2000` |
| (8, 10) | `$2000 + 320 + 8` = `$2148` |
| (16, 10) | `$2150` |
| (31, 29) | `$23BF` |

Attributes live in `$23C0`–`$23FF` (not tile indices). Don’t use those for “tile `$A0`” breaks.

If the screen uses another nametable base (`$2400` / `$2800` / `$2C00`), use that base instead of `$2000`. Name Table Viewer in FCEUX shows which NT is on screen.

---

## 2. Breakpoint setup (FCEUX Debugger)

**Debug → Debugger → Breakpoints → Add** (dialog fields match the UI):

| Dialog control | Value |
|---|---|
| Address (left box) | e.g. `$2148` — leave the right box empty for a single address |
| **Write** | checked |
| **Read** / **Execute** | unchecked |
| **Enable** | checked |
| Memory | **PPU** (not CPU / OAM / ROM) |
| Condition | `A == #A0` |
| Name | optional label |

In the Breakpoints list this shows as Addr `$2148`, Flags like `-P-W--` (PPU + Write), Cond `(A == #A0)`.

Why `A == #A0` (not `W`): nametable uploads usually put the tile in **A** and `STA` to PPUDATA / a buffer. Conditioning on the accumulator matches that path and is what FCEUX shows when you pause (register pane: A = the tile).

Alternative: `W == #A0` breaks on the byte being written regardless of which register held it — use if the store isn’t via A.

Notes:

- Condition numbers are hex: `#A0` = immediate, `$2148` = address.
- After OK, **Edit** the breakpoint once — if the condition was invalid, FCEUX clears it.
- Prefer a **unique** tile for that screen. Common sky/blank tiles will fire constantly.
- When paused, the status line reads like “Emulator Stopped / Paused at Breakpoint: N”. The disassembly footer also shows **CPU Address** (`bank:addr`) and **File Offset** (`0x……`, 6 hex digits).

**Without a value condition:** PPU Write on `$2148` alone also works; you’ll stop on every write to that cell (clear, RLE fill, final tile). Check A / step until the tile is `$A0`.

---

## 3. From the hit → stream pointer

When execution breaks:

1. Note **PC** (and File Offset under the disassembly) — often a store loop near PPU upload.
2. Walk **up the call stack** (or scroll up in the disassembly) to the caller that started “upload this screen.”
3. Look for a load of a 16-bit address used as the **read cursor** into the compressed stream, e.g.:
   - `LDA $xxxx` / `LDA $xxxx+1` (pointer in RAM)
   - `LDA table,X` / `LDA table+1,X` (pointer table in ROM)
   - Immediate `LDA #$4B` / `LDA #$A5` then `STA` into a ZP pointer
4. That ROM location holding `lo` then `hi` (or the table entry you indexed) is the **pointer site** for `romPatches`.

If the decoder keeps the stream pointer in zero-page (common):

1. When broken on the PPU write, check ZP slots that look like a CPU address in `$8000`–`$BFFF`.
2. Set a **CPU Write** breakpoint on that ZP pointer (when it was *initialized*).
3. Replay the screen load; the write that sets ZP to e.g. `$A54B` is near the pointer source — or the value was copied from the ROM pointer bytes.

**File offset ↔ CPU (same bank @ `$8000`):**

```
cpu = ((file_offset - 0x10) % 0x4000) + 0x8000
```

Example: stream at file `0x01255B` → CPU `$A54B` → ROM bytes `4B A5`.

---

## 4. Faster path when you already know the stream offset

If PPUX / hex editor already gave you the compressed range start:

1. Compute original CPU pointer (`0x01255B` → `$A54B` → `4B A5`).
2. In FCEUX Hex Editor (or any ROM search): find **`4B A5`** in PRG.
3. Confirm it’s the real pointer (not coincidence):
   - Change those two bytes temporarily, reload the screen → layout breaks / wrong data.
   - Or set a **CPU Read** breakpoint on that ROM CPU address while the screen loads.

This often beats PPU tile hunting once the stream location is known.

---

## 5. Caveats (Konami / Contra-style streams)

- Uploads may use **RLE**: many tiles written from one register value. `A == #A0` still works; you may break mid-run.
- The first write to a cell might be a clear (`$00` / `$20` fill) before the real tile — value condition avoids that.
- Decoder may set PPUADDR with `00 20 …` style commands; your break is on the **nametable byte write**, not on reading the compressed opcode.
- Pointer tables may be **indexed** (screen ID → pointer). Patch the entry for that screen, not a shared routine immediate.
- `relocateTo` must stay in the **same 16KB PRG bank**; the pointer does not bankswitch.

---

## 6. Checklist → `romPatches`

1. Stream file start known (e.g. `0x01255B`).
2. Original pointer bytes known (`4B A5`) and **ROM address of those two bytes** found (e.g. `0x01C9D1`).
3. Pick free `relocateTo` (same bank), compute new `lo`/`hi`.
4. PPUX: layer `relocateTo = …` + `romPatches` at the pointer site with new `lo`, `hi`.

Related: `misc/nametable_relocation_workflow.md` (full relocate checklist), `misc/nametable_relocation.md` (math), `misc/relocation_pointer_calculator.md` (new pointer values), `misc/nametable_breakpoint_calculator.md` (PPU break address UI).
