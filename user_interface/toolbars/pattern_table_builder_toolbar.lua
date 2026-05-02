-- pattern_table_builder_toolbar.lua
-- Toolbar for pattern table builder windows: layer navigation and pattern generation.

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")

local PatternTableBuilderToolbar = {}
PatternTableBuilderToolbar.__index = PatternTableBuilderToolbar
setmetatable(PatternTableBuilderToolbar, { __index = ToolbarBase })

function PatternTableBuilderToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), PatternTableBuilderToolbar)

  self.ctx = ctx
  self.windowController = windowController

  local _, _, _, hh = window:getHeaderRect()
  self.h = hh

  self.layerLabel = self:addLabel("", self.h * 3, function()
    if not self.window then return "0/0" end
    return string.format("%d/%d", self.window:getActiveLayerIndex() or 1, self.window:getLayerCount() or 0)
  end)
  self.layerLabel.renderInContent = true

  self:addButton(images.icons.icon_down, function()
    self:_onPrevLayer()
  end, "Previous layer")

  self:addButton(images.icons.icon_up, function()
    self:_onNextLayer()
  end, "Next layer")

  self.generateButton = self:addTextButton("G", function()
    self:_onGenerate()
  end, "Generate packed layer")

  self:updatePosition()
  return self
end

function PatternTableBuilderToolbar:_onPrevLayer()
  if not self.window then return end
  self.window:prevLayer()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
end

function PatternTableBuilderToolbar:_onNextLayer()
  if not self.window then return end
  self.window:nextLayer()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
end

function PatternTableBuilderToolbar:_onGenerate()
  if not (self.window and self.window.generatePackedPatternTable) then
    return
  end

  local ok, result = self.window:generatePackedPatternTable()
  if not ok then
    if self.ctx and self.ctx.app and self.ctx.app.setStatus then
      self.ctx.app:setStatus("Pattern generation failed")
    end
    if self.ctx and self.ctx.showToast then
      self.ctx.showToast("error", "Pattern generation failed")
    end
    return
  end

  local status = string.format(
    "Generated %d unique 8x8 tiles into packed layer (%d/%d)",
    result.placedTiles,
    result.placedTiles,
    result.capacity
  )
  if result.overflowTiles > 0 then
    status = string.format(
      "Generated %d/%d unique 8x8 tiles, %d overflow",
      result.placedTiles,
      result.uniqueTiles,
      result.overflowTiles
    )
  end

  if self.ctx and self.ctx.showToast then
    local kind = (result.overflowTiles > 0) and "warning" or "info"
    self.ctx.showToast(kind, status)
  end
end

function PatternTableBuilderToolbar:updateIcons()
  return
end

return PatternTableBuilderToolbar
