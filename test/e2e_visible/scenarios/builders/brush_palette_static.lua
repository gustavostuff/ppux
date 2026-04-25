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


local function buildBrushPaintLinesScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local bankWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local regionStartCol = 4
  local regionStartRow = 4

  local function chrRegionPixelPoint(px, py)
    return function(h)
      local tileCol = regionStartCol + math.floor(px / 8)
      local tileRow = regionStartRow + math.floor(py / 8)
      local localPx = px % 8
      local localPy = py % 8
      return h:windowPixelCenter(bankWin, tileCol, tileRow, localPx, localPy)
    end
  end

  local steps = {
    pause("Start", 0.35),
  }

  steps[#steps + 1] = call("Focus CHR window", function(_, currentApp)
    currentApp.wm:setFocus(bankWin)
  end)
  steps[#steps + 1] = keyPress("Switch to edit mode", "tab")
  steps[#steps + 1] = pause("Observe edit mode", 0.35)

  steps[#steps + 1] = keyPress("Choose fill color 1", "2")
  steps[#steps + 1] = keyPress("Set large brush", "4", { "alt" })
  steps[#steps + 1] = pause("Observe large brush fill setup", 0.2)

  for band = 0, 10 do
    local y = math.min(63, band * 6)
    local fromX = (band % 2 == 0) and 0 or 63
    local toX = (band % 2 == 0) and 63 or 0
    appendDrag(steps, string.format("Wash full region band %d", band + 1), chrRegionPixelPoint(fromX, y), chrRegionPixelPoint(toX, y), {
      dragDuration = 0.14,
      postPause = 0.04,
    })
  end
  steps[#steps + 1] = pause("Observe cleared region", 0.2)

  steps[#steps + 1] = keyPress("Choose line color 2", "3")
  steps[#steps + 1] = keyPress("Set small brush", "1", { "alt" })
  appendDrag(steps, "Paint main diagonal", chrRegionPixelPoint(0, 0), chrRegionPixelPoint(63, 63), {
    dragDuration = 0.22,
    postPause = 0.16,
  })
  appendDrag(steps, "Paint box top edge", chrRegionPixelPoint(25, 25), chrRegionPixelPoint(30, 25), {
    dragDuration = 0.08,
    postPause = 0.06,
  })
  appendDrag(steps, "Paint box bottom edge", chrRegionPixelPoint(25, 30), chrRegionPixelPoint(30, 30), {
    dragDuration = 0.08,
    postPause = 0.06,
  })
  appendDrag(steps, "Paint box left edge", chrRegionPixelPoint(25, 25), chrRegionPixelPoint(25, 30), {
    dragDuration = 0.08,
    postPause = 0.06,
  })
  appendDrag(steps, "Paint box right edge", chrRegionPixelPoint(30, 25), chrRegionPixelPoint(30, 30), {
    dragDuration = 0.08,
    postPause = 0.12,
  })

  steps[#steps + 1] = keyPress("Choose line color 3", "4")
  steps[#steps + 1] = keyPress("Set medium brush", "2", { "alt" })
  appendDrag(steps, "Paint opposite diagonal", chrRegionPixelPoint(0, 63), chrRegionPixelPoint(63, 0), {
    dragDuration = 0.22,
    postPause = 0.16,
  })
  appendDrag(steps, "Paint center horizontal line", chrRegionPixelPoint(0, 31), chrRegionPixelPoint(63, 31), {
    dragDuration = 0.2,
    postPause = 0.16,
  })

  steps[#steps + 1] = keyPress("Choose line color 0", "1")
  steps[#steps + 1] = keyPress("Set broad brush", "3", { "alt" })
  appendDrag(steps, "Paint vertical accent line", chrRegionPixelPoint(31, 0), chrRegionPixelPoint(31, 63), {
    dragDuration = 0.2,
    postPause = 0.25,
  })

  steps[#steps + 1] = keyPress("Set temporary color 1", "2")
  steps[#steps + 1] = pause("Observe temporary color", 0.12)
  steps[#steps + 1] = moveTo("Move to painted box color", chrRegionPixelPoint(25, 25), 0.08)
  steps[#steps + 1] = pause("Prepare color grab", 0.08)
  steps[#steps + 1] = call("Pick painted box color", function(h)
    local x, y = h:windowPixelCenter(bankWin, regionStartCol + 3, regionStartRow + 3, 1, 1)
    h:keyDown("g", { "g" })
    h:click(x, y, { wait = false })
    h:keyUp("g", { "g" })
  end)
  steps[#steps + 1] = pause("Observe picked color", 0.16)
  steps[#steps + 1] = moveTo("Move inside painted box", chrRegionPixelPoint(27, 27), 0.08)
  steps[#steps + 1] = pause("Prepare flood fill", 0.08)
  steps[#steps + 1] = call("Flood fill inside painted box", function(h)
    local x, y = h:windowPixelCenter(bankWin, regionStartCol + 3, regionStartRow + 3, 3, 3)
    h:keyDown("f", { "f" })
    h:click(x, y, { wait = false })
    h:keyUp("f", { "f" })
  end)
  steps[#steps + 1] = pause("Observe flood fill result", 0.45)

  steps[#steps + 1] = keyPress("Choose shift tool color 2", "3")
  steps[#steps + 1] = keyPress("Set small brush for shift tools", "1", { "alt" })
  steps[#steps + 1] = pause("Prepare shift line anchor", 0.08)
  steps[#steps + 1] = call("Set shift line anchor", function(h)
    local x, y = chrRegionPixelPoint(8, 48)(h)
    h:keyDown("lshift", { "lshift" })
    h:click(x, y, { wait = false })
    h:keyUp("lshift", { "lshift" })
  end)
  steps[#steps + 1] = pause("Observe line anchor", 0.16)
  steps[#steps + 1] = call("Draw shift line from anchor", function(h)
    local x, y = chrRegionPixelPoint(24, 56)(h)
    h:keyDown("lshift", { "lshift" })
    h:click(x, y, { wait = false })
    h:keyUp("lshift", { "lshift" })
  end)
  steps[#steps + 1] = pause("Observe shift line", 0.2)

  steps[#steps + 1] = keyPress("Choose rectangle color 3", "4")
  steps[#steps + 1] = pause("Prepare shift rectangle", 0.08)
  steps[#steps + 1] = call("Draw shift rectangle fill", function(h)
    local x1, y1 = chrRegionPixelPoint(40, 40)(h)
    local x2, y2 = chrRegionPixelPoint(52, 52)(h)
    h:keyDown("lshift", { "lshift" })
    h:moveMouse(x1, y1)
    h:mouseDown(1, x1, y1)
    h:wait(0.06)
    h:moveMouse(x2, y2)
    h:wait(0.08)
    h:mouseUp(1, x2, y2)
    h:keyUp("lshift", { "lshift" })
  end)
  steps[#steps + 1] = pause("Observe shift rectangle fill", 0.35)

  steps[#steps + 1] = pause("Observe all painted brush tools", 0.8)
  steps[#steps + 1] = keyPress("Return to tile mode", "tab")
  steps[#steps + 1] = pause("Observe tile mode", 0.5)

  return steps
end

local function buildNewWindowVariantsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local tileWindowName = "Tile Draft"
  local spriteWindowName = "Sprite 8x16"
  local steps = {
    pause("Start", 0.35),
    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.6),
    moveTo("Move to tile window option", newWindowOptionCenter(1), 0.12),
    pause("Prepare tile option click", 0.08),
    mouseDown("Pick tile window type", newWindowOptionCenter(1), 1),
    pause("Hold tile option click", 0.08),
    mouseUp("Release tile option click", newWindowOptionCenter(1), 1),
    pause("Observe tile window settings", 0.2),
    call("Set tile window name", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField, "expected new window modal name field")
      modal.nameField:setText(tileWindowName)
    end),
    pause("Observe tile window name", 0.3),
    keyPress("Confirm tile window settings", "return"),
    pause("Observe new tile window", 0.7),
    keyPress("Open new window modal again", "n", { "lctrl" }),
    pause("Observe modal for sprite window", 0.55),
  }

  steps[#steps + 1] = moveTo("Move to sprite window option", newWindowOptionCenter(2), 0.12)
  steps[#steps + 1] = pause("Prepare sprite option click", 0.08)
  steps[#steps + 1] = mouseDown("Pick sprite window type", newWindowOptionCenter(2), 1)
  steps[#steps + 1] = pause("Hold sprite option click", 0.08)
  steps[#steps + 1] = mouseUp("Release sprite type click", newWindowOptionCenter(2), 1)
  steps[#steps + 1] = pause("Observe sprite settings modal", 0.2)

  appendClick(steps, "Toggle sprite mode to 8x16", newWindowModeToggleCenter(), {
    moveDuration = 0.08,
    postPause = 0.3,
  })

  steps[#steps + 1] = call("Set sprite window name", function(_, currentApp)
    local modal = currentApp.newWindowModal
    assert(modal and modal.nameField, "expected new window modal name field")
    modal.nameField:setText(spriteWindowName)
  end)
  steps[#steps + 1] = pause("Observe sprite window name", 0.3)
  steps[#steps + 1] = keyPress("Confirm sprite window settings", "return")
  steps[#steps + 1] = pause("Resolve created windows", 0.25)
  steps[#steps + 1] = call("Refocus sprite window", function(currentHarness, currentApp, currentRunner)
    currentRunner.tileVariantWin = assert(currentHarness:findWindow({
      kind = "static_art",
      title = tileWindowName,
    }), "expected created tile window")
    currentRunner.spriteVariantWin = assert(currentHarness:findWindow({
      kind = "static_art",
      title = spriteWindowName,
    }), "expected created sprite window")
    if currentApp.wm and currentApp.wm.setFocus then
      currentApp.wm:setFocus(currentRunner.spriteVariantWin)
    end
  end)
  steps[#steps + 1] = pause("Observe created window variants", 1.0)

  return steps
end

local function buildPaletteShaderPreviewScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local spriteWindowName = "Palette Preview"

  local steps = {
    pause("Start", 0.35),
    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.55),
    moveTo("Move to sprite window option", newWindowOptionCenter(2), 0.12),
    pause("Prepare sprite option click", 0.08),
    mouseDown("Pick sprite window type", newWindowOptionCenter(2), 1),
    pause("Hold sprite option click", 0.08),
    mouseUp("Release sprite option click", newWindowOptionCenter(2), 1),
    pause("Observe sprite settings modal", 0.2),
    call("Set sprite window name", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField, "expected new window modal name field")
      modal.nameField:setText(spriteWindowName)
    end),
    pause("Observe sprite window name", 0.25),
    keyPress("Confirm sprite window settings", "return"),
    pause("Resolve sprite window", 0.3),
    call("Focus created sprite window", function(currentHarness, currentApp, currentRunner)
      currentRunner.paletteSpriteWin = assert(currentHarness:findWindow({
        kind = "static_art",
        title = spriteWindowName,
      }), "expected sprite preview window")
      if currentApp.wm and currentApp.wm.setFocus then
        currentApp.wm:setFocus(currentRunner.paletteSpriteWin)
      end
    end),
  }

  appendDrag(steps, "Place sprite from ROM bank", function(h)
    return h:windowCellCenter(srcWin, 6, 0)
  end, function(h, _, currentRunner)
    return h:windowCellCenter(currentRunner.paletteSpriteWin, 0, 0)
  end, {
    dragDuration = 0.12,
    postPause = 0.35,
  })

  appendClick(steps, "Select placed sprite", function(h, _, currentRunner)
    return h:windowPixelCenter(currentRunner.paletteSpriteWin, 0, 0, 4, 4)
  end, {
    moveDuration = 0.08,
    postPause = 0.25,
  })

  steps[#steps + 1] = keyPress("Assign palette 3", "3")
  steps[#steps + 1] = pause("Observe palette change", 0.65)
  steps[#steps + 1] = keyPress("Toggle shader preview off", "r")
  steps[#steps + 1] = pause("Observe raw pixels", 0.65)
  steps[#steps + 1] = keyPress("Toggle shader preview on", "r")
  steps[#steps + 1] = pause("Observe shader preview restored", 0.75)

  return steps
end

local function buildStaticSpriteOpsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local spriteWindowName = "Sprite Ops"
  local placements = {
    { tile = 6, col = 1, row = 1 },
    { tile = 7, col = 3, row = 1 },
    { tile = 22, col = 1, row = 3 },
    { tile = 23, col = 3, row = 3 },
  }

  local steps = {
    pause("Start", 0.35),
    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.55),
    moveTo("Move to static sprite option", newWindowOptionCenterByText("Static Sprites window"), 0.12),
    pause("Prepare static sprite option click", 0.08),
    mouseDown("Pick static sprite window type", newWindowOptionCenterByText("Static Sprites window"), 1),
    pause("Hold static sprite option click", 0.08),
    mouseUp("Release static sprite option click", newWindowOptionCenterByText("Static Sprites window"), 1),
    pause("Observe sprite ops settings", 0.2),
    call("Configure sprite ops window", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField and modal.colsSpinner and modal.rowsSpinner, "expected new window modal controls")
      modal.nameField:setText(spriteWindowName)
      modal.colsSpinner:setValue(12)
      modal.rowsSpinner:setValue(10)
    end),
    pause("Observe sprite ops settings", 0.3),
    keyPress("Confirm static sprite window settings", "return"),
    pause("Resolve sprite ops window", 0.35),
    call("Focus sprite ops window", function(currentHarness, currentApp, currentRunner)
      currentRunner.spriteOpsWin = assert(currentHarness:findWindow({
        kind = "static_art",
        title = spriteWindowName,
      }), "expected sprite ops window")
      assert(
        currentRunner.spriteOpsWin.layers
          and currentRunner.spriteOpsWin.layers[1]
          and currentRunner.spriteOpsWin.layers[1].kind == "sprite",
        "expected Sprite Ops window to use a sprite layer"
      )
      currentRunner.spriteOpsWin.x = 320
      currentRunner.spriteOpsWin.y = 72
      currentApp.wm:setFocus(currentRunner.spriteOpsWin)
    end),
    pause("Observe sprite ops window", 0.45),
  }

  for i, placement in ipairs(placements) do
    local srcCol, srcRow = BubbleExample.bankCellForTile(srcWin, placement.tile)
    appendDrag(steps, string.format("Place sprite tile %d", placement.tile), function(h)
      return h:windowCellCenter(srcWin, srcCol, srcRow)
    end, function(h, _, currentRunner)
      return h:windowCellCenter(currentRunner.spriteOpsWin, placement.col, placement.row)
    end, {
      dragDuration = 0.12,
      postPause = 0.18,
    })
  end

  steps[#steps + 1] = call("Assert initial sprite placements", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.spriteOpsWin, "expected sprite ops window")
    local layer = assert(win.layers and win.layers[1], "expected sprite layer")
    assert(#(layer.items or {}) == 4, string.format("expected 4 initial sprites, got %d", #(layer.items or {})))
    currentApp.wm:setFocus(win)
  end)
  steps[#steps + 1] = pause("Observe initial sprite placements", 0.5)

  appendClick(steps, "Select first sprite", function(h, _, currentRunner)
    return h:windowCellCenter(currentRunner.spriteOpsWin, 1, 1)
  end, {
    moveDuration = 0.08,
    postPause = 0.18,
  })

  steps[#steps + 1] = keyPress("Copy selected sprite", "c", { "lctrl" })
  steps[#steps + 1] = pause("Observe copied sprite status", 0.2)
  steps[#steps + 1] = keyPress("Paste selected sprite", "v", { "lctrl" })
  steps[#steps + 1] = pause("Observe pasted sprite at center", 0.55)
  steps[#steps + 1] = call("Assert single sprite paste", function(_, _, currentRunner)
    local layer = assert(currentRunner.spriteOpsWin.layers and currentRunner.spriteOpsWin.layers[1], "expected sprite layer")
    assert(#(layer.items or {}) == 5, string.format("expected 5 sprites after single paste, got %d", #(layer.items or {})))
    currentRunner.spriteOpsPastedSingleIndex = #layer.items
  end)

  steps[#steps + 1] = call("Ctrl-drag copy centered sprite", function(currentHarness, currentApp, currentRunner)
    local fromX, fromY = spriteItemCenter(function(r) return r.spriteOpsWin end, function(r) return r.spriteOpsPastedSingleIndex end)(nil, currentApp, currentRunner)
    local toX, toY = currentHarness:windowCellCenter(currentRunner.spriteOpsWin, 8, 1)
    currentHarness:keyDown("lctrl", { "lctrl" })
    currentHarness:drag(fromX, fromY, toX, toY, {
      wait = false,
      steps = 6,
      dt = currentHarness.stepDt,
    })
    currentHarness:keyUp("lctrl", { "lctrl" })
  end)
  steps[#steps + 1] = pause("Observe ctrl-drag copy", 0.55)
  steps[#steps + 1] = call("Assert ctrl-drag copy count", function(_, _, currentRunner)
    local layer = assert(currentRunner.spriteOpsWin.layers and currentRunner.spriteOpsWin.layers[1], "expected sprite layer")
    assert(#(layer.items or {}) == 6, string.format("expected 6 sprites after ctrl-drag copy, got %d", #(layer.items or {})))
  end)

  steps[#steps + 1] = call("Marquee select original sprite group", function(currentHarness, _, currentRunner)
    local win = assert(currentRunner.spriteOpsWin, "expected sprite ops window")
    local x1, y1 = currentHarness:windowPixelCenter(win, 0, 0, 4, 4)
    local x2, y2 = currentHarness:windowPixelCenter(win, 4, 4, 4, 4)
    currentHarness:keyDown("lshift", { "lshift" })
    currentHarness:drag(x1, y1, x2, y2, {
      wait = false,
      steps = 6,
      dt = currentHarness.stepDt,
    })
    currentHarness:keyUp("lshift", { "lshift" })
  end)
  steps[#steps + 1] = pause("Observe marquee selection", 0.45)
  steps[#steps + 1] = call("Assert marquee group selection", function(_, _, currentRunner)
    local layer = assert(currentRunner.spriteOpsWin.layers and currentRunner.spriteOpsWin.layers[1], "expected sprite layer")
    local selected = {}
    for idx, on in pairs(layer.multiSpriteSelection or {}) do
      if on then
        selected[#selected + 1] = idx
      end
    end
    assert(#selected >= 4, string.format("expected at least 4 marquee-selected sprites, got %d", #selected))
    currentRunner.spriteOpsMarqueeSelectionCount = #selected
  end)

  steps[#steps + 1] = keyPress("Copy selected sprite group", "c", { "lctrl" })
  steps[#steps + 1] = pause("Observe copied group status", 0.2)
  steps[#steps + 1] = keyPress("Paste selected sprite group", "v", { "lctrl" })
  steps[#steps + 1] = pause("Observe pasted sprite group", 0.65)
  steps[#steps + 1] = call("Assert group paste and selection", function(_, _, currentRunner)
    local layer = assert(currentRunner.spriteOpsWin.layers and currentRunner.spriteOpsWin.layers[1], "expected sprite layer")
    local selectedCount = tonumber(currentRunner.spriteOpsMarqueeSelectionCount) or 4
    local expectedTotal = 6 + selectedCount
    assert(
      #(layer.items or {}) == expectedTotal,
      string.format("expected %d sprites after group paste, got %d", expectedTotal, #(layer.items or {}))
    )
    local selected = {}
    for idx, on in pairs(layer.multiSpriteSelection or {}) do
      if on then
        selected[#selected + 1] = idx
      end
    end
    assert(
      #selected == selectedCount,
      string.format("expected pasted group selection of %d sprites, got %d", selectedCount, #selected)
    )
  end)

  steps[#steps + 1] = keyPress("Mirror pasted group horizontally", "h")
  steps[#steps + 1] = pause("Observe horizontal mirror", 0.45)
  steps[#steps + 1] = call("Assert horizontal mirror on selected group", function(_, _, currentRunner)
    local layer = assert(currentRunner.spriteOpsWin.layers and currentRunner.spriteOpsWin.layers[1], "expected sprite layer")
    local mirrored = 0
    local selectedCount = tonumber(currentRunner.spriteOpsMarqueeSelectionCount) or 4
    for idx, on in pairs(layer.multiSpriteSelection or {}) do
      local sprite = layer.items and layer.items[idx]
      if on and sprite and sprite.mirrorX == true then
        mirrored = mirrored + 1
      end
    end
    assert(
      mirrored == selectedCount,
      string.format("expected %d horizontally mirrored sprites, got %d", selectedCount, mirrored)
    )
  end)

  steps[#steps + 1] = keyPress("Mirror pasted group vertically", "v")
  steps[#steps + 1] = pause("Observe vertical mirror", 0.55)
  steps[#steps + 1] = call("Assert vertical mirror on selected group", function(_, _, currentRunner)
    local layer = assert(currentRunner.spriteOpsWin.layers and currentRunner.spriteOpsWin.layers[1], "expected sprite layer")
    local mirrored = 0
    local selectedCount = tonumber(currentRunner.spriteOpsMarqueeSelectionCount) or 4
    for idx, on in pairs(layer.multiSpriteSelection or {}) do
      local sprite = layer.items and layer.items[idx]
      if on and sprite and sprite.mirrorY == true then
        mirrored = mirrored + 1
      end
    end
    assert(
      mirrored == selectedCount,
      string.format("expected %d vertically mirrored sprites, got %d", selectedCount, mirrored)
    )
  end)
  steps[#steps + 1] = pause("Observe final sprite operations", 0.8)

  return steps
end


return {
  brush_paint_tools = { title = "Brush Paint Tools", build = buildBrushPaintLinesScenario },
  new_window_variants = { title = "New Window Variants", build = buildNewWindowVariantsScenario },
  palette_shader_preview = { title = "Palette + Shader Preview", build = buildPaletteShaderPreviewScenario },
  static_sprite_ops = { title = "Static Sprite Ops", build = buildStaticSpriteOpsScenario },
}
