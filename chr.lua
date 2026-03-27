-- chr.lua — iNES (1.0) parser + CHR helpers

local chr = {}

local function u8(x) return math.fmod(tonumber(x) or 0, 256) end
local function u8_str(s, i) return string.byte(s, i, i) or 0 end
local function slice(s, startIdx, len) return s:sub(startIdx, startIdx + len - 1) end

-- ==== byte-table helpers ====
function chr.stringToBytes(s)
  local t = {}
  for i = 1, #s do t[i] = u8_str(s, i) end
  return t
end

function chr.bytesToString(t)
  local tmp = {}
  for i = 1, #t do tmp[i] = string.char(t[i]) end
  return table.concat(tmp)
end

function chr.concatBanksToString(banksBytes)
  local parts = {}
  for i = 1, #banksBytes do parts[i] = chr.bytesToString(banksBytes[i]) end
  return table.concat(parts)
end

-- ==== math bit helpers (no bitlib) ====
local function bitAt(byte, bitIndex) return math.floor(byte / (2 ^ bitIndex)) % 2 end
local function setBitValue(byte, bitIndex, value)
  local pow = 2 ^ bitIndex
  local cur = math.floor(byte / pow) % 2
  if value == 1 then
    if cur == 0 then byte = byte + pow end
  else
    if cur == 1 then byte = byte - pow end
  end
  return byte
end

