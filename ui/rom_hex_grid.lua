-- FCEUX-style read-only ROM hex grid: 16 columns x 8 rows, absolute offset gutter,
-- 00-0F column headers. Wheel scrolls 8 rows (Shift+wheel: 64 rows / 1KB).
-- Selection is groups of `groupSize` bytes from each selected start address.
-- Click toggles a group Selected; click again restores Semi-selected or Normal.
-- Disabled groups are non-interactive. Optional scrollbar minimap markers
-- ({ offset, color, groupCount=N, groupSize=M }; span = N×M bytes, overlaps OK).

local colors = require("app_colors")
local Text = require("utils.text_utils")
local LoveCompat = require("utils.love_compat")

local M = {}
M.__index = M

M.COLS = 16
M.ROWS = 8
M.BYTES_PER_PAGE = M.COLS * M.ROWS
M.WHEEL_ROWS = 8
M.WHEEL_ROWS_SHIFT = 64
--- Historical OAM record size; Add-sprite passes groupSize = 4.
M.OAM_SPAN = 4
--- Convenience cap for Add-sprite; grid only enforces when maxSelectedStarts is set.
M.MAX_SELECTED_STARTS = 8

-- Fixed-pitch gutter: 6 hex digits × OFFSET_DIGIT_W (Aseprite is not fully mono).
local OFFSET_DIGITS = 6
local OFFSET_DIGIT_W = 6
local GUTTER_W = OFFSET_DIGITS * OFFSET_DIGIT_W + 2
local HEADER_H = 12
local CELL_W = 15
local CELL_H = 10
local PAD = 2
local HIGHLIGHT_RADIUS = 2
-- Non-interactive position indicator (right of the byte grid).
local SCROLLBAR_W = 3
local SCROLLBAR_GAP = 2
-- Optical nudge: Text.print baseline sits a bit low in these short cells.
local TEXT_NUDGE_Y = -2

local HIGHLIGHT_KEYS = { "red", "green", "blue", "yellow", "brown" }
local HIGHLIGHT_KEY_SET = {}
for _, key in ipairs(HIGHLIGHT_KEYS) do
  HIGHLIGHT_KEY_SET[key] = true
end
-- Minimap also accepts gray (occupied / disabled regions).
local MINIMAP_COLOR_SET = {}
for key in pairs(HIGHLIGHT_KEY_SET) do
  MINIMAP_COLOR_SET[key] = true
end
MINIMAP_COLOR_SET.gray = true

local function disabledHighlightColor()
  local g = colors.gray50
  if type(g) == "table" and type(g[1]) == "number" then
    return { g[1], g[2] or 0, g[3] or 0, 0.9 }
  end
  return { 0.5, 0.5, 0.5, 0.9 }
end

local function disabledTextColor()
  local g = colors.gray75
  if type(g) == "table" and type(g[1]) == "number" then
    return { g[1], g[2] or 0, g[3] or 0, 1 }
  end
  return { 0.75, 0.75, 0.75, 1 }
end

local function buildHighlightColors()
  local out = {}
  for i, key in ipairs(HIGHLIGHT_KEYS) do
    local rgb = colors[key]
    if type(rgb) == "table" and type(rgb[1]) == "number" then
      out[i] = { rgb[1], rgb[2] or 0, rgb[3] or 0, 0.9 }
    else
      out[i] = { 0.2, 0.35, 0.85, 0.9 }
    end
  end
  return out
end

function M.getHighlightColors()
  if not M.HIGHLIGHT_COLORS then
    M.HIGHLIGHT_COLORS = buildHighlightColors()
  end
  return M.HIGHLIGHT_COLORS
end

M.HIGHLIGHT_COLORS = buildHighlightColors()

function M.contentWidth()
  return GUTTER_W + M.COLS * CELL_W + SCROLLBAR_GAP + SCROLLBAR_W + PAD * 2
end

function M.contentHeight()
  return HEADER_H + M.ROWS * CELL_H + PAD * 2
end

local function romLen(romRaw)
  if type(romRaw) ~= "string" then
    return 0
  end
  return #romRaw
end

function M.alignRow(addr)
  addr = math.floor(tonumber(addr) or 0)
  if addr < 0 then addr = 0 end
  return addr - (addr % M.COLS)
end

