-- toolbar_base.lua
-- Base class for all toolbars

local colors = require("app_colors")
local Button = require("user_interface.button")

local images = require("images")
local DebugController = require("controllers.dev.debug_controller")
local SpaceHighlightController = require("controllers.window.space_highlight_controller")
local Timer = require("utils.timer_utils")

local ToolbarBase = {}
ToolbarBase.__index = ToolbarBase

local _layerLabelId = 0

local function canInteractWhenUnfocused(self)
  return self and self.allowWhenUnfocused == true
end

local function isToolbarFocusAllowed(self)
  if not self or not self.window or not self.windowController then
    return false
  end
  if canInteractWhenUnfocused(self) then
    return true
  end
  return self.window == self.windowController:getFocus()
end

function ToolbarBase.new(window, data)
  data = data or {}
  _layerLabelId = _layerLabelId + 1
  local layerLabelShowDuration = 1.0
  local layerLabelFadeDuration = 1.0
  local itemCountLabelShowDuration = 0.0
  local itemCountLabelFadeDuration = 1.0
  if type(data.layerLabelShowDuration) == "number" then
    layerLabelShowDuration = data.layerLabelShowDuration
  end
  if type(data.layerLabelFadeDuration) == "number" then
    layerLabelFadeDuration = data.layerLabelFadeDuration
  end
  if type(data.itemCountLabelShowDuration) == "number" then
    itemCountLabelShowDuration = data.itemCountLabelShowDuration
  end
  if type(data.itemCountLabelFadeDuration) == "number" then
    itemCountLabelFadeDuration = data.itemCountLabelFadeDuration
  end

  local self = setmetatable({
    window = window,  -- Reference to the window this toolbar belongs to
    x = data.x or 0,
    y = data.y or 0,
    w = data.w or 0,
    h = data.h or 0,
    visible = data.visible ~= false,  -- Default to visible
    enabled = data.enabled ~= false,  -- Default to enabled
    buttons = {},  -- Array of button objects
    labels = {},   -- Array of label objects
    pressedButton = nil,  -- Track which button is currently pressed
    layerLabelMarkName = "layerLabel_" .. tostring(_layerLabelId),
    layerLabelOverrideText = nil,
    layerLabelShowDuration = layerLabelShowDuration,
    layerLabelFadeDuration = layerLabelFadeDuration,
    itemCountLabelMarkName = "itemCountLabel_" .. tostring(_layerLabelId),
    itemCountLabelShowDuration = itemCountLabelShowDuration,
    itemCountLabelFadeDuration = itemCountLabelFadeDuration,
    itemCountLabelSpaceDown = false,
  }, ToolbarBase)
  
  return self
end

-- Update toolbar position based on window header
-- Specialized toolbars (left-aligned) are positioned above header
-- Header toolbars (right-aligned) override this method
function ToolbarBase:updatePosition()
  if not self.window then return end
  local hx, hy, hw, hh = self.window:getHeaderRect()
  
  -- Ensure toolbar height is set (should match header height)
  if not self.h or self.h == 0 then
    self.h = hh
  end
  
  -- Position above the header bar (for specialized toolbars)
  self.y = hy - self.h
  
  -- Re-layout buttons when position changes
  self:_layoutButtons()
end

-- Add a button to the toolbar
function ToolbarBase:addButton(icon, action, tooltip)
  local button = Button.new({
    icon = icon,  -- Image object
    action = action,  -- Function to call when clicked
    tooltip = tooltip or "",
    x = 0,  -- Will be set by layout
    y = 0,
  })
  
  table.insert(self.buttons, button)
  self:_layoutButtons()
  
  return button
end

function ToolbarBase:addTextButton(text, action, tooltip, opts)
  opts = opts or {}
  local button = Button.new({
    text = text or "",
    action = action,
    tooltip = tooltip or "",
    x = 0,
    y = 0,
    w = opts.w or self.h,
    h = opts.h or self.h,
    bgColor = opts.bgColor,
    bgAlpha = opts.bgAlpha,
    transparent = opts.transparent,
  })

  table.insert(self.buttons, button)
  self:_layoutButtons()
  return button
end

-- Add a label to the toolbar
function ToolbarBase:addLabel(text, width, updateFn)
  local label = {
    text = text or "",
    width = width or self.h * 2,  -- Default width is 2x button size
    updateFn = updateFn,  -- Optional function to update text dynamically
    x = 0,  -- Will be set by layout
    y = 0,
    h = self.h,  -- Label height = toolbar height
    renderInContent = false,  -- If true, label will be drawn in window content instead of toolbar
  }
  
  table.insert(self.labels, label)
  self:_layoutButtons()
  
  return label
