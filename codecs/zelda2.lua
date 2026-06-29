-- codecs/zelda2.lua
-- Zelda II: The Adventure of Link PPU macro stream codec.
--
-- Format documented in FiendsOfTheElements/z2disassembly (Tables_for_Game_Over_screen_text).
-- Commands: [addr_hi] [addr_lo] [ctrl] [payload...]
-- ctrl:
--   bit 7 set: vertical literal — next (ctrl & 0x3F) bytes, PPU addr += 32 each write
--   bit 6 set (bit 7 clear): horizontal repeat — repeat next byte (ctrl & 0x3F) times, PPU addr += 1
--   otherwise: horizontal literal — next (ctrl & 0x3F) bytes, PPU addr += 1 each write
-- Terminator: 0xFF
-- Optional 0x4C [ptr_hi] [ptr_lo] retargets indirect pointer (ignored for linear ROM blobs).
--
-- Before the macro stream runs, the game fills nametable 0 with tile $F4 and attributes with $00.

local DebugController = require("controllers.dev.debug_controller")

local M = {}

local TERMINATOR = 0xFF
local BANK_SWITCH = 0x4C
local PAGE_BASE = 0x2000
local NT_BYTES = 960
local ATTR_BYTES = 64
local PAGE_BYTES = NT_BYTES + ATTR_BYTES
local DEFAULT_NT_FILL = 0xF4
local DEFAULT_ATTR_FILL = 0x00

local function u8(x)
  return math.fmod(x or 0, 256)
end

local function wrap14(x)
  return math.fmod((x or 0), 16384)
end

local function flat_to_ppu(offset)
  if offset >= NT_BYTES then
    return 0x23C0 + (offset - NT_BYTES)
  end
  local row = math.floor(offset / 32)
  local col = offset % 32
  return PAGE_BASE + row * 0x20 + col
end

local function ppu_to_flat(addr)
  if addr >= 0x23C0 and addr <= 0x23FF then
    return NT_BYTES + (addr - 0x23C0)
  end
  if addr >= PAGE_BASE and addr <= 0x23BF then
    local rel = addr - PAGE_BASE
    local row = math.floor(rel / 0x20)
    local col = rel % 0x20
    if row < 30 and col < 32 then
      return row * 32 + col
    end
  end
  return nil
end

local function next_ppu_horizontal(addr)
  return wrap14(addr + 1)
end

local function next_ppu_vertical(addr)
  return wrap14(addr + 0x20)
end

local function ctrl_count(ctrl)
  return math.fmod(ctrl or 0, 64)
end

local function is_vertical_literal(ctrl)
  local c = math.fmod(ctrl or 0, 256)
  return c >= 0x80
end

local function is_horizontal_repeat(ctrl)
  local c = math.fmod(ctrl or 0, 256)
  return c >= 0x40 and c < 0x80
end

local function default_for_offset(offset)
  if offset < NT_BYTES then
    return DEFAULT_NT_FILL
  end
  return DEFAULT_ATTR_FILL
end

