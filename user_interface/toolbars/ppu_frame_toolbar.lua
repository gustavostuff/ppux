-- ppu_frame_toolbar.lua
-- Toolbar for PPU frame windows: layer navigation, add/remove, layer counter

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")

local PPUFrameToolbar = {}
PPUFrameToolbar.__index = PPUFrameToolbar
setmetatable(PPUFrameToolbar, { __index = ToolbarBase })

local function getNametableLayer(window)
  if not (window and window.layers) then return nil end
  for _, layer in ipairs(window.layers) do
    if layer and layer.kind ~= "sprite" then
      return layer
    end
  end
  return nil
end

local function getFirstSpriteLayer(window)
  if not (window and window.layers) then return nil, nil end
  for i, layer in ipairs(window.layers) do
    if layer and layer.kind == "sprite" then
      return layer, i
    end
  end
  return nil, nil
end

local function hasConfiguredRange(window)
  local layer = getNametableLayer(window)
  return layer
    and type(layer.nametableStartAddr) == "number"
    and type(layer.nametableEndAddr) == "number"
end

local function isShiftDown()
  if not (love and love.keyboard and love.keyboard.isDown) then
    return false
  end
  return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
end

local function clamp(value, minValue, maxValue)
  value = math.floor(tonumber(value) or 0)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

function PPUFrameToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), PPUFrameToolbar)
  
  self.ctx = ctx
  self.windowController = windowController
  
  -- Get header dimensions
  local hx, hy, hw, hh = window:getHeaderRect()
  self.h = hh  -- Toolbar height matches header height
  
  -- Layer counter label (N/M format) - rendered in window content area
  self.layerLabel = self:addLabel("", self.h * 3, function()
    if not self.window then return "0/0" end
    local current = self.window:getActiveLayerIndex() or 1
    local total = self.window:getLayerCount() or 0
    return string.format("%d/%d", current, total)
  end)
  self.layerLabel.renderInContent = true
  
  -- Previous layer button (down icon)
  self:addButton(images.icons.icon_down, function()
    self:_onPrevLayer()
  end, "Previous layer")
  
  -- Next layer button (up icon)
  self:addButton(images.icons.icon_up, function()
    self:_onNextLayer()
  end, "Next layer")

  self.rangeButton = self:addButton(images.icons.icon_nametable_range, function()
    self:_onConfigureRange()
  end, "Set stat and end addresses for nametable")

  self.addSpriteButton = self:addButton(images.icons.icon_add_sprite, function()
    self:_onAddSprite()
  end, "Add a sprite on sprite layer")

  self.originXMinusButton = self:addButton(images.icons.icon_minus, function()
    self:_onAdjustSpriteOrigin("x", -1)
  end, "Origin X -1")
  self.originXMinusButton.bgColor = colors.red

  self.originXPlusButton = self:addButton(images.icons.icon_plus, function()
    self:_onAdjustSpriteOrigin("x", 1)
  end, "Origin X +1")
  self.originXPlusButton.bgColor = colors.red

  self.originYMinusButton = self:addButton(images.icons.icon_minus, function()
    self:_onAdjustSpriteOrigin("y", -1)
  end, "Origin Y -1")
  self.originYMinusButton.bgColor = colors.green

  self.originYPlusButton = self:addButton(images.icons.icon_plus, function()
    self:_onAdjustSpriteOrigin("y", 1)
  end, "Origin Y +1")
  self.originYPlusButton.bgColor = colors.green

  self.toggleOriginGuidesButton = self:addButton(images.icons.icon_dotted_lines, function()
    self:_onToggleOriginGuides()
  end, "Toggle origin guides")

  self:updateRangeButton()
  self:updateSpriteButton()
  self:updateOriginButtons()
  
  -- Update position
  self:updatePosition()
  
  return self
end

-- Handle previous layer
function PPUFrameToolbar:_onPrevLayer()
  if not self.window then return end
  
  self.window:prevLayer()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
  
  if self.ctx and self.ctx.setStatus then
    local current = self.window:getActiveLayerIndex()
    local total = self.window:getLayerCount()
    self.ctx.setStatus(string.format("Layer %d/%d", current, total))
  end
end

-- Handle next layer
function PPUFrameToolbar:_onNextLayer()
  if not self.window then return end
  
  self.window:nextLayer()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
  
  if self.ctx and self.ctx.setStatus then
    local current = self.window:getActiveLayerIndex()
    local total = self.window:getLayerCount()
    self.ctx.setStatus(string.format("Layer %d/%d", current, total))
  end
end

function PPUFrameToolbar:_onConfigureRange()
  local app = self.ctx and self.ctx.app or nil
  if app and app.showPpuFrameRangeModal then
    app:showPpuFrameRangeModal(self.window)
  end
end

local function normalizeSpriteMode(mode)
  return (mode == "8x16") and "8x16" or "8x8"
end

