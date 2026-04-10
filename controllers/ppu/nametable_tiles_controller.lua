-- nametable_tiles_controller.lua
-- Centralized handling of nametable / tilemap data for PPU frame windows.
-- Responsibilities:
--   * Decode compressed nametable bytes from ROM (using NametableUtils)
--   * Populate window grid cells with tile refs from tilesPool
--   * Track a compact diff map of tile swaps vs original bytes
--   * Re-encode current nametable/attribute bytes back into ROM
--
-- This is intentionally window-agnostic: it operates on any Window that:
--   * Has .cols / .rows fields (tile grid dimensions)
--   * Has :set(col,row,tileRef,layerIndex) and :clear(col,row,layerIndex)
--   * Has a layers[] array containing the layer table we pass in
--
-- It mirrors the behaviour that used to live inside ppu_frame_window.lua,
-- but is factored out so other code can call it without knowing details.

local chr            = require("chr")
local NametableUtils = require("utils.nametable_utils")
local TableUtils     = require("utils.table_utils")
local DebugController   = require("controllers.dev.debug_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local PatternTableMapping = require("utils.pattern_table_mapping")

local M = {}

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

function M.updateOverflowToastForWindow(win, layer, compressedSize, originalSize)
  if type(win) ~= "table" then
    return false
  end

  if not (layer and layer.noOverflowSupported == true) then
    win._nametableOverflowWarned = false
    return false
  end

  if type(compressedSize) ~= "number" or type(originalSize) ~= "number" then
    return false
  end
  if originalSize <= 0 then
    return false
  end

  local overBudget = compressedSize > originalSize
  local warned = (win._nametableOverflowWarned == true)

  if overBudget then
    if warned then
      return false
    end
    local ctx = rawget(_G, "ctx")
    if ctx and ctx.showToast then
      ctx.showToast(
        "warning",
        string.format(
          "Nametable data (%d bytes) larger than original (%d bytes)",
          compressedSize,
          originalSize
        )
      )
    end
    win._nametableOverflowWarned = true
    return true
  end

  if warned then
    local ctx = rawget(_G, "ctx")
    if ctx and ctx.showToast then
      ctx.showToast(
        "info",
        string.format("Nametable size is valid again (%d bytes)", compressedSize)
      )
    end
    win._nametableOverflowWarned = false
    return true
  end

  win._nametableOverflowWarned = false
  return false
end

local function logPerf(label, startedAt, extra)
  local elapsed = nowSeconds() - (startedAt or nowSeconds())
  if extra and extra ~= "" then
    DebugController.log("info", "LOAD_PERF", "%s duration=%.3fs %s", tostring(label), elapsed, tostring(extra))
  else
    DebugController.log("info", "LOAD_PERF", "%s duration=%.3fs", tostring(label), elapsed)
  end
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Linear index helpers (1-based indexes into nametableBytes array).
local function lin(cols, col, row)
  return row * cols + col + 1  -- (row, col) → 1..N
end

local function ensurePatternTableBanks(patternTable, ensureTiles)
  if type(ensureTiles) ~= "function" then
    return
  end
  local ensured = {}
  local function ensureOne(bank)
    local b = math.floor(tonumber(bank) or 1)
    if b < 1 then b = 1 end
    if ensured[b] then return end
    ensured[b] = true
    ensureTiles(b)
  end

  if type(patternTable) == "table" and type(patternTable.ranges) == "table" then
    for _, r in ipairs(patternTable.ranges) do
      if type(r) == "table" then
        ensureOne(r.bank)
      end
    end
  end
end

local function copyBytes(src)
  local out = {}
  if type(src) ~= "table" then
    return out
  end
  for i = 1, #src do
    out[i] = src[i]
  end
  return out
end

local function reportDecodeCoverageError(message, opts)
  if opts and opts.reportErrors == false then
    return
  end
  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app or nil
  if app and app.setStatus then
    app:setStatus(message)
  end
  if app and app.showToast then
    app:showToast("error", message)
  end
end

local function bytesEqual(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

local function hasWindowNametableChanges(win)
  local nt = win and win.nametableBytes or nil
  local ntOrig = win and win._originalNametableBytes or nil
  local at = win and win.nametableAttrBytes or nil
  local atOrig = win and win._originalNametableAttrBytes or nil

  if type(nt) ~= "table" or type(ntOrig) ~= "table" then
    return true
  end

  if not bytesEqual(nt, ntOrig) then
    return true
  end

  if type(at) ~= "table" or type(atOrig) ~= "table" then
    return true
  end

  return not bytesEqual(at, atOrig)
end

-- RLE encode/decode helpers for tileSwaps (row-major, default 32x30 grid).
local function encodeTileSwapsRLE(swaps, cols, rows)
  if not swaps or #swaps == 0 then return nil end
  cols = cols or 32
  rows = rows or 30
  local total = cols * rows
  local cells = {}
  for i = 1, total do cells[i] = -1 end

  for _, s in ipairs(swaps) do
    local c, r, v = s.col, s.row, s.val
    if c and r and v ~= nil then
      local idx = r * cols + c + 1
      if idx >= 1 and idx <= total then
        cells[idx] = v
      end
    end
  end

  local parts = {}
  local cur = cells[1]
  local count = 1
  for i = 2, total do
    local v = cells[i]
    if v == cur then
      count = count + 1
    else
      parts[#parts + 1] = string.format("%d:%d", cur, count)
      cur = v
      count = 1
    end
  end
  parts[#parts + 1] = string.format("%d:%d", cur, count)

  local body = table.concat(parts, ";")
  local header = string.format("%dx%d|", cols, rows)
  local full = header .. body

  -- Split into multiple strings if very long to keep lines manageable (~128 chars each)
  local maxChunk = 128
  if #full <= maxChunk then
    return full
  end

  local chunks = {}
  local idx = 1
  local firstBodyLen = math.max(0, maxChunk - #header)
  if firstBodyLen > 0 then
    chunks[#chunks + 1] = header .. body:sub(1, firstBodyLen)
    idx = firstBodyLen + 1
  else
    chunks[#chunks + 1] = header
  end

  while idx <= #body do
    local chunkBody = body:sub(idx, idx + maxChunk - 1)
    chunks[#chunks + 1] = chunkBody
    idx = idx + #chunkBody
  end

  return chunks
end

local function decodeTileSwapsRLE(rle)
  if not rle then return nil end
  local full
  if type(rle) == "table" then
    -- Concatenate array-of-strings form; ignore non-string entries
    local parts = {}
    for i, v in ipairs(rle) do
      if type(v) == "string" then parts[#parts + 1] = v end
    end
    full = table.concat(parts, "")
  elseif type(rle) == "string" then
    full = rle
  else
    return nil
  end

  if full == "" then return nil end

  local cols, rows, body = full:match("^(%d+)x(%d+)%|(.*)$")
  cols = tonumber(cols) or 32
  rows = tonumber(rows) or 30
  body = body or ""
  local total = cols * rows
  local cells = {}
  for token in body:gmatch("([^;]+)") do
    local v, len = token:match("^(-?%d+):(%d+)$")
    v, len = tonumber(v), tonumber(len)
    if v and len then
      for _ = 1, len do
        if #cells < total then
          cells[#cells + 1] = v
        end
      end
    end
  end
  while #cells < total do cells[#cells + 1] = -1 end

  local swaps = {}
  for i = 1, total do
    local v = cells[i]
    if v and v >= 0 then
      local z = i - 1
      swaps[#swaps + 1] = { col = z % cols, row = math.floor(z / cols), val = v }
    end
  end

  if #swaps == 0 then return nil end
  return swaps
end

function M.countSerializedTileSwaps(tileSwaps)
  if tileSwaps == nil then
    return 0
  end

  if type(tileSwaps) == "table" and tileSwaps.rle then
    tileSwaps = tileSwaps.rle
  end

  local decoded
  if type(tileSwaps) == "string" or type(tileSwaps) == "table" then
    decoded = decodeTileSwapsRLE(tileSwaps)
  end

  if type(decoded) == "table" then
    return #decoded
  end
  return 0
end

-- Find index of a given layer table inside win.layers.
local function findLayerIndex(win, layer)
  if not (win and win.layers and layer) then return nil end
  for idx, L in ipairs(win.layers) do
    if L == layer then return idx end
  end
  return nil
end

-- Ensure internal structures exist on the window to track diffs.
local function ensureDiffState(win)
  win._originalNametableBytes = win._originalNametableBytes or {}
  win._tileSwaps              = win._tileSwaps or {}
end

-- Record that nametableBytes[idx] differs from original, or clear if back to original.
local function recordSwap(win, idx)
  if not win._originalNametableBytes then return end
  local orig = win._originalNametableBytes[idx]
  local cur  = win.nametableBytes[idx]
  if orig == nil then return end

  if cur == orig then
    -- Value matches original → remove from diff map.
    if win._tileSwaps then
      win._tileSwaps[idx] = nil
    end
  else
    win._tileSwaps = win._tileSwaps or {}
    win._tileSwaps[idx] = cur
  end
end

-- Expand compact diff map into a pretty list of {col,row,val} swaps.
local function buildTileSwapsList(win)
  local swaps = {}
  local diff  = win._tileSwaps or {}
  local cols  = win.cols or 32

  for idx, val in pairs(diff) do
    local z   = idx - 1
    local col = z % cols
    local row = math.floor(z / cols)
    swaps[#swaps + 1] = { col = col, row = row, val = val }
  end

  if #swaps == 0 then
    return nil
  end

  table.sort(swaps, function(a, b)
    if a.row == b.row then return a.col < b.col end
    return a.row < b.row
  end)

  return swaps
end

----------------------------------------------------------------------
-- Hydration / decode
----------------------------------------------------------------------

--- Decode a compressed nametable+attribute stream from ROM and attach it
--  to a window + layer, populating:
--    win.nametableBytes        (960 entries)
--    win.nametableAttrBytes    (64 entries)
--    win._originalNametableBytes (copy of baseline bytes)
--    win._tileSwaps            (empty diff map)
--    win.nametableStart
--  and filling the window grid with tile refs from tilesPool.
--
--  win   : the PPU frame window (or compatible)
--  layer : the tile/nametable layer table on this window
--  opts  :
--    romRaw              : ROM string
--    tilesPool           : tilesPool[bankIndex][tileIndex] → Tile
--    ensureTiles         : function(bankIndex) to lazily build tiles
--    nametableStartAddr  : 0-based ROM address of compressed stream start
--    nametableEndAddr    : 0-based ROM address of compressed stream end (inclusive)
--    tileSwaps           : optional list { {col,row,val}, ... } to apply after load
function M.hydrateWindowNametable(win, layer, opts)
  if not (win and layer and opts) then
    return nil, "missing_args"
  end
  local romRaw      = opts.romRaw or ""
  local tilesPool   = opts.tilesPool
  local ensureTiles = opts.ensureTiles
  local startAddr   = opts.nametableStartAddr or layer.nametableStartAddr or win.nametableStart
  local endAddr     = opts.nametableEndAddr   or layer.nametableEndAddr
  local tileSwaps   = opts.tileSwaps or layer.tileSwaps
  local noOverflowSupported = (opts.noOverflowSupported == true) or (layer.noOverflowSupported == true)

  if type(startAddr) ~= "number" or type(endAddr) ~= "number" then
    return nil, "missing_nametable_range"
  end
  if type(romRaw) ~= "string" or #romRaw == 0 then
    return nil, "empty_rom"
  end

  local readStartedAt = nowSeconds()
  local compressed, err = chr.readBytesFromRange(romRaw, startAddr, endAddr)
  if not compressed then
    return nil, "[NametableTilesController] readBytesFromRange failed: " .. tostring(err)
  end
  win._originalCompressedBytes = copyBytes(compressed)
  logPerf("ntm.read_compressed", readStartedAt, string.format("title=%s", tostring(win.title or "")))

  -- Get codec from opts, layer, or default to "konami"
  local codec = opts.codec or layer.codec or "konami"
  
  local decodeStartedAt = nowSeconds()
  local ntBytes, attrBytes, decodeMeta = NametableUtils.decode_compressed_nametable(compressed, false, codec)
  if not ntBytes or not attrBytes then
    return nil, "[NametableTilesController] decode_compressed_nametable failed"
  end
  local totalPageWrites = decodeMeta and decodeMeta.totalPageWrites or nil
  if type(totalPageWrites) == "number" and totalPageWrites > 1024 then
    local message = string.format("PPU frame range expands to %d bytes, which exceeds 1024", totalPageWrites)
    reportDecodeCoverageError(message, opts)
    return nil, message
  end
  logPerf("ntm.decode_compressed", decodeStartedAt, string.format("title=%s", tostring(win.title or "")))

  -- Copy & clamp bytes to 0..255
  local byteCopyStartedAt = nowSeconds()
  win.nametableBytes = {}
  for i = 1, #ntBytes do
    local b = tonumber(ntBytes[i]) or 0
    if b < 0 then b = 0 elseif b > 255 then b = 255 end
    win.nametableBytes[i] = b
  end

  win.nametableAttrBytes = {}
  -- NES standard: attribute table is always exactly 64 bytes for standard nametables
  -- Only copy the first 64 bytes from ROM (ignore any extra bytes)
  local attrSizeToCopy = math.min(64, #attrBytes)
  for i = 1, attrSizeToCopy do
    local b = tonumber(attrBytes[i]) or 0
    if b < 0 then b = 0 elseif b > 255 then b = 255 end
    win.nametableAttrBytes[i] = b
  end
  -- Pad to 64 bytes if ROM had fewer than 64 bytes
  for i = attrSizeToCopy + 1, 64 do
    win.nametableAttrBytes[i] = 0x00
  end
  if #attrBytes ~= 64 then
    DebugController.log("info", "NTM", "ROM had %d attribute bytes, normalized to 64 bytes", #attrBytes)
  end
  win._originalNametableAttrBytes = copyBytes(win.nametableAttrBytes)
  logPerf("ntm.copy_bytes", byteCopyStartedAt, string.format("title=%s", tostring(win.title or "")))

  -- Debug: Count unique attribute bytes loaded from ROM
  local uniqueAttrBytes = {}
  for i = 1, #win.nametableAttrBytes do
    local b = win.nametableAttrBytes[i]
    uniqueAttrBytes[b] = true
  end
  local uniqueCount = 0
  local uniqueList = {}
  for byteVal, _ in pairs(uniqueAttrBytes) do
    uniqueCount = uniqueCount + 1
    table.insert(uniqueList, byteVal)
  end
  table.sort(uniqueList)
  local hexList = {}
  for _, byteVal in ipairs(uniqueList) do
    table.insert(hexList, string.format("%02x", byteVal))
  end
  DebugController.log("info", "NTM", "Loaded %d attribute bytes from ROM, %d unique values: %s", 
    #win.nametableAttrBytes, uniqueCount, table.concat(hexList, ", "))

  -- Baseline copy for diff tracking
  win._originalNametableBytes = {}
  for i = 1, #win.nametableBytes do
    win._originalNametableBytes[i] = win.nametableBytes[i]
  end
  win._tileSwaps = {}

  win.nametableStart = startAddr
  if endAddr >= startAddr then
    win.originalTotalByteNumber = endAddr - startAddr + 1
  else
    win.originalTotalByteNumber = startAddr - endAddr + 1
  end
  win._nametableOriginalSize = win.originalTotalByteNumber
  win._nametableCompressedSize = win.originalTotalByteNumber

  -- Ensure grid dimensions are sane
  win.cols = win.cols or 32
  win.rows = win.rows or math.max(1, math.floor((#win.nametableBytes + win.cols - 1) / win.cols))

  -- Update layer metadata
  layer.kind  = layer.kind or "tile"
  layer.mode  = layer.mode or "8x8"
  layer.codec = layer.codec or codec or "konami"
  layer.nametableStartAddr = startAddr
  layer.nametableEndAddr   = endAddr
  layer.noOverflowSupported = noOverflowSupported

  -- Fill visual grid from nametableBytes
  local li = findLayerIndex(win, layer) or 1

  if type(opts.patternTable) == "table" then
    layer.patternTable = TableUtils.deepcopy(opts.patternTable)
  end
  if type(layer.patternTable) ~= "table" then
    layer.patternTable = {}
  end
  local mapOk, mapErr = PatternTableMapping.validate(layer.patternTable)
  if not mapOk then
    local message = string.format("Invalid patternTable mapping for '%s'", win.title or "")
    reportDecodeCoverageError(message, opts)
    return nil, message
  end

  ensurePatternTableBanks(layer.patternTable, ensureTiles)
  if tilesPool then
    local fillGridStartedAt = nowSeconds()
    for i = 1, #win.nametableBytes do
      local z   = i - 1
      local col = z % win.cols
      local row = math.floor(z / win.cols)
      local byteVal = win.nametableBytes[i]
      if win.syncNametableVisualCell then
        win:syncNametableVisualCell(col, row, byteVal, tilesPool, li)
      else
        local tileRef = PatternTableMapping.resolveTile(tilesPool, layer, byteVal)
        if tileRef then
          win:set(col, row, tileRef, li)
        else
          win:clear(col, row, li)
        end
      end
    end
    logPerf("ntm.fill_grid", fillGridStartedAt, string.format("title=%s", tostring(win.title or "")))
  end

  -- Apply any pre-existing tileSwaps from layout/project
  if tileSwaps then
    local swapsStartedAt = nowSeconds()
    local rawTileSwaps = tileSwaps
    if type(tileSwaps) == "string" then
      tileSwaps = decodeTileSwapsRLE(tileSwaps)
    elseif type(tileSwaps) == "table" and tileSwaps.rle then
      tileSwaps = decodeTileSwapsRLE(tileSwaps.rle)
    elseif type(tileSwaps) == "table" then
      -- Keep native { {col,row,val}, ... } swap lists; only decode when this is
      -- the chunked-RLE table representation.
      tileSwaps = decodeTileSwapsRLE(tileSwaps) or rawTileSwaps
    end
    if tileSwaps and #tileSwaps > 0 then
      M.applyTileSwaps(win, layer, tileSwaps, tilesPool)
    end
    logPerf("ntm.apply_tile_swaps", swapsStartedAt, string.format("title=%s count=%d", tostring(win.title or ""), tileSwaps and #tileSwaps or 0))
  end

  -- Load user-defined attribute bytes from project if they exist
  -- These override the attribute bytes loaded from ROM
  local userDefinedAttrs = (opts and opts.userDefinedAttrs) or nil
  if userDefinedAttrs and type(userDefinedAttrs) == "string" and #userDefinedAttrs >= 128 then
    -- Parse hex string: "0AF8B7..." -> array of bytes
    local userAttrBytes = {}
    for i = 1, 64 do
      local hexPair = userDefinedAttrs:sub((i - 1) * 2 + 1, i * 2)
      local byteVal = tonumber(hexPair, 16)
      if byteVal then
        userAttrBytes[i] = byteVal
      else
        userAttrBytes[i] = 0x00
      end
    end
    -- Overwrite all 64 attribute bytes with user-defined values
    -- Truncate array to exactly 64 bytes (remove any extra bytes from ROM)
    win.nametableAttrBytes = {}
    for i = 1, 64 do
      win.nametableAttrBytes[i] = userAttrBytes[i] or 0x00
    end
    DebugController.log("info", "NTM", "Loaded userDefinedAttrs: %d bytes overwritten (array set to exactly 64 bytes)", 64)
  else
    -- Even if no userDefinedAttrs, ensure array is exactly 64 bytes
    if not win.nametableAttrBytes then
      win.nametableAttrBytes = {}
    end
    
    if #win.nametableAttrBytes > 64 then
      -- Truncate if ROM had more than 64 bytes
      local originalSize = #win.nametableAttrBytes
      local trimmed = {}
      for i = 1, 64 do
        trimmed[i] = win.nametableAttrBytes[i] or 0x00
      end
      win.nametableAttrBytes = trimmed
      DebugController.log("info", "NTM", "Truncated nametableAttrBytes from %d to 64 bytes (ROM had extra bytes)", originalSize)
    elseif #win.nametableAttrBytes < 64 then
      -- Pad with zeros if ROM had fewer than 64 bytes
      local originalSize = #win.nametableAttrBytes
      for i = #win.nametableAttrBytes + 1, 64 do
        win.nametableAttrBytes[i] = 0x00
      end
      DebugController.log("info", "NTM", "Padded nametableAttrBytes from %d to 64 bytes (ROM had fewer bytes)", originalSize)
    end
  end

  -- Extract palette numbers from attribute bytes (either from ROM or user-defined)
  local paletteExtractStartedAt = nowSeconds()
  M.extractPaletteNumbersFromAttributes(win, layer, win.cols, win.rows)
  if win.invalidateNametableLayerCanvas then
    win:invalidateNametableLayerCanvas(li)
  end
  logPerf("ntm.extract_palette_numbers", paletteExtractStartedAt, string.format("title=%s", tostring(win.title or "")))

  return true
end

----------------------------------------------------------------------
-- Tile swaps / edits
----------------------------------------------------------------------

--- Apply a list of swaps { {col,row,val}, ... } on top of the current
--  nametableBytes and grid, updating the diff map so that a future
--  snapshot can serialize only the changes.
function M.applyTileSwaps(win, layer, swaps, tilesPool, opts)
  if not (win and layer and swaps) then return end
  opts = opts or {}
  if type(swaps) == "string" then
    swaps = decodeTileSwapsRLE(swaps) or {}
  elseif type(swaps) == "table" and swaps.rle then
    swaps = decodeTileSwapsRLE(swaps.rle) or {}
  elseif type(swaps) == "table" then
    swaps = decodeTileSwapsRLE(swaps) or swaps
  end
  if not swaps or #swaps == 0 then return end

  local li = findLayerIndex(win, layer) or 1
  local cols = win.cols or 32
  ensureDiffState(win)

  for _, s in ipairs(swaps) do
    local col, row, val = s.col, s.row, s.val
    if col ~= nil and row ~= nil and val ~= nil then
      local idx = lin(cols, col, row)
      win.nametableBytes[idx] = val

      -- Update visual tile if we have a tilesPool
      if tilesPool then
        if win.syncNametableVisualCell then
          win:syncNametableVisualCell(col, row, val, tilesPool, li)
        else
          local tileRef = PatternTableMapping.resolveTile(tilesPool, layer, val)
          if tileRef then
            win:clear(col, row, li)
            win:set(col, row, tileRef, li)
          else
            win:clear(col, row, li)
          end
        end
      end

      -- Keep diff map consistent with original baseline
      recordSwap(win, idx)
      if win.invalidateNametableLayerCanvas then
        win:invalidateNametableLayerCanvas(li, col, row)
      end
    end
  end
end

----------------------------------------------------------------------
-- Snapshot / serialization helpers
----------------------------------------------------------------------

--- Build a project-ready table for a nametable layer.
--  We intentionally do NOT serialize the full 960-byte nametable;
--  instead we store:
--    * nametableStartAddr / nametableEndAddr
--    * tileSwaps (list {col,row,val} for cells that differ from ROM)
function M.snapshotNametableLayer(win, layer)
  if not (win and layer and layer.kind == "tile" and layer.nametableStartAddr) then
    return nil
  end

  local out = {
    name               = layer.name,
    kind               = "tile",
    opacity            = (layer.opacity ~= nil) and layer.opacity or 1.0,
    mode               = layer.mode or "8x8",
    patternTable       = TableUtils.deepcopy(layer.patternTable),
    nametableStartAddr = layer.nametableStartAddr,
    nametableEndAddr   = layer.nametableEndAddr,
    items              = {},  -- always empty: base tiles come from ROM
  }
  if layer.noOverflowSupported ~= nil then
    out.noOverflowSupported = (layer.noOverflowSupported == true)
  end
  out.patternTable = out.patternTable or {}

  -- Swaps as pretty list { {col,row,val}, ... }
  local swaps = buildTileSwapsList(win)
  if swaps then
    local encoded = encodeTileSwapsRLE(swaps, win.cols, win.rows)
    out.tileSwaps = encoded or swaps
  end

  -- User-defined attribute bytes as hex string (64 bytes = 128 hex characters)
  -- Convert attribute bytes array to hex string
  if win.nametableAttrBytes and #win.nametableAttrBytes >= 64 then
    local hexParts = {}
    for i = 1, 64 do
      local byteVal = win.nametableAttrBytes[i] or 0x00
      hexParts[i] = string.format("%02x", byteVal)
    end
    out.userDefinedAttrs = table.concat(hexParts, "")
    DebugController.log("info", "NTM", "snapshotNametableLayer: saving userDefinedAttrs (%d bytes as hex)", 64)
  end

  return out
end

----------------------------------------------------------------------
-- ROM write-back
----------------------------------------------------------------------

--- Encode current nametableBytes + nametableAttrBytes back into a compressed
--  stream and overwrite the original range in romRaw.
--
--  win    : window holding nametableBytes/AttrBytes
--  layer  : nametable layer (used for metadata; may be nil if fields are on win)
--  romRaw : ROM string
--
--  Returns: newRomRaw (string) on success, or nil, errorMessage on failure.
function M.writeBackToROM(win, layer, romRaw)
  if type(romRaw) ~= "string" then
    return nil, "romRaw must be a string"
  end

  local startAddr = (layer and layer.nametableStartAddr) or win.nametableStart
  if type(startAddr) ~= "number" then
    return nil, "missing_nametable_start"
  end

  local endAddr = (layer and layer.nametableEndAddr) or nil
  local noOverflowSupported = (layer and layer.noOverflowSupported == true)

  local nt  = win.nametableBytes or {}
  local at  = win.nametableAttrBytes or {}
  if #nt == 0 then
    return nil, "empty_nametableBytes"
  end

  local hasChanges = hasWindowNametableChanges(win)
  local budget = nil
  if type(endAddr) == "number" then
    budget = math.abs(endAddr - startAddr) + 1
  elseif type(win.originalTotalByteNumber) == "number" and win.originalTotalByteNumber > 0 then
    budget = win.originalTotalByteNumber
  elseif type(win._originalCompressedBytes) == "table" and #win._originalCompressedBytes > 0 then
    budget = #win._originalCompressedBytes
  end

  local writeStart = startAddr
  if type(endAddr) == "number" and endAddr < startAddr then
    writeStart = endAddr
  end

  local bytesToWrite = nil
  if (not hasChanges) and type(win._originalCompressedBytes) == "table" and #win._originalCompressedBytes > 0 then
    bytesToWrite = copyBytes(win._originalCompressedBytes)
    DebugController.log(
      "info",
      "NTM",
      "writeBackToROM: unchanged nametable, reusing original compressed stream (%d bytes)",
      #bytesToWrite
    )
  else
  -- Get codec from layer or default to "konami"
    local codec = (layer and layer.codec) or "konami"
    local compressed = NametableUtils.encode_decompressed_nametable(
      nt,
      at,
      codec
    )

    local compressedSize = #compressed
    if noOverflowSupported and budget and compressedSize > budget then
      DebugController.log(
        "warning",
        "NTM",
        "writeBackToROM: compressed nametable exceeds budget (%d > %d), writing with overflow",
        compressedSize,
        budget
      )
    end
    bytesToWrite = compressed
  end

  if budget and #bytesToWrite < budget then
    for i = #bytesToWrite + 1, budget do
      bytesToWrite[i] = 0xFF
    end
  end

  local newRom, err
  if budget and #bytesToWrite <= budget then
    newRom, err = chr.writeBytesToRange(romRaw, writeStart, budget, bytesToWrite)
    if not newRom then
      return nil, "[NametableTilesController] writeBytesToRange failed: " .. tostring(err)
    end
  else
    newRom, err = chr.writeBytesStartingAt(romRaw, writeStart, bytesToWrite)
    if not newRom then
      return nil, "[NametableTilesController] writeBytesStartingAt failed: " .. tostring(err)
    end
  end

  DebugController.log(
    "info",
    "NTM",
    "Wrote %d compressed bytes to ROM at 0x%04X%s",
    #bytesToWrite,
    writeStart,
    budget and string.format(" (budget=%d)", budget) or ""
  )
  return newRom
end

-- Given a PPUFrameWindow + its nametable layer, decode the 64 attribute bytes
-- into per-tile palette numbers (1..4) stored in layer.paletteNumbers[idx].
-- idx is 0-based: idx = row * cols + col (row/col also 0-based).
function M.extractPaletteNumbersFromAttributes(win, layer, cols, rows)
  layer.paletteNumbers = layer.paletteNumbers or {}

  local attrBytes = win.nametableAttrBytes or {}
  if #attrBytes == 0 then
    DebugController.log("info", "NTM", "extractPaletteNumbersFromAttributes: no attr bytes for %s", win.title or "(no title)")
    return
  end

  -- Debug header
  DebugController.log("info", "NTM", "=== extractPaletteNumbersFromAttributes ===")
  DebugController.log("info", "NTM", "  win.title: %s", win.title or "(no title)")
  DebugController.log("info", "NTM", "  layer.name: %s", layer.name or "(no name)")
  DebugController.log("info", "NTM", "  cols, rows: %d, %d", cols, rows)
  DebugController.log("info", "NTM", "  attr byte count: %d", #attrBytes)

  -- NES: attributes stored as an 8x8 table (for a 32x30 nametable).
  -- Each attribute byte covers a 4x4 tile area, split into 4 quadrants
  -- (2x2 tiles each), each quadrant picking a palette 0..3.
  local attrCols = math.floor(cols / 4)  -- typically 8 for 32 cols
  local attrRows = math.floor(rows / 4)  -- typically 7 or 8 for 30 rows

  for attrIndex = 1, #attrBytes do
    local attrByte = attrBytes[attrIndex] or 0

    -- Position of this attribute byte in the 8x8 attr grid
    local z       = attrIndex - 1              -- 0-based
    local attrCol = (z % attrCols)            -- 0-based
    local attrRow = math.floor(z / attrCols)  -- 0-based

    -- Decode 4 quadrant palette indices (0..3) from the attribute byte
    local topLeft     =  attrByte        % 4
    local topRight    = math.floor((attrByte % 16)  / 4)   -- bits 2..3
    local bottomLeft  = math.floor((attrByte % 64)  / 16)  -- bits 4..5
    local bottomRight = math.floor( attrByte        / 64)  -- bits 6..7

    -- Convert to palette numbers (1..4) to match your paletteData.items[1..4]
    local palTL = topLeft     + 1
    local palTR = topRight    + 1
    local palBL = bottomLeft  + 1
    local palBR = bottomRight + 1

    -- Base tile coords (top-left of the 4x4 area this attribute covers)
    local baseCol = attrCol * 4
    local baseRow = attrRow * 4

    -- Helper to assign a 2x2 block, clamped to cols/rows
    local function assign2x2(startCol, startRow, palNum)
      for qRow = 0, 1 do
        for qCol = 0, 1 do
          local tileCol = startCol + qCol
          local tileRow = startRow + qRow
          if tileCol < cols and tileRow < rows then
            local idx = tileRow * cols + tileCol   -- 0-based linear index
            layer.paletteNumbers[idx] = palNum
          end
        end
      end
    end

    -- Top-left quadrant (2x2 tiles)
    assign2x2(baseCol,     baseRow,     palTL)
    -- Top-right quadrant
    assign2x2(baseCol + 2, baseRow,     palTR)
    -- Bottom-left quadrant
    assign2x2(baseCol,     baseRow + 2, palBL)
    -- Bottom-right quadrant
    assign2x2(baseCol + 2, baseRow + 2, palBR)
  end

  -- Sample a few indices for debugging
  local testIndices = { 0, 1, cols, cols + 1, cols * 4 + 4 }
  for _, idx in ipairs(testIndices) do
    local v = layer.paletteNumbers[idx]
    if v ~= nil then
      DebugController.log("info", "NTM", "  paletteNumbers[%d] = %d", idx, v)
    end
  end

  DebugController.log("info", "NTM", "=== end extractPaletteNumbersFromAttributes ===")
end

----------------------------------------------------------------------
-- Palette number assignment
----------------------------------------------------------------------

--- Set palette number for a tile at (col, row) on a layer.
--  For PPU frame windows: updates nametableAttrBytes and all 4 tiles in the 2x2 quadrant.
--  For regular tile layers: updates layer.paletteNumbers[idx].
--
--  win        : window object
--  layer      : layer table
--  col, row   : tile coordinates (0-based)
--  paletteNum : palette number (1-4)
--
--  Returns: true on success, false on failure
function M.setPaletteNumberForTile(win, layer, col, row, paletteNum)
  if not (win and layer) then return false end
  if not (col and row) then return false end
  if not paletteNum or paletteNum < 1 or paletteNum > 4 then return false end
  
  local cols = win.cols or 32
  local rows = win.rows or 30
  
  -- Validate coordinates
  if col < 0 or col >= cols or row < 0 or row >= rows then return false end
  
  -- For PPU frame windows, update attribute bytes
  if WindowCaps.isPpuFrame(win) and win.nametableAttrBytes then
    return M._setPaletteNumberForPPUFrame(win, layer, col, row, paletteNum, cols, rows)
  end
  
  -- For regular tile layers, just update paletteNumbers array
  layer.paletteNumbers = layer.paletteNumbers or {}
  local idx = row * cols + col  -- 0-based linear index
  layer.paletteNumbers[idx] = paletteNum
  return true
end

--- Set palette number for PPU frame window tile, updating attribute bytes.
--  This affects all 4 tiles in the 2x2 quadrant that share the same attribute byte.
--  Internal function (called by setPaletteNumberForTile).
function M._setPaletteNumberForPPUFrame(win, layer, col, row, paletteNum, cols, rows)
  local attrBytes = win.nametableAttrBytes
  if not attrBytes or #attrBytes == 0 then return false end
  
  -- Each attribute byte covers a 4x4 tile area
  local attrCols = math.floor(cols / 4)  -- typically 8 for 32 cols
  local attrRows = math.floor(rows / 4)  -- typically 7 or 8 for 30 rows
  
  -- Which attribute byte covers this tile?
  local attrCol = math.floor(col / 4)
  local attrRow = math.floor(row / 4)
  
  if attrCol < 0 or attrCol >= attrCols or attrRow < 0 or attrRow >= attrRows then
    return false
  end
  
  local attrIndex = attrRow * attrCols + attrCol + 1  -- 1-based index
  if attrIndex < 1 or attrIndex > #attrBytes then return false end
  
  local attrByte = attrBytes[attrIndex] or 0
  
  -- Determine which quadrant of the 4x4 area this tile is in
  local localCol = col % 4  -- 0-3
  local localRow = row % 4  -- 0-3
  
  -- Convert palette number (1-4) to palette index (0-3)
  local palIndex = paletteNum - 1
  
  -- Update the appropriate bits in the attribute byte
  local topLeft     = attrByte % 4
  local topRight    = math.floor((attrByte % 16) / 4)
  local bottomLeft  = math.floor((attrByte % 64) / 16)
  local bottomRight = math.floor(attrByte / 64)
  
  if localRow < 2 then
    -- Top half
    if localCol < 2 then
      topLeft = palIndex  -- bits 0-1
    else
      topRight = palIndex  -- bits 2-3
    end
  else
    -- Bottom half
    if localCol < 2 then
      bottomLeft = palIndex  -- bits 4-5
    else
      bottomRight = palIndex  -- bits 6-7
    end
  end
  
  -- Reconstruct attribute byte from quadrants
  local newAttrByte = topLeft + (topRight * 4) + (bottomLeft * 16) + (bottomRight * 64)
  attrBytes[attrIndex] = newAttrByte
  
  -- Ensure attribute bytes array maintains correct size and all elements are initialized
  -- NES standard: attribute table is always 8x8 = 64 bytes for 32-column nametables
  -- Even if nametable has fewer rows (e.g., 30 rows), we still need 64 attribute bytes
  local expectedSize = math.min(64, attrCols * 8)  -- Cap at 64 bytes (NES standard)
  for i = 1, expectedSize do
    if attrBytes[i] == nil then
      attrBytes[i] = 0x00
    end
  end
  
  -- Safety: Ensure array doesn't exceed 64 bytes
  if #attrBytes > 64 then
    local originalSize = #attrBytes
    local trimmed = {}
    for i = 1, 64 do
      trimmed[i] = attrBytes[i] or 0x00
    end
    win.nametableAttrBytes = trimmed
    DebugController.log("warning", "NTM", "Truncated nametableAttrBytes to 64 bytes during palette update (was %d)", originalSize)
  end
  
  -- Sync paletteNumbers from updated attribute bytes
  -- This ensures all 4 tiles in the 2x2 quadrant are updated correctly
  M.extractPaletteNumbersFromAttributes(win, layer, cols, rows)

  -- Attribute updates affect the selected 2x2 quadrant inside this 4x4 attribute block.
  -- Invalidate those cells for the cached PPU nametable canvas path.
  if win.invalidateNametableLayerCanvas and win.getActiveLayerIndex then
    local li = win:getActiveLayerIndex() or win.activeLayer or 1
    local baseCol = attrCol * 4
    local baseRow = attrRow * 4
    local qCol = (localCol < 2) and 0 or 2
    local qRow = (localRow < 2) and 0 or 2
    for dy = 0, 1 do
      for dx = 0, 1 do
        local c = baseCol + qCol + dx
        local r = baseRow + qRow + dy
        if c >= 0 and c < cols and r >= 0 and r < rows then
          win:invalidateNametableLayerCanvas(li, c, r)
        end
      end
    end
  end

  -- Keep compressed nametable bytes in ROM synchronized with edited attribute bytes.
  if win.updateCompressedBytesInROM then
    local ok, err = win:updateCompressedBytesInROM()
    if not ok then
      DebugController.log("warning", "NTM", "Failed to update ROM after palette assignment: %s", tostring(err))
    end
  end

  if win.syncNametableLayerMetadata then
    win:syncNametableLayerMetadata()
  end
  
  -- Note: We no longer store paletteAssignments.
  -- User-defined attribute bytes are saved as userDefinedAttrs hex string in snapshotNametableLayer.
  
  return true
end

return M
