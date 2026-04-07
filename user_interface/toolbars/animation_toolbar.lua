-- animation_toolbar.lua
-- Toolbar for animation windows: layer navigation, add/remove, layer counter

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")
local DebugController = require("controllers.dev.debug_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local AnimationToolbar = {}
AnimationToolbar.__index = AnimationToolbar
setmetatable(AnimationToolbar, { __index = ToolbarBase })

local function isAnimationKind(window)
  return WindowCaps.isAnimationLike(window)
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

function AnimationToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), AnimationToolbar)
  
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
    return string.format("Layer %d/%d", current, total)
  end)
  self.layerLabel.renderInContent = true

  self.linkButton = self:addButton(images.icons.icon_connect, nil, "Palette link handle")
  
  -- Previous layer button (down icon)
  self:addButton(images.icons.icon_down, function()
    self:_onPrevLayer()
  end, "Previous layer")
  
  -- Next layer button (up icon)
  self:addButton(images.icons.icon_up, function()
    self:_onNextLayer()
  end, "Next layer")

  -- Remove layer button (minus icon)
  self:addButton(images.icons.icon_minus, function()
    self:_onRemoveLayer()
  end, "Remove layer")
  
  -- Add layer button (plus icon)
  self:addButton(images.icons.icon_plus, function()
    self:_onAddLayer()
  end, "Add layer")

  if WindowCaps.isOamAnimation(window) then
    self.addSpriteButton = self:addButton(images.icons.icon_add_sprite, function()
      self:_onAddSprite()
    end, "Add a sprite on active layer")

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
  end

  -- Copy from previous layer button
  self:addButton(images.icons.icon_copy_layer, function()
    self:_onCopyFromPrevious()
  end, "Copy previous layer")
  
  -- Play/Pause button (toggle between play and pause icons)
  -- Start with play icon if not playing, pause icon if playing
  local initialIcon = (window.isPlaying and images.icons.icon_pause) or images.icons.icon_play
  local initialTooltip = (window.isPlaying and "Pause") or "Play"
  self.playButton = self:addButton(initialIcon, function()
    self:_onTogglePlay()
  end, initialTooltip)
  
  -- Update position
  self:updatePosition()
  self:updateOriginButtons()
  
  return self
end

function AnimationToolbar:getLinkHandleRect()
  if not self.linkButton or self.linkButton.hidden == true then
    return nil
  end
  self:updatePosition()
  return self.linkButton.x, self.linkButton.y, self.linkButton.w, self.linkButton.h
end

-- Handle previous layer
function AnimationToolbar:_onPrevLayer()
  if not self.window then return end
  
  -- Check if animation is playing
  if self.window.isPlaying then
    if self.ctx and self.ctx.setStatus then
      self.ctx.setStatus("Cannot change layers while animation is playing")
    end
    return
  end
  
  local oldLayer = self.window:getActiveLayerIndex()
  self.window:prevLayer()
  
  -- Only show status if layer actually changed
  local newLayer = self.window:getActiveLayerIndex()
  if oldLayer ~= newLayer and self.ctx and self.ctx.setStatus then
    local current = self.window:getActiveLayerIndex()
    local total = self.window:getLayerCount()
    self.ctx.setStatus(string.format("Layer %d/%d", current, total))
  end
  self:updateOriginButtons()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
end

-- Handle next layer
function AnimationToolbar:_onNextLayer()
  if not self.window then return end
  
  -- Check if animation is playing
  if self.window.isPlaying then
    if self.ctx and self.ctx.setStatus then
      self.ctx.setStatus("Cannot change layers while animation is playing")
    end
    return
  end
  
  local oldLayer = self.window:getActiveLayerIndex()
  self.window:nextLayer()
  
  -- Only show status if layer actually changed
  local newLayer = self.window:getActiveLayerIndex()
  if oldLayer ~= newLayer and self.ctx and self.ctx.setStatus then
    local current = self.window:getActiveLayerIndex()
    local total = self.window:getLayerCount()
    self.ctx.setStatus(string.format("Layer %d/%d", current, total))
  end
  self:updateOriginButtons()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
