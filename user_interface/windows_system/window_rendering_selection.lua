local images = require("images")
local colors = require("app_colors")
local Draw = require("utils.draw_utils")
local SpriteController = require("controllers.sprite.sprite_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local SpaceHighlightController = require("controllers.window.space_highlight_controller")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
local CanvasSpace = require("utils.canvas_space")

local HOVER_OPACITY = 0.4
local SELECTION_RECT_ANIM = {
  stepPx = 1,
  intervalSeconds = 0.1,
}

local function isChr8x16SelectionMode(win)
  return WindowCaps.isChrLike(win) and win.orderMode == "oddEven"
end

local function getChr8x16TopRow(row)
  row = math.floor(tonumber(row) or 0)
  return row - (row % 2)
end

local function getSelectionTileRef(win, layer, col, row, layerIndex)
  local cols = win.cols or 1
  local idx = (row * cols) + col + 1
  local item = layer.items and layer.items[idx] or nil
  if item ~= nil then
    return item
  end
  if win.getVirtualTileHandle then
    item = win:getVirtualTileHandle(col, row, layerIndex)
    if item ~= nil then
      return item
    end
  end
  if win.get then
    return win:get(col, row, layerIndex)
  end
  return nil
end

return function(Window)
local function spriteScreenRect(self, sprite, ctx)
  if not sprite then return nil end
  local mode   = ctx.mode
  local z      = ctx.z
  local cw     = ctx.cw
  local ch     = ctx.ch
  local scol   = ctx.scol
  local srow   = ctx.srow
  local originX = ctx.originX
  local originY = ctx.originY
  local NES_W   = ctx.NES_W
  local NES_H   = ctx.NES_H

  local spriteH = (mode == "8x16") and (2 * ch) or ch
  local worldX = sprite.worldX or sprite.baseX or sprite.x or 0
  local worldY = sprite.worldY or sprite.baseY or sprite.y or 0

  local drawX = (originX + worldX) % NES_W
  local drawY = (originY + worldY) % NES_H

  local screenX = self.x + ((drawX - scol * cw) * z)
  local screenY = self.y + ((drawY - srow * ch) * z)

  return screenX, screenY, cw * z, spriteH * z
end

local function drawSelectionRectAnimated(x, y, w, h)
  Draw.drawRepeatingImageAnimated(images.pattern_a, math.floor(x), math.floor(y), w, h, SELECTION_RECT_ANIM)
end

local function spriteOverlayKey(sprite, overlayCtx)
  if not sprite then return nil end
  local worldX = sprite.worldX or sprite.baseX or sprite.x or 0
  local worldY = sprite.worldY or sprite.baseY or sprite.y or 0
  local drawX = (overlayCtx.originX + worldX) % overlayCtx.NES_W
  local drawY = (overlayCtx.originY + worldY) % overlayCtx.NES_H
  return tostring(drawX) .. ":" .. tostring(drawY)
end

function Window:collectOverlappingSpriteKeys(L, overlayCtx)
  local counts = {}
  local reps = {}
  for _, sprite in ipairs(L.items or {}) do
    if sprite and sprite.removed ~= true then
      local key = spriteOverlayKey(sprite, overlayCtx)
      if key then
        counts[key] = (counts[key] or 0) + 1
        reps[key] = reps[key] or sprite
      end
    end
  end

  local keys = {}
  local sprites = {}
  for key, count in pairs(counts) do
    if count >= 2 then
      keys[key] = true
      sprites[key] = reps[key]
    end
  end
  return keys, sprites
end

local function setOverlayColor(color, alpha)
  local c = color or colors.white
  love.graphics.setColor(c[1], c[2], c[3], alpha or 1.0)
end

local function hoverBlockedByResizeHandle(wm, mouse)
  if not (wm and mouse and wm.focusedResizeHandleAt) then
    return false
  end
  return wm:focusedResizeHandleAt(mouse.x, mouse.y) == true
end

local function hoverBlockedByAppChrome(ctx, mouse)
  if not (ctx and mouse) then
    return false
  end
  local app = ctx.app
  if not app then
    return false
  end

  local topToolbarBottomY = AppTopToolbarController.getContentOffsetY(app)
  if type(topToolbarBottomY) == "number" and mouse.y < topToolbarBottomY then
    return true
  end

  local taskbar = app.taskbar
  if taskbar then
    local taskbarTopY = nil
    if type(taskbar.getTopY) == "function" then
      taskbarTopY = taskbar:getTopY()
    else
      taskbarTopY = taskbar.y
    end
    if type(taskbarTopY) == "number" and mouse.y >= taskbarTopY then
      return true
    end
  end

  return false
end

function Window:highlightOverlappingSprites(overlayCtx, overlappingSpritesByKey)
  for _, sprite in pairs(overlappingSpritesByKey or {}) do
    local sx, sy, sw, sh = spriteScreenRect(self, sprite, overlayCtx)
    if sx then
      love.graphics.setColor(colors.yellow)
      drawSelectionRectAnimated(sx, sy, sw, sh)
    end
  end
  love.graphics.setColor(colors.white)
end

function Window:highlightSelectedSprite(L, overlayCtx, overlappingKeys, spaceHighlightModel)
  if not (L and L.kind == "sprite") then return end
  
  local indices = SpriteController.getSelectedSpriteIndices(L)
  for _, idx in ipairs(indices) do
    local sprite = L.items[idx]
    if sprite and not sprite.removed then
      local key = spriteOverlayKey(sprite, overlayCtx)
      if overlappingKeys and key and overlappingKeys[key] then
        goto continue
      end
      local sx, sy, sw, sh = spriteScreenRect(self, sprite, overlayCtx)
      if sx then
        setOverlayColor(SpaceHighlightController.resolveMappedOverlayColor(self, sprite, spaceHighlightModel) or colors.white)
        drawSelectionRectAnimated(sx, sy, sw, sh)
      end
    end
    ::continue::
  end
end

function Window:highlightAllSprites(L, overlayCtx, opts)
  if not (L and L.kind == "sprite") then return end
  opts = opts or {}

  local selectedSet
  if opts.skipSelected then
    selectedSet = {}
    for _, idx in ipairs(SpriteController.getSelectedSpriteIndices(L)) do
      selectedSet[idx] = true
    end
  end

  for idx, sprite in ipairs(L.items or {}) do
    if sprite and sprite.removed ~= true then
      if selectedSet and selectedSet[idx] then
        goto continue
      end
      local key = spriteOverlayKey(sprite, overlayCtx)
      if opts.overlappingKeys and key and opts.overlappingKeys[key] then
        goto continue
      end
      local sx, sy, sw, sh = spriteScreenRect(self, sprite, overlayCtx)
      if sx then
        local color = colors.white
        if opts.resolveColor then
          color = opts.resolveColor(sprite, idx)
        end
        if color == nil then
          goto continue
        end
        setOverlayColor(color)
        drawSelectionRectAnimated(sx, sy, sw, sh)
      end
    end
    ::continue::
  end
end

function Window:highlightHoveredSprite(L, overlayCtx, overlappingKeys, spaceHighlightModel)
  if not (L and L.kind == "sprite" and L.hoverSpriteIndex) then return end

  local sprite = L.items[L.hoverSpriteIndex]
  if not sprite or sprite.removed == true then return end
  local key = spriteOverlayKey(sprite, overlayCtx)
  if overlappingKeys and key and overlappingKeys[key] then return end

  local sx, sy, sw, sh = spriteScreenRect(self, sprite, overlayCtx)
  if not sx then return end

  local c = SpaceHighlightController.resolveMappedOverlayColor(self, sprite, spaceHighlightModel) or colors.white
  setOverlayColor(c, HOVER_OPACITY)
  -- love.graphics.rectangle("line", math.floor(sx), math.floor(sy), sw + 1, sh + 1)
  drawSelectionRectAnimated(sx, sy, sw, sh)
  love.graphics.setColor(colors.white)
end

function Window:drawSpriteSelectionOverlays(isFocused)
  local ctx = _G.ctx
  if not (ctx and ctx.getMode and (ctx.getMode() == "tile" or ctx.getMode() == "edit")) then return end
  local mouse = ctx.scaledMouse and ctx.scaledMouse() or nil
  local wm = ctx.wm and ctx.wm()
  local hoverBlocked = hoverBlockedByResizeHandle(wm, mouse)
    or hoverBlockedByAppChrome(ctx, mouse)
  local hoveredWindow = (wm and mouse) and wm:windowAt(mouse.x, mouse.y) or nil
  local shouldShow = isFocused or ((not hoverBlocked) and hoveredWindow == self)
  if not shouldShow then return end
  local modeName = ctx.getMode and ctx.getMode()

  local L = self.layers and self.layers[self.activeLayer or 1]
  if not (L and L.kind == "sprite") then return end


  local z = (self.getZoomLevel and self:getZoomLevel()) or self.zoom or 1
  local cw = self.cellW or 8
  local ch = self.cellH or 8
  local scol = self.scrollCol or 0
  local srow = self.scrollRow or 0
  local originX = L.originX or 0
  local originY = L.originY or 0
  local mode = L.mode or "8x8"

  local NES_W = SpriteController.SPRITE_X_RANGE
  local NES_H = SpriteController.SPRITE_Y_RANGE

  local overlayCtx = {
    z = z, cw = cw, ch = ch,
    scol = scol, srow = srow,
    originX = originX, originY = originY,
    mode = mode,
    NES_W = NES_W, NES_H = NES_H,
  }

  -- Keep drawing inside the window bounds
  local prevScissor = { love.graphics.getScissor() }
  local sx, sy, sw, sh = self:getScreenRect()
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)
  local spaceDown = SpaceHighlightController.isSpaceHighlightActive()
  local spaceHighlightModel = SpaceHighlightController.buildModel(nil, spaceDown)
  local suppressSelectedHighlights = (WindowCaps.isAnimationLike(self) and self.isPlaying == true)
  local overlappingKeys, overlappingSpritesByKey = self:collectOverlappingSpriteKeys(L, overlayCtx)

  if modeName ~= "edit" and not suppressSelectedHighlights then
    self:highlightSelectedSprite(L, overlayCtx, overlappingKeys, spaceHighlightModel)
  end
  if isFocused and self:canShowSpaceHighlight(L) and spaceDown then
    self:highlightAllSprites(L, overlayCtx, {
      -- In edit mode, Space should show all sprites, including selected ones.
      -- Also include selected sprites while animation is playing because
      -- selected overlays are intentionally suppressed in that state.
      skipSelected = (modeName ~= "edit") and (not suppressSelectedHighlights),
      overlappingKeys = overlappingKeys,
      resolveColor = function(sprite)
        return SpaceHighlightController.resolveMappedOverlayColor(self, sprite, spaceHighlightModel) or colors.white
      end,
    })
  end
  if not hoverBlocked then
    self:highlightHoveredSprite(L, overlayCtx, overlappingKeys, spaceHighlightModel)
  end
  self:highlightOverlappingSprites(overlayCtx, overlappingSpritesByKey)

  if prevScissor[1] then
    love.graphics.setScissor(prevScissor[1], prevScissor[2], prevScissor[3], prevScissor[4])
  else
    love.graphics.setScissor()
  end
  love.graphics.setColor(colors.white)
