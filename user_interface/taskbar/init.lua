local colors = require("app_colors")
local images = require("images")
local UiScale = require("user_interface.ui_scale")

local UserInput = require("controllers.input.input")
local Helpers = require("user_interface.taskbar.helpers")
local ModeIndicator = require("user_interface.taskbar.mode_indicator")
local Minimized = require("user_interface.taskbar.minimized")
local Menu = require("user_interface.taskbar.menu")

local Taskbar = {}
Taskbar.__index = Taskbar

local DEFAULT_CANVAS_W = 640
local DEFAULT_CANVAS_H = 360

ModeIndicator.install(Taskbar, Helpers)
Minimized.install(Taskbar, Helpers)
Menu.install(Taskbar, Helpers)

function Taskbar.new(app, data)
  data = data or {}
  local self = setmetatable({
    app = app,
    x = 0,
    y = 0,
    w = 0,
    h = data.h or UiScale.taskbarHeight(),
    paddingX = 0,
    paddingY = 0,
    spacing = 0,
    pressedButton = nil,
    buttons = {},
    minimizedWindows = {},
    minimizedButtonsByWindow = {},
    minimizedScrollOffset = 0,
    menuController = nil,
    menuButton = nil,
    sortAlphaAscending = true,
    sortKindAscending = true,
    sortAlphaButton = nil,
    sortKindButton = nil,
    minimizedScrollLeftButton = nil,
    minimizedScrollRightButton = nil,
    showSortButtons = false,
    minimizedScrollbarOpacity = 0,
    visibleMinimizedButtons = {},
    minimizedStripX = nil,
    minimizedStripW = 0,
    minimizedDrag = {
      button = nil,
      win = nil,
      startX = 0,
      startY = 0,
      active = false,
      reordered = false,
    },
    modeIndicatorPressed = false,
  }, Taskbar)

  local menuButton = Helpers.newTaskbarButton({
    icon = images.menu_button,
    iconRespectTheme = false,
    tooltip = "Menu",
    action = function()
      self:toggleMenu()
    end,
  })
  menuButton.fitIconWidth = true
  self.menuButton = menuButton

  self:_initWindowControls()
  self:_initMenu()

  self.buttons = {
    menuButton,
    self.sortAlphaButton,
    self.sortKindButton,
  }
  self:_refreshMenuItems()
  return self
end

