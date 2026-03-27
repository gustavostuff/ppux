local MultiSelectController = require("controllers.input_support.multi_select_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local clipboard = nil

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

local function pasteTileClipboard(ctx, focus, layer, layerIndex, data)
  if not (focus and layer and layer.kind == "tile" and data and data.entries) then return 0 end

  local cols = focus.cols or 0
  local rows = focus.rows or 0
  if cols <= 0 or rows <= 0 then return 0 end

  local anchorCol = math.floor((cols - (data.width or 1)) / 2)
  local anchorRow = math.floor((rows - (data.height or 1)) / 2)
  local selectedSet = {}
  local count = 0
  local firstCol, firstRow = nil, nil
  local tilesPool = ctx.app and ctx.app.appEditState and ctx.app.appEditState.tilesPool

  for _, entry in ipairs(data.entries) do
    local col = anchorCol + (entry.offsetCol or 0)
    local row = anchorRow + (entry.offsetRow or 0)
    if col >= 0 and col < cols and row >= 0 and row < rows then
      if WindowCaps.isPpuFrame(focus) and focus.setNametableByteAt and entry.byte ~= nil then
        focus:setNametableByteAt(col, row, entry.byte, tilesPool, layerIndex)
      elseif focus.set then
        focus:set(col, row, materializeClipboardTileItem(data, entry.item, layerIndex), layerIndex)
      end
      local idx = (row * cols + col) + 1
      selectedSet[idx] = true
      count = count + 1
      if not firstCol then
        firstCol, firstRow = col, row
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

local function pasteSpriteClipboard(focus, layer, data)
  if not (focus and layer and layer.kind == "sprite" and data and data.entries) then return 0 end

  layer.items = layer.items or {}

  local layerPixelW = math.max(1, (focus.cols or 0) * (focus.cellW or 8))
  local layerPixelH = math.max(1, (focus.rows or 0) * (focus.cellH or 8))
  local anchorX = math.floor((layerPixelW - (data.widthPx or 1)) / 2)
  local anchorY = math.floor((layerPixelH - (data.heightPx or 1)) / 2)

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

function M.handleCopySelection(ctx, utils, key, focus)
  if key ~= "c" and key ~= "C" then return false end
  if not (utils.ctrlDown and utils.ctrlDown()) then return false end
  if (utils.altDown and utils.altDown()) or (utils.shiftDown and utils.shiftDown()) then return false end
  if ctx.getMode() == "edit" then return false end
  if not (focus and focus.layers and focus.getActiveLayerIndex) then return true end

  local layerIndex = focus:getActiveLayerIndex()
  local layer = focus.layers[layerIndex]
  if not layer then return true end

  if layer.kind == "tile" then
    clipboard = captureTileClipboard(focus, layer, layerIndex)
    if clipboard and clipboard.count > 0 then
      ctx.setStatus((clipboard.count == 1) and "Copied 1 tile" or string.format("Copied %d tiles", clipboard.count))
    else
      ctx.setStatus("No tiles selected to copy")
    end
    return true
  end

  if layer.kind == "sprite" then
    clipboard = captureSpriteClipboard(focus, layer)
    if clipboard and clipboard.count > 0 then
      ctx.setStatus((clipboard.count == 1) and "Copied 1 sprite" or string.format("Copied %d sprites", clipboard.count))
    else
      ctx.setStatus("No sprites selected to copy")
    end
    return true
  end

  return true
end

function M.handlePasteSelection(ctx, utils, key, focus)
  if key ~= "v" and key ~= "V" then return false end
  if not (utils.ctrlDown and utils.ctrlDown()) then return false end
  if (utils.altDown and utils.altDown()) or (utils.shiftDown and utils.shiftDown()) then return false end
  if ctx.getMode() == "edit" then return false end
  if not (focus and focus.layers and focus.getActiveLayerIndex) then return true end

  if not clipboard or not clipboard.kind then
    ctx.setStatus("Clipboard is empty")
    return true
  end

  local layerIndex = focus:getActiveLayerIndex()
  local layer = focus.layers[layerIndex]
  if not layer then return true end

  local pastedCount = 0
  if clipboard.kind == "tile" and layer.kind == "tile" then
    pastedCount = pasteTileClipboard(ctx, focus, layer, layerIndex, clipboard)
    if pastedCount > 0 and ctx.app and ctx.app.markUnsaved then
      ctx.app:markUnsaved("tile_move")
    end
    if pastedCount > 0 then
      ctx.setStatus((pastedCount == 1) and "Pasted 1 tile at center" or string.format("Pasted %d tiles at center", pastedCount))
    else
      ctx.setStatus("Nothing pasted")
    end
    return true
  end

  if clipboard.kind == "sprite" and layer.kind == "sprite" then
    if WindowCaps.isOamAnimation(focus) then
      ctx.setStatus("Cannot add sprites to OAM animation windows")
      return true
    end
    pastedCount = pasteSpriteClipboard(focus, layer, clipboard)
    if pastedCount > 0 and ctx.app and ctx.app.markUnsaved then
      ctx.app:markUnsaved("sprite_move")
    end
    if pastedCount > 0 then
      ctx.setStatus((pastedCount == 1) and "Pasted 1 sprite at center" or string.format("Pasted %d sprites at center", pastedCount))
    else
      ctx.setStatus("Nothing pasted")
    end
    return true
  end

  ctx.setStatus("Clipboard content does not match active layer type")
  return true
end

return M
