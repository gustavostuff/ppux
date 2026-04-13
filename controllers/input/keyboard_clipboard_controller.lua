local MultiSelectController = require("controllers.input_support.multi_select_controller")
local WindowCaps = require("controllers.window.window_capabilities")

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
  local mx, my = ctx.scaledMouse()
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
  local cells = MultiSelectController.getSelectedTileCells(win, layerIndex, fallbackCol, fallbackRow)
  if #cells == 0 then return nil end

  local minCol, minRow = math.huge, math.huge
  local maxCol, maxRow = -math.huge, -math.huge
  local entries = {}

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

local function pasteTileClipboard(ctx, focus, layer, layerIndex, data, opts)
  if not (focus and layer and layer.kind == "tile" and data and data.entries) then return 0 end

  local cols = focus.cols or 0
  local rows = focus.rows or 0
  if cols <= 0 or rows <= 0 then return 0 end

  local anchorCol = (opts and type(opts.anchorCol) == "number") and math.floor(opts.anchorCol)
  local anchorRow = (opts and type(opts.anchorRow) == "number") and math.floor(opts.anchorRow)
  if anchorCol == nil or anchorRow == nil then
    local mx, my = resolveScaledMouse(ctx)
    if mx ~= nil and my ~= nil and focus.toGridCoords then
      local ok, col, row = focus:toGridCoords(mx, my)
      if ok then
        anchorCol = col
        anchorRow = row
      end
    end
  end
  if anchorCol == nil or anchorRow == nil then
    anchorCol = math.floor((cols - (data.width or 1)) / 2)
    anchorRow = math.floor((rows - (data.height or 1)) / 2)
  end
  local selectedSet = {}
  local count = 0
  local firstCol, firstRow = nil, nil
  local tilesPool = ctx.app and ctx.app.appEditState and ctx.app.appEditState.tilesPool

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
        focus:setNametableByteAt(col, row, entry.byte, tilesPool, layerIndex)
        applied = true
      elseif WindowCaps.isChrLike(focus) then
        local srcItem = materializeClipboardTileItem(data, entry.item, layerIndex)
        local dstItem = nil
        if focus.get then
          dstItem = focus:get(col, row, layerIndex)
        end
        applied = copyPixelsByValue(dstItem, srcItem)
      elseif focus.set then
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

  return count
end

local function pasteSpriteClipboard(ctx, focus, layer, data, opts)
  if not (focus and layer and layer.kind == "sprite" and data and data.entries) then return 0 end

  layer.items = layer.items or {}

  local layerPixelW = math.max(1, (focus.cols or 0) * (focus.cellW or 8))
  local layerPixelH = math.max(1, (focus.rows or 0) * (focus.cellH or 8))
  local anchorX = (opts and type(opts.anchorX) == "number") and math.floor(opts.anchorX)
  local anchorY = (opts and type(opts.anchorY) == "number") and math.floor(opts.anchorY)
  if anchorX == nil or anchorY == nil then
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
  end
  if anchorX == nil or anchorY == nil then
    anchorX = math.floor((layerPixelW - (data.widthPx or 1)) / 2)
    anchorY = math.floor((layerPixelH - (data.heightPx or 1)) / 2)
  end

  local newIndices = {}
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
  end

  if #newIndices > 0 then
    local SpriteController = require("controllers.sprite.sprite_controller")
    SpriteController.setSpriteSelection(layer, newIndices)
    layer.selectedSpriteIndex = newIndices[1]
    layer.hoverSpriteIndex = newIndices[1]
  end

  return #newIndices
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
  for _, cell in ipairs(cells) do
    local tile = focus.get and focus:get(cell.col, cell.row, layerIndex) or nil
    if tile and tile.pixels then
      local changed = false
      for i = 1, 64 do
        if tile.pixels[i] ~= 0 then
          tile.pixels[i] = 0
          changed = true
        end
      end
      if changed then
        cleared = cleared + 1
      end
    end
  end

  layer.multiTileSelection = nil
  if focus.clearSelected then
    focus:clearSelected(layerIndex)
  end
  if cleared == 0 then
    return nil
  end
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
  local pastedCount = 0
  if clipboard.kind == "tile" and layer.kind == "tile" then
    pastedCount = pasteTileClipboard(ctx, focus, layer, layerIndex, clipboard, opts)
    if pastedCount > 0 and ctx.app and ctx.app.markUnsaved then
      ctx.app:markUnsaved("tile_move")
    end
    if pastedCount > 0 then
      setStatus(ctx, (pastedCount == 1) and "Pasted 1 tile at center" or string.format("Pasted %d tiles at center", pastedCount))
    else
      setStatus(ctx, "Nothing pasted")
    end
    return true
  end

  if clipboard.kind == "sprite" and layer.kind == "sprite" then
    pastedCount = pasteSpriteClipboard(ctx, focus, layer, clipboard, opts)
    if pastedCount > 0 and ctx.app and ctx.app.markUnsaved then
      ctx.app:markUnsaved("sprite_move")
    end
    if pastedCount > 0 then
      setStatus(ctx, (pastedCount == 1) and "Pasted 1 sprite at center" or string.format("Pasted %d sprites at center", pastedCount))
    else
      setStatus(ctx, "Nothing pasted")
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
