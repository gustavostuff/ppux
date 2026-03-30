local Button = require("user_interface.button")
local colors = require("app_colors")
local Text = require("utils.text_utils")

local Panel = {}
Panel.__index = Panel
Panel.DEFAULT_CELL_W = 96
Panel.DEFAULT_CELL_H = 16

local function getFont()
  return love.graphics.getFont()
end

local function clampSpan(value, maxValue)
  local n = math.floor(tonumber(value) or 1)
  if n < 1 then n = 1 end
  if maxValue and n > maxValue then n = maxValue end
  return n
end

local function rectsIntersect(aCol, aRow, aCols, aRows, bCol, bRow, bCols, bRows)
  local aRight = aCol + aCols - 1
  local aBottom = aRow + aRows - 1
  local bRight = bCol + bCols - 1
  local bBottom = bRow + bRows - 1

  return not (
    aRight < bCol or
    bRight < aCol or
    aBottom < bRow or
    bBottom < aRow
  )
end

local function callIfPresent(target, method, ...)
  if target and type(target[method]) == "function" then
    return target[method](target, ...)
  end
  return nil
end

local function applyGeometry(target, x, y, w, h)
  if not target then return end
  if type(target.setPosition) == "function" then
    target:setPosition(x, y)
  else
    target.x = x
    target.y = y
  end

  if type(target.setSize) == "function" then
    target:setSize(w, h)
  else
    target.w = w
    target.h = h
  end
end

local function isTextFieldComponent(target)
  return target
    and type(target.getText) == "function"
    and type(target.setText) == "function"
    and type(target.onTextInput) == "function"
    and type(target.setFocused) == "function"
end

local function normalizeLabelText(text, preserveTrailingColon)
  text = tostring(text or "")
  if preserveTrailingColon == true then
    return text
  end
  return (text:gsub("%s*:%s*$", ""))
end

local function clearFocusOnCell(cell)
  if not cell then return end
  if cell.button then
    cell.button.focused = false
  end
  if cell.component and type(cell.component.setFocused) == "function" then
    cell.component:setFocused(false)
  end
end

local function createButtonForCell(panel, cell)
  return Button.new({
    icon = cell.icon,
    text = cell.text,
    action = cell.action,
    tooltip = cell.tooltip or cell.text,
    alwaysOpaqueContent = cell.alwaysOpaqueContent == true,
    textAlign = cell.textAlign or cell.align or "left",
    contentPaddingX = cell.contentPaddingX or 6,
    iconTextGap = cell.iconTextGap or 5,
    textOffsetY = cell.textOffsetY or (panel and panel.textOffsetY) or 0,
    enabled = cell.enabled ~= false,
    transparent = cell.transparent == true,
    bgColor = cell.bgColor,
    bgAlpha = cell.bgAlpha,
  })
end

function Panel.new(opts)
  opts = opts or {}
  local self = setmetatable({
    x = opts.x or 0,
    y = opts.y or 0,
    cols = math.max(1, opts.cols or 1),
    rows = math.max(1, opts.rows or 1),
    cellW = opts.cellW or Panel.DEFAULT_CELL_W,
    cellH = opts.cellH or Panel.DEFAULT_CELL_H,
    padding = opts.padding or 2,
    spacingX = opts.spacingX or 1,
    spacingY = opts.spacingY or 1,
    cellPaddingX = opts.cellPaddingX or 2,
    cellPaddingY = opts.cellPaddingY or 2,
    textOffsetY = opts.textOffsetY or 0,
    visible = opts.visible == true,
    title = opts.title,
    titleH = opts.title and (opts.titleH or 14) or 0,
    bgColor = opts.bgColor or colors.gray20,
    borderColor = opts.borderColor or colors.white,
    debugShowCells = opts.debugShowCells == true,
    debugCellColor = opts.debugCellColor or colors.gray10,
    debugCellAlpha = opts.debugCellAlpha or 0.35,
    cells = {},
    occupancy = {},
    pressedButton = nil,
    pressedComponent = nil,
    focusedComponent = nil,
  }, Panel)

  self:updateLayout()
  -- self:setDebugShowCells(true)
  return self
