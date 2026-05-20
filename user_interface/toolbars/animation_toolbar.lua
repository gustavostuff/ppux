-- animation_toolbar.lua
-- Toolbar for animation windows: layer navigation, add/remove, layer counter

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")
local DebugController = require("controllers.dev.debug_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local AnimationWindowUndo = require("controllers.input_support.animation_window_undo")

local AnimationToolbar = {}
AnimationToolbar.__index = AnimationToolbar
setmetatable(AnimationToolbar, { __index = ToolbarBase })

local function setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

local function isAnimationKind(window)
  return WindowCaps.isAnimationLike(window)
end

local function clamp(value, minValue, maxValue)
  value = math.floor(tonumber(value) or 0)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function oamBulkPatternTableFullyLinked(window)
  if not (window and window.layers) then
    return false
  end
  local firstId = nil
  local sawSprite = false
  for _, layer in ipairs(window.layers) do
    if layer and layer.kind == "sprite" then
      sawSprite = true
      local id = layer.linkedPatternTableWindowId
      if type(id) ~= "string" or id == "" then
        return false
      end
      if firstId == nil then
        firstId = id
      elseif firstId ~= id then
        return false
      end
    end
  end
  return sawSprite == true and firstId ~= nil
end

local function isOamMultiRowEnabled(window)
  if not WindowCaps.isOamAnimation(window) then
    return false
  end
  return window.multiRowToolbar == true
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

  local primaryRow = WindowCaps.isOamAnimation(window) and 1 or nil
  local secondaryRow = WindowCaps.isOamAnimation(window) and 2 or nil
  if WindowCaps.isOamAnimation(window) then
    self.useButtonRows = isOamMultiRowEnabled(window)
  end

  -- Previous layer button (down icon)
  self:addButton(images.icons.chrome.icon_down, function()
    self:_onPrevLayer()
  end, "Previous layer", {
    row = primaryRow,
  })
  
  -- Next layer button (up icon)
  self:addButton(images.icons.chrome.icon_up, function()
    self:_onNextLayer()
  end, "Next layer", {
    row = primaryRow,
  })

  -- Remove layer button (minus icon)
  self:addButton(images.icons.chrome.icon_minus, function()
    self:_onRemoveLayer()
  end, "Remove layer", {
    row = primaryRow,
  })
  
  -- Add layer button (plus icon)
  self:addButton(images.icons.chrome.icon_plus, function()
    self:_onAddLayer()
  end, "Add layer", {
    row = primaryRow,
  })

  if WindowCaps.isOamAnimation(window) then
    self.addSpriteButton = self:addButton(images.icons.actions.icon_add_sprite, function()
      self:_onAddSprite()
    end, "Add a sprite on active layer", {
      row = secondaryRow,
    })

    self.toggleOriginGuidesButton = self:addButton(images.icons.actions.icon_dotted_lines, function()
      self:_onToggleOriginGuides()
    end, "Toggle origin guides", {
      row = secondaryRow,
    })
  end

  -- Copy from previous layer button
  self:addButton(images.icons.actions.icon_copy_layer, function()
    self:_onCopyFromPrevious()
  end, "Copy previous layer", {
    row = secondaryRow,
  })
  
  -- Play/Pause button (toggle between play and pause icons)
  -- Start with play icon if not playing, pause icon if playing
  local initialIcon = (window.isPlaying and images.icons.actions.icon_pause) or images.icons.actions.icon_play
  local initialTooltip = (window.isPlaying and "Pause") or "Play"
  self.playButton = self:addButton(initialIcon, function()
    self:_onTogglePlay()
  end, initialTooltip, {
    row = secondaryRow,
  })

  if WindowCaps.isOamAnimation(window) then
    self.patternTableLinkButton = self:addButton(images.icons.actions.icon_pattern_table or images.icons.chrome.icon_connect, function()
      self:_onPatternTableLinkMenu()
    end, "Link pattern table for all frames (menu)", {
      row = secondaryRow or primaryRow,
    })
  end

  -- Link handle last (palette connections); kept in screen order as the rightmost toolbar control.
  self.linkButton = self:addButton(images.icons.actions.icon_connect, nil, "Palette link handle; right-drag to a ROM palette to link; left-click for menu", {
    row = secondaryRow or primaryRow,
    paletteLinkHandle = true,
  })
  
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
    setStatus(self.ctx, "Cannot change layers while animation is playing")
    return
  end
  
  self.window:prevLayer()
  
  self:updateOriginButtons()
  self:updateIcons()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
end

-- Handle next layer
function AnimationToolbar:_onNextLayer()
  if not self.window then return end
  
  -- Check if animation is playing
  if self.window.isPlaying then
    setStatus(self.ctx, "Cannot change layers while animation is playing")
    return
  end
  
  self.window:nextLayer()
  
  self:updateOriginButtons()
  self:updateIcons()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
end

-- Handle add layer
function AnimationToolbar:_onAddLayer()
  if not isAnimationKind(self.window) then return end
  
  local newLayerIdx = self.window:addLayerAfterActive({
    name = "Frame " .. (#self.window.layers + 1),
  })
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
  
  self:updateOriginButtons()
end

function AnimationToolbar:_onAddSprite()
  if not WindowCaps.isOamAnimation(self.window) then return end

  local app = self.ctx and self.ctx.app or nil
  if app and app.showPpuFrameAddSpriteModal then
    app:showPpuFrameAddSpriteModal(self.window)
    return
  end

  setStatus(self.ctx, "Add sprite dialog is unavailable")
end

function AnimationToolbar:_onPatternTableLinkMenu()
  if not WindowCaps.isOamAnimation(self.window) then
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
  app:showPatternTableLinkDestinationContextMenu(self.window, btn.x + btn.w * 0.5, btn.y + btn.h * 0.5)
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

  local app = self.ctx and self.ctx.app
  local undoRedo = app and app.undoRedo
  local snapBefore = AnimationWindowUndo.snapshot(self.window)
  local success = self.window:removeActiveLayer()
  if success then
    local snapAfter = AnimationWindowUndo.snapshot(self.window)
    if undoRedo and undoRedo.addAnimationWindowStateEvent and not AnimationWindowUndo.snapshotsEqual(snapBefore, snapAfter) then
      undoRedo:addAnimationWindowStateEvent({
        type = "animation_window_state",
        win = self.window,
        beforeState = snapBefore,
        afterState = snapAfter,
      })
    end
  else
    setStatus(self.ctx, "Cannot remove the last layer")
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
      self.playButton.icon = images.icons.actions.icon_pause
      self.playButton.tooltip = "Pause"
    else
      self.playButton.icon = images.icons.actions.icon_play
      self.playButton.tooltip = "Play"
    end
  end
  
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
end

-- Copy tiles from previous layer into the active layer
function AnimationToolbar:_onCopyFromPrevious()
  if not isAnimationKind(self.window) then return end
  if not self.window.copyTilesFromPreviousLayer then return end
  
  local ok = self.window:copyTilesFromPreviousLayer()
  if not ok then
    setStatus(self.ctx, "Nothing to copy from previous layer")
  end
end

-- Update button icons
function AnimationToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
  if WindowCaps.isOamAnimation(self.window) then
    self.useButtonRows = isOamMultiRowEnabled(self.window)
  end
  if self.linkButton then
    self.linkButton.icon = images.icons.actions.icon_connect or self.linkButton.icon
    local linkedPalette = PaletteLinkController.getActiveLayerLinkedPaletteWindow(self.window, self.windowController)
    self.linkButton.bgColor = linkedPalette and colors.green or colors.gray20
    self.linkButton.contentColor = colors.white
    if linkedPalette then
      self.linkButton.tooltip = string.format(
        "Linked to %s; right-drag to a ROM palette to change link; left-click for menu",
        tostring(linkedPalette.title or "palette")
      )
    else
      self.linkButton.tooltip = "No palette linked; right-drag to a ROM palette to link; left-click for menu"
    end
  end
  if self.addSpriteButton then
    self.addSpriteButton.icon = images.icons.actions.icon_add_sprite or self.addSpriteButton.icon
  end
  self:updateOriginButtons()

  if self.patternTableLinkButton and WindowCaps.isOamAnimation(self.window) then
    local linked = oamBulkPatternTableFullyLinked(self.window)
    self.patternTableLinkButton.icon = images.icons.actions.icon_pattern_table or self.patternTableLinkButton.icon
    self.patternTableLinkButton.contentColor = colors.white
    if linked then
      self.patternTableLinkButton.bgColor = colors.green
      self.patternTableLinkButton.tooltip = "Pattern table linked for all frames (menu)"
    else
      self.patternTableLinkButton.bgColor = colors.gray20
      self.patternTableLinkButton.tooltip = "Link pattern table for all animation frames (menu)"
    end
  end

  -- Update play button icon based on current play state
  if self.playButton and self.window then
    if self.window.isPlaying then
      self.playButton.icon = images.icons.actions.icon_pause
      self.playButton.tooltip = "Pause"
    else
      self.playButton.icon = images.icons.actions.icon_play
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

  if self.toggleOriginGuidesButton then
    local enabledGuides = isActiveSpriteLayer and (self.window and self.window.showSpriteOriginGuides == true)
    self.toggleOriginGuidesButton.icon = images.icons.actions.icon_dotted_lines or self.toggleOriginGuidesButton.icon
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
