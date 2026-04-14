local MultiSelectController = require("controllers.input_support.multi_select_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local chr = require("chr")
local GameArtController = require("controllers.game_art.game_art_controller")
local BankCanvasSupport = require("controllers.chr.bank_canvas_support")

local M = {}

local clipboard = nil

local function setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

local function showWarning(ctx, text)
  setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.showToast) == "function" then
    ctx.app:showToast("warning", text)
  end
end

local function resolveScaledMouse(ctx)
  if not (ctx and type(ctx.scaledMouse) == "function") then
    return nil, nil
  end
  local a, b, c = ctx.scaledMouse()
  if type(a) == "table" then
    local mx = tonumber(a.x)
    local my = tonumber(a.y)
    if type(mx) == "number" and type(my) == "number" then
      return mx, my
    end
    return nil, nil
  end

  local mx, my = a, b
  if type(a) == "boolean" then
    if a ~= true then
      return nil, nil
    end
    mx, my = b, c
  end
  if type(mx) ~= "number" or type(my) ~= "number" then
    return nil, nil
  end
  return mx, my
end

function M.reset()
  clipboard = nil
end

local function shallowCloneTable(src)
  local out = {}
  for k, v in pairs(src or {}) do
    out[k] = v
  end
  return out
end

local function ensureAppEdits(app)
  if not app then return nil end
  if type(app.edits) ~= "table" then
    app.edits = GameArtController.newEdits()
  end
  app.edits.banks = app.edits.banks or {}
  return app.edits
end

local function beginUndoPaintEvent(undoRedo)
  if not (undoRedo and undoRedo.startPaintEvent and undoRedo.finishPaintEvent and undoRedo.cancelPaintEvent and undoRedo.recordPixelChange) then
    return nil
  end
  if undoRedo.activeEvent ~= nil then
    return nil
  end
  undoRedo:startPaintEvent()
  return {
    undoRedo = undoRedo,
    changed = false,
  }
end

local function recordUndoChrPixelDiff(paintCtx, tileRef, beforePixels)
  if not (paintCtx and paintCtx.undoRedo and tileRef and beforePixels and tileRef.pixels) then
    return
  end
  local bankIdx = tileRef._bankIndex
  local tileIdx = tileRef.index
  if type(bankIdx) ~= "number" or type(tileIdx) ~= "number" then
    return
  end
  for y = 0, 7 do
    for x = 0, 7 do
      local i = y * 8 + x + 1
      local before = beforePixels[i] or 0
      local after = tileRef.pixels[i] or 0
      if before ~= after then
        paintCtx.undoRedo:recordPixelChange(bankIdx, tileIdx, x, y, before, after)
        paintCtx.changed = true
      end
    end
  end
end

local function finishUndoPaintEvent(paintCtx)
  if not (paintCtx and paintCtx.undoRedo) then
    return false
  end
  if paintCtx.changed then
    return paintCtx.undoRedo:finishPaintEvent()
  end
  paintCtx.undoRedo:cancelPaintEvent()
  return false
end

local function snapshotTilePixels(tile)
  if not (tile and tile.pixels) then
    return nil
  end
  local out = {}
  for i = 1, 64 do
    out[i] = tile.pixels[i] or 0
  end
  return out
end

local function captureSpriteUndoState(sprite)
  if not sprite then
    return nil
  end
  return {
    worldX = sprite.worldX,
    worldY = sprite.worldY,
    x = sprite.x,
    y = sprite.y,
    dx = sprite.dx,
    dy = sprite.dy,
    hasMoved = sprite.hasMoved,
    removed = sprite.removed == true,
    mirrorX = sprite.mirrorX,
    mirrorY = sprite.mirrorY,
    mirrorXSet = (sprite.mirrorX ~= nil),
    mirrorYSet = (sprite.mirrorY ~= nil),
    mirrorXOverrideSet = sprite._mirrorXOverrideSet == true,
    mirrorYOverrideSet = sprite._mirrorYOverrideSet == true,
    attr = sprite.attr,
    attrSet = (sprite.attr ~= nil),
    paletteNumber = sprite.paletteNumber,
    paletteNumberSet = (sprite.paletteNumber ~= nil),
  }
end

