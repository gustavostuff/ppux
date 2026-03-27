local colors = require("app_colors")
local BankCanvasSupport = require("controllers.chr.bank_canvas_support")
local chr       = require("chr")
local BaseItem  = require("user_interface.windows_system.generic_window_item")

local TILE_W, TILE_H = 8, 8

local Tile = setmetatable({}, { __index = BaseItem })
Tile.__index = Tile

-- Simple grayscale mapping for the CPU-side preview buffer.
-- (Actual colorization happens in the palette shader during draw.)
local function idxToRGBA(i)
  local v = (i or 0) / 3 -- 0..1
  return v, v, v, 1
end

local function offsetKey(x, y)
  return string.format("%d,%d", x, y)
end

local function getOffsetPixel(storage, x, y, fillValue)
  local value = storage and storage[offsetKey(x, y)]
  if value == nil then
    return fillValue
  end
  return value
end

local function setOffsetPixel(storage, x, y, value, fillValue)
  if not storage then return end
  local key = offsetKey(x, y)
  if value == fillValue then
    storage[key] = nil
  else
    storage[key] = value
  end
end

local function writePixelsToCHR(tile)
  if not (tile and tile._bankBytesRef and type(tile.index) == "number") then
    return
  end
  for y = 0, 7 do
    for x = 0, 7 do
      local pixelValue = tile:getPixel(x, y)
      if pixelValue then
        chr.setTilePixel(tile._bankBytesRef, tile.index, x, y, pixelValue)
      end
    end
  end
  BankCanvasSupport.invalidateTile(nil, tile._bankIndex, tile.index)
end

local function ensureImageResources(tile)
  if tile.imgData and tile.image then
    return
  end

  tile.imgData = tile.imgData or love.image.newImageData(TILE_W, TILE_H)
  tile.image = tile.image or love.graphics.newImage(tile.imgData)
  tile.image:setFilter("nearest", "nearest")
end

local function ensureOffsetStorage(tile, fillValue)
  if tile._offsetStorage then return end
  tile._offsetStorage = {}
  tile._offsetViewportX = tile._offsetViewportX or 0
  tile._offsetViewportY = tile._offsetViewportY or 0

  for y = 0, TILE_H - 1 do
    for x = 0, TILE_W - 1 do
      local idx = y * TILE_W + x + 1
      local value = tile.pixels[idx] or fillValue
      setOffsetPixel(tile._offsetStorage, x, y, value, fillValue)
    end
  end
end

local function syncVisibleWindowToStorage(tile, fillValue)
  if not tile._offsetStorage then return end
  local ox = tile._offsetViewportX or 0
  local oy = tile._offsetViewportY or 0

  for y = 0, TILE_H - 1 do
    for x = 0, TILE_W - 1 do
      local idx = y * TILE_W + x + 1
      local value = tile.pixels[idx] or fillValue
      local sx = x - ox
      local sy = y - oy
      setOffsetPixel(tile._offsetStorage, sx, sy, value, fillValue)
    end
  end
end

local function renderVisibleWindowFromStorage(tile, fillValue)
  if not tile._offsetStorage then return end
  local ox = tile._offsetViewportX or 0
  local oy = tile._offsetViewportY or 0

  for y = 0, TILE_H - 1 do
    for x = 0, TILE_W - 1 do
      local idx = y * TILE_W + x + 1
      local sx = x - ox
      local sy = y - oy
      tile.pixels[idx] = getOffsetPixel(tile._offsetStorage, sx, sy, fillValue)
    end
  end
end

----------------------------------------------------------------
-- Construction / Loading
----------------------------------------------------------------

--- Create a Tile from a CHR bank byte array and 0-based tile index.
function Tile.fromCHR(chrBankBuf, tileIndex)
  local self = BaseItem.new()
  setmetatable(self, Tile)

  self.index   = tileIndex or 0       -- 0-based within bank
  self.pixels  = {}                   -- 64 entries (row-major), values 0..3
  self.imgData = nil
  self.image   = nil
  self._imageDirty = true

  self:loadFromCHR(chrBankBuf, self.index)
  return self
end

--- (Re)load pixel data from CHR for this tile index.
function Tile:loadFromCHR(chrBankBuf, tileIndex)
  tileIndex = tileIndex or self.index
  local pixels, err = chr.decodeTile(chrBankBuf, tileIndex)
  if not pixels then
    self.error = err or "decode-failed"
    return
  end
  self.index  = tileIndex
  self.pixels = pixels
  self._imageDirty = true
  if self.image then
    self:refreshImage()
  end
  self._offsetStorage = nil
  self._offsetViewportX = 0
  self._offsetViewportY = 0
  self.error = nil
end

----------------------------------------------------------------
-- Pixel access / mutation
----------------------------------------------------------------

--- Get palette index (0..3) at x,y (0..7)
function Tile:getPixel(x, y)
  if x < 0 or x >= TILE_W or y < 0 or y >= TILE_H then return nil end
  return self.pixels[y * TILE_W + x + 1]
end

--- Set palette index and update the GPU image.
function Tile:edit(x, y, color)
  if x < 0 or x >= TILE_W or y < 0 or y >= TILE_H then return end
  local i = y * TILE_W + x + 1
  self.pixels[i] = color or 0
  if self._offsetStorage then
    local ox = self._offsetViewportX or 0
    local oy = self._offsetViewportY or 0
    setOffsetPixel(self._offsetStorage, x - ox, y - oy, self.pixels[i], 0)
  end
  if self.image and self.imgData then
    self.imgData:setPixel(x, y, idxToRGBA(self.pixels[i]))
    self.image:replacePixels(self.imgData)
    self._imageDirty = false
  else
    self._imageDirty = true
  end
