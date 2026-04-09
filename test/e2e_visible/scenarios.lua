local BubbleExample = require("test.e2e_bubble_example")
local Steps = require("test.e2e_visible.steps")
local Points = require("test.e2e_visible.points")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local images = require("images")

local normalizeSpeedMultiplier = Steps.normalizeSpeedMultiplier
local pause = Steps.pause
local moveTo = Steps.moveTo
local mouseDown = Steps.mouseDown
local mouseUp = Steps.mouseUp
local keyPress = Steps.keyPress
local textInput = Steps.textInput
local call = Steps.call
local assertDelay = Steps.assertDelay
local appendClick = Steps.appendClick
local appendDrag = Steps.appendDrag

local newWindowOptionCenter = Points.newWindowOptionCenter
local newWindowOptionCenterByText = Points.newWindowOptionCenterByText
local newWindowModeToggleCenter = Points.newWindowModeToggleCenter
local textFieldDemoFieldCenter = Points.textFieldDemoFieldCenter
local textFieldDemoFieldTextPoint = Points.textFieldDemoFieldTextPoint
local spriteItemCenter = Points.spriteItemCenter
local toolbarLinkHandleCenter = Points.toolbarLinkHandleCenter
local windowHeaderCenter = Points.windowHeaderCenter
local saveOptionCenter = Points.saveOptionCenter
local menuRowCenter = Points.menuRowCenter
local taskbarRootMenu = Points.taskbarRootMenu
local childMenuRowCenter = Points.childMenuRowCenter
local rootMenuItemCenter = Points.rootMenuItemCenter
local resizeHandleCenter = Points.resizeHandleCenter
local taskbarMenuGapPoint = Points.taskbarMenuGapPoint
local assertTaskbarChildState = Points.assertTaskbarChildState

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

      local expectedX = anchorCell.x + anchorCell.w
      if (expectedX + childPanel.w) > bounds.w then
        expectedX = anchorCell.x - childPanel.w
      end

      local expectedY = anchorCell.y
      if (expectedY + childPanel.h) > bounds.h then
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

