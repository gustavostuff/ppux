-- Toolbar-driven grid resize for animation / static art windows (cols × rows, cellW × cellH).

local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local function idxBy(cols, col, row)
  return row * cols + col + 1
end

function M.isGridResizeWindow(win)
  return win
    and not win._closed
    and not win._minimized
    and (WindowCaps.isAnimationLike(win) or WindowCaps.isStaticArt(win))
end

local function layerSpriteBoundsPx(layer, sprite, cw, ch)
  local originX = layer.originX or 0
  local originY = layer.originY or 0
  local mode = layer.mode or "8x8"
  local wTile = cw
  local hSprite = (mode == "8x16") and (2 * ch) or ch
  local px = originX + (sprite.worldX or sprite.baseX or sprite.x or 0)
  local py = originY + (sprite.worldY or sprite.baseY or sprite.y or 0)
  return px, py, px + wTile, py + hSprite
end

local function intervalsOverlap1D(a0, a1, b0, b1)
  return a0 < b1 and b0 < a1
end

local function tileOccupiesColumn(win, col)
  local cols = win.cols or 1
  local rows = win.rows or 1
  for li, L in ipairs(win.layers or {}) do
    if L.kind == "tile" and L.items then
      for row = 0, rows - 1 do
        local i = idxBy(cols, col, row)
        if L.items[i] ~= nil then
          return true
        end
      end
    end
  end
  return false
end

local function tileOccupiesRow(win, row)
  local cols = win.cols or 1
  local rows = win.rows or 1
  for li, L in ipairs(win.layers or {}) do
    if L.kind == "tile" and L.items then
      for col = 0, cols - 1 do
        local i = idxBy(cols, col, row)
        if L.items[i] ~= nil then
          return true
        end
      end
    end
  end
  return false
end

local function spriteOverlapsColumnStrip(win, colIndex)
  local cols = win.cols or 1
  local rows = win.rows or 1
  local cw = win.cellW or 8
  local ch = win.cellH or 8
  local stripX0 = colIndex * cw
  local stripX1 = (colIndex + 1) * cw
  local gridY0 = 0
  local gridY1 = rows * ch

  for _, L in ipairs(win.layers or {}) do
    if L.kind == "sprite" and L.items then
      for _, s in ipairs(L.items) do
        if s and s.removed ~= true then
          local x0, y0, x1, y1 = layerSpriteBoundsPx(L, s, cw, ch)
          if intervalsOverlap1D(x0, x1, stripX0, stripX1)
              and intervalsOverlap1D(y0, y1, gridY0, gridY1) then
            return true
          end
        end
      end
    end
  end
  return false
end

local function spriteOverlapsRowStrip(win, rowIndex)
  local cols = win.cols or 1
  local rows = win.rows or 1
  local cw = win.cellW or 8
  local ch = win.cellH or 8
  local gridX0 = 0
  local gridX1 = cols * cw
  local stripY0 = rowIndex * ch
  local stripY1 = (rowIndex + 1) * ch

  for _, L in ipairs(win.layers or {}) do
    if L.kind == "sprite" and L.items then
      for _, s in ipairs(L.items) do
        if s and s.removed ~= true then
          local x0, y0, x1, y1 = layerSpriteBoundsPx(L, s, cw, ch)
          if intervalsOverlap1D(x0, x1, gridX0, gridX1)
              and intervalsOverlap1D(y0, y1, stripY0, stripY1) then
            return true
          end
        end
      end
    end
  end
  return false
end

function M.canRemoveLastColumn(win)
  local cols = win.cols or 1
  if cols <= 1 then
    return false, "Can't remove column, it's occupied by layout items."
  end
  local lastCol = cols - 1
  if tileOccupiesColumn(win, lastCol) or spriteOverlapsColumnStrip(win, lastCol) then
    return false, "Can't remove column, it's occupied by layout items."
  end
  return true
end

function M.canRemoveLastRow(win)
  local rows = win.rows or 1
  if rows <= 1 then
    return false, "Can't remove row, it's occupied by layout items."
  end
  local lastRow = rows - 1
  if tileOccupiesRow(win, lastRow) or spriteOverlapsRowStrip(win, lastRow) then
    return false, "Can't remove row, it's occupied by layout items."
  end
  return true
end

local function remapSparseIndexMap(map, oldCols, newCols, rows)
  if not map then
    return
  end
  local out = {}
  for oldIdx, v in pairs(map) do
    if v then
      local z = math.floor(tonumber(oldIdx) or 0) - 1
      if z >= 0 then
        local col = z % oldCols
        local row = math.floor(z / oldCols)
        if col < newCols and row < rows then
          out[row * newCols + col + 1] = true
        end
      end
    end
  end
  for k in pairs(map) do
    map[k] = nil
  end
  for k, v in pairs(out) do
    map[k] = v
  end
end

-- paletteNumbers is keyed by 0-based linear index (row * cols + col), matching
-- core_controller_draw and layout hydration; remap when cols changes.
local function remapPaletteNumbersForNewCols(L, oldCols, newCols, rows)
  if not (L and L.paletteNumbers) then
    return
  end
  local map = L.paletteNumbers
  local out = {}
  for oldKey, v in pairs(map) do
    if v ~= nil then
      local z = math.floor(tonumber(oldKey) or -1)
      if z >= 0 then
        local col = z % oldCols
        local row = math.floor(z / oldCols)
        if col < newCols and row < rows then
          local newKey = row * newCols + col
          out[newKey] = v
        end
      end
    end
  end
  for k in pairs(map) do
    map[k] = nil
  end
  for k, v in pairs(out) do
    map[k] = v
  end
