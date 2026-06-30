-- Shared PPU frame nametable / pattern-table helpers used by core_controller_ppu_frame
-- and core_controller_ppu_chr_menus (must not rely on mixin load order).

local TableUtils = require("utils.table_utils")
local BankViewController = require("controllers.chr.bank_view_controller")
local PatternTableMapping = require("utils.pattern_table_mapping")

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

--- Default "Add tile range" modal fields from the last persisted range row.
--- @return initialBank, initialPage, initialFrom, initialTo (strings for from/to except bank)
function M.patternRangeModalInitialValues(lastRange)
  local initialBank = "1"
  local initialPage = 1
  local initialFrom = "0"
  local initialTo = "255"
  if type(lastRange) ~= "table" then
    return initialBank, initialPage, initialFrom, initialTo
  end
  initialBank = tostring(tonumber(lastRange.bank) or 1)
  if M.patternRangeUsesExplicitTiles(lastRange) then
    return initialBank, initialPage, initialFrom, initialTo
  end
  if PatternTableMapping.isGlobalChrFromToRange(lastRange) then
    local a, b = PatternTableMapping.globalChrFromToBounds(lastRange)
    if a == nil or b == nil then
      return initialBank, initialPage, initialFrom, initialTo
    end
    if a <= 255 and b <= 255 then
      return initialBank, 1, tostring(a), tostring(b)
    end
    if a >= 256 and b >= 256 then
      return initialBank, 2, tostring(a - 256), tostring(b - 256)
    end
    return initialBank, 1, tostring(a), tostring(255)
  end
  return initialBank, initialPage, initialFrom, initialTo
end

--- One logical "range" row may list explicit `{ bank, page, byte }` or `{ bank, tileIndex }` tiles (CHR multi-drop),
--- instead of contiguous `{ bank, from, to }` (global CHR 0..511).
function M.patternRangeUsesExplicitTiles(range)
  return type(range) == "table" and type(range.tiles) == "table" and #range.tiles > 0
end

local function explicitTileBankPageByte(t, idxForErr, defaultBank)
  defaultBank = math.floor(tonumber(defaultBank) or -1)
  if type(t) ~= "table" then
    return nil, nil, nil, (idxForErr and string.format("tiles[%d] is not a table", idxForErr)) or "invalid tile"
  end
  local bank = math.floor(tonumber(t.bank) or defaultBank or -1)
  if t.tileIndex ~= nil or t.startTileIndex ~= nil then
    local ti = math.floor(tonumber(t.tileIndex or t.startTileIndex) or -1)
    if bank < 1 then
      return nil, nil, nil, (idxForErr and string.format("tiles[%d] has invalid bank", idxForErr)) or "invalid bank"
    end
    if ti < 0 or ti > 511 then
      return nil, nil, nil, (idxForErr and string.format("tiles[%d] has invalid tileIndex", idxForErr)) or "invalid tileIndex"
    end
    local page = (ti >= 256) and 2 or 1
    local byte = ti % 256
    return bank, page, byte, nil
  end
  local page = math.floor(tonumber(t.page) or -1)
  local byteRaw = t.byte
  if byteRaw == nil and t.tileByte ~= nil then
    byteRaw = t.tileByte
  end
  local byte = math.floor(tonumber(byteRaw) or -1)
  if bank < 1 then
    return nil, nil, nil, (idxForErr and string.format("tiles[%d] has invalid bank", idxForErr)) or "invalid bank"
  end
  if page ~= 1 and page ~= 2 then
    return nil, nil, nil, (idxForErr and string.format("tiles[%d] has invalid page", idxForErr)) or "invalid page"
  end
  if byte < 0 or byte > 255 then
    return nil, nil, nil, (idxForErr and string.format("tiles[%d] has invalid byte", idxForErr)) or "invalid byte"
  end
  return bank, page, byte, nil
end

--- @return length, err
function M.patternRangeLogicalLength(range)
  if M.patternRangeUsesExplicitTiles(range) then
    local db = range.bank
    for i, t in ipairs(range.tiles) do
      local _, _, _, terr = explicitTileBankPageByte(t, i, db)
      if terr then
        return nil, terr
      end
    end
    return #range.tiles, nil
  end
  if PatternTableMapping.isGlobalChrFromToRange(range) then
    local a, b = PatternTableMapping.globalChrFromToBounds(range)
    if a == nil or b == nil then
      return nil, "invalid global from/to"
    end
    return (b - a + 1), nil
  end
  return nil, "pattern range must use explicit tiles or { bank, from, to } (CHR 0..511)"