local function copyStarts(starts)
  local out = {}
  for i = 1, #(starts or {}) do
    out[i] = starts[i]
  end
  return out
end

local function normalizeStartList(starts)
  local list = {}
  local set = {}
  for _, addr in ipairs(starts or {}) do
    addr = math.floor(tonumber(addr) or -1)
    if addr >= 0 and not set[addr] then
      set[addr] = true
      list[#list + 1] = addr
    end
  end
  table.sort(list)
  return list, set
end

function M.new(opts)
  opts = opts or {}
  local groupSize = math.floor(tonumber(opts.groupSize) or 1)
  if groupSize < 1 then groupSize = 1 end
  local maxSelected = opts.maxSelectedStarts
  if maxSelected ~= nil then
    maxSelected = math.max(1, math.floor(tonumber(maxSelected) or 1))
  end
  local self = setmetatable({
    x = 0,
    y = 0,
    w = M.contentWidth(),
    h = M.contentHeight(),
    romRaw = "",
    scrollOffset = 0,
    groupSize = groupSize,
    maxSelectedStarts = maxSelected,
    selectedAddr = 0,
    selectedStarts = {},
    -- Color index (into HIGHLIGHT_KEYS) assigned when each start was first selected.
    _startColorIndex = {},
    _nextColorSeq = 1,
    -- Disabled groups (formerly occupied OAM starts).
    disabledStarts = {},
    _disabledSet = {},
    -- Alias kept for callers still using occupied naming.
    occupiedStarts = {},
    _occupiedSet = {},
    semiSelectedStarts = {},
    _semiSet = {},
    minimapMarkers = {},
    onSelect = opts.onSelect,
    _hoverX = nil,
    _hoverY = nil,
    _selectionCapHit = false,
  }, M)
  return self
end

function M:getGroupSize()
  return math.max(1, math.floor(tonumber(self.groupSize) or 1))
end

--- Disabled (non-interactive) group starts.
function M:setDisabledStarts(starts)
  local list, set = normalizeStartList(starts)
  self.disabledStarts = list
  self._disabledSet = set
  self.occupiedStarts = list
  self._occupiedSet = set
end

--- Alias for setDisabledStarts (Add-sprite / in-layer OAM starts).
function M:setOccupiedStarts(starts)
  self:setDisabledStarts(starts)
end

function M:getDisabledStarts()
  return copyStarts(self.disabledStarts)
end

function M:getOccupiedStarts()
  return self:getDisabledStarts()
end

function M:isDisabledStart(addr)
  addr = math.floor(tonumber(addr) or -1)
  return self._disabledSet and self._disabledSet[addr] == true
end

function M:isOccupiedStart(addr)
  return self:isDisabledStart(addr)
end

function M:setSemiSelectedStarts(starts)
  local list, set = normalizeStartList(starts)
  self.semiSelectedStarts = list
  self._semiSet = set
  self:_syncStartColors(list, { resetColors = false })
end

function M:getSemiSelectedStarts()
  return copyStarts(self.semiSelectedStarts)
end

local MINIMAP_COLORS = MINIMAP_COLOR_SET

local function normalizeMinimapMarker(m)
  if type(m) ~= "table" then
    return nil
  end
  local offset = math.floor(tonumber(m.offset) or -1)
  local color = m.color
  if offset < 0 or type(color) ~= "string" or not MINIMAP_COLORS[color] then
    return nil
  end
  -- Contiguous range: N groups × M bytes each (defaults = single byte).
  local groupCount = math.max(1, math.floor(tonumber(m.groupCount) or 1))
  local groupSize = math.max(1, math.floor(tonumber(m.groupSize) or 1))
  return {
    offset = offset,
    color = color,
    groupCount = groupCount,
    groupSize = groupSize,
  }
end

function M:setMinimapMarkers(markers)
  local out = {}
  for _, m in ipairs(markers or {}) do
    local normalized = normalizeMinimapMarker(m)
    if normalized then
      out[#out + 1] = normalized
    end
  end
  self.minimapMarkers = out
end

function M:getMinimapMarkers()
  local out = {}
  for i, m in ipairs(self.minimapMarkers or {}) do
    out[i] = {
      offset = m.offset,
      color = m.color,
      groupCount = m.groupCount,
      groupSize = m.groupSize,
    }
  end
  return out
end

--- Byte length covered by a minimap marker (groupCount × groupSize).
function M.minimapMarkerByteLength(marker)
  if type(marker) ~= "table" then
    return 1
  end
  local n = math.max(1, math.floor(tonumber(marker.groupCount) or 1))
  local size = math.max(1, math.floor(tonumber(marker.groupSize) or 1))
  return n * size
end

--- True when two group starts' spans overlap for this grid's groupSize.
function M.spansOverlap(a, b, span)
  a = math.floor(tonumber(a) or 0)
  b = math.floor(tonumber(b) or 0)
  span = math.max(1, math.floor(tonumber(span) or 1))
  return a < b + span and b < a + span
end

--- Backward-compatible name (assumes OAM 4-byte span).
function M.oamSpansOverlap(a, b)
  return M.spansOverlap(a, b, M.OAM_SPAN)
end

function M:startOverlapsDisabled(startAddr)
  startAddr = math.floor(tonumber(startAddr) or -1)
  if startAddr < 0 then
    return false
  end
  local span = self:getGroupSize()
  for _, occ in ipairs(self.disabledStarts or {}) do
    if M.spansOverlap(startAddr, occ, span) then
      return true
    end
  end
  return false
end

function M:startOverlapsOccupied(startAddr)
  return self:startOverlapsDisabled(startAddr)
end

--- True when `addr` lies inside any disabled group's span.
function M:addrInDisabledSpan(addr)
  addr = math.floor(tonumber(addr) or -1)
  if addr < 0 then
    return false
  end
  local span = self:getGroupSize()
  for _, occ in ipairs(self.disabledStarts or {}) do
    if addr >= occ and addr < occ + span then
      return true
    end
  end
  return false
end

function M:addrInOccupiedSpan(addr)
  return self:addrInDisabledSpan(addr)
end

--- Map a click/typed address to a selectable start that does not overlap disabled
--- groups. Clicks in the groupSize bytes immediately before/after a disabled
--- group snap to that neighboring full group. Clicks on disabled itself return nil.
function M:resolveSelectableStart(addr)
  addr = self:_clampAddr(addr)
  if self:addrInDisabledSpan(addr) then
    return nil
  end
  if not self:startOverlapsDisabled(addr) then
    return addr
  end

  local span = self:getGroupSize()
  local best, bestDist = nil, nil
  for _, occ in ipairs(self.disabledStarts or {}) do
    for _, cand in ipairs({ occ - span, occ + span }) do
      if cand >= 0 and not self:startOverlapsDisabled(cand) then
        if addr >= cand and addr < cand + span then
          local dist = math.abs(addr - cand)
          if best == nil or dist < bestDist then
            best, bestDist = cand, dist
          end
        end
      end
    end
  end
  return best
end

local function selectionStartAllowed(self, addr, opts)
  opts = opts or {}
  if opts.allowOccupied == true or opts.allowDisabled == true then
    return true
  end
  return not self:startOverlapsDisabled(addr)
end

function M:setPosition(x, y)
  self.x = math.floor(tonumber(x) or 0)
  self.y = math.floor(tonumber(y) or 0)
end

function M:setSize(w, h)
  if type(w) == "number" then
    self.w = math.floor(w)
  end
  if type(h) == "number" then
    self.h = math.floor(h)
  end
end

function M:getWidth()
  return self.w
end

function M:getHeight()
  return self.h
end

function M:contains(px, py)
  return px >= self.x and px < self.x + self.w
    and py >= self.y and py < self.y + self.h
end

function M:setRomRaw(romRaw)
  self.romRaw = type(romRaw) == "string" and romRaw or ""
  self:clampScroll()
end

function M:maxScroll()
  local len = romLen(self.romRaw)
  if len <= M.BYTES_PER_PAGE then
    return 0
  end
  return M.alignRow(len - M.BYTES_PER_PAGE)
end

function M:clampScroll()
  local maxS = self:maxScroll()
  local s = M.alignRow(self.scrollOffset)
  if s < 0 then s = 0 end
  if s > maxS then s = maxS end
  self.scrollOffset = s
end

function M:getSelectedAddr()
  return self.selectedAddr
end

function M:getSelectedStarts()
  return copyStarts(self.selectedStarts)
end

function M:_clampAddr(addr)
  addr = math.floor(tonumber(addr) or 0)
  if addr < 0 then addr = 0 end
  local len = romLen(self.romRaw)
  if len > 0 and addr >= len then
    addr = len - 1
  elseif len == 0 then
    addr = 0
  end
  return addr
end

function M:_emitSelect(opts)
  opts = opts or {}
  if self.onSelect then
    self.onSelect(self.selectedAddr, {
      starts = self:getSelectedStarts(),
      selectionCapHit = opts.selectionCapHit == true,
    })
  end
end

--- Prefer keeping already-selected starts, then append new ones (cleaned order).
local function clampStartsToMax(cleaned, previousStarts, maxN)
  if #cleaned <= maxN then
    return cleaned, false
  end
  local inCleaned = {}
  for _, addr in ipairs(cleaned) do
    inCleaned[addr] = true
  end
  local kept = {}
  local keptSet = {}
  for _, addr in ipairs(previousStarts or {}) do
    if inCleaned[addr] and not keptSet[addr] and #kept < maxN then
      kept[#kept + 1] = addr
      keptSet[addr] = true
    end
  end
  for _, addr in ipairs(cleaned) do
    if not keptSet[addr] and #kept < maxN then
      kept[#kept + 1] = addr
      keptSet[addr] = true
    end
  end
  return kept, true
end

--- Bind highlight colors by selection order (not list index).
function M:_syncStartColors(cleaned, opts)
  opts = opts or {}
  if opts.resetColors then
    self._startColorIndex = {}
    self._nextColorSeq = 1
  end
  local map = self._startColorIndex or {}
  for _, addr in ipairs(cleaned) do
    if map[addr] == nil then
      map[addr] = self._nextColorSeq
      self._nextColorSeq = self._nextColorSeq + 1
    end
  end
  self._startColorIndex = map
end

function M:_resolvedMaxSelected(opts)
  opts = opts or {}
  if opts.maxSelectedStarts ~= nil then
    return math.max(1, math.floor(tonumber(opts.maxSelectedStarts) or 1))
  end
  if self.maxSelectedStarts ~= nil then
    return math.max(1, math.floor(tonumber(self.maxSelectedStarts) or 1))
  end
  return nil
end

function M:_setStarts(starts, primary, opts)
  opts = opts or {}
  local cleaned = {}
  local seen = {}
  for _, addr in ipairs(starts or {}) do
    addr = self:_clampAddr(addr)
    if not seen[addr] and selectionStartAllowed(self, addr, opts) then
      seen[addr] = true
      cleaned[#cleaned + 1] = addr
    end
  end
  local previousStarts = self.selectedStarts
  local allowEmpty = opts.allowEmpty == true
  if #cleaned == 0 and not allowEmpty then
    -- Keep a prior free selection rather than forcing an overlapping start.
    for _, addr in ipairs(previousStarts or {}) do
      addr = self:_clampAddr(addr)
      if not seen[addr] and selectionStartAllowed(self, addr, opts) then
        seen[addr] = true
        cleaned[#cleaned + 1] = addr
      end
    end
  end
  if #cleaned == 0 and (opts.allowOccupied == true or opts.allowDisabled == true) and not allowEmpty then
    cleaned[1] = self:_clampAddr(primary or 0)
    seen[cleaned[1]] = true
  end
  local capHit = false
  local maxN = self:_resolvedMaxSelected(opts)
  if opts.enforceMax ~= false and maxN ~= nil and #cleaned > 0 then
    cleaned, capHit = clampStartsToMax(cleaned, previousStarts, maxN)
    seen = {}
    for _, addr in ipairs(cleaned) do
      seen[addr] = true
    end
  end
  self:_syncStartColors(cleaned, opts)
  self.selectedStarts = cleaned
  primary = self:_clampAddr(primary or (cleaned[#cleaned] or 0))
  if #cleaned > 0 and not seen[primary] then
    primary = cleaned[#cleaned]
  elseif #cleaned == 0 then
    primary = self:_clampAddr(primary)
  end
  self.selectedAddr = primary
  if opts.scrollToReveal ~= false and #cleaned > 0 then
    self:scrollToReveal(primary)
  end
  self._selectionCapHit = capHit
  if opts.emit ~= false then
    self:_emitSelect({
      selectionCapHit = capHit,
    })
  end
end

--- Replace selection with a single start (text field / programmatic).
function M:setSelectedAddr(addr, opts)
  opts = opts or {}
  addr = self:_clampAddr(addr)
  if opts.resetColors == nil then
    opts.resetColors = true
  end
  if opts.allowOccupied ~= true and opts.allowDisabled ~= true then
    local resolved = self:resolveSelectableStart(addr)
    if resolved == nil then
      if opts.emit then
        self:_emitSelect({
          selectionCapHit = self._selectionCapHit == true,
        })
      end
      return
    end
    addr = resolved
  end
  self:_setStarts({ addr }, addr, opts)
end

function M:scrollToReveal(addr)
  addr = math.floor(tonumber(addr) or 0)
  local pageStart = self.scrollOffset
  local pageEnd = pageStart + M.BYTES_PER_PAGE - 1
  if addr >= pageStart and addr <= pageEnd then
    return
  end
  if addr < pageStart then
    self.scrollOffset = M.alignRow(addr)
  else
    self.scrollOffset = M.alignRow(addr - M.BYTES_PER_PAGE + M.COLS)
  end
  self:clampScroll()
end

function M:scrollByRows(deltaRows)
  deltaRows = math.floor(tonumber(deltaRows) or 0)
  if deltaRows == 0 then
    return false
  end
  local before = self.scrollOffset
  self.scrollOffset = M.alignRow(self.scrollOffset + deltaRows * M.COLS)
  self:clampScroll()
  return self.scrollOffset ~= before
end

--- Wheel with canvas pointer. opts.shift forces Shift+wheel step size (tests).
function M:wheelmovedAt(dx, dy, px, py, opts)
  if not self:contains(px, py) then
    return false
  end
  self._hoverX, self._hoverY = px, py
  opts = opts or {}
  local shift = opts.shift
  if shift == nil then
    shift = LoveCompat.isShiftDown()
  end
  local rows = shift and M.WHEEL_ROWS_SHIFT or M.WHEEL_ROWS
  local delta = (tonumber(dy) or 0) > 0 and -rows or ((tonumber(dy) or 0) < 0 and rows or 0)
  if delta ~= 0 then
    self:scrollByRows(delta)
  end
  return true
end

function M:addrAtPixel(px, py)
  local gridX = self.x + PAD + GUTTER_W
  local gridY = self.y + PAD + HEADER_H
  if px < gridX or py < gridY then
    return nil
  end
  local col = math.floor((px - gridX) / CELL_W)
  local row = math.floor((py - gridY) / CELL_H)
  if col < 0 or col >= M.COLS or row < 0 or row >= M.ROWS then
    return nil
  end
  local addr = self.scrollOffset + row * M.COLS + col
  local len = romLen(self.romRaw)
  if addr < 0 or addr >= len then
    return nil
  end
  return addr
end

local function startsCoveringAddr(starts, addr, span)
  span = math.max(1, math.floor(tonumber(span) or 1))
  local covering = {}
  for i, start in ipairs(starts) do
    if addr >= start and addr < start + span then
      covering[#covering + 1] = i
    end
  end
  return covering
end

--- Selected group start under the pointer, or nil when not over a selected span.
function M:getHoveredSelectedStart()
  if self._hoverX == nil or self._hoverY == nil then
    return nil
  end
  local addr = self:addrAtPixel(self._hoverX, self._hoverY)
  if addr == nil then
    return nil
  end
  local starts = self.selectedStarts or {}
  local covering = startsCoveringAddr(starts, addr, self:getGroupSize())
  if #covering == 0 then
    return nil
  end
  return starts[covering[#covering]]
end

--- Group start on `phase` that contains `addr`.
local function groupStartOnPhase(addr, phase, span)
  span = math.max(1, math.floor(tonumber(span) or 1))
  local k = math.floor((addr - phase) / span)
  return phase + k * span
end

local function phaseRefOfStarts(starts)
  local phase = starts[1]
  for i = 2, #starts do
    if starts[i] < phase then
      phase = starts[i]
    end
  end
  return phase
end

--- Add a single group for `addr` on the existing selection's phase.
--- `groupSize` defaults to OAM_SPAN for module-level callers/tests.
function M.addStartGroup(existingStarts, addr, groupSize)
  addr = math.floor(tonumber(addr) or 0)
  groupSize = math.max(1, math.floor(tonumber(groupSize) or M.OAM_SPAN))
  local existing = copyStarts(existingStarts)
  if #existing == 0 then
    return { addr }, addr
  end
  local newG = groupStartOnPhase(addr, phaseRefOfStarts(existing), groupSize)
  for _, s in ipairs(existing) do
    if s == newG then
      return existing, newG
    end
  end
  existing[#existing + 1] = newG
  return existing, newG
end

function M:mousepressed(px, py, button, _opts)
  if button ~= 1 or not self:contains(px, py) then
    return false
  end
  local addr = self:addrAtPixel(px, py)
  if addr == nil then
    return true
  end

  local span = self:getGroupSize()
  local covering = startsCoveringAddr(self.selectedStarts or {}, addr, span)
  if #covering > 0 then
    -- Toggle off the covered selected group; semi list is unchanged so outline returns.
    local removeIdx = covering[#covering]
    local removeAddr = self.selectedStarts[removeIdx]
    local nextStarts = {}
    for i, s in ipairs(self.selectedStarts) do
      if i ~= removeIdx then
        nextStarts[#nextStarts + 1] = s
      end
    end
    local primary = nextStarts[#nextStarts] or removeAddr
    self:_setStarts(nextStarts, primary, {
      scrollToReveal = false,
      emit = true,
      allowEmpty = true,
      resetColors = false,
    })
    return true
  end

  local resolved = self:resolveSelectableStart(addr)
  if resolved == nil then
    return true
  end

  local nextStarts, primary
  if #(self.selectedStarts or {}) == 0 then
    nextStarts, primary = { resolved }, resolved
  else
    nextStarts, primary = M.addStartGroup(self.selectedStarts, resolved, span)
    if self:startOverlapsDisabled(primary) then
      return true
    end
  end

  self:_setStarts(nextStarts, primary, {
    scrollToReveal = false,
    emit = true,
    resetColors = false,
  })
  return true
end

function M:mousemoved(px, py)
  self._hoverX, self._hoverY = px, py
end

function M:mousereleased(_px, _py, button)
  if button ~= 1 then
    return false
  end
  return false
end

function M:_colorSeqForStart(addr)
  addr = math.floor(tonumber(addr) or 0)
  local map = self._startColorIndex
  local seq = map and map[addr]
  if type(seq) ~= "number" then
    seq = 1
  end
  return seq
end

function M:highlightColorForStart(addr)
  local colorsList = M.getHighlightColors()
  local n = #colorsList
  if n == 0 then
    return { 0.2, 0.35, 0.85, 0.9 }
  end
  local i = ((self:_colorSeqForStart(addr) - 1) % n) + 1
  return colorsList[i]
end

--- Color for `selectedStarts[index]` (selection-order tint, not index-in-list).
function M:highlightColorForStartIndex(index)
  local starts = self.selectedStarts or {}
  local addr = starts[math.floor(tonumber(index) or 1)]
  if addr == nil then
    local colorsList = M.getHighlightColors()
    local n = #colorsList
    if n == 0 then
      return { 0.2, 0.35, 0.85, 0.9 }
    end
    local i = ((math.floor(tonumber(index) or 1) - 1) % n) + 1
    return colorsList[i]
  end
  return self:highlightColorForStart(addr)
end

function M:textColorForStart(addr)
  local n = #HIGHLIGHT_KEYS
  if n == 0 then
    return colors.white
  end
  local i = ((self:_colorSeqForStart(addr) - 1) % n) + 1
  if HIGHLIGHT_KEYS[i] == "yellow" then
    return colors.black
  end
  return colors.white
end

function M:textColorForStartIndex(index)
  local starts = self.selectedStarts or {}
  local addr = starts[math.floor(tonumber(index) or 1)]
  if addr == nil then
    local n = #HIGHLIGHT_KEYS
    local i = ((math.floor(tonumber(index) or 1) - 1) % n) + 1
    if HIGHLIGHT_KEYS[i] == "yellow" then
      return colors.black
    end
    return colors.white
  end
  return self:textColorForStart(addr)
end

local function printOffsetDigits(x, y, addr, font)
  local label = string.format("%0" .. OFFSET_DIGITS .. "X", addr)
  for i = 1, OFFSET_DIGITS do
    local ch = label:sub(i, i)
    local tw = Text.getFontWidth(ch, font)
    Text.print(ch, x + (i - 1) * OFFSET_DIGIT_W + math.floor((OFFSET_DIGIT_W - tw) * 0.5), y, {
      color = { 0.75, 0.75, 0.75, 1 },
      font = font,
      literalColor = true,
    })
  end
end

local function colorFromKey(key)
  if key == "gray" then
    local g = colors.gray50
    if type(g) == "table" and type(g[1]) == "number" then
      return { g[1], g[2] or 0, g[3] or 0, 0.9 }
    end
    return { 0.5, 0.5, 0.5, 0.9 }
  end
  local rgb = colors[key]
  if type(rgb) == "table" and type(rgb[1]) == "number" then
    return { rgb[1], rgb[2] or 0, rgb[3] or 0, 0.9 }
  end
  return { 0.2, 0.35, 0.85, 0.9 }
end

--- Read-only vertical scrollbar: track, optional minimap markers, then thumb.
function M:_drawScrollbar(gridX, gridY)
  local maxS = self:maxScroll()
  local trackH = M.ROWS * CELL_H
  local trackX = gridX + M.COLS * CELL_W + SCROLLBAR_GAP
  local trackY = gridY
  local len = romLen(self.romRaw)

  -- Always draw track when there is ROM (minimap useful even if no scroll).
  local showScroll = maxS > 0
  if showScroll or (#(self.minimapMarkers or {}) > 0 and len > 0) then
    love.graphics.setColor(1, 1, 1, 0.18)
    love.graphics.rectangle("fill", trackX, trackY, SCROLLBAR_W, trackH)
  end

  if len > 0 then
    for _, marker in ipairs(self.minimapMarkers or {}) do
      local offset = marker.offset
      if type(offset) == "number" and offset >= 0 and offset < len then
        local byteLen = M.minimapMarkerByteLength(marker)
        local endOffset = math.min(len, offset + byteLen)
        local y0 = math.floor(trackY + (trackH - 1) * (offset / len))
        local y1 = math.floor(trackY + (trackH - 1) * ((endOffset - 1) / len))
        if y1 < y0 then y1 = y0 end
        -- At least 1px; larger ranges stretch on the track. Overlaps are fine.
        local h = math.max(1, y1 - y0 + 1)
        local c = colorFromKey(marker.color)
        love.graphics.setColor(c[1], c[2], c[3], c[4] or 0.9)
        love.graphics.rectangle("fill", trackX, y0, SCROLLBAR_W, h)
      end
    end
  end

  if not showScroll then
    return
  end
  local visibleFrac = M.BYTES_PER_PAGE / (maxS + M.BYTES_PER_PAGE)
  local thumbH = math.max(4, math.floor(trackH * visibleFrac))
  local offsetFrac = (self.scrollOffset or 0) / maxS
  if offsetFrac < 0 then offsetFrac = 0 end
  if offsetFrac > 1 then offsetFrac = 1 end
  local thumbY = math.floor(trackY + (trackH - thumbH) * offsetFrac)

  love.graphics.setColor(1, 1, 1, 0.65)
  love.graphics.rectangle("fill", trackX, thumbY, SCROLLBAR_W, thumbH)
end

--- One rounded rect per contiguous same-row run of a group (splits on row wrap).
--- mode: "fill" (default) or "line".
function M:_drawGroupHighlights(gridX, gridY, starts, colorForStart, mode)
  mode = mode or "fill"
  local span = self:getGroupSize()
  local pageStart = self.scrollOffset
  local pageEnd = pageStart + M.BYTES_PER_PAGE - 1
  for _, start in ipairs(starts or {}) do
    local c
    if type(colorForStart) == "function" then
      c = colorForStart(start)
    else
      c = self:highlightColorForStart(start)
    end
    if type(c) ~= "table" then
      c = { 0.5, 0.5, 0.5, 0.9 }
    end
    love.graphics.setColor(c[1], c[2], c[3], c[4] or 0.9)

    local runCol, runRow, runLen = nil, nil, 0
    local function flush()
      if runLen > 0 and runCol ~= nil then
        local x = gridX + runCol * CELL_W
        local y = gridY + runRow * CELL_H
        local w = runLen * CELL_W - 1
        if mode == "line" then
          love.graphics.rectangle("line", x, y, w, CELL_H, HIGHLIGHT_RADIUS, HIGHLIGHT_RADIUS)
        else
          love.graphics.rectangle("fill", x, y, w, CELL_H, HIGHLIGHT_RADIUS, HIGHLIGHT_RADIUS)
        end
      end
      runCol, runRow, runLen = nil, nil, 0
    end

    for off = 0, span - 1 do
      local a = start + off
      if a >= pageStart and a <= pageEnd then
        local rel = a - pageStart
        local row = math.floor(rel / M.COLS)
        local col = rel % M.COLS
        if runLen == 0 then
          runCol, runRow, runLen = col, row, 1
        elseif row == runRow and col == runCol + runLen then
          runLen = runLen + 1
        else
          flush()
          runCol, runRow, runLen = col, row, 1
        end
      else
        flush()
      end
    end
    flush()
  end
end

function M:draw()
  local font = nil
  if love and love.graphics and love.graphics.getFont then
    local ok, f = pcall(love.graphics.getFont)
    if ok then font = f end
  end
  local x0 = self.x + PAD
  local y0 = self.y + PAD
  local gridX = x0 + GUTTER_W
  local gridY = y0 + HEADER_H

  love.graphics.setColor(colors.black[1], colors.black[2], colors.black[3], 0.55)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

  for col = 0, M.COLS - 1 do
    local label = string.format("%02X", col)
    local tw = Text.getFontWidth(label, font)
    Text.print(label, gridX + col * CELL_W + math.floor((CELL_W - tw) * 0.5), y0 + TEXT_NUDGE_Y, {
      color = colors.white,
      font = font,
      literalColor = true,
    })
  end

  love.graphics.setColor(0.7, 0.7, 0.7, 1)
  love.graphics.line(gridX, gridY - 1, gridX + M.COLS * CELL_W, gridY - 1)
  love.graphics.line(gridX - 1, gridY, gridX - 1, gridY + M.ROWS * CELL_H)

  local len = romLen(self.romRaw)
  local disabled = self.disabledStarts or {}
  local semi = self.semiSelectedStarts or {}
  local starts = self.selectedStarts or {}
  local span = self:getGroupSize()
  -- Semi outline under selection fill; disabled gray on top.
  self:_drawGroupHighlights(gridX, gridY, semi, nil, "line")
  self:_drawGroupHighlights(gridX, gridY, starts, nil, "fill")
  self:_drawGroupHighlights(gridX, gridY, disabled, function()
    return disabledHighlightColor()
  end, "fill")

  local hoverAddr = nil
  if self._hoverX ~= nil and self._hoverY ~= nil then
    hoverAddr = self:addrAtPixel(self._hoverX, self._hoverY)
  end

  local disText = disabledTextColor()

  for row = 0, M.ROWS - 1 do
    local rowAddr = self.scrollOffset + row * M.COLS
    local rowY = gridY + row * CELL_H
    printOffsetDigits(x0, rowY + TEXT_NUDGE_Y, rowAddr, font)

    for col = 0, M.COLS - 1 do
      local addr = rowAddr + col
      local cellX = gridX + col * CELL_W
      local covering = startsCoveringAddr(starts, addr, span)
      local coveringDis = startsCoveringAddr(disabled, addr, span)
      local coveringSemi = startsCoveringAddr(semi, addr, span)
      local base = colors.white
      if #coveringDis > 0 then
        base = disText
      elseif #covering > 0 then
        base = self:textColorForStart(starts[covering[#covering]])
      elseif #coveringSemi > 0 then
        base = self:textColorForStart(semi[coveringSemi[#coveringSemi]])
      end
      local alpha = (hoverAddr ~= nil and addr == hoverAddr) and 1 or 0.6
      local textColor = { base[1], base[2], base[3], alpha }
      local byteText = "  "
      if addr < len then
        byteText = string.format("%02X", string.byte(self.romRaw, addr + 1) or 0)
      end
      local tw = Text.getFontWidth(byteText, font)
      Text.print(byteText, cellX + math.floor((CELL_W - tw) * 0.5), rowY + TEXT_NUDGE_Y, {
        color = textColor,
        font = font,
        literalColor = true,
      })
    end
  end

  self:_drawScrollbar(gridX, gridY)

  love.graphics.setColor(colors.white)
end

return M
