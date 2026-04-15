-- toolbar_base.lua
-- Base class for all toolbars

local colors = require("app_colors")
local Button = require("user_interface.button")
local UiScale = require("user_interface.ui_scale")
local Text = require("utils.text_utils")

local images = require("images")
local DebugController = require("controllers.dev.debug_controller")
local SpaceHighlightController = require("controllers.window.space_highlight_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local Timer = require("utils.timer_utils")
local PaletteLinkController = require("controllers.palette.palette_link_controller")

local ToolbarBase = {}
ToolbarBase.__index = ToolbarBase

local _layerLabelId = 0

local function isButtonVisible(button)
  return button and button.hidden ~= true
end

local function drawRoundedToolbarStencil(x, y, w, h)
  if w <= 0 or h <= 0 then
    return false
  end
  love.graphics.stencil(function()
    love.graphics.rectangle("fill", x, y, w, h, 2, 2)
  end, "replace", 1, true)
  love.graphics.setStencilTest("greater", 0)
  return true
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
    rowHeight = data.rowHeight or 0,
    buttonsPerRow = tonumber(data.buttonsPerRow) or nil,
    useButtonRows = (data.useButtonRows ~= false),
    _layoutRowWidths = {},
  }, ToolbarBase)
  
  return self
end

function ToolbarBase:_resolveButtonRow(button, visibleIndex)
  if self.useButtonRows == false then
    local buttonsPerRow = tonumber(self.buttonsPerRow) or 0
    if buttonsPerRow > 0 then
      return math.floor((visibleIndex - 1) / buttonsPerRow) + 1
    end
    return 1
  end

  if button and tonumber(button.toolbarRow) then
    return math.max(1, math.floor(tonumber(button.toolbarRow)))
  end

  local buttonsPerRow = tonumber(self.buttonsPerRow) or 0
  if buttonsPerRow > 0 then
    return math.floor((visibleIndex - 1) / buttonsPerRow) + 1
  end

  return 1
end

function ToolbarBase:_getRowHeight(fallbackHeight)
  local rowHeight = tonumber(self.rowHeight) or 0
  if rowHeight <= 0 then
    rowHeight = tonumber(fallbackHeight) or 0
  end
  return rowHeight
end

function ToolbarBase:_getButtonRowCount()
  local visibleCount = 0
  local maxRow = 1
  for _, button in ipairs(self.buttons) do
    if isButtonVisible(button) then
      visibleCount = visibleCount + 1
      local row = self:_resolveButtonRow(button, visibleCount)
      if row > maxRow then
        maxRow = row
      end
    end
  end

  if visibleCount <= 0 then
    return 1
  end
  return maxRow
end

function ToolbarBase:_getToolbarHeight(fallbackHeight)
  local rowHeight = self:_getRowHeight(fallbackHeight)
  local rowCount = self:_getButtonRowCount()
  if rowHeight <= 0 then
    return tonumber(fallbackHeight) or 0
  end
  return rowHeight * rowCount
end

-- Update toolbar position based on window header
-- Specialized toolbars (left-aligned) are positioned above header
-- Header toolbars (right-aligned) override this method
function ToolbarBase:updatePosition()
  if not self.window then return end

  local dock = self._dockLayout
  if dock and type(dock.leftX) == "number" and type(dock.topY) == "number" then
    local rowH = self:_getRowHeight(dock.rowHeight or dock.topY)
    self.rowHeight = rowH
    self.h = self:_getToolbarHeight(rowH)
    self.y = dock.topY
    self:_layoutButtons()
    return
  end

  local hx, hy, hw, hh = self.window:getHeaderRect()

  -- Ensure toolbar height is set (should match header height)
  self.rowHeight = self:_getRowHeight(hh)
  self.h = self:_getToolbarHeight(hh)

  -- Position above the header bar (for specialized toolbars)
  self.y = hy - self.h - 1

  -- Re-layout buttons when position changes
  self:_layoutButtons()
end

