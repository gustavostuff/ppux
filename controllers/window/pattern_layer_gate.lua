-- Shared rules for when PPU / OAM layers may render fully or receive edits:
-- * Nametable (ROM tile) layers: nametable addresses, decoded grid bytes, complete pattern table
--   for interaction / CHR rendering. Addresses + bytes alone allow a frequency "shadow" preview.
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

local function ppuNametableLayer(win, layerIndex)
  local layer = win and win.layers and win.layers[layerIndex]
  if not (WindowCaps.isPpuFrame(win) and ppuTileLayerUsesNametableBytes(layer)) then
    return nil
  end
  if layer._runtimePatternTableRefLayer == true then
    return nil
  end
  return layer
end

--- True when a layer points at a pattern_table window id that is missing or closed.
local function linkedPatternTableWindowMissing(layer)
  local id = layer and layer.linkedPatternTableWindowId
  if type(id) ~= "string" or id == "" then
    return false
  end
  local ctx = rawget(_G, "ctx")
  local wm = ctx and ctx.app and ctx.app.wm
  if not (wm and wm.getWindows) then
    return false
  end
  for _, w in ipairs(wm:getWindows()) do
    if w and w._id == id and not w._closed and WindowCaps.isPatternTable(w) then
      return false
    end
  end
  return true
end

--- True when decoded nametable bytes can be shown as a frequency shadow (no pattern table required).
function M.canDrawNametableShadow(win, layerIndex)
  local layer = ppuNametableLayer(win, layerIndex)
  if not layer then
    return false
  end
  if type(layer.nametableStartAddr) ~= "number" or type(layer.nametableEndAddr) ~= "number" then
    return false
  end
  return M.nametableByteGridReady(win)
end

--- Shadow instead of CHR: bytes ready and pattern table not usable (invalid or link target gone).
function M.shouldDrawNametableShadow(win, layerIndex)
  if not M.canDrawNametableShadow(win, layerIndex) then
    return false
  end
  local layer = ppuNametableLayer(win, layerIndex)
  if not layer then
    return false
  end
  if linkedPatternTableWindowMissing(layer) then
    return true
  end
  local ok = PatternTableMapping.validate(layer.patternTable)
  return not ok
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
      if linkedPatternTableWindowMissing(layer) then
        return true, "pattern table window missing"
      end
      local ok, err = PatternTableMapping.validate(layer.patternTable)
      if not ok then
        return true, err or "patternTable invalid"
      end
      return false, nil
    end

    if layer.kind == "sprite" then
      if linkedPatternTableWindowMissing(layer) then
        return true, "pattern table window missing"
      end
      local ok, err = PatternTableMapping.validate(layer.patternTable)
      if not ok then
        return true, err or "sprite patternTable invalid"
      end
      return false, nil
    end

    return false, nil
  end

  if WindowCaps.isOamAnimation(win) and layer.kind == "sprite" then
    if linkedPatternTableWindowMissing(layer) then
      return true, "pattern table window missing"
    end
    local ok, err = PatternTableMapping.validate(layer.patternTable)
    if not ok then
      return true, err or "sprite patternTable invalid"
    end
  end

  return false, nil
end

return M
