-- image_import_controller.lua
-- Handles importing indexed PNG images into CHR bank windows.
-- Converts 4-color indexed PNG images to NES tiles (8x8 patterns).

local chr = require("chr")
local BankCanvasSupport = require("controllers.chr.bank_canvas_support")
local Tile = require("user_interface.windows_system.tile_item")
local DebugController = require("controllers.dev.debug_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local PngPaletteMappingController = require("controllers.png.palette_mapping_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

----------------------------------------------------------------------
-- Validation
----------------------------------------------------------------------

--- Validate that image dimensions are multiples of 8
--  Returns: true, nil on success, or false, errorMessage on failure
local function validateImageDimensions(width, height)
  if width % 8 ~= 0 then
    return false, string.format("Image width (%d) must be a multiple of 8", width)
  end
  if height % 8 ~= 0 then
    return false, string.format("Image height (%d) must be a multiple of 8", height)
  end
  return true
end

--- Validate that image has at most 4 colors (indexed)
--  imgData: LÖVE2D ImageData object
--  Returns: true, nil on success, or false, errorMessage on failure
local function validateImageColors(imgData)
  local width, height = imgData:getWidth(), imgData:getHeight()
  local colorSet = {}
  local colorCount = 0
  
  -- Sample all pixels to count unique colors
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local r, g, b, a = imgData:getPixel(x, y)
      -- Skip fully transparent pixels (alpha = 0)
      if a > 0 then
        local key = string.format("%d_%d_%d", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
        if not colorSet[key] then
          colorSet[key] = true
          colorCount = colorCount + 1
          if colorCount > 4 then
            return false, string.format("Image has more than 4 colors (%d found)", colorCount)
          end
        end
      end
    end
  end
  
  return true
end

----------------------------------------------------------------------
-- Image to indexed color conversion
----------------------------------------------------------------------

-- Build a mapping from unique colors (sorted darkest->lightest) to indices 0..3.
-- Returns: map[key]=index, uniqueCount
local function buildBrightnessIndexMap(imgData)
  return PngPaletteMappingController.buildBrightnessRankMap(imgData, {
    rankStart = 0,
    maxRank = 3,
  })
end

-- Build a remap from brightness rank (0..3) to tile pixel value (0..3)
-- based on the luminance ordering of the target palette colors.
local function buildPaletteBrightnessRemapForTiles(paletteColors)
  return PngPaletteMappingController.buildPaletteBrightnessRemap(paletteColors, {
    pixelValues = { 0, 1, 2, 3 },
    rankStart = 0,
  })
end

-- Build a remap from opaque brightness rank (0..2) to visible tile pixel values (1..3),
-- ignoring palette slot 0 because the shader renders it transparent.
local function buildVisiblePaletteBrightnessRemapForTiles(paletteColors)
  return PngPaletteMappingController.buildPaletteBrightnessRemap(paletteColors, {
    pixelValues = { 1, 2, 3 },
    rankStart = 0,
  })
end

--- Convert image pixels to indexed color values (0-3) based on PNG brightness,
-- then remap those brightness ranks through the target palette's luminance order.
-- This keeps PNG import aligned with palette shader colors instead of raw grayscale.
local function convertToIndexedByBrightness(imgData)
  local width, height = imgData:getWidth(), imgData:getHeight()
  local indexedData = {}
  local brightnessToIndex = buildBrightnessIndexMap(imgData)
  
  for y = 0, height - 1 do
    indexedData[y + 1] = {}
    for x = 0, width - 1 do
      local r, g, b, a = imgData:getPixel(x, y)
      
      if a == 0 then
        -- Transparent pixels map to color 0
        indexedData[y + 1][x + 1] = 0
      else
        local key = PngPaletteMappingController.rgbKeyFromFloats(r, g, b)
        indexedData[y + 1][x + 1] = brightnessToIndex[key] or 0
      end
    end
  end
  
  return indexedData, brightnessToIndex
end

local function convertToIndexedByPaletteBrightness(imgData, paletteColors)
  local indexedData, brightnessToIndex = convertToIndexedByBrightness(imgData)
  local width, height = imgData:getWidth(), imgData:getHeight()

  local hasTransparency = PngPaletteMappingController.imageHasTransparency(imgData)

  -- If the PNG uses transparency, map opaque colors through visible palette slots (1..3)
  -- to match what the shader actually renders. Otherwise use all 4 slots.
  local remap = hasTransparency
    and buildVisiblePaletteBrightnessRemapForTiles(paletteColors)
    or buildPaletteBrightnessRemapForTiles(paletteColors)
  if not remap then
    return nil, "Could not resolve palette brightness mapping"
  end

  for y = 1, height do
    for x = 1, width do
      local _, _, _, a = imgData:getPixel(x - 1, y - 1)
      if a == 0 then
        indexedData[y][x] = 0
        goto continue
      end
      local rank = indexedData[y][x] or 0
      indexedData[y][x] = remap[rank] or 0
      ::continue::
    end
  end

  return indexedData, brightnessToIndex, remap
end

----------------------------------------------------------------------
-- Tile encoding
----------------------------------------------------------------------

--- Encode a single 8x8 tile from indexed pixel data
--  pixels: array of 64 values (0-3) in row-major order (pixels[y*8 + x + 1])
--  Returns: array of 16 bytes representing the tile in CHR format
local function encodeTile(pixels)
  if not pixels or #pixels ~= 64 then
    error("encodeTile: pixels array must have exactly 64 elements")
  end
  
  local bytes = {}
  -- Initialize 16 bytes to 0
  for i = 1, 16 do
    bytes[i] = 0
  end
  
  -- Encode each row (8 rows total)
  for row = 0, 7 do
    local p0 = 0  -- low bit plane (bit 0)
    local p1 = 0  -- high bit plane (bit 1)
    
    -- Encode each column in this row
    for col = 0, 7 do
      local pixelIndex = row * 8 + col + 1
      local color = pixels[pixelIndex] or 0
      
      -- Extract bit 0 and bit 1
      local lo = color % 2
      local hi = math.floor(color / 2) % 2
      
      -- Set bits in the bit planes (MSB first, left to right)
      local bitPos = 7 - col
      if lo == 1 then
        p0 = p0 + (2 ^ bitPos)
      end
      if hi == 1 then
        p1 = p1 + (2 ^ bitPos)
      end
    end
    
    -- Store the two bytes for this row
    bytes[row + 1] = p0      -- bytes 0-7: low bit plane
    bytes[row + 8 + 1] = p1  -- bytes 8-15: high bit plane
  end
  
  return bytes
end

-- Tile pattern comparison (for PPU frame imports)
----------------------------------------------------------------------

--- Compare two 8x8 pixel patterns for exact match
--  pattern1, pattern2: arrays of 64 values (0-3) in row-major order
--  Returns: true if patterns match exactly, false otherwise
local function compareTilePatterns(pattern1, pattern2)
  if not pattern1 or not pattern2 or #pattern1 ~= 64 or #pattern2 ~= 64 then
    return false
  end
  
  for i = 1, 64 do
    if pattern1[i] ~= pattern2[i] then
      return false
    end
  end
  
  return true
end

--- Find matching tile index in CHR bank for a given 8x8 pattern
--  pattern: array of 64 values (0-3) in row-major order
--  bankBytes: CHR bank byte array
--  maxTiles: maximum number of tiles to search (default 512)
--  Returns: tileIndex (0-based) if match found, nil otherwise
local function findMatchingTile(pattern, bankBytes, maxTiles)
  maxTiles = maxTiles or 512
  
  for tileIndex = 0, maxTiles - 1 do
    -- Decode tile from CHR bank
    local tilePixels, err = chr.decodeTile(bankBytes, tileIndex)
    if tilePixels and #tilePixels == 64 then
      -- Compare patterns
      if compareTilePatterns(pattern, tilePixels) then
        return tileIndex
      end
    end
  end
  
  return nil
end

----------------------------------------------------------------------
-- Main import function
----------------------------------------------------------------------

--- Import an indexed PNG image into a CHR bank window
--  file: LÖVE2D File object (PNG file)
--  win: CHR bank window object
--  startCol, startRow: starting tile coordinates (0-based) where to place the image
--  appEditState: application state containing tilesPool, chrBanksBytes, currentBank, etc.
--  edits: edits table to record changes (optional)
--  orderMode: optional order mode ("normal" or "8x16") - defaults to "normal"
--  app: optional app table (used for syncDuplicateTiles behavior)
--  Returns: success (boolean), message (string)
function M.importImageToCHRWindow(file, win, startCol, startRow, appEditState, edits, orderMode, undoRedo, app)
  -- Validate inputs
  if not file then
    return false, "No file provided"
  end
  
  if not WindowCaps.isChrLike(win) then
    return false, "Target window must be a CHR bank window"
  end
  
  if not appEditState then
    return false, "appEditState is required"
  end
  
  if not appEditState.chrBanksBytes or not appEditState.tilesPool then
    return false, "CHR banks or tiles pool not initialized"
  end
  
  local bankIdx = win.currentBank or appEditState.currentBank
  if not bankIdx or not appEditState.chrBanksBytes[bankIdx] then
    return false, "Current CHR bank not available"
  end
  
  -- Load image data from file
  -- First try to read file as binary data
  file:open("r")
  local fileData = file:read()
  file:close()
  
  if not fileData or #fileData == 0 then
    return false, "Could not read file data"
  end
  
  -- Create FileData object and load image
  local ok, fileDataObj = pcall(function()
    return love.filesystem.newFileData(fileData, file:getFilename() or "image.png")
  end)
  
  if not ok or not fileDataObj then
    return false, "Failed to create FileData: " .. (tostring(fileDataObj) or "unknown error")
  end
  
  local ok2, imgData = pcall(function()
    return love.image.newImageData(fileDataObj)
  end)
  
  if not ok2 or not imgData then
    return false, "Failed to decode image: " .. (tostring(imgData) or "unknown error")
  end
  
  local width, height = imgData:getWidth(), imgData:getHeight()
  
  -- Validate dimensions (must be multiple of 8)
  local validDims, dimError = validateImageDimensions(width, height)
  if not validDims then
    return false, dimError
  end
  
  -- Validate color count (must be <= 4)
  local validColors, colorError = validateImageColors(imgData)
  if not validColors then
    return false, colorError
  end
  
  -- Convert to indexed color data using the same palette-color luminance ordering
  -- used by shader rendering. CHR windows default to global palette #1.
  local chrLayer = win.layers and win.layers[1] or nil
  local paletteColors = ShaderPaletteController.getPaletteColors(
    chrLayer,
    1,
    appEditState.romRaw
  )
  if not paletteColors then
    return false, "No palette context available for PNG color mapping"
  end

  local indexedData, mapErr = convertToIndexedByPaletteBrightness(imgData, paletteColors)
  if not indexedData then
    return false, tostring(mapErr or "Could not map PNG colors through palette")
  end
  
  -- Calculate how many tiles we need
  local tilesWide = math.floor(width / 8)
  local tilesHigh = math.floor(height / 8)
  
  -- Validate that we have enough space in the bank
  local maxTiles = 512  -- Each CHR bank has 512 tiles (0-511)
  local bankBytes = appEditState.chrBanksBytes[bankIdx]
  
  -- Calculate starting tile index based on startCol, startRow
  -- The visual position in the window maps to a tile index based on order mode
  local bankCols = win.cols or 16
  local visualPos = startRow * bankCols + startCol
  
  -- Map visual position to actual tile index based on order mode
  orderMode = orderMode or "normal"
  local startTileIndex
  if orderMode == "normal" then
    startTileIndex = visualPos
  else
    -- 8x16 mode: reverse the mapping used in bank_view_controller
    local row = math.floor(visualPos / bankCols)
    local col = visualPos % bankCols
    local pair = math.floor(row / 2)
    local isOdd = (row % 2 == 1)
    startTileIndex = pair * 32 + col * 2 + (isOdd and 1 or 0)
  end
  
  if startTileIndex >= maxTiles then
    return false, string.format("Starting position (%d, %d) is out of bank bounds", startCol, startRow)
  end
  
  -- Note: We validate each tile position individually during the import loop
  -- since visual positions may not map to sequential tile indices in 8x16 mode
  
  -- Convert image to tiles and write to bank
  -- Calculate tile indices for each position, accounting for order mode
  local tilesWritten = 0
  local trackUndo = undoRedo
    and undoRedo.startPaintEvent
    and undoRedo.recordPixelChange
    and undoRedo.finishPaintEvent
    and (undoRedo.activeEvent == nil)
  if trackUndo then
    undoRedo:startPaintEvent()
  end
  local function finalizeUndo()
    if not trackUndo then return end
    if undoRedo.activeEvent then
      undoRedo:finishPaintEvent()
    end
  end
  local syncChangedTargets = { list = {}, _set = {} }
  
  for tileY = 0, tilesHigh - 1 do
    for tileX = 0, tilesWide - 1 do
      -- Calculate visual position for this tile
      local visualCol = startCol + tileX
      local visualRow = startRow + tileY
      local visualPos = visualRow * bankCols + visualCol
      
      -- Map visual position to actual tile index based on order mode
      local tileIndex
      if orderMode == "normal" then
        tileIndex = visualPos
      else
        -- 8x16 mode: reverse the mapping
        local row = math.floor(visualPos / bankCols)
        local col = visualPos % bankCols
        local pair = math.floor(row / 2)
        local isOdd = (row % 2 == 1)
        tileIndex = pair * 32 + col * 2 + (isOdd and 1 or 0)
      end
      
      -- Validate tile index is within bounds
      if tileIndex >= maxTiles then
        finalizeUndo()
        return false, string.format("Tile at visual position (%d, %d) maps to out-of-bounds tile index %d", 
          visualCol, visualRow, tileIndex)
      end
      
      -- Extract 8x8 pixel block for this tile
      local tilePixels = {}
      for y = 0, 7 do
        for x = 0, 7 do
          local imgX = tileX * 8 + x
          local imgY = tileY * 8 + y
          local color = indexedData[imgY + 1][imgX + 1] or 0
          tilePixels[y * 8 + x + 1] = color
        end
      end
      
      -- Encode tile to bytes
      local tileBytes = encodeTile(tilePixels)
      local syncTargets = ChrDuplicateSync.getSyncGroup(
        appEditState,
        bankIdx,
        tileIndex,
        ChrDuplicateSync.isEnabledForWindow(app, win)
      )
      if #syncTargets == 0 then
        syncTargets = { { bank = bankIdx, tileIndex = tileIndex } }
      end

      for _, target in ipairs(syncTargets) do
        local tBank = target.bank
        local tTileIndex = target.tileIndex
        local tBankBytes = appEditState.chrBanksBytes and appEditState.chrBanksBytes[tBank]
        if not tBankBytes or tTileIndex == nil then
          goto next_target
        end

        local beforePixels = nil
        if trackUndo then
          local decoded = chr.decodeTile(tBankBytes, tTileIndex)
          if decoded and #decoded == 64 then
            beforePixels = decoded
          end
        end

        -- Write tile bytes to target tile (16 bytes per tile)
        local base = tTileIndex * 16
        for i = 1, 16 do
          tBankBytes[base + i] = tileBytes[i]
        end

        if beforePixels then
          for y = 0, 7 do
            for x = 0, 7 do
              local pixelIndex = y * 8 + x + 1
              local beforeValue = beforePixels[pixelIndex] or 0
              local afterValue = tilePixels[pixelIndex] or 0
              if beforeValue ~= afterValue then
                undoRedo:recordPixelChange(tBank, tTileIndex, x, y, beforeValue, afterValue)
              end
            end
          end
        end

        -- Update tile in pool if it exists
        local tilesPool = appEditState.tilesPool[tBank]
        if tilesPool and tilesPool[tTileIndex] then
          tilesPool[tTileIndex]:loadFromCHR(tBankBytes, tTileIndex)
        end

        -- Record edits for this tile
        if edits then
          local GameArtController = require("controllers.game_art.game_art_controller")
          for y = 0, 7 do
            for x = 0, 7 do
              local pixelIndex = y * 8 + x + 1
              local color = tilePixels[pixelIndex]
              GameArtController.recordEdit(edits, tBank, tTileIndex, x, y, color)
            end
          end
        end

        do
          local keyId = string.format("%d:%d", tBank, tTileIndex)
          if not syncChangedTargets._set[keyId] then
            syncChangedTargets._set[keyId] = true
            syncChangedTargets.list[#syncChangedTargets.list + 1] = { bank = tBank, tileIndex = tTileIndex }
          end
        end

        ::next_target::
      end
      
      tilesWritten = tilesWritten + 1
    end
  end

  if appEditState then
    if #syncChangedTargets.list > 0 then
      ChrDuplicateSync.updateTiles(appEditState, syncChangedTargets.list)
    else
      ChrDuplicateSync.reindexBank(appEditState, bankIdx)
    end
  end

  if #syncChangedTargets.list > 0 then
    for _, target in ipairs(syncChangedTargets.list) do
      BankCanvasSupport.invalidateTile(app, target.bank, target.tileIndex)
    end
  else
    BankCanvasSupport.invalidateBank(app, bankIdx)
  end
  finalizeUndo()

  return true, string.format("Imported %d tiles (%dx%d) starting at tile (%d, %d)", 
    tilesWritten, tilesWide, tilesHigh, startCol, startRow)
end

return M