end

  -- Layout buttons and labels horizontally (left to right: labels first, then buttons)
  function ToolbarBase:_layoutButtons()
    if not self.window then return end
    
    -- Get header dimensions
    local hx, hy, hw, hh = self.window:getHeaderRect()
    
    -- Calculate total width of all buttons and labels (exclude labels that render in content)
    local totalButtonWidth = 0
    for _, button in ipairs(self.buttons) do
      totalButtonWidth = totalButtonWidth + button.w
    end
    
    local totalLabelWidth = 0
    for _, label in ipairs(self.labels) do
      if not label.renderInContent then
        totalLabelWidth = totalLabelWidth + label.width
      end
    end
    
    local totalWidth = totalButtonWidth + totalLabelWidth
    
    -- Ensure we have valid self.y from updatePosition
    local itemY = self.y or hy
    
    -- Position from left edge of window (aligned with window border)
    local x = hx - 1 -- minus 1 because of the window border
    
    -- Layout labels first (left side, skip labels that render in content)
    for _, label in ipairs(self.labels) do
      if not label.renderInContent then
        label.x = x
        label.y = itemY
        x = x + label.width
      end
    end
    
    -- Then layout buttons (right side)
    for _, button in ipairs(self.buttons) do
      button:setPosition(x, itemY)
      x = x + button.w
    end
    
    -- Update toolbar position and width
    self.x = hx  -- Aligned with window's left edge
    self.w = totalWidth
  end

-- Check if a point is inside the toolbar (check all buttons and labels)
function ToolbarBase:contains(px, py)
  if not self.visible then return false end
  
  -- For specialized toolbars, check if window is focused
  if not self.window or not self.windowController then return false end
  if not isToolbarFocusAllowed(self) then return false end
  
  -- Check if point is within any button bounds
  for _, button in ipairs(self.buttons) do
    if button:contains(px, py) then
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

-- Get button at a point
function ToolbarBase:getButtonAt(px, py)
  if not self:contains(px, py) then return nil end
  
  for _, button in ipairs(self.buttons) do
    if button:contains(px, py) then
      return button
    end
  end
  
  return nil
end

function ToolbarBase:getTooltipAt(px, py)
  local btn = self:getButtonAt(px, py)
  if not btn then return nil end
  if not btn.tooltip or btn.tooltip == "" then return nil end
  return {
    text = btn.tooltip,
    immediate = (btn.tooltipImmediate == true),
    key = btn,
  }
end

-- Get label at a point
function ToolbarBase:getLabelAt(px, py)
  if not self:contains(px, py) then return nil end
  
  for _, label in ipairs(self.labels) do
    if px >= label.x and px <= label.x + label.width and
       py >= label.y and py <= label.y + label.h then
      return label
    end
  end
  
  return nil
end

