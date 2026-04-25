#!/usr/bin/env python3
"""Split test/e2e_visible/scenarios/definitions.lua into builders/*.lua + thin definitions.lua."""
from pathlib import Path
from textwrap import dedent

ROOT = Path(__file__).resolve().parents[1]
DEF = ROOT / "test" / "e2e_visible" / "scenarios" / "definitions.lua"
OUT_BUILDERS = ROOT / "test" / "e2e_visible" / "scenarios" / "builders"

PRELUDE_REQ = 'local P = require("test.e2e_visible.scenarios.prelude")\n'

LOCALS = dedent(
    """\
local BubbleExample, PaletteLinkController, ContextualMenuController, images,
  normalizeSpeedMultiplier, pause, moveTo, mouseDown, mouseUp, keyPress, textInput, call, assertDelay, appendClick, appendDrag,
  newWindowOptionCenter, newWindowOptionCenterByText, newWindowModeToggleCenter,
  textFieldDemoFieldCenter, textFieldDemoFieldTextPoint, spriteItemCenter, toolbarLinkHandleCenter,
  windowHeaderCenter, saveOptionCenter, menuRowCenter, taskbarRootMenu, childMenuRowCenter,
  rootMenuItemCenter, resizeHandleCenter, taskbarMenuGapPoint, assertTaskbarChildState,
  buttonCenter, appQuickButtonCenter, ppuToolbarButtonCenter, menuRowCenterByText, setFocusedTextFieldValue,
  setupDeterministicPpuFixture, harnessHoldShiftForGridResize, assertStatusContainsOccupiedLayout
  = P.BubbleExample, P.PaletteLinkController, P.ContextualMenuController, P.images,
  P.normalizeSpeedMultiplier, P.pause, P.moveTo, P.mouseDown, P.mouseUp, P.keyPress, P.textInput, P.call, P.assertDelay, P.appendClick, P.appendDrag,
  P.newWindowOptionCenter, P.newWindowOptionCenterByText, P.newWindowModeToggleCenter,
  P.textFieldDemoFieldCenter, P.textFieldDemoFieldTextPoint, P.spriteItemCenter, P.toolbarLinkHandleCenter,
  P.windowHeaderCenter, P.saveOptionCenter, P.menuRowCenter, P.taskbarRootMenu, P.childMenuRowCenter,
  P.rootMenuItemCenter, P.resizeHandleCenter, P.taskbarMenuGapPoint, P.assertTaskbarChildState,
  P.buttonCenter, P.appQuickButtonCenter, P.ppuToolbarButtonCenter, P.menuRowCenterByText, P.setFocusedTextFieldValue,
  P.setupDeterministicPpuFixture, P.harnessHoldShiftForGridResize, P.assertStatusContainsOccupiedLayout

"""
)

HEADER = (
    "-- Scenario builder chunk (split from definitions.lua).\n"
    + PRELUDE_REQ
    + LOCALS
    + "\n"
)

# (filename, start_line, end_line inclusive) — 1-based, original definitions.lua
PARTS = [
    ("context_menus.lua", 50, 483),
    ("modals_tile.lua", 484, 864),
    ("brush_palette_static.lua", 865, 1331),
    ("undo_palette_rom.lua", 1332, 2396),
    ("save_modal_nav.lua", 2397, 2641),
    ("clipboard_matrix.lua", 2642, 3505),
    ("ppu_toolbar.lua", 3506, 3732),
    ("clipboard_paths.lua", 3733, 4079),
    ("grid_resize.lua", 4080, 4440),
]

