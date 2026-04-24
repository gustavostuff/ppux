#!/usr/bin/env python3
"""One-off: split test/e2e_visible/scenarios.lua into scenarios/*.lua (run from repo root)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "test" / "e2e_visible" / "scenarios.lua"
OUT_DIR = ROOT / "test" / "e2e_visible" / "scenarios"
PRELUDE = '''-- Scenario builder implementations (split from former scenarios.lua).
-- Expects bindings from common.lua and helpers.lua (injected below).

local C = require("test.e2e_visible.scenarios.common")
local H = require("test.e2e_visible.scenarios.helpers")

local BubbleExample = C.BubbleExample
local PaletteLinkController = C.PaletteLinkController
local ContextualMenuController = C.ContextualMenuController
local images = C.images

local normalizeSpeedMultiplier = C.normalizeSpeedMultiplier
local pause = C.pause
local moveTo = C.moveTo
local mouseDown = C.mouseDown
local mouseUp = C.mouseUp
local keyPress = C.keyPress
local textInput = C.textInput
local call = C.call
local assertDelay = C.assertDelay
local appendClick = C.appendClick
local appendDrag = C.appendDrag

local newWindowOptionCenter = C.newWindowOptionCenter
local newWindowOptionCenterByText = C.newWindowOptionCenterByText
local newWindowModeToggleCenter = C.newWindowModeToggleCenter
local textFieldDemoFieldCenter = C.textFieldDemoFieldCenter
local textFieldDemoFieldTextPoint = C.textFieldDemoFieldTextPoint
local spriteItemCenter = C.spriteItemCenter
local toolbarLinkHandleCenter = C.toolbarLinkHandleCenter
local windowHeaderCenter = C.windowHeaderCenter
local saveOptionCenter = C.saveOptionCenter
local menuRowCenter = C.menuRowCenter
local taskbarRootMenu = C.taskbarRootMenu
local childMenuRowCenter = C.childMenuRowCenter
local rootMenuItemCenter = C.rootMenuItemCenter
local resizeHandleCenter = C.resizeHandleCenter
local taskbarMenuGapPoint = C.taskbarMenuGapPoint
local assertTaskbarChildState = C.assertTaskbarChildState

local buttonCenter = H.buttonCenter
local appQuickButtonCenter = H.appQuickButtonCenter
local ppuToolbarButtonCenter = H.ppuToolbarButtonCenter
local menuRowCenterByText = H.menuRowCenterByText
local setFocusedTextFieldValue = H.setFocusedTextFieldValue
local setupDeterministicPpuFixture = H.setupDeterministicPpuFixture
local harnessHoldShiftForGridResize = H.harnessHoldShiftForGridResize
local assertStatusContainsOccupiedLayout = H.assertStatusContainsOccupiedLayout

'''

ALIASES_BLOCK = """
local SCENARIO_ALIASES = {
  all_modals = "modals",
  tile_drag_demo = "boot_and_drag",
  animation_playback_demo = "animation_playback",
  grid_resize_toolbar_demo = "grid_resize_toolbar",
  tile_edit_roundtrip_demo = "tile_edit_roundtrip",
  brush_paint_lines = "brush_paint_tools",
  brush_paint_lines_demo = "brush_paint_tools",
  new_window_variants_demo = "new_window_variants",
  palette_shader_preview_demo = "palette_shader_preview",
  static_sprite_ops_demo = "static_sprite_ops",
  undo_redo_events_demo = "undo_redo_events",
  palette_edit_roundtrip_demo = "palette_edit_roundtrip",
  rom_palette_links_demo = "rom_palette_links",
  rom_palette_link_interactions_demo = "rom_palette_link_interactions",
  save_reload_persistence_demo = "save_reload_persistence",
  submenu_positions_demo = "submenu_positions",
  context_menus_and_submenus_demo = "context_menus_and_submenus",
  window_resize_and_hover_priority_demo = "window_resize_and_hover_priority",
  modal_navigation_keyboard_only_demo = "modal_navigation_keyboard_only",
  text_field_variants_demo = "text_field_variants",
  clipboard_matrix_demo = "clipboard_matrix",
  clipboard_intra_inter_paths_demo = "clipboard_intra_inter_paths",
  ppu_toolbar_ranges_setup_demo = "ppu_toolbar_ranges_setup",
  ppu_toolbar_pattern_ranges_demo = "ppu_toolbar_pattern_ranges",
  ppu_toolbar_sprite_and_mode_controls_demo = "ppu_toolbar_sprite_and_mode_controls",
}
"""

SCENARIOS_BLOCK = """
local SCENARIOS = {
  default_action_delay = {
    title = "Default Action Delay",
    build = buildDefaultActionDelayScenario,
  },
  modals = {
    title = "All Modals",
    build = buildAllModalsScenario,
  },
  boot_and_drag = {
    title = "Building pretty girl",
    build = buildTileDragScenario,
  },
  animation_playback = {
    title = "Animation Playback",
    build = buildAnimationPlaybackScenario,
  },
  grid_resize_toolbar = {
    title = "Grid resize (toolbar + blocked removes)",
    build = buildGridResizeToolbarScenario,
  },
  tile_edit_roundtrip = {
    title = "Tile Edit Roundtrip",
    build = buildTileEditRoundtripScenario,
  },
  brush_paint_tools = {
    title = "Brush Paint Tools",
    build = buildBrushPaintLinesScenario,
  },
  new_window_variants = {
    title = "New Window Variants",
    build = buildNewWindowVariantsScenario,
  },
  palette_shader_preview = {
    title = "Palette + Shader Preview",
    build = buildPaletteShaderPreviewScenario,
  },
  static_sprite_ops = {
    title = "Static Sprite Ops",
    build = buildStaticSpriteOpsScenario,
  },
  undo_redo_events = {
    title = "Undo Redo Events",
    build = buildUndoRedoEventsScenario,
  },
  palette_edit_roundtrip = {
    title = "Palette Edit Roundtrip",
    build = buildPaletteEditRoundtripScenario,
  },
  rom_palette_links = {
    title = "ROM Palette Links",
    build = buildRomPaletteLinkScenario,
  },
  rom_palette_link_interactions = {
    title = "ROM Palette Link Interactions",
    build = buildRomPaletteLinkInteractionsScenario,
  },
  save_reload_persistence = {
    title = "Save Reload Persistence",
    build = buildSaveReloadPersistenceScenario,
  },
  submenu_positions = {
    title = "Submenu Positions",
    build = buildSubmenuPositionScenario,
  },
  context_menus_and_submenus = {
    title = "Context Menus + Submenus",
    build = buildContextMenusAndSubmenusScenario,
  },
  window_resize_and_hover_priority = {
    title = "Window Resize + Hover Priority",
    build = buildWindowResizeAndHoverPriorityScenario,
  },
  modal_navigation_keyboard_only = {
    title = "Modal Navigation Keyboard Only",
    build = buildModalNavigationKeyboardOnlyScenario,
  },
  text_field_variants = {
    title = "Text Field Variants",
    build = buildTextFieldVariantsScenario,
  },
  clipboard_matrix = {
    title = "Clipboard Matrix",
    build = buildClipboardMatrixScenario,
  },
  clipboard_intra_inter_paths = {
    title = "Clipboard Intra/Inter Paths",
    build = buildClipboardIntraInterPathsScenario,
  },
  ppu_toolbar_ranges_setup = {
    title = "PPU Toolbar Ranges Setup",
    build = buildPpuToolbarRangesSetupScenario,
  },
  ppu_toolbar_pattern_ranges = {
    title = "PPU Toolbar Pattern Ranges",
    build = buildPpuToolbarPatternRangesScenario,
  },
  ppu_toolbar_sprite_and_mode_controls = {
    title = "PPU Toolbar Sprite + Mode Controls",
    build = buildPpuToolbarSpriteAndModeControlsScenario,
  },
}
"""


def main() -> None:
    text = SRC.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)

    # 1-based line numbers from grep: drop original requires (1-36), inline helpers (2628-2758), grid helpers (4199-4212)
    # Keep: 37-2627, 2759-4197, 4214-4574
    part_a = lines[36:2627]  # 37..2627
    part_b = lines[2758:4197]  # 2759..4197 (0-based end exclusive 4197 -> line 4197)
    part_c = lines[4213:4574]  # 4214..4574

    body = "".join(part_a + part_b + part_c)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    definitions_path = OUT_DIR / "definitions.lua"
    definitions_path.write_text(PRELUDE + body + "\n" + SCENARIOS_BLOCK + "\n" + ALIASES_BLOCK + "\nreturn {\n  scenarios = SCENARIOS,\n  aliases = SCENARIO_ALIASES,\n}\n", encoding="utf-8")

    init_path = OUT_DIR / "init.lua"
    init_path.write_text(
        '''-- Package entry for test.e2e_visible.scenarios (directory module).
return require("test.e2e_visible.scenarios.definitions")
''',
        encoding="utf-8",
    )

    # Remove legacy single-file shim if present (loader uses scenarios/init.lua).
    had_src = SRC.exists()
    if had_src:
        SRC.unlink()

    print("Wrote", definitions_path.relative_to(ROOT))
    print("Wrote", init_path.relative_to(ROOT))
    if had_src:
        print("Removed", SRC.relative_to(ROOT))


if __name__ == "__main__":
    main()
