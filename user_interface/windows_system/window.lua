-- window.lua — base grid window model
-- Constructor lives here; behavior/rendering are installed from sibling modules.

local Window = {}
Window.__index = Window
local UiScale = require("user_interface.ui_scale")

local SCROLL_BAR_OPACITY_TIME = 1.5

-- NOTE: visibleCols / visibleRows are optional and default to cols/rows.
function Window.new(x, y, cellW, cellH, cols, rows, zoom, data)
  data = data or {}
  local self = setmetatable({
    title = data.title or "(untitled)",
    x = x, y = y,
    cellW = cellW, cellH = cellH,
    cols = cols, rows = rows,
    zoom = zoom or 1.0,
    resizable = data.resizable,
    minWindowSize = data.minWindowSize,

    -- Scrolling viewport
    visibleCols = math.max(1, math.floor(data.visibleCols or cols)),
    visibleRows = math.max(1, math.floor(data.visibleRows or rows)),
    scrollCol   = 0,
    scrollRow   = 0,

    layers = {
      {
        items   = {},
        opacity = 1.0,
        name    = "Layer 1",
        kind    = "tile",
      }
    },
    nonActiveLayerOpacity = data.nonActiveLayerOpacity or 1.0,
    activeLayer = 1,

    flags = data.flags,

    dragging = false, dx = 0, dy = 0,
    checkerLight = { 0.15, 0.15, 0.15 },
    checkerDark  = { 0.10, 0.10, 0.10 },
    selected = nil,
    selectedByLayer = {},
    headerH = UiScale.windowHeaderHeight(),
    scrollbarOpacity = SCROLL_BAR_OPACITY_TIME,
    itemCountLabelMarkName = nil,
    itemCountLabelSpaceDown = false,
  }, Window)

  self.itemCountLabelMarkName = "windowItemCount_" .. tostring(self)

  return self
end

require("user_interface.windows_system.window_behaviors")(Window)
require("user_interface.windows_system.window_rendering")(Window)

return Window