local function build_src(nametable, attributes)
  local src = {}
  for i = 1, NT_BYTES do
    src[#src + 1] = u8(nametable[i])
  end
  for i = 1, ATTR_BYTES do
    src[#src + 1] = u8(attributes[i] or 0)
  end
  while #src < PAGE_BYTES do
    src[#src + 1] = 0
  end
  return src
end

function M.decode_nametable(data, debug)
  data = data or {}

  local page = {}
  for i = 0, NT_BYTES - 1 do
    page[i] = DEFAULT_NT_FILL
  end
  for i = NT_BYTES, PAGE_BYTES - 1 do
    page[i] = DEFAULT_ATTR_FILL
  end
  local touched = {}
  local totalPageWrites = 0

  local function write_byte(ppu_addr, value)
    local offset = ppu_to_flat(ppu_addr)
    if offset ~= nil then
      totalPageWrites = totalPageWrites + 1
      touched[offset] = true
      page[offset] = u8(value)
    end
    if debug then
      print(string.format("WRITE $%04X (%s) = %02X", ppu_addr, tostring(offset), u8(value)))
    end
  end

  local i = 1
  while i <= #data do
    local opcode = data[i]
    if opcode == nil then
      break
    end
    if opcode == TERMINATOR then
      if debug then
        print(string.format("END @%d", i))
      end
      break
    end

    if opcode == BANK_SWITCH then
      i = i + 3
    else
      local addr_hi = opcode
      local addr_lo = data[i + 1]
      local ctrl = data[i + 2]
      if addr_lo == nil or ctrl == nil then
        break
      end

      local ppu_addr = wrap14(addr_hi * 256 + addr_lo)
      local count = ctrl_count(ctrl)
      local pos = i + 3

      if count > 0 then
        if is_vertical_literal(ctrl) then
          for _ = 1, count do
            local val = data[pos]
            if val == nil then
              count = 0
              break
            end
            write_byte(ppu_addr, val)
            ppu_addr = next_ppu_vertical(ppu_addr)
            pos = pos + 1
          end
        elseif is_horizontal_repeat(ctrl) then
          local val = data[pos]
          if val == nil then
            break
          end
          for _ = 1, count do
            write_byte(ppu_addr, val)
            ppu_addr = next_ppu_horizontal(ppu_addr)
          end
          pos = pos + 1
        else
          for _ = 1, count do
            local val = data[pos]
            if val == nil then
              count = 0
              break
            end
            write_byte(ppu_addr, val)
            ppu_addr = next_ppu_horizontal(ppu_addr)
            pos = pos + 1
          end
        end
      end

      i = pos
    end
  end

  local nt, at = {}, {}
  for k = 0, NT_BYTES - 1 do
    nt[#nt + 1] = page[k]
  end
  for k = NT_BYTES, PAGE_BYTES - 1 do
    at[#at + 1] = page[k]
  end

  local uniquePageWrites = 0
  for _ in pairs(touched) do
    uniquePageWrites = uniquePageWrites + 1
  end

  return nt, at, {
    expectedPageBytes = PAGE_BYTES,
    totalPageWrites = totalPageWrites,
    uniquePageWrites = uniquePageWrites,
    complete = (uniquePageWrites == PAGE_BYTES),
  }
end

local function append_command(out, ppu_addr, ctrl, payload)
  out[#out + 1] = math.floor(ppu_addr / 256) % 256
  out[#out + 1] = ppu_addr % 256
  out[#out + 1] = ctrl
  for j = 1, #payload do
    out[#out + 1] = u8(payload[j])
  end
end

local function max_horizontal_literal_from(src, start_offset)
  local max = math.min(63, #src - start_offset)
  local count = 1
  while count < max do
    local cur_ppu = flat_to_ppu(start_offset + count - 1)
    local next_ppu = next_ppu_horizontal(cur_ppu)
    local expected = flat_to_ppu(start_offset + count)
    if next_ppu ~= expected then
      break
    end
    count = count + 1
  end
  return count
end

local function max_vertical_literal_from(src, start_offset)
  local max = math.min(63, #src - start_offset)
  local count = 1
  while count < max do
    local cur_ppu = flat_to_ppu(start_offset + count - 1)
    local next_ppu = next_ppu_vertical(cur_ppu)
    local expected = flat_to_ppu(start_offset + count)
    if next_ppu ~= expected then
      break
    end
    count = count + 1
  end
  return count
end

local function max_horizontal_repeat_from(src, start_offset)
  local val = src[start_offset + 1]
  local count = 1
  while count < 63 do
    local next_offset = start_offset + count
    if next_offset >= #src then
      break
    end
    if src[next_offset + 1] ~= val then
      break
    end
    local cur_ppu = flat_to_ppu(start_offset + count - 1)
    if next_ppu_horizontal(cur_ppu) ~= flat_to_ppu(next_offset) then
      break
    end
    count = count + 1
  end
  return count, val
end

function M.encode_nametable(nametable, attributes)
  nametable = nametable or {}
  attributes = attributes or {}

  if #nametable ~= NT_BYTES then
    DebugController.log("error", "ZELDA2_CODEC", "nametable bytes should be %d bytes, but got %d bytes", NT_BYTES, #nametable)
  end
  if #attributes ~= ATTR_BYTES then
    DebugController.log("error", "ZELDA2_CODEC", "attr bytes should be %d bytes, but got %d bytes", ATTR_BYTES, #attributes)
  end

  local src = build_src(nametable, attributes)
  local out = {}
  local offset = 0

  while offset < #src do
    while offset < #src and src[offset + 1] == default_for_offset(offset) do
      offset = offset + 1
    end
    if offset >= #src then
      break
    end

    local repeat_count, repeat_val = max_horizontal_repeat_from(src, offset)
    if repeat_count >= 2 then
      append_command(out, flat_to_ppu(offset), 0x40 + repeat_count, { repeat_val })
      offset = offset + repeat_count
    else
      local vert_count = max_vertical_literal_from(src, offset)
      if vert_count >= 2 then
        local payload = {}
        for j = 0, vert_count - 1 do
          payload[#payload + 1] = src[offset + j + 1]
        end
        append_command(out, flat_to_ppu(offset), 0x80 + vert_count, payload)
        offset = offset + vert_count
      else
        local lit_count = max_horizontal_literal_from(src, offset)
        if lit_count < 1 then
          lit_count = 1
        end
        local payload = {}
        for j = 0, lit_count - 1 do
          payload[#payload + 1] = src[offset + j + 1]
        end
        append_command(out, flat_to_ppu(offset), lit_count, payload)
        offset = offset + lit_count
      end
    end
  end

  out[#out + 1] = TERMINATOR
  return out
end

M.encode = M.encode_nametable
M.decode = M.decode_nametable

return M
