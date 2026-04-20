local M = {}
local WindowCaps = require("controllers.window.window_capabilities")

local SPRITE_X_RANGE = 256
local SPRITE_Y_RANGE = 256

local spriteMarquee = { active = false }
local tileMarquee = { active = false }

local function screenToContent(win, sx, sy)
  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local cw = win.cellW or 8
  local ch = win.cellH or 8
  local scol = win.scrollCol or 0
  local srow = win.scrollRow or 0

  local cx = (sx - win.x) / z
  local cy = (sy - win.y) / z
  return cx + scol * cw, cy + srow * ch
end

local function toGridCoordsClamped(win, sx, sy)
  if not (win and win.cols and win.rows and win.cellW and win.cellH) then
    return nil, nil
  end
  if win.cols <= 0 or win.rows <= 0 then
    return nil, nil
  end

  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local cx = (sx - win.x) / z
  local cy = (sy - win.y) / z
  local col = math.floor(cx / win.cellW) + (win.scrollCol or 0)
  local row = math.floor(cy / win.cellH) + (win.scrollRow or 0)

  if col < 0 then col = 0 end
  if row < 0 then row = 0 end
  if col >= win.cols then col = win.cols - 1 end
  if row >= win.rows then row = win.rows - 1 end

  return col, row
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function getTileInteractionItem(win, col, row, layerIdx)
  if not win then
    return nil
  end
  if win.getVirtualTileHandle then
    local item = win:getVirtualTileHandle(col, row, layerIdx)
    if item ~= nil then
      return item
    end
  end
  if win.get then
    return win:get(col, row, layerIdx)
  end
  return nil
end

local function materializeTileInteractionItem(win, item, layerIdx)
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

local function wrapSpriteContentPosition(origin, world, range)
  return ((origin or 0) + (world or 0)) % range
end

local function getSpriteSelectionSet(layer)
  layer.multiSpriteSelection = layer.multiSpriteSelection or {}
  return layer.multiSpriteSelection
end

local function cloneSelectionSet(sel)
  local out = {}
  if type(sel) ~= "table" then return out end
  for idx, on in pairs(sel) do
    if on then out[idx] = true end
  end
  return out
end

