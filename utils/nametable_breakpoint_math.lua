-- Nametable cell → PPU address for FCEUX write breakpoints
-- (finding stream pointer *sites*, not pointer values).

local M = {}

M.DEFAULT_NAMETABLE_BASE = 0x2000
M.NAMETABLE_COLS = 32
M.NAMETABLE_ROWS = 30
M.ATTR_START = 0x23C0

local VALID_BASES = {
  [0x2000] = true,
  [0x2400] = true,
  [0x2800] = true,
  [0x2C00] = true,
}

function M.parseCellIndex(text, maxInclusive)
  local raw = tostring(text or ""):match("^%s*(.-)%s*$") or ""
  if raw == "" then
    return nil, "empty"
  end
  local hadHexPrefix = raw:match("^[$]") or raw:match("^[0Oo][Xx]")
  raw = raw:gsub("^[$]", ""):gsub("^[0Oo][Xx]", "")
  if raw == "" then
    return nil, "empty"
  end
  local value
  if hadHexPrefix or raw:match("[A-Fa-f]") then
    if not raw:match("^[0-9A-Fa-f]+$") then
      return nil, "invalid"
    end
    value = tonumber(raw, 16)
  elseif raw:match("^[0-9]+$") then
    value = tonumber(raw, 10)
  else
    return nil, "invalid"
  end
  if type(value) ~= "number" or value ~= math.floor(value) or value < 0 then
    return nil, "invalid"
  end
  if maxInclusive ~= nil and value > maxInclusive then
    return nil, "out_of_range"
  end
  return value
end

function M.parseTileIndex(text)
  local raw = tostring(text or ""):match("^%s*(.-)%s*$") or ""
  if raw == "" then
    return nil, "empty"
  end
  raw = raw:gsub("^[$]", ""):gsub("^[0Oo][Xx]", ""):gsub("^#", "")
  if raw == "" or not raw:match("^[0-9A-Fa-f]+$") then
    return nil, "invalid"
  end
  local value = tonumber(raw, 16)
  if type(value) ~= "number" or value ~= math.floor(value) or value < 0 or value > 0xFF then
    return nil, "invalid"
  end
  return value
end

function M.formatTileByte(tile)
  return string.format("%02X", math.floor(tonumber(tile) or 0) % 256)
end

function M.formatPpuAddress(addr)
  return string.format("$%04X", math.floor(tonumber(addr) or 0) % 0x10000)
end

function M.formatConditionA(tile)
  return string.format("A == #%s", M.formatTileByte(tile))
end

function M.formatConditionW(tile)
  return string.format("W == #%s", M.formatTileByte(tile))
end

--- @return ppuAddr, warnKey (warnKey may be "attributes" or nil), or nil, err
function M.cellToPpuAddress(col, row, opts)
  opts = opts or {}
  local base = math.floor(tonumber(opts.nametableBase) or M.DEFAULT_NAMETABLE_BASE)
  if not VALID_BASES[base] then
    return nil, nil, "bad_base"
  end
  col = math.floor(tonumber(col) or -1)
  row = math.floor(tonumber(row) or -1)
  if col < 0 or col >= M.NAMETABLE_COLS then
    return nil, nil, "bad_col"
  end
  if row < 0 or row >= M.NAMETABLE_ROWS then
    return nil, nil, "bad_row"
  end
  local addr = base + (row * M.NAMETABLE_COLS) + col
  local warn = nil
  -- Attribute table occupies the last 64 bytes of each nametable region.
  local attrStart = base + 0x3C0
  if addr >= attrStart and addr <= (base + 0x3FF) then
    warn = "attributes"
  end
  return addr, warn
end

return M
