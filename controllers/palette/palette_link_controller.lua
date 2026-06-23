local WindowCaps = require("controllers.window.window_capabilities")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local SpriteStateSnapshot = require("controllers.sprite.sprite_state_snapshot")
local chr = require("chr")
local LoveCompat = require("utils.love_compat")

local M = {}

local DOUBLE_CLICK_SECONDS = 0.35
local DOUBLE_CLICK_MOVE_TOLERANCE = 4
local lastPaletteLinkHandleClick = nil
local lastDestinationLinkClick = nil

local DRAG_MODE_LINK_CREATE = "link_create"
local DRAG_MODE_LINK_CREATE_FROM_CONTENT = "link_create_from_content"
local DRAG_MODE_MOVE_SINGLE = "move_single"
local DRAG_MODE_MOVE_ALL = "move_all"

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
  local layer = win and win.layers and win.layers[layerIndex]
  if layer and layer.kind == "sprite" then
    local app = getApp()
    local editState = app and app.appEditState
    SpriteController.hydrateSpriteLayer(layer, {
      romRaw = editState and editState.romRaw,
      tilesPool = editState and editState.tilesPool,
      appEditState = editState,
      keepWorld = true,
    })
    return
  end
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
  if targetWin._closed or targetWin._minimized or targetWin._groupHidden == true then
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
  -- ROM palettes may be _groupHidden while another palette is active; move/link by id is still valid.
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

--- ROM palette window linked from a specific content layer (by index), if any.
local function getLinkedRomPaletteWindowForLayer(contentWin, wm, layerIndex)
  if not (contentWin and type(layerIndex) == "number") then
    return nil
  end
  local layer = contentWin.layers and contentWin.layers[layerIndex] or nil
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

local function getActiveLayerLinkedPaletteWin(contentWin, wm)
  return getLinkedRomPaletteWindowForLayer(contentWin, wm, getActiveLayerIndex(contentWin))
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
      and win._groupHidden ~= true
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

local PALETTE_ROW_DEFAULT = 1

local function mergeSpritePaletteAttr(sprite, paletteNum)
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
end

