-- Standalone color picker: 10×8 panel grid.
-- Col 1: lightness (HSL L) for the current hue/saturation from the matrix.
-- Col 2: non-interactive spacer (no drawing).
-- Cols 3–10: hue × saturation at fixed L=0.5 (HSL); vertical axis is saturation (full at top, none at bottom).
-- onChange / getSelected still report h, s, v as HSV [0,1] derived from the resulting RGB.
local Panel = require("user_interface.panel")
local colors = require("app_colors")
local Draw = require("utils.draw_utils")
local images = require("images")

-- Same timing as tile/sprite selection overlays (window_rendering_selection.lua).
local SELECTION_RECT_ANIM = {
  stepPx = 1,
  intervalSeconds = 0.1,
}

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

local function hslToRgb(h, s, l)
  h = h % 1
  if s <= 0 then
    return l, l, l
  end
  local function hue2rgb(p, q, t)
    if t < 0 then
      t = t + 1
    end
    if t > 1 then
      t = t - 1
    end
    if t < 1 / 6 then
      return p + (q - p) * 6 * t
    end
    if t < 1 / 2 then
      return q
    end
    if t < 2 / 3 then
      return p + (q - p) * (2 / 3 - t) * 6
    end
    return p
  end
  local q = (l < 0.5) and (l * (1 + s)) or (l + s - l * s)
  local p = 2 * l - q
  return hue2rgb(p, q, h + 1 / 3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1 / 3)
end

local function rgbToHsl(r, g, b)
  local max = math.max(r, g, b)
  local min = math.min(r, g, b)
  local d = max - min
  local l = (max + min) * 0.5
  if d <= 1e-10 then
    return 0, 0, l
  end
  local s = (l > 0.5) and (d / (2 - max - min)) or (d / (max + min))
  local h
  if max == min then
    h = 0
  elseif max == r then
    h = ((g - b) / d + (g < b and 6 or 0)) / 6
  elseif max == g then
    h = ((b - r) / d + 2) / 6
  else
    h = ((r - g) / d + 4) / 6
  end
  return h % 1, s, l
end

local function rgbToHsv(r, g, b)
  local max = math.max(r, g, b)
  local min = math.min(r, g, b)
  local d = max - min
  local v = max
  local s = (max > 0) and (d / max) or 0
  local h = 0
  if d > 1e-10 then
    if max == r then
      h = (((g - b) / d) % 6) / 6
    elseif max == g then
      h = ((b - r) / d + 2) / 6
    else
      h = ((r - g) / d + 4) / 6
    end
    h = h % 1
  end
  return h, s, v
end

local function makeSpacerComponent()
  return {
    enabled = true,
    draw = function() end,
    contains = function()
      return false
    end,
  }
end

