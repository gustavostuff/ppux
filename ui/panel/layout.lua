local function install(Panel, utils)
  --- Pixel-aligned outer rect for floating menus (fractional rects make LOVE rounded quads tessellate corners unevenly).
  --- When `chromeEnvelopeRectPx` reports didSnap, use its x,y,w,h for menu fill, separators, outline, and shadow masks.
  function Panel:chromeEnvelopeRectPx()
    if self.menuOutline ~= true and self.menuRowSeparators ~= true then
      return tonumber(self.x) or 0, tonumber(self.y) or 0, tonumber(self.w) or 0, tonumber(self.h) or 0, false
    end

    local x = tonumber(self.x) or 0
    local y = tonumber(self.y) or 0
    local w = tonumber(self.w) or 0
    local h = tonumber(self.h) or 0
    if w <= 0 or h <= 0 then
      return x, y, math.max(0, w), math.max(0, h), true
    end

    local ix = math.floor(x + 1e-4)
    local iy = math.floor(y + 1e-4)
    local iw = math.max(1, math.ceil(x + w - 1e-4) - ix)
    local ih = math.max(1, math.ceil(y + h - 1e-4) - iy)

    return ix, iy, iw, ih, true
  end

  function Panel:updateLayout()
    local gridW = 0
    if type(self.cellWidths) == "table" and next(self.cellWidths) ~= nil then
      for col = 1, self.cols do
        gridW = gridW + (tonumber(self.cellWidths[col]) or self.cellW)
      end
    else
      gridW = self.cols * self.cellW
    end
    gridW = gridW + math.max(0, self.cols - 1) * self.spacingX
    local titleRowH = (self.title and self.title ~= "") and (self.titleH > 0 and self.titleH or self.cellH) or 0
    local titleSpacing = (titleRowH > 0 and self.rows > 0) and self.spacingY or 0
    local gridH = self.rows * self.cellH + math.max(0, self.rows - 1) * self.spacingY
    self.w = self.padding * 2 + gridW
    self.h = self.padding * 2 + titleRowH + titleSpacing + gridH

    for _, cell in ipairs(self:_iterCells()) do
      local x = self.x + self.padding
      if type(self.cellWidths) == "table" and next(self.cellWidths) ~= nil then
        for col = 1, (cell.col - 1) do
          x = x + (tonumber(self.cellWidths[col]) or self.cellW) + self.spacingX
        end
      else
        x = x + (cell.col - 1) * (self.cellW + self.spacingX)
      end
      local y = self.y + self.padding + titleRowH + titleSpacing + (cell.row - 1) * (self.cellH + self.spacingY)
      local w = 0
      if type(self.cellWidths) == "table" and next(self.cellWidths) ~= nil then
        for col = cell.col, (cell.col + cell.colspan - 1) do
          w = w + (tonumber(self.cellWidths[col]) or self.cellW)
        end
      else
        w = cell.colspan * self.cellW
      end
      w = w + math.max(0, cell.colspan - 1) * self.spacingX
      local h = (cell.rowspan * self.cellH) + math.max(0, cell.rowspan - 1) * self.spacingY
      cell.x = x
      cell.y = y
      cell.w = w
      cell.h = h
      if cell.button then
        utils.applyGeometry(cell.button, x, y, w, h)
      end
      if cell.component then
        local componentX = x
        local componentW = w
        if utils.isTextFieldComponent(cell.component) then
          -- reserved for text-field specific margins if needed later
        end
        utils.applyGeometry(cell.component, componentX, y, componentW, h)
      end
    end
  end

  function Panel:setPosition(x, y)
    self.x = x or self.x
    self.y = y or self.y
    self:updateLayout()
  end
end

return {
  install = install,
}
