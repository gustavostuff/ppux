-- ppu_frame_toolbar.lua
-- Toolbar for PPU frame windows: layer navigation, add/remove, layer counter

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")

local PPUFrameToolbar = {}
PPUFrameToolbar.__index = PPUFrameToolbar
setmetatable(PPUFrameToolbar, { __index = ToolbarBase })

local function setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

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
  end, "Set start and end addresses for nametable")

  self.addSpriteButton = self:addButton(images.icons.icon_add_sprite, function()
    self:_onAddSprite()
  end, "Add a sprite on sprite layer")

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
  self:updateOriginButtons()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
  
  local current = self.window:getActiveLayerIndex()
  local total = self.window:getLayerCount()
  setStatus(self.ctx, string.format("Layer %d/%d", current, total))
end

-- Handle next layer
function PPUFrameToolbar:_onNextLayer()
  if not self.window then return end
  
  self.window:nextLayer()
  self:updateOriginButtons()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
  
  local current = self.window:getActiveLayerIndex()
  local total = self.window:getLayerCount()
  setStatus(self.ctx, string.format("Layer %d/%d", current, total))
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

function PPUFrameToolbar:_getActiveTileLayer()
  if not self.window then return nil, nil end
  local activeIndex = self.window:getActiveLayerIndex() or self.window.activeLayer or 1
  local activeLayer = self.window.layers and self.window.layers[activeIndex] or nil
  if activeLayer and activeLayer.kind ~= "sprite" then
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
            setStatus(self.ctx, "Could not create sprite layer")
            return false
          end
          setStatus(self.ctx, "Created sprite layer (" .. normalizeSpriteMode(spriteMode) .. ")")
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
      setStatus(self.ctx, "Created sprite layer and opened add sprite dialog")
      return
    end
  end

  spriteLayer = self:_ensureSpriteLayer(nil, false)
  if not spriteLayer then
    setStatus(self.ctx, "Could not resolve a sprite layer")
    return
  end

  if app and app.showPpuFrameAddSpriteModal then
    app:showPpuFrameAddSpriteModal(self.window)
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
  
  setStatus(self.ctx, string.format("Added layer %d", newLayerIdx))
end

-- Handle remove layer
function PPUFrameToolbar:_onRemoveLayer()
  if not self.window then return end
  
  local numLayers = self.window:getLayerCount()
  if numLayers <= 1 then
    setStatus(self.ctx, "Cannot remove the last layer")
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
  
  local current = self.window:getActiveLayerIndex()
  setStatus(self.ctx, string.format("Removed layer, now on layer %d", current))
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
    self.rangeButton.tooltip = "Set start and end addresses for nametable"
  else
    self.rangeButton.bgColor = colors.yellow
    self.rangeButton.contentColor = colors.black
    self.rangeButton.tooltip = "Set start and end addresses for nametable"
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
  local tileLayer = self:_getActiveTileLayer()
  local isActiveSpriteLayer = layer ~= nil
  local isActiveTileLayer = tileLayer ~= nil
  local hideOriginButtons = not isActiveSpriteLayer

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
