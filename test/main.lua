love.graphics.setBackgroundColor(0.1, 0.1, 0.1)
love.graphics.setLineStyle("rough")
love.graphics.setLineWidth(1)

-- Add parent directory to package path so we can require modules from project root
-- When running from test/ directory with `love .`, we need to add parent (root) to package.path
local function addParentToPath()
  -- Get the directory where this script is located (test/)
  local source = debug.getinfo(1, "S").source
  local parentDir = nil
  
  if source and source:match("@") then
    source = source:match("@(.+)")
    -- Get the full path to main.lua
    -- Example: /home/user/repos/nes-art-editor-v3/test/main.lua
    -- We want: /home/user/repos/nes-art-editor-v3/
    
    -- Get directory containing main.lua (test/)
    local testDir = source:match("^(.*/)[^/]+$") or ""
    -- Remove "test/" from end to get parent (root)
    parentDir = testDir:match("^(.*/)[^/]+/$")
  end
  
  if parentDir then
    -- Add project root to package path
    package.path = parentDir .. "?.lua;" .. parentDir .. "?/init.lua;" .. package.path
  else
    -- Fallback: try using ../ relative to test directory
    -- When running `love .` from test/, the working directory should be test/
    -- So we add parent as ../
    package.path = "../?.lua;../?/init.lua;" .. package.path
  end
end

addParentToPath()
_G.__PPUX_DISABLE_LOADING_SCREEN__ = true

-- In the test runtime, image assets may not be mounted the same way as the app runtime.
-- Ensure the icons namespace exists so modules using images.icons.* can be required safely.
do
  local ok, images = pcall(require, "images")
  if ok and type(images) == "table" then
    images.icons = images.icons or {}
    if not images.icons.icon_circle then
      images.icons.icon_circle = {
        getWidth = function() return 15 end,
        getHeight = function() return 15 end,
      }
    end
  end
end

-- Load test framework
-- When running from test/ directory, the framework is in the same directory
local TestFramework = require("test_framework")
TestFramework.setupGlobals()

-- Helper function to load test files (since require treats dots as path separators)
local function loadTestFile(filename)
  local filter = rawget(_G, "__PPUX_TEST_FILE_FILTER__")
  if filter and not filename:find(filter, 1, true) then
    return
  end

  local filepath = filename .. ".lua"
  local chunk, err = loadfile(filepath)
  if not chunk then
    error("Failed to load test file " .. filepath .. ": " .. (err or "unknown error"))
  end
  chunk()
end

local function parseTestFilter()
  if type(arg) ~= "table" then
    return nil
  end

  for i = 1, #arg do
    local value = arg[i]
    if value == "--" then
      return arg[i + 1]
    end
  end

  return nil
end

_G.__PPUX_TEST_FILE_FILTER__ = parseTestFilter()
local Text = require("utils.text_utils")

-- Load all test files
loadTestFile("tests/unit/chr.test")
loadTestFile("tests/unit/chr_bank_window_swap_persistence.test")
loadTestFile("tests/unit/table_utils.test")
loadTestFile("tests/unit/nametable_utils.test")
loadTestFile("tests/unit/shader_palette_controller.test")
loadTestFile("tests/unit/nametable_tiles_controller.test")
loadTestFile("tests/unit/nametable_unscramble_controller_undo.test")
loadTestFile("tests/unit/cursors_controller.test")
loadTestFile("tests/unit/debug_controller.test")
loadTestFile("tests/unit/window_capabilities.test")
  loadTestFile("tests/unit/window_grid_metrics.test")
  loadTestFile("tests/unit/window_grid_resize_controller.test")
