-- chr_duplicate_sync.lua
-- Tracks duplicate CHR tiles and helps apply edits across identical tiles.

local chr = require("chr")

local M = {}

local function markIndexIncomplete(state)
  if not state then return end
  state.tileSignatureIndexReady = false
end

local function markIndexReady(state)
  if not state then return end
  state.tileSignatureIndexReady = true
end

local function hasCompleteIndex(state)
  return state
    and state.tileSignatureIndexReady == true
    and type(state.tileSignatureIndex) == "table"
    and type(state.tileSignatureByTile) == "table"
end

-- Flat single-color tiles are intentionally excluded from duplicate sync.
local function isFlatColorTile(bankBytes, tileIndex)
  if not bankBytes then return false end
  local base = tileIndex * 16
  local plane0 = bankBytes[base + 1] or 0
  local plane1 = bankBytes[base + 9] or 0

  if not ((plane0 == 0 or plane0 == 255) and (plane1 == 0 or plane1 == 255)) then
    return false
  end

  for row = 1, 8 do
    if (bankBytes[base + row] or 0) ~= plane0 then
      return false
    end
    if (bankBytes[base + 8 + row] or 0) ~= plane1 then
      return false
    end
  end

  return true
end

-- Build a stable signature for a tile using its 16 CHR bytes (faster than decoding pixels).
local function buildSignature(bankBytes, tileIndex)
  if not bankBytes then return nil end
  if isFlatColorTile(bankBytes, tileIndex) then
    return nil
  end
  local base = tileIndex * 16
  local tmp = {}
  for i = 1, 16 do
    tmp[i] = bankBytes[base + i] or 0
  end
  return table.concat(tmp, ",")
end

local function ensureIndexes(state)
  state.tileSignatureIndex = state.tileSignatureIndex or {}
  state.tileSignatureByTile = state.tileSignatureByTile or {}
end

local function removeFromIndex(state, signature, bankIdx, tileIndex)
  if not signature then return end
  local list = state.tileSignatureIndex and state.tileSignatureIndex[signature]
  if not list then return end
  for i = #list, 1, -1 do
    local entry = list[i]
    if entry.bank == bankIdx and entry.tileIndex == tileIndex then
      table.remove(list, i)
      break
    end
  end
  if #list == 0 then
    state.tileSignatureIndex[signature] = nil
  end
end

