local colors = require("app_colors")
local images = require("images")
local Button = require("user_interface.button")

-- Simple numeric spinner with minus button, value label, and plus button.
-- Buttons match toolbar size (15x15 by default); label spans two button widths.
local NumericSpinner = {}
NumericSpinner.__index = NumericSpinner

function NumericSpinner.new(opts)
  opts = opts or {}
  local buttonSize = opts.buttonSize or 15
  local labelWidth = opts.labelWidth or (buttonSize * 2)
  local self = setmetatable({
    x = opts.x or 0,
    y = opts.y or 0,
    buttonSize = buttonSize,
    labelWidth = labelWidth,
    value = opts.value or 0,
    min = opts.min or 0,
    max = opts.max or 999,
    step = opts.step or 1,
    onChange = opts.onChange,
    minusButton = Button.new({
      icon = images.icons.icon_minus,
      w = buttonSize,
      h = buttonSize,
    }),
    plusButton = Button.new({
      icon = images.icons.icon_plus,
      w = buttonSize,
      h = buttonSize,
    }),
  }, NumericSpinner)
  return self
end

function NumericSpinner:getWidth()
  return self.buttonSize * 2 + self.labelWidth
end

function NumericSpinner:getHeight()
  return self.buttonSize
end

function NumericSpinner:setPosition(x, y)
  self.x = x or self.x
  self.y = y or self.y
  -- Update button positions
  self.minusButton:setPosition(self.x, self.y)
  local plusX = self.x + self.buttonSize + self.labelWidth
  self.plusButton:setPosition(plusX, self.y)
end

function NumericSpinner:setSize(w, h)
  local nextH = math.max(1, math.floor(h or self.buttonSize))
  local nextW = math.max((nextH * 2) + 1, math.floor(w or self:getWidth()))
  self.buttonSize = nextH
  self.labelWidth = math.max(1, nextW - (nextH * 2))
  self.minusButton:setSize(nextH, nextH)
  self.plusButton:setSize(nextH, nextH)
  self:setPosition(self.x, self.y)
end

function NumericSpinner:setValue(v)
  local newVal = math.max(self.min, math.min(self.max, v))
  if newVal ~= self.value then
    self.value = newVal
    if self.onChange then self.onChange(newVal) end
  end
end

function NumericSpinner:adjust(delta)
  self:setValue(self.value + delta * self.step)
end

function NumericSpinner:mousepressed(mx, my)
  if self.minusButton:contains(mx, my) then
    self.minusButton.pressed = true
    self:adjust(-1)
    return true
  end
  if self.plusButton:contains(mx, my) then
    self.plusButton.pressed = true
    self:adjust(1)
    return true
  end
  return false
end

function NumericSpinner:mousereleased()
  self.minusButton.pressed = false
  self.plusButton.pressed = false
end

function NumericSpinner:mousemoved(mx, my)
  self.minusButton.hovered = self.minusButton:contains(mx, my)
  self.plusButton.hovered = self.plusButton:contains(mx, my)
end

function NumericSpinner:draw()
  local btnW = self.buttonSize
  local btnH = self.buttonSize

  -- label box
  local labelX = self.x + btnW
  local labelY = self.y

  local text = tostring(self.value)
  local font = love.graphics.getFont()
  if font then
    local tw = font:getWidth(text)
    local th = font:getHeight()
    love.graphics.setColor(colors.white)
    love.graphics.print(text, labelX + (self.labelWidth - tw) / 2, labelY + (btnH - th) / 2)
  end

  love.graphics.setColor(colors.white)
  self.minusButton:draw()
  self.plusButton:draw()

  love.graphics.setColor(colors.white)
end

return NumericSpinner
