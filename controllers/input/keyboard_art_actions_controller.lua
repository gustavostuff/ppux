local chr = require("chr")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local DebugController = require("controllers.dev.debug_controller")
local TileSpriteOffsetController = require("controllers.input_support.tile_sprite_offset_controller")
local MultiSelectController = require("controllers.input_support.multi_select_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local SpriteStateSnapshot = require("controllers.sprite.sprite_state_snapshot")

local M = {}

local function setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

local function isChr8x16Mode(win)
  return WindowCaps.isChrLike(win) and win.orderMode == "oddEven"
end

local function materializeFocusTile(focus, item, layerIndex)
  if item == nil then
    return nil
  end
  if focus and focus.materializeTileHandle then
    local resolved = focus:materializeTileHandle(item, layerIndex)
    if resolved ~= nil then
      return resolved
    end
  end
  return item
end

local function rotateTileWithSync(tile, direction, app, state, tilesPool, sourceWin, paintUndo)
  if not (tile and tile.pixels and type(tile.pixels) == "table" and #tile.pixels == 64) then
    return false, nil
  end

  local bankIdx = tile._bankIndex
  local targets = ChrDuplicateSync.getSyncGroup(state, bankIdx, tile.index, ChrDuplicateSync.isEnabledForWindow(app, sourceWin))
  if #targets == 0 then
    targets = {
      { bank = bankIdx, tileIndex = tile.index },
    }
  end

  local rotatedThisTile = false
  for _, target in ipairs(targets) do
    local tRef = nil
    if tilesPool[target.bank] and tilesPool[target.bank][target.tileIndex] then
      tRef = tilesPool[target.bank][target.tileIndex]
    elseif target.bank == bankIdx and target.tileIndex == tile.index then
      tRef = tile
    end

    if tRef then
      local snap = nil
      if paintUndo and tRef.pixels and type(tRef.pixels) == "table" and type(tRef._bankIndex) == "number" and type(tRef.index) == "number" then
        snap = {}
        for i = 1, 64 do
          snap[i] = tRef.pixels[i] or 0
        end
      end

      local rotated = false
      if tRef.rotatePaletteValues then
        rotated = tRef:rotatePaletteValues(direction)
      elseif tRef.pixels and type(tRef.pixels) == "table" and #tRef.pixels == 64 then
        local dirNorm = (direction > 0) and 1 or -1
        for i = 1, 64 do
          local oldValue = tRef.pixels[i] or 0
          local newValue = (dirNorm == 1) and ((oldValue + 1) % 4) or ((oldValue - 1 + 4) % 4)
          tRef.pixels[i] = newValue
        end
        if tRef.refreshImage then
          tRef:refreshImage()
        end
        if tRef._bankBytesRef and type(tRef.index) == "number" then
          for y = 0, 7 do
            for x = 0, 7 do
              local idx = y * 8 + x + 1
              local pixelValue = tRef.pixels[idx]
              if pixelValue then
                chr.setTilePixel(tRef._bankBytesRef, tRef.index, x, y, pixelValue)
              end
            end
          end
        end
        rotated = true
      end

      if snap and paintUndo and type(tRef._bankIndex) == "number" and type(tRef.index) == "number" then
        for iy = 0, 7 do
          for ix = 0, 7 do
            local i = iy * 8 + ix + 1
            local beforeV = snap[i] or 0
            local afterV = (tRef.pixels and tRef.pixels[i]) or 0
            if beforeV ~= afterV then
              paintUndo:recordPixelChange(tRef._bankIndex, tRef.index, ix, iy, beforeV, afterV)
            end
          end
        end
      end

      rotatedThisTile = rotatedThisTile or rotated
    end
  end

  if rotatedThisTile and state then
    ChrDuplicateSync.updateTiles(state, targets)
  end

  return rotatedThisTile, targets
end

function M.handlePixelOffset(ctx, utils, key, focus)
  return TileSpriteOffsetController.handleKey(key, focus, ctx, utils)
end

function M.handleTileRotation(ctx, utils, key, focus)
  if not utils.shiftDown() then return false end
  if key ~= "left" and key ~= "right" then return false end
  if not focus then return false end

  local col, row, layerIndex = focus:getSelected()
  if not (layerIndex or (col and row)) then return false end
  layerIndex = layerIndex or (focus.getActiveLayerIndex and focus:getActiveLayerIndex()) or 1

  local direction = (key == "right") and 1 or -1
  local success = false
  local rotatedUnitsCount = 0

  local app = ctx.app
  local state = app and app.appEditState
  local tilesPool = state and state.tilesPool or {}
  local undoRedo = app and app.undoRedo
  if undoRedo then
    undoRedo:startPaintEvent()
  end

  if isChr8x16Mode(focus) then
    local pairs = MultiSelectController.getSelectedChr8x16Pairs(focus, layerIndex, col, row)
    if not pairs or #pairs == 0 then return false end

    for _, pair in ipairs(pairs) do
      local rotatedThisUnit = false
      for _, tile in ipairs({
        materializeFocusTile(focus, pair.topItem, layerIndex),
        materializeFocusTile(focus, pair.bottomItem, layerIndex),
      }) do
        local rotated = rotateTileWithSync(tile, direction, app, state, tilesPool, focus, undoRedo)
        rotatedThisUnit = rotatedThisUnit or rotated
        success = success or rotated
      end
      if rotatedThisUnit then
        rotatedUnitsCount = rotatedUnitsCount + 1
      end
    end
  else
    local cells = nil
    if WindowCaps.isChrLike(focus) then
      cells = MultiSelectController.getSelectedTileCells(focus, layerIndex, col, row)
    end
    if not cells or #cells == 0 then
      if not (col and row) then return false end
      cells = { { col = col, row = row } }
    end

    for _, cell in ipairs(cells) do
      local tile = focus:get(cell.col, cell.row, layerIndex)
      local rotated = rotateTileWithSync(tile, direction, app, state, tilesPool, focus, undoRedo)
      if rotated then
        success = true
        rotatedUnitsCount = rotatedUnitsCount + 1
      end
    end
  end

  if success then
    if undoRedo then
      undoRedo:finishPaintEvent()
    end
    local dirText = (direction == 1) and "right" or "left"
    if rotatedUnitsCount > 1 then
      local unitLabel = isChr8x16Mode(focus) and "items" or "tiles"
      setStatus(ctx, string.format("Rotated tile palette values %s on %d %s", dirText, rotatedUnitsCount, unitLabel))
    else
      setStatus(ctx, string.format("Rotated tile palette values %s", dirText))
    end
    return true
  end

  if undoRedo then
    undoRedo:cancelPaintEvent()
  end
  return false
end

function M.handlePaletteNumberAssignment(ctx, key, focus, appCoreRef)
  appCoreRef = appCoreRef or {}
  local appEditState = appCoreRef.appEditState

  if key ~= "1" and key ~= "2" and key ~= "3" and key ~= "4" then return false end
  if ctx.getMode() == "edit" then return false end

  local w = focus
  if not w then return false end
  if not (w.layers and w.getActiveLayerIndex) then return false end

  local paletteNum = tonumber(key)
  if not paletteNum or paletteNum < 1 or paletteNum > 4 then return false end

  local li = w:getActiveLayerIndex()
  local layer = w.layers[li]
  if not layer then return false end

  if layer.kind == "sprite" then
    local SpriteController = require("controllers.sprite.sprite_controller")
    local selected = SpriteController and SpriteController.getSelectedSpriteIndices(layer) or {}
    if (#selected == 0) and layer.selectedSpriteIndex then
      selected = { layer.selectedSpriteIndex }
    end

    local items = layer.items or {}
    local updated = 0
    local newRom = appEditState and appEditState.romRaw
    local undoRedo = ctx and ctx.app and ctx.app.undoRedo
    local trackedSprites = {}
    local beforeBySprite = {}

    for _, idx in ipairs(selected) do
      local sprite = items[idx]
      if sprite and sprite.removed ~= true then
        trackedSprites[#trackedSprites + 1] = sprite
        beforeBySprite[sprite] = SpriteStateSnapshot.captureSpriteState(sprite)

        sprite.paletteNumber = paletteNum

        local curAttr = tonumber(sprite.attr) or 0
        curAttr = math.floor(curAttr)
        local palBits = (paletteNum - 1) % 4
        local mergedAttr = (curAttr - (curAttr % 4)) + palBits

        local function setBit(byte, bitIndex, on)
          local pow = 2 ^ bitIndex
          local cur = math.floor(byte / pow) % 2
          if on and cur == 0 then
            byte = byte + pow
          elseif (not on) and cur == 1 then
            byte = byte - pow
          end
          return byte
        end

        if sprite.mirrorX ~= nil then
          mergedAttr = setBit(mergedAttr, 6, sprite.mirrorX and true or false)
        end
        if sprite.mirrorY ~= nil then
          mergedAttr = setBit(mergedAttr, 7, sprite.mirrorY and true or false)
        end

        sprite.attr = mergedAttr

        if SpriteController and SpriteController.syncSharedOAMSpriteState then
          SpriteController.syncSharedOAMSpriteState(w, sprite, {
            syncPosition = false,
            syncVisual = true,
            syncAttr = true,
          })
        end

        if sprite.startAddr and newRom then
          DebugController.log("info", "SPRITE_UPDATE", "Updating sprite palette to addr: %02X", sprite.startAddr + 2)
          DebugController.log("info", "SPRITE_UPDATE", "Attr byte: %02X", mergedAttr)
          newRom = chr.writeByteToAddress(newRom, sprite.startAddr + 2, mergedAttr)
        end
        updated = updated + 1
      end
    end

    if newRom and appEditState then
      appEditState.romRaw = newRom
    end

    if updated > 0 then
      if undoRedo and undoRedo.addDragEvent and #trackedSprites > 0 then
        local actions = {}
        for _, sprite in ipairs(trackedSprites) do
          local beforeState = beforeBySprite[sprite]
          local afterState = SpriteStateSnapshot.captureSpriteState(sprite)
          if beforeState and afterState and not SpriteStateSnapshot.statesEqual(beforeState, afterState) then
            actions[#actions + 1] = {
              win = w,
              layerIndex = li,
              sprite = sprite,
              before = beforeState,
              after = afterState,
            }
          end
        end
        if #actions > 0 then
          undoRedo:addDragEvent({
            type = "sprite_drag",
            mode = "palette",
            sync = {
              syncPosition = false,
              syncVisual = true,
              syncAttr = true,
            },
            actions = actions,
          })
        end
      end
      local statusMsg = (updated > 1) and string.format("Sprite palettes set to %d", paletteNum)
        or string.format("Sprite palette set to %d", paletteNum)
      setStatus(ctx, statusMsg)
      return true
    end
    return false
  end

  if layer.kind ~= "tile" then
    return false
  end

  local col, row, _ = w:getSelected()
  local selectedCells = MultiSelectController.getSelectedTileCells(w, li, col, row)
  if not selectedCells or #selectedCells == 0 then
    return false
  end

  local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
  local beforeState
  if WindowCaps.isPpuFrame(w) and appCoreRef.snapshotPpuFrameUndoState then
    beforeState = appCoreRef:snapshotPpuFrameUndoState(w, li)
  end

  local cols = w.cols or 32
  local paletteChanges = (not WindowCaps.isPpuFrame(w)) and {} or nil
  local undoRedo = ctx and ctx.app and ctx.app.undoRedo

  local updated = 0
  for _, cell in ipairs(selectedCells) do
    if paletteChanges then
      local idx = cell.row * cols + cell.col
      local beforePal = layer.paletteNumbers and layer.paletteNumbers[idx]
      local success = NametableTilesController.setPaletteNumberForTile(w, layer, cell.col, cell.row, paletteNum)
      if success then
        updated = updated + 1
        paletteChanges[#paletteChanges + 1] = {
          win = w,
          layerIndex = li,
          col = cell.col,
          row = cell.row,
          linearIndex = idx,
          before = beforePal,
          after = paletteNum,
          isPaletteNumber = true,
        }
      end
    else
      local success = NametableTilesController.setPaletteNumberForTile(w, layer, cell.col, cell.row, paletteNum)
      if success then
        updated = updated + 1
      end
    end
  end
  if updated > 0 then
    if beforeState and appCoreRef.pushPpuFrameNametableUndoIfChanged and appCoreRef.snapshotPpuFrameUndoState then
      local afterState = appCoreRef:snapshotPpuFrameUndoState(w, li)
      appCoreRef:pushPpuFrameNametableUndoIfChanged(w, li, beforeState, afterState)
    elseif paletteChanges and #paletteChanges > 0 and undoRedo and undoRedo.addDragEvent then
      undoRedo:addDragEvent({
        type = "tile_drag",
        mode = "palette",
        changes = paletteChanges,
      })
    end
    if updated > 1 then
      setStatus(ctx, string.format("Tile palettes set to %d", paletteNum))
    else
      setStatus(ctx, string.format("Tile palette set to %d", paletteNum))
    end
    return true
  end

  return false
end

return M