function Taskbar:updateLayout(canvasW, canvasH)
  local resolvedW = tonumber(canvasW)
  local resolvedH = tonumber(canvasH)
  if (not resolvedW or resolvedW <= 0) or (not resolvedH or resolvedH <= 0) then
    local canvas = self.app and self.app.canvas or nil
    if canvas and canvas.getWidth and canvas.getHeight then
      resolvedW = tonumber(canvas:getWidth()) or resolvedW
      resolvedH = tonumber(canvas:getHeight()) or resolvedH
    end
  end
  if not resolvedW or resolvedW <= 0 then
    resolvedW = (self.w and self.w > 0) and self.w or DEFAULT_CANVAS_W
  end
  if not resolvedH or resolvedH <= 0 then
    resolvedH = (self.y and self.h and self.y >= 0) and (self.y + self.h) or DEFAULT_CANVAS_H
  end

  self.w = resolvedW
  self.y = resolvedH - self.h
  if not (self.menuController and (self.menuController:isVisible() or self.menuController:hasPressedButton())) then
    self:_refreshMenuAvailability()
  end

  self:_buildVisibleToolbarButtons()

  local buttonSize = self.h
  local x = self.x + self.paddingX
  local y = self.y + self.paddingY
  self.visibleMinimizedButtons = {}
  self.minimizedStripX = nil
  self.minimizedStripW = 0

  for _, button in ipairs(self.buttons) do
    local isMinimizedButton = (button.isMinimizedWindowButton == true)
    local isIconOnly = (button.icon ~= nil) and (button.text == nil)
    local buttonW = buttonSize
    local buttonH = buttonSize
    if isIconOnly then
      if button._explicitW then
        buttonW = button.w
      elseif button.icon and button.icon.getWidth then
        local mappedW = UiScale.mapStandardButtonSize(button.icon:getWidth())
        buttonW = mappedW or button.icon:getWidth()
      end
      if button._explicitH then
        buttonH = button.h
      elseif button.icon and button.icon.getHeight then
        local mappedH = UiScale.mapStandardButtonSize(button.icon:getHeight())
        buttonH = mappedH or button.icon:getHeight()
      end
    elseif button.fitIconWidth and button.icon and button.icon.getWidth then
      local iconW = UiScale.mapStandardButtonSize(button.icon:getWidth()) or button.icon:getWidth()
      buttonW = math.max(buttonSize, iconW)
    end
    button:setSize(buttonW, buttonH)
    button:setPosition(x, y)
    if isMinimizedButton then
      self.visibleMinimizedButtons[#self.visibleMinimizedButtons + 1] = button
      if not self.minimizedStripX then
        self.minimizedStripX = x
      end
      self.minimizedStripW = (x + buttonW) - (self.minimizedStripX or x)
    end
    x = x + buttonW + self.spacing
  end

  for _, btn in pairs(self.minimizedButtonsByWindow) do
    local isVisible = false
    for _, visibleBtn in ipairs(self.buttons) do
      if visibleBtn == btn then
        isVisible = true
        break
      end
    end
    if not isVisible then
      btn.hovered = false
      btn.pressed = false
    end
  end

  if self.menuController and self.menuController:isVisible() then
    local panelX, panelY = self:_getMenuAnchor()
    self.menuController:setPosition(panelX, panelY)
  end
end

function Taskbar:getTopY()
  return self.y
end

function Taskbar:contains(px, py)
  local inBar = px >= self.x and px <= self.x + self.w and
    py >= self.y and py <= self.y + self.h
  if inBar then return true end
  if self.menuController and self.menuController:isVisible() and self.menuController:contains(px, py) then
    return true
  end
  return false
end

function Taskbar:getButtonAt(px, py)
  for _, button in ipairs(self.buttons) do
    if button.isMinimizedScrollButton and button.scrollEnabled == false then
      goto continue
    end
    if button:contains(px, py) then
      return button
    end
    ::continue::
  end
  return nil
end

function Taskbar:getTooltipAt(px, py)
  if self.menuController and self.menuController:isVisible() and self.menuController:contains(px, py) then
    local panelBtn = self.menuController:getButtonAt(px, py)
    if panelBtn and panelBtn.tooltip and panelBtn.tooltip ~= "" then
      return {
        text = panelBtn.tooltip,
        immediate = (panelBtn.tooltipImmediate == true),
        key = panelBtn,
      }
    end
  end

  local btn = self:getButtonAt(px, py)
  if not btn or not btn.tooltip or btn.tooltip == "" then
    return nil
  end

  local text = btn.tooltip
  local immediate = (btn.tooltipImmediate == true)
  if btn.isMinimizedWindowButton then
    local win = btn.minimizedWindow
    if win and win.title and tostring(win.title) ~= "" then
      text = tostring(win.title)
    end
    immediate = true
  end

  return {
    text = text,
    immediate = immediate,
    key = btn,
  }
end

function Taskbar:isInteractiveAt(px, py)
  if self.menuController and self.menuController:isVisible() and self.menuController:contains(px, py) then
    return self.menuController:getButtonAt(px, py) ~= nil
  end

  if self:getButtonAt(px, py) then
    return true
  end

  return self:_modeIndicatorContains(px, py)
end

function Taskbar:mousepressed(x, y, button)
  if self.menuController and self.menuController:isVisible() and self.menuController:contains(x, y) then
    return self.menuController:mousepressed(x, y, button)
  end

  if (not self:contains(x, y)) then
    if self.menuController and self.menuController:isVisible() and button == 1 then
      self.menuController:hide()
    end
    return false
  end

  if button == 2 or button == 3 then
    local btn = self:getButtonAt(x, y)
    if btn and btn.isMinimizedWindowButton and btn.minimizedWindow then
      if self.app and self.app.hideAppContextMenus then
        self.app:hideAppContextMenus()
      end
      if UserInput.beginTaskbarMinimizedWindowContextMenu(btn.minimizedWindow, x, y, button) then
        return true
      end
    end
  end

  if button == 1 then
    local btn = self:getButtonAt(x, y)
    if btn then
      self.modeIndicatorPressed = false
      btn.pressed = true
      self.pressedButton = btn
      if btn.isMinimizedWindowButton then
        self.minimizedDrag = {
          button = btn,
          win = btn.minimizedWindow,
          startX = x,
          startY = y,
          active = false,
          reordered = false,
        }
      else
        self.minimizedDrag = {
          button = nil, win = nil, startX = 0, startY = 0, active = false, reordered = false
        }
      end
    else
      self.pressedButton = nil
      self.modeIndicatorPressed = self:_modeIndicatorContains(x, y)
      self.minimizedDrag = {
        button = nil, win = nil, startX = 0, startY = 0, active = false, reordered = false
      }
    end
  end

  return true
end

function Taskbar:mousereleased(x, y, button)
  if self.menuController and self.menuController:isVisible()
    and (self.menuController:contains(x, y) or self.menuController:hasPressedButton()) then
    return self.menuController:mousereleased(x, y, button)
  end

  local consumed = false
  local dragState = self.minimizedDrag or {}
  local modeIndicatorClicked = false

  if button == 1 and self.pressedButton then
    consumed = true
    local pressedBtn = self.pressedButton
    local releasedBtn = self:getButtonAt(x, y)
    local cancelClick = (dragState.button == pressedBtn) and (dragState.active or dragState.reordered)
    if (not cancelClick) and releasedBtn == pressedBtn and pressedBtn.action then
      pressedBtn.action()
    end
  elseif button == 1 and self.modeIndicatorPressed then
    consumed = true
    modeIndicatorClicked = self:_modeIndicatorContains(x, y)
  elseif self:contains(x, y) then
    consumed = true
  end

  for _, b in ipairs(self.buttons) do
    b.pressed = false
  end
  self.pressedButton = nil
  self.modeIndicatorPressed = false
  self.minimizedDrag = {
    button = nil, win = nil, startX = 0, startY = 0, active = false, reordered = false
  }
  if modeIndicatorClicked then
    self:_toggleMode()
  end

  return consumed
end

function Taskbar:mousemoved(x, y)
  self:_handleMinimizedDrag(x, y)

  local inBar = self:contains(x, y)
  local hovered = inBar and self:getButtonAt(x, y) or nil
  for _, b in ipairs(self.buttons) do
    b.hovered = (b == hovered)
  end
  if self.menuController then
    self.menuController:mousemoved(x, y)
  end
end

function Taskbar:draw(eventText)
  local c = colors:focusedChromeColor()
  love.graphics.setColor(c[1], c[2], c[3], 1)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

  for _, b in ipairs(self.buttons) do
    local hot = b.enabled ~= false and (b.hovered or b.pressed)
    b.contentColor = hot and colors:chromeTextIconsColorFocused() or colors:chromeTextIconsColorNonFocused()
    b.literalContentColor = true
    b.iconRespectTheme = false
    b:draw()
  end

  self:_drawModeIndicator()

  if self:_hasMinimizedOverflow()
      and (self.minimizedScrollbarOpacity or 0) > 0
      and (self.minimizedStripX and self.minimizedStripW and self.minimizedStripW > 0) then
    local total = #self.minimizedWindows
    local visible = math.min(Minimized.MINIMIZED_VISIBLE_MAX, total)
    local maxScroll = math.max(1, total - visible)
    local frac = visible / total
    local trackX = self.minimizedStripX
    local trackW = self.minimizedStripW
    local thumbW = math.max(2, math.floor(trackW * frac))
    local posFrac = (self.minimizedScrollOffset or 0) / maxScroll
    local thumbX = math.floor(trackX + posFrac * math.max(0, trackW - thumbW))
    local thumbY = self.y + self.h - 2
    local wc = colors:chromeTextIconsColorNonFocused()
    love.graphics.setColor(wc[1], wc[2], wc[3], self.minimizedScrollbarOpacity or 0)
    love.graphics.rectangle("fill", thumbX, thumbY, thumbW, 2)
    love.graphics.setColor(colors.white)
  end

  if self.menuController then
    if self.menuController.update then
      self.menuController:update()
    end
    self.menuController:draw()
  end

  self:_drawStatusWithBrushIndicator(eventText, { drawStatusText = false, drawBrush = false })
  love.graphics.setColor(colors.white)
end

return Taskbar
