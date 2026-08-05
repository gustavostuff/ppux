-- nametable_unscramble_controller.lua
-- Handles unscrambling PPU frame nametables from reference PNG images

local DebugController = require("controllers.dev.debug_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local PngPaletteMappingController = require("controllers.png.palette_mapping_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local PatternTableMapping = require("utils.pattern_table_mapping")
local PpuRange = require("controllers.app.ppu_frame_range_helpers")
local BankViewController = require("controllers.chr.bank_view_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")

local M = {}

-- Convert RGB to brightness (luminance formula)
local function getBrightness(r, g, b)
  -- Standard luminance formula: 0.299*R + 0.587*G + 0.114*B
  return 0.299 * (r or 0) + 0.587 * (g or 0) + 0.114 * (b or 0)
end

-- Build a mapping from unique opaque colors (sorted darkest->lightest) to indices 0..3.
-- Returns map[key]=index, uniqueCount
local function buildBrightnessIndexMap(imageData, paletteColors)
  local rankMap, uniqueCount = PngPaletteMappingController.buildBrightnessRankMap(imageData, {
    rankStart = 0,
    maxRank = 3,
  })

  local remap = nil
  if paletteColors then
    local hasTransparency = PngPaletteMappingController.imageHasTransparency(imageData)
    remap = hasTransparency
      and PngPaletteMappingController.buildPaletteBrightnessRemap(paletteColors, {
        pixelValues = { 1, 2, 3 },
        rankStart = 0,
      })
      or PngPaletteMappingController.buildPaletteBrightnessRemap(paletteColors, {
        pixelValues = { 0, 1, 2, 3 },
        rankStart = 0,
      })
  end

  return rankMap, uniqueCount, remap
end

local function mapPixelToIndex(r, g, b, a, brightnessMap, brightnessRemap)
  if a == 0 then return 0 end
  local key = PngPaletteMappingController.rgbKeyFromFloats(r, g, b)
  local rank = brightnessMap[key] or 0
  if brightnessRemap then
    return brightnessRemap[rank] or 0
  end
  return rank
end

-- Extract 8x8 tile pattern from PNG at given position
-- Returns array of 64 indices based on image brightness ordering (darkest->0)
local function extractTileFromPNG(imageData, tileCol, tileRow, brightnessMap, brightnessRemap)
  local pixels = {}
  local tileX = tileCol * 8
  local tileY = tileRow * 8
  
  for y = 0, 7 do
    for x = 0, 7 do
      local px = tileX + x
      local py = tileY + y
      local r, g, b, a = imageData:getPixel(px, py)

      pixels[y * 8 + x + 1] = mapPixelToIndex(r, g, b, a, brightnessMap, brightnessRemap)
    end
  end
  
  return pixels
end

-- Compare two 8x8 pixel patterns
-- Returns number of differing pixels
local function comparePatterns(pattern1, pattern2, threshold)
  threshold = threshold or 0
  local differences = 0
  
  for i = 1, 64 do
    if pattern1[i] ~= pattern2[i] then
      differences = differences + 1
      if differences > threshold then
        return differences
      end
    end
  end
  
  return differences
end

local function patternEntryHasByte(entry, byteVal)
  if not (entry and entry.bytes and type(byteVal) == "number") then
    return false
  end
  for _, b in ipairs(entry.bytes) do
    if b == byteVal then
      return true
    end
  end
  return false
end

local function resolveEmptyNametableByte(layer)
  if layer and type(layer.emptyByte) == "number" then
    return layer.emptyByte
  end
  local codec = (layer and layer.codec) or "konami"
  if codec == "zelda2" then
    return 0xF4
  end
  return 0x00
end

local function isPngTileTransparent(imageData, tileCol, tileRow)
  local tileX = tileCol * 8
  local tileY = tileRow * 8

  for y = 0, 7 do
    for x = 0, 7 do
      local _, _, _, a = imageData:getPixel(tileX + x, tileY + y)
      if a > 0 then
        return false
      end
    end
  end

  return true
end

local function findLinkedPatternTableWindow(layer, app)
  local id = layer and layer.linkedPatternTableWindowId
  if type(id) ~= "string" or id == "" then
    return nil
  end
  local wm = app and app.wm
  if not (wm and wm.getWindows) then
    return nil
  end
  for _, w in ipairs(wm:getWindows()) do
    if w and w._id == id then
      return w
    end
  end
  return nil
end

--- Sync linked pattern-table ranges onto the nametable layer, then build the logical map.
--- Returns map, errMessage (errMessage is set when no usable pattern table is available).
local function resolveUnscramblePatternMap(layer, app)
  if not layer then
    return nil, "No tile layer found"
  end

  if app and app.wm and PatternTableDisplayController.resolveLinkedPatternTableLayers then
    PatternTableDisplayController.resolveLinkedPatternTableLayers(app.wm)
  end

  local patternTable = layer.patternTable
  if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" or #patternTable.ranges == 0 then
    if type(layer.linkedPatternTableWindowId) == "string" and layer.linkedPatternTableWindowId ~= "" then
      return nil, "Linked Pattern table has no usable ranges"
    end
    return nil, "Link a Pattern table window (or set patternTable.ranges) before unscrambling"
  end

  local map, mapErr = PpuRange.buildPatternTableMapAllowPartial(patternTable)
  if not map then
    return nil, mapErr or "Invalid pattern table mapping"
  end

  local count = 0
  for _ in pairs(map) do
    count = count + 1
  end
  if count == 0 then
    return nil, "Pattern table mapping is empty"
  end

  return map, nil
end

local function ensureMappedBanks(map, app)
  local state = app and app.appEditState
  if not (state and map and type(state.chrBanksBytes) == "table") then
    return
  end
  local seen = {}
  for _, entry in pairs(map) do
    local bank = entry and tonumber(entry.bank)
    if bank and not seen[bank] and state.chrBanksBytes[bank] then
      seen[bank] = true
      BankViewController.ensureBankTiles(state, bank)
    end
  end
end

local function resolveTile(tilesPool, map, byteVal)
  if not (tilesPool and map and type(byteVal) == "number") then
    return nil
  end
  local entry = map[byteVal]
  if not entry then
    return nil
  end
  local bankTiles = tilesPool[entry.bank]
  return bankTiles and bankTiles[entry.tileIndex] or nil
end

local function addCatalogEntry(catalog, byteVal, tileRef)
  if not (tileRef and tileRef.pixels and type(byteVal) == "number") then
    return
  end
  local patternKey = table.concat(tileRef.pixels, ",")
  if not catalog[patternKey] then
    catalog[patternKey] = {
      byte = byteVal,
      bytes = { byteVal },
      col = nil,
      row = nil,
      tile = tileRef,
      pattern = tileRef.pixels,
    }
    return
  end
  local entry = catalog[patternKey]
  local seen = false
  for _, existingByte in ipairs(entry.bytes or {}) do
    if existingByte == byteVal then
      seen = true
      break
    end
  end
  if not seen then
    entry.bytes = entry.bytes or {}
    entry.bytes[#entry.bytes + 1] = byteVal
  end
end

local function buildCatalogFromPatternTableItems(ptWin, tilesPool)
  if not (ptWin and tilesPool) then
    return nil
  end
  local layer = ptWin.layers and ptWin.layers[1]
  local items = layer and layer.items
  if type(items) ~= "table" then
    return nil
  end

  local hasItem = false
  for _, tileRef in pairs(items) do
    if tileRef and tileRef.pixels then
      hasItem = true
      break
    end
  end
  if not hasItem then
    return nil
  end

  local catalog = {}
  local cols = math.max(1, math.floor(tonumber(ptWin.cols) or 16))
  local rows = math.max(1, math.floor(tonumber(ptWin.rows) or 16))
  local layoutMode = (layer and layer.mode) or "8x8"
  local maxPos = math.min(255, rows * cols - 1)

  for pos = 0, maxPos do
    local logicalIndex = BankViewController.chrOrderingIndexForGridPos(layoutMode, pos)
    local tileRef = items[pos + 1]
    addCatalogEntry(catalog, logicalIndex, tileRef)
  end

  local size = 0
  for _ in pairs(catalog) do
    size = size + 1
  end
  if size == 0 then
    return nil
  end
  return catalog
end

local function originalTileMatchesPng(originalByte, pngPattern, tilesPool, map)
  if type(originalByte) ~= "number" then
    return false
  end
  local tileRef = resolveTile(tilesPool, map, originalByte)
  if not (tileRef and tileRef.pixels) then
    return false
  end
  return comparePatterns(pngPattern, tileRef.pixels, 0) == 0
end

local function pickCatalogByte(catalogEntry, originalByte, pngPattern, tilesPool, map)
  if catalogEntry and type(originalByte) == "number" and patternEntryHasByte(catalogEntry, originalByte) then
    local tileRef = resolveTile(tilesPool, map, originalByte)
    if tileRef and tileRef.pixels and comparePatterns(pngPattern, tileRef.pixels, 0) == 0 then
      return originalByte
    end
  end
  return catalogEntry and catalogEntry.byte or nil
end

local function preferOriginalAmongCandidates(candidates, originalByte, pngPattern, tilesPool, map)
  if type(originalByte) ~= "number" then
    return candidates[1]
  end
  local tileRef = resolveTile(tilesPool, map, originalByte)
  if not (tileRef and tileRef.pixels) then
    return candidates[1]
  end
  if comparePatterns(pngPattern, tileRef.pixels, 0) ~= 0 then
    return candidates[1]
  end
  for _, cand in ipairs(candidates) do
    if cand.byte == originalByte then
      return cand
    end
  end
  return candidates[1]
end

local function findBestCatalogMatch(tileCatalog, pngPattern, threshold, originalByte, tilesPool, map)
  threshold = threshold or 0
  local bestMatch = nil
  local bestDiff = 999
  local candidates = {}

  for _, catalogEntry in pairs(tileCatalog) do
    local diff = comparePatterns(pngPattern, catalogEntry.pattern, 999)
    if diff <= threshold then
      if diff < bestDiff then
        bestDiff = diff
        candidates = { catalogEntry }
      elseif diff == bestDiff then
        candidates[#candidates + 1] = catalogEntry
      end
    end
  end

  if #candidates > 0 then
    bestMatch = candidates[1]
    if #candidates > 1 then
      bestMatch = preferOriginalAmongCandidates(candidates, originalByte, pngPattern, tilesPool, map)
    end
  end

  return bestMatch, bestDiff
end

local function findNearestCatalogMatch(tileCatalog, pngPattern, originalByte, tilesPool, map)
  local bestMatch = nil
  local bestDiff = 999

  for _, catalogEntry in pairs(tileCatalog) do
    local diff = comparePatterns(pngPattern, catalogEntry.pattern, 999)
    if diff < bestDiff then
      bestDiff = diff
      bestMatch = catalogEntry
    end
  end

  if bestMatch then
    local tied = {}
    for _, catalogEntry in pairs(tileCatalog) do
      local diff = comparePatterns(pngPattern, catalogEntry.pattern, 999)
      if diff == bestDiff then
        tied[#tied + 1] = catalogEntry
      end
    end
    if #tied > 1 then
      bestMatch = preferOriginalAmongCandidates(tied, originalByte, pngPattern, tilesPool, map)
    end
  end

  return bestMatch, bestDiff
end

-- Build a catalog of unique tile patterns from the linked Pattern table (preferred)
-- or from the layer's patternTable.ranges map. Never falls back to a raw CHR bank.
-- Returns: catalog, map, errMessage
local function buildTileCatalog(win, layer, tilesPool, app)
  local catalog = {}
  local cols = win.cols
  local rows = win.rows

  if not tilesPool then
    return catalog, nil, "No tiles pool available for catalog building"
  end

  local map, mapErr = resolveUnscramblePatternMap(layer, app)
  if not map then
    return catalog, nil, mapErr
  end

  ensureMappedBanks(map, app)

  local ptWin = findLinkedPatternTableWindow(layer, app)
  local fromItems = buildCatalogFromPatternTableItems(ptWin, tilesPool)
  if fromItems then
    catalog = fromItems
    DebugController.log(
      "info",
      "UNSCR",
      "Built tile catalog from linked Pattern table window items (%s)",
      tostring(ptWin.title or ptWin._id or "?")
    )
  else
    for byteVal, entry in pairs(map) do
      local bankTiles = tilesPool[entry.bank]
      local tileRef = bankTiles and bankTiles[entry.tileIndex] or nil
      addCatalogEntry(catalog, byteVal, tileRef)
    end
    DebugController.log("info", "UNSCR", "Built tile catalog from patternTable.ranges map")
  end

  -- Mark which catalog patterns appear in the current nametable (prefer those when matching).
  if win.nametableBytes then
    for i = 1, #win.nametableBytes do
      local byteVal = win.nametableBytes[i]
      local tileRef = resolveTile(tilesPool, map, byteVal)

      if tileRef and tileRef.pixels then
        local patternKey = table.concat(tileRef.pixels, ",")
        local entry = catalog[patternKey]

        if entry then
          local z = i - 1
          local col = z % cols
          local row = math.floor(z / cols)
          entry.col = col
          entry.row = row
        end
      end
    end
  end

  return catalog, map, nil
end

-- Main unscramble function
function M.unscrambleFromPNG(win, file, tilesPool, threshold, app)
  threshold = threshold or 0  -- Default: zero-error margin
  
  if not WindowCaps.isPpuFrame(win) then
    return false, "Window must be a PPU frame window"
  end
  
  -- Get the nametable layer
  local layer = win.layers and win.layers[win.activeLayer or 1]
  if not layer or layer.kind ~= "tile" then
    return false, "No tile layer found"
  end
  
  -- Load PNG image
  local imageData
  local success, err = pcall(function()
    file:open("r")
    local fileData = file:read()
    file:close()
    
    if not fileData or #fileData == 0 then
      error("Could not read file data")
    end
    
    -- Create FileData object and load image
    local fileDataObj = love.filesystem.newFileData(fileData, file:getFilename() or "unscramble.png")
    if not fileDataObj then
      error("Failed to create FileData")
    end
    
    imageData = love.image.newImageData(fileDataObj)
    if not imageData then
      error("Failed to decode image")
    end
  end)
  
  if not success or not imageData then
    return false, "Failed to load PNG: " .. (err or "unknown error")
  end
  
  -- Verify image dimensions (should be 256x240 for 32x30 tiles)
  local imgW, imgH = imageData:getWidth(), imageData:getHeight()
  local expectedTilesW = math.floor(imgW / 8)
  local expectedTilesH = math.floor(imgH / 8)
  
  if expectedTilesW ~= win.cols or expectedTilesH ~= win.rows then
    DebugController.log("warning", "UNSCR", "PNG size (%dx%d) doesn't match nametable size (%dx%d)", 
      expectedTilesW, expectedTilesH, win.cols, win.rows)
  end

  local romRaw = (app and app.appEditState and app.appEditState.romRaw) or win.romRaw
  local paletteSourceLayer = (app and app.winBank and app.winBank.layers and app.winBank.layers[1]) or layer
  local paletteColors = ShaderPaletteController.getPaletteColors(paletteSourceLayer, 1, romRaw)
  local brightnessMap, uniqueColorCount, brightnessRemap = buildBrightnessIndexMap(imageData, paletteColors)
  if uniqueColorCount > 4 then
    DebugController.log("warning", "UNSCR", "PNG has %d unique opaque colors; mapping darkest->lightest and clamping to 0-3", uniqueColorCount)
  else
    DebugController.log("info", "UNSCR", "PNG unique opaque colors (dark->light): %d", uniqueColorCount)
  end
  
  -- Build catalog from the linked Pattern table (or layer patternTable.ranges).
  DebugController.log("info", "UNSCR", "Building tile catalog...")
  local tileCatalog, patternMap, catalogErr = buildTileCatalog(win, layer, tilesPool, app)
  local catalogSize = 0
  for _ in pairs(tileCatalog) do catalogSize = catalogSize + 1 end
  DebugController.log("info", "UNSCR", "Found %d unique tile patterns in pattern table catalog", catalogSize)

  if not patternMap then
    return false, catalogErr or "No pattern table available for unscramble"
  end
  if catalogSize == 0 then
    return false, catalogErr or "No tiles found in linked Pattern table"
  end
  
  -- Count unique patterns in PNG
  local pngPatterns = {}
  local totalTilesInPNG = expectedTilesW * expectedTilesH
  for row = 0, math.min(win.rows - 1, expectedTilesH - 1) do
    for col = 0, math.min(win.cols - 1, expectedTilesW - 1) do
      local pngPattern = extractTileFromPNG(imageData, col, row, brightnessMap, brightnessRemap)
      local patternKey = table.concat(pngPattern, ",")
      pngPatterns[patternKey] = (pngPatterns[patternKey] or 0) + 1
    end
  end
  local uniquePngPatterns = 0
  for _ in pairs(pngPatterns) do uniquePngPatterns = uniquePngPatterns + 1 end
  DebugController.log("info", "UNSCR", "PNG contains %d unique patterns out of %d total tiles (max should be <= 256)", uniquePngPatterns, totalTilesInPNG)
  
  if uniquePngPatterns > 256 then
    DebugController.log("warning", "UNSCR", "PNG has %d unique patterns, which exceeds NES limit of 256 tiles per page!", uniquePngPatterns)
  end
  
  -- Extract tiles from PNG and match to catalog
  local newNametableBytes = {}
  local previousNametableBytes = {}
  local matchedCount = 0
  local unmatchedCount = 0
  
  -- Initialize with original bytes (for unmatched tiles)
  for i = 1, #win.nametableBytes do
    previousNametableBytes[i] = win.nametableBytes[i]
    newNametableBytes[i] = win.nametableBytes[i]
  end
  
  DebugController.log("info", "UNSCR", "Matching PNG tiles to catalog (threshold=%d)...", threshold)
  
  local ambiguousMatches = 0
  local perfectMatches = 0
  local emptyTileMatches = 0
  local fallbackMatches = 0
  local emptyByte = resolveEmptyNametableByte(layer)

  for row = 0, math.min(win.rows - 1, expectedTilesH - 1) do
    for col = 0, math.min(win.cols - 1, expectedTilesW - 1) do
      local idx = row * win.cols + col + 1
      local originalByte = win.nametableBytes and win.nametableBytes[idx]

      -- Extract pattern from PNG (brightness-based quantization)
      local pngPattern = extractTileFromPNG(imageData, col, row, brightnessMap, brightnessRemap)
      local pngPatternKey = table.concat(pngPattern, ",")

      if isPngTileTransparent(imageData, col, row) then
        newNametableBytes[idx] = emptyByte
        matchedCount = matchedCount + 1
        emptyTileMatches = emptyTileMatches + 1
        goto continue_match
      end

      local exactEntry = tileCatalog[pngPatternKey]
      if exactEntry then
        newNametableBytes[idx] = pickCatalogByte(exactEntry, originalByte, pngPattern, tilesPool, patternMap)
        matchedCount = matchedCount + 1
        perfectMatches = perfectMatches + 1
        if exactEntry.bytes and #exactEntry.bytes > 1 then
          ambiguousMatches = ambiguousMatches + 1
        end
        goto continue_match
      end

      local origMatchesPng = originalTileMatchesPng(originalByte, pngPattern, tilesPool, patternMap)

      local bestMatch, bestDiff = findBestCatalogMatch(tileCatalog, pngPattern, threshold, originalByte, tilesPool, patternMap)
      if not bestMatch then
        bestMatch, bestDiff = findNearestCatalogMatch(tileCatalog, pngPattern, originalByte, tilesPool, patternMap)
        if bestMatch and bestDiff > 16 and origMatchesPng then
          bestMatch = nil
        end
      end

      if bestMatch then
        newNametableBytes[idx] = pickCatalogByte(bestMatch, originalByte, pngPattern, tilesPool, patternMap)
        matchedCount = matchedCount + 1
        if bestDiff == 0 then
          perfectMatches = perfectMatches + 1
        else
          fallbackMatches = fallbackMatches + 1
        end
        if bestMatch.bytes and #bestMatch.bytes > 1 then
          ambiguousMatches = ambiguousMatches + 1
        end
        goto continue_match
      end

      if not origMatchesPng then
        bestMatch, bestDiff = findNearestCatalogMatch(tileCatalog, pngPattern, originalByte, tilesPool, patternMap)
        if bestMatch then
          newNametableBytes[idx] = pickCatalogByte(bestMatch, originalByte, pngPattern, tilesPool, patternMap)
          matchedCount = matchedCount + 1
          fallbackMatches = fallbackMatches + 1
          if bestMatch.bytes and #bestMatch.bytes > 1 then
            ambiguousMatches = ambiguousMatches + 1
          end
          goto continue_match
        end
      end

      -- Keep the original byte only when it still matches the PNG tile content.
      unmatchedCount = unmatchedCount + 1

      ::continue_match::
    end
    
    -- Log progress every 10 rows
    if row % 10 == 0 then
      DebugController.log("info", "UNSCR", "Progress: row %d/%d", row, math.min(win.rows - 1, expectedTilesH - 1))
    end
  end
  
  if ambiguousMatches > 0 then
    DebugController.log("warning", "UNSCR", "Found %d tiles with ambiguous matches (multiple candidates)", ambiguousMatches)
  end
  
  -- Verify nametable bytes array size (should be 960 for standard NES nametable)
  if #newNametableBytes ~= #win.nametableBytes then
    DebugController.log("warning", "UNSCR", "Nametable bytes size mismatch: expected %d, got %d", 
      #win.nametableBytes, #newNametableBytes)
  end

  local undoRedo = app and app.undoRedo or nil
  local undoChanges = {}
  if undoRedo and undoRedo.addDragEvent then
    for i = 1, #newNametableBytes do
      local beforeByte = previousNametableBytes[i]
      local afterByte = newNametableBytes[i]
      if beforeByte ~= afterByte then
        local z = i - 1
        undoChanges[#undoChanges + 1] = {
          win = win,
          layerIndex = win.activeLayer or 1,
          col = z % win.cols,
          row = math.floor(z / win.cols),
          before = beforeByte,
          after = afterByte,
          isNametableByte = true,
        }
      end
    end
  end
  
  -- Update nametable bytes and record swaps
  if win._originalNametableBytes then
    win._tileSwaps = win._tileSwaps or {}
    for i = 1, #newNametableBytes do
      local newByte = newNametableBytes[i]
      local origByte = win._originalNametableBytes[i]
      
      if newByte == origByte then
        -- No change, remove from swaps
        win._tileSwaps[i] = nil
      else
        -- Changed, record swap
        win._tileSwaps[i] = newByte
      end
    end
  end
  
  DebugController.log("info", "UNSCR", "Setting nametable bytes: %d bytes", #newNametableBytes)
  win.nametableBytes = newNametableBytes
  
  -- Update visual layer items directly (avoid calling win:set() which triggers ROM writes)
  -- This is similar to how swapCells() works - update items directly, then ROM once at the end
  layer.items = {}
  
  -- Debug: Track tile-to-byte conversion mismatches
  local conversionMismatches = 0
  local conversionDebugSample = {}
  local maxDebugSamples = 5
  
  for i = 1, #win.nametableBytes do
    local byteVal = win.nametableBytes[i]
    local tileRef = resolveTile(tilesPool, patternMap, byteVal)
    
    if tileRef then
      local z = i - 1
      local col = z % win.cols
      local row = math.floor(z / win.cols)
      
      -- Store tile reference directly in layer.items (1-based index)
      layer.items[i] = tileRef
      
      -- Verify tile-to-byte conversion (debug only)
      -- This checks if converting the tile back to a byte matches our original byte
      -- Uses the same logic as tileToByte() in ppu_frame_window.lua
      local convertedByte = nil
      if tileRef and tileRef.index ~= nil then
        local tileIndex = tileRef.index  -- 0-based within bank
        convertedByte = PatternTableMapping.logicalIndexForTileRef(
          layer,
          tileRef
        )
        if convertedByte == nil then
          convertedByte = tileIndex % 256
        end
        
        if convertedByte ~= byteVal then
          conversionMismatches = conversionMismatches + 1
          if #conversionDebugSample < maxDebugSamples then
            table.insert(conversionDebugSample, {
              idx = i,
              col = col,
              row = row,
              expectedByte = byteVal,
              tileIndex = tileIndex,
              convertedByte = convertedByte,
              page = (tileIndex >= 256) and 2 or 1
            })
          end
        end
      end
    else
      -- No tile found for this byte - clear the item
      layer.items[i] = nil
    end
  end
  
  -- Log conversion mismatches if any
  if conversionMismatches > 0 then
    DebugController.log("warning", "UNSCR", "Found %d tile-to-byte conversion mismatches (tile index doesn't match byte value)", conversionMismatches)
    for _, sample in ipairs(conversionDebugSample) do
      DebugController.log("warning", "UNSCR", "  Sample: idx=%d (col=%d, row=%d) expected byte=%d, tile.index=%d, converted=%d", 
        sample.idx, sample.col, sample.row, sample.expectedByte, sample.tileIndex, sample.convertedByte)
    end
  end
  
  -- Update ROM once at the end (avoid 960 individual ROM writes)
  if win.updateCompressedBytesInROM then
    DebugController.log("info", "UNSCR", "Updating ROM with %d nametable bytes...", #win.nametableBytes)
    local ok, err = win:updateCompressedBytesInROM()
    if not ok then
      DebugController.log("warning", "UNSCR", "Failed to update ROM: %s", tostring(err))
    else
      DebugController.log("info", "UNSCR", "ROM update successful")
    end
  end
  
  -- Sync layer metadata
  if win.syncNametableLayerMetadata then
    win:syncNametableLayerMetadata()
  end
  if win.invalidateNametableLayerCanvas then
    win:invalidateNametableLayerCanvas(win.activeLayer or 1)
  end

  if #undoChanges > 0 then
    undoRedo:addDragEvent({
      type = "tile_drag",
      mode = "move",
      tilesPool = tilesPool,
      changes = undoChanges,
    })
  end
  
  DebugController.log("info", "UNSCR", "Unscrambling complete: %d matched (%d perfect, %d empty, %d fallback), %d unmatched", matchedCount, perfectMatches, emptyTileMatches, fallbackMatches, unmatchedCount)
  
  local matchRate = ((matchedCount + unmatchedCount) > 0) and (matchedCount / (matchedCount + unmatchedCount) * 100) or 0
  return true, string.format("Matched %d/%d tiles (%d perfect, %d empty, %d fallback, %d unmatched, %.1f%% matched)", matchedCount, matchedCount + unmatchedCount, perfectMatches, emptyTileMatches, fallbackMatches, unmatchedCount, matchRate)
end

return M