end

function M.foreachBankInPatternRange(range, fn)
  if type(fn) ~= "function" or type(range) ~= "table" then
    return
  end
  if M.patternRangeUsesExplicitTiles(range) then
    for _, t in ipairs(range.tiles) do
      local b = math.floor(tonumber(t.bank) or tonumber(range.bank) or -1)
      if b >= 1 then
        fn(b)
      end
    end
    return
  end
  if PatternTableMapping.isGlobalChrFromToRange(range) then
    local b = math.floor(tonumber(range.bank) or -1)
    if b >= 1 then
      fn(b)
    end
  end
end

--- Human / validation errors when appending a range row (modal uses classic shape only).
function M.validatePatternRangeAppendShape(range, rangeIndex)
  rangeIndex = tonumber(rangeIndex) or 0
  local label = rangeIndex > 0 and string.format("pattern range %d", rangeIndex) or "pattern range"

  if M.patternRangeUsesExplicitTiles(range) then
    local db = range.bank
    for i, t in ipairs(range.tiles) do
      local _, _, _, terr = explicitTileBankPageByte(t, i, db)
      if terr then
        return label .. ": " .. terr
      end
    end
    return nil
  end

  if PatternTableMapping.isGlobalChrFromToRange(range) then
    local bank = math.floor(tonumber(range.bank) or -1)
    if bank < 1 then
      return label .. " is missing bank"
    end
    local a, b = PatternTableMapping.globalChrFromToBounds(range)
    if a == nil or b == nil then
      return label .. ": invalid global from/to (0..511, from <= to)"
    end
    return nil
  end

  return label .. ": use explicit tiles or { bank, from, to } without page on the row"
end

--- Row-major logical indices 0..255 across patternTable.ranges (same packing as populateTileLayerItemsFromPatternTable).
--- Returns startLogical, endLogical for the segment containing logicalIndex, or nil if none / invalid.
function M.patternLogicalSpanContainingIndex(patternTable, logicalIndex)
  if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" then
    return nil, nil
  end
  local idx = math.floor(tonumber(logicalIndex) or -1)
  if idx < 0 or idx > 255 then
    return nil, nil
  end
  local cursor = 0
  for _, range in ipairs(patternTable.ranges) do
    local len, cerr = M.patternRangeLogicalLength(range)
    if not len then
      return nil, nil
    end
    local startLogical = cursor
    local endLogical = cursor + len - 1
    if idx >= startLogical and idx <= endLogical then
      return startLogical, endLogical
    end
    cursor = cursor + len
    if cursor > 256 then
      break
    end
  end
  return nil, nil
end

