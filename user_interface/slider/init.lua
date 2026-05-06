-- Simple horizontal value slider (track + thumb) for modal panels.

local colors = require("app_colors")
local Text = require("utils.text_utils")
local UiScale = require("user_interface.ui_scale")

local Slider = {}
Slider.__index = Slider

local TRACK_H = 6
local THUMB_W = 8
local PADDING_Y = 2

local function clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

function Slider.new(opts)
  opts = opts or {}
  local minV = tonumber(opts.min) or 0
  local maxV = tonumber(opts.max) or 1
  if maxV < minV then
    minV, maxV = maxV, minV
  end
  local self = setmetatable({
    x = opts.x or 0,
    y = opts.y or 0,
    w = opts.w or 120,
    h = math.max(TRACK_H + PADDING_Y * 2, math.floor(tonumber(opts.h) or UiScale.menuCellSize())),
    min = minV,
    max = maxV,
    value = clamp(tonumber(opts.value) or minV, minV, maxV),
    enabled = opts.enabled ~= false,
    dragging = false,
    hovered = false,
    tooltip = opts.tooltip or "",
    onChange = opts.onChange,
    onCommit = opts.onCommit,
    formatValue = opts.formatValue,
  }, Slider)
  return self
end

function Slider:setEnabled(on)
  self.enabled = (on == true)
  if not self.enabled then
    self.dragging = false
    self.hovered = false
  end
end

function Slider:setValue(v, opts)
  opts = opts or {}
  local silent = opts.silent == true
  if not self.enabled and not silent then
    return
  end
  local n = clamp(tonumber(v) or self.min, self.min, self.max)
  if n ~= self.value then
    self.value = n
    if not silent and self.onChange then
      self.onChange(n)
    end
  end
end

function Slider:getValue()
  return self.value
end

function Slider:isDragging()
  return self.dragging == true
end

function Slider:setPosition(x, y)
  self.x = x or self.x
  self.y = y or self.y
end

function Slider:setSize(w, h)
  self.w = math.max(1, math.floor(tonumber(w) or self.w))
  self.h = math.max(TRACK_H + PADDING_Y * 2, math.floor(tonumber(h) or self.h))
end

function Slider:_trackGeometry()
  local tw = math.max(1, self.w - THUMB_W)
  local tx = self.x + math.floor(THUMB_W / 2)
  local ty = self.y + math.floor((self.h - TRACK_H) * 0.5)
  return tx, ty, tw, TRACK_H
end

function Slider:_thumbCenterX()
  local tx, _, tw = self:_trackGeometry()
  local t = (self.max > self.min) and ((self.value - self.min) / (self.max - self.min)) or 0
  return tx + t * tw
end

function Slider:_setFromMouseX(mx)
  local tx, _, tw = self:_trackGeometry()
  if tw <= 0 then
    return
  end
  local t = (mx - tx) / tw
  t = clamp(t, 0, 1)
  self:setValue(self.min + t * (self.max - self.min))
end

function Slider:contains(px, py)
  return px >= self.x and px <= (self.x + self.w) and py >= self.y and py <= (self.y + self.h)
end

function Slider:mousepressed(mx, my, button)
  if not self.enabled or button ~= 1 then
    return false
  end
  if not self:contains(mx, my) then
    return false
  end
  self.dragging = true
  self:_setFromMouseX(mx)
  return true
end

function Slider:mousereleased(mx, my, button)
  if button ~= 1 then
    return false
  end
  if self.dragging then
    self.dragging = false
    if self.onCommit then
      self.onCommit(self.value)
    end
    return true
  end
  return false
end

function Slider:mousemoved(mx, my)
  if not self.enabled then
    self.hovered = false
    return
  end
  self.hovered = self:contains(mx, my)
  if self.dragging then
    self:_setFromMouseX(mx)
  end
end

function Slider:_valueLabel()
  if type(self.formatValue) == "function" then
    return self.formatValue(self.value)
  end
  return string.format("%.2f", self.value)
end

function Slider:draw()
  local tx, ty, tw, th = self:_trackGeometry()
  local cx = self:_thumbCenterX()
  local thumbW = THUMB_W
  local thumbRectH = TRACK_H + 2
  if self.enabled and (self.hovered or self.dragging) then
    thumbW = THUMB_W + 4
    thumbRectH = thumbRectH + 3
  end
  local thumbX = math.floor(cx - thumbW / 2)
  local thumbY = math.floor(self.y + (self.h - thumbRectH) * 0.5)

  local trackBg = self.enabled and colors.gray10 or colors.gray20
  local fillTo = cx
  love.graphics.setColor(trackBg[1], trackBg[2], trackBg[3], trackBg[4] or 1)
  love.graphics.rectangle("fill", tx, ty, tw, th, 2, 2)

  if self.enabled then
    love.graphics.setColor(colors.yellow[1], colors.yellow[2], colors.yellow[3], 0.55)
    local fillW = math.max(0, fillTo - tx)
    if fillW > 0 then
      love.graphics.rectangle("fill", tx, ty, fillW, th, 2, 2)
    end
  end

  local thumbBg = colors.white
  if not self.enabled then
    thumbBg = colors.gray50
  end

  love.graphics.setColor(thumbBg[1], thumbBg[2], thumbBg[3], thumbBg[4] or 1)
  love.graphics.rectangle("fill", thumbX, thumbY, thumbW, thumbRectH, 2, 2)

  local label = self:_valueLabel()
  local font = love.graphics.getFont()
  local fh = font and font:getHeight() or 10
  local textY = math.floor(self.y + (self.h - fh) * 0.5)
  local textX = math.floor(tx + tw + 6)
  local textColor = self.enabled and colors.white or colors.gray50
  Text.print(label, textX, textY, { color = textColor })
  love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 1)
end

return Slider
