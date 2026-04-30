-- Standalone HSV color picker: 10×8 panel grid.
-- Col 1: brightness (value) for the current hue/saturation.
-- Col 2: non-interactive spacer.
-- Cols 3–10: hue × saturation matrix (hue left→right, saturation top→full / bottom→none).
local Panel = require("user_interface.panel")
local colors = require("app_colors")

local GRID_COLS = 10
local GRID_ROWS = 8
local MATRIX_COLS = 8
local MATRIX_FIRST_COL = 3
local BRIGHT_COL = 1
local SPACER_COL = 2

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

--- h, s, v in [0,1]. Returns r, g, b in [0,1].
local function hsvToRgb(h, s, v)
  h = h % 1
  if s <= 0 then
    return v, v, v
  end
  local hh = h * 6
  local i = math.floor(hh)
  local f = hh - i
  local p = v * (1 - s)
  local q = v * (1 - s * f)
  local t = v * (1 - s * (1 - f))
  i = i % 6
  if i == 0 then
    return v, t, p
  elseif i == 1 then
    return q, v, p
  elseif i == 2 then
    return p, v, t
  elseif i == 3 then
    return p, q, v
  elseif i == 4 then
    return t, p, v
  end
  return v, p, q
end

local function makeSpacerComponent()
  return {
    enabled = true,
    draw = function(self)
      love.graphics.setColor(0, 0, 0, 0.06)
      love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
      love.graphics.setColor(1, 1, 1, 0.12)
      love.graphics.rectangle("line", self.x, self.y, self.w, self.h)
    end,
    contains = function()
      return false
    end,
  }
end

local function makeSwatchComponent(getRgbFn, onPickReleased)
  local self = {
    enabled = true,
    x = 0,
    y = 0,
    w = 0,
    h = 0,
    getRgb = getRgbFn,
    draw = function(component)
      local r, g, b, a = component.getRgb()
      a = a or 1
      love.graphics.setColor(r, g, b, a)
      love.graphics.rectangle("fill", component.x, component.y, component.w, component.h)
      love.graphics.setColor(0, 0, 0, 0.35)
      love.graphics.rectangle("line", component.x, component.y, component.w, component.h)
    end,
    contains = function(component, px, py)
      return px >= component.x
        and px <= component.x + component.w
        and py >= component.y
        and py <= component.y + component.h
    end,
    mousepressed = function()
      return true
    end,
    mousereleased = function(component, px, py, button)
      if button ~= 1 then
        return
      end
      if component:contains(px, py) and onPickReleased then
        onPickReleased()
      end
    end,
  }
  return self
end

local ColorPickerMatrix = {}
ColorPickerMatrix.__index = ColorPickerMatrix