local function syncChrTileMutation(tileRef, app)
  if not (tileRef and tileRef.pixels and #tileRef.pixels == 64) then
    return
  end

  if tileRef.refreshImage then
    tileRef:refreshImage()
  end

  if tileRef._bankBytesRef and type(tileRef.index) == "number" then
    for y = 0, 7 do
      for x = 0, 7 do
        local idx = y * 8 + x + 1
        local pixelValue = tileRef.pixels[idx]
        if pixelValue ~= nil then
          chr.setTilePixel(tileRef._bankBytesRef, tileRef.index, x, y, pixelValue)
        end
      end
    end
  end

  local bankIdx = tileRef._bankIndex
  local tileIdx = tileRef.index
  if type(bankIdx) ~= "number" or type(tileIdx) ~= "number" then
    return
  end
  local edits = ensureAppEdits(app)
  if not edits then
    return
  end
  for y = 0, 7 do
    for x = 0, 7 do
      local idx = y * 8 + x + 1
      local pixelValue = tileRef.pixels[idx]
      if pixelValue == nil then pixelValue = 0 end
      GameArtController.recordEdit(edits, bankIdx, tileIdx, x, y, pixelValue)
    end
  end

  -- CHR/ROM bank windows render from cached bank canvases, so mark this tile dirty.
  BankCanvasSupport.invalidateTile(app, bankIdx, tileIdx)
end

local function getClipboardTileItem(win, col, row, layerIndex)
  if not win then
    return nil
  end
  if win.getVirtualTileHandle then
    local item = win:getVirtualTileHandle(col, row, layerIndex)
    if item ~= nil then
      return item
    end
  end
  if win.get then
    return win:get(col, row, layerIndex)
  end
  return nil
end

local function materializeClipboardTileItem(data, item, layerIndex)
  if item == nil then
    return nil
  end
  local sourceWin = data and data.sourceWin or nil
  if sourceWin and sourceWin.materializeTileHandle then
    local resolved = sourceWin:materializeTileHandle(item, layerIndex)
    if resolved ~= nil then
      return resolved
    end
  end
  return item
end

local function captureTileClipboard(win, layer, layerIndex)
  if not (win and layer and layer.kind == "tile") then return nil end

  local fallbackCol, fallbackRow = nil, nil
  if win.getSelected then
    fallbackCol, fallbackRow = win:getSelected()
  end
  local minCol, minRow = math.huge, math.huge
  local maxCol, maxRow = -math.huge, -math.huge
  local entries = {}
  local isChr8x16 = WindowCaps.isChrLike(win) and win.orderMode == "oddEven"

  if isChr8x16 then
    local pairs = MultiSelectController.getSelectedChr8x16Pairs(win, layerIndex, fallbackCol, fallbackRow) or {}
    if #pairs == 0 then return nil end
    for _, pair in ipairs(pairs) do
      local col = pair.col
      if pair.topItem ~= nil and type(pair.topRow) == "number" then
        entries[#entries + 1] = {
          col = col,
          row = pair.topRow,
          item = pair.topItem,
          byte = nil,
        }
        minCol = math.min(minCol, col)
        minRow = math.min(minRow, pair.topRow)
        maxCol = math.max(maxCol, col)
        maxRow = math.max(maxRow, pair.topRow)
      end
      if pair.bottomItem ~= nil and type(pair.bottomRow) == "number" then
        entries[#entries + 1] = {
          col = col,
          row = pair.bottomRow,
          item = pair.bottomItem,
          byte = nil,
        }
        minCol = math.min(minCol, col)
        minRow = math.min(minRow, pair.bottomRow)
        maxCol = math.max(maxCol, col)
        maxRow = math.max(maxRow, pair.bottomRow)
      end
    end
  else
    local cells = MultiSelectController.getSelectedTileCells(win, layerIndex, fallbackCol, fallbackRow)
    if #cells == 0 then return nil end
    for _, cell in ipairs(cells) do
      local col, row = cell.col, cell.row
      local idx = (row * (win.cols or 0) + col) + 1
      local item = getClipboardTileItem(win, col, row, layerIndex)
      if item ~= nil then
        entries[#entries + 1] = {
          col = col,
          row = row,
          item = item,
          byte = (WindowCaps.isPpuFrame(win) and win.nametableBytes and win.nametableBytes[idx]) or nil,
        }
        minCol = math.min(minCol, col)
        minRow = math.min(minRow, row)
        maxCol = math.max(maxCol, col)
        maxRow = math.max(maxRow, row)
      end
    end
  end

  if #entries == 0 then return nil end
  for _, entry in ipairs(entries) do
    entry.offsetCol = entry.col - minCol
    entry.offsetRow = entry.row - minRow
  end

  return {
    kind = "tile",
    sourceWin = WindowCaps.isChrLike(win) and win or nil,
    entries = entries,
    width = (maxCol - minCol) + 1,
    height = (maxRow - minRow) + 1,
    count = #entries,
  }
end

local function captureSpriteClipboard(win, layer)
  if not (win and layer and layer.kind == "sprite") then return nil end

  local SpriteController = require("controllers.sprite.sprite_controller")
  local selected = SpriteController.getSelectedSpriteIndices(layer)
  if (#selected == 0) and layer.selectedSpriteIndex then
    selected = { layer.selectedSpriteIndex }
  end
  if #selected == 0 then return nil end

  local spriteW = win.cellW or 8
  local spriteH = ((layer.mode or "8x8") == "8x16") and ((win.cellH or 8) * 2) or (win.cellH or 8)

  local minX, minY = math.huge, math.huge
  local maxRight, maxBottom = -math.huge, -math.huge
  local entries = {}

  for _, idx in ipairs(selected) do
    local s = layer.items and layer.items[idx]
    if s and s.removed ~= true then
      local x = s.worldX or s.baseX or s.x or 0
      local y = s.worldY or s.baseY or s.y or 0
      entries[#entries + 1] = {
        x = x,
        y = y,
        sprite = shallowCloneTable(s),
      }
      minX = math.min(minX, x)
      minY = math.min(minY, y)
      maxRight = math.max(maxRight, x + spriteW)
      maxBottom = math.max(maxBottom, y + spriteH)
    end
  end

  if #entries == 0 then return nil end
  for _, entry in ipairs(entries) do
    entry.relX = entry.x - minX
    entry.relY = entry.y - minY
  end

  return {
    kind = "sprite",
    entries = entries,
    widthPx = math.max(1, maxRight - minX),
    heightPx = math.max(1, maxBottom - minY),
    count = #entries,
  }
end

local function fitAnchorToBounds(anchor, payloadSize, limitSize)
  local payload = math.max(1, math.floor(tonumber(payloadSize) or 1))
  local limit = math.max(0, math.floor(tonumber(limitSize) or 0))
  if payload > limit then
    return nil, true, "payload_too_large"
  end

  local fitted = math.floor(tonumber(anchor) or 0)
  if fitted < 0 then
    fitted = 0
  end
  local maxStart = math.max(0, limit - payload)
  if fitted > maxStart then
    fitted = maxStart
  end
  return fitted, (fitted ~= math.floor(tonumber(anchor) or 0)), nil
end

local function resolveTileSelectionAnchor(focus, layerIndex)
  if not (focus and type(focus.getSelected) == "function") then
    return nil, nil
  end

  local selCol, selRow, selLayer = focus:getSelected()
  if type(selCol) ~= "number" or type(selRow) ~= "number" then
    return nil, nil
  end
  if type(selLayer) == "number" and type(layerIndex) == "number" and selLayer ~= layerIndex then
    return nil, nil
  end

  return math.floor(selCol), math.floor(selRow)
end

local function resolveSpriteSelectionAnchor(layer)
  if not layer then
    return nil, nil
  end
  local SpriteController = require("controllers.sprite.sprite_controller")
  local selected = SpriteController.getSelectedSpriteIndices(layer)
  if #selected == 0 then
    return nil, nil
  end

  local minX, minY = nil, nil
  for _, idx in ipairs(selected) do
    local s = layer.items and layer.items[idx]
    if s and s.removed ~= true then
      local x = s.worldX or s.baseX or s.x or 0
      local y = s.worldY or s.baseY or s.y or 0
      if minX == nil or x < minX then minX = x end
      if minY == nil or y < minY then minY = y end
    end
  end

  if minX == nil or minY == nil then
    return nil, nil
  end
  return math.floor(minX), math.floor(minY)
end

local function pasteTileClipboard(ctx, focus, layer, layerIndex, data, opts)
  if not (focus and layer and layer.kind == "tile" and data and data.entries) then
    return { count = 0, shifted = false, source = "none" }
  end

  local cols = focus.cols or 0
  local rows = focus.rows or 0
  if cols <= 0 or rows <= 0 then
    return { count = 0, shifted = false, source = "none" }
  end

  local anchorCol, anchorRow = resolveTileSelectionAnchor(focus, layerIndex)
  local anchorSource = "selection"
  if anchorCol == nil or anchorRow == nil then
    anchorSource = "cursor"
    local mx, my = resolveScaledMouse(ctx)
    if mx ~= nil and my ~= nil and focus.toGridCoords then
      local ok, col, row = focus:toGridCoords(mx, my)
      if ok then
        anchorCol = col
        anchorRow = row
      end
    end
    if anchorCol == nil or anchorRow == nil then
      anchorSource = "top_left"
      anchorCol = 0
      anchorRow = 0
    end
  end

  local fittedCol, shiftedX, fitErrX = fitAnchorToBounds(anchorCol, data.width or 1, cols)
  local fittedRow, shiftedY, fitErrY = fitAnchorToBounds(anchorRow, data.height or 1, rows)
  if fitErrX == "payload_too_large" or fitErrY == "payload_too_large" then
    return {
      count = 0,
      shifted = false,
      source = anchorSource,
      reason = "Selection does not fit in target layer",
    }
  end
  anchorCol = fittedCol
  anchorRow = fittedRow

  local selectedSet = {}
  local count = 0
  local firstCol, firstRow = nil, nil
  local tilesPool = ctx.app and ctx.app.appEditState and ctx.app.appEditState.tilesPool
  local undoRedo = ctx and ctx.app and ctx.app.undoRedo or nil
  local undoPaintCtx = WindowCaps.isChrLike(focus) and beginUndoPaintEvent(undoRedo) or nil
  local undoTileChanges = {}
  local undoPpuChanges = {}
  local seenTileChanges = {}

  local function stageTileUndoCell(col, row, before)
    if not undoRedo then
      return
    end
    local key = tostring(col) .. ":" .. tostring(row)
    if seenTileChanges[key] then
      return
    end
    seenTileChanges[key] = true
    undoTileChanges[#undoTileChanges + 1] = {
      win = focus,
      layerIndex = layerIndex,
      col = col,
      row = row,
      before = before,
    }
  end

  local function copyPixelsByValue(dstTile, srcTile)
    if not (dstTile and srcTile and dstTile.pixels and srcTile.pixels) then
      return false
    end
    local changed = false
    for i = 1, 64 do
      local v = srcTile.pixels[i]
      if v == nil then v = 0 end
      if dstTile.pixels[i] ~= v then
        dstTile.pixels[i] = v
        changed = true
      end
    end
    return changed
  end

  for _, entry in ipairs(data.entries) do
    local col = anchorCol + (entry.offsetCol or 0)
    local row = anchorRow + (entry.offsetRow or 0)
    if col >= 0 and col < cols and row >= 0 and row < rows then
      local applied = false
      if WindowCaps.isPpuFrame(focus) and focus.setNametableByteAt and entry.byte ~= nil then
        local idx = (row * cols + col) + 1
        local beforeByte = focus.nametableBytes and focus.nametableBytes[idx] or nil
        focus:setNametableByteAt(col, row, entry.byte, tilesPool, layerIndex)
        applied = true
        if undoRedo and beforeByte ~= entry.byte then
          undoPpuChanges[#undoPpuChanges + 1] = {
            win = focus,
            layerIndex = layerIndex,
            col = col,
            row = row,
            before = beforeByte,
            after = entry.byte,
            isNametableByte = true,
            tilesPool = tilesPool,
          }
        end
      elseif WindowCaps.isChrLike(focus) then
        local srcItem = materializeClipboardTileItem(data, entry.item, layerIndex)
        local dstItem = nil
        if focus.get then
          dstItem = focus:get(col, row, layerIndex)
        end
        local beforePixels = snapshotTilePixels(dstItem)
        applied = copyPixelsByValue(dstItem, srcItem)
        if applied then
          if beforePixels ~= nil then
            recordUndoChrPixelDiff(undoPaintCtx, dstItem, beforePixels)
          end
          syncChrTileMutation(dstItem, ctx and ctx.app or nil)
        end
      elseif focus.set then
        local beforeItem = focus.get and focus:get(col, row, layerIndex) or nil
        stageTileUndoCell(col, row, beforeItem)
        focus:set(col, row, materializeClipboardTileItem(data, entry.item, layerIndex), layerIndex)
        applied = true
      end

      if applied then
        local idx = (row * cols + col) + 1
        selectedSet[idx] = true
        count = count + 1
        if not firstCol then
          firstCol, firstRow = col, row
        end
      end
    end
  end

  if count > 1 then
    layer.multiTileSelection = selectedSet
  else
    layer.multiTileSelection = nil
  end

  if firstCol and focus.setSelected then
    focus:setSelected(firstCol, firstRow, layerIndex)
  elseif focus.clearSelected then
    focus:clearSelected(layerIndex)
  end

  if #undoPpuChanges > 0 and undoRedo and undoRedo.addDragEvent then
    undoRedo:addDragEvent({
      type = "tile_drag",
      mode = "copy",
      changes = undoPpuChanges,
      tilesPool = tilesPool,
    })
  elseif #undoTileChanges > 0 and undoRedo and undoRedo.addDragEvent then
    local committed = {}
    for _, rec in ipairs(undoTileChanges) do
      local after = focus.get and focus:get(rec.col, rec.row, layerIndex) or nil
      if rec.before ~= after then
        committed[#committed + 1] = {
          win = rec.win,
          layerIndex = rec.layerIndex,
          col = rec.col,
          row = rec.row,
          before = rec.before,
          after = after,
        }
      end
    end
    if #committed > 0 then
      undoRedo:addDragEvent({
        type = "tile_drag",
        mode = "copy",
        changes = committed,
      })
    end
  end

  finishUndoPaintEvent(undoPaintCtx)

  return {
    count = count,
    shifted = (shiftedX == true or shiftedY == true),
    source = anchorSource,
  }
end

local function pasteSpriteClipboard(ctx, focus, layer, data, opts)
  if not (focus and layer and layer.kind == "sprite" and data and data.entries) then
    return { count = 0, shifted = false, source = "none" }
  end

  layer.items = layer.items or {}

  local layerPixelW = math.max(1, (focus.cols or 0) * (focus.cellW or 8))
  local layerPixelH = math.max(1, (focus.rows or 0) * (focus.cellH or 8))
  local anchorX, anchorY = resolveSpriteSelectionAnchor(layer)
  local anchorSource = "selection"
  if anchorX == nil or anchorY == nil then
    anchorSource = "cursor"
    local mx, my = resolveScaledMouse(ctx)
    if mx ~= nil and my ~= nil and focus.toGridCoords then
      local ok, col, row, lx, ly = focus:toGridCoords(mx, my)
      if ok then
        local cellW = focus.cellW or 8
        local cellH = focus.cellH or 8
        anchorX = (col * cellW) + (lx or 0)
        anchorY = (row * cellH) + (ly or 0)
      end
    end
    if anchorX == nil or anchorY == nil then
      anchorSource = "top_left"
      anchorX = 0
      anchorY = 0
    end
  end

  local fittedX, shiftedX, fitErrX = fitAnchorToBounds(anchorX, data.widthPx or 1, layerPixelW)
  local fittedY, shiftedY, fitErrY = fitAnchorToBounds(anchorY, data.heightPx or 1, layerPixelH)
  if fitErrX == "payload_too_large" or fitErrY == "payload_too_large" then
    return {
      count = 0,
      shifted = false,
      source = anchorSource,
      reason = "Selection does not fit in target layer",
    }
  end
  anchorX = fittedX
  anchorY = fittedY

  local newIndices = {}
  local undoActions = {}
  for _, entry in ipairs(data.entries) do
    local clone = shallowCloneTable(entry.sprite)
    clone.removed = false
    local worldX = anchorX + (entry.relX or 0)
    local worldY = anchorY + (entry.relY or 0)
    clone.worldX = worldX
    clone.worldY = worldY
    clone.x = worldX
    clone.y = worldY

    local baseX = clone.baseX or worldX
    local baseY = clone.baseY or worldY
    clone.dx = worldX - baseX
    clone.dy = worldY - baseY
    clone.hasMoved = (clone.dx ~= 0 or clone.dy ~= 0)

    table.insert(layer.items, clone)
    newIndices[#newIndices + 1] = #layer.items
    undoActions[#undoActions + 1] = {
      win = focus,
      sprite = clone,
      before = { removed = true },
      after = captureSpriteUndoState(clone),
    }
  end

  if #newIndices > 0 then
    local SpriteController = require("controllers.sprite.sprite_controller")
    SpriteController.setSpriteSelection(layer, newIndices)
    layer.selectedSpriteIndex = newIndices[1]
    layer.hoverSpriteIndex = newIndices[1]
  end

  local undoRedo = ctx and ctx.app and ctx.app.undoRedo or nil
  if #undoActions > 0 and undoRedo and undoRedo.addDragEvent then
    undoRedo:addDragEvent({
      type = "sprite_drag",
      mode = "copy",
      actions = undoActions,
    })
  end

  return {
    count = #newIndices,
    shifted = (shiftedX == true or shiftedY == true),
    source = anchorSource,
  }
end

local function getActiveLayer(focus, opts)
  if not (focus and focus.layers) then
    return nil, nil
  end
  local layerIndex = opts and opts.layerIndex
  if type(layerIndex) ~= "number" then
    if not focus.getActiveLayerIndex then
      return nil, nil
    end
    layerIndex = focus:getActiveLayerIndex()
  end
  local layer = focus.layers[layerIndex]
  return layerIndex, layer
end

local function restrictionMessage(action, focus, layer)
  if not (focus and layer and layer.kind == "sprite") then
    return nil
  end
  if WindowCaps.isOamAnimation(focus) then
    if action == "paste" then
      return "Cannot add sprites to OAM animation windows"
    end
    if action == "copy" then
      return "Cannot copy sprites in OAM animation windows"
    end
    if action == "cut" then
      return "Cannot cut sprites in OAM animation windows"
    end
    return "Clipboard is disabled for sprite layers in OAM animation windows"
  end
  if WindowCaps.isPpuFrame(focus) then
    if action == "copy" then
      return "Cannot copy sprites in PPU frame windows"
    end
    if action == "cut" then
      return "Cannot cut sprites in PPU frame windows"
    end
    if action == "paste" then
      return "Cannot paste sprites in PPU frame windows"
    end
    return "Clipboard is disabled for sprite layers in PPU frame windows"
  end
  return nil
end

function M.getActionAvailability(ctx, focus, action, opts)
  if not focus then
    return { allowed = false, reason = "No focused window", noFocus = true, layerIndex = nil, layer = nil }
  end
  local layerIndex, layer = getActiveLayer(focus, opts)
  if not layer then
    return { allowed = false, reason = "No active layer selected", layerIndex = layerIndex, layer = layer, noLayer = true }
  end
  if layer.kind ~= "tile" and layer.kind ~= "sprite" then
    return { allowed = false, reason = "Clipboard is not available for this layer type", layerIndex = layerIndex, layer = layer }
  end

  local restriction = restrictionMessage(action, focus, layer)
  if restriction then
    return { allowed = false, reason = restriction, layerIndex = layerIndex, layer = layer, restricted = true }
  end

  if action == "paste" then
    if not clipboard or not clipboard.kind then
      return { allowed = false, reason = "Clipboard is empty", layerIndex = layerIndex, layer = layer }
    end
    if clipboard.kind ~= layer.kind then
      return { allowed = false, reason = "Clipboard content does not match active layer type", layerIndex = layerIndex, layer = layer }
    end
  end

  return { allowed = true, layerIndex = layerIndex, layer = layer }
end

local function cutChrTileSelection(ctx, focus, layer, layerIndex)
  local fallbackCol, fallbackRow = nil, nil
  if focus.getSelected then
    fallbackCol, fallbackRow = focus:getSelected()
  end
  local cells = MultiSelectController.getSelectedTileCells(focus, layerIndex, fallbackCol, fallbackRow)
  if #cells == 0 then
    return nil
  end

  local cleared = 0
  local undoRedo = ctx and ctx.app and ctx.app.undoRedo or nil
  local undoPaintCtx = beginUndoPaintEvent(undoRedo)
  for _, cell in ipairs(cells) do
    local tile = focus.get and focus:get(cell.col, cell.row, layerIndex) or nil
    if tile and tile.pixels then
      local beforePixels = snapshotTilePixels(tile)
      local changed = false
      for i = 1, 64 do
        if tile.pixels[i] ~= 0 then
          tile.pixels[i] = 0
          changed = true
        end
      end
      if changed then
          if beforePixels ~= nil then
            recordUndoChrPixelDiff(undoPaintCtx, tile, beforePixels)
          end
          syncChrTileMutation(tile, ctx and ctx.app or nil)
        cleared = cleared + 1
      end
    end
  end

  layer.multiTileSelection = nil
  if focus.clearSelected then
    focus:clearSelected(layerIndex)
  end
  if cleared == 0 then
    finishUndoPaintEvent(undoPaintCtx)
    return nil
  end
  finishUndoPaintEvent(undoPaintCtx)
  if ctx and ctx.app and ctx.app.markUnsaved then
    ctx.app:markUnsaved("tile_move")
  end
  return { count = cleared }
end

local function freezeTileClipboardItems(data, layerIndex)
  if not (data and data.entries) then
    return data
  end
  for _, entry in ipairs(data.entries) do
    local source = materializeClipboardTileItem(data, entry.item, layerIndex)
    if source and source.pixels then
      local snapPixels = {}
      for i = 1, 64 do
        local v = source.pixels[i]
        if v == nil then v = 0 end
        snapPixels[i] = v
      end
      entry.item = { pixels = snapPixels }
    end
  end
  data.sourceWin = nil
  return data
end

local function doCopy(ctx, focus)
  local avail = M.getActionAvailability(ctx, focus, "copy")
  if not avail.allowed then
    if avail.restricted then
      showWarning(ctx, avail.reason)
    end
    return true
  end

  local layerIndex = avail.layerIndex
  local layer = avail.layer
  if layer.kind == "tile" then
    clipboard = captureTileClipboard(focus, layer, layerIndex)
    if clipboard and clipboard.count > 0 then
      setStatus(ctx, (clipboard.count == 1) and "Copied 1 tile" or string.format("Copied %d tiles", clipboard.count))
    else
      setStatus(ctx, "No tiles selected to copy")
    end
    return true
  end

  if layer.kind == "sprite" then
    clipboard = captureSpriteClipboard(focus, layer)
    if clipboard and clipboard.count > 0 then
      setStatus(ctx, (clipboard.count == 1) and "Copied 1 sprite" or string.format("Copied %d sprites", clipboard.count))
    else
      setStatus(ctx, "No sprites selected to copy")
    end
    return true
  end

  return true
end

local function doPaste(ctx, focus, opts)
  local avail = M.getActionAvailability(ctx, focus, "paste", opts)
  if not avail.allowed then
    if avail.restricted or avail.noFocus then
      showWarning(ctx, avail.reason)
    else
      setStatus(ctx, avail.reason)
    end
    return true
  end

  local layerIndex = avail.layerIndex
  local layer = avail.layer
  local pasteResult = {
    count = 0,
    shifted = false,
    source = "none",
    reason = nil,
  }
  if clipboard.kind == "tile" and layer.kind == "tile" then
    pasteResult = pasteTileClipboard(ctx, focus, layer, layerIndex, clipboard, opts) or pasteResult
    local pastedCount = tonumber(pasteResult.count) or 0
    if pastedCount > 0 and ctx.app and ctx.app.markUnsaved then
      ctx.app:markUnsaved("tile_move")
    end
    if pastedCount > 0 then
      local message = (pastedCount == 1) and "Pasted 1 tile" or string.format("Pasted %d tiles", pastedCount)
      if pasteResult.shifted == true then
        message = message .. " (shifted to fit bounds)"
      end
      setStatus(ctx, message)
    else
      setStatus(ctx, pasteResult.reason or "Nothing pasted")
    end
    return true
  end

  if clipboard.kind == "sprite" and layer.kind == "sprite" then
    pasteResult = pasteSpriteClipboard(ctx, focus, layer, clipboard, opts) or pasteResult
    local pastedCount = tonumber(pasteResult.count) or 0
    if pastedCount > 0 and ctx.app and ctx.app.markUnsaved then
      ctx.app:markUnsaved("sprite_move")
    end
    if pastedCount > 0 then
      local message = (pastedCount == 1) and "Pasted 1 sprite" or string.format("Pasted %d sprites", pastedCount)
      if pasteResult.shifted == true then
        message = message .. " (shifted to fit bounds)"
      end
      setStatus(ctx, message)
    else
      setStatus(ctx, pasteResult.reason or "Nothing pasted")
    end
    return true
  end

  setStatus(ctx, "Clipboard content does not match active layer type")
  return true
end

local function doCut(ctx, focus, opts)
  local avail = M.getActionAvailability(ctx, focus, "cut", opts)
  if not avail.allowed then
    if avail.restricted then
      showWarning(ctx, avail.reason)
    else
      setStatus(ctx, avail.reason)
    end
    return true
  end

  local layerIndex = avail.layerIndex
  local layer = avail.layer
  if layer.kind == "tile" then
    local copied = captureTileClipboard(focus, layer, layerIndex)
    if not (copied and copied.count and copied.count > 0) then
      setStatus(ctx, "No tiles selected to cut")
      return true
    end
    if WindowCaps.isChrLike(focus) then
      copied = freezeTileClipboardItems(copied, layerIndex)
    end
    clipboard = copied

    local result = nil
    if WindowCaps.isChrLike(focus) then
      result = cutChrTileSelection(ctx, focus, layer, layerIndex)
    else
      local fallbackCol, fallbackRow = nil, nil
      if focus.getSelected then
        fallbackCol, fallbackRow = focus:getSelected()
      end
      result = MultiSelectController.deleteTileSelection(
        focus,
        layerIndex,
        fallbackCol,
        fallbackRow,
        ctx and ctx.app or nil,
        ctx and ctx.app and ctx.app.undoRedo or nil
      )
      if result and result.count and result.count > 0 and ctx and ctx.app and ctx.app.markUnsaved then
        ctx.app:markUnsaved("tile_move")
      end
    end
    if result and result.count and result.count > 0 then
      setStatus(ctx, (result.count == 1) and "Cut 1 tile" or string.format("Cut %d tiles", result.count))
    else
      setStatus(ctx, "Nothing cut")
    end
    return true
  end

  if layer.kind == "sprite" then
    local copied = captureSpriteClipboard(focus, layer)
    if not (copied and copied.count and copied.count > 0) then
      setStatus(ctx, "No sprites selected to cut")
      return true
    end
    clipboard = copied
    local result = MultiSelectController.deleteSpriteSelection(focus, layerIndex, ctx and ctx.app and ctx.app.undoRedo or nil)
    if result and result.count and result.count > 0 then
      if ctx and ctx.app and ctx.app.markUnsaved then
        ctx.app:markUnsaved("sprite_move")
      end
      setStatus(ctx, (result.count == 1) and "Cut 1 sprite" or string.format("Cut %d sprites", result.count))
    elseif result and result.status then
      showWarning(ctx, result.status)
    else
      setStatus(ctx, "Nothing cut")
    end
    return true
  end

  return true
end

function M.performClipboardAction(ctx, focus, action, opts)
  if action == "copy" then
    return doCopy(ctx, focus)
  end
  if action == "cut" then
    return doCut(ctx, focus, opts)
  end
  if action == "paste" then
    return doPaste(ctx, focus, opts)
  end
  return false
end

function M.hasClipboardData()
  return clipboard ~= nil and clipboard.kind ~= nil
end

function M.handleCopySelection(ctx, utils, key, focus)
  if key ~= "c" and key ~= "C" then return false end
  if not (utils.ctrlDown and utils.ctrlDown()) then return false end
  if (utils.altDown and utils.altDown()) or (utils.shiftDown and utils.shiftDown()) then return false end
  if ctx.getMode() == "edit" then return false end
  return M.performClipboardAction(ctx, focus, "copy")
end

function M.handleCutSelection(ctx, utils, key, focus)
  if key ~= "x" and key ~= "X" then return false end
  if not (utils.ctrlDown and utils.ctrlDown()) then return false end
  if (utils.altDown and utils.altDown()) or (utils.shiftDown and utils.shiftDown()) then return false end
  if ctx.getMode() == "edit" then return false end
  return M.performClipboardAction(ctx, focus, "cut")
end

function M.handlePasteSelection(ctx, utils, key, focus)
  if key ~= "v" and key ~= "V" then return false end
  if not (utils.ctrlDown and utils.ctrlDown()) then return false end
  if (utils.altDown and utils.altDown()) or (utils.shiftDown and utils.shiftDown()) then return false end
  if ctx.getMode() == "edit" then return false end
  return M.performClipboardAction(ctx, focus, "paste")
end

return M
