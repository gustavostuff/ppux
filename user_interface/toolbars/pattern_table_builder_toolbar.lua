-- pattern_table_builder_toolbar.lua
-- Toolbar for pattern table builder windows: layer navigation, tools, generate placeholder.

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

  self.pencilButton = self:addTextButton("P", function()
    self:_onSelectTool("pencil")
  end, "Pencil tool")

  self.eraserButton = self:addTextButton("E", function()
    self:_onSelectTool("eraser")
  end, "Eraser tool")

  self.lineButton = self:addTextButton("L", function()
    self:_onSelectTool("line")
  end, "Line tool")

  self.rectButton = self:addTextButton("R", function()
    self:_onSelectTool("rect")
  end, "Filled rectangle tool")

  self:addButton(images.icons.icon_plus, function()
    self:_onGenerate()
  end, "Generate packed layer")

  self:updatePosition()
  return self
end

function PatternTableBuilderToolbar:_setLayerStatus()
  if self.ctx and self.ctx.setStatus and self.window then
    self.ctx.setStatus(string.format("Layer %d/%d", self.window:getActiveLayerIndex() or 1, self.window:getLayerCount() or 0))
  end
end

function PatternTableBuilderToolbar:_onPrevLayer()
  if not self.window then return end
  self.window:prevLayer()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
  self:_setLayerStatus()
end

function PatternTableBuilderToolbar:_onNextLayer()
  if not self.window then return end
  self.window:nextLayer()
  if self.triggerLayerLabelFlash then self:triggerLayerLabelFlash() end
  self:_setLayerStatus()
end

function PatternTableBuilderToolbar:_onGenerate()
  if self.ctx and self.ctx.setStatus then
    self.ctx.setStatus("Pattern packing is not implemented yet")
  end
  if self.ctx and self.ctx.showToast then
    self.ctx.showToast("info", "Pattern packing is not implemented yet")
  end
end

function PatternTableBuilderToolbar:_onSelectTool(tool)
  if not (self.window and self.window.setBuilderTool) then return end
  if not self.window:setBuilderTool(tool) then return end
  if self.ctx and self.ctx.setStatus then
    self.ctx.setStatus("Pattern tool: " .. tostring(tool))
  end
end

function PatternTableBuilderToolbar:updateIcons()
  if not self.window then return end
  local tool = self.window.getBuilderTool and self.window:getBuilderTool() or "pencil"
  local activeColor = { 0.15, 0.15, 0.15 }
  local inactiveColor = nil
  if self.pencilButton then self.pencilButton.bgColor = (tool == "pencil") and activeColor or inactiveColor end
  if self.eraserButton then self.eraserButton.bgColor = (tool == "eraser") and activeColor or inactiveColor end
  if self.lineButton then self.lineButton.bgColor = (tool == "line") and activeColor or inactiveColor end
  if self.rectButton then self.rectButton.bgColor = (tool == "rect") and activeColor or inactiveColor end
end

return PatternTableBuilderToolbar
