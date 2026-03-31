local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local DOUBLE_CLICK_SECONDS = 0.35
local DOUBLE_CLICK_MOVE_TOLERANCE = 4
local lastPaletteLinkHandleClick = nil

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function getApp()
  local gctx = rawget(_G, "ctx")
  return gctx and gctx.app or nil
end

local function getPaletteLinkDrag()
  local app = getApp()
  return app and app.paletteLinkDrag or nil
end

local function deepCopy(value, seen)
  if type(value) ~= "table" then
    return value
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[deepCopy(k, seen)] = deepCopy(v, seen)
  end
  return copy
end

local function clonePaletteData(paletteData)
  if type(paletteData) ~= "table" then
    return nil
  end
  return deepCopy(paletteData)
end

local function isPointInWindowInteractiveArea(win, x, y)
  if not win then
    return false
  end
  if win.contains and win:contains(x, y) then
    return true
  end
  if win.specializedToolbar and win.specializedToolbar.contains and win.specializedToolbar:contains(x, y) then
    return true
  end
  if win.headerToolbar and win.headerToolbar.contains and win.headerToolbar:contains(x, y) then
    return true
  end
  return false
end

local function isPointInWindowDropArea(win, x, y)
  return isPointInWindowInteractiveArea(win, x, y)
end

function M.canApplyToTarget(targetWin, sourceWin)
  if not targetWin or targetWin == sourceWin then
    return false, "Palette link failed"
  end
  if targetWin._closed or targetWin._minimized then
    return false, "Palette link failed"
  end
  if WindowCaps.isAnyPaletteWindow(targetWin) then
    return false, "Cannot link a palette to another palette window"
  end
  if WindowCaps.isChrLike(targetWin) then
    return false, "Cannot link a palette to CHR/ROM bank windows"
  end

  local li = (targetWin.getActiveLayerIndex and targetWin:getActiveLayerIndex()) or targetWin.activeLayer or 1
  local layer = targetWin.layers and targetWin.layers[li] or nil
  if not layer then
    return false, "Target window has no active layer"
  end

  return true, li
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

