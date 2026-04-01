local colors = require("app_colors")
local images = require("images")

local NumericSpinner = {}
NumericSpinner.__index = NumericSpinner

local BUTTON_SIZE = 15
local VALUE_PADDING_X = 4
local MIN_VALUE_WIDTH = 12

local function getIconSize(icon)
  if not icon then return 0, 0 end
  if type(icon.getWidth) == "function" and type(icon.getHeight) == "function" then
    return icon:getWidth(), icon:getHeight()
  end
  return tonumber(icon.w) or 0, tonumber(icon.h) or 0
end

local function drawIcon(icon, x, y)
  if not icon then
    return
  end
  if type(icon) == "table" and type(icon.draw) == "function" then
    icon:draw(math.floor(x), math.floor(y))
    return
  end
  love.graphics.draw(icon, math.floor(x), math.floor(y))
end

local function getFont()
  if love and love.graphics and love.graphics.getFont then
    return love.graphics.getFont()
  end
  return nil
end

local function pointInRect(px, py, x, y, w, h)
  return px >= x and px <= (x + w) and py >= y and py <= (y + h)
end

function NumericSpinner.new(opts)
  opts = opts or {}
  local self = setmetatable({
    x = opts.x or 0,
    y = opts.y or 0,
    h = BUTTON_SIZE,
    w = 0,
    buttonSize = BUTTON_SIZE,
    value = opts.value or 0,
    min = opts.min or 0,
    max = opts.max or 999,
    step = opts.step or 1,
    onChange = opts.onChange,
    minValueWidth = math.max(MIN_VALUE_WIDTH, math.floor(opts.minValueWidth or 0)),
    fixedValueWidth = (opts.valueWidth ~= nil) and math.max(1, math.floor(opts.valueWidth)) or nil,
    valuePaddingX = math.max(0, math.floor(opts.valuePaddingX or VALUE_PADDING_X)),
    bgColor = opts.bgColor,
    minusIcon = opts.minusIcon or (images and images.icons and images.icons.icon_minus),
    plusIcon = opts.plusIcon or (images and images.icons and images.icons.icon_plus),
    hoveredPart = nil,
    pressedPart = nil,
  }, NumericSpinner)
  self:_updateWidth()
  return self
end

function NumericSpinner:_valueText()
  return tostring(self.value)
end

function NumericSpinner:_valueAreaWidth()
  if self.fixedValueWidth then
    return self.fixedValueWidth
  end
  local font = getFont()
  local textW = font and font:getWidth(self:_valueText()) or 0
  return math.max(self.minValueWidth, textW + (self.valuePaddingX * 2))
end

function NumericSpinner:_updateWidth()
  self.w = (self.buttonSize * 2) + self:_valueAreaWidth()
end

function NumericSpinner:getWidth()
  self:_updateWidth()
  return self.w
end

function NumericSpinner:getHeight()
  return self.h
end

function NumericSpinner:setPosition(x, y)
  self.x = x or self.x
  self.y = y or self.y
end

function NumericSpinner:setSize()
  self.h = self.buttonSize
  self:_updateWidth()
end

function NumericSpinner:_minusRect()
  return self.x, self.y, self.buttonSize, self.h
end

function NumericSpinner:_plusRect()
  self:_updateWidth()
  return self.x + self.w - self.buttonSize, self.y, self.buttonSize, self.h
end

function NumericSpinner:contains(px, py)
  self:_updateWidth()
  return pointInRect(px, py, self.x, self.y, self.w, self.h)
end

function NumericSpinner:setValue(v)
  local newVal = math.max(self.min, math.min(self.max, v))
  if newVal ~= self.value then
    self.value = newVal
    self:_updateWidth()
    if self.onChange then
      self.onChange(newVal)
    end
  end
end

function NumericSpinner:adjust(delta)
  self:setValue(self.value + (delta * self.step))
end

function NumericSpinner:mousepressed(mx, my, button)
  if button ~= 1 then
    return false
  end

  local minusX, minusY, minusW, minusH = self:_minusRect()
  if pointInRect(mx, my, minusX, minusY, minusW, minusH) then
    self.pressedPart = "minus"
    self:adjust(-1)
    return true
  end

  local plusX, plusY, plusW, plusH = self:_plusRect()
  if pointInRect(mx, my, plusX, plusY, plusW, plusH) then
    self.pressedPart = "plus"
    self:adjust(1)
    return true
  end

  return self:contains(mx, my)
end

function NumericSpinner:mousereleased()
  self.pressedPart = nil
  return true
end

function NumericSpinner:mousemoved(mx, my)
  self.hoveredPart = nil
  local minusX, minusY, minusW, minusH = self:_minusRect()
  if pointInRect(mx, my, minusX, minusY, minusW, minusH) then
    self.hoveredPart = "minus"
    return
  end

  local plusX, plusY, plusW, plusH = self:_plusRect()
  if pointInRect(mx, my, plusX, plusY, plusW, plusH) then
    self.hoveredPart = "plus"
  end
end

function NumericSpinner:draw()
  self:_updateWidth()

  local minusX, minusY, minusW, minusH = self:_minusRect()
  local plusX, plusY, plusW, plusH = self:_plusRect()
  local valueX = self.x + self.buttonSize
  local valueW = self.w - (self.buttonSize * 2)

  if self.bgColor then
    love.graphics.setColor(self.bgColor)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
  end

  if self.hoveredPart == "minus" or self.pressedPart == "minus" then
    love.graphics.setColor(0, 0, 0, 0.18)
    love.graphics.rectangle("fill", minusX, minusY, minusW, minusH)
  end
  if self.hoveredPart == "plus" or self.pressedPart == "plus" then
    love.graphics.setColor(0, 0, 0, 0.18)
    love.graphics.rectangle("fill", plusX, plusY, plusW, plusH)
  end

  local font = getFont()
  local textH = font and font:getHeight() or 0
  local valueText = self:_valueText()
  local valueTextW = font and font:getWidth(valueText) or 0
  local textY = self.y + math.floor((self.h - textH) * 0.5)
  local minusIconW, minusIconH = getIconSize(self.minusIcon)
  local plusIconW, plusIconH = getIconSize(self.plusIcon)

  love.graphics.setColor(colors.white)
  drawIcon(self.minusIcon, minusX + (minusW - minusIconW) * 0.5, minusY + (minusH - minusIconH) * 0.5)
  drawIcon(self.plusIcon, plusX + (plusW - plusIconW) * 0.5, plusY + (plusH - plusIconH) * 0.5)
  love.graphics.print(valueText, math.floor(valueX + (valueW - valueTextW) * 0.5), textY)
end

return NumericSpinner
