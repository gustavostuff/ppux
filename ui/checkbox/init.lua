-- checkbox.lua
-- Icon + label control without button chrome / modal outline.

local colors = require("app_colors")
local images = require("images")
local Draw = require("utils.draw_utils")
local Text = require("utils.text_utils")
local UiScale = require("ui.ui_scale")

local Checkbox = {}
Checkbox.__index = Checkbox

local DEFAULT_ICON_GAP = 4

local function iconSize(icon)
  if not icon then return 0, 0 end
  if type(icon.getWidth) == "function" and type(icon.getHeight) == "function" then
    return icon:getWidth(), icon:getHeight()
  end
  return tonumber(icon.w) or 0, tonumber(icon.h) or 0
end

local function resolveIcons(opts)
  local selected = opts.iconSelected
  local notSelected = opts.iconNotSelected
  local chrome = images and images.icons and images.icons.chrome
  if not selected and chrome then
    selected = chrome.icon_selected
  end
  if not notSelected and chrome then
    notSelected = chrome.icon_not_selected
  end
  return selected, notSelected
end

function Checkbox.new(opts)
  opts = opts or {}
  local iconSelected, iconNotSelected = resolveIcons(opts)
  local iw, ih = iconSize(iconNotSelected or iconSelected)
  local self = setmetatable({
    text = opts.text or "",
    checked = opts.checked == true,
    iconSelected = iconSelected,
    iconNotSelected = iconNotSelected,
    x = opts.x or 0,
    y = opts.y or 0,
    w = opts.w or math.max(iw, UiScale.buttonSize()),
    h = opts.h or math.max(ih, UiScale.buttonSize()),
    enabled = opts.enabled ~= false,
    hovered = false,
    pressed = false,
    focused = false,
    contentPaddingX = opts.contentPaddingX or 0,
    iconTextGap = opts.iconTextGap or DEFAULT_ICON_GAP,
    contentColor = opts.contentColor,
    onChange = opts.onChange,
    tooltip = opts.tooltip or "",
  }, Checkbox)

  -- Panel treats components with `.action` like buttons for click/release.
  self.action = function()
    if self.enabled == false then
      return
    end
    self:toggle()
  end

  return self
end

function Checkbox:isChecked()
  return self.checked == true
end

function Checkbox:setChecked(checked, opts)
  opts = opts or {}
  local nextChecked = checked == true
  if self.checked == nextChecked then
    return
  end
  self.checked = nextChecked
  if opts.silent ~= true and type(self.onChange) == "function" then
    self.onChange(self.checked)
  end
end

function Checkbox:toggle(opts)
  self:setChecked(not self:isChecked(), opts)
end

function Checkbox:setText(text)
  self.text = tostring(text or "")
end

function Checkbox:contains(px, py)
  return px >= self.x and px <= self.x + self.w
    and py >= self.y and py <= self.y + self.h
end

function Checkbox:setPosition(x, y)
  self.x = x or self.x
  self.y = y or self.y
end

function Checkbox:setSize(w, h)
  self.w = w or self.w
  self.h = h or self.h
end

function Checkbox:applyUiScale()
  local size = UiScale.buttonSize()
  local iw, ih = iconSize(self.iconNotSelected or self.iconSelected)
  if self.h <= 0 or UiScale.isKnownButtonSize(self.h) then
    self.h = math.max(size, ih)
  end
  if self.w <= 0 then
    self.w = math.max(size, iw)
  end
end

function Checkbox:_activeIcon()
  if self:isChecked() then
    return self.iconSelected or self.iconNotSelected
  end
  return self.iconNotSelected or self.iconSelected
end

function Checkbox:draw()
  if self.enabled == false then
    love.graphics.setColor(1, 1, 1, 0.5)
  end

  local icon = self:_activeIcon()
  local iw, ih = iconSize(icon)
  local iconX = self.x + (self.contentPaddingX or 0)
  local iconY = self.y + math.floor((self.h - ih) * 0.5)

  local ink = self.contentColor or colors.iconPrimary or colors.white
  love.graphics.setColor(ink[1] or 1, ink[2] or 1, ink[3] or 1, self.enabled == false and 0.5 or 1)
  if icon then
    Draw.drawIcon(icon, iconX, iconY, { respectTheme = false })
  end

  local label = self.text
  if label and label ~= "" then
    local font = love.graphics.getFont()
    local textX = iconX + iw + (self.iconTextGap or DEFAULT_ICON_GAP)
    local textY = self.y + math.floor((self.h - (font and font:getHeight() or 0)) * 0.5)
    Text.print(label, textX, textY, {
      shadowColor = colors.transparent,
      color = ink,
      literalColor = true,
    })
  end

  love.graphics.setColor(colors.white)
end

return Checkbox
