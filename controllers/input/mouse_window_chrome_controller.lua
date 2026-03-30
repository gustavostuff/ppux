local WindowCaps = require("controllers.window.window_capabilities")

local M = {}
local DOUBLE_CLICK_SECONDS = 0.35
local DOUBLE_CLICK_MOVE_TOLERANCE = 4

local lastHeaderTitleClick = nil
local lastPaletteLinkHandleClick = nil

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function isInHeaderTitleArea(win, x, y)
  if not (win and win.isInHeader and win:isInHeader(x, y)) then
    return false
  end

  local headerLeft, headerTop, headerWidth, headerHeight
  if win.getHeaderRect then
    headerLeft, headerTop, headerWidth, headerHeight = win:getHeaderRect()
  else
    headerLeft = win.x or 0
    headerTop = (win.y or 0) - (win.headerH or 15)
    headerWidth = ((win.cellW or 0) * (win.visibleCols or win.cols or 0) * (win.zoom or 1))
    headerHeight = win.headerH or 15
  end

  local left = headerLeft + 4
  local right = headerLeft + headerWidth - 4
  if win.headerToolbar and type(win.headerToolbar.x) == "number" and type(win.headerToolbar.w) == "number" then
    right = math.min(right, win.headerToolbar.x - 2)
  end

  return x >= left and x <= right and y >= headerTop and y <= (headerTop + headerHeight)
end

function M._resetHeaderDoubleClickState()
  lastHeaderTitleClick = nil
  lastPaletteLinkHandleClick = nil
end

local function isWindowDragMouseButton(button)
  return button == 2 or button == 3
end

local function getApp()
  local gctx = rawget(_G, "ctx")
  return gctx and gctx.app or nil
end

local function getPaletteLinkDrag()
  local app = getApp()
  return app and app.paletteLinkDrag or nil
end

local function isValidPaletteLinkHandle(toolbar, x, y)
  if not (toolbar and toolbar.getLinkHandleRect) then
    return false
  end
  local bx, by, bw, bh = toolbar:getLinkHandleRect()
  return bx and by and bw and bh
    and x >= bx and x <= (bx + bw)
    and y >= by and y <= (by + bh)
end

local function getLinkedLayerIndexForPalette(targetWin, paletteWin)
  if not (targetWin and paletteWin and paletteWin._id) then
    return nil
  end
  if WindowCaps.isAnyPaletteWindow(targetWin) then
    return nil
  end

  local li = (targetWin.getActiveLayerIndex and targetWin:getActiveLayerIndex()) or targetWin.activeLayer or 1
  local layer = targetWin.layers and targetWin.layers[li] or nil
  local pd = layer and layer.paletteData or nil
  if pd and pd.winId == paletteWin._id then
    return li
  end
  return nil
end

