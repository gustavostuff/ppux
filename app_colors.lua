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

-- #5b6ee1 — default dark focused window chrome (light focused chrome builtin is white; see _appearanceChromeBuiltinDefault).
local _CHROME_FOCUSED_DEFAULT = copyColor(colors.blue)

local _baseGray10 = copyColor(colors.gray10)
local _baseGray20 = copyColor(colors.gray20)
local _baseGray50 = copyColor(colors.gray50)
local _baseGray75 = copyColor(colors.gray75)
local _baseWhite = copyColor(colors.white)
local _baseBlack = copyColor(colors.black)

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
  -- Defaults match curated appearanceChrome from in-app Colors settings (0–1 RGB).
  if slotId == "dark_background" then
    return { 0.24489795918367, 0.26530612244898, 0.3265306122449 }
  end
  if slotId == "light_background" then
    return { 0.71428571428571, 0.71428571428571, 0.71428571428571 }
  end
  if slotId == "dark_focused" then
    return copyColor(_CHROME_FOCUSED_DEFAULT)
  end
  if slotId == "light_focused" then
    return { 1, 1, 1 }
  end
  if slotId == "dark_non_focused" then
    return { 0.42857142857143, 0.42857142857143, 0.42857142857143 }
  end
  if slotId == "light_non_focused" then
    return { 0.85714285714286, 0.85714285714286, 0.85714285714286 }
  end
  if slotId == "dark_text_icons_focused" then
    return copyColor(self.white)
  end
  if slotId == "dark_text_icons_non_focused" then
    return { 0.71428571428571, 0.71428571428571, 0.71428571428571 }
  end
  if slotId == "light_text_icons_focused" then
    return { 0.28571428571429, 0.28571428571429, 0.28571428571429 }
  end
  if slotId == "light_text_icons_non_focused" then
    return { 0.42857142857143, 0.42857142857143, 0.42857142857143 }
  end
  return copyColor(_CHROME_FOCUSED_DEFAULT)
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