-- Add a button to the toolbar
function ToolbarBase:addButton(icon, action, tooltip, opts)
  opts = opts or {}
  local buttonSize = self:_getRowHeight(self.h)
  local button = Button.new({
    icon = icon,  -- Image object
    action = action,  -- Function to call when clicked
    tooltip = tooltip or "",
    x = 0,  -- Will be set by layout
    y = 0,
    w = opts.w or buttonSize,
    h = opts.h or buttonSize,
    bgColor = opts.bgColor,
    bgAlpha = opts.bgAlpha,
    transparent = opts.transparent,
  })
  button.toolbarRow = tonumber(opts.row) or nil
  if opts.paletteLinkHandle then
    button.paletteLinkHandle = true
  end

  table.insert(self.buttons, button)
  self:_layoutButtons()
  
  return button
end

function ToolbarBase:addTextButton(text, action, tooltip, opts)
  opts = opts or {}
  local buttonSize = self:_getRowHeight(self.h)
  local button = Button.new({
    text = text or "",
    action = action,
    tooltip = tooltip or "",
    x = 0,
    y = 0,
    w = opts.w or buttonSize,
    h = opts.h or buttonSize,
    bgColor = opts.bgColor,
    bgAlpha = opts.bgAlpha,
    transparent = opts.transparent,
  })
  button.toolbarRow = tonumber(opts.row) or nil

  table.insert(self.buttons, button)
  self:_layoutButtons()
  return button
end

-- Add a label to the toolbar
function ToolbarBase:addLabel(text, width, updateFn)
  local rowHeight = self:_getRowHeight(self.h)
  local label = {
    text = text or "",
    width = width or rowHeight * 2,  -- Default width is 2x button size
    updateFn = updateFn,  -- Optional function to update text dynamically
    x = 0,  -- Will be set by layout
    y = 0,
    h = rowHeight,  -- Label height = toolbar row height
    renderInContent = false,  -- If true, label will be drawn in window content instead of toolbar
  }
  
  table.insert(self.labels, label)
  self:_layoutButtons()
  
  return label
end

-- Layout buttons and labels (labels on top row, buttons can wrap into multiple rows)
function ToolbarBase:_layoutButtons()
  if not self.window then return end

  local dock = self._dockLayout
  local hx, hy, hw, hh
  if dock and type(dock.leftX) == "number" and type(dock.topY) == "number" then
    hx = dock.leftX + 1
    hy = dock.topY
    hh = tonumber(dock.rowHeight) or 24
  else
    hx, hy, hw, hh = self.window:getHeaderRect()
  end
  local rowHeight = self:_getRowHeight(hh)

  local totalLabelWidth = 0
  for _, label in ipairs(self.labels) do
    if not label.renderInContent then
      totalLabelWidth = totalLabelWidth + label.width
      label.h = rowHeight
    end
  end

  local visibleIndex = 0
  local rowWidths = {}
  local rowCount = 1
  for _, button in ipairs(self.buttons) do
    if isButtonVisible(button) then
      visibleIndex = visibleIndex + 1
      local rowIndex = self:_resolveButtonRow(button, visibleIndex)
      rowWidths[rowIndex] = (rowWidths[rowIndex] or 0) + button.w
      if rowIndex > rowCount then
        rowCount = rowIndex
      end
    end
  end

  local totalWidth = totalLabelWidth + (rowWidths[1] or 0)
  for rowIndex = 2, rowCount do
    totalWidth = math.max(totalWidth, rowWidths[rowIndex] or 0)
  end
  self._layoutRowWidths = rowWidths

  local itemY = self.y or hy
  local topRowX = hx - 1
  local labelEndX = topRowX

  for _, label in ipairs(self.labels) do
    if not label.renderInContent then
      label.x = labelEndX
      label.y = itemY
      labelEndX = labelEndX + label.width
    end
  end

  visibleIndex = 0
  local currentRowIndex = 1
  local currentRowX = labelEndX
  for _, button in ipairs(self.buttons) do
    if isButtonVisible(button) then
      visibleIndex = visibleIndex + 1
      local rowIndex = self:_resolveButtonRow(button, visibleIndex)
      if rowIndex ~= currentRowIndex then
        currentRowIndex = rowIndex
        currentRowX = (rowIndex == 1) and labelEndX or topRowX
      end
      local rowY = itemY + ((rowIndex - 1) * rowHeight)
      button:setPosition(currentRowX, rowY)
      currentRowX = currentRowX + button.w
    end
  end

  self.x = hx
  self.w = totalWidth
