-- ppu_frame_window.lua
local Window = require("user_interface.windows_system.window")
local chr = require("chr")
local NametableUtils = require("utils.nametable_utils")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local colors = require("app_colors")
local Text = require("utils.text_utils")
local DebugController = require("controllers.dev.debug_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")

local PPUFrameWindow = {}
PPUFrameWindow.__index = PPUFrameWindow
setmetatable(PPUFrameWindow, { __index = Window })

-- NES nametable: 32x30 (960). If different length, keep 32 cols and grow rows.
local function inferDims(n)
  local cols = 32
  local rows = math.max(1, math.floor((n + cols - 1) / cols))
  return cols, rows
end

-- Per your mapping:
--   page 1: byte B -> tilesPool[bank][B]
--   page 2: byte B -> tilesPool[bank][256 + B]      (so B=0 -> index 256)
local function resolveTile(tilesPool, bankIndex, pageIndex, byteVal)
  if not tilesPool then return nil end
  local bank = tilesPool[bankIndex]
  if not bank then return nil end
  local B = byteVal or 0
  if pageIndex == 2 then
    return bank[256 + B]
  else
    return bank[B]
  end
end

-- linear index helpers (1-based for internal arrays)
local function lin(cols, col, row) return row * cols + col + 1 end

local function makeNametableCanvas(self)
  local w = math.max(1, (self.cols or 32) * (self.cellW or 8))
  local h = math.max(1, (self.rows or 30) * (self.cellH or 8))
  local canvas = love.graphics.newCanvas(w, h)
  canvas:setFilter("nearest", "nearest")
  return canvas, w, h
end

local function clampByte(byteVal)
  local v = math.floor(tonumber(byteVal) or 0)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

local function getTransparentTileByte(layer)
  if layer and layer.glassTileByte ~= nil then
    return clampByte(layer.glassTileByte)
  end
  if layer and layer.transparentTileByte ~= nil then
    return clampByte(layer.transparentTileByte)
  end
  return 0x00
end

local function isTransparentNametableByte(layer, byteVal, showGlassTile)
  if showGlassTile == false then
    return false
  end

  local v = clampByte(byteVal)
  local hasExplicitTransparent = false

  if layer and layer.glassTileByte ~= nil then
    hasExplicitTransparent = true
    if v == clampByte(layer.glassTileByte) then
      return true
    end
  end

  if layer and layer.transparentTileByte ~= nil then
    hasExplicitTransparent = true
    if v == clampByte(layer.transparentTileByte) then
      return true
    end
  end

  if not hasExplicitTransparent then
    return v == 0x00
  end

  return false
end

local function recordSwap(self, idx)
  if not self._originalNametableBytes then return end
  local orig = self._originalNametableBytes[idx]
  local cur  = self.nametableBytes[idx]
  if orig == nil then return end

  -- If value matches original, no need to store this cell in the diff
  if cur == orig then
    if self._tileSwaps then
      self._tileSwaps[idx] = nil
    end
  else
    self._tileSwaps = self._tileSwaps or {}
    self._tileSwaps[idx] = cur
  end
end

local function isNametableLayer(layer)
  if not layer then return false end
  if layer.kind == "tile" then return true end
  return (layer.nametableStartAddr ~= nil) or (layer.nametableEndAddr ~= nil)
end

-- Find the nametable layer.
-- Prefer active layer when it is a nametable/tile layer; otherwise fall back
-- to the first layer tagged as tile/nametable.
local function getNametableLayer(self)
  if not self.layers or #self.layers == 0 then return nil, nil end
  local idx = tonumber(self.activeLayer) or 1
  local active = self.layers[idx]
  if isNametableLayer(active) then
    return active, idx
  end

  for i, L in ipairs(self.layers) do
    if isNametableLayer(L) then
      return L, i
    end
  end

  local first = self.layers[1]
  if not first then return nil, nil end
  return first, 1
end

local function getBankPage(self)
  local L = getNametableLayer(self)
  local bank = (L and L.bank) or 1
  local page = (L and L.page) or 1
  return bank, page
end

-- Get the codec name from layer/project (project-level for now, defaults to "konami")
local function getCodec(layer, projectData)
  -- TODO: Get from project-level data when project system supports it
  -- For now, check layer, then default to "konami"
  return (layer and layer.codec) or (projectData and projectData.codec) or "konami"
end

local function resolveOriginalCompressedSizeBudget(self, layer, startAddr)
  local resolvedStart = startAddr
  if type(resolvedStart) ~= "number" then
    resolvedStart = self and self.nametableStart or nil
  end

  local resolvedEnd = layer and layer.nametableEndAddr or nil
  if type(resolvedEnd) ~= "number" and self and self.layers then
    for _, L in ipairs(self.layers) do
      if isNametableLayer(L) and type(L.nametableEndAddr) == "number" then
        local layerStart = L.nametableStartAddr or (self and self.nametableStart or nil)
        if type(resolvedStart) ~= "number" or layerStart == resolvedStart then
          resolvedEnd = L.nametableEndAddr
          if type(layerStart) == "number" then
            resolvedStart = layerStart
          end
          break
        end
      end
    end
  end

  if type(resolvedStart) == "number" and type(resolvedEnd) == "number" then
    if resolvedEnd >= resolvedStart then
      return (resolvedEnd - resolvedStart + 1), resolvedStart, resolvedEnd
    end
    DebugController.log(
      "warning",
      "NT_VERIFICATION",
      "Nametable range is reversed (start=%d, end=%d); using absolute span",
      resolvedStart,
      resolvedEnd
    )
    return (resolvedStart - resolvedEnd + 1), resolvedStart, resolvedEnd
  end

  if type(self and self.originalTotalByteNumber) == "number" and self.originalTotalByteNumber > 0 then
    return self.originalTotalByteNumber, resolvedStart, resolvedEnd
  end

  return nil, resolvedStart, resolvedEnd
