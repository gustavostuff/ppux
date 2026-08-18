-- scanners/oam_heuristic_scanner.lua
-- One-shot OAM pair scan for Add/Edit sprite Scanned mode.
-- Two consecutive 4-byte records (Y, tile, attr, X) whose attr bytes are
-- palette-only (00/01/10/11) and that share X or Y. Consecutive 4-byte-stride
-- pairs merge into one hit so a metasprite row/column is one click target.

local M = {}

M.SPRITE_SPAN = 4
M.PAIR_SPAN = 8

local function isPaletteAttr(attr)
  return type(attr) == "number" and attr >= 0 and attr <= 3
end

local function byteAt(romRaw, addr)
  return string.byte(romRaw, addr + 1)
end

--- Palette-only attr (no flip / priority / unused bits).
function M.isPaletteAttr(attr)
  return isPaletteAttr(attr)
end

--- True when two sprites at `startAddr` (0-based) look like an OAM pair.
function M.isOamPairStart(romRaw, startAddr)
  if type(romRaw) ~= "string" then
    return false
  end
  startAddr = math.floor(tonumber(startAddr) or -1)
  if startAddr < 0 or startAddr + M.PAIR_SPAN > #romRaw then
    return false
  end
  local y1 = byteAt(romRaw, startAddr)
  local tile1 = byteAt(romRaw, startAddr + 1)
  local attr1 = byteAt(romRaw, startAddr + 2)
  local x1 = byteAt(romRaw, startAddr + 3)
  local y2 = byteAt(romRaw, startAddr + 4)
  local tile2 = byteAt(romRaw, startAddr + 5)
  local attr2 = byteAt(romRaw, startAddr + 6)
  local x2 = byteAt(romRaw, startAddr + 7)
  if not (isPaletteAttr(attr1) and isPaletteAttr(attr2)) then
    return false
  end
  -- All-zero padding is aligned and palette-legal; skip it.
  if y1 == 0 and tile1 == 0 and attr1 == 0 and x1 == 0
      and y2 == 0 and tile2 == 0 and attr2 == 0 and x2 == 0 then
    return false
  end
  if x1 ~= x2 and y1 ~= y2 then
    return false
  end
  return true, y1 == y2, x1 == x2
end

--- Chain raw pair offsets that share alignment and sit 4 bytes apart.
--- Then drop overlapping runs, preferring longer then 4-aligned.
function M.mergePairOffsets(offsets)
  local byAlign = { {}, {}, {}, {} }
  local seen = {}
  for _, off in ipairs(offsets or {}) do
    off = math.floor(tonumber(off) or -1)
    if off >= 0 and not seen[off] then
      seen[off] = true
      local align = (off % M.SPRITE_SPAN) + 1
      local list = byAlign[align]
      list[#list + 1] = off
    end
  end

  local runs = {}
  for align = 1, M.SPRITE_SPAN do
    local list = byAlign[align]
    table.sort(list)
    local i = 1
    while i <= #list do
      local startAddr = list[i]
      local last = startAddr
      i = i + 1
      while i <= #list and list[i] == last + M.SPRITE_SPAN do
        last = list[i]
        i = i + 1
      end
      runs[#runs + 1] = {
        start = startAddr,
        ["end"] = last + M.PAIR_SPAN - 1,
      }
    end
  end

  table.sort(runs, function(a, b)
    local la = (a["end"] or 0) - (a.start or 0)
    local lb = (b["end"] or 0) - (b.start or 0)
    if la ~= lb then
      return la > lb
    end
    local aa = (a.start or 0) % M.SPRITE_SPAN
    local ba = (b.start or 0) % M.SPRITE_SPAN
    if aa ~= ba then
      return aa < ba
    end
    return (a.start or 0) < (b.start or 0)
  end)

  local kept = {}
  for _, run in ipairs(runs) do
    local s = run.start
    local e = run["end"]
    local overlaps = false
    for _, other in ipairs(kept) do
      if s <= other["end"] and other.start <= e then
        overlaps = true
        break
      end
    end
    if not overlaps then
      kept[#kept + 1] = run
    end
  end
  table.sort(kept, function(a, b)
    return a.start < b.start
  end)
  return kept
end

--- 4-byte OAM starts covered by a hit (inclusive).
function M.startsForHit(hit)
  local starts = {}
  if type(hit) ~= "table" then
    return starts
  end
  local s = math.floor(tonumber(hit.start) or -1)
  local e = math.floor(tonumber(hit["end"]) or -1)
  if s < 0 or e < s then
    return starts
  end
  for addr = s, e - (M.SPRITE_SPAN - 1), M.SPRITE_SPAN do
    starts[#starts + 1] = addr
  end
  return starts
end

--- Find the hit containing or starting at addr (prefer exact start).
--- Hits are sorted and non-overlapping after merge; binary search.
function M.hitAt(hits, addr)
  addr = math.floor(tonumber(addr) or -1)
  if addr < 0 or type(hits) ~= "table" or #hits == 0 then
    return nil
  end
  local lo, hi = 1, #hits
  local cand = nil
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local hit = hits[mid]
    local s = math.floor(tonumber(hit.start) or -1)
    if s == addr then
      return hit
    elseif s < addr then
      cand = hit
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  if cand then
    local e = math.floor(tonumber(cand["end"]) or -1)
    if addr <= e then
      return cand
    end
  end
  return nil
end

--- Scan ROM for OAM pair / metasprite runs.
--- @param romRaw string
--- @param opts table|nil { returnTiming=bool, onTimed=fn, merge=bool }
--- @return table[] hits { start, end, aligned_horizontally, aligned_vertically }
function M.scan(romRaw, opts)
  opts = opts or {}
  local hits = {}
  if type(romRaw) ~= "string" or #romRaw < M.PAIR_SPAN then
    if opts.returnTiming then
      return hits, nil
    end
    return hits
  end

  local t0 = nil
  if opts.onTimed or opts.returnTiming then
    t0 = (love and love.timer and love.timer.getTime and love.timer.getTime())
      or (os and os.clock and os.clock())
      or nil
  end

  local pairMeta = {}
  local offsets = {}
  local maxStart = #romRaw - M.PAIR_SPAN
  for startAddr = 0, maxStart do
    local ok, horiz, vert = M.isOamPairStart(romRaw, startAddr)
    if ok then
      offsets[#offsets + 1] = startAddr
      pairMeta[startAddr] = {
        aligned_horizontally = horiz == true,
        aligned_vertically = vert == true,
      }
    end
  end

  if opts.merge == false then
    for _, startAddr in ipairs(offsets) do
      local meta = pairMeta[startAddr] or {}
      hits[#hits + 1] = {
        start = startAddr,
        ["end"] = startAddr + M.PAIR_SPAN - 1,
        aligned_horizontally = meta.aligned_horizontally,
        aligned_vertically = meta.aligned_vertically,
      }
    end
  else
    hits = M.mergePairOffsets(offsets)
    for _, hit in ipairs(hits) do
      local meta = pairMeta[hit.start] or {}
      hit.aligned_horizontally = meta.aligned_horizontally == true
      hit.aligned_vertically = meta.aligned_vertically == true
    end
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

return M
