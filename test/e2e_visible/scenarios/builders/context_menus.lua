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


local function buildSubmenuPositionScenario(_, app)
  local margin = 4
  local function buildChildItems()
    return {
      { text = "First child", icon = images.icons.icon_clock },
      { text = "Second child", icon = images.icons.settings },
      { text = "Third child", icon = images.icons.icon_windows },
      { text = "Fourth child", icon = images.icons.save },
      { text = "Fifth child", icon = images.icons.icon_quit },
      { text = "Sixth child", icon = images.icons.icon_x },
    }
  end

  local demoItems = {
    { text = "Corner Alpha", icon = images.icons.icon_clock, children = buildChildItems },
    { text = "Corner Beta", icon = images.icons.settings, children = buildChildItems },
    { text = "Corner Gamma", icon = images.icons.icon_windows, children = buildChildItems },
  }

  local function rootMenu(_, currentRunner)
    return assert(currentRunner.demoMenu, "expected demo contextual menu")
  end

  local function showRootAtCorner(corner)
    return function(_, currentApp, currentRunner)
      local menu = rootMenu(currentApp, currentRunner)
      menu:showAt(0, 0, demoItems)

      local canvasW = currentApp.canvas:getWidth()
      local canvasH = currentApp.canvas:getHeight()
      local x = margin
      local y = margin

      if corner == "top_right" or corner == "bottom_right" then
        x = canvasW - menu.panel.w - margin
      end
      if corner == "bottom_left" or corner == "bottom_right" then
        y = canvasH - menu.panel.h - margin
      end

      menu:showAt(x, y, demoItems)
    end
  end

  local function assertChildPlacement()
    return function(_, currentApp, currentRunner)
      local menu = rootMenu(currentApp, currentRunner)
      local child = assert(menu.childMenu, "expected child menu")
      local childPanel = assert(child.panel, "expected child menu panel")
      local bounds = menu.getBounds and menu.getBounds() or {
        w = currentApp.canvas:getWidth(),
        h = currentApp.canvas:getHeight(),
      }
      local anchorCol = (menu.activeSplitIconCell == true and (tonumber(menu.cols) or 1) > 1) and 2 or 1
      local anchorCell = assert(menu.panel:getCell(anchorCol, 1), "expected root anchor cell")

      -- Match controllers/ui/contextual_menu_controller.resolveChildPosition (gap + inset).
      local gap = tonumber(ContextualMenuController.PARENT_GAP_PX) or 2
      local inset = gap
      local expectedX = anchorCell.x + anchorCell.w + gap
      local maxRight = bounds.w - inset
      if (expectedX + childPanel.w) > maxRight then
        expectedX = anchorCell.x - childPanel.w - gap
      end

      local expectedY = anchorCell.y
      local maxBottom = bounds.h - inset
      if (expectedY + childPanel.h) > maxBottom then
        expectedY = anchorCell.y + anchorCell.h - childPanel.h
      end

      assert(child.x == expectedX, string.format("expected child x=%d got %d", expectedX, child.x))
      assert(child.y == expectedY, string.format("expected child y=%d got %d", expectedY, child.y))
    end
  end

  local function hoverRootFirstRow()
    return function(currentHarness, currentApp, currentRunner)
      local menu = rootMenu(currentApp, currentRunner)
      local anchorCol = (menu.activeSplitIconCell == true and (tonumber(menu.cols) or 1) > 1) and 2 or 1
      local cell = assert(menu.panel:getCell(anchorCol, 1), "expected root anchor cell")
      local x = cell.x + math.floor(cell.w * 0.5)
      local y = cell.y + math.floor(cell.h * 0.5)
      currentHarness:moveMouse(x, y)
      menu:mousemoved(x, y)
    end
  end

  local steps = {
    pause("Start", 0.35),
    call("Show root menu top-left", showRootAtCorner("top_left")),
    pause("Observe top-left root", 0.2),
    moveTo("Move to first row top-left", function(_, currentApp, currentRunner)
      return menuRowCenter(rootMenu, 1)(nil, currentApp, currentRunner)
    end, 0.12),
    call("Hover first row top-left", hoverRootFirstRow()),
    pause("Observe top-left submenu", 0.6),
    call("Assert top-left submenu placement", assertChildPlacement()),
    pause("Hold top-left placement", 0.5),

    call("Show root menu bottom-left", showRootAtCorner("bottom_left")),
    pause("Observe bottom-left root", 0.2),
    moveTo("Move to first row bottom-left", function(_, currentApp, currentRunner)
      return menuRowCenter(rootMenu, 1)(nil, currentApp, currentRunner)
    end, 0.12),
    call("Hover first row bottom-left", hoverRootFirstRow()),
    pause("Observe bottom-left submenu", 0.6),
    call("Assert bottom-left submenu placement", assertChildPlacement()),
    pause("Hold bottom-left placement", 0.5),

    call("Show root menu top-right", showRootAtCorner("top_right")),
    pause("Observe top-right root", 0.2),
    moveTo("Move to first row top-right", function(_, currentApp, currentRunner)
      return menuRowCenter(rootMenu, 1)(nil, currentApp, currentRunner)
    end, 0.12),
    call("Hover first row top-right", hoverRootFirstRow()),
    pause("Observe top-right submenu", 0.6),
    call("Assert top-right submenu placement", assertChildPlacement()),
    pause("Hold top-right placement", 0.5),

    call("Show root menu bottom-right", showRootAtCorner("bottom_right")),
    pause("Observe bottom-right root", 0.2),
    moveTo("Move to first row bottom-right", function(_, currentApp, currentRunner)
      return menuRowCenter(rootMenu, 1)(nil, currentApp, currentRunner)
    end, 0.12),
    call("Hover first row bottom-right", hoverRootFirstRow()),
    pause("Observe bottom-right submenu", 0.75),
    call("Assert bottom-right submenu placement", assertChildPlacement()),
    pause("Scenario complete", 0.7),
  }

  return steps
