-- Shift + right-drag to adjust sprite layer originX/originY (PPU Frame, OAM Animation).

local WindowCaps = require("controllers.window.window_capabilities")
local SpriteController = require("controllers.sprite.sprite_controller")

local M = {}

local state = {
  pending = false,
  dragging = false,
  win = nil,
  layerIndex = nil,
  startX = 0,
  startY = 0,
  lastCx = nil,
  lastCy = nil,
  originStartX = nil,
  originStartY = nil,
  sumCx = nil,
  sumCy = nil,
}

local DRAG_TOL = 4

-- Match drawSprites / pickSpriteAt (nearestZoomStep); raw win.zoom can diverge in theory.
local function effectiveZoom(win)
  local z = (win and win.getZoomLevel and win:getZoomLevel()) or (win and win.zoom) or 1
  if z <= 0 then
    return 1
  end
  return z
end

local function clampOriginX(v)
  v = math.floor(tonumber(v) or 0)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

local function clampOriginY(v)
  v = math.floor(tonumber(v) or 0)
  if v < 0 then return 0 end
  if v > 239 then return 239 end
  return v
end

function M.clear()
  state.pending = false
  state.dragging = false
  state.win = nil
  state.layerIndex = nil
  state.startX = 0
  state.startY = 0
  state.lastCx = nil
  state.lastCy = nil
  state.originStartX = nil
  state.originStartY = nil
  state.sumCx = nil
  state.sumCy = nil
end

function M.isActive()
  return state.pending == true or state.dragging == true
end

--- Right press + Shift on PPU Frame / OAM Animation sprite layer (content below header).
function M.tryBeginPress(_ctx, utils, x, y, win, wm)
  if not (utils.shiftDown and utils.shiftDown()) then
    return false
  end
  if not (win and (WindowCaps.isPpuFrame(win) or WindowCaps.isOamAnimation(win))) then
    return false
  end

  local li = win.getActiveLayerIndex and win:getActiveLayerIndex() or win.activeLayer or 1
  local L = win.layers and win.layers[li]
  if not (L and L.kind == "sprite") then
    return false
  end

  if win.toContentCoords and not select(1, win:toContentCoords(x, y)) then
    return false
  end

  if win.getHeaderRect then
    local _, hy, _, hh = win:getHeaderRect()
    if type(hy) == "number" and type(hh) == "number" and y < (hy + hh) then
      return false
    end
  end

  wm:setFocus(win)
  state.pending = true
  state.dragging = false
  state.win = win
  state.layerIndex = li
  state.startX = x
  state.startY = y
  state.lastCx = nil
  state.lastCy = nil
  state.originStartX = nil
  state.originStartY = nil
  state.sumCx = nil
  state.sumCy = nil
  return true
end

function M.updateMove(ctx, x, y, utils)
  if not (state.pending or state.dragging) then
    return false
  end
  if not (love and love.mouse and love.mouse.isDown(2)) then
    return false
  end

  local win = state.win
  local li = state.layerIndex

  if state.pending and not state.dragging then
    local dxm = x - state.startX
    local dym = y - state.startY
    if (dxm * dxm + dym * dym) < (DRAG_TOL * DRAG_TOL) then
      return false
    end
    local L0 = win and win.layers and li and win.layers[li]
    if not (L0 and L0.kind == "sprite") then
      M.clear()
      return false
    end
    state.dragging = true
    state.pending = false
    local z0 = effectiveZoom(win)
    -- Content-space anchor (float) so zoom matches what the window draws; immune to accidental win.x drift.
    state.lastCx = (state.startX - (win and win.x or 0)) / z0
    state.lastCy = (state.startY - (win and win.y or 0)) / z0
    -- Integer origins + fractional motion per frame at zoom>1: accumulate before floor in clamp*.
    state.originStartX = L0.originX or 0
    state.originStartY = L0.originY or 0
    state.sumCx = 0
    state.sumCy = 0
  end

  if not state.dragging then
    return false
  end

  if not (win and win.layers and li) then
    return false
  end

  local L = win.layers[li]
  if not (L and L.kind == "sprite") then
    return false
  end

  local z = effectiveZoom(win)
  local cx = (x - win.x) / z
  local cy = (y - win.y) / z
  local dcx = cx - (state.lastCx or cx)
  local dcy = cy - (state.lastCy or cy)
  state.lastCx = cx
  state.lastCy = cy

  state.sumCx = (state.sumCx or 0) + dcx
  state.sumCy = (state.sumCy or 0) + dcy
  L.originX = clampOriginX((state.originStartX or 0) + state.sumCx)
  L.originY = clampOriginY((state.originStartY or 0) + state.sumCy)

  local app = ctx and ctx.app
  if app and app.markUnsaved then
    app:markUnsaved("sprite_origin_drag")
  end

  local tb = win.specializedToolbar
  if tb and tb.updateOriginButtons then
    tb:updateOriginButtons()
  end

  if ctx and ctx.setStatus then
    ctx.setStatus(string.format("Sprite origin: %d, %d", L.originX, L.originY))
  end

  return true
end

--- Returns true if this controller handled the release (caller should stop other handlers).
function M.finishRelease(ctx, button, x, y, app)
  if button ~= 2 then
    return false
  end
  if not (state.pending or state.dragging) then
    return false
  end

  local wasDragging = state.dragging
  local wasPending = state.pending
  local win = state.win
  local li = state.layerIndex
  local sx, sy = state.startX, state.startY

  M.clear()

  if wasDragging then
    return true
  end

  if wasPending and win and app then
    local pickedLayerIndex, itemIndex = SpriteController.pickSpriteAt(win, sx, sy, li)
    if type(pickedLayerIndex) == "number" and type(itemIndex) == "number" then
      if app.showSelectInChrContextMenu then
        app:showSelectInChrContextMenu(win, pickedLayerIndex, nil, nil, itemIndex, sx, sy)
      end
      return true
    end
    if WindowCaps.isOamAnimation(win) and app.showOamSpriteEmptySpaceContextMenu then
      app:showOamSpriteEmptySpaceContextMenu(win, li, sx, sy)
      return true
    end
  end

  return wasPending
end

return M