end

-- Check if a point is inside the toolbar (check all buttons and labels)
function ToolbarBase:contains(px, py)
  if not self.visible then return false end
  
  -- For specialized toolbars, check if window is focused
  if not self.window or not self.windowController then return false end
  local isFocused = (self.window == self.windowController:getFocus())
  if not isFocused then return false end
  
  -- Check if point is within any button bounds
  for _, button in ipairs(self.buttons) do
    if isButtonVisible(button) and button:contains(px, py) then
      return true
    end
  end
  -- Check if point is within any label bounds (skip content-drawn labels; their x/y are not toolbar space)
  for _, label in ipairs(self.labels) do
    if not label.renderInContent then
      if px >= label.x and px <= label.x + label.width and
         py >= label.y and py <= label.y + label.h then
        return true
      end
    end
  end
  return false
end

-- Get button at a point
function ToolbarBase:getButtonAt(px, py)
  if not self:contains(px, py) then return nil end
  
  for _, button in ipairs(self.buttons) do
    if isButtonVisible(button) and button:contains(px, py) then
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
  local isFocused = (self.window == self.windowController:getFocus())
  if not isFocused then return false end
  
  -- Update position before checking (toolbar might have moved)
  self:updateIcons()
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
    if isButtonVisible(b) then
      DebugController.log("info", "UI", "  Button %d: (%.1f, %.1f, %.1f, %.1f)", i, b.x, b.y, b.w, b.h)
    end
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
  self:updateIcons()
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
  local isFocused = (self.window == self.windowController:getFocus())
  if not isFocused then 
    -- Clear hover states if not focused
    for _, b in ipairs(self.buttons) do
      b.hovered = false
    end
    return false
  end

  self:updateIcons()
  self:updatePosition()
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
  local isFocused = (self.window == self.windowController:getFocus())
  if not isFocused then return end
  
  -- Update position before drawing (this also re-layouts buttons)
  self:updateIcons()
  self:updatePosition()
  
  local drawX = self.x - 1 -- minus 1 because of the window border
  local drawY = self.y
  local drawW = math.max(0, tonumber(self.w) or 0)
  local drawH = math.max(0, tonumber(self.h) or 0)
  local usingStencil = drawRoundedToolbarStencil(drawX, drawY, drawW, drawH)

  local function drawToolbarContents()
    -- Draw background only behind occupied row spans.
    love.graphics.setColor(colors.blue)
    local rowHeight = self:_getRowHeight(self.h)
    local rowWidths = self._layoutRowWidths or {}
    local drewRow = false
    for rowIndex, rowWidth in pairs(rowWidths) do
      if rowWidth and rowWidth > 0 then
        local bgWidth = rowWidth
        if rowIndex == 1 then
          local labelWidth = 0
          for _, label in ipairs(self.labels) do
            if not label.renderInContent then
              labelWidth = labelWidth + label.width
            end
          end
          bgWidth = labelWidth + rowWidth
        end
        love.graphics.rectangle("fill",
          drawX,
          self.y + ((rowIndex - 1) * rowHeight),
          bgWidth,
          rowHeight
        )
        drewRow = true
      end
    end
    if not drewRow then
      love.graphics.rectangle("fill", drawX, self.y, self.w, self.h)
    end

    love.graphics.setColor(colors.white)

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
      if isButtonVisible(button) then
        if button.paletteLinkHandle then
          button.skipIconDraw = PaletteLinkController.shouldHidePaletteLinkHandleIconForWindow(self.window)
          button:draw()
          button.skipIconDraw = nil
        else
          button:draw()
        end
      end
    end
  end

  drawToolbarContents()
  if usingStencil then
    love.graphics.setStencilTest()
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
    Text.print(label.text, textX, textY, { color = colors.white })
  end
  
  love.graphics.setColor(colors.white)
end

-- Note: Button drawing is now handled by Button:draw() method in user_interface/button.lua

-- Draw layer label in window content area (called from Window:draw)
function ToolbarBase:drawLayerLabelInContent()
  -- Layer/item labels rendered over window content are intentionally disabled:
  -- these overlays obstruct editing and the same information is shown in status.
  return
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
