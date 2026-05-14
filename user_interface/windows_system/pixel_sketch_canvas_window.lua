-- pixel_sketch_canvas_window.lua
-- Free-form pixel canvas (NES-style indexed pixels) for authoring artwork later used to
-- build non-ROM pattern tables. Painting only; packing / pattern_table kind is separate.

local Window = require("user_interface.windows_system.window")
local PixelCanvas = require("user_interface.windows_system.pixel_canvas")

local PixelSketchCanvasWindow = setmetatable({}, { __index = Window })
PixelSketchCanvasWindow.__index = PixelSketchCanvasWindow

local CANVAS_W = 256
local CANVAS_H = 240
local CELL = 8

local function addCanvasLayer(self, name, width, height, fillValue)
  local idx = self:addLayer({
    name = name,
    kind = "canvas",
  })
  local layer = self.layers[idx]
  layer.canvas = PixelCanvas.new(width, height, fillValue or 0)
  layer.canvasWidth = width
  layer.canvasHeight = height
  return idx
end

function PixelSketchCanvasWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  data = data or {}
  cols = cols or math.floor(CANVAS_W / CELL)
  rows = rows or math.floor(CANVAS_H / CELL)
  cellW = cellW or CELL
  cellH = cellH or CELL

  local self = Window.new(x, y, cellW, cellH, cols, rows, zoom, {
    flags = {
      allowInternalDrag = false,
      allowExternalDrag = true,
      allowExternalDrop = false,
    },
    title = data.title or "Pixel sketch",
    visibleRows = data.visibleRows or rows,
    visibleCols = data.visibleCols or cols,
    resizable = false,
  })
  setmetatable(self, PixelSketchCanvasWindow)

  self.kind = "pattern_sketch_canvas"
  self.layers = {}

  addCanvasLayer(self, "Sketch", CANVAS_W, CANVAS_H, 0)
  self.activeLayer = 1

  return self
end

function PixelSketchCanvasWindow:getActiveCanvasLayer()
  local li = self:getActiveLayerIndex() or 1
  local layer = self.layers and self.layers[li] or nil
  if layer and layer.kind == "canvas" and layer.canvas then
    return layer, li
  end
  return nil, li
end

function PixelSketchCanvasWindow:getActiveCanvas()
  local layer = self:getActiveCanvasLayer()
  return layer and layer.canvas or nil
end

function PixelSketchCanvasWindow:getVisibleSize()
  local canvas = self:getActiveCanvas()
  if canvas then
    return canvas.width, canvas.height
  end
  return Window.getVisibleSize(self)
end

function PixelSketchCanvasWindow:getRealContentSize()
  local canvas = self:getActiveCanvas()
  if canvas then
    return canvas.width, canvas.height
  end
  return Window.getRealContentSize(self)
end

function PixelSketchCanvasWindow:getContentSize()
  local canvas = self:getActiveCanvas()
  if canvas then
    return canvas.width, canvas.height
  end
  return Window.getContentSize(self)
end

function PixelSketchCanvasWindow:toGridCoords(px, py)
  local ok, cx, cy = self:toContentCoords(px, py)
  if not ok then return false end

  local canvas = self:getActiveCanvas()
  if not canvas then
    return Window.toGridCoords(self, px, py)
  end

  if cx < 0 or cy < 0 or cx >= canvas.width or cy >= canvas.height then
    return false
  end

  local col = math.floor(cx / self.cellW)
  local row = math.floor(cy / self.cellH)
  local lx = cx - (col * self.cellW)
  local ly = cy - (row * self.cellH)
  return true, col, row, lx, ly
end

return PixelSketchCanvasWindow