local function collectLinkedTargetsForPalette(wm, paletteWin)
  local out = {}
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for _, win in ipairs(windows) do
    if not WindowCaps.isAnyPaletteWindow(win) then
      local layers = win and win.layers or {}
      local numericKeys = {}
      for key, value in pairs(layers) do
        if type(key) == "number" and value ~= nil then
          numericKeys[#numericKeys + 1] = key
        end
      end
      table.sort(numericKeys)
      for _, layerIndex in ipairs(numericKeys) do
        local layer = layers[layerIndex]
        local pd = layer and layer.paletteData or nil
        if paletteWin and paletteWin._id and pd and pd.winId == paletteWin._id then
          out[#out + 1] = { win = win, layerIndex = layerIndex }
        end
      end
    end
  end
  return out
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

local function unlinkAllPaletteTargets(wm, paletteWin)
  local app = getApp()
  local linked = collectLinkedTargetsForPalette(wm, paletteWin)
  local removedCount = 0
  local undoActions = {}

  for _, entry in ipairs(linked) do
    local layer = entry.win and entry.win.layers and entry.win.layers[entry.layerIndex] or nil
    local beforePaletteData = clonePaletteData(layer and layer.paletteData or nil)
    if clearPaletteWinIdLink(layer) then
      removedCount = removedCount + 1
      undoActions[#undoActions + 1] = {
        win = entry.win,
        layerIndex = entry.layerIndex,
        beforePaletteData = beforePaletteData,
        afterPaletteData = clonePaletteData(layer and layer.paletteData or nil),
      }
    end
  end

  if removedCount <= 0 then
    return false
  end

  if app and app.undoRedo and app.undoRedo.addPaletteLinkEvent then
    app.undoRedo:addPaletteLinkEvent({
      type = "palette_link",
      actions = undoActions,
    })
  elseif app and app.markUnsaved then
    app:markUnsaved("palette_link_change")
  end
  if app and app.setStatus then
    app:setStatus(string.format("Unlinked %d palette connection%s from %s", removedCount, removedCount == 1 and "" or "s", paletteWin.title or "Palette"))
  end
  return true
end

local function maybeHandleDoubleClick(toolbar, x, y, win, wm)
  if not isValidPaletteLinkHandle(toolbar, x, y) then
    return false
  end

  local t = nowSeconds()
  local prev = lastPaletteLinkHandleClick
  local sameClick = prev
    and prev.paletteWin == win
    and (t - (prev.time or 0)) <= DOUBLE_CLICK_SECONDS
    and math.abs((prev.x or 0) - x) <= DOUBLE_CLICK_MOVE_TOLERANCE
    and math.abs((prev.y or 0) - y) <= DOUBLE_CLICK_MOVE_TOLERANCE

  lastPaletteLinkHandleClick = {
    paletteWin = win,
    time = t,
    x = x,
    y = y,
  }

  if not sameClick then
    return false
  end

  lastPaletteLinkHandleClick = nil
  return unlinkAllPaletteTargets(wm, win)
end

function M.beginDrag(toolbar, button, x, y, win, wm)
  if button ~= 1 then
    return false
  end
  if not (win and win._id and WindowCaps.isRomPaletteWindow(win)) then
    return false
  end
  if not isValidPaletteLinkHandle(toolbar, x, y) then
    return false
  end

  if maybeHandleDoubleClick(toolbar, x, y, win, wm) then
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

function M.getHoverTarget(wm, sourceWin, x, y)
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local win = windows[i]
    local ok = M.canApplyToTarget(win, sourceWin)
    if win
      and win ~= sourceWin
      and not win._closed
      and not win._minimized
      and ok
      and isPointInWindowDropArea(win, x, y)
    then
      return win
    end
  end
  return nil
end

function M.getDropTarget(wm, sourceWin, x, y)
  if sourceWin then
    if (sourceWin.specializedToolbar and sourceWin.specializedToolbar.contains and sourceWin.specializedToolbar:contains(x, y))
      or (sourceWin.headerToolbar and sourceWin.headerToolbar.contains and sourceWin.headerToolbar:contains(x, y))
    then
      return nil
    end
  end

  local hoverTarget = M.getHoverTarget(wm, sourceWin, x, y)
  local focusedWin = wm and wm.getFocus and wm:getFocus() or nil
  if not focusedWin or focusedWin == sourceWin or focusedWin ~= hoverTarget then
    return nil
  end
  if focusedWin._closed or focusedWin._minimized then
    return nil
  end
  if isPointInWindowDropArea(focusedWin, x, y) then
    return focusedWin
  end

  return nil
end

local function applyToTarget(targetWin, paletteWin)
  if not (targetWin and paletteWin and paletteWin._id) then
    return false, "Palette link failed"
  end

  local ok, result = M.canApplyToTarget(targetWin, paletteWin)
  if not ok then
    return false, result
  end
  local li = result
  local layer = targetWin.layers and targetWin.layers[li] or nil
  local beforePaletteData = clonePaletteData(layer and layer.paletteData or nil)
  layer.paletteData = { winId = paletteWin._id }
  return true, {
    layerIndex = li,
    actions = {
      {
        win = targetWin,
        layerIndex = li,
        beforePaletteData = beforePaletteData,
        afterPaletteData = clonePaletteData(layer and layer.paletteData or nil),
      },
    },
  }
end

function M.finishDrag(wm, x, y)
  local drag = getPaletteLinkDrag()
  if not (drag and drag.active) then
    return false
  end

  local app = getApp()
  local sourceWin = drag.sourceWin
  local sourceTitle = sourceWin and (sourceWin.title or sourceWin._id) or "Palette"
  local sourceToolbar = sourceWin and sourceWin.specializedToolbar or nil
  local targetWin = M.getDropTarget(wm, sourceWin, x, y)

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

  local ok, result = applyToTarget(targetWin, sourceWin)
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
  if app and app.undoRedo and app.undoRedo.addPaletteLinkEvent and result.actions and #result.actions > 0 then
    app.undoRedo:addPaletteLinkEvent({
      type = "palette_link",
      actions = result.actions,
    })
  elseif app and app.markUnsaved and result.actions and #result.actions > 0 then
    app:markUnsaved("palette_link_change")
  end
  if app and app.setStatus then
    app:setStatus(string.format("Linked %s to %s layer %d", sourceTitle, targetWin.title or "window", result.layerIndex))
  end
  drag.sourceWin = nil
  drag.sourceWinId = nil
  return true
end

function M.updateDragHover(wm, x, y)
  local drag = getPaletteLinkDrag()
  if not (drag and drag.active) then
    return nil
  end

  drag.currentX = x
  drag.currentY = y
  local hoveredWin = M.getHoverTarget(wm, drag.sourceWin, x, y)
  if hoveredWin and hoveredWin ~= drag.sourceWin and wm and wm.setFocus then
    wm:setFocus(hoveredWin)
  end
  return hoveredWin
end

function M.resetDoubleClickState()
  lastPaletteLinkHandleClick = nil
end

return M
