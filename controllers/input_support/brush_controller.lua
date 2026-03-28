-- brush_controller.lua
-- Brush tools: single pixel brush, flood fill, and future brush tools

local chr = require("chr")
local BankCanvasSupport = require("controllers.chr.bank_canvas_support")
local GameArtController = require("controllers.game_art.game_art_controller")
local DebugController = require("controllers.dev.debug_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")

local M = {}

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

----------------------------------------------------------------
-- Brush patterns
----------------------------------------------------------------

-- Returns a table of {dx, dy} offsets for the brush pattern
-- brushSize: 1 = 1x1, 2 = 3x3, 3 = 5x5, 4 = 7x7
function M.getBrushPattern(brushSize)
  if brushSize == 1 then
    -- 1x1 single pixel
    return {{0, 0}}
  elseif brushSize == 2 then
    -- 3x3 brush
    return {
      {-1,-1}, {0,-1}, {1,-1},

      {-1, 0}, {0, 0}, {1, 0},
      
      {-1, 1}, {0, 1}, {1, 1},
    }
  elseif brushSize == 3 then
    -- 5x5 brush
    return {
               {-1,-2}, {0,-2}, {1,-2},

      {-2,-1}, {-1,-1}, {0,-1}, {1,-1}, {2,-1},

      {-2, 0}, {-1, 0}, {0, 0}, {1, 0}, {2, 0},

      {-2, 1}, {-1, 1}, {0, 1}, {1, 1}, {2, 1},

               {-1, 2}, {0, 2}, {1, 2},
    }
  elseif brushSize == 4 then
    -- 7x7 brush
    return {
                      {-1,-3}, {0,-3}, {1,-3},

             {-2,-2}, {-1,-2}, {0,-2}, {1,-2}, {2,-2},

    {-3,-1}, {-2,-1}, {-1,-1}, {0,-1}, {1,-1}, {2,-1}, {3,-1},

    {-3, 0}, {-2, 0}, {-1, 0}, {0, 0}, {1, 0}, {2, 0}, {3, 0},

    {-3, 1}, {-2, 1}, {-1, 1}, {0, 1}, {1, 1}, {2, 1}, {3, 1},
    
             {-2, 2}, {-1, 2}, {0, 2}, {1, 2}, {2, 2},

                      {-1, 3}, {0, 3}, {1, 3},
    }
  end
  -- Default to 1x1
  return {{0, 0}}
end

----------------------------------------------------------------
-- Helper functions
----------------------------------------------------------------

local function observePerfMs(name, startedAt)
  if not startedAt then
    return
  end
  DebugController.perfObserveMs(name, math.max(0, (nowSeconds() - startedAt) * 1000))
end

