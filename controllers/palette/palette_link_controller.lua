local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local DOUBLE_CLICK_SECONDS = 0.35
local DOUBLE_CLICK_MOVE_TOLERANCE = 4
local lastPaletteLinkHandleClick = nil
local lastDestinationLinkClick = nil

local DRAG_MODE_LINK_CREATE = "link_create"
local DRAG_MODE_LINK_CREATE_FROM_CONTENT = "link_create_from_content"
local DRAG_MODE_MOVE_SINGLE = "move_single"
local DRAG_MODE_MOVE_ALL = "move_all"

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

local function clearPaletteLinkDragState(drag, x, y)
  if not drag then
    return
  end
  drag.active = false
  drag.sourceWin = nil
  drag.sourceWinId = nil
  drag.mode = nil
  drag.originContentWin = nil
  drag.originPaletteWin = nil
  drag.currentX = x or drag.currentX or 0
  drag.currentY = y or drag.currentY or 0
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

local function invalidatePaletteLinkedPpuLayer(win, layerIndex)
  local app = getApp()
  if app and app.invalidatePpuFramePaletteLayer then
    app:invalidatePpuFramePaletteLayer(win, layerIndex)
  end
end

local function invalidatePaletteLinkedPpuLayersForActions(actions)
  for _, action in ipairs(actions or {}) do
    invalidatePaletteLinkedPpuLayer(action and action.win or nil, action and action.layerIndex or nil)
  end
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

local function canMoveAllToPaletteTarget(targetWin, sourceWin, opts)
  opts = opts or {}
  if not targetWin then
    return false
  end
  if targetWin == sourceWin and not opts.allowSource then
    return false
  end
  if targetWin._closed or targetWin._minimized then
    return false
  end
  return WindowCaps.isRomPaletteWindow(targetWin) == true
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

local function isPointInRect(x, y, rx, ry, rw, rh)
  return rx and ry and rw and rh
    and x >= rx and x <= (rx + rw)
    and y >= ry and y <= (ry + rh)
end

local function getWindowLinkHandleRect(win)
  if not win or win._collapsed or win._closed or win._minimized then
    return nil
  end
  local toolbar = win.specializedToolbar
  if not (toolbar and toolbar.getLinkHandleRect) then
    return nil
  end
  if toolbar.updatePosition then
    toolbar:updatePosition()
  end
  local x, y, w, h = toolbar:getLinkHandleRect()
  if not (x and y and w and h) then
    return nil
  end
  return x, y, w, h
end

local function isPointInWindowLinkHandle(win, x, y)
  return isPointInRect(x, y, getWindowLinkHandleRect(win))
end

