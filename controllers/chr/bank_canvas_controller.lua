local chr = require("chr")
local CanvasSpace = require("utils.canvas_space")
local DebugController = require("controllers.dev.debug_controller")

local M = {}
M.__index = M

local BANK_TILE_COLS = 16
local BANK_TILE_COUNT = 512
local TILE_SIZE = 8
local BANK_PIXEL_W = BANK_TILE_COLS * TILE_SIZE
local BANK_TILE_ROWS = BANK_TILE_COUNT / BANK_TILE_COLS
local BANK_PIXEL_H = BANK_TILE_ROWS * TILE_SIZE

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function idxToGray(value)
  return (tonumber(value) or 0) / 3
end

local function mapIndexForOrder(orderMode, pos)
  if orderMode == "normal" then
    return pos
  end
  local row = math.floor(pos / BANK_TILE_COLS)
  local col = pos % BANK_TILE_COLS
  local pair = math.floor(row / 2)
  local isOdd = (row % 2 == 1)
  return pair * 32 + col * 2 + (isOdd and 1 or 0)
end

local function mapPosForTileIndex(orderMode, tileIndex)
  if orderMode == "normal" then
    return tileIndex
  end

  local pair = math.floor(tileIndex / 32)
  local withinPair = tileIndex % 32
  local col = math.floor(withinPair / 2)
  local isOdd = (withinPair % 2) == 1
  local row = pair * 2 + (isOdd and 1 or 0)
  return row * BANK_TILE_COLS + col
end

local function newImageData()
  local imageData = love.image.newImageData(BANK_PIXEL_W, BANK_PIXEL_H)
  imageData:mapPixel(function()
    return 0, 0, 0, 1
  end)
  return imageData
end

function M.new()
  local self = setmetatable({}, M)
  self.currentBank = nil
  self.currentOrderMode = "normal"
  self.dirtyBanks = {}
  self.dirtyTiles = {}
  self.imageData = newImageData()
  self.image = love.graphics.newImage(self.imageData)
  self.image:setFilter("nearest", "nearest")
  self.canvas = love.graphics.newCanvas(BANK_PIXEL_W, BANK_PIXEL_H)
  self.canvas:setFilter("nearest", "nearest")
  self.tileQuad = love.graphics.newQuad(0, 0, TILE_SIZE, TILE_SIZE, BANK_PIXEL_W, BANK_PIXEL_H)
  self._canvasDirty = true
  self._fullRepaintNeeded = true
  return self
end

function M:getCanvasSize()
  return BANK_PIXEL_W, BANK_PIXEL_H
end

function M:invalidateBank(bankIdx)
  local bank = math.floor(tonumber(bankIdx) or -1)
  if bank < 1 then return end
  DebugController.perfIncrement("chr_canvas_invalidate_bank")
  self.dirtyBanks[bank] = true
  self.dirtyTiles[bank] = nil
  if self.currentBank == bank then
    self._canvasDirty = true
    self._fullRepaintNeeded = true
  end
end

function M:invalidateTile(bankIdx, tileIndex)
  local bank = math.floor(tonumber(bankIdx) or -1)
  local idx = math.floor(tonumber(tileIndex) or -1)
  if bank < 1 or idx < 0 or idx >= BANK_TILE_COUNT then
    return
  end
  DebugController.perfIncrement("chr_canvas_invalidate_tile")
  if self.dirtyBanks[bank] == true then
    return
  end
  self.dirtyTiles[bank] = self.dirtyTiles[bank] or {}
  self.dirtyTiles[bank][idx] = true
  if self.currentBank == bank then
    self._canvasDirty = true
  end
end

function M:invalidateAll()
  self.currentBank = nil
  self.currentOrderMode = "normal"
  self.dirtyBanks = {}
  self.dirtyTiles = {}
  self._canvasDirty = true
  self._fullRepaintNeeded = true
end

function M:setView(bankIdx, orderMode)
  local bank = math.floor(tonumber(bankIdx) or 1)
  local normalizedOrderMode = (orderMode == "oddEven") and "oddEven" or "normal"
  DebugController.perfSet("chr_canvas_current_bank", bank)
  DebugController.perfSet("chr_canvas_order_mode", normalizedOrderMode)
  if self.currentBank ~= bank or self.currentOrderMode ~= normalizedOrderMode then
    self.currentBank = bank
    self.currentOrderMode = normalizedOrderMode
    self._canvasDirty = true
    self._fullRepaintNeeded = true
  end
end

