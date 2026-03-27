-- chr_bank_window.lua
-- CHR bank browser: drag tiles out to other windows, no drops allowed in.
-- Each ROM/CHR bank is loaded into its own layer; the active layer is the
-- currently visible bank.

local Window = require("user_interface.windows_system.window")
local BankViewController = require("controllers.chr.bank_view_controller")
local BankCanvasSupport = require("controllers.chr.bank_canvas_support")
local DebugController = require("controllers.dev.debug_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")

local ChrBankWindow = setmetatable({}, { __index = Window })
ChrBankWindow.__index = ChrBankWindow

local function isOddEvenMode(win)
  return win and win.orderMode == "oddEven"
end

local function getTopRow(row)
  row = math.floor(tonumber(row) or 0)
  return row - (row % 2)
end

local function swapEditEntries(bankEdits, tileA, tileB)
  if not (bankEdits and tileA and tileB) then return end
  if type(tileA.index) ~= "number" or type(tileB.index) ~= "number" then return end

  local editsA = bankEdits[tileA.index]
  local editsB = bankEdits[tileB.index]
  bankEdits[tileA.index] = editsB
  bankEdits[tileB.index] = editsA

  if editsB == nil or (type(editsB) == "table" and next(editsB) == nil) then
    bankEdits[tileA.index] = nil
  end
  if editsA == nil or (type(editsA) == "table" and next(editsA) == nil) then
    bankEdits[tileB.index] = nil
  end
end

local function recordTileSnapshotToEdits(edits, bankIdx, tileRef)
  if not (edits and tileRef and tileRef.pixels) then return end
  if type(bankIdx) ~= "number" then return end
  if type(tileRef.index) ~= "number" then return end

  edits.banks = edits.banks or {}
  edits.banks[bankIdx] = edits.banks[bankIdx] or {}
  edits.banks[bankIdx][tileRef.index] = edits.banks[bankIdx][tileRef.index] or {}
  local tileEdits = edits.banks[bankIdx][tileRef.index]
  for y = 0, 7 do
    for x = 0, 7 do
      local pixel = tileRef.pixels[(y * 8) + x + 1]
      if pixel == nil then pixel = 0 end
      tileEdits[x .. "_" .. y] = pixel
    end
  end
end

local function clampBankIndex(self, bankIdx)
  local count = #(self.layers or {})
  if count <= 0 then
    return 1
  end
  local n = math.floor(tonumber(bankIdx) or 1)
  if n < 1 then n = 1 end
  if n > count then n = count end
  return n
end

local function resolveAppEditState(win)
  if win and win.appEditState then
    return win.appEditState
  end
  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app or nil
  return app and app.appEditState or nil
end

local function tileIndexForCell(self, col, row)
  if type(col) ~= "number" or type(row) ~= "number" then
    return nil
  end
  if col < 0 or row < 0 or col >= (self.cols or 0) or row >= (self.rows or 0) then
    return nil
  end
  local pos = row * (self.cols or 0) + col
  if pos < 0 or pos >= 512 then
    return nil
  end

  if isOddEvenMode(self) then
    local pair = math.floor(row / 2)
    local isOdd = (row % 2 == 1)
    return pair * 32 + col * 2 + (isOdd and 1 or 0)
  end

  return pos
end

function ChrBankWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  data = data or {}
  data.resizable = true
  local self = Window.new(x, y, cellW, cellH, cols, rows, zoom, {
    flags = {
      allowInternalDrag = false,
      allowExternalDrag = true,
      allowExternalDrop = true,  -- Allow PNG file drops for image import
    },
    title = data.title,
    visibleRows = data.visibleRows or rows,
    visibleCols = data.visibleCols or cols,
    resizable = data.resizable,
  })
  setmetatable(self, ChrBankWindow)

  self.kind = "chr"
  self.drawOnlyActiveLayer = true
  self.layers = {}
  self:addLayer({ opacity = 1.0, name = "Bank" })
  self.activeLayer = 1
  
  -- CHR window-specific state
  self.orderMode = data.orderMode or "normal"
  self.currentBank = data.currentBank or 1

  return self
end

function ChrBankWindow:getTileIndexAt(col, row)
  return tileIndexForCell(self, col, row)
end

function ChrBankWindow:getVirtualTileHandle(col, row, layerIndex)
  local layer = self:getLayer(layerIndex)
  if not layer then return nil end

  local tileIndex = tileIndexForCell(self, col, row)
  if tileIndex == nil then
    return nil
  end

  local bankIdx = clampBankIndex(self, layer.bank or layerIndex or self.currentBank or self.activeLayer or 1)
  return {
    kind = "chr_virtual_tile",
    index = tileIndex,
    _bankIndex = bankIdx,
    _virtual = true,
  }
end

function ChrBankWindow:materializeTileHandle(handle, layerIndex)
  if handle == nil then
    return nil
  end
  if handle._virtual ~= true then
    return handle
  end

  local bankIdx = tonumber(handle._bankIndex)
  if bankIdx == nil then
    local layer = self:getLayer(layerIndex)
    bankIdx = clampBankIndex(self, layer and layer.bank or layerIndex or self.currentBank or self.activeLayer or 1)
  end

  local tileIndex = tonumber(handle.index)
  if tileIndex == nil then
    return nil
  end

  DebugController.perfIncrement("chr_tile_materialize")
  local state = resolveAppEditState(self)
  return BankViewController.getTileRef(state, bankIdx, tileIndex)
