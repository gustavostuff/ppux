-- Nametable byte to use when clearing / "emptying" a PPU tile layer cell.
-- Matches PPUFrameWindow:getTransparentTileByte semantics — no assumption that empty is 0x00.

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
  if layer and layer.transparentTileByte ~= nil then
    return clampByte(layer.transparentTileByte)
  end
  return 0x00
end

return M