-- Recompute and store signature for a single tile.
local function reindexTile(state, bankIdx, tileIndex)
  if not state or not state.chrBanksBytes then return nil end
  local bankBytes = state.chrBanksBytes[bankIdx]
  if not bankBytes then return nil end

  ensureIndexes(state)

  state.tileSignatureByTile[bankIdx] = state.tileSignatureByTile[bankIdx] or {}
  local prevSig = state.tileSignatureByTile[bankIdx][tileIndex]
  local sig = buildSignature(bankBytes, tileIndex)

  if prevSig ~= sig then
    removeFromIndex(state, prevSig, bankIdx, tileIndex)
  end

  state.tileSignatureByTile[bankIdx][tileIndex] = sig
  if not sig then
    return nil
  end

  state.tileSignatureIndex[sig] = state.tileSignatureIndex[sig] or {}

  local list = state.tileSignatureIndex[sig]
  local alreadyPresent = false
  for _, entry in ipairs(list) do
    if entry.bank == bankIdx and entry.tileIndex == tileIndex then
      alreadyPresent = true
      break
    end
  end
  if not alreadyPresent then
    list[#list + 1] = { bank = bankIdx, tileIndex = tileIndex }
  end

  return sig
end

-- Public: rebuild indexes for every tile in every bank.
function M.reindexAllBanks(state)
  if not state or not state.chrBanksBytes then return end
  state.syncGroups = nil
  state.tileSignatureIndex = {}
  state.tileSignatureByTile = {}
  for bankIdx, bankBytes in ipairs(state.chrBanksBytes) do
    local tileCount = math.floor(#bankBytes / 16)
    state.tileSignatureByTile[bankIdx] = {}
    for tileIndex = 0, tileCount - 1 do
      reindexTile(state, bankIdx, tileIndex)
    end
  end
  markIndexReady(state)
end

-- Public: rebuild indexes for a single bank.
function M.reindexBank(state, bankIdx)
  if not state or not state.chrBanksBytes then return end
  local bankBytes = state.chrBanksBytes[bankIdx]
  if not bankBytes then return end
  if not hasCompleteIndex(state) then
    markIndexIncomplete(state)
    return
  end

  state.syncGroups = nil

  ensureIndexes(state)
  state.tileSignatureByTile[bankIdx] = {}

  -- Remove any previous entries for this bank
  if state.tileSignatureIndex then
    for sig, entries in pairs(state.tileSignatureIndex) do
      for i = #entries, 1, -1 do
        if entries[i].bank == bankIdx then
          table.remove(entries, i)
        end
      end
      if #entries == 0 then
        state.tileSignatureIndex[sig] = nil
      end
    end
  end

  local tileCount = math.floor(#bankBytes / 16)
  for tileIndex = 0, tileCount - 1 do
    reindexTile(state, bankIdx, tileIndex)
  end
end

-- Public: return list of tiles identical to the given tile (always includes the tile itself).
function M.getMatchingTiles(state, bankIdx, tileIndex, forceReindex)
  if not state or not state.chrBanksBytes then return {} end
  if forceReindex or not hasCompleteIndex(state) then
    M.reindexAllBanks(state)
  end

  local sig = reindexTile(state, bankIdx, tileIndex)
  if not sig then
    return {}
  end

  local matches = state.tileSignatureIndex[sig] or {}
  local out = {}
  for _, entry in ipairs(matches) do
    out[#out + 1] = { bank = entry.bank, tileIndex = entry.tileIndex }
  end

  if #out == 0 then
    return { { bank = bankIdx, tileIndex = tileIndex } }
  end
  return out
end

-- Public: refresh signatures for a set of tiles after they change.
function M.updateTiles(state, targets)
  if not state or not targets then return end
  if not hasCompleteIndex(state) then
    markIndexIncomplete(state)
    return
  end
  state.syncGroups = state.syncGroups -- keep groups frozen until explicitly rebuilt
  for _, target in ipairs(targets) do
    reindexTile(state, target.bank, target.tileIndex)
  end
end

-- Public: rebuild frozen sync groups based on current signatures.
function M.buildSyncGroups(state)
  if not state or not state.chrBanksBytes then return end
  -- Ensure signature index is up to date
  M.reindexAllBanks(state)

  local groupsBySig = {}
  for sig, entries in pairs(state.tileSignatureIndex or {}) do
    groupsBySig[sig] = {}
    for _, entry in ipairs(entries) do
      groupsBySig[sig][#groupsBySig[sig] + 1] = { bank = entry.bank, tileIndex = entry.tileIndex }
    end
  end

  state.syncGroups = {}
  for sig, grp in pairs(groupsBySig) do
    for _, entry in ipairs(grp) do
      state.syncGroups[entry.bank] = state.syncGroups[entry.bank] or {}
      state.syncGroups[entry.bank][entry.tileIndex] = grp
    end
  end
end

function M.clearSyncGroups(state)
  if state then
    state.syncGroups = nil
    state.tileSignatureIndex = nil
    state.tileSignatureByTile = nil
    markIndexIncomplete(state)
  end
end

-- Public: get frozen sync group (falls back to just the tile).
function M.getSyncGroup(state, bankIdx, tileIndex, enabled)
  if not enabled then
    return { { bank = bankIdx, tileIndex = tileIndex } }
  end

  local bankBytes = state and state.chrBanksBytes and state.chrBanksBytes[bankIdx] or nil
  if not buildSignature(bankBytes, tileIndex) then
    return { { bank = bankIdx, tileIndex = tileIndex } }
  end

  if state and state.syncGroups and state.syncGroups[bankIdx] and state.syncGroups[bankIdx][tileIndex] then
    return state.syncGroups[bankIdx][tileIndex]
  end

  return { { bank = bankIdx, tileIndex = tileIndex } }
end

-- Public: check if sync mode is enabled (default false).
function M.isEnabled(app)
  if not app then return false end
  return app.syncDuplicateTiles == true
end

function M.isAvailableForWindow(win)
  if not win then return true end
  return not (win.kind == "chr" and win.isRomWindow == true)
end

function M.isEnabledForWindow(app, win)
  return M.isEnabled(app) and M.isAvailableForWindow(win)
end

return M
