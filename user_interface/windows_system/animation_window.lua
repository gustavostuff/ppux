-- animation_window.lua
-- A layered window intended for simple animation mockups.
-- Inherits from Window and starts with exactly 3 layers.

local Window = require("user_interface.windows_system.window")
local Timer = require("utils.timer_utils")
local DebugController = require("controllers.dev.debug_controller")

local AnimationWindow = setmetatable({}, { __index = Window })
AnimationWindow.__index = AnimationWindow

-- Default delay per frame (in seconds) - can be configured later
local DEFAULT_FRAME_DELAY = 0.2
local MIN_FRAME_DELAY = 0.1
local MAX_FRAME_DELAY = 1.0
local FRAME_DELAY_STEP = 0.05

function AnimationWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  data = data or {}
  data.resizable = true
  if data.nonActiveLayerOpacity == nil then
    data.nonActiveLayerOpacity = 0.0
  end
  local self = Window.new(x, y, cellW, cellH, cols, rows, zoom, data)
  setmetatable(self, AnimationWindow)

  self.kind = "animation"
  self.layers = {}
  self.activeLayer = 1
  
  -- Animation state
  self.isPlaying = false
  self.frameTimerId = nil  -- Timer ID for current frame (can be cancelled)
  self.frameDelays = {}  -- Delays for each frame (indexed by layer index)
  
  -- Layer opacity mode: when true, only active layer is visible
  -- This is the default behavior (configurable later)
  self.singleLayerMode = true
  
  -- Ensure opacities are updated after layers are added
  -- This will be called again after layers are populated, but good to initialize
  -- The actual initialization happens in createAnimationWindow after layers are created

  return self
end

-- Advance to the next frame (called by Timer callback)
function AnimationWindow:advanceToNextFrame()
  if not self.isPlaying or not self.singleLayerMode then
    return
  end
  
  local numLayers = #self.layers
  if numLayers == 0 then
    return
  end
  
  local oldLayer = self.activeLayer
  -- Move to next layer (wrap around)
  self.activeLayer = (self.activeLayer % numLayers) + 1
  
  DebugController.log("info", "ANIM", "Window '%s' frame advanced: layer %d -> %d", self.title or "untitled", oldLayer, self.activeLayer)
  
  -- Update layer opacities: only active layer is visible
  self:updateLayerOpacities()
  if self.specializedToolbar and self.specializedToolbar.triggerLayerLabelFlash then
    self.specializedToolbar:triggerLayerLabelFlash()
  end
  
  -- Schedule next frame advance
  self:scheduleNextFrame()
end

-- Schedule the timer for the current frame
function AnimationWindow:scheduleNextFrame()
  if not self.isPlaying or not self.singleLayerMode then
    return
  end
  
  local numLayers = #self.layers
  if numLayers == 0 then
    return
  end
  
  -- Cancel any existing timer
  if self.frameTimerId then
    Timer.cancel(self.frameTimerId)
    self.frameTimerId = nil
  end
  
  -- Get delay for current layer (default if not specified)
  local delay = self.frameDelays[self.activeLayer] or DEFAULT_FRAME_DELAY
  
  -- Schedule next frame advance
  self.frameTimerId = Timer.after(delay, function()
    self:advanceToNextFrame()
  end)
end

-- Adjust delay for all frames at once.
-- direction: 1 to increase, -1 to decrease.
-- Delay is clamped between MIN_FRAME_DELAY and MAX_FRAME_DELAY.
function AnimationWindow:adjustAllFrameDelays(direction)
  if direction ~= 1 and direction ~= -1 then
    return nil
  end

  local numLayers = #self.layers
  if numLayers == 0 then
    return nil
  end

  local currentDelay = self.frameDelays[self.activeLayer] or DEFAULT_FRAME_DELAY
  currentDelay = math.floor(currentDelay * 100 + 0.5) / 100
  local nextDelay = math.max(
    MIN_FRAME_DELAY,
    math.min(MAX_FRAME_DELAY, currentDelay + (direction * FRAME_DELAY_STEP))
  )

  -- Keep two decimals to avoid float drift over repeated key presses.
  nextDelay = math.floor(nextDelay * 100 + 0.5) / 100

  for i = 1, numLayers do
    self.frameDelays[i] = nextDelay
  end

  -- Apply new timing immediately while playing, but only if current
  -- active frame delay actually changed. This avoids "slowing down"
  -- from repeatedly resetting the timer at clamp boundaries.
  if self.isPlaying and math.abs(nextDelay - currentDelay) > 0.0001 then
    self:scheduleNextFrame()
  end

  return nextDelay
