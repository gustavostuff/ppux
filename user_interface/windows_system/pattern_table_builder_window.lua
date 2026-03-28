-- pattern_table_builder_window.lua
-- Scratch workspace for drawing a 256x240 source canvas and future pattern-table packing.

local Window = require("user_interface.windows_system.window")
local TileItem = require("user_interface.windows_system.tile_item")

local PatternTableBuilderWindow = setmetatable({}, { __index = Window })
PatternTableBuilderWindow.__index = PatternTableBuilderWindow

local function seedBlankCanvasLayer(layer, cols, rows, fillValue)
  layer.items = {}
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local idx = row * cols + col + 1
      layer.items[idx] = TileItem.blank(fillValue)
    end
  end
end

function PatternTableBuilderWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  data = data or {}
  cols = cols or 32
  rows = rows or 30
  cellW = cellW or 8
  cellH = cellH or 8

  local self = Window.new(x, y, cellW, cellH, cols, rows, zoom, {
    flags = {
      allowInternalDrag = false,
      allowExternalDrag = true,
      allowExternalDrop = false,
    },
    title = data.title or "Pattern Table Builder",
    visibleRows = data.visibleRows or rows,
    visibleCols = data.visibleCols or cols,
    resizable = (data.resizable ~= false),
  })
  setmetatable(self, PatternTableBuilderWindow)

  self.kind = "pattern_table_builder"
  self.patternTolerance = math.max(0, math.floor(tonumber(data.patternTolerance) or 0))
  self.layers = {}

  local sourceIdx = self:addLayer({
    name = "Source Canvas",
    kind = "tile",
  })
  local packedIdx = self:addLayer({
    name = "Packed Pattern Table",
    kind = "tile",
  })

  seedBlankCanvasLayer(self.layers[sourceIdx], cols, rows, 0)
  self.layers[packedIdx].items = {}
  self.activeLayer = 1

  return self
end

return PatternTableBuilderWindow
