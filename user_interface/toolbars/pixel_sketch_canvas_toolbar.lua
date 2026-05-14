-- pixel_sketch_canvas_toolbar.lua
-- Minimal chrome for sketch canvas windows (painting uses global toolbar / shortcuts).

local ToolbarBase = require("user_interface.toolbars.toolbar_base")

local PixelSketchCanvasToolbar = {}
PixelSketchCanvasToolbar.__index = PixelSketchCanvasToolbar
setmetatable(PixelSketchCanvasToolbar, { __index = ToolbarBase })

function PixelSketchCanvasToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), PixelSketchCanvasToolbar)
  self.ctx = ctx
  self.windowController = windowController
  local _, _, _, hh = window:getHeaderRect()
  self.h = hh or 22
  self:updatePosition()
  return self
end

function PixelSketchCanvasToolbar:updateIcons()
end

return PixelSketchCanvasToolbar