RETURN_TAILS = {
    "context_menus.lua": """
return {
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
}
""",
    "modals_tile.lua": """
return {
  modals = { title = "All Modals", build = buildAllModalsScenario },
  text_field_variants = { title = "Text Field Variants", build = buildTextFieldVariantsScenario },
  boot_and_drag = { title = "Building pretty girl", build = buildTileDragScenario },
  animation_playback = { title = "Animation Playback", build = buildAnimationPlaybackScenario },
  tile_edit_roundtrip = { title = "Tile Edit Roundtrip", build = buildTileEditRoundtripScenario },
}
""",
    "brush_palette_static.lua": """
return {
  brush_paint_tools = { title = "Brush Paint Tools", build = buildBrushPaintLinesScenario },
  new_window_variants = { title = "New Window Variants", build = buildNewWindowVariantsScenario },
  palette_shader_preview = { title = "Palette + Shader Preview", build = buildPaletteShaderPreviewScenario },
  static_sprite_ops = { title = "Static Sprite Ops", build = buildStaticSpriteOpsScenario },
}
""",
    "undo_palette_rom.lua": """
return {
  undo_redo_events = { title = "Undo Redo Events", build = buildUndoRedoEventsScenario },
  palette_edit_roundtrip = { title = "Palette Edit Roundtrip", build = buildPaletteEditRoundtripScenario },
  rom_palette_links = { title = "ROM Palette Links", build = buildRomPaletteLinkScenario },
  rom_palette_link_interactions = {
    title = "ROM Palette Link Interactions",
    build = buildRomPaletteLinkInteractionsScenario,
  },
}
""",
    "save_modal_nav.lua": """
return {
  save_reload_persistence = { title = "Save Reload Persistence", build = buildSaveReloadPersistenceScenario },
  default_action_delay = { title = "Default Action Delay", build = buildDefaultActionDelayScenario },
  modal_navigation_keyboard_only = {
    title = "Modal Navigation Keyboard Only",
    build = buildModalNavigationKeyboardOnlyScenario,
  },
}
""",
    "clipboard_matrix.lua": """
return {
  clipboard_matrix = { title = "Clipboard Matrix", build = buildClipboardMatrixScenario },
}
""",
    "ppu_toolbar.lua": """
return {
  ppu_toolbar_ranges_setup = { title = "PPU Toolbar Ranges Setup", build = buildPpuToolbarRangesSetupScenario },
  ppu_toolbar_pattern_ranges = { title = "PPU Toolbar Pattern Ranges", build = buildPpuToolbarPatternRangesScenario },
  ppu_toolbar_sprite_and_mode_controls = {
    title = "PPU Toolbar Sprite + Mode Controls",
    build = buildPpuToolbarSpriteAndModeControlsScenario,
  },
}
""",
    "clipboard_paths.lua": """
return {
  clipboard_intra_inter_paths = {
    title = "Clipboard Intra/Inter Paths",
    build = buildClipboardIntraInterPathsScenario,
  },
}
""",
    "grid_resize.lua": """
return {
  grid_resize_toolbar = {
    title = "Grid resize (toolbar + blocked removes)",
    build = buildGridResizeToolbarScenario,
  },
}
""",
}


def main() -> None:
    lines = DEF.read_text(encoding="utf-8").splitlines(keepends=True)
    OUT_BUILDERS.mkdir(parents=True, exist_ok=True)

    merge_lines = []
    for fname, a, b in PARTS:
        chunk = "".join(lines[a - 1 : b])
        tail = dedent(RETURN_TAILS[fname]).lstrip("\n")
        mod = HEADER + chunk + "\n" + tail
        path = OUT_BUILDERS / fname
        path.write_text(mod, encoding="utf-8")
        base = fname.replace(".lua", "")
        merge_lines.append(
            f'merge(scenarios, require("test.e2e_visible.scenarios.builders.{base}"))'
        )

    thin = (
        "-- Merges scenario builder modules under builders/.\n"
        "local function merge(dst, src)\n"
        "  for k, v in pairs(src) do\n"
        "    dst[k] = v\n"
        "  end\n"
        "end\n\n"
        "local scenarios = {}\n"
        + "\n".join(merge_lines)
        + "\n\n"
        "return {\n"
        "  scenarios = scenarios,\n"
        '  aliases = require("test.e2e_visible.scenarios.scenario_aliases"),\n'
        "}\n"
    )

    DEF.write_text(thin, encoding="utf-8")
    print("Wrote builders/*.lua and thin definitions.lua")


if __name__ == "__main__":
    main()