end

local function buildContextMenusAndSubmenusScenario(harness, app)
  harness:loadROM(BubbleExample.getLoadPath())
  app:setRecentProjects({
    "/tmp/project_a/foo",
    "/tmp/project_b/foo",
    "/tmp/project_c/bar",
  }, {
    persist = false,
  })

  local steps = {
    pause("Start", 0.35),
  }

  appendClick(steps, "Open taskbar menu", function(h)
    return h:getTaskbarButtonCenter({ kind = "menu" })
  end)

  steps[#steps + 1] = moveTo("Hover Recent Projects", rootMenuItemCenter(taskbarRootMenu, "Recent Projects"), 0.12)
  steps[#steps + 1] = pause("Observe Recent Projects submenu", 0.22)
  steps[#steps + 1] = call("Assert Recent Projects submenu is visible", assertTaskbarChildState(nil, true))

  steps[#steps + 1] = moveTo("Move through diagonal gap", taskbarMenuGapPoint(1), 0.12)
  steps[#steps + 1] = pause("Pause briefly outside both menus", 0.08)
  steps[#steps + 1] = call("Assert submenu survives grace gap", assertTaskbarChildState(nil, true))

  steps[#steps + 1] = moveTo("Enter Recent Projects child item", childMenuRowCenter(taskbarRootMenu, 1), 0.12)
  steps[#steps + 1] = pause("Observe child menu entry", 0.4)
  steps[#steps + 1] = call("Assert child menu still visible", assertTaskbarChildState(nil, true))

  steps[#steps + 1] = moveTo("Hover Windows parent item", rootMenuItemCenter(taskbarRootMenu, "Windows"), 0.08)
  steps[#steps + 1] = call("Assert submenu stays visible during sibling grace", assertTaskbarChildState(nil, true))
  steps[#steps + 1] = pause("Wait for submenu switch", 0.22)
  steps[#steps + 1] = call("Assert Windows submenu is now visible", assertTaskbarChildState("Windows", true))

  steps[#steps + 1] = moveTo("Enter Windows child item", childMenuRowCenter(taskbarRootMenu, 1), 0.12)
  steps[#steps + 1] = pause("Observe Windows child menu", 0.45)

  steps[#steps + 1] = moveTo("Hover Settings leaf item", rootMenuItemCenter(taskbarRootMenu, "Settings"), 0.08)
  steps[#steps + 1] = call("Assert submenu stays visible during leaf grace", assertTaskbarChildState(nil, true))
  steps[#steps + 1] = pause("Observe leaf hover grace", 0.35)
  steps[#steps + 1] = pause("Scenario complete", 0.5)
  return steps
end

local function buildWindowResizeAndHoverPriorityScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local bankWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local staticWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")

  local function currentBankWin(_, currentRunner)
    return currentRunner.bankResizeWin
  end

  local function currentStaticWin(_, currentRunner)
    return currentRunner.staticResizeWin
  end

  local function currentPpuWin(_, currentRunner)
    return currentRunner.ppuSelectWin
  end

  local steps = {
    pause("Start", 0.35),
    call("Arrange overlapping windows", function(_, currentApp, currentRunner)
      currentRunner.bankResizeWin = bankWin
      currentRunner.staticResizeWin = staticWin

      bankWin.x = 96
      bankWin.y = 58
      staticWin.x = 180
      staticWin.y = 112

      currentApp:_applySeparateToolbarSetting(true, false)

      if currentApp.wm and currentApp.wm.setFocus then
        currentApp.wm:setFocus(staticWin)
      end

      currentRunner.staticBefore = {
        cols = staticWin.visibleCols,
        rows = staticWin.visibleRows,
      }
      currentRunner.bankBefore = {
        cols = bankWin.visibleCols,
        rows = bankWin.visibleRows,
      }
    end),
    pause("Observe overlapping windows", 0.65),
    moveTo("Hover static resize handle over overlapping area", resizeHandleCenter(currentStaticWin), 0.12),
    pause("Observe handle hover priority", 0.55),
  }

  appendDrag(steps, "Resize static art window inward", resizeHandleCenter(currentStaticWin), function(_, _, currentRunner)
    local win = assert(currentRunner.staticResizeWin, "expected static resize window")
    local hx, hy, hw, hh = win:getResizeHandleRect()
    local zoom = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
    local shrinkX = math.max(18, math.floor(((win.cellW or 8) * zoom) + 6))
    local shrinkY = math.max(18, math.floor(((win.cellH or 8) * zoom) + 6))
    return hx + math.floor(hw * 0.5) - shrinkX, hy + math.floor(hh * 0.5) - shrinkY
  end, {
    dragDuration = 0.28,
    postPause = 0.35,
  })

  steps[#steps + 1] = call("Assert static window resized", function(_, _, currentRunner)
    local before = assert(currentRunner.staticBefore, "expected static size snapshot")
    local win = assert(currentRunner.staticResizeWin, "expected static resize window")
    assert((win.visibleCols or 0) < (before.cols or 0) or (win.visibleRows or 0) < (before.rows or 0), "expected static window visible size to shrink")
  end)
  steps[#steps + 1] = pause("Observe resized static window", 0.55)

  steps[#steps + 1] = call("Focus bank window", function(_, currentApp, currentRunner)
    if currentApp.wm and currentApp.wm.setFocus then
      currentApp.wm:setFocus(currentRunner.bankResizeWin)
    end
  end)
  steps[#steps + 1] = pause("Observe bank focus", 0.2)
  steps[#steps + 1] = moveTo("Hover bank resize handle", resizeHandleCenter(currentBankWin), 0.12)
  steps[#steps + 1] = pause("Observe bank handle hover priority", 0.5)

  steps[#steps + 1] = call("Resize bank window inward", function(currentHarness, currentApp, currentRunner)
    local win = assert(currentRunner.bankResizeWin, "expected bank resize window")
    if currentApp.wm and currentApp.wm.setFocus then
      currentApp.wm:setFocus(win)
    end

    local fromX, fromY = resizeHandleCenter(currentBankWin)(currentHarness, currentApp, currentRunner)
    local hx, hy, hw, hh = win:getResizeHandleRect()
    local zoom = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
    local shrinkX = math.max(22, math.floor(((win.cellW or 8) * zoom) + 10))
    local shrinkY = math.max(22, math.floor(((win.cellH or 8) * zoom) + 10))
    local toX, toY = currentHarness:contentToCanvasPoint(
      hx + math.floor(hw * 0.5) - shrinkX,
      hy + math.floor(hh * 0.5) - shrinkY
    )

    currentHarness:drag(fromX, fromY, toX, toY, {
      wait = false,
      steps = 6,
      dt = currentHarness.stepDt,
    })
  end)
  steps[#steps + 1] = pause("Observe bank resize drag", 0.35)

  steps[#steps + 1] = call("Assert bank window resized", function(_, _, currentRunner)
    local before = assert(currentRunner.bankBefore, "expected bank size snapshot")
    local win = assert(currentRunner.bankResizeWin, "expected bank resize window")
    assert((win.visibleCols or 0) < (before.cols or 0) or (win.visibleRows or 0) < (before.rows or 0), "expected bank window visible size to shrink")
  end)
  steps[#steps + 1] = pause("Observe resized bank window", 0.7)

  steps[#steps + 1] = call("Create PPU selection regression windows", function(_, currentApp, currentRunner)
    local oamWin = currentApp.wm:createSpriteWindow({
      animated = true,
      oamBacked = true,
      numFrames = 1,
      multiRowToolbar = true,
      spriteMode = "8x8",
      title = "Toolbar Focus",
      x = 28,
      y = 176,
      cols = 8,
      rows = 8,
      zoom = 2,
    })
    assert(oamWin, "expected OAM animation window")
    currentRunner.toolbarFocusWin = oamWin

    local ppuWin = currentApp.wm:createPPUFrameWindow({
      title = "PPU Select",
      x = 360,
      y = 72,
      zoom = 2,
      romRaw = currentApp.appEditState and currentApp.appEditState.romRaw,
      bankIndex = 1,
      pageIndex = 1,
    })
    assert(ppuWin, "expected PPU frame window")
    ppuWin.visibleCols = 8
    ppuWin.visibleRows = 8
    if ppuWin.setScroll then
      ppuWin:setScroll(0, 0)
    end

    local tilesPool = currentApp.appEditState and currentApp.appEditState.tilesPool
    assert(tilesPool, "expected tiles pool for PPU frame window")
    local BankViewController = require("controllers.chr.bank_view_controller")
    BankViewController.ensureBankTiles(currentApp.appEditState, 1)

    local bytes = {}
    for i = 1, 32 * 30 do
      bytes[i] = 0
    end
    bytes[(4 * 32) + 4 + 1] = 6
    bytes[(4 * 32) + 5 + 1] = 7
    bytes[(5 * 32) + 4 + 1] = 22
    bytes[(5 * 32) + 5 + 1] = 23
    do
      local layer = ppuWin.layers and ppuWin.layers[1] or nil
      if layer then
        -- Ensure PPU interaction-readiness gates are satisfied in tests.
        layer.patternTable = {
          ranges = {
            { bank = 1, page = 1, tileRange = { from = 0, to = 255 } },
          },
        }
        -- PPU interactions are now gated by explicit nametable address bounds.
        layer.nametableStartAddr = 0
        layer.nametableEndAddr = #bytes - 1
      end
    end
    ppuWin:setNametableBytes(bytes, 1, 1, tilesPool)

    local attrBytes = {}
    for i = 1, 64 do
      attrBytes[i] = 0
    end
    ppuWin:setAttributeBytes(attrBytes)

    if ppuWin.setActiveLayerIndex then
      ppuWin:setActiveLayerIndex(1)
    end

    currentRunner.ppuSelectWin = ppuWin
    currentRunner.ppuSelectionAnchor = { col = 4, row = 4 }
    currentRunner.ppuSelectionCorner = { col = 5, row = 5 }
  end)
  steps[#steps + 1] = pause("Observe added PPU regression windows", 0.45)

  steps[#steps + 1] = call("Refocus OAM toolbar window before PPU selection", function(_, currentApp, currentRunner)
    local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
    assert(currentRunner.toolbarFocusWin, "expected OAM toolbar focus window")
    currentApp.wm:setFocus(currentRunner.toolbarFocusWin)
    currentRunner.toolbarOffsetBeforePpuSelection = AppTopToolbarController.getContentOffsetY(currentApp)
  end)
  steps[#steps + 1] = pause("Observe docked multi-row toolbar", 0.4)

  appendClick(steps, "Select PPU frame tile after focus swap", function(h, _, currentRunner)
    local target = assert(currentRunner.ppuSelectionAnchor, "expected PPU selection anchor")
    return h:windowCellCenter(currentRunner.ppuSelectWin, target.col, target.row)
  end, {
    moveDuration = 0.08,
    postPause = 0.25,
  })

  steps[#steps + 1] = call("Assert PPU tile selection aligns with click", function(_, currentApp, currentRunner)
    local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
    local win = assert(currentRunner.ppuSelectWin, "expected PPU selection window")
    local target = assert(currentRunner.ppuSelectionAnchor, "expected PPU target")
    local col, row = win:getSelected()
    assert(col == target.col and row == target.row,
      string.format("expected selected PPU tile (%d,%d), got (%s,%s)",
        target.col, target.row, tostring(col), tostring(row)))
    assert(currentApp.wm:getFocus() == win, "expected PPU window to gain focus after tile click")
    assert(
      AppTopToolbarController.getContentOffsetY(currentApp) == currentRunner.toolbarOffsetBeforePpuSelection,
      "expected content offset to remain stable across focus swap"
    )
  end)
  steps[#steps + 1] = pause("Observe aligned PPU tile selection", 0.45)

  steps[#steps + 1] = call("Marquee select 2x2 block in PPU frame", function(currentHarness, _, currentRunner)
    local win = assert(currentRunner.ppuSelectWin, "expected PPU selection window")
    local start = assert(currentRunner.ppuSelectionAnchor, "expected marquee start")
    local finish = assert(currentRunner.ppuSelectionCorner, "expected marquee end")
    local x1, y1 = currentHarness:windowCellCenter(win, start.col, start.row)
    local x2, y2 = currentHarness:windowCellCenter(win, finish.col, finish.row)
    currentHarness:keyDown("lshift", { "lshift" })
    currentHarness:drag(x1, y1, x2, y2, {
      wait = false,
      steps = 6,
      dt = currentHarness.stepDt,
    })
    currentHarness:keyUp("lshift", { "lshift" })
  end)
  steps[#steps + 1] = pause("Observe PPU marquee selection", 0.45)
  steps[#steps + 1] = call("Assert PPU marquee selection alignment", function(_, _, currentRunner)
    local win = assert(currentRunner.ppuSelectWin, "expected PPU selection window")
    local layer = assert(win.layers and win.layers[1], "expected PPU tile layer")
    local selected = {}
    for idx, on in pairs(layer.multiTileSelection or {}) do
      if on then
        selected[#selected + 1] = idx
      end
    end
    assert(#selected == 4, string.format("expected 4 marquee-selected PPU tiles, got %d", #selected))
    local col, row = win:getSelected()
    local target = assert(currentRunner.ppuSelectionAnchor, "expected PPU target")
    assert(col == target.col and row == target.row,
      string.format("expected marquee anchor selection (%d,%d), got (%s,%s)",
        target.col, target.row, tostring(col), tostring(row)))
  end)
  steps[#steps + 1] = pause("Observe stable PPU selection after marquee", 0.65)

  return steps
end


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
