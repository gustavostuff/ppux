-- sketch_canvas_pack_controller.lua
-- Pack a sketch canvas into tilesPool ({x,y} refs) + nametableBytes, and apply to a linked PT.

local Tile = require("user_interface.windows_system.tile_item")
local PixelCanvas = require("user_interface.windows_system.pixel_canvas")
local BankViewController = require("controllers.chr.bank_view_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local TileInvalidationIndex = require("controllers.app.tile_invalidation_index")

local M = {}

M.MAX_UNIQUE = 256
M.PT_SLOT_COUNT = 256
M.GRID_COLS = 32
M.GRID_ROWS = 30
M.CELL = 8
M.MAX_TOLERANCE = 64
M.SKETCH_OWNED_PATTERN_TABLE_MSG =
  "Pattern table is linked to a sketch canvas (CHR drops blocked)"

local function pixelDiffCount(pattern1, pattern2, threshold)
  threshold = threshold or 0
  local differences = 0
  for i = 1, 64 do
    if pattern1[i] ~= pattern2[i] then
      differences = differences + 1
      if differences > threshold then
        return differences
      end
    end
  end
  return differences
end

local function resolveCanvas(winOrCanvas)
  if type(winOrCanvas) ~= "table" then
    return nil
  end
  if type(winOrCanvas.extractTilePixels) == "function" and type(winOrCanvas.getPixel) == "function" then
    return winOrCanvas
  end
  if type(winOrCanvas.getActiveCanvas) == "function" then
    return winOrCanvas:getActiveCanvas()
  end
  local layer = winOrCanvas.layers and winOrCanvas.layers[winOrCanvas.activeLayer or 1]
  if layer and layer.kind == "canvas" and layer.canvas then
    return layer.canvas
  end
  return nil
end

local function clampTolerance(tolerance)
  local t = math.floor(tonumber(tolerance) or 0)
  if t < 0 then
    return 0
  end
  if t > M.MAX_TOLERANCE then
    return M.MAX_TOLERANCE
  end
  return t
end

local function copyPixels(pixels)
  local out = {}
  for i = 1, 64 do
    out[i] = math.floor(tonumber(pixels and pixels[i]) or 0)
  end
  return out
end

local function findWindowById(wm, id)
  if not (wm and type(id) == "string" and id ~= "") then
    return nil
  end
  if wm.findWindowById then
    return wm:findWindowById(id)
  end
  if wm.getWindows then
    for _, w in ipairs(wm:getWindows()) do
      if w and w._id == id then
        return w
      end
    end
  end
  return nil
end

local function clearPatternTableScratchItems(ptWin)
  local layer = ptWin and ptWin.layers and ptWin.layers[1]
  if not layer then
    return
  end
  layer.items = {}
  if type(layer.patternTable) ~= "table" then
    layer.patternTable = { ranges = {} }
  else
    layer.patternTable.ranges = {}
  end
  if ptWin.invalidateTileLayerCanvas then
    ptWin:invalidateTileLayerCanvas(1)
  end
  TileInvalidationIndex.markDirtyFromCtx()
end

function M.makeScratchTileFromPixels(pixels)
  local tile = Tile.blank(0)
  for i = 1, 64 do
    tile.pixels[i] = math.floor(tonumber(pixels and pixels[i]) or 0)
  end
  tile._imageDirty = true
  return tile
end

--- Place 0-based logical tile refs into the PT grid using the layer's 8x8 / 8x16 ordering.
local function placeLogicalTilesOnPatternTable(ptWin, logicalTiles)
  local layer = ptWin and ptWin.layers and ptWin.layers[1]
  if not layer then
    return false
  end
  local layoutMode = layer.mode or "8x8"
  layer.patternTable = { ranges = {} }
  layer.items = {}
  for pos = 0, M.PT_SLOT_COUNT - 1 do
    local logicalIndex = BankViewController.chrOrderingIndexForGridPos(layoutMode, pos)
    layer.items[pos + 1] = logicalTiles[logicalIndex]
  end
  if ptWin.invalidateTileLayerCanvas then
    ptWin:invalidateTileLayerCanvas(1)
  end
  TileInvalidationIndex.markDirtyFromCtx()
  return true
end

--- Remap existing sketch PT items from one CHR layout mode to another (same logical tiles).
function M.relayoutSketchOwnedPatternTableItems(ptWin, fromMode, toMode)
  local layer = ptWin and ptWin.layers and ptWin.layers[1]
  if not layer then
    return false
  end
  fromMode = fromMode or "8x8"
  toMode = toMode or layer.mode or "8x8"
  local byLogical = {}
  for pos = 0, M.PT_SLOT_COUNT - 1 do
    local logicalIndex = BankViewController.chrOrderingIndexForGridPos(fromMode, pos)
    byLogical[logicalIndex] = layer.items and layer.items[pos + 1]
  end
  layer.mode = toMode
  return placeLogicalTilesOnPatternTable(ptWin, byLogical)
end

--- Snapshot scratch tile pixels keyed by logical index (0-based + 1 for Lua array).
function M.snapshotPatternTableItemPixels(ptWin)
  local layer = ptWin and ptWin.layers and ptWin.layers[1]
  if not layer then
    return nil
  end
  local mode = layer.mode or "8x8"
  local out = {}
  for pos = 0, M.PT_SLOT_COUNT - 1 do
    local logicalIndex = BankViewController.chrOrderingIndexForGridPos(mode, pos)
    local item = layer.items and layer.items[pos + 1]
    if item and type(item.pixels) == "table" then
      out[logicalIndex + 1] = copyPixels(item.pixels)
    else
      out[logicalIndex + 1] = nil
    end
  end
  return out
end

function M.restorePatternTableItemPixels(ptWin, pixelsByLogical)
  if not (ptWin and type(pixelsByLogical) == "table") then
    return false
  end
  local layer = ptWin.layers and ptWin.layers[1]
  if not layer then
    return false
  end
  local logicalTiles = {}
  for logical = 0, M.PT_SLOT_COUNT - 1 do
    local pixels = pixelsByLogical[logical + 1]
    if type(pixels) == "table" then
      logicalTiles[logical] = M.makeScratchTileFromPixels(pixels)
    else
      logicalTiles[logical] = nil
    end
  end
  return placeLogicalTilesOnPatternTable(ptWin, logicalTiles)
end

--- Pack a PixelCanvas into unique pool refs + 32x30 nametable indices.
--- @return pack table `{ tilesPool, nametableBytes, uniqueCount }` or nil, err
function M.packFromCanvas(canvas, tolerance)
  if not (canvas and type(canvas.extractTilePixels) == "function") then
    return nil, "no_canvas"
  end
  local width = tonumber(canvas.width) or 0
  local height = tonumber(canvas.height) or 0
  if width < M.GRID_COLS * M.CELL or height < M.GRID_ROWS * M.CELL then
    return nil, "canvas_too_small"
  end

  tolerance = clampTolerance(tolerance)
  local tilesPool = {}
  local uniquePatterns = {}
  local nametableBytes = {}

  for row = 0, M.GRID_ROWS - 1 do
    for col = 0, M.GRID_COLS - 1 do
      local ox = col * M.CELL
      local oy = row * M.CELL
      local pixels = canvas:extractTilePixels(ox, oy, M.CELL)
      local matchIndex = nil
      for i = 1, #uniquePatterns do
        if pixelDiffCount(pixels, uniquePatterns[i], tolerance) <= tolerance then
          matchIndex = i
          break
        end
      end

      if not matchIndex then
        if #tilesPool >= M.MAX_UNIQUE then
          return nil, "too_many_unique"
        end
        tilesPool[#tilesPool + 1] = { x = ox, y = oy }
        uniquePatterns[#uniquePatterns + 1] = pixels
        matchIndex = #tilesPool
      end

      -- 0-based pool index stored in nametableBytes (NES tile index style).
      nametableBytes[#nametableBytes + 1] = matchIndex - 1
    end
  end

  return {
    tilesPool = tilesPool,
    nametableBytes = nametableBytes,
    uniqueCount = #tilesPool,
    tolerance = tolerance,
  }
end

function M.applyPackToWindow(win, pack)
  if not (win and pack) then
    return false
  end
  win.tilesPool = pack.tilesPool or {}
  win.nametableBytes = pack.nametableBytes
  M.invalidateReflectDisplay(win)
  return true
end

function M.hasPackData(win)
  return type(win) == "table"
    and type(win.tilesPool) == "table"
    and #win.tilesPool > 0
    and type(win.nametableBytes) == "table"
    and #win.nametableBytes == (M.GRID_COLS * M.GRID_ROWS)
end

function M.invalidateReflectDisplay(win)
  if not win then
    return
  end
  win._reflectDisplayDirty = true
end

--- Build/update a display-only canvas composed from nametableBytes + pool samples of the paint buffer.
--- Does not mutate the paint PixelCanvas.
function M.getReflectDisplayCanvas(sketchWin)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return nil
  end
  if not M.hasPackData(sketchWin) then
    return nil
  end
  local paint = resolveCanvas(sketchWin)
  if not paint then
    return nil
  end

  local display = sketchWin._reflectDisplayCanvas
  if not display then
    display = PixelCanvas.new(M.GRID_COLS * M.CELL, M.GRID_ROWS * M.CELL, paint.fillValue or 0)
    sketchWin._reflectDisplayCanvas = display
    sketchWin._reflectDisplayDirty = true
  end

  if sketchWin._reflectDisplayDirty ~= true then
    return display
  end

  local pool = sketchWin.tilesPool
  local nt = sketchWin.nametableBytes
  local fallback = pool[1]
  for row = 0, M.GRID_ROWS - 1 do
    for col = 0, M.GRID_COLS - 1 do
      local ntIndex = row * M.GRID_COLS + col + 1
      local poolIndex = math.floor(tonumber(nt[ntIndex]) or 0)
      local entry = pool[poolIndex + 1] or fallback
      local ox = entry and math.floor(tonumber(entry.x) or 0) or 0
      local oy = entry and math.floor(tonumber(entry.y) or 0) or 0
      local pixels = paint:extractTilePixels(ox, oy, M.CELL)
      display:loadTilePixels(col * M.CELL, row * M.CELL, pixels, M.CELL)
    end
  end
  sketchWin._reflectDisplayDirty = false
  return display
end

function M.setReflectPatternTable(sketchWin, enabled)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return false
  end
  enabled = enabled == true
  if enabled and not M.hasPackData(sketchWin) then
    return false, "no_pack"
  end
  sketchWin.reflectPatternTable = enabled
  if enabled then
    M.invalidateReflectDisplay(sketchWin)
  end
  return true
end

function M.toggleReflectPatternTable(sketchWin)
  local nextOn = not (sketchWin and sketchWin.reflectPatternTable == true)
  local ok, err = M.setReflectPatternTable(sketchWin, nextOn)
  if not ok then
    return false, err
  end
  return true, nextOn
end

function M.resolveLinkedPatternTable(sketchWin, wm)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return nil
  end
  local id = sketchWin.linkedPatternTableWindowId
  if type(id) ~= "string" or id == "" then
    return nil
  end
  local pt = findWindowById(wm, id)
  if pt and WindowCaps.isPatternTable(pt) and not pt._closed then
    return pt
  end
  return nil
end

function M.isSketchOwnedPatternTable(ptWin, wm)
  if not WindowCaps.isPatternTable(ptWin) then
    return false
  end
  if type(ptWin.linkedSketchCanvasWindowId) == "string" and ptWin.linkedSketchCanvasWindowId ~= "" then
    return true
  end
  if not (wm and wm.getWindows) then
    return false
  end
  local ptId = ptWin._id
  if type(ptId) ~= "string" or ptId == "" then
    return false
  end
  for _, w in ipairs(wm:getWindows()) do
    if WindowCaps.isSketchCanvas(w)
      and not w._closed
      and w.linkedPatternTableWindowId == ptId
    then
      return true
    end
  end
  return false
end

--- Rebuild reverse marks on pattern tables from sketch window links.
function M.resolveSketchOwnedPatternTables(wm)
  if not (wm and wm.getWindows) then
    return
  end
  for _, w in ipairs(wm:getWindows()) do
    if WindowCaps.isPatternTable(w) then
      w.linkedSketchCanvasWindowId = nil
    end
  end
  for _, w in ipairs(wm:getWindows()) do
    if WindowCaps.isSketchCanvas(w) and not w._closed then
      local pt = M.resolveLinkedPatternTable(w, wm)
      if pt then
        pt.linkedSketchCanvasWindowId = w._id
      end
    end
  end
end

local function clearReverseLinkIfOwned(ptWin, sketchWin)
  if ptWin
    and type(ptWin.linkedSketchCanvasWindowId) == "string"
    and ptWin.linkedSketchCanvasWindowId ~= ""
    and (not sketchWin or ptWin.linkedSketchCanvasWindowId == sketchWin._id)
  then
    ptWin.linkedSketchCanvasWindowId = nil
  end
end

--- Link sketch -> pattern table (window-level). Marks PT as sketch-owned.
function M.linkSketchToPatternTable(sketchWin, ptWin, wm)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return false, "not_sketch_canvas"
  end
  if not WindowCaps.isPatternTable(ptWin) then
    return false, "not_pattern_table"
  end
  if type(ptWin._id) ~= "string" or ptWin._id == "" then
    return false, "pattern_table_missing_id"
  end

  -- Detach previous link on this sketch.
  local prevPt = M.resolveLinkedPatternTable(sketchWin, wm)
  if prevPt and prevPt ~= ptWin then
    clearReverseLinkIfOwned(prevPt, sketchWin)
  end

  -- If another sketch owns this PT, detach that sketch.
  if type(ptWin.linkedSketchCanvasWindowId) == "string"
    and ptWin.linkedSketchCanvasWindowId ~= ""
    and ptWin.linkedSketchCanvasWindowId ~= sketchWin._id
  then
    local other = findWindowById(wm, ptWin.linkedSketchCanvasWindowId)
    if WindowCaps.isSketchCanvas(other) then
      other.linkedPatternTableWindowId = nil
    end
  end

  sketchWin.linkedPatternTableWindowId = ptWin._id
  ptWin.linkedSketchCanvasWindowId = sketchWin._id

  local layer = ptWin.layers and ptWin.layers[1]
  if layer then
    layer.patternTable = { ranges = {} }
  end

  if type(sketchWin.tilesPool) == "table" and #sketchWin.tilesPool > 0 then
    return M.applyPackToLinkedPatternTable(sketchWin, wm)
  end

  clearPatternTableScratchItems(ptWin)
  return true
end

function M.unlinkSketchPatternTable(sketchWin, wm)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return false, "not_sketch_canvas"
  end
  local pt = M.resolveLinkedPatternTable(sketchWin, wm)
  sketchWin.linkedPatternTableWindowId = nil
  if pt then
    clearReverseLinkIfOwned(pt, sketchWin)
  end
  return true
end

local function clampPaddingIndex(sketchWin, uniqueCount)
  local pad = math.floor(tonumber(sketchWin and sketchWin.paddingTileIndex) or 0)
  if uniqueCount <= 0 then
    return 0
  end
  if pad < 0 then
    pad = 0
  elseif pad >= uniqueCount then
    pad = uniqueCount - 1
  end
  return pad
end

--- Fill linked PT with 256 scratch tiles sampled from the sketch canvas at pool coords.
function M.applyPackToLinkedPatternTable(sketchWin, wm)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return false, "not_sketch_canvas"
  end
  local ptWin = M.resolveLinkedPatternTable(sketchWin, wm)
  if not ptWin then
    return false, "no_linked_pattern_table"
  end
  local canvas = resolveCanvas(sketchWin)
  if not canvas then
    return false, "no_canvas"
  end
  local pool = sketchWin.tilesPool
  if type(pool) ~= "table" or #pool == 0 then
    return false, "empty_tiles_pool"
  end

  local uniqueCount = #pool
  local padIndex = clampPaddingIndex(sketchWin, uniqueCount)
  local padEntry = pool[padIndex + 1]
  local padPixels = canvas:extractTilePixels(padEntry.x, padEntry.y, M.CELL)

  -- Build unique scratch tiles once; padding slots share the pad tile ref.
  local uniqueTiles = {}
  for i = 1, uniqueCount do
    local entry = pool[i]
    local pixels = canvas:extractTilePixels(entry.x, entry.y, M.CELL)
    uniqueTiles[i] = M.makeScratchTileFromPixels(pixels)
  end
  local padTile = uniqueTiles[padIndex + 1] or M.makeScratchTileFromPixels(padPixels)

  local layer = ptWin.layers and ptWin.layers[1]
  if not layer then
    return false, "pattern_table_missing_layer"
  end

  -- Logical 0..255 catalog; grid placement follows layer.mode (8x8 / 8x16 pairs).
  local logicalTiles = {}
  for slot = 0, M.PT_SLOT_COUNT - 1 do
    if slot < uniqueCount then
      logicalTiles[slot] = uniqueTiles[slot + 1]
    else
      logicalTiles[slot] = padTile
    end
  end
  placeLogicalTilesOnPatternTable(ptWin, logicalTiles)

  ptWin.linkedSketchCanvasWindowId = sketchWin._id
  return true, {
    uniqueCount = uniqueCount,
    paddingTileIndex = padIndex,
    patternTableWindowId = ptWin._id,
  }
end

function M.reapplyAllSketchLinkedPatternTables(wm)
  if not (wm and wm.getWindows) then
    return
  end
  for _, w in ipairs(wm:getWindows()) do
    if WindowCaps.isSketchCanvas(w)
      and not w._closed
      and type(w.tilesPool) == "table"
      and #w.tilesPool > 0
      and type(w.linkedPatternTableWindowId) == "string"
      and w.linkedPatternTableWindowId ~= ""
    then
      M.applyPackToLinkedPatternTable(w, wm)
    end
  end
end

--- Pack the sketch window paint buffer into tilesPool + nametableBytes.
--- @return ok, packOrErr
function M.generate(win)
  if not WindowCaps.isSketchCanvas(win) then
    return false, "not_sketch_canvas"
  end
  local canvas = resolveCanvas(win)
  if not canvas then
    return false, "no_canvas"
  end
  local pack, err = M.packFromCanvas(canvas, win.tolerance)
  if not pack then
    return false, err or "pack_failed"
  end
  M.applyPackToWindow(win, pack)
  return true, pack
end

--- Pack, then apply to linked pattern table when linked.
function M.generateAndApply(win, wm)
  local ok, packOrErr = M.generate(win)
  if not ok then
    return false, packOrErr
  end
  if type(win.linkedPatternTableWindowId) == "string" and win.linkedPatternTableWindowId ~= "" then
    local applyOk, applyInfoOrErr = M.applyPackToLinkedPatternTable(win, wm)
    if not applyOk then
      return false, applyInfoOrErr or "apply_failed"
    end
    packOrErr.appliedToPatternTable = true
    packOrErr.paddingTileIndex = applyInfoOrErr and applyInfoOrErr.paddingTileIndex
  end
  return true, packOrErr
end

function M.formatGenerateStatus(ok, packOrErr)
  if ok and type(packOrErr) == "table" then
    local n = tonumber(packOrErr.uniqueCount) or 0
    local tol = tonumber(packOrErr.tolerance) or 0
    local base = string.format(
      "Sketch generate: %d unique pattern%s (tolerance %d)",
      n,
      n == 1 and "" or "s",
      tol
    )
    if packOrErr.appliedToPatternTable then
      return base .. " -> pattern table"
    end
    return base
  end
  local err = tostring(packOrErr or "pack_failed")
  if err == "too_many_unique" then
    return "Sketch generate failed: more than 256 unique patterns (raise tolerance)"
  end
  if err == "no_canvas" then
    return "Sketch generate failed: no canvas"
  end
  if err == "canvas_too_small" then
    return "Sketch generate failed: canvas too small"
  end
  if err == "no_linked_pattern_table" then
    return "Sketch generate failed: linked pattern table missing"
  end
  return "Sketch generate failed: " .. err
end

function M.snapshotPackFields(win)
  local pool = {}
  for i, entry in ipairs((win and win.tilesPool) or {}) do
    pool[i] = {
      x = math.floor(tonumber(entry.x) or 0),
      y = math.floor(tonumber(entry.y) or 0),
    }
  end
  local nt = nil
  if type(win and win.nametableBytes) == "table" then
    nt = {}
    for i, b in ipairs(win.nametableBytes) do
      nt[i] = math.floor(tonumber(b) or 0)
    end
  end
  return {
    tilesPool = pool,
    nametableBytes = nt,
  }
end

function M.restorePackFields(win, snap)
  if not (win and snap) then
    return false
  end
  win.tilesPool = {}
  for i, entry in ipairs(snap.tilesPool or {}) do
    win.tilesPool[i] = {
      x = math.floor(tonumber(entry.x) or 0),
      y = math.floor(tonumber(entry.y) or 0),
    }
  end
  if type(snap.nametableBytes) == "table" then
    win.nametableBytes = {}
    for i, b in ipairs(snap.nametableBytes) do
      win.nametableBytes[i] = math.floor(tonumber(b) or 0)
    end
  else
    win.nametableBytes = nil
  end
  M.invalidateReflectDisplay(win)
  if win.reflectPatternTable and not M.hasPackData(win) then
    win.reflectPatternTable = false
  end
  return true
end

return M
