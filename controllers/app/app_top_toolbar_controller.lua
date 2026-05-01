-- Top-of-canvas strip: quick actions + optional docked focused-window toolbar ("Separate toolbar").
local colors = require("app_colors")
local Button = require("user_interface.button")
local images = require("images")
local UiScale = require("user_interface.ui_scale")
local WindowCaps = require("controllers.window.window_capabilities")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local Text = require("utils.text_utils")

local M = {}

local MIN_BAR_H = 15
local OUTER_MARGIN = 0
local SECTION_GAP = 0
local BUTTON_GAP = 0
local STATUS_BG_H = 15
local STATUS_AREA_RATIO = 0.5

-- Unit tests and some harnesses stub `love` without `keyboard`; treat as no modifiers.
local function isShiftHeld()
  local kb = love and love.keyboard
  if not (kb and type(kb.isDown) == "function") then
    return false
  end
  return kb.isDown("lshift") or kb.isDown("rshift")
end

local function measureDockedToolbarHeight(toolbar, cell)
  if not toolbar then
    return 0
  end

  if toolbar._getToolbarHeight then
    local ok, height = pcall(function()
      return toolbar:_getToolbarHeight(cell)
    end)
    if ok and type(height) == "number" then
      return height
    end
  end

  return tonumber(toolbar.h) or tonumber(cell) or 0
end

function M.getContentOffsetY(app)
  local lay = app and app._appTopToolbarLayout
  local h = lay and lay.totalH
  if type(h) ~= "number" or h < MIN_BAR_H then
    return MIN_BAR_H
  end
  return h
end

