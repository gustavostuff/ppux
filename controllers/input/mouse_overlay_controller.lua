local MultiSelectController = require("controllers.input_support.multi_select_controller")
local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local colors = require("app_colors")
local Draw = require("utils.draw_utils")
local images = require("images")

local M = {}

local function resolvePreviewItem(win, item, layerIndex)
  if item == nil then
    return nil
  end
  if win and win.materializeTileHandle then
    local resolved = win:materializeTileHandle(item, layerIndex)
    if resolved ~= nil then
      return resolved
    end
  end
  return item
end

local function canDrawChrVirtualPreview(env, item)
  local drag = env and env.drag
  local app = env and env.ctx and env.ctx.app
  local controller = app and app.chrBankCanvasController
  local state = app and app.appEditState
  return drag
    and drag.srcWin
    and WindowCaps.isChrLike(drag.srcWin)
    and item
    and item._virtual == true
    and controller
    and state
end

local function drawChrVirtualPreview(env, item, x, y, opts)
  if not canDrawChrVirtualPreview(env, item) then
    return false
  end

  local drag = env.drag
  local app = env.ctx.app
  local controller = app.chrBankCanvasController
  local state = app.appEditState
  local orderMode = drag.srcWin and drag.srcWin.orderMode or "normal"
  opts = opts or {}

  if not controller:drawTileHandle(state, item, orderMode, x, y, opts.sx, opts.sy, drag.ghostAlpha) then
    return false
  end

  if opts.bottomItem then
    controller:drawTileHandle(
      state,
      opts.bottomItem,
      orderMode,
      x,
      y + (opts.bottomOffsetY or 0),
      opts.sx,
      opts.sy,
      drag.ghostAlpha
    )
  end

  love.graphics.setColor(colors.white)
  Draw.drawRepeatingImageAnimated(images.pattern_a, math.floor(x), math.floor(y), opts.w or 0, opts.h or 0)
  love.graphics.setColor(colors.white)
  return true
end

local function resolveChrBottomPreviewItem(env, topItem, explicitBottomItem)
  if explicitBottomItem then
    local drag = env and env.drag
    return resolvePreviewItem(drag and drag.srcWin, explicitBottomItem, drag and drag.srcLayer)
  end
  if not topItem then
    return nil
  end

  local app = env and env.ctx and env.ctx.app
  local tilesPool = app and app.appEditState and app.appEditState.tilesPool
  local bank = topItem._bankIndex
  local tileIndex = topItem.index
  if not (tilesPool and type(bank) == "number" and type(tileIndex) == "number") then
    return nil
  end

  local poolBank = tilesPool[bank]
  local bottomItem = poolBank and poolBank[tileIndex + 1] or nil
  if bottomItem ~= nil then
    return bottomItem
  end

  local drag = env and env.drag
  local srcWin = drag and drag.srcWin
  if srcWin and srcWin.materializeTileHandle then
    return srcWin:materializeTileHandle({
      kind = "chr_virtual_tile",
      index = tileIndex + 1,
      _bankIndex = bank,
      _virtual = true,
    }, drag and drag.srcLayer)
  end

  return nil
end

