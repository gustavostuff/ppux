local colors = {
  black = "000000",
  white = "FFFFFF",
  gray10 = "222222",
  gray20 = "333333",
  gray50 = "808080",
  gray75 = "BFBFBF",
  red = "d95763",
  green = "37946e",
  blue = "5b6ee1",
  lightBlue = "8895e1",
  yellow = "fbf236",
  tooltipBg = "fff7c6",
}

local function copyColor(c)
  return { c[1], c[2], c[3], c[4] }
end

-- transform to RGb, 0-1 based:
for k, v in pairs(colors) do
  colors[k] = {
    tonumber("0x" .. v:sub(1, 2)) / 255,
    tonumber("0x" .. v:sub(3, 4)) / 255,
    tonumber("0x" .. v:sub(5, 6)) / 255,
  }
end

local _baseGray10 = copyColor(colors.gray10)
local _baseGray20 = copyColor(colors.gray20)
local _baseGray50 = copyColor(colors.gray50)
local _baseGray75 = copyColor(colors.gray75)
local _baseWhite = copyColor(colors.white)
local _baseBlack = copyColor(colors.black)

--- Default appearance chrome (hex, no #). Used as fallback when a slot is missing from settings.
local defaultAppColors = {
  dark_background = "3E4453",
  light_background = "ACB1C1",
  dark_focused = "242424",
  light_focused = "DBDBDB",
  dark_non_focused = "494949",
  light_non_focused = "929292",
  dark_text_icons_focused = "FFFFFF",
  light_text_icons_focused = "494949",
  dark_text_icons_non_focused = "B6B6B6",
  light_text_icons_non_focused = "242424",
}

local function hex6ToRgb01(hex)
  local s = tostring(hex or ""):gsub("^#", ""):upper()
  if #s ~= 6 then
    return nil
  end
  local r = tonumber(s:sub(1, 2), 16)
  local g = tonumber(s:sub(3, 4), 16)
  local b = tonumber(s:sub(5, 6), 16)
  if not (r and g and b) then
    return nil
  end
  return { r / 255, g / 255, b / 255 }
end

colors.defaultAppColors = defaultAppColors

function colors.defaultAppearanceChromeAsRgb()
  local out = {}
  for slotId, hex in pairs(defaultAppColors) do
    local rgb = hex6ToRgb01(hex)
    if rgb then
      out[slotId] = { rgb[1], rgb[2], rgb[3] }
    end
  end
  return out
end

function colors:withBrightness(key, brightness)
  return {
    self[key][1] * brightness,
    self[key][2] * brightness,
    self[key][3] * brightness,
  }
end

function colors:getTheme()
  return self._themeKey or "dark"
end

colors._appearanceChromeOverrides = {}

local function clampCh(x)
  if type(x) ~= "number" then return nil end
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

function colors:_appearanceChromeBuiltinDefault(slotId)
  local hex = defaultAppColors[slotId]
  local rgb = hex and hex6ToRgb01(hex)
  if rgb then
    return copyColor(rgb)
  end
  rgb = hex6ToRgb01(defaultAppColors.dark_background)
  if rgb then
    return copyColor(rgb)
  end
  return copyColor(_baseGray10)
end

function colors:appearanceChromeResolved(slotId)
  if slotId == "dark_text_icons" then
    slotId = "dark_text_icons_focused"
  elseif slotId == "light_text_icons" then
    slotId = "light_text_icons_focused"
  end
  local o = self._appearanceChromeOverrides[slotId]
  if type(o) == "table" then
    local r = clampCh(tonumber(o[1] ~= nil and o[1] or o.r))
    local g = clampCh(tonumber(o[2] ~= nil and o[2] or o.g))
    local b = clampCh(tonumber(o[3] ~= nil and o[3] or o.b))
    if r and g and b then
      return { r, g, b }
    end
  end
  return self:_appearanceChromeBuiltinDefault(slotId)
end

--- Focused chrome fill (window header/border when focused, modals, toolbars).
function colors:focusedChromeColor()
  local prefix = (self:getTheme() == "light") and "light" or "dark"
  return copyColor(self:appearanceChromeResolved(prefix .. "_focused"))
end

--- Unfocused window chrome background (replaces plain gray20 for headers/borders).
function colors:chromeBackgroundUnfocused()
  local prefix = (self:getTheme() == "light") and "light" or "dark"
  return copyColor(self:appearanceChromeResolved(prefix .. "_non_focused"))
end

--- Strong chrome ink (window title when focused, modal title, hover on global chrome UI).
function colors:chromeTextIconsColorFocused()
  local prefix = (self:getTheme() == "light") and "light" or "dark"
  return copyColor(self:appearanceChromeResolved(prefix .. "_text_icons_focused"))
end

--- Muted chrome ink (taskbar, toolbars, menus by default; unfocused window titles).
function colors:chromeTextIconsColorNonFocused()
  local prefix = (self:getTheme() == "light") and "light" or "dark"
  return copyColor(self:appearanceChromeResolved(prefix .. "_text_icons_non_focused"))
end

--- Backward-compatible alias for chromeTextIconsColorFocused().
function colors:chromeTextIconsColor()
  return self:chromeTextIconsColorFocused()
end

--- Main workspace fill behind windows (per UI theme: dark vs light slot).
function colors:appWorkspaceFill()
  local prefix = (self:getTheme() == "light") and "light" or "dark"
  return copyColor(self:appearanceChromeResolved(prefix .. "_background"))
end

function colors:syncLoveGraphicsBackground()
  if not (love and love.graphics and love.graphics.setBackgroundColor) then
    return
  end
  local c = self:appWorkspaceFill()
  love.graphics.setBackgroundColor(c[1], c[2], c[3])
end

function colors:setAppearanceChromeOverrides(table)
  self._appearanceChromeOverrides = {}
  if type(table) ~= "table" then
    return
  end
  for slotId, o in pairs(table) do
    if type(o) == "table" and type(slotId) == "string" then
      local r = clampCh(tonumber(o[1] ~= nil and o[1] or o.r))
      local g = clampCh(tonumber(o[2] ~= nil and o[2] or o.g))
      local b = clampCh(tonumber(o[3] ~= nil and o[3] or o.b))
      if r and g and b then
        self._appearanceChromeOverrides[slotId] = { r, g, b }
      end
    end
  end
end

function colors:setAppearanceChromeOverride(slotId, rgb)
  if type(slotId) ~= "string" or type(rgb) ~= "table" then
    return
  end
  local r = clampCh(tonumber(rgb.r or rgb[1]))
  local g = clampCh(tonumber(rgb.g or rgb[2]))
  local b = clampCh(tonumber(rgb.b or rgb[3]))
  if not (r and g and b) then
    return
  end
  self._appearanceChromeOverrides[slotId] = { r, g, b }
end

function colors:getAppearanceChromeOverridesForSave()
  local out = {}
  for k, v in pairs(self._appearanceChromeOverrides) do
    if type(v) == "table" then
      local r, g, b = tonumber(v[1]), tonumber(v[2]), tonumber(v[3])
      if r and g and b then
        out[k] = { r, g, b }
      end
    end
  end
  return out
end

function colors:setTheme(themeKey)
  local key = (themeKey == "light") and "light" or "dark"
  self._themeKey = key

  if key == "light" then
    self.gray10 = copyColor(_baseGray50)
    self.gray20 = copyColor(_baseGray75)
    -- Text/icons must use the *base* palette grays, not the remapped surface
    -- slots above (those are intentionally lighter for chrome/backgrounds).
    self.textPrimary = copyColor(_baseGray20)
    self.iconPrimary = copyColor(_baseBlack)
  else
    self.gray10 = copyColor(_baseGray10)
    self.gray20 = copyColor(_baseGray20)
    self.textPrimary = copyColor(_baseGray75)
    self.iconPrimary = copyColor(_baseGray75)
  end
end

colors.transparent = {0, 0, 0, 0}
colors:setTheme("dark")

return colors