-- Handle mouse press
function ToolbarBase:mousepressed(x, y, button)
  if not self.enabled or not self.visible then
    DebugController.log("info", "UI", "ToolbarBase:mousepressed - toolbar not enabled/visible (enabled: %s, visible: %s)", tostring(self.enabled), tostring(self.visible))
    return false
  end
  
  -- For specialized toolbars, check if window is focused
  if not self.window or not self.windowController then return false end
  if not isToolbarFocusAllowed(self) then return false end
  
  -- Update position before checking (toolbar might have moved)
  self:updatePosition()
  
  DebugController.log("info", "UI", "ToolbarBase:mousepressed - mouse: (%.1f, %.1f), toolbar: (%.1f, %.1f, %.1f, %.1f), button: %d", x, y, self.x, self.y, self.w, self.h, button)
  DebugController.log("info", "UI", "ToolbarBase:contains? %s", tostring(self:contains(x, y)))
  
  local btn = self:getButtonAt(x, y)
  if btn and button == 1 then
    DebugController.log("info", "UI", "ToolbarBase:mousepressed - button found! x: %.1f, y: %.1f, w: %.1f, h: %.1f", btn.x, btn.y, btn.w, btn.h)
    btn.pressed = true
    self.pressedButton = btn  -- Remember which button was pressed
    return true  -- Consume the event
  end
  
  -- Check if click is on a label - consume the event to prevent focus loss
  local label = self:getLabelAt(x, y)
  if label and button == 1 then
    DebugController.log("info", "UI", "ToolbarBase:mousepressed - label clicked, consuming event to maintain focus")
    return true  -- Consume the event to prevent focus loss
  end
  
  DebugController.log("info", "UI", "ToolbarBase:mousepressed - no button found. Button count: %d", #self.buttons)
  for i, b in ipairs(self.buttons) do
    DebugController.log("info", "UI", "  Button %d: (%.1f, %.1f, %.1f, %.1f)", i, b.x, b.y, b.w, b.h)
  end
  
  self.pressedButton = nil
  return false
end

-- Handle mouse release
function ToolbarBase:mousereleased(x, y, button)
  if not self.enabled or not self.visible then
    DebugController.log("info", "UI", "ToolbarBase:mousereleased - toolbar not enabled/visible")
    return false
  end
  
  -- Update position before checking (toolbar might have moved)
  self:updatePosition()
  
  DebugController.log("info", "UI", "ToolbarBase:mousereleased - mouse: (%.1f, %.1f), pressedButton: %s, button: %d", x, y, self.pressedButton and "set" or "nil", button)
  
  -- If we have a pressed button tracked, only trigger on release inside the same button.
  if self.pressedButton and button == 1 then
    local pressedBtn = self.pressedButton
    local releasedInside = pressedBtn:contains(x, y)
    DebugController.log("info", "UI", "ToolbarBase:mousereleased - pressed button release inside? %s", tostring(releasedInside))
    pressedBtn.pressed = false
    self.pressedButton = nil
    
    -- Trigger the action only when the mouse is released over the same button.
    if releasedInside and pressedBtn.action then
      DebugController.log("info", "UI", "ToolbarBase:mousereleased - calling button action")
      pressedBtn.action()
      DebugController.log("info", "UI", "ToolbarBase:mousereleased - button action completed")
    elseif not releasedInside then
      DebugController.log("info", "UI", "ToolbarBase:mousereleased - release outside button, action canceled")
    else
      DebugController.log("info", "UI", "ToolbarBase:mousereleased - button has no action!")
    end
    
    -- Reset all button states
    for _, b in ipairs(self.buttons) do
      b.pressed = false
    end
    return true  -- Consume the event
  end
  
  DebugController.log("info", "UI", "ToolbarBase:mousereleased - no pressed button or wrong button (%d)", button)
  
  -- Reset pressed state for all buttons
  for _, b in ipairs(self.buttons) do
    b.pressed = false
  end
  self.pressedButton = nil
  
  return false
end

-- Handle mouse move (for hover state)
function ToolbarBase:mousemoved(x, y)
  if not self.enabled or not self.visible then return false end
  
  -- For specialized toolbars, check if window is focused
  if not self.window or not self.windowController then return false end
  if not isToolbarFocusAllowed(self) then 
    -- Clear hover states if not focused
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

-- Draw the toolbar
function ToolbarBase:draw()
  if not self.visible then return end
  
  -- Check if window is focused (specialized toolbars only show when focused)
  if not self.window or not self.windowController then return end
  if not isToolbarFocusAllowed(self) then return end
  
  -- Update position before drawing (this also re-layouts buttons)
  self:updatePosition()
  
  -- Draw gray20 background covering toolbar width
  love.graphics.setColor(colors.blue)
  love.graphics.rectangle("fill",
    self.x - 1, -- minus 1 because of the window border
    self.y,
    self.w,
    self.h
  )
  love.graphics.setColor(colors.white)
  
  -- Allow subclasses to update button icons (e.g., collapse icon state)
  self:updateIcons()
  
  -- Update label text if update function is provided
  for _, label in ipairs(self.labels) do
    if label.updateFn then
      label.text = label.updateFn() or label.text or ""
    end
  end
  
  -- Draw labels first (skip labels that render in content area)
  for _, label in ipairs(self.labels) do
    if not label.renderInContent then
      self:_drawLabel(label)
    end
  end
  
  -- Draw buttons
  for _, button in ipairs(self.buttons) do
    button:draw()
  end
end

-- Draw a label
function ToolbarBase:_drawLabel(label)
  local x, y, w, h = label.x, label.y, label.width, label.h
  
  -- All labels get gray10 background with exact size 45x13
  local labelW = 45
  local labelH = 15
  
  local labelX = x + (w - labelW) / 2  -- Center horizontally within allocated width
  local labelY = y + (h - labelH) / 2  -- Center vertically
  
  love.graphics.setColor(colors.white)
  -- Draw label text (centered within the box)
  if label.text and label.text ~= "" then
    local font = love.graphics.getFont()
    local textW = font:getWidth(label.text)
    local textH = font:getHeight()
    local textX = labelX + (labelW - textW) / 2  -- Center horizontally
    local textY = labelY + (labelH - textH) / 2  -- Center vertically
    love.graphics.print(label.text, textX, textY)
  end
  
  love.graphics.setColor(colors.white)
end

-- Note: Button drawing is now handled by Button:draw() method in user_interface/button.lua

-- Draw layer label in window content area (called from Window:draw)
function ToolbarBase:drawLayerLabelInContent()
  -- Content labels should only render for the focused window.
  if self.windowController and self.windowController.getFocus then
    local focused = self.windowController:getFocus()
    if focused ~= self.window and self.allowContentLabelWhenUnfocused ~= true then
      return
    end
  end

  -- Find the layer label
  local layerLabel = nil
  for _, label in ipairs(self.labels) do
    if label.renderInContent then
      layerLabel = label
      break
    end
  end
  
  if not layerLabel or not self.window then return end
  
  -- Update label text if update function is provided
  if layerLabel.updateFn then
    layerLabel.text = layerLabel.updateFn() or layerLabel.text or ""
  end

  local function alphaFromElapsed(elapsed, showDuration, fadeDuration)
    if not elapsed then return nil end
    if elapsed > (showDuration + fadeDuration) then return nil end
    if elapsed <= showDuration then return 1.0 end
    local t = (elapsed - showDuration) / fadeDuration
    return 1.0 - math.max(0, math.min(1, t))
  end

  local function drawContentLabel(text, alpha)
    if not text or text == "" then return end
    local sx, sy = self.window:getScreenRect()
    local margin = 4
    local labelX = sx + margin
    local labelY = sy + margin
    local TU = require("utils.text_utils")
    TU.print(text, labelX, labelY, {
      outline = true,
      color = { colors.white[1], colors.white[2], colors.white[3], alpha or 1.0 }
    })
  end

  local function getLayerItemCountText()
    local li = (self.window.getActiveLayerIndex and self.window:getActiveLayerIndex()) or self.window.activeLayer or 1
    local L = self.window.layers and self.window.layers[li]
    if not L then return nil end

    if L.kind == "sprite" then
      local count = 0
      for _, item in ipairs(L.items or {}) do
        if item and item.removed ~= true then
          count = count + 1
        end
      end
      local suffix = (count == 1) and "sprite" or "sprites"
      return string.format("%d %s", count, suffix)
    end

    local count = 0
    local removed = L.removedCells
    for idx, item in pairs(L.items or {}) do
      if item ~= nil and not (removed and removed[idx]) then
        count = count + 1
      end
    end
    local suffix = (count == 1) and "tile" or "tiles"
    return string.format("%d %s", count, suffix)
  end

  -- Space-toggle item count label: visible while active; fades out on deactivation.
  local spaceDown = SpaceHighlightController.isSpaceHighlightActive()
  if spaceDown then
    self.itemCountLabelSpaceDown = true
    drawContentLabel(getLayerItemCountText(), 1.0)
    return
  end
  if self.itemCountLabelSpaceDown then
    self.itemCountLabelSpaceDown = false
    Timer.mark(self.itemCountLabelMarkName)
  end
  local itemCountAlpha = alphaFromElapsed(
    Timer.elapsed(self.itemCountLabelMarkName),
    self.itemCountLabelShowDuration,
    self.itemCountLabelFadeDuration
  )
  if itemCountAlpha and itemCountAlpha > 0 then
    drawContentLabel(getLayerItemCountText(), itemCountAlpha)
    return
  end

  -- Default layer index label flash.
  local layerAlpha = alphaFromElapsed(
    Timer.elapsed(self.layerLabelMarkName),
    self.layerLabelShowDuration,
    self.layerLabelFadeDuration
  )
  if layerAlpha and layerAlpha > 0 then
    local layerText = self.layerLabelOverrideText or layerLabel.text
    drawContentLabel(layerText, layerAlpha)
  end
end

function ToolbarBase:triggerLayerLabelFlash(options)
  if type(options) == "string" then
    self.layerLabelOverrideText = options
  elseif type(options) == "table" then
    if options.text ~= nil then
      self.layerLabelOverrideText = options.text
    elseif options.clearOverride ~= false then
      self.layerLabelOverrideText = nil
    end
  else
    self.layerLabelOverrideText = nil
  end

  Timer.mark(self.layerLabelMarkName)
end

function ToolbarBase:triggerLayerLabelTextFlash(text)
  if type(text) ~= "string" or text == "" then return end
  self:triggerLayerLabelFlash({ text = text })
end

-- Empty updateIcons method - can be overridden by subclasses to update button icons
function ToolbarBase:updateIcons()
  -- Default implementation does nothing
end

return ToolbarBase
