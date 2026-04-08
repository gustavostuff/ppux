local SpriteController = require("controllers.sprite.sprite_controller")
local SpriteOriginDrag = require("controllers.sprite.sprite_origin_drag_controller")
local MultiSelectController = require("controllers.input_support.multi_select_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}
local romPaletteCellDoubleClick = {
  win = nil,
  col = nil,
  row = nil,
  at = -math.huge,
}
local ROM_PALETTE_DOUBLE_CLICK_SECONDS = 0.35

local function nowSeconds(env)
  if env and type(env.nowSeconds) == "function" then
    return env.nowSeconds()
  end
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function rememberRomPaletteCellClick(win, col, row, at)
  romPaletteCellDoubleClick.win = win
  romPaletteCellDoubleClick.col = col
  romPaletteCellDoubleClick.row = row
  romPaletteCellDoubleClick.at = at or -math.huge
end

local function clearRomPaletteCellClick()
  rememberRomPaletteCellClick(nil, nil, nil, -math.huge)
end

local function clearSpriteSelection(env, win)
  if not win or not win.layers then return end
  for _, layer in ipairs(win.layers) do
    if layer.kind == "sprite" then
      SpriteController.clearSpriteSelection(layer)
      layer.hoverSpriteIndex = nil
    end
  end
end

local function showSelectedTileLabel(ctx, win, col, row, item)
  if WindowCaps.isChrLike(win) then
    local toolbar = win.specializedToolbar
    if not toolbar then return end

    local tileIndex = (item and type(item.index) == "number") and item.index or nil
    if tileIndex == nil then
      local cols = win.cols or 0
      tileIndex = (row * cols) + col
    end

    if toolbar.showTileLabel then
      toolbar:showTileLabel(tileIndex)
      return
    end

    if toolbar.triggerLayerLabelTextFlash then
      toolbar:triggerLayerLabelTextFlash(string.format("tile %d (%02X hex)", tileIndex, tileIndex % 0x100))
    elseif toolbar.triggerLayerLabelFlash then
      toolbar:triggerLayerLabelFlash(string.format("tile %d (%02X hex)", tileIndex, tileIndex % 0x100))
    end
    return
  end

  if ctx and ctx.showBankTileLabel then
    ctx.showBankTileLabel(item)
  end
end

local function isTileMultiSelectWindow(env, win, layerIdx)
  local ctx = env.ctx
  if ctx.getMode() ~= "tile" then return false end
  if not (WindowCaps.isStaticOrAnimationArt(win) or WindowCaps.isChrLike(win) or WindowCaps.isPpuFrame(win)) then return false end
  local layer = win.layers and win.layers[layerIdx]
  return layer and layer.kind == "tile"
end

local function isChr8x16SelectionMode(win)
  return WindowCaps.isChrLike(win) and win.orderMode == "oddEven"
end

local function canonicalizeChr8x16Target(win, layerIdx, col, row, item)
  if not isChr8x16SelectionMode(win) then
    return col, row, item
  end

  local topRow = row - (row % 2)
  local topItem = item
  if win.getVirtualTileHandle then
    topItem = win:getVirtualTileHandle(col, topRow, layerIdx)
  elseif win.get then
    topItem = win:get(col, topRow, layerIdx)
  end
  return col, topRow, topItem
end

local function isSpriteMultiSelectWindow(env, win, layerIdx)
  local ctx = env.ctx
  if ctx.getMode() ~= "tile" then return false end
  if not (WindowCaps.isStaticOrAnimationArt(win) or WindowCaps.isPpuFrame(win)) then return false end
  local layer = win.layers and win.layers[layerIdx]
  return layer and layer.kind == "sprite"
end

local function startTileDrag(env, win, col, row, layerIdx, item, wm, x, y, copyMode, tileGroup)
  local drag = env.drag
  drag.pending = true
  drag.startX, drag.startY = x, y
  drag.srcWin, drag.srcCol, drag.srcRow, drag.srcLayer = win, col, row, layerIdx
  drag.item = item
  drag.copyMode = (copyMode == true)
  drag.tileGroup = tileGroup
  drag.srcTemporarilyCleared = false

  local stack = win:getStack(col, row, layerIdx)
  drag.srcStackIndex = (stack and #stack) or 1
end

local function handleSpriteClick(env, button, x, y, win, wm)
  local ctx = env.ctx
  local utils = env.utils or {}
  local getSpriteClick = env.getSpriteClick
  local setSpriteClick = env.setSpriteClick

  if button ~= 1 or ctx.getMode() ~= "tile" then return false end
  if not (win and win.layers and win.getActiveLayerIndex) then return false end

  local li = win:getActiveLayerIndex()
  local L = win.layers[li]
  if not (L and L.kind == "sprite") then return false end

  local shiftDown = utils.shiftDown and utils.shiftDown()
  local ctrlDown = utils.ctrlDown and utils.ctrlDown()

  if shiftDown and isSpriteMultiSelectWindow(env, win, li) then
    setSpriteClick({ active = false })
    wm:setFocus(win)
    SpriteController.startSpriteMarquee(win, li, x, y, false)
    SpriteController.clearSpriteSelection(L)
    L.hoverSpriteIndex = nil
    return true
  end

  local layerIndex, itemIndex, offsetX, offsetY = SpriteController.pickSpriteAt(win, x, y, li)
  SpriteController.updateSpriteMarquee(x, y)

  if layerIndex and itemIndex then
    wm:setFocus(win)

    local targetIndex = itemIndex
    local currentSel = SpriteController.getSelectedSpriteIndices(L)
    local currentSelOrdered = SpriteController.getSelectedSpriteIndicesInOrder(L)
    if #currentSel == 0 and L.selectedSpriteIndex then
      currentSel = { L.selectedSpriteIndex }
    end
    if #currentSelOrdered == 0 and L.selectedSpriteIndex then
      currentSelOrdered = { L.selectedSpriteIndex }
    end
    local contains = false
    for _, idx in ipairs(currentSel) do
      if idx == itemIndex then contains = true break end
    end

    if ctrlDown then
      if not contains then
        local nextSel = {}
        for _, idx in ipairs(currentSelOrdered) do
          nextSel[#nextSel + 1] = idx
        end
        nextSel[#nextSel + 1] = itemIndex
        SpriteController.setSpriteSelection(L, nextSel)
      end
      targetIndex = itemIndex
    else
      local multiSelected = (#currentSel > 1)
      if not (multiSelected and contains) then
        local newIndex = SpriteController.bringSpriteToFront(L, itemIndex)
        targetIndex = newIndex or itemIndex
        SpriteController.setSpriteSelection(L, { targetIndex })
      end
    end
    L.selectedSpriteIndex = targetIndex
    L.hoverSpriteIndex = targetIndex
    showSelectedTileLabel(ctx, win, 0, 0, L.items and L.items[targetIndex] or nil)

    if not shiftDown then
      setSpriteClick({
        active = true,
        moved = false,
        startX = x,
        startY = y,
        win = win,
        layerIndex = layerIndex,
        targetIndex = targetIndex,
        ctrlSelection = ctrlDown and true or false,
      })
    else
      setSpriteClick({ active = false })
    end

    SpriteController.beginDrag(win, layerIndex, targetIndex, offsetX, offsetY, ctrlDown)
    return true
  end

  setSpriteClick({ active = false })
  SpriteController.clearSpriteSelection(L)
  L.hoverSpriteIndex = nil
  return true
end

local function handleRightButton(env, button, x, y, win, wm)
  local function isOverToolbarControl(toolbar)
    if not toolbar then return false end
    if toolbar.updatePosition then
      toolbar:updatePosition()
    end
    if (toolbar.getButtonAt and toolbar:getButtonAt(x, y))
      or (toolbar.getLabelAt and toolbar:getLabelAt(x, y))
    then
      return true
    end
    return false
  end

  local function beginPpuTileContextClick()
    if not (win and WindowCaps.isPpuFrame(win) and env.beginContextMenuClick) then
      return false
    end

    local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
    local layer = win.layers and win.layers[li] or nil
    if not (layer and layer.kind == "tile") then
      return false
    end

    local pickByVisual = env.utils and env.utils.pickByVisual or nil
    if type(pickByVisual) ~= "function" then
      return false
    end

    local hit, col, row, item = pickByVisual(win, x, y, li)
    if not (hit and item and type(col) == "number" and type(row) == "number") then
      return false
    end

    env.beginContextMenuClick("ppu_tile", x, y, button, win, {
      layerIndex = li,
      col = col,
      row = row,
    })
    return true
  end

  local function beginSelectInChrContextClick()
    if not (win and env.beginContextMenuClick) then
      return false
    end

    if not (WindowCaps.isPpuFrame(win) or WindowCaps.isStaticOrAnimationArt(win)) then
      return false
    end

    local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
    local layer = win.layers and win.layers[li] or nil
    if not layer then
      return false
    end

    if layer.kind == "tile" then
      local pickByVisual = env.utils and env.utils.pickByVisual or nil
      if type(pickByVisual) ~= "function" then
        return false
      end

      local hit, col, row, item = pickByVisual(win, x, y, li)
      if not (hit and item and type(col) == "number" and type(row) == "number") then
        return false
      end

      env.beginContextMenuClick("select_in_chr", x, y, button, win, {
        layerIndex = li,
        col = col,
        row = row,
      })
      return true
    end

    if layer.kind == "sprite" then
      local pickedLayerIndex, itemIndex = SpriteController.pickSpriteAt(win, x, y, li)
      if not (type(pickedLayerIndex) == "number" and type(itemIndex) == "number") then
        return false
      end

      env.beginContextMenuClick("select_in_chr", x, y, button, win, {
        layerIndex = pickedLayerIndex,
        itemIndex = itemIndex,
      })
      return true
    end

    return false
  end

  local function beginOamSpriteEmptySpaceContextClick()
    if not (win and env.beginContextMenuClick and WindowCaps.isOamAnimation(win)) then
      return false
    end

    local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
    local layer = win.layers and win.layers[li] or nil
    if not (layer and layer.kind == "sprite") then
      return false
    end

    local pickedLayerIndex, itemIndex = SpriteController.pickSpriteAt(win, x, y, li)
    if type(pickedLayerIndex) == "number" and type(itemIndex) == "number" then
      return false
    end

    local inContent = false
    if win.toGridCoords then
      inContent = (select(1, win:toGridCoords(x, y)) == true)
    end
    if not inContent then
      return false
    end

    env.beginContextMenuClick("oam_sprite_empty", x, y, button, win, {
      layerIndex = li,
    })
    return true
  end

  if button == 2 or button == 3 then
    if win then
      if isOverToolbarControl(win.specializedToolbar) or isOverToolbarControl(win.headerToolbar) then
        return true
      end
      wm:setFocus(win)
      if button == 2 then
        if SpriteOriginDrag.tryBeginPress(env.ctx, env.utils or {}, x, y, win, wm) then
          win:mousepressed(x, y, button)
          return true
        end
      end
      if beginPpuTileContextClick() then
        win:mousepressed(x, y, button)
        return true
      end
      if beginSelectInChrContextClick() then
        win:mousepressed(x, y, button)
        return true
      end
      if beginOamSpriteEmptySpaceContextClick() then
        win:mousepressed(x, y, button)
        return true
      end
      win:mousepressed(x, y, button)
    else
      wm:setFocus(nil)
      if env.beginContextMenuClick then
        env.beginContextMenuClick("empty_space", x, y, button, nil)
      end
    end
    return true
  end
  return false
end

local function handlePaletteClick(env, button, x, y, win, wm)
  local ctx = env.ctx
  if button ~= 1 or not win or not win.isPalette then return false end

  wm:setFocus(win)

  if win.kind ~= "rom_palette" and not win.activePalette then
    ctx.setStatus("Activate palette before using it")
    return true
  end

  local ok, col, row = win:toGridCoords(x, y)
  if ok and col >= 0 and col < win.cols and row >= 0 and row < win.rows then
    if WindowCaps.isRomPaletteWindow(win) and win.isCellEditable and not win:isCellEditable(col, row) then
      local at = nowSeconds(env)
      local sameCell = romPaletteCellDoubleClick.win == win
        and romPaletteCellDoubleClick.col == col
        and romPaletteCellDoubleClick.row == row
      local isDoubleClick = sameCell and ((at - (romPaletteCellDoubleClick.at or -math.huge)) <= ROM_PALETTE_DOUBLE_CLICK_SECONDS)
      if isDoubleClick then
        clearRomPaletteCellClick()
        local app = ctx and ctx.app or nil
        if app and app.showRomPaletteAddressModal then
          app:showRomPaletteAddressModal(win, col, row)
        else
          ctx.setStatus("ROM address entry is unavailable")
        end
        return true
      end
      rememberRomPaletteCellClick(win, col, row, at)
      ctx.setStatus("Double-click to assign ROM palette address")
      return true
    end

    clearRomPaletteCellClick()

    win:setSelected(col, row)

    local app = ctx.app
    if app then
      if win.rows == 1 and win.cols == 4 then
        app.currentColor = col
        ctx.setStatus(string.format("Selected color %d", col))
      else
        local colorIndex = row * win.cols + col
        app.currentColor = colorIndex
        ctx.setStatus(string.format("Selected color %d", colorIndex))
      end
    end
  end

  return true
end

local function handleEditModeClick(env, button, x, y, win, wm)
  local ctx = env.ctx
  local utils = env.utils or {}
  if button ~= 1 or ctx.getMode() ~= "edit" then return false end

  local focused = wm:getFocus()

  if win then
    if win ~= focused then
      wm:setFocus(win)
      ctx.setPainting(false)
      return true
    end
  else
    wm:setFocus(nil)
    ctx.setPainting(false)
    return true
  end

  if win.isPalette then return true end

  local ok, col, row, lx, ly = win:toGridCoords(x, y)
  if ok then
    if utils.fillDown and utils.fillDown() then
      local BrushController = require("controllers.input_support.brush_controller")
      local success = BrushController.floodFillTile(ctx.app, win, col, row, lx, ly)
      if success then
        ctx.setStatus("Flood fill applied")
      else
        ctx.setStatus("Flood fill failed")
      end
      ctx.setPainting(false)
    elseif utils.shiftDown and utils.shiftDown() then
      local px = col * (win.cellW or 8) + math.floor(lx or 0)
      local py = row * (win.cellH or 8) + math.floor(ly or 0)
      win.editShapeDrag = {
        kind = "rect_or_line",
        startX = px,
        startY = py,
        currentX = px,
        currentY = py,
        moved = false,
      }
      ctx.setPainting(false)
    elseif ctx.app and ctx.app.editTool == "rect_fill" then
      local px = col * (win.cellW or 8) + math.floor(lx or 0)
      local py = row * (win.cellH or 8) + math.floor(ly or 0)
      win.editShapeDrag = {
        kind = "rect_fill",
        startX = px,
        startY = py,
        currentX = px,
        currentY = py,
        moved = false,
      }
      ctx.setPainting(false)
    elseif utils.grabDown and utils.grabDown() then
      ctx.paintAt(win, col, row, lx, ly, true)
      ctx.setPainting(false)
    else
      if ctx.app and ctx.app.undoRedo then
        ctx.app.undoRedo:startPaintEvent()
      end
      ctx.paintAt(win, col, row, lx, ly, false)
      ctx.setPainting(true)
    end
  end
  return true
end

local function handleTilePaintMode(env, button, x, y, win, wm)
  local ctx = env.ctx
  local utils = env.utils or {}
  local tilePaintState = env.tilePaintState

  if button ~= 1 then return false end
  if ctx.getMode() ~= "tile" then return false end
  if not ((utils.ctrlDown and utils.ctrlDown()) and (utils.altDown and utils.altDown())) then return false end

  if not win then return false end
  if not WindowCaps.isStaticOrAnimationArt(win) then return false end

  local layerIdx = win:getActiveLayerIndex()
  local layer = win.layers and win.layers[layerIdx]
  if not layer or layer.kind ~= "tile" then return false end

  local ok, col, row = win:toGridCoords(x, y)
  if not ok then return false end

  local existingItem = win:get(col, row, layerIdx)
  if existingItem then return false end

  local selectedTile = utils.getSelectedTileFromCHR and utils.getSelectedTileFromCHR()
  if not selectedTile then
    ctx.setStatus("No tile selected in CHR window")
    return false
  end

  wm:setFocus(win)
  win:set(col, row, selectedTile, layerIdx)
  win:setSelected(col, row, layerIdx)

  if tilePaintState then
    tilePaintState.active = true
    tilePaintState.lastCol = col
    tilePaintState.lastRow = row
  end

  ctx.setStatus("Tile paint mode active")
  return true
end

local function handleTileSelection(env, button, x, y, win, wm)
  local ctx = env.ctx
  local utils = env.utils or {}
  local getTileClick = env.getTileClick
  local setTileClick = env.setTileClick

  if button ~= 1 then return false end
  if ctx.getMode() ~= "tile" then return false end
  if not win then
    wm:setFocus(nil)
    return true
  end

  wm:setFocus(win)
  local layerIdx = win:getActiveLayerIndex()
  if win.layers and win.layers[layerIdx] and win.layers[layerIdx].kind == "sprite" then
    return false
  end

  if (utils.shiftDown and utils.shiftDown()) and isTileMultiSelectWindow(env, win, layerIdx) then
    setTileClick({ active = false })
    local ok, col, row = win:toGridCoords(x, y)
    if ok then
      MultiSelectController.startTileMarquee(win, layerIdx, col, row, x, y)
    else
      MultiSelectController.clearTileMultiSelection(win, layerIdx)
      win:clearSelected(layerIdx)
      clearSpriteSelection(env, win)
    end
    return true
  end

  local hit, vcol, vrow, vitem = utils.pickByVisual(win, x, y, layerIdx)
  local ctrlDown = utils.ctrlDown and utils.ctrlDown()

  if hit and vitem then
    vcol, vrow, vitem = canonicalizeChr8x16Target(win, layerIdx, vcol, vrow, vitem)
    local tileGroup = nil
    if isChr8x16SelectionMode(win) then
      if ctrlDown then
        MultiSelectController.addTileCellToSelection(win, layerIdx, vcol, vrow, true)
      end
      tileGroup = MultiSelectController.buildTileDragGroup(win, layerIdx, vcol, vrow)
    elseif ctrlDown then
      MultiSelectController.addTileCellToSelection(win, layerIdx, vcol, vrow, true)
      tileGroup = MultiSelectController.buildTileDragGroup(win, layerIdx, vcol, vrow)
    elseif MultiSelectController.isTileCellSelected(win, layerIdx, vcol, vrow) then
      tileGroup = MultiSelectController.buildTileDragGroup(win, layerIdx, vcol, vrow)
    end

    if not ctrlDown then
      setTileClick({
        active = true,
        moved = false,
        win = win,
        layerIdx = layerIdx,
        col = vcol,
        row = vrow,
      })
    else
      setTileClick({ active = false })
    end
    if not ctrlDown then
      win:setSelected(vcol, vrow, layerIdx)
    end
    showSelectedTileLabel(ctx, win, vcol, vrow, vitem)
    startTileDrag(env, win, vcol, vrow, layerIdx, vitem, wm, x, y, ctrlDown, tileGroup)
    return true
  end

  local ok, col, row = win:toGridCoords(x, y)
  if ok then
    local item = (win.getVirtualTileHandle and win:getVirtualTileHandle(col, row, layerIdx))
      or win:get(col, row, layerIdx)
    if item then
      col, row, item = canonicalizeChr8x16Target(win, layerIdx, col, row, item)
      local tileGroup = nil
      if isChr8x16SelectionMode(win) then
        if ctrlDown then
          MultiSelectController.addTileCellToSelection(win, layerIdx, col, row, true)
        end
        tileGroup = MultiSelectController.buildTileDragGroup(win, layerIdx, col, row)
      elseif ctrlDown then
        MultiSelectController.addTileCellToSelection(win, layerIdx, col, row, true)
        tileGroup = MultiSelectController.buildTileDragGroup(win, layerIdx, col, row)
      elseif MultiSelectController.isTileCellSelected(win, layerIdx, col, row) then
        tileGroup = MultiSelectController.buildTileDragGroup(win, layerIdx, col, row)
      end

      if not ctrlDown then
        setTileClick({
          active = true,
          moved = false,
          win = win,
          layerIdx = layerIdx,
          col = col,
          row = row,
        })
      else
        setTileClick({ active = false })
      end
      if not ctrlDown then
        win:setSelected(col, row, layerIdx)
      end
      showSelectedTileLabel(ctx, win, col, row, item)
      startTileDrag(env, win, col, row, layerIdx, item, wm, x, y, ctrlDown, tileGroup)
    else
      setTileClick({ active = false })
      MultiSelectController.clearTileMultiSelection(win, layerIdx)
      win:clearSelected()
      clearSpriteSelection(env, win)
    end
  else
    setTileClick({ active = false })
    MultiSelectController.clearTileMultiSelection(win, layerIdx)
    win:clearSelected()
    clearSpriteSelection(env, win)
  end
  return true
end

function M._resetRomPaletteDoubleClickState()
  clearRomPaletteCellClick()
end

local function handlePaletteDestinationLinkClick(env, button, x, y, wm)
  return false
end

local function handlePaletteLinkContextClick(env, button, x, y, win, wm)
  if not (button == 2 or button == 3) then
    return false
  end
  if not (win and win.specializedToolbar and env.beginContextMenuClick) then
    return false
  end
  if not PaletteLinkController.isPointInToolbarLinkHandle(win.specializedToolbar, x, y) then
    return false
  end

  if wm and wm.setFocus then
    wm:setFocus(win)
  end

  if WindowCaps.isRomPaletteWindow(win) then
    env.beginContextMenuClick("palette_link_source", x, y, button, win)
    return true
  end

  if WindowCaps.isAnyPaletteWindow(win) or WindowCaps.isChrLike(win) then
    return false
  end

  env.beginContextMenuClick("palette_link_destination", x, y, button, win, {
    layerIndex = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1,
  })
  return true
end

function M.handleMousePressed(env, x, y, button)
  local ctx = env.ctx
  local wm = ctx.wm()
  local chrome = env.chrome
  local toolbarWin = chrome.findToolbarWindowAt and chrome.findToolbarWindowAt(x, y, wm) or nil

  if handlePaletteLinkContextClick(env, button, x, y, toolbarWin, wm) then
    return true
  end

  if handlePaletteDestinationLinkClick(env, button, x, y, wm) then
    return true
  end

  local topInteractiveWin = chrome.getTopInteractiveWindowAt and chrome.getTopInteractiveWindowAt(x, y, wm) or nil

  local focusedWin = wm:getFocus()
  if focusedWin and focusedWin == topInteractiveWin and chrome.handleToolbarClicks(button, x, y, focusedWin, wm) then
    return true
  end

  if toolbarWin and toolbarWin ~= focusedWin then
    if chrome.handleToolbarClicks(button, x, y, toolbarWin, wm) then
      return true
    end
  end

  if chrome.handleResizeHandle(button, x, y, wm) then return true end

  local win = topInteractiveWin or wm:windowAt(x, y)
  if chrome.handleHeaderClick(button, x, y, win, wm, {
    onWindowTitleDoubleClick = function(targetWindow)
      local app = env.ctx and env.ctx.app or nil
      if app and app.showRenameWindowModal then
        app:showRenameWindowModal(targetWindow)
      end
    end,
    onWindowTitleContextMenu = function(targetWindow, menuX, menuY)
      if env.beginContextMenuClick then
        env.beginContextMenuClick("window_header", menuX, menuY, button, targetWindow)
      end
    end,
  }) then return true end
  if chrome.handleToolbarClicks(button, x, y, win, wm) then return true end

  if handlePaletteClick(env, button, x, y, win, wm) then return true end
  if handleSpriteClick(env, button, x, y, win, wm) then return true end
  if handleRightButton(env, button, x, y, win, wm) then return true end
  if handleEditModeClick(env, button, x, y, win, wm) then return true end
  if handleTilePaintMode(env, button, x, y, win, wm) then return true end
  if handleTileSelection(env, button, x, y, win, wm) then return true end

  return false
end

return M
