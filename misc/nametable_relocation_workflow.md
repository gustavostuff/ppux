Note: this doc is AI-generated, and has been manually verified

# Nametable relocation workflow

How to move a compressed nametable stream so it can grow, and patch the game pointer that points at it.

Works with the top-toolbar **Relocation Pointer Calculator** (**R**).

The Nametable Breakpoint Calculator (**B**) stays in the codebase for cases where you do not know the stream start yet, but its toolbar button is off by default (hex search is enough for the usual relocate path). See `misc/nametable_breakpoint_calculator.md`.

| Tool | Toolbar mark | Job |
|---|---|---|
| Relocation Pointer Calculator | **R** | File offset → pointer **values** (`lo hi`) |
| Nametable Breakpoint Calculator | **B** (toolbar hidden) | Col/row → FCEUX breakpoint (only if you do not know the stream start yet) |

---

## What you need

1. **Stream start** in the ROM file (from PPUX: layer `nametableStartAddr`), e.g. cutscene 2 Bella: `0x01255B`.
2. A free **`relocateTo`** destination in the **same 16KB PRG bank** as the original stream.
3. The **pointer site** in ROM (where the game stores `lo` then `hi`) — found by search, not by a formula.

ROM file offsets: always **6 hex digits** (e.g. `0x01255B`).

---

## Steps (when you already know the stream start)

### 1. Get the **original** pointer values

1. Open **Relocation Pointer Calculator**.
2. Enter the current stream start (`nametableStartAddr`), e.g. `0x01255B`.
3. Leave defaults for Contra-style mapping (Header `0x10`, Bank `0x4000`, CPU `$8000`) unless you know otherwise.
4. Calculate → copy **both** bytes (example for `0x01255B`: **`4B A5`**).

Those are the bytes currently stored in ROM as the stream pointer.

### 2. Find **where** those bytes live

1. In FCEUX Hex Editor (or any ROM hex search), search for that pair: `4B A5` (lo then hi).
2. Note the **file offset** of the hit (6 hex digits).
3. Confirm it is the real pointer (not a coincidence):
   - Temporarily change those two bytes, reload the screen → layout should break or show wrong data.
   - Or put them back and continue.

That file offset is your **`romPatches` address** (often two consecutive bytes).

### 3. Pick `relocateTo` and get **new** pointer values

1. Choose a free destination in the **same bank** (enough room for the stream to grow).
2. In Relocation Pointer Calculator, enter that `relocateTo` offset (e.g. `0x013300`).
3. Calculate → new `lo hi` (example: **`F0 B2`**).

### 4. Apply in PPUX

1. On the PPU Frame nametable layer: set **`relocateTo`** to the destination you chose.
2. Add **`romPatches`** at the pointer site from step 2, with the **new** bytes from step 3 (lo, then hi).
3. Save / export and test the screen in emulator.

You do **not** need the breakpoint calculator for this path.

---

## Example: Cutscene 2, frame 1 - Bella

| Piece | Value |
|---|---|
| Stream start (`nametableStartAddr`) | `0x01255B` |
| Original CPU pointer | `$A54B` |
| Original ROM bytes (search for these) | `4B A5` |
| Then | Find file offset of `4B A5` → confirm |
| Then | Choose `relocateTo` → calculator → new `lo hi` |
| Then | Layer `relocateTo` + `romPatches` with new bytes |

Cutscene 1 (already done in the Bikini project) used the same pattern: start `0x012493` → `83 A4` → site `0x01C9D1`, then new bytes `F0 B2` for `relocateTo = 0x013300`.

---

## If you do **not** know the stream start

Use **Nametable Breakpoint Calculator** (col/row + tile) to set a FCEUX PPU Write break, then trace or use other means to learn the stream range. After you have `nametableStartAddr`, come back to the steps above.

Full debugger notes: `misc/finding_nametable_pointers.md`.

---

## Checklist

1. [ ] Original start offset known
2. [ ] Calculator → original `lo hi`
3. [ ] Hex search found and confirmed pointer site
4. [ ] `relocateTo` chosen (same bank, enough space)
5. [ ] Calculator → new `lo hi`
6. [ ] PPUX: `relocateTo` + `romPatches` (new bytes at pointer site)
7. [ ] Test in emulator

---

## Related

- `misc/relocation_pointer_calculator.md` — value calculator UI
- `misc/nametable_breakpoint_calculator.md` — breakpoint address UI
- `misc/finding_nametable_pointers.md` — FCEUX details
