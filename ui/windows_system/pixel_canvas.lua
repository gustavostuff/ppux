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

--- Draw a single tile-sized region (pixel coords) with the current shader/color.
--- Reuses one Quad on the canvas to avoid per-tile allocations.
function PixelCanvas:drawRegion(destX, destY, srcX, srcY, srcW, srcH, scale)
  self:ensureImage()
  if self._imageDirty then
    self:refreshImage()
  end
  scale = scale or 1
  srcX = math.floor(tonumber(srcX) or 0)
  srcY = math.floor(tonumber(srcY) or 0)
  srcW = math.floor(tonumber(srcW) or 8)
  srcH = math.floor(tonumber(srcH) or 8)
  if not self._drawQuad then
    self._drawQuad = love.graphics.newQuad(srcX, srcY, srcW, srcH, self.width, self.height)
  else
    self._drawQuad:setViewport(srcX, srcY, srcW, srcH, self.width, self.height)
  end
  love.graphics.draw(
    self.image,
    self._drawQuad,
    math.floor(destX or 0),
    math.floor(destY or 0),
    0,
    scale,
    scale
  )
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
  local any = false
  for y = 0, tileH - 1 do
    for x = 0, 7 do
      local px = tileX + x
      local py = tileY + y
      if px >= 0 and py >= 0 and px < self.width and py < self.height then
        local value = math.max(0, math.min(3, math.floor(tonumber(pixels[idx]) or self.fillValue or 0)))
        local pidx = py * self.width + px + 1
        if self.pixels[pidx] ~= value then
          self.pixels[pidx] = value
          any = true
        end
      end
      idx = idx + 1
    end
  end
  -- Defer ImageData upload to refreshImage/draw (avoid per-pixel replacePixels).
  if any then
    self._imageDirty = true
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

--- Extract an axis-aligned region into a new PixelCanvas (clamped to bounds).
--- @return PixelCanvas|nil, x, y, w, h  (origin may be clamped)
function PixelCanvas:extractRect(x, y, w, h)
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  w = math.floor(tonumber(w) or 0)
  h = math.floor(tonumber(h) or 0)
  if w < 1 or h < 1 then
    return nil
  end
  local x2 = x + w - 1
  local y2 = y + h - 1
  if x < 0 then x = 0 end
  if y < 0 then y = 0 end
  if x2 >= self.width then x2 = self.width - 1 end
  if y2 >= self.height then y2 = self.height - 1 end
  local rw = x2 - x + 1
  local rh = y2 - y + 1
  if rw < 1 or rh < 1 then
    return nil
  end
  local out = PixelCanvas.new(rw, rh, self.fillValue)
  for py = 0, rh - 1 do
    for px = 0, rw - 1 do
      out.pixels[py * rw + px + 1] = self:getPixel(x + px, y + py) or self.fillValue
    end
  end
  out._imageDirty = true
  return out, x, y, rw, rh
end

--- Write a flat pixel array or PixelCanvas into this canvas at (destX, destY).
--- @param source PixelCanvas|table  canvas or 1-based flat array with sourceW/sourceH
function PixelCanvas:loadRect(destX, destY, source, sourceW, sourceH)
  destX = math.floor(tonumber(destX) or 0)
  destY = math.floor(tonumber(destY) or 0)
  local sw, sh, get
  if type(source) == "table" and source.pixels and source.width and source.height then
    sw = source.width
    sh = source.height
    get = function(px, py)
      return source.pixels[py * sw + px + 1]
    end
  else
    sw = math.floor(tonumber(sourceW) or 0)
    sh = math.floor(tonumber(sourceH) or 0)
    get = function(px, py)
      return source[py * sw + px + 1]
    end
  end
  if sw < 1 or sh < 1 then
    return false
  end
  local any = false
  for py = 0, sh - 1 do
    for px = 0, sw - 1 do
      if self:edit(destX + px, destY + py, get(px, py) or self.fillValue) then
        any = true
      end
    end
  end
  return any
end

--- Fill an axis-aligned region with a constant value (clamped).
function PixelCanvas:fillRect(x, y, w, h, value)
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  w = math.floor(tonumber(w) or 0)
  h = math.floor(tonumber(h) or 0)
  value = math.max(0, math.min(3, math.floor(tonumber(value) or self.fillValue or 0)))
  if w < 1 or h < 1 then
    return false
  end
  local any = false
  for py = y, y + h - 1 do
    for px = x, x + w - 1 do
      if self:edit(px, py, value) then
        any = true
      end
    end
  end
  return any
end

return PixelCanvas
