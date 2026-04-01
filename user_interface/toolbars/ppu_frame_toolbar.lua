-- ppu_frame_toolbar.lua
-- Toolbar for PPU frame windows: layer navigation, add/remove, layer counter

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")
local DebugController = require("controllers.dev.debug_controller")

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

local function hasConfiguredRange(window)
  local layer = getNametableLayer(window)
  return layer
    and type(layer.nametableStartAddr) == "number"
    and type(layer.nametableEndAddr) == "number"
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

  self.rangeButton = self:addButton(images.icons.icon_not_selected, function()
    self:_onConfigureRange()
  end, "Set tile range")
  self:updateRangeButton()
  
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
end

function PPUFrameToolbar:updateRangeButton()
  if not self.rangeButton then return end
  if hasConfiguredRange(self.window) then
    self.rangeButton.icon = images.icons.icon_selected or self.rangeButton.icon
    self.rangeButton.bgColor = nil
    self.rangeButton.contentColor = colors.white
    self.rangeButton.tooltip = "Edit tile range"
  else
    self.rangeButton.icon = images.icons.icon_not_selected or self.rangeButton.icon
    self.rangeButton.bgColor = colors.yellow
    self.rangeButton.contentColor = colors.black
    self.rangeButton.tooltip = "Set tile range"
  end
end

return PPUFrameToolbar