end

function Panel:setDebugShowCells(v)
  self.debugShowCells = v == true
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
    if rectsIntersect(col, row, colspan, rowspan, cell.col, cell.row, cell.colspan, cell.rowspan) then
      removals[#removals + 1] = cell
    end
  end

  for _, cell in ipairs(removals) do
    clearFocusOnCell(cell)
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

function Panel:setVisible(v)
  self.visible = v == true
  if not self.visible then
    self.pressedButton = nil
    self.pressedComponent = nil
    self.focusedComponent = nil
    for _, cell in ipairs(self:_iterCells()) do
      if cell.button then
        cell.button.hovered = false
        cell.button.pressed = false
        cell.button.focused = false
      end
      if cell.component and type(cell.component.setFocused) == "function" then
        cell.component:setFocused(false)
      end
    end
  end
end

function Panel:isVisible()
  return self.visible == true
end

function Panel:toggle()
  self:setVisible(not self.visible)
  return self.visible
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
      applyGeometry(cell.button, x, y, w, h)
    end
    if cell.component then
      local componentX = x
      local componentW = w
      if isTextFieldComponent(cell.component) then
        -- local marginX = 4
        -- componentX = x + marginX
        -- componentW = math.max(1, w - (marginX * 2))
      end
      applyGeometry(cell.component, componentX, y, componentW, h)
    end
  end
end

function Panel:setPosition(x, y)
  self.x = x or self.x
  self.y = y or self.y
  self:updateLayout()
end

function Panel:contains(px, py)
  if not self.visible then return false end
  return px >= self.x and px <= (self.x + self.w) and py >= self.y and py <= (self.y + self.h)
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

  local colspan = clampSpan(cell.colspan or cell.colSpan or 1, self.cols - col + 1)
  local rowspan = clampSpan(cell.rowspan or cell.rowSpan or 1, self.rows - row + 1)

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
    textOffsetY = cell.textOffsetY,
    component = cell.component,
    draw = cell.draw,
  }

  if out.kind == "label" then
    out.text = normalizeLabelText(out.text, cell.preserveTrailingColon)
  end

  if out.kind == "button" and not out.component then
    out.button = createButtonForCell(self, cell)
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
  for _, cell in ipairs(self:_iterCells()) do
    if px >= cell.x and px <= (cell.x + cell.w) and py >= cell.y and py <= (cell.y + cell.h) then
      return cell
    end
  end
  return nil
end

function Panel:getButtonAt(px, py)
  local cell = self:getCellAt(px, py)
  if cell and cell.button and cell.button.enabled ~= false and cell.button:contains(px, py) then
    return cell.button
  end
  if cell and cell.component and cell.component.enabled ~= false and cell.component.action then
    if type(cell.component.contains) ~= "function" or cell.component:contains(px, py) then
      return cell.component
    end
  end
  return nil
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

function Panel:mousepressed(x, y, button)
  if not self.visible then return false end
  if not self:contains(x, y) then return false end
  if button ~= 1 then return true end

  local target = self:getComponentAt(x, y)
  self.pressedButton = nil
  self.pressedComponent = nil

  if target then
    self:setFocusedComponent(target)
  else
    self:setFocusedComponent(nil)
  end

  if target and target.action then
    target.pressed = true
    self.pressedButton = target
    return true
  end

  if target then
    self.pressedComponent = target
    if callIfPresent(target, "mousepressed", x, y, button) ~= false then
      return true
    end
  end

  return true
end

function Panel:mousereleased(x, y, button)
  if not self.visible then return false end

  local consumed = false
  if button == 1 and self.pressedButton then
    consumed = true
    local pressedBtn = self.pressedButton
    local releasedBtn = self:getButtonAt(x, y)
    if releasedBtn == pressedBtn and pressedBtn.action then
      pressedBtn.action()
    end
  elseif button == 1 and self.pressedComponent then
    consumed = true
    callIfPresent(self.pressedComponent, "mousereleased", x, y, button)
  elseif self:contains(x, y) then
    consumed = true
  end

  for _, cell in ipairs(self:_iterCells()) do
    if cell.button then
      cell.button.pressed = false
    end
  end
  self.pressedButton = nil
  self.pressedComponent = nil

  return consumed