end

--- Bulk refresh the CPU/GPU images from self.pixels.
function Tile:refreshImage()
  ensureImageResources(self)
  local k = 1
  self.imgData:mapPixel(function(x, y, r, g, b, a)
    local v = self.pixels[k] or 0
    k = k + 1
    return idxToRGBA(v)
  end)
  self.image:replacePixels(self.imgData)
  self._imageDirty = false
end

--- Rotate palette values in all pixels by +1 (right) or -1 (left).
-- direction: 1 for right (0->1, 1->2, 2->3, 3->0), -1 for left (0->3, 1->0, 2->1, 3->2)
-- Returns true if rotation was applied, false if no valid tile
function Tile:rotatePaletteValues(direction)
  if not self.pixels or #self.pixels ~= 64 then return false end
  
  direction = (direction > 0) and 1 or -1  -- Normalize to +1 or -1
  
  -- Rotate all pixel values
  for i = 1, 64 do
    local oldValue = self.pixels[i] or 0
    local newValue
    if direction == 1 then
      -- Right: 0->1, 1->2, 2->3, 3->0
      newValue = (oldValue + 1) % 4
    else
      -- Left: 0->3, 1->0, 2->1, 3->2
      newValue = (oldValue - 1 + 4) % 4
    end
    self.pixels[i] = newValue
  end
  
  -- Update visual representation
  self:refreshImage()
  syncVisibleWindowToStorage(self, 0)

  writePixelsToCHR(self)

  return true
end

--- Offset tile pixels by dx, dy.
-- Defaults to non-wrapping behavior with hidden offscreen preservation:
-- pixels outside the 8x8 viewport are kept and can reappear when offsetting back.
-- Set opts.wrap = true to wrap pixels around tile edges.
-- Returns true if offset was applied, false if no valid tile.
function Tile:offsetPixels(dx, dy, opts)
  if not self.pixels or #self.pixels ~= 64 then return false end

  opts = opts or {}
  local wrap = opts.wrap == true
  local fillValue = math.floor(tonumber(opts.fillValue) or 0)
  if fillValue < 0 then fillValue = 0 end
  if fillValue > 3 then fillValue = 3 end

  dx = math.floor(tonumber(dx) or 0)
  dy = math.floor(tonumber(dy) or 0)

  if dx == 0 and dy == 0 then
    return true
  end

  if wrap then
    local source = self.pixels
    local shifted = {}

    for y = 0, TILE_H - 1 do
      for x = 0, TILE_W - 1 do
        local sx = ((x - dx) % TILE_W + TILE_W) % TILE_W
        local sy = ((y - dy) % TILE_H + TILE_H) % TILE_H
        shifted[y * TILE_W + x + 1] = source[sy * TILE_W + sx + 1] or fillValue
      end
    end

    for i = 1, TILE_W * TILE_H do
      self.pixels[i] = shifted[i]
    end

    self._offsetStorage = nil
    self._offsetViewportX = 0
    self._offsetViewportY = 0
  else
    ensureOffsetStorage(self, fillValue)
    syncVisibleWindowToStorage(self, fillValue)

    self._offsetViewportX = (self._offsetViewportX or 0) + dx
    self._offsetViewportY = (self._offsetViewportY or 0) + dy

    renderVisibleWindowFromStorage(self, fillValue)
  end

  self:refreshImage()
  writePixelsToCHR(self)
  
  return true
end

--- Swap pixel data with another tile (copy by value).
-- This swaps the pixel patterns but keeps the tile references intact.
-- Returns true if swap was successful, false otherwise
function Tile:swapPixelsWith(otherTile)
  if not self.pixels or #self.pixels ~= 64 then return false end
  if not otherTile or not otherTile.pixels or #otherTile.pixels ~= 64 then return false end
  
  -- Swap pixel arrays (copy by value)
  local tempPixels = {}
  for i = 1, 64 do
    tempPixels[i] = self.pixels[i]
    self.pixels[i] = otherTile.pixels[i]
    otherTile.pixels[i] = tempPixels[i]
  end
  
  -- Update visual representation for both tiles
  self:refreshImage()
  otherTile:refreshImage()
  syncVisibleWindowToStorage(self, 0)
  syncVisibleWindowToStorage(otherTile, 0)

  writePixelsToCHR(self)
  writePixelsToCHR(otherTile)
  
  return true
end

----------------------------------------------------------------
-- Draw
----------------------------------------------------------------

--- Draw the tile at (x,y). Accepts either a uniform scale or sx,sy.
-- Usage:
--   tile:draw(x, y)           -- scale = 1
--   tile:draw(x, y, 2)        -- uniform scale
--   tile:draw(x, y, 2, 3)     -- non-uniform (sx=2, sy=3)
function Tile:draw(x, y, scale_or_sx, sy)
  if not self.image or self._imageDirty then
    self:refreshImage()
  end

  local sx, sy2
  if sy ~= nil then
    sx, sy2 = scale_or_sx or 1, sy or 1
  else
    sx = scale_or_sx or 1
    sy2 = sx
  end

  -- Ensure crisp pixels even if someone rebuilt the Image elsewhere.
  self.image:setFilter("nearest", "nearest")

  love.graphics.setColor(colors.white)
  love.graphics.draw(self.image, x, y, 0, sx, sy2)
end

return Tile
