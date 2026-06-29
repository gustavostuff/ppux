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

local function is_default_byte(src, offset)
  return src[offset + 1] == default_for_offset(offset)
end

local function row_remaining(offset)
  if offset < NT_BYTES then
    return 32 - (offset % 32)
  end
  return 64
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

local function copy_bytes(src)
  local out = {}
  for i = 1, #(src or {}) do
    out[i] = src[i]
  end
  return out
end

local function max_horizontal_repeat_from(src, start_offset)
  local val = src[start_offset + 1]
  if is_default_byte(src, start_offset) then
    return 1, val
  end
  local max = math.min(63, row_remaining(start_offset))
  local count = 1
  while count < max do
    local next_offset = start_offset + count
    if next_offset >= #src then
      break
    end
    if src[next_offset + 1] ~= val or is_default_byte(src, next_offset) then
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

local function max_horizontal_literal_from(src, start_offset)
  local max = math.min(63, #src - start_offset, row_remaining(start_offset))
  local count = 1
  while count < max do
    local next_offset = start_offset + count
    if is_default_byte(src, next_offset) then
      break
    end
    local cur_ppu = flat_to_ppu(start_offset + count - 1)
    local next_ppu = next_ppu_horizontal(cur_ppu)
    local expected = flat_to_ppu(next_offset)
    if next_ppu ~= expected then
      break
    end
    local ahead_count = max_horizontal_repeat_from(src, next_offset)
    if ahead_count >= 2 then
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
    local next_offset = start_offset + count
    if is_default_byte(src, next_offset) then
      break
    end
    local cur_ppu = flat_to_ppu(start_offset + count - 1)
    local next_ppu = next_ppu_vertical(cur_ppu)
    local expected = flat_to_ppu(next_offset)
    if next_ppu ~= expected then
      break
    end
    count = count + 1
  end
  return count
end

local function parse_commands(data)
  data = data or {}
  local commands = {}
  local i = 1

  while i <= #data do
    local opcode = data[i]
    if opcode == nil or opcode == TERMINATOR then
      break
    end

    if opcode == BANK_SWITCH then
      commands[#commands + 1] = {
        kind = "bank",
        bytes = { data[i], data[i + 1], data[i + 2] },
        written = {},
      }
      i = i + 3
    else
      local start_i = i
      local addr_hi = opcode
      local addr_lo = data[i + 1]
      local ctrl = data[i + 2]
      if addr_lo == nil or ctrl == nil then
        break
      end

      local ppu_addr = wrap14(addr_hi * 256 + addr_lo)
      local count = ctrl_count(ctrl)
      local pos = i + 3
      local written = {}

      if count > 0 then
        if is_vertical_literal(ctrl) then
          for _ = 1, count do
            local flat = ppu_to_flat(ppu_addr)
            if flat ~= nil then
              written[#written + 1] = flat
            end
            ppu_addr = next_ppu_vertical(ppu_addr)
            pos = pos + 1
          end
        elseif is_horizontal_repeat(ctrl) then
          for _ = 1, count do
            local flat = ppu_to_flat(ppu_addr)
            if flat ~= nil then
              written[#written + 1] = flat
            end
            ppu_addr = next_ppu_horizontal(ppu_addr)
          end
          pos = pos + 1
        else
          for _ = 1, count do
            local flat = ppu_to_flat(ppu_addr)
            if flat ~= nil then
              written[#written + 1] = flat
            end
            ppu_addr = next_ppu_horizontal(ppu_addr)
            pos = pos + 1
          end
        end
      end

      local cmd_bytes = {}
      for j = start_i, pos - 1 do
        cmd_bytes[#cmd_bytes + 1] = data[j]
      end

      commands[#commands + 1] = {
        kind = "write",
        bytes = cmd_bytes,
        written = written,
        ctrl = ctrl,
        ppu_addr = wrap14(addr_hi * 256 + addr_lo),
      }
      i = pos
    end
  end

  return commands
end

local function expand_horizontal_forward(src, min_off, max_off)
  if min_off >= NT_BYTES then
    return min_off, max_off
  end

  local row = math.floor(min_off / 32)
  local row_end = row * 32 + 31

  while max_off < row_end and not is_default_byte(src, max_off + 1) do
    max_off = max_off + 1
  end

  return min_off, max_off
end

local function expand_horizontal_edges(src, min_off, max_off)
  if min_off >= NT_BYTES then
    return min_off, max_off
  end

  local row = math.floor(min_off / 32)
  local row_start = row * 32

  while min_off > row_start and not is_default_byte(src, min_off - 1) do
    min_off = min_off - 1
  end

  return expand_horizontal_forward(src, min_off, max_off)
end

local function reencode_command_from_src(cmd, src)
  if cmd.kind == "bank" then
    return copy_bytes(cmd.bytes)
  end

  local ctrl = cmd.ctrl
  local ppu_addr = cmd.ppu_addr
  local offsets = cmd.written or {}

  if is_vertical_literal(ctrl) then
    local payload = {}
    for j = 1, #offsets do
      payload[#payload + 1] = src[offsets[j] + 1]
    end
    local out = {}
    append_command(out, ppu_addr, 0x80 + #payload, payload)
    return out
  end

  local written = cmd.written or {}
  if #written == 0 then
    return copy_bytes(cmd.bytes)
  end

  local min_off, max_off = written[1], written[#written]
  min_off, max_off = expand_horizontal_forward(src, min_off, max_off)
  local span_len = max_off - min_off + 1
  local start_ppu = cmd.ppu_addr

  local repeat_val = src[min_off + 1]
  local all_repeat = span_len >= 2
  if all_repeat then
    for off = min_off + 1, max_off do
      if src[off + 1] ~= repeat_val then
        all_repeat = false
        break
      end
    end
  end

  local out = {}
  if all_repeat and not is_default_byte(src, min_off) then
    append_command(out, start_ppu, 0x40 + span_len, { repeat_val })
    return out
  end

  local payload = {}
  for off = min_off, max_off do
    payload[#payload + 1] = src[off + 1]
  end
  append_command(out, start_ppu, #payload, payload)
  return out
end

local function encode_span(src, start_offset, end_offset)
  local out = {}
  local offset = start_offset
  while offset <= end_offset do
    while offset <= end_offset and is_default_byte(src, offset) do
      offset = offset + 1
    end
    if offset > end_offset then
      break
    end

    local repeat_count, repeat_val = max_horizontal_repeat_from(src, offset)
    if repeat_count >= 2 then
      append_command(out, flat_to_ppu(offset), 0x40 + repeat_count, { repeat_val })
      offset = offset + repeat_count
    else
      local vert_count = max_vertical_literal_from(src, offset)
      if vert_count >= 2 and offset + vert_count - 1 <= end_offset then
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
        if offset + lit_count - 1 > end_offset then
          lit_count = end_offset - offset + 1
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
  return out
end

local function find_dirty_offsets(baseline_src, src)
  local dirty = {}
  for offset = 0, #src - 1 do
    if baseline_src[offset + 1] ~= src[offset + 1] then
      dirty[offset] = true
    end
  end
  return dirty
end

local function command_is_dirty(cmd, dirty, baseline_src, src)
  for j = 1, #(cmd.written or {}) do
    if dirty[cmd.written[j]] then
      return true
    end
  end

  if cmd.kind ~= "write" or is_vertical_literal(cmd.ctrl) then
    return false
  end

  local written = cmd.written or {}
  if #written == 0 then
    return false
  end

  local min_off, max_off = expand_horizontal_edges(src, written[1], written[#written])
  for off = min_off, max_off do
    if dirty[off] then
      return true
    end
    if baseline_src[off + 1] == default_for_offset(off) and not is_default_byte(src, off) then
      return true
    end
  end
  return false
end

local function append_orphan_spans(out, src, dirty, covered)
  local orphan_start = nil
  for offset = 0, #src - 1 do
    local needs_write = dirty[offset] and not covered[offset]
    if needs_write and orphan_start == nil then
      orphan_start = offset
    elseif not needs_write and orphan_start ~= nil then
      local span = encode_span(src, orphan_start, offset - 1)
      for j = 1, #span do
        out[#out + 1] = span[j]
      end
      orphan_start = nil
    end
  end
  if orphan_start ~= nil then
    local span = encode_span(src, orphan_start, #src - 1)
    for j = 1, #span do
      out[#out + 1] = span[j]
    end
  end
end

local function encode_nametable_full(src)
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

local function encode_nametable_patched(src, original_compressed)
  if #original_compressed == 0 then
    return encode_nametable_full(src)
  end

  local baseline_nt, baseline_at = M.decode_nametable(original_compressed)
  local baseline_src = build_src(baseline_nt, baseline_at)
  local dirty = find_dirty_offsets(baseline_src, src)

  if not next(dirty) then
    return copy_bytes(original_compressed)
  end

  local commands = parse_commands(original_compressed)
  local dirty_indices = {}
  for idx = 1, #commands do
    if command_is_dirty(commands[idx], dirty, baseline_src, src) then
      dirty_indices[idx] = true
    end
  end

  local out = {}
  for idx = 1, #commands do
    local cmd = commands[idx]
    if dirty_indices[idx] then
      local encoded = reencode_command_from_src(cmd, src)
      for j = 1, #encoded do
        out[#out + 1] = encoded[j]
      end
    else
      for j = 1, #(cmd.bytes or {}) do
        out[#out + 1] = cmd.bytes[j]
      end
    end
  end

  local covered = {}
  for idx = 1, #commands do
    local cmd = commands[idx]
    if dirty_indices[idx] then
      local written = cmd.written or {}
      if #written > 0 and cmd.kind == "write" and not is_vertical_literal(cmd.ctrl) then
        local min_off, max_off = expand_horizontal_forward(src, written[1], written[#written])
        for off = min_off, max_off do
          covered[off] = true
        end
      else
        for j = 1, #written do
          covered[written[j]] = true
        end
      end
    else
      for j = 1, #(cmd.written or {}) do
        covered[cmd.written[j]] = true
      end
    end
  end

  append_orphan_spans(out, src, dirty, covered)
  out[#out + 1] = TERMINATOR
  return out
end

function M.encode_nametable(nametable, attributes, original_compressed)
  nametable = nametable or {}
  attributes = attributes or {}

  if #nametable ~= NT_BYTES then
    DebugController.log("error", "ZELDA2_CODEC", "nametable bytes should be %d bytes, but got %d bytes", NT_BYTES, #nametable)
  end
  if #attributes ~= ATTR_BYTES then
    DebugController.log("error", "ZELDA2_CODEC", "attr bytes should be %d bytes, but got %d bytes", ATTR_BYTES, #attributes)
  end

  local src = build_src(nametable, attributes)
  if type(original_compressed) == "table" and #original_compressed > 0 then
    return encode_nametable_patched(src, original_compressed)
  end
  return encode_nametable_full(src)
end

M.encode = M.encode_nametable
M.decode = M.decode_nametable

return M
