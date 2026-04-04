-- nametable_unscramble_controller.lua
-- Handles unscrambling PPU frame nametables from reference PNG images

local DebugController = require("controllers.dev.debug_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local PngPaletteMappingController = require("controllers.png.palette_mapping_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")

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

-- Helper function to resolve tile from byte (copied from ppu_frame_window)
local function resolveTile(tilesPool, bankIndex, pageIndex, byteVal)
  if not tilesPool then return nil end
  local bank = tilesPool[bankIndex]
  if not bank then return nil end
  local B = byteVal or 0
  if pageIndex == 2 then
    return bank[256 + B]
  else
    return bank[B]
  end
end

-- Build a catalog of all unique tile patterns in the current layer
-- Includes ALL tiles from the CHR bank for the current page (0-255)
-- Returns: map of pattern -> {byte, col, row, tile}
local function buildTileCatalog(win, layer, tilesPool)
  local catalog = {}
  local cols = win.cols
  local rows = win.rows
  
  -- Get bank/page info from layer
  local bank = layer.bank or 1
  local page = layer.page or 1
  
  if not tilesPool then
    DebugController.log("warning", "UNSCR", "No tilesPool available for catalog building")
    return catalog
  end
  
  local bankData = tilesPool[bank]
  if not bankData then
    DebugController.log("warning", "UNSCR", "Bank %d not found in tilesPool", bank)
    return catalog
  end
  
  -- Include ALL 256 tiles from the CHR bank for the current page
  -- This ensures we have access to all available tiles, not just those in the nametable
  for byteVal = 0, 255 do
    local tileRef = resolveTile(tilesPool, bank, page, byteVal)
    
    if tileRef and tileRef.pixels then
      local patternKey = table.concat(tileRef.pixels, ",")
      
      -- If this pattern already exists, keep the first byte value we found
      -- (same pattern might exist at different byte positions, prefer lower byte)
      if not catalog[patternKey] then
        catalog[patternKey] = {
          byte = byteVal,
          col = nil,  -- Not from a specific position
          row = nil,
          tile = tileRef,
          pattern = tileRef.pixels
        }
      end
    end
  end
  
  -- Also mark which tiles are currently in use in the nametable
  -- This helps with preferring existing tiles when matching
  if win.nametableBytes then
    for i = 1, #win.nametableBytes do
      local byteVal = win.nametableBytes[i]
      local tileRef = resolveTile(tilesPool, bank, page, byteVal)
      
      if tileRef and tileRef.pixels then
        local patternKey = table.concat(tileRef.pixels, ",")
        local entry = catalog[patternKey]
        
        -- Update entry with position info if it exists
        if entry then
          local z = i - 1
          local col = z % cols
          local row = math.floor(z / cols)
          entry.col = col
          entry.row = row
          -- If multiple bytes have the same pattern, prefer the one in the nametable
          if entry.byte ~= byteVal then
            -- Keep the catalog entry but note that this byte also has this pattern
            -- (we'll prefer entries that match byteVal in matching logic)
          end
        end
      end
    end
  end
  
  return catalog
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
  
  -- Build catalog of all available tiles in the layer
  DebugController.log("info", "UNSCR", "Building tile catalog...")
  local tileCatalog = buildTileCatalog(win, layer, tilesPool)
  local catalogSize = 0
  for _ in pairs(tileCatalog) do catalogSize = catalogSize + 1 end
  DebugController.log("info", "UNSCR", "Found %d unique tile patterns in CHR bank (max 256 per page)", catalogSize)
  
  if catalogSize == 0 then
    return false, "No tiles found in CHR bank"
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
  local originalTileMatches = 0
  
  for row = 0, math.min(win.rows - 1, expectedTilesH - 1) do
    for col = 0, math.min(win.cols - 1, expectedTilesW - 1) do
      local idx = row * win.cols + col + 1
      local originalByte = win.nametableBytes and win.nametableBytes[idx]
      
      -- Extract pattern from PNG (brightness-based quantization)
      local pngPattern = extractTileFromPNG(imageData, col, row, brightnessMap, brightnessRemap)
      
      -- First, check if the original tile at this position is a perfect match
      -- Note: PNG pattern is brightness-quantized, tile pixels are palette indices
      -- They should match directly (0=darkest, 3=lightest) if image was rendered correctly
      local originalTile = nil
      if originalByte then
        local bank = layer.bank or 1
        local page = layer.page or 1
        local tileRef = resolveTile(tilesPool, bank, page, originalByte)
        if tileRef and tileRef.pixels then
          -- Compare PNG brightness pattern to tile's palette index pattern
          -- These should match if rendering is correct (both 0-3 range)
          local diff = comparePatterns(pngPattern, tileRef.pixels, 999)
          if diff == 0 then
            -- Perfect match with original tile - keep it!
            originalTile = {
              byte = originalByte,
              tile = tileRef,
              pattern = tileRef.pixels
            }
            originalTileMatches = originalTileMatches + 1
            perfectMatches = perfectMatches + 1
          end
        end
      end
      
      -- If original tile is a perfect match, use it
      if originalTile then
        newNametableBytes[idx] = originalTile.byte
        matchedCount = matchedCount + 1
      else
        -- Find best match in catalog
        local bestMatch = nil
        local bestDiff = 999
        local candidates = {}  -- Store all candidates with the same best difference
        
        for patternKey, catalogEntry in pairs(tileCatalog) do
          local diff = comparePatterns(pngPattern, catalogEntry.pattern, 999) -- Don't limit here
          if diff <= threshold then
            if diff < bestDiff then
              bestDiff = diff
              candidates = {catalogEntry}  -- Start new candidate list
            elseif diff == bestDiff then
              table.insert(candidates, catalogEntry)  -- Add to candidates
            end
          end
        end
        
        -- If we have candidates, pick the best one
        if #candidates > 0 then
          bestMatch = candidates[1]
          
          -- If multiple candidates with same score, prefer the one matching original byte
          if #candidates > 1 then
            ambiguousMatches = ambiguousMatches + 1
            for _, cand in ipairs(candidates) do
              if cand.byte == originalByte then
                bestMatch = cand
                break
              end
            end
          end
          
          if bestDiff == 0 then
            perfectMatches = perfectMatches + 1
          end
          
          newNametableBytes[idx] = bestMatch.byte
          matchedCount = matchedCount + 1
        else
          unmatchedCount = unmatchedCount + 1
        end
      end
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
  local bank, page = layer.bank or 1, layer.page or 1
  layer.items = {}
  
  -- Debug: Track tile-to-byte conversion mismatches
  local conversionMismatches = 0
  local conversionDebugSample = {}
  local maxDebugSamples = 5
  
  for i = 1, #win.nametableBytes do
    local byteVal = win.nametableBytes[i]
    local tileRef = resolveTile(tilesPool, bank, page, byteVal)
    
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
        if page == 2 and tileIndex >= 256 and tileIndex <= 511 then
          convertedByte = tileIndex - 256
        else
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
              page = page
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

  if #undoChanges > 0 then
    undoRedo:addDragEvent({
      type = "tile_drag",
      mode = "move",
      tilesPool = tilesPool,
      changes = undoChanges,
    })
  end
  
  DebugController.log("info", "UNSCR", "Unscrambling complete: %d matched (%d perfect, %d original-tile matches), %d unmatched", matchedCount, perfectMatches, originalTileMatches, unmatchedCount)
  
  local matchRate = ((matchedCount + unmatchedCount) > 0) and (matchedCount / (matchedCount + unmatchedCount) * 100) or 0
  return true, string.format("Matched %d/%d tiles (%d perfect, %d kept original, %d unmatched, %.1f%% matched)", matchedCount, matchedCount + unmatchedCount, perfectMatches, originalTileMatches, unmatchedCount, matchRate)
end

return M
