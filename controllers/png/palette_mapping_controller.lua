local M = {}

function M.calculateLuminance(r, g, b)
  return 0.299 * (r or 0) + 0.587 * (g or 0) + 0.114 * (b or 0)
end

function M.rgbKeyFromFloats(r, g, b)
  local r8 = math.floor((r or 0) * 255 + 0.5)
  local g8 = math.floor((g or 0) * 255 + 0.5)
  local b8 = math.floor((b or 0) * 255 + 0.5)
  return string.format("%d_%d_%d", r8, g8, b8)
end

-- Build a mapping from unique opaque colors (sorted darkest->lightest) to brightness ranks.
-- opts.rankStart: default 0
-- opts.maxRank: default 3
-- Returns: map[key]=rank, uniqueCount
function M.buildBrightnessRankMap(imgData, opts)
  if not imgData then return {}, 0 end
  opts = opts or {}
  local rankStart = tonumber(opts.rankStart) or 0
  local maxRank = tonumber(opts.maxRank)
  if maxRank == nil then maxRank = 3 end

  local width, height = imgData:getWidth(), imgData:getHeight()
  local seen = {}
  local entries = {}

  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local r, g, b, a = imgData:getPixel(x, y)
      if a > 0 then
        local key = M.rgbKeyFromFloats(r, g, b)
        if not seen[key] then
          seen[key] = true
          entries[#entries + 1] = {
            key = key,
            lum = M.calculateLuminance(r, g, b),
          }
        end
      end
    end
  end

  table.sort(entries, function(a, b)
    if a.lum == b.lum then
      return a.key < b.key
    end
    return a.lum < b.lum
  end)

  local map = {}
  for i, entry in ipairs(entries) do
    local rank = rankStart + (i - 1)
    if rank > maxRank then rank = maxRank end
    map[entry.key] = rank
  end

  return map, #entries
end

-- Build a remap from brightness rank -> pixel value, based on luminance order of palette colors.
-- opts.pixelValues: array of palette slot indices to consider (default {0,1,2,3})
-- opts.rankStart: rank key to start assigning from (default 0)
function M.buildPaletteBrightnessRemap(paletteColors, opts)
  if type(paletteColors) ~= "table" then
    return nil
  end
  opts = opts or {}
  local pixelValues = opts.pixelValues or { 0, 1, 2, 3 }
  local rankStart = tonumber(opts.rankStart) or 0

  local entries = {}
  for _, pixelValue in ipairs(pixelValues) do
    local rgb = paletteColors[pixelValue + 1]
    if type(rgb) ~= "table" then
      return nil
    end
    entries[#entries + 1] = {
      pixelValue = pixelValue,
      lum = M.calculateLuminance(rgb[1], rgb[2], rgb[3]),
    }
  end

  table.sort(entries, function(a, b)
    if a.lum == b.lum then
      return a.pixelValue < b.pixelValue
    end
    return a.lum < b.lum
  end)

  local remap = {}
  for i, entry in ipairs(entries) do
    remap[rankStart + (i - 1)] = entry.pixelValue
  end
  return remap
end

function M.imageHasTransparency(imgData)
  if not imgData then return false end
  local width, height = imgData:getWidth(), imgData:getHeight()
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local _, _, _, a = imgData:getPixel(x, y)
      if a == 0 then
        return true
      end
    end
  end
  return false
end

return M
