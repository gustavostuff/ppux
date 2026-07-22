-- Relocation pointer math: ROM file offset --> little-endian CPU pointer bytes.
-- Defaults match Contra-style 16KB banks mapped at $8000 with a 16-byte iNES header.

local M = {}

M.DEFAULT_HEADER_SIZE = 0x10
M.DEFAULT_BANK_SIZE = 0x4000
M.DEFAULT_CPU_MAP_BASE = 0x8000

function M.parseFileOffset(text)
  local raw = tostring(text or ""):match("^%s*(.-)%s*$") or ""
  if raw == "" then
    return nil, "empty"
  end
  raw = raw:gsub("^[$]", ""):gsub("^[0Oo][Xx]", "")
  if raw == "" or not raw:match("^[0-9A-Fa-f]+$") then
    return nil, "invalid_hex"
  end
  local value = tonumber(raw, 16)
  if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
    return nil, "invalid_hex"
  end
  return value
end

function M.formatFileOffset(offset)
  local n = math.floor(tonumber(offset) or 0)
  if n < 0 then n = 0 end
  return string.format("0x%06X", n)
end

local function resolveMapping(opts)
  opts = opts or {}
  local headerSize = math.floor(tonumber(opts.headerSize) or M.DEFAULT_HEADER_SIZE)
  local bankSize = math.floor(tonumber(opts.bankSize) or M.DEFAULT_BANK_SIZE)
  local cpuMapBase = math.floor(tonumber(opts.cpuMapBase) or M.DEFAULT_CPU_MAP_BASE)
  if headerSize < 0 then
    headerSize = M.DEFAULT_HEADER_SIZE
  end
  if bankSize <= 0 then
    bankSize = M.DEFAULT_BANK_SIZE
  end
  if cpuMapBase < 0 then
    cpuMapBase = M.DEFAULT_CPU_MAP_BASE
  end
  return headerSize, bankSize, cpuMapBase
end

function M.formatFormula(opts)
  local headerSize, bankSize, cpuMapBase = resolveMapping(opts)
  return string.format(
    "cpu = ((offset - 0x%X) %% 0x%X) + 0x%X",
    headerSize,
    bankSize,
    cpuMapBase
  )
end

--- @return cpu, lo, hi (or nil, nil, nil, err)
function M.fileOffsetToPointer(romFileOffset, opts)
  local offset = math.floor(tonumber(romFileOffset) or -1)
  if offset < 0 then
    return nil, nil, nil, "invalid_offset"
  end
  local headerSize, bankSize, cpuMapBase = resolveMapping(opts)
  local prgOffset = offset - headerSize
  if prgOffset < 0 then
    return nil, nil, nil, "before_header"
  end
  local bankOffset = prgOffset % bankSize
  local cpu = bankOffset + cpuMapBase
  local lo = cpu % 256
  local hi = math.floor(cpu / 256) % 256
  return cpu, lo, hi
end

function M.formatByte(byteVal)
  return string.format("%02X", math.floor(tonumber(byteVal) or 0) % 256)
end

return M
