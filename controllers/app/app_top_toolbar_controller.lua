-- Top-of-canvas strip: quick actions + optional docked focused-window toolbar ("Separate toolbar").
local colors = require("app_colors")
local Button = require("user_interface.button")
local images = require("images")
local UiScale = require("user_interface.ui_scale")
local PaletteLinkController = require("controllers.palette.palette_link_controller")

local M = {}

local MIN_BAR_H = 15
local PAD_X = 6
local PAD_Y = 2
local GAP = 4

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
        if app.showNewWindowModal and app:showNewWindowModal() then
          app:setStatus("Opened new window modal")
        end
      end,
      x = 0,
      y = 0,
      w = cell,
      h = cell,
    }),
    saveLua = Button.new({
      icon = images.icons.save,
      tooltip = "Save Lua project",
      action = withRom(app, function(a)
        a:saveProject()
      end),
      x = 0,
      y = 0,
      w = cell,
      h = cell,
    }),
    savePpux = Button.new({
      icon = images.icons.save,
      tooltip = "Save compressed .ppux project",
      action = withRom(app, function(a)
        a:saveEncodedProject()
      end),
      x = 0,
      y = 0,
      w = cell,
      h = cell,
    }),
    saveRom = Button.new({
      icon = images.icons.save,
      tooltip = "Save edited ROM",
      action = withRom(app, function(a)
        a:saveEdited()
      end),
      x = 0,
      y = 0,
      w = cell,
      h = cell,
    }),
    saveAll = Button.new({
      icon = images.icons.save,
      tooltip = "Save ROM, Lua project, and .ppux",
      action = withRom(app, function(a)
        a:saveAllArtifacts()
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
  local x = PAD_X
  local topY = PAD_Y

  for _, key in ipairs({ "newWindow", "saveLua", "savePpux", "saveRom", "saveAll" }) do
    local b = app._appTopQuickButtons[key]
    if b then
      b:setPosition(x, topY)
      x = x + b.w + GAP
    end
  end

  local totalH = math.max(MIN_BAR_H, topY + cell + PAD_Y)
  local dockedWin = nil
  local dockLeftX = x + GAP

  if app.separateToolbar == true and app.wm and app.wm.getFocus then
    local focus = app.wm:getFocus()
    if focus and not focus._closed and not focus._minimized and focus.specializedToolbar then
      dockedWin = focus
      local tb = focus.specializedToolbar
      tb._dockLayout = {
        leftX = dockLeftX,
        topY = topY,
        rowHeight = cell,
      }
      tb:updatePosition()
      totalH = math.max(totalH, topY + tb.h + PAD_Y)
    end
  end

  app._appTopToolbarLayout = {
    totalH = totalH,
    dockedWin = dockedWin,
    dockLeftX = dockLeftX,
    dockTopY = topY,
    cell = cell,
  }
end

function M.draw(app)
  if not app then
    return
  end
  local lay = app._appTopToolbarLayout
  local h = (lay and lay.totalH) or MIN_BAR_H
  local cw = app.canvas and app.canvas:getWidth() or 0

  love.graphics.setColor(colors.gray20)
  love.graphics.rectangle("fill", 0, 0, cw, h)
  love.graphics.setColor(colors.white)

  ensureQuickButtons(app)
  for _, key in ipairs({ "newWindow", "saveLua", "savePpux", "saveRom", "saveAll" }) do
    local b = app._appTopQuickButtons[key]
    if b then
      b:draw()
    end
  end

  if app.separateToolbar == true and lay and lay.dockedWin and lay.dockedWin.specializedToolbar then
    lay.dockedWin.specializedToolbar:draw()
  end
end

local function pointInQuickButton(app, px, py)
  ensureQuickButtons(app)
  for _, key in ipairs({ "newWindow", "saveLua", "savePpux", "saveRom", "saveAll" }) do
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
  if button ~= 1 then
    return true
  end
  local b = pointInQuickButton(app, px, py)
  if b then
    b.pressed = true
    app._appTopPressedButton = b
    return true
  end
  if app.separateToolbar == true and app.wm and app.wm.getFocus then
    local focus = app.wm:getFocus()
    local tb = focus and focus.specializedToolbar
    if focus and tb and button == 1 and PaletteLinkController.isPointInToolbarLinkHandle(tb, px, py) then
      local UserInput = require("controllers.input")
      if UserInput.beginPaletteLinkContextFromAppTopBar(focus, px, py, button, M.getContentOffsetY(app)) then
        return true
      end
    end
    if tb and tb.mousepressed and tb:mousepressed(px, py, button) then
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
  if pb:contains(px, py) and pb.action then
    pb.action()
  end
  return true
end

function M.mousereleasedDockedToolbar(app, px, py, button)
  if not (app and app.separateToolbar == true and app.wm and app.wm.getFocus) then
    return false
  end
  local focus = app.wm:getFocus()
  local tb = focus and focus.specializedToolbar
  if tb and tb.mousereleased and tb:mousereleased(px, py, button) then
    return true
  end
  return false
end

function M.mousemoved(app, px, py)
  if not M.containsPointer(app, px, py) then
    for _, key in ipairs({ "newWindow", "saveLua", "savePpux", "saveRom", "saveAll" }) do
      local b = app._appTopQuickButtons and app._appTopQuickButtons[key]
      if b then
        b.hovered = false
      end
    end
    return false
  end
  local hit = pointInQuickButton(app, px, py)
  for _, key in ipairs({ "newWindow", "saveLua", "savePpux", "saveRom", "saveAll" }) do
    local b = app._appTopQuickButtons and app._appTopQuickButtons[key]
    if b then
      b.hovered = (b == hit)
    end
  end
  if app.separateToolbar == true and app.wm and app.wm.getFocus then
    local focus = app.wm:getFocus()
    local tb = focus and focus.specializedToolbar
    if tb and tb.mousemoved then
      tb:mousemoved(px, py)
    end
  end
  return hit ~= nil
end

return M
