-- Top-of-canvas strip: quick actions + optional docked focused-window toolbar ("Separate toolbar").
local colors = require("app_colors")
local Button = require("user_interface.button")
local images = require("images")
local UiScale = require("user_interface.ui_scale")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local Text = require("utils.text_utils")

local M = {}

local MIN_BAR_H = 15
local PAD_X = 0
local PAD_Y = 0
local GAP = 0
local QUICK_BUTTON_ORDER = { "newWindow", "open", "save" }
local STATUS_AREA_RATIO = 0.5

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
        app:setStatus("New window — choose a type")
        if app.showToast then
          app:showToast("info", "New window — choose a type")
        end
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
  }
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
  local statusLeftX = math.floor(canvasW * STATUS_AREA_RATIO)
  local x = PAD_X
  local topY = PAD_Y

  for _, key in ipairs(QUICK_BUTTON_ORDER) do
    local b = app._appTopQuickButtons[key]
    if b then
      b:setPosition(x, topY)
      x = x + b.w + GAP
    end
  end

  local totalH = math.max(MIN_BAR_H, topY + cell + PAD_Y)
  local dockedWin = nil
  local dockLeftX = x + GAP
  local dockRightX = math.max(dockLeftX, statusLeftX - 2)

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
    totalH = math.max(totalH, topY + maxDockedToolbarH + PAD_Y)
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
    dockLeftX = dockLeftX,
    dockRightX = dockRightX,
    statusLeftX = statusLeftX,
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

  love.graphics.setColor(colors.gray20)
  love.graphics.rectangle("fill", 0, 0, cw, h)
  love.graphics.setColor(colors.gray10)
  love.graphics.rectangle("fill", statusLeftX, 0, math.max(0, cw - statusLeftX), h)
  love.graphics.setColor(colors.white)

  ensureQuickButtons(app)
  for _, key in ipairs(QUICK_BUTTON_ORDER) do
    local b = app._appTopQuickButtons[key]
    if b then
      b:draw()
    end
  end

  if app.separateToolbar == true and lay and lay.dockedWin and lay.dockedWin.specializedToolbar then
    love.graphics.setScissor(0, 0, math.max(0, statusLeftX - 2), h)
    lay.dockedWin.specializedToolbar:draw()
    love.graphics.setScissor()
  end

  local statusText = tostring(app.lastEventText or app.statusText or "")
  local pad = 4
  local textX = statusLeftX + pad
  local textY = math.floor((h - love.graphics.getFont():getHeight()) / 2)
  local textW = math.max(0, cw - statusLeftX - (pad * 2))
  love.graphics.setScissor(statusLeftX, 0, math.max(0, cw - statusLeftX), h)
  love.graphics.setColor(colors.white)
  Text.drawScrollingText(statusText, textX, textY, textW, {
    speed = 8,
    pause = 1,
    key = "app_top_status",
  })
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
  for _, key in ipairs(QUICK_BUTTON_ORDER) do
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
  if b and button == 1 then
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
      if button == 1 then
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
    for _, key in ipairs(QUICK_BUTTON_ORDER) do
      local b = app._appTopQuickButtons and app._appTopQuickButtons[key]
      if b then
        b.hovered = false
      end
    end
    return false
  end
  local hit = pointInQuickButton(app, px, py)
  for _, key in ipairs(QUICK_BUTTON_ORDER) do
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