end

local function drawNametableByteBudgetInfo(self)
  if not (self and self.getScreenRect) then return end

  local layer = getNametableLayer(self)
  local startAddr = (layer and layer.nametableStartAddr) or self.nametableStart
  local originalSize = self._nametableOriginalSize
  if type(originalSize) ~= "number" then
    originalSize = select(1, resolveOriginalCompressedSizeBudget(self, layer, startAddr))
  end

  local currentSize = self._nametableCompressedSize
  if type(currentSize) ~= "number" then
    currentSize = originalSize
  end

  if type(originalSize) ~= "number" and type(currentSize) ~= "number" then
    return
  end

  local sx, sy = self:getScreenRect()
  local x = sx + 4
  local y = sy + 4

  -- local originalText = (type(originalSize) == "number")
  --   and string.format("NT original: %d bytes", originalSize)
  --   or "NT original: ? bytes"
  -- local currentText = (type(currentSize) == "number")
  --   and string.format("NT current: %d bytes", currentSize)
  --   or "NT current: ? bytes"

  -- Text.print(originalText, x, y, { outline = true })
  -- Text.print(currentText, x, y + 10, { outline = true })
end

-- Sync window-level nametable state into the layer metadata.
-- This is what will eventually be serialized into the project file.
function PPUFrameWindow:syncNametableLayerMetadata()
  local L, idx = getNametableLayer(self)
  if not L then return end

  -- Make sure this layer is tagged as a tile/nametable layer
  L.kind = L.kind or "tile"

  -- Mode is optional; default to 8x8 unless caller sets otherwise
  L.mode = L.mode or "8x8"

  -- Nametable byte range in ROM
  -- IMPORTANT: These addresses are IMMUTABLE - they point to the original ROM data location.
  -- They should ONLY be set when loading from project/database, NEVER recalculated or overwritten.
  -- Once set from project/database, they must be preserved exactly as-is for reading from ROM.
  -- Only set if not already loaded from project/database (preserve existing values)
  if self.nametableStart and not L.nametableStartAddr then
    L.nametableStartAddr = self.nametableStart
  end
  -- nametableEndAddr: NEVER recalculate if it already exists (from project/database).
  -- Only calculate if it doesn't exist at all (for new windows created manually, not from project).
  if not L.nametableEndAddr and self.nametableStart and self.originalTotalByteNumber then
    L.nametableEndAddr = self.nametableStart + self.originalTotalByteNumber - 1
  end

  -- Swaps as a pretty list { {val,row,col}, ... } for serialization
  if self._tileSwaps then
    L.tileSwaps = self:getTileSwaps()
  else
    L.tileSwaps = nil
  end
end

function PPUFrameWindow:isTransparentNametableByte(byteVal, layerIndex)
  local layer = self:getLayer(layerIndex) or select(1, getNametableLayer(self))
  return isTransparentNametableByte(layer, byteVal, self.showGlassTile ~= false)
end

function PPUFrameWindow:syncNametableVisualCell(col, row, byteVal, tilesPool, layerIndex)
  local li = layerIndex or self.activeLayer or 1
  local layer = self:getLayer(li)
  if not layer then return end

  if isTransparentNametableByte(layer, byteVal, self.showGlassTile ~= false) then
    Window.clear(self, col, row, li)
    self:invalidateNametableLayerCanvas(li, col, row)
    return
  end

  if not tilesPool then
    self:invalidateNametableLayerCanvas(li, col, row)
    return
  end

  local bank = layer.bank or 1
  local page = layer.page or 1
  local tileRef = resolveTile(tilesPool, bank, page, byteVal)
  if tileRef then
    Window.set(self, col, row, tileRef, li)
  else
    Window.clear(self, col, row, li)
  end
  self:invalidateNametableLayerCanvas(li, col, row)
end

function PPUFrameWindow:drawVisibleNametableCells(renderCell, layerIndex)
  local li = layerIndex or self.activeLayer or 1
  local layer = self:getLayer(li)
  if not layer then
    return false
  end

  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.scale(self.zoom, self.zoom)
  love.graphics.setLineWidth(1)
  love.graphics.setLineStyle("rough")

  local cw, ch = self.cellW, self.cellH
  local sx, sy, sw, sh = self:getScreenRect()
  love.graphics.setScissor(sx, sy, sw, sh)
  love.graphics.translate(-self.scrollCol * cw, -self.scrollRow * ch)

  local vC0 = self.scrollCol
  local vR0 = self.scrollRow
  local vC1 = math.min(self.cols - 1, vC0 + self.visibleCols - 1)
  local vR1 = math.min(self.rows - 1, vR0 + self.visibleRows - 1)

  local spill = 1
  local c0 = math.max(0, vC0 - spill)
  local r0 = math.max(0, vR0 - spill)
  local c1 = math.min(self.cols - 1, vC1 + spill)
  local r1 = math.min(self.rows - 1, vR1 + spill)

  local layerAlpha = (layer.opacity ~= nil) and layer.opacity or 1.0

  for idx, item in pairs(layer.items or {}) do
    if item ~= nil then
      local z = idx - 1
      local col = z % self.cols
      local row = math.floor(z / self.cols)

      if col >= c0 and col <= c1 and row >= r0 and row <= r1 then
        local x = col * cw
        local y = row * ch
        renderCell(col, row, x, y, cw - 1, ch - 1, li, layerAlpha, item, z)
      end
    end
  end

  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.setColor(colors.white)
  return true
