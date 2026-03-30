local E2EHarness = require("test.e2e_harness")
local BubbleExample = require("test.e2e_bubble_example")
local E2EVisualConfig = require("test.e2e_visual_config")
local ContextualMenuController = require("controllers.ui.contextual_menu_controller")
local colors = require("app_colors")
local Flux = require("lib.flux")
local images = require("images")

local VisibleE2ERunner = {}
VisibleE2ERunner.__index = VisibleE2ERunner
VisibleE2ERunner.ABORT_ALL_FLAG_PATH = "/tmp/ppux_e2e_abort_all.flag"

local cachedOverlayFont = nil

local function getOverlayFont()
  if cachedOverlayFont then
    return cachedOverlayFont
  end

  local paths = {
    "user_interface/fonts/proggy-tiny.ttf",
    "../user_interface/fonts/proggy-tiny.ttf",
  }

  for _, path in ipairs(paths) do
    local ok, font = pcall(love.graphics.newFont, path, 32)
    if ok and font then
      cachedOverlayFont = font
      return cachedOverlayFont
    end
  end

  cachedOverlayFont = love.graphics.newFont(32)
  return cachedOverlayFont
end

local function normalizeSpeedMultiplier(value)
  local n = tonumber(value)
  if not n or n <= 0 then
    return 1
  end
  return n
end

local function applySpeedMultiplierToSteps(steps, speedMultiplier)
  local multiplier = normalizeSpeedMultiplier(speedMultiplier)
  if multiplier == 1 then
    return steps or {}
  end

  local scaled = {}
  for i, step in ipairs(steps or {}) do
    local nextStep = {}
    for k, v in pairs(step) do
      nextStep[k] = v
    end

    if (nextStep.kind == "pause" or nextStep.kind == "move") and type(nextStep.duration) == "number" then
      nextStep.duration = nextStep.duration / multiplier
    end

    if nextStep.kind == "assert_delay" then
      if type(nextStep.expected) == "number" then
        nextStep.expected = nextStep.expected / multiplier
      end
      if type(nextStep.tolerance) == "number" then
        nextStep.tolerance = math.max(0.0005, nextStep.tolerance / multiplier)
      end
    end

    scaled[i] = nextStep
  end

  return scaled
end

local function pause(label, duration)
  return {
    kind = "pause",
    label = label,
    duration = duration or 0.1,
  }
end

local function moveTo(label, pointResolver, duration)
  return {
    kind = "move",
    label = label,
    duration = duration or 0.1,
    pointResolver = pointResolver,
  }
end

local function mouseDown(label, pointResolver, button)
  return {
    kind = "mouse_down",
    label = label,
    pointResolver = pointResolver,
    button = button or 1,
    recordKey = nil,
  }
end

local function mouseUp(label, pointResolver, button)
  return {
    kind = "mouse_up",
    label = label,
    pointResolver = pointResolver,
    button = button or 1,
    recordKey = nil,
  }
end

local function keyPress(label, key, mods)
  return {
    kind = "key_press",
    label = label,
    key = key,
    mods = mods,
    recordKey = nil,
  }
end

local function textInput(label, text)
  return {
    kind = "text_input",
    label = label,
    text = text,
    recordKey = nil,
  }
end

local function call(label, fn)
  return {
    kind = "call",
    label = label,
    fn = fn,
  }
end

local function assertDelay(label, fromKey, toKey, expected, tolerance)
  return {
    kind = "assert_delay",
    label = label,
    fromKey = fromKey,
    toKey = toKey,
    expected = expected,
    tolerance = tolerance or 0.02,
  }
end

local function resolvePoint(resolver, harness, app, runner)
  if type(resolver) == "function" then
    return resolver(harness, app, runner)
  end
  if type(resolver) == "table" then
    return resolver.x, resolver.y
  end
  return nil, nil
end

