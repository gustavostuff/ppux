local colors = require("app_colors")
local CanvasSpace = require("utils.canvas_space")
local SpriteController = require("controllers.sprite.sprite_controller")
local images = require("images")

return function(Window)
local function intersectsRange(startPos, size, minPos, maxPos)
  local a0 = startPos
  local a1 = startPos + size
  return a0 < maxPos and a1 > minPos
end

local function collectWrappedPositions(basePos, size, range, viewMin, viewMax)
  local positions = {}
  local seen = {}
  for _, candidate in ipairs({ basePos - range, basePos, basePos + range }) do
    if not seen[candidate] and intersectsRange(candidate, size, viewMin, viewMax) then
      positions[#positions + 1] = candidate
      seen[candidate] = true
    end
  end
  if #positions == 0 then
    positions[1] = basePos
  end
  table.sort(positions)
  return positions
end

local function drawDefaultSpriteBody(L, s, isActiveLayer, cw, ch, mode, layerOpacity, romRaw)
  local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
  local SpriteHydrationController = require("controllers.sprite.hydration_controller")

  local alpha = (L.opacity ~= nil) and L.opacity or layerOpacity or 1.0
  love.graphics.setColor(1.0, 1.0, 1.0, alpha)

  local layerOpacityOverride = (L and L.opacity ~= nil) and L.opacity or nil
  ShaderPaletteController.applyLayerItemPalette(
    L,
    s,
    isActiveLayer,
    romRaw,
    nil,
    layerOpacityOverride
  )

  local top = s.topRef
  if mode == "8x16" and (not top or not s.botRef) then
    local ctx = rawget(_G, "ctx")
    local app = ctx and ctx.app or nil
    local state = app and app.appEditState or nil
    if state and state.tilesPool then
      SpriteHydrationController.ensureTileRefsForSpriteItem(s, mode, state.tilesPool, state)
      top = s.topRef
    end
  end
  if not (top and top.draw) then
    ShaderPaletteController.releaseShader()
    return
  end
  local mirrorX = s.mirrorX or false
  local mirrorY = s.mirrorY or false
  local scaleX = mirrorX and -1 or 1
  local scaleY = mirrorY and -1 or 1

  love.graphics.push()
  local offsetX = mirrorX and cw or 0
  local offsetY = 0
  if mirrorY then
    offsetY = (mode == "8x16") and (2 * ch) or ch
  end
  if offsetX ~= 0 or offsetY ~= 0 then
    love.graphics.translate(offsetX, offsetY)
  end

  if mode == "8x16" and mirrorY then
    if s.botRef and s.botRef.draw then
      s.botRef:draw(0, -ch, scaleX, scaleY)
    end
    top:draw(0, 0, scaleX, scaleY)
  else
    top:draw(0, 0, scaleX, scaleY)
    if mode == "8x16" and s.botRef and s.botRef.draw then
      s.botRef:draw(0, ch, scaleX, scaleY)
    end
  end

  love.graphics.pop()
  ShaderPaletteController.releaseShader()
end

local function drawConcatenatedDottedGuides(axisX, axisY)
  local dotted = images and images.dotted_line or nil
  if not dotted then
    return false
  end

  -- `img/dotted_line.png` is 32x1. Draw 8 segments => 256px guide.
  -- Horizontal
  for i = 0, 7 do
    love.graphics.draw(dotted, i * 32, axisY)
  end

  -- Vertical (rotated 90 degrees)
  for i = 0, 7 do
    love.graphics.draw(dotted, axisX, i * 32, math.pi * 0.5, 1, 1)
  end

  return true
end

function Window:drawLinesGrid()
  -- grid with horizontal and vertical lines
  love.graphics.push()
  love.graphics.translate(self.x, self.y)

  love.graphics.setColor(colors.black)
  -- vertical lines
  for row = 1, self.visibleRows - 1 do
    local x0, y0 = 0, row * self.cellH
    local x1, y1 = self.visibleCols * self.cellW, row * self.cellH
    love.graphics.line(x0 * self.zoom, y0 * self.zoom, x1 * self.zoom, y1 * self.zoom)
  end
  -- horizontal lines
  for col = 1, self.visibleCols - 1 do
    local x0, y0 = col * self.cellW, 0
    local x1, y1 = col * self.cellW, self.visibleRows * self.cellH
    love.graphics.line(x0 * self.zoom, y0 * self.zoom, x1 * self.zoom, y1 * self.zoom)
  end

  love.graphics.pop()
end

-- ==== DRAW ====
function Window:drawGrid(renderCell, isFocused, layerIndex)
  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.scale(self.zoom, self.zoom)
  love.graphics.setLineWidth(1)
  love.graphics.setLineStyle("rough")

  local cw, ch = self.cellW, self.cellH
  local sx, sy, sw, sh = self:getScreenRect()
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)

  -- Apply scroll offset in world space
  love.graphics.translate(-self.scrollCol * cw, -self.scrollRow * ch)

  -- Visible area
  local vC0 = self.scrollCol
  local vR0 = self.scrollRow
  local vC1 = math.min(self.cols - 1, vC0 + self.visibleCols - 1)
  local vR1 = math.min(self.rows - 1, vR0 + self.visibleRows - 1)

  -- Spill ring: 1 tile beyond visible area on each side
  local spill = 1
  local c0 = math.max(0, vC0 - spill)
  local r0 = math.max(0, vR0 - spill)
  local c1 = math.min(self.cols - 1, vC1 + spill)
  local r1 = math.min(self.rows - 1, vR1 + spill)

  local activeLayerIndex = self.activeLayer or 1
  local ctx = _G.ctx
  -- Decide which layer to render: default to activeLayer if none specified
  local li = layerIndex or activeLayerIndex
  local L  = self:getLayer(li)
  local isActiveLayer = (li == activeLayerIndex)

  if L then
    local la = (L.opacity ~= nil) and L.opacity or 1.0

    for row = r0, r1 do
      for col = c0, c1 do
        local x, y = col * cw, row * ch
        renderCell(col, row, x, y, cw - 1, ch - 1, li, la)
      end
    end
  end

  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.setColor(colors.white)
