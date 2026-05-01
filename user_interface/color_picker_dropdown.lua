-- Composite control: Dropdown whose trigger shows only the selected color (11×11 fill + animated
-- marching-ants border using the same pattern as tile/sprite selection overlays) and whose menu
-- embeds a ColorPickerMatrix. The list panel uses a transparent background by default so no grey strip
-- appears beside the matrix; override with opts.menuBgColor.
-- opts.menuOpenAbove (default true): place the matrix above the trigger; set false to prefer below (same as Dropdown).
local Button = require("user_interface.button")
local ColorPickerMatrix = require("user_interface.color_picker_matrix")
local Dropdown = require("user_interface.dropdown")
local Draw = require("utils.draw_utils")
local images = require("images")
local colors = require("app_colors")

local SWATCH_PX = 11
-- Matches user_interface/windows_system/window_rendering_selection.lua (tile/sprite selection).
local SELECTION_RECT_ANIM = {
  stepPx = 1,
  intervalSeconds = 0.1,
}

local function rgbChannelToByte(c)
  return math.max(0, math.min(255, math.floor((tonumber(c) or 0) * 255 + 0.5)))
end

local function rgbToHex8(r, g, b)
  return string.format("#%02X%02X%02X", rgbChannelToByte(r), rgbChannelToByte(g), rgbChannelToByte(b))
end

local function makeSwatchIcon(matrix)
  return {
    getWidth = function()
      return SWATCH_PX
    end,
    getHeight = function()
      return SWATCH_PX
    end,
    draw = function(_, ix, iy)
      local fill = matrix.getSwatchFill and matrix:getSwatchFill() or matrix:getSelected()
      local s = fill
      local fx = math.floor(ix)
      local fy = math.floor(iy)
      love.graphics.setColor(s.r, s.g, s.b, s.a or 1)
      love.graphics.rectangle("fill", fx, fy, SWATCH_PX, SWATCH_PX)
      if images.pattern_a then
        love.graphics.setColor(1, 1, 1, 1)
        Draw.drawRepeatingImageAnimated(
          images.pattern_a,
          fx,
          fy,
          SWATCH_PX,
          SWATCH_PX,
          SELECTION_RECT_ANIM
        )
      end
      love.graphics.setColor(1, 1, 1, 1)
    end,
  }
end

local ColorPickerDropdown = {}
ColorPickerDropdown.__index = ColorPickerDropdown

local function forward(self, name, ...)
  return self._dropdown[name](self._dropdown, ...)
end

function ColorPickerDropdown.new(opts)
  opts = opts or {}
  local userOnChange = opts.onChange

  local picker = ColorPickerMatrix.new({
    cellSize = opts.cellSize,
    cellW = opts.cellW,
    cellH = opts.cellH,
    colGap = opts.colGap,
    rowGap = opts.rowGap,
    gap = opts.gap,
    padding = opts.padding,
    bgColor = opts.matrixBgColor or opts.bgColor,
    initialHSV = opts.initialHSV,
    onChange = function(c)
      if userOnChange then
        userOnChange(c)
      end
    end,
  })

  local dd = Dropdown.new({
    getBounds = opts.getBounds,
    menuCellH = picker:getHeight(),
    menuCellW = opts.menuCellW,
    menuOpenAbove = opts.menuOpenAbove ~= false,
    menuBgColor = opts.menuBgColor or colors.transparent,
    closeMenuOnItemPick = opts.closeMenuOnItemPick,
    tooltip = opts.tooltip or "",
    enabled = opts.enabled,
    default = opts.default,
    onBeforeOpenMenu = opts.onBeforeOpenMenu,
    items = {
      {
        value = opts.itemValue or 1,
        text = opts.itemText ~= nil and opts.itemText or "",
        embed = picker,
      },
    },
  })

  local prev = dd.trigger
  local trigger = Button.new({
    icon = makeSwatchIcon(picker),
    text = "",
    textAlign = "left",
    contentPaddingX = 4,
    iconTextGap = 6,
    transparent = true,
    tooltip = opts.tooltip or "",
    w = prev.w,
    h = prev.h,
    enabled = opts.enabled ~= false,
    alwaysOpaqueContent = true,
  })
  trigger:setPosition(prev.x, prev.y)

  local function triggerDraw(self)
    local fill = picker.getSwatchFill and picker:getSwatchFill() or picker:getSelected()
    if fill then
      self.text = rgbToHex8(fill.r, fill.g, fill.b)
    else
      self.text = ""
    end
    Button.draw(self)
  end
  trigger.draw = triggerDraw

  dd.trigger = trigger

  local self = setmetatable({
    _dropdown = dd,
    matrix = picker,
    menu = dd.menu,
    trigger = trigger,
    action = function() end,
  }, ColorPickerDropdown)

  return self
end

function ColorPickerDropdown:getSelected()
  return self.matrix:getSelected()
end

function ColorPickerDropdown:setSelectedFromRgb(r, g, b, opts)
  self.matrix:setSelectedFromRgb(r, g, b, opts)
end

function ColorPickerDropdown:wantsHandCursorAt(px, py)
  if not self:isMenuVisible() then
    return false
  end
  return self.matrix:wantsHandCursorAt(px, py)
end

function ColorPickerDropdown:setGetBounds(fn)
  return forward(self, "setGetBounds", fn)
end

function ColorPickerDropdown:isMenuVisible()
  return forward(self, "isMenuVisible")
end

function ColorPickerDropdown:closeMenu()
  return forward(self, "closeMenu")
end

function ColorPickerDropdown:contains(px, py)
  return forward(self, "contains", px, py)
end

function ColorPickerDropdown:setPosition(x, y)
  return forward(self, "setPosition", x, y)
end

function ColorPickerDropdown:setSize(w, h)
  return forward(self, "setSize", w, h)
end

function ColorPickerDropdown:setFocused(focused)
  return forward(self, "setFocused", focused)
end

function ColorPickerDropdown:getValue()
  return forward(self, "getValue")
end

function ColorPickerDropdown:getLabel()
  return forward(self, "getLabel")
end

function ColorPickerDropdown:draw()
  return forward(self, "draw")
end

function ColorPickerDropdown:drawMenu()
  return forward(self, "drawMenu")
end

function ColorPickerDropdown:mousemoved(x, y)
  return forward(self, "mousemoved", x, y)
end

function ColorPickerDropdown:handleMousePressed(x, y, button)
  return forward(self, "handleMousePressed", x, y, button)
end

function ColorPickerDropdown:handleMouseReleased(x, y, button)
  return forward(self, "handleMouseReleased", x, y, button)
end

return ColorPickerDropdown
