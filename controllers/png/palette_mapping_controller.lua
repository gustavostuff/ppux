local M = {}

function M.calculateLuminance(r, g, b)
  -- Simple channel average (not Rec.601). Matches sketch/CHR PNG brightness ranking.
  return ((r or 0) + (g or 0) + (b or 0)) / 3
end

function M.rgbKeyFromFloats(r, g, b)
  local r8 = math.floor((r or 0) * 255 + 0.5)
  local g8 = math.floor((g or 0) * 255 + 0.5)
  local b8 = math.floor((b or 0) * 255 + 0.5)
  return string.format("%d_%d_%d", r8, g8, b8)
end

-- Build a mapping from unique colors (sorted darkest->lightest) to brightness ranks.
-- opts.rankStart: default 0
-- opts.maxRank: default 3
-- opts.includeTransparentAsRgb: optional {r,g,b} floats (0-1). When set, fully transparent
--   pixels are counted as that RGB (default use-case: black BG / NES transparent).
-- Returns: map[key]=rank, uniqueCount
function M.buildBrightnessRankMap(imgData, opts)
  if not imgData then return {}, 0 end
  opts = opts or {}
  local rankStart = tonumber(opts.rankStart) or 0
  local maxRank = tonumber(opts.maxRank)
  if maxRank == nil then maxRank = 3 end
  local transparentAs = opts.includeTransparentAsRgb
  local transparentKey = nil
  local transparentLum = nil
  if type(transparentAs) == "table" then
    transparentKey = M.rgbKeyFromFloats(transparentAs[1], transparentAs[2], transparentAs[3])
    transparentLum = M.calculateLuminance(transparentAs[1], transparentAs[2], transparentAs[3])
  end

  local width, height = imgData:getWidth(), imgData:getHeight()
  local seen = {}
  local entries = {}

  local function addEntry(key, lum)
    if seen[key] then
      return
    end
    seen[key] = true
    entries[#entries + 1] = {
      key = key,
      lum = lum,
    }
  end

  if transparentKey then
    addEntry(transparentKey, transparentLum)
  end

  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local r, g, b, a = imgData:getPixel(x, y)
      if a > 0 then
        addEntry(M.rgbKeyFromFloats(r, g, b), M.calculateLuminance(r, g, b))
      elseif opts.treatTransparentAsBlack then
        addEntry(M.rgbKeyFromFloats(0, 0, 0), M.calculateLuminance(0, 0, 0))
      elseif transparentKey then
        -- already seeded; still mark that transparency was observed
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

local function rgbDist2(r, g, b, rgb)
  local dr = (r or 0) - (rgb[1] or 0)
  local dg = (g or 0) - (rgb[2] or 0)
  local db = (b or 0) - (rgb[3] or 0)
  return dr * dr + dg * dg + db * db
end

--- Assign each unique image color to a distinct palette slot by minimum RGB distance.
--  colorEntries: array of { key=, r=, g=, b= }
--  pixelValues: palette slot indices to use (e.g. {0,1,2,3} or {1,2,3})
--  Returns map[key]=pixelValue, or nil on failure.
function M.assignNearestPaletteIndices(colorEntries, paletteColors, pixelValues)
  if type(colorEntries) ~= "table" or type(paletteColors) ~= "table" or type(pixelValues) ~= "table" then
    return nil
  end
  local n = #colorEntries
  local m = #pixelValues
  if n == 0 then
    return {}
  end
  if n > m then
    return nil
  end
  for _, pv in ipairs(pixelValues) do
    if type(paletteColors[pv + 1]) ~= "table" then
      return nil
    end
  end

  local bestCost = math.huge
  local bestAssign = nil
  local used = {}

  local function search(ci, cost, assign)
    if cost >= bestCost then
      return
    end
    if ci > n then
      bestCost = cost
      bestAssign = {}
      for k, v in pairs(assign) do
        bestAssign[k] = v
      end
      return
    end
    local color = colorEntries[ci]
    for si = 1, m do
      if not used[si] then
        local pv = pixelValues[si]
        local d = rgbDist2(color.r, color.g, color.b, paletteColors[pv + 1])
        used[si] = true
        assign[color.key] = pv
        search(ci + 1, cost + d, assign)
        assign[color.key] = nil
        used[si] = nil
      end
    end
  end

  search(1, 0, {})
  return bestAssign
end

--- Collect unique opaque colors from ImageData as {key,r,g,b} entries (first-seen order).
function M.collectUniqueOpaqueColors(imgData)
  if not imgData then
    return {}, 0
  end
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
          entries[#entries + 1] = { key = key, r = r, g = g, b = b }
        end
      end
    end
  end
  return entries, #entries
end

return M
