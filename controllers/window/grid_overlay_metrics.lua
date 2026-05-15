-- Chess / lines grid overlays: vertical band size in NES pixels when "8×16 metatile rows"
-- are shown on an 8px-tall nominal grid (CHR bank, pattern table CHR-order), vs windows whose
-- getDisplayGridMetrics already uses cellH = 2 × baseCellH (e.g. static_art tile layer 8x16).

local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

--- One horizontal band height for chess / horizontal line spacing in lines grid (NES px).
function M.overlayVerticalPeriodNes(window, grid, layerIndex)
  grid = grid or {}
  layerIndex = layerIndex
    or window and window.getActiveLayerIndex and window:getActiveLayerIndex()
    or window and window.activeLayer
    or 1
  local layer = window and window.layers and window.layers[layerIndex]
  local baseH = grid.baseCellH or 8
  local physH = grid.cellH or baseH

  if physH >= baseH * 2 then
    return physH
  end

  if WindowCaps.isChrLike(window) and window.orderMode == "oddEven" then
    return baseH * 2
  end

  if WindowCaps.isPatternTable(window)
    and layer
    and layer.kind == "tile"
    and (layer.mode == "8x16" or layer.mode == "oddEven")
  then
    return baseH * 2
  end

  return physH
end

--- How many nominal grid rows (8px indexing) between chess-band passes when iterating drawGrid.
function M.chessNominalRowSkip(window, grid, layerIndex)
  grid = grid or {}
  local baseH = grid.baseCellH or 8
  local physH = grid.cellH or baseH

  if physH >= baseH * 2 then
    return 1
  end

  local period = M.overlayVerticalPeriodNes(window, grid, layerIndex)
  if period > physH and physH >= 1 then
    local skip = math.floor(period / physH + 1e-6)
    return math.max(2, skip)
  end

  return 1
end

return M
