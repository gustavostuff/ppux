Note: this doc is AI-generated, and has been manually verified

# Relocation Pointer Calculator — design

Modal tool (not a project window) that turns a ROM **file** offset into the 2-byte little-endian CPU pointer used in `romPatches` when pairing with `relocateTo`.

Opened from the **app top toolbar** (**R** calculator). Ephemeral — never saved into projects.

Math:

```
cpu = ((rom_offset - header) % bankSize) + cpuBase
lo  = cpu & 0xFF
hi  = (cpu >> 8) & 0xFF
```

Defaults (Contra-style): header `0x10`, bank `0x4000`, CPU base `$8000`. Mapping knobs are dropdowns on the modal.

Does **not** write ROM, set `relocateTo`, or invent the patch address. Finding the original pointer site stays a separate step — see the full checklist in `misc/nametable_relocation_workflow.md` (and `misc/finding_nametable_pointers.md`).

---

## Role in the app

| Piece | Who owns it |
|---|---|
| Source nametable range | PPU Frame layer (`nametableStartAddr` / `End`) |
| Write destination | PPU Frame layer (`relocateTo`) |
| New pointer bytes | **This calculator modal** |
| Patch site in ROM | User finds (FCEUX / hex search) → `romPatches` |

---

## Address display convention

**ROM file offsets**: always **6 hex digits** (FCEUX-style), e.g. `0x013300`. Pad on Calculate (`13300` → `0x013300`).

---

## Inputs / outputs

**Input:** ROM file offset (`relocateTo`) — accept `013300`, `0x013300`, `$013300`.

**Mapping dropdowns** (session-persistent on the modal instance):

| Control | Options | Default |
|---|---|---|
| Header size | `0x10`, `0x00` | `0x10` |
| Bank size | `0x2000`, `0x4000`, `0x8000` | `0x4000` |
| CPU map base | `$8000`, `$A000`, `$C000` | `$8000` |

**Outputs:** Pointer bytes `lo` / `hi` (`F0`, `B2`).

**Actions:** Calculate (Enter), Clear, Copy lo / hi / both. Escape closes an open dropdown first, then the modal. Click outside closes.

Footer formula updates from the three dropdowns.

---

## UI mockup

```
┌─ Relocation Pointer Calculator ──────────────────┐
│  Converts relocateTo offset to lo/hi for romPatches.│
│                                                    │
│  ROM file offset (relocateTo)                      │
│  ┌──────────────────────────────────────────────┐  │
│  │ 0x013300                                     │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  Header size:   [ 0x10 ▾ ]                         │
│  Bank size:     [ 0x4000 ▾ ]                       │
│  CPU map base:  [ $8000 ▾ ]                        │
│                                                    │
│  [ Calculate ]              [ Clear ]              │
│                                                    │
│  Pointer bytes    F0  B2  (lo, hi)                 │
│                                                    │
│  [ Copy lo ]  [ Copy hi ]  [ Copy both ]           │
│                                                    │
│  cpu = ((offset - 0x10) % 0x4000) + 0x8000         │
│  Patch order: lo, then hi. Same PRG bank required. │
└────────────────────────────────────────────────────┘
```

---

## Implementation

1. `utils/relocation_pointer_math.lua` — parse + formula (+ optional mapping opts)
2. `user_interface/modals/relocation_pointer_calculator_modal.lua` — Panel + TextField + Dropdowns + Buttons
3. App top toolbar button → `AppCoreController:showRelocationPointerCalculatorModal()`
4. Modal registered in `APP_MODAL_KEYS_IN_ORDER` + textinput routes + draw