function ColorPickerMatrix.new(opts)
  opts = opts or {}
  local cellSize = tonumber(opts.cellSize) or 7
  local cellW = tonumber(opts.cellW) or cellSize
  local cellH = tonumber(opts.cellH) or cellSize
  local gapX = (opts.colGap ~= nil) and opts.colGap or (opts.gap ~= nil and opts.gap or 1)
  local gapY = (opts.rowGap ~= nil) and opts.rowGap or (opts.gap ~= nil and opts.gap or 1)
  local padding = (opts.padding ~= nil) and opts.padding or 2
  local bg = opts.bgColor or colors.gray10

  local self = setmetatable({
    visible = true,
    panel = nil,
    onChange = opts.onChange,
    _cellW = cellW,
    _cellH = cellH,
    _hueIndex = nil,
    _satRow = nil,
    _v = 1,
    _brightComponents = {},
  }, ColorPickerMatrix)

  local panel = Panel.new({
    cols = GRID_COLS,
    rows = GRID_ROWS,
    cellW = cellW,
    cellH = cellH,
    spacingX = gapX,
    spacingY = gapY,
    padding = padding,
    visible = true,
    bgColor = bg,
  })

  local function hueSatFromIndices(hueIndex, satRow)
    local h = (hueIndex - 1) / MATRIX_COLS
    local s = (GRID_ROWS - satRow) / (GRID_ROWS - 1)
    if GRID_ROWS == 1 then
      s = 1
    end
    return h, clamp01(s)
  end

  local function currentHueSat()
    if self._hueIndex and self._satRow then
      return hueSatFromIndices(self._hueIndex, self._satRow)
    end
    return 0, 0
  end

  local function brightnessVForRow(row)
    return (GRID_ROWS - row) / (GRID_ROWS - 1)
  end

  local function emitChange()
    local h, s = currentHueSat()
    local v = clamp01(self._v or 1)
    if not self._hueIndex then
      h, s, v = 0, 0, clamp01(self._v or 1)
    end
    local r, g, b = hsvToRgb(h, s, v)
    if self.onChange then
      self.onChange({
        r = r,
        g = g,
        b = b,
        a = 1,
        h = h,
        s = s,
        v = v,
      })
    end
  end

  function self:_refreshBrightnessSwatches()
    local h, s = currentHueSat()
    for row = 1, GRID_ROWS do
      local comp = self._brightComponents[row]
      if comp then
        local vv = brightnessVForRow(row)
        local r, g, b
        if self._hueIndex then
          r, g, b = hsvToRgb(h, s, vv)
        else
          r, g, b = vv, vv, vv
        end
        comp._rgb = { r, g, b, 1 }
        comp.getRgb = function()
          return comp._rgb[1], comp._rgb[2], comp._rgb[3], comp._rgb[4]
        end
      end
    end
  end

  function self:_pickBrightnessRow(row)
    self._v = brightnessVForRow(row)
    emitChange()
  end

  function self:_pickMatrixCell(hueIndex, satRow)
    self._hueIndex = hueIndex
    self._satRow = satRow
    self._v = 1
    self:_refreshBrightnessSwatches()
    emitChange()
  end

  for row = 1, GRID_ROWS do
    local rrow = row
    local brightComp = makeSwatchComponent(function()
      return 1, 1, 1, 1
    end, function()
      self:_pickBrightnessRow(rrow)
    end)
    brightComp._rgb = { 1, 1, 1, 1 }
    brightComp.getRgb = function()
      return brightComp._rgb[1], brightComp._rgb[2], brightComp._rgb[3], brightComp._rgb[4]
    end
    self._brightComponents[row] = brightComp
    panel:setCell(BRIGHT_COL, row, { component = brightComp })
  end

  for row = 1, GRID_ROWS do
    panel:setCell(SPACER_COL, row, { component = makeSpacerComponent() })
  end

  for row = 1, GRID_ROWS do
    for mc = 1, MATRIX_COLS do
      local hueIndex = mc
      local satRow = row
      local h, s = hueSatFromIndices(hueIndex, satRow)
      local r, g, b = hsvToRgb(h, s, 1)
      local fn = function()
        return r, g, b, 1
      end
      local matComp = makeSwatchComponent(fn, function()
        self:_pickMatrixCell(hueIndex, satRow)
      end)
      panel:setCell(MATRIX_FIRST_COL + mc - 1, row, { component = matComp })
    end
  end

  self.panel = panel
  self:_refreshBrightnessSwatches()

  if opts.initialHSV then
    local ih = clamp01(opts.initialHSV.h or 0)
    local is = clamp01(opts.initialHSV.s or 1)
    local iv = opts.initialHSV.v ~= nil and clamp01(opts.initialHSV.v) or 1
    self._hueIndex = math.max(1, math.min(MATRIX_COLS, math.floor(ih * MATRIX_COLS) + 1))
    self._satRow = math.max(1, math.min(GRID_ROWS, GRID_ROWS - math.floor(is * (GRID_ROWS - 1))))
    self._v = iv
    self:_refreshBrightnessSwatches()
    emitChange()
  end

  return self
end

function ColorPickerMatrix:setVisible(visible)
  self.visible = visible ~= false
  if self.panel then
    self.panel:setVisible(self.visible)
  end
end

function ColorPickerMatrix:isVisible()
  return self.visible ~= false
end

function ColorPickerMatrix:getSelected()
  local h, s = 0, 0
  if self._hueIndex and self._satRow then
    h = (self._hueIndex - 1) / MATRIX_COLS
    s = (GRID_ROWS - self._satRow) / (GRID_ROWS - 1)
    if GRID_ROWS == 1 then
      s = 1
    end
  end
  local v = clamp01(self._v or 1)
  if not self._hueIndex then
    h, s, v = 0, 0, v
  end
  local r, g, b = hsvToRgb(h, s, v)
  return {
    r = r,
    g = g,
    b = b,
    a = 1,
    h = h,
    s = s,
    v = v,
  }
end

function ColorPickerMatrix:setPosition(x, y)
  if self.panel then
    self.panel:setPosition(x, y)
  end
end

function ColorPickerMatrix:getWidth()
  return self.panel and self.panel.w or 0
end

function ColorPickerMatrix:getHeight()
  return self.panel and self.panel.h or 0
end

function ColorPickerMatrix:contains(px, py)
  return self.panel and self.panel:contains(px, py) or false
end

function ColorPickerMatrix:draw()
  if not self.visible or not self.panel then
    return
  end
  self.panel:draw()
end

function ColorPickerMatrix:mousepressed(x, y, button)
  if not self.visible or not self.panel then
    return false
  end
  return self.panel:mousepressed(x, y, button)
end

function ColorPickerMatrix:mousereleased(x, y, button)
  if not self.visible or not self.panel then
    return false
  end
  return self.panel:mousereleased(x, y, button)
end

function ColorPickerMatrix:mousemoved(x, y)
  if not self.visible or not self.panel then
    return
  end
  self.panel:mousemoved(x, y)
end

return ColorPickerMatrix
