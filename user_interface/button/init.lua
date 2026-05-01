-- button.lua
-- Reusable button component for toolbars and UI

local colors = require("app_colors")
local UiScale = require("user_interface.ui_scale")
local Text = require("utils.text_utils")
local Draw = require("utils.draw_utils")

local Button = {}
Button.__index = Button

local function iconSize(icon)
  if not icon then return 0, 0 end
  if type(icon.getWidth) == "function" and type(icon.getHeight) == "function" then
    return icon:getWidth(), icon:getHeight()
  end
  return tonumber(icon.w) or 0, tonumber(icon.h) or 0
end

local function drawIcon(icon, x, y, opts)
  local dx = math.floor(x)
  local dy = math.floor(y)
  if type(icon) == "table" then
    if type(icon.draw) == "function" then
      icon:draw(dx, dy)
    end
    return
  end
  Draw.drawIcon(icon, dx, dy, opts)
end

function Button.new(opts)
  opts = opts or {}
  local hasExplicitW = (opts.w ~= nil)
  local hasExplicitH = (opts.h ~= nil)
  local initialW = opts.w or 0
  local initialH = opts.h or 0
  if opts.icon and not opts.text then
    local iw, ih = iconSize(opts.icon)
    if (not hasExplicitW) then
      initialW = UiScale.mapStandardButtonSize(iw) or iw
    end
    if (not hasExplicitH) then
      initialH = UiScale.mapStandardButtonSize(ih) or ih
    end
  end
  local self = setmetatable({
    icon = opts.icon,  -- Image object
    text = opts.text,
    action = opts.action,  -- Function to call when clicked
    tooltip = opts.tooltip or "",
    x = opts.x or 0,
    y = opts.y or 0,
    w = initialW,
    h = initialH,
    _explicitW = hasExplicitW,
    _explicitH = hasExplicitH,
    hovered = false,
    pressed = false,
    focused = false,
    enabled = opts.enabled ~= false,
    alwaysOpaqueContent = opts.alwaysOpaqueContent == true,
    normalContentAlpha = opts.normalContentAlpha,
    transparent = opts.transparent == true,
    textAlign = opts.textAlign or "center",
    contentPaddingX = opts.contentPaddingX or 4,
    iconTextGap = opts.iconTextGap or 4,
    alignTextToContentPadding = opts.alignTextToContentPadding == true,
    bgColor = opts.bgColor,
    bgAlpha = (opts.bgAlpha ~= nil) and opts.bgAlpha or 1,
    contentColor = opts.contentColor,
    iconRespectTheme = opts.iconRespectTheme,
    literalContentColor = opts.literalContentColor == true,
    skipIconContrastAdapt = opts.skipIconContrastAdapt == true,
    -- Additional properties can be stored here
    isCloseButton = opts.isCloseButton,
  }, Button)
  
  return self
end

-- Check if a point is inside the button
function Button:contains(px, py)
  return px >= self.x and px <= self.x + self.w and
         py >= self.y and py <= self.y + self.h
end

