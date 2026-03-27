-- codecs/konami.lua
-- Konami-style nametable codec used by games like Contra and Castlevania.

local DebugController = require("controllers.dev.debug_controller")

local function u8(x) return math.fmod(x or 0, 256) end
local function band127(x) return math.fmod(x or 0, 128) end
local function wrap14(x) return math.fmod((x or 0), 16384) end
local function is_data_opcode(b)
  -- Valid data opcodes are 0x01..0xFE.
  return b and b > 0 and b < 0xFF
end

local M = {}

function M.encode_nametable(nametable, attributes)
  nametable = nametable or {}
  attributes = attributes or {}

  if #nametable ~= 960 then
    DebugController.log("error", "KONAMI_CODEC", "nametable bytes should be 960 bytes, but got %d bytes", #nametable)
  end
  if #attributes ~= 64 then
    DebugController.log("error", "KONAMI_CODEC", "attr bytes should be 64 bytes, but got %d bytes", #attributes)
  end

  local src = {}
  for i = 1, #nametable do src[#src+1] = u8(nametable[i]) end
  -- Ensure attributes are always exactly 64 bytes.
  for i = 1, 64 do
    if i <= #attributes then
      src[#src+1] = u8(attributes[i])
    else
      src[#src+1] = 0x00
    end
  end

  -- Ensure the decoded page payload is exactly $400 bytes (1024).
  while #src < 1024 do src[#src+1] = 0 end
  if #src > 1024 then
    local trimmed = {}
    for i = 1, 1024 do trimmed[i] = src[i] end
    src = trimmed
  end

  local MAX_BLOCK = 0x7E
  local N = #src

  -- Precompute maximal RLE run length at each source position.
  local runMax = {}
  for i = 1, N do
    local v = src[i]
    local run = 1
    while (i + run <= N) and (src[i + run] == v) and (run < MAX_BLOCK) do
      run = run + 1
    end
    runMax[i] = run
  end

  -- Dynamic programming:
  -- dp[i] = minimal encoded payload size (without address+terminator) for src[i..N].
  -- choice* arrays keep how we reached dp[i].
  local INF = 10 ^ 9
  local dp = {}
  local choiceKind = {}
  local choiceLen = {}

  dp[N + 1] = 0

  for i = N, 1, -1 do
    local bestCost = INF
    local bestKind = nil
    local bestLen = 0

    -- Literal block: opcode (1 byte) + len bytes.
    local maxLit = math.min(MAX_BLOCK, N - i + 1)
    for len = 1, maxLit do
      local cost = 1 + len + (dp[i + len] or INF)
      if cost < bestCost or (cost == bestCost and len > bestLen) then
        bestCost = cost
        bestKind = "lit"
        bestLen = len
      end
    end

    -- RLE block: opcode + value (2 bytes), valid for run length >= 2.
    local maxRun = runMax[i] or 1
    if maxRun >= 2 then
      for len = 2, maxRun do
        local cost = 2 + (dp[i + len] or INF)
        if cost < bestCost or (cost == bestCost and len > bestLen) then
          bestCost = cost
          bestKind = "rle"
          bestLen = len
        end
      end
    end

    dp[i] = bestCost
    choiceKind[i] = bestKind
    choiceLen[i] = bestLen
  end

  local out = {}
  -- Set PPU address to $2000.
  out[#out + 1] = 0x00
  out[#out + 1] = 0x20

  local i = 1
  while i <= N do
    local kind = choiceKind[i]
    local len = choiceLen[i] or 1

    if kind == "rle" then
      out[#out + 1] = len
      out[#out + 1] = src[i]
    else
      -- 0x81..0xFE for literal blocks (0xFF reserved for terminator).
      out[#out + 1] = 0x80 + len
      for k = 0, len - 1 do
        out[#out + 1] = src[i + k]
      end
    end

    i = i + len
  end

  out[#out + 1] = 0xFF
  return out
end

function M.decode_nametable(data, debug)
  data = data or {}

  local PAGE_BASE, PAGE_END = 0x2000, 0x23FF
  local page = {}
  for i = 0, (PAGE_END - PAGE_BASE) do page[i] = 0 end

  local i = 1
  local addr = 0

  local function write_byte(b)
    if addr >= PAGE_BASE and addr <= PAGE_END then
      page[addr - PAGE_BASE] = u8(b)
    end
    addr = wrap14(addr + 1)
  end

  while i <= #data do
    local op = data[i]
    local n1 = data[i+1] or 0
    local n2 = data[i+2] or 0

    -- Terminator: single 0xFF.
    if op == 0xFF then
      if debug then print(string.format("END @%d", i)) end
      break
    end

    if op == 0x00 then
      -- Set PPU address.
      if i + 1 > #data then break end

      -- Heuristic for 2-byte format used by this stream layout.
      local nextByte = data[i + 2]
      if n1 == 0x20 and nextByte and nextByte ~= 0x00 and nextByte ~= 0xFF then
        addr = wrap14(n1 * 256 + 0x00)
        if debug then print(string.format("SET $%04X (2-byte format at %d)", addr, i)) end
        i = i + 2
      else
        if i + 2 > #data then break end
        addr = wrap14(n1 * 256 + n2)
        if debug then print(string.format("SET $%04X (3-byte format at %d)", addr, i)) end
        i = i + 3
        -- Optional padding 00.
        if data[i] == 0x00 and is_data_opcode(data[i+1]) then
          if debug then print(string.format("SKIP padding 00 @%d", i)) end
          i = i + 1
        end
      end
    elseif op >= 0x80 then
      -- Literal block.
      local len = band127(op)
      if i + len > #data then len = math.max(0, #data - i) end
      if debug then print(string.format("LIT  x%02X @%d", len, i)) end
      for k = 1, len do write_byte(data[i + k]) end
      i = i + 1 + len
    else
      -- RLE block.
      local len, val = op, n1
      if debug then print(string.format("RLE  x%02X = %02X @%d", len, val, i)) end
      for _ = 1, len do write_byte(val) end
      i = i + 2
    end
  end

  local nt, at = {}, {}
  for k = 0, 959 do nt[#nt+1] = page[k] end
  for k = 960, 1023 do at[#at+1] = page[k] end
  return nt, at
end

-- Optional aliases used by some callers.
M.encode = M.encode_nametable
M.decode = M.decode_nametable

return M