local function collectLinkedTargetsForPalette(wm, paletteWin)
  local out = {}
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for _, win in ipairs(windows) do
    local li = getLinkedLayerIndexForPalette(win, paletteWin)
    if li then
      out[#out + 1] = { win = win, layerIndex = li }
    end
  end
  return out
end

local function resolvePaletteUnlinkTarget(wm, paletteWin, previousFocus)
  local li = getLinkedLayerIndexForPalette(previousFocus, paletteWin)
  if li then
    return previousFocus, li
  end

  local linked = collectLinkedTargetsForPalette(wm, paletteWin)
  if #linked == 1 then
    return linked[1].win, linked[1].layerIndex
  end

  return nil, nil
end

local function clearPaletteWinIdLink(layer)
  if not (layer and layer.paletteData and layer.paletteData.winId) then
    return false
  end
  layer.paletteData.winId = nil
  if next(layer.paletteData) == nil then
    layer.paletteData = nil
  end
  return true
end

local function unlinkPaletteTarget(wm, paletteWin, targetWin, layerIndex)
  local app = getApp()
  local layer = targetWin and targetWin.layers and targetWin.layers[layerIndex] or nil
  if not clearPaletteWinIdLink(layer) then
    return false
  end

  if wm and wm.setFocus then
    wm:setFocus(targetWin)
  end
  if app and app.markUnsaved then
    app:markUnsaved("palette_link_change")
  end
  if app and app.setStatus then
    app:setStatus(string.format("Unlinked %s from %s layer %d", paletteWin.title or "Palette", targetWin.title or "window", layerIndex))
  end
  return true
end

local function maybeHandlePaletteLinkDoubleClick(toolbar, x, y, win, wm, previousFocus)
  if not isValidPaletteLinkHandle(toolbar, x, y) then
    return false
  end

  local targetWin, targetLayerIndex = resolvePaletteUnlinkTarget(wm, win, previousFocus)
  local t = nowSeconds()
  local prev = lastPaletteLinkHandleClick
  local sameClick = prev
    and prev.paletteWin == win
    and prev.targetWin == targetWin
    and prev.targetLayerIndex == targetLayerIndex
    and targetWin ~= nil
    and (t - (prev.time or 0)) <= DOUBLE_CLICK_SECONDS
    and math.abs((prev.x or 0) - x) <= DOUBLE_CLICK_MOVE_TOLERANCE
    and math.abs((prev.y or 0) - y) <= DOUBLE_CLICK_MOVE_TOLERANCE

  lastPaletteLinkHandleClick = {
    paletteWin = win,
    targetWin = targetWin,
    targetLayerIndex = targetLayerIndex,
    time = t,
    x = x,
    y = y,
  }

  if not sameClick then
    return false
  end

  lastPaletteLinkHandleClick = nil
  return unlinkPaletteTarget(wm, win, targetWin, targetLayerIndex)
end

local function beginPaletteLinkDrag(toolbar, button, x, y, win, wm, previousFocus)
  if button ~= 1 then
    return false
  end
  if not (win and win._id and WindowCaps.isAnyPaletteWindow(win)) then
    return false
  end
  if not isValidPaletteLinkHandle(toolbar, x, y) then
    return false
  end

  if maybeHandlePaletteLinkDoubleClick(toolbar, x, y, win, wm, previousFocus) then
    return true
  end

  local drag = getPaletteLinkDrag()
  if not drag then
    return false
  end

  drag.active = true
  drag.sourceWin = win
  drag.sourceWinId = win._id
  drag.currentX = x
  drag.currentY = y
  return true
end

local function getPaletteLinkDropTarget(wm, sourceWin, x, y)
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local win = windows[i]
    if win and win ~= sourceWin and not win._closed and not win._minimized and not WindowCaps.isAnyPaletteWindow(win) then
      if win.contains and win:contains(x, y) then
        return win
      end
    end
  end
  return nil
end

local function applyPaletteLinkToTarget(targetWin, paletteWin)
  if not (targetWin and paletteWin and paletteWin._id) then
    return false, "Palette link failed"
  end

  local li = (targetWin.getActiveLayerIndex and targetWin:getActiveLayerIndex()) or targetWin.activeLayer or 1
  local layer = targetWin.layers and targetWin.layers[li] or nil
  if not layer then
    return false, "Target window has no active layer"
  end
  if layer.kind ~= "tile" and layer.kind ~= "sprite" then
    return false, "Target layer cannot use palettes"
  end

  layer.paletteData = { winId = paletteWin._id }
  return true, li
end

local function finishPaletteLinkDrag(wm, x, y)
  local drag = getPaletteLinkDrag()
  if not (drag and drag.active) then
    return false
  end

  local app = getApp()
  local sourceWin = drag.sourceWin
  local sourceTitle = sourceWin and (sourceWin.title or sourceWin._id) or "Palette"
  local sourceToolbar = sourceWin and sourceWin.specializedToolbar or nil
  local targetWin = getPaletteLinkDropTarget(wm, sourceWin, x, y)

  drag.active = false
  drag.currentX = x
  drag.currentY = y

  if not targetWin then
    if sourceToolbar and isValidPaletteLinkHandle(sourceToolbar, x, y) then
      drag.sourceWin = nil
      drag.sourceWinId = nil
      return true
    end
    if app and app.setStatus then
      app:setStatus("Palette link canceled")
    end
    drag.sourceWin = nil
    drag.sourceWinId = nil
    return true
  end

  local ok, result = applyPaletteLinkToTarget(targetWin, sourceWin)
  if not ok then
    if app and app.setStatus then
      app:setStatus(result)
    end
    if app and app.showToast then
      app:showToast("error", result)
    end
    drag.sourceWin = nil
    drag.sourceWinId = nil
    return true
  end

  if wm and wm.setFocus then
    wm:setFocus(targetWin)
  end
  if app and app.markUnsaved then
    app:markUnsaved("palette_link_change")
  end
  if app and app.setStatus then
    app:setStatus(string.format("Linked %s to %s layer %d", sourceTitle, targetWin.title or "window", result))
  end
  drag.sourceWin = nil
  drag.sourceWinId = nil
  return true
end

local function beginToolbarWindowDragIfNeeded(toolbar, button, x, y, win)
  if not (toolbar and toolbar.contains and isWindowDragMouseButton(button)) then
    return false
  end
  if not toolbar:contains(x, y) then
    return false
  end
  win.dragging = true
  win.dx = x - win.x
  win.dy = y - win.y
  return true
end

function M.handleToolbarClicks(button, x, y, win, wm)
  if not win or win._closed or win._minimized then return false end

  local previousFocus = wm:getFocus()
  wm:setFocus(win)

  if not win._collapsed and win.specializedToolbar then
    local toolbar = win.specializedToolbar
    if toolbar.updatePosition then
      toolbar:updatePosition()
    end
    if beginPaletteLinkDrag(toolbar, button, x, y, win, wm, previousFocus) then
      return true
    end
    if beginToolbarWindowDragIfNeeded(toolbar, button, x, y, win) then
      return true
    end
    if toolbar.mousepressed and toolbar:mousepressed(x, y, button) then
      return true
    end
  end

  if win.headerToolbar then
    local toolbar = win.headerToolbar
    if toolbar.updatePosition then
      toolbar:updatePosition()
    end
    if beginToolbarWindowDragIfNeeded(toolbar, button, x, y, win) then
      return true
    end
    if toolbar.mousepressed and toolbar:mousepressed(x, y, button) then
      return true
    end
  end

  return false
end

function M.handleToolbarRelease(button, x, y, wm)
  if finishPaletteLinkDrag(wm, x, y) then
    return true
  end

  local focusedWin = wm:getFocus()
  if not focusedWin or focusedWin._closed or focusedWin._minimized then return false end

  if not focusedWin._collapsed and focusedWin.specializedToolbar then
    local toolbar = focusedWin.specializedToolbar
    if toolbar.updatePosition then
      toolbar:updatePosition()
    end
    if toolbar.mousereleased and toolbar:mousereleased(x, y, button) then
      return true
    end
  end

  if focusedWin.headerToolbar then
    local toolbar = focusedWin.headerToolbar
    if toolbar.updatePosition then
      toolbar:updatePosition()
    end
    if toolbar.mousereleased and toolbar:mousereleased(x, y, button) then
      return true
    end
  end

  return false
end

function M.updateToolbarHover(x, y, wm)
  local windows = wm:getWindows()
  for _, w in ipairs(windows) do
    if not w._closed and not w._minimized then
      if not w._collapsed and w.specializedToolbar and w.specializedToolbar.mousemoved then
        w.specializedToolbar:mousemoved(x, y)
      end
      if w.headerToolbar and w.headerToolbar.mousemoved then
        w.headerToolbar:mousemoved(x, y)
      end
    end
  end
end

function M.handleHeaderClick(button, x, y, win, wm, opts)
  opts = opts or {}
  if isWindowDragMouseButton(button) and win and isInHeaderTitleArea(win, x, y) then
    wm:setFocus(win)
    lastHeaderTitleClick = nil
    if type(opts.onWindowTitleContextMenu) == "function" then
      opts.onWindowTitleContextMenu(win, x, y, button)
    end
    return false
  end

  if button == 1 and win and win:isInHeader(x, y) then
    wm:setFocus(win)
    if M.handleToolbarClicks(button, x, y, win, wm) then
      return true
    end

    local titleAreaClick = isInHeaderTitleArea(win, x, y)
    if titleAreaClick then
      local t = tonumber(opts.nowSeconds) or nowSeconds()
      local prev = lastHeaderTitleClick
      local dt = prev and (t - (prev.time or 0)) or math.huge
      local dx = prev and math.abs((prev.x or 0) - x) or math.huge
      local dy = prev and math.abs((prev.y or 0) - y) or math.huge
      local sameWindow = prev and prev.win == win

      local isDoubleClick = sameWindow
        and dt >= 0
        and dt <= DOUBLE_CLICK_SECONDS
        and dx <= DOUBLE_CLICK_MOVE_TOLERANCE
        and dy <= DOUBLE_CLICK_MOVE_TOLERANCE

      lastHeaderTitleClick = {
        win = win,
        x = x,
        y = y,
        time = t,
      }

      if isDoubleClick and type(opts.onWindowTitleDoubleClick) == "function" then
        opts.onWindowTitleDoubleClick(win)
        return true
      end
    else
      lastHeaderTitleClick = nil
    end

    win:mousepressed(x, y, button)
    return true
  end
  return false
end

function M.handleResizeHandle(button, x, y, wm)
  if button ~= 1 then return false end

  local windows = wm:getWindows()
  if not windows then return false end
  local focused = wm:getFocus()

  for i = #windows, 1, -1 do
    local w = windows[i]
    if w == focused and not w._closed and not w._minimized and w:hitResizeHandle(x, y) then
      w:mousepressed(x, y, button)
      return true
    end
  end
  return false
end

function M.handleResizeEnd(button, x, y, fwin)
  if fwin and not fwin._minimized and fwin.resizing and fwin.mousereleased then
    fwin:mousereleased(x, y, button)
    return true
  end
  return false
end

function M.handleWindowDragEnd(button, x, y, fwin)
  if fwin and not fwin._minimized and fwin.dragging and fwin.mousereleased then
    fwin:mousereleased(x, y, button)
    return true
  end
  return false
end

return M
