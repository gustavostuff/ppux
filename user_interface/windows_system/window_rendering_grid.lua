local colors = require("app_colors")
local SpriteController = require("controllers.sprite.sprite_controller")

return function(Window)
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
  love.graphics.setScissor(sx, sy, sw, sh)

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
  love.graphics.setScissor(sx, sy, sw, sh)

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

      -- Sprite positions are in absolute world coordinates
      -- The scroll offset is already applied via the graphics transformation above,
      -- so we don't subtract it from the sprite positions
      local screenX = drawX
      local screenY = drawY

      love.graphics.push()
      love.graphics.translate(screenX, screenY)

      if renderSprite then
        renderSprite(L, s, isActiveLayer, ch, mode, idx, spriteW, spriteH, layerOpacity, romRaw)
      else
        -- Default drawing if no callback - apply palette and draw
        local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
        
        -- Apply layer opacity to the color (alpha component)
        local alpha = (L.opacity ~= nil) and L.opacity or layerOpacity or 1.0
        love.graphics.setColor(1.0, 1.0, 1.0, alpha)
        
        -- Pass the layer's actual opacity to the palette shader
        local layerOpacityOverride = (L and L.opacity ~= nil) and L.opacity or nil
        
        ShaderPaletteController.applyLayerItemPalette(
          L,
          s,
          isActiveLayer,
          romRaw,
          nil,  -- paletteNumberOverride
          layerOpacityOverride
        )
        
        -- Apply mirroring: negative scale for X and/or Y
        local mirrorX = s.mirrorX or false
        local mirrorY = s.mirrorY or false
        local scaleX = mirrorX and -1 or 1
        local scaleY = mirrorY and -1 or 1
        
        -- Apply transform for mirroring
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
          -- For vertical mirroring in 8x16, swap top and bottom tiles
          -- Bottom tile goes on top (draw at negative offset)
          if s.botRef and s.botRef.draw then
            s.botRef:draw(0, -ch, scaleX, scaleY)
          end
          -- Top tile goes on bottom (draw at 0)
          top:draw(0, 0, scaleX, scaleY)
        else
          -- Normal drawing (or horizontal mirror only)
          top:draw(0, 0, scaleX, scaleY)
          if mode == "8x16" and s.botRef and s.botRef.draw then
            s.botRef:draw(0, ch, scaleX, scaleY)
          end
        end
        
        love.graphics.pop()
        
        ShaderPaletteController.releaseShader()
      end

      love.graphics.pop()
    end
    ::continue::
  end

  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.setColor(colors.white)
end

end
