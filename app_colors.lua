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
  yellow = "fbf236",
  tooltipBg = "fff7c6",
}

-- transform to RGb, 0-1 based:
for k, v in pairs(colors) do
  colors[k] = {
    tonumber("0x" .. v:sub(1, 2)) / 255,
    tonumber("0x" .. v:sub(3, 4)) / 255,
    tonumber("0x" .. v:sub(5, 6)) / 255,
  }
end

function colors:withBrightness(key, brightness)
  return {
    self[key][1] * brightness,
    self[key][2] * brightness,
    self[key][3] * brightness,
  }
end

colors.transparent = {0, 0, 0, 0}

return colors
