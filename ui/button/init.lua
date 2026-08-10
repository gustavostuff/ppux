-- button.lua
-- Reusable button component for toolbars and UI

local colors = require("app_colors")
local UiScale = require("ui.ui_scale")
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
    normalContentAlpha = opts.normalContentAlpha,
    transparent = opts.transparent == true,
    textAlign = opts.textAlign or "center",
    contentPaddingX = opts.contentPaddingX or 4,
    contentPaddingRight = opts.contentPaddingRight or 0,
    iconTextGap = opts.iconTextGap or 4,
    alignTextToContentPadding = opts.alignTextToContentPadding == true,
    bgColor = opts.bgColor,
    bgAlpha = (opts.bgAlpha ~= nil) and opts.bgAlpha or 1,
    contentColor = opts.contentColor,
    --- When set, icon multiply tint only (e.g. white glyphs); label/text still uses `contentColor`.
    iconTintColor = opts.iconTintColor,
    iconRespectTheme = opts.iconRespectTheme,
    literalContentColor = opts.literalContentColor == true,
    skipIconContrastAdapt = opts.skipIconContrastAdapt == true,
    -- When true, hover/focus underlay only draws for hover/press (not keyboard/window "focused" alone).
    underlayOnHoverOnly = opts.underlayOnHoverOnly == true,
    -- Corner radius for the dark hover/focus underlay (0 = sharp square). Default 2 for menus/modals.
    underlayCornerRadius = (opts.underlayCornerRadius ~= nil) and opts.underlayCornerRadius or 2,
    -- When true, skip the dark rounded hover/focus fill (e.g. parent draws one rect across split cells).
    skipHoverFocusUnderlay = opts.skipHoverFocusUnderlay == true,
    -- When true, modal panel chrome does not replace contentColor with chrome ink (file rows, etc.).
    preserveModalContentColor = opts.preserveModalContentColor == true,
    -- When true, skip the modal 1px control outline (file list rows, etc.).
    skipModalControlOutline = opts.skipModalControlOutline == true,
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

local function contentAlphaFor(button)
  if button.enabled == false then
    return 0.5
  end
  if button.normalContentAlpha ~= nil then
    return (button.hovered or button.pressed or button.focused) and 1.0 or button.normalContentAlpha
  end
  return 1.0
end

local function iconInkRgbaFor(button, alpha)
  local tint = button.iconTintColor
  if type(tint) == "table" then
    return tint[1] or 1, tint[2] or 1, tint[3] or 1, alpha
  end
  if button.skipIconContrastAdapt == true then
    return colors.white[1], colors.white[2], colors.white[3], alpha
  end
  if button.literalContentColor == true and button.contentColor then
    return button.contentColor[1], button.contentColor[2], button.contentColor[3], alpha
  end
  if button.iconRespectTheme == false then
    return colors.white[1], colors.white[2], colors.white[3], alpha
  end
  local ic = colors.iconPrimary or colors.white
  return ic[1], ic[2], ic[3], alpha
end

--- Icon top-left for the current layout, or nil when there is nothing to draw.
function Button:getIconDrawPosition()
  if not self.icon or self.skipIconDraw then
    return nil
  end
  local iconW, iconH = iconSize(self.icon)
  if iconW <= 0 or iconH <= 0 then
    return nil
  end
  local iconY = self.y + (self.h - iconH) / 2
  if self.text then
    local font = love.graphics.getFont()
    local textW = font and font:getWidth(self.text) or 0
    local contentW = iconW + self.iconTextGap + textW
    local contentX
    if self.textAlign == "left" then
      contentX = self.x + self.contentPaddingX
    else
      contentX = self.x + (self.w - contentW) / 2
    end
    local iconX = contentX
    if self.textAlign == "left" and self.alignTextToContentPadding == true then
      iconX = self.x
    end
    return iconX, iconY
  end
  return self.x + (self.w - iconW) / 2, iconY
end

--- Draw only the icon (used after control outlines so strokes do not cover glyphs).
function Button:drawIconContent()
  local iconX, iconY = self:getIconDrawPosition()
  if iconX == nil then
    return
  end
  local iconAlpha = contentAlphaFor(self)
  local ir, ig, ib, ia = iconInkRgbaFor(self, iconAlpha)
  love.graphics.setColor(ir, ig, ib, ia)
  drawIcon(self.icon, iconX, iconY, { respectTheme = false })
  love.graphics.setColor(colors.white)
end

-- Draw the button (transparent background with icon)
-- opts.skipIcon: draw fill/text only; call drawIconContent() after an outline.
function Button:draw(opts)
  opts = opts or {}
  local skipIcon = opts.skipIcon == true

  local function drawBaseFill()
    if not self.bgColor then return end
    local c = self.bgColor
    local a = self.bgAlpha or 1
    love.graphics.setColor(c[1] or 1, c[2] or 1, c[3] or 1, a)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
  end

  local function contentColorWithAlpha(alpha)
    local c = self.contentColor or colors.white
    return c[1], c[2], c[3], alpha
  end

  local function drawHoverFocusUnderlay()
    if self.skipHoverFocusUnderlay then
      return
    end
    if self.enabled == false then return end
    local show
    if self.underlayOnHoverOnly then
      show = self.hovered or self.pressed
    else
      show = self.hovered or self.pressed or self.focused
    end
    if not show then return end

    love.graphics.setColor(0, 0, 0, 0.10)
    local rx = tonumber(self.underlayCornerRadius) or 2
    if rx > 0 then
      love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, rx, rx)
    else
      -- Sharp square; window toolbars clip this via their rounded stencil/scissor.
      love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
    end
    love.graphics.setColor(colors.white)
  end

  if not self.icon and self.text then
    drawBaseFill()
    drawHoverFocusUnderlay()
    local font = love.graphics.getFont()
    local textW = font:getWidth(self.text)
    local textH = font:getHeight()
    local padL = self.contentPaddingX or 0
    local padR = self.contentPaddingRight or 0
    local textX
    if self.textAlign == "left" then
      textX = self.x + padL
    else
      textX = self.x + padL + (self.w - padL - padR - textW) / 2
    end
    local textY = self.y + (self.h - textH) / 2
    local a = contentAlphaFor(self)
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
    local textX = iconX + iconW + self.iconTextGap
    if self.textAlign == "left" and self.alignTextToContentPadding == true then
      textX = self.x + self.contentPaddingX
      iconX = self.x
    end
    local textY = self.y + (self.h - textH) / 2

    if not skipIcon then
      self:drawIconContent()
    end

    local a = contentAlphaFor(self)
    local r, g, b, aa = contentColorWithAlpha(a)
    Text.print(self.text, math.floor(textX), math.floor(textY), {
      color = { r, g, b, aa },
      literalColor = self.literalContentColor == true,
    })
    love.graphics.setColor(colors.white)
    return
  end

  if not self.icon then return end
  drawBaseFill()
  drawHoverFocusUnderlay()

  if not skipIcon then
    self:drawIconContent()
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
