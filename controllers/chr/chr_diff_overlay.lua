-- Visual diff overlays for CHR bank grid: compares current CHR bytes vs load baseline.

local BANK_TILE_COLS = 16
local BANK_TILE_COUNT = 512
local TILE_SIZE = 8

local function mapIndexForOrder(orderMode, pos)
  if orderMode ~= "oddEven" then
    return pos
  end
  local row = math.floor(pos / BANK_TILE_COLS)
  local col = pos % BANK_TILE_COLS
  local pair = math.floor(row / 2)
  local isOdd = (row % 2 == 1)
  return pair * 32 + col * 2 + (isOdd and 1 or 0)
end

local function tileBytesChanged(origBank, curBank, tileIndex)
  local base = math.floor(tonumber(tileIndex) or 0) * 16
  for offset = 1, 16 do
    local bi = base + offset
    local before = origBank and origBank[bi] or 0
    local after = curBank and curBank[bi] or 0
    if before ~= after then
      return true
    end
  end
  return false
end

local M = {}

-- Exposed for tests (CHR grid vs baseline, 16 bytes per tile).
M.tileBytesChanged = tileBytesChanged
M.mapIndexForOrder = mapIndexForOrder

function M.cellChanged(origBank, curBank, orderMode, gridPos)
  gridPos = math.floor(tonumber(gridPos) or 0)
  if gridPos < 0 or gridPos >= BANK_TILE_COUNT then
    return false
  end
  if orderMode ~= "oddEven" then
    local ti = mapIndexForOrder("normal", gridPos)
    return tileBytesChanged(origBank, curBank, ti)
  end
  local row = math.floor(gridPos / BANK_TILE_COLS)
  local col = gridPos % BANK_TILE_COLS
  local pairRow = math.floor(row / 2)
  local pos0 = pairRow * 32 + col
  local pos1 = pos0 + 16
  local t0 = mapIndexForOrder("oddEven", pos0)
  local t1 = mapIndexForOrder("oddEven", pos1)
  return tileBytesChanged(origBank, curBank, t0) or tileBytesChanged(origBank, curBank, t1)
end

function M.draw(state, win, layerOpacity)
  if not win or not state or win.showChrDiffMode ~= true then
    return
  end
  local bankIdx = tonumber(win.currentBank) or tonumber(state.currentBank) or 1
  local cur = state.chrBanksBytes and state.chrBanksBytes[bankIdx]
  if not cur then
    return
  end
  local orig = state.originalChrBanksBytes and state.originalChrBanksBytes[bankIdx]
  local orderMode = (win.orderMode == "oddEven") and "oddEven" or "normal"
  local aMul = tonumber(layerOpacity) or 1.0
  if aMul <= 0.001 then
    return
  end

  local baseAlpha = 0.5

  love.graphics.push("all")

  love.graphics.setBlendMode("alpha")
  for pos = 0, BANK_TILE_COUNT - 1 do
    local changed = M.cellChanged(orig, cur, orderMode, pos)
    if changed then
      love.graphics.setColor(0, 1, 0, baseAlpha * aMul)
    else
      love.graphics.setColor(0, 0, 0, baseAlpha * aMul)
    end
    local tc = pos % BANK_TILE_COLS
    local tr = math.floor(pos / BANK_TILE_COLS)
    love.graphics.rectangle("fill", tc * TILE_SIZE, tr * TILE_SIZE, TILE_SIZE, TILE_SIZE)
  end

  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
end

return M
