local SpriteController = require("controllers.sprite.sprite_controller")
local SpriteOriginDrag = require("controllers.sprite.sprite_origin_drag_controller")
local MultiSelectController = require("controllers.input_support.multi_select_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local PaletteLinkController = require("controllers.palette.palette_link_controller")

local M = {}

local function updateSpriteHover(x, y, wm, fwin)
  local win = wm:windowAt(x, y) or fwin
  if not (win and win.layers and win.getActiveLayerIndex and SpriteController and SpriteController.pickSpriteAt) then
    return
  end

  local li = win:getActiveLayerIndex()
  local L = win.layers[li]
  if L and L.kind == "sprite" then
    local _, itemIndex = SpriteController.pickSpriteAt(win, x, y, li)
    if itemIndex then
      L.hoverSpriteIndex = itemIndex
    else
      L.hoverSpriteIndex = nil
    end
  end
end

local function handleWindowResizing(x, y, fwin)
  if fwin and fwin.resizing and fwin.mousemoved then
    fwin:mousemoved(x, y)
    return true
  end
  return false
end

local function forwardMouseMove(x, y, dx, dy, wm)
  local win = wm:windowAt(x, y)
  if win and win.mousemoved then
    win:mousemoved(x, y)
  end

  for _, w in ipairs(wm:getWindows()) do
    if w.mousemoved then w:mousemoved(x, y, dx, dy) end
  end
end

local function handleEditShapeDrag(env, x, y, wm)
  local ctx = env.ctx
  local utils = env.utils or {}
  if not (ctx and ctx.getMode and ctx.getMode() == "edit") then
    return false
  end
  if not love.mouse.isDown(1) then
    return false
  end

  local focused = wm:getFocus()
  local win = (focused and focused.editShapeDrag) and focused or nil
  if not (win and win.editShapeDrag) then
    return false
  end

  local shape = win.editShapeDrag
  if not shape or (shape.kind ~= "rect_or_line" and shape.kind ~= "rect_fill") then
    return false
  end

  local ok, col, row, lx, ly = win:toGridCoords(x, y)
  if not ok then
    return true
  end

  local px = col * (win.cellW or 8) + math.floor(lx or 0)
  local py = row * (win.cellH or 8) + math.floor(ly or 0)
  shape.currentX = px
  shape.currentY = py

  local tol = utils.DRAG_TOL or 4
  if math.abs(px - (shape.startX or px)) >= tol or math.abs(py - (shape.startY or py)) >= tol then
    shape.moved = true
  end

  return true
end

local function handlePaintingDrag(env, x, y, wm)
  local ctx = env.ctx
  local utils = env.utils or {}
  local dx = env.dx or 0
  local dy = env.dy or 0
  if ctx.getMode() ~= "edit" or not ctx.getPainting() or not love.mouse.isDown(1) then
    return false
  end

  if utils.fillDown and utils.fillDown() then
    return false
  end

  local w2 = wm:getFocus()
  if w2 then
    local pickOnly = utils.grabDown and utils.grabDown()
    local function paintInterpolatedSegment(win, x0, y0, x1, y1)
      if not (win and win.toContentCoords) then
        return false
      end

      local ok0, cx0, cy0 = win:toContentCoords(x0, y0)
      local ok1, cx1, cy1 = win:toContentCoords(x1, y1)
      if not ok1 then
        return false
      end

      if pickOnly or not ok0 then
        local ok, col, row, lx, ly = win:toGridCoords(x1, y1)
        if ok then
          ctx.paintAt(win, col, row, math.floor(lx), math.floor(ly), pickOnly)
          return true
        end
        return false
      end

      local dxContent = cx1 - cx0
      local dyContent = cy1 - cy0
      local steps = math.max(math.abs(dxContent), math.abs(dyContent))
      if steps < 1 then
        steps = 1
      end

      local painted = false
      local lastCol, lastRow, lastLx, lastLy
      for i = 0, steps do
        local t = i / steps
        local cx = cx0 + dxContent * t
        local cy = cy0 + dyContent * t
        local sampleCx = math.floor(cx)
        local sampleCy = math.floor(cy)

        local localCol = math.floor(sampleCx / win.cellW)
        local localRow = math.floor(sampleCy / win.cellH)
        if localCol >= 0 and localRow >= 0
          and localCol < (win.visibleCols or 0)
          and localRow < (win.visibleRows or 0) then
          local col = localCol + (win.scrollCol or 0)
          local row = localRow + (win.scrollRow or 0)
          if col >= 0 and row >= 0 and col < (win.cols or 0) and row < (win.rows or 0) then
            local lx = sampleCx - localCol * win.cellW
            local ly = sampleCy - localRow * win.cellH
            if col ~= lastCol or row ~= lastRow or lx ~= lastLx or ly ~= lastLy then
              ctx.paintAt(win, col, row, lx, ly, false)
              lastCol, lastRow, lastLx, lastLy = col, row, lx, ly
              painted = true
            end
          end
        end
      end

      return painted
    end

    paintInterpolatedSegment(w2, x - dx, y - dy, x, y)
  end
  return true
end

local function handleTilePaintDrag(env, x, y, wm)
  local ctx = env.ctx
  local utils = env.utils or {}
  local tilePaintState = env.tilePaintState

  if ctx.getMode() ~= "tile" then
    if tilePaintState then
      tilePaintState.active = false
      tilePaintState.lastCol = nil
      tilePaintState.lastRow = nil
    end
    return false
  end

  if not ((utils.ctrlDown and utils.ctrlDown()) and (utils.altDown and utils.altDown())) then
    if tilePaintState then
      tilePaintState.active = false
      tilePaintState.lastCol = nil
      tilePaintState.lastRow = nil
    end
    return false
  end

  if not love.mouse.isDown(1) then return false end
  if not tilePaintState or not tilePaintState.active then return false end

  local win = wm:windowAt(x, y)
  if not win then return false end
  if not WindowCaps.isStaticOrAnimationArt(win) then return false end

  local layerIdx = win:getActiveLayerIndex()
  local layer = win.layers and win.layers[layerIdx]
  if not layer or layer.kind ~= "tile" then return false end

  local ok, col, row = win:toGridCoords(x, y)
  if not ok then return false end

  if col == tilePaintState.lastCol and row == tilePaintState.lastRow then
    return true
  end

  local existingItem = win:get(col, row, layerIdx)
  if existingItem then return true end

  local selectedTile = utils.getSelectedTileFromCHR and utils.getSelectedTileFromCHR()
  if not selectedTile then return false end

  win:set(col, row, selectedTile, layerIdx)
  win:setSelected(col, row, layerIdx)
  tilePaintState.lastCol = col
  tilePaintState.lastRow = row

  return true
end

local function activateTileDrag(env, x, y)
  local drag = env.drag
  local utils = env.utils or {}
  local getTileClick = env.getTileClick

  if not (drag and drag.pending and not drag.active and love.mouse.isDown(1)) then
    return
  end

  local dxm, dym = x - drag.startX, y - drag.startY
  local tol = utils.DRAG_TOL or 4
  if (dxm * dxm + dym * dym) >= (tol * tol) then
    local tileClick = getTileClick and getTileClick() or nil
    if tileClick and tileClick.active then
      tileClick.moved = true
    end
    drag.active = true

    if (not drag.copyMode)
      and (not drag.tileGroup)
      and drag.srcWin
      and drag.srcWin.kind ~= "chr"
      and drag.srcWin.kind ~= "ppu_frame"
      and drag.srcWin.set
    then
      local srcLayer = drag.srcLayer or (drag.srcWin.getActiveLayerIndex and drag.srcWin:getActiveLayerIndex()) or 1
      local layer = drag.srcWin.layers and drag.srcWin.layers[srcLayer]
      if layer and layer.kind ~= "sprite" then
        drag.srcWin:set(drag.srcCol, drag.srcRow, nil, srcLayer)
        drag.srcTemporarilyCleared = true
      end
    end
  end
end

function M.handleMouseMoved(env, x, y, dx, dy)
  local ctx = env.ctx
  local drag = env.drag
  local utils = env.utils or {}
  local chrome = env.chrome
  local getSpriteClick = env.getSpriteClick
  local app = ctx and ctx.app or nil
  env.dx = dx or 0
  env.dy = dy or 0

  if SpriteOriginDrag.updateMove(ctx, x, y, utils) then
    return true
  end

  if SpriteController.isDragging() then
    local spriteClick = getSpriteClick and getSpriteClick() or nil
    if spriteClick and spriteClick.active and not spriteClick.moved then
      local dxm = x - (spriteClick.startX or x)
      local dym = y - (spriteClick.startY or y)
      local tol = utils.DRAG_TOL or 4
      if (dxm * dxm + dym * dym) >= (tol * tol) then
        spriteClick.moved = true
      end
    end
    SpriteController.updateDrag(x, y)
    return true
  end

  SpriteController.updateSpriteMarquee(x, y)
  MultiSelectController.updateTileMarquee(x, y)

  local wm = ctx.wm()
  local fwin = wm:getFocus()

  if drag and (drag.pending or drag.active) then
    drag.currentX = x
    drag.currentY = y
  end

  if app and app.paletteLinkDrag and app.paletteLinkDrag.active and PaletteLinkController.updateDragHover then
    PaletteLinkController.updateDragHover(wm, x, y)
  end

  chrome.updateToolbarHover(x, y, wm)
  updateSpriteHover(x, y, wm, fwin)
  if handleWindowResizing(x, y, fwin) then return true end
  forwardMouseMove(x, y, dx, dy, wm)
  if handleEditShapeDrag(env, x, y, wm) then return true end
  if handleTilePaintDrag(env, x, y, wm) then return true end
  if handlePaintingDrag(env, x, y, wm) then return true end
  activateTileDrag(env, x, y)
  return true
end

return M
