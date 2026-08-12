-- ui/nametable_shape_preview.lua
-- Standalone 32x30 grayscale "shape" of a decompressed nametable page.
-- Shade = f(occurrence count): most-repeated tile ID → black; rarest → white.
-- Equal counts share one shade. Distinct frequency levels are ranked (not raw
-- count span), so mid-frequency tiles stay gray even with a dominant background.
-- Luminance is quantized to 5 discrete grays (incl. black and white).

local NametableUtils = require("utils.nametable_utils")

local M = {}
M.__index = M

M.W = 32
M.H = 30

-- Black, three mid grays, white.
local GRAY_SHADES = { 0, 0.25, 0.5, 0.75, 1 }

local function quantizeToGrayShade(lum)
  lum = tonumber(lum) or 0
  if lum < 0 then lum = 0 end
  if lum > 1 then lum = 1 end
  local i = math.floor(lum * (#GRAY_SHADES - 1) + 0.5) + 1
  return GRAY_SHADES[i]
end

local function sliceRomBytes(romRaw, startAddr, endAddr)
  local out = {}
  startAddr = math.floor(tonumber(startAddr) or 0)
  endAddr = math.floor(tonumber(endAddr) or startAddr)
  if type(romRaw) ~= "string" or startAddr < 0 or endAddr < startAddr then
    return out
  end
  local len = #romRaw
  for addr = startAddr, endAddr do
    if addr >= len then
      break
    end
    out[#out + 1] = string.byte(romRaw, addr + 1) or 0
  end
  return out
end

--- Map each tile ID to luminance 0..1 from occurrence count.
--- Most-repeated → black (0); rarest → white (1). Same count ⇒ same shade.
--- Shade steps are ranked by *distinct frequency levels* (not raw count span),
--- so a tile that appears ~30× stays mid-gray even when a background tile
--- dominates hundreds of cells. Output uses only the five GRAY_SHADES values.
function M.luminanceByFrequency(nametable)
  local counts = {}
  local n = math.min(960, type(nametable) == "table" and #nametable or 0)
  for i = 1, n do
    local tile = math.floor(tonumber(nametable[i]) or 0) % 256
    counts[tile] = (counts[tile] or 0) + 1
  end

  -- Unique count values, descending (most frequent first).
  local countSeen = {}
  local distinctCounts = {}
  for _, count in pairs(counts) do
    if not countSeen[count] then
      countSeen[count] = true
      distinctCounts[#distinctCounts + 1] = count
    end
  end
  table.sort(distinctCounts, function(a, b)
    return a > b
  end)

  local rankByCount = {}
  for rank, count in ipairs(distinctCounts) do
    rankByCount[count] = rank
  end

  local levels = #distinctCounts
  local shade = {}
  for tile, count in pairs(counts) do
    local rank = rankByCount[count] or levels
    local lum
    if levels <= 1 then
      lum = 0
    else
      lum = (rank - 1) / (levels - 1)
    end
    shade[tile] = quantizeToGrayShade(lum)
  end
  return shade, distinctCounts
end

--- Build 32x30 flat luminance samples (row-major) from nametable bytes.
function M.buildLuminanceGrid(nametable)
  local shade = M.luminanceByFrequency(nametable)
  local grid = {}
  for row = 0, M.H - 1 do
    for col = 0, M.W - 1 do
      local idx = row * M.W + col + 1
      local tile = math.floor(tonumber(nametable and nametable[idx]) or 0) % 256
      grid[idx] = shade[tile] or 1
    end
  end
  return grid
end

function M.new()
  return setmetatable({
    x = 0,
    y = 0,
    w = M.W,
    h = M.H,
    _imgData = nil,
    _image = nil,
    _active = false,
  }, M)
end

function M:setPosition(x, y)
  self.x = math.floor(tonumber(x) or 0)
  self.y = math.floor(tonumber(y) or 0)
end

function M:setSize(w, h)
  -- Fixed native pixel size; panel may pass larger cells — keep 32x30 draw size.
  if type(w) == "number" then self.w = M.W end
  if type(h) == "number" then self.h = M.H end
end

function M:getWidth()
  return M.W
end

function M:getHeight()
  return M.H
end

function M:preferredHeight()
  return M.H
end

function M:contains(px, py)
  return px >= self.x and px < self.x + M.W
    and py >= self.y and py < self.y + M.H
end

function M:clear()
  self._active = false
  self._imgData = nil
  self._image = nil
end

function M:_ensureImage()
  if not (love and love.image and love.image.newImageData) then
    return false
  end
  if not self._imgData then
    self._imgData = love.image.newImageData(M.W, M.H)
  end
  if not self._image and love.graphics and love.graphics.newImage then
    self._image = love.graphics.newImage(self._imgData)
    if self._image.setFilter then
      self._image:setFilter("nearest", "nearest")
    end
  end
  return self._imgData ~= nil and self._image ~= nil
end

--- Decode rom slice and refresh the 32x30 shape image.
function M:setFromStream(romRaw, startAddr, endAddr, codec)
  local data = sliceRomBytes(romRaw, startAddr, endAddr)
  if #data < 2 then
    self:clear()
    return false
  end
  local nt = NametableUtils.decode_compressed_nametable(data, false, codec or "konami")
  if type(nt) ~= "table" or #nt < 960 then
    self:clear()
    return false
  end
  return self:setFromNametable(nt)
end

function M:setFromNametable(nametable)
  if not self:_ensureImage() then
    -- Headless / tests: still mark active if we can build the grid.
    local grid = M.buildLuminanceGrid(nametable)
    self._grid = grid
    self._active = true
    return true
  end

  local grid = M.buildLuminanceGrid(nametable)
  self._grid = grid
  for row = 0, M.H - 1 do
    for col = 0, M.W - 1 do
      local lum = grid[row * M.W + col + 1] or 1
      self._imgData:setPixel(col, row, lum, lum, lum, 1)
    end
  end
  if self._image.replacePixels then
    self._image:replacePixels(self._imgData)
  else
    self._image = love.graphics.newImage(self._imgData)
    if self._image.setFilter then
      self._image:setFilter("nearest", "nearest")
    end
  end
  self._active = true
  return true
end

function M:isActive()
  return self._active == true
end

function M:draw()
  if not self._active or not self._image then
    return
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self._image, self.x, self.y)
end

return M
