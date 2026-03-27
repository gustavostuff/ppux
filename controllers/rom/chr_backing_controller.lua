-- chr_backing_controller.lua
-- Abstraction for CHR-like backing storage:
--   - "chr_rom": real CHR banks from iNES CHR ROM
--   - "rom_raw": pseudo CHR banks over raw ROM data (CHR-RAM carts)

local chr = require("chr")

local M = {}

M.PSEUDO_CHR_BANK_SIZE = 8192
M.MODES = {
  CHR_ROM = "chr_rom",
  ROM_RAW = "rom_raw",
}

local function splitRomRawIntoPseudoChrBanks(romRaw, dataOffset)
  local banks = {}
  if type(romRaw) ~= "string" or #romRaw == 0 then
    return banks
  end

  dataOffset = math.max(0, math.floor(tonumber(dataOffset) or 0))
  local dataStart = dataOffset + 1 -- Lua strings are 1-based
  local viewRaw = romRaw:sub(dataStart)
  if #viewRaw == 0 then
    return banks
  end

  local bankCount = math.max(1, math.ceil(#viewRaw / M.PSEUDO_CHR_BANK_SIZE))
  for i = 1, bankCount do
    local startPos = ((i - 1) * M.PSEUDO_CHR_BANK_SIZE) + 1
    local chunk = viewRaw:sub(startPos, startPos + M.PSEUDO_CHR_BANK_SIZE - 1)
    local bytes = chr.stringToBytes(chunk)
    for bi = #bytes + 1, M.PSEUDO_CHR_BANK_SIZE do
      bytes[bi] = 0
    end
    banks[i] = bytes
  end
  return banks
end

local function normalizeBackingDescriptor(backing, romRaw)
  backing = backing or {}
  local mode = backing.mode
  if mode ~= M.MODES.CHR_ROM and mode ~= M.MODES.ROM_RAW then
    mode = M.MODES.CHR_ROM
  end
  backing.mode = mode
  backing.bankSize = tonumber(backing.bankSize) or M.PSEUDO_CHR_BANK_SIZE
  backing.originalSize = tonumber(backing.originalSize)
  backing.dataOffset = math.max(0, math.floor(tonumber(backing.dataOffset) or 0))
  backing.dataSize = tonumber(backing.dataSize)
  if backing.dataSize ~= nil then
    backing.dataSize = math.max(0, math.floor(backing.dataSize))
  elseif mode == M.MODES.ROM_RAW and type(romRaw) == "string" then
    backing.dataSize = math.max(0, #romRaw - backing.dataOffset)
  end
  return backing
end

function M.syncLegacyFields(state)
  if type(state) ~= "table" then return end
  local backing = normalizeBackingDescriptor(state.chrBacking, state.romRaw)
  state.chrBacking = backing

  local isRomRaw = (backing.mode == M.MODES.ROM_RAW)
  state.romTileViewMode = isRomRaw
  state.romTileViewOriginalSize = isRomRaw and backing.originalSize or nil
  state.romTileViewDataOffset = isRomRaw and backing.dataOffset or nil
  state.romTileViewDataSize = isRomRaw and backing.dataSize or nil
end

function M.getDescriptor(state)
  if type(state) ~= "table" then return nil end
  if type(state.chrBacking) ~= "table" then
    local mode = (state.romTileViewMode == true) and M.MODES.ROM_RAW or M.MODES.CHR_ROM
    state.chrBacking = {
      mode = mode,
      bankSize = M.PSEUDO_CHR_BANK_SIZE,
      originalSize = state.romTileViewOriginalSize,
      dataOffset = state.romTileViewDataOffset,
      dataSize = state.romTileViewDataSize,
    }
  end
  M.syncLegacyFields(state)
  return state.chrBacking
end

function M.getMode(state)
  local d = M.getDescriptor(state)
  return d and d.mode or M.MODES.CHR_ROM
end

function M.isRomRawMode(state)
  return M.getMode(state) == M.MODES.ROM_RAW
end

function M.resetState(state)
  if type(state) ~= "table" then return end
  state.chrBacking = {
    mode = M.MODES.CHR_ROM,
    bankSize = M.PSEUDO_CHR_BANK_SIZE,
    originalSize = nil,
    dataOffset = nil,
    dataSize = nil,
  }
  M.syncLegacyFields(state)
end

function M.configureFromParsedINES(state, parsed)
  if type(state) ~= "table" then
    return nil, "invalid-state"
  end
  if type(parsed) ~= "table" or type(parsed.chr) ~= "table" then
    return nil, "invalid-parsed-ines"
  end

  state.chrBanksBytes = {}

  if #parsed.chr == 0 then
    local romRaw = state.romRaw
    local offset = 16 -- skip iNES header in ROM-backed tile viewer
    state.chrBacking = {
      mode = M.MODES.ROM_RAW,
      bankSize = M.PSEUDO_CHR_BANK_SIZE,
      originalSize = type(romRaw) == "string" and #romRaw or nil,
      dataOffset = offset,
      dataSize = (type(romRaw) == "string") and math.max(0, #romRaw - offset) or 0,
    }
    state.chrBanksBytes = splitRomRawIntoPseudoChrBanks(romRaw, offset)
  else
    state.chrBacking = {
      mode = M.MODES.CHR_ROM,
      bankSize = M.PSEUDO_CHR_BANK_SIZE,
      originalSize = nil,
      dataOffset = nil,
      dataSize = nil,
    }
    for i = 1, #parsed.chr do
      state.chrBanksBytes[i] = chr.stringToBytes(parsed.chr[i])
    end
  end

  M.syncLegacyFields(state)
  return state.chrBanksBytes
end

function M.rebuildROMFromBacking(state)
  if not M.isRomRawMode(state) then
    return nil, "Backing mode is not rom_raw"
  end

  local banks = state and state.chrBanksBytes
  if type(banks) ~= "table" or #banks == 0 then
    return nil, "No ROM banks available"
  end

  local baseRom = state and state.romRaw
  if type(baseRom) ~= "string" or #baseRom == 0 then
    return nil, "Missing base ROM"
  end

  local backing = M.getDescriptor(state)
  local dataOffset = math.max(0, math.floor(tonumber(backing.dataOffset) or 0))
  local dataSize = tonumber(backing.dataSize)
  if dataSize == nil then
    dataSize = math.max(0, #baseRom - dataOffset)
  end
  dataSize = math.max(0, math.floor(dataSize))

  local body = chr.concatBanksToString(banks)
  if #body > dataSize then
    body = body:sub(1, dataSize)
  end

  local prefix = (dataOffset > 0) and baseRom:sub(1, dataOffset) or ""
  local suffixStart = dataOffset + dataSize + 1
  local suffix = (suffixStart <= #baseRom) and baseRom:sub(suffixStart) or ""
  local raw = prefix .. body .. suffix

  local originalSize = tonumber(backing.originalSize) or #raw
  if originalSize >= 0 and originalSize < #raw then
    raw = raw:sub(1, originalSize)
  end
  return raw
end

return M