end

-- Override update to call parent (Timer.update is handled globally)
function AnimationWindow:update(dt)
  -- Call parent update first
  Window.update(self, dt)
  -- Timer callbacks are handled by Timer.update() in AppCoreController
end

-- Update layer opacities based on play state and singleLayerMode
function AnimationWindow:updateLayerOpacities()
  if not self.singleLayerMode then
    -- All layers visible (opacity comes from layer.opacity settings)
    return
  end
  
  local numLayers = #self.layers
  if numLayers == 0 then return end
  
  -- Clamp active layer to valid range
  local visibleIndex = math.max(1, math.min(self.activeLayer, numLayers))
  
  -- Update all layer opacities: only active layer is visible
  for i, layer in ipairs(self.layers) do
    if i == visibleIndex then
      layer.opacity = 1.0
    else
      layer.opacity = self.nonActiveLayerOpacity or 0.0
    end
  end
end

-- Add a new layer after the active layer
function AnimationWindow:addLayerAfterActive(opts)
  opts = opts or {}
  local activeIdx = self.activeLayer or 1
  local insertIdx = activeIdx + 1
  
  -- Determine layer kind based on existing layers (prefer not mixing)
  local layerKind = opts.kind or "tile"
  local layerMode = opts.mode
  local layerOriginX = opts.originX
  local layerOriginY = opts.originY
  if #self.layers > 0 then
    -- Use the kind of the first layer if not specified
    local firstLayer = self.layers[1]
    if firstLayer and firstLayer.kind then
      layerKind = firstLayer.kind
      if layerKind == "sprite" and layerMode == nil then
        layerMode = firstLayer.mode or "8x8"
      end
      if layerKind == "sprite" then
        if layerOriginX == nil then layerOriginX = firstLayer.originX or 0 end
        if layerOriginY == nil then layerOriginY = firstLayer.originY or 0 end
      end
    end
  end
  
  -- Create new layer
  local newLayer = {
    items = {},
    opacity = opts.opacity or self.nonActiveLayerOpacity or 0.0,  -- Start with non-active opacity
    name = opts.name or ("Frame " .. (#self.layers + 1)),
    kind = layerKind,
    mode = layerMode,
    originX = layerOriginX,
    originY = layerOriginY,
  }
  
  -- Insert at position after active layer
  table.insert(self.layers, insertIdx, newLayer)
  if self.selectedByLayer then
    for li = #self.layers, insertIdx + 1, -1 do
      self.selectedByLayer[li] = self.selectedByLayer[li - 1]
    end
    self.selectedByLayer[insertIdx] = nil
    self.selected = self.selectedByLayer[self.activeLayer or 1]
  end
  
  DebugController.log("info", "ANIM", "Window '%s' added layer at index %d: '%s' (kind: %s, total: %d)", self.title or "untitled", insertIdx, newLayer.name, layerKind, #self.layers)
  
  -- Update active layer index if needed
  if insertIdx <= self.activeLayer then
    self.activeLayer = self.activeLayer + 1
  end
  
  -- Update opacities
  self:updateLayerOpacities()
  if self.specializedToolbar and self.specializedToolbar.triggerLayerLabelFlash then
    self.specializedToolbar:triggerLayerLabelFlash()
  end
  
  return insertIdx
end

-- Remove the active layer
function AnimationWindow:removeActiveLayer()
  local numLayers = #self.layers
  if numLayers <= 1 then
    DebugController.log("info", "ANIM", "Window '%s' cannot remove layer: only %d layer(s) remaining", self.title or "untitled", numLayers)
    return false  -- Can't remove the last layer
  end
  
  local activeIdx = self.activeLayer
  local removedLayer = self.layers[activeIdx]
  local layerName = removedLayer and removedLayer.name or "unknown"
  table.remove(self.layers, activeIdx)
  if self.selectedByLayer then
    self.selectedByLayer[activeIdx] = nil
    for li = activeIdx, #self.layers do
      self.selectedByLayer[li] = self.selectedByLayer[li + 1]
    end
    self.selectedByLayer[#self.layers + 1] = nil
  end
  
  DebugController.log("info", "ANIM", "Window '%s' removed layer at index %d: '%s' (remaining: %d)", self.title or "untitled", activeIdx, layerName, #self.layers)
  
  -- Adjust active layer index
  if activeIdx > numLayers then
    self.activeLayer = numLayers - 1
  elseif activeIdx > 1 then
    self.activeLayer = activeIdx - 1
  else
    self.activeLayer = 1
  end
  
  -- Ensure active layer is within valid range
  if self.activeLayer > #self.layers then
    self.activeLayer = #self.layers
  end
  if self.activeLayer < 1 then
    self.activeLayer = 1
  end
  self.selected = self.selectedByLayer and self.selectedByLayer[self.activeLayer] or nil
  if self.specializedToolbar and self.specializedToolbar.triggerLayerLabelFlash then
    self.specializedToolbar:triggerLayerLabelFlash()
  end
  
  -- Reschedule timer if playing
  if self.isPlaying then
    -- Cancel existing timer before rescheduling
    if self.frameTimerId then
      Timer.cancel(self.frameTimerId)
      self.frameTimerId = nil
    end
    
    -- Reschedule timer for current frame
    self:scheduleNextFrame()
  end
  
  -- Update opacities
  self:updateLayerOpacities()

  local ctx = _G.ctx
  if ctx and ctx.showToast then
    local title = tostring(self.title or "Untitled")
    ctx.showToast("warning", string.format("Removed layer from %s", title))
  end
  
  return true
end

-- Toggle play/pause
function AnimationWindow:togglePlay()
  self.isPlaying = not self.isPlaying
  
  DebugController.log("info", "ANIM", "Window '%s' playback %s", self.title or "untitled", self.isPlaying and "STARTED" or "PAUSED")
  
  -- Cancel any existing timer
  if self.frameTimerId then
    Timer.cancel(self.frameTimerId)
    self.frameTimerId = nil
  end
  
  if self.isPlaying then
    -- Update opacities immediately
    self:updateLayerOpacities()
    -- Schedule first frame advance
    self:scheduleNextFrame()
  else
    -- Paused: update opacities to show active layer
    self:updateLayerOpacities()
  end
  
  return self.isPlaying
end

-- Override setActiveLayerIndex to prevent changes when playing
local parentSetActiveLayerIndex = Window.setActiveLayerIndex
function AnimationWindow:setActiveLayerIndex(i)
  -- Prevent manual layer changes when animation is playing
  if self.isPlaying then
    return
  end
  
  parentSetActiveLayerIndex(self, i)
  -- Update opacities (when not playing, manual changes are allowed)
  self:updateLayerOpacities()
end

-- Copy all placements from the previous layer into the active one (tiles or sprites).
-- Returns true if copy succeeded (requires an existing previous layer of the same kind).
function AnimationWindow:copyTilesFromPreviousLayer()
  local idx = self.activeLayer or 1
  if idx <= 1 then
    return false
  end

  local prev = self.layers and self.layers[idx - 1]
  local curr = self.layers and self.layers[idx]
  if not prev or not curr then
    return false
  end
  if prev.kind ~= curr.kind then
    return false
  end

  local function cloneMap(src)
    if not src then return nil end
    local dst = {}
    for k, v in pairs(src) do
      dst[k] = v
    end
    return dst
  end

  local function copyTileLayer()
    -- Copy items by reference (tiles are shared objects) into a fresh items table.
    curr.items = {}
    if prev.items then
      for k, v in pairs(prev.items) do
        curr.items[k] = v
      end
    end

    -- Copy per-cell metadata tables (paletteNumbers, removedCells) by value.
    curr.paletteNumbers = cloneMap(prev.paletteNumbers)
    curr.removedCells   = cloneMap(prev.removedCells)
  end

  local function copySpriteLayer()
    curr.items = {}
    for i, sprite in ipairs(prev.items or {}) do
      local clone = {}
      for k, v in pairs(sprite) do
        clone[k] = v
      end
      curr.items[i] = clone
    end

    -- Reset selection/hover state on the destination layer.
    curr.hoverSpriteIndex   = nil
    curr.selectedSpriteIndex = nil
    curr.multiSpriteSelection = nil
    curr.multiSpriteSelectionOrder = nil
  end

  if prev.kind == "tile" then
    copyTileLayer()
    return true
  end

  if prev.kind == "sprite" then
    copySpriteLayer()
    return true
  end

  return false
end

-- Override nextLayer and prevLayer to prevent changes when playing
function AnimationWindow:nextLayer()
  -- Prevent manual layer changes when animation is playing
  if self.isPlaying then
    return
  end
  
  Window.nextLayer(self)
  self:updateLayerOpacities()
end

function AnimationWindow:prevLayer()
  -- Prevent manual layer changes when animation is playing
  if self.isPlaying then
    return
  end
  
  Window.prevLayer(self)
  self:updateLayerOpacities()
end

return AnimationWindow