end

function PPUFrameWindow:_ensureNametableLayerCanvasState(layerIndex)
  local li = layerIndex or select(2, getNametableLayer(self)) or self.activeLayer or 1
  self._nametableLayerCanvas = self._nametableLayerCanvas or {}
  local state = self._nametableLayerCanvas[li]
  local expectedW = math.max(1, (self.cols or 32) * (self.cellW or 8))
  local expectedH = math.max(1, (self.rows or 30) * (self.cellH or 8))

  if not state then
    local canvas, cw, ch = makeNametableCanvas(self)
    state = {
      canvas = canvas,
      width = cw,
      height = ch,
      dirtyAll = true,
      dirtyCells = {},
    }
    self._nametableLayerCanvas[li] = state
    return state, li
  end

  if not state.canvas or state.width ~= expectedW or state.height ~= expectedH then
    local canvas, cw, ch = makeNametableCanvas(self)
    state.canvas = canvas
    state.width = cw
    state.height = ch
    state.dirtyAll = true
    state.dirtyCells = {}
  end

  return state, li
end

function PPUFrameWindow:invalidateNametableLayerCanvas(layerIndex, col, row)
  local state, li = self:_ensureNametableLayerCanvasState(layerIndex)
  if not state then
    return false
  end

  if col == nil or row == nil then
    state.dirtyAll = true
    state.dirtyCells = {}
    return true
  end

  local idx = lin(self.cols or 32, col, row)
  state.dirtyCells = state.dirtyCells or {}
  state.dirtyCells[idx] = true
  return true
end

function PPUFrameWindow:_paintNametableCellToCanvas(layer, idx)
  if not layer or not idx then
    return
  end

  local cols = self.cols or 32
  local col = (idx - 1) % cols
  local row = math.floor((idx - 1) / cols)
  local x = col * (self.cellW or 8)
  local y = row * (self.cellH or 8)
  local w = self.cellW or 8
  local h = self.cellH or 8
  local item = layer.items and layer.items[idx] or nil
  local paletteNum = layer.paletteNumbers and layer.paletteNumbers[(row * cols) + col] or nil

  love.graphics.setBlendMode("replace", "premultiplied")
  love.graphics.setColor(0, 0, 0, 0)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setBlendMode("alpha", "alphamultiply")

  if item and item.draw then
    ShaderPaletteController.applyLayerItemPalette(
      layer,
      item,
      true,
      self.romRaw,
      paletteNum,
      1.0
    )
    love.graphics.setColor(colors.white)
    item:draw(x, y, 1)
    ShaderPaletteController.releaseShader()
  end
end

function PPUFrameWindow:_repaintNametableLayerCanvas(layerIndex)
  local state, li = self:_ensureNametableLayerCanvasState(layerIndex)
  local layer = self:getLayer(li)
  if not (state and layer and layer.kind == "tile" and state.canvas) then
    return false
  end

  local dirtyCells = state.dirtyCells or {}
  local hasDirtyCells = next(dirtyCells) ~= nil
  local repaintAll = state.dirtyAll == true or not hasDirtyCells

  love.graphics.push("all")
  love.graphics.setCanvas(state.canvas)
  if repaintAll then
    love.graphics.clear(0, 0, 0, 0)
    local max = math.max(0, (self.cols or 32) * (self.rows or 30))
    for idx = 1, max do
      self:_paintNametableCellToCanvas(layer, idx)
    end
  else
    for idx in pairs(dirtyCells) do
      self:_paintNametableCellToCanvas(layer, idx)
    end
  end
  love.graphics.setCanvas()
  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.setColor(colors.white)
  ShaderPaletteController.releaseShader()

  state.dirtyAll = false
  state.dirtyCells = {}
  return true
end

function PPUFrameWindow:drawNametableLayerCanvas(layerIndex)
  local state, li = self:_ensureNametableLayerCanvasState(layerIndex)
  local layer = self:getLayer(li)
  if not (state and layer and layer.kind == "tile" and state.canvas) then
    return false
  end
  if layer.attrMode == true then
    return false
  end

  if state.dirtyAll or (state.dirtyCells and next(state.dirtyCells) ~= nil) then
    self:_repaintNametableLayerCanvas(li)
  end

  local sx, sy, sw, sh = self:getScreenRect()
  local layerOpacity = (layer.opacity ~= nil) and layer.opacity or 1.0
  local z = self.zoom or 1
  local cw, ch = self.cellW or 8, self.cellH or 8

  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.scale(z, z)
  love.graphics.setScissor(sx, sy, sw, sh)
  love.graphics.translate(-(self.scrollCol or 0) * cw, -(self.scrollRow or 0) * ch)
  love.graphics.setColor(1, 1, 1, layerOpacity)
  love.graphics.draw(state.canvas, 0, 0)
  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.setColor(colors.white)
  return true
end

