-- ui/nametable_shape_preview.lua
-- 32x30 grayscale "shape" of a decompressed nametable page.
-- Shade = f(occurrence count): most-repeated tile ID → black; rarest → white.
-- Equal counts share one shade (no rank spread / tile-ID gradient).

local NametableUtils = require("utils.nametable_utils")

local M = {}
M.__index = M

M.W = 32
M.H = 30

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
--- Most-repeated → black (0); rarest → white (1). Same count ⇒ same shade
--- (avoids fake spatial gradients when many unique tiles are tie-broken by ID).
function M.luminanceByFrequency(nametable)
  local counts = {}
  local n = math.min(960, type(nametable) == "table" and #nametable or 0)
  for i = 1, n do
    local tile = math.floor(tonumber(nametable[i]) or 0) % 256
    counts[tile] = (counts[tile] or 0) + 1
  end

  local ranked = {}
  local maxCount, minCount = 0, nil
  for tile, count in pairs(counts) do
    ranked[#ranked + 1] = { tile = tile, count = count }
    if count > maxCount then
      maxCount = count
    end
    if minCount == nil or count < minCount then
      minCount = count
    end
  end
  table.sort(ranked, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.tile < b.tile
  end)

  minCount = minCount or 0
  local shade = {}
  local range = maxCount - minCount
  for _, entry in ipairs(ranked) do
    if range <= 0 then
      shade[entry.tile] = 0
    else
      shade[entry.tile] = (maxCount - entry.count) / range
    end
  end
  return shade, ranked
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
