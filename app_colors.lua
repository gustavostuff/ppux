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

--- Focused window / modal chrome (same accent in light and dark).
function colors:focusedChromeColor()
  return self.blue
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