local function resolveTileLayerCellItem(win, layerIndex, col, row)
  if not (win and type(col) == "number" and type(row) == "number") then
    return nil
  end

  local stack = win.getStack and win:getStack(col, row, layerIndex) or nil
  local item = stack and stack[#stack] or nil
  if item == nil and win.getVirtualTileHandle then
    item = win:getVirtualTileHandle(col, row, layerIndex)
  elseif item == nil and win.get then
    item = win:get(col, row, layerIndex)
  end

  if item and win.materializeTileHandle then
    item = win:materializeTileHandle(item, layerIndex)
  end

  return item
end

local function updatePaletteSelection(app, colorIndex)
  -- Update active palette window's selection when picking color
  local wm = app.wm
  if wm then
    local windows = wm:getWindows()
    for _, win in ipairs(windows) do
      if win.isPalette and win.activePalette then
        -- Move selection to the picked color index
        if win.rows == 1 and win.cols == 4 and colorIndex >= 0 and colorIndex < 4 then
          win:setSelected(colorIndex, 0)
        end
        break
      end
    end
  end
end

----------------------------------------------------------------
-- Duplicate sync helpers
----------------------------------------------------------------

local function getSyncTargets(app, bankIdx, tileIndex, sourceWin)
  local state = app and app.appEditState
  if not state or not state.chrBanksBytes or not state.chrBanksBytes[bankIdx] then
    return {}
  end

  local enabled = ChrDuplicateSync.isEnabledForWindow(app, sourceWin)
  return ChrDuplicateSync.getSyncGroup(state, bankIdx, tileIndex, enabled)
end

local function makePixelWriteBatch(app, color)
  return {
    app = app,
    color = color,
    syncTargetsBySource = {},
    writesByKey = {},
    writeList = {},
    sourceTilesByKey = {},
    sourceTileCount = 0,
    duplicateTargetCount = 0,
  }
end

local function sourceKey(bankIdx, tileIndex)
  return string.format("%d:%d", bankIdx, tileIndex)
end

local function pixelKey(bankIdx, tileIndex, tx, ty)
  return string.format("%d:%d:%d:%d", bankIdx, tileIndex, tx, ty)
end

local function getBatchSyncTargets(batch, bankIdx, tileIndex, sourceWin)
  local key = sourceKey(bankIdx, tileIndex)
  if not batch.sourceTilesByKey[key] then
    batch.sourceTilesByKey[key] = true
    batch.sourceTileCount = batch.sourceTileCount + 1
  end

  local targets = batch.syncTargetsBySource[key]
  if targets ~= nil then
    return targets
  end

  local startedAt = nowSeconds()
  targets = getSyncTargets(batch.app, bankIdx, tileIndex, sourceWin)
  batch.syncTargetsBySource[key] = targets
  observePerfMs("chr_paint_duplicate_sync_ms", startedAt)
  return targets
end

local function stagePixelWriteToTargets(batch, targets, tx, ty, color, beforeValue)
  if not targets or #targets == 0 then
    return false
  end

  local staged = false
  for _, target in ipairs(targets) do
    batch.duplicateTargetCount = batch.duplicateTargetCount + 1
    local key = pixelKey(target.bank, target.tileIndex, tx, ty)
    local write = batch.writesByKey[key]
    if not write then
      write = {
        bank = target.bank,
        tileIndex = target.tileIndex,
        tx = tx,
        ty = ty,
        before = beforeValue or 0,
        after = color,
      }
      batch.writesByKey[key] = write
      batch.writeList[#batch.writeList + 1] = write
      staged = true
    else
      write.after = color
      if write.before == nil then
        write.before = beforeValue or 0
      end
      staged = true
    end
  end

  return staged
end

local function stageSourcePixelWrite(batch, bankIdx, tileIndex, tx, ty, beforeValue, sourceWin)
  local targets = getBatchSyncTargets(batch, bankIdx, tileIndex, sourceWin)
  return stagePixelWriteToTargets(batch, targets, tx, ty, batch.color, beforeValue)
end

local function commitPixelWriteBatch(batch)
  if not batch then return false end

  local app = batch.app
  local state = app and app.appEditState
  if not state or not state.chrBanksBytes then return false end
  if #batch.writeList == 0 then return false end

  local tilesPool = state.tilesPool or {}
  local undoRedo = app.undoRedo
  local touchedTiles = {}
  local applied = false
  local undoMs = 0
  local applyStartedAt = nowSeconds()

  for _, write in ipairs(batch.writeList) do
    local bankBytes = state.chrBanksBytes[write.bank]
    if bankBytes then
      local tileRef = tilesPool[write.bank] and tilesPool[write.bank][write.tileIndex] or nil
      if undoRedo and undoRedo.activeEvent then
        local undoStartedAt = nowSeconds()
        undoRedo:recordPixelChange(write.bank, write.tileIndex, write.tx, write.ty, write.before or 0, write.after)
        undoMs = undoMs + math.max(0, (nowSeconds() - undoStartedAt) * 1000)
      end

      chr.setTilePixel(bankBytes, write.tileIndex, write.tx, write.ty, write.after)
      if tileRef and tileRef.edit then
        tileRef:edit(write.tx, write.ty, write.after)
      end
      if app.edits then
        GameArtController.recordEdit(app.edits, write.bank, write.tileIndex, write.tx, write.ty, write.after)
      end
      touchedTiles[sourceKey(write.bank, write.tileIndex)] = write
      applied = true
    end
  end

  observePerfMs("chr_paint_apply_ms", applyStartedAt)
  DebugController.perfObserveMs("chr_paint_undo_ms", undoMs)
  DebugController.perfIncrement("chr_paint_duplicate_targets", batch.duplicateTargetCount)
  DebugController.perfIncrement("chr_paint_source_tiles", batch.sourceTileCount)
  DebugController.perfIncrement("chr_paint_written_pixels", #batch.writeList)

  local invalidationCount = 0
  for _, write in pairs(touchedTiles) do
    BankCanvasSupport.invalidateTile(app, write.bank, write.tileIndex)
    invalidationCount = invalidationCount + 1
  end
  DebugController.perfIncrement("chr_paint_invalidate_count", invalidationCount)
  DebugController.perfIncrement("chr_paint_target_tiles", invalidationCount)

  return applied
end

local function applyPixelToTargets(app, targets, tx, ty, color, beforeValue)
  local batch = makePixelWriteBatch(app, color)
  if not stagePixelWriteToTargets(batch, targets, tx, ty, color, beforeValue) then
    return false
  end
  return commitPixelWriteBatch(batch)
end

----------------------------------------------------------------
-- Single pixel brush - sprite layers
----------------------------------------------------------------

local function paintSpriteLayerPixel(app, win, layer, px, py, pickOnly)
  px = math.floor(px or 0)
  py = math.floor(py or 0)
  local mode    = layer.mode or "8x8"
  local hTile   = 8
  local wTile   = 8
  local hSprite = (mode == "8x16") and 16 or 8

  local originX = layer.originX or 0
  local originY = layer.originY or 0
  local NES_W   = 256
  local NES_H   = 256

  if not layer.items then return false end

  for idx = #layer.items, 1, -1 do
    local s = layer.items[idx]

    local worldX = s.worldX or s.baseX or s.x or 0
    local worldY = s.worldY or s.baseY or s.y or 0

    local sx = (originX + worldX) % NES_W
    local sy = (originY + worldY) % NES_H

    if px >= sx and px < sx + wTile and
       py >= sy and py < sy + hSprite then

      local localX = px - sx
      local localY = py - sy

      -- Apply mirroring transformation to coordinates
      local mirrorX = s.mirrorX or false
      local mirrorY = s.mirrorY or false
      
      -- Remap coordinates based on mirror state
      if mirrorX then
        localX = wTile - 1 - localX  -- Mirror horizontally
      end
      
      -- For vertical mirroring, handle 8x16 specially
      local tileIndex
      local tileRef
      local tyOnTile
      
      if mode == "8x16" then
        if mirrorY then
          -- Vertical mirroring: swap top and bottom
          if localY >= 8 then
            -- Was bottom, now top
            tileIndex = s.tileBelow or s.tile + 1
            tileRef   = s.botRef
            tyOnTile  = 15 - localY  -- Mirror Y within bottom tile
          else
            -- Was top, now bottom
            tileIndex = s.tile
            tileRef   = s.topRef
            tyOnTile  = 7 - localY  -- Mirror Y within top tile
          end
        else
          -- Normal 8x16
          if localY >= 8 then
            tileIndex = s.tileBelow or s.tile + 1
            tileRef   = s.botRef
            tyOnTile  = localY - 8
          else
            tileIndex = s.tile
            tileRef   = s.topRef
            tyOnTile  = localY
          end
        end
      else
        -- 8x8 sprite
        tileIndex = s.tile
        tileRef   = s.topRef
        if mirrorY then
          tyOnTile = 7 - localY  -- Mirror Y
        else
          tyOnTile = localY
        end
      end

      if not (tileIndex and tileRef) then return false end

      local bankIdx = s.bank
      if not bankIdx then return false end

      local tx = math.floor(localX)
      local ty = math.floor(tyOnTile)
      if tx < 0 or ty < 0 or tx >= 8 or ty >= 8 then return false end

      if pickOnly then
        local colorIndex = tileRef:getPixel(tx, ty) or 0
        app.currentColor = colorIndex
        app:setStatus(("Picked color %d"):format(colorIndex))
        updatePaletteSelection(app, colorIndex)
        return true
      end

      -- Validate bank exists before trying to set pixel
      if not app.appEditState or not app.appEditState.chrBanksBytes or not app.appEditState.chrBanksBytes[bankIdx] then
        app:setStatus("Cannot paint: CHR bank not loaded")
        return false
      end
      
      local color = app.currentColor
      local targets = getSyncTargets(app, bankIdx, tileIndex, win)
      local applied = applyPixelToTargets(app, targets, tx, ty, color, tileRef:getPixel(tx, ty) or 0)
      return applied
    end
  end

  return false
end

----------------------------------------------------------------
-- Single pixel brush - tile layers
----------------------------------------------------------------

local function paintTileLayerCellPixel(app, win, layer, col, row, tx, ty, pickOnly, batch)
  tx = math.floor(tx or 0)
  ty = math.floor(ty or 0)
  local layerIndex = win:getActiveLayerIndex()
  local item = resolveTileLayerCellItem(win, layerIndex, col, row)
  if not item then return false end

  if tx < 0 or ty < 0 or tx >= 8 or ty >= 8 then return false end

  if pickOnly then
    local colorIndex = item:getPixel(tx, ty) or 0
    app.currentColor = colorIndex
    app:setStatus(("Picked color %d"):format(colorIndex))
    updatePaletteSelection(app, colorIndex)
    return true
  end

  local bankIdx   = item._bankIndex
  local tileIndex = item.index

  if (bankIdx == nil or tileIndex == nil) and item.edit then
    local beforeValue = item:getPixel(tx, ty) or 0
    local color = app.currentColor or 0
    if beforeValue == color then
      return false
    end

    if app.undoRedo and app.undoRedo.activeEvent then
      app.undoRedo:recordDirectPixelChange(item, tx, ty, beforeValue, color)
    end
    item:edit(tx, ty, color)
    return true
  end
  
  -- Validate bank exists before trying to set pixel
  if not app.appEditState or not app.appEditState.chrBanksBytes or not app.appEditState.chrBanksBytes[bankIdx] then
    app:setStatus("Cannot paint: CHR bank not loaded")
    return false
  end
  
  -- Get before value for undo/redo tracking
  local beforeValue = item:getPixel(tx, ty) or 0
  if batch then
    return stageSourcePixelWrite(batch, bankIdx, tileIndex, tx, ty, beforeValue, win)
  end

  local color = app.currentColor
  local targets = getSyncTargets(app, bankIdx, tileIndex, win)
  return applyPixelToTargets(app, targets, tx, ty, color, beforeValue)
end

local function paintTileLayerPixel(app, win, layer, px, py, pickOnly)
  px = math.floor(px or 0)
  py = math.floor(py or 0)
  local cw, ch = win.cellW, win.cellH
  local col = math.floor(px / cw)
  local row = math.floor(py / ch)
  local tx = math.floor(px - (col * cw))
  local ty = math.floor(py - (row * ch))
  return paintTileLayerCellPixel(app, win, layer, col, row, tx, ty, pickOnly, nil)
end

----------------------------------------------------------------
-- Brush pattern painting helpers
----------------------------------------------------------------

-- Calculate tile coordinates for a pixel with spillover handling
-- Returns: targetCol, targetRow, targetLx, targetLy (or nil if out of bounds)
local function calculateTileCoordsForPixel(col, row, lx, ly, dx, dy)
  lx = math.floor(lx or 0)
  ly = math.floor(ly or 0)
  local targetLx = lx + dx
  local targetLy = ly + dy
  local targetCol = col
  local targetRow = row
  
  -- Adjust column if pixel spills over horizontally
  while targetLx < 0 do
    targetCol = targetCol - 1
    targetLx = targetLx + 8
  end
  while targetLx >= 8 do
    targetCol = targetCol + 1
    targetLx = targetLx - 8
  end
  
  -- Adjust row if pixel spills over vertically
  while targetLy < 0 do
    targetRow = targetRow - 1
    targetLy = targetLy + 8
  end
  while targetLy >= 8 do
    targetRow = targetRow + 1
    targetLy = targetLy - 8
  end
  
  -- Return coordinates (validated by caller)
  return targetCol, targetRow, targetLx, targetLy
end

-- Paint brush pattern on tile layers
-- Checks each pixel in the pattern and paints on any tile it hits
local function paintBrushPatternOnTileLayer(app, win, layer, pattern, col, row, lx, ly, pickOnly)
  local layerIndex = win:getActiveLayerIndex()
  local batch = pickOnly and nil or makePixelWriteBatch(app, app.currentColor)
  local painted = false
  
  for _, offset in ipairs(pattern) do
    local dx, dy = offset[1], offset[2]
    local targetCol, targetRow, targetLx, targetLy = calculateTileCoordsForPixel(col, row, lx, ly, dx, dy)
    
    -- Skip if coordinates are out of bounds
    if targetLx < 0 or targetLx >= 8 or targetLy < 0 or targetLy >= 8 then
      goto continue
    end
    
    if paintTileLayerCellPixel(app, win, layer, targetCol, targetRow, targetLx, targetLy, pickOnly, batch) then
      painted = true
      -- For pickOnly, we only want to pick once (from center)
      if pickOnly then break end
    end
    
    ::continue::
  end

  if not pickOnly and painted then
    local committed = false
    if batch and #batch.writeList > 0 then
      committed = commitPixelWriteBatch(batch)
    end
    return committed or painted
  end
  
  return painted
end

-- Paint brush pattern on sprite layers
-- Checks each pixel in the pattern against all sprites to see which ones it hits
local function paintBrushPatternOnSpriteLayer(app, win, layer, pattern, col, row, lx, ly, pickOnly)
  local cw, ch = win.cellW, win.cellH
  local basePx = col * cw + math.floor(lx or 0)
  local basePy = row * ch + math.floor(ly or 0)
  local painted = false
  
  local mode = layer.mode or "8x8"
  local wTile = 8
  local hSprite = (mode == "8x16") and 16 or 8
  local originX = layer.originX or 0
  local originY = layer.originY or 0
  local NES_W, NES_H = 256, 256
  
  -- For each pixel in the brush pattern, check all sprites to see if it hits any
  for _, offset in ipairs(pattern) do
    local dx, dy = offset[1], offset[2]
    local patternPx = basePx + dx
    local patternPy = basePy + dy
    
    -- Check all sprites to see if this pattern pixel hits any of them
    for idx = #layer.items, 1, -1 do
      local s = layer.items[idx]
      if s.removed == true then goto sprite_continue end
      
      local worldX = s.worldX or s.baseX or s.x or 0
      local worldY = s.worldY or s.baseY or s.y or 0
      
      local sx = (originX + worldX) % NES_W
      local sy = (originY + worldY) % NES_H
      
      -- Check if this pattern pixel is within sprite bounds
      if patternPx >= sx and patternPx < sx + wTile and 
         patternPy >= sy and patternPy < sy + hSprite then
        
        -- Paint this pixel on the sprite
        if paintSpriteLayerPixel(app, win, layer, patternPx, patternPy, pickOnly) then
          painted = true
          -- For pickOnly, we only want to pick once (from center)
          if pickOnly then break end
        end
      end
      
      ::sprite_continue::
    end
    
    if pickOnly and painted then break end
  end
  
  return painted
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- Paint using brush pattern (handles tile spillover and multi-sprite hits)
-- win: window
-- col, row: grid coordinates
-- lx, ly: local pixel coordinates within the tile (0-7)
-- brushSize: 1 = 1x1, 2 = 3x3, 3 = 5x5, 4 = 7x7
-- pickOnly: if true, pick color instead of painting
local function paintWithBrushPattern(app, win, col, row, lx, ly, brushSize, pickOnly)
  pickOnly = pickOnly or false
  brushSize = brushSize or 1
  
  local pattern = M.getBrushPattern(brushSize)
  local layerIndex = win:getActiveLayerIndex()
  local L = win.layers and win.layers[layerIndex]
  
  if not L then return false end
  
  -- Delegate to specialized functions based on layer type
  if L.kind == "sprite" then
    return paintBrushPatternOnSpriteLayer(app, win, L, pattern, col, row, lx, ly, pickOnly)
  else
    return paintBrushPatternOnTileLayer(app, win, L, pattern, col, row, lx, ly, pickOnly)
  end
end

-- Paint a single pixel (brush tool)
-- win: window
-- col, row: grid coordinates
-- lx, ly: local pixel coordinates within the tile (0-7)
-- pickOnly: if true, pick color instead of painting
function M.paintPixel(app, win, col, row, lx, ly, pickOnly)
  local startedAt = (not pickOnly) and nowSeconds() or nil
  pickOnly = pickOnly or false
  local brushSize = app.brushSize or 1
  
  -- Color picking should always sample the center pixel, regardless of brush size.
  local ok = false
  if pickOnly or brushSize == 1 then
    local cw, ch = win.cellW, win.cellH
    local px = col * cw + lx
    local py = row * ch + ly
    
    local layerIndex = win:getActiveLayerIndex()
    local L = win.layers and win.layers[layerIndex]
    
    if not L then return false end
    
    if L.kind == "sprite" then
      ok = paintSpriteLayerPixel(app, win, L, px, py, pickOnly)
    else
      ok = paintTileLayerPixel(app, win, L, px, py, pickOnly)
    end
  else
    ok = paintWithBrushPattern(app, win, col, row, lx, ly, brushSize, pickOnly)
  end

  if not pickOnly then
    observePerfMs("chr_paint_pixel_ms", startedAt)
  end

  return ok
end

-- Flood fill helper - works on a single tile item
local function floodFillTileItem(app, item, tx, ty, targetColor, fillColor, sourceWin)
  -- Ensure coordinates are within tile bounds
  if tx < 0 or ty < 0 or tx >= 8 or ty >= 8 then 
    DebugController.log("warning", "BRUSH", "Flood fill: coordinates out of tile bounds")
    return false 
  end
  
  -- Get target and fill colors
  local target = targetColor
  if target == nil then
    target = item:getPixel(tx, ty) or 0
  end
  
  local fill = fillColor
  if fill == nil then
    fill = app.currentColor or 0
  end
  
  -- If target and fill are the same, nothing to do
  if target == fill then 
    DebugController.log("info", "BRUSH", "Flood fill: target and fill colors are the same")
    return false 
  end

  if (item._bankIndex == nil or item.index == nil) and item.edit then
    local visited = {}
    local painted = 0
    local queue = {{tx, ty}}

    local function getKey(x, y)
      return y * 8 + x
    end

    local function isValid(x, y)
      return x >= 0 and x < 8 and y >= 0 and y < 8
    end

    while #queue > 0 do
      local current = table.remove(queue, 1)
      local x, y = current[1], current[2]
      local key = getKey(x, y)

      if visited[key] then goto continue end
      if not isValid(x, y) then goto continue end

      local pixelColor = item:getPixel(x, y)
      if pixelColor ~= target then goto continue end

      visited[key] = true
      if app.undoRedo and app.undoRedo.activeEvent then
        app.undoRedo:recordDirectPixelChange(item, x, y, target, fill)
      end
      item:edit(x, y, fill)
      painted = painted + 1

      table.insert(queue, {x - 1, y})
      table.insert(queue, {x + 1, y})
      table.insert(queue, {x, y - 1})
      table.insert(queue, {x, y + 1})

      ::continue::
    end

    return painted > 0
  end
  
  -- Get bank index and tile index
  local bankIdx = item._bankIndex
  local tileIndex = item.index
  
  if not bankIdx or not tileIndex then
    DebugController.log("warning", "BRUSH", "Flood fill: item missing bank or tile index")
    return false
  end
  
  -- Verify CHR bank exists
  if not app.appEditState or not app.appEditState.chrBanksBytes or not app.appEditState.chrBanksBytes[bankIdx] then
    DebugController.log("warning", "BRUSH", "Flood fill: CHR bank %d not found", bankIdx or -1)
    return false
  end
  
  -- Flood fill algorithm (breadth-first search within the 8x8 tile)
  local visited = {}
  local painted = 0
  local queue = {{tx, ty}}
  local targets = getSyncTargets(app, bankIdx, tileIndex, sourceWin)
  
  local function getKey(x, y)
    return y * 8 + x
  end
  
  local function isValid(x, y)
    return x >= 0 and x < 8 and y >= 0 and y < 8
  end
  
  while #queue > 0 do
    local current = table.remove(queue, 1)
    local x, y = current[1], current[2]
    local key = getKey(x, y)
    
    if visited[key] then goto continue end
    if not isValid(x, y) then goto continue end
    
    local pixelColor = item:getPixel(x, y)
    if pixelColor ~= target then goto continue end
    
    visited[key] = true
    
    -- Paint this pixel
    local applied = applyPixelToTargets(app, targets, x, y, fill, target)
    if applied then
      painted = painted + 1
    end
    
    -- Add neighbors to queue
    table.insert(queue, {x - 1, y})  -- left
    table.insert(queue, {x + 1, y})  -- right
    table.insert(queue, {x, y - 1})  -- up
    table.insert(queue, {x, y + 1})  -- down
    
    ::continue::
  end
  
  return painted > 0
end

-- Flood fill helper for sprite layers (bankIdx and tileIndex passed separately)
local function floodFillTileItemForSprite(app, item, bankIdx, tileIndex, tx, ty, targetColor, fillColor, sourceWin)
  if not item then return false end
  
  -- Get target color
  local target = targetColor
  if target == nil then
    target = item:getPixel(tx, ty) or 0
  end
  
  local fill = fillColor
  if fill == nil then
    fill = app.currentColor or 0
  end
  
  -- If target and fill are the same, nothing to do
  if target == fill then 
    DebugController.log("info", "BRUSH", "Flood fill: target and fill colors are the same")
    return false 
  end
  
  -- Verify CHR bank exists
  if not app.appEditState or not app.appEditState.chrBanksBytes or not app.appEditState.chrBanksBytes[bankIdx] then
    DebugController.log("warning", "BRUSH", "Flood fill: CHR bank %d not found", bankIdx or -1)
    return false
  end
  
  -- Flood fill algorithm (breadth-first search within the 8x8 tile)
  local visited = {}
  local painted = 0
  local queue = {{tx, ty}}
  local targets = getSyncTargets(app, bankIdx, tileIndex, sourceWin)
  
  local function getKey(x, y)
    return y * 8 + x
  end
  
  local function isValid(x, y)
    return x >= 0 and x < 8 and y >= 0 and y < 8
  end
  
  while #queue > 0 do
    local current = table.remove(queue, 1)
    local x, y = current[1], current[2]
    local key = getKey(x, y)
    
    if visited[key] then goto continue end
    if not isValid(x, y) then goto continue end
    
    local pixelColor = item:getPixel(x, y)
    if pixelColor ~= target then goto continue end
    
    visited[key] = true
    
    -- Paint this pixel
    local applied = applyPixelToTargets(app, targets, x, y, fill, target)
    if applied then
      painted = painted + 1
    end
    
    -- Add neighbors to queue
    table.insert(queue, {x - 1, y})  -- left
    table.insert(queue, {x + 1, y})  -- right
    table.insert(queue, {x, y - 1})  -- up
    table.insert(queue, {x, y + 1})  -- down
    
    ::continue::
  end
  
  return painted > 0
end

-- Flood fill a single tile (8x8)
-- win: window
-- col, row: grid coordinates of the tile (for tile layers) or ignored (for sprite layers)
-- lx, ly: local pixel coordinates within the tile (0-7) where to start the fill
-- targetColor: color to replace (if nil, will use color at starting pixel)
-- fillColor: color to fill with (if nil, will use app.currentColor)
function M.floodFillTile(app, win, col, row, lx, ly, targetColor, fillColor)
  local undo = app and app.undoRedo
  local startedUndo = false
  local function finalize(success)
    if startedUndo and undo then
      if success then
        undo:finishPaintEvent()
      else
        undo:cancelPaintEvent()
      end
    end
    return success
  end

  if undo and not undo.activeEvent then
    undo:startPaintEvent()
    startedUndo = true
  end

  local layerIndex = win:getActiveLayerIndex()
  local L = win.layers and win.layers[layerIndex]
  
  if not L then 
    DebugController.log("warning", "BRUSH", "Flood fill: no layer found")
    return finalize(false)
  end
  
  -- Handle sprite layers
  if L.kind == "sprite" then
    local cw, ch = win.cellW, win.cellH
    local px = col * cw + lx
    local py = row * ch + ly
    
    -- Find which sprite and tile we're clicking on (similar to paintSpriteLayerPixel)
    local mode = L.mode or "8x8"
    local hSprite = (mode == "8x16") and 16 or 8
    local originX = L.originX or 0
    local originY = L.originY or 0
    local NES_W = 256
    local NES_H = 256
    
    if not L.items then 
      DebugController.log("warning", "BRUSH", "Flood fill: sprite layer has no items")
      return false 
    end
    
    -- Check sprites from back to front (same as painting)
    for idx = #L.items, 1, -1 do
      local s = L.items[idx]
      local worldX = s.worldX or s.baseX or s.x or 0
      local worldY = s.worldY or s.baseY or s.y or 0
      
      local sx = (originX + worldX) % NES_W
      local sy = (originY + worldY) % NES_H
      
      if px >= sx and px < sx + 8 and py >= sy and py < sy + hSprite then
        local localX = px - sx
        local localY = py - sy
        
        -- Apply mirroring transformation to coordinates (same as paintSpriteLayerPixel)
        local mirrorX = s.mirrorX or false
        local mirrorY = s.mirrorY or false
        local wTile = 8
        
        if mirrorX then
          localX = wTile - 1 - localX  -- Mirror horizontally
        end
        
        local bankIdx = s.bank
        if not bankIdx then return false end
        
        local tileIndex
        local tileRef
        local tyOnTile
        
        -- Handle vertical mirroring with coordinate remapping
        if mode == "8x16" then
          if mirrorY then
            -- Vertical mirroring: swap top and bottom
            if localY >= 8 then
              -- Was bottom, now top
              tileIndex = s.tileBelow or s.tile + 1
              tileRef   = s.botRef
              tyOnTile  = 15 - localY  -- Mirror Y within bottom tile
            else
              -- Was top, now bottom
              tileIndex = s.tile
              tileRef   = s.topRef
              tyOnTile  = 7 - localY  -- Mirror Y within top tile
            end
          else
            -- Normal 8x16
            if localY >= 8 then
              tileIndex = s.tileBelow or s.tile + 1
              tileRef   = s.botRef
              tyOnTile  = localY - 8
            else
              tileIndex = s.tile
              tileRef   = s.topRef
              tyOnTile  = localY
            end
          end
        else
          -- 8x8 sprite
          tileIndex = s.tile
          tileRef   = s.topRef
          if mirrorY then
            tyOnTile = 7 - localY  -- Mirror Y
          else
            tyOnTile = localY
          end
        end
        
        if not (tileIndex and tileRef) then return false end
        
        local tx = math.floor(localX)
        local ty = math.floor(tyOnTile)
        if tx < 0 or ty < 0 or tx >= 8 or ty >= 8 then goto continue end

        -- Validate bank exists before trying to flood fill
        if not app.appEditState or not app.appEditState.chrBanksBytes or not app.appEditState.chrBanksBytes[bankIdx] then
          DebugController.log("warning", "BRUSH", "Flood fill: CHR bank %d not loaded", bankIdx or -1)
          return false
        end

        -- Perform flood fill on this sprite tile
        -- For sprites, we need to pass bankIdx and tileIndex since tileRef doesn't have _bankIndex
        return finalize(floodFillTileItemForSprite(app, tileRef, bankIdx, tileIndex, tx, ty, targetColor, fillColor, win))
      end
      ::continue::
    end
    
    DebugController.log("warning", "BRUSH", "Flood fill: no sprite found at position")
    return finalize(false)
  end
  
  -- Handle tile layers
  
  -- Validate grid coordinates
  if col < 0 or col >= win.cols or row < 0 or row >= win.rows then
    DebugController.log("warning", "BRUSH", "Flood fill: invalid grid coordinates")
    return finalize(false)
  end
  
  -- Get the tile item directly from grid coordinates
  local item = win:get(col, row, layerIndex)
  if not item then 
    DebugController.log("warning", "BRUSH", "Flood fill: no item at grid position")
    return finalize(false)
  end
  
  -- Get local tile coordinates
  local tx = math.floor(lx)
  local ty = math.floor(ly)
  
  -- Perform flood fill on this tile item using the helper function
  return finalize(floodFillTileItem(app, item, tx, ty, targetColor, fillColor, win))
end

return M
