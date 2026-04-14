local SpriteController = require("controllers.sprite.sprite_controller")
local MultiSelectController = require("controllers.input_support.multi_select_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local function setStatusFromEnv(env, text)
  local ctx = env and env.ctx or nil
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

local function copyTilePixels(tile)
  if not (tile and tile.pixels and #tile.pixels == 64) then return nil end
  local out = {}
  for i = 1, 64 do
    out[i] = tile.pixels[i] or 0
  end
  return out
end

local function resolveChrTileItem(win, item, layerIndex)
  if item == nil then
    return nil
  end
  if win and win.materializeTileHandle then
    local resolved = win:materializeTileHandle(item, layerIndex)
    if resolved ~= nil then
      return resolved
    end
  end
  return item
end

local function normalizeSwapRowForOddEven(win, row)
  row = math.floor(tonumber(row) or 0)
  if win and win.orderMode == "oddEven" then
    return row - (row % 2)
  end
  return row
end

local function buildChrSwapUndoContext(win, layerIndex, c1, r1, c2, r2)
  if not (win and win.get and type(layerIndex) == "number") then
    return nil
  end

  local rowA = normalizeSwapRowForOddEven(win, r1)
  local rowB = normalizeSwapRowForOddEven(win, r2)
  local pairs = {}

  local function addPair(colA, rowA0, colB, rowB0)
    local tileA = win:get(colA, rowA0, layerIndex)
    local tileB = win:get(colB, rowB0, layerIndex)
    if not (tileA and tileB) then return false end
    if type(tileA.index) ~= "number" or type(tileB.index) ~= "number" then return false end

    local beforeA = copyTilePixels(tileA)
    local beforeB = copyTilePixels(tileB)
    if not (beforeA and beforeB) then return false end

    pairs[#pairs + 1] = {
      tileA = tileA,
      tileB = tileB,
      beforeA = beforeA,
      beforeB = beforeB,
    }
    return true
  end

  if not addPair(c1, rowA, c2, rowB) then
    return nil
  end

  if win.orderMode == "oddEven" then
    if not addPair(c1, rowA + 1, c2, rowB + 1) then
      return nil
    end
  end

  return pairs
end

local function recordChrSwapAsPaintEvent(undoRedo, bankIdx, swapPairs)
  if not (
    undoRedo
    and undoRedo.startPaintEvent
    and undoRedo.recordPixelChange
    and undoRedo.finishPaintEvent
    and undoRedo.cancelPaintEvent
  ) then
    return false
  end
  if type(bankIdx) ~= "number" then
    return false
  end
  if not (swapPairs and #swapPairs > 0) then
    return false
  end
  if undoRedo.activeEvent ~= nil then
    return false
  end

  undoRedo:startPaintEvent()
  local changed = false

  local function recordTileDiff(tile, beforePixels)
    local afterPixels = tile and tile.pixels
    if not (afterPixels and #afterPixels == 64 and type(tile.index) == "number") then
      return
    end
    for i = 1, 64 do
      local beforeValue = beforePixels[i] or 0
      local afterValue = afterPixels[i] or 0
      if beforeValue ~= afterValue then
        local px = (i - 1) % 8
        local py = math.floor((i - 1) / 8)
        undoRedo:recordPixelChange(bankIdx, tile.index, px, py, beforeValue, afterValue)
        changed = true
      end
    end
  end

  for _, pair in ipairs(swapPairs) do
    recordTileDiff(pair.tileA, pair.beforeA)
    recordTileDiff(pair.tileB, pair.beforeB)
  end

  if not changed then
    undoRedo:cancelPaintEvent()
    return false
  end

  return undoRedo:finishPaintEvent() and true or false
end

local function makeTileDragRecorder(undoRedo, mode)
  if not (undoRedo and undoRedo.addDragEvent) then return nil end

  local byKey = {}
  local order = {}

  local function keyFor(win, li, col, row)
    return tostring(win) .. "|" .. tostring(li) .. "|" .. tostring(col) .. "|" .. tostring(row)
  end

  local function stageCell(win, layerIndex, col, row, beforeOverride)
    if not (win and layerIndex) then return end
    if type(col) ~= "number" or type(row) ~= "number" then return end

    local key = keyFor(win, layerIndex, col, row)
    if byKey[key] then return end

    local before = beforeOverride
    if before == nil and win.get then
      before = win:get(col, row, layerIndex)
    end

    local rec = {
      win = win,
      layerIndex = layerIndex,
      col = col,
      row = row,
      before = before,
    }
    byKey[key] = rec
    order[#order + 1] = rec
  end

  local function commit()
    local changes = {}

    for _, rec in ipairs(order) do
      local after = nil
      if rec.win and rec.win.get then
        after = rec.win:get(rec.col, rec.row, rec.layerIndex)
      end
      if rec.before ~= after then
        changes[#changes + 1] = {
          win = rec.win,
          layerIndex = rec.layerIndex,
          col = rec.col,
          row = rec.row,
          before = rec.before,
          after = after,
        }
      end
    end

    if #changes > 0 then
      undoRedo:addDragEvent({
        type = "tile_drag",
        mode = mode or "move",
        changes = changes,
      })
    end
  end

  return {
    stageCell = stageCell,
    commit = commit,
  }
end

local function canDropOnWindow(dst)
  if not dst then return false end
  if WindowCaps.isChrLike(dst) then return false end
  return true
end

local function getSpriteLayerGridSize(dst, layer)
  local cw = dst and dst.cellW or 8
  local ch = dst and dst.cellH or 8
  local cols = layer.cols or dst.cols or layer.visibleCols or dst.visibleCols
    or math.floor(SpriteController.SPRITE_X_RANGE / cw)
  local rows = layer.rows or dst.rows or layer.visibleRows or dst.visibleRows
    or math.floor(SpriteController.SPRITE_Y_RANGE / ch)
  return cols, rows
end

local function getEntryBounds(entries)
  local minOffsetCol, maxOffsetCol = 0, 0
  local minOffsetRow, maxOffsetRow = 0, 0

  for i, entry in ipairs(entries or {}) do
    local offsetCol = entry.offsetCol or 0
    local offsetRow = entry.offsetRow or 0
    if i == 1 then
      minOffsetCol, maxOffsetCol = offsetCol, offsetCol
      minOffsetRow, maxOffsetRow = offsetRow, offsetRow
    else
      if offsetCol < minOffsetCol then minOffsetCol = offsetCol end
      if offsetCol > maxOffsetCol then maxOffsetCol = offsetCol end
      if offsetRow < minOffsetRow then minOffsetRow = offsetRow end
      if offsetRow > maxOffsetRow then maxOffsetRow = offsetRow end
    end
  end

  return minOffsetCol, maxOffsetCol, minOffsetRow, maxOffsetRow
end

local function getEntriesSpan(entries)
  local minOffsetCol, maxOffsetCol, minOffsetRow, maxOffsetRow = getEntryBounds(entries)
  return (maxOffsetCol - minOffsetCol) + 1, (maxOffsetRow - minOffsetRow) + 1
end

local function getGroupSpriteFootprintRows(entries, layer)
  local spanRows = select(2, getEntriesSpan(entries))
  local mode = layer and layer.mode or "8x8"
  local spriteRows = (mode == "8x16") and 2 or 1
  return spanRows + spriteRows - 1, spriteRows
end

local function getTooltipTextForReason(reason)
  if reason == "out_of_bounds" then
    return "out of bounds"
  end
  if reason == "not_enough_area" then
    return "not enough area to drop"
  end
  if reason == "chr_8x8_multi_into_sprite_8x16" then
    return "8x8 tile payload cannot drop into 8x16 sprite layer"
  end
  return nil
end

local function getHoveredAnchorCell(dst, x, y)
  if not dst then return nil, nil end
  if dst.isInContentArea and not dst:isInContentArea(x, y) then
    return nil, nil
  end

  local ok, col, row = dst:toGridCoords(x, y)
  if ok and type(col) == "number" and type(row) == "number" then
    return col, row
  end
  return nil, nil
end

local function getHoveredAnchorPixel(dst, x, y)
  if not dst then return nil, nil end
  if dst.isInContentArea and not dst:isInContentArea(x, y) then
    return nil, nil
  end

  local z = (dst.getZoomLevel and dst:getZoomLevel()) or dst.zoom or 1
  local cw = dst.cellW or 8
  local ch = dst.cellH or 8
  local scol = dst.scrollCol or 0
  local srow = dst.scrollRow or 0
  local cx = (x - dst.x) / z
  local cy = (y - dst.y) / z

  return math.floor((cx + scol * cw) + 0.5), math.floor((cy + srow * ch) + 0.5)
end

local function getChrGroupEntriesForDestination(group, layer)
  if not (group and layer) then return nil end
  if layer.kind ~= "sprite" then
    return group.entries
  end
  if (layer.mode or "8x8") ~= "8x16" then
    return group.entries
  end
  if group.sourceSelectionMode == "8x16" and group.spriteEntries and #group.spriteEntries > 0 then
    return group.spriteEntries
  end
  return group.entries
end

local function isBlockedChr8x8ToSprite8x16(group, layer)
  return layer
    and layer.kind == "sprite"
    and (layer.mode or "8x8") == "8x16"
    and group
    and group.sourceSelectionMode ~= "8x16"
end

local function buildChrGroupPlacements(dst, entries, anchorCol, anchorRow, anchorPixelX, anchorPixelY)
  local cw = dst.cellW or 8
  local ch = dst.cellH or 8
  local placements = {}

  for _, entry in ipairs(entries or {}) do
    local placement = {
      item = entry.item,
      bottomItem = entry.bottomItem,
      offsetCol = entry.offsetCol or 0,
      offsetRow = entry.offsetRow or 0,
    }
    if type(anchorCol) == "number" and type(anchorRow) == "number" then
      placement.col = anchorCol + placement.offsetCol
      placement.row = anchorRow + placement.offsetRow
    end
    if type(anchorPixelX) == "number" and type(anchorPixelY) == "number" then
      placement.pixelX = anchorPixelX + placement.offsetCol * cw
      placement.pixelY = anchorPixelY + placement.offsetRow * ch
    end
    placements[#placements + 1] = placement
  end

  return placements
end

local function getChrGroupDropState(env, x, y, wm)
  local drag = env and env.drag
  if not (drag and drag.active and drag.tileGroup and WindowCaps.isChrLike(drag.srcWin)) then
    return nil
  end

  local dst = wm and wm:windowAt(x, y) or nil
  if not dst or dst.isPalette or not canDropOnWindow(dst) then
    return nil
  end
  if not WindowCaps.isStaticOrAnimationArt(dst) then
    return nil
  end

  local dstLayer = (dst.getActiveLayerIndex and dst:getActiveLayerIndex()) or drag.srcLayer or 1
  local layer = dst.layers and dst.layers[dstLayer] or nil
  if not (layer and (layer.kind == "tile" or layer.kind == "sprite")) then
    return nil
  end

  if layer.kind == "sprite" and env.isSpriteLayerDropBlocked and env.isSpriteLayerDropBlocked(dst, layer, drag.srcWin) then
    return nil
  end

  local cols, rows
  if layer.kind == "sprite" then
    cols, rows = getSpriteLayerGridSize(dst, layer)
  else
    cols, rows = dst.cols or 0, dst.rows or 0
  end
  if cols <= 0 or rows <= 0 then
    return nil
  end

  local state = {
    dst = dst,
    dstLayer = dstLayer,
    srcWin = drag.srcWin,
    srcLayer = drag.srcLayer,
    layer = layer,
    anchorCol = nil,
    anchorRow = nil,
    anchorPixelX = nil,
    anchorPixelY = nil,
    placements = nil,
    footprintCols = 0,
    footprintRows = 0,
    spriteRows = 1,
    valid = false,
    reason = nil,
  }

  if isBlockedChr8x8ToSprite8x16(drag.tileGroup, layer) then
    state.reason = "chr_8x8_multi_into_sprite_8x16"
    return state
  end

  local placementEntries = getChrGroupEntriesForDestination(drag.tileGroup, layer)
  if not placementEntries or #placementEntries == 0 then
    return state
  end

  local spanCols, spanRows = getEntriesSpan(placementEntries)
  local minOffsetCol, maxOffsetCol, minOffsetRow, maxOffsetRow = getEntryBounds(placementEntries)

  local footprintRows, spriteRows = spanRows, 1
  if layer.kind == "sprite" then
    footprintRows, spriteRows = getGroupSpriteFootprintRows(placementEntries, layer)
  end

  state.footprintCols = spanCols
  state.footprintRows = footprintRows
  state.spriteRows = spriteRows

  if spanCols > cols or footprintRows > rows then
    state.reason = "not_enough_area"
    return state
  end

  if layer.kind == "sprite" then
    local anchorPixelX, anchorPixelY = getHoveredAnchorPixel(dst, x, y)
    state.anchorPixelX = anchorPixelX
    state.anchorPixelY = anchorPixelY
    if type(anchorPixelX) ~= "number" or type(anchorPixelY) ~= "number" then
      return state
    end

    local cw = dst.cellW or 8
    local ch = dst.cellH or 8
    local spriteW = cw
    local spriteH = spriteRows * ch
    local originX = layer.originX or 0
    local originY = layer.originY or 0
    local minWorldX = -originX
    local minWorldY = -originY
    local maxWorldX = cols * cw - spriteW - originX
    local maxWorldY = rows * ch - spriteH - originY

    state.placements = buildChrGroupPlacements(dst, placementEntries, nil, nil, anchorPixelX, anchorPixelY)
    for _, placement in ipairs(state.placements or {}) do
      if placement.pixelX < minWorldX
        or placement.pixelX > maxWorldX
        or placement.pixelY < minWorldY
        or placement.pixelY > maxWorldY
      then
        state.reason = "out_of_bounds"
        return state
      end
    end

    state.valid = true
    return state
  end

  local anchorCol, anchorRow = getHoveredAnchorCell(dst, x, y)
  state.anchorCol = anchorCol
  state.anchorRow = anchorRow
  if type(anchorCol) ~= "number" or type(anchorRow) ~= "number" then
    return state
  end

  local minCol = anchorCol + minOffsetCol
  local maxCol = anchorCol + maxOffsetCol
  local minRow = anchorRow + minOffsetRow
  local maxRow = anchorRow + maxOffsetRow + spriteRows - 1
  if minCol < 0 or maxCol >= cols or minRow < 0 or maxRow >= rows then
    state.reason = "out_of_bounds"
    state.placements = buildChrGroupPlacements(dst, placementEntries, anchorCol, anchorRow)
    return state
  end

  state.valid = true
  state.placements = buildChrGroupPlacements(dst, placementEntries, anchorCol, anchorRow)
  return state
end

local function applyChrGroupToSpriteLayer(state, tilesPool)
  if not (state and state.valid and state.layer and state.layer.kind == "sprite" and tilesPool) then
    return nil
  end

  local itemIndices = {}
  for _, placement in ipairs(state.placements or {}) do
    local item = resolveChrTileItem(state.srcWin, placement.item, state.srcLayer)
    local itemIndex = SpriteController.addSpriteToLayer(
      state.layer,
      item,
      placement.pixelX,
      placement.pixelY,
      tilesPool
    )
    if itemIndex then
      itemIndices[#itemIndices + 1] = itemIndex
    end
  end

  if #itemIndices == 0 then
    return nil
  end

  SpriteController.setSpriteSelection(state.layer, itemIndices)
  state.layer.selectedSpriteIndex = itemIndices[1]
  return itemIndices
end

local function getPpuNametableByte(win, col, row)
  if not (WindowCaps.isPpuFrame(win) and win.nametableBytes) then
    return nil, false
  end

  local cols = tonumber(win.cols) or 0
  local rows = tonumber(win.rows) or 0
  if cols <= 0 or rows <= 0 then
    return nil, false
  end
  if col < 0 or col >= cols or row < 0 or row >= rows then
    return nil, false
  end

  local idx = (row * cols + col) + 1
  if idx < 1 or idx > #win.nametableBytes then
    return nil, false
  end

  local byte = win.nametableBytes[idx]
  if type(byte) ~= "number" then
    return nil, false
  end

  return byte, true
end

local function setPpuNametableByte(win, col, row, byteVal, app, layerIdx)
  if not (WindowCaps.isPpuFrame(win) and win.setNametableByteAt) then
    return false
  end

  local tilesPool = app and app.appEditState and app.appEditState.tilesPool
  win:setNametableByteAt(col, row, byteVal, tilesPool, layerIdx)
  return true
end

local function getTransparentPpuByte(win, layerIdx)
  return 0x00
end

local function handleSameCellDrop(dst, col, row, drag, wm, dstLayer)
  if drag.srcWin == dst and col == drag.srcCol and row == drag.srcRow then
    if dst.setSelected then
      wm:setFocus(dst)
      dst:setSelected(col, row, dstLayer)
    end
    return true
  end
  return false
end

local function handleChrBankCopy(dst, col, row, drag, dstLayer)
  if WindowCaps.isChrLike(drag.srcWin) then
    if dst.set then
      dst:set(col, row, resolveChrTileItem(drag.srcWin, drag.item, drag.srcLayer), dstLayer)
    end
    return true
  end
  return false
end

local function handleChrBankCopyToSpriteLayer(env, dst, x, y, drag, dstLayer)
  if not (WindowCaps.isChrLike(drag.srcWin) and drag.item) then
    return false
  end

  if not (dst and dst.layers and dstLayer) then
    return false
  end

  local layer = dst.layers[dstLayer]
  if not (layer and layer.kind == "sprite") then
    return false
  end

  if (layer.mode or "8x8") == "8x16" and ((drag.srcWin and drag.srcWin.orderMode) ~= "oddEven") then
    setStatusFromEnv(env, "8x8 tile payload cannot drop into 8x16 sprite layer")
    return false
  end

  if env.isSpriteLayerDropBlocked and env.isSpriteLayerDropBlocked(dst, layer, drag.srcWin) then
    setStatusFromEnv(env, "Cannot drop CHR tiles onto sprite layers in this window")
    return false
  end

  local z = (dst.getZoomLevel and dst:getZoomLevel()) or dst.zoom or 1
  local cw = dst.cellW or 8
  local ch = dst.cellH or 8
  local scol = dst.scrollCol or 0
  local srow = dst.scrollRow or 0

  local cx = (x - dst.x) / z
  local cy = (y - dst.y) / z
  local pixelX = cx + scol * cw
  local pixelY = cy + srow * ch

  local cols, rows = getSpriteLayerGridSize(dst, layer)
  local spriteRows = ((layer.mode or "8x8") == "8x16") and 2 or 1
  local spriteW = cw
  local spriteH = spriteRows * ch
  local originX = layer.originX or 0
  local originY = layer.originY or 0
  local minWorldX = -originX
  local minWorldY = -originY
  local maxWorldX = cols * cw - spriteW - originX
  local maxWorldY = rows * ch - spriteH - originY

  if pixelX < minWorldX or pixelX > maxWorldX or pixelY < minWorldY or pixelY > maxWorldY then
    setStatusFromEnv(env, "out of bounds")
    return false
  end

  local app = env.ctx and env.ctx.app
  local tilesPool = app and app.appEditState and app.appEditState.tilesPool
  if not tilesPool then
    return false
  end

  local item = resolveChrTileItem(drag.srcWin, drag.item, drag.srcLayer)
  local itemIndex = SpriteController.addSpriteToLayer(layer, item, pixelX, pixelY, tilesPool)
  if itemIndex then
    SpriteController.setSpriteSelection(layer, { itemIndex })
    layer.selectedSpriteIndex = itemIndex
    return true
  end

  return false
end

local function handleTileMove(src, dst, col, row, drag, dstLayer)
  if not drag.srcWin or WindowCaps.isChrLike(drag.srcWin) then return false end

  if src == dst then
    local srcLayer = drag.srcLayer or (src.getActiveLayerIndex and src:getActiveLayerIndex()) or 1
    local L = src:getLayer(srcLayer)
    if L then
      local srcIdx = (drag.srcRow * src.cols + drag.srcCol) + 1
      L.items[srcIdx] = nil
    end
  else
    if src.removeAt then
      src:removeAt(drag.srcCol, drag.srcRow, drag.srcLayer, drag.srcStackIndex)
    end
  end

  if dst.set then
    dst:set(col, row, drag.item, dstLayer)
  end
  return true
end

local function handleTileSwap(src, dst, col, row, drag, dstLayer, dstItem)
  if not drag.srcWin or WindowCaps.isChrLike(drag.srcWin) then return false end

  local srcLayer = drag.srcLayer or (src.getActiveLayerIndex and src:getActiveLayerIndex()) or 1
  local srcCol = drag.srcCol
  local srcRow = drag.srcRow
  local srcItem = drag.item

  if src and src.set then
    src:set(srcCol, srcRow, dstItem, srcLayer)
  end
  if dst and dst.set then
    dst:set(col, row, srcItem, dstLayer)
  end
  return true
end

function M.handleTileDrop(env, x, y, wm)
  local drag = env and env.drag
  if not (drag and drag.active and drag.item) then return false end

  local src = drag.srcWin
  local srcIsChr = WindowCaps.isChrLike(src)
  local dst = wm:windowAt(x, y)
  local app = env.ctx and env.ctx.app
  local undoRedo = app and app.undoRedo
  local recorder = makeTileDragRecorder(undoRedo, ((drag.copyMode or srcIsChr) and "copy") or "move")

  if src and dst and src ~= dst and (not srcIsChr) then
    env.clearDragState(false)
    return true
  end

  if src and dst and src == dst and WindowCaps.isChrLike(dst) and dst.swapCells then
    local ok, col, row = dst:toGridCoords(x, y)
    if ok and type(col) == "number" and type(row) == "number" then
      local dstLayer = dst:getActiveLayerIndex() or drag.srcLayer or 1
      local edits = app and app.edits
      local bankIdx = dst.currentBank
      local swapUndoContext = buildChrSwapUndoContext(dst, dstLayer, drag.srcCol, drag.srcRow, col, row)
      dst:swapCells(drag.srcCol, drag.srcRow, col, row, edits, bankIdx, app and app.appEditState)
      local recordedSwapPaint = recordChrSwapAsPaintEvent(undoRedo, bankIdx, swapUndoContext)
      if (not recordedSwapPaint) and env.markUnsaved then
        env.markUnsaved("tile_move")
      end
      if dst.setSelected then
        wm:setFocus(dst)
        dst:setSelected(col, row, dstLayer)
      end
      env.clearDragState(true)
      return true
    end
  end

  if srcIsChr and drag.tileGroup then
    local chrGroupState = getChrGroupDropState(env, x, y, wm)
    if not (chrGroupState and chrGroupState.valid) then
      local reasonText = chrGroupState and getTooltipTextForReason(chrGroupState.reason)
      if reasonText and env.ctx and env.ctx.app and env.ctx.app.setStatus then
        setStatusFromEnv(env, reasonText)
      end
      env.clearDragState(false)
      return true
    end

    dst = chrGroupState.dst
    local dstLayer = chrGroupState.dstLayer
    local layer = chrGroupState.layer

    if layer.kind == "sprite" then
      local tilesPool = app and app.appEditState and app.appEditState.tilesPool
      local itemIndices = applyChrGroupToSpriteLayer(chrGroupState, tilesPool)
      if itemIndices and #itemIndices > 0 then
        wm:setFocus(dst)
        env.clearDragState(true)
        return true
      end
      env.clearDragState(false)
      return true
    end

    if recorder then
      for _, placement in ipairs(chrGroupState.placements or {}) do
        recorder.stageCell(dst, dstLayer, placement.col, placement.row)
      end
    end

    local applyResult = MultiSelectController.applyTileDragGroup(dst, dstLayer, drag.tileGroup, chrGroupState.anchorCol, chrGroupState.anchorRow, {
      copyMode = true,
      srcWin = src,
      srcLayer = drag.srcLayer,
      tilesPool = app and app.appEditState and app.appEditState.tilesPool,
    })
    if applyResult and applyResult.count and applyResult.count > 0 and dst.setSelected and applyResult.firstCol then
      wm:setFocus(dst)
      dst:setSelected(applyResult.firstCol, applyResult.firstRow, dstLayer)
    end
    if recorder then recorder.commit() end
    env.clearDragState(true)
    return true
  end

  if not dst or dst.isPalette then
    env.clearDragState(false)
    return true
  end

  local dstLayer = dst:getActiveLayerIndex() or drag.srcLayer or 1

  if not canDropOnWindow(dst) then
    env.clearDragState(false)
    return true
  end

  local layer = dst.layers and dst.layers[dstLayer]
  local isSpriteLayer = layer and layer.kind == "sprite"
  if isSpriteLayer and (WindowCaps.isPpuFrame(dst) or WindowCaps.isOamAnimation(dst)) then
    setStatusFromEnv(env, "Cannot drop items onto sprite layers in this window")
    env.clearDragState(false)
    return true
  end

  if isSpriteLayer and srcIsChr then
    if handleChrBankCopyToSpriteLayer(env, dst, x, y, drag, dstLayer) then
      wm:setFocus(dst)
      env.clearDragState(true)
      return true
    end
    env.clearDragState(false)
    return true
  end

  local ok, col, row = dst:toGridCoords(x, y)
  if not ok or type(col) ~= "number" or type(row) ~= "number" then
    col, row = MultiSelectController.getGridCoordsClamped(dst, x, y)
  end
  if type(col) ~= "number" or type(row) ~= "number" then
    env.clearDragState(false)
    return true
  end

  if drag.tileGroup then
    if not (layer and layer.kind == "tile") then
      env.clearDragState(false)
      return true
    end

    local anchorCol, anchorRow = MultiSelectController.clampTileDropAnchor(dst, drag.tileGroup, col, row)
    if type(anchorCol) ~= "number" or type(anchorRow) ~= "number" then
      env.clearDragState(false)
      return true
    end

    if recorder then
      local srcLayer = drag.srcLayer or 1
      for _, entry in ipairs(drag.tileGroup.entries or {}) do
        recorder.stageCell(src, srcLayer, entry.srcCol, entry.srcRow, entry.item)
      end
      for _, entry in ipairs(drag.tileGroup.entries or {}) do
        local dstCol = anchorCol + (entry.offsetCol or 0)
        local dstRow = anchorRow + (entry.offsetRow or 0)
        recorder.stageCell(dst, dstLayer, dstCol, dstRow)
      end
    end

    local applyResult = MultiSelectController.applyTileDragGroup(dst, dstLayer, drag.tileGroup, anchorCol, anchorRow, {
      copyMode = drag.copyMode,
      srcWin = src,
      srcLayer = drag.srcLayer,
      tilesPool = app and app.appEditState and app.appEditState.tilesPool,
    })
    if applyResult and applyResult.count and applyResult.count > 0 and dst.setSelected and applyResult.firstCol then
      wm:setFocus(dst)
      dst:setSelected(applyResult.firstCol, applyResult.firstRow, dstLayer)
    end
    if recorder then recorder.commit() end
    env.clearDragState(true)
    return true
  end

  local dstItem = dst.get and dst:get(col, row, dstLayer)

  if handleSameCellDrop(dst, col, row, drag, wm, dstLayer) then
    env.clearDragState(false)
    return true
  end

  if WindowCaps.isPpuFrame(src) and WindowCaps.isPpuFrame(dst) then
    local srcLayer = drag.srcLayer or (src.getActiveLayerIndex and src:getActiveLayerIndex()) or 1

    -- Same-window PPU tile move should use the native swap path so we only
    -- recompress/write once (avoids transient intermediate budget states).
    if not drag.copyMode and src == dst and src.swapCells then
      if recorder then
        recorder.stageCell(src, srcLayer, drag.srcCol, drag.srcRow)
        recorder.stageCell(dst, dstLayer, col, row)
      end

      src:swapCells(drag.srcCol, drag.srcRow, col, row)
      if env.markUnsaved then env.markUnsaved("tile_move") end

      if dst.setSelected then
        wm:setFocus(dst)
        dst:setSelected(col, row, dstLayer)
      end
      if recorder then recorder.commit() end

      env.clearDragState(true)
      return true
    end

    local srcByte, srcValid = getPpuNametableByte(src, drag.srcCol, drag.srcRow)
    local dstByte, dstValid = getPpuNametableByte(dst, col, row)

    if not (srcValid and dstValid) then
      env.clearDragState(false)
      return true
    end

    if recorder then
      if not drag.copyMode then
        recorder.stageCell(src, srcLayer, drag.srcCol, drag.srcRow)
      end
      recorder.stageCell(dst, dstLayer, col, row)
    end

    if drag.copyMode then
      setPpuNametableByte(dst, col, row, srcByte, app, dstLayer)
    else
      setPpuNametableByte(dst, col, row, srcByte, app, dstLayer)
      if src == dst then
        setPpuNametableByte(src, drag.srcCol, drag.srcRow, dstByte, app, srcLayer)
      else
        local transparentByte = getTransparentPpuByte(src, srcLayer)
        setPpuNametableByte(src, drag.srcCol, drag.srcRow, transparentByte, app, srcLayer)
      end
      if env.markUnsaved then env.markUnsaved("tile_move") end
    end

    if dst.setSelected then
      wm:setFocus(dst)
      dst:setSelected(col, row, dstLayer)
    end
    if recorder then recorder.commit() end

    env.clearDragState(true)
    return true
  end

  if srcIsChr then
    if recorder then recorder.stageCell(dst, dstLayer, col, row) end
    handleChrBankCopy(dst, col, row, drag, dstLayer)
  else
    if drag.copyMode then
      if recorder then recorder.stageCell(dst, dstLayer, col, row) end
      if dst.set then
        dst:set(col, row, drag.item, dstLayer)
      end
    else
      if not dstItem then
        if recorder then
          local srcLayer = drag.srcLayer or (src and src.getActiveLayerIndex and src:getActiveLayerIndex()) or 1
          recorder.stageCell(src, srcLayer, drag.srcCol, drag.srcRow, drag.item)
          recorder.stageCell(dst, dstLayer, col, row)
        end
        handleTileMove(src, dst, col, row, drag, dstLayer)
      else
        if recorder then
          local srcLayer = drag.srcLayer or (src and src.getActiveLayerIndex and src:getActiveLayerIndex()) or 1
          recorder.stageCell(src, srcLayer, drag.srcCol, drag.srcRow, drag.item)
          recorder.stageCell(dst, dstLayer, col, row)
        end
        handleTileSwap(src, dst, col, row, drag, dstLayer, dstItem)
      end
    end
  end

  if dst.setSelected then
    wm:setFocus(dst)
    dst:setSelected(col, row, dstLayer)
  end
  if recorder then recorder.commit() end

  env.clearDragState(true)
  return true
end

function M.getHoverDropState(env, x, y, wm)
  return getChrGroupDropState(env, x, y, wm)
end

function M.getHoverTooltipCandidate(env, x, y, wm)
  local state = getChrGroupDropState(env, x, y, wm)
  local text = state and getTooltipTextForReason(state.reason) or nil
  if not text then
    return nil
  end
  return {
    text = text,
    immediate = true,
    key = table.concat({
      text,
      tostring(state and state.dst),
      tostring(state and state.dstLayer),
      tostring(state and state.anchorCol),
      tostring(state and state.anchorRow),
    }, "|"),
  }
end

return M