local function appendClick(steps, label, pointResolver, opts)
  opts = opts or {}
  steps[#steps + 1] = moveTo(label, pointResolver, opts.moveDuration or 0.12)
  steps[#steps + 1] = pause(label, opts.prePressPause or 0.08)
  steps[#steps + 1] = mouseDown(label, pointResolver, opts.button or 1)
  steps[#steps + 1] = pause(label, opts.holdDuration or 0.08)
  steps[#steps + 1] = mouseUp(label, pointResolver, opts.button or 1)
  steps[#steps + 1] = pause(label, opts.postPause or 0.12)
end

local function appendDrag(steps, label, fromResolver, toResolver, opts)
  opts = opts or {}
  steps[#steps + 1] = moveTo(label, fromResolver, opts.moveDuration or 0.12)
  steps[#steps + 1] = pause(label, opts.prePressPause or 0.08)
  steps[#steps + 1] = mouseDown(label, fromResolver, opts.button or 1)
  steps[#steps + 1] = pause(label, opts.holdDuration or 0.08)
  steps[#steps + 1] = moveTo(label, toResolver, opts.dragDuration or 0.4)
  steps[#steps + 1] = pause(label, opts.preReleasePause or 0.06)
  steps[#steps + 1] = mouseUp(label, toResolver, opts.button or 1)
  steps[#steps + 1] = pause(label, opts.postPause or 0.12)
end

local function newWindowOptionCenter(optionIndex)
  return function(_, currentApp)
    local cell = currentApp.newWindowModal
      and currentApp.newWindowModal.panel
      and currentApp.newWindowModal.panel:getCell(1, 5 + optionIndex)
    assert(cell, "expected new window option cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

local function newWindowModeToggleCenter()
  return function(_, currentApp)
    local cell = currentApp.newWindowModal
      and currentApp.newWindowModal.panel
      and currentApp.newWindowModal.panel:getCell(4, 3)
    assert(cell, "expected new window mode toggle cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

local function saveOptionCenter(optionIndex)
  return function(_, currentApp)
    local cell = currentApp.saveOptionsModal
      and currentApp.saveOptionsModal.panel
      and currentApp.saveOptionsModal.panel:getCell(1, optionIndex)
    assert(cell, "expected save option cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

local function menuRowCenter(menuResolver, row)
  return function(_, currentApp, currentRunner)
    local menu = menuResolver(currentApp, currentRunner)
    assert(menu and menu.panel and menu:isVisible(), "expected visible contextual menu")
    local anchorCol = (menu.activeSplitIconCell == true and (tonumber(menu.cols) or 1) > 1) and 2 or 1
    local cell = menu.panel:getCell(anchorCol, row)
    assert(cell, "expected contextual menu row cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

local function taskbarRootMenu(_, currentRunner)
  local currentApp = currentRunner and currentRunner.app or app
  local taskbar = currentApp and currentApp.taskbar or nil
  return taskbar and taskbar.menuController or nil
end

local function childMenuRowCenter(menuResolver, row)
  return function(_, currentApp, currentRunner)
    local menu = menuResolver(currentApp, currentRunner)
    local childMenu = assert(menu and menu.childMenu, "expected visible child menu")
    local anchorCol = (childMenu.activeSplitIconCell == true and (tonumber(childMenu.cols) or 1) > 1) and 2 or 1
    local cell = childMenu.panel:getCell(anchorCol, row)
    assert(cell, "expected child menu row cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

local function rootMenuItemCenter(menuResolver, itemText)
  return function(_, currentApp, currentRunner)
    local menu = assert(menuResolver(currentApp, currentRunner), "expected visible root menu")
    local items = menu.visibleItems or {}
    local targetRow = nil
    for index, item in ipairs(items) do
      if item and item.text == itemText then
        targetRow = index
        break
      end
    end
    assert(targetRow, "expected root menu item: " .. tostring(itemText))
    return menuRowCenter(menuResolver, targetRow)(nil, currentApp, currentRunner)
  end
end

local function resizeHandleCenter(winResolver)
  return function(_, currentApp, currentRunner)
    local win = assert(winResolver(currentApp, currentRunner), "expected target window for resize handle")
    local x, y, w, h = win:getResizeHandleRect()
    return x + math.floor(w * 0.5), y + math.floor(h * 0.5)
  end
end

local function taskbarMenuGapPoint(row)
  return function(_, currentApp, currentRunner)
    local menu = assert(taskbarRootMenu(currentApp, currentRunner), "expected visible taskbar root menu")
    local anchorCol = (menu.activeSplitIconCell == true and (tonumber(menu.cols) or 1) > 1) and 2 or 1
    local cell = assert(menu.panel:getCell(anchorCol, row), "expected root menu row cell")
    local childMenu = assert(menu.childMenu, "expected visible child menu")
    local x = math.floor(cell.x + cell.w + 6)
    local y = math.floor(math.min(cell.y, childMenu.y) - 6)
    return x, y
  end
end

local function assertTaskbarChildState(expectedRootText, shouldExist)
  return function(_, currentApp, currentRunner)
    local menu = assert(taskbarRootMenu(currentApp, currentRunner), "expected visible taskbar root menu")
    local childMenu = menu.childMenu
    if shouldExist == false then
      assert(childMenu == nil, "expected taskbar submenu to be hidden")
      return
    end
    assert(childMenu and childMenu:isVisible(), "expected taskbar submenu to be visible")
    if expectedRootText then
      local activeText = menu.activeChildItem and menu.activeChildItem.text or nil
      assert(activeText == expectedRootText, string.format("expected active submenu root %s, got %s", tostring(expectedRootText), tostring(activeText)))
    end
  end
end

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

  local steps = {
    pause("Start", 0.35),
    call("Arrange overlapping windows", function(_, currentApp, currentRunner)
      currentRunner.bankResizeWin = bankWin
      currentRunner.staticResizeWin = staticWin

      bankWin.x = 96
      bankWin.y = 58
      staticWin.x = 180
      staticWin.y = 112

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
    return hx + math.floor(hw * 0.5) - 18, hy + math.floor(hh * 0.5) - 18
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

  appendDrag(steps, "Resize bank window inward", resizeHandleCenter(currentBankWin), function(_, _, currentRunner)
    local win = assert(currentRunner.bankResizeWin, "expected bank resize window")
    local hx, hy, hw, hh = win:getResizeHandleRect()
    return hx + math.floor(hw * 0.5) - 22, hy + math.floor(hh * 0.5) - 22
  end, {
    dragDuration = 0.24,
    postPause = 0.35,
  })

  steps[#steps + 1] = call("Assert bank window resized", function(_, _, currentRunner)
    local before = assert(currentRunner.bankBefore, "expected bank size snapshot")
    local win = assert(currentRunner.bankResizeWin, "expected bank resize window")
    assert((win.visibleCols or 0) < (before.cols or 0) or (win.visibleRows or 0) < (before.rows or 0), "expected bank window visible size to shrink")
  end)
  steps[#steps + 1] = pause("Observe resized bank window", 0.7)

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
    title = "Bubble Assembly",
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
  palette_edit_roundtrip = {
    title = "Palette Edit Roundtrip",
    build = buildPaletteEditRoundtripScenario,
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
  palette_edit_roundtrip_demo = "palette_edit_roundtrip",
  save_reload_persistence_demo = "save_reload_persistence",
  submenu_positions_demo = "submenu_positions",
  context_menus_and_submenus_demo = "context_menus_and_submenus",
  window_resize_and_hover_priority_demo = "window_resize_and_hover_priority",
  modal_navigation_keyboard_only_demo = "modal_navigation_keyboard_only",
}

function VisibleE2ERunner.new(opts)
  opts = opts or {}
  local requestedScenarioName = opts.scenario or "modals"
  local scenarioName = SCENARIO_ALIASES[requestedScenarioName] or requestedScenarioName
  local scenario = assert(SCENARIOS[scenarioName], "Unknown E2E scenario: " .. tostring(requestedScenarioName))
  local speedMultiplier = normalizeSpeedMultiplier(
    opts.speedMultiplier
      or opts.speed
      or (E2EVisualConfig and E2EVisualConfig.speedMultiplier)
      or 1
  )

  local harness = E2EHarness.new({
    stepDelaySeconds = 0,
    settings = opts.settings,
    shimEventQuit = false,
  })
  local app = harness:boot()
  local self = setmetatable({
    harness = harness,
    app = app,
    scenarioName = scenarioName,
    requestedScenarioName = requestedScenarioName,
    scenario = scenario,
    speedMultiplier = speedMultiplier,
    steps = {},
    currentStepIndex = 0,
    currentStep = nil,
    currentLabel = "Booting",
    done = false,
    doneElapsed = 0,
    autoCloseDelay = (opts.autoCloseDelay or 0.5) / speedMultiplier,
    quitIssued = false,
    timelineSeconds = 0,
    recordedTimes = {},
    demoMenu = nil,
    abortModalVisible = false,
    abortModalFocusIndex = 3,
    abortButtons = {
      { label = "Current", action = "current" },
      { label = "All", action = "all" },
      { label = "Continue", action = "continue" },
    },
    abortButtonRects = {},
  }, VisibleE2ERunner)

  if scenarioName == "submenu_positions" then
    self.demoMenu = ContextualMenuController.new({
      getBounds = function()
        return {
          w = app.canvas:getWidth(),
          h = app.canvas:getHeight(),
        }
      end,
      cols = 8,
      cellW = 15,
      cellH = 15,
      padding = 0,
      colGap = 0,
      rowGap = 1,
      splitIconCell = true,
    })
    app.e2eOverlayMenu = self.demoMenu
  end

  self.steps = applySpeedMultiplierToSteps(scenario.build(harness, app, self) or {}, speedMultiplier)
  return self
end

function VisibleE2ERunner:getApp()
  return self.app
end

function VisibleE2ERunner:_startNextStep()
  self.currentStepIndex = self.currentStepIndex + 1
  local step = self.steps[self.currentStepIndex]
  self.currentStep = step
  if not step then
    self.done = true
    self.currentLabel = "Done"
    return
  end

  step.elapsed = 0
  self.currentLabel = step.label or step.kind or ("Step " .. tostring(self.currentStepIndex))

  if step.kind == "move" then
    local fromX, fromY = self.harness:getMouseCanvasPosition()
    local toX, toY = resolvePoint(step.pointResolver, self.harness, self.app, self)
    step.fromX = fromX
    step.fromY = fromY
    step.toX = assert(toX, "move step x could not be resolved")
    step.toY = assert(toY, "move step y could not be resolved")
    step.duration = math.max(0.001, tonumber(step.duration) or 0.1)
    step.cursor = {
      x = fromX,
      y = fromY,
    }
    step.tweenGroup = Flux.group()
    step.tweenGroup:to(step.cursor, step.duration, {
      x = step.toX,
      y = step.toY,
    }):ease("linear")
    self.harness:moveMouse(fromX, fromY)
  elseif step.kind == "pause" then
    step.duration = math.max(0.001, tonumber(step.duration) or 0.1)
  end
end

function VisibleE2ERunner:_recordEvent(key)
  if not key then
    return
  end
  self.recordedTimes[key] = self.timelineSeconds
end

function VisibleE2ERunner:_setAbortModalVisible(visible)
  self.abortModalVisible = (visible == true)
  if self.abortModalVisible then
    self.abortModalFocusIndex = self.abortModalFocusIndex or 3
  end
end

function VisibleE2ERunner:_quitNow(exitCode)
  if self.app and self.app.clearUnsavedChanges then
    self.app:clearUnsavedChanges()
  end
  if self.app then
    self.app._allowImmediateQuit = true
  end
  self.quitIssued = true
  love.event.quit(exitCode or 0)
end

function VisibleE2ERunner:_requestAbortAll()
  local path = self.ABORT_ALL_FLAG_PATH
  local file = io.open(path, "wb")
  if file then
    file:write("abort_all\n")
    file:close()
  end
end

function VisibleE2ERunner:_activateAbortChoice(action)
  if action == "continue" then
    self:_setAbortModalVisible(false)
    return true
  end

  if action == "all" then
    self:_requestAbortAll()
    self:_quitNow(0)
    return true
  end

  if action == "current" then
    self:_quitNow(0)
    return true
  end

  return false
end

function VisibleE2ERunner:keypressed(key)
  if not self.abortModalVisible then
    if key == "escape" then
      self:_setAbortModalVisible(true)
      return true
    end
    return false
  end

  if key == "escape" then
    self:_activateAbortChoice("continue")
    return true
  end

  if key == "left" then
    self.abortModalFocusIndex = math.max(1, (self.abortModalFocusIndex or 1) - 1)
    return true
  end
  if key == "right" or key == "tab" then
    self.abortModalFocusIndex = math.min(#self.abortButtons, (self.abortModalFocusIndex or 1) + 1)
    return true
  end
  if key == "return" or key == "kpenter" or key == "space" then
    local button = self.abortButtons[self.abortModalFocusIndex or 1]
    return button and self:_activateAbortChoice(button.action) or true
  end
  if key == "1" or key == "kp1" then
    return self:_activateAbortChoice("current")
  end
  if key == "2" or key == "kp2" then
    return self:_activateAbortChoice("all")
  end
  if key == "3" or key == "kp3" then
    return self:_activateAbortChoice("continue")
  end

  return true
end

function VisibleE2ERunner:mousepressed(x, y, button)
  if not self.abortModalVisible or button ~= 1 then
    return false
  end

  for index, rect in ipairs(self.abortButtonRects or {}) do
    if x >= rect.x and x <= (rect.x + rect.w) and y >= rect.y and y <= (rect.y + rect.h) then
      self.abortModalFocusIndex = index
      local buttonDef = self.abortButtons[index]
      if buttonDef then
        self:_activateAbortChoice(buttonDef.action)
      end
      return true
    end
  end

  return true
end

function VisibleE2ERunner:_runInstantStep(step)
  if step.kind == "mouse_down" or step.kind == "mouse_up" then
    local x, y = resolvePoint(step.pointResolver, self.harness, self.app, self)
    assert(x and y, step.kind .. " point could not be resolved")
    if step.kind == "mouse_down" then
      self.harness:mouseDown(step.button or 1, x, y)
    else
      self.harness:mouseUp(step.button or 1, x, y)
    end
    self:_recordEvent(step.recordKey)
    self.currentStep = nil
    return
  end

  if step.kind == "key_press" then
    self.harness:keyPress(step.key, {
      mods = step.mods,
      wait = false,
    })
    self:_recordEvent(step.recordKey)
    self.currentStep = nil
    return
  end

  if step.kind == "text_input" then
    self.harness:textInput(step.text, {
      wait = false,
    })
    self:_recordEvent(step.recordKey)
    self.currentStep = nil
    return
  end

  if step.kind == "call" then
    assert(type(step.fn) == "function", "call step requires fn")
    step.fn(self.harness, self.app, self)
    self:_recordEvent(step.recordKey)
    self.currentStep = nil
    return
  end

  if step.kind == "assert_delay" then
    local fromTime = assert(self.recordedTimes[step.fromKey], "missing recorded time: " .. tostring(step.fromKey))
    local toTime = assert(self.recordedTimes[step.toKey], "missing recorded time: " .. tostring(step.toKey))
    local actual = toTime - fromTime
    local expected = tonumber(step.expected) or 0.1
    local tolerance = tonumber(step.tolerance) or 0.02
    local delta = math.abs(actual - expected)
    if delta > tolerance then
      error(string.format(
        "Visible E2E delay assertion failed: expected %.3fs between %s and %s, got %.3fs",
        expected,
        tostring(step.fromKey),
        tostring(step.toKey),
        actual
      ))
    end
    self.app:setStatus(string.format("Delay OK: %.3fs", actual))
    self.currentStep = nil
    return
  end
end

function VisibleE2ERunner:update(dt)
  if self.abortModalVisible then
    return
  end

  if self.harness and self.harness.advanceTimer then
    self.harness:advanceTimer(dt)
  end
  local remaining = dt

  while remaining > 0 do
    if not self.currentStep and not self.done then
      self:_startNextStep()
    end

    local step = self.currentStep
    if not step then
      self.timelineSeconds = self.timelineSeconds + remaining
      remaining = 0
      break
    end

    if step.kind == "pause" then
      local needed = math.max(0, step.duration - step.elapsed)
      local consume = math.min(remaining, needed)
      step.elapsed = step.elapsed + consume
      self.timelineSeconds = self.timelineSeconds + consume
      remaining = remaining - consume
      if step.elapsed >= step.duration then
        self.currentStep = nil
      end
    elseif step.kind == "move" then
      local needed = math.max(0, step.duration - step.elapsed)
      local consume = math.min(remaining, needed)
      step.elapsed = step.elapsed + consume
      self.timelineSeconds = self.timelineSeconds + consume
      remaining = remaining - consume

      if step.tweenGroup then
        step.tweenGroup:update(consume)
      end
      self.harness:moveMouse(
        step.cursor and step.cursor.x or step.toX,
        step.cursor and step.cursor.y or step.toY
      )
      if step.elapsed >= step.duration then
        self.harness:moveMouse(step.toX, step.toY)
        step.tweenGroup = nil
        step.cursor = nil
        self.currentStep = nil
      end
    else
      self:_runInstantStep(step)
      if self.currentStep == step then
        break
      end
    end
  end

  self.app:update(dt)

  if self.done and not self.quitIssued then
    self.doneElapsed = self.doneElapsed + dt
    if self.doneElapsed >= self.autoCloseDelay then
      if self.app.clearUnsavedChanges then
        self.app:clearUnsavedChanges()
      end
      self.app._allowImmediateQuit = true
      self.quitIssued = true
      love.event.quit()
    end
  end
end

function VisibleE2ERunner:drawOverlay()
  local title = string.format("E2E: %s (%0.2fx)", self.scenario.title or self.scenarioName, self.speedMultiplier or 1)
  local stepText = string.format("Step %d/%d: %s", math.min(self.currentStepIndex, #self.steps), #self.steps, self.currentLabel or "")
  local escHint = "Esc to pause/abort"

  local previousFont = love.graphics.getFont()
  local font = getOverlayFont()
  love.graphics.setFont(font)

  local w1 = font:getWidth(title)
  local w2 = font:getWidth(stepText)
  local w3 = font:getWidth(escHint)
  local boxW = math.max(w1, w2, w3) + 16
  local boxH = font:getHeight() * 3 + 18

  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", 8, 8, boxW, boxH)
  love.graphics.setColor(colors.white)
  love.graphics.print(title, 14, 12)
  love.graphics.print(stepText, 14, 12 + font:getHeight() + 2)
  love.graphics.setColor(1, 0.95, 0.2, 1)
  love.graphics.print(escHint, 14, 12 + (font:getHeight() + 2) * 2)

  local cursorCanvasX, cursorCanvasY = self.harness:getMouseCanvasPosition()
  local cursorScreenX, cursorScreenY = self.harness:canvasToScreen(cursorCanvasX, cursorCanvasY)
  love.graphics.setColor(1, 0.95, 0.2, 0.95)
  love.graphics.circle("fill", cursorScreenX, cursorScreenY, 6)
  love.graphics.setColor(0, 0, 0, 0.9)
  love.graphics.circle("line", cursorScreenX, cursorScreenY, 6)

  if self.abortModalVisible then
    local titleText = "Abort:"
    local buttonGap = 6
    local padding = 12
    local buttonH = font:getHeight() + 12
    local widestButton = 0
    for _, button in ipairs(self.abortButtons) do
      widestButton = math.max(widestButton, font:getWidth(button.label))
    end
    local buttonW = widestButton + 20
    local titleW = font:getWidth(titleText)
    local innerW = (buttonW * 3) + (buttonGap * 2)
    local boxW = math.max(titleW, innerW) + (padding * 2)
    local boxH = padding * 2 + font:getHeight() + 6 + buttonH
    local boxX = math.floor((love.graphics.getWidth() - boxW) * 0.5)
    local boxY = math.floor((love.graphics.getHeight() - boxH) * 0.5)
    local buttonsY = boxY + padding + font:getHeight() + 6
    local buttonsX = boxX + padding

    love.graphics.setColor(0, 0, 0, 0.78)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH)
    love.graphics.setColor(colors.white)
    love.graphics.print(titleText, boxX + padding, boxY + padding)

    self.abortButtonRects = {}
    for index, button in ipairs(self.abortButtons) do
      local bx = buttonsX + (index - 1) * (buttonW + buttonGap)
      local by = buttonsY
      self.abortButtonRects[index] = { x = bx, y = by, w = buttonW, h = buttonH }
      if index == (self.abortModalFocusIndex or 1) then
        love.graphics.setColor(0.2, 0.65, 0.2, 1)
      else
        love.graphics.setColor(0.22, 0.22, 0.22, 1)
      end
      love.graphics.rectangle("fill", bx, by, buttonW, buttonH)
      love.graphics.setColor(colors.white)
      local labelW = font:getWidth(button.label)
      local labelX = bx + math.floor((buttonW - labelW) * 0.5)
      local labelY = by + math.floor((buttonH - font:getHeight()) * 0.5)
      love.graphics.print(button.label, labelX, labelY)
    end
  else
    self.abortButtonRects = {}
  end

  love.graphics.setColor(colors.white)
  if previousFont and previousFont ~= font then
    love.graphics.setFont(previousFont)
  end
end

function VisibleE2ERunner:destroy()
  if self.demoMenu and self.demoMenu.hide then
    self.demoMenu:hide()
  end
  if self.app and self.app.e2eOverlayMenu == self.demoMenu then
    self.app.e2eOverlayMenu = nil
  end
  if self.harness then
    self.harness:destroy()
  end
end

VisibleE2ERunner._normalizeSpeedMultiplier = normalizeSpeedMultiplier
VisibleE2ERunner._applySpeedMultiplierToSteps = applySpeedMultiplierToSteps

return VisibleE2ERunner