end

local function tileScreenRect(self, col, row, ctx)
  local z   = ctx.z
  local cw  = ctx.cw
  local ch  = ctx.ch
  local scol = ctx.scol
  local srow = ctx.srow

  local screenX = self.x + ((col - scol) * cw) * z
  local screenY = self.y + ((row - srow) * ch) * z
  return screenX, screenY, cw * z, ch * z
end

local function getTileSelectionRect(self, col, row, ctx)
  local topRow = row
  local rowSpan = 1
  if isChr8x16SelectionMode(self) then
    topRow = getChr8x16TopRow(row)
    rowSpan = math.min(2, math.max(1, (self.rows or 0) - topRow))
  end

  local screenX, screenY, screenW, screenH = tileScreenRect(self, col, topRow, ctx)
  return screenX, screenY, screenW, screenH * rowSpan, topRow
end

function Window:highlightAllTiles(L, overlayCtx, opts)
  if not (L and L.kind ~= "sprite") then return end
  opts = opts or {}

  local cols = self.cols or 0
  local rows = self.rows or 0
  local removedCells = (WindowCaps.isPpuFrame(self) and L.kind == "tile") and nil or L.removedCells
  local layerIndex = self.activeLayer or 1
  local drawnKeys = {}

  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local i = row * cols + col + 1
      local item = getSelectionTileRef(self, L, col, row, layerIndex)
      if item ~= nil and not (removedCells and removedCells[i]) then
        local rx, ry, rw, rh, topRow = getTileSelectionRect(self, col, row, overlayCtx)
        local drawKey = string.format("%d:%d", col, topRow or row)
        if drawnKeys[drawKey] then
          goto continue
        end
        drawnKeys[drawKey] = true
        local color = colors.white
        if opts.resolveColor then
          color = opts.resolveColor(item, i, col, row)
        end
        if color == nil then
          goto continue
        end
        setOverlayColor(color)
        drawSelectionRectAnimated(rx, ry, rw, rh)
      end
      ::continue::
    end
  end
