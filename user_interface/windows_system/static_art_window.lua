-- static_art_window.lua
-- A layered art window for static compositions.
-- Inherits from Window and starts with exactly 2 layers.

local Window = require("user_interface.windows_system.window")

local StaticArtWindow = setmetatable({}, { __index = Window })
StaticArtWindow.__index = StaticArtWindow

-- Helper: reset layers to a fixed count with optional names/opacities
local function resetLayers(self, count, names)
  self.layers = {}
  for i = 1, count do
    self:addLayer({
      opacity = 1.0,
      name    = (names and names[i]) or ("Layer " .. i),
    })
  end
  self.activeLayer = 1
end

function StaticArtWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  data = data or {}
  data.resizable = true
  local self = Window.new(x, y, cellW, cellH, cols, rows, zoom, {
    flags = {
      allowInternalDrag = false,
      allowExternalDrag = true,
      allowExternalDrop = false,
    },
    title = data.title,
    visibleRows = data.visibleRows or rows,
    visibleCols = data.visibleCols or cols,
    resizable = data.resizable,
  })
  setmetatable(self, StaticArtWindow)

  self.kind = "static_art"
  self.layers = {}
  self.activeLayer = 1

  return self
end

return StaticArtWindow