function PPUFrameToolbar:_getActiveSpriteLayer()
  if not self.window then return nil, nil end
  local activeIndex = self.window:getActiveLayerIndex() or self.window.activeLayer or 1
  local activeLayer = self.window.layers and self.window.layers[activeIndex] or nil
  if activeLayer and activeLayer.kind == "sprite" then
    activeLayer.items = activeLayer.items or {}
    activeLayer.originX = clamp(activeLayer.originX or 0, 0, 255)
    activeLayer.originY = clamp(activeLayer.originY or 0, 0, 239)
    return activeLayer, activeIndex
  end
  return nil, nil
end

function PPUFrameToolbar:_ensureSpriteLayer(mode, createIfMissing, targetWindow)
  local window = targetWindow or self.window
  if not window then return nil, nil, false end

  local activeIndex = window:getActiveLayerIndex()
  local activeLayer = window.layers and window.layers[activeIndex] or nil
  if activeLayer and activeLayer.kind == "sprite" then
    activeLayer.items = activeLayer.items or {}
    return activeLayer, activeIndex, false
  end

  local existingLayer, existingIndex = getFirstSpriteLayer(window)
  if existingLayer then
    existingLayer.items = existingLayer.items or {}
    if window.setActiveLayerIndex then
      window:setActiveLayerIndex(existingIndex)
    else
      window.activeLayer = existingIndex
    end
    return existingLayer, existingIndex, false
  end

  if createIfMissing == false then
    return nil, nil, false
  end

  local spriteMode = normalizeSpriteMode(mode)
  local newIndex = window:addLayer({
    name = "Sprites",
    kind = "sprite",
    mode = spriteMode,
    originX = 0,
    originY = 0,
  })
  local newLayer = window.layers and window.layers[newIndex] or nil
  if newLayer then
    newLayer.items = newLayer.items or {}
  end
  if window.setActiveLayerIndex then
    window:setActiveLayerIndex(newIndex)
  else
    window.activeLayer = newIndex
  end
  self:updateSpriteButton()
  return newLayer, newIndex, true
end

function PPUFrameToolbar:_onAddSprite()
  if not self.window then return end

  local spriteLayer = self:_ensureSpriteLayer(nil, false)
  local app = self.ctx and self.ctx.app or nil
  if not spriteLayer then
    if app and app.showPpuFrameSpriteLayerModeModal then
      local opened = app:showPpuFrameSpriteLayerModeModal(self.window, {
        onConfirm = function(spriteMode, targetWindow)
          local layer = self:_ensureSpriteLayer(spriteMode, true, targetWindow)
          if not layer then
            if self.ctx and self.ctx.setStatus then
              self.ctx.setStatus("Could not create sprite layer")
            end
            return false
          end
          if self.ctx and self.ctx.setStatus then
            self.ctx.setStatus("Created sprite layer (" .. normalizeSpriteMode(spriteMode) .. ")")
          end
          return true
        end,
      })
      if opened ~= false then
        return
      end
    end

    local fallbackLayer = self:_ensureSpriteLayer("8x8", true)
    if fallbackLayer and app and app.showPpuFrameAddSpriteModal then
      app:showPpuFrameAddSpriteModal(self.window)
      if self.ctx and self.ctx.setStatus then
        self.ctx.setStatus("Created sprite layer and opened add sprite dialog")
      end
      return
    end
  end

  spriteLayer = self:_ensureSpriteLayer(nil, false)
  if not spriteLayer then
    if self.ctx and self.ctx.setStatus then
      self.ctx.setStatus("Could not resolve a sprite layer")
    end
    return
  end

  if app and app.showPpuFrameAddSpriteModal then
    app:showPpuFrameAddSpriteModal(self.window)
  end
end

function PPUFrameToolbar:_onAdjustSpriteOrigin(axis, direction)
  local layer = self:_getActiveSpriteLayer()
  if not layer then
    return
  end

  local step = isShiftDown() and 8 or 1
  local delta = (direction < 0) and -step or step

  if axis == "x" then
    layer.originX = clamp((layer.originX or 0) + delta, 0, 255)
  else
    layer.originY = clamp((layer.originY or 0) + delta, 0, 239)
  end
end

function PPUFrameToolbar:_onToggleOriginGuides()
  local layer = self:_getActiveSpriteLayer()
  if not layer or not self.window then
    return
  end
  self.window.showSpriteOriginGuides = not (self.window.showSpriteOriginGuides == true)
  self:updateOriginButtons()
end

