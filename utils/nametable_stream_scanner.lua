-- utils/nametable_stream_scanner.lua
-- On-demand nametable stream scan: candidate starts → bound terminator → trial decode.
-- Keep only streams that fully fill one PPU page (960 NT + 64 attr ⇒ uniquePageWrites == 1024).
--
-- Konami first. Zelda2 candidate rules are deferred (phase 2).
--
-- Native deferral: if Lua Scan is too slow on large ROMs, replace the walk+decode
-- loop with a sibling of libppux_sketch (e.g. ppux_nametable_scan_konami) using the
-- same FFI packaging as utils/ppux_sketch_native.lua. Ship Lua first; measure via
-- opts.onTimed / returned timingMs before adding C.
-- Practical threshold: if Scan status shows >> ~200ms on real ROMs and feels frozen
-- even with the loading pulse, implement native. Planted ~75KB Contra-offset scans
-- are currently single-digit ms in unit tests — keep this Lua until measured otherwise.

local NametableUtils = require("utils.nametable_utils")

local M = {}

--- Default max bytes from candidate start to terminator (inclusive).
M.DEFAULT_MAX_SPAN = 4096

--- Marker / ranking score: prefer complete pages with fewer overwrites and tighter size.
local function scoreHit(meta, byteLen)
  local unique = math.floor(tonumber(meta and meta.uniquePageWrites) or 0)
  local total = math.floor(tonumber(meta and meta.totalPageWrites) or 0)
  local len = math.max(1, math.floor(tonumber(byteLen) or 1))
  -- Higher is better: full unique page, no extra writes, compact stream.
  return (unique * 1000) - math.max(0, total - unique) - math.floor(len / 4)
end

local function isDataOpcode(b)
  return type(b) == "number" and b > 0 and b < 0xFF
end

--- Cheap Konami candidate: `00 20` with next byte a plausible data opcode (matches decode SET heuristic).
function M.isKonamiCandidateStart(romRaw, startAddr)
  if type(romRaw) ~= "string" then
    return false
  end
  startAddr = math.floor(tonumber(startAddr) or -1)
  if startAddr < 0 or startAddr + 2 >= #romRaw then
    return false
  end
  local b0 = string.byte(romRaw, startAddr + 1)
  local b1 = string.byte(romRaw, startAddr + 2)
  local b2 = string.byte(romRaw, startAddr + 3)
  return b0 == 0x00 and b1 == 0x20 and isDataOpcode(b2)
end

--- Walk Konami opcodes from startAddr until 0xFF or maxSpan. Returns inclusive 0-based end, or nil.
function M.boundKonamiStream(romRaw, startAddr, maxSpan)
  if type(romRaw) ~= "string" then
    return nil
  end
  startAddr = math.floor(tonumber(startAddr) or -1)
  maxSpan = math.max(1, math.floor(tonumber(maxSpan) or M.DEFAULT_MAX_SPAN))
  if startAddr < 0 or startAddr >= #romRaw then
    return nil
  end

  local len = #romRaw
  local endLimit = math.min(len, startAddr + maxSpan)
  -- 1-based index into romRaw
  local i = startAddr + 1
  local absoluteEnd = endLimit -- 0-based exclusive upper for last readable byte index+1 as 1-based

  while i <= absoluteEnd do
    local op = string.byte(romRaw, i)
    if op == nil then
      return nil
    end
    if op == 0xFF then
      return i - 1 -- 0-based inclusive end
    end

    if op == 0x00 then
      if i + 1 > absoluteEnd then
        return nil
      end
      local n1 = string.byte(romRaw, i + 1) or 0
      local nextByte = string.byte(romRaw, i + 2)
      if n1 == 0x20 and nextByte ~= nil and nextByte ~= 0x00 and nextByte ~= 0xFF then
        i = i + 2
      else
        if i + 2 > absoluteEnd then
          return nil
        end
        i = i + 3
        local pad = string.byte(romRaw, i)
        local padNext = string.byte(romRaw, i + 1)
        if pad == 0x00 and isDataOpcode(padNext) then
          i = i + 1
        end
      end
    elseif op >= 0x80 then
      local blockLen = op % 128
      i = i + 1 + blockLen
    else
      -- RLE: opcode + value
      if i + 1 > absoluteEnd then
        return nil
      end
      i = i + 2
    end
  end

  return nil
end