local function makeSwatchComponent(getRgbFn, onPickReleased)
  local self = {
    enabled = true,
    hovered = false,
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
      if component.hovered and images.pattern_a then
        love.graphics.setColor(1, 1, 1, 1)
        Draw.drawRepeatingImageAnimated(
          images.pattern_a,
          math.floor(component.x),
          math.floor(component.y),
          component.w,
          component.h,
          SELECTION_RECT_ANIM
        )
      end
      love.graphics.setColor(1, 1, 1, 1)
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
    _lightness = 1,
    _brightComponents = {},
    -- Exact RGB for the closed swatch; cleared when the user picks on the matrix (grid quantizes hue/sat).
    _swatchPinRgb = nil,
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

  -- HSL hue [0,1) and HSL saturation [0,1] for the matrix slice at L = 0.5.
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

  local function lightnessForRow(row)
    return (GRID_ROWS - row) / (GRID_ROWS - 1)
  end

  local function emitChange()
    local r, g, b
    local hsvH, hsvS, hsvV
    if not self._hueIndex then
      local l = clamp01(self._lightness or 1)
      r, g, b = l, l, l
      hsvH, hsvS, hsvV = rgbToHsv(r, g, b)
    else
      local h, s = currentHueSat()
      local l = clamp01(self._lightness or 0.5)
      r, g, b = hslToRgb(h, s, l)
      hsvH, hsvS, hsvV = rgbToHsv(r, g, b)
    end
    if self.onChange then
      self.onChange({
        r = r,
        g = g,
        b = b,
        a = 1,
        h = hsvH,
        s = hsvS,
        v = hsvV,
      })
    end
  end

  function self:_refreshBrightnessSwatches()
    local h, s = currentHueSat()
    for row = 1, GRID_ROWS do
      local comp = self._brightComponents[row]
      if comp then
        local Lrow = lightnessForRow(row)
        local r, g, b
        if self._hueIndex then
          r, g, b = hslToRgb(h, s, Lrow)
        else
          r, g, b = Lrow, Lrow, Lrow
        end
        comp._rgb = { r, g, b, 1 }
        comp.getRgb = function()
          return comp._rgb[1], comp._rgb[2], comp._rgb[3], comp._rgb[4]
        end
      end
    end
  end

  function self:_pickBrightnessRow(row)
    self._swatchPinRgb = nil
    self._lightness = lightnessForRow(row)
    emitChange()
  end

  function self:_pickMatrixCell(hueIndex, satRow)
    self._swatchPinRgb = nil
    self._hueIndex = hueIndex
    self._satRow = satRow
    self._lightness = 0.5
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
      local r, g, b = hslToRgb(h, s, 0.5)
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
    local r0, g0, b0 = hsvToRgb(ih, is, iv)
    local hh, ss, ll = rgbToHsl(r0, g0, b0)
    self._hueIndex = math.max(1, math.min(MATRIX_COLS, math.floor(hh * MATRIX_COLS) + 1))
    self._satRow = math.max(1, math.min(GRID_ROWS, GRID_ROWS - math.floor(ss * (GRID_ROWS - 1))))
    self._lightness = ll
    self:_refreshBrightnessSwatches()
    emitChange()
    self._swatchPinRgb = { r0, g0, b0, 1 }
  end

  function self:setSelectedFromRgb(r, g, b, opts)
    opts = opts or {}
    r = clamp01(tonumber(r) or 0)
    g = clamp01(tonumber(g) or 0)
    b = clamp01(tonumber(b) or 0)
    self._swatchPinRgb = { r, g, b, 1 }
    local hh, ss, ll = rgbToHsl(r, g, b)
    self._hueIndex = math.max(1, math.min(MATRIX_COLS, math.floor(hh * MATRIX_COLS) + 1))
    self._satRow = math.max(1, math.min(GRID_ROWS, GRID_ROWS - math.floor(ss * (GRID_ROWS - 1))))
    self._lightness = ll
    self:_refreshBrightnessSwatches()
    if opts.silent ~= true then
      emitChange()
    end
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

--- RGB for the dropdown trigger swatch (exact when synced from app; otherwise same as getSelected).
function ColorPickerMatrix:getSwatchFill()
  local pin = self._swatchPinRgb
  if pin then
    local h, s, v = rgbToHsv(pin[1], pin[2], pin[3])
    return {
      r = pin[1],
      g = pin[2],
      b = pin[3],
      a = pin[4] or 1,
      h = h,
      s = s,
      v = v,
    }
  end
  return self:getSelected()
end

function ColorPickerMatrix:getSelected()
  local r, g, b
  if self._hueIndex and self._satRow then
    local h = (self._hueIndex - 1) / MATRIX_COLS
    local s = (GRID_ROWS - self._satRow) / (GRID_ROWS - 1)
    if GRID_ROWS == 1 then
      s = 1
    end
    local l = clamp01(self._lightness or 0.5)
    r, g, b = hslToRgb(h, s, l)
  else
    local l = clamp01(self._lightness or 1)
    r, g, b = l, l, l
  end
  local hsvH, hsvS, hsvV = rgbToHsv(r, g, b)
  return {
    r = r,
    g = g,
    b = b,
    a = 1,
    h = hsvH,
    s = hsvS,
    v = hsvV,
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

--- True when (px,py) is over a clickable color swatch (brightness column or hue×sat grid, not spacer).
function ColorPickerMatrix:wantsHandCursorAt(px, py)
  if not self.visible or not self.panel then
    return false
  end
  if not self.panel:contains(px, py) then
    return false
  end
  local cell = self.panel:getCellAt(px, py)
  if not cell or not cell.component then
    return false
  end
  local col = cell.col
  if col == SPACER_COL then
    return false
  end
  if col == BRIGHT_COL then
    return true
  end
  return col >= MATRIX_FIRST_COL and col <= MATRIX_FIRST_COL + MATRIX_COLS - 1
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