-- Handle add layer
function PPUFrameToolbar:_onAddLayer()
  if not self.window then return end
  
  local newLayerIdx = self.window:addLayer({
    name = "Layer " .. (#self.window.layers + 1),
  })
  
  if self.ctx and self.ctx.setStatus then
    self.ctx.setStatus(string.format("Added layer %d", newLayerIdx))
  end
end

-- Handle remove layer
function PPUFrameToolbar:_onRemoveLayer()
  if not self.window then return end
  
  local numLayers = self.window:getLayerCount()
  if numLayers <= 1 then
    if self.ctx and self.ctx.setStatus then
      self.ctx.setStatus("Cannot remove the last layer")
    end
    return
  end
  
  local activeIdx = self.window:getActiveLayerIndex()
  table.remove(self.window.layers, activeIdx)
  
  -- Adjust active layer index
  if activeIdx > numLayers then
    self.window.activeLayer = numLayers - 1
  elseif activeIdx > 1 then
    self.window.activeLayer = activeIdx - 1
  else
    self.window.activeLayer = 1
  end
  
  if self.ctx and self.ctx.setStatus then
    local current = self.window:getActiveLayerIndex()
    self.ctx.setStatus(string.format("Removed layer, now on layer %d", current))
  end
  if self.ctx and self.ctx.showToast then
    local title = tostring((self.window and self.window.title) or "Untitled")
    self.ctx.showToast("warning", string.format("Removed layer from %s", title))
  end
end

-- Empty updateIcons method
function PPUFrameToolbar:updateIcons()
  self:updateRangeButton()
  self:updateSpriteButton()
  self:updateOriginButtons()
end

function PPUFrameToolbar:updateRangeButton()
  if not self.rangeButton then return end
  self.rangeButton.icon = images.icons.icon_nametable_range or self.rangeButton.icon
  if hasConfiguredRange(self.window) then
    self.rangeButton.bgColor = nil
    self.rangeButton.contentColor = colors.white
    self.rangeButton.tooltip = "Set stat and end addresses for nametable"
  else
    self.rangeButton.bgColor = colors.yellow
    self.rangeButton.contentColor = colors.black
    self.rangeButton.tooltip = "Set stat and end addresses for nametable"
  end
end

function PPUFrameToolbar:updateSpriteButton()
  if not self.addSpriteButton then return end
  self.addSpriteButton.icon = images.icons.icon_add_sprite or self.addSpriteButton.icon
  local _, spriteLayerIndex = getFirstSpriteLayer(self.window)
  if spriteLayerIndex then
    self.addSpriteButton.tooltip = "Add a sprite on sprite layer"
  else
    self.addSpriteButton.tooltip = "Create sprite layer"
  end
end

function PPUFrameToolbar:updateOriginButtons()
  local layer = self:_getActiveSpriteLayer()
  local isActiveSpriteLayer = layer ~= nil
  local hideOriginButtons = not isActiveSpriteLayer
  local originX = layer and clamp(layer.originX or 0, 0, 255) or 0
  local originY = layer and clamp(layer.originY or 0, 0, 239) or 0
  local stepHint = " (Shift: 8)"

  if self.originXMinusButton then
    self.originXMinusButton.icon = images.icons.icon_minus or self.originXMinusButton.icon
    self.originXMinusButton.bgColor = colors.red
    self.originXMinusButton.enabled = isActiveSpriteLayer
    self.originXMinusButton.hidden = hideOriginButtons
    self.originXMinusButton.tooltip = string.format("Origin X: %d -1%s", originX, stepHint)
  end
  if self.originXPlusButton then
    self.originXPlusButton.icon = images.icons.icon_plus or self.originXPlusButton.icon
    self.originXPlusButton.bgColor = colors.red
    self.originXPlusButton.enabled = isActiveSpriteLayer
    self.originXPlusButton.hidden = hideOriginButtons
    self.originXPlusButton.tooltip = string.format("Origin X: %d +1%s", originX, stepHint)
  end
  if self.originYMinusButton then
    self.originYMinusButton.icon = images.icons.icon_minus or self.originYMinusButton.icon
    self.originYMinusButton.bgColor = colors.green
    self.originYMinusButton.enabled = isActiveSpriteLayer
    self.originYMinusButton.hidden = hideOriginButtons
    self.originYMinusButton.tooltip = string.format("Origin Y: %d -1%s", originY, stepHint)
  end
  if self.originYPlusButton then
    self.originYPlusButton.icon = images.icons.icon_plus or self.originYPlusButton.icon
    self.originYPlusButton.bgColor = colors.green
    self.originYPlusButton.enabled = isActiveSpriteLayer
    self.originYPlusButton.hidden = hideOriginButtons
    self.originYPlusButton.tooltip = string.format("Origin Y: %d +1%s", originY, stepHint)
  end

  if self.toggleOriginGuidesButton then
    local enabledGuides = isActiveSpriteLayer and (self.window and self.window.showSpriteOriginGuides == true)
    self.toggleOriginGuidesButton.icon = images.icons.icon_dotted_lines or self.toggleOriginGuidesButton.icon
    self.toggleOriginGuidesButton.enabled = isActiveSpriteLayer
    self.toggleOriginGuidesButton.hidden = hideOriginButtons
    if enabledGuides then
      self.toggleOriginGuidesButton.bgColor = nil
    else
      self.toggleOriginGuidesButton.bgColor = colors.gray20
    end
    self.toggleOriginGuidesButton.tooltip = enabledGuides
      and "Hide sprite origin guides"
      or "Show sprite origin guides"
  end
end

return PPUFrameToolbar
