-- managers/bank_view_controller.lua
-- Handles CHR bank tiles and the CHR bank window content.

local Tile = require("user_interface.windows_system.tile_item")
local DebugController = require("controllers.dev.debug_controller")

local M = {}

local BANK_COLS = 16
local BANK_TILE_COUNT = 512

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function mapIndexForOrder(orderMode, pos)
  if orderMode == "normal" then return pos end
  local row   = math.floor(pos / BANK_COLS)
  local col   = pos % BANK_COLS
  local pair  = math.floor(row / 2)           -- two rows per 8x16 pair
  local isOdd = (row % 2 == 1)
  return pair * 32 + col * 2 + (isOdd and 1 or 0)
end

-- Ensure all 512 tiles for a CHR bank are present in tilesPool.
-- appEditState:
--   chrBanksBytes[bankIdx] : bytes array
--   tilesPool[bankIdx][i]  : Tile
function M.ensureBankTiles(appEditState, bankIdx)
  appEditState.tilesPool[bankIdx] = appEditState.tilesPool[bankIdx] or {}
  local bank = appEditState.tilesPool[bankIdx]
  if bank.__ready then 
    DebugController.log("info", "BANK", "Bank %d tiles already ready, skipping", bankIdx)
    return 
  end

  DebugController.log("info", "BANK", "Ensuring tiles for bank %d", bankIdx)
  local startedAt = nowSeconds()

  for i = 0, BANK_TILE_COUNT - 1 do
    local t = Tile.fromCHR(appEditState.chrBanksBytes[bankIdx], i)
    t._bankBytesRef = appEditState.chrBanksBytes[bankIdx]
    t._bankIndex    = bankIdx
    bank[i] = t
  end

  bank.__ready = true
  DebugController.log("info", "BANK", "Bank %d tiles initialized (%d tiles)", bankIdx, BANK_TILE_COUNT)
  DebugController.log("info", "LOAD_PERF", "ensureBankTiles bank=%d duration=%.3fs", bankIdx, nowSeconds() - startedAt)
end

function M.getTileRef(appEditState, bankIdx, tileIndex)
  if not (appEditState and appEditState.chrBanksBytes and type(bankIdx) == "number" and type(tileIndex) == "number") then
    return nil
  end

  local bankBytes = appEditState.chrBanksBytes[bankIdx]
  if not bankBytes then
    return nil
  end

  appEditState.tilesPool = appEditState.tilesPool or {}
  appEditState.tilesPool[bankIdx] = appEditState.tilesPool[bankIdx] or {}
  local bank = appEditState.tilesPool[bankIdx]
  local tile = bank[tileIndex]
  if tile then
    return tile
  end

  local created = Tile.fromCHR(bankBytes, tileIndex)
  created._bankBytesRef = bankBytes
  created._bankIndex = bankIdx
  bank[tileIndex] = created
  DebugController.perfIncrement("chr_tile_create")
  return created
end

local function fillBankWindowLayer(winBank, appEditState, bankIdx, orderMode)
  if not winBank or winBank.kind ~= "chr" then return end
  if not (appEditState and appEditState.tilesPool and appEditState.chrBanksBytes) then return end

  M.ensureBankTiles(appEditState, bankIdx)
  local bank = appEditState.tilesPool[bankIdx]
  local layer = winBank:getLayer(bankIdx)
  if not (bank and layer) then return end

  layer.items = {}
  layer.kind = "tile"
  layer.name = ("Bank %d"):format(bankIdx)
  layer.bank = bankIdx

  for r = 0, winBank.rows - 1 do
    for c = 0, winBank.cols - 1 do
      local pos = r * winBank.cols + c
      if pos >= BANK_TILE_COUNT then break end
      local idx = mapIndexForOrder(orderMode, pos)
      local t   = bank[idx]
      if t then
        layer.items[(r * winBank.cols) + c + 1] = t
      end
    end
  end
end

-- Rebuild CHR/ROM bank window layers based on current bank + orderMode.
-- setStatus(text) is optional; used to update status bar.
function M.rebuildBankWindowItems(winBank, appEditState, orderMode, setStatus)
  if not winBank then return end
  if not (appEditState and appEditState.chrBanksBytes and #appEditState.chrBanksBytes > 0) then
    return
  end

  DebugController.log("info", "BANK", "Rebuilding bank window items - bank: %d, orderMode: %s", appEditState.currentBank or 1, orderMode or "normal")
  local bankCount = math.max(1, #((appEditState and appEditState.chrBanksBytes) or {}))
  winBank.appEditState = appEditState

  if winBank.resetBankLayers then
    winBank:resetBankLayers(bankCount)
  end

  local targetBank = tonumber(appEditState and appEditState.currentBank) or tonumber(winBank.currentBank) or 1
  if winBank.setCurrentBank then
    winBank:setCurrentBank(targetBank)
  else
    winBank.currentBank = targetBank
    winBank.activeLayer = targetBank
  end
  if appEditState then
    appEditState.currentBank = winBank.currentBank or targetBank
  end

  if setStatus and appEditState.chrBanksBytes then
    local txt = ("Bank %d/%d - Tile Mode: drag by ref (Tab to switch)")
      :format(winBank.currentBank or appEditState.currentBank or 1, #appEditState.chrBanksBytes)
    setStatus(txt)
  end
end

return M
