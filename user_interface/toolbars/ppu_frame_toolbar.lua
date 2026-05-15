-- ppu_frame_toolbar.lua
-- Toolbar for PPU frame windows: layer navigation, add/remove, layer counter

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")
local AnimationWindowUndo = require("controllers.input_support.animation_window_undo")

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

local function findPpuNametableTileLayerIndexForToolbar(window)
  if not (window and window.layers) then
    return nil
  end
  for i, layer in ipairs(window.layers) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      if type(layer.nametableStartAddr) == "number" and type(layer.nametableEndAddr) == "number" then
        return i
      end
    end
  end
  for i, layer in ipairs(window.layers) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      return i
    end
  end
  return nil
end

local function findPpuFirstSpriteLayerIndexForToolbar(window)
  if not (window and window.layers) then
    return nil
  end
  for i, layer in ipairs(window.layers) do
    if layer and layer.kind == "sprite" then
      return i
    end
  end
  return nil
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
  self:addButton(images.icons.chrome.icon_down, function()
    self:_onPrevLayer()
  end, "Previous layer")
  
  -- Next layer button (up icon)
  self:addButton(images.icons.chrome.icon_up, function()
    self:_onNextLayer()
  end, "Next layer")

  self.rangeButton = self:addButton(images.icons.actions.icon_nametable_range, function()
    self:_onConfigureRange()
  end, "Set start and end addresses for nametable")

  self.addSpriteButton = self:addButton(images.icons.actions.icon_add_sprite, function()
    self:_onAddSprite()
  end, "Add a sprite on sprite layer")

  self.patternTableLinkButton = self:addButton(images.icons.actions.icon_pattern_table or images.icons.actions.icon_nametable_range, function()
    self:_onPatternTableLinkMenu()
  end, "Background and sprite pattern table links")

  self.toggleOriginGuidesButton = self:addButton(images.icons.actions.icon_dotted_lines, function()
    self:_onToggleOriginGuides()
  end, "Toggle origin guides")

  self:updatePatternTableLinkButton()
  self:updateRangeButton()
  self:updateSpriteButton()
  self:updateOriginButtons()
  
  -- Update position
  self:updatePosition()
  
  return self
end

function PPUFrameToolbar:_onPatternTableLinkMenu()
  if not self.window then
    return
  end
  local app = self.ctx and self.ctx.app
  if not app or not app.showPatternTableLinkDestinationContextMenu then
    setStatus(self.ctx, "Pattern table link is not available")
    return
  end
  local btn = self.patternTableLinkButton
  if not btn then
    return
  end
  self:updatePosition()
  local x = btn.x + btn.w * 0.5
  local y = btn.y + btn.h * 0.5
  app:showPatternTableLinkDestinationContextMenu(self.window, x, y)
end

