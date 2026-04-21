-- Snapshot / restore grid dimensions and per-layer tile/sprite placement for
-- animation + static art windows (add/remove row/column toolbar actions).

local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local function supportedWin(win)
  return win and (WindowCaps.isAnimationLike(win) or WindowCaps.isStaticArt(win))
end

local function cloneSparseMap(src)
  if not src then
    return nil
  end
  local dst = {}
  for k, v in pairs(src) do
    dst[k] = v
  end
  return dst
end

local function cloneSelectedEntry(sel)
  if not sel then
    return nil
  end
  local c = {}
  for k, v in pairs(sel) do
    c[k] = v
  end
  return c
end

local function cloneSelectedByLayer(sb)
  if not sb then
    return nil
  end
  local t = {}
  for k, v in pairs(sb) do
    t[k] = cloneSelectedEntry(v)
  end
  return t
end

local function cloneSpriteItem(spr)
  if not spr then
    return nil
  end
  local c = {}
  for k, v in pairs(spr) do
    c[k] = v
  end
  return c
end

local function sparseMapsEqual(a, b)
  local seen = {}
  for k, v in pairs(a or {}) do
    seen[k] = true
    if (b or {})[k] ~= v then
      return false
    end
  end
  for k in pairs(b or {}) do
    if not seen[k] then
      return false
    end
  end
  return true
end

local function spriteListsEqual(a, b)
  local la, lb = a or {}, b or {}
  if #la ~= #lb then
    return false
  end
  for i = 1, #la do
    if not sparseMapsEqual(la[i], lb[i]) then
      return false
    end
  end
  return true
end

local function selectedByLayerEqual(a, b)
  local keys = {}
  for k in pairs(a or {}) do
    keys[k] = true
  end
  for k in pairs(b or {}) do
    keys[k] = true
  end
  for k in pairs(keys) do
    if not sparseMapsEqual(a and a[k], b and b[k]) then
      return false
    end
  end
  return true
end

function M.snapshot(win)
  if not supportedWin(win) then
    return nil
  end
  local layerSnaps = {}
  for li, L in ipairs(win.layers or {}) do
    local kind = L and L.kind
    local entry = { kind = kind }
    if kind == "tile" then
      entry.items = cloneSparseMap(L.items or {})
      entry.paletteNumbers = cloneSparseMap(L.paletteNumbers)
      entry.removedCells = cloneSparseMap(L.removedCells)
      entry.multiTileSelection = cloneSparseMap(L.multiTileSelection)
    elseif kind == "sprite" then
      entry.items = {}
      for i, spr in ipairs(L.items or {}) do
        entry.items[i] = cloneSpriteItem(spr)
      end
    end
    layerSnaps[li] = entry
  end
  return {
    cols = win.cols,
    rows = win.rows,
    visibleCols = win.visibleCols,
    visibleRows = win.visibleRows,
    scrollCol = win.scrollCol,
    scrollRow = win.scrollRow,
    selectedByLayer = cloneSelectedByLayer(win.selectedByLayer),
    layers = layerSnaps,
  }
end

local function assignSparseField(L, field, snapVal)
  if snapVal == nil then
    L[field] = nil
    return
  end
  L[field] = L[field] or {}
  local dst = L[field]
  for k in pairs(dst) do
    dst[k] = nil
  end
  for k, v in pairs(snapVal) do
    dst[k] = v
  end
end

function M.apply(win, snap)
  if not (win and snap and supportedWin(win)) then
    return false
  end
  win.cols = snap.cols
  win.rows = snap.rows
  win.visibleCols = snap.visibleCols
  win.visibleRows = snap.visibleRows
  win.scrollCol = snap.scrollCol
  win.scrollRow = snap.scrollRow
  if win.setScroll then
    win:setScroll(snap.scrollCol or 0, snap.scrollRow or 0)
  end
  if snap.selectedByLayer then
    win.selectedByLayer = cloneSelectedByLayer(snap.selectedByLayer)
    win.selected = win.selectedByLayer[win.activeLayer or 1]
  end
  for li, layerSnap in ipairs(snap.layers or {}) do
    local L = win.layers and win.layers[li]
    if L and layerSnap then
      if layerSnap.kind == "tile" and L.kind == "tile" then
        assignSparseField(L, "items", layerSnap.items)
        assignSparseField(L, "paletteNumbers", layerSnap.paletteNumbers)
        assignSparseField(L, "removedCells", layerSnap.removedCells)
        assignSparseField(L, "multiTileSelection", layerSnap.multiTileSelection)
      elseif layerSnap.kind == "sprite" and L.kind == "sprite" then
        L.items = {}
        for i, spr in ipairs(layerSnap.items or {}) do
          L.items[i] = cloneSpriteItem(spr)
        end
      end
    end
  end
  if win.updateLayerOpacities then
    win:updateLayerOpacities()
  end
  if win.isPlaying and win.scheduleNextFrame then
    win:scheduleNextFrame()
  end
  return true
end

function M.snapshotsEqual(a, b)
  if not (a and b) then
    return false
  end
  if (a.cols or 0) ~= (b.cols or 0) or (a.rows or 0) ~= (b.rows or 0) then
    return false
  end
  if (a.visibleCols or 0) ~= (b.visibleCols or 0) or (a.visibleRows or 0) ~= (b.visibleRows or 0) then
    return false
  end
  if (a.scrollCol or 0) ~= (b.scrollCol or 0) or (a.scrollRow or 0) ~= (b.scrollRow or 0) then
    return false
  end
  if not selectedByLayerEqual(a.selectedByLayer, b.selectedByLayer) then
    return false
  end
  if #(a.layers or {}) ~= #(b.layers or {}) then
    return false
  end
  for li = 1, #(a.layers or {}) do
    local la, lb = a.layers[li], b.layers[li]
    if (la.kind or "") ~= (lb.kind or "") then
      return false
    end
    if la.kind == "tile" then
      if not sparseMapsEqual(la.items, lb.items) then
        return false
      end
      if not sparseMapsEqual(la.paletteNumbers, lb.paletteNumbers) then
        return false
      end
      if not sparseMapsEqual(la.removedCells, lb.removedCells) then
        return false
      end
      if not sparseMapsEqual(la.multiTileSelection, lb.multiTileSelection) then
        return false
      end
    elseif la.kind == "sprite" then
      if not spriteListsEqual(la.items, lb.items) then
        return false
      end
    end
  end
  return true
end

return M
