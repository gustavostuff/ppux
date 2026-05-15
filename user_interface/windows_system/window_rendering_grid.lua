local colors = require("app_colors")
local CanvasSpace = require("utils.canvas_space")
local SpriteLayerDraw = require("user_interface.windows_system.sprite_layer_draw")

return function(Window)

function Window:ensureCrtSpriteExportCanvas(app, layerIndex)
  return SpriteLayerDraw.rasterizeSpriteLayerForCrt(self, app, layerIndex)
end

function Window:drawLinesGrid()
  -- grid with horizontal and vertical lines
  love.graphics.push()
  local ox, oy = self:getContentScreenOrigin()
  love.graphics.translate(ox, oy)

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
  local ox, oy = self:getContentScreenOrigin()
  love.graphics.translate(ox, oy)
  local z = (self.getZoomLevel and self:getZoomLevel()) or self.zoom or 1
  love.graphics.scale(z, z)
  love.graphics.setLineWidth(1)
  love.graphics.setLineStyle("rough")

  local li = layerIndex or self.activeLayer or 1
  local grid = self.getDisplayGridMetrics and self:getDisplayGridMetrics(li) or {}
  local cw = grid.cellW or self.cellW or 8
  local ch = grid.cellH or self.cellH or 8
  local sx, sy, sw, sh = self:getInsetContentScreenRect()
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
  local L = self:getLayer(li)
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
  local ox, oy = self:getContentScreenOrigin()
  love.graphics.translate(ox, oy)
  local z = (self.getZoomLevel and self:getZoomLevel()) or self.zoom or 1
  love.graphics.scale(z, z)
  love.graphics.setLineWidth(1)
  love.graphics.setLineStyle("rough")

  local grid = self:getDisplayGridMetrics(li)
  local gcw = grid.cellW or self.cellW or 8
  local gch = grid.cellH or self.cellH or 8
  local cw = grid.baseCellW or grid.cellW or self.cellW or 8
  local ch = grid.baseCellH or grid.cellH or self.cellH or 8
  local sx, sy, sw, sh = self:getInsetContentScreenRect()
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)

  -- Apply scroll offset in world space (grid cell size may differ from base CHR pixel size)
  local scol = self.scrollCol or 0
  local srow = self.scrollRow or 0
  love.graphics.translate(-scol * gcw, -srow * gch)

  local isActiveLayer = (self.activeLayer == li)

  SpriteLayerDraw.drawSpriteOriginGuidesIfNeeded({
    windowKind = self.kind,
    showSpriteOriginGuides = self.showSpriteOriginGuides,
    layer = L,
    isActiveLayer = isActiveLayer,
  })

  local viewMinX = scol * gcw
  local viewMinY = srow * gch
  local viewMaxX = viewMinX + (self.visibleCols or self.cols or 0) * gcw
  local viewMaxY = viewMinY + (self.visibleRows or self.rows or 0) * gch

  SpriteLayerDraw.drawSpriteLayerInContentSpace({
    layer = L,
    romRaw = romRaw,
    cellW = cw,
    cellH = ch,
    viewMinX = viewMinX,
    viewMinY = viewMinY,
    viewMaxX = viewMaxX,
    viewMaxY = viewMaxY,
    windowKind = self.kind,
    isActiveLayer = isActiveLayer,
    spriteLayerIndex = li,
    renderSprite = renderSprite,
  })

  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.setColor(colors.white)
end

end
