local function install(Panel, utils)
  --- Inclusive hit test for a laid-out cell. When `_hitTestIncludeRowGaps`, vertical
  --- range claims half the spacingY gutter above/below so menu row gaps are not dead zones.
  local function pointInCellHit(panel, cell, px, py)
    if px < cell.x or px > (cell.x + cell.w) then
      return false
    end
    local top = cell.y
    local bottom = cell.y + cell.h
    if panel._hitTestIncludeRowGaps == true then
      local spacingY = tonumber(panel.spacingY) or 0
      if spacingY > 0 then
        local halfUp = math.floor(spacingY * 0.5)
        local halfDown = spacingY - halfUp
        local row = cell.row or 1
        local rowspan = cell.rowspan or 1
        local rows = panel.rows or 1
        if row > 1 then
          top = cell.y - halfUp
        end
        if (row + rowspan - 1) < rows then
          bottom = cell.y + cell.h + halfDown
        end
      end
    end
    return py >= top and py <= bottom
  end

  function Panel:_iterCells()
    local list = {}
    for row, rowCells in pairs(self.cells) do
      for col, cell in pairs(rowCells) do
        list[#list + 1] = cell
      end
    end
    table.sort(list, function(a, b)
      if a.row == b.row then
        return a.col < b.col
      end
      return a.row < b.row
    end)
    return list
  end

  function Panel:_rebuildOccupancy()
    self.occupancy = {}
    for _, cell in ipairs(self:_iterCells()) do
      for row = cell.row, (cell.row + cell.rowspan - 1) do
        self.occupancy[row] = self.occupancy[row] or {}
        for col = cell.col, (cell.col + cell.colspan - 1) do
          self.occupancy[row][col] = cell
        end
      end
    end
  end

  function Panel:_removeIntersectingCells(col, row, colspan, rowspan)
    local removals = {}
    for _, cell in ipairs(self:_iterCells()) do
      if utils.rectsIntersect(col, row, colspan, rowspan, cell.col, cell.row, cell.colspan, cell.rowspan) then
        removals[#removals + 1] = cell
      end
    end

    for _, cell in ipairs(removals) do
      utils.clearFocusOnCell(cell)
      if self.focusedComponent and cell.component == self.focusedComponent then
        self.focusedComponent = nil
      end
      if self.pressedButton and cell.button == self.pressedButton then
        self.pressedButton = nil
      end
      if self.pressedComponent and cell.component == self.pressedComponent then
        self.pressedComponent = nil
      end
      if self.cells[cell.row] then
        self.cells[cell.row][cell.col] = nil
        if not next(self.cells[cell.row]) then
          self.cells[cell.row] = nil
        end
      end
    end
  end

  function Panel:setFocusedComponent(component)
    self.focusedComponent = component
    for _, cell in ipairs(self:_iterCells()) do
      if cell.button then
        cell.button.focused = (cell.button == component)
      end
      if cell.component and type(cell.component.setFocused) == "function" then
        cell.component:setFocused(cell.component == component)
      end
    end
  end

  function Panel:setCell(col, row, cell)
    if type(col) ~= "number" or type(row) ~= "number" then return end
    col = math.floor(col)
    row = math.floor(row)
    if col < 1 or col > self.cols or row < 1 or row > self.rows then return end
    if type(cell) ~= "table" then return end

    local colspan = utils.clampSpan(cell.colspan or cell.colSpan or 1, self.cols - col + 1)
    local rowspan = utils.clampSpan(cell.rowspan or cell.rowSpan or 1, self.rows - row + 1)

    self:_removeIntersectingCells(col, row, colspan, rowspan)
    self.cells[row] = self.cells[row] or {}

    local out = {
      col = col,
      row = row,
      colspan = colspan,
      rowspan = rowspan,
      kind = cell.kind or (cell.component and "component" or (cell.action and "button" or "label")),
      text = cell.text or "",
      action = cell.action,
      align = cell.align or "left",
      icon = cell.icon,
      enabled = cell.enabled ~= false,
      tooltip = cell.tooltip,
      transparent = cell.transparent == true,
      bgColor = cell.bgColor,
      bgAlpha = cell.bgAlpha,
      textColor = cell.textColor,
      marginX = cell.marginX,
      component = cell.component,
      draw = cell.draw,
    }

    if out.kind == "label" then
      out.text = utils.normalizeLabelText(out.text, cell.preserveTrailingColon)
    end

    if out.kind == "button" and not out.component then
      out.button = utils.createButtonForCell(self, cell)
    elseif out.kind ~= "label" and not out.component and type(cell.draw) == "function" then
      out.component = {
        draw = function(_, ...)
          return cell.draw(out, ...)
        end,
      }
    end

    self.cells[row][col] = out
    self:_rebuildOccupancy()
    self:updateLayout()
  end

  function Panel:getCell(col, row)
    local rowCells = self.occupancy[row]
    if not rowCells then return nil end
    return rowCells[col]
  end

  function Panel:getCellAt(px, py)
    if not self:contains(px, py) then return nil end
    local list = self:_iterCells()
    for idx = #list, 1, -1 do
      local cell = list[idx]
      if pointInCellHit(self, cell, px, py) then
        return cell
      end
    end
    return nil
  end

  function Panel:getButtonAt(px, py)
    local cell = self:getCellAt(px, py)
    if cell and cell.button and cell.button.enabled ~= false then
      if cell.button:contains(px, py) or self._hitTestIncludeRowGaps == true then
        return cell.button
      end
    end
    if cell and cell.component and cell.component.enabled ~= false and cell.component.action then
      if type(cell.component.contains) ~= "function" or cell.component:contains(px, py) then
        return cell.component
      end
    end
    return nil
  end

  --- True when (px,py) is over a disabled panel button (or embedded Button component).
  function Panel:isHoveringDisabledButtonAt(px, py)
    if not self.visible or not self:contains(px, py) then
      return false
    end
    for _, cell in ipairs(self:_iterCells()) do
      if pointInCellHit(self, cell, px, py) then
        local b = cell.button
        if b and b.enabled == false then
          if b:contains(px, py) or self._hitTestIncludeRowGaps == true then
            return true
          end
        end
        local c = cell.component
        if c and utils.Button and getmetatable(c) == utils.Button and c.enabled == false then
          if type(c.contains) ~= "function" or c:contains(px, py) then
            return true
          end
        end
      end
    end
    return false
  end

  function Panel:getTooltipAt(px, py)
    local btn = self:getButtonAt(px, py)
    if not btn or not btn.tooltip or btn.tooltip == "" then
      return nil
    end

    return {
      text = btn.tooltip,
      immediate = (btn.tooltipImmediate == true),
      key = btn,
    }
  end

  function Panel:getComponentAt(px, py)
    local cell = self:getCellAt(px, py)
    if not cell then return nil end
    if cell.button and cell.button.enabled ~= false then
      return cell.button
    end
    if cell.component then
      if type(cell.component.contains) == "function" then
        if cell.component:contains(px, py) then
          return cell.component
        end
        return nil
      end
      return cell.component
    end
    return nil
  end
end

return {
  install = install,
}
