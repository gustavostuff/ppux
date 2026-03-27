#!/usr/bin/env lua

-- Analyze Konami nametable codec streams.
-- Usage:
--   lua scripts/analyze_konami_codec.lua [--codec konami] [--simulate-edits N] [--seed N] <hex_file_or_- >...
-- Notes:
--   * Each input is parsed as hex bytes (spaces/newlines allowed).
--   * "-" means read one stream from stdin.

package.path = "./?.lua;./?/init.lua;" .. package.path

local NametableUtils = require("utils.nametable_utils")

local function read_all(path)
  if path == "-" then
    return io.read("*a")
  end
  local f, err = io.open(path, "r")
  if not f then
    error(string.format("failed to open '%s': %s", tostring(path), tostring(err)))
  end
  local content = f:read("*a")
  f:close()
  return content
end

local function basename(path)
  return tostring(path):gsub("\\", "/"):match("([^/]+)$") or tostring(path)
end

local function u8(x)
  return math.floor(tonumber(x) or 0) % 256
end

local function copy_table(src)
  local out = {}
  for i = 1, #src do
    out[i] = src[i]
  end
  return out
end

local function parse_stream_ops(data)
  local i = 1
  local addr = 0
  local term_at = nil
  local out_of_bounds_writes = 0
  local page_writes = 0
  local written = {}

  local counts = {
    set2 = 0,
    set3 = 0,
    set_padding = 0,
    rle = 0,
    lit = 0,
    lit_zero = 0,
    term = 0,
    invalid = 0,
  }

  local function write_byte(v)
    if addr >= 0x2000 and addr <= 0x23FF then
      local idx = (addr - 0x2000) + 1
      written[idx] = true
      page_writes = page_writes + 1
    else
      out_of_bounds_writes = out_of_bounds_writes + 1
    end
    addr = (addr + 1) % 0x4000
  end

  while i <= #data do
    local op = data[i]
    local n1 = data[i + 1]
    local n2 = data[i + 2]

    if op == 0xFF then
      counts.term = counts.term + 1
      term_at = i
      break
    elseif op == 0x00 then
      if not n1 then
        counts.invalid = counts.invalid + 1
        break
      end
      -- Same heuristic as codecs/konami.lua.
      if n1 == 0x20 and n2 and n2 ~= 0x00 and n2 ~= 0xFF then
        addr = (n1 * 256) % 0x4000
        counts.set2 = counts.set2 + 1
        i = i + 2
      else
        if not n2 then
          counts.invalid = counts.invalid + 1
          break
        end
        addr = ((n1 * 256) + n2) % 0x4000
        counts.set3 = counts.set3 + 1
        i = i + 3
        if data[i] == 0x00 and data[i + 1] and data[i + 1] > 0x00 and data[i + 1] < 0xFF then
          counts.set_padding = counts.set_padding + 1
          i = i + 1
        end
      end
    elseif op >= 0x80 then
      local len = op % 0x80
      if len == 0 then
        counts.lit_zero = counts.lit_zero + 1
      else
        counts.lit = counts.lit + 1
      end
      for k = 1, len do
        local b = data[i + k]
        if not b then
          counts.invalid = counts.invalid + 1
          return {
            counts = counts,
            term_at = term_at,
            final_i = i,
            final_addr = addr,
            page_writes = page_writes,
            unique_written = 0,
            out_of_bounds_writes = out_of_bounds_writes,
            truncated = true,
          }
        end
        write_byte(b)
      end
      i = i + 1 + len
    else
      local len = op
      local val = n1
      if not val then
        counts.invalid = counts.invalid + 1
        break
      end
      counts.rle = counts.rle + 1
      for _ = 1, len do
        write_byte(val)
      end
      i = i + 2
    end
  end

  local unique_written = 0
  for _, on in pairs(written) do
    if on then
      unique_written = unique_written + 1
    end
  end

  return {
    counts = counts,
    term_at = term_at,
    final_i = i,
    final_addr = addr,
    page_writes = page_writes,
    unique_written = unique_written,
    out_of_bounds_writes = out_of_bounds_writes,
    truncated = false,
  }
end