loadTestFile("tests/unit/window_drag_bounds.test")
loadTestFile("tests/unit/window_space_highlight_controller.test")
loadTestFile("tests/unit/chr_selection_mode.test")
loadTestFile("tests/unit/revert_tile_pixels_controller.test")
loadTestFile("tests/unit/chr_group_drag_drop.test")
loadTestFile("tests/unit/chr_8x16_operations.test")
loadTestFile("tests/unit/taskbar_minimize.test")
loadTestFile("tests/unit/toast_controller.test")
loadTestFile("tests/unit/panel.test")
loadTestFile("tests/unit/contextual_menu_controller.test")
loadTestFile("tests/unit/app_core_controller_save_flow.test")
loadTestFile("tests/unit/app_core_controller_tooltips.test")
loadTestFile("tests/unit/app_core_controller_bank_label.test")
loadTestFile("tests/unit/app_core_controller_window_scale.test")
loadTestFile("tests/unit/app_core_controller_context_menu.test")
loadTestFile("tests/unit/app_top_toolbar_controller.test")
loadTestFile("tests/unit/settings_controller.test")
loadTestFile("tests/unit/undo_redo_controller.test")
loadTestFile("tests/unit/undo_redo_controller.test")
loadTestFile("tests/unit/brush_controller.test")
loadTestFile("tests/unit/animation_toolbar.test")
loadTestFile("tests/unit/toolbar_controller_palette_link_handle.test")
loadTestFile("tests/unit/grouped_palette_controller.test")
loadTestFile("tests/unit/palette_link_controller.test")
loadTestFile("tests/unit/toolbar_base_button_release.test")
loadTestFile("tests/unit/bank_view_controller_loading.test")
loadTestFile("tests/unit/tile_item_lazy_image.test")
loadTestFile("tests/unit/images_lazy_loading.test")
loadTestFile("tests/unit/text_field.test")
loadTestFile("tests/unit/new_window_modal.test")
loadTestFile("tests/unit/open_project_modal.test")
loadTestFile("tests/unit/open_project_modal_home.test")
loadTestFile("tests/unit/rename_window_modal.test")
loadTestFile("tests/unit/rom_palette_address_modal.test")
loadTestFile("tests/unit/save_options_modal.test")
loadTestFile("tests/unit/ppu_frame_sprite_layer_mode_modal.test")
loadTestFile("tests/unit/static_art_toolbar_sprite_mode.test")
loadTestFile("tests/unit/ppu_frame_toolbar_add_sprite_flow.test")
loadTestFile("tests/unit/chr_duplicate_sync.test")
loadTestFile("tests/unit/chr_backing_controller.test")
loadTestFile("tests/unit/chr_backing_integration.test")
loadTestFile("tests/e2e/e2e_visible_runner_speed.test")
loadTestFile("tests/e2e/ppu_frame_png_unscramble_flow.test")
loadTestFile("tests/unit/keyboard_input.test")
loadTestFile("tests/unit/keyboard_clipboard_controller_chr_virtual_handles.test")
loadTestFile("tests/unit/keyboard_clipboard_controller_toolbar_shared.test")
loadTestFile("tests/unit/keyboard_navigation_controller.test")
loadTestFile("tests/unit/keyboard_window_shortcuts_controller.test")
loadTestFile("tests/unit/keyboard_input_route_logging.test")
loadTestFile("tests/unit/keyboard_debug_controller.test")
loadTestFile("tests/unit/keyboard_art_actions_controller.test")
loadTestFile("tests/unit/sprite_controller_drag.test")
loadTestFile("tests/unit/sprite_controller_png_import_palette_mapping.test")
loadTestFile("tests/unit/image_import_controller_undo.test")
loadTestFile("tests/unit/png_palette_mapping_controller.test")
loadTestFile("tests/unit/window_controller_window_creation.test")
loadTestFile("tests/unit/window_controller_resize_handle.test")
loadTestFile("tests/unit/game_art_controller_static_sprite_persistence.test")
loadTestFile("tests/unit/game_art_controller_oam_animation_window.test")
loadTestFile("tests/unit/game_art_controller_rom_patches.test")
loadTestFile("tests/unit/game_art_rom_patch_controller_direct.test")
loadTestFile("tests/unit/game_art_layout_io_controller.test")
loadTestFile("tests/unit/game_art_edits_controller.test")
loadTestFile("tests/unit/game_art_window_builder_controller.test")
loadTestFile("tests/unit/game_art_db_lookup.test")
loadTestFile("tests/unit/rom_project_controller_png_drop_routing.test")
loadTestFile("tests/unit/rom_project_controller_project_drop.test")
loadTestFile("tests/unit/mouse_input_sprite_ctrl_click_selection.test")
loadTestFile("tests/unit/mouse_input_sprite_drop_restrictions.test")
loadTestFile("tests/unit/mouse_input_route_logging.test")
loadTestFile("tests/unit/mouse_extracted_controllers_smoke.test")
loadTestFile("tests/unit/mouse_window_chrome_controller.test")
loadTestFile("tests/unit/mouse_input_context_menu_release.test")
loadTestFile("tests/unit/mouse_overlay_controller.test")
loadTestFile("tests/unit/mouse_input_tile_drag_copy.test")
loadTestFile("tests/unit/mouse_input_ppu_tile_drag.test")
loadTestFile("tests/unit/multi_select_controller_ppu_drag.test")
loadTestFile("tests/unit/ppu_frame_window_sparse_draw.test")
loadTestFile("tests/unit/ppu_frame_window_pattern_layer_toggle.test")
loadTestFile("tests/unit/pattern_table_builder_window.test")
loadTestFile("tests/unit/palette_window.test")
loadTestFile("tests/unit/rom_palette_window.test")
loadTestFile("tests/unit/quit_confirm_modal.test")
loadTestFile("tests/unit/unsaved_state_tracking.test")

