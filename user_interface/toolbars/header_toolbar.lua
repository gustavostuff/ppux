-- header_toolbar.lua
-- Header toolbar for most windows (collapse + close)

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")
local DebugController = require("controllers.dev.debug_controller")
local ResolutionController = require("controllers.app.resolution_controller")

local TOOLBAR_PROXIMITY_PX = 8

local HeaderToolbar = {}
HeaderToolbar.__index = HeaderToolbar
setmetatable(HeaderToolbar, { __index = ToolbarBase })

function HeaderToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), HeaderToolbar)
  
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
    windowController:setFocus(window)
  end, "Collapse window")
  collapseBtn.isCloseButton = false  -- Mark as non-close button
  
  -- Store reference to collapse button so we can update its icon
  self.collapseButton = collapseBtn

  -- Create close button (X icon) - red
  local closeBtn = self:addButton(images.icons.icon_x, function()
    windowController:setFocus(window)
    self:_onClose()
  end, "Close window")
  closeBtn.isCloseButton = true  -- Mark as close button
  
  -- Update collapse icon based on current window state
  self:updateCollapseIcon()
  
  -- Update position
  self:updatePosition()
  
  return self
end

function HeaderToolbar:_isMouseNearToolbar(mouseX, mouseY)
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

function HeaderToolbar:_refreshVisibility(mouseX, mouseY)
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

function HeaderToolbar:_applyButtonBackgrounds()
  local focusedWindow = self.windowController and self.windowController.getFocus and self.windowController:getFocus() or nil
  local isFocused = (focusedWindow == self.window)
  local bg = isFocused and colors.blue or colors.gray20
  for _, button in ipairs(self.buttons) do
    button.bgColor = bg
    button.bgAlpha = 1
  end
end

function HeaderToolbar:_onMinimize()
  if not self.window or not self.windowController then return end

  if self.windowController.minimizeWindow and self.windowController:minimizeWindow(self.window) then
    if self.ctx then
      self.ctx.setStatus("Window minimized")
    end
  end
end

-- Override updatePosition for right-aligned header toolbar
function HeaderToolbar:updatePosition()
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
function HeaderToolbar:_layoutButtons()
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
  -- Last button added (close) goes to rightmost position, first button (collapse) to its left
  for i = #self.buttons, 1, -1 do
    local button = self.buttons[i]
    button:setPosition(x - button.w, itemY)
    x = button.x  -- Move x to the left of this button for next iteration
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
function HeaderToolbar:draw()
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
  
  -- Draw buttons (no background - transparent on header)
  for _, button in ipairs(self.buttons) do
    button:draw()
  end
end

-- Override contains to always allow interaction (header toolbars always visible)
function HeaderToolbar:contains(px, py)
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

-- Override mousepressed to not check focus (header toolbars always interactive)
function HeaderToolbar:mousepressed(x, y, button)
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

-- Override mousemoved to not check focus (header toolbars always interactive)
function HeaderToolbar:mousemoved(x, y)
  if not self:_refreshVisibility(x, y) then
    for _, b in ipairs(self.buttons) do
      b.hovered = false
    end
    return false
  end
  
  local btn = self:getButtonAt(x, y)
  
  -- Update hover states
  for _, b in ipairs(self.buttons) do
    b.hovered = (b == btn)
  end
  
  return btn ~= nil
end

function HeaderToolbar:mousereleased(x, y, button)
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
function HeaderToolbar:updateCollapseIcon()
  if not self.collapseButton or not self.window then return end
  
  -- Use "down" icon when collapsed, "up" icon when expanded
  if self.window._collapsed then
    self.collapseButton.icon = images.icons.icon_down
  else
    self.collapseButton.icon = images.icons.icon_up
  end
end

-- Called during draw to ensure icons are up-to-date
function HeaderToolbar:updateIcons()
  self:updateCollapseIcon()
end

-- Handle collapse action
function HeaderToolbar:_onCollapse()
  if not self.window then return end
  
  -- Toggle collapsed state
  self.window._collapsed = not self.window._collapsed
  
  -- Update collapse icon to reflect new state
  self:updateCollapseIcon()
  
  if self.ctx and self.ctx.setStatus then
    if self.window._collapsed then
      self.ctx.setStatus("Window collapsed")
    else
      self.ctx.setStatus("Window expanded")
    end
  end
end

-- Handle close action
function HeaderToolbar:_onClose()
  DebugController.log("info", "UI", "HeaderToolbar:_onClose - called")
  if not self.window then
    DebugController.log("info", "UI", "HeaderToolbar:_onClose - no window!")
    return
  end
  
  -- Ensure window has an ID
  if not self.window._id then
    DebugController.log("info", "UI", "HeaderToolbar:_onClose - window has no ID, generating one")
    -- Generate a unique ID if one doesn't exist
    local wm = self.windowController
    if wm then
      local windows = wm:getWindows()
      local maxId = 0
      for _, w in ipairs(windows) do
        if w._id and type(w._id) == "number" then
          maxId = math.max(maxId, w._id)
        end
      end
      self.window._id = maxId + 1
    else
      -- Fallback to timestamp-based ID
      self.window._id = "win_" .. tostring(love.timer.getTime())
    end
    DebugController.log("info", "UI", "HeaderToolbar:_onClose - generated ID: %s", tostring(self.window._id))
  end

  local wasClosed = (self.window._closed == true)
  local wasMinimized = (self.window._minimized == true)
  local wasFocused = false
  if self.windowController and self.windowController.getFocus then
    wasFocused = (self.windowController:getFocus() == self.window)
  end

  local closed = false
  if self.windowController and self.windowController.closeWindow then
    closed = self.windowController:closeWindow(self.window)
  else
    if not self.window._closed then
      self.window._closed = true
      self.window._minimized = false
      closed = true
    end
  end
  DebugController.log("info", "UI", "HeaderToolbar:_onClose - window marked as closed: %s", tostring(self.window._closed))

  if not closed then
    return
  end

  local app = self.ctx and self.ctx.app or nil
  local undoRedo = app and app.undoRedo or nil
  if undoRedo and undoRedo.addWindowEvent then
    undoRedo:addWindowEvent({
      type = "window_close",
      win = self.window,
      wm = self.windowController,
      prevClosed = wasClosed,
      prevMinimized = wasMinimized,
      prevFocused = wasFocused,
    })
  end
  
  if self.ctx and self.ctx.setStatus then
    self.ctx.setStatus("Window closed")
  end
  if self.ctx and self.ctx.showToast then
    local title = tostring((self.window and self.window.title) or "Untitled")
    self.ctx.showToast("warning", string.format("Removed window: %s", title))
  end
end

-- Note: Button drawing is now handled by Button:draw() method
-- Header toolbar buttons use the same drawing logic as other buttons

return HeaderToolbar
