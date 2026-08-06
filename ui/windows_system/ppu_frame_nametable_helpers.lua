-- Shared nametable model/render helpers for PPU frame windows.

local M = {}

function M.lin(cols, col, row)
  return row * cols + col + 1
end

function M.isNametableLayer(layer)
  if not layer then
    return false
  end
  if layer._runtimePatternTableRefLayer == true then
    return false
  end
  if layer.kind == "tile" then
    return true
  end
  return (layer.nametableStartAddr ~= nil) or (layer.nametableEndAddr ~= nil)
end

function M.getNametableLayer(self)
  if not self.layers or #self.layers == 0 then
    return nil, nil
  end
  local idx = tonumber(self.activeLayer) or 1
  local active = self.layers[idx]
  if M.isNametableLayer(active) then
    return active, idx
  end

  for i, L in ipairs(self.layers) do
    if M.isNametableLayer(L) then
      return L, i
    end
  end

  local first = self.layers[1]
  if not first then
    return nil, nil
  end
  return first, 1
end

function M.getCurrentRomRaw(self)
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app or nil
  local liveRom = app and app.appEditState and app.appEditState.romRaw or nil
  if type(liveRom) == "string" and liveRom ~= "" then
    return liveRom
  end
  return self.romRaw
end

function M.decodePaletteNumberFromAttributes(win, col, row)
  local attrBytes = win and win.nametableAttrBytes or nil
  local cols = win and win.cols or 32
  if type(attrBytes) ~= "table" or #attrBytes == 0 then
    return nil
  end

  local attrCols = math.max(1, math.floor((cols or 32) / 4))
  local attrCol = math.floor((col or 0) / 4)
  local attrRow = math.floor((row or 0) / 4)
  local attrIndex = attrRow * attrCols + attrCol + 1
  if attrIndex < 1 or attrIndex > #attrBytes then
    return nil
  end

  local attrByte = tonumber(attrBytes[attrIndex]) or 0
  local localCol = (col or 0) % 4
  local localRow = (row or 0) % 4
  local palIndex = 0
  if localRow < 2 then
    if localCol < 2 then
      palIndex = attrByte % 4
    else
      palIndex = math.floor((attrByte % 16) / 4)
    end
  else
    if localCol < 2 then
      palIndex = math.floor((attrByte % 64) / 16)
    else
      palIndex = math.floor(attrByte / 64)
    end
  end
  return palIndex + 1
end

function M.getPaletteLayerForRender(win, layer)
  if type(layer) == "table" and layer._runtimePatternTableRefLayer == true then
    return nil
  end
  if type(layer) == "table" and type(layer.paletteData) == "table" then
    return layer
  end
  if not (win and type(win.layers) == "table") then
    return layer
  end
  for _, candidate in ipairs(win.layers) do
    if candidate
      and candidate.kind == "tile"
      and candidate._runtimePatternTableRefLayer ~= true
      and type(candidate.paletteData) == "table"
    then
      return candidate
    end
  end
  return layer
end

return M
