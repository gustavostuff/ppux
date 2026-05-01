-- chr_header_toolbar.lua
-- Header toolbar for CHR windows (collapse only, no close)

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")
local ResolutionController = require("controllers.app.resolution_controller")

local TOOLBAR_PROXIMITY_PX = 0

local ChrHeaderToolbar = {}
ChrHeaderToolbar.__index = ChrHeaderToolbar
setmetatable(ChrHeaderToolbar, { __index = ToolbarBase })

function ChrHeaderToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), ChrHeaderToolbar)
  
  self.ctx = ctx
  self.windowController = windowController
  
  -- Get header dimensions
  local hx, hy, hw, hh = window:getHeaderRect()
  self.h = hh
  
  -- Create minimize button (independent from collapse state)
  local minimizeBtn = self:addButton(images.icons.icon_minus, function()
    self:_onMinimize()
  end, "Minimize window")
  minimizeBtn.isCloseButton = false

  -- Create collapse button - blue, starts with "up" icon (window is expanded)
  local collapseBtn = self:addButton(images.icons.icon_up, function()
    self:_onCollapse()
  end, "Collapse window")
  collapseBtn.isCloseButton = false  -- Mark as non-close button
  
  -- Store reference to collapse button so we can update its icon
  self.collapseButton = collapseBtn

  -- Update collapse icon based on current window state
  self:updateCollapseIcon()
  
  -- Update position
  self:updatePosition()
  
  return self
end

function ChrHeaderToolbar:_isMouseNearToolbar(mouseX, mouseY)
  if not (mouseX and mouseY) then return false end
  if not self.window or not self.window.getHeaderRect then return false end
  local hx, hy, hw, hh = self.window:getHeaderRect()
  local pad = TOOLBAR_PROXIMITY_PX
  local x0 = hx - pad
  local y0 = hy - pad
  local x1 = hx + hw + pad
  local y1 = hy + hh + pad
  return mouseX >= x0 and mouseX <= x1 and mouseY >= y0 and mouseY <= y1
end

function ChrHeaderToolbar:_refreshVisibility(mouseX, mouseY)
  self:updatePosition()

  if mouseX == nil or mouseY == nil then
    local scaled = ResolutionController:getScaledMouse(true)
    mouseX = scaled and scaled.x or nil
    mouseY = scaled and scaled.y or nil
  end

  local near = self:_isMouseNearToolbar(mouseX, mouseY)
  if self.pressedButton then
    near = true
  end

  self.visible = near
  self.enabled = near
  return near
end

function ChrHeaderToolbar:_applyButtonBackgrounds()
  local focusedWindow = self.windowController and self.windowController.getFocus and self.windowController:getFocus() or nil
  local isFocused = (focusedWindow == self.window)
  local bg = isFocused and colors:focusedChromeColor() or colors:chromeBackgroundUnfocused()
  for _, button in ipairs(self.buttons) do
    button.bgColor = bg
    button.bgAlpha = 1
    if isFocused then
      button.contentColor = colors:chromeTextIconsColor()
      button.iconRespectTheme = false
      button.literalContentColor = true
    else
      button.contentColor = colors.textPrimary
      button.iconRespectTheme = false
      button.literalContentColor = false
    end
  end
end

function ChrHeaderToolbar:_onMinimize()
  if not self.window or not self.windowController then return end

  if self.windowController.minimizeWindow and self.windowController:minimizeWindow(self.window) then
    if self.ctx then
      self.ctx.app:setStatus("Window minimized")
    end
  end
end

-- Override updatePosition for right-aligned header toolbar
function ChrHeaderToolbar:updatePosition()
  if not self.window then return end
  local hx, hy, hw, hh = self.window:getHeaderRect()
  
  -- Ensure toolbar height is set (should match header height)
  if not self.h or self.h == 0 then
    self.h = hh
  end
  
  -- Position inside the header bar (right-aligned)
  self.y = hy
  
  -- Re-layout buttons when position changes
  self:_layoutButtons()
end

