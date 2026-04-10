local M = {}

local function clampByte(v)
  local n = math.floor(tonumber(v) or 0)
  if n < 0 then return 0 end
  if n > 255 then return 255 end
  return n
end

local function clampBank(v)
  local n = math.floor(tonumber(v) or 1)
  if n < 1 then return 1 end
  return n
end

local function clampPage(v)
  local n = math.floor(tonumber(v) or 1)
  if n < 1 then return 1 end
  if n > 2 then return 2 end
  return n
end

local function buildDefaultMap(fallbackBank, fallbackPage)
  local out = {}
  local bank = clampBank(fallbackBank)
  local page = clampPage(fallbackPage)
  for i = 0, 255 do
    out[i] = {
      bank = bank,
      page = page,
      tileByte = i,
      tileIndex = (page == 2) and (256 + i) or i,
    }
  end
  return out
end

local function parseRangeBounds(range)
  if type(range) ~= "table" then
    return nil, nil
  end
  local from = range.from
  local to = range.to
  if from == nil and range.start ~= nil then
    from = range.start
  end
  if to == nil and range["end"] ~= nil then
    to = range["end"]
  end
  if type(range.tileRange) == "table" then
    local tr = range.tileRange
    if from == nil and tr.from ~= nil then
      from = tr.from
    end
    if to == nil and tr.to ~= nil then
      to = tr.to
    end
    if from == nil and tr.start ~= nil then
      from = tr.start
    end
    if to == nil and tr["end"] ~= nil then
      to = tr["end"]
    end
  end
  return from, to
end

function M.buildMap(patternTable, fallbackBank, fallbackPage)
  if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" then
    return buildDefaultMap(fallbackBank, fallbackPage), nil
  end

  local out = {}
  local nextIdx = 0
  for i, r in ipairs(patternTable.ranges) do
    local fromRaw, toRaw = parseRangeBounds(r)
    if fromRaw == nil or toRaw == nil then
      return nil, string.format("patternTable.ranges[%d] missing from/to", i)
    end
    local from = clampByte(fromRaw)
    local to = clampByte(toRaw)
    if to < from then
      return nil, string.format("patternTable.ranges[%d] has to < from", i)
    end
    local bank = clampBank(r.bank)
    local page = clampPage(r.page)
    for src = from, to do
      if nextIdx > 255 then
        return nil, "patternTable ranges exceed 256 tiles"
      end
      out[nextIdx] = {
        bank = bank,
        page = page,
        tileByte = src,
        tileIndex = (page == 2) and (256 + src) or src,
      }
      nextIdx = nextIdx + 1
    end
  end

  if nextIdx ~= 256 then
    return nil, string.format("patternTable ranges must add up to 256 tiles (got %d)", nextIdx)
  end

  return out, nil
end

function M.resolveTile(tilesPool, layer, logicalIndex, fallbackBank, fallbackPage)
  if not tilesPool then
    return nil, "missing_tiles_pool"
  end
  local map, err = M.buildMap(layer and layer.patternTable or nil, fallbackBank, fallbackPage)
  if not map then
    return nil, err
  end

  local idx = clampByte(logicalIndex)
  local entry = map[idx]
  if not entry then
    return nil, "pattern_table_index_out_of_range"
  end
  local bank = tilesPool[entry.bank]
  if not bank then
    return nil, string.format("missing_bank_%d", entry.bank)
  end
  return bank[entry.tileIndex], nil
end

function M.logicalIndexForTileRef(layer, tileRef, fallbackBank, fallbackPage)
  if type(tileRef) ~= "table" or type(tileRef.index) ~= "number" then
    return nil, "invalid_tile_ref"
  end
  local map, err = M.buildMap(layer and layer.patternTable or nil, fallbackBank, fallbackPage)
  if not map then
    return nil, err
  end

  local bank = clampBank(tileRef._bankIndex or fallbackBank)
  local tileIndex = math.floor(tonumber(tileRef.index) or 0)
  local page = (tileIndex >= 256) and 2 or 1
  local tileByte = clampByte(tileIndex % 256)

  for logicalIndex = 0, 255 do
    local entry = map[logicalIndex]
    if entry
      and entry.bank == bank
      and entry.page == page
      and entry.tileByte == tileByte then
      return logicalIndex, nil
    end
  end

  return nil, "tile_not_mapped_in_pattern_table"
end

function M.validate(patternTable)
  local _, err = M.buildMap(patternTable, 1, 1)
  if err then
    return false, err
  end
  return true, nil
end

return M
