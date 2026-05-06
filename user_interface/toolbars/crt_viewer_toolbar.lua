-- Specialized toolbar for CRT layer visualizer: cycle referenced layers (refs), Shift+Up/Down matches other windows.

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")

local CrtViewerToolbar = {}
CrtViewerToolbar.__index = CrtViewerToolbar
setmetatable(CrtViewerToolbar, { __index = ToolbarBase })

function CrtViewerToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), CrtViewerToolbar)

  self.ctx = ctx
  self.windowController = windowController

  local _, _, _, hh = window:getHeaderRect()
  self.h = hh

  self.layerLabel = self:addLabel("", self.h * 3, function()
    if not self.window then
      return "Ref 0/0"
    end
    local total = self.window.getLayerCount and self.window:getLayerCount() or 0
    local current = self.window.getActiveLayerIndex and self.window:getActiveLayerIndex() or 1
    if total <= 0 then
      return "Ref 0/0"
    end
    current = math.max(1, math.min(current, total))
    return string.format("Ref %d/%d", current, total)
  end)
  self.layerLabel.renderInContent = true

  self:addButton(images.icons.icon_down, function()
    self.window:prevLayer()
  end, "Previous reference layer", {})

  self:addButton(images.icons.icon_up, function()
    self.window:nextLayer()
  end, "Next reference layer", {})

  self:updatePosition()

  return self
end

return CrtViewerToolbar
