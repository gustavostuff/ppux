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

--- CHR index within one 8KiB bank: page-1 tiles 0..255, page-2 tiles 256..511.
local function clampChrTileIndex511(v)
  local n = math.floor(tonumber(v) or 0)
  if n < 0 then return 0 end
  if n > 511 then return 511 end
  return n
end

local function chrTileIndexToPageByte(ti)
  ti = clampChrTileIndex511(ti)
  local page = (ti >= 256) and 2 or 1
  local tileByte = ti % 256
  return page, tileByte
end

local function readGlobalChrFromTo(r)
  if type(r) ~= "table" then
    return nil, nil
  end
  local from = r.from
  local to = r.to
  if from == nil and r.start ~= nil then
    from = r.start
  end
  if to == nil and r["end"] ~= nil then
    to = r["end"]
  end
  if from == nil or to == nil then
    return nil, nil
  end
  from = math.floor(tonumber(from) or -1)
  to = math.floor(tonumber(to) or -1)
  if from < 0 or from > 511 or to < 0 or to > 511 or to < from then
    return nil, nil
  end
  return from, to
end

--- Contiguous CHR indices 0..511 within `bank`, **without** legacy `page` (1/2).
--- Use top-level `from` / `to` (or `start` / `end`) as CHR indices 0..511; no `page` (1/2) on the row.
local function rangeUsesGlobalChrFromTo(r)
  if type(r) ~= "table" then
    return false
  end
  if type(r.tiles) == "table" and #r.tiles > 0 then
    return false
  end
  local page = r.page
  if page ~= nil then
    local pn = math.floor(tonumber(page) or -1)
    if pn == 1 or pn == 2 then
      return false
    end
  end
  local from, to = readGlobalChrFromTo(r)
  return from ~= nil and to ~= nil
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

function M.buildMap(patternTable, fallbackBank, fallbackPage)
  if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" then
    return buildDefaultMap(fallbackBank, fallbackPage), nil
  end

  local function appendExplicitTilesRange(r, ri, out, nextIdx)
    if type(r.tiles) ~= "table" or #r.tiles == 0 then
      return nil, string.format("patternTable.ranges[%d] has empty tiles list", ri)
    end
    local defaultBank = clampBank(r.bank)
    for j, t in ipairs(r.tiles) do
      if type(t) ~= "table" then
        return nil, string.format("patternTable.ranges[%d].tiles[%d] invalid", ri, j)
      end
      local bank = clampBank(t.bank or defaultBank)
      local page, src
      if t.tileIndex ~= nil or t.startTileIndex ~= nil then
        local ti = t.tileIndex or t.startTileIndex
        page, src = chrTileIndexToPageByte(ti)
      else
        page = clampPage(t.page)
        local rawB = t.byte
        if rawB == nil and t.tileByte ~= nil then
          rawB = t.tileByte
        end
        src = clampByte(rawB)
      end
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
    return nextIdx, nil
  end

  local out = {}
  local nextIdx = 0
  for i, r in ipairs(patternTable.ranges) do
    if type(r) == "table" and type(r.tiles) == "table" and #r.tiles > 0 then
      local nxt, terr = appendExplicitTilesRange(r, i, out, nextIdx)
      if terr ~= nil then
        return nil, terr
      end
      nextIdx = nxt
    elseif rangeUsesGlobalChrFromTo(r) then
      local fromTI, toTI = readGlobalChrFromTo(r)
      if fromTI == nil then
        return nil, string.format("patternTable.ranges[%d] has invalid global from/to (0..511)", i)
      end
      local bank = clampBank(r.bank)
      if bank < 1 then
        return nil, string.format("patternTable.ranges[%d] is missing bank", i)
      end
      for ti = fromTI, toTI do
        if nextIdx > 255 then
          return nil, "patternTable ranges exceed 256 tiles"
        end
        local page, src = chrTileIndexToPageByte(ti)
        out[nextIdx] = {
          bank = bank,
          page = page,
          tileByte = src,
          tileIndex = ti,
        }
        nextIdx = nextIdx + 1
      end
    else
      return nil, string.format(
        "patternTable.ranges[%d] must use explicit `tiles` or contiguous `{ bank, from, to }` (CHR 0..511, no page on row)",
        i
      )
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

--- Layout / persistence validation: require an explicit `ranges` list that maps exactly 256 indices.
--- Do **not** treat nil or `{ ranges = nil }` as valid - `buildMap` would silently fall back to bank 1
--- for every tile and would mask linked-only nametable layers until after `resolveLinkedPatternTableLayers`.
function M.validate(patternTable)
  if type(patternTable) ~= "table" then
    return false, "pattern_table_missing"
  end
  if type(patternTable.ranges) ~= "table" then
    return false, "pattern_table_missing_ranges"
  end
  local _, err = M.buildMap(patternTable, 1, 1)
  if err then
    return false, err
  end
  return true, nil
end

--- Compact layout rows: `{ bank, from, to }` with CHR indices 0..511 (no `page`).
function M.isGlobalChrFromToRange(r)
  return rangeUsesGlobalChrFromTo(r)
end

--- @return fromChr, toChr or nil, nil
function M.globalChrFromToBounds(r)
  if not rangeUsesGlobalChrFromTo(r) then
    return nil, nil
  end
  return readGlobalChrFromTo(r)
end

return M
