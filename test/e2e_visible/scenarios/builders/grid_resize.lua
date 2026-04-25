-- Scenario builder chunk (split from definitions.lua).
local P = require("test.e2e_visible.scenarios.prelude")
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


local function buildGridResizeToolbarScenario(harness, app, _runner)
  local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
  harness:loadROM(BubbleExample.getLoadPath())
  BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )

  local tileWinTitle = "E2E Grid (tiles)"
  local spriteWinTitle = "E2E Grid (sprites)"

  local function chrTileRefForGridResize(currentApp, romIndex)
    local srcWin = assert(BubbleExample.findBankWindow(currentApp), "expected CHR bank window")
    BubbleExample.prepareBankWindow(srcWin)
    local sc, sr = BubbleExample.bankCellForTile(srcWin, romIndex)
    return assert(srcWin:get(sc, sr, 1), "expected CHR tile index " .. tostring(romIndex))
  end

  local function spriteItemFromChr(currentApp, romIndex, worldX, worldY)
    local topRef = chrTileRefForGridResize(currentApp, romIndex)
    return {
      worldX = worldX,
      worldY = worldY,
      removed = false,
      topRef = topRef,
      bank = 1,
      tile = romIndex,
    }
  end

  local steps = {
    pause("Start", 0.35),
    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.65),
    moveTo("Move to animation tiles option", newWindowOptionCenter(3), 0.12),
    pause("Prepare animation option click", 0.08),
    mouseDown("Pick animation window type", newWindowOptionCenter(3), 1),
    pause("Hold animation option click", 0.08),
    mouseUp("Release animation type click", newWindowOptionCenter(3), 1),
    pause("Observe animation settings modal", 0.22),
    call("Set tile animation window name", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField, "expected new window modal name field")
      modal.nameField:setText(tileWinTitle)
    end),
    pause("Observe animation window name", 0.18),
    keyPress("Confirm animation window settings", "return"),
    pause("Observe animation window", 0.7),
    call("Resolve and focus tile animation window", function(currentHarness, currentApp, currentRunner)
      local animWin = assert(currentHarness:findWindow({
        kind = "animation",
        title = tileWinTitle,
      }), "expected tile animation window")
      currentRunner.gridResizeTileAnimWin = animWin
      local canvas = currentApp.canvas
      if canvas and currentApp.wm and currentApp.wm.setFocus then
        local zoom = (animWin.getZoomLevel and animWin:getZoomLevel()) or animWin.zoom or 1
        local contentW = (animWin.visibleCols or animWin.cols or 1) * (animWin.cellW or 8) * zoom
        local contentH = (animWin.visibleRows or animWin.rows or 1) * (animWin.cellH or 8) * zoom
        animWin.x = math.floor((canvas:getWidth() - contentW) * 0.5)
        animWin.y = math.floor((canvas:getHeight() - contentH) * 0.35)
        currentApp.wm:setFocus(animWin)
      end
    end),
    pause("Observe focused tile animation window", 0.45),
    call("Sync app top toolbar layout", function(_, currentApp)
      AppTopToolbarController.syncLayout(currentApp)
    end),
    pause("Toolbar ready", 0.12),
    call("Seed palette at (col 5, row 1) for column remap check", function(_, _, currentRunner)
      local animWin = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
      local layer = assert(animWin.layers and animWin.layers[1], "expected first frame layer")
      layer.paletteNumbers = layer.paletteNumbers or {}
      local cols = animWin.cols or 8
      local linear = 1 * cols + 5
      layer.paletteNumbers[linear] = 3
    end),
    pause("Observe seeded palette", 0.15),
    call("Assert baseline 8x8 tile window grid", function(_, _, currentRunner)
      local w = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
      assert(
        w.cols == 8 and w.rows == 8,
        string.format("expected 8x8 animation grid, got %dx%d", tonumber(w.cols) or -1, tonumber(w.rows) or -1)
      )
    end),
  }

  appendClick(steps, "Add column (app toolbar)", appQuickButtonCenter("addGridColumn"), {
    moveDuration = 0.12,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert add column: width 9 and palette remapped", function(_, _, currentRunner)
    local w = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
    assert(w.cols == 9, string.format("expected cols=9 after add column, got %s", tostring(w.cols)))
    local layer = assert(w.layers and w.layers[1], "expected frame layer")
    local pal = layer.paletteNumbers or {}
    assert(pal[13] == nil, "expected old 0-based palette index 13 to be cleared after widen")
    assert(
      pal[14] == 3,
      string.format("expected palette 3 at new index 14 (row 1 col 5), got %s", tostring(pal[14]))
    )
  end)
  steps[#steps + 1] = pause("Observe widened grid", 0.35)

  steps[#steps + 1] = call("Hold Shift for remove-column mode", function(harness)
    harnessHoldShiftForGridResize(harness, true)
  end)
  appendClick(steps, "Remove last column (Shift + same button)", appQuickButtonCenter("addGridColumn"), {
    moveDuration = 0.12,
    postPause = 0.2,
  })
  steps[#steps + 1] = call("Release Shift", function(harness)
    harnessHoldShiftForGridResize(harness, false)
  end)
  steps[#steps + 1] = pause("Observe after column remove", 0.25)
  steps[#steps + 1] = call("Assert column remove restored 8 cols and palette slot", function(_, _, currentRunner)
    local w = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
    assert(w.cols == 8, string.format("expected cols=8 after remove, got %s", tostring(w.cols)))
    local layer = assert(w.layers and w.layers[1], "expected frame layer")
    local pal = layer.paletteNumbers or {}
    assert(
      pal[13] == 3,
      string.format("expected palette 3 back at index 13, got %s", tostring(pal[13]))
    )
    assert(pal[14] == nil, "expected stray widened-grid palette slot to be gone")
  end)

  appendClick(steps, "Add row (app toolbar)", appQuickButtonCenter("addGridRow"), {
    moveDuration = 0.12,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert add row height 9", function(_, _, currentRunner)
    local w = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
    assert(w.rows == 9, string.format("expected rows=9 after add row, got %s", tostring(w.rows)))
  end)
  steps[#steps + 1] = pause("Observe taller grid", 0.3)

  steps[#steps + 1] = call("Hold Shift for remove-row mode", function(harness)
    harnessHoldShiftForGridResize(harness, true)
  end)
  appendClick(steps, "Remove last row (Shift + row button)", appQuickButtonCenter("addGridRow"), {
    moveDuration = 0.12,
    postPause = 0.2,
  })
  steps[#steps + 1] = call("Release Shift after row remove", function(harness)
    harnessHoldShiftForGridResize(harness, false)
  end)
  steps[#steps + 1] = pause("Observe after row remove", 0.25)
  steps[#steps + 1] = call("Assert row remove restored 8 rows", function(_, _, currentRunner)
    local w = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
    assert(w.rows == 8, string.format("expected rows=8 after remove, got %s", tostring(w.rows)))
  end)

  -- Tile window: six tiles at varied cells; last column occupied -> remove column blocked
  steps[#steps + 1] = call("Place six tiles (varied cells + last-column blocker)", function(_, currentApp, currentRunner)
    local animWin = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
    currentApp.wm:setFocus(animWin)
    local placements = {
      { col = 1, row = 2, rom = 6 },
      { col = 2, row = 1, rom = 9 },
      { col = 3, row = 4, rom = 11 },
      { col = 4, row = 2, rom = 13 },
      { col = 0, row = 3, rom = 15 },
      { col = 7, row = 5, rom = 21 },
    }
    for _, p in ipairs(placements) do
      animWin:set(p.col, p.row, chrTileRefForGridResize(currentApp, p.rom), 1)
    end
  end)
  steps[#steps + 1] = pause("Observe six scattered tiles", 0.28)
  steps[#steps + 1] = call("Hold Shift for blocked column remove", function(harness)
    harnessHoldShiftForGridResize(harness, true)
  end)
  appendClick(steps, "Try remove last column (should no-op)", appQuickButtonCenter("addGridColumn"), {
    moveDuration = 0.12,
    postPause = 0.18,
  })
  steps[#steps + 1] = call("Release Shift after blocked column remove", function(harness)
    harnessHoldShiftForGridResize(harness, false)
  end)
  steps[#steps + 1] = pause("Observe blocked column remove", 0.22)
  steps[#steps + 1] = call("Assert tile window column remove blocked", function(currentHarness, _, currentRunner)
    local w = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
    assert(w.cols == 8, string.format("expected cols still 8 when last column occupied, got %s", tostring(w.cols)))
    assertStatusContainsOccupiedLayout(currentHarness)
  end)

  steps[#steps + 1] = call("Clear six tiles from column-block segment", function(_, currentApp, currentRunner)
    local animWin = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
    currentApp.wm:setFocus(animWin)
    for _, p in ipairs({
      { col = 1, row = 2 },
      { col = 2, row = 1 },
      { col = 3, row = 4 },
      { col = 4, row = 2 },
      { col = 0, row = 3 },
      { col = 7, row = 5 },
    }) do
      animWin:set(p.col, p.row, nil, 1)
    end
  end)
  steps[#steps + 1] = pause("Cleared column-block tiles", 0.18)

  -- Tile window: six tiles incl. last row -> remove row blocked
  steps[#steps + 1] = call("Place six tiles (varied cells + last-row blocker)", function(_, currentApp, currentRunner)
    local animWin = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
    currentApp.wm:setFocus(animWin)
    local placements = {
      { col = 2, row = 0, rom = 7 },
      { col = 5, row = 2, rom = 10 },
      { col = 1, row = 4, rom = 12 },
      { col = 6, row = 3, rom = 14 },
      { col = 3, row = 5, rom = 18 },
      { col = 4, row = 7, rom = 22 },
    }
    for _, p in ipairs(placements) do
      animWin:set(p.col, p.row, chrTileRefForGridResize(currentApp, p.rom), 1)
    end
  end)
  steps[#steps + 1] = pause("Observe six tiles incl. last row", 0.28)
  steps[#steps + 1] = call("Hold Shift for blocked row remove", function(harness)
    harnessHoldShiftForGridResize(harness, true)
  end)
  appendClick(steps, "Try remove last row (should no-op)", appQuickButtonCenter("addGridRow"), {
    moveDuration = 0.12,
    postPause = 0.18,
  })
  steps[#steps + 1] = call("Release Shift after blocked row remove", function(harness)
    harnessHoldShiftForGridResize(harness, false)
  end)
  steps[#steps + 1] = pause("Observe blocked row remove", 0.22)
  steps[#steps + 1] = call("Assert tile window row remove blocked", function(currentHarness, _, currentRunner)
    local w = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
    assert(w.rows == 8, string.format("expected rows still 8 when last row occupied, got %s", tostring(w.rows)))
    assertStatusContainsOccupiedLayout(currentHarness)
  end)

  steps[#steps + 1] = call("Clear six tiles from row-block segment", function(_, currentApp, currentRunner)
    local animWin = assert(currentRunner.gridResizeTileAnimWin, "expected tile animation window")
    currentApp.wm:setFocus(animWin)
    for _, p in ipairs({
      { col = 2, row = 0 },
      { col = 5, row = 2 },
      { col = 1, row = 4 },
      { col = 6, row = 3 },
      { col = 3, row = 5 },
      { col = 4, row = 7 },
    }) do
      animWin:set(p.col, p.row, nil, 1)
    end
  end)
  steps[#steps + 1] = pause("Cleared row-block tiles", 0.2)

  -- Sprite animation window: sprite in last column / last row strips -> removes blocked
  steps[#steps + 1] = keyPress("Open new window modal for sprites", "n", { "lctrl" })
  steps[#steps + 1] = pause("Observe new window modal (sprites)", 0.55)
  steps[#steps + 1] = moveTo("Move to animation sprites option", newWindowOptionCenter(4), 0.12)
  steps[#steps + 1] = pause("Prepare animation sprites click", 0.08)
  steps[#steps + 1] = mouseDown("Pick animation sprites type", newWindowOptionCenter(4), 1)
  steps[#steps + 1] = pause("Hold animation sprites click", 0.08)
  steps[#steps + 1] = mouseUp("Release animation sprites click", newWindowOptionCenter(4), 1)
  steps[#steps + 1] = pause("Observe sprite animation settings modal", 0.22)
  steps[#steps + 1] = call("Set sprite animation window name", function(_, currentApp)
    local modal = currentApp.newWindowModal
    assert(modal and modal.nameField, "expected new window modal name field")
    modal.nameField:setText(spriteWinTitle)
  end)
  steps[#steps + 1] = pause("Observe sprite window name", 0.15)
  steps[#steps + 1] = keyPress("Confirm sprite animation settings", "return")
  steps[#steps + 1] = pause("Observe sprite animation window", 0.65)
  steps[#steps + 1] = call("Resolve and place sprite animation window", function(currentHarness, currentApp, currentRunner)
    local w = assert(currentHarness:findWindow({
      kind = "animation",
      title = spriteWinTitle,
    }), "expected sprite animation window")
    currentRunner.gridResizeSpriteAnimWin = w
    local canvas = currentApp.canvas
    if canvas and currentApp.wm and currentApp.wm.setFocus then
      local zoom = (w.getZoomLevel and w:getZoomLevel()) or w.zoom or 1
      local contentW = (w.visibleCols or w.cols or 1) * (w.cellW or 8) * zoom
      local contentH = (w.visibleRows or w.rows or 1) * (w.cellH or 8) * zoom
      w.x = math.max(24, math.floor(canvas:getWidth() * 0.5 - contentW * 0.5))
      w.y = math.min(
        math.max(120, math.floor(canvas:getHeight() * 0.55)),
        math.max(80, canvas:getHeight() - contentH - 40)
      )
      currentApp.wm:setFocus(w)
    end
  end)
  steps[#steps + 1] = pause("Observe focused sprite window", 0.4)
  steps[#steps + 1] = call("Sync toolbar after sprite window", function(_, currentApp)
    AppTopToolbarController.syncLayout(currentApp)
  end)
  steps[#steps + 1] = pause("Toolbar ready (sprite window)", 0.12)

  steps[#steps + 1] = call("Seed six sprites (non-8 coords + last-column strip overlap)", function(_, currentApp, currentRunner)
    local w = assert(currentRunner.gridResizeSpriteAnimWin, "expected sprite animation window")
    currentApp.wm:setFocus(w)
    local layer = assert(w.layers and w.layers[1], "expected first layer")
    assert(layer.kind == "sprite", "expected sprite layer on animation sprites window")
    layer.items = {
      spriteItemFromChr(currentApp, 6, 11, 19),
      spriteItemFromChr(currentApp, 8, 23, 14),
      spriteItemFromChr(currentApp, 10, 35, 27),
      spriteItemFromChr(currentApp, 12, 41, 5),
      spriteItemFromChr(currentApp, 14, 5, 41),
      spriteItemFromChr(currentApp, 20, 57, 3),
    }
  end)
  steps[#steps + 1] = pause("Observe six sprites (one blocks last column)", 0.26)
  steps[#steps + 1] = call("Hold Shift sprite column remove attempt", function(harness)
    harnessHoldShiftForGridResize(harness, true)
  end)
  appendClick(steps, "Try remove last column on sprite window", appQuickButtonCenter("addGridColumn"), {
    moveDuration = 0.12,
    postPause = 0.18,
  })
  steps[#steps + 1] = call("Release Shift sprite column", function(harness)
    harnessHoldShiftForGridResize(harness, false)
  end)
  steps[#steps + 1] = pause("After sprite column remove attempt", 0.2)
  steps[#steps + 1] = call("Assert sprite window column remove blocked", function(currentHarness, _, currentRunner)
    local w = assert(currentRunner.gridResizeSpriteAnimWin, "expected sprite animation window")
    assert(w.cols == 8, string.format("expected cols still 8 (sprite blocks strip), got %s", tostring(w.cols)))
    assertStatusContainsOccupiedLayout(currentHarness)
  end)

  steps[#steps + 1] = call("Replace with six sprites (non-8 coords + last-row strip overlap)", function(_, currentApp, currentRunner)
    local w = assert(currentRunner.gridResizeSpriteAnimWin, "expected sprite animation window")
    currentApp.wm:setFocus(w)
    local layer = assert(w.layers and w.layers[1], "expected sprite layer")
    layer.items = {
      spriteItemFromChr(currentApp, 7, 10, 12),
      spriteItemFromChr(currentApp, 9, 26, 20),
      spriteItemFromChr(currentApp, 11, 38, 9),
      spriteItemFromChr(currentApp, 13, 19, 44),
      spriteItemFromChr(currentApp, 16, 33, 31),
      spriteItemFromChr(currentApp, 22, 13, 59),
    }
  end)
  steps[#steps + 1] = pause("Observe six sprites (one blocks last row)", 0.26)
  steps[#steps + 1] = call("Hold Shift sprite row remove attempt", function(harness)
    harnessHoldShiftForGridResize(harness, true)
  end)
  appendClick(steps, "Try remove last row on sprite window", appQuickButtonCenter("addGridRow"), {
    moveDuration = 0.12,
    postPause = 0.18,
  })
  steps[#steps + 1] = call("Release Shift sprite row", function(harness)
    harnessHoldShiftForGridResize(harness, false)
  end)
  steps[#steps + 1] = pause("After sprite row remove attempt", 0.2)
  steps[#steps + 1] = call("Assert sprite window row remove blocked", function(currentHarness, _, currentRunner)
    local w = assert(currentRunner.gridResizeSpriteAnimWin, "expected sprite animation window")
    assert(w.rows == 8, string.format("expected rows still 8 (sprite blocks strip), got %s", tostring(w.rows)))
    assertStatusContainsOccupiedLayout(currentHarness)
  end)

  steps[#steps + 1] = pause("Grid resize toolbar scenario complete", 0.45)

  return steps
end

return {
  grid_resize_toolbar = {
    title = "Grid resize (toolbar + blocked removes)",
    build = buildGridResizeToolbarScenario,
  },
}