end

-- Handle add layer
function AnimationToolbar:_onAddLayer()
  if not isAnimationKind(self.window) then return end
  
  local newLayerIdx = self.window:addLayerAfterActive({
    name = "Frame " .. (#self.window.layers + 1),
  })
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
  
  if self.ctx and self.ctx.setStatus then
    self.ctx.setStatus(string.format("Added layer %d", newLayerIdx))
  end
  self:updateOriginButtons()
end

function AnimationToolbar:_onAddSprite()
  if not WindowCaps.isOamAnimation(self.window) then return end

  local app = self.ctx and self.ctx.app or nil
  if app and app.showPpuFrameAddSpriteModal then
    app:showPpuFrameAddSpriteModal(self.window)
    return
  end

  if self.ctx and self.ctx.setStatus then
    self.ctx.setStatus("Add sprite dialog is unavailable")
  end
end

function AnimationToolbar:_getActiveSpriteLayer()
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

function AnimationToolbar:_onAdjustSpriteOrigin(axis, direction)
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

  self:updateOriginButtons()
end

function AnimationToolbar:_onToggleOriginGuides()
  local layer = self:_getActiveSpriteLayer()
  if not layer or not self.window then
    return
  end
  self.window.showSpriteOriginGuides = not (self.window.showSpriteOriginGuides == true)
  self:updateOriginButtons()
end

-- Handle remove layer
function AnimationToolbar:_onRemoveLayer()
  if not isAnimationKind(self.window) then return end
  
  local success = self.window:removeActiveLayer()
  if success then
    if self.ctx and self.ctx.setStatus then
      local current = self.window:getActiveLayerIndex()
      self.ctx.setStatus(string.format("Removed layer, now on layer %d", current))
    end
  else
    if self.ctx and self.ctx.setStatus then
      self.ctx.setStatus("Cannot remove the last layer")
    end
  end
  self:updateOriginButtons()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
end

-- Handle play/pause toggle
function AnimationToolbar:_onTogglePlay()
  if not isAnimationKind(self.window) then return end
  
  local wasPlaying = self.window.isPlaying
  self.window:togglePlay()
  if self.window.isPlaying and self.triggerLayerLabelFlash then
    self:triggerLayerLabelFlash()
  end
  
  -- Update button icon based on new play state
  if self.playButton then
    if self.window.isPlaying then
      self.playButton.icon = images.icons.icon_pause
      self.playButton.tooltip = "Pause"
    else
      self.playButton.icon = images.icons.icon_play
      self.playButton.tooltip = "Play"
    end
  end
  
  if self.ctx and self.ctx.setStatus then
    self.ctx.setStatus(self.window.isPlaying and "Animation playing" or "Animation paused")
  end
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
end

-- Copy tiles from previous layer into the active layer
function AnimationToolbar:_onCopyFromPrevious()
  if not isAnimationKind(self.window) then return end
  if not self.window.copyTilesFromPreviousLayer then return end
  
  local ok = self.window:copyTilesFromPreviousLayer()
  if self.ctx and self.ctx.setStatus then
    if ok then
      self.ctx.setStatus("Copied previous layer")
    else
      self.ctx.setStatus("Nothing to copy from previous layer")
    end
  end
end

-- Update button icons
function AnimationToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
  if self.linkButton then
    self.linkButton.icon = images.icons.icon_connect or self.linkButton.icon
  end
  if self.addSpriteButton then
    self.addSpriteButton.icon = images.icons.icon_add_sprite or self.addSpriteButton.icon
  end
  self:updateOriginButtons()

  -- Update play button icon based on current play state
  if self.playButton and self.window then
    if self.window.isPlaying then
      self.playButton.icon = images.icons.icon_pause
      self.playButton.tooltip = "Pause"
    else
      self.playButton.icon = images.icons.icon_play
      self.playButton.tooltip = "Play"
    end
  end
end

function AnimationToolbar:updateOriginButtons()
  if not WindowCaps.isOamAnimation(self.window) then
    return
  end

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

return AnimationToolbar