local function getActiveLayerIndex(win)
  if not win then
    return 1
  end
  return (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
end

local function getActiveLayer(win)
  local layerIndex = getActiveLayerIndex(win)
  return win and win.layers and win.layers[layerIndex] or nil, layerIndex
end

local function getActiveLayerLinkedPaletteWin(contentWin, wm)
  local layer = getActiveLayer(contentWin)
  local pd = layer and layer.paletteData or nil
  if not (wm and pd and pd.winId) then
    return nil
  end
  local linked = wm:findWindowById(pd.winId)
  if linked and not linked._closed and not linked._minimized and WindowCaps.isRomPaletteWindow(linked) then
    return linked
  end
  return nil
end

local function getRomPaletteWindows(wm)
  local out = {}
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for _, win in ipairs(windows) do
    if WindowCaps.isRomPaletteWindow(win) and not win._closed and not win._minimized then
      out[#out + 1] = win
    end
  end
  table.sort(out, function(a, b)
    local at = tostring(a and (a.title or a._id or "") or "")
    local bt = tostring(b and (b.title or b._id or "") or "")
    if at ~= bt then
      return at < bt
    end
    return tostring(a) < tostring(b)
  end)
  return out
end

local function findTopWindowByPredicate(wm, predicate)
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local win = windows[i]
    if predicate(win) then
      return win
    end
  end
  return nil
end

local function getHandleTargetForLinkCreate(wm, sourceWin, x, y)
  return findTopWindowByPredicate(wm, function(win)
    local ok = M.canApplyToTarget(win, sourceWin)
    return win
      and win ~= sourceWin
      and not win._closed
      and not win._minimized
      and ok
      and isPointInWindowLinkHandle(win, x, y)
  end)
end

local function getHandleTargetForMoveAll(wm, sourceWin, x, y, opts)
  return findTopWindowByPredicate(wm, function(win)
    return canMoveAllToPaletteTarget(win, sourceWin, opts)
      and isPointInWindowLinkHandle(win, x, y)
  end)
end

local function getHandleTargetForMoveSingle(wm, sourcePaletteWin, x, y, opts)
  return findTopWindowByPredicate(wm, function(win)
    return canMoveAllToPaletteTarget(win, sourcePaletteWin, opts)
      and isPointInWindowLinkHandle(win, x, y)
  end)
end

--- Topmost ROM palette under (x,y), for dropping a new link from a content window.
local function getRomPaletteAtPoint(wm, x, y, opts)
  opts = opts or {}
  local exclude = opts.excludeWin
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local win = windows[i]
    if WindowCaps.isRomPaletteWindow(win)
      and win ~= exclude
      and not win._closed
      and not win._minimized
      and (isPointInWindowLinkHandle(win, x, y) or isPointInWindowDropArea(win, x, y))
    then
      return win
    end
  end
  return nil
end

local function collectNumericLayerKeys(layers)
  local numericKeys = {}
  for key, value in pairs(layers or {}) do
    if type(key) == "number" and value ~= nil then
      numericKeys[#numericKeys + 1] = key
    end
  end
  table.sort(numericKeys)
  return numericKeys
end

local function collectLinkedTargetsForPalette(wm, paletteWin)
  local out = {}
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for _, win in ipairs(windows) do
    if not WindowCaps.isAnyPaletteWindow(win) then
      local layers = win and win.layers or {}
      for _, layerIndex in ipairs(collectNumericLayerKeys(layers)) do
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

local function collectLinkedTargetsForWindowPalette(contentWin, paletteWin)
  local out = {}
  if not (contentWin and contentWin.layers and paletteWin and paletteWin._id) then
    return out
  end
  for _, layerIndex in ipairs(collectNumericLayerKeys(contentWin.layers)) do
    local layer = contentWin.layers[layerIndex]
    local pd = layer and layer.paletteData or nil
    if pd and pd.winId == paletteWin._id then
      out[#out + 1] = { win = contentWin, layerIndex = layerIndex }
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

local function pushPaletteLinkUndo(actions)
  if type(actions) ~= "table" or #actions == 0 then
    return false
  end

  local app = getApp()
  if app and app.undoRedo and app.undoRedo.addPaletteLinkEvent then
    app.undoRedo:addPaletteLinkEvent({
      type = "palette_link",
      actions = actions,
    })
    return true
  end
  if app and app.markUnsaved then
    app:markUnsaved("palette_link_change")
    return true
  end
  return false
end

local function unlinkAllPaletteTargets(wm, paletteWin, opts)
  opts = opts or {}
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
    return false, undoActions, removedCount
  end

  if opts.commitUndo ~= false then
    pushPaletteLinkUndo(undoActions)
  end
  invalidatePaletteLinkedPpuLayersForActions(undoActions)
  if opts.setStatus ~= false then
    local app = getApp()
    if app and app.setStatus then
      app:setStatus(string.format(
        "Unlinked %d palette connection%s from %s",
        removedCount,
        removedCount == 1 and "" or "s",
        paletteWin and (paletteWin.title or "Palette") or "Palette"
      ))
    end
  end

  return true, undoActions, removedCount
end

local function unlinkWindowPaletteTargets(contentWin, paletteWin, outActions)
  local linked = collectLinkedTargetsForWindowPalette(contentWin, paletteWin)
  local removedCount = 0
  for _, entry in ipairs(linked) do
    local layer = entry.win and entry.win.layers and entry.win.layers[entry.layerIndex] or nil
    local beforePaletteData = clonePaletteData(layer and layer.paletteData or nil)
    if clearPaletteWinIdLink(layer) then
      removedCount = removedCount + 1
      outActions[#outActions + 1] = {
        win = entry.win,
        layerIndex = entry.layerIndex,
        beforePaletteData = beforePaletteData,
        afterPaletteData = clonePaletteData(layer and layer.paletteData or nil),
      }
    end
  end
  return removedCount
end

local function unlinkPaletteConnection(contentWin, paletteWin)
  local actions = {}
  local removedCount = unlinkWindowPaletteTargets(contentWin, paletteWin, actions)
  if removedCount <= 0 then
    return false
  end

  pushPaletteLinkUndo(actions)
  invalidatePaletteLinkedPpuLayersForActions(actions)

  local app = getApp()
  if app and app.setStatus then
    app:setStatus(string.format(
      "Unlinked %d palette connection%s from %s",
      removedCount,
      removedCount == 1 and "" or "s",
      contentWin and (contentWin.title or "window") or "window"
    ))
  end
  return true
end

local function unlinkPaletteConnectionForLayer(contentWin, paletteWin, layerIndex)
  if not (contentWin and paletteWin and type(layerIndex) == "number") then
    return false
  end
  local layer = contentWin.layers and contentWin.layers[layerIndex] or nil
  if not layer then
    return false
  end
  local pd = layer.paletteData
  if not (pd and pd.winId and paletteWin._id and pd.winId == paletteWin._id) then
    return false
  end

  local beforePaletteData = clonePaletteData(layer.paletteData or nil)
  if not clearPaletteWinIdLink(layer) then
    return false
  end

  pushPaletteLinkUndo({
    {
      win = contentWin,
      layerIndex = layerIndex,
      beforePaletteData = beforePaletteData,
      afterPaletteData = clonePaletteData(layer.paletteData or nil),
    },
  })
  invalidatePaletteLinkedPpuLayer(contentWin, layerIndex)

  local app = getApp()
  if app and app.setStatus then
    app:setStatus(string.format(
      "Unlinked palette from %s layer %d",
      contentWin and (contentWin.title or "window") or "window",
      layerIndex
    ))
  end

  return true
end

local function moveAllPaletteTargets(wm, sourcePaletteWin, targetPaletteWin)
  if not canMoveAllToPaletteTarget(targetPaletteWin, sourcePaletteWin) then
    return false, "Move target must be another ROM palette window"
  end
  if not (sourcePaletteWin and sourcePaletteWin._id and targetPaletteWin and targetPaletteWin._id) then
    return false, "Palette link move failed"
  end

  local linked = collectLinkedTargetsForPalette(wm, sourcePaletteWin)
  if #linked == 0 then
    return false, "No palette connections to move"
  end

  local actions = {}
  for _, entry in ipairs(linked) do
    local layer = entry.win and entry.win.layers and entry.win.layers[entry.layerIndex] or nil
    if layer then
      local beforePaletteData = clonePaletteData(layer.paletteData or nil)
      layer.paletteData = { winId = targetPaletteWin._id }
      actions[#actions + 1] = {
        win = entry.win,
        layerIndex = entry.layerIndex,
        beforePaletteData = beforePaletteData,
        afterPaletteData = clonePaletteData(layer.paletteData or nil),
      }
    end
  end

  if #actions == 0 then
    return false, "No palette connections to move"
  end

  pushPaletteLinkUndo(actions)
  invalidatePaletteLinkedPpuLayersForActions(actions)

  local app = getApp()
  if app and app.setStatus then
    app:setStatus(string.format(
      "Moved %d palette connection%s from %s to %s",
      #actions,
      #actions == 1 and "" or "s",
      sourcePaletteWin.title or "Palette",
      targetPaletteWin.title or "Palette"
    ))
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

local function maybeHandleDestinationDoubleClick(link, x, y)
  if not (link and link.contentWin and link.paletteWin) then
    return false
  end

  local t = nowSeconds()
  local prev = lastDestinationLinkClick
  local sameClick = prev
    and prev.contentWin == link.contentWin
    and prev.paletteWin == link.paletteWin
    and (t - (prev.time or 0)) <= DOUBLE_CLICK_SECONDS
    and math.abs((prev.x or 0) - x) <= DOUBLE_CLICK_MOVE_TOLERANCE
    and math.abs((prev.y or 0) - y) <= DOUBLE_CLICK_MOVE_TOLERANCE

  lastDestinationLinkClick = {
    contentWin = link.contentWin,
    paletteWin = link.paletteWin,
    time = t,
    x = x,
    y = y,
  }

  if not sameClick then
    return false
  end

  lastDestinationLinkClick = nil
  local activeLayer = (link.contentWin.getActiveLayerIndex and link.contentWin:getActiveLayerIndex())
    or link.contentWin.activeLayer
    or 1
  return unlinkPaletteConnectionForLayer(link.contentWin, link.paletteWin, activeLayer)
end

function M.beginDrag(toolbar, button, x, y, win, wm)
  if button ~= 1 then
    return false
  end
  if not (win and win._id) then
    return false
  end
  if not isValidPaletteLinkHandle(toolbar, x, y) then
    return false
  end

  if WindowCaps.isRomPaletteWindow(win) then
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
    drag.mode = DRAG_MODE_LINK_CREATE
    drag.originContentWin = nil
    drag.originPaletteWin = nil
    return true
  end

  if WindowCaps.isAnyPaletteWindow(win) or WindowCaps.isChrLike(win) then
    return false
  end

  local paletteWin = getActiveLayerLinkedPaletteWin(win, wm)
  if not paletteWin then
    if WindowCaps.isStaticOrAnimationArt(win) then
      local drag = getPaletteLinkDrag()
      if not drag then
        return false
      end
      drag.active = true
      drag.sourceWin = win
      drag.sourceWinId = win._id
      drag.currentX = x
      drag.currentY = y
      drag.mode = DRAG_MODE_LINK_CREATE_FROM_CONTENT
      drag.originContentWin = win
      drag.originPaletteWin = nil
      return true
    end
    return false
  end

  local link = {
    contentWin = win,
    paletteWin = paletteWin,
  }
  if maybeHandleDestinationDoubleClick(link, x, y) then
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
  drag.mode = DRAG_MODE_MOVE_SINGLE
  drag.originContentWin = win
  drag.originPaletteWin = paletteWin
  return true
end

function M.beginDestinationDrag(button, x, y, link, wm)
  if button ~= 1 then
    return false
  end
  if not (link and link.contentWin and link.paletteWin and link.paletteWin._id) then
    return false
  end

  if maybeHandleDestinationDoubleClick(link, x, y) then
    return true
  end

  local drag = getPaletteLinkDrag()
  if not drag then
    return false
  end

  drag.active = true
  drag.sourceWin = link.contentWin
  drag.sourceWinId = link.contentWin._id
  drag.currentX = x
  drag.currentY = y
  drag.mode = DRAG_MODE_MOVE_SINGLE
  drag.originContentWin = link.contentWin
  drag.originPaletteWin = link.paletteWin

  if wm and wm.setFocus and link.contentWin then
    wm:setFocus(link.contentWin)
  end

  return true
end

function M.getHoverTarget(wm, sourceWin, x, y)
  local handleTarget = getHandleTargetForLinkCreate(wm, sourceWin, x, y)
  if handleTarget then
    return handleTarget
  end
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local win = windows[i]
    local ok = M.canApplyToTarget(win, sourceWin)
    if win
      and win ~= sourceWin
      and not win._closed
      and not win._minimized
      and ok
      and (isPointInWindowLinkHandle(win, x, y) or isPointInWindowDropArea(win, x, y))
    then
      return win
    end
  end
  return nil
end

function M.getMoveAllTarget(wm, sourceWin, x, y, opts)
  opts = opts or {}
  local handleTarget = getHandleTargetForMoveAll(wm, sourceWin, x, y, opts)
  if handleTarget then
    return handleTarget
  end
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local win = windows[i]
    if canMoveAllToPaletteTarget(win, sourceWin, opts)
      and (isPointInWindowLinkHandle(win, x, y) or isPointInWindowDropArea(win, x, y))
    then
      return win
    end
  end
  return nil
end

function M.getMoveSingleTarget(wm, sourceContentWin, x, y, opts)
  opts = opts or {}
  local sourcePaletteWin = opts.sourcePaletteWin or getActiveLayerLinkedPaletteWin(sourceContentWin, wm)
  local handleTarget = getHandleTargetForMoveSingle(wm, sourcePaletteWin, x, y, opts)
  if handleTarget then
    return handleTarget
  end
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local win = windows[i]
    if canMoveAllToPaletteTarget(win, sourcePaletteWin, opts)
      and (isPointInWindowLinkHandle(win, x, y) or isPointInWindowDropArea(win, x, y))
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

  local handleTarget = getHandleTargetForLinkCreate(wm, sourceWin, x, y)
  if handleTarget then
    return handleTarget
  end

  local hoverTarget = M.getHoverTarget(wm, sourceWin, x, y)
  if not hoverTarget then
    return nil
  end

  local focusedWin = wm and wm.getFocus and wm:getFocus() or nil
  if focusedWin and focusedWin ~= sourceWin and focusedWin == hoverTarget then
    if focusedWin._closed or focusedWin._minimized then
      return nil
    end
    if isPointInWindowLinkHandle(focusedWin, x, y) or isPointInWindowDropArea(focusedWin, x, y) then
      return focusedWin
    end
  end

  -- Fallback: use the valid hovered target even if focus transition lagged
  -- during drag/release.
  if isPointInWindowLinkHandle(hoverTarget, x, y) or isPointInWindowDropArea(hoverTarget, x, y) then
    return hoverTarget
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

local function finishCreateLinkDrag(wm, x, y, drag)
  local app = getApp()
  local sourceWin = drag.sourceWin
  local sourceTitle = sourceWin and (sourceWin.title or sourceWin._id) or "Palette"
  local sourceToolbar = sourceWin and sourceWin.specializedToolbar or nil
  local targetWin = M.getDropTarget(wm, sourceWin, x, y)

  if not targetWin then
    if sourceToolbar and isValidPaletteLinkHandle(sourceToolbar, x, y) then
      return true
    end
    if app and app.setStatus then
      app:setStatus("Palette link canceled")
    end
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
    return true
  end

  if wm and wm.setFocus then
    wm:setFocus(targetWin)
  end
  if result.actions and #result.actions > 0 then
    pushPaletteLinkUndo(result.actions)
    invalidatePaletteLinkedPpuLayersForActions(result.actions)
  end
  if app and app.setStatus then
    app:setStatus(string.format("Linked %s to %s layer %d", sourceTitle, targetWin.title or "window", result.layerIndex))
  end
  return true
end

local function finishCreateLinkFromContentDrag(wm, x, y, drag)
  local app = getApp()
  local contentWin = drag.originContentWin or drag.sourceWin
  if not contentWin then
    return true
  end

  local paletteWin = getRomPaletteAtPoint(wm, x, y, { excludeWin = contentWin })
  if not paletteWin then
    local tb = contentWin.specializedToolbar
    if tb and isValidPaletteLinkHandle(tb, x, y) then
      return true
    end
    if app and app.setStatus then
      app:setStatus("Palette link canceled")
    end
    return true
  end

  local layerIndex = getActiveLayerIndex(contentWin)
  local ok, err = M.linkLayerToPalette(contentWin, layerIndex, paletteWin)
  if not ok and app then
    if app.setStatus then
      app:setStatus(tostring(err or "Palette link failed"))
    end
    if app.showToast then
      app:showToast("error", tostring(err or "Palette link failed"))
    end
  end
  if ok and wm and wm.setFocus then
    wm:setFocus(contentWin)
  end
  return true
end

local function finishMoveSingleDrag(wm, x, y, drag)
  local app = getApp()
  local originContentWin = drag.originContentWin
  local sourcePalette = drag.originPaletteWin
  local targetPalette = M.getMoveSingleTarget(wm, originContentWin, x, y, {
    allowSource = true,
    sourcePaletteWin = sourcePalette,
  })

  if not targetPalette then
    if app and app.setStatus then
      app:setStatus("Palette link move canceled")
    end
    return true
  end

  if targetPalette == sourcePalette then
    if app and app.setStatus then
      app:setStatus("Palette link unchanged")
    end
    return true
  end

  local layerIndex = getActiveLayerIndex(originContentWin)
  local layer = originContentWin and originContentWin.layers and originContentWin.layers[layerIndex] or nil
  if not (layer and targetPalette and targetPalette._id) then
    if app and app.setStatus then
      app:setStatus("Palette link move failed")
    end
    return true
  end

  local beforePaletteData = clonePaletteData(layer.paletteData or nil)
  layer.paletteData = { winId = targetPalette._id }
  pushPaletteLinkUndo({
    {
      win = originContentWin,
      layerIndex = layerIndex,
      beforePaletteData = beforePaletteData,
      afterPaletteData = clonePaletteData(layer.paletteData or nil),
    },
  })
  invalidatePaletteLinkedPpuLayer(originContentWin, layerIndex)
  if app and app.setStatus then
    app:setStatus(string.format(
      "Moved %s layer %d palette link to %s",
      originContentWin and (originContentWin.title or "window") or "window",
      layerIndex,
      targetPalette.title or "Palette"
    ))
  end
  if wm and wm.setFocus then
    wm:setFocus(targetPalette)
  end
  return true
end

local function finishMoveAllDrag(wm, x, y, drag)
  local app = getApp()
  local sourcePalette = drag.sourceWin
  local targetPalette = M.getMoveAllTarget(wm, sourcePalette, x, y, { allowSource = true })

  if targetPalette == sourcePalette then
    if app and app.setStatus then
      app:setStatus("Palette links unchanged")
    end
    return true
  end

  if not targetPalette then
    local unlinked = unlinkAllPaletteTargets(wm, sourcePalette, {
      commitUndo = true,
      setStatus = true,
    })
    if not unlinked and app and app.setStatus then
      app:setStatus("No palette connections to remove")
    end
    return true
  end

  local ok, err = moveAllPaletteTargets(wm, sourcePalette, targetPalette)
  if not ok and app and app.setStatus then
    app:setStatus(err or "Palette link move failed")
  end
  if ok and wm and wm.setFocus then
    wm:setFocus(targetPalette)
  end
  return true
end

function M.finishDrag(wm, x, y)
  local drag = getPaletteLinkDrag()
  if not (drag and drag.active) then
    return false
  end

  local mode = drag.mode or DRAG_MODE_LINK_CREATE
  local handled = false
  if mode == DRAG_MODE_MOVE_SINGLE then
    handled = finishMoveSingleDrag(wm, x, y, drag)
  elseif mode == DRAG_MODE_MOVE_ALL then
    handled = finishMoveAllDrag(wm, x, y, drag)
  elseif mode == DRAG_MODE_LINK_CREATE_FROM_CONTENT then
    handled = finishCreateLinkFromContentDrag(wm, x, y, drag)
  else
    handled = finishCreateLinkDrag(wm, x, y, drag)
  end

  clearPaletteLinkDragState(drag, x, y)
  return handled
end

function M.updateDragHover(wm, x, y)
  local drag = getPaletteLinkDrag()
  if not (drag and drag.active) then
    return nil
  end

  drag.currentX = x
  drag.currentY = y

  local hoveredWin = nil
  if drag.mode == DRAG_MODE_MOVE_ALL then
    hoveredWin = M.getMoveAllTarget(wm, drag.sourceWin, x, y, { allowSource = true })
  elseif drag.mode == DRAG_MODE_MOVE_SINGLE then
    hoveredWin = M.getMoveSingleTarget(wm, drag.originContentWin, x, y, {
      allowSource = true,
      sourcePaletteWin = drag.originPaletteWin,
    })
  elseif drag.mode == DRAG_MODE_LINK_CREATE_FROM_CONTENT then
    hoveredWin = getRomPaletteAtPoint(wm, x, y, { excludeWin = drag.sourceWin })
  else
    hoveredWin = M.getHoverTarget(wm, drag.sourceWin, x, y)
  end

  if hoveredWin and hoveredWin ~= drag.sourceWin and wm and wm.setFocus then
    wm:setFocus(hoveredWin)
  end
  return hoveredWin
end

function M.resetDoubleClickState()
  lastPaletteLinkHandleClick = nil
  lastDestinationLinkClick = nil
end

function M.isPointInToolbarLinkHandle(toolbar, x, y)
  return isValidPaletteLinkHandle(toolbar, x, y)
end

function M.getActiveLayerLinkedPaletteWindow(contentWin, wm)
  return getActiveLayerLinkedPaletteWin(contentWin, wm)
end

function M.getLinkedTargetsForPalette(wm, paletteWin)
  return collectLinkedTargetsForPalette(wm, paletteWin)
end

function M.getRomPaletteWindows(wm)
  return getRomPaletteWindows(wm)
end

function M.getContentToPaletteLinkDropTarget(wm, contentWin, x, y)
  return getRomPaletteAtPoint(wm, x, y, { excludeWin = contentWin })
end

function M.removeAllLinksForPalette(wm, paletteWin)
  local ok = unlinkAllPaletteTargets(wm, paletteWin, {
    commitUndo = true,
    setStatus = true,
  })
  return ok and true or false
end

function M.removeLinkForLayer(contentWin, layerIndex)
  if not (contentWin and type(layerIndex) == "number") then
    return false
  end
  local wm = getApp() and getApp().wm or nil
  local paletteWin = getActiveLayerLinkedPaletteWin(contentWin, wm)
  if not paletteWin then
    return false
  end
  return unlinkPaletteConnectionForLayer(contentWin, paletteWin, layerIndex)
end

function M.linkLayerToPalette(contentWin, layerIndex, paletteWin)
  if not (contentWin and paletteWin and type(layerIndex) == "number") then
    return false, "Palette link failed"
  end
  if not (paletteWin and paletteWin._id and WindowCaps.isRomPaletteWindow(paletteWin)) then
    return false, "Target palette is invalid"
  end
  local ok, result = M.canApplyToTarget(contentWin, paletteWin)
  if not ok then
    return false, result
  end
  if result ~= layerIndex then
    return false, "Active layer changed"
  end

  local layer = contentWin.layers and contentWin.layers[layerIndex] or nil
  if not layer then
    return false, "Target window has no active layer"
  end

  local beforePaletteData = clonePaletteData(layer.paletteData or nil)
  local beforeWinId = beforePaletteData and beforePaletteData.winId or nil
  if beforeWinId == paletteWin._id then
    return true
  end

  layer.paletteData = { winId = paletteWin._id }
  local actions = {
    {
      win = contentWin,
      layerIndex = layerIndex,
      beforePaletteData = beforePaletteData,
      afterPaletteData = clonePaletteData(layer.paletteData or nil),
    },
  }
  pushPaletteLinkUndo(actions)
  invalidatePaletteLinkedPpuLayer(contentWin, layerIndex)

  local app = getApp()
  if app and app.setStatus then
    app:setStatus(string.format(
      "Linked %s layer %d to %s",
      contentWin.title or "window",
      layerIndex,
      paletteWin.title or "Palette"
    ))
  end
  return true
end

function M.moveAllLinksToPalette(wm, sourcePaletteWin, targetPaletteWin)
  return moveAllPaletteTargets(wm, sourcePaletteWin, targetPaletteWin)
end

return M
