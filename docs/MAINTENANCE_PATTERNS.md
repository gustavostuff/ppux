# Maintenance patterns & smells (short audit)

**Status:** `APP_MODAL_KEYS_IN_ORDER`, `modalVisible`, `anyModalVisible`, and context-menu key lists live in `controllers/app/core_controller_shared.lua`. `core_controller_input.lua` loops those lists for keyboard/mouse/textinput routing; `core_controller_draw.lua` draws overlay context menus via `APP_OVERLAY_CONTEXT_MENU_KEYS`. The unused duplicate `anyModalVisible` in `core_controller_lifecycle.lua` was removed.

Short catalog of recurring patterns that are hard to extend safely, plus practical directions (not a refactor mandate).

---

## 1. Long chains of “if modal visible → dispatch”

**Where it shows up**

- `controllers/app/core_controller_input.lua` — keyboard: repeated `modalVisible(self.*)` + `modalHandleKey(...)` (e.g. ~199–260); same modal set again as a big `or` for “block other input” (~306–320); mouse pressed/moved/released repeat nearly the same list with `:isVisible()` (~336–644); wheel handler groups modals again (~687–700).
- `controllers/app/core_controller_shared.lua` — `anyModalVisible(app)` is the same membership expressed as one long `or` chain (~76–91).
- `controllers/app/core_controller_lifecycle.lua` — local `anyModalVisible` duplicates the same idea (~268–282).

**Why it’s a problem**

- Adding or removing a modal requires touching many sites; order matters for keyboard focus.
- The same logical set is re-encoded with **three** different guard styles: `modalVisible(...)` (nil-safe), `modal and modal:isVisible()`, and bare `self.fooModal:isVisible()` — easy to get inconsistent behavior if one path forgets a nil check or a new modal.

**Possible directions**

- **Single ordered registry**: e.g. `app._modalStack` or `app._modalsInKeyOrder = { "quitConfirmModal", ... }` built at init; helpers `forEachModal(app, fn)` and `firstVisibleModal(app)` for key routing. Optional modals (e.g. `openReferencePngModal`) stay in the list with `optional = true` or a separate small list merged at runtime.
- **Reuse one visibility predicate**: implement `anyModalVisible` once (shared module) and use it everywhere; keyboard handler becomes “find first visible in order, then dispatch” instead of N separate `if` blocks.
- **Event-style modals**: if modals share a small interface (`handleKey`, `isVisible`), a loop is enough; special cases (e.g. `refreshCursor`) become hooks on the modal or a thin wrapper type.

---

## 2. Redundant / doubled guards on objects the app always owns

**Example**

- `controllers/app/core_controller_draw.lua` — context menus: `app.paletteLinkContextMenu and app.paletteLinkContextMenu.isVisible and app.paletteLinkContextMenu:isVisible()` then optional `if ... .update then ...:update()` (~1568–1590; same shape for other menus). `AppCoreController` constructs these in `core_controller.lua`, so they are normally non-nil; `isVisible` as both a field check and a method call is especially noisy.

**Why it’s a problem**

- Hides the real contract (what must a menu implement?) and makes call sites longer than needed.
- The same menus are already iterated more cleanly in `core_controller_input.lua` via `eachAppContextMenu` + `drawHardShadowMasksForOpenContextMenus` (list-driven).

**Possible directions**

- **One helper**: `drawContextMenuIfVisible(menu)` that assumes `menu` exists in production, only checks `:isVisible()`, calls `update` if present (or make `update` a no-op on the controller class).
- **Unify draw with the same table** as input/shadows: single `app._contextMenus` array, `for _, m in ipairs(...) do drawIfVisible(m) end` — removes four copy-paste blocks.

---

## 3. List drift between duplicated “any modal open” implementations

**Concrete case**

- `core_controller_shared.lua` `anyModalVisible` includes `ppuFramePatternRangeModal` (~90).
- `core_controller_lifecycle.lua`’s local `anyModalVisible` does **not** include that modal (~268–282) — same pattern, different membership.

**Why it’s a problem**

- Subtle bugs (e.g. lifecycle thinks no modal is open when that one is) with no compile-time warning.

**Possible directions**

- **Delete the duplicate**; require lifecycle (and any other file) to call `Shared.anyModalVisible(app)` only.
- If a file truly needs a different definition, name it explicitly (e.g. `anyModalVisibleForQuitFlow`) and document why the set differs.

---

## 4. Duck checks on `love.*` and optional subsystems

**Where**

- Widespread: `if love and love.timer and love.timer.getTime then` (e.g. animation code, ROM controller), `love.filesystem`, `love.system.openURL`, etc.

**Assessment**

- Often **justified** for headless tests, minimal boot, or platform gaps. This is less “smell” than **documented contract**: “these modules may run without full LÖVE.”

**Possible direction**

- Tiny `love_compat.lua` (or extend an existing util) with `getTime()`, `openURL`, etc. that return safe defaults or no-ops, so call sites don’t repeat the chain.

---

## 5. Optional capabilities on `ctx` / `app` across controllers

**Where**

- e.g. `mouse_tile_drop_controller.lua` `ctx.app.setStatus`, `palette_toolbar.lua` `invalidatePpuFrameLayersAffectedByPaletteWin` guarded with `if self.ctx and self.ctx.app and ... then`.

**Assessment**

- Reasonable when the same controller is used in multiple harnesses (unit test vs full app). The smell is **inconsistency**: some paths assume full `app`, others guard every step.

**Possible direction**

- Narrow interface: `ctx.appUi` with required methods for toolbar code paths, or assert full app in production entrypoints and pass a test double in tests (fewer `if` chains in hot paths).

---

## Summary

| Pattern | Main risk | Lean fix |
|--------|-----------|----------|
| Repeated modal lists | Miss a site when adding/removing modals | Ordered registry + one visibility/dispatch loop |
| `menu and menu.isVisible and menu:isVisible()` on fixed app fields | Noise; unclear API | Shared menu list + one `drawIfVisible` / assume constructor invariants |
| Duplicated `anyModalVisible` | Drift (already seen) | Single implementation in shared |
| `love and love.*` | Repetition | Central compat shims |
| Deep `ctx.app.*` guards | Inconsistent assumptions | Explicit small facades or test doubles |

When touching any of these areas, prefer consolidating **data** (lists, registries) over growing another `if` ladder.