local function ensureQuickButtons(app)
  if app._appTopQuickButtons then
    return
  end

  local function withRom(appRef, fn)
    return function()
      if not appRef:hasLoadedROM() then
        appRef:setStatus("Open a ROM before using this action.")
        if appRef.showToast then
          appRef:showToast("warning", appRef.statusText or "Open a ROM first.")
        end
        return
      end
      fn(appRef)
    end
  end

  local function zoomFocusedByWheelStep(a, delta)
    local wm = a.wm
    if not wm or not wm.getFocus then
      return
    end
    local focus = wm:getFocus()
    if not focus or focus._closed or focus._minimized then
      a:setStatus("No focused window to zoom.")
      if a.showToast then
        a:showToast("warning", a.statusText or "No focused window to zoom.")
      end
      return
    end
    if WindowCaps.isAnyPaletteWindow(focus) then
      return
    end
    if focus.addZoomLevel then
      wm:setFocus(focus)
      focus:addZoomLevel(delta)
    end
  end

  local cell = math.max(UiScale.menuCellSize(), MIN_BAR_H)

  app._appTopQuickButtons = {
    newWindow = Button.new({
      icon = images.icons.icon_new_window,
      tooltip = "New window",
      action = function()
        if not app.hasLoadedROM or not app:hasLoadedROM() then
          app:setStatus("Open a ROM before creating windows.")
          if app.showToast then
            app:showToast("warning", app.statusText or "Open a ROM first.")
          end
          return
        end
        app:showNewWindowModal()
      end,
      x = 0,
      y = 0,
      w = cell,
      h = cell,
    }),
    open = Button.new({
      icon = images.icons.icon_open or images.icons.icon_empty or images.icons.icon_scroll_toolbar_empty,
      tooltip = "Open",
      action = function()
        if app.showOpenProjectModal then
          app:showOpenProjectModal()
        end
      end,
      x = 0,
      y = 0,
      w = cell,
      h = cell,
    }),
    save = Button.new({
      icon = images.icons.save,
      tooltip = "Save options",
      action = withRom(app, function(a)
        a:showSaveOptionsModal()
      end),
      x = 0,
      y = 0,
      w = cell,
      h = cell,
    }),
    zoomOut = Button.new({
      icon = images.icons.icon_zoom_out or images.icons.icon_empty or images.icons.icon_scroll_toolbar_empty,
      tooltip = "Zoom out (Ctrl+scroll)",
      action = withRom(app, function(a)
        zoomFocusedByWheelStep(a, -1)
      end),
      x = 0,
      y = 0,
      w = cell,
      h = cell,
    }),
    zoomIn = Button.new({
      icon = images.icons.icon_zoom_in or images.icons.icon_empty or images.icons.icon_scroll_toolbar_empty,
      tooltip = "Zoom in (Ctrl+scroll)",
      action = withRom(app, function(a)
        zoomFocusedByWheelStep(a, 1)
      end),
      x = 0,
      y = 0,
      w = cell,
      h = cell,
    }),
    addGridColumn = Button.new({
      icon = images.icons.icon_new_col or images.icons.icon_empty or images.icons.icon_scroll_toolbar_empty,
      tooltip = "Add column to the right",
      action = withRom(app, function(a)
        local shift = isShiftHeld()
        if a.resizeFocusedWindowGrid then
          a:resizeFocusedWindowGrid({
            addColumn = not shift,
            removeColumn = shift,
          })
        end
      end),
      x = 0,
      y = 0,
      w = cell,
      h = cell,
      enabled = false,
    }),
    addGridRow = Button.new({
      icon = images.icons.icon_new_row or images.icons.icon_empty or images.icons.icon_scroll_toolbar_empty,
      tooltip = "Add row below",
      action = withRom(app, function(a)
        local shift = isShiftHeld()
        if a.resizeFocusedWindowGrid then
          a:resizeFocusedWindowGrid({
            addRow = not shift,
            removeRow = shift,
          })
        end
      end),
      x = 0,
      y = 0,
      w = cell,
      h = cell,
      enabled = false,
    }),
    cloneWindow = Button.new({
      icon = images.icons.icon_clone or images.icons.icon_empty or images.icons.icon_scroll_toolbar_empty,
      tooltip = "Clone focused window",
      action = withRom(app, function(a)
        if a.cloneFocusedWindow then
          a:cloneFocusedWindow()
        end
      end),
      x = 0,
      y = 0,
      w = cell,
      h = cell,
    }),
    copy = Button.new({
      icon = images.icons.icon_copy or images.icons.icon_empty or images.icons.icon_scroll_toolbar_empty,
      tooltip = "Copy",
      action = function()
        if app.performClipboardToolbarAction then
          app:performClipboardToolbarAction("copy")
        end
      end,
      x = 0,
      y = 0,
      w = cell,
      h = cell,
      enabled = false,
    }),
    cut = Button.new({
      icon = images.icons.icon_cut or images.icons.icon_empty or images.icons.icon_scroll_toolbar_empty,
      tooltip = "Cut",
      action = function()
        if app.performClipboardToolbarAction then
          app:performClipboardToolbarAction("cut")
        end
      end,
      x = 0,
      y = 0,
      w = cell,
      h = cell,
      enabled = false,
    }),
    paste = Button.new({
      icon = images.icons.icon_paste or images.icons.icon_empty or images.icons.icon_scroll_toolbar_empty,
      tooltip = "Paste",
      action = function()
        if app.performClipboardToolbarAction then
          app:performClipboardToolbarAction("paste")
        end
      end,
      x = 0,
      y = 0,
      w = cell,
      h = cell,
      enabled = false,
    }),
  }
end

local function hasOpenProject(app)
  return app and app.hasLoadedROM and app:hasLoadedROM() == true
end

