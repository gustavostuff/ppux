local Button = require("user_interface.button")
local colors = require("app_colors")
local Text = require("utils.text_utils")
local UiScale = require("user_interface.ui_scale")

local Cells = require("user_interface.panel.cells")
local Layout = require("user_interface.panel.layout")
local Input = require("user_interface.panel.input")
local Rendering = require("user_interface.panel.rendering")

local Panel = {}
Panel.__index = Panel
Panel.DEFAULT_CELL_W = 96
Panel.DEFAULT_CELL_H = UiScale.menuCellSize()

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
    enabled = cell.enabled ~= false,
    transparent = cell.transparent == true,
    bgColor = cell.bgColor,
    bgAlpha = cell.bgAlpha,
  })
end

local shared = {
  Button = Button,
  colors = colors,
  Text = Text,
  getFont = getFont,
  clampSpan = clampSpan,
  rectsIntersect = rectsIntersect,
  callIfPresent = callIfPresent,
  applyGeometry = applyGeometry,
  isTextFieldComponent = isTextFieldComponent,
  normalizeLabelText = normalizeLabelText,
  clearFocusOnCell = clearFocusOnCell,
  createButtonForCell = createButtonForCell,
}

function Panel.new(opts)
  opts = opts or {}
  local resolvedCellH = opts.cellH or Panel.DEFAULT_CELL_H
  local self = setmetatable({
    x = opts.x or 0,
    y = opts.y or 0,
    cols = math.max(1, opts.cols or 1),
    rows = math.max(1, opts.rows or 1),
    cellW = opts.cellW or Panel.DEFAULT_CELL_W,
    cellH = resolvedCellH,
    padding = opts.padding or 2,
    spacingX = opts.spacingX or 1,
    spacingY = opts.spacingY or 1,
    cellPaddingX = opts.cellPaddingX or 2,
    cellPaddingY = opts.cellPaddingY or 2,
    visible = opts.visible == true,
    title = opts.title,
    titleH = opts.title and (opts.titleH or resolvedCellH) or 0,
    bgCornerRadius = tonumber(opts.bgCornerRadius) or 0,
    titleCornerRadius = tonumber(opts.titleCornerRadius) or 0,
    bgColor = opts.bgColor or colors.gray20,
    titleBgColor = opts.titleBgColor or opts.bgColor or colors.gray20,
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
  return self
end

function Panel:setDebugShowCells(v)
  self.debugShowCells = v == true
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

function Panel:contains(px, py)
  if not self.visible then return false end
  return px >= self.x and px <= (self.x + self.w) and py >= self.y and py <= (self.y + self.h)
end

Cells.install(Panel, shared)
Layout.install(Panel, shared)
Input.install(Panel, shared)
Rendering.install(Panel, shared)

return Panel
