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
  local fallback = nil
  for _, layer in ipairs(window.layers) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      fallback = fallback or layer
      if type(layer.nametableStartAddr) == "number" and type(layer.nametableEndAddr) == "number" then
        return layer
      end
    end
  end
  return fallback
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

local function patternRangeCount(window)
  local layer = getNametableLayer(window)
  if not layer or type(layer.patternTable) ~= "table" or type(layer.patternTable.ranges) ~= "table" then
    return 0
  end
  return #layer.patternTable.ranges
end

local function clamp(value, minValue, maxValue)
  value = math.floor(tonumber(value) or 0)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function getLayerDisplayProgress(window)
  if not window then return 0, 0 end
  if window.getAllowedLayerIndicesForNavigation then
    local allowed = window:getAllowedLayerIndicesForNavigation() or {}
    local total = #allowed
    if total <= 0 then
      return 0, 0
    end
    local active = window:getActiveLayerIndex() or 1
    local pos = 1
    for i, idx in ipairs(allowed) do
      if idx == active then
        pos = i
        break
      end
    end
    return pos, total
  end
  local current = window:getActiveLayerIndex() or 1
  local total = window:getLayerCount() or 0
  return current, total
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
    local current, total = getLayerDisplayProgress(self.window)
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

  self.addTileRangeButton = self:addButton(images.icons.icon_plus, function()
    self:_onAddTileRange()
  end, "Add tile range")

  self.rangeButton = self:addButton(images.icons.icon_nametable_range, function()
    self:_onConfigureRange()
  end, "Set start and end addresses for nametable")

  self.addSpriteButton = self:addButton(images.icons.icon_add_sprite, function()
    self:_onAddSprite()
  end, "Add a sprite on sprite layer")

  self.patternLayerToggleButton = self:addButton(images.icons.icon_pattern_table or images.icons.icon_nametable_range, function()
    self:_onTogglePatternLayerSolo()
  end, "Show pattern table layer only")

  self.toggleOriginGuidesButton = self:addButton(images.icons.icon_dotted_lines, function()
    self:_onToggleOriginGuides()
  end, "Toggle origin guides")

  self:updatePatternRangeButton()
  self:updatePatternLayerToggleButton()
  self:updateRangeButton()
  self:updateSpriteButton()
  self:updateOriginButtons()
  
  -- Update position
  self:updatePosition()
  
  return self
end

function PPUFrameToolbar:_onTogglePatternLayerSolo()
  if not self.window then return end
  local currentlyOn = (self.window.patternLayerSoloMode == true)
  local ok, reason = true, nil
  if self.window.setPatternLayerSoloMode then
    ok, reason = self.window:setPatternLayerSoloMode(not currentlyOn)
  end
  if not ok then
    setStatus(self.ctx, tostring(reason or "Pattern table layer is not available"))
    if self.ctx and self.ctx.showToast then
      self.ctx.showToast("warning", tostring(reason or "Pattern table layer is not available"))
    end
    self:updatePatternLayerToggleButton()
    return
  end
  self:updatePatternLayerToggleButton()
  self:updateOriginButtons()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
end

-- Handle previous layer
function PPUFrameToolbar:_onPrevLayer()
  if not self.window then return end
  
  self.window:prevLayer()
  self:updatePatternRangeButton()
  self:updateOriginButtons()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
  
  if self.window.isPatternTableInteractionLocked then
    local layerIdx = self.window:getActiveLayerIndex() or self.window.activeLayer or 1
    local locked, reason = self.window:isPatternTableInteractionLocked(layerIdx)
    if locked and reason then
      setStatus(self.ctx, reason)
    end
  end
end

-- Handle next layer
function PPUFrameToolbar:_onNextLayer()
  if not self.window then return end
  
  self.window:nextLayer()
  self:updatePatternRangeButton()
  self:updateOriginButtons()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
  
  if self.window.isPatternTableInteractionLocked then
    local layerIdx = self.window:getActiveLayerIndex() or self.window.activeLayer or 1
    local locked, reason = self.window:isPatternTableInteractionLocked(layerIdx)
    if locked and reason then
      setStatus(self.ctx, reason)
    end
  end
end

function PPUFrameToolbar:_onConfigureRange()
  local app = self.ctx and self.ctx.app or nil
  if app and app.showPpuFrameRangeModal then
    app:showPpuFrameRangeModal(self.window)
  end
end

function PPUFrameToolbar:_onAddTileRange()
  local app = self.ctx and self.ctx.app or nil
  if app and app.showPpuFramePatternRangeModal then
    app:showPpuFramePatternRangeModal(self.window)
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
  
  self.window:addLayer({
    name = "Layer " .. (#self.window.layers + 1),
  })
  
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
  
  if self.ctx and self.ctx.showToast then
    local title = tostring((self.window and self.window.title) or "Untitled")
    self.ctx.showToast("warning", string.format("Removed layer from %s", title))
  end
end

-- Empty updateIcons method
function PPUFrameToolbar:updateIcons()
  self:updatePatternRangeButton()
  self:updatePatternLayerToggleButton()
  self:updateRangeButton()
  self:updateSpriteButton()
  self:updateOriginButtons()
end

function PPUFrameToolbar:updatePatternLayerToggleButton()
  local button = self.patternLayerToggleButton
  if not button then return end
  button.icon = images.icons.icon_pattern_table or images.icons.icon_nametable_range or button.icon
  local enabled = (self.window and self.window.findPatternReferenceLayerIndex and self.window:findPatternReferenceLayerIndex() ~= nil)
  button.enabled = true
  local active = self.window and self.window.patternLayerSoloMode == true
  if active then
    button.bgColor = colors.green
    button.contentColor = colors.white
    button.tooltip = "Return to tile/sprite layers"
  else
    if enabled then
      button.bgColor = nil
      button.contentColor = colors.white
      button.tooltip = "Show pattern table layer only"
    else
      button.bgColor = colors.gray20
      button.contentColor = colors.white
      button.tooltip = "Pattern table layer is not available"
    end
  end
end

function PPUFrameToolbar:updatePatternRangeButton()
  if not self.addTileRangeButton then return end
  self.addTileRangeButton.icon = images.icons.icon_plus or self.addTileRangeButton.icon
  local rangeCount = patternRangeCount(self.window)
  if rangeCount > 0 then
    self.addTileRangeButton.bgColor = nil
    self.addTileRangeButton.contentColor = colors.white
  else
    self.addTileRangeButton.bgColor = colors.yellow
    self.addTileRangeButton.contentColor = colors.black
  end
  self.addTileRangeButton.tooltip = "Add tile range"
end

function PPUFrameToolbar:updateRangeButton()
  if not self.rangeButton then return end
  self.rangeButton.icon = images.icons.icon_nametable_range or self.rangeButton.icon
  self.rangeButton.enabled = true
  if hasConfiguredRange(self.window) then
    self.rangeButton.bgColor = nil
    self.rangeButton.contentColor = colors.white
  else
    self.rangeButton.bgColor = colors.yellow
    self.rangeButton.contentColor = colors.black
  end
  self.rangeButton.tooltip = "Set start and end addresses for nametable"
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