-- Handle previous layer
function PPUFrameToolbar:_onPrevLayer()
  if not self.window then return end
  
  self.window:prevLayer()
  self:updatePatternTableLinkButton()
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
  self:updatePatternTableLinkButton()
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
  if not self.window then return end
  local _, spriteIdx = getFirstSpriteLayer(self.window)
  if not spriteIdx then
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

  local app = self.ctx and self.ctx.app
  local undoRedo = app and app.undoRedo
  local snapBefore = AnimationWindowUndo.snapshot(self.window)

  local activeIdx = self.window:getActiveLayerIndex()
  table.remove(self.window.layers, activeIdx)
  if self.window.selectedByLayer then
    self.window.selectedByLayer[activeIdx] = nil
    for li = activeIdx, #self.window.layers do
      self.window.selectedByLayer[li] = self.window.selectedByLayer[li + 1]
    end
    self.window.selectedByLayer[#self.window.layers + 1] = nil
  end

  -- Adjust active layer index (mirror AnimationWindow:removeActiveLayer)
  if activeIdx > numLayers then
    self.window.activeLayer = numLayers - 1
  elseif activeIdx > 1 then
    self.window.activeLayer = activeIdx - 1
  else
    self.window.activeLayer = 1
  end
  if self.window.activeLayer > #self.window.layers then
    self.window.activeLayer = #self.window.layers
  end
  if self.window.activeLayer < 1 then
    self.window.activeLayer = 1
  end
  self.window.selected = self.window.selectedByLayer and self.window.selectedByLayer[self.window.activeLayer] or nil
  if self.window.updateLayerOpacities then
    self.window:updateLayerOpacities()
  end

  local snapAfter = AnimationWindowUndo.snapshot(self.window)
  if undoRedo and undoRedo.addAnimationWindowStateEvent and not AnimationWindowUndo.snapshotsEqual(snapBefore, snapAfter) then
    undoRedo:addAnimationWindowStateEvent({
      type = "animation_window_state",
      win = self.window,
      beforeState = snapBefore,
      afterState = snapAfter,
    })
  end

  if self.ctx and self.ctx.showToast then
    local title = tostring((self.window and self.window.title) or "Untitled")
    self.ctx.showToast("warning", string.format("Removed layer from %s", title))
  end
end

-- Empty updateIcons method
function PPUFrameToolbar:updateIcons()
  self:updatePatternTableLinkButton()
  self:updateRangeButton()
  self:updateSpriteButton()
  self:updateOriginButtons()
end

function PPUFrameToolbar:updatePatternTableLinkButton()
  local button = self.patternTableLinkButton
  if not button then
    return
  end
  button.icon = images.icons.actions.icon_pattern_table or images.icons.actions.icon_nametable_range or button.icon
  button.enabled = true
  local bgIdx = self.window and findPpuNametableTileLayerIndexForToolbar(self.window)
  local sprIdx = self.window and findPpuFirstSpriteLayerIndexForToolbar(self.window)
  local bgLayer = bgIdx and self.window.layers and self.window.layers[bgIdx]
  local sprLayer = sprIdx and self.window.layers and self.window.layers[sprIdx]
  local bgLinked = bgLayer and type(bgLayer.linkedPatternTableWindowId) == "string" and bgLayer.linkedPatternTableWindowId ~= ""
  local sprLinked = sprLayer and type(sprLayer.linkedPatternTableWindowId) == "string" and sprLayer.linkedPatternTableWindowId ~= ""
  local linked = bgLinked or sprLinked
  if linked then
    button.bgColor = colors.green
    button.contentColor = colors.white
    button.tooltip = "Background and/or sprite pattern table linked (menu)"
  else
    button.bgColor = nil
    button.contentColor = colors.white
    button.tooltip = "Link background and sprite pattern tables (menu)"
  end
end

function PPUFrameToolbar:updateRangeButton()
  if not self.rangeButton then return end
  self.rangeButton.icon = images.icons.actions.icon_nametable_range or self.rangeButton.icon
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
  self.addSpriteButton.icon = images.icons.actions.icon_add_sprite or self.addSpriteButton.icon
  local _, spriteLayerIndex = getFirstSpriteLayer(self.window)
  if spriteLayerIndex then
    self.addSpriteButton.tooltip = "Add a sprite on sprite layer"
  else
    self.addSpriteButton.tooltip = "Create sprite layer"
  end
end

function PPUFrameToolbar:updateOriginButtons()
  local _, spriteLayerIndex = getFirstSpriteLayer(self.window)
  local hasSpriteLayer = spriteLayerIndex ~= nil

  if self.toggleOriginGuidesButton then
    local guidesOn = self.window and self.window.showSpriteOriginGuides == true
    local enabledGuides = hasSpriteLayer and guidesOn
    self.toggleOriginGuidesButton.icon = images.icons.actions.icon_dotted_lines or self.toggleOriginGuidesButton.icon
    self.toggleOriginGuidesButton.enabled = hasSpriteLayer
    self.toggleOriginGuidesButton.hidden = not hasSpriteLayer
    if enabledGuides then
      self.toggleOriginGuidesButton.bgColor = nil
    else
      self.toggleOriginGuidesButton.bgColor = colors.gray20
    end
    self.toggleOriginGuidesButton.tooltip = guidesOn
      and "Hide sprite origin guides"
      or "Show sprite origin guides"
  end

end

return PPUFrameToolbar
