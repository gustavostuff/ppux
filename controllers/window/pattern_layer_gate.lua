-- Shared rules for when PPU / OAM layers may render or receive edits:
-- * Nametable (ROM tile) layers: nametable addresses, decoded grid bytes, complete pattern table.
-- * Sprite layers (PPU + OAM): complete pattern table (256 logical tiles) from layout or linked window.

local WindowCaps = require("controllers.window.window_capabilities")
local PatternTableMapping = require("utils.pattern_table_mapping")

local M = {}

function M.nametableByteGridReady(win)
  if not win then
    return false
  end
  local bytes = win.nametableBytes
  if type(bytes) ~= "table" then
    return false
  end
  local cols = math.floor(tonumber(win.cols) or 32)
  local rows = math.floor(tonumber(win.rows) or 30)
  local need = math.max(1, cols * rows)
  return #bytes >= need
end

local function ppuTileLayerUsesNametableBytes(layer)
  return layer and layer.kind == "tile" and layer.attrMode ~= true
end

--- Returns locked (boolean), reason (string|nil). Mirrors legacy PPUFrameWindow:isPatternTableInteractionLocked
--- for tile layers; extends sprite layers on PPU + OAM animation windows.
function M.isLayerInteractionLocked(win, layerIndex)
  local layer = win and win.layers and win.layers[layerIndex]
  if not layer then
    return true, "missing_layer"
  end

  if WindowCaps.isPpuFrame(win) then
    if layer._runtimePatternTableRefLayer == true then
      return false, nil
    end

    if layer.kind == "tile" then
      if not ppuTileLayerUsesNametableBytes(layer) then
        return false, nil
      end
      if type(layer.nametableStartAddr) ~= "number" then
        return true, "nametableStartAddr is missing"
      end
      if type(layer.nametableEndAddr) ~= "number" then
        return true, "nametableEndAddr is missing"
      end
      if not M.nametableByteGridReady(win) then
        return true, "nametable bytes not loaded"
      end
      local ok, err = PatternTableMapping.validate(layer.patternTable)
      if not ok then
        return true, err or "patternTable invalid"
      end
      return false, nil
    end

    if layer.kind == "sprite" then
      local ok, err = PatternTableMapping.validate(layer.patternTable)
      if not ok then
        return true, err or "sprite patternTable invalid"
      end
      return false, nil
    end

    return false, nil
  end

  if WindowCaps.isOamAnimation(win) and layer.kind == "sprite" then
    local ok, err = PatternTableMapping.validate(layer.patternTable)
    if not ok then
      return true, err or "sprite patternTable invalid"
    end
  end

  return false, nil
end

return M
