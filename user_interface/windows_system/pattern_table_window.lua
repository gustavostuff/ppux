-- pattern_table_window.lua
-- Standalone 16x16 (default) logical pattern table editor; ROM-backed tile ranges only for now.

local Window = require("user_interface.windows_system.window")

local PatternTableWindow = setmetatable({}, { __index = Window })
PatternTableWindow.__index = PatternTableWindow

function PatternTableWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
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
  setmetatable(self, PatternTableWindow)

  self.kind = "pattern_table"
  self.layers = {}
  self.activeLayer = 1

  return self
end

return PatternTableWindow