-- Font for rendering (monospace Proggy font at 16px)
local font = nil
local scrollY = 0
local lineHeight = 20
local padding = 20
local testsPerFrame = 1
local slowReportPrinted = false
local scrollbar = {
  width = 14,
  margin = 5,
  bottom = 10,
  minThumbHeight = 20,
  dragging = false,
  dragOffsetY = 0,
}

local function clampScroll(value, maxScroll)
  if value < 0 then value = 0 end
  if value > maxScroll then value = maxScroll end

  -- Keep scroll integer-aligned so pixel fonts render crisply.
  value = math.floor(value + 0.5)

  if value < 0 then value = 0 end
  if value > maxScroll then value = maxScroll end
  return value
end

--- Pixels from top for title + summary + optional "running" line (not scrolled).
local function getHeaderBottomY(state)
  local y = padding + lineHeight -- title
  y = y + lineHeight -- summary
  if state.isRunning and state.currentTask then
    y = y + lineHeight -- current test (single line)
  end
  return y
end

--- Height of the scrollable failures region (viewport).
local function getScrollViewportHeight(state)
  local screenH = love.graphics.getHeight()
  local headerBottom = getHeaderBottomY(state)
  local h = screenH - headerBottom - scrollbar.bottom
  if h < 1 then
    h = 1
  end
  return h, headerBottom
end

--- Total height of scrollable content: failure entries + optional footer line.
local function calculateScrollContentHeight(state)
  local y = 0
  if #(state.errors or {}) > 0 then
    y = y + lineHeight -- "Failures:"
    for _ in ipairs(state.errors) do
      y = y + lineHeight * 2
    end
  end
  if state.isComplete then
    y = y + lineHeight
  end
  return math.max(y, 1)
end

local function getScrollbarMetrics()
  local state = TestFramework.getState()
  local screenWidth = love.graphics.getWidth()
  local screenHeight = love.graphics.getHeight()
  local viewportH, headerBottom = getScrollViewportHeight(state)
  local totalHeight = calculateScrollContentHeight(state)
  local maxScroll = math.max(0, totalHeight - viewportH)

  local trackX = screenWidth - scrollbar.width - scrollbar.margin
  local trackY = headerBottom
  local trackH = viewportH
  if trackH < 1 then
    trackH = 1
  end

  local thumbHeight = trackH
  if totalHeight > 0 then
    thumbHeight = math.max(scrollbar.minThumbHeight, trackH * (viewportH / totalHeight))
  end
  if thumbHeight > trackH then
    thumbHeight = trackH
  end

  local scrollRatio = (maxScroll > 0) and (scrollY / maxScroll) or 0
  local thumbY = trackY + (trackH - thumbHeight) * scrollRatio

  return {
    state = state,
    screenHeight = screenHeight,
    headerBottom = headerBottom,
    viewportH = viewportH,
    totalHeight = totalHeight,
    maxScroll = maxScroll,
    trackX = trackX,
    trackY = trackY,
    trackH = trackH,
    thumbY = thumbY,
    thumbHeight = thumbHeight,
  }
end