--- Cells to receive default palette when a ROM palette link is created (ignores tile/layer selection).
local function collectTileCellsForPaletteAssignment(win, layerIndex)
  local layer = win.layers and win.layers[layerIndex] or nil
  if not (layer and layer.kind == "tile") then
    return {}
  end

  local cols = win.cols or 0
  local rows = win.rows or 0
  if cols <= 0 or rows <= 0 then
    return {}
  end

  if WindowCaps.isPpuFrame(win) then
    local full = {}
    for r = 0, rows - 1 do
      for c = 0, cols - 1 do
        full[#full + 1] = { col = c, row = r, idx = r * cols + c + 1 }
      end
    end
    return full
  end

  local out = {}
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      local idx = r * cols + c + 1
      local has = false
      if win.get and win:get(c, r, layerIndex) then
        has = true
      elseif layer.items and layer.items[idx] then
        has = true
      end
      if has then
        out[#out + 1] = { col = c, row = r, idx = idx }
      end
    end
  end
  return out
end

local function ppuNametableSnapshotsDiffer(before, after)
  if not before or not after then
    return false
  end
  local function arrDiff(a, b)
    if not a or not b or #a ~= #b then
      return true
    end
    for i = 1, #a do
      if (a[i] or 0) ~= (b[i] or 0) then
        return true
      end
    end
    return false
  end
  return arrDiff(before.nametableAttrBytes, after.nametableAttrBytes)
    or arrDiff(before.nametableBytes, after.nametableBytes)
end

local function buildSpritePaletteAssignmentUndoEvent(win, layerIndex, paletteNum)
  local layer = win.layers and win.layers[layerIndex]
  if not (layer and layer.kind == "sprite") then
    return nil
  end
  local items = layer.items or {}
  local indices = {}
  for i, spr in ipairs(items) do
    if spr and spr.removed ~= true then
      indices[#indices + 1] = i
    end
  end

  local app = getApp()
  local editState = app and app.appEditState
  local newRom = editState and editState.romRaw
  local actions = {}

  for _, idx in ipairs(indices) do
    local sprite = items[idx]
    if sprite and sprite.removed ~= true then
      local beforeState = SpriteStateSnapshot.captureSpriteState(sprite)
      mergeSpritePaletteAttr(sprite, paletteNum)
      if SpriteController.syncSharedOAMSpriteState then
        SpriteController.syncSharedOAMSpriteState(win, sprite, {
          syncPosition = false,
          syncVisual = true,
          syncAttr = true,
        })
      end
      if sprite.startAddr and newRom then
        newRom = chr.writeByteToAddress(newRom, sprite.startAddr + 2, tonumber(sprite.attr) or 0)
      end
      local afterState = SpriteStateSnapshot.captureSpriteState(sprite)
      if beforeState
        and afterState
        and not SpriteStateSnapshot.statesEqual(beforeState, afterState) then
        actions[#actions + 1] = {
          win = win,
          layerIndex = layerIndex,
          sprite = sprite,
          before = beforeState,
          after = afterState,
        }
      end
    end
  end

  if newRom and editState then
    editState.romRaw = newRom
  end

  if #actions == 0 then
    return nil
  end

  return {
    type = "sprite_drag",
    mode = "palette",
    sync = {
      syncPosition = false,
      syncVisual = true,
      syncAttr = true,
    },
    actions = actions,
  }
end

local function buildTilePaletteAssignmentUndoEvent(win, layerIndex, paletteNum)
  local layer = win.layers and win.layers[layerIndex]
  if not (layer and layer.kind == "tile") then
    return nil
  end

  if WindowCaps.isPpuFrame(win) then
    local app = getApp()
    if not (app and type(app.snapshotPpuFrameUndoState) == "function") then
      return nil
    end
    local cells = collectTileCellsForPaletteAssignment(win, layerIndex)
    if #cells == 0 then
      return nil
    end
    local beforeState = app:snapshotPpuFrameUndoState(win, layerIndex)
    local batch = type(win.beginNametableRomBatch) == "function" and type(win.endNametableRomBatch) == "function"
    if batch then
      win:beginNametableRomBatch()
    end
    local updated = 0
    for _, cell in ipairs(cells) do
      if NametableTilesController.setPaletteNumberForTile(win, layer, cell.col, cell.row, paletteNum) then
        updated = updated + 1
      end
    end
    if batch then
      win:endNametableRomBatch()
      if updated > 0 then
        NametableTilesController.syncPpuFrameLayerAfterPaletteBatch(win, layer, layerIndex)
      end
    end
    if updated == 0 then
      return nil
    end
    local afterState = app:snapshotPpuFrameUndoState(win, layerIndex)
    if not ppuNametableSnapshotsDiffer(beforeState, afterState) then
      return nil
    end
    return {
      type = "ppu_frame_range",
      win = win,
      layerIndex = layerIndex,
      beforeState = beforeState,
      afterState = afterState,
    }
  end

  local cells = collectTileCellsForPaletteAssignment(win, layerIndex)
  if #cells == 0 then
    return nil
  end

  local cols = win.cols or 1
  local changes = {}
  for _, cell in ipairs(cells) do
    local idx = cell.row * cols + cell.col
    local beforePal = layer.paletteNumbers and layer.paletteNumbers[idx]
    if NametableTilesController.setPaletteNumberForTile(win, layer, cell.col, cell.row, paletteNum) then
      changes[#changes + 1] = {
        win = win,
        layerIndex = layerIndex,
        col = cell.col,
        row = cell.row,
        linearIndex = idx,
        before = beforePal,
        after = paletteNum,
        isPaletteNumber = true,
      }
      if win.invalidateTileLayerCanvas then
        win:invalidateTileLayerCanvas(layerIndex, cell.col, cell.row)
      end
    end
  end

  if #changes == 0 then
    return nil
  end
  return {
    type = "tile_drag",
    mode = "palette",
    changes = changes,
  }
end

local function buildItemPaletteAssignmentUndoEventsForLink(win, layerIndex)
  local layer = win.layers and win.layers[layerIndex]
  if not layer then
    return {}
  end
  local out = {}
  if layer.kind == "sprite" then
    local ev = buildSpritePaletteAssignmentUndoEvent(win, layerIndex, PALETTE_ROW_DEFAULT)
    if ev then
      out[#out + 1] = ev
    end
    return out
  end
  if layer.kind == "tile" then
    local ev = buildTilePaletteAssignmentUndoEvent(win, layerIndex, PALETTE_ROW_DEFAULT)
    if ev then
      out[#out + 1] = ev
    end
    return out
  end
  return {}
end

local function buildAllItemPaletteAssignmentUndoEventsFromLinkActions(paletteLinkActions)
  local extra = {}
  local seen = {}
  for _, act in ipairs(paletteLinkActions or {}) do
    local w, li = act.win, act.layerIndex
    if w and type(li) == "number" then
      local key = tostring(w._id or w) .. ":" .. tostring(li)
      if not seen[key] then
        seen[key] = true
        for _, ev in ipairs(buildItemPaletteAssignmentUndoEventsForLink(w, li)) do
          extra[#extra + 1] = ev
        end
      end
    end
  end
  return extra
end

local function pushPaletteLinkUndo(actions, applyItemPaletteDefaults)
  if type(actions) ~= "table" or #actions == 0 then
    return false
  end

  applyItemPaletteDefaults = (applyItemPaletteDefaults ~= false)

  local app = getApp()
  if not app then
    return false
  end

  if applyItemPaletteDefaults then
    local assignmentEvents = buildAllItemPaletteAssignmentUndoEventsFromLinkActions(actions)
    if #assignmentEvents > 0 and app.undoRedo and app.undoRedo.addCompositeEvent then
      local compositeEvents = {
        { type = "palette_link", actions = actions },
      }
      for _, ev in ipairs(assignmentEvents) do
        compositeEvents[#compositeEvents + 1] = ev
      end
      return app.undoRedo:addCompositeEvent({
        type = "composite",
        events = compositeEvents,
        unsavedType = "palette_link_change",
      })
    end
  end

  if app.undoRedo and app.undoRedo.addPaletteLinkEvent then
    app.undoRedo:addPaletteLinkEvent({
      type = "palette_link",
      actions = actions,
    })
    return true
  end
  if app.markUnsaved then
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
    pushPaletteLinkUndo(undoActions, false)
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

  pushPaletteLinkUndo(actions, false)
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
  }, false)
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

  local t = LoveCompat.getTime()
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

  local t = LoveCompat.getTime()
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

function M.tryHandleLinkHandleDoubleClickUnlink(toolbar, x, y, win, wm)
  return maybeHandleDoubleClick(toolbar, x, y, win, wm)
end

function M.beginDrag(toolbar, button, x, y, win, wm)
  if button ~= 2 then
    return false
  end
  if not (toolbar and win and isValidPaletteLinkHandle(toolbar, x, y)) then
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
  drag.originContentWin = nil
  drag.originPaletteWin = nil

  if WindowCaps.isRomPaletteWindow(win) then
    drag.mode = DRAG_MODE_LINK_CREATE
  elseif not WindowCaps.isAnyPaletteWindow(win) and not WindowCaps.isChrLike(win) then
    drag.mode = DRAG_MODE_LINK_CREATE_FROM_CONTENT
    drag.originContentWin = win
    drag.originPaletteWin = getActiveLayerLinkedPaletteWin(win, wm)
  else
    clearPaletteLinkDragState(drag, x, y)
    return false
  end

  if wm and wm.setFocus then
    wm:setFocus(win)
  end

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

--- While a palette-link drag is active, hide the link handle icon on the window it started from.
function M.shouldHidePaletteLinkHandleIconForWindow(win)
  local drag = getPaletteLinkDrag()
  return not not (drag and drag.active and win and drag.sourceWin == win)
end

function M.getActiveLayerLinkedPaletteWindow(contentWin, wm)
  return getActiveLayerLinkedPaletteWin(contentWin, wm)
end

function M.getLinkedRomPaletteWindowForLayer(contentWin, wm, layerIndex)
  return getLinkedRomPaletteWindowForLayer(contentWin, wm, layerIndex)
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
  local paletteWin = getLinkedRomPaletteWindowForLayer(contentWin, wm, layerIndex)
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
