-- pattern_table_builder_window.lua
-- Scratch workspace for drawing source pixel art and generating packed pattern tables.

local Window = require("user_interface.windows_system.window")
local PixelCanvas = require("user_interface.windows_system.pixel_canvas")

local PatternTableBuilderWindow = setmetatable({}, { __index = Window })
PatternTableBuilderWindow.__index = PatternTableBuilderWindow

local SOURCE_W = 256
local SOURCE_H = 240
local PACKED_W = 128
local PACKED_H = 128
local CELL = 8
local PACKED_TILE_COLS = math.floor(PACKED_W / CELL)
local PACKED_TILE_ROWS = math.floor(PACKED_H / CELL)
local MAX_PACKED_TILES = PACKED_TILE_COLS * PACKED_TILE_ROWS

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

function PatternTableBuilderWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  data = data or {}
  cols = cols or math.floor(SOURCE_W / CELL)
  rows = rows or math.floor(SOURCE_H / CELL)
  cellW = cellW or CELL
  cellH = cellH or CELL

  local self = Window.new(x, y, cellW, cellH, cols, rows, zoom, {
    flags = {
      allowInternalDrag = false,
      allowExternalDrag = true,
      allowExternalDrop = false,
    },
    title = data.title or "Pattern Table Builder",
    visibleRows = data.visibleRows or rows,
    visibleCols = data.visibleCols or cols,
    resizable = false,
  })
  setmetatable(self, PatternTableBuilderWindow)

  self.kind = "pattern_table_builder"
  self.patternTolerance = math.max(0, math.floor(tonumber(data.patternTolerance) or 0))
  self.layers = {}
  self.lastGenerationResult = nil

  addCanvasLayer(self, "Source Canvas", SOURCE_W, SOURCE_H, 0)
  addCanvasLayer(self, "Packed Pattern Table", PACKED_W, PACKED_H, 0)
  self.activeLayer = 1

  return self
end

local function tilePixelsKey(pixels)
  local out = {}
  for i = 1, #pixels do
    out[i] = string.char((pixels[i] or 0) + 48)
  end
  return table.concat(out)
end

function PatternTableBuilderWindow:generatePackedPatternTable()
  local sourceLayer = self.layers and self.layers[1] or nil
  local packedLayer = self.layers and self.layers[2] or nil
  local sourceCanvas = sourceLayer and sourceLayer.canvas or nil
  local packedCanvas = packedLayer and packedLayer.canvas or nil
  if not (sourceCanvas and packedCanvas) then
    return false, "missing_canvas"
  end

  packedCanvas:clear(0)

  local seen = {}
  local uniqueTiles = 0
  local totalTiles = 0
  local overflowTiles = 0

  for tileRow = 0, math.floor(sourceCanvas.height / CELL) - 1 do
    for tileCol = 0, math.floor(sourceCanvas.width / CELL) - 1 do
      totalTiles = totalTiles + 1
      local px = tileCol * CELL
      local py = tileRow * CELL
      local pixels = sourceCanvas:extractTilePixels(px, py, CELL)
      local key = tilePixelsKey(pixels)

      if not seen[key] then
        uniqueTiles = uniqueTiles + 1
        if uniqueTiles <= MAX_PACKED_TILES then
          seen[key] = uniqueTiles
          local packedIndex = uniqueTiles - 1
          local packedTileCol = packedIndex % PACKED_TILE_COLS
          local packedTileRow = math.floor(packedIndex / PACKED_TILE_COLS)
          packedCanvas:loadTilePixels(packedTileCol * CELL, packedTileRow * CELL, pixels, CELL)
        else
          overflowTiles = overflowTiles + 1
        end
      end
    end
  end

  local placedTiles = math.min(uniqueTiles, MAX_PACKED_TILES)
  local result = {
    mode = "8x8",
    totalTiles = totalTiles,
    uniqueTiles = uniqueTiles,
    placedTiles = placedTiles,
    overflowTiles = overflowTiles,
    capacity = MAX_PACKED_TILES,
    toleranceUsed = self.patternTolerance or 0,
  }
  self.lastGenerationResult = result
  return true, result
end

function PatternTableBuilderWindow:getActiveCanvasLayer()
  local li = self:getActiveLayerIndex() or 1
  local layer = self.layers and self.layers[li] or nil
  if layer and layer.kind == "canvas" and layer.canvas then
    return layer, li
  end
  return nil, li
end

function PatternTableBuilderWindow:getActiveCanvas()
  local layer = self:getActiveCanvasLayer()
  return layer and layer.canvas or nil
end

function PatternTableBuilderWindow:getVisibleSize()
  local canvas = self:getActiveCanvas()
  if canvas then
    return canvas.width, canvas.height
  end
  return Window.getVisibleSize(self)
end

function PatternTableBuilderWindow:getRealContentSize()
  local canvas = self:getActiveCanvas()
  if canvas then
    return canvas.width, canvas.height
  end
  return Window.getRealContentSize(self)
end

function PatternTableBuilderWindow:getContentSize()
  local canvas = self:getActiveCanvas()
  if canvas then
    return canvas.width, canvas.height
  end
  return Window.getContentSize(self)
end

function PatternTableBuilderWindow:toGridCoords(px, py)
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

return PatternTableBuilderWindow