end

function ChrBankWindow:get(col, row, layerIndex)
  local handle = self:getVirtualTileHandle(col, row, layerIndex)
  return self:materializeTileHandle(handle, layerIndex)
end

function ChrBankWindow:getStack(col, row, layerIndex)
  local item = self:getVirtualTileHandle(col, row, layerIndex)
  if item == nil then
    return nil
  end
  return { item }, { { ox = 0, oy = 0 } }
end

function ChrBankWindow:setActiveLayerIndex(i)
  Window.setActiveLayerIndex(self, i)
  self.currentBank = clampBankIndex(self, self.activeLayer or i or 1)
end

function ChrBankWindow:setCurrentBank(bankIdx)
  self:setActiveLayerIndex(clampBankIndex(self, bankIdx))
  return self.currentBank
end

function ChrBankWindow:shiftBank(delta)
  local count = #(self.layers or {})
  if count <= 0 then
    self.currentBank = 1
    self.activeLayer = 1
    return self.currentBank
  end

  local current = clampBankIndex(self, self.currentBank or self.activeLayer or 1)
  local nextIndex = ((current - 1 + math.floor(delta or 0)) % count) + 1
  self:setCurrentBank(nextIndex)
  return self.currentBank
end

function ChrBankWindow:resetBankLayers(bankCount)
  local count = math.max(1, math.floor(tonumber(bankCount) or 1))
  self.layers = {}
  self.selectedByLayer = {}
  self.selected = nil
  for bankIdx = 1, count do
    self.layers[#self.layers + 1] = {
      items = {},
      opacity = 1.0,
      name = ("Bank %d"):format(bankIdx),
      kind = "tile",
      bank = bankIdx,
    }
  end
  self:setCurrentBank(clampBankIndex(self, self.currentBank or 1))
end

----------------------------------------------------------------
-- Tile pixel swapping (copy by value, not reference)
----------------------------------------------------------------

-- Swap pixel data between two tiles in the CHR window.
-- This swaps the pixel patterns but keeps the tile references intact.
-- edits: optional edits table to swap edit entries (app.edits)
-- bankIdx: optional bank index (self.currentBank if not provided)
-- appEditState: optional app edit state for duplicate-sync bookkeeping
function ChrBankWindow:swapCells(c1, r1, c2, r2, edits, bankIdx, appEditState)
  if isOddEvenMode(self) then
    r1 = getTopRow(r1)
    r2 = getTopRow(r2)
  end

  if c1 == c2 and r1 == r2 then return end
  
  local Lidx = self.activeLayer or 1
  local L = self:getLayer(Lidx)
  if not L or L.kind ~= "tile" then return end
  
  bankIdx = bankIdx or self.currentBank

  local swapPairs = {
    {
      tileA = self:get(c1, r1, Lidx),
      tileB = self:get(c2, r2, Lidx),
      rowA = r1,
      rowB = r2,
    },
  }

  if isOddEvenMode(self) then
    swapPairs[#swapPairs + 1] = {
      tileA = self:get(c1, r1 + 1, Lidx),
      tileB = self:get(c2, r2 + 1, Lidx),
      rowA = r1 + 1,
      rowB = r2 + 1,
    }
  end

  for _, pair in ipairs(swapPairs) do
    if not pair.tileA or not pair.tileB then return end
    if not pair.tileA.pixels or #pair.tileA.pixels ~= 64 then return end
    if not pair.tileB.pixels or #pair.tileB.pixels ~= 64 then return end
  end

  local bankEdits = edits and edits.banks and bankIdx and edits.banks[bankIdx] or nil
  for _, pair in ipairs(swapPairs) do
    pair.tileA:swapPixelsWith(pair.tileB)
    if bankEdits then
      swapEditEntries(bankEdits, pair.tileA, pair.tileB)
    end
  end

  if edits and type(bankIdx) == "number" then
    for _, pair in ipairs(swapPairs) do
      recordTileSnapshotToEdits(edits, bankIdx, pair.tileA)
      recordTileSnapshotToEdits(edits, bankIdx, pair.tileB)
    end
  end

  if appEditState and bankIdx then
    local targets = {}
    for _, pair in ipairs(swapPairs) do
      if type(pair.tileA.index) == "number" then
        targets[#targets + 1] = { bank = bankIdx, tileIndex = pair.tileA.index }
      end
      if type(pair.tileB.index) == "number" then
        targets[#targets + 1] = { bank = bankIdx, tileIndex = pair.tileB.index }
      end
    end
    if #targets > 0 then
      ChrDuplicateSync.updateTiles(appEditState, targets)
      for _, target in ipairs(targets) do
        BankCanvasSupport.invalidateTile(nil, target.bank, target.tileIndex)
      end
    end
  end
  
  DebugController.log("info", "CHR", "Swapped pixel data between tiles at (%d,%d) and (%d,%d)%s", c1, r1, c2, r2, isOddEvenMode(self) and " in 8x16 mode" or "")
end

return ChrBankWindow