local function writeTilePixelsToImage(imageData, bankBytes, tileIndex, dstTilePos)
  local pixels = chr.decodeTile(bankBytes, tileIndex)
  if not pixels then
    return
  end

  local tileCol = dstTilePos % BANK_TILE_COLS
  local tileRow = math.floor(dstTilePos / BANK_TILE_COLS)
  local baseX = tileCol * TILE_SIZE
  local baseY = tileRow * TILE_SIZE

  for py = 0, 7 do
    for px = 0, 7 do
      local value = pixels[(py * TILE_SIZE) + px + 1] or 0
      local gray = idxToGray(value)
      imageData:setPixel(baseX + px, baseY + py, gray, gray, gray, 1)
    end
  end
end

function M:repaint(state)
  if not (state and state.chrBanksBytes) then
    return false
  end

  local bankBytes = state.chrBanksBytes[self.currentBank]
  if not bankBytes then
    return false
  end

  local dirtyTiles = self.dirtyTiles[self.currentBank]
  local fullRepaint = self._fullRepaintNeeded or self.dirtyBanks[self.currentBank] == true
  local dirtyCount = 0
  local startedAt = nowSeconds()

  if dirtyTiles ~= nil then
    for _ in pairs(dirtyTiles) do
      dirtyCount = dirtyCount + 1
    end
  end
  DebugController.perfSet("chr_canvas_dirty_tile_count", fullRepaint and BANK_TILE_COUNT or dirtyCount)

  if fullRepaint or dirtyTiles == nil then
    for pos = 0, BANK_TILE_COUNT - 1 do
      local tileIndex = mapIndexForOrder(self.currentOrderMode, pos)
      writeTilePixelsToImage(self.imageData, bankBytes, tileIndex, pos)
    end
  else
    for tileIndex in pairs(dirtyTiles) do
      local pos = mapPosForTileIndex(self.currentOrderMode, tileIndex)
      writeTilePixelsToImage(self.imageData, bankBytes, tileIndex, pos)
    end
  end

  self.image:replacePixels(self.imageData)

  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.image, 0, 0)
  love.graphics.setCanvas()
  love.graphics.pop()

  local elapsedMs = (nowSeconds() - startedAt) * 1000
  DebugController.perfObserveMs("chr_canvas_repaint_ms", elapsedMs)
  if fullRepaint or dirtyTiles == nil then
    DebugController.perfIncrement("chr_canvas_repaint_full")
  else
    DebugController.perfIncrement("chr_canvas_repaint_partial")
  end

  self.dirtyBanks[self.currentBank] = nil
  self.dirtyTiles[self.currentBank] = nil
  self._canvasDirty = false
  self._fullRepaintNeeded = false
  return true
end

function M:ensureReady(state, bankIdx, orderMode)
  self:setView(bankIdx, orderMode)
  if self._canvasDirty or self.dirtyBanks[self.currentBank] == true then
    return self:repaint(state)
  end
  return true
end

function M:drawWindow(state, win, layerOpacity)
  if not (win and state) then
    return false
  end

  local bankIdx = tonumber(win.currentBank) or tonumber(state.currentBank) or 1
  if not self:ensureReady(state, bankIdx, win.orderMode or "normal") then
    return false
  end

  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local sx, sy, sw, sh = win:getScreenRect()

  love.graphics.push()
  love.graphics.translate(win.x, win.y)
  love.graphics.scale(z, z)
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)
  love.graphics.translate(-(win.scrollCol or 0) * TILE_SIZE, -(win.scrollRow or 0) * TILE_SIZE)
  love.graphics.setColor(1, 1, 1, layerOpacity or 1.0)
  love.graphics.draw(self.image, 0, 0)
  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

function M:drawTileHandle(state, handle, orderMode, x, y, sx, sy, alpha)
  if not (
    state
    and handle
    and type(handle.index) == "number"
    and type(handle._bankIndex) == "number"
    and self.tileQuad
  ) then
    return false
  end

  local normalizedOrderMode = (orderMode == "oddEven") and "oddEven" or "normal"
  if not self:ensureReady(state, handle._bankIndex, normalizedOrderMode) then
    return false
  end

  local pos = mapPosForTileIndex(normalizedOrderMode, handle.index)
  local tileCol = pos % BANK_TILE_COLS
  local tileRow = math.floor(pos / BANK_TILE_COLS)
  self.tileQuad:setViewport(tileCol * TILE_SIZE, tileRow * TILE_SIZE, TILE_SIZE, TILE_SIZE, BANK_PIXEL_W, BANK_PIXEL_H)

  DebugController.perfIncrement("chr_ghost_canvas_draw")
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(self.image, self.tileQuad, x, y, 0, sx or 1, sy or sx or 1)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

return M