function M.patternTableLogicalSize(patternTable)
  if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" then
    return 0, "patternTable.ranges is missing"
  end
  local total = 0
  for i, range in ipairs(patternTable.ranges) do
    local len, cerr = M.patternRangeLogicalLength(range)
    if not len then
      return total, string.format("patternTable.ranges[%d]: %s", i, tostring(cerr or "invalid"))
    end
    total = total + len
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
    if M.patternRangeUsesExplicitTiles(range) then
      local db = range.bank
      for j, t in ipairs(range.tiles) do
        local bank, page, src, terr = explicitTileBankPageByte(t, j, db)
        if terr then
          return nil, string.format("patternTable.ranges[%d] %s", i, terr)
        end
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
    elseif PatternTableMapping.isGlobalChrFromToRange(range) then
      local a, b = PatternTableMapping.globalChrFromToBounds(range)
      if a == nil or b == nil then
        return nil, string.format("patternTable.ranges[%d] has invalid global from/to", i)
      end
      local bank = math.max(1, math.floor(tonumber(range.bank) or -1))
      if bank < 1 then
        return nil, string.format("patternTable.ranges[%d] is missing bank", i)
      end
      for ti = a, b do
        if logicalIndex > 255 then
          return nil, "patternTable ranges exceed 256 tiles"
        end
        local page = (ti >= 256) and 2 or 1
        local src = ti % 256
        map[logicalIndex] = {
          bank = bank,
          page = page,
          tileByte = src,
          tileIndex = ti,
        }
        logicalIndex = logicalIndex + 1
      end
    else
      return nil, string.format("patternTable.ranges[%d] must use tiles or global { bank, from, to }", i)
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
      if M.patternRangeUsesExplicitTiles(range) then
        parts[#parts + 1] = "tiles"
        local db = range.bank
        for j, t in ipairs(range.tiles) do
          local b, p, bb, terr = explicitTileBankPageByte(t, j, db)
          if terr then
            parts[#parts + 1] = ":?"
          else
            parts[#parts + 1] = string.format(":%d:%d:%d", b, p, bb)
          end
        end
      elseif PatternTableMapping.isGlobalChrFromToRange(range) then
        local a, b = PatternTableMapping.globalChrFromToBounds(range)
        parts[#parts + 1] = string.format(
          "g:%d:%s:%s",
          math.floor(tonumber(range.bank) or -1),
          tostring(a),
          tostring(b)
        )
      else
        parts[#parts + 1] = "invalid_range"
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

----------------------------------------------------------------------
-- CHR / ROM bank multi-drag → pattern_table.ranges (append order)
----------------------------------------------------------------------

local function materializeChrDragItem(win, item, layerIdx)
  if item == nil then
    return nil
  end
  if win and win.materializeTileHandle then
    local resolved = win:materializeTileHandle(item, layerIdx)
    if resolved ~= nil then
      return resolved
    end
  end
  return item
end

local function chrItemBankPageByte(srcWin, srcLayer, item)
  item = materializeChrDragItem(srcWin, item, srcLayer)
  if type(item) ~= "table" then
    return nil, nil, nil
  end
  local bank = tonumber(item._bankIndex) or tonumber(srcWin and srcWin.currentBank)
  if bank == nil or bank < 1 then
    return nil, nil, nil
  end
  bank = math.floor(bank)

  local ti = tonumber(item.index)
  if type(ti) ~= "number" and item.topRef then
    ti = tonumber(item.topRef.index)
  end
  if type(ti) ~= "number" then
    return nil, nil, nil
  end
  ti = math.floor(ti)
  if ti < 0 then
    return nil, nil, nil
  end
  if ti >= 512 then
    ti = ti % 512
  end
  local page = (ti >= 256) and 2 or 1
  local byte = ti % 256
  return bank, page, byte
end

--- CHR bank/ROM viewer "oddEven" orderMode matches pattern-table layers using 8x16 CHR ordering.
function M.chrUses8x16TileLayout(win)
  return win and win.orderMode == "oddEven"
end

--- Pattern table tile layers use layer.mode `"8x16"`/`"oddEven"` vs `"8x8"` (and nil → 8x8).
function M.patternTableUses8x16TileLayout(layer)
  local m = layer and layer.mode
  return m == "8x16" or m == "oddEven"
end

--- Drop sources must mirror destination: both 8x8-ish or both 8x16-pair ordering.
function M.chrLayoutMatchesPatternTableLayer(win, layer)
  return M.chrUses8x16TileLayout(win) == M.patternTableUses8x16TileLayout(layer)
end

--- Canonical tile-layer `layer.mode` to align pattern-table ordering with CHR `oddEven` vs normal grids.
function M.patternTableTileLayerModeAlignedToChr(srcWin)
  return M.chrUses8x16TileLayout(srcWin) and "8x16" or "8x8"
end

--- Sets `layer.mode` when CHR / pattern-table tile ordering disagree. Returns whether it changed `mode`.
function M.syncPatternTableTileLayerModeToChr(srcWin, layer)
  if type(layer) ~= "table" then
    return false
  end
  if M.chrLayoutMatchesPatternTableLayer(srcWin, layer) then
    return false
  end
  layer.mode = M.patternTableTileLayerModeAlignedToChr(srcWin)
  return true
end

--- Read-only overlay for CHR→pattern-table drop preview parity/grid without mutating the real layer yet.
function M.patternTableLayerEffectiveForChrDropPreview(layer, srcWin)
  if not (layer and srcWin) then
    return layer
  end
  if M.chrLayoutMatchesPatternTableLayer(srcWin, layer) then
    return layer
  end
  local mode = M.patternTableTileLayerModeAlignedToChr(srcWin)
  return setmetatable({ mode = mode }, { __index = layer })
end

--- 8×16 CHR layout consumes logical CHR indices in multiples of two (128 visual stacks).
function M.patternTableAppendChrParityOk(layer, currentTotalBytes, addBytes)
  if not M.patternTableUses8x16TileLayout(layer) then
    return true, nil
  end
  if type(currentTotalBytes) ~= "number" or type(addBytes) ~= "number" then
    return false, "Cannot verify 8×16 pattern table tiling"
  end
  if currentTotalBytes % 2 ~= 0 then
    return false,
      "Pattern table (8×16 CHR layout) has an uneven CHR tile count — only complete pairs are allowed"
  end
  if addBytes % 2 ~= 0 then
    return false,
      "8×16 CHR layout requires adding whole pairs (one visual 8×16 item = two CHR indices)"
  end
  return true, nil
end

--- Map row-major logical slot (next append index) to grid cell for ghost preview.
function M.patternTableGridCellForLogicalIndex(win, layer, logicalIndex)
  if not (win and layer) then
    return nil, nil
  end
  local cols = math.max(1, math.floor(tonumber(win.cols) or 16))
  local rows = math.max(1, math.floor(tonumber(win.rows) or 16))
  local layoutMode = layer.mode or "8x8"
  local li = math.floor(tonumber(logicalIndex) or 0)
  if li < 0 then
    li = 0
  end
  local maxPos = math.min(rows * cols - 1, 255)
  for pos = 0, maxPos do
    if BankViewController.chrOrderingIndexForGridPos(layoutMode, pos) == li then
      return pos % cols, math.floor(pos / cols)
    end
  end
  return nil, nil
end

--- Turn a CHR grouped drag payload into pattern-table range rows, in append order.
--- One logical range per drop: an explicit `tiles` list preserving selection order (LRTB for 8×8;
--- 8×16 path expands each column pair to two rows). Tiles may omit ROM-contiguity or share a bank.
--- @return ranges, addedCount, err, orderedItemRefs -- orderedItemRefs: { { item = ... }, ... } for drag preview
function M.planPatternRangesFromChrTileGroup(srcWin, srcLayer, tileGroup)
  srcLayer = tonumber(srcLayer) or 1

  local cells = {}
  local chrUses16 = M.chrUses8x16TileLayout(srcWin)

  if chrUses16 then
    local spr = tileGroup.spriteEntries
    if not (type(spr) == "table" and #spr > 0) then
      return nil, 0, "CHR 8x16 layout drag is missing paired tile selections"
    end
    local sorted = {}
    for _, e in ipairs(spr) do
      sorted[#sorted + 1] = e
    end
    table.sort(sorted, function(a, b)
      local ra = tonumber(a.srcRow) or 0
      local rb = tonumber(b.srcRow) or 0
      if ra == rb then
        return (tonumber(a.srcCol) or 0) < (tonumber(b.srcCol) or 0)
      end
      return ra < rb
    end)
    for _, se in ipairs(sorted) do
      local sc = se.srcCol
      local sr = se.srcRow
      if type(sc) ~= "number" or type(sr) ~= "number" then
        return nil, 0, "CHR drag group entry is missing grid coordinates"
      end
      local bankT, pageT, byteT = chrItemBankPageByte(srcWin, srcLayer, se.item)
      if not bankT then
        return nil, 0, "Could not resolve CHR bank or tile index"
      end
      cells[#cells + 1] = {
        srcRow = sr,
        srcCol = sc,
        bank = bankT,
        page = pageT,
        byte = byteT,
        item = se.item,
      }
      local bot = se.bottomItem
      if type(bot) ~= "table" then
        return nil, 0, "CHR 8x16 layout requires both tiles in each vertical pair"
      end
      local bankB, pageB, byteB = chrItemBankPageByte(srcWin, srcLayer, bot)
      if not bankB then
        return nil, 0, "Could not resolve CHR bank or tile index"
      end
      cells[#cells + 1] = {
        srcRow = sr + 1,
        srcCol = sc,
        bank = bankB,
        page = pageB,
        byte = byteB,
        item = bot,
      }
    end
  else
    if not (tileGroup and type(tileGroup.entries) == "table" and #tileGroup.entries > 0) then
      return nil, 0, "No CHR tiles in drag group"
    end
    for _, entry in ipairs(tileGroup.entries) do
      local sc = entry.srcCol
      local sr = entry.srcRow
      if type(sc) ~= "number" or type(sr) ~= "number" then
        return nil, 0, "CHR drag group entry is missing grid coordinates"
      end
      local bank, page, byte = chrItemBankPageByte(srcWin, srcLayer, entry.item)
      if not bank then
        return nil, 0, "Could not resolve CHR bank or tile index"
      end
      cells[#cells + 1] = {
        srcRow = sr,
        srcCol = sc,
        bank = bank,
        page = page,
        byte = byte,
        item = entry.item,
      }
    end
  end

  if #cells == 0 then
    return nil, 0, "No CHR tiles in drag group"
  end

  if not chrUses16 then
    table.sort(cells, function(a, b)
      if a.srcRow == b.srcRow then
        return a.srcCol < b.srcCol
      end
      return a.srcRow < b.srcRow
    end)
  end

  local orderedItemRefs = {}
  for _, c in ipairs(cells) do
    orderedItemRefs[#orderedItemRefs + 1] = { item = c.item }
  end

  local tiles = {}
  for _, c in ipairs(cells) do
    if c.byte < 0 or c.byte > 255 then
      return nil, 0, "From/To must be between 0 and 255"
    end
    if c.page ~= 1 and c.page ~= 2 then
      return nil, 0, "Page must be 1 or 2"
    end
    tiles[#tiles + 1] = {
      bank = c.bank,
      page = c.page,
      byte = c.byte,
      tileIndex = (c.page == 2) and (256 + c.byte) or c.byte,
    }
  end

  local total = #tiles
  local ranges = { { tiles = tiles } }
  return ranges, total, nil, orderedItemRefs
end

local function explicitTileGlobalChrIndex(t, idxForErr, defaultBank)
  local bank, page, byte, terr = explicitTileBankPageByte(t, idxForErr, defaultBank)
  if terr then
    return nil, nil, terr
  end
  local ti = (page == 2) and (256 + byte) or byte
  return bank, ti, nil
end

--- Merge consecutive same-bank CHR indices in one explicit `tiles` row into `{ bank, from, to }` rows.
local function compactExplicitTilesRangeToFromTo(range)
  local out = {}
  local defaultBank = range.bank
  local runBank, runFrom, runTo = nil, nil, nil

  local function flushRun()
    if runBank ~= nil and runFrom ~= nil and runTo ~= nil then
      out[#out + 1] = { bank = runBank, from = runFrom, to = runTo }
    end
    runBank, runFrom, runTo = nil, nil, nil
  end

  for i, t in ipairs(range.tiles) do
    local bank, ti, terr = explicitTileGlobalChrIndex(t, i, defaultBank)
    if terr then
      return nil, terr
    end
    if runBank == nil then
      runBank, runFrom, runTo = bank, ti, ti
    elseif bank == runBank and ti == runTo + 1 then
      runTo = ti
    else
      flushRun()
      runBank, runFrom, runTo = bank, ti, ti
    end
  end
  flushRun()
  return out, nil
end

--- Project save format: only `{ bank, from, to }` range rows (global CHR 0..511), no per-tile `tiles` lists.
function M.compactPatternTableForPersistence(patternTable)
  if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" then
    return { ranges = {} }
  end

  local outRanges = {}
  for _, range in ipairs(patternTable.ranges) do
    if M.patternRangeUsesExplicitTiles(range) then
      local compacted, cerr = compactExplicitTilesRangeToFromTo(range)
      if cerr then
        return TableUtils.deepcopy(patternTable)
      end
      for _, cr in ipairs(compacted or {}) do
        outRanges[#outRanges + 1] = cr
      end
    elseif PatternTableMapping.isGlobalChrFromToRange(range) then
      local fromChr, toChr = PatternTableMapping.globalChrFromToBounds(range)
      local bank = math.max(1, math.floor(tonumber(range.bank) or 1))
      outRanges[#outRanges + 1] = {
        bank = bank,
        from = fromChr,
        to = toChr,
      }
    else
      outRanges[#outRanges + 1] = TableUtils.deepcopy(range)
    end
  end

  return { ranges = outRanges }
end

return M
