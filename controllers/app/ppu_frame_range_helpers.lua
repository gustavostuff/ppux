-- Shared PPU frame nametable / pattern-table helpers used by core_controller_ppu_frame
-- and core_controller_ppu_chr_menus (must not rely on mixin load order).

local TableUtils = require("utils.table_utils")

local M = {}

function M.getPpuNametableLayer(win)
  if not (win and win.layers) then return nil end
  local activeIndex = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  local activeLayer = win.layers[activeIndex]
  if activeLayer and activeLayer.kind ~= "sprite" then
    return activeLayer, activeIndex
  end
  for _, layer in ipairs(win.layers) do
    if layer and layer.kind ~= "sprite" then
      return layer
    end
  end
  return nil
end

function M.parsePatternRangeBounds(range)
  if type(range) ~= "table" then
    return nil, nil
  end
  local tileRange = type(range.tileRange) == "table" and range.tileRange or nil
  local from = range.from
  local to = range.to
  if from == nil and tileRange then
    from = tileRange.from
  end
  if to == nil and tileRange then
    to = tileRange.to
  end
  from = math.floor(tonumber(from) or -1)
  to = math.floor(tonumber(to) or -1)
  if from < 0 or from > 255 or to < 0 or to > 255 or to < from then
    return nil, nil
  end
  return from, to
end

function M.patternTableLogicalSize(patternTable)
  if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" then
    return 0, "patternTable.ranges is missing"
  end
  local total = 0
  for i, range in ipairs(patternTable.ranges) do
    local from, to = M.parsePatternRangeBounds(range)
    if from == nil or to == nil then
      return total, string.format("patternTable.ranges[%d] has invalid from/to", i)
    end
    total = total + (to - from + 1)
  end
  return total, nil
end

function M.buildPatternTableMapAllowPartial(patternTable)
  local map = {}

  if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" then
    return map, nil
  end

  local logicalIndex = 0
  for i, range in ipairs(patternTable.ranges) do
    local from, to = M.parsePatternRangeBounds(range)
    if from == nil or to == nil then
      return nil, string.format("patternTable.ranges[%d] has invalid from/to", i)
    end
    local bank = math.max(1, math.floor(tonumber(range.bank) or -1))
    local page = math.floor(tonumber(range.page) or -1)
    if bank < 1 then
      return nil, string.format("patternTable.ranges[%d] is missing bank", i)
    end
    if page < 1 then
      return nil, string.format("patternTable.ranges[%d] is missing page", i)
    end
    if page < 1 then page = 1 elseif page > 2 then page = 2 end
    for src = from, to do
      if logicalIndex > 255 then
        return nil, "patternTable ranges exceed 256 tiles"
      end
      map[logicalIndex] = {
        bank = bank,
        page = page,
        tileByte = src,
        tileIndex = (page == 2) and (256 + src) or src,
      }
      logicalIndex = logicalIndex + 1
    end
  end
  return map, nil
end

local function copyNumberArray(values)
  local out = {}
  if type(values) ~= "table" then
    return out
  end
  for i = 1, #values do
    out[i] = values[i]
  end
  return out
end

function M.snapshotPpuFrameRangeState(win, layerIndex)
  if not (win and win.kind == "ppu_frame") then
    return nil
  end

  local layer, resolvedLayerIndex = M.getPpuNametableLayer(win)
  local li = layerIndex or resolvedLayerIndex or 1
  layer = (win.getLayer and win:getLayer(li)) or layer
  if not layer then
    return nil
  end

  return {
    win = win,
    layerIndex = li,
    cols = win.cols,
    rows = win.rows,
    nametableStart = win.nametableStart,
    nametableBytes = copyNumberArray(win.nametableBytes),
    nametableAttrBytes = copyNumberArray(win.nametableAttrBytes),
    originalNametableBytes = copyNumberArray(win._originalNametableBytes),
    originalNametableAttrBytes = copyNumberArray(win._originalNametableAttrBytes),
    originalCompressedBytes = copyNumberArray(win._originalCompressedBytes),
    tileSwapsMap = TableUtils.deepcopy(win._tileSwaps),
    originalTotalByteNumber = win.originalTotalByteNumber,
    nametableOriginalSize = win._nametableOriginalSize,
    nametableCompressedSize = win._nametableCompressedSize,
    layerState = {
      kind = layer.kind,
      mode = layer.mode,
      codec = layer.codec,
      nametableStartAddr = layer.nametableStartAddr,
      nametableEndAddr = layer.nametableEndAddr,
      noOverflowSupported = layer.noOverflowSupported,
      patternTable = TableUtils.deepcopy(layer.patternTable),
      attrMode = layer.attrMode,
      tileSwaps = TableUtils.deepcopy(layer.tileSwaps),
    },
  }
end

function M.didPpuFrameRangeSettingsChange(beforeState, afterState)
  local beforeLayer = beforeState and beforeState.layerState or nil
  local afterLayer = afterState and afterState.layerState or nil
  if not (beforeLayer and afterLayer) then
    return false
  end

  local function patternTableSignature(patternTable)
    if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" then
      return ""
    end
    local parts = {}
    for i, range in ipairs(patternTable.ranges) do
      local from, to = M.parsePatternRangeBounds(range)
      parts[#parts + 1] = string.format(
        "%d:%d:%s:%s",
        math.floor(tonumber(range.bank) or -1),
        math.floor(tonumber(range.page) or -1),
        tostring(from),
        tostring(to)
      )
      if type(range.tileRange) == "table" then
        parts[#parts + 1] = string.format(
          "tr:%s:%s",
          tostring(range.tileRange.from),
          tostring(range.tileRange.to)
        )
      end
      parts[#parts + 1] = ";"
      if i >= 512 then
        break
      end
    end
    return table.concat(parts, "|")
  end

  return beforeLayer.nametableStartAddr ~= afterLayer.nametableStartAddr
    or beforeLayer.nametableEndAddr ~= afterLayer.nametableEndAddr
    or beforeLayer.noOverflowSupported ~= afterLayer.noOverflowSupported
    or beforeLayer.codec ~= afterLayer.codec
    or patternTableSignature(beforeLayer.patternTable) ~= patternTableSignature(afterLayer.patternTable)
end

return M