end

local function migrateTileLayerItemsForNewCols(L, oldCols, newCols, rows)
  if not (L and L.kind == "tile") then
    return
  end
  L.items = L.items or {}
  local oldItems = L.items
  local newItems = {}
  for row = 0, rows - 1 do
    for col = 0, math.min(oldCols, newCols) - 1 do
      local oi = row * oldCols + col + 1
      local ni = row * newCols + col + 1
      newItems[ni] = oldItems[oi]
    end
  end
  L.items = newItems
  remapSparseIndexMap(L.removedCells, oldCols, newCols, rows)
  remapSparseIndexMap(L.multiTileSelection, oldCols, newCols, rows)
  remapPaletteNumbersForNewCols(L, oldCols, newCols, rows)
end

local function clampSelectionsAfterGridChange(win)
  local cols = win.cols or 1
  local rows = win.rows or 1
  if win.selectedByLayer then
    for li, sel in pairs(win.selectedByLayer) do
      if sel and type(sel.col) == "number" and type(sel.row) == "number" then
        if sel.col < 0 or sel.col >= cols or sel.row < 0 or sel.row >= rows then
          win.selectedByLayer[li] = nil
        end
      end
    end
  end
  win.selected = win.selectedByLayer and win.selectedByLayer[win.activeLayer or 1] or nil
end

function M.addColumn(win)
  local oldCols = win.cols or 1
  local rows = win.rows or 1
  local newCols = oldCols + 1
  for _, L in ipairs(win.layers or {}) do
    if L.kind == "tile" then
      migrateTileLayerItemsForNewCols(L, oldCols, newCols, rows)
    end
  end
  win.cols = newCols
  win.visibleCols = math.min(win.visibleCols or newCols, newCols)
  if win.setScroll then
    win:setScroll(win.scrollCol or 0, win.scrollRow or 0)
  end
  clampSelectionsAfterGridChange(win)
  if win.invalidateAllTileLayerCanvases then
    win:invalidateAllTileLayerCanvases()
  end
  return true
end

function M.removeLastColumn(win)
  local ok, err = M.canRemoveLastColumn(win)
  if not ok then
    return false, err
  end
  local oldCols = win.cols or 1
  local rows = win.rows or 1
  local newCols = oldCols - 1
  for _, L in ipairs(win.layers or {}) do
    if L.kind == "tile" then
      migrateTileLayerItemsForNewCols(L, oldCols, newCols, rows)
    end
  end
  win.cols = newCols
  win.visibleCols = math.min(win.visibleCols or newCols, newCols)
  if win.setScroll then
    win:setScroll(win.scrollCol or 0, win.scrollRow or 0)
  end
  clampSelectionsAfterGridChange(win)
  if win.invalidateAllTileLayerCanvases then
    win:invalidateAllTileLayerCanvases()
  end
  return true
end

function M.addRow(win)
  local cols = win.cols or 1
  local oldRows = win.rows or 1
  win.rows = oldRows + 1
  win.visibleRows = math.min(win.visibleRows or win.rows, win.rows)
  if win.setScroll then
    win:setScroll(win.scrollCol or 0, win.scrollRow or 0)
  end
  clampSelectionsAfterGridChange(win)
  if win.invalidateAllTileLayerCanvases then
    win:invalidateAllTileLayerCanvases()
  end
  return true
end

function M.removeLastRow(win)
  local ok, err = M.canRemoveLastRow(win)
  if not ok then
    return false, err
  end
  local cols = win.cols or 1
  local oldRows = win.rows or 1
  local newRows = oldRows - 1
  for _, L in ipairs(win.layers or {}) do
    if L.kind == "tile" then
      L.items = L.items or {}
      for col = 0, cols - 1 do
        local deadIdx = idxBy(cols, col, oldRows - 1)
        L.items[deadIdx] = nil
      end
      if L.removedCells then
        for col = 0, cols - 1 do
          L.removedCells[idxBy(cols, col, oldRows - 1)] = nil
        end
      end
      if L.multiTileSelection then
        for col = 0, cols - 1 do
          L.multiTileSelection[idxBy(cols, col, oldRows - 1)] = nil
        end
      end
    end
  end
  win.rows = newRows
  win.visibleRows = math.min(win.visibleRows or newRows, newRows)
  if win.setScroll then
    win:setScroll(win.scrollCol or 0, win.scrollRow or 0)
  end
  clampSelectionsAfterGridChange(win)
  if win.invalidateAllTileLayerCanvases then
    win:invalidateAllTileLayerCanvases()
  end
  return true
end

function M.applyFocusedResize(app, opts)
  opts = opts or {}
  local wm = app and app.wm
  if not (wm and wm.getFocus) then
    return false, "No focused window."
  end
  local win = wm:getFocus()
  if not win or win._closed or win._minimized then
    return false, "No focused window."
  end
  if not M.isGridResizeWindow(win) then
    return false, "Grid resize is not available for this window."
  end

  local addCol = opts.addColumn == true
  local addRow = opts.addRow == true
  local remCol = opts.removeColumn == true
  local remRow = opts.removeRow == true

  local ok, err
  if addCol then
    ok = M.addColumn(win)
  elseif addRow then
    ok = M.addRow(win)
  elseif remCol then
    ok, err = M.removeLastColumn(win)
  elseif remRow then
    ok, err = M.removeLastRow(win)
  else
    return false, "No resize action."
  end

  if not ok then
    return false, err or "Could not resize grid."
  end
  if app.markUnsaved then
    app:markUnsaved("tile_move")
  end
  return true
end

return M