end

function Window:drawSprites(renderSprite, isFocused, layerIndex, romRaw)
  -- Similar structure to drawGrid but for sprite layers
  if not self.layers then return end

  local li = layerIndex or self.activeLayer or 1
  local L = self:getLayer(li)
  if not (L and L.kind == "sprite") then return end

  local items = L.items
  if not (items and #items > 0) then return end

  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  local z = (self.getZoomLevel and self:getZoomLevel()) or self.zoom or 1
  love.graphics.scale(z, z)
  love.graphics.setLineWidth(1)
  love.graphics.setLineStyle("rough")

  local cw = self.cellW or 8
  local ch = self.cellH or 8
  local sx, sy, sw, sh = self:getScreenRect()
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)

  -- Apply scroll offset in world space
  local scol = self.scrollCol or 0
  local srow = self.scrollRow or 0
  love.graphics.translate(-scol * cw, -srow * ch)

  local originX = L.originX or 0
  local originY = L.originY or 0
  local mode = L.mode or "8x8"
  local spriteW = cw
  local spriteH = (mode == "8x16") and (2 * ch) or ch

  local NES_W = SpriteController.SPRITE_X_RANGE
  local NES_H = SpriteController.SPRITE_Y_RANGE

  local isActiveLayer = (self.activeLayer == li)
  local layerOpacity = (L.opacity ~= nil) and L.opacity or 1.0
  local ctx = _G.ctx
  local viewMinX = scol * cw
  local viewMinY = srow * ch
  local viewMaxX = viewMinX + (self.visibleCols or self.cols or 0) * cw
  local viewMaxY = viewMinY + (self.visibleRows or self.rows or 0) * ch
  local wrapPreview = (self.kind == "oam_animation")

  if (self.kind == "ppu_frame" or self.kind == "oam_animation")
    and isActiveLayer
    and self.showSpriteOriginGuides == true
  then
    local axisX = originX
    local axisY = originY
    love.graphics.setColor(colors.gray75[1], colors.gray75[2], colors.gray75[3], 0.85)
    if not drawConcatenatedDottedGuides(axisX, axisY) then
      -- Fallback line if the dotted image is unavailable.
      love.graphics.line(0, axisY, 256, axisY)
      love.graphics.line(axisX, 0, axisX, 256)
    end
    love.graphics.setColor(colors.white)
  end

  -- Draw sprites
  for idx, s in ipairs(items) do
    -- Skip removed sprites
    if s.removed == true then
      goto continue
    end
    local top = s.topRef
    if top and top.draw then
      local worldX = s.worldX or s.baseX or s.x or 0
      local worldY = s.worldY or s.baseY or s.y or 0

      local drawX = (originX + worldX) % NES_W
      local drawY = (originY + worldY) % NES_H

      local drawXs = wrapPreview
        and collectWrappedPositions(drawX, spriteW, NES_W, viewMinX, viewMaxX)
        or { drawX }
      local drawYs = wrapPreview
        and collectWrappedPositions(drawY, spriteH, NES_H, viewMinY, viewMaxY)
        or { drawY }

      for _, screenY in ipairs(drawYs) do
        for _, screenX in ipairs(drawXs) do
          love.graphics.push()
          love.graphics.translate(screenX, screenY)

          if renderSprite then
            renderSprite(L, s, isActiveLayer, ch, mode, idx, spriteW, spriteH, layerOpacity, romRaw)
          else
            drawDefaultSpriteBody(L, s, isActiveLayer, cw, ch, mode, layerOpacity, romRaw)
          end

          love.graphics.pop()
        end
      end
    end
    ::continue::
  end

  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.setColor(colors.white)
end

end
