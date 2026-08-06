-- sketch_canvas_window.lua
-- Free-form pixel canvas (NES-style indexed pixels) for authoring background /
-- nametable artwork. Painting only for now; pack / pattern-table link comes later.

local Window = require("ui.windows_system.window")
local PixelCanvas = require("ui.windows_system.pixel_canvas")

local SketchCanvasWindow = setmetatable({}, { __index = Window })
SketchCanvasWindow.__index = SketchCanvasWindow

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

function SketchCanvasWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
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
    title = data.title or "Sketch canvas",
    visibleRows = data.visibleRows or rows,
    visibleCols = data.visibleCols or cols,
    resizable = false,
  })
  setmetatable(self, SketchCanvasWindow)

  self.kind = "sketch_canvas"
  self.layers = {}

  -- Pack / link state (Phase 2+). Pixels stay on the canvas layer snapshot only.
  -- tilesPool may be a pipe-separated project string or a legacy entry table.
  do
    local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
    self.tilesPool = SketchCanvasPackController.decodeTilesPool(data.tilesPool)
  end

  self.nametableBytes = nil
  if type(data.nametableBytes) == "table" then
    local LayoutIO = require("controllers.game_art.layout_io_controller")
    -- Prefer full NES nametable size when present; allow shorter legacy test arrays.
    local expected = nil
    if data.nametableBytes.kind == "byte_blob" then
      expected = math.floor(tonumber(data.nametableBytes.count) or 960)
    elseif #data.nametableBytes == 960 then
      expected = 960
    end
    local nt = LayoutIO.normalizeByteList(data.nametableBytes, expected)
    if nt and #nt > 0 then
      self.nametableBytes = nt
    end
  end

  self.nametableAttrBytes = nil
  if type(data.nametableAttrBytes) == "table" then
    local LayoutIO = require("controllers.game_art.layout_io_controller")
    local attrs = LayoutIO.normalizeByteList(data.nametableAttrBytes, 64)
    if attrs and #attrs > 0 then
      while #attrs < 64 do
        attrs[#attrs + 1] = 0
      end
      self.nametableAttrBytes = attrs
    end
  end

  self.tolerance = math.floor(tonumber(data.tolerance) or 0)
  if self.tolerance < 0 then
    self.tolerance = 0
  end
  self.reflectPatternTable = data.reflectPatternTable == true
  if type(data.linkedPatternTableWindowId) == "string" and data.linkedPatternTableWindowId ~= "" then
    self.linkedPatternTableWindowId = data.linkedPatternTableWindowId
  else
    self.linkedPatternTableWindowId = nil
  end
  self.paddingTileIndex = math.floor(tonumber(data.paddingTileIndex) or 0)
  if self.paddingTileIndex < 0 then
    self.paddingTileIndex = 0
  elseif self.paddingTileIndex > 255 then
    self.paddingTileIndex = 255
  end
  if data.generateDirty == true then
    self._generateDirty = true
  end

  addCanvasLayer(self, "Sketch", CANVAS_W, CANVAS_H, 0)
  self.activeLayer = 1

  return self
end

function SketchCanvasWindow:getActiveCanvasLayer()
  local li = self:getActiveLayerIndex() or 1
  local layer = self.layers and self.layers[li] or nil
  if layer and layer.kind == "canvas" and layer.canvas then
    return layer, li
  end
  return nil, li
end

function SketchCanvasWindow:getActiveCanvas()
  local layer = self:getActiveCanvasLayer()
  return layer and layer.canvas or nil
end

function SketchCanvasWindow:getVisibleSize()
  local canvas = self:getActiveCanvas()
  if canvas then
    return canvas.width, canvas.height
  end
  return Window.getVisibleSize(self)
end

function SketchCanvasWindow:getRealContentSize()
  local canvas = self:getActiveCanvas()
  if canvas then
    return canvas.width, canvas.height
  end
  return Window.getRealContentSize(self)
end

function SketchCanvasWindow:getContentSize()
  local canvas = self:getActiveCanvas()
  if canvas then
    return canvas.width, canvas.height
  end
  return Window.getContentSize(self)
end

function SketchCanvasWindow:toGridCoords(px, py)
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

local function ntIndex(self, col, row)
  local cols = self.cols or 32
  return row * cols + col + 1
end

--- Virtual tile handle for tile-mode nametable editing (pool index as item.id).
function SketchCanvasWindow:get(col, row, layerIndex)
  local WindowCaps = require("controllers.window.window_capabilities")
  if WindowCaps.isSketchReflectNametable(self) and type(self.nametableBytes) == "table" then
    local idx = ntIndex(self, col, row)
    local byte = self.nametableBytes[idx]
    if byte == nil then
      return nil
    end
    return {
      kind = "sketch_nt",
      id = math.floor(tonumber(byte) or 0),
      poolIndex = math.floor(tonumber(byte) or 0),
    }
  end
  return Window.get(self, col, row, layerIndex)
end

function SketchCanvasWindow:setNametableByteAt(col, row, byteVal, _tilesPool, _layerIndex)
  if type(self.nametableBytes) ~= "table" then
    return false
  end
  local idx = ntIndex(self, col, row)
  if idx < 1 or idx > #self.nametableBytes then
    return false
  end
  local v = math.floor(tonumber(byteVal) or 0)
  if v < 0 then
    v = 0
  elseif v > 255 then
    v = 255
  end
  self.nametableBytes[idx] = v
  local Pack = require("controllers.game_art.sketch_canvas_pack_controller")
  Pack.markReflectLayoutDirty(self)
  Pack.invalidateReflectDisplay(self)
  return true
end

function SketchCanvasWindow:swapNametableBytesAt(col1, row1, col2, row2)
  if type(self.nametableBytes) ~= "table" then
    return false
  end
  local i1 = ntIndex(self, col1, row1)
  local i2 = ntIndex(self, col2, row2)
  if i1 < 1 or i1 > #self.nametableBytes or i2 < 1 or i2 > #self.nametableBytes then
    return false
  end
  local a = self.nametableBytes[i1]
  self.nametableBytes[i1] = self.nametableBytes[i2]
  self.nametableBytes[i2] = a
  local Pack = require("controllers.game_art.sketch_canvas_pack_controller")
  Pack.markReflectLayoutDirty(self)
  Pack.invalidateReflectDisplay(self)
  return true
end

return SketchCanvasWindow