local function sliceBytes(romRaw, startAddr, endAddr)
  local out = {}
  for addr = startAddr, endAddr do
    out[#out + 1] = string.byte(romRaw, addr + 1) or 0
  end
  return out
end

local function tryKonamiHit(romRaw, startAddr, opts)
  local maxSpan = opts.maxSpan or M.DEFAULT_MAX_SPAN
  local endAddr = M.boundKonamiStream(romRaw, startAddr, maxSpan)
  if endAddr == nil or endAddr < startAddr then
    return nil
  end

  local data = sliceBytes(romRaw, startAddr, endAddr)
  local _, _, meta = NametableUtils.decode_compressed_nametable(data, false, "konami")
  if type(meta) ~= "table" then
    return nil
  end
  if meta.complete ~= true then
    return nil
  end
  local total = math.floor(tonumber(meta.totalPageWrites) or 0)
  if total > 1024 then
    return nil
  end

  local byteLen = endAddr - startAddr + 1
  return {
    start = startAddr,
    ["end"] = endAddr,
    score = scoreHit(meta, byteLen),
    uniquePageWrites = math.floor(tonumber(meta.uniquePageWrites) or 0),
    totalPageWrites = total,
    byteLen = byteLen,
    codec = "konami",
  }
end

--- Drop overlapping hits (prefer higher score, then longer span). Nested false
--- positives otherwise paint stacked semi fills that look like broken groups.
function M.dedupeOverlapping(hits)
  local list = {}
  for _, hit in ipairs(hits or {}) do
    local s = math.floor(tonumber(hit.start) or -1)
    local e = math.floor(tonumber(hit["end"]) or -1)
    if s >= 0 and e >= s then
      list[#list + 1] = hit
    end
  end
  table.sort(list, function(a, b)
    local sa = tonumber(a.score) or 0
    local sb = tonumber(b.score) or 0
    if sa ~= sb then
      return sa > sb
    end
    local la = (tonumber(a["end"]) or 0) - (tonumber(a.start) or 0)
    local lb = (tonumber(b["end"]) or 0) - (tonumber(b.start) or 0)
    if la ~= lb then
      return la > lb
    end
    return (tonumber(a.start) or 0) < (tonumber(b.start) or 0)
  end)

  local kept = {}
  for _, hit in ipairs(list) do
    local s = math.floor(tonumber(hit.start) or 0)
    local e = math.floor(tonumber(hit["end"]) or 0)
    local overlaps = false
    for _, other in ipairs(kept) do
      local os = math.floor(tonumber(other.start) or 0)
      local oe = math.floor(tonumber(other["end"]) or 0)
      if s <= oe and os <= e then
        overlaps = true
        break
      end
    end
    if not overlaps then
      kept[#kept + 1] = hit
    end
  end
  table.sort(kept, function(a, b)
    return (tonumber(a.start) or 0) < (tonumber(b.start) or 0)
  end)
  return kept
end

--- Scan ROM for complete nametable streams.
--- @param romRaw string ROM bytes
--- @param opts table|nil { codec="konami", maxSpan=n, onTimed=fn(ms) }
--- @return table[] hits sorted by start ascending: { start, end, score, ... }
function M.scan(romRaw, opts)
  opts = opts or {}
  local codec = tostring(opts.codec or "konami"):lower()
  local hits = {}

  if type(romRaw) ~= "string" or #romRaw < 3 then
    return hits
  end

  if codec ~= "konami" then
    -- Zelda2 (and others) deferred until Konami Scan UX proves out.
    return hits
  end

  local t0 = nil
  if opts.onTimed or opts.returnTiming then
    t0 = (love and love.timer and love.timer.getTime and love.timer.getTime())
      or (os and os.clock and os.clock())
      or nil
  end

  local maxStart = #romRaw - 3
  for startAddr = 0, maxStart do
    if M.isKonamiCandidateStart(romRaw, startAddr) then
      local hit = tryKonamiHit(romRaw, startAddr, opts)
      if hit then
        hits[#hits + 1] = hit
      end
    end
  end

  table.sort(hits, function(a, b)
    if a.start ~= b.start then
      return a.start < b.start
    end
    return (a.score or 0) > (b.score or 0)
  end)

  if opts.dedupeOverlaps ~= false then
    hits = M.dedupeOverlapping(hits)
  end

  if t0 ~= nil then
    local t1 = (love and love.timer and love.timer.getTime and love.timer.getTime())
      or (os and os.clock and os.clock())
      or t0
    local timingMs = (t1 - t0) * 1000
    if type(opts.onTimed) == "function" then
      opts.onTimed(timingMs, #hits)
    end
    if opts.returnTiming then
      return hits, timingMs
    end
  end

  return hits
end

--- Find the best scan hit containing or starting at addr (prefer exact start match).
function M.hitAt(hits, addr)
  addr = math.floor(tonumber(addr) or -1)
  if addr < 0 or type(hits) ~= "table" then
    return nil
  end
  local containing = nil
  for _, hit in ipairs(hits) do
    local s = math.floor(tonumber(hit.start) or -1)
    local e = math.floor(tonumber(hit["end"]) or -1)
    if s == addr then
      return hit
    end
    if containing == nil and addr >= s and addr <= e then
      containing = hit
    end
  end
  return containing
end

return M