local function setScrollFromThumb(topY, metrics)
  local travel = metrics.trackH - metrics.thumbHeight
  if travel <= 0 or metrics.maxScroll <= 0 then
    scrollY = 0
    return
  end

  local minY = metrics.trackY
  local maxY = metrics.trackY + travel
  local clampedTop = topY
  if clampedTop < minY then clampedTop = minY end
  if clampedTop > maxY then clampedTop = maxY end

  local ratio = (clampedTop - metrics.trackY) / travel
  scrollY = clampScroll(ratio * metrics.maxScroll, metrics.maxScroll)
end

local function printSlowestTestsReport(limit)
  local slowest = TestFramework.getSlowestTests(limit or 10)
  print("")
  print(string.rep("=", 72))
  print(string.format("Top %d slowest tests", #slowest))
  print(string.rep("=", 72))
  if #slowest == 0 then
    print("(no completed tests)")
    return
  end

  for i, entry in ipairs(slowest) do
    local status = entry.passed and "OK" or "X"
    print(string.format(
      "%2d. %8.3f ms  [%s]  %s > %s",
      i,
      tonumber(entry.durationMs) or 0,
      status,
      tostring(entry.suite or "(unknown suite)"),
      tostring(entry.test or "(unknown test)")
    ))
  end
end

-- All tests are now in separate .test.lua files
-- Love2D callbacks below

function love.load()
  -- Load Proggy Clean SZ monospace font at 16px (default for test framework)
  local fontPath = "proggy-clean-sz.ttf"
  
  -- Try loading the custom monospace font at size 16
  local success, loadedFont = pcall(love.graphics.newFont, fontPath, 16)
  
  if success and loadedFont then
    font = loadedFont
  else
    -- Fallback to default font if custom font can't be loaded
    font = love.graphics.newFont(16)
    print("Warning: Could not load proggy-clean-sz.ttf, using default font")
    print("Note: Default font may have alignment issues as it's not monospace")
  end
  
  -- Set as default font for the whole test framework
  love.graphics.setFont(font)
  
  -- Start tests and execute them progressively so the UI can render live updates.
  TestFramework.startRun()
  slowReportPrinted = false
end

function love.update(dt)
  TestFramework.updateRun(testsPerFrame)

  local state = TestFramework.getState()
  local m = getScrollbarMetrics()
  if state.isRunning then
    scrollY = clampScroll(m.maxScroll, m.maxScroll)
  else
    scrollY = clampScroll(scrollY, m.maxScroll)
  end
  if state.isComplete and not slowReportPrinted then
    printSlowestTestsReport(10)
    slowReportPrinted = true
  end
end

function love.wheelmoved(x, y)
  scrollY = scrollY - y * 30
  local m = getScrollbarMetrics()
  scrollY = clampScroll(scrollY, m.maxScroll)
end

function love.mousepressed(x, y, button)
  if button ~= 1 then return end

  local metrics = getScrollbarMetrics()
  if metrics.maxScroll <= 0 then return end

  local inTrack = x >= metrics.trackX and x <= (metrics.trackX + scrollbar.width)
    and y >= metrics.trackY and y <= (metrics.trackY + metrics.trackH)
  if not inTrack then return end

  local inThumb = y >= metrics.thumbY and y <= (metrics.thumbY + metrics.thumbHeight)
  scrollbar.dragging = true
  if inThumb then
    scrollbar.dragOffsetY = y - metrics.thumbY
  else
    scrollbar.dragOffsetY = metrics.thumbHeight * 0.5
    setScrollFromThumb(y - scrollbar.dragOffsetY, metrics)
  end
end

function love.mousemoved(x, y, dx, dy)
  if not scrollbar.dragging then return end

  local metrics = getScrollbarMetrics()
  setScrollFromThumb(y - scrollbar.dragOffsetY, metrics)
end

function love.mousereleased(x, y, button)
  if button == 1 then
    scrollbar.dragging = false
  end
end

-- Draw scrollbar for the failures viewport (only when content overflows).
local function drawScrollIndicators()
  local metrics = getScrollbarMetrics()
  if metrics.maxScroll <= 0 then
    return
  end

  love.graphics.setFont(font)

  love.graphics.setColor(0.3, 0.3, 0.3, 0.55)
  love.graphics.rectangle("fill", metrics.trackX, metrics.trackY, scrollbar.width, metrics.trackH)

  love.graphics.setColor(0.6, 0.6, 0.6, 0.85)
  love.graphics.rectangle("fill", metrics.trackX, metrics.thumbY, scrollbar.width, metrics.thumbHeight)

  love.graphics.setColor(0.4, 0.4, 0.4, 0.9)
  love.graphics.rectangle("line", metrics.trackX, metrics.thumbY, scrollbar.width, metrics.thumbHeight)
  love.graphics.rectangle("line", metrics.trackX, metrics.trackY, scrollbar.width, metrics.trackH)
end

function love.draw()
  local state = TestFramework.getState()
  local screenW = love.graphics.getWidth()
  local screenH = love.graphics.getHeight()
  local metrics = getScrollbarMetrics()
  local headerBottom = metrics.headerBottom
  local viewportH = metrics.viewportH

  love.graphics.setColor(0.1, 0.1, 0.1)
  love.graphics.rectangle("fill", 0, 0, screenW, screenH)

  love.graphics.setFont(font)

  local passedColor = { 0.2, 0.8, 0.2 }
  local failedColor = { 0.8, 0.2, 0.2 }
  local runningColor = { 1.0, 0.85, 0.35 }

  -- Fixed header: title, summary, current test (not scrolled).
  local y = padding

  if state.isComplete then
    Text.print("Test run complete", padding, y, { color = { 0.6, 0.8, 1.0, 1 } })
  else
    Text.print("Running tests...", padding, y, { color = { 0.6, 0.8, 1.0, 1 } })
  end
  y = y + lineHeight

  local completedTests = state.passedTests + state.failedTests
  local summary = string.format(
    "Tests: %d passed, %d failed, %d/%d complete",
    state.passedTests,
    state.failedTests,
    completedTests,
    state.totalTests
  )

  local prefix1 = "Tests: "
  local prefix2 = string.format("Tests: %d passed, ", state.passedTests)
  local passedNumX = padding + font:getWidth(prefix1)
  local failedNumX = padding + font:getWidth(prefix2)

  Text.print(summary, padding, y, { color = { 1.0, 1.0, 1.0, 1 } })

  if state.passedTests > 0 then
    Text.print(tostring(state.passedTests), passedNumX, y, { color = { passedColor[1], passedColor[2], passedColor[3], 1 } })
  end
  if state.failedTests > 0 then
    Text.print(tostring(state.failedTests), failedNumX, y, { color = { failedColor[1], failedColor[2], failedColor[3], 1 } })
  end
  y = y + lineHeight

  if state.isRunning and state.currentTask then
    Text.print(
      string.format(
        "Running: %s > %s",
        state.currentTask.suitePath,
        state.currentTask.test.name
      ),
      padding,
      y,
      { color = { runningColor[1], runningColor[2], runningColor[3], 1 } }
    )
  end

  -- Failures (+ footer) scroll inside the viewport below the header.
  love.graphics.setScissor(0, headerBottom, screenW, viewportH)
  love.graphics.push()
  love.graphics.translate(0, headerBottom - scrollY)

  y = 0
  if #(state.errors or {}) > 0 then
    Text.print("Failures:", padding, y, { color = { failedColor[1], failedColor[2], failedColor[3], 1 } })
    y = y + lineHeight

    for _, err in ipairs(state.errors) do
      Text.print(string.format("  %s > %s", err.suite, err.test), padding, y, { color = { 0.8, 0.4, 0.4, 1 } })
      y = y + lineHeight
      Text.print("    " .. tostring(err.error), padding, y, { color = { 0.6, 0.6, 0.6, 1 } })
      y = y + lineHeight
    end
  end

  if state.isComplete then
    if state.failedTests == 0 then
      Text.print("All tests passed!", padding, y, { color = { passedColor[1], passedColor[2], passedColor[3], 1 } })
    else
      Text.print("Some tests failed.", padding, y, { color = { failedColor[1], failedColor[2], failedColor[3], 1 } })
    end
  end

  love.graphics.pop()
  love.graphics.setScissor()

  if state.isComplete or state.isRunning then
    drawScrollIndicators()
  end
end

function love.keypressed(key, scancode, isrepeat)
  if key == "escape" then
    love.event.quit()
  end
end