-- Override layout for right-aligned positioning
function ChrHeaderToolbar:_layoutButtons()
  if not self.window then return end
  
  -- Get header dimensions
  local hx, hy, hw, hh = self.window:getHeaderRect()
  
  -- Calculate total width of all buttons and labels
  local totalButtonWidth = 0
  for _, button in ipairs(self.buttons) do
    totalButtonWidth = totalButtonWidth + button.w
  end
  
  local totalLabelWidth = 0
  for _, label in ipairs(self.labels) do
    totalLabelWidth = totalLabelWidth + label.width
  end
  
  local totalWidth = totalButtonWidth + totalLabelWidth
  
  local itemY = self.y or hy
  
  -- Right-aligned: position from right edge of header
  local rightEdge = hx + hw
  local x = rightEdge
  
  -- Layout buttons from right to left
  for i = #self.buttons, 1, -1 do
    local button = self.buttons[i]
    button:setPosition(x - button.w, itemY)
    x = button.x
  end
  
  -- Then layout labels (right to left, if any)
  for i = #self.labels, 1, -1 do
    local label = self.labels[i]
    label.x = x - label.width
    label.y = itemY
    x = label.x
  end
  
  -- Update toolbar position and width
  self.x = x
  self.w = totalWidth
end

-- Override draw to not check focus (header toolbars always visible)
function ChrHeaderToolbar:draw()
  if not self:_refreshVisibility() then return end
  self:_applyButtonBackgrounds()
  
  -- Allow subclasses to update button icons (e.g., collapse icon state)
  if self.updateIcons then
    self:updateIcons()
  end
  
  -- Update label text if update function is provided
  for _, label in ipairs(self.labels) do
    if label.updateFn then
      label.text = label.updateFn() or label.text or ""
    end
  end
  
  -- Draw labels first
  for _, label in ipairs(self.labels) do
    self:_drawLabel(label)
  end
  
  -- Draw buttons
  for _, button in ipairs(self.buttons) do
    button:draw()
  end
end

-- Override contains to always allow interaction (header toolbars always visible)
function ChrHeaderToolbar:contains(px, py)
  if not self:_refreshVisibility(px, py) then return false end
  
  -- Check if point is within any button bounds
  for _, button in ipairs(self.buttons) do
    if px >= button.x and px <= button.x + button.w and
       py >= button.y and py <= button.y + button.h then
      return true
    end
  end
  -- Check if point is within any label bounds
  for _, label in ipairs(self.labels) do
    if px >= label.x and px <= label.x + label.width and
       py >= label.y and py <= label.y + label.h then
      return true
    end
  end
  return false
end

function ChrHeaderToolbar:mousepressed(x, y, button)
  if not self:_refreshVisibility(x, y) then return false end

  local btn = self:getButtonAt(x, y)
  if btn and button == 1 then
    btn.pressed = true
    self.pressedButton = btn
    return true
  end

  self.pressedButton = nil
  return false
end

function ChrHeaderToolbar:mousemoved(x, y)
  if not self:_refreshVisibility(x, y) then
    for _, b in ipairs(self.buttons) do
      b.hovered = false
    end
    return false
  end

  local btn = self:getButtonAt(x, y)
  for _, b in ipairs(self.buttons) do
    b.hovered = (b == btn)
  end
  return btn ~= nil
end

function ChrHeaderToolbar:mousereleased(x, y, button)
  self:_refreshVisibility(x, y)

  if self.pressedButton and button == 1 then
    local pressedBtn = self.pressedButton
    local releasedInside = pressedBtn:contains(x, y)
    pressedBtn.pressed = false
    self.pressedButton = nil
    self:_refreshVisibility(x, y)
    if releasedInside and pressedBtn.action then
      pressedBtn.action()
    end
    return true
  end

  return false
end

-- Update collapse button icon based on window state
function ChrHeaderToolbar:updateCollapseIcon()
  if not self.collapseButton or not self.window then return end
  
  -- Use "down" icon when collapsed, "up" icon when expanded
  if self.window._collapsed then
    self.collapseButton.icon = images.icons.icon_down
  else
    self.collapseButton.icon = images.icons.icon_up
  end
end

-- Called during draw to ensure icons are up-to-date
function ChrHeaderToolbar:updateIcons()
  self:updateCollapseIcon()
end

-- Handle collapse action
function ChrHeaderToolbar:_onCollapse()
  if not self.window then return end
  
  -- Toggle collapsed state
  self.window._collapsed = not self.window._collapsed
  
  -- Update collapse icon to reflect new state
  self:updateCollapseIcon()
  
  if self.ctx and self.ctx.app and self.ctx.app.setStatus then
    if self.window._collapsed then
      self.ctx.app:setStatus("Window collapsed")
    else
      self.ctx.app:setStatus("Window expanded")
    end
  end
end

-- Note: Button drawing is now handled by Button:draw() method
-- Header toolbar buttons use the same drawing logic as other buttons

return ChrHeaderToolbar