local function cloneSelectionOrder(order)
  local out = {}
  if type(order) ~= "table" then return out end
  for _, idx in ipairs(order) do
    if type(idx) == "number" then
      out[#out + 1] = idx
    end
  end
  return out
end

local function normalizeSpriteSelectionIndices(layer)
  local sel = layer and layer.multiSpriteSelection
  if not sel then return {} end

  local list = {}
  for idx, on in pairs(sel) do
    if on then
      list[#list + 1] = idx
    end
  end
  table.sort(list)
  return list
end

function M.selectSpritesInRect(win, layerIndex, rect, append)
  if not (win and win.layers and layerIndex and rect) then return end
  local layer = win.layers[layerIndex]
  if not (layer and layer.kind == "sprite") then return end

  local cw = win.cellW or 8
  local ch = win.cellH or 8
  local originX = layer.originX or 0
  local originY = layer.originY or 0
  local mode = layer.mode or "8x8"
  local spriteW = cw
  local spriteH = (mode == "8x16") and (2 * ch) or ch

  local x1 = math.min(rect.x1, rect.x2)
  local y1 = math.min(rect.y1, rect.y2)
  local x2 = math.max(rect.x1, rect.x2)
  local y2 = math.max(rect.y1, rect.y2)

  local existingOrder = {}
  if append then
    existingOrder = cloneSelectionOrder(layer.multiSpriteSelectionOrder)
  end

  if not append then
    layer.multiSpriteSelection = nil
    layer.multiSpriteSelectionOrder = nil
    layer.selectedSpriteIndex = nil
  end
  local sel = getSpriteSelectionSet(layer)
  local hitEntries = {}

  for idx, s in ipairs(layer.items or {}) do
    if s and s.removed ~= true then
      local worldX = s.worldX or s.baseX or s.x or 0
      local worldY = s.worldY or s.baseY or s.y or 0
      local sx = wrapSpriteContentPosition(originX, worldX, SPRITE_X_RANGE)
      local sy = wrapSpriteContentPosition(originY, worldY, SPRITE_Y_RANGE)
      local ex = sx + spriteW
      local ey = sy + spriteH
      local overlaps = (sx <= x2 and ex >= x1 and sy <= y2 and ey >= y1)
      if overlaps then
        sel[idx] = true
        hitEntries[#hitEntries + 1] = { idx = idx, sx = sx, sy = sy }
      end
    end
  end

  table.sort(hitEntries, function(a, b)
    if a.sy ~= b.sy then return a.sy < b.sy end
    if a.sx ~= b.sx then return a.sx < b.sx end
    return a.idx < b.idx
  end)

  local list = normalizeSpriteSelectionIndices(layer)
  if #list == 0 then
    layer.multiSpriteSelectionOrder = nil
    layer.selectedSpriteIndex = nil
    return
  end

  local order = {}
  local seen = {}
  if append then
    for _, idx in ipairs(existingOrder) do
      if sel[idx] and not seen[idx] then
        order[#order + 1] = idx
        seen[idx] = true
      end
    end
  end
  for _, hit in ipairs(hitEntries) do
    local idx = hit.idx
    if sel[idx] and not seen[idx] then
      order[#order + 1] = idx
      seen[idx] = true
    end
  end
  for _, idx in ipairs(list) do
    if sel[idx] and not seen[idx] then
      order[#order + 1] = idx
      seen[idx] = true
    end
  end

  layer.multiSpriteSelectionOrder = order
  layer.selectedSpriteIndex = order[1]
end

function M.deleteSpriteSelection(win, layerIndex, undoRedo, opts)
  opts = opts or {}
  if not (win and layerIndex and win.layers) then return nil end
  local layer = win.layers[layerIndex]
  if not (layer and layer.kind == "sprite") then return nil end

  local SpriteController = require("controllers.sprite.sprite_controller")
  local selected
  if type(opts.indices) == "table" and #opts.indices > 0 then
    selected = opts.indices
  else
    selected = SpriteController and SpriteController.getSelectedSpriteIndices(layer) or {}
    if (#selected == 0) and layer.selectedSpriteIndex then
      selected = { layer.selectedSpriteIndex }
    end
  end
  if #selected == 0 then return nil end

  local items = layer.items or {}
  local actions = {}

  if SpriteController and SpriteController.isDragging and SpriteController.isDragging() then
    SpriteController.endDrag()
  end

  for _, spriteIndex in ipairs(selected) do
    local sprite = items[spriteIndex]
    if sprite and sprite.removed ~= true then
      actions[#actions + 1] = {
        win         = win,
        layerIndex  = layerIndex,
        spriteIndex = spriteIndex,
        sprite      = sprite,
        prevRemoved = sprite.removed == true,
      }
    end
  end

  if #actions == 0 then return nil end

  if undoRedo then
    undoRedo:addRemovalEvent({
      type    = "remove_tile",
      subtype = "sprite",
      actions = actions,
    })
  end

  for _, act in ipairs(actions) do
    local sprite = act.sprite
    sprite.removed = true
  end

  if SpriteController and SpriteController.clearSpriteSelection then
    SpriteController.clearSpriteSelection(layer)
  else
    layer.selectedSpriteIndex = nil
    layer.multiSpriteSelection = nil
    layer.multiSpriteSelectionOrder = nil
  end
  layer.hoverSpriteIndex = nil

  local removedCount = #actions
  return {
    count = removedCount,
    status = (removedCount > 1) and string.format("Deleted %d sprites", removedCount) or "Deleted sprite",
  }
end

function M.startSpriteMarquee(win, layerIndex, startX, startY, append)
  local baseSelection = nil
  local baseSelectionOrder = nil
  if append and win and win.layers and layerIndex then
    local layer = win.layers[layerIndex]
    if layer and layer.kind == "sprite" then
      baseSelection = cloneSelectionSet(layer.multiSpriteSelection)
      baseSelectionOrder = cloneSelectionOrder(layer.multiSpriteSelectionOrder)
      if layer.selectedSpriteIndex then
        baseSelection[layer.selectedSpriteIndex] = true
      end
    end
  end

  spriteMarquee = {
    active = true,
    win = win,
    layerIndex = layerIndex,
    startX = startX,
    startY = startY,
    currentX = startX,
    currentY = startY,
    append = append or false,
    baseSelection = baseSelection,
    baseSelectionOrder = baseSelectionOrder,
  }
end

function M.updateSpriteMarquee(x, y)
  if not spriteMarquee.active then return end
  spriteMarquee.currentX = x
  spriteMarquee.currentY = y

  local m = spriteMarquee
  local win = m.win
  local layerIndex = m.layerIndex
  if not (win and win.layers and layerIndex) then return end
  local layer = win.layers[layerIndex]
  if not (layer and layer.kind == "sprite") then return end

  local x1, y1 = screenToContent(win, m.startX, m.startY)
  local x2, y2 = screenToContent(win, x, y)

  if m.append and m.baseSelection then
    layer.multiSpriteSelection = cloneSelectionSet(m.baseSelection)
    layer.multiSpriteSelectionOrder = cloneSelectionOrder(m.baseSelectionOrder)
    local existing = normalizeSpriteSelectionIndices(layer)
    layer.selectedSpriteIndex = existing[1]
    M.selectSpritesInRect(win, layerIndex, { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }, true)
    return
  end

  M.selectSpritesInRect(win, layerIndex, { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }, false)
end

function M.finishSpriteMarquee(x, y)
  if not spriteMarquee.active then return false end

  local m = spriteMarquee
  spriteMarquee = { active = false }

  local win = m.win
  local layerIndex = m.layerIndex
  if not (win and win.layers and layerIndex) then return false end
  local layer = win.layers[layerIndex]
  if not (layer and layer.kind == "sprite") then return false end

  local x1, y1 = screenToContent(win, m.startX, m.startY)
  local x2, y2 = screenToContent(win, x or m.currentX, y or m.currentY)
  if m.append and m.baseSelection then
    layer.multiSpriteSelection = cloneSelectionSet(m.baseSelection)
    layer.multiSpriteSelectionOrder = cloneSelectionOrder(m.baseSelectionOrder)
    local existing = normalizeSpriteSelectionIndices(layer)
    layer.selectedSpriteIndex = existing[1]
    M.selectSpritesInRect(win, layerIndex, { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }, true)
  else
    M.selectSpritesInRect(win, layerIndex, { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }, false)
  end
  return true
end

function M.getSpriteMarquee()
  if spriteMarquee.active then
    return spriteMarquee
  end
  return nil
end

function M.clearTileMultiSelection(win, layerIdx)
  local layer = win and win.layers and win.layers[layerIdx]
  if layer then
    layer.multiTileSelection = nil
  end
end

function M.getGridCoordsClamped(win, sx, sy)
  return toGridCoordsClamped(win, sx, sy)
end

function M.isTileCellSelected(win, layerIdx, col, row)
  if not (win and layerIdx and col and row) then return false end
  local layer = win.layers and win.layers[layerIdx]
  if not (layer and layer.kind == "tile") then return false end
  local cols = win.cols or 0
  if cols <= 0 then return false end
  local idx = (row * cols + col) + 1
  return layer.multiTileSelection and layer.multiTileSelection[idx] == true
end

function M.addTileCellToSelection(win, layerIdx, col, row, includeCurrentSingle)
  if not (win and layerIdx and col and row) then return false end
  local layer = win.layers and win.layers[layerIdx]
  if not (layer and layer.kind == "tile") then return false end

  local cols = win.cols or 0
  local rows = win.rows or 0
  if cols <= 0 or rows <= 0 then return false end
  if col < 0 or col >= cols or row < 0 or row >= rows then return false end

  local idx = (row * cols + col) + 1
  local removedCells = (WindowCaps.isPpuFrame(win) and layer.kind == "tile") and nil or layer.removedCells
  local item = getTileInteractionItem(win, col, row, layerIdx)
  if item == nil or (removedCells and removedCells[idx]) then
    return false
  end

  local selected = layer.multiTileSelection
  if type(selected) ~= "table" then
    selected = {}

    if includeCurrentSingle and win.getSelected then
      local sCol, sRow, sLayer = win:getSelected()
      if type(sCol) == "number" and type(sRow) == "number"
        and (sLayer == nil or sLayer == layerIdx)
        and sCol >= 0 and sCol < cols and sRow >= 0 and sRow < rows
      then
        local sIdx = (sRow * cols + sCol) + 1
        local sItem = getTileInteractionItem(win, sCol, sRow, layerIdx)
        if sItem ~= nil and not (removedCells and removedCells[sIdx]) then
          selected[sIdx] = true
        end
      end
    end
  end

  selected[idx] = true
  layer.multiTileSelection = selected
  if win.setSelected then
    win:setSelected(col, row, layerIdx)
  end
  return true
end

function M.getSelectedTileCells(win, layerIdx, fallbackCol, fallbackRow)
  if not (win and layerIdx) then return {} end
  local layer = win.layers and win.layers[layerIdx]
  if not (layer and layer.kind == "tile") then return {} end

  local cols = win.cols or 0
  local cells = {}
  local selectedSet = layer.multiTileSelection
  if selectedSet and type(selectedSet) == "table" then
    for idx, on in pairs(selectedSet) do
      if on then
        local zeroBased = idx - 1
        local col = zeroBased % cols
        local row = math.floor(zeroBased / cols)
        cells[#cells + 1] = { col = col, row = row, idx = idx }
      end
    end
    table.sort(cells, function(a, b)
      if a.row == b.row then
        return a.col < b.col
      end
      return a.row < b.row
    end)
  end

  if #cells == 0 and fallbackCol and fallbackRow then
    cells[1] = {
      col = fallbackCol,
      row = fallbackRow,
      idx = (fallbackRow * cols + fallbackCol) + 1,
    }
  end

  return cells
end

local function isChr8x16SelectionMode(win)
  return WindowCaps.isChrLike(win) and win.orderMode == "oddEven"
end

local function getChr8x16TopRow(row)
  row = math.floor(tonumber(row) or 0)
  return row - (row % 2)
end

function M.getSelectedChr8x16Pairs(win, layerIdx, fallbackCol, fallbackRow)
  if not isChr8x16SelectionMode(win) then return nil end
  if not (win and layerIdx) then return {} end

  local rows = win.rows or 0
  local selected = M.getSelectedTileCells(win, layerIdx, fallbackCol, fallbackRow)
  if #selected == 0 then return {} end

  local pairs = {}
  local byKey = {}

  for _, cell in ipairs(selected) do
    local col = cell.col
    local topRow = getChr8x16TopRow(cell.row)
    local key = string.format("%d:%d", col, topRow)
    if not byKey[key] then
      local bottomRow = topRow + 1
      local topItem = getTileInteractionItem(win, col, topRow, layerIdx)
      local bottomItem = (bottomRow < rows) and getTileInteractionItem(win, col, bottomRow, layerIdx) or nil

      if topItem or bottomItem then
        local pair = {
          col = col,
          topRow = topRow,
          bottomRow = bottomRow,
          topItem = topItem,
          bottomItem = bottomItem,
        }
        byKey[key] = pair
        pairs[#pairs + 1] = pair
      end
    end
  end

  table.sort(pairs, function(a, b)
    if a.topRow == b.topRow then
      return a.col < b.col
    end
    return a.topRow < b.topRow
  end)

  return pairs
end

function M.deleteTileSelection(win, layerIdx, fallbackCol, fallbackRow, app, undoRedo)
  if not (win and layerIdx) then return nil end
  local layer = win.layers and win.layers[layerIdx]
  if not (layer and layer.kind == "tile") then return nil end

  local cells = M.getSelectedTileCells(win, layerIdx, fallbackCol, fallbackRow)
  if #cells == 0 then return nil end

  if WindowCaps.isPpuFrame(win) then
    local clearByte = 0x00
    local actions = {}

    for _, cell in ipairs(cells) do
      local idx = cell.idx or ((cell.row * (win.cols or 0) + cell.col) + 1)
      local prevByte = win.nametableBytes and win.nametableBytes[idx]
      if prevByte ~= clearByte then
        actions[#actions + 1] = {
          win        = win,
          layerIndex = layerIdx,
          col        = cell.col,
          row        = cell.row,
          prevByte   = prevByte,
          newByte    = clearByte,
        }
      end
    end

    if #actions == 0 then return nil end

    if undoRedo then
      undoRedo:addRemovalEvent({
        type    = "remove_tile",
        subtype = "ppu",
        actions = actions,
      })
    end

    local tilesPool = (app and app.appEditState and app.appEditState.tilesPool) or nil
    for _, act in ipairs(actions) do
      win:setNametableByteAt(act.col, act.row, clearByte, tilesPool, layerIdx)
    end

    layer.multiTileSelection = nil
    if #actions == 1 then
      win:setSelected(actions[1].col, actions[1].row, layerIdx)
      return { count = 1, status = "Cleared tile" }
    end

    win:clearSelected(layerIdx)
    return {
      count = #actions,
      status = string.format("Cleared %d tiles", #actions),
    }
  end

  local actions = {}
  for _, cell in ipairs(cells) do
    local idx = cell.idx or ((cell.row * (win.cols or 0) + cell.col) + 1)
    local prevRemoved = layer.removedCells and layer.removedCells[idx] or false
    if not prevRemoved then
      actions[#actions + 1] = {
        win         = win,
        layerIndex  = layerIdx,
        col         = cell.col,
        row         = cell.row,
        prevRemoved = prevRemoved,
      }
    end
  end

  if #actions == 0 then return nil end

  if undoRedo then
    undoRedo:addRemovalEvent({
      type    = "remove_tile",
      subtype = WindowCaps.isAnimationLike(win) and "animation" or "static",
      actions = actions,
    })
  end

  for _, act in ipairs(actions) do
    if win.markCellRemoved then
      win:markCellRemoved(act.col, act.row, layerIdx)
    else
      layer.removedCells = layer.removedCells or {}
      local idx = (act.row * (win.cols or 0) + act.col) + 1
      layer.removedCells[idx] = true
    end
  end

  layer.multiTileSelection = nil
  win:clearSelected(layerIdx)
  local removedCount = #actions
  return {
    count = removedCount,
    status = (removedCount > 1) and string.format("Deleted %d items", removedCount) or "Deleted item",
  }
end

function M.buildTileDragGroup(win, layerIdx, anchorCol, anchorRow)
  if not (win and layerIdx and anchorCol and anchorRow) then return nil end
  local layer = win.layers and win.layers[layerIdx]
  if not (layer and layer.kind == "tile") then return nil end

  if isChr8x16SelectionMode(win) then
    local pairs = M.getSelectedChr8x16Pairs(win, layerIdx, anchorCol, anchorRow)
    if not pairs or #pairs == 0 then return nil end

    local anchorTopRow = getChr8x16TopRow(anchorRow)
    local anchorInSelection = false
    for _, pair in ipairs(pairs) do
      if pair.col == anchorCol and pair.topRow == anchorTopRow then
        anchorInSelection = true
        break
      end
    end
    if not anchorInSelection then return nil end

    local entries = {}
    local spriteEntries = {}
    local minOffsetCol, maxOffsetCol = 0, 0
    local minOffsetRow, maxOffsetRow = 0, 0
    local spriteMinOffsetCol, spriteMaxOffsetCol = 0, 0
    local spriteMinOffsetRow, spriteMaxOffsetRow = 0, 0

    local function updateBounds(offsetCol, offsetRow, isSprite)
      if isSprite then
        if #spriteEntries == 1 then
          spriteMinOffsetCol, spriteMaxOffsetCol = offsetCol, offsetCol
          spriteMinOffsetRow, spriteMaxOffsetRow = offsetRow, offsetRow
        else
          if offsetCol < spriteMinOffsetCol then spriteMinOffsetCol = offsetCol end
          if offsetCol > spriteMaxOffsetCol then spriteMaxOffsetCol = offsetCol end
          if offsetRow < spriteMinOffsetRow then spriteMinOffsetRow = offsetRow end
          if offsetRow > spriteMaxOffsetRow then spriteMaxOffsetRow = offsetRow end
        end
      else
        if #entries == 1 then
          minOffsetCol, maxOffsetCol = offsetCol, offsetCol
          minOffsetRow, maxOffsetRow = offsetRow, offsetRow
        else
          if offsetCol < minOffsetCol then minOffsetCol = offsetCol end
          if offsetCol > maxOffsetCol then maxOffsetCol = offsetCol end
          if offsetRow < minOffsetRow then minOffsetRow = offsetRow end
          if offsetRow > maxOffsetRow then maxOffsetRow = offsetRow end
        end
      end
    end

    for _, pair in ipairs(pairs) do
      local offsetCol = pair.col - anchorCol
      local offsetTopRow = pair.topRow - anchorTopRow

      if pair.topItem ~= nil then
        entries[#entries + 1] = {
          srcCol = pair.col,
          srcRow = pair.topRow,
          offsetCol = offsetCol,
          offsetRow = offsetTopRow,
          item = pair.topItem,
        }
        updateBounds(offsetCol, offsetTopRow, false)

        spriteEntries[#spriteEntries + 1] = {
          srcCol = pair.col,
          srcRow = pair.topRow,
          offsetCol = offsetCol,
          offsetRow = offsetTopRow,
          item = pair.topItem,
          bottomItem = pair.bottomItem,
        }
        updateBounds(offsetCol, offsetTopRow, true)
      end

      if pair.bottomItem ~= nil then
        entries[#entries + 1] = {
          srcCol = pair.col,
          srcRow = pair.bottomRow,
          offsetCol = offsetCol,
          offsetRow = offsetTopRow + 1,
          item = pair.bottomItem,
        }
        updateBounds(offsetCol, offsetTopRow + 1, false)
      end
    end

    if #entries == 0 then return nil end

    table.sort(entries, function(a, b)
      if a.srcRow == b.srcRow then
        return a.srcCol < b.srcCol
      end
      return a.srcRow < b.srcRow
    end)
    table.sort(spriteEntries, function(a, b)
      if a.srcRow == b.srcRow then
        return a.srcCol < b.srcCol
      end
      return a.srcRow < b.srcRow
    end)

    return {
      anchorCol = anchorCol,
      anchorRow = anchorTopRow,
      entries = entries,
      spriteEntries = spriteEntries,
      minOffsetCol = minOffsetCol,
      maxOffsetCol = maxOffsetCol,
      minOffsetRow = minOffsetRow,
      maxOffsetRow = maxOffsetRow,
      spanCols = (maxOffsetCol - minOffsetCol) + 1,
      spanRows = (maxOffsetRow - minOffsetRow) + 1,
      spriteMinOffsetCol = spriteMinOffsetCol,
      spriteMaxOffsetCol = spriteMaxOffsetCol,
      spriteMinOffsetRow = spriteMinOffsetRow,
      spriteMaxOffsetRow = spriteMaxOffsetRow,
      spriteSpanCols = (spriteMaxOffsetCol - spriteMinOffsetCol) + 1,
      spriteSpanRows = (spriteMaxOffsetRow - spriteMinOffsetRow) + 1,
      sourceSelectionMode = "8x16",
    }
  end

  local selected = M.getSelectedTileCells(win, layerIdx)
  if #selected <= 1 then return nil end

  local anchorInSelection = false
  for _, cell in ipairs(selected) do
    if cell.col == anchorCol and cell.row == anchorRow then
      anchorInSelection = true
      break
    end
  end
  if not anchorInSelection then return nil end

  local entries = {}
  local minOffsetCol, maxOffsetCol = 0, 0
  local minOffsetRow, maxOffsetRow = 0, 0
  local cols = win.cols or 0
  local removedCells = (WindowCaps.isPpuFrame(win) and layer.kind == "tile") and nil or layer.removedCells

  for _, cell in ipairs(selected) do
    local idx = cell.idx or ((cell.row * cols + cell.col) + 1)
    local item = getTileInteractionItem(win, cell.col, cell.row, layerIdx)
    if item ~= nil and not (removedCells and removedCells[idx]) then
      local offsetCol = cell.col - anchorCol
      local offsetRow = cell.row - anchorRow
      entries[#entries + 1] = {
        srcCol = cell.col,
        srcRow = cell.row,
        offsetCol = offsetCol,
        offsetRow = offsetRow,
        item = item,
      }
      if #entries == 1 then
        minOffsetCol, maxOffsetCol = offsetCol, offsetCol
        minOffsetRow, maxOffsetRow = offsetRow, offsetRow
      else
        if offsetCol < minOffsetCol then minOffsetCol = offsetCol end
        if offsetCol > maxOffsetCol then maxOffsetCol = offsetCol end
        if offsetRow < minOffsetRow then minOffsetRow = offsetRow end
        if offsetRow > maxOffsetRow then maxOffsetRow = offsetRow end
      end
    end
  end

  if #entries <= 1 then return nil end

  table.sort(entries, function(a, b)
    if a.srcRow == b.srcRow then
      return a.srcCol < b.srcCol
    end
    return a.srcRow < b.srcRow
  end)

  return {
    anchorCol = anchorCol,
    anchorRow = anchorRow,
    entries = entries,
    minOffsetCol = minOffsetCol,
    maxOffsetCol = maxOffsetCol,
    minOffsetRow = minOffsetRow,
    maxOffsetRow = maxOffsetRow,
    spanCols = (maxOffsetCol - minOffsetCol) + 1,
    spanRows = (maxOffsetRow - minOffsetRow) + 1,
    sourceSelectionMode = "8x8", -- Future: CHR/ROM windows may expose 8x16 selection semantics directly.
  }
end

function M.clampTileDropAnchor(win, group, targetCol, targetRow)
  if not (win and targetCol and targetRow) then return nil, nil end

  local cols = win.cols or 0
  local rows = win.rows or 0
  if cols <= 0 or rows <= 0 then return nil, nil end

  local minCol = 0
  local maxCol = cols - 1
  local minRow = 0
  local maxRow = rows - 1

  if group and group.entries and #group.entries > 0 then
    minCol = 0 - (group.minOffsetCol or 0)
    maxCol = (cols - 1) - (group.maxOffsetCol or 0)
    minRow = 0 - (group.minOffsetRow or 0)
    maxRow = (rows - 1) - (group.maxOffsetRow or 0)
  end

  if minCol > maxCol or minRow > maxRow then return nil, nil end

  return clamp(targetCol, minCol, maxCol), clamp(targetRow, minRow, maxRow)
end

function M.applyTileDragGroup(win, layerIdx, group, anchorCol, anchorRow, opts)
  -- anchor 0 is valid; do not use "anchorCol and anchorRow" (0 is falsy in Lua).
  if not (win and layerIdx and group and group.entries) then
    return nil
  end
  if type(anchorCol) ~= "number" or type(anchorRow) ~= "number" then
    return nil
  end
  opts = opts or {}

  local layer = win.layers and win.layers[layerIdx]
  if not (layer and layer.kind == "tile") then return nil end

  local cols = win.cols or 0
  local rows = win.rows or 0
  if cols <= 0 or rows <= 0 then return nil end

  local copyMode = opts.copyMode == true
  local srcWin = opts.srcWin or win
  local srcLayer = opts.srcLayer or layerIdx
  local tilesPool = opts.tilesPool

  local selectedSet = {}
  local placed = 0
  local firstCol, firstRow = nil, nil
  local placements = {}
  local destSet = {}

  for _, entry in ipairs(group.entries) do
    local col = anchorCol + (entry.offsetCol or 0)
    local row = anchorRow + (entry.offsetRow or 0)
    if col >= 0 and col < cols and row >= 0 and row < rows then
      placements[#placements + 1] = {
        col = col,
        row = row,
        item = entry.item,
      }
      destSet[(row * cols + col) + 1] = true
    end
  end

  -- PPU nametable layers should move bytes directly (any PPU → PPU). Using win:set + materialize
  -- on virtual handles maps everything to CHR tile 0 for multi-drag across windows or layers.
  if WindowCaps.isPpuFrame(win)
    and WindowCaps.isPpuFrame(srcWin)
    and win.nametableBytes
    and srcWin.nametableBytes
    and win.setNametableByteAt
    and srcWin.setNametableByteAt
  then
    local srcCols = srcWin.cols or 0
    local srcLayerTbl = srcWin.layers and srcWin.layers[srcLayer]
    local transparentByte = 0x00
    local placementBytes = {}

    for _, entry in ipairs(group.entries) do
      local srcCol = entry.srcCol
      local srcRow = entry.srcRow
      local dstCol = anchorCol + (entry.offsetCol or 0)
      local dstRow = anchorRow + (entry.offsetRow or 0)
      if type(srcCol) == "number" and type(srcRow) == "number"
        and dstCol >= 0 and dstCol < cols and dstRow >= 0 and dstRow < rows
      then
        local srcIdx = (srcRow * srcCols + srcCol) + 1
        local srcByte = srcWin.nametableBytes[srcIdx] or 0
        placementBytes[#placementBytes + 1] = {
          col = dstCol,
          row = dstRow,
          byte = srcByte,
          srcIdx = srcIdx,
          srcCol = srcCol,
          srcRow = srcRow,
        }
      end
    end

    if (not copyMode) then
      for _, p in ipairs(placementBytes) do
        local skipClear = false
        if srcWin == win then
          -- Same grid: do not clear a source cell that is also a drop target for another tile.
          skipClear = destSet[p.srcIdx] == true
        end
        if not skipClear then
          srcWin:setNametableByteAt(p.srcCol, p.srcRow, transparentByte, tilesPool, srcLayer)
        end
      end
    end

    for _, p in ipairs(placementBytes) do
      win:setNametableByteAt(p.col, p.row, p.byte, tilesPool, layerIdx)
      local idx = (p.row * cols + p.col) + 1
      selectedSet[idx] = true
      placed = placed + 1
      if not firstCol then
        firstCol, firstRow = p.col, p.row
      end
    end

    if placed > 1 then
      layer.multiTileSelection = selectedSet
    else
      layer.multiTileSelection = nil
    end

    if win.setSelected and firstCol then
      win:setSelected(firstCol, firstRow, layerIdx)
    end

    return {
      count = placed,
      firstCol = firstCol,
      firstRow = firstRow,
      selection = selectedSet,
    }
  end

  if (not copyMode) and srcWin then
    local srcCols = srcWin.cols or 0
    local sameLayer = (srcWin == win) and (srcLayer == layerIdx)
    for _, entry in ipairs(group.entries) do
      local srcCol = entry.srcCol
      local srcRow = entry.srcRow
      if type(srcCol) == "number" and type(srcRow) == "number" then
        local srcIdx = (srcRow * srcCols + srcCol) + 1
        if not (sameLayer and destSet[srcIdx]) then
          if srcWin.removeAt then
            srcWin:removeAt(srcCol, srcRow, srcLayer, nil)
          elseif srcWin.set then
            srcWin:set(srcCol, srcRow, nil, srcLayer)
          end
        end
      end
    end
  end

  for _, placement in ipairs(placements) do
    if win.set then
      win:set(
        placement.col,
        placement.row,
        materializeTileInteractionItem(srcWin, placement.item, srcLayer),
        layerIdx
      )
    end
    local idx = (placement.row * cols + placement.col) + 1
    selectedSet[idx] = true
    placed = placed + 1
    if not firstCol then
      firstCol, firstRow = placement.col, placement.row
    end
  end

  if placed > 1 then
    layer.multiTileSelection = selectedSet
  else
    layer.multiTileSelection = nil
  end

  if win.setSelected and firstCol then
    win:setSelected(firstCol, firstRow, layerIdx)
  end

  return {
    count = placed,
    firstCol = firstCol,
    firstRow = firstRow,
    selection = selectedSet,
  }
end

local function applyTileMarqueeSelection(win, layerIdx, startCol, startRow, endCol, endRow)
  local layer = win and win.layers and win.layers[layerIdx]
  if not (layer and layer.kind == "tile") then return false end

  local minCol = math.min(startCol, endCol)
  local maxCol = math.max(startCol, endCol)
  local minRow = math.min(startRow, endRow)
  local maxRow = math.max(startRow, endRow)
  local cols = win.cols or 0
  local removedCells = (WindowCaps.isPpuFrame(win) and layer.kind == "tile") and nil or layer.removedCells

  local selected = {}
  local selectedCount = 0
  local firstCol, firstRow = nil, nil

  for row = minRow, maxRow do
    for col = minCol, maxCol do
      local i = row * cols + col + 1
      local item = getTileInteractionItem(win, col, row, layerIdx)
      if item ~= nil and not (removedCells and removedCells[i]) then
        selected[i] = true
        selectedCount = selectedCount + 1
        if not firstCol then
          firstCol, firstRow = col, row
        end
      end
    end
  end

  if selectedCount > 0 then
    layer.multiTileSelection = selected
    if win.setSelected then
      win:setSelected(firstCol, firstRow, layerIdx)
    end
  else
    layer.multiTileSelection = nil
    if win.clearSelected then
      win:clearSelected(layerIdx)
    end
  end

  return true
end

function M.startTileMarquee(win, layerIdx, col, row, x, y)
  tileMarquee = {
    active = true,
    win = win,
    layerIdx = layerIdx,
    startCol = col,
    startRow = row,
    currentCol = col,
    currentRow = row,
    startX = x,
    startY = y,
    currentX = x,
    currentY = y,
  }
end

function M.updateTileMarquee(x, y)
  if not tileMarquee.active then return end
  tileMarquee.currentX = x
  tileMarquee.currentY = y
  local col, row = toGridCoordsClamped(tileMarquee.win, x, y)
  if col and row then
    tileMarquee.currentCol = col
    tileMarquee.currentRow = row
    applyTileMarqueeSelection(
      tileMarquee.win,
      tileMarquee.layerIdx,
      tileMarquee.startCol,
      tileMarquee.startRow,
      col,
      row
    )
  end
end

function M.finishTileMarquee(x, y)
  if not tileMarquee.active then return false end

  local m = tileMarquee
  tileMarquee = { active = false }

  local win = m.win
  local layerIdx = m.layerIdx
  if not (win and layerIdx and win.layers and win.layers[layerIdx]) then
    return false
  end

  local endCol = m.currentCol
  local endRow = m.currentRow
  if x and y then
    local col, row = toGridCoordsClamped(win, x, y)
    if col and row then
      endCol = col
      endRow = row
    end
  end
  if not (endCol and endRow) then return false end

  return applyTileMarqueeSelection(win, layerIdx, m.startCol, m.startRow, endCol, endRow)
end

function M.getTileMarquee()
  if tileMarquee.active then
    return tileMarquee
  end
  return nil
end

function M.reset()
  spriteMarquee = { active = false }
  tileMarquee = { active = false }
end

return M
