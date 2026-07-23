-- Shared fixtures for Mirror X drag/drop and clipboard layout tests.
-- Loaded via loadfile from sibling unit test files (not on package.path).

local Window = require("user_interface.windows_system.window")

local M = {}

function M.makeGroup(entries, extra)
  local minCol, maxCol = 0, 0
  local minRow, maxRow = 0, 0
  for i, entry in ipairs(entries) do
    local col = entry.offsetCol or 0
    local row = entry.offsetRow or 0
    if i == 1 then
      minCol, maxCol = col, col
      minRow, maxRow = row, row
    else
      if col < minCol then minCol = col end
      if col > maxCol then maxCol = col end
      if row < minRow then minRow = row end
      if row > maxRow then maxRow = row end
    end
  end
  local group = {
    entries = entries,
    minOffsetCol = minCol,
    maxOffsetCol = maxCol,
    minOffsetRow = minRow,
    maxOffsetRow = maxRow,
    spanCols = (maxCol - minCol) + 1,
    spanRows = (maxRow - minRow) + 1,
    sourceSelectionMode = "8x8",
  }
  if extra then
    for k, v in pairs(extra) do
      group[k] = v
    end
  end
  return group
end

function M.item(index, bank)
  return { id = "t" .. tostring(index), index = index, _bankIndex = bank or 1 }
end

function M.singleEntry(offsetCol, offsetRow, index)
  return {
    srcCol = offsetCol or 0,
    srcRow = offsetRow or 0,
    offsetCol = offsetCol or 0,
    offsetRow = offsetRow or 0,
    item = M.item(index or 1),
  }
end