-- ==== Parse iNES 1.0 ====
function chr.parseINES(bytes)
  if type(bytes) ~= "string" or #bytes < 16 then error("Not a valid ROM: too small") end
  if bytes:sub(1,4) ~= "NES\x1A" then error("Not a valid iNES header") end

  local prg_count = u8_str(bytes, 5)
  local chr_count = u8_str(bytes, 6)
  local flags6 = u8_str(bytes, 7)

  local has_trainer = (math.floor(flags6 / 0x04) % 2) == 1
  local offset = 16
  if has_trainer then offset = offset + 512 end

  local prg_size = prg_count * 16384
  local chr_size = chr_count * 8192

  if #bytes < offset + prg_size + chr_size then
    error(("ROM truncated: need >= %d, got %d"):format(offset + prg_size + chr_size, #bytes))
  end

  local prgBanks = {}
  for i = 1, prg_count do
    local start = offset + (i-1)*16384 + 1
    prgBanks[i] = slice(bytes, start, 16384)
  end
  offset = offset + prg_size

  local chrBanks = {}
  for i = 1, chr_count do
    local start = offset + (i-1)*8192 + 1
    chrBanks[i] = slice(bytes, start, 8192)
  end

  local chr_start = 16 + (has_trainer and 512 or 0) + prg_size + 1        -- 1-based
  local chr_end   = chr_start + chr_size - 1                               -- inclusive

  return {
    prg_count = prg_count,
    chr_count = chr_count,
    prg = prgBanks,
    chr = chrBanks,
    meta = {
      chr_start = chr_start,               -- inclusive (1-based)
      chr_end   = chr_end,                 -- inclusive (1-based)
      prg_size  = prg_size,
      chr_size  = chr_size,
      has_trainer = has_trainer,
      rom_size  = #bytes,
    }
  }
end

-- ==== CHR decode/encode helpers ====
local function u8_any(buf, i)
  if type(buf) == "string" then return u8_str(buf, i) else return buf[i] or 0 end
end

function chr.decodeTile(chrBank, tileIndex)
  local base = tileIndex * 16
  local total = (type(chrBank) == "string") and #chrBank or #chrBank
  if base + 16 > total then return nil, "Tile out of range" end
  local pixels = {}
  for row = 0, 7 do
    local p0 = u8_any(chrBank, base + 1 + row)
    local p1 = u8_any(chrBank, base + 1 + 8 + row)
    for col = 0, 7 do
      local bit = 7 - col
      local lo = bitAt(p0, bit)
      local hi = bitAt(p1, bit)
      pixels[row * 8 + col + 1] = lo + hi * 2
    end
  end
  return pixels
end

function chr.setTilePixel(bankBytes, tileIndex, x, y, color)
  local base = tileIndex * 16
  local idx0 = base + 1 + y
  local idx1 = base + 1 + 8 + y
  local p0 = bankBytes[idx0] or 0
  local p1 = bankBytes[idx1] or 0
  local bit = 7 - x
  local lo = color % 2
  local hi = math.floor(color / 2) % 2
  bankBytes[idx0] = setBitValue(p0, bit, lo)
  bankBytes[idx1] = setBitValue(p1, bit, hi)
end

-- ==== Safe ROM reassembly: keep suffix after CHR region ====
function chr.replaceCHR(romRaw, meta, banksBytes)
  local newCHR = chr.concatBanksToString(banksBytes)
  -- Enforce exact size from header
  if #newCHR ~= meta.chr_size then
    error(("CHR size mismatch: header=%d, new=%d"):format(meta.chr_size, #newCHR))
  end
  local prefix = romRaw:sub(1, meta.chr_start - 1)
  local suffix = romRaw:sub(meta.chr_end + 1)  -- keep anything after CHR
  return prefix .. newCHR .. suffix
end

-- ==== Generic ROM byte I/O on a Lua string (1-based absolute addresses) ====

-- Read a single byte at a 1-based absolute ROM address.
-- romRaw: string of the full ROM file contents
-- addr:  0-based index into romRaw
-- returns: byte (0..255) or nil, "error"
function chr.readByteFromAddress(romRaw, addr)
  addr = addr + 1
  if type(romRaw) ~= "string" then
    return nil, "romRaw must be a string"
  end
  if type(addr) ~= "number" then
    return nil, "addr must be a number"
  end
  if addr < 1 or addr > #romRaw then
    return nil, "address out of range"
  end
  return string.byte(romRaw, addr)
end

-- Write a single byte at a 1-based absolute ROM address.
-- romRaw: string of the full ROM file contents
-- addr:  0-based index into romRaw
-- value: byte (0..255)
-- returns: newRom (string) or nil, "error"
function chr.writeByteToAddress(romRaw, addr, value)
  addr = addr + 1
  if type(romRaw) ~= "string" then
    return nil, "romRaw must be a string"
  end
  if type(addr) ~= "number" then
    return nil, "addr must be a number"
  end
  if addr < 1 or addr > #romRaw then
    return nil, "address out of range"
  end
  local v = math.floor(tonumber(value) or 0) % 256
  local prefix = (addr > 1) and romRaw:sub(1, addr - 1) or ""
  local suffix = (addr < #romRaw) and romRaw:sub(addr + 1) or ""
  return prefix .. string.char(v) .. suffix
end


-- Write bytes starting at 0-based address addrA, over exactly previousSize bytes.
-- If 'bytes' is shorter than previousSize, pad the remainder with 0xFF.
-- If 'bytes' is longer, it is truncated to previousSize.
-- 'bytes' may be a table of numbers (0..255) or a raw string of bytes.
-- Returns: newRom (string) or nil, "error"
function chr.writeBytesToRange(romRaw, startAddr, previousSize, bytes)
  if type(romRaw) ~= "string" then
    return nil, "romRaw must be a string"
  end
  if type(startAddr) ~= "number" or type(previousSize) ~= "number" then
    return nil, "startAddr/previousSize must be numbers"
  end

  local a = math.floor(startAddr) + 1              -- convert to 1-based
  local span = math.max(0, math.floor(previousSize))
  if span == 0 then
    -- Nothing to overwrite; return original ROM unchanged
    return romRaw
  end

  local b = a + span - 1                        -- inclusive end (1-based)
  if a < 1 or b > #romRaw then
    return nil, "address range out of rom bounds"
  end

  -- Build exactly 'span' bytes to write
  local tmp = {}
  if type(bytes) == "string" then
    for i = 1, span do
      local v = string.byte(bytes, i, i)
      if v == nil then v = 0xFF end
      tmp[i] = string.char(u8(v))
    end
  else
    bytes = bytes or {}
    for i = 1, span do
      local v = bytes[i]
      if v == nil then v = 0xFF end
      tmp[i] = string.char(u8(v))
    end
  end
  local mid = table.concat(tmp)

  local prefix = (a > 1) and romRaw:sub(1, a - 1) or ""
  local suffix = (b < #romRaw) and romRaw:sub(b + 1) or ""
  return prefix .. mid .. suffix
end

-- Write bytes starting at a given address (no size limit, just writes what's provided).
-- If the new data is smaller than what was there, remaining bytes stay as-is.
-- As long as the data ends with FF FF terminator, the decoder will stop correctly.
-- Returns: newRom (string) or nil, "error"
function chr.writeBytesStartingAt(romRaw, startAddr, bytes)
  if type(romRaw) ~= "string" then
    return nil, "romRaw must be a string"
  end
  if type(startAddr) ~= "number" then
    return nil, "startAddr must be a number"
  end

  local a = math.floor(startAddr) + 1  -- convert to 1-based
  if a < 1 then
    return nil, "startAddr out of bounds"
  end

  -- Convert bytes to string
  local bytesString
  if type(bytes) == "string" then
    bytesString = bytes
  else
    bytes = bytes or {}
    local tmp = {}
    for i = 1, #bytes do
      local v = bytes[i]
      if v == nil then v = 0xFF end
      tmp[i] = string.char(u8(v))
    end
    bytesString = table.concat(tmp)
  end

  local bytesLen = #bytesString
  if bytesLen == 0 then
    return romRaw  -- Nothing to write
  end

  -- Build the new ROM: prefix + new bytes + suffix
  local prefix = (a > 1) and romRaw:sub(1, a - 1) or ""
  local suffix = (a + bytesLen <= #romRaw) and romRaw:sub(a + bytesLen) or ""
  return prefix .. bytesString .. suffix
end

-- Read a span of bytes at 0-based addresses [addrA, addrB] inclusive.
-- Returns: table of numbers (0..255), or nil, "error"
function chr.readBytesFromRange(romRaw, addrA, addrB)
  if type(romRaw) ~= "string" then
    return nil, "romRaw must be a string"
  end
  if type(addrA) ~= "number" or type(addrB) ~= "number" then
    return nil, "addrA/addrB must be numbers"
  end

  local a = math.floor(addrA) + 1
  local b = math.floor(addrB) + 1
  if a > b then a, b = b, a end

  if a < 1 or b > #romRaw then
    return nil, "address range out of rom bounds"
  end

  local out = {}
  for i = a, b do
    out[#out + 1] = string.byte(romRaw, i)
  end
  return out
end

function chr.decimalToHex(dec)
  return string.format("%02X", dec)
end

return chr