function M.drawOverlay(env)
  local drag = env and env.drag
  local ctx = env and env.ctx
  if not (
    drag and
    drag.active and
    drag.srcWin
  ) then
    return
  end

  local mouse = ResolutionController:getScaledMouse(true)
  local wm = ctx.wm()
  local mouseX = drag.currentX or mouse.x
  local mouseY = drag.currentY or mouse.y
  local win = wm:windowAt(drag.currentX or mouse.x, drag.currentY or mouse.y) or drag.srcWin

  if not win or win.isPalette or type(win.toGridCoords) ~= "function" then
    return
  end

  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local cw = win.cellW or 8
  local ch = win.cellH or 8
  if not (cw and ch) then return end

  local previewItem = drag.item
  local resolvedPreviewItem = resolvePreviewItem(drag.srcWin, previewItem, drag.srcLayer)
  local hasSingleDrawable = canDrawChrVirtualPreview(env, previewItem)
    or (resolvedPreviewItem and type(resolvedPreviewItem.draw) == "function")
  local hasTileGroup = drag.tileGroup and drag.tileGroup.entries and #drag.tileGroup.entries > 0
  if (not hasSingleDrawable) and (not hasTileGroup) then
    return
  end

  local gx, gy
  local chrGroupDropState = nil

  local srcIsChr = WindowCaps.isChrLike(drag.srcWin)
  local dstLayer = win:getActiveLayerIndex() or drag.srcLayer or 1
  local layer = win.layers and win.layers[dstLayer]
  local isSpriteLayer = layer and layer.kind == "sprite"
  local ghostW = cw * z
  local ghostH = ch * z
  if isSpriteLayer then
    local mode = layer and layer.mode or "8x8"
    if mode == "8x16" then
      ghostH = ghostH * 2
    end
  end

  if hasTileGroup and srcIsChr then
    chrGroupDropState = MouseTileDropController.getHoverDropState(env, mouseX, mouseY, wm)
  end

  if isSpriteLayer and srcIsChr and not (env.isSpriteLayerDropBlocked and env.isSpriteLayerDropBlocked(win, layer, drag.srcWin)) then
    local scol = win.scrollCol or 0
    local srow = win.scrollRow or 0
    if chrGroupDropState and chrGroupDropState.anchorPixelX and chrGroupDropState.anchorPixelY then
      gx = win.x + ((chrGroupDropState.anchorPixelX - scol * cw) * z)
      gy = win.y + ((chrGroupDropState.anchorPixelY - srow * ch) * z)
    else
      local cx = (mouseX - win.x) / z
      local cy = (mouseY - win.y) / z
      local pixelX = cx + scol * cw
      local pixelY = cy + srow * ch

      pixelX = math.floor(pixelX + 0.5)
      pixelY = math.floor(pixelY + 0.5)

      gx = win.x + ((pixelX - scol * cw) * z)
      gy = win.y + ((pixelY - srow * ch) * z)
    end
  else
    local ok, col, row = win:toGridCoords(mouseX, mouseY)
    if not ok or type(col) ~= "number" or type(row) ~= "number" then
      col, row = MultiSelectController.getGridCoordsClamped(win, mouseX, mouseY)
      if type(col) ~= "number" or type(row) ~= "number" then
        return
      end
    end

    if hasTileGroup and srcIsChr and chrGroupDropState and chrGroupDropState.anchorCol and chrGroupDropState.anchorRow then
      col, row = chrGroupDropState.anchorCol, chrGroupDropState.anchorRow
    elseif hasTileGroup then
      local anchorCol, anchorRow = MultiSelectController.clampTileDropAnchor(win, drag.tileGroup, col, row)
      if type(anchorCol) == "number" and type(anchorRow) == "number" then
        col, row = anchorCol, anchorRow
      else
        return
      end
    end

    local scol = win.scrollCol or 0
    local srow = win.scrollRow or 0
    gx = win.x + (((col - scol) * cw) * z)
    gy = win.y + (((row - srow) * ch) * z)
  end

  local function drawGhost(item, x, y, w, h, opts)
    opts = opts or {}
    if drawChrVirtualPreview(env, item, x, y, {
      bottomItem = opts.bottomItem,
      bottomOffsetY = ch * z,
      sx = z,
      sy = z,
      w = w,
      h = h,
    }) then
      return
    end

    item = resolvePreviewItem(drag.srcWin, item, drag.srcLayer)
    if not (item and type(item.draw) == "function") then return end
    local bottomItem = resolvePreviewItem(drag.srcWin, opts.bottomItem, drag.srcLayer)
    love.graphics.setColor(1, 1, 1, drag.ghostAlpha)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(z, z)
    item:draw(0, 0, 1)
    if bottomItem and type(bottomItem.draw) == "function" then
      bottomItem:draw(0, ch, 1)
    end
    love.graphics.pop()
    love.graphics.setColor(colors.white)
    Draw.drawRepeatingImageAnimated(images.pattern_a, math.floor(x), math.floor(y), w, h)
    love.graphics.setColor(colors.white)
  end

  if hasTileGroup and isSpriteLayer and srcIsChr and chrGroupDropState and chrGroupDropState.placements then
    local scol = win.scrollCol or 0
    local srow = win.scrollRow or 0
    for _, placement in ipairs(chrGroupDropState.placements) do
      local px = win.x + ((placement.pixelX - scol * cw) * z)
      local py = win.y + ((placement.pixelY - srow * ch) * z)
      local bottomPreviewItem = nil
      if (layer.mode or "8x8") == "8x16" then
        bottomPreviewItem = resolveChrBottomPreviewItem(env, placement.item, placement.bottomItem)
      end
      drawGhost(placement.item, px, py, cw * z, ghostH, {
        bottomItem = bottomPreviewItem,
      })
    end
    return
  end

  if hasTileGroup and not (isSpriteLayer and srcIsChr) then
    for _, entry in ipairs(drag.tileGroup.entries or {}) do
      local ox = (entry.offsetCol or 0) * cw * z
      local oy = (entry.offsetRow or 0) * ch * z
      drawGhost(entry.item, gx + ox, gy + oy, cw * z, ch * z)
    end
    return
  end

  local bottomPreviewItem = nil
  if isSpriteLayer and (layer.mode or "8x8") == "8x16" and srcIsChr then
    bottomPreviewItem = resolveChrBottomPreviewItem(env, drag.item)
  end
  drawGhost(drag.item, gx, gy, ghostW, ghostH, {
    bottomItem = bottomPreviewItem,
  })
end

return M
