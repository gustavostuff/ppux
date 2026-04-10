-- Nametable byte for "empty" / glass cells and for clearing moved tiles on PPU nametable layers.
-- New preferred source: layer.patternTable.glassTileIndex (logical tile index).
-- Backward compatible with legacy layer.glassTile / glassTileByte / transparentTileByte.

local M = {}

local function clampByte(byteVal)
  local v = math.floor(tonumber(byteVal) or 0)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

local function ensurePatternTable(layer)
  if type(layer) ~= "table" then
    return nil
  end
  if type(layer.patternTable) ~= "table" then
    layer.patternTable = {}
  end
  return layer.patternTable
end

--- @param layer table|nil layer from win.layers[i]
--- @return number|nil normalized logical index (0..255)
function M.getGlassTileIndex(layer)
  if type(layer) ~= "table" then
    return nil
  end

  local pt = layer.patternTable
  if type(pt) == "table" and pt.glassTileIndex ~= nil and type(pt.glassTileIndex) == "number" then
    return clampByte(pt.glassTileIndex)
  end

  if type(layer.glassTile) == "table" and layer.glassTile.tile ~= nil then
    -- Legacy absolute tile (0..511): keep the byte-facing logical index.
    return clampByte(layer.glassTile.tile % 256)
  end

  if layer.glassTileByte ~= nil then
    return clampByte(layer.glassTileByte)
  end

  if layer.transparentTileByte ~= nil then
    return clampByte(layer.transparentTileByte)
  end

  return nil
end

function M.setGlassTileIndex(layer, tileIndex)
  local pt = ensurePatternTable(layer)
  if not pt then return false end
  pt.glassTileIndex = clampByte(tileIndex)
  return true
end

function M.clearGlassTileIndex(layer)
  local pt = ensurePatternTable(layer)
  if pt then
    pt.glassTileIndex = nil
  end
  if type(layer) == "table" then
    layer.glassTile = nil
    layer.glassTileByte = nil
    layer.transparentTileByte = nil
  end
end

--- @param layer table|nil layer from win.layers[i]
function M.forLayer(layer)
  local glassTileIndex = M.getGlassTileIndex(layer)
  if glassTileIndex ~= nil then
    return clampByte(glassTileIndex)
  end
  return 0x00
end

function M.hasExplicit(layer)
  return M.getGlassTileIndex(layer) ~= nil
end

--- Migrate legacy transparentTileByte; clears transparentTileByte from the table.
function M.migrateLayerFields(layer)
  if not layer then
    return
  end

  local migratedIndex = M.getGlassTileIndex(layer)
  if migratedIndex ~= nil then
    M.setGlassTileIndex(layer, migratedIndex)
  end

  layer.glassTile = nil
  layer.glassTileByte = nil
  layer.transparentTileByte = nil
end

--- Walk project.layout-style windows tables (windows[].layers[]).
function M.migrateProjectWindowsLayers(windows)
  if type(windows) ~= "table" then
    return
  end
  for _, win in ipairs(windows) do
    if type(win) == "table" and type(win.layers) == "table" then
      for _, L in ipairs(win.layers) do
        M.migrateLayerFields(L)
      end
    end
  end
end

return M