----------------------------------------------------------------
-- Constructor
----------------------------------------------------------------
function PPUFrameWindow.new(x, y, zoom, data)
  data = data or {}
  data.resizable = true
  local cellW, cellH = 8, 8
  local cols, rows   = 32, 30

  local self = Window.new(
    x, y, cellW, cellH, cols, rows, zoom, data
  )
  setmetatable(self, PPUFrameWindow)

  self.kind       = "ppu_frame"
  self.showSpriteOriginGuides = (data.showSpriteOriginGuides == true)
  self.showGlassTile = (data.showGlassTile ~= false)
  self._nametableLayerCanvas = {}
  self.nametableBytes     = {}   -- table of numbers 0..255, length = cols*rows (or fewer)
  self.nametableAttrBytes = {}   -- table of numbers 0..255, length = 256
  self.romRaw = data.romRaw
  self.nametableStart = data.nametableStart or 0

    -- Sprite overlay state (second layer)
  self.spriteData       = nil       -- raw config from project/DB
  self._spriteRuntime   = nil       -- parsed OAM bytes etc.

  -- Ensure one drawing layer exists and tag it as a tile/nametable layer
  if not self.layers or #self.layers == 0 then
    self.layers = {
      {
        items   = {},
        opacity = 1.0,
        name    = "Layer 1",
        kind    = "tile",  -- grid / nametable layer
        mode    = "8x8",
        codec   = data.codec or "konami",
      }
    }
    self.activeLayer = 1
  else
    -- If layers already exist, at least ensure the active one is a tile layer
    local L = self.layers[self.activeLayer or 1] or self.layers[1]
    if L and not L.kind then
      L.kind = "tile"
    end
    if L and not L.codec then
      L.codec = data.codec or "konami"
    end
  end

  -- Seed layer metadata from the current window-level state
  self:syncNametableLayerMetadata()

  return self
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- bytesTbl: table of numbers 0..255
-- bankIndex: tilesPool bank index
-- pageIndex: 1 or 2
-- tilesPool: source of live tile refs
function PPUFrameWindow:setNametableBytes(bytesTbl, bankIndex, pageIndex, tilesPool)
  self.nametableBytes = {}
  for i = 1, #bytesTbl do
    local b = tonumber(bytesTbl[i]) or 0
    if b < 0 then b = 0 elseif b > 255 then b = 255 end
    self.nametableBytes[i] = b
  end

  self._originalNametableBytes = {}
  for i = 1, #self.nametableBytes do
    self._originalNametableBytes[i] = self.nametableBytes[i]
  end
  self._tileSwaps = {}  -- compact diff map

  local bank  = tonumber(bankIndex or 1) or 1
  local page  = (pageIndex == 2) and 2 or 1

  local Lnt = select(1, getNametableLayer(self))
  if Lnt then
    Lnt.bank = bank
    Lnt.page = page
  end

  self:syncNametableLayerMetadata()

  -- Fit logical grid to data size
  local cols, rows = inferDims(#self.nametableBytes)
  self.cols, self.rows = cols, rows

  DebugController.log("info", "PPU", "Window '%s' nametable bytes set: %d bytes, %dx%d grid, bank: %d, page: %d", self.title or "untitled", #self.nametableBytes, cols, rows, bank, page)

  -- Clear existing items on layer 1
  local li = select(2, getNametableLayer(self)) or self.activeLayer or 1
  local L = self.layers[li]
  if L then
    L.items = {}
  end

  if tilesPool then
    for i = 1, #self.nametableBytes do
      local b = self.nametableBytes[i]
      local z = i - 1
      local col = z % cols
      local row = math.floor(z / cols)
      self:syncNametableVisualCell(col, row, b, tilesPool, li)
    end
  end
  self:invalidateNametableLayerCanvas(li)

  if self.setScroll then self:setScroll(self.scrollCol or 0, self.scrollRow or 0) end

  if #self.nametableAttrBytes > 0 then
    local ok, err = self:updateCompressedBytesInROM()
    if not ok then DebugController.log("info", "PPU", "Update failed: %s", tostring(err)) end
  end

  self:syncNametableLayerMetadata()
end

-- Store PPU attribute table bytes (typically 64 bytes for a 32x30 nametable).
-- bytesTbl: table of numbers 0..255
function PPUFrameWindow:setAttributeBytes(bytesTbl)
  self.nametableAttrBytes = {}
  for i = 1, (bytesTbl and #bytesTbl or 0) do
    local b = tonumber(bytesTbl[i]) or 0
    if b < 0 then b = 0 elseif b > 255 then b = 255 end
    self.nametableAttrBytes[i] = b
  end

  if not self._originalNametableAttrBytes or #self._originalNametableAttrBytes == 0 then
    self._originalNametableAttrBytes = {}
    for i = 1, #self.nametableAttrBytes do
      self._originalNametableAttrBytes[i] = self.nametableAttrBytes[i]
    end
  end

  -- Extract palette numbers from attribute bytes for the nametable layer
  local Lnt = select(1, getNametableLayer(self))
  if Lnt then
    NametableTilesController.extractPaletteNumbersFromAttributes(
      self,        -- win
      Lnt,         -- layer
      self.cols,   -- cols
      self.rows    -- rows
    )
  end
  self:invalidateNametableLayerCanvas(select(2, getNametableLayer(self)) or self.activeLayer or 1)

  if #self.nametableBytes > 0 then
    local ok, err = self:updateCompressedBytesInROM()
    if not ok then DebugController.log("info", "PPU", "Update failed: %s", tostring(err)) end
  end

  self:syncNametableLayerMetadata()
end

function PPUFrameWindow:updateSpriteBytes(layerIndex, itemIndex)
  if type(self.romRaw) ~= "string" or #self.romRaw == 0 then
    return
  end

  -- Look up the sprite layer from the unified layer list
  if not (self.layers and self.layers[layerIndex]) then
    return
  end

  local L = self.layers[layerIndex]
  if not (L and L.kind == "sprite" and L.items) then
    return
  end

  local s = L.items[itemIndex]
  if not s or type(s.startAddr) ~= "number" then
    return
  end

  -- Build the 4 OAM bytes we want to write back:
  -- Y, tileByte, attr, X
  local y        = s.y or 0
  local x        = s.x or 0
  local attr     = s.attr or 0
  local tileByte = s.oamTile or s.tile or 0

  -- Clamp to NES byte range
  if y < 0 then y = 0 elseif y > 255 then y = 255 end
  if x < 0 then x = 0 elseif x > 255 then x = 255 end
  if attr < 0 then attr = 0 elseif attr > 255 then attr = 255 end
  if tileByte < 0 then tileByte = 0 elseif tileByte > 255 then tileByte = 255 end

  local bytes = {
    y,
    tileByte,
    attr,
    x,
  }

  local newRom, err = chr.writeBytesToRange(self.romRaw, s.startAddr, 4, bytes)
  if not newRom then
    DebugController.log("info", "PPU", "updateSpriteBytes failed: %s", tostring(err))
    return
  end

  self.romRaw = newRom
end

function PPUFrameWindow:setTotalCompressedBytesSize(size)
  self.originalTotalByteNumber = size
  if type(size) == "number" and size > 0 then
    self._nametableOriginalSize = size
    if type(self._nametableCompressedSize) ~= "number" then
      self._nametableCompressedSize = size
    end
  end
  self:syncNametableLayerMetadata()
end

-- Optional: re-point to a different bank/page after loading bytes
function PPUFrameWindow:setBankPage(bankIndex, pageIndex, tilesPool)
  local Lnt = select(1, getNametableLayer(self))
  if not Lnt then return end

  if bankIndex ~= nil then
    Lnt.bank = tonumber(bankIndex) or Lnt.bank or 1
  end
  if pageIndex ~= nil then
    Lnt.page = (pageIndex == 2) and 2 or 1
  end

  -- Rebuild items from current bytes
  local cols = self.cols
  local li = select(2, getNametableLayer(self)) or 1
  local layer = self:getLayer(li)
  if layer then
    layer.items = {}
  end
  if tilesPool then
    for i = 1, #self.nametableBytes do
      local b = self.nametableBytes[i]
      local z = i - 1
      local col = z % cols
      local row = math.floor(z / cols)
      self:syncNametableVisualCell(col, row, b, tilesPool, li)
    end
  end
  self:invalidateNametableLayerCanvas(li)
  if self.setScroll then self:setScroll(self.scrollCol or 0, self.scrollRow or 0) end

  self:syncNametableLayerMetadata()
end

----------------------------------------------------------------
-- Helper: Convert tile object to nametable byte value
----------------------------------------------------------------

local function tileToByte(tile, layer)
  if not tile or tile.index == nil then
    return nil
  end
  
  local page = (layer and layer.page) or 1
  local tileIndex = tile.index  -- 0-based within bank
  
  -- Reverse of resolveTile logic:
  --   page 1: byte B -> tilesPool[bank][B], so tileIndex = B, byte = tileIndex
  --   page 2: byte B -> tilesPool[bank][256 + B], so tileIndex = 256 + B, byte = tileIndex - 256
  if page == 2 and tileIndex >= 256 and tileIndex <= 511 then
    return tileIndex - 256
  else
    return tileIndex % 256
  end
end

----------------------------------------------------------------
-- Override set() to update nametable bytes
----------------------------------------------------------------

function PPUFrameWindow:set(col, row, item, layerIndex)
  -- For nametable layers, also update the nametable byte
  local L = self:getLayer(layerIndex)
  if not L or L.kind ~= "tile" then
    Window.set(self, col, row, item, layerIndex)
    return
  end
  
  local idx = lin(self.cols, col, row)
  if idx < 1 or idx > #self.nametableBytes then return end
  
  local nametableByte
  
  if item then
    -- Try to convert tile to byte value
    nametableByte = tileToByte(item, L)
  end
  
  if nametableByte == nil then
    -- No item or couldn't convert - use transparent tile byte
    nametableByte = getTransparentTileByte(L)
  end

  if isTransparentNametableByte(L, nametableByte, self.showGlassTile ~= false) then
    Window.clear(self, col, row, layerIndex)
  else
    Window.set(self, col, row, item, layerIndex)
  end
  
  -- Update nametable byte
  self.nametableBytes[idx] = nametableByte
  
  -- Record the change
  recordSwap(self, idx)
  
  -- Update ROM
  local ok, err = self:updateCompressedBytesInROM()
  if not ok then
    DebugController.log("info", "PPU", "Update failed after set: %s", tostring(err))
  end
  self:invalidateNametableLayerCanvas(layerIndex or self.activeLayer or 1, col, row)
end

----------------------------------------------------------------
-- Swapping (intra-window drag/drop)
----------------------------------------------------------------

function PPUFrameWindow:swapCells(c1, r1, c2, r2)
  if c1 == c2 and r1 == r2 then return end

  local Lidx = self.activeLayer or 1
  local L = self:getLayer(Lidx)
  if not L or L.kind ~= "tile" then return end
  
  local a = self:get(c1, r1, Lidx)
  local b = self:get(c2, r2, Lidx)

  -- Calculate linear indices
  local i1 = lin(self.cols, c1, r1)
  local i2 = lin(self.cols, c2, r2)
  
  -- Save current byte values BEFORE any operations
  local byte1 = self.nametableBytes[i1]
  local byte2 = self.nametableBytes[i2]

  -- Swap the items in the grid directly (avoid triggering set() which would update bytes incorrectly)
  if a or b then
    -- Directly swap the items without calling set()
    local L = self:getLayer(Lidx)
    if L and L.items then
      L.items[i1] = b
      L.items[i2] = a
    end
  end

  -- Swap the byte values to match the visual swap
  self.nametableBytes[i1] = byte2
  self.nametableBytes[i2] = byte1

  -- record per-cell diffs vs original
  recordSwap(self, i1)
  recordSwap(self, i2)

  -- Update ROM once with the correct swapped bytes
  local ok, err = self:updateCompressedBytesInROM()
  if not ok then DebugController.log("info", "PPU", "Update failed: %s", tostring(err)) end
  self:invalidateNametableLayerCanvas(Lidx, c1, r1)
  self:invalidateNametableLayerCanvas(Lidx, c2, r2)
end

-- Return a compact list of swapped cells for serialization:
--   { { col = C, row = R, val = BYTE }, ... }
function PPUFrameWindow:getTileSwaps()
  if not self._tileSwaps then return nil end

  local out = {}
  for idx, val in pairs(self._tileSwaps) do
    local z   = idx - 1
    local col = z % self.cols
    local row = math.floor(z / self.cols)
    out[#out+1] = { col = col, row = row, val = val }
  end

  if #out == 0 then return nil end

  -- Sort for stable, pretty output
  table.sort(out, function(a, b)
    if a.row == b.row then return a.col < b.col end
    return a.row < b.row
  end)

  return out
end

-- Apply a list of swaps { {col,row,val}, ... } on top of the current bytes/grid.
function PPUFrameWindow:applyTileSwapsFrom(swaps, tilesPool)
  if not swaps or #swaps == 0 then return end

  tilesPool = tilesPool or nil
  self._tileSwaps = self._tileSwaps or {}
  local li = select(2, getNametableLayer(self)) or 1

  for _, s in ipairs(swaps) do
    local col, row, val = s.col, s.row, s.val
    if col ~= nil and row ~= nil and val ~= nil then
      local idx = lin(self.cols, col, row)
      self.nametableBytes[idx] = val

      -- Update visual tile if we have a tilesPool
      if tilesPool then
        self:syncNametableVisualCell(col, row, val, tilesPool, li)
      end

      -- Keep diff map consistent with original baseline
      recordSwap(self, idx)
      self:invalidateNametableLayerCanvas(li, col, row)
    end
  end

  -- Refresh compressed data in romRaw so preview / save-to-ROM uses the swapped map
  if #self.nametableAttrBytes > 0 then
    local ok, err = self:updateCompressedBytesInROM()
    if not ok then DebugController.log("info", "PPU", "applyTileSwapsFrom failed: %s", tostring(err)) end
  end

  self:syncNametableLayerMetadata()
end

-- Set a specific nametable byte, refresh the visual tile (if tilesPool is provided),
-- and update ROM/diff bookkeeping. This bypasses PPUFrameWindow:set() to avoid
-- re-translating tiles back into bytes.
function PPUFrameWindow:setNametableByteAt(col, row, byteVal, tilesPool, layerIndex)
  local idx = lin(self.cols, col, row)
  if not self.nametableBytes or idx < 1 or idx > #self.nametableBytes then
    return
  end

  -- Clamp to byte range
  local v = math.max(0, math.min(255, math.floor(byteVal or 0)))
  self.nametableBytes[idx] = v

  -- Record diff vs original
  recordSwap(self, idx)

  -- Refresh visual tile if we can resolve it
  local li = layerIndex or self.activeLayer or 1
  self:syncNametableVisualCell(col, row, v, tilesPool, li)
  self:invalidateNametableLayerCanvas(li, col, row)

  local ok, err = self:updateCompressedBytesInROM()
  if not ok then
    DebugController.log("info", "PPU", "Update failed after setNametableByteAt: %s", tostring(err))
  end
end

function PPUFrameWindow:refreshNametableVisuals(tilesPool, layerIndex)
  local li = layerIndex or select(2, getNametableLayer(self)) or self.activeLayer or 1
  local layer = self:getLayer(li)
  if not layer then
    return false
  end

  layer.items = {}

  for i = 1, #(self.nametableBytes or {}) do
    local z = i - 1
    local col = z % (self.cols or 1)
    local row = math.floor(z / (self.cols or 1))
    local byteVal = self.nametableBytes[i]
    self:syncNametableVisualCell(col, row, byteVal, tilesPool, li)
  end

  if self.setScroll then
    self:setScroll(self.scrollCol or 0, self.scrollRow or 0)
  end

  self:invalidateNametableLayerCanvas(li)
  self:syncNametableLayerMetadata()
  return true
end

function PPUFrameWindow:setGlassTileByte(byteVal, tilesPool, layerIndex)
  local li = layerIndex or select(2, getNametableLayer(self)) or self.activeLayer or 1
  local layer = self:getLayer(li)
  if not layer then
    return false
  end

  layer.glassTileByte = clampByte(byteVal)
  layer.transparentTileByte = nil
  return self:refreshNametableVisuals(tilesPool, li)
end

function PPUFrameWindow:clearGlassTileByte(tilesPool, layerIndex)
  local li = layerIndex or select(2, getNametableLayer(self)) or self.activeLayer or 1
  local layer = self:getLayer(li)
  if not layer then
    return false
  end

  layer.glassTileByte = nil
  layer.transparentTileByte = nil
  return self:refreshNametableVisuals(tilesPool, li)
end

function PPUFrameWindow:updateCompressedBytesInROM()
  if type(self.romRaw) ~= "string" or #self.romRaw == 0 then
    DebugController.log("info", "PPU", "romRaw is empty; aborting write")
    return false, "empty_rom"
  end

  -- Get the nametable layer to access start/end addresses
  local layer = getNametableLayer(self)
  if not layer then
    DebugController.log("warning", "PPU", "No nametable layer found")
    return false, "no_layer"
  end

  -- Get start address (0-based)
  local startAddr = layer.nametableStartAddr or self.nametableStart
  
  if not startAddr then
    DebugController.log("warning", "PPU", "nametableStartAddr not available")
    return false, "no_start_addr"
  end

  -- Store original decompressed bytes for verification
  local originalNametableBytes = {}
  local originalAttrBytes = {}
  for i = 1, #self.nametableBytes do
    originalNametableBytes[i] = self.nametableBytes[i]
  end
  for i = 1, #self.nametableAttrBytes do
    originalAttrBytes[i] = self.nametableAttrBytes[i]
  end
  DebugController.log("info", "NT_VERIFICATION", "Original decompressed: %d nametable bytes, %d attribute bytes", 
    #originalNametableBytes, #originalAttrBytes)

  -- Get codec from layer/project (defaults to "konami")
  local codec = getCodec(layer, self.projectData)
  
  -- Encode without padding
  local totalCompressedBytes = NametableUtils.encode_decompressed_nametable(
    self.nametableBytes,
    self.nametableAttrBytes,
    codec
  )

  local compressedSize = #totalCompressedBytes
  self._nametableCompressedSize = compressedSize
  DebugController.log("info", "NT_VERIFICATION", "Compressed size: %d bytes", compressedSize)

  -- DEBUG: Verify compression/decompression round-trip
  -- Decompress immediately after encoding to check if data is preserved
  DebugController.log("info", "NT_VERIFICATION", "Verifying compression/decompression round-trip... (codec: %s)", codec)
  local decompressedNt, decompressedAt = NametableUtils.decode_compressed_nametable(totalCompressedBytes, false, codec)
  
  if not decompressedNt or not decompressedAt then
    DebugController.log("error", "NT_VERIFICATION", "Failed to decompress after encoding!")
  else
    DebugController.log("info", "NT_VERIFICATION", "Decompressed: %d nametable bytes, %d attribute bytes", 
      #decompressedNt, #decompressedAt)
    
    -- Compare nametable bytes
    local ntMismatches = 0
    local firstNtMismatch = nil
    if #decompressedNt ~= #originalNametableBytes then
      DebugController.log("error", "NT_VERIFICATION", "Nametable size mismatch: original=%d, decompressed=%d", 
        #originalNametableBytes, #decompressedNt)
    else
      for i = 1, #originalNametableBytes do
        if decompressedNt[i] ~= originalNametableBytes[i] then
          ntMismatches = ntMismatches + 1
          if not firstNtMismatch then
            firstNtMismatch = i
            local col = (i - 1) % 32
            local row = math.floor((i - 1) / 32)
            DebugController.log("error", "NT_VERIFICATION", "Nametable mismatch at byte %d (col=%d, row=%d): original=0x%02X, decompressed=0x%02X", 
              i, col, row, originalNametableBytes[i], decompressedNt[i])
          end
          if ntMismatches <= 5 then
            local col = (i - 1) % 32
            local row = math.floor((i - 1) / 32)
            DebugController.log("error", "NT_VERIFICATION", "  Additional mismatch at byte %d (col=%d, row=%d): 0x%02X vs 0x%02X", 
              i, col, row, originalNametableBytes[i], decompressedNt[i])
          end
        end
      end
    end
    
    -- Compare attribute bytes
    local atMismatches = 0
    local firstAtMismatch = nil
    if #decompressedAt ~= #originalAttrBytes then
      DebugController.log("error", "NT_VERIFICATION", "Attribute size mismatch: original=%d, decompressed=%d", 
        #originalAttrBytes, #decompressedAt)
    else
      for i = 1, #originalAttrBytes do
        if decompressedAt[i] ~= originalAttrBytes[i] then
          atMismatches = atMismatches + 1
          if not firstAtMismatch then
            firstAtMismatch = i
            DebugController.log("error", "NT_VERIFICATION", "Attribute mismatch at byte %d: original=0x%02X, decompressed=0x%02X", 
              i, originalAttrBytes[i], decompressedAt[i])
          end
          if atMismatches <= 5 then
            DebugController.log("error", "NT_VERIFICATION", "  Additional attribute mismatch at byte %d: 0x%02X vs 0x%02X", 
              i, originalAttrBytes[i], decompressedAt[i])
          end
        end
      end
    end
    
    if ntMismatches == 0 and atMismatches == 0 then
      DebugController.log("info", "NT_VERIFICATION", "(OK) Compression/decompression round-trip verified: all bytes match!")
    else
      DebugController.log("error", "NT_VERIFICATION", "(X) Compression/decompression mismatch: %d nametable differences, %d attribute differences", 
        ntMismatches, atMismatches)
    end
  end

  -- Calculate original byte budget using layer range metadata (or fallback baseline).
  local originalSize, resolvedStartAddr, resolvedEndAddr = resolveOriginalCompressedSizeBudget(self, layer, startAddr)
  if originalSize then
    if type(resolvedStartAddr) == "number" and type(resolvedEndAddr) == "number" then
      DebugController.log(
        "info",
        "NT_VERIFICATION",
        "Original size: %d bytes (from %d to %d)",
        originalSize,
        resolvedStartAddr,
        resolvedEndAddr
      )
    else
      DebugController.log(
        "info",
        "NT_VERIFICATION",
        "Original size: %d bytes (from stored baseline)",
        originalSize
      )
    end
  else
    DebugController.log(
      "warning",
      "NT_VERIFICATION",
      "No nametable byte budget available (missing endAddr and baseline size)"
    )
  end
  self._nametableOriginalSize = originalSize
  if NametableTilesController and NametableTilesController.updateOverflowToastForWindow then
    NametableTilesController.updateOverflowToastForWindow(self, layer, compressedSize, originalSize)
  end

  -- If compressed size is smaller than original, pad with 0xFF to preserve ROM size
  local bytesToWrite = totalCompressedBytes
  if originalSize and compressedSize < originalSize then
    DebugController.log("info", "NT_VERIFICATION", "Padding %d bytes with 0xFF to preserve original size", originalSize - compressedSize)
    for i = compressedSize + 1, originalSize do
      bytesToWrite[i] = 0xFF
    end
  end

  -- Write using writeBytesStartingAt (writes exactly what we provide, doesn't change ROM size if smaller)
  local newRom, err = chr.writeBytesStartingAt(
    self.romRaw,
    startAddr,
    bytesToWrite
  )
  
  if not newRom then
    DebugController.log("info", "PPU", "writeBytesStartingAt failed: %s", tostring(err))
    return false, err
  end

  self.romRaw = newRom
  self.originalTotalByteNumber = #bytesToWrite
  
  DebugController.log("info", "NT_VERIFICATION", "Successfully wrote %d bytes to ROM at address %d", #bytesToWrite, startAddr)

  self:syncNametableLayerMetadata()

  return true
end

function PPUFrameWindow:renderCell(col, row, x, y, w, h, layerIndex, layerAlpha)
  local item = self:get(col, row, layerIndex)
  if not item or not item.draw then return end

  local layer = self.layers and self.layers[layerIndex]
  local drawingActiveLayer = (layerIndex == self.activeLayer)
  local paletteNum = nil

  -- For nametable/tile layers, use per-cell paletteNumbers computed from attributes
  if layer and layer.kind == "tile" and layer.paletteNumbers then
    -- 0-based linear index: same convention as NametableTilesController & snapshot code
    local idx = row * self.cols + col
    paletteNum = layer.paletteNumbers[idx]
  end

  ShaderPaletteController.applyLayerItemPalette(
    layer,
    item,
    drawingActiveLayer,
    self.romRaw,
    paletteNum,
    layerAlpha
  )

  love.graphics.setColor(colors.white)
  item:draw(x, y, 1)

  ShaderPaletteController.releaseShader()
  love.graphics.setColor(colors.white)
end

function PPUFrameWindow:draw()
  self:drawGrid(function(col, row, x, y, w, h, li, la)
    self:renderCell(col, row, x, y, w, h, li, la)
  end)
end

function PPUFrameWindow:drawLayerLabelInContent(isFocused)
  Window.drawLayerLabelInContent(self, isFocused)
  drawNametableByteBudgetInfo(self)
end

function PPUFrameWindow:printNametableDataAsHex()
  local s = ""
  for i = 1, self.rows do
    for j = 1, self.cols do
      local b = self.nametableBytes[lin(self.cols, j, i)] or 0
      s = s .. string.format("%02x ", b)
    end
    s = s .. "\n"
  end
  print(s)
end

function PPUFrameWindow:printNametableAttrDataAsHex()
  local s = ""
  -- NES attribute table is always exactly 64 bytes for standard nametables
  local attrSize = math.min(64, self.nametableAttrBytes and #self.nametableAttrBytes or 64)
  for i = 1, attrSize do
    local b = self.nametableAttrBytes[i] or 0
    s = s .. string.format("%02x ", b)
  end
  print(s)
  print(string.format("Total attribute bytes: %d (should be 64)", self.nametableAttrBytes and #self.nametableAttrBytes or 0))
end

function PPUFrameWindow:printTotalCompressedBytesAsHex()
  local layer = getNametableLayer(self)
  local codec = getCodec(layer, self.projectData)
  
  local totalCompressedBytes = NametableUtils.encode_decompressed_nametable(
    self.nametableBytes,
    self.nametableAttrBytes,
    codec
  )

  local s = ""
  for i = 1, #totalCompressedBytes do
    local b = totalCompressedBytes[i] or 0
    s = s .. string.format("%02x ", b)
    if i % 16 == 0 then s = s .. "\n" end
  end
  print(s)
end

return PPUFrameWindow