--- Contiguous row of N tiles starting at offset 0.
function M.contiguousRow(count, startIndex)
  local entries = {}
  startIndex = startIndex or 1
  for i = 0, count - 1 do
    entries[#entries + 1] = M.singleEntry(i, 0, startIndex + i)
  end
  return M.makeGroup(entries)
end

--- Non-contiguous: tiles at cols 0 and 2 (hole at 1).
function M.gappedRowTwo()
  return M.makeGroup({
    M.singleEntry(0, 0, 1),
    M.singleEntry(2, 0, 2),
  })
end

--- Non-contiguous L-ish with a hole: (0,0), (2,0), (2,1).
function M.gappedShape()
  return M.makeGroup({
    M.singleEntry(0, 0, 1),
    M.singleEntry(2, 0, 2),
    M.singleEntry(2, 1, 3),
  })
end

function M.make8x16Group(spriteEntriesExtra)
  local topA = M.item(4)
  local botA = M.item(5)
  local topB = M.item(6)
  local botB = M.item(7)
  local entries = {
    { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = topA },
    { srcCol = 0, srcRow = 1, offsetCol = 0, offsetRow = 1, item = botA },
    { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = topB },
    { srcCol = 1, srcRow = 1, offsetCol = 1, offsetRow = 1, item = botB },
  }
  local spriteEntries = {
    { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = topA, bottomItem = botA },
    { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = topB, bottomItem = botB },
  }
  local group = M.makeGroup(entries, {
    sourceSelectionMode = "8x16",
    spriteEntries = spriteEntries,
    spriteMinOffsetCol = 0,
    spriteMaxOffsetCol = 1,
    spriteMinOffsetRow = 0,
    spriteMaxOffsetRow = 0,
    spriteSpanCols = 2,
    spriteSpanRows = 1,
  })
  if spriteEntriesExtra then
    for k, v in pairs(spriteEntriesExtra) do
      group[k] = v
    end
  end
  return group, topA, botA, topB, botB
end

function M.make8x16GappedGroup()
  local topA = M.item(4)
  local botA = M.item(5)
  local topC = M.item(8)
  local botC = M.item(9)
  local entries = {
    { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = topA },
    { srcCol = 0, srcRow = 1, offsetCol = 0, offsetRow = 1, item = botA },
    { srcCol = 2, srcRow = 0, offsetCol = 2, offsetRow = 0, item = topC },
    { srcCol = 2, srcRow = 1, offsetCol = 2, offsetRow = 1, item = botC },
  }
  local spriteEntries = {
    { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = topA, bottomItem = botA },
    { srcCol = 2, srcRow = 0, offsetCol = 2, offsetRow = 0, item = topC, bottomItem = botC },
  }
  return M.makeGroup(entries, {
    sourceSelectionMode = "8x16",
    spriteEntries = spriteEntries,
    spriteMinOffsetCol = 0,
    spriteMaxOffsetCol = 2,
    spriteMinOffsetRow = 0,
    spriteMaxOffsetRow = 0,
    spriteSpanCols = 3,
    spriteSpanRows = 1,
  }), topA, botA, topC, botC
end

function M.winFlags(mirror)
  return { kind = "chr", _mirrorXPreview = mirror == true }
end

function M.dstFlags(mirror, kind)
  return { kind = kind or "static_art", _mirrorXPreview = mirror == true }
end

function M.makeTileWindow(cols, rows, opts)
  opts = opts or {}
  local items = {}
  local win = {
    kind = opts.kind or "static_art",
    _mirrorXPreview = opts.mirror == true,
    x = 0,
    y = 0,
    zoom = 1,
    cellW = 8,
    cellH = 8,
    cols = cols,
    rows = rows,
    scrollCol = 0,
    scrollRow = 0,
    layers = { { kind = "tile" } },
    getActiveLayerIndex = function()
      return 1
    end,
    isInContentArea = function(_, x, y)
      return x >= 0 and y >= 0 and x < (cols * 8) and y < (rows * 8)
    end,
    toGridCoords = function(self, x, y)
      local sx, sy = x, y
      if self.remapPreviewMirrorScreenXYIfNeeded then
        sx, sy = self:remapPreviewMirrorScreenXYIfNeeded(x, y)
      end
      if sx < 0 or sy < 0 or sx >= cols * 8 or sy >= rows * 8 then
        return false
      end
      return true, math.floor(sx / 8), math.floor(sy / 8)
    end,
    set = function(_, col, row, item)
      items[(row * cols) + col + 1] = item
    end,
    get = function(_, col, row)
      return items[(row * cols) + col + 1]
    end,
    setSelected = function() end,
    clearSelected = function() end,
  }
  if opts.useRealMirrorRemap then
    M.attachRealMirrorMapping(win, cols * 8, rows * 8)
  end
  win._items = items
  return win
end

function M.makeSpriteWindow(cols, rows, mode, opts)
  opts = opts or {}
  local win = {
    kind = opts.kind or "static_art",
    _mirrorXPreview = opts.mirror == true,
    x = 0,
    y = 0,
    zoom = 1,
    cellW = 8,
    cellH = 8,
    cols = cols,
    rows = rows,
    scrollCol = 0,
    scrollRow = 0,
    layers = {
      {
        kind = "sprite",
        mode = mode or "8x8",
        items = {},
        originX = 0,
        originY = 0,
      },
    },
    getActiveLayerIndex = function()
      return 1
    end,
    isInContentArea = function(_, x, y)
      return x >= 0 and y >= 0 and x < (cols * 8) and y < (rows * 8)
    end,
    toGridCoords = function(self, x, y)
      local sx, sy = x, y
      if self.remapPreviewMirrorScreenXYIfNeeded then
        sx, sy = self:remapPreviewMirrorScreenXYIfNeeded(x, y)
      end
      if sx < 0 or sy < 0 or sx >= cols * 8 or sy >= rows * 8 then
        return false
      end
      return true, math.floor(sx / 8), math.floor(sy / 8)
    end,
  }
  if opts.useRealMirrorRemap then
    M.attachRealMirrorMapping(win, cols * 8, rows * 8)
  end
  return win
end

function M.attachRealMirrorMapping(win, contentW, contentH)
  contentW = contentW or 64
  contentH = contentH or 64
  win.getZoomLevel = function()
    return 1
  end
  win.getInsetContentScreenRect = function()
    return 0, 0, contentW, contentH
  end
  win.remapPreviewMirrorScreenXYIfNeeded = Window.remapPreviewMirrorScreenXYIfNeeded
  win.screenToAbsoluteCanvasXY = Window.screenToAbsoluteCanvasXY
end

function M.withUnfocusedCtx(fn)
  local previousCtx = rawget(_G, "ctx")
  _G.ctx = {
    app = {
      wm = {
        getFocus = function()
          return { id = "other" }
        end,
      },
    },
  }
  local ok, err = pcall(fn)
  _G.ctx = previousCtx
  if not ok then
    error(err)
  end
end

function M.poolForItems(items)
  local bank = {}
  for _, it in ipairs(items) do
    bank[it.index] = it
  end
  return { [1] = bank }
end

function M.sortedOffsetCols(entries)
  local cols = {}
  for _, e in ipairs(entries or {}) do
    cols[#cols + 1] = e.offsetCol or 0
  end
  table.sort(cols)
  return cols
end

function M.offsetsByItemIndex(entries)
  local map = {}
  for _, e in ipairs(entries or {}) do
    local idx = e.item and e.item.index
    if idx ~= nil then
      map[idx] = e.offsetCol or 0
    end
  end
  return map
end

return M