end

function Window:canShowSpaceHighlight(layer)
  if WindowCaps.isAnyPaletteWindow(self) then
    return false
  end

  if WindowCaps.isChrLike(self) then
    return false
  end

  if WindowCaps.isPpuFrame(self) and layer and layer.kind ~= "sprite" then
    return false
  end

  return true
end

function Window:drawTileSelectionOverlays(isFocused)
  local ctx = _G.ctx
  if not (ctx and ctx.getMode and (ctx.getMode() == "tile" or ctx.getMode() == "edit")) then return end
  local mode = ctx.getMode and ctx.getMode()
  local mouse = ctx.scaledMouse and ctx.scaledMouse() or nil
  local wm = ctx.wm and ctx.wm()
  local hoverBlocked = hoverBlockedByResizeHandle(wm, mouse)
    or hoverBlockedByAppChrome(ctx, mouse)
  local hoveredWindow = (wm and mouse) and wm:windowAt(mouse.x, mouse.y) or nil
  local showHover = ((not hoverBlocked) and hoveredWindow == self)

  local L = self.layers and self.layers[self.activeLayer or 1]
  if not (L and L.kind ~= "sprite") then return end

  local z = (self.getZoomLevel and self:getZoomLevel()) or self.zoom or 1
  local cw = self.cellW or 8
  local ch = self.cellH or 8
  local scol = self.scrollCol or 0
  local srow = self.scrollRow or 0

  local overlayCtx = { z = z, cw = cw, ch = ch, scol = scol, srow = srow }

  local prevScissor = { love.graphics.getScissor() }
  local sx, sy, sw, sh = self:getScreenRect()
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)
  local suppressSelectedHighlights = (WindowCaps.isAnimationLike(self) and self.isPlaying == true)
  local spaceDown = SpaceHighlightController.isSpaceHighlightActive()
  local spaceHighlightModel = SpaceHighlightController.buildModel(nil, spaceDown)
  local selectionHighlightModel = SpaceHighlightController.buildSelectionModel()
  local showFocusedSpaceHighlight = (
    spaceDown
    and spaceHighlightModel
    and self == spaceHighlightModel.focusedWindow
    and self:canShowSpaceHighlight(L)
  )
  local showBankWindowMappedHighlight = (
      SpaceHighlightController.shouldShowMappedHighlightInWindow(self, spaceHighlightModel)
    ) or (
      selectionHighlightModel
      and self == selectionHighlightModel.bankWindow
      and SpaceHighlightController.hasMatchedKeys(selectionHighlightModel)
    )

  -- Selected cell
  if not suppressSelectedHighlights then
    if mode ~= "edit" and L.multiTileSelection then
      local drawnKeys = {}
      for idx, on in pairs(L.multiTileSelection) do
        if on then
          local zeroBased = idx - 1
          local col = zeroBased % (self.cols or 1)
          local row = math.floor(zeroBased / (self.cols or 1))
          local rx, ry, rw, rh, topRow = getTileSelectionRect(self, col, row, overlayCtx)
          local drawKey = string.format("%d:%d", col, topRow)
          if not drawnKeys[drawKey] then
            drawnKeys[drawKey] = true
            setOverlayColor(colors.white)
            drawSelectionRectAnimated(rx, ry, rw, rh)
          end
        end
      end
    else
      local sel = self:getLayerSelection(self.activeLayer or 1)
      if mode ~= "edit" and sel and type(sel.col) == "number" and type(sel.row) == "number" then
        local rx, ry, rw, rh, topRow = getTileSelectionRect(self, sel.col, sel.row, overlayCtx)
        setOverlayColor(colors.white)
        -- love.graphics.rectangle("line", math.floor(rx), math.floor(ry), rw + 1, rh + 1)
        drawSelectionRectAnimated(rx, ry, rw, rh)
      end
    end
  end

  if showFocusedSpaceHighlight then
    self:highlightAllTiles(L, overlayCtx, {
      resolveColor = function(item)
        return SpaceHighlightController.resolveMappedOverlayColor(self, item, spaceHighlightModel) or colors.white
      end,
    })
  elseif showBankWindowMappedHighlight then
    self:highlightAllTiles(L, overlayCtx, {
      resolveColor = function(item)
        local color = SpaceHighlightController.resolveMappedOverlayColor(self, item, selectionHighlightModel)
        if color then
          return color
        end
        return SpaceHighlightController.resolveMappedOverlayColor(self, item, spaceHighlightModel)
      end,
    })
  end

  -- Hovered cell (when focused or under the pointer)
  if showHover and mouse then
    local ok, col, row = self:toGridCoords(mouse.x, mouse.y)
    if ok then
      local rx, ry, rw, rh, topRow = getTileSelectionRect(self, col, row, overlayCtx)
      setOverlayColor(colors.white, HOVER_OPACITY)
      -- love.graphics.rectangle("line", math.floor(rx), math.floor(ry), rw, rh)
      drawSelectionRectAnimated(rx, ry, rw, rh)
      love.graphics.setColor(colors.white)
    end
  end

  if prevScissor[1] then
    love.graphics.setScissor(prevScissor[1], prevScissor[2], prevScissor[3], prevScissor[4])
  else
    love.graphics.setScissor()
  end
  love.graphics.setColor(colors.white)
end

function Window:drawSelectionOverlays(isFocused)
  local L = self.layers and self.layers[self.activeLayer or 1]
  if not L then return end
  if L.kind == "sprite" then
    return self:drawSpriteSelectionOverlays(isFocused)
  else
    return self:drawTileSelectionOverlays(isFocused)
  end
end

end
