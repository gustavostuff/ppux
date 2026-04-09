-- Nametable byte for "empty" / glass cells and for clearing moved tiles on PPU nametable layers.
-- Single source: layer.glassTileByte when set; otherwise default 0 (pattern-table index 0 within
-- the layer's bank/page — page 2 still uses byte 0, resolved to tilesPool offset 256+0).

local M = {}

local function clampByte(byteVal)
  local v = math.floor(tonumber(byteVal) or 0)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

--- @param layer table|nil layer from win.layers[i]
function M.forLayer(layer)
  if layer and layer.glassTileByte ~= nil then
    return clampByte(layer.glassTileByte)
  end
  return 0x00
end

--- Migrate legacy transparentTileByte; clears transparentTileByte from the table.
function M.migrateLayerFields(layer)
  if not layer then
    return
  end
  if layer.transparentTileByte ~= nil and layer.glassTileByte == nil then
    layer.glassTileByte = clampByte(layer.transparentTileByte)
  end
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
