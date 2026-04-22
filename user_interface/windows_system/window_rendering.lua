-- window_rendering.lua
-- Aggregates rendering mixins for Window.

local installGrid = require("user_interface.windows_system.window_rendering_grid")
local installSelection = require("user_interface.windows_system.window_rendering_selection")
local installChrome = require("user_interface.windows_system.window_rendering_chrome")
local installTileLayerCanvas = require("user_interface.windows_system.window_tile_layer_canvas")

return function(Window)
  installGrid(Window)
  installSelection(Window)
  installChrome(Window)
  installTileLayerCanvas(Window)
end
