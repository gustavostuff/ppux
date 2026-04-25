# Critical Test Coverage Expansion Plan

NOTE: This is an AI-generated doc, a plan to improve unit and E2E testing coverage.

## Goals
- Close high-risk regressions in save/load integrity, project lifecycle, and user-entry workflows.
- Keep tests fast and stable by putting logic-heavy cases in unit tests and wiring/user-path cases in visual E2E.
- Align cross-platform suite behavior and testing docs.

## Priority 1: Data integrity and persistence (highest risk)

### 1) ROM save/export pipeline hardening
- **Why critical**: Corruption-risk area; logic spans nametable, sprite, palette, and final ROM write mode.
- **Files**: [controllers/rom/save_controller.lua](/home/g/Repos/ppux/controllers/rom/save_controller.lua), [test/tests/unit/](/home/g/Repos/ppux/test/tests/unit/)
- **Add tests (Unit)**:
  - Nametable write-back success/failure branches.
  - Sprite displacement application branch.
  - Palette write-back branch across multiple ROM palette windows.
  - Raw vs edited CHR write path in final save.
  - Ordering and short-circuit behavior on failure.
- **Add tests (E2E, minimal)**:
  - One golden save-and-reload smoke validating expected window/data survives roundtrip.

### 2) Project lifecycle/load path correctness
- **Why critical**: Entry-point stability for real users; recent project and path resolution regressions are high impact.
- **Files**: [controllers/rom/rom_project_controller.lua](/home/g/Repos/ppux/controllers/rom/rom_project_controller.lua), [test/tests/unit/](/home/g/Repos/ppux/test/tests/unit/)
- **Add tests (Unit)**:
  - `closeProject` full reset behavior.
  - `loadProjectFile` happy path merge/application.
  - Recent/adjacent project path resolution edge cases (`.lua`/`.ppux`).
  - `requestLoad` clean-state immediate load path.
- **Add tests (E2E)**:
  - Open Project modal happy path with fixture project; verify resulting loaded state.

## Priority 2: Critical user workflows currently under-visualized

### 3) Open Project + browser UX
- **Why critical**: Core workflow currently not strongly represented in visual E2E.
- **Files**: [test/e2e_visible/scenarios/](/home/g/Repos/ppux/test/e2e_visible/scenarios/) (`builders/`, `definitions.lua`, etc.)
- **Add tests (E2E)**:
  - Open from toolbar, navigate directories, open fixture project, assert loaded windows/status.
  - Invalid project selection path with explicit error and modal close behavior.
- **Unit companion**: Keep parser/validation branches in existing project-controller unit tests.

### 4) OAM/animated sprite flows
- **Why critical**: User-facing workflows exist but are only partially covered via fixture side effects.
- **Files**: [test/e2e_visible/scenarios/](/home/g/Repos/ppux/test/e2e_visible/scenarios/) (`builders/`, `definitions.lua`, etc.)
- **Add tests (E2E)**:
  - Dedicated OAM animation scenario: frame/layer navigation, play/pause, sprite add/remove smoke.
  - Animated sprite window creation + frame controls smoke.
- **Unit companion**: Keep frame/state mutation edge cases in input/controller unit tests.

## Priority 3: Settings-to-runtime wiring and grouped behaviors

### 5) Settings application and grouped palette runtime behavior
- **Why critical**: Large settings controller with many side effects; grouped palette behavior is easy to regress.
- **Files**: [controllers/app/core_controller_save_settings.lua](/home/g/Repos/ppux/controllers/app/core_controller_save_settings.lua), [test/tests/unit/](/home/g/Repos/ppux/test/tests/unit/)
- **Add tests (Unit)**:
  - `_apply*` setting methods for image mode/resizable/tooltips/grouped palettes.
  - Grouped palette cycle/focus hooks and window-created behavior.
  - `saveBeforeQuit` matrix (`hasProject`/`hasRom`).
- **Add tests (E2E)**:
  - Settings toggle flow proving grouped palette UX (single logical windows + toolbar cycling).

## Priority 4: Domain editing surfaces with incomplete direct coverage

### 6) CHR edit/revert logic
- **Why critical**: Pixel-level correctness and revert semantics can silently drift.
- **Files**: [controllers/chr/bank_canvas_controller.lua](/home/g/Repos/ppux/controllers/chr/bank_canvas_controller.lua), [controllers/chr/revert_tile_pixels_controller.lua](/home/g/Repos/ppux/controllers/chr/revert_tile_pixels_controller.lua)
- **Add tests (Unit)**:
  - Paint operations mutate expected tile/bank targets.
  - Revert eligibility checks and revert restoration behavior.
- **Add tests (E2E, optional smoke)**:
  - One brush+revert flow assertion in visual scenario (non-exhaustive).

### 7) Palette link decision logic and tooltip behavior
- **Why critical**: Complex target validation and UX feedback; currently mostly integration-touched.
- **Files**: [controllers/palette/palette_link_controller.lua](/home/g/Repos/ppux/controllers/palette/palette_link_controller.lua), [controllers/ui/tooltip_controller.lua](/home/g/Repos/ppux/controllers/ui/tooltip_controller.lua)
- **Add tests (Unit)**:
  - Link eligibility matrix by source/target layer type.
  - Link/remove/jump behavior invariants.
  - Tooltip show/hide when settings flip.
- **Add tests (E2E)**:
  - Keep current ROM palette interactions scenario; add one assertion pass for tooltip visibility ordering if needed.

## Priority 5: Suite reliability and parity cleanup

### 8) Cross-platform suite parity + doc drift
- **Why critical**: Missing scenario on one platform silently reduces protection.
- **Files**: [scripts/unix/run_e2e_tests.sh](/home/g/Repos/ppux/scripts/unix/run_e2e_tests.sh), [scripts/windows/run_e2e_tests.bat](/home/g/Repos/ppux/scripts/windows/run_e2e_tests.bat), [docs/test/E2E_TESTING.md](/home/g/Repos/ppux/docs/test/E2E_TESTING.md)
- **Add/adjust (Both)**:
  - Ensure Unix/Windows scenario lists match (notably ROM palette interaction coverage).
  - Update doc examples to canonical scenario IDs.

## Unit vs E2E decision rubric (apply to each new test)
- **Unit-first** when behavior is deterministic, branch-heavy, data-transform heavy, or needs exhaustive edge matrices.
- **E2E-first** when validating UI wiring, modal/taskbar/window focus interaction, drag/drop routing, or end-user flow across subsystems.
- **Both** for high-value critical paths where logic correctness and integration wiring can independently regress (save/load, grouped palette settings, core clipboard workflows).

## Execution order
1. Add Priority 1 unit tests, then minimal E2E save/load and open-project flow.
2. Add Priority 2 workflow scenarios (OAM/animated sprites).
3. Add Priority 3 settings/grouped palette unit + E2E.
4. Add Priority 4 domain-unit tests (CHR revert, palette link/tooltip).
5. Finish with Priority 5 parity/doc cleanup.