local function arrays_equal(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

local function simulate_edit_sizes(nt, at, codec, n)
  if not n or n <= 0 then
    return nil
  end

  local min_size, max_size, sum = nil, nil, 0
  for _ = 1, n do
    local nt2 = copy_table(nt)
    local at2 = copy_table(at)
    local pick = math.random(1, 960 + 64)
    if pick <= 960 then
      local idx = pick
      local prev = nt2[idx] or 0
      local nextv = (prev + math.random(1, 255)) % 256
      nt2[idx] = nextv
    else
      local idx = pick - 960
      local prev = at2[idx] or 0
      local nextv = (prev + math.random(1, 255)) % 256
      at2[idx] = nextv
    end
    local encoded = NametableUtils.encode_decompressed_nametable(nt2, at2, codec)
    local sz = #encoded
    if not min_size or sz < min_size then min_size = sz end
    if not max_size or sz > max_size then max_size = sz end
    sum = sum + sz
  end

  return {
    min = min_size or 0,
    max = max_size or 0,
    avg = (n > 0) and (sum / n) or 0,
    runs = n,
  }
end

local function analyze_stream(label, raw_hex, codec, simulate_edits)
  local bytes = NametableUtils.hex_to_bytes(raw_hex or "")
  if #bytes == 0 then
    return {
      label = label,
      error = "no_bytes",
    }
  end

  local ops = parse_stream_ops(bytes)
  local nt, at = NametableUtils.decode_compressed_nametable(bytes, false, codec)
  local reencoded = NametableUtils.encode_decompressed_nametable(nt, at, codec)
  local nt2, at2 = NametableUtils.decode_compressed_nametable(reencoded, false, codec)
  local roundtrip_ok = arrays_equal(nt, nt2) and arrays_equal(at, at2)
  local term_at = ops.term_at or (#bytes + 1)
  local original_effective_size = term_at
  local trailing_count = math.max(0, #bytes - term_at)
  local simulate = simulate_edit_sizes(nt, at, codec, simulate_edits)

  return {
    label = label,
    bytes_len = #bytes,
    original_effective_size = original_effective_size,
    trailing_count = trailing_count,
    ops = ops,
    nt_len = #nt,
    at_len = #at,
    reencoded_len = #reencoded,
    size_delta_vs_original = #reencoded - original_effective_size,
    roundtrip_ok = roundtrip_ok,
    simulate = simulate,
  }
end

local function print_result(r)
  print(string.rep("=", 72))
  print(string.format("%s", r.label))
  if r.error then
    print(string.format("error: %s", tostring(r.error)))
    return
  end

  print(string.format("input bytes: %d", r.bytes_len))
  print(string.format("effective bytes (through first terminator): %d", r.original_effective_size))
  print(string.format("trailing bytes after first terminator: %d", r.trailing_count))
  print(string.format("decoded sizes: nametable=%d attr=%d", r.nt_len, r.at_len))
  print(string.format("re-encoded bytes: %d", r.reencoded_len))
  print(string.format("size delta vs original effective stream: %+d", r.size_delta_vs_original))
  print(string.format("decode(reencode(decode(x))) stable: %s", r.roundtrip_ok and "yes" or "no"))

  local c = r.ops.counts
  print(string.format(
    "ops: set2=%d set3=%d pad=%d rle=%d lit=%d lit0=%d term=%d invalid=%d",
    c.set2, c.set3, c.set_padding, c.rle, c.lit, c.lit_zero, c.term, c.invalid
  ))
  print(string.format(
    "writes: page_total=%d page_unique=%d out_of_bounds=%d final_addr=$%04X",
    r.ops.page_writes, r.ops.unique_written, r.ops.out_of_bounds_writes, r.ops.final_addr or 0
  ))
  if r.ops.truncated then
    print("warning: stream parsing ended due to truncated opcode payload")
  end

  if r.simulate then
    print(string.format(
      "simulated %d single-byte edits -> encoded size min=%d avg=%.2f max=%d",
      r.simulate.runs, r.simulate.min, r.simulate.avg, r.simulate.max
    ))
  end
end

local codec = "konami"
local simulate_edits = 0
local seed = 1337
local inputs = {}

do
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == "--codec" then
      i = i + 1
      codec = arg[i] or codec
    elseif a == "--simulate-edits" then
      i = i + 1
      simulate_edits = tonumber(arg[i]) or 0
    elseif a == "--seed" then
      i = i + 1
      seed = tonumber(arg[i]) or seed
    else
      inputs[#inputs + 1] = a
    end
    i = i + 1
  end
end

if #inputs == 0 then
  inputs[1] = "-"
end

math.randomseed(seed)

local results = {}
for _, path in ipairs(inputs) do
  local raw = read_all(path)
  local label = (path == "-") and "stdin" or basename(path)
  results[#results + 1] = analyze_stream(label, raw, codec, simulate_edits)
end

for _, r in ipairs(results) do
  print_result(r)
end

if #results >= 2 then
  print(string.rep("=", 72))
  print("cross-stream size comparison (re-encoded):")
  for i = 1, #results do
    local ri = results[i]
    if not ri.error then
      for j = i + 1, #results do
        local rj = results[j]
        if not rj.error then
          local delta = ri.reencoded_len - rj.reencoded_len
          print(string.format("  %s - %s = %+d bytes", ri.label, rj.label, delta))
        end
      end
    end
  end
end
