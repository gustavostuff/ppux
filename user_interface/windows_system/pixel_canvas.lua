local chr = require("chr")

local PixelCanvas = {}
PixelCanvas.__index = PixelCanvas

local function idxToRGBA(i)
  local v = (i or 0) / 3
  return v, v, v, 1
end

function PixelCanvas.new(width, height, fillValue)
  local self = setmetatable({}, PixelCanvas)
  self.width = math.max(1, math.floor(tonumber(width) or 1))
  self.height = math.max(1, math.floor(tonumber(height) or 1))
  self.fillValue = math.max(0, math.min(3, math.floor(tonumber(fillValue) or 0)))
  self.pixels = {}
  self.imgData = nil
  self.image = nil
  self._imageDirty = true

  local count = self.width * self.height
  for i = 1, count do
    self.pixels[i] = self.fillValue
  end

  return self
end

function PixelCanvas:clone()
  local other = PixelCanvas.new(self.width, self.height, self.fillValue)
  for i = 1, #self.pixels do
    other.pixels[i] = self.pixels[i]
  end
  other._imageDirty = true
  return other
end

function PixelCanvas:clear(fillValue)
  local value = fillValue
  if value == nil then
    value = self.fillValue
  end
  value = math.max(0, math.min(3, math.floor(tonumber(value) or 0)))
  self.fillValue = value
  for i = 1, #self.pixels do
    self.pixels[i] = value
  end
  self._imageDirty = true
  if self.imgData and self.image then
    self:refreshImage()
  end
end

function PixelCanvas:getPixel(x, y)
  x = math.floor(tonumber(x) or -1)
  y = math.floor(tonumber(y) or -1)
  if x < 0 or y < 0 or x >= self.width or y >= self.height then
    return nil
  end
  return self.pixels[y * self.width + x + 1]
end

function PixelCanvas:edit(x, y, color)
  x = math.floor(tonumber(x) or -1)
  y = math.floor(tonumber(y) or -1)
  if x < 0 or y < 0 or x >= self.width or y >= self.height then
    return false
  end

  local value = math.max(0, math.min(3, math.floor(tonumber(color) or 0)))
  local idx = y * self.width + x + 1
  if self.pixels[idx] == value then
    return false
  end

  self.pixels[idx] = value
  if self.imgData and self.image then
    self.imgData:setPixel(x, y, idxToRGBA(value))
    self.image:replacePixels(self.imgData)
    self._imageDirty = false
  else
    self._imageDirty = true
  end
  return true
end

function PixelCanvas:ensureImage()
  if self.imgData and self.image then
    return
  end

  self.imgData = love.image.newImageData(self.width, self.height)
  self.image = love.graphics.newImage(self.imgData)
  self.image:setFilter("nearest", "nearest")
  self._imageDirty = true
end

function PixelCanvas:refreshImage()
  self:ensureImage()
  local k = 1
  self.imgData:mapPixel(function()
    local v = self.pixels[k] or self.fillValue
    k = k + 1
    return idxToRGBA(v)
  end)
  self.image:replacePixels(self.imgData)
  self._imageDirty = false
end

function PixelCanvas:draw(x, y, scale)
  self:ensureImage()
  if self._imageDirty then
    self:refreshImage()
  end
  love.graphics.draw(self.image, math.floor(x or 0), math.floor(y or 0), 0, scale or 1, scale or 1)
end

function PixelCanvas:extractTilePixels(tileX, tileY, tileH)
  local out = {}
  tileX = math.floor(tonumber(tileX) or 0)
  tileY = math.floor(tonumber(tileY) or 0)
  tileH = math.max(1, math.floor(tonumber(tileH) or 8))
  for y = 0, tileH - 1 do
    for x = 0, 7 do
      out[#out + 1] = self:getPixel(tileX + x, tileY + y) or self.fillValue
    end
  end
  return out
end

function PixelCanvas:loadTilePixels(tileX, tileY, pixels, tileH)
  tileX = math.floor(tonumber(tileX) or 0)
  tileY = math.floor(tonumber(tileY) or 0)
  tileH = math.max(1, math.floor(tonumber(tileH) or 8))
  local idx = 1
  for y = 0, tileH - 1 do
    for x = 0, 7 do
      self:edit(tileX + x, tileY + y, pixels[idx] or self.fillValue)
      idx = idx + 1
    end
  end
end

function PixelCanvas:loadCHRTileAt(tileX, tileY, chrBytes, tileIndex)
  local pixels, err = chr.decodeTile(chrBytes, tileIndex)
  if not pixels then
    return false, err
  end
  self:loadTilePixels(tileX, tileY, pixels, 8)
  return true
end

return PixelCanvas
