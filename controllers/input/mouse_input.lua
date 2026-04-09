-- ============================================================================
-- Mouse Input Handler
-- ============================================================================

local DebugController = require("controllers.dev.debug_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local MultiSelectController = require("controllers.input_support.multi_select_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")
local MouseWheelController = require("controllers.input.mouse_wheel_controller")
local MouseOverlayController = require("controllers.input.mouse_overlay_controller")
local MouseWindowChromeController = require("controllers.input.mouse_window_chrome_controller")
local MouseClickController = require("controllers.input.mouse_click_controller")
local MouseMoveController = require("controllers.input.mouse_move_controller")
local SpriteOriginDrag = require("controllers.sprite.sprite_origin_drag_controller")

local M = {}

local ctx
local drag
local tilePaintState
local utils = {}
local tileClick = { active = false }
local spriteClick = { active = false }
local contextClick = { active = false }
local CONTEXT_MENU_DRAG_TOLERANCE = 4

local function fmtWin(win)
  if not win then return "nil" end
  return string.format("%s:%s", tostring(win.kind or "?"), tostring(win._id or win.title or "?"))
end

local function getFocusedWindowSafe()
  if not (ctx and ctx.wm) then return nil end
  local wm = ctx.wm()
  return wm and wm:getFocus() or nil
end

local function logRoute(eventName, route, x, y, buttonOrExtra, focusWin)
  DebugController.log(
    "debug",
    "INPUT_ROUTE",
    "event=%s route=%s x=%s y=%s arg=%s focus=%s",
    tostring(eventName),
    tostring(route),
    tostring(x),
    tostring(y),
    tostring(buttonOrExtra),
    fmtWin(focusWin)
  )
end

function M.setup(context, dragState, paintState, utilities)
  ctx = context
  drag = dragState
  tilePaintState = paintState
  utils = utilities or {}
  MultiSelectController.reset()
  tileClick = { active = false }
  spriteClick = { active = false }
  contextClick = { active = false }
end

function M.resetTransientState()
  if drag then
    drag.pending = false
    drag.active = false
    drag.item = nil
    drag.srcWin = nil
    drag.srcCol = nil
    drag.srcRow = nil
    drag.srcLayer = nil
    drag.srcStackIndex = nil
    drag.copyMode = false
    drag.tileGroup = nil
    drag.srcTemporarilyCleared = false
  end
  if tilePaintState then
    tilePaintState.active = false
    tilePaintState.lastCol = nil
    tilePaintState.lastRow = nil
  end
  tileClick = { active = false }
  spriteClick = { active = false }
  contextClick = { active = false }
  local app = ctx and ctx.app or nil
  if app and app.paletteLinkDrag then
    app.paletteLinkDrag.active = false
    app.paletteLinkDrag.sourceWin = nil
    app.paletteLinkDrag.sourceWinId = nil
    app.paletteLinkDrag.mode = nil
    app.paletteLinkDrag.originContentWin = nil
    app.paletteLinkDrag.originPaletteWin = nil
  end
  SpriteOriginDrag.clear()
  MultiSelectController.reset()
  if SpriteController and SpriteController.endDrag then
    SpriteController.endDrag()
  end
end

local function markUnsaved(eventType)
  local app = ctx and ctx.app
  if app and app.markUnsaved then
    app:markUnsaved(eventType)
  end
end

local function isSpriteLayerDropBlocked(dst, layer, srcWin)
  if not WindowCaps.isChrLike(srcWin) then return false end
  if not (dst and layer and layer.kind == "sprite") then return false end
  return WindowCaps.isPpuFrame(dst) or WindowCaps.isOamAnimation(dst)
end

local function handleToolbarClicks(button, x, y, win, wm)
  return MouseWindowChromeController.handleToolbarClicks(button, x, y, win, wm)
end

local function handleToolbarRelease(button, x, y, wm)
  return MouseWindowChromeController.handleToolbarRelease(button, x, y, wm)
end

local function updateToolbarHover(x, y, wm)
  return MouseWindowChromeController.updateToolbarHover(x, y, wm)
end

local function handleHeaderClick(button, x, y, win, wm)
  return MouseWindowChromeController.handleHeaderClick(button, x, y, win, wm)
end

local function handleResizeHandle(button, x, y, wm)
  return MouseWindowChromeController.handleResizeHandle(button, x, y, wm)
end

local function beginContextMenuClick(kind, x, y, button, win, extra)
  contextClick = {
    active = true,
    kind = kind,
    button = button,
    startX = x,
    startY = y,
    moved = false,
    win = win,
  }
  if type(extra) == "table" then
    for k, v in pairs(extra) do
      contextClick[k] = v
    end
  end
end

local function updateContextMenuDragState(x, y)
  if not (contextClick and contextClick.active) then
    return
  end

  if math.abs((x or 0) - (contextClick.startX or 0)) > CONTEXT_MENU_DRAG_TOLERANCE
      or math.abs((y or 0) - (contextClick.startY or 0)) > CONTEXT_MENU_DRAG_TOLERANCE then
    contextClick.moved = true
  end
end

local function handleContextMenuRelease(button, x, y)
  if not (contextClick and contextClick.active) then
    return false
  end

  local pending = contextClick
  contextClick = { active = false }

  if button ~= pending.button then
    return false
  end
  if pending.moved then
    return false
  end

  local app = ctx and ctx.app or nil
  if not app then
    return false
  end

  if pending.kind == "window_header" then
    if app.showWindowHeaderContextMenu and pending.win then
      app:showWindowHeaderContextMenu(pending.win, x, y)
      return true
    end
    return false
  end

  if pending.kind == "empty_space" then
    if app.showEmptySpaceContextMenu then
      app:showEmptySpaceContextMenu(x, y)
      return true
    end
    return false
  end

  if pending.kind == "ppu_tile" then
    if app.showPpuTileContextMenu and pending.win then
      app:showPpuTileContextMenu(pending.win, pending.layerIndex, pending.col, pending.row, x, y)
      return true
    end
    return false
  end

  if pending.kind == "select_in_chr" then
    if app.showSelectInChrContextMenu and pending.win then
      app:showSelectInChrContextMenu(
        pending.win,
        pending.layerIndex,
        pending.col,
        pending.row,
        pending.itemIndex,
        x,
        y
      )
      return true
    end
    return false
  end

  if pending.kind == "chr_bank_tile" then
    if app.showChrBankTileContextMenu and pending.win and type(pending.col) == "number" and type(pending.row) == "number" then
      app:showChrBankTileContextMenu(pending.win, pending.col, pending.row, x, y)
      return true
    end
    return false
  end

  if pending.kind == "oam_sprite_empty" then
    if app.showOamSpriteEmptySpaceContextMenu and pending.win then
      app:showOamSpriteEmptySpaceContextMenu(
        pending.win,
        pending.layerIndex,
        x,
        y
      )
      return true
    end
    return false
  end

  if pending.kind == "palette_link_source" then
    if app.showPaletteLinkSourceContextMenu and pending.win then
      app:showPaletteLinkSourceContextMenu(pending.win, x, y)
      return true
    end
    return false
  end

  if pending.kind == "palette_link_destination" then
    if app.showPaletteLinkDestinationContextMenu and pending.win then
      app:showPaletteLinkDestinationContextMenu(pending.win, x, y)
      return true
    end
    return false
  end

  return false
end

--- Palette link handle on the app-top docked toolbar (canvas coordinates throughout).
function M.beginPaletteLinkContextFromAppTopBar(win, canvasX, canvasY, button)
  if button ~= 1 then
    return false
  end
  local wm = ctx and ctx.wm and ctx.wm() or nil
  if wm and wm.setFocus and win then
    wm:setFocus(win)
  end
  if WindowCaps.isRomPaletteWindow(win) then
    beginContextMenuClick("palette_link_source", canvasX, canvasY, button, win)
    return true
  end
  if WindowCaps.isAnyPaletteWindow(win) or WindowCaps.isChrLike(win) then
    return false
  end
  local layerIndex = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  beginContextMenuClick("palette_link_destination", canvasX, canvasY, button, win, { layerIndex = layerIndex })
  return true
end

-- ===== Mouse =====
function M.mousepressed(x, y, button)
  local handled = MouseClickController.handleMousePressed({
    ctx = ctx,
    drag = drag,
    tilePaintState = tilePaintState,
    utils = utils,
    chrome = MouseWindowChromeController,
    getTileClick = function() return tileClick end,
    setTileClick = function(v) tileClick = v end,
    getSpriteClick = function() return spriteClick end,
    setSpriteClick = function(v) spriteClick = v end,
    beginContextMenuClick = beginContextMenuClick,
  }, x, y, button)
  logRoute("mousepressed", handled and "mouse_click_controller" or "unhandled", x, y, button, getFocusedWindowSafe())
end

function M.mousemoved(x, y, dx, dy)
  updateContextMenuDragState(x, y)
  MouseMoveController.handleMouseMoved({
    ctx = ctx,
    drag = drag,
    tilePaintState = tilePaintState,
    utils = utils,
    chrome = MouseWindowChromeController,
    getTileClick = function() return tileClick end,
    getSpriteClick = function() return spriteClick end,
  }, x, y, dx, dy)
end

local function clearDragState(commitDrop)
  if drag and drag.srcTemporarilyCleared and (not commitDrop) then
    local srcLayer = drag.srcLayer or (drag.srcWin and drag.srcWin.getActiveLayerIndex and drag.srcWin:getActiveLayerIndex()) or 1
    if drag.srcWin and drag.srcWin.set and drag.item then
      drag.srcWin:set(drag.srcCol, drag.srcRow, drag.item, srcLayer)
    end
  end

  drag.active = false
  drag.pending = false
  drag.item = nil
  drag.srcWin, drag.srcCol, drag.srcRow, drag.srcLayer = nil, nil, nil, nil
  drag.srcStackIndex = nil
  drag.copyMode = false
  drag.tileGroup = nil
  drag.srcTemporarilyCleared = false
  tileClick = { active = false }
end

local function handleResizeEnd(button, x, y, fwin)
  return MouseWindowChromeController.handleResizeEnd(button, x, y, fwin)
end

local function handleWindowDragEnd(button, x, y, fwin)
  return MouseWindowChromeController.handleWindowDragEnd(button, x, y, fwin)
end

local function handleSpriteDragEnd()
  if SpriteController.isDragging() then
    if spriteClick and spriteClick.active and not spriteClick.moved and spriteClick.ctrlSelection then
      -- Ctrl+click without drag is used for additive selection.
      -- Cancel copy-drag side effects (temporary clones) and keep the original selection.
      SpriteController.endDrag()

      local win = spriteClick.win
      local layerIndex = spriteClick.layerIndex
      local targetIndex = spriteClick.targetIndex
      local layer = win and win.layers and layerIndex and win.layers[layerIndex] or nil
      if layer and layer.kind == "sprite" then
        local indices = SpriteController.getSelectedSpriteIndicesInOrder(layer)
        local hasTarget = false
        for _, idx in ipairs(indices) do
          if idx == targetIndex then
            hasTarget = true
            break
          end
        end
        if not hasTarget and targetIndex then
          indices[#indices + 1] = targetIndex
          SpriteController.setSpriteSelection(layer, indices)
        end
        layer.selectedSpriteIndex = targetIndex
        layer.hoverSpriteIndex = targetIndex
      end

      spriteClick = { active = false }
      return true
    end

    -- Copy mode is decided when drag starts (Ctrl+click/drag).
    -- Releasing Ctrl before mouse-up should not cancel copy.
    local app = ctx and ctx.app
    local undoRedo = app and app.undoRedo
    SpriteController.finishDrag(nil, undoRedo)

    if spriteClick and spriteClick.active and not spriteClick.moved then
      local win = spriteClick.win
      local layerIndex = spriteClick.layerIndex
      local targetIndex = spriteClick.targetIndex
      local layer = win and win.layers and layerIndex and win.layers[layerIndex] or nil
      if layer and layer.kind == "sprite" then
        local target = layer.items and layer.items[targetIndex]
        if target and target.removed ~= true then
          SpriteController.setSpriteSelection(layer, { targetIndex })
          layer.selectedSpriteIndex = targetIndex
          layer.hoverSpriteIndex = targetIndex
        end
      end
    end

    spriteClick = { active = false }
    return true
  end
  spriteClick = { active = false }
  return false
end

local function handleClickCancel(button)
  if button == 1 and drag and drag.pending and not drag.active then
    if tileClick and tileClick.active and not tileClick.moved then
      MultiSelectController.clearTileMultiSelection(tileClick.win, tileClick.layerIdx)
      if tileClick.win and tileClick.win.setSelected then
        tileClick.win:setSelected(tileClick.col, tileClick.row, tileClick.layerIdx)
      end
    end
    clearDragState()
    return true
  end
  return false
end

local function handleTileDrop(x, y, wm)
  return MouseTileDropController.handleTileDrop({
    ctx = ctx,
    drag = drag,
    clearDragState = clearDragState,
    markUnsaved = markUnsaved,
    isSpriteLayerDropBlocked = isSpriteLayerDropBlocked,
  }, x, y, wm)
end

local function finishEditShape(x, y, button)
  if button ~= 1 then return false end
  local win = ctx and ctx.wm and ctx.wm():getFocus() or nil
  if not (win and win.editShapeDrag) then
    return false
  end

  local shape = win.editShapeDrag
  win.editShapeDrag = nil
  local BrushController = require("controllers.input_support.brush_controller")
  local app = ctx and ctx.app or nil
  if not (app and app.undoRedo) then
    return false
  end

  if shape.kind == "rect_fill" then
    local endX = shape.currentX or shape.startX
    local endY = shape.currentY or shape.startY
    app.undoRedo:startPaintEvent()
    local ok = BrushController.fillRect(app, win, shape.startX, shape.startY, endX, endY, false)
    if ok then
      app.undoRedo:finishPaintEvent()
      win.editLastPoint = { x = endX, y = endY }
      if ctx.setStatus then
        ctx.setStatus("Filled rectangle drawn")
      end
    else
      app.undoRedo:cancelPaintEvent()
      if ctx.setStatus then
        ctx.setStatus("Rectangle draw failed")
      end
    end
    return true
  end

  if shape.kind ~= "rect_or_line" then
    return false
  end

  local endX = shape.currentX or shape.startX
  local endY = shape.currentY or shape.startY

  if shape.moved then
    app.undoRedo:startPaintEvent()
    local ok = BrushController.fillRect(app, win, shape.startX, shape.startY, endX, endY, false)
    if ok then
      app.undoRedo:finishPaintEvent()
      win.editLastPoint = { x = endX, y = endY }
      if ctx.setStatus then
        ctx.setStatus("Filled rectangle drawn")
      end
    else
      app.undoRedo:cancelPaintEvent()
      if ctx.setStatus then
        ctx.setStatus("Rectangle draw failed")
      end
    end
    return true
  end

  if win.editLastPoint then
    app.undoRedo:startPaintEvent()
    local ok = BrushController.drawLine(app, win, win.editLastPoint.x, win.editLastPoint.y, endX, endY, false)
    if ok then
      app.undoRedo:finishPaintEvent()
      win.editLastPoint = { x = endX, y = endY }
      if ctx.setStatus then
        ctx.setStatus("Line drawn")
      end
    else
      app.undoRedo:cancelPaintEvent()
      if ctx.setStatus then
        ctx.setStatus("Line draw failed")
      end
    end
  else
    win.editLastPoint = { x = endX, y = endY }
    if ctx.setStatus then
      ctx.setStatus("Line anchor set")
    end
  end

  return true
end

function M.mousereleased(x, y, button)
  local wm = ctx.wm()
  local fwin = wm:getFocus()

  -- Handle toolbar releases first (for the focused window)
  if handleToolbarRelease(button, x, y, wm) then
    logRoute("mousereleased", "toolbar_release", x, y, button, fwin)
    return
  end

  if finishEditShape(x, y, button) then
    logRoute("mousereleased", "edit_shape", x, y, button, fwin)
    return
  end

  -- Finish undo/redo paint event if we were painting
  if ctx.getMode() == "edit" and ctx.getPainting() and ctx.app and ctx.app.undoRedo then
    if ctx.app.undoRedo:finishPaintEvent() then
      -- Paint event was stored successfully
      if fwin and fwin.toGridCoords then
        local ok, col, row, lx, ly = fwin:toGridCoords(x, y)
        if ok then
          local px = col * (fwin.cellW or 8) + math.floor(lx or 0)
          local py = row * (fwin.cellH or 8) + math.floor(ly or 0)
          fwin.editLastPoint = { x = px, y = py }
        end
      end
      ctx.setPainting(false)
    else
      -- No pixels were painted, just cancel
      ctx.app.undoRedo:cancelPaintEvent()
      ctx.setPainting(false)
    end
  end

  -- Clear tile paint state on mouse release
  if tilePaintState then
    tilePaintState.active = false
    tilePaintState.lastCol = nil
    tilePaintState.lastRow = nil
  end

  if SpriteController.finishSpriteMarquee(x, y) then logRoute("mousereleased", "finish_sprite_marquee", x, y, button, fwin); return end
  if MultiSelectController.finishTileMarquee(x, y) then logRoute("mousereleased", "finish_tile_marquee", x, y, button, fwin); return end
  local resizeEnded = handleResizeEnd(button, x, y, fwin)
  local windowDragEnded = handleWindowDragEnd(button, x, y, fwin)
  local spriteDragEnded = handleSpriteDragEnd()
  if SpriteOriginDrag.finishRelease(ctx, button, x, y, ctx and ctx.app) then
    logRoute("mousereleased", "sprite_origin_drag", x, y, button, fwin)
    return
  end
  if handleContextMenuRelease(button, x, y) then logRoute("mousereleased", "context_menu_release", x, y, button, fwin); return end
  if resizeEnded then logRoute("mousereleased", "resize_end", x, y, button, fwin); return end
  if windowDragEnded then logRoute("mousereleased", "window_drag_end", x, y, button, fwin); return end
  if spriteDragEnded then logRoute("mousereleased", "sprite_drag_end", x, y, button, fwin); return end
  if handleClickCancel(button) then logRoute("mousereleased", "click_cancel", x, y, button, fwin); return end
  if handleTileDrop(x, y, wm) then logRoute("mousereleased", "tile_drop", x, y, button, fwin); return end

  -- Forward regular releases to the window under cursor
  local win = wm:windowAt(x, y)
  if win and win.mousereleased then
    win:mousereleased(x, y, button)
    logRoute("mousereleased", "window_forward", x, y, button, win)
    return
  end
  logRoute("mousereleased", "unhandled", x, y, button, fwin)
end

function M.wheelmoved(dx, dy)
  local handled = MouseWheelController.handleWheel({ ctx = ctx, utils = utils }, dx, dy)
  logRoute("wheelmoved", handled and "mouse_wheel_controller" or "unhandled", dx, dy, "wheel", getFocusedWindowSafe())
  return handled
end

function M.drawOverlay()
  return MouseOverlayController.drawOverlay({
    ctx = ctx,
    drag = drag,
    isSpriteLayerDropBlocked = isSpriteLayerDropBlocked,
  })
end

function M.getTooltipCandidate(x, y)
  if not (ctx and ctx.wm and MouseTileDropController.getHoverTooltipCandidate) then
    return nil
  end
  return MouseTileDropController.getHoverTooltipCandidate({
    ctx = ctx,
    drag = drag,
    isSpriteLayerDropBlocked = isSpriteLayerDropBlocked,
  }, x, y, ctx.wm())
end

function M.getTileMarquee()
  return MultiSelectController.getTileMarquee()
end

return M