local function quickButtonOrder(app)
  local order = { "open" }
  if hasOpenProject(app) then
    order[#order + 1] = "newWindow"
    order[#order + 1] = "save"
    order[#order + 1] = "copy"
    order[#order + 1] = "cut"
    order[#order + 1] = "paste"
    order[#order + 1] = "zoomOut"
    order[#order + 1] = "zoomIn"
    order[#order + 1] = "addGridColumn"
    order[#order + 1] = "addGridRow"
    order[#order + 1] = "cloneWindow"
  end
  return order
end

local function updateClipboardButtonStates(app)
  if not (app and app._appTopQuickButtons) then
    return
  end
  local actions = {
    copy = "copy",
    cut = "cut",
    paste = "paste",
  }
  for key, action in pairs(actions) do
    local button = app._appTopQuickButtons[key]
    if button then
      local state = app.getClipboardToolbarActionState and app:getClipboardToolbarActionState(action) or nil
      button.enabled = not not (state and state.allowed)
    end
  end
end

local function updateZoomButtonStates(app)
  if not (app and app._appTopQuickButtons) then
    return
  end
  local zoomOut = app._appTopQuickButtons.zoomOut
  local zoomIn = app._appTopQuickButtons.zoomIn
  if not (zoomOut and zoomIn) then
    return
  end
  local allow = false
  local wm = app.wm
  if wm and wm.getFocus then
    local focus = wm:getFocus()
    if focus
      and not focus._closed
      and not focus._minimized
      and not WindowCaps.isAnyPaletteWindow(focus)
      and type(focus.addZoomLevel) == "function"
    then
      allow = true
    end
  end
  zoomOut.enabled = allow
  zoomIn.enabled = allow
end

local function updateGridResizeButtons(app)
  if not (app and app._appTopQuickButtons) then
    return
  end
  local colBtn = app._appTopQuickButtons.addGridColumn
  local rowBtn = app._appTopQuickButtons.addGridRow
  if not (colBtn and rowBtn) then
    return
  end
  local WindowGridResizeController = require("controllers.window.window_grid_resize_controller")
  local shift = isShiftHeld()
  local wm = app.wm
  local focus = wm and wm.getFocus and wm:getFocus() or nil
  local allow = WindowGridResizeController.isGridResizeWindow(focus)

  colBtn.enabled = allow
  rowBtn.enabled = allow

  if allow then
    if shift then
      colBtn.icon = images.icons.icon_remove_col or colBtn.icon
      colBtn.tooltip = "Remove last column (Shift)"
      rowBtn.icon = images.icons.icon_remove_row or rowBtn.icon
      rowBtn.tooltip = "Remove last row (Shift)"
    else
      colBtn.icon = images.icons.icon_new_col or colBtn.icon
      colBtn.tooltip = "Add column to the right"
      rowBtn.icon = images.icons.icon_new_row or rowBtn.icon
      rowBtn.tooltip = "Add row below"
    end
  else
    colBtn.icon = images.icons.icon_new_col or colBtn.icon
    colBtn.tooltip = "Add column to the right"
    rowBtn.icon = images.icons.icon_new_row or rowBtn.icon
    rowBtn.tooltip = "Add row below"
  end
end

local function styleAppTopChromeButton(button)
  if not button then
    return
  end
  button.contentColor = colors:chromeTextIconsColor()
  button.literalContentColor = true
  button.iconRespectTheme = false
end

function M.clearDockLayouts(app)
  if not (app and app.wm and app.wm.getWindows) then
    return
  end
  for _, w in ipairs(app.wm:getWindows()) do
    local tb = w and w.specializedToolbar
    if tb then
      tb._dockLayout = nil
    end
  end
end

--- Compute strip height and docked toolbar layout. Call each frame from update().
function M.syncLayout(app)
  if not app then
    return
  end
  ensureQuickButtons(app)
  M.clearDockLayouts(app)

  local cell = math.max(UiScale.menuCellSize(), MIN_BAR_H)
  local canvasW = app.canvas and app.canvas:getWidth() or 0
  local quickLeftX = OUTER_MARGIN
  local x = quickLeftX
  local topY = OUTER_MARGIN
  local placedButtons = 0

  for _, key in ipairs(quickButtonOrder(app)) do
    local b = app._appTopQuickButtons[key]
    if b then
      if placedButtons > 0 then
        x = x + BUTTON_GAP
      end
      b:setPosition(x, topY)
      x = x + b.w
      placedButtons = placedButtons + 1
    end
  end
  updateClipboardButtonStates(app)
  updateZoomButtonStates(app)
  updateGridResizeButtons(app)

  local quickRightX = x
  local dockLeftX = quickRightX + SECTION_GAP
  local minStatusLeftX = math.floor(canvasW * STATUS_AREA_RATIO)
  local statusLeftX = math.max(minStatusLeftX, dockLeftX + SECTION_GAP)
  local statusRightX = math.max(statusLeftX, canvasW - OUTER_MARGIN)

  local totalH = math.max(MIN_BAR_H, topY + cell + OUTER_MARGIN)
  local dockedWin = nil
  local dockRightX = math.max(dockLeftX, statusLeftX - SECTION_GAP)

  if app.separateToolbar == true and app.wm and app.wm.getWindows then
    local maxDockedToolbarH = 0
    for _, win in ipairs(app.wm:getWindows() or {}) do
      if win and not win._closed and not win._minimized and win.specializedToolbar then
        maxDockedToolbarH = math.max(
          maxDockedToolbarH,
          measureDockedToolbarHeight(win.specializedToolbar, cell)
        )
      end
    end
    totalH = math.max(totalH, topY + maxDockedToolbarH + OUTER_MARGIN)
  end

  if app.separateToolbar == true and app.wm and app.wm.getFocus then
    local focus = app.wm:getFocus()
    if focus and not focus._closed and not focus._minimized and focus.specializedToolbar then
      dockedWin = focus
      local tb = focus.specializedToolbar
      tb._dockLayout = {
        leftX = dockLeftX,
        rightX = dockRightX,
        topY = topY,
        rowHeight = cell,
      }
      tb:updatePosition()
    end
  end

  app._appTopToolbarLayout = {
    totalH = totalH,
    dockedWin = dockedWin,
    quickLeftX = quickLeftX,
    quickRightX = quickRightX,
    quickTopY = topY,
    dockLeftX = dockLeftX,
    dockRightX = dockRightX,
    statusLeftX = statusLeftX,
    statusRightX = statusRightX,
    dockTopY = topY,
    cell = cell,
  }
end

--- Saved layout files store Y below the app top strip. After load, windows are built at those
--- coordinates; call once after toolbars exist to shift into full-canvas space. Toolbar height
--- is not tracked for live relayout of windows.
function M.applyLoadedLayoutYOffset(app)
  if not app or not app.wm then
    return
  end
  M.syncLayout(app)
  local oy = M.getContentOffsetY(app)
  if type(oy) ~= "number" or oy <= 0 then
    return
  end
  for _, w in ipairs(app.wm:getWindows() or {}) do
    if w and not w._closed and type(w.y) == "number" then
      w.y = w.y + oy
    end
  end
end

function M.draw(app)
  if not app then
    return
  end
  local lay = app._appTopToolbarLayout
  local h = (lay and lay.totalH) or MIN_BAR_H
  local cw = app.canvas and app.canvas:getWidth() or 0
  local statusLeftX = (lay and lay.statusLeftX) or math.floor(cw * STATUS_AREA_RATIO)
  local statusRightX = (lay and lay.statusRightX) or math.max(statusLeftX, cw - OUTER_MARGIN)
  local statusW = math.max(0, statusRightX - statusLeftX)
  local statusY = OUTER_MARGIN
  local quickLeftX = (lay and lay.quickLeftX) or OUTER_MARGIN
  local quickRightX = (lay and lay.quickRightX) or quickLeftX

  local barBg = colors:focusedChromeColor()
  love.graphics.setColor(barBg[1], barBg[2], barBg[3], 1)
  love.graphics.rectangle("fill", 0, 0, cw, h)

  ensureQuickButtons(app)
  for _, key in ipairs(quickButtonOrder(app)) do
    local b = app._appTopQuickButtons[key]
    if b then
      styleAppTopChromeButton(b)
      b:draw()
    end
  end

  if app.separateToolbar == true and lay and lay.dockedWin and lay.dockedWin.specializedToolbar then
    love.graphics.setScissor(lay.dockLeftX or 0, 0, math.max(0, (lay.dockRightX or statusLeftX) - (lay.dockLeftX or 0)), h)
    lay.dockedWin.specializedToolbar:draw()
    love.graphics.setScissor()
  end

  local statusText = tostring(app.lastEventText or app.statusText or "")
  local pad = 4
  local textW = math.max(0, statusW - (pad * 2))
  local textY = statusY + math.floor((STATUS_BG_H - love.graphics.getFont():getHeight()) / 2)
  local textX = statusRightX - pad - love.graphics.getFont():getWidth(statusText)
  local statusTint = colors:chromeTextIconsColor()
  love.graphics.setScissor(statusLeftX, statusY, statusW, STATUS_BG_H)
  love.graphics.setColor(statusTint[1], statusTint[2], statusTint[3], statusTint[4] or 1)
  if textW > 0 then
    Text.print(statusText, textX, textY, { color = statusTint, literalColor = true })
  end
  love.graphics.setScissor()
  love.graphics.setColor(colors.white)
end

local function inStatusArea(app, px)
  local lay = app and app._appTopToolbarLayout or nil
  local cw = app and app.canvas and app.canvas.getWidth and app.canvas:getWidth() or 0
  local statusLeftX = (lay and lay.statusLeftX) or math.floor(cw * STATUS_AREA_RATIO)
  return px >= statusLeftX
end

local function inDockArea(app, px)
  if inStatusArea(app, px) then
    return false
  end
  return true
end

local function pointInQuickButton(app, px, py)
  ensureQuickButtons(app)
  for _, key in ipairs(quickButtonOrder(app)) do
    local b = app._appTopQuickButtons[key]
    if b and b:contains(px, py) then
      return b
    end
  end
  return nil
end

function M.getTooltipAt(app, px, py)
  if not (app and px and py) then
    return nil
  end
  local h = M.getContentOffsetY(app)
  if py >= h then
    return nil
  end
  local b = pointInQuickButton(app, px, py)
  if b and b.tooltip and b.tooltip ~= "" then
    return { text = b.tooltip, immediate = false, key = b }
  end
  if app.separateToolbar == true and app.wm and app.wm.getFocus then
    local focus = app.wm:getFocus()
    local tb = focus and focus.specializedToolbar
    if tb and tb.getTooltipAt and tb:contains(px, py) then
      return tb:getTooltipAt(px, py)
    end
  end
  return nil
end

function M.containsPointer(app, px, py)
  if not (app and px and py) then
    return false
  end
  return py < M.getContentOffsetY(app)
end

function M.mousepressed(app, px, py, button)
  if not M.containsPointer(app, px, py) then
    return false
  end
  local b = pointInQuickButton(app, px, py)
  if b and button == 1 and b.enabled ~= false then
    b.pressed = true
    app._appTopPressedButton = b
    if b.action then
      b.action()
    end
    return true
  end
  if app.separateToolbar == true and app.wm and app.wm.getFocus then
    local focus = app.wm:getFocus()
    local tb = focus and focus.specializedToolbar
    if inDockArea(app, px) and focus and tb and PaletteLinkController.isPointInToolbarLinkHandle(tb, px, py) then
      if button == 2 then
        if PaletteLinkController.beginDrag(tb, button, px, py, focus, app.wm) then
          return true
        end
      else
        local UserInput = require("controllers.input")
        if UserInput.beginPaletteLinkContextFromAppTopBar(focus, px, py, button) then
          return true
        end
      end
    end
    if button == 1 and inDockArea(app, px) and tb and tb.mousepressed and tb:mousepressed(px, py, button) then
      return true
    end
  end
  return true
end

function M.mousereleasedQuickButtons(app, px, py, button)
  local pb = app._appTopPressedButton
  if not (pb and button == 1) then
    return false
  end
  pb.pressed = false
  app._appTopPressedButton = nil
  return true
end

function M.mousereleasedDockedToolbar(app, px, py, button)
  if not (app and app.separateToolbar == true and app.wm and app.wm.getFocus) then
    return false
  end
  local focus = app.wm:getFocus()
  local tb = focus and focus.specializedToolbar
  if inDockArea(app, px) and tb and tb.mousereleased and tb:mousereleased(px, py, button) then
    return true
  end
  return false
end

function M.mousemoved(app, px, py)
  if not M.containsPointer(app, px, py) then
    for _, key in ipairs(quickButtonOrder(app)) do
      local b = app._appTopQuickButtons and app._appTopQuickButtons[key]
      if b then
        b.hovered = false
      end
    end
    return false
  end
  local hit = pointInQuickButton(app, px, py)
  for _, key in ipairs(quickButtonOrder(app)) do
    local b = app._appTopQuickButtons and app._appTopQuickButtons[key]
    if b then
      b.hovered = (b == hit)
    end
  end
  if app.separateToolbar == true and app.wm and app.wm.getFocus then
    local focus = app.wm:getFocus()
    local tb = focus and focus.specializedToolbar
    if inDockArea(app, px) and tb and tb.mousemoved then
      tb:mousemoved(px, py)
    end
  end
  return hit ~= nil
end

return M