-- Draw the button (transparent background with icon)
-- Override this method in subclasses for different button styles
function Button:draw()
  local function drawBaseFill()
    if not self.bgColor then return end
    local c = self.bgColor
    local a = self.bgAlpha or 1
    love.graphics.setColor(c[1] or 1, c[2] or 1, c[3] or 1, a)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
  end

  local function contentAlpha()
    if self.enabled == false then
      return 0.12
    end
    if self.alwaysOpaqueContent then
      return 1.0
    end
    local idleAlpha = (self.normalContentAlpha ~= nil) and self.normalContentAlpha or 0.4
    return (self.hovered or self.pressed or self.focused) and 1.0 or idleAlpha
  end

  local function contentColorWithAlpha(alpha)
    local c = self.contentColor or colors.white
    return c[1], c[2], c[3], alpha
  end

  --- Icons are bitmap white-fill; tint via multiply. With literal + contentColor, use contentColor (Appearance).
  local function iconInkRgba(alpha)
    if self.skipIconContrastAdapt == true then
      return colors.white[1], colors.white[2], colors.white[3], alpha
    end
    if self.literalContentColor == true and self.contentColor then
      return self.contentColor[1], self.contentColor[2], self.contentColor[3], alpha
    end
    if self.iconRespectTheme == false then
      return colors.white[1], colors.white[2], colors.white[3], alpha
    end
    local ic = colors.iconPrimary or colors.white
    return ic[1], ic[2], ic[3], alpha
  end

  local function drawHoverFocusUnderlay()
    if self.enabled == false then return end
    if not (self.hovered or self.focused) then return end
    love.graphics.setColor(0, 0, 0, 0.10)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 2)
  end

  if not self.icon and self.text then
    drawBaseFill()
    drawHoverFocusUnderlay()
    local font = love.graphics.getFont()
    local textW = font:getWidth(self.text)
    local textH = font:getHeight()
    local textX
    if self.textAlign == "left" then
      textX = self.x + self.contentPaddingX
    else
      textX = self.x + (self.w - textW) / 2
    end
    local textY = self.y + (self.h - textH) / 2
    local a = contentAlpha()
    local r, g, b, aa = contentColorWithAlpha(a)
    Text.print(self.text, math.floor(textX), math.floor(textY), {
      color = { r, g, b, aa },
      literalColor = self.literalContentColor == true,
    })
    love.graphics.setColor(colors.white)
    return
  end

  if self.icon and self.text then
    drawBaseFill()
    drawHoverFocusUnderlay()
    local font = love.graphics.getFont()
    local iconW, iconH = iconSize(self.icon)
    local textW = font:getWidth(self.text)
    local textH = font:getHeight()
    local contentW = iconW + self.iconTextGap + textW

    local contentX
    if self.textAlign == "left" then
      contentX = self.x + self.contentPaddingX
    else
      contentX = self.x + (self.w - contentW) / 2
    end
    local iconX = contentX
    local iconY = self.y + (self.h - iconH) / 2
    local textX = iconX + iconW + self.iconTextGap
    if self.textAlign == "left" and self.alignTextToContentPadding == true then
      textX = self.x + self.contentPaddingX
      iconX = self.x
    end
    local textY = self.y + (self.h - textH) / 2

    local iconAlpha = contentAlpha()
    local r, g, b, a = contentColorWithAlpha(iconAlpha)
    local ir, ig, ib, ia = iconInkRgba(iconAlpha)
    love.graphics.setColor(ir, ig, ib, ia)
    drawIcon(self.icon, iconX, iconY, { respectTheme = false })

    Text.print(self.text, math.floor(textX), math.floor(textY), {
      color = { r, g, b, a },
      literalColor = self.literalContentColor == true,
    })
    love.graphics.setColor(colors.white)
    return
  end

  if not self.icon then return end
  drawBaseFill()
  drawHoverFocusUnderlay()

  if not self.skipIconDraw then
    local iconAlpha = contentAlpha()
    local ir, ig, ib, ia = iconInkRgba(iconAlpha)
    love.graphics.setColor(ir, ig, ib, ia)

    local iconW, iconH = iconSize(self.icon)
    local iconX = self.x + (self.w - iconW) / 2  -- Center horizontally
    local iconY = self.y + (self.h - iconH) / 2  -- Center vertically
    drawIcon(self.icon, iconX, iconY, { respectTheme = false })
  end
  love.graphics.setColor(colors.white)
end

-- Update button position
function Button:setPosition(x, y)
  self.x = x or self.x
  self.y = y or self.y
end

-- Update button size
function Button:setSize(w, h)
  self.w = w or self.w
  self.h = h or self.h
end

function Button:applyUiScale()
  local w = tonumber(self.w)
  local h = tonumber(self.h)
  if UiScale.isScalableButtonSquare(w, h) then
    local size = UiScale.buttonSize()
    self:setSize(size, size)
    return true
  end
  return false
end

return Button