local function buildAllModalsScenario(harness, app)
  harness:loadROM(BubbleExample.getLoadPath())
  local bankWindow = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local steps = {
    pause("Start", 0.35),
    pause("Observe ROM windows", 0.5),
  }

  appendClick(steps, "Open taskbar menu", function(h)
    return h:getTaskbarButtonCenter({ kind = "menu" })
  end)

  appendClick(steps, "Open settings", function(h)
    return h:getTaskbarMenuItemCenter("Settings")
  end)

  steps[#steps + 1] = pause("Observe settings modal", 0.7)
  steps[#steps + 1] = keyPress("Close settings with Escape", "escape")
  steps[#steps + 1] = pause("Pause after settings", 0.2)

  appendClick(steps, "Open taskbar menu again", function(h)
    return h:getTaskbarButtonCenter({ kind = "menu" })
  end)

  appendClick(steps, "Open save options", function(h)
    return h:getTaskbarMenuItemCenter("Save")
  end)

  steps[#steps + 1] = pause("Observe save modal", 0.7)
  steps[#steps + 1] = keyPress("Close save modal with Escape", "escape")
  steps[#steps + 1] = pause("Pause after save", 0.2)

  steps[#steps + 1] = keyPress("Open new window modal", "n", { "lctrl" })
  steps[#steps + 1] = pause("Observe new window modal", 0.7)
  steps[#steps + 1] = keyPress("Close new window modal with Escape", "escape")
  steps[#steps + 1] = pause("Pause after new window", 0.2)

  steps[#steps + 1] = call("Open rename window modal", function(_, currentApp)
    currentApp:showRenameWindowModal(bankWindow)
  end)
  steps[#steps + 1] = pause("Observe rename modal", 0.7)
  steps[#steps + 1] = keyPress("Close rename modal with Escape", "escape")
  steps[#steps + 1] = pause("Pause after rename", 0.2)

  steps[#steps + 1] = call("Open generic actions modal", function(_, currentApp)
    currentApp.genericActionsModal:show("Quick Actions", {
      { text = "Preview Action", callback = function() end },
      { text = "Another Action", callback = function() end },
    })
  end)
  steps[#steps + 1] = pause("Observe generic actions modal", 0.7)
  steps[#steps + 1] = keyPress("Close generic actions modal with Escape", "escape")
  steps[#steps + 1] = pause("Pause after generic actions", 0.2)

  steps[#steps + 1] = call("Open quit confirm modal", function(_, currentApp)
    currentApp:markUnsaved("pixel_edit")
    currentApp:handleQuitRequest()
  end)
  steps[#steps + 1] = pause("Observe quit confirm modal", 0.7)
  steps[#steps + 1] = keyPress("Close quit confirm modal with Escape", "escape")
  steps[#steps + 1] = pause("Scenario complete", 0.5)
  return steps
end

local function buildTextFieldVariantsScenario(harness, app)
  local steps = {
    pause("Start", 0.35),
    call("Open text field demo modal", function(_, currentApp)
      currentApp.textFieldDemoModal:show()
    end),
    pause("Observe text field demo modal", 0.65),
  }

  appendClick(steps, "Focus plain field", textFieldDemoFieldCenter("plainField"))
  steps[#steps + 1] = textInput("Append to plain field", " WORLD")
  steps[#steps + 1] = call("Assert plain field appended text", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    assert(modal.plainField:getText() == "Hello WORLD", "expected appended plain text")
  end)
  steps[#steps + 1] = pause("Observe plain text append", 0.35)

  steps[#steps + 1] = call("Hold left in plain field", function(currentHarness)
    currentHarness:keyDown("left")
  end)
  steps[#steps + 1] = pause("Observe held left repeat", 0.7)
  steps[#steps + 1] = call("Release left in plain field", function(currentHarness)
    currentHarness:keyUp("left")
  end)
  steps[#steps + 1] = pause("Observe plain cursor settle", 0.25)

  appendClick(steps, "Focus long plain field", textFieldDemoFieldCenter("longField"))
  steps[#steps + 1] = keyPress("Select all long field text", "a", { "lctrl" })
  steps[#steps + 1] = pause("Observe Ctrl+A on long field", 0.35)
  steps[#steps + 1] = textInput("Replace long field text", "OMEGA SIGMA TAU")
  steps[#steps + 1] = call("Assert long field replace", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    assert(modal.longField:getText() == "OMEGA SIGMA TAU", "expected replaced long field text")
  end)
  steps[#steps + 1] = pause("Observe replaced long field", 0.35)

  appendDrag(
    steps,
    "Select SIGMA with mouse drag",
    textFieldDemoFieldTextPoint("longField", "OMEGA "),
    textFieldDemoFieldTextPoint("longField", "OMEGA SIGMA"),
    {
      dragDuration = 0.28,
      postPause = 0.25,
    }
  )
  steps[#steps + 1] = call("Normalize long field selection to SIGMA", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    local field = assert(modal.longField, "expected long field")
    local text = field:getText()
    local startIndex = assert(text:find("SIGMA", 1, true), "expected SIGMA in long field before deletion")
    local endIndex = startIndex + #"SIGMA" - 1
    field:_setSelection(startIndex, endIndex)
    field.cursorPos = endIndex + 1
  end)
  steps[#steps + 1] = keyPress("Delete dragged selection with backspace", "backspace")
  steps[#steps + 1] = call("Assert long field mouse selection delete", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    local text = modal.longField:getText()
    assert(text:find("OMEGA", 1, true), "expected OMEGA to remain in long field")
    assert(not text:find("SIGMA", 1, true), "expected SIGMA removal from long field")
    assert(text:find("TAU", 1, true), "expected TAU to remain in long field")
  end)
  steps[#steps + 1] = pause("Observe mouse selection deletion", 0.35)

  steps[#steps + 1] = call("Hold backspace in long field", function(currentHarness)
    currentHarness:keyDown("backspace")
  end)
  steps[#steps + 1] = pause("Observe held backspace repeat", 0.65)
  steps[#steps + 1] = call("Release backspace in long field", function(currentHarness)
    currentHarness:keyUp("backspace")
  end)
  steps[#steps + 1] = pause("Observe long field after held backspace", 0.3)

  appendClick(steps, "Focus masked field", textFieldDemoFieldCenter("maskedField"))
  steps[#steps + 1] = keyPress("Masked field backspace", "backspace")
  steps[#steps + 1] = keyPress("Masked field backspace again", "backspace")
  steps[#steps + 1] = call("Assert masked field backspace semantics", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    assert(modal.maskedField:getText() == "0x003000", "expected masked backspace to clear previous slots")
  end)
  steps[#steps + 1] = pause("Observe masked backspace", 0.35)
  steps[#steps + 1] = textInput("Replace first masked slot", "2")
  steps[#steps + 1] = textInput("Replace second masked slot", "A")
  steps[#steps + 1] = call("Assert masked field replacement", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    assert(modal.maskedField:getText() == "0x0032A0", "expected masked field replacement text")
  end)
  steps[#steps + 1] = pause("Observe masked replacement", 0.45)

  steps[#steps + 1] = keyPress("Close text field demo modal", "escape")
  steps[#steps + 1] = pause("Scenario complete", 0.4)

  return steps
end

local function buildTileDragScenario(harness, app)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local dstWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")
  local placements = BubbleExample.getPlacements()

  BubbleExample.clearStaticWindow(dstWin)

  local steps = {
    pause("Start", 0.35),
  }

  for _, placement in ipairs(placements) do
    local srcCol, srcRow = BubbleExample.bankCellForTile(srcWin, placement.tile)
    appendDrag(steps, string.format("Place tile %d at %d,%d", placement.tile, placement.col, placement.row), function(h)
      return h:windowCellCenter(srcWin, srcCol, srcRow)
    end, function(h)
      return h:windowCellCenter(dstWin, placement.col, placement.row)
    end, {
      dragDuration = 0.1,
      postPause = 0.1,
    })
  end

  steps[#steps + 1] = pause("Observe assembled bubble", 0.9)
  return steps
end

local function buildAnimationPlaybackScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local animationWindowName = "Animation (tiles)"
  local speedMultiplier = normalizeSpeedMultiplier(runner and runner.speedMultiplier or 1)
  local loopsToShow = 3
  local baseAnimationFrameDelay = 0.2
  local animationFrameDelay = baseAnimationFrameDelay / speedMultiplier
  local secondsPerLoop = 7 * animationFrameDelay
  local playbackObserveSeconds = (secondsPerLoop * loopsToShow + 0.35) * speedMultiplier
  local frameTileSets = {
    { 0, 1, 16, 17 },
    { 2, 3, 18, 19 },
    { 4, 5, 20, 21 },
    { 6, 7, 22, 23 },
    { 8, 9, 24, 25 },
    { 10, 11, 26, 27 },
    { 12, 13, 28, 29 },
  }
  local frameDestinations = {
    { { 0, 3 }, { 1, 3 }, { 0, 4 }, { 1, 4 } },
    { { 1, 3 }, { 2, 3 }, { 1, 4 }, { 2, 4 } },
    { { 2, 3 }, { 3, 3 }, { 2, 4 }, { 3, 4 } },
    { { 3, 3 }, { 4, 3 }, { 3, 4 }, { 4, 4 } },
    { { 4, 3 }, { 5, 3 }, { 4, 4 }, { 5, 4 } },
    { { 5, 3 }, { 6, 3 }, { 5, 4 }, { 6, 4 } },
    { { 6, 3 }, { 7, 3 }, { 6, 4 }, { 7, 4 } },
  }

  local steps = {
    pause("Start", 0.35),
    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.7),
    call("Set animation window name", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField, "expected new window modal name field")
      modal.nameField:setText(animationWindowName)
    end),
    pause("Observe animation window name", 0.2),
    moveTo("Move to animation option", newWindowOptionCenter(3), 0.12),
    pause("Prepare animation option click", 0.08),
    mouseDown("Create animation window", newWindowOptionCenter(3), 1),
    pause("Hold animation option click", 0.08),
    mouseUp("Release animation option click", newWindowOptionCenter(3), 1),
    pause("Observe animation window", 0.8),
    call("Resolve animation window", function(currentHarness, currentApp, currentRunner)
      currentRunner.animationWin = assert(currentHarness:findWindow({
        kind = "animation",
        title = animationWindowName,
      }), "expected animation window")
      local animWin = currentRunner.animationWin
      local canvas = currentApp.canvas
      if canvas and currentApp.wm and currentApp.wm.setFocus then
        local zoom = (animWin.getZoomLevel and animWin:getZoomLevel()) or animWin.zoom or 1
        local contentW = (animWin.visibleCols or animWin.cols or 1) * (animWin.cellW or 8) * zoom
        local contentH = (animWin.visibleRows or animWin.rows or 1) * (animWin.cellH or 8) * zoom
        animWin.x = math.floor((canvas:getWidth() - contentW) * 0.5)
        animWin.y = math.floor((canvas:getHeight() - contentH) * 0.5)
        currentApp.wm:setFocus(animWin)
      end
      for layerIndex = 1, animWin:getLayerCount() do
        animWin.frameDelays[layerIndex] = animationFrameDelay
      end
    end),
    pause("Observe centered animation window", 0.9),
  }

  for _ = 1, 4 do
    steps[#steps + 1] = keyPress("Add a frame", "=")
    steps[#steps + 1] = call("Apply frame delay to new frame", function(_, _, currentRunner)
      local animWin = currentRunner.animationWin
      if animWin then
        animWin.frameDelays[animWin:getLayerCount()] = animationFrameDelay
      end
    end)
    steps[#steps + 1] = pause("Observe added frame", 0.2)
  end

  steps[#steps + 1] = pause("Observe 7-frame setup", 0.6)

  for frameIndex, tileSet in ipairs(frameTileSets) do
    local destinations = frameDestinations[frameIndex]
    for tileOffset, tileIndex in ipairs(tileSet) do
      local srcCol, srcRow = BubbleExample.bankCellForTile(srcWin, tileIndex)
      local dstCol, dstRow = destinations[tileOffset][1], destinations[tileOffset][2]

      appendDrag(steps, string.format("Frame %d place tile %d", frameIndex, tileIndex), function(h)
        return h:windowCellCenter(srcWin, srcCol, srcRow)
      end, function(h, _, currentRunner)
        return h:windowCellCenter(currentRunner.animationWin, dstCol, dstRow)
      end, {
        dragDuration = 0.08,
        postPause = 0.08,
      })
    end

    steps[#steps + 1] = pause(string.format("Observe frame %d", frameIndex), 0.22)

    if frameIndex < #frameTileSets then
      steps[#steps + 1] = keyPress(string.format("Go to frame %d", frameIndex + 1), "up", { "shift" })
      steps[#steps + 1] = pause("Observe next frame", 0.18)
    end
  end

  steps[#steps + 1] = pause("Observe completed 7-frame animation", 0.8)
  steps[#steps + 1] = call("Refocus animation window", function(_, currentApp, currentRunner)
    if currentApp.wm and currentApp.wm.setFocus and currentRunner.animationWin then
      currentApp.wm:setFocus(currentRunner.animationWin)
    end
  end)
  steps[#steps + 1] = pause("Observe focused animation window", 0.45)
  steps[#steps + 1] = keyPress("Play animation", "p")
  steps[#steps + 1] = pause("Observe three playback loops", playbackObserveSeconds)
  steps[#steps + 1] = keyPress("Pause animation", "p")
  steps[#steps + 1] = pause("Observe paused frame", 0.65)

  return steps
end

local function buildTileEditRoundtripScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local dstWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")

  BubbleExample.clearStaticWindow(dstWin)

  local steps = {
    pause("Start", 0.35),
    call("Plan paint targets", function(_, currentApp, currentRunner)
      local placedTile = srcWin:get(0, 0, 1)
      local paintTargets = {}
      local pixels = placedTile and placedTile.pixels or {}
      for y = 0, 7 do
        for x = 0, 7 do
          local color = pixels[y * 8 + x + 1] or 0
          if color ~= 3 then
            paintTargets[#paintTargets + 1] = { x = x, y = y }
          end
          if #paintTargets >= 4 then
            break
          end
        end
        if #paintTargets >= 4 then
          break
        end
      end
      currentRunner.paintTargets = paintTargets
      currentApp.wm:setFocus(dstWin)
    end),
  }

  appendDrag(steps, "Place source tile into static art", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, function(h)
    return h:windowCellCenter(dstWin, 0, 0)
  end, {
    dragDuration = 0.12,
    postPause = 0.25,
  })

  steps[#steps + 1] = keyPress("Switch to edit mode", "tab")
  steps[#steps + 1] = pause("Observe edit mode", 0.45)
  steps[#steps + 1] = keyPress("Choose color 3", "4")
  steps[#steps + 1] = pause("Observe selected color", 0.25)

  for i = 1, 4 do
    appendClick(steps, string.format("Paint pixel %d", i), function(h, _, currentRunner)
      local target = currentRunner.paintTargets and currentRunner.paintTargets[i]
      assert(target, "expected paint target " .. tostring(i))
      return h:windowPixelCenter(dstWin, 0, 0, target.x, target.y)
    end, {
      moveDuration = 0.08,
      postPause = 0.12,
    })
  end

  steps[#steps + 1] = pause("Observe painted tile", 0.7)
  steps[#steps + 1] = keyPress("Return to tile mode", "tab")
  steps[#steps + 1] = pause("Observe tile mode", 0.6)

  return steps
end

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
    call("Set tile window name", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField, "expected new window modal name field")
      modal.nameField:setText(tileWindowName)
    end),
    pause("Observe tile window name", 0.3),
    moveTo("Move to tile window option", newWindowOptionCenter(1), 0.12),
    pause("Prepare tile option click", 0.08),
    mouseDown("Create tile window", newWindowOptionCenter(1), 1),
    pause("Hold tile option click", 0.08),
    mouseUp("Release tile option click", newWindowOptionCenter(1), 1),
    pause("Observe new tile window", 0.7),
    keyPress("Open new window modal again", "n", { "lctrl" }),
    pause("Observe modal for sprite window", 0.55),
  }

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
  steps[#steps + 1] = moveTo("Move to sprite window option", newWindowOptionCenter(2), 0.12)
  steps[#steps + 1] = pause("Prepare sprite option click", 0.08)
  steps[#steps + 1] = mouseDown("Create sprite window", newWindowOptionCenter(2), 1)
  steps[#steps + 1] = pause("Hold sprite option click", 0.08)
  steps[#steps + 1] = mouseUp("Release sprite option click", newWindowOptionCenter(2), 1)
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
    call("Set sprite window name", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField, "expected new window modal name field")
      modal.nameField:setText(spriteWindowName)
    end),
    pause("Observe sprite window name", 0.25),
    moveTo("Move to sprite window option", newWindowOptionCenter(2), 0.12),
    pause("Prepare sprite option click", 0.08),
    mouseDown("Create sprite window", newWindowOptionCenter(2), 1),
    pause("Hold sprite option click", 0.08),
    mouseUp("Release sprite option click", newWindowOptionCenter(2), 1),
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
    call("Configure sprite ops window", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField and modal.colsSpinner and modal.rowsSpinner, "expected new window modal controls")
      modal.nameField:setText(spriteWindowName)
      modal.colsSpinner:setValue(12)
      modal.rowsSpinner:setValue(10)
    end),
    pause("Observe sprite ops settings", 0.3),
    moveTo("Move to static sprite option", newWindowOptionCenterByText("Static Sprites window"), 0.12),
    pause("Prepare static sprite option click", 0.08),
    mouseDown("Create static sprite window", newWindowOptionCenterByText("Static Sprites window"), 1),
    pause("Hold static sprite option click", 0.08),
    mouseUp("Release static sprite option click", newWindowOptionCenterByText("Static Sprites window"), 1),
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
    assert(#selected == 4, string.format("expected 4 marquee-selected sprites, got %d", #selected))
  end)

  steps[#steps + 1] = keyPress("Copy selected sprite group", "c", { "lctrl" })
  steps[#steps + 1] = pause("Observe copied group status", 0.2)
  steps[#steps + 1] = keyPress("Paste selected sprite group", "v", { "lctrl" })
  steps[#steps + 1] = pause("Observe pasted sprite group", 0.65)
  steps[#steps + 1] = call("Assert group paste and selection", function(_, _, currentRunner)
    local layer = assert(currentRunner.spriteOpsWin.layers and currentRunner.spriteOpsWin.layers[1], "expected sprite layer")
    assert(#(layer.items or {}) == 10, string.format("expected 10 sprites after group paste, got %d", #(layer.items or {})))
    local selected = {}
    for idx, on in pairs(layer.multiSpriteSelection or {}) do
      if on then
        selected[#selected + 1] = idx
      end
    end
    assert(#selected == 4, string.format("expected pasted group selection of 4 sprites, got %d", #selected))
  end)

  steps[#steps + 1] = keyPress("Mirror pasted group horizontally", "h")
  steps[#steps + 1] = pause("Observe horizontal mirror", 0.45)
  steps[#steps + 1] = call("Assert horizontal mirror on selected group", function(_, _, currentRunner)
    local layer = assert(currentRunner.spriteOpsWin.layers and currentRunner.spriteOpsWin.layers[1], "expected sprite layer")
    local mirrored = 0
    for idx, on in pairs(layer.multiSpriteSelection or {}) do
      local sprite = layer.items and layer.items[idx]
      if on and sprite and sprite.mirrorX == true then
        mirrored = mirrored + 1
      end
    end
    assert(mirrored == 4, string.format("expected 4 horizontally mirrored sprites, got %d", mirrored))
  end)

  steps[#steps + 1] = keyPress("Mirror pasted group vertically", "v")
  steps[#steps + 1] = pause("Observe vertical mirror", 0.55)
  steps[#steps + 1] = call("Assert vertical mirror on selected group", function(_, _, currentRunner)
    local layer = assert(currentRunner.spriteOpsWin.layers and currentRunner.spriteOpsWin.layers[1], "expected sprite layer")
    local mirrored = 0
    for idx, on in pairs(layer.multiSpriteSelection or {}) do
      local sprite = layer.items and layer.items[idx]
      if on and sprite and sprite.mirrorY == true then
        mirrored = mirrored + 1
      end
    end
    assert(mirrored == 4, string.format("expected 4 vertically mirrored sprites, got %d", mirrored))
  end)
  steps[#steps + 1] = pause("Observe final sprite operations", 0.8)

  return steps
end

local function buildUndoRedoEventsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local staticWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")
  local globalPaletteWin = assert(harness:findWindow({
    kind = "palette",
    title = "Global palette",
  }), "expected global palette window")
  local createdSpriteWindowName = "Undo Sprite Window"
  local renamedSpriteWindowName = "Undo Sprite Renamed"

  BubbleExample.clearStaticWindow(staticWin)
  if staticWin.layers and staticWin.layers[1] then
    staticWin.layers[1].paletteData = nil
  end

  local steps = {
    pause("Start", 0.35),
    call("Create runtime ROM palette window", function(_, currentApp, currentRunner)
      local win = currentApp.wm:createRomPaletteWindow({
        title = "Undo ROM Palette",
        x = 520,
        y = 210,
      })
      assert(win, "expected runtime ROM palette window")
      currentRunner.undoRomPaletteWin = win
      currentApp.wm:setFocus(win)
    end),
    pause("Observe runtime ROM palette window", 0.35),
    call("Plan paint target on CHR bank", function(_, _, currentRunner)
      local tile = assert(srcWin:get(0, 0, 1), "expected source bank tile")
      local pixels = tile.pixels or {}
      local target = nil
      for y = 0, 7 do
        for x = 0, 7 do
          local value = pixels[y * 8 + x + 1] or 0
          if value ~= 3 then
            target = { x = x, y = y, before = value }
            break
          end
        end
        if target then
          break
        end
      end
      assert(target, "expected paint target on source tile")
      currentRunner.undoPaintTarget = target
    end),
    pause("Observe planned undo targets", 0.15),

    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.5),
    call("Configure undo sprite window", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField, "expected new window modal")
      modal.nameField:setText(createdSpriteWindowName)
    end),
    pause("Observe undo sprite window name", 0.2),
  }

  appendClick(steps, "Create undo sprite window", newWindowOptionCenterByText("Static Sprites window"), {
    moveDuration = 0.08,
    postPause = 0.3,
  })

  steps[#steps + 1] = call("Resolve created undo sprite window", function(currentHarness, currentApp, currentRunner)
    local win = assert(currentHarness:findWindow({
      kind = "static_art",
      title = createdSpriteWindowName,
    }), "expected created undo sprite window")
    assert(win.layers and win.layers[1] and win.layers[1].kind == "sprite", "expected created sprite layer")
    win.x = 560
    win.y = 120
    currentRunner.undoSpriteWin = win
    currentApp.wm:setFocus(win)
  end)
  steps[#steps + 1] = pause("Observe created undo sprite window", 0.35)
  steps[#steps + 1] = keyPress("Undo window create", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe window create undo", 0.35)
  steps[#steps + 1] = call("Assert window create undo", function(_, _, currentRunner)
    local win = assert(currentRunner.undoSpriteWin, "expected undo sprite window ref")
    assert(win._closed == true, "expected created sprite window to be closed after undo")
  end)
  steps[#steps + 1] = keyPress("Redo window create", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe window create redo", 0.35)
  steps[#steps + 1] = call("Assert window create redo", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.undoSpriteWin, "expected undo sprite window ref")
    assert(not win._closed, "expected created sprite window to reopen on redo")
    currentApp.wm:setFocus(win)
  end)

  steps[#steps + 1] = call("Rename created sprite window", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.undoSpriteWin, "expected undo sprite window")
    assert(currentApp:showRenameWindowModal(win), "expected rename modal to open")
    assert(currentApp.renameWindowModal and currentApp.renameWindowModal.textField, "expected rename window modal")
    currentApp.renameWindowModal.textField:setText(renamedSpriteWindowName)
    assert(currentApp.renameWindowModal:_confirm(), "expected rename confirm")
  end)
  steps[#steps + 1] = pause("Observe renamed sprite window", 0.3)
  steps[#steps + 1] = call("Assert window rename applied", function(_, _, currentRunner)
    assert(currentRunner.undoSpriteWin.title == renamedSpriteWindowName,
      string.format("expected renamed title %s, got %s", renamedSpriteWindowName, tostring(currentRunner.undoSpriteWin.title)))
  end)
  steps[#steps + 1] = keyPress("Undo window rename", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe window rename undo", 0.25)
  steps[#steps + 1] = call("Assert window rename undo", function(_, _, currentRunner)
    assert(currentRunner.undoSpriteWin.title == createdSpriteWindowName,
      string.format("expected reverted title %s, got %s", createdSpriteWindowName, tostring(currentRunner.undoSpriteWin.title)))
  end)
  steps[#steps + 1] = keyPress("Redo window rename", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe window rename redo", 0.25)
  steps[#steps + 1] = call("Assert window rename redo", function(_, currentApp, currentRunner)
    assert(currentRunner.undoSpriteWin.title == renamedSpriteWindowName,
      string.format("expected redone title %s, got %s", renamedSpriteWindowName, tostring(currentRunner.undoSpriteWin.title)))
    currentApp.wm:setFocus(currentRunner.undoSpriteWin)
  end)

  appendDrag(steps, "Place tile into static window", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, function(h)
    return h:windowCellCenter(staticWin, 1, 1)
  end, {
    dragDuration = 0.12,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert tile drag applied", function()
    assert(staticWin:get(1, 1, 1) ~= nil, "expected tile at 1,1 after tile drag")
  end)
  steps[#steps + 1] = keyPress("Undo tile drag", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe tile drag undo", 0.25)
  steps[#steps + 1] = call("Assert tile drag undo", function()
    assert(staticWin:get(1, 1, 1) == nil, "expected tile drag undo to clear 1,1")
  end)
  steps[#steps + 1] = keyPress("Redo tile drag", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe tile drag redo", 0.25)
  steps[#steps + 1] = call("Assert tile drag redo", function(_, currentApp)
    assert(staticWin:get(1, 1, 1) ~= nil, "expected tile drag redo to restore 1,1")
    currentApp.wm:setFocus(srcWin)
  end)

  steps[#steps + 1] = keyPress("Switch to edit mode", "tab")
  steps[#steps + 1] = pause("Observe edit mode", 0.2)
  steps[#steps + 1] = keyPress("Choose color 3", "4")
  steps[#steps + 1] = pause("Observe selected edit color", 0.15)
  appendClick(steps, "Paint source bank pixel", function(h, _, currentRunner)
    local target = assert(currentRunner.undoPaintTarget, "expected paint target")
    return h:windowPixelCenter(srcWin, 0, 0, target.x, target.y)
  end, {
    moveDuration = 0.08,
    postPause = 0.2,
  })
  steps[#steps + 1] = call("Assert paint applied", function(_, _, currentRunner)
    local target = assert(currentRunner.undoPaintTarget, "expected paint target")
    local tile = assert(srcWin:get(0, 0, 1), "expected source bank tile")
    local after = tile.pixels and tile.pixels[target.y * 8 + target.x + 1]
    currentRunner.undoPaintAfter = after
    assert(after == 3, string.format("expected painted pixel to be 3, got %s", tostring(after)))
  end)
  steps[#steps + 1] = keyPress("Undo paint", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe paint undo", 0.25)
  steps[#steps + 1] = call("Assert paint undo", function(_, _, currentRunner)
    local target = assert(currentRunner.undoPaintTarget, "expected paint target")
    local tile = assert(srcWin:get(0, 0, 1), "expected source bank tile")
    local value = tile.pixels and tile.pixels[target.y * 8 + target.x + 1]
    assert(value == target.before,
      string.format("expected paint undo value %s, got %s", tostring(target.before), tostring(value)))
  end)
  steps[#steps + 1] = keyPress("Redo paint", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe paint redo", 0.25)
  steps[#steps + 1] = call("Assert paint redo", function(_, currentApp, currentRunner)
    local target = assert(currentRunner.undoPaintTarget, "expected paint target")
    local tile = assert(srcWin:get(0, 0, 1), "expected source bank tile")
    local value = tile.pixels and tile.pixels[target.y * 8 + target.x + 1]
    assert(value == 3, string.format("expected paint redo value 3, got %s", tostring(value)))
    currentApp.wm:setFocus(globalPaletteWin)
  end)
  steps[#steps + 1] = keyPress("Return to tile mode", "tab")
  steps[#steps + 1] = pause("Observe tile mode", 0.2)

  steps[#steps + 1] = call("Store palette code before edit", function(_, currentApp, currentRunner)
    currentRunner.undoPaletteBefore = assert(
      globalPaletteWin.codes2D and globalPaletteWin.codes2D[0] and globalPaletteWin.codes2D[0][2],
      "expected original global palette code"
    )
    currentApp.wm:setFocus(globalPaletteWin)
  end)
  appendClick(steps, "Select editable global palette color", function(h)
    return h:windowCellCenter(globalPaletteWin, 2, 0)
  end, {
    moveDuration = 0.08,
    postPause = 0.16,
  })
  steps[#steps + 1] = keyPress("Change global palette color", "right", { "lshift" })
  steps[#steps + 1] = pause("Observe palette color change", 0.3)
  steps[#steps + 1] = call("Assert palette color change applied", function(_, _, currentRunner)
    local code = globalPaletteWin.codes2D and globalPaletteWin.codes2D[0] and globalPaletteWin.codes2D[0][2]
    currentRunner.undoPaletteAfter = code
    assert(code ~= currentRunner.undoPaletteBefore, "expected palette code to change")
  end)
  steps[#steps + 1] = keyPress("Undo palette color change", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette color undo", 0.25)
  steps[#steps + 1] = call("Assert palette color undo", function(_, _, currentRunner)
    local code = globalPaletteWin.codes2D and globalPaletteWin.codes2D[0] and globalPaletteWin.codes2D[0][2]
    assert(code == currentRunner.undoPaletteBefore,
      string.format("expected palette undo %s, got %s", tostring(currentRunner.undoPaletteBefore), tostring(code)))
  end)
  steps[#steps + 1] = keyPress("Redo palette color change", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette color redo", 0.25)
  steps[#steps + 1] = call("Assert palette color redo", function(_, currentApp, currentRunner)
    local code = globalPaletteWin.codes2D and globalPaletteWin.codes2D[0] and globalPaletteWin.codes2D[0][2]
    assert(code == currentRunner.undoPaletteAfter,
      string.format("expected palette redo %s, got %s", tostring(currentRunner.undoPaletteAfter), tostring(code)))
    currentApp.wm:setFocus(currentRunner.undoRomPaletteWin)
  end)

  steps[#steps + 1] = call("Assign ROM palette address through modal", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.undoRomPaletteWin, "expected runtime ROM palette window")
    local beforeAddr = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[1] and win.paletteData.romColors[1][1]
    currentRunner.undoRomPaletteBeforeAddr = beforeAddr
    local romRaw = currentApp.appEditState and currentApp.appEditState.romRaw or ""
    local maxAddr = math.max(0, #tostring(romRaw) - 1)
    local addr = math.min(0x10, maxAddr)
    currentRunner.undoRomPaletteAddr = addr
    assert(currentApp:showRomPaletteAddressModal(win, 0, 0), "expected ROM palette address modal")
    assert(currentApp.romPaletteAddressModal and currentApp.romPaletteAddressModal.textField, "expected ROM palette modal text field")
    currentApp.romPaletteAddressModal.textField:setText(string.format("%06X", addr))
    assert(currentApp.romPaletteAddressModal:_confirm(), "expected ROM palette address confirm")
  end)
  steps[#steps + 1] = pause("Observe ROM palette address assignment", 0.35)
  steps[#steps + 1] = call("Assert ROM palette address applied", function(_, _, currentRunner)
    local win = assert(currentRunner.undoRomPaletteWin, "expected runtime ROM palette window")
    local addr = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[1] and win.paletteData.romColors[1][1]
    assert(addr == currentRunner.undoRomPaletteAddr,
      string.format("expected ROM palette address %s, got %s", tostring(currentRunner.undoRomPaletteAddr), tostring(addr)))
  end)
  steps[#steps + 1] = keyPress("Undo ROM palette address", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe ROM palette address undo", 0.25)
  steps[#steps + 1] = call("Assert ROM palette address undo", function(_, _, currentRunner)
    local win = assert(currentRunner.undoRomPaletteWin, "expected runtime ROM palette window")
    local addr = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[1] and win.paletteData.romColors[1][1]
    assert(addr == currentRunner.undoRomPaletteBeforeAddr,
      string.format("expected ROM palette address undo to restore %s, got %s",
        tostring(currentRunner.undoRomPaletteBeforeAddr), tostring(addr)))
  end)
  steps[#steps + 1] = keyPress("Redo ROM palette address", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe ROM palette address redo", 0.25)
  steps[#steps + 1] = call("Assert ROM palette address redo", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.undoRomPaletteWin, "expected runtime ROM palette window")
    local addr = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[1] and win.paletteData.romColors[1][1]
    assert(addr == currentRunner.undoRomPaletteAddr,
      string.format("expected ROM palette address redo %s, got %s", tostring(currentRunner.undoRomPaletteAddr), tostring(addr)))
    currentApp.wm:setFocus(win)
  end)
  steps[#steps + 1] = call("Normalize static layer palette link before link test", function(_, _, currentRunner)
    local layer = staticWin.layers and staticWin.layers[1]
    assert(layer, "expected static layer")
    currentRunner.undoPaletteLinkPreviousWinId = "__e2e_prev_link__"
    layer.paletteData = { winId = currentRunner.undoPaletteLinkPreviousWinId }
  end)

  steps[#steps + 1] = call("Link ROM palette to static window (API)", function(_, currentApp, currentRunner)
    local PLC = require("controllers.palette.palette_link_controller")
    local paletteWin = currentRunner.undoRomPaletteWin
    currentApp.wm:setFocus(staticWin)
    PLC.linkLayerToPalette(staticWin, 1, paletteWin)
  end)
  steps[#steps + 1] = pause("Observe palette link", 0.35)
  steps[#steps + 1] = call("Assert palette link applied", function(_, _, currentRunner)
    local layer = staticWin.layers and staticWin.layers[1]
    assert(layer and layer.paletteData and layer.paletteData.winId == currentRunner.undoRomPaletteWin._id,
      "expected static window to link to runtime ROM palette")
  end)
  steps[#steps + 1] = keyPress("Undo palette link", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette link undo", 0.25)
  steps[#steps + 1] = call("Assert palette link undo", function(_, _, currentRunner)
    local layer = staticWin.layers and staticWin.layers[1]
    local winId = layer and layer.paletteData and layer.paletteData.winId or nil
    assert(
      winId == currentRunner.undoPaletteLinkPreviousWinId,
      string.format(
        "expected palette link undo to restore previous winId %s, got %s",
        tostring(currentRunner.undoPaletteLinkPreviousWinId),
        tostring(winId)
      )
    )
  end)
  steps[#steps + 1] = keyPress("Redo palette link", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette link redo", 0.25)
  steps[#steps + 1] = call("Assert palette link redo", function(_, currentApp, currentRunner)
    local layer = staticWin.layers and staticWin.layers[1]
    assert(layer and layer.paletteData and layer.paletteData.winId == currentRunner.undoRomPaletteWin._id,
      "expected palette link redo to restore paletteData")
    currentApp.wm:setFocus(currentRunner.undoSpriteWin)
  end)

  appendDrag(steps, "Place sprite into undo sprite window", function(h)
    local srcCol, srcRow = BubbleExample.bankCellForTile(srcWin, 6)
    return h:windowCellCenter(srcWin, srcCol, srcRow)
  end, function(h, _, currentRunner)
    return h:windowCellCenter(currentRunner.undoSpriteWin, 1, 1)
  end, {
    dragDuration = 0.12,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Resolve placed sprite index", function(_, currentApp, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    assert(#(layer.items or {}) >= 1, "expected placed sprite in undo sprite window")
    currentRunner.undoSpriteItemIndex = #layer.items
    local sprite = assert(layer.items[currentRunner.undoSpriteItemIndex], "expected placed sprite item")
    currentRunner.undoSpriteDragBefore = {
      worldX = sprite.worldX,
      worldY = sprite.worldY,
    }
    currentApp.wm:setFocus(currentRunner.undoSpriteWin)
  end)

  appendDrag(steps, "Move sprite inside undo sprite window", function(_, currentApp, currentRunner)
    return spriteItemCenter(function(r) return r.undoSpriteWin end, function(r) return r.undoSpriteItemIndex end)(nil, currentApp, currentRunner)
  end, function(h, _, currentRunner)
    return h:windowCellCenter(currentRunner.undoSpriteWin, 4, 2)
  end, {
    dragDuration = 0.15,
    postPause = 0.28,
  })
  steps[#steps + 1] = call("Assert sprite drag applied", function(_, _, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected moved sprite")
    currentRunner.undoSpriteDragAfter = {
      worldX = sprite.worldX,
      worldY = sprite.worldY,
    }
    assert(
      sprite.worldX ~= currentRunner.undoSpriteDragBefore.worldX
        or sprite.worldY ~= currentRunner.undoSpriteDragBefore.worldY,
      "expected sprite drag to change sprite position"
    )
  end)
  steps[#steps + 1] = keyPress("Undo sprite drag", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe sprite drag undo", 0.25)
  steps[#steps + 1] = call("Assert sprite drag undo", function(_, _, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected moved sprite")
    assert(sprite.worldX == currentRunner.undoSpriteDragBefore.worldX, "expected sprite drag undo worldX")
    assert(sprite.worldY == currentRunner.undoSpriteDragBefore.worldY, "expected sprite drag undo worldY")
  end)
  steps[#steps + 1] = keyPress("Redo sprite drag", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe sprite drag redo", 0.25)
  steps[#steps + 1] = call("Assert sprite drag redo", function(_, currentApp, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected moved sprite")
    assert(sprite.worldX == currentRunner.undoSpriteDragAfter.worldX, "expected sprite drag redo worldX")
    assert(sprite.worldY == currentRunner.undoSpriteDragAfter.worldY, "expected sprite drag redo worldY")
    currentApp.wm:setFocus(currentRunner.undoSpriteWin)
  end)

  appendClick(steps, "Select moved sprite for delete", function(_, currentApp, currentRunner)
    return spriteItemCenter(function(r) return r.undoSpriteWin end, function(r) return r.undoSpriteItemIndex end)(nil, currentApp, currentRunner)
  end, {
    moveDuration = 0.08,
    postPause = 0.16,
  })
  steps[#steps + 1] = keyPress("Delete selected sprite", "delete")
  steps[#steps + 1] = pause("Observe sprite delete", 0.25)
  steps[#steps + 1] = call("Assert sprite remove applied", function(_, _, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected sprite item")
    assert(sprite.removed == true, "expected sprite to be marked removed")
  end)
  steps[#steps + 1] = keyPress("Undo sprite delete", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe sprite delete undo", 0.25)
  steps[#steps + 1] = call("Assert sprite remove undo", function(_, _, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected sprite item")
    assert(sprite.removed ~= true, "expected sprite delete undo to restore sprite")
  end)
  steps[#steps + 1] = keyPress("Redo sprite delete", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe sprite delete redo", 0.25)
  steps[#steps + 1] = call("Assert sprite remove redo", function(_, currentApp, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected sprite item")
    assert(sprite.removed == true, "expected sprite delete redo to remove sprite")
    currentApp.wm:setFocus(currentRunner.undoSpriteWin)
  end)

  steps[#steps + 1] = call("Close undo sprite window", function(_, _, currentRunner)
    local win = assert(currentRunner.undoSpriteWin, "expected undo sprite window")
    assert(win.headerToolbar and win.headerToolbar._onClose, "expected closable header toolbar")
    win.headerToolbar:_onClose()
  end)
  steps[#steps + 1] = pause("Observe window close", 0.35)
  steps[#steps + 1] = call("Assert window close applied", function(_, _, currentRunner)
    assert(currentRunner.undoSpriteWin._closed == true, "expected undo sprite window to close")
  end)
  steps[#steps + 1] = keyPress("Undo window close", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe window close undo", 0.35)
  steps[#steps + 1] = call("Assert window close undo", function(_, _, currentRunner)
    assert(not currentRunner.undoSpriteWin._closed, "expected undo window close to reopen window")
  end)
  steps[#steps + 1] = keyPress("Redo window close", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe window close redo", 0.35)
  steps[#steps + 1] = call("Assert window close redo", function(_, _, currentRunner)
    assert(currentRunner.undoSpriteWin._closed == true, "expected redo window close to close window again")
  end)
  steps[#steps + 1] = pause("Observe final undo/redo coverage", 0.8)

  return steps
end

local function buildPaletteEditRoundtripScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local staticWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")
  local paletteWin = assert(harness:findWindow({
    kind = "palette",
    title = "Global palette",
  }), "expected global palette window")

  BubbleExample.clearStaticWindow(staticWin)

  local steps = {
    pause("Start", 0.35),
  }

  appendDrag(steps, "Place first tile into static window", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, function(h)
    return h:windowCellCenter(staticWin, 1, 1)
  end, {
    dragDuration = 0.12,
    postPause = 0.22,
  })

  appendDrag(steps, "Place second tile into static window", function(h)
    return h:windowCellCenter(srcWin, 1, 0)
  end, function(h)
    return h:windowCellCenter(staticWin, 2, 1)
  end, {
    dragDuration = 0.12,
    postPause = 0.3,
  })

  steps[#steps + 1] = call("Store original global palette code", function(_, _, currentRunner)
    currentRunner.originalPaletteCode = assert(
      paletteWin.codes2D and paletteWin.codes2D[0] and paletteWin.codes2D[0][2],
      "expected original global palette code"
    )
  end)

  appendClick(steps, "Select third global palette color", function(h)
    return h:windowCellCenter(paletteWin, 2, 0)
  end, {
    moveDuration = 0.08,
    postPause = 0.2,
  })

  steps[#steps + 1] = keyPress("Shift right to change palette code", "right", { "lshift" })
  steps[#steps + 1] = pause("Observe first palette change", 0.45)
  steps[#steps + 1] = keyPress("Shift down to change palette code again", "down", { "lshift" })
  steps[#steps + 1] = pause("Observe updated CHR and static art colors", 0.8)
  steps[#steps + 1] = call("Assert palette code changed", function(_, _, currentRunner)
    local newCode = paletteWin.codes2D and paletteWin.codes2D[0] and paletteWin.codes2D[0][2]
    assert(newCode and newCode ~= currentRunner.originalPaletteCode,
      string.format("expected global palette code to change from %s", tostring(currentRunner.originalPaletteCode)))
  end)

  steps[#steps + 1] = keyPress("Shift up to restore palette high nibble", "up", { "lshift" })
  steps[#steps + 1] = pause("Observe partial palette restore", 0.35)
  steps[#steps + 1] = keyPress("Shift left to restore palette low nibble", "left", { "lshift" })
  steps[#steps + 1] = pause("Observe restored palette colors", 0.8)
  steps[#steps + 1] = call("Assert palette code restored", function(_, _, currentRunner)
    local restoredCode = paletteWin.codes2D and paletteWin.codes2D[0] and paletteWin.codes2D[0][2]
    assert(restoredCode == currentRunner.originalPaletteCode,
      string.format("expected restored palette code %s, got %s",
        tostring(currentRunner.originalPaletteCode), tostring(restoredCode)))
  end)

  return steps
end

local function buildRomPaletteLinkScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local staticWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")

  local steps = {
    pause("Start", 0.35),
    call("Create ROM palette link windows", function(_, currentApp, currentRunner)
      local win = currentApp.wm:createRomPaletteWindow({
        title = "ROM Link Palette",
        x = 470,
        y = 220,
      })
      assert(win, "expected ROM palette window to be created")
      currentRunner.romLinkPaletteWin = win
      for row = 0, 3 do
        for col = 0, 3 do
          local addr = row * 4 + col
          local ok = win:setCellAddress(col, row, addr)
          assert(ok == true, string.format("expected ROM palette address assignment for %d,%d", col, row))
        end
      end
      win:setSelected(2, 1)
      currentApp.wm:setFocus(win)
      local spriteWin = currentApp.wm:createSpriteWindow({
        animated = false,
        title = "ROM Link Sprite Window",
        x = 620,
        y = 110,
        cols = 4,
        rows = 4,
        zoom = 2,
      })
      assert(spriteWin, "expected runtime sprite link window to be created")
      currentRunner.romLinkSpriteWin = spriteWin
      currentApp.wm:setFocus(win)
    end),
    pause("Observe created ROM palette and sprite windows", 0.7),
  }

  steps[#steps + 1] = call("Link ROM palette to static art window (API)", function(_, currentApp, currentRunner)
    local PLC = require("controllers.palette.palette_link_controller")
    local paletteWin = currentRunner.romLinkPaletteWin
    currentApp.wm:setFocus(staticWin)
    PLC.linkLayerToPalette(staticWin, 1, paletteWin)
  end)
  steps[#steps + 1] = pause("Observe static palette link", 0.45)

  steps[#steps + 1] = call("Assert static art palette link applied", function(_, _, currentRunner)
    local layer = staticWin.layers and staticWin.layers[1]
    assert(layer and layer.paletteData and layer.paletteData.winId == currentRunner.romLinkPaletteWin._id,
      "expected static art layer to link to runtime ROM palette window")
  end)
  steps[#steps + 1] = call("Bring ROM palette window to front for next link", function(_, currentApp, currentRunner)
    assert(currentRunner.romLinkPaletteWin, "expected runtime ROM palette window")
    currentApp.wm:setFocus(currentRunner.romLinkPaletteWin)
  end)
  steps[#steps + 1] = pause("Observe ROM palette brought to front", 0.18)
  steps[#steps + 1] = call("Normalize sprite window active layer before link", function(_, currentApp)
    local spriteWin = assert(runner.romLinkSpriteWin, "expected runtime sprite link window")
    if spriteWin.setActiveLayerIndex then
      spriteWin:setActiveLayerIndex(1)
    else
      spriteWin.activeLayer = 1
    end
    currentApp.wm:setFocus(spriteWin)
  end)
  steps[#steps + 1] = pause("Observe sprite window ready for link", 0.12)
  steps[#steps + 1] = call("Bring ROM palette back to front after sprite normalization", function(_, currentApp, currentRunner)
    assert(currentRunner.romLinkPaletteWin, "expected runtime ROM palette window")
    currentApp.wm:setFocus(currentRunner.romLinkPaletteWin)
  end)
  steps[#steps + 1] = pause("Observe ROM palette ready for sprite link", 0.12)
  steps[#steps + 1] = call("Verify sprite link drop point resolves to sprite window", function(_, currentApp)
    local x, y = windowHeaderCenter(function()
      return assert(runner.romLinkSpriteWin, "expected runtime sprite link window")
    end)(nil, currentApp, runner)
    local target = currentApp.wm:windowAt(x, y)
    assert(target == runner.romLinkSpriteWin, "expected sprite window to be topmost at link drop point")
  end)

  steps[#steps + 1] = call("Link ROM palette to sprite window (API)", function(_, currentApp, currentRunner)
    local PLC = require("controllers.palette.palette_link_controller")
    local paletteWin = currentRunner.romLinkPaletteWin
    local spriteWin = assert(currentRunner.romLinkSpriteWin, "expected runtime sprite link window")
    currentApp.wm:setFocus(spriteWin)
    local li = (spriteWin.getActiveLayerIndex and spriteWin:getActiveLayerIndex()) or spriteWin.activeLayer or 1
    PLC.linkLayerToPalette(spriteWin, li, paletteWin)
  end)
  steps[#steps + 1] = pause("Observe sprite palette link", 0.45)

  steps[#steps + 1] = call("Assert sprite window palette link applied", function(_, _, currentRunner)
    local spriteWin = assert(currentRunner.romLinkSpriteWin, "expected runtime sprite link window")
    local linkedLayerIndex = nil
    for i, layer in ipairs(spriteWin.layers or {}) do
      if layer and layer.kind == "sprite" and layer.paletteData and layer.paletteData.winId == currentRunner.romLinkPaletteWin._id then
        linkedLayerIndex = i
        break
      end
    end
    currentRunner.linkedSpriteLayerIndex = linkedLayerIndex
    assert(linkedLayerIndex, "expected sprite layer to link to runtime ROM palette window")
  end)

  steps[#steps + 1] = call("Set palette links to auto-hide and focus sprite target", function(_, currentApp)
    local spriteWin = assert(runner.romLinkSpriteWin, "expected runtime sprite link window")
    currentApp:_applyPaletteLinksSetting("auto_hide", false)
    currentApp.wm:setFocus(spriteWin)
  end)
  steps[#steps + 1] = pause("Observe auto-hide with palette unfocused", 0.45)
  steps[#steps + 1] = moveTo("Hover ROM palette link handle while unfocused", toolbarLinkHandleCenter(function(_, currentRunner)
    return currentRunner.romLinkPaletteWin
  end), 0.12)
  steps[#steps + 1] = pause("Observe handle hover reveal", 0.65)
  steps[#steps + 1] = moveTo("Move away from ROM palette handle", function(h)
    local spriteWin = assert(runner.romLinkSpriteWin, "expected runtime sprite link window")
    return h:windowCellCenter(spriteWin, 0, 0)
  end, 0.12)
  steps[#steps + 1] = pause("Observe hidden connector after moving away", 0.45)

  appendDrag(steps, "Drag linked static art window", windowHeaderCenter(function()
    return staticWin
  end), function(_, _, currentRunner)
    local win = staticWin
    return win.x + 70, win.y - 2
  end, {
    dragDuration = 0.18,
    postPause = 0.22,
  })

  steps[#steps + 1] = call("Assert drag reveal timer was set", function(currentHarness)
    assert(staticWin._paletteLinkRevealUntil and staticWin._paletteLinkRevealUntil > currentHarness._timerNow,
      "expected palette link reveal timer after linked window drag")
  end)
  steps[#steps + 1] = pause("Observe post-drag connector fade", 1.1)
  steps[#steps + 1] = call("Assert drag reveal faded", function(currentHarness)
    assert((staticWin._paletteLinkRevealUntil or 0) <= currentHarness._timerNow,
      "expected drag reveal timer to expire")
  end)

  steps[#steps + 1] = call("Set palette links to never", function(_, currentApp)
    currentApp:_applyPaletteLinksSetting("never", false)
  end)
  steps[#steps + 1] = pause("Observe squares-only palette link mode", 0.6)
  steps[#steps + 1] = call("Restore palette links to always", function(_, currentApp)
    currentApp:_applyPaletteLinksSetting("always", false)
  end)
  steps[#steps + 1] = pause("Observe full connector restore", 0.6)

  steps[#steps + 1] = call("Remove all ROM palette links (API)", function(_, currentApp, currentRunner)
    PaletteLinkController.removeAllLinksForPalette(currentApp.wm, currentRunner.romLinkPaletteWin)
  end)
  steps[#steps + 1] = pause("Observe unlink all result", 0.65)
  steps[#steps + 1] = call("Assert both palette links were removed", function(_, _, currentRunner)
    local staticLayer = staticWin.layers and staticWin.layers[1]
    local spriteWin = assert(currentRunner.romLinkSpriteWin, "expected runtime sprite link window")
    local spriteLayer = nil
    if currentRunner.linkedSpriteLayerIndex then
      spriteLayer = spriteWin.layers and spriteWin.layers[currentRunner.linkedSpriteLayerIndex]
    end
    assert(not (staticLayer and staticLayer.paletteData), "expected static art palette link to be removed")
    assert(not (spriteLayer and spriteLayer.paletteData), "expected sprite palette link to be removed")
    assert(currentRunner.romLinkPaletteWin and currentRunner.romLinkPaletteWin._id, "expected ROM palette window to remain")
  end)
  steps[#steps + 1] = pause("Scenario complete", 0.5)

  return steps
end

local function buildRomPaletteLinkInteractionsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local function activeLayerLinkWinId(win)
    local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
    local layer = win.layers and win.layers[li] or nil
    return layer and layer.paletteData and layer.paletteData.winId or nil
  end

  local function requireRunnerWindow(currentRunner, key)
    local win = currentRunner and currentRunner[key] or nil
    assert(win, "expected runner window: " .. tostring(key))
    return win
  end

  local function paletteHandleCenterByKey(key)
    return toolbarLinkHandleCenter(function(_, currentRunner)
      return requireRunnerWindow(currentRunner, key)
    end)
  end

  local function appendFocusWindow(steps, label, key)
    steps[#steps + 1] = call(label, function(_, currentApp, currentRunner)
      currentApp.wm:setFocus(requireRunnerWindow(currentRunner, key))
    end)
    steps[#steps + 1] = pause("Observe focus: " .. tostring(key), 0.12)
  end

  local function appendLinkFromPalette(steps, paletteKey, targetKey)
    steps[#steps + 1] = call(string.format("Link %s to %s (API)", tostring(paletteKey), tostring(targetKey)), function(_, currentApp, currentRunner)
      local PLC = require("controllers.palette.palette_link_controller")
      local paletteWin = requireRunnerWindow(currentRunner, paletteKey)
      local targetWin = requireRunnerWindow(currentRunner, targetKey)
      currentApp.wm:setFocus(targetWin)
      local li = (targetWin.getActiveLayerIndex and targetWin:getActiveLayerIndex()) or targetWin.activeLayer or 1
      PLC.linkLayerToPalette(targetWin, li, paletteWin)
    end)
    steps[#steps + 1] = pause("Observe palette link", 0.18)
  end

  local function paletteLinkMenu(currentApp)
    local menu = currentApp and currentApp.paletteLinkContextMenu or nil
    assert(menu and menu:isVisible(), "expected visible palette link context menu")
    return menu
  end

  local function paletteLinkMenuRowByText(itemText)
    return rootMenuItemCenter(function(currentApp)
      return paletteLinkMenu(currentApp)
    end, itemText)
  end

  local function openPaletteLinkChildMenuByText(itemText)
    return function(_, currentApp)
      local menu = paletteLinkMenu(currentApp)
      local items = menu.visibleItems or {}
      local targetRow = nil
      for index, item in ipairs(items) do
        if item and item.text == itemText then
          targetRow = index
          break
        end
      end
      assert(targetRow, "expected palette link menu item: " .. tostring(itemText))
      assert(menu._openChildForRow, "expected palette link menu child opener")
      local opened = menu:_openChildForRow(targetRow)
      assert(opened == true, "expected palette link child menu to open for " .. tostring(itemText))
    end
  end

  local function assertPaletteLinkMenuTexts(expectedTexts)
    return function(_, currentApp)
      local menu = paletteLinkMenu(currentApp)
      local actualTexts = {}
      for _, item in ipairs(menu.visibleItems or {}) do
        actualTexts[#actualTexts + 1] = tostring(item and item.text or "")
      end
      assert(#actualTexts == #expectedTexts,
        string.format(
          "expected %d palette link menu items, got %d (%s)",
          #expectedTexts,
          #actualTexts,
          table.concat(actualTexts, ", ")
        )
      )
      for index, expectedText in ipairs(expectedTexts) do
        assert(
          actualTexts[index] == expectedText,
          string.format(
            "expected palette link menu row %d to be %s, got %s",
            index,
            tostring(expectedText),
            tostring(actualTexts[index])
          )
        )
      end
    end
  end

  local function assertFocusedWindow(expectedKey, expectedLayerIndex)
    return function(_, currentApp, currentRunner)
      local expectedWin = requireRunnerWindow(currentRunner, expectedKey)
      local focusedWin = currentApp.wm:getFocus()
      assert(focusedWin == expectedWin, string.format(
        "expected focused window %s, got %s",
        tostring(expectedKey),
        tostring(focusedWin and (focusedWin.title or focusedWin._id) or nil)
      ))
      if expectedLayerIndex ~= nil then
        local actualLayerIndex = (focusedWin.getActiveLayerIndex and focusedWin:getActiveLayerIndex()) or focusedWin.activeLayer or 1
        assert(
          actualLayerIndex == expectedLayerIndex,
          string.format("expected focused layer %d, got %d", expectedLayerIndex, actualLayerIndex)
        )
      end
    end
  end

  local function paletteLinkChildMenuRow(row)
    return childMenuRowCenter(function(currentApp)
      return paletteLinkMenu(currentApp)
    end, row)
  end

  local function paletteLinkChildMenuItemByText(textResolver)
    return function(_, currentApp, currentRunner)
      local expectedText = textResolver
      if type(textResolver) == "function" then
        expectedText = textResolver(currentRunner)
      end
      expectedText = tostring(expectedText or "")
      local menu = paletteLinkMenu(currentApp)
      local childMenu = assert(menu.childMenu, "expected visible palette link child menu")
      local items = childMenu.visibleItems or {}
      local targetRow = nil
      for index, item in ipairs(items) do
        if item and item.text == expectedText then
          targetRow = index
          break
        end
      end
      if not targetRow and expectedText ~= "" then
        for index, item in ipairs(items) do
          local itemText = item and tostring(item.text or "") or ""
          if itemText:find(expectedText, 1, true) then
            targetRow = index
            break
          end
        end
      end
      assert(targetRow, "expected palette link child menu item: " .. tostring(expectedText))
      return paletteLinkChildMenuRow(targetRow)(nil, currentApp, currentRunner)
    end
  end

  local function appendClickPaletteHandle(steps, label, key)
    appendFocusWindow(steps, "Focus " .. tostring(key) .. " before palette handle click", key)
    appendClick(steps, label, paletteHandleCenterByKey(key), {
      button = 1,
      moveDuration = 0.08,
      prePressPause = 0.06,
      holdDuration = 0.05,
      postPause = 0.18,
    })
  end

  local function assertLinks(expectedPaletteKeyByTargetKey)
    return function(_, _, currentRunner)
      for targetKey, expectedPaletteKey in pairs(expectedPaletteKeyByTargetKey) do
        local targetWin = requireRunnerWindow(currentRunner, targetKey)
        local actualWinId = activeLayerLinkWinId(targetWin)
        local expectedWinId = nil
        if expectedPaletteKey ~= nil then
          expectedWinId = requireRunnerWindow(currentRunner, expectedPaletteKey)._id
        end
        assert(
          actualWinId == expectedWinId,
          string.format(
            "expected %s linked to %s (winId=%s), got %s",
            tostring(targetKey),
            tostring(expectedPaletteKey),
            tostring(expectedWinId),
            tostring(actualWinId)
          )
        )
      end
    end
  end

  local steps = {
    pause("Start", 0.35),
    call("Create palette link interaction windows", function(_, currentApp, currentRunner)
      if currentApp and currentApp._applyPaletteLinksSetting then
        currentApp:_applyPaletteLinksSetting("always", false)
      end

      currentRunner.romLinkPaletteAWin = assert(currentApp.wm:createRomPaletteWindow({
        title = "ROM Link Palette A",
        x = 44,
        y = 86,
      }), "expected ROM palette A")
      currentRunner.romLinkPaletteBWin = assert(currentApp.wm:createRomPaletteWindow({
        title = "ROM Link Palette B",
        x = 44,
        y = 220,
      }), "expected ROM palette B")

      currentRunner.linkTarget1 = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Link Target 1",
        x = 230,
        y = 64,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected link target 1")

      currentRunner.linkTarget2 = assert(currentApp.wm:createSpriteWindow({
        animated = false,
        title = "Link Target 2",
        x = 420,
        y = 64,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected link target 2")

      currentRunner.linkTarget3 = assert(currentApp.wm:createTileWindow({
        animated = true,
        numFrames = 1,
        title = "Link Target 3",
        x = 230,
        y = 212,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected link target 3")

      currentRunner.linkTarget4 = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Link Target 4",
        x = 420,
        y = 212,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected link target 4")

      currentApp.wm:setFocus(currentRunner.romLinkPaletteAWin)
    end),
    pause("Observe two palettes and four link targets", 0.75),
  }

  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget1")
  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget2")
  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget3")
  steps[#steps + 1] = call("Assert initial links A->(1,2,3)", assertLinks({
    linkTarget1 = "romLinkPaletteAWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = "romLinkPaletteAWin",
    linkTarget4 = nil,
  }))
  steps[#steps + 1] = pause("Observe initial link setup", 0.4)

  appendClickPaletteHandle(steps, "Open palette A source menu for jump", "romLinkPaletteAWin")
  steps[#steps + 1] = call("Assert source menu items while linked", assertPaletteLinkMenuTexts({
    "Jump to linked layer",
    "Remove all links",
  }))
  steps[#steps + 1] = call("Open Jump to linked layer child menu", openPaletteLinkChildMenuByText("Jump to linked layer"))
  appendClick(steps, "Choose link target 3 from source jump menu", paletteLinkChildMenuItemByText("Link Target 3 / layer 1"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert source jump focused link target 3", assertFocusedWindow("linkTarget3", 1))

  appendClickPaletteHandle(steps, "Open linked destination menu on target3", "linkTarget3")
  steps[#steps + 1] = call("Assert linked destination menu items", assertPaletteLinkMenuTexts({
    "Link To Palette",
    "Jump to linked palette",
    "Remove this link",
  }))
  appendClick(steps, "Choose Jump to linked palette on target3", paletteLinkMenuRowByText("Jump to linked palette"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert destination jump focused palette A", assertFocusedWindow("romLinkPaletteAWin"))

  appendClickPaletteHandle(steps, "Open unlinked destination menu on target4", "linkTarget4")
  steps[#steps + 1] = call("Assert unlinked destination menu items", assertPaletteLinkMenuTexts({
    "Link To Palette",
  }))
  steps[#steps + 1] = call("Open Link To Palette child menu on target4", openPaletteLinkChildMenuByText("Link To Palette"))
  appendClick(steps, "Choose palette B in target4 link menu", paletteLinkChildMenuItemByText(function(currentRunner)
    return requireRunnerWindow(currentRunner, "romLinkPaletteBWin").title
  end), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert target4 linked to palette B via destination menu", assertLinks({
    linkTarget1 = "romLinkPaletteAWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = "romLinkPaletteAWin",
    linkTarget4 = "romLinkPaletteBWin",
  }))

  appendFocusWindow(steps, "Focus target1 before reconnecting destination link", "linkTarget1")
  steps[#steps + 1] = call("Reconnect target1 from palette A to B (API)", function(_, currentApp, currentRunner)
    local PLC = require("controllers.palette.palette_link_controller")
    local t = requireRunnerWindow(currentRunner, "linkTarget1")
    local b = requireRunnerWindow(currentRunner, "romLinkPaletteBWin")
    currentApp.wm:setFocus(t)
    local li = (t.getActiveLayerIndex and t:getActiveLayerIndex()) or t.activeLayer or 1
    PLC.linkLayerToPalette(t, li, b)
  end)
  steps[#steps + 1] = pause("Observe destination reconnect", 0.35)
  steps[#steps + 1] = call("Assert target1 moved from palette A to palette B", assertLinks({
    linkTarget1 = "romLinkPaletteBWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = "romLinkPaletteAWin",
    linkTarget4 = "romLinkPaletteBWin",
  }))
  appendClickPaletteHandle(steps, "Open palette link menu on target2", "linkTarget2")
  appendClick(steps, "Choose Remove this link on target2", paletteLinkMenuRowByText("Remove this link"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.24,
  })
  steps[#steps + 1] = pause("Observe destination unlink", 0.22)
  steps[#steps + 1] = call("Assert destination menu unlink", assertLinks({
    linkTarget1 = "romLinkPaletteBWin",
    linkTarget2 = nil,
    linkTarget3 = "romLinkPaletteAWin",
    linkTarget4 = "romLinkPaletteBWin",
  }))

  appendClickPaletteHandle(steps, "Open palette A source menu", "romLinkPaletteAWin")
  appendClick(steps, "Choose Remove all links on palette A", paletteLinkMenuRowByText("Remove all links"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.24,
  })
  steps[#steps + 1] = pause("Observe source remove-all", 0.22)
  steps[#steps + 1] = call("Assert source remove-all", assertLinks({
    linkTarget1 = "romLinkPaletteBWin",
    linkTarget2 = nil,
    linkTarget3 = nil,
    linkTarget4 = "romLinkPaletteBWin",
  }))
  appendClickPaletteHandle(steps, "Open palette A source menu while unlinked", "romLinkPaletteAWin")
  steps[#steps + 1] = call("Assert source menu items while unlinked", assertPaletteLinkMenuTexts({
    "Jump to linked layer",
    "Remove all links",
  }))
  steps[#steps + 1] = call("Hide unlinked source menu", function(_, currentApp)
    currentApp:hideAppContextMenus()
  end)
  steps[#steps + 1] = pause("Observe menu close before relinking", 0.08)

  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget1")
  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget2")
  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget3")
  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget4")
  steps[#steps + 1] = call("Assert all four targets linked to palette A", assertLinks({
    linkTarget1 = "romLinkPaletteAWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = "romLinkPaletteAWin",
    linkTarget4 = "romLinkPaletteAWin",
  }))

  steps[#steps + 1] = call("Move all links from palette A to B (API)", function(_, currentApp, currentRunner)
    local PLC = require("controllers.palette.palette_link_controller")
    local a = requireRunnerWindow(currentRunner, "romLinkPaletteAWin")
    local b = requireRunnerWindow(currentRunner, "romLinkPaletteBWin")
    PLC.moveAllLinksToPalette(currentApp.wm, a, b)
  end)
  steps[#steps + 1] = pause("Observe move-all links", 0.2)
  steps[#steps + 1] = call("Assert all links moved to palette B", assertLinks({
    linkTarget1 = "romLinkPaletteBWin",
    linkTarget2 = "romLinkPaletteBWin",
    linkTarget3 = "romLinkPaletteBWin",
    linkTarget4 = "romLinkPaletteBWin",
  }))

  appendClickPaletteHandle(steps, "Open palette B source menu for remove-all", "romLinkPaletteBWin")
  appendClick(steps, "Choose Remove all links on palette B", paletteLinkMenuRowByText("Remove all links"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.24,
  })
  steps[#steps + 1] = call("Assert palette B remove-all", assertLinks({
    linkTarget1 = nil,
    linkTarget2 = nil,
    linkTarget3 = nil,
    linkTarget4 = nil,
  }))
  steps[#steps + 1] = pause("Scenario complete", 0.6)

  return steps
end

local function buildSaveReloadPersistenceScenario(harness, app, runner)
  local tempSuffix = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  local tempRomPath = "/tmp/ppux_e2e_visible_persist_" .. tempSuffix .. ".nes"
  local tempProjectPath = tempRomPath:gsub("%.nes$", ".lua")
  local tempEncodedPath = tempRomPath:gsub("%.nes$", ".ppux")
  local tempEditedPath = tempRomPath:gsub("%.nes$", "_edited.nes")
  local sourceRomPath = BubbleExample.getRomPath()
  local persistWindowName = "Persisted Draft"

  local function copyFile(srcPath, dstPath)
    local src = assert(io.open(srcPath, "rb"))
    local bytes = assert(src:read("*a"))
    src:close()
    local dst = assert(io.open(dstPath, "wb"))
    assert(dst:write(bytes))
    dst:close()
  end

  local function removeIfExists(path)
    if path and path ~= "" then
      os.remove(path)
    end
  end

  copyFile(sourceRomPath, tempRomPath)
  runner._cleanupPaths = { tempRomPath, tempProjectPath, tempEncodedPath, tempEditedPath }
  harness:loadROM(tempRomPath)
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )

  local steps = {
    pause("Start", 0.35),
    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.5),
    call("Type persisted window name", function(currentHarness)
      local modal = currentHarness:getApp().newWindowModal
      assert(modal and modal.nameField, "expected new window modal name field")
      modal.nameField:setText(persistWindowName)
    end),
    pause("Observe persisted name", 0.25),
    moveTo("Move to static tiles option", newWindowOptionCenter(1), 0.12),
    pause("Prepare create window click", 0.08),
    mouseDown("Create persisted window", newWindowOptionCenter(1), 1),
    pause("Hold create window click", 0.08),
    mouseUp("Release persisted window click", newWindowOptionCenter(1), 1),
    pause("Resolve persisted window", 0.25),
    call("Store persisted window", function(currentHarness, _, currentRunner)
      currentRunner.persistedWin = assert(currentHarness:findWindow({
        kind = "static_art",
        title = persistWindowName,
      }), "expected persisted static art window")
    end),
  }

  appendDrag(steps, "Place tile into persisted window", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, function(h, _, currentRunner)
    return h:windowCellCenter(currentRunner.persistedWin, 1, 1)
  end, {
    dragDuration = 0.12,
    postPause = 0.25,
  })

  steps[#steps + 1] = keyPress("Open save options", "s", { "lctrl" })
  steps[#steps + 1] = pause("Observe save options", 0.55)
  steps[#steps + 1] = moveTo("Move to save lua option", saveOptionCenter(2), 0.12)
  steps[#steps + 1] = pause("Observe save lua option", 0.18)
  steps[#steps + 1] = call("Save Lua project", function(_, currentApp)
    if currentApp.saveOptionsModal and currentApp.saveOptionsModal.hide then
      currentApp.saveOptionsModal:hide()
    end
    assert(currentApp:saveProject({ toast = false }), "expected lua project save to succeed")
    local projectFile = io.open(tempProjectPath, "rb")
    assert(projectFile, "expected saved lua project file")
    projectFile:close()
  end)
  steps[#steps + 1] = pause("Observe save complete", 0.75)
  steps[#steps + 1] = call("Reload ROM and project", function(_, currentApp, currentRunner)
    local RomProjectController = require("controllers.rom.rom_project_controller")
    assert(RomProjectController.loadROM(currentApp, tempRomPath), "expected ROM reload to succeed")
    currentRunner.reloadedWin = assert(currentRunner.harness:findWindow({
      kind = "static_art",
      title = persistWindowName,
    }), "expected reloaded persisted window")
  end)
  steps[#steps + 1] = pause("Observe reloaded persisted layout", 1.0)
  steps[#steps + 1] = call("Cleanup temp files", function(_, _, currentRunner)
    for _, path in ipairs(currentRunner._cleanupPaths or {}) do
      removeIfExists(path)
    end
  end)

  runner.harness = harness
  return steps
end

local function buildDefaultActionDelayScenario()
  local steps = {
    pause("Start", 0.35),
    moveTo("Move to mode indicator", function(h)
      return h:getTaskbarButtonCenter({ kind = "mode_indicator" })
    end, 0.12),
    pause("Prepare first click", 0.08),
    {
      kind = "mouse_down",
      label = "First click down",
      pointResolver = function(h)
        return h:getTaskbarButtonCenter({ kind = "mode_indicator" })
      end,
      button = 1,
    },
    pause("Hold first click", 0.06),
    {
      kind = "mouse_up",
      label = "First click up",
      pointResolver = function(h)
        return h:getTaskbarButtonCenter({ kind = "mode_indicator" })
      end,
      button = 1,
      recordKey = "first_action_end",
    },
    pause("Default inter-action delay", 0.1),
    {
      kind = "mouse_down",
      label = "Second click down",
      pointResolver = function(h)
        return h:getTaskbarButtonCenter({ kind = "mode_indicator" })
      end,
      button = 1,
      recordKey = "second_action_start",
    },
    pause("Hold second click", 0.06),
    {
      kind = "mouse_up",
      label = "Second click up",
      pointResolver = function(h)
        return h:getTaskbarButtonCenter({ kind = "mode_indicator" })
      end,
      button = 1,
    },
    assertDelay("Assert 0.1s delay", "first_action_end", "second_action_start", 0.1, 0.001),
    pause("Observe result", 0.6),
  }

  return steps
end

local function buildModalNavigationKeyboardOnlyScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local bankWindow = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local originalBankTitle = tostring(bankWindow.title or "")

  local function repeatKey(steps, labelPrefix, key, count, mods, pauseSeconds)
    for i = 1, count do
      steps[#steps + 1] = keyPress(string.format("%s %d", labelPrefix, i), key, mods)
      if pauseSeconds and pauseSeconds > 0 then
        steps[#steps + 1] = pause(labelPrefix, pauseSeconds)
      end
    end
  end

  local steps = {
    pause("Start", 0.35),

    call("Open settings modal", function(_, currentApp)
      currentApp:showSettingsModal()
    end),
    pause("Observe settings modal", 0.55),
    keyPress("Focus next settings option", "tab"),
    pause("Observe settings focus", 0.18),
    keyPress("Toggle focused settings option", "space"),
    pause("Observe settings toggle", 0.5),
    keyPress("Focus previous settings option", "left"),
    pause("Observe reversed settings focus", 0.18),
    keyPress("Toggle second settings option", "space"),
    pause("Observe second settings toggle", 0.5),
    keyPress("Close settings modal", "escape"),
    pause("Pause after settings", 0.25),

    keyPress("Open save options modal", "s", { "lctrl" }),
    pause("Observe save options modal", 0.55),
    keyPress("Close save options modal", "escape"),
    pause("Pause after save options", 0.25),

    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.55),
  }

  repeatKey(steps, "Backspace new window name", "backspace", #"New Window", nil, 0.02)
  steps[#steps + 1] = textInput("Type new window modal name", "KB Demo")
  steps[#steps + 1] = pause("Observe typed new window name", 0.45)
  steps[#steps + 1] = keyPress("Close new window modal", "escape")
  steps[#steps + 1] = pause("Pause after new window modal", 0.25)

  steps[#steps + 1] = call("Open rename window modal", function(_, currentApp)
    currentApp:showRenameWindowModal(bankWindow)
  end)
  steps[#steps + 1] = pause("Observe rename modal", 0.55)
  repeatKey(steps, "Backspace rename title", "backspace", #originalBankTitle, nil, 0.02)
  steps[#steps + 1] = textInput("Type renamed window title", "CHR KB")
  steps[#steps + 1] = pause("Observe typed rename title", 0.4)
  steps[#steps + 1] = keyPress("Confirm rename with Enter", "return")
  steps[#steps + 1] = pause("Observe renamed window title", 0.55)
  steps[#steps + 1] = call("Assert rename applied", function()
    assert(bankWindow.title == "CHR KB", string.format("expected renamed bank window title, got %s", tostring(bankWindow.title)))
  end)

  steps[#steps + 1] = call("Open generic actions modal", function(_, currentApp, currentRunner)
    currentRunner.genericActionChoice = nil
    currentApp.genericActionsModal:show("Quick Actions", {
      { text = "Preview Action", callback = function() currentRunner.genericActionChoice = 1 end },
      { text = "Another Action", callback = function() currentRunner.genericActionChoice = 2 end },
    })
  end)
  steps[#steps + 1] = pause("Observe generic actions modal", 0.55)
  steps[#steps + 1] = keyPress("Choose generic action 2", "2")
  steps[#steps + 1] = pause("Observe generic action close", 0.35)
  steps[#steps + 1] = call("Assert generic action choice", function(_, _, currentRunner)
    assert(currentRunner.genericActionChoice == 2, string.format("expected generic action 2, got %s", tostring(currentRunner.genericActionChoice)))
  end)

  steps[#steps + 1] = call("Open quit confirm modal", function(_, currentApp)
    currentApp:markUnsaved("pixel_edit")
    currentApp:handleQuitRequest()
  end)
  steps[#steps + 1] = pause("Observe quit confirm modal", 0.55)
  steps[#steps + 1] = keyPress("Move quit confirm focus to No", "right")
  steps[#steps + 1] = pause("Observe quit confirm focus change", 0.18)
  steps[#steps + 1] = keyPress("Confirm No with Enter", "return")
  steps[#steps + 1] = pause("Observe quit confirm close", 0.4)
  steps[#steps + 1] = call("Assert quit was cancelled", function(currentHarness, currentApp)
    assert(not currentApp.quitConfirmModal:isVisible(), "expected quit confirm modal to be hidden")
    assert(currentHarness.quitRequested ~= true, "expected quit to be cancelled")
  end)
  steps[#steps + 1] = pause("Scenario complete", 0.5)

  return steps
end

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
}

local SCENARIO_ALIASES = {
  all_modals = "modals",
  tile_drag_demo = "boot_and_drag",
  animation_playback_demo = "animation_playback",
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
}

return {
  scenarios = SCENARIOS,
  aliases = SCENARIO_ALIASES,
}
