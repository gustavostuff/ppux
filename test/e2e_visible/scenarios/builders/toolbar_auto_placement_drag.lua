-- Visible E2E: drag CHR window around; specialized toolbar stays on top with Y clamp.

local P = require("test.e2e_visible.scenarios.prelude")
local BubbleExample, pause, call, appendDrag, windowHeaderCenter = P.BubbleExample, P.pause, P.call, P.appendDrag, P.windowHeaderCenter

local ToolbarAuto = require("test.e2e_visible.scenarios.toolbar_auto_placement_helpers")

local function chrWinFromRunner(_currentApp, currentRunner)
  return assert(currentRunner.toolbarAutoChrWin, "expected CHR window on runner")
end

--- Mouse canvas position to release drag so window content aims at (tx, ty) after header-center press (uses win.dx, win.dy).
local function dragReleaseCanvasNearContent(tx, ty)
  return function(_harness, _app, currentRunner)
    local win = assert(currentRunner.toolbarAutoChrWin, "expected CHR window")
    return tx + win.dx, ty + win.dy
  end
end

local function buildToolbarAutoPlacementDragScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local spots = {
    { 48, 90 },
    { 520, 70 },
    { 720, 320 },
    { 120, 400 },
    { 340, 200 },
    { 10, 160 },
    { 840, 120 },
    { 180, 300 },
    { 200, -40 },
    { 100, -120 },
    { -80, 200 },
    { 1200, 220 },
  }

  local steps = {
    pause("Start - toolbar top clamp (drag CHR)", 0.45),
    call("Use attached (non-detached) toolbar", function(_, currentApp)
      if currentApp._applySeparateToolbarSetting then
        currentApp:_applySeparateToolbarSetting(false, false)
      end
    end),
    pause("Settings applied", 0.35),
    call("Focus CHR bank window", function(currentHarness, currentApp, currentRunner)
      local win = assert(currentHarness:findWindow({ kind = "chr" }), "expected CHR bank window")
      currentRunner.toolbarAutoChrWin = win
      currentApp.wm:setFocus(win)
    end),
    pause("Observe focused CHR + specialized toolbar", 0.65),
  }

  for i, spot in ipairs(spots) do
    appendDrag(
      steps,
      string.format("Drag CHR header (spot %d/%d)", i, #spots),
      windowHeaderCenter(chrWinFromRunner),
      dragReleaseCanvasNearContent(spot[1], spot[2]),
      {
        dragDuration = 0.55,
        moveDuration = 0.14,
        prePressPause = 0.09,
        holdDuration = 0.07,
        preReleasePause = 0.08,
        postPause = 0.28,
      }
    )
    steps[#steps + 1] = call(string.format("Assert toolbar top clamp (spot %d)", i), function(_, currentApp, currentRunner)
      local win = assert(currentRunner.toolbarAutoChrWin, "expected CHR window")
      ToolbarAuto.assertSpecializedToolbarMatchesTopClamp(win, currentApp)
    end)
    steps[#steps + 1] = pause(string.format("Layout OK - spot %d", i), 0.45)
  end

  steps[#steps + 1] = pause("Done", 0.85)
  return steps
end

return {
  toolbar_auto_placement_drag = {
    title = "Toolbar top clamp (drag CHR)",
    build = buildToolbarAutoPlacementDragScenario,
  },
}
