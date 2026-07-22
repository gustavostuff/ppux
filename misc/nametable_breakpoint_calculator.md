Note: this doc is AI-generated, and has been manually verified

# Nametable Breakpoint Calculator — design

Modal helper for the FCEUX **PPU write breakpoint** path used to find where stream **pointer bytes live in ROM** (not the pointer values — that is the Relocation Pointer Calculator).

Opened from the **app top toolbar** (**B** calculator) when enabled; toolbar entry is off by default. Ephemeral. Modal code remains wired.

Math (nametable 0 style, 32×30 tiles):

```
ppu = ntBase + (row * 32) + col
```

Default `ntBase` = `$2000`. Also `$2400` / `$2800` / `$2C00`.

---

## Inputs / outputs

| Input | Notes |
|---|---|
| Col | 0–31 |
| Row | 0–29 |
| Tile index | Hex byte for the condition (prefer a unique tile) |
| NT base | Dropdown |

| Output | Example |
|---|---|
| PPU address | `$2148` |
| Condition | `A == #A0` |

Copy buttons for address and condition. Footer steps summarize FCEUX Add Breakpoint setup; full guide: `misc/finding_nametable_pointers.md`.

---

## Implementation

1. `utils/nametable_breakpoint_math.lua`
2. `user_interface/modals/nametable_breakpoint_calculator_modal.lua`
3. Toolbar → `showNametableBreakpointCalculatorModal()`