end

function Panel:mousemoved(x, y)
  if not self.visible then return end
  local hovered = self:getButtonAt(x, y)
  for _, cell in ipairs(self:_iterCells()) do
    if cell.button then
      cell.button.hovered = (cell.button == hovered)
    end
    if cell.component and type(cell.component.mousemoved) == "function" then
      cell.component:mousemoved(x, y)
    end
  end
end

function Panel:handleKey(key)
  if not self.visible then return false end
  if self.focusedComponent and type(self.focusedComponent.onKeyPressed) == "function" then
    return self.focusedComponent:onKeyPressed(key) == true
  end
  if self.focusedComponent and type(self.focusedComponent.handleKey) == "function" then
    return self.focusedComponent:handleKey(key) == true
  end
  return false
end

function Panel:textinput(text)
  if not self.visible then return false end
  if self.focusedComponent and type(self.focusedComponent.onTextInput) == "function" then
    return self.focusedComponent:onTextInput(text) == true
  end
  if self.focusedComponent and type(self.focusedComponent.textinput) == "function" then
    return self.focusedComponent:textinput(text) == true
  end
  return false
end

function Panel:draw()
  if not self.visible then return end

  local bg = self.bgColor
  love.graphics.setColor(bg[1], bg[2], bg[3], 1)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

  if self.title and self.title ~= "" then
    local titleRowH = (self.titleH > 0 and self.titleH or self.cellH)
    local font = love.graphics.getFont()
    local titleW = font and font:getWidth(self.title) or 0
    local titleX = self.x + math.floor((self.w - titleW) * 0.5)
    love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 1)
    local titleY = self.y + self.padding + math.floor((titleRowH - (font and font:getHeight() or 0)) * 0.5)
    Text.print(
      self.title,
      titleX,
      titleY,
      { shadowColor = colors.transparent }
    )
  end

  if self.debugShowCells then
    local debugColor = self.debugCellColor or colors.gray10
    local alpha = self.debugCellAlpha or 1
    local titleRowH = (self.title and self.title ~= "") and (self.titleH > 0 and self.titleH or self.cellH) or 0
    local titleSpacing = (titleRowH > 0 and self.rows > 0) and self.spacingY or 0
    local gridStartY = self.y + self.padding + titleRowH + titleSpacing

    love.graphics.setColor(debugColor[1], debugColor[2], debugColor[3], alpha)
    for row = 1, self.rows do
      local cellY = gridStartY + (row - 1) * (self.cellH + self.spacingY)
      for col = 1, self.cols do
        local cellX = self.x + self.padding + (col - 1) * (self.cellW + self.spacingX)
        love.graphics.rectangle("fill", cellX, cellY, self.cellW, self.cellH)
      end
    end
  end

  for _, cell in ipairs(self:_iterCells()) do
    if cell.button then
      cell.button:draw()
    elseif cell.component and type(cell.component.draw) == "function" then
      cell.component:draw()
    elseif cell.kind == "label" then
      local textColor = cell.textColor or colors.white
      love.graphics.setColor(textColor[1], textColor[2], textColor[3], 1)
      local font = getFont()
      local labelMarginX = math.floor(cell.h / 2)
      local textX = cell.x + labelMarginX
      local textY = cell.y + math.floor((cell.h - (font and font:getHeight() or 0)) * 0.5)
      textY = textY + (cell.textOffsetY or self.textOffsetY or 0)
      if cell.align == "center" then
        local textW = font and font:getWidth(cell.text or "") or 0
        textX = math.floor(cell.x + (cell.w - textW) * 0.5)
      end
      Text.print(cell.text or "", textX, textY, { shadowColor = colors.transparent })
    end
  end

  love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 1)
end

return Panel
