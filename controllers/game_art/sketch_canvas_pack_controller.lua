-- sketch_canvas_pack_controller.lua
-- Pack a sketch canvas into tilesPool ({x,y} refs) + nametableBytes, and apply to a linked PT.

local Tile = require("ui.windows_system.tile_item")
local PixelCanvas = require("ui.windows_system.pixel_canvas")
local BankViewController = require("controllers.chr.bank_view_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local TileInvalidationIndex = require("controllers.app.tile_invalidation_index")
local ImageImportController = require("controllers.rom.image_import_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")

local M = {}

M.MAX_UNIQUE = 256
M.PT_SLOT_COUNT = 256
M.GRID_COLS = 32
M.GRID_ROWS = 30
M.CELL = 8
M.MAX_TOLERANCE = 32
M.SKETCH_OWNED_PATTERN_TABLE_MSG =
  "Pattern table is linked to a sketch canvas (CHR drops blocked)"
M.PNG_IMPORT_TOLERANCE = 0
M.PNG_IMPORT_WIDTH = M.GRID_COLS * M.CELL
M.PNG_IMPORT_HEIGHT = M.GRID_ROWS * M.CELL
M.PNG_DROP_USE_SKETCH_MSG =
  "Drop PNG on a Sketch canvas to pack into its linked Pattern table"
M.PNG_IMPORT_NEEDS_CONFIRM = "needs_confirm"

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

--- Count pixels that differ from a constant shade (0-3). Early-out past threshold.
local function solidDiffCount(pixels, shade, threshold)
  threshold = threshold or 0
  shade = math.floor(tonumber(shade) or 0)
  local differences = 0
  for i = 1, 64 do
    if pixels[i] ~= shade then
      differences = differences + 1
      if differences > threshold then
        return differences
      end
    end
  end
  return differences
end

local function makeSolidPattern(shade)
  shade = math.floor(tonumber(shade) or 0)
  if shade < 0 then
    shade = 0
  elseif shade > 3 then
    shade = 3
  end
  local pixels = {}
  for i = 1, 64 do
    pixels[i] = shade
  end
  return pixels
end

--- If a tile is within tolerance of a flat shade, collapse it to that shade.
--- Prefer the closest shade; ties keep the lower shade index.
local function canonicalSolidShade(pixels, tolerance)
  local bestShade = nil
  local bestDiff = nil
  for shade = 0, 3 do
    local diff = solidDiffCount(pixels, shade, tolerance)
    if diff <= tolerance and (bestDiff == nil or diff < bestDiff) then
      bestShade = shade
      bestDiff = diff
    end
  end
  return bestShade
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

--- Serializable pool entry ({x,y} plus optional solidShade metadata).
function M.copyPoolEntry(pe)
  if type(pe) ~= "table" then
    return nil
  end
  local x = tonumber(pe.x)
  local y = tonumber(pe.y)
  if not (x and y) then
    return nil
  end
  local out = {
    x = math.floor(x),
    y = math.floor(y),
  }
  local shade = tonumber(pe.solidShade)
  if shade and shade >= 0 and shade <= 3 then
    out.solidShade = math.floor(shade)
  end
  if pe.exactSolid == true then
    out.exactSolid = true
  end
  return out
end

-- Compact project form (same spirit as PPU-frame tileSwaps strings):
--   { "x,y|x,y,s|...", "..." }  -- chunks ~100 chars, split on |
-- where s is solidShade 0..3 and optional trailing e means exactSolid.
local function encodePoolEntryToken(pe)
  local copied = M.copyPoolEntry(pe)
  if not copied then
    return nil
  end
  if type(copied.solidShade) == "number" then
    if copied.exactSolid == true then
      return string.format("%d,%d,%de", copied.x, copied.y, copied.solidShade)
    end
    return string.format("%d,%d,%d", copied.x, copied.y, copied.solidShade)
  end
  return string.format("%d,%d", copied.x, copied.y)
end

local function decodePoolEntryToken(token)
  if type(token) ~= "string" or token == "" then
    return nil
  end
  local x, y, shade, exact = token:match("^(%-?%d+),(%-?%d+),([0-3])(e?)$")
  if x then
    local out = {
      x = math.floor(tonumber(x)),
      y = math.floor(tonumber(y)),
      solidShade = math.floor(tonumber(shade)),
    }
    if exact == "e" then
      out.exactSolid = true
    end
    return out
  end
  x, y = token:match("^(%-?%d+),(%-?%d+)$")
  if x then
    return {
      x = math.floor(tonumber(x)),
      y = math.floor(tonumber(y)),
    }
  end
  return nil
end

--- Encode tilesPool for project Lua as a list of pipe-separated strings
--- (~100 chars each; never splits mid-token). Short pools are a one-element list.
--- Empty pool is {}.
--- @return table array of strings
function M.encodeTilesPool(pool)
  local parts = {}
  if type(pool) == "table" then
    for i = 1, math.min(256, #pool) do
      local token = encodePoolEntryToken(pool[i])
      if token then
        parts[#parts + 1] = token
      end
    end
  end
  if #parts == 0 then
    return {}
  end

  local maxChunk = 100
  local chunks = {}
  local current = parts[1]
  for i = 2, #parts do
    local token = parts[i]
    local withSep = current .. "|" .. token
    if #withSep <= maxChunk then
      current = withSep
    else
      chunks[#chunks + 1] = current
      current = token
    end
  end
  chunks[#chunks + 1] = current
  return chunks
end

local function decodeTilesPoolFromString(full, out)
  if type(full) ~= "string" or full == "" then
    return out
  end
  for token in full:gmatch("([^|]+)") do
    local entry = decodePoolEntryToken(token)
    if entry then
      out[#out + 1] = entry
      if #out >= 256 then
        break
      end
    end
  end
  return out
end

--- Decode tilesPool from project form to entry tables.
--- Accepts: chunked string list, single pipe string, or legacy entry-table.
--- @return table
function M.decodeTilesPool(encoded)
  local out = {}
  if type(encoded) == "string" then
    return decodeTilesPoolFromString(encoded, out)
  end
  if type(encoded) ~= "table" then
    return out
  end

  -- Chunked project form: { "0,0|8,8", "16,16|..." }
  if type(encoded[1]) == "string" then
    local parts = {}
    for i = 1, #encoded do
      if type(encoded[i]) == "string" then
        parts[#parts + 1] = encoded[i]
      end
    end
    return decodeTilesPoolFromString(table.concat(parts, "|"), out)
  end

  -- Legacy project form: array of {x,y[,solidShade][,exactSolid]}
  for i = 1, math.min(256, #encoded) do
    local copied = M.copyPoolEntry(encoded[i])
    if copied then
      out[#out + 1] = copied
    end
  end
  return out
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

--- Pixels for a pool entry: canonical solid when packed as a flat shade, else canvas sample.
function M.pixelsForPoolEntry(canvas, entry)
  if type(entry) ~= "table" then
    return nil
  end
  local shade = entry.solidShade
  if type(shade) == "number" and shade >= 0 and shade <= 3 then
    -- Paint under the sample may have been edited (PT scratch / undo). If it no
    -- longer matches the packed solid, fall back to the live canvas sample.
    if canvas and type(canvas.extractTilePixels) == "function" then
      local sampled = canvas:extractTilePixels(
        math.floor(tonumber(entry.x) or 0),
        math.floor(tonumber(entry.y) or 0),
        M.CELL
      )
      if sampled and solidDiffCount(sampled, shade, 0) > 0 then
        entry.solidShade = nil
        entry.exactSolid = nil
        return sampled
      end
    end
    return makeSolidPattern(shade)
  end
  if not (canvas and type(canvas.extractTilePixels) == "function") then
    return nil
  end
  return canvas:extractTilePixels(entry.x, entry.y, M.CELL)
end

--- Remember which sketch paint cell this scratch tile samples (for undo/redo sync).
function M.stampScratchTileSketchSource(tile, sketchWin, poolX, poolY)
  if not tile then
    return
  end
  tile._sketchCanvasWindowId = sketchWin and sketchWin._id or nil
  tile._sketchPoolX = math.floor(tonumber(poolX) or 0)
  tile._sketchPoolY = math.floor(tonumber(poolY) or 0)
end

--- Re-attach pool {x,y} stamps on all scratch tiles of a sketch-owned PT.
function M.restampPatternTableScratchSources(ptWin, wm)
  local sketch = M.resolveSketchForOwnedPatternTable(ptWin, wm)
  if not sketch or not M.hasPackData(sketch) then
    return false
  end
  local layer = ptWin.layers and ptWin.layers[1]
  if not layer or type(layer.items) ~= "table" then
    return false
  end
  local mode = layer.mode or "8x8"
  local cols = math.max(1, math.floor(tonumber(ptWin.cols) or 16))
  local stamped = {}
  for pos = 0, M.PT_SLOT_COUNT - 1 do
    local item = layer.items[pos + 1]
    if item and not stamped[item] then
      local row = math.floor(pos / cols)
      local col = pos - row * cols
      local logical = BankViewController.chrOrderingIndexForGridPos(mode, pos)
      local entry = M.poolEntryForLogicalSlot(sketch, logical)
      if entry then
        M.stampScratchTileSketchSource(item, sketch, entry.x, entry.y)
        stamped[item] = true
      end
    end
  end
  return true
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

function M.restorePatternTableItemPixels(ptWin, pixelsByLogical, wm)
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
  local ok = placeLogicalTilesOnPatternTable(ptWin, logicalTiles)
  if ok then
    M.restampPatternTableScratchSources(ptWin, wm)
  end
  return ok
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
  -- One pool slot per flat shade (0-3) when any tile collapses to that solid.
  local solidPoolIndex = { nil, nil, nil, nil } -- 1-based keyed by shade+1
  local nametableBytes = {}

  for row = 0, M.GRID_ROWS - 1 do
    for col = 0, M.GRID_COLS - 1 do
      local ox = col * M.CELL
      local oy = row * M.CELL
      local pixels = canvas:extractTilePixels(ox, oy, M.CELL)
      local matchIndex = nil

      -- Near-flats within tolerance collapse to one canonical solid per shade.
      -- Avoids several "empty looking" uniques that greedy pairwise match misses.
      -- Exception: shade 0 (transparent) only collapses when the tile is an *exact*
      -- blank. Near-empty edge tiles (skirts, hair tips) must stay unique or tile
      -- mode / Gallery ROM punch holes where freehand paint still has pixels.
      local solidShade = canonicalSolidShade(pixels, tolerance)
      if solidShade == 0 and solidDiffCount(pixels, 0, 0) > 0 then
        solidShade = nil
      end
      if solidShade ~= nil then
        local slot = solidShade + 1
        matchIndex = solidPoolIndex[slot]
        local isExactSolid = solidDiffCount(pixels, solidShade, 0) == 0
        if not matchIndex then
          if #tilesPool >= M.MAX_UNIQUE then
            return nil, "too_many_unique"
          end
          tilesPool[#tilesPool + 1] = {
            x = ox,
            y = oy,
            solidShade = solidShade,
            exactSolid = isExactSolid,
          }
          uniquePatterns[#uniquePatterns + 1] = makeSolidPattern(solidShade)
          matchIndex = #tilesPool
          solidPoolIndex[slot] = matchIndex
        else
          -- Upgrade sample point once from a near-flat to a true flat.
          local entry = tilesPool[matchIndex]
          if entry and entry.solidShade == solidShade and not entry.exactSolid and isExactSolid then
            entry.x = ox
            entry.y = oy
            entry.exactSolid = true
          end
        end
      else
        for i = 1, #uniquePatterns do
          local entry = tilesPool[i]
          -- Never absorb freehand near-detail into a canonical solid slot via greedy.
          if entry and type(entry.solidShade) == "number" then
            if pixelDiffCount(pixels, uniquePatterns[i], 0) == 0 then
              matchIndex = i
              break
            end
          elseif pixelDiffCount(pixels, uniquePatterns[i], tolerance) <= tolerance then
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
  M.clearReflectLayoutDirty(win)
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

--- True when the app global mode is tile (sketch nametable / reflect editing).
function M.isSketchGlobalTileMode()
  local ctx = rawget(_G, "ctx")
  local mode = ctx and ctx.getMode and ctx.getMode() or nil
  return mode == "tile"
end

--- Drop packed nametable/catalog state (paint canvas is unchanged unless clearPaint).
function M.clearPackData(win, opts)
  opts = opts or {}
  if not WindowCaps.isSketchCanvas(win) then
    return false
  end
  win.tilesPool = {}
  win.nametableBytes = nil
  win.reflectPatternTable = false
  win._reflectDisplayCanvas = nil
  M.clearReflectLayoutDirty(win)
  M.invalidateReflectDisplay(win)
  M.markGenerateDirty(win)
  if opts.clearPaint == true then
    local canvas = resolveCanvas(win)
    if canvas and canvas.clear then
      canvas:clear(0)
    end
    local layer = win.layers and win.layers[win.activeLayer or 1]
    if layer then
      layer.multiTileSelection = nil
    end
    if type(win.clearSelection) == "function" then
      win:clearSelection()
    elseif win.selectedCol ~= nil or win.selectedRow ~= nil then
      win.selectedCol = nil
      win.selectedRow = nil
    end
  end
  if win.specializedToolbar and win.specializedToolbar.updateIcons then
    win.specializedToolbar:updateIcons()
  end
  return true
end

function M.invalidateReflectDisplay(win)
  if not win then
    return
  end
  win._reflectDisplayDirty = true
end

--- Nametable tile edits (swap/drag/remove) while in tile mode; bake into paint on leave.
function M.markReflectLayoutDirty(win)
  if WindowCaps.isSketchCanvas(win) then
    win._reflectLayoutDirty = true
  end
end

function M.clearReflectLayoutDirty(win)
  if win then
    win._reflectLayoutDirty = false
  end
end

function M.isReflectLayoutDirty(win)
  return WindowCaps.isSketchCanvas(win) and win._reflectLayoutDirty == true
end

function M.markGenerateDirty(win)
  if WindowCaps.isSketchCanvas(win) then
    win._generateDirty = true
    -- Freeze the last packed compose; paint edits stay Edit-mode only until Generate.
    if win._reflectDisplayCanvas then
      win._reflectDisplayDirty = false
    end
  end
end

function M.clearGenerateDirty(win)
  if win then
    win._generateDirty = false
  end
end

function M.isGenerateDirty(win)
  return WindowCaps.isSketchCanvas(win) and win._generateDirty == true
end

--- If paint at any nametable cell disagrees with the pack sample for that cell,
--- mark Generate dirty so the toolbar prompts a re-pack.
--- Skips solidShade entries (intentional NES collapse vs freehand detail).
function M.markGenerateDirtyIfPackDisagreesWithPaint(win)
  if not M.hasPackData(win) then
    return false
  end
  if M.isGenerateDirty(win) then
    return true
  end
  local paint = resolveCanvas(win)
  if not paint then
    return false
  end
  local pool = win.tilesPool
  local nt = win.nametableBytes
  for row = 0, M.GRID_ROWS - 1 do
    for col = 0, M.GRID_COLS - 1 do
      local ntIndex = row * M.GRID_COLS + col + 1
      local poolIndex = math.floor(tonumber(nt[ntIndex]) or 0)
      local entry = pool[poolIndex + 1]
      if entry and type(entry.solidShade) ~= "number" then
        local expected = M.pixelsForPoolEntry(paint, entry)
        local actual = paint:extractTilePixels(col * M.CELL, row * M.CELL, M.CELL)
        if expected and actual and pixelDiffCount(actual, expected, 0) > 0 then
          M.markGenerateDirty(win)
          return true
        end
      end
    end
  end
  return false
end

--- After project load: re-arm Generate dirty when pack samples no longer match paint.
function M.reconcileLoadedSketchPacks(wm)
  if not wm then
    return 0
  end
  local windows = wm.getWindows and wm:getWindows() or wm.windows or wm._windows or {}
  local count = 0
  for _, win in ipairs(windows) do
    if WindowCaps.isSketchCanvas(win) and not win._closed then
      if M.markGenerateDirtyIfPackDisagreesWithPaint(win) then
        count = count + 1
      end
    end
  end
  return count
end

--- Build/update a display-only canvas composed from nametableBytes + pool samples of the paint buffer.
--- Does not mutate the paint PixelCanvas.
--- When Generate is dirty, samples may lag paint; tile mode still shows this last-pack compose
--- until Generate is applied again.
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
      local pixels = M.pixelsForPoolEntry(paint, entry)
      if not pixels then
        local ox = entry and math.floor(tonumber(entry.x) or 0) or 0
        local oy = entry and math.floor(tonumber(entry.y) or 0) or 0
        pixels = paint:extractTilePixels(ox, oy, M.CELL)
      end
      display:loadTilePixels(col * M.CELL, row * M.CELL, pixels, M.CELL)
    end
  end
  sketchWin._reflectDisplayDirty = false
  return display
end

--- Stamp the packed nametable composition into the paint buffer and remap pool
--- sample points to first NT occurrences so edit mode matches tile-mode view.
--- Only runs when nametable layout was edited (see markReflectLayoutDirty); otherwise
--- leaving tile mode must not wipe freehand paint that is ahead of the pack.
function M.bakeReflectIntoPaint(sketchWin)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return false
  end
  if not M.hasPackData(sketchWin) then
    return false
  end
  -- Never bake a stale pack over newer freehand/selection edits.
  if M.isGenerateDirty(sketchWin) then
    return false
  end
  if not M.isReflectLayoutDirty(sketchWin) then
    return false
  end
  local paint = resolveCanvas(sketchWin)
  if not paint then
    return false
  end
  sketchWin._reflectDisplayDirty = true
  local display = M.getReflectDisplayCanvas(sketchWin)
  if not display then
    return false
  end

  local w = math.min(paint.width or 0, display.width or 0)
  local h = math.min(paint.height or 0, display.height or 0)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      paint:edit(x, y, display:getPixel(x, y) or 0)
    end
  end

  local pool = sketchWin.tilesPool
  local nt = sketchWin.nametableBytes
  local seen = {}
  for row = 0, M.GRID_ROWS - 1 do
    for col = 0, M.GRID_COLS - 1 do
      local ntIndex = row * M.GRID_COLS + col + 1
      local poolIndex = math.floor(tonumber(nt[ntIndex]) or 0)
      if not seen[poolIndex] then
        seen[poolIndex] = true
        local entry = pool[poolIndex + 1]
        if entry then
          entry.x = col * M.CELL
          entry.y = row * M.CELL
        end
      end
    end
  end

  M.invalidateReflectDisplay(sketchWin)
  M.clearReflectLayoutDirty(sketchWin)
  return true
end

--- Bake packed sketches whose nametable layout changed while in tile mode.
function M.bakeAllReflectIntoPaint(wm)
  if not wm then
    return 0
  end
  local windows = wm.getWindows and wm:getWindows() or wm.windows or wm._windows or {}
  local count = 0
  for _, win in ipairs(windows) do
    if WindowCaps.isSketchCanvas(win)
      and not win._closed
      and M.hasPackData(win)
      and M.isReflectLayoutDirty(win)
    then
      if M.bakeReflectIntoPaint(win) then
        count = count + 1
      end
    end
  end
  return count
end

function M.setReflectPatternTable(sketchWin, enabled)
  -- Legacy API: mirror view is now driven by global tile/edit mode.
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

--- Resolve the sketch canvas that owns a sketch-linked pattern table.
function M.resolveSketchForOwnedPatternTable(ptWin, wm)
  if not WindowCaps.isPatternTable(ptWin) then
    return nil
  end
  local id = ptWin.linkedSketchCanvasWindowId
  if type(id) == "string" and id ~= "" then
    local sketch = findWindowById(wm, id)
    if WindowCaps.isSketchCanvas(sketch) and not sketch._closed then
      return sketch
    end
  end
  if not (wm and wm.getWindows) then
    return nil
  end
  local ptId = ptWin._id
  if type(ptId) ~= "string" or ptId == "" then
    return nil
  end
  for _, w in ipairs(wm:getWindows()) do
    if WindowCaps.isSketchCanvas(w)
      and not w._closed
      and w.linkedPatternTableWindowId == ptId
    then
      return w
    end
  end
  return nil
end

function M.logicalIndexForPatternTableCell(ptWin, col, row)
  if not (ptWin and type(col) == "number" and type(row) == "number") then
    return nil
  end
  local cols = math.max(1, math.floor(tonumber(ptWin.cols) or 16))
  local gridPos = math.floor(row) * cols + math.floor(col)
  local layer = ptWin.layers and ptWin.layers[1]
  local mode = (layer and layer.mode) or "8x8"
  return BankViewController.chrOrderingIndexForGridPos(mode, gridPos)
end

--- Pool entry for a logical PT slot (0..255), using paddingTileIndex past uniqueCount.
function M.poolEntryForLogicalSlot(sketchWin, logicalIndex)
  if not (M.hasPackData(sketchWin) and type(logicalIndex) == "number") then
    return nil, nil
  end
  local pool = sketchWin.tilesPool
  local uniqueCount = #pool
  local slot = math.floor(logicalIndex)
  if slot < 0 or slot >= M.PT_SLOT_COUNT then
    return nil, nil
  end
  local poolIndex
  if slot < uniqueCount then
    poolIndex = slot
  else
    -- Mirror clampPaddingIndex (defined later) so this can live near other helpers.
    local pad = math.floor(tonumber(sketchWin.paddingTileIndex) or 0)
    if pad < 0 then
      pad = 0
    elseif pad >= uniqueCount then
      pad = uniqueCount - 1
    end
    poolIndex = pad
  end
  return pool[poolIndex + 1], poolIndex
end

--- Freeze 8x8 pixels from the sketch paint canvas for a PT grid cell.
function M.extractFrozenPixelsForPatternTableCell(ptWin, col, row, wm)
  local sketch = M.resolveSketchForOwnedPatternTable(ptWin, wm)
  if not sketch then
    return nil
  end
  local canvas = resolveCanvas(sketch)
  if not canvas then
    return nil
  end
  local logical = M.logicalIndexForPatternTableCell(ptWin, col, row)
  if logical == nil then
    return nil
  end
  local entry = M.poolEntryForLogicalSlot(sketch, logical)
  if not entry then
    return nil
  end
  local pixels = M.pixelsForPoolEntry(canvas, entry)
  if not pixels then
    return nil
  end
  return copyPixels(pixels)
end

local function entryGridCoords(entry)
  if not entry then
    return nil, nil
  end
  local col = entry.col
  local row = entry.row
  if type(col) ~= "number" then
    col = entry.srcCol
  end
  if type(row) ~= "number" then
    row = entry.srcRow
  end
  if type(col) ~= "number" or type(row) ~= "number" then
    return nil, nil
  end
  return col, row
end

--- Replace entry.item with frozen { pixels } sampled from the sketch paint buffer.
function M.freezeSketchOwnedPatternTableEntries(ptWin, entries, wm)
  if not (ptWin and entries and M.isSketchOwnedPatternTable(ptWin, wm)) then
    return false
  end
  local any = false
  for _, entry in ipairs(entries) do
    local col, row = entryGridCoords(entry)
    local pixels = col and M.extractFrozenPixelsForPatternTableCell(ptWin, col, row, wm) or nil
    if pixels then
      entry.item = { pixels = pixels }
      any = true
    end
  end
  return any
end

function M.freezeSketchOwnedPatternTableClipboard(ptWin, clipboard, wm)
  if not (clipboard and clipboard.entries) then
    return false
  end
  local ok = M.freezeSketchOwnedPatternTableEntries(ptWin, clipboard.entries, wm)
  if ok then
    clipboard.chrPixelPaint = true
  end
  return ok
end

--- Freeze an in-progress tile drag from a sketch-owned pattern table.
function M.freezeSketchOwnedPatternTableDrag(ptWin, drag, wm)
  if not (drag and M.isSketchOwnedPatternTable(ptWin, wm)) then
    return false
  end

  local groupEntries = drag.tileGroup and drag.tileGroup.entries
  if groupEntries and #groupEntries > 0 then
    local ok = M.freezeSketchOwnedPatternTableEntries(ptWin, groupEntries, wm)
    if not ok then
      return false
    end
    drag.chrPixelPaint = true
    drag.tileGroup.chrPixelPaint = true
  end

  if type(drag.srcCol) == "number" and type(drag.srcRow) == "number" then
    local pixels = M.extractFrozenPixelsForPatternTableCell(ptWin, drag.srcCol, drag.srcRow, wm)
    if pixels then
      drag.item = { pixels = pixels }
      drag.chrPixelPaint = true
      return true
    end
  end

  return drag.chrPixelPaint == true
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

--- Default title for a Pattern table created for / linked from a sketch canvas.
function M.defaultLinkedPatternTableTitle(sketchWin)
  local name = tostring(sketchWin and sketchWin.title or "Sketch canvas")
  name = name:match("^%s*(.-)%s*$") or name
  if name == "" then
    name = "Sketch canvas"
  end
  return name .. " pattern table"
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

  -- Detach previous link on this sketch (drop orphan scratch tiles; CHR/sketch cannot mix).
  local prevPt = M.resolveLinkedPatternTable(sketchWin, wm)
  if prevPt and prevPt ~= ptWin then
    clearReverseLinkIfOwned(prevPt, sketchWin)
    clearPatternTableScratchItems(prevPt)
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

function M.unlinkSketchPatternTable(sketchWin, wm, opts)
  opts = opts or {}
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return false, "not_sketch_canvas"
  end
  local pt = M.resolveLinkedPatternTable(sketchWin, wm)
  if not pt then
    -- Close path marks the PT `_closed` before unlink; still clear its scratch catalog.
    local id = sketchWin.linkedPatternTableWindowId
    if type(id) == "string" and id ~= "" then
      local candidate = findWindowById(wm, id)
      if candidate and WindowCaps.isPatternTable(candidate) then
        pt = candidate
      end
    end
  end
  sketchWin.linkedPatternTableWindowId = nil
  if pt then
    clearReverseLinkIfOwned(pt, sketchWin)
    -- Empty the PT: scratch catalog cannot coexist with CHR ranges after unlink.
    clearPatternTableScratchItems(pt)
  end

  -- Tile mode shows the packed nametable; without a PT link, clear that catalog
  -- so the reflect view goes empty. Keep Edit-mode paint pixels intact.
  local clearPack = opts.clearPack
  if clearPack == nil then
    clearPack = M.isSketchGlobalTileMode()
  end
  if clearPack then
    -- Bake pending tile-mode rearranges into paint before dropping the pack.
    if M.isReflectLayoutDirty(sketchWin) and M.hasPackData(sketchWin) then
      M.bakeReflectIntoPaint(sketchWin)
    end
    local hadPack = M.hasPackData(sketchWin)
    M.clearPackData(sketchWin, { clearPaint = false })
    if opts.toast ~= false and hadPack then
      local ctx = rawget(_G, "ctx")
      local app = ctx and ctx.app
      if app and type(app.showToast) == "function" then
        app:showToast("info", "Sketch tiles cleared; Edit-mode paint kept")
      end
    end
  end
  return true
end

--- Snapshot sketch + PT state before a linked pattern table is closed/unlinked.
function M.captureSketchPatternTableCloseRestore(ptWin, wm)
  if not WindowCaps.isPatternTable(ptWin) then
    return nil
  end
  local ptId = ptWin._id
  if type(ptId) ~= "string" or ptId == "" then
    return nil
  end
  local sketch = nil
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for _, w in ipairs(windows) do
    if WindowCaps.isSketchCanvas(w) and w.linkedPatternTableWindowId == ptId then
      sketch = w
      break
    end
  end
  if not sketch and type(ptWin.linkedSketchCanvasWindowId) == "string" then
    sketch = findWindowById(wm, ptWin.linkedSketchCanvasWindowId)
    if not WindowCaps.isSketchCanvas(sketch) then
      sketch = nil
    end
  end
  if not sketch then
    return nil
  end
  return {
    sketchWin = sketch,
    linkedId = ptId,
    beforePack = M.snapshotPackFields(sketch),
    beforeItemsPixels = M.snapshotPatternTableItemPixels(ptWin),
  }
end

--- Re-link sketch and restore pack/paint/PT tiles after undoing a PT window close.
function M.restoreSketchPatternTableCloseUndo(restore, wm)
  if type(restore) ~= "table" or not restore.sketchWin then
    return false
  end
  local sketchWin = restore.sketchWin
  local ptWin = findWindowById(wm, restore.linkedId)
  if not (WindowCaps.isSketchCanvas(sketchWin) and WindowCaps.isPatternTable(ptWin)) then
    return false
  end
  M.restorePackFields(sketchWin, restore.beforePack)
  local ok = M.linkSketchToPatternTable(sketchWin, ptWin, wm)
  if type(restore.beforeItemsPixels) == "table" then
    M.restorePatternTableItemPixels(ptWin, restore.beforeItemsPixels, wm)
  elseif ok and M.hasPackData(sketchWin) then
    M.applyPackToLinkedPatternTable(sketchWin, wm)
  end
  if sketchWin.specializedToolbar and sketchWin.specializedToolbar.updateIcons then
    sketchWin.specializedToolbar:updateIcons()
  end
  if ptWin.specializedToolbar and ptWin.specializedToolbar.updateIcons then
    ptWin.specializedToolbar:updateIcons()
  end
  return true
end

--- Pattern table window closed/removed: detach owning sketch(es) and clear tile-mode packs.
function M.onPatternTableClosed(ptWin, wm)
  if not WindowCaps.isPatternTable(ptWin) or not wm then
    return
  end
  local ptId = ptWin._id
  if type(ptId) ~= "string" or ptId == "" then
    ptWin.linkedSketchCanvasWindowId = nil
    return
  end
  -- Stash for window_close undo (HeaderToolbar reads this after closeWindow returns).
  ptWin._sketchCloseUndoRestore = M.captureSketchPatternTableCloseRestore(ptWin, wm)
  local windows = wm.getWindows and wm:getWindows() or {}
  for _, w in ipairs(windows) do
    if WindowCaps.isSketchCanvas(w) and w.linkedPatternTableWindowId == ptId then
      M.unlinkSketchPatternTable(w, wm)
    end
  end
  ptWin.linkedSketchCanvasWindowId = nil
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
  local padPixels = M.pixelsForPoolEntry(canvas, padEntry)
    or canvas:extractTilePixels(padEntry.x, padEntry.y, M.CELL)

  -- Build unique scratch tiles once; padding slots share the pad tile ref.
  local uniqueTiles = {}
  for i = 1, uniqueCount do
    local entry = pool[i]
    local pixels = M.pixelsForPoolEntry(canvas, entry)
      or canvas:extractTilePixels(entry.x, entry.y, M.CELL)
    local tile = M.makeScratchTileFromPixels(pixels)
    M.stampScratchTileSketchSource(tile, sketchWin, entry.x, entry.y)
    uniqueTiles[i] = tile
  end
  local padTile = uniqueTiles[padIndex + 1]
  if not padTile then
    padTile = M.makeScratchTileFromPixels(padPixels)
    M.stampScratchTileSketchSource(padTile, sketchWin, padEntry.x, padEntry.y)
  end

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
  M.clearGenerateDirty(win)
  -- Snapshot packed preview now so later paint does not refresh tile-mode compose.
  M.getReflectDisplayCanvas(win)
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

--- @return kind ("info"|"error"), message
function M.formatGenerateToast(ok, packOrErr)
  local text = M.formatGenerateStatus(ok, packOrErr)
  if ok then
    return "info", text
  end
  return "error", text
end

function M.snapshotPackFields(win)
  local pool = {}
  for i, entry in ipairs((win and win.tilesPool) or {}) do
    local copied = M.copyPoolEntry(entry)
    if copied then
      pool[i] = copied
    else
      pool[i] = {
        x = math.floor(tonumber(entry and entry.x) or 0),
        y = math.floor(tonumber(entry and entry.y) or 0),
      }
    end
  end
  local nt = nil
  if type(win and win.nametableBytes) == "table" then
    nt = {}
    for i, b in ipairs(win.nametableBytes) do
      nt[i] = math.floor(tonumber(b) or 0)
    end
  end
  local paintPixels = nil
  local canvas = resolveCanvas(win)
  if canvas and type(canvas.pixels) == "table" and #canvas.pixels > 0 then
    paintPixels = {}
    for i = 1, #canvas.pixels do
      paintPixels[i] = math.floor(tonumber(canvas.pixels[i]) or 0)
    end
  end
  return {
    tilesPool = pool,
    nametableBytes = nt,
    paintPixels = paintPixels,
  }
end

function M.restorePackFields(win, snap)
  if not (win and snap) then
    return false
  end
  win.tilesPool = {}
  for i, entry in ipairs(snap.tilesPool or {}) do
    win.tilesPool[i] = M.copyPoolEntry(entry) or {
      x = math.floor(tonumber(entry and entry.x) or 0),
      y = math.floor(tonumber(entry and entry.y) or 0),
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
  if type(snap.paintPixels) == "table" then
    local canvas = resolveCanvas(win)
    if canvas and type(canvas.pixels) == "table" then
      local n = math.min(#canvas.pixels, #snap.paintPixels)
      for i = 1, n do
        canvas.pixels[i] = math.floor(tonumber(snap.paintPixels[i]) or 0)
      end
      canvas._imageDirty = true
    end
  end
  M.invalidateReflectDisplay(win)
  if win.reflectPatternTable and not M.hasPackData(win) then
    win.reflectPatternTable = false
  end
  if win.specializedToolbar and win.specializedToolbar.updateIcons then
    win.specializedToolbar:updateIcons()
  end
  return true
end

--- After painting a scratch tile on a sketch-owned PT: refresh the PT tile canvas and
--- write the cell's pixels back into the sketch paint buffer at the pool {x,y}.
function M.syncPatternTableCellPixelsToSketch(ptWin, col, row, wm)
  if not (type(col) == "number" and type(row) == "number") then
    return false
  end
  local sketch = M.resolveSketchForOwnedPatternTable(ptWin, wm)
  if not sketch or not M.hasPackData(sketch) then
    return false
  end
  local canvas = resolveCanvas(sketch)
  if not (canvas and type(canvas.edit) == "function") then
    return false
  end
  local logical = M.logicalIndexForPatternTableCell(ptWin, col, row)
  if logical == nil then
    return false
  end
  local entry = M.poolEntryForLogicalSlot(sketch, logical)
  if not entry then
    return false
  end

  local layerIndex = 1
  if ptWin.getActiveLayerIndex then
    layerIndex = ptWin:getActiveLayerIndex() or 1
  end
  local item = ptWin.get and ptWin:get(col, row, layerIndex) or nil
  if not (item and (item.getPixel or item.pixels)) then
    return false
  end

  local ox = math.floor(tonumber(entry.x) or 0)
  local oy = math.floor(tonumber(entry.y) or 0)
  for ty = 0, 7 do
    for tx = 0, 7 do
      local v
      if item.getPixel then
        v = item:getPixel(tx, ty)
      else
        v = item.pixels[ty * 8 + tx + 1]
      end
      canvas:edit(ox + tx, oy + ty, math.floor(tonumber(v) or 0))
    end
  end
  -- Scratch paint may no longer match a canonical solid; sample paint for Reflect.
  entry.solidShade = nil
  entry.exactSolid = nil
  M.invalidateReflectDisplay(sketch)
  return true
end

--- Invalidate PT tile-layer canvas after scratch-tile paint; sync sketch when owned.
function M.afterScratchPatternTablePaint(app, ptWin, col, row)
  if not WindowCaps.isPatternTable(ptWin) then
    return false
  end
  local layerIndex = 1
  if ptWin.getActiveLayerIndex then
    layerIndex = ptWin:getActiveLayerIndex() or 1
  end
  local wm = app and app.wm
  local sketchOwned = M.isSketchOwnedPatternTable(ptWin, wm)

  if ptWin.invalidateTileLayerCanvas then
    -- Padding slots share tile refs with the pad unique; dirty the whole layer.
    if sketchOwned then
      ptWin:invalidateTileLayerCanvas(layerIndex)
    else
      ptWin:invalidateTileLayerCanvas(layerIndex, col, row)
    end
  end

  if sketchOwned then
    return M.syncPatternTableCellPixelsToSketch(ptWin, col, row, wm)
  end
  return true
end

--- Write a stamped scratch tile's pixels back into its sketch paint cell.
function M.syncScratchTileItemToSketch(item, wm)
  if not item then
    return false
  end
  local sketchId = item._sketchCanvasWindowId
  if type(sketchId) ~= "string" or sketchId == "" then
    return false
  end
  local sketch = findWindowById(wm, sketchId)
  if not WindowCaps.isSketchCanvas(sketch) or sketch._closed then
    return false
  end
  local canvas = resolveCanvas(sketch)
  if not (canvas and type(canvas.edit) == "function") then
    return false
  end
  local ox = math.floor(tonumber(item._sketchPoolX) or 0)
  local oy = math.floor(tonumber(item._sketchPoolY) or 0)
  for ty = 0, 7 do
    for tx = 0, 7 do
      local v
      if item.getPixel then
        v = item:getPixel(tx, ty)
      else
        v = item.pixels and item.pixels[ty * 8 + tx + 1]
      end
      canvas:edit(ox + tx, oy + ty, math.floor(tonumber(v) or 0))
    end
  end
  if type(sketch.tilesPool) == "table" then
    for _, entry in ipairs(sketch.tilesPool) do
      if entry
        and math.floor(tonumber(entry.x) or -1) == ox
        and math.floor(tonumber(entry.y) or -1) == oy
      then
        entry.solidShade = nil
        entry.exactSolid = nil
        break
      end
    end
  end
  M.invalidateReflectDisplay(sketch)
  return true
end

--- After undo/redo restores scratch tile pixels: refresh tile canvases + sketch Reflect/paint.
--- Also marks Generate dirty when a sketch paint PixelCanvas was edited directly
--- (selection move/stamp undo), so tile mode does not show a stale pack.
function M.refreshViewsForScratchTileItems(app, items)
  if type(items) ~= "table" then
    return false
  end
  local wm = app and app.wm
  local seen = {}
  local any = false
  for _, item in pairs(items) do
    if item and not seen[item] then
      seen[item] = true
      if M.syncScratchTileItemToSketch(item, wm) then
        any = true
      end
    end
  end

  if wm and wm.getWindows then
    for _, win in ipairs(wm:getWindows()) do
      if WindowCaps.isSketchCanvas(win) and not win._closed then
        local canvas = resolveCanvas(win)
        if canvas and seen[canvas] then
          M.markGenerateDirty(win)
          M.invalidateReflectDisplay(win)
          any = true
        end
      end
    end
  end

  if not (wm and wm.getWindows) then
    return any
  end
  for _, win in ipairs(wm:getWindows()) do
    if win and not win._closed and win.invalidateTileLayerCanvas and win.layers then
      for li, layer in ipairs(win.layers) do
        if layer and layer.kind == "tile" and type(layer.items) == "table" then
          local hit = false
          for i = 1, #layer.items do
            if seen[layer.items[i]] then
              hit = true
              break
            end
          end
          if hit then
            -- Full layer: padding slots may share the same scratch tile ref.
            win:invalidateTileLayerCanvas(li)
            any = true
          end
        end
      end
    end
  end
  return any
end

----------------------------------------------------------------------
-- Sketch canvas PNG import (paint -> pack tol 0 -> linked PT catalog)
----------------------------------------------------------------------

function M.patternTableHasCatalogItems(ptWin)
  if not WindowCaps.isPatternTable(ptWin) then
    return false
  end
  local layer = ptWin.layers and ptWin.layers[1]
  if not (layer and type(layer.items) == "table") then
    return false
  end
  for _, item in pairs(layer.items) do
    if item ~= nil then
      return true
    end
  end
  return false
end

function M.needsPngImportReplaceConfirm(sketchWin, wm)
  if M.hasPackData(sketchWin) then
    return true
  end
  local pt = M.resolveLinkedPatternTable(sketchWin, wm)
  return pt ~= nil and M.patternTableHasCatalogItems(pt)
end

local function resolveSketchPaletteColors(sketchWin, app)
  local layer = sketchWin and sketchWin.layers and sketchWin.layers[1]
  local romRaw = app and app.appEditState and app.appEditState.romRaw
  return ShaderPaletteController.getPaletteColors(layer, 1, romRaw)
end

local function buildPendingFromFile(sketchWin, file, wm, app)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return nil, "not_sketch_canvas"
  end
  local ptWin = M.resolveLinkedPatternTable(sketchWin, wm)
  if not ptWin then
    return nil, "no_linked_pattern_table"
  end

  local paletteColors = resolveSketchPaletteColors(sketchWin, app)
  local flat, width, height = ImageImportController.decodePngFileToIndexedPixels(file, paletteColors)
  if not flat then
    return nil, width -- width holds err when flat is nil
  end
  if width ~= M.PNG_IMPORT_WIDTH or height ~= M.PNG_IMPORT_HEIGHT then
    return nil, "bad_dimensions"
  end

  local temp = PixelCanvas.new(width, height, 0)
  temp:loadRect(0, 0, flat, width, height)
  local pack, packErr = M.packFromCanvas(temp, M.PNG_IMPORT_TOLERANCE)
  if not pack then
    return nil, packErr or "pack_failed"
  end

  return {
    flat = flat,
    width = width,
    height = height,
    pack = pack,
    needsConfirm = M.needsPngImportReplaceConfirm(sketchWin, wm),
  }
end

local function applyPendingToSketch(sketchWin, pending, wm)
  local canvas = resolveCanvas(sketchWin)
  if not canvas then
    return false, "no_canvas"
  end

  canvas:loadRect(0, 0, pending.flat, pending.width, pending.height)
  M.applyPackToWindow(sketchWin, pending.pack)
  M.clearGenerateDirty(sketchWin)
  local applyOk, applyInfoOrErr = M.applyPackToLinkedPatternTable(sketchWin, wm)
  if not applyOk then
    return false, applyInfoOrErr or "apply_failed"
  end
  -- Warm tile-mode compose so edit and tile views both match the PNG.
  M.getReflectDisplayCanvas(sketchWin)
  pending.pack.appliedToPatternTable = true
  pending.pack.paddingTileIndex = applyInfoOrErr and applyInfoOrErr.paddingTileIndex
  return true, pending.pack
end

--- Import a 256x240 PNG onto a sketch canvas: write paint, pack at tolerance 0,
--- fill the linked Pattern table with a 256-slot scratch catalog.
--- When the PT / pack is already populated and opts.confirmed is not true,
--- returns false, "needs_confirm", pending (so the caller can show a modal).
--- @return ok, packOrErr [, pending]
function M.importPngToSketchCanvas(sketchWin, file, wm, opts)
  opts = opts or {}
  local pending = opts.pending
  if not pending then
    local built, err = buildPendingFromFile(sketchWin, file, wm, opts.app)
    if not built then
      return false, err
    end
    pending = built
  end

  if pending.needsConfirm and opts.confirmed ~= true then
    return false, M.PNG_IMPORT_NEEDS_CONFIRM, pending
  end

  return applyPendingToSketch(sketchWin, pending, wm)
end

function M.formatPngImportStatus(ok, packOrErr)
  if ok and type(packOrErr) == "table" then
    local n = tonumber(packOrErr.uniqueCount) or 0
    return string.format(
      "Sketch PNG imported: %d unique pattern%s -> pattern table",
      n,
      n == 1 and "" or "s"
    )
  end
  local err = tostring(packOrErr or "import_failed")
  if err == M.PNG_IMPORT_NEEDS_CONFIRM then
    return "Sketch PNG import: confirm replace"
  end
  if err == "too_many_unique" then
    return "Sketch PNG import failed: more than 256 unique patterns"
  end
  if err == "no_linked_pattern_table" then
    return "Sketch PNG import failed: link a Pattern table first"
  end
  if err == "bad_dimensions" then
    return string.format(
      "Sketch PNG import failed: image must be %dx%d",
      M.PNG_IMPORT_WIDTH,
      M.PNG_IMPORT_HEIGHT
    )
  end
  if err == "no_canvas" then
    return "Sketch PNG import failed: no canvas"
  end
  if err == "not_sketch_canvas" then
    return "Sketch PNG import failed: not a Sketch canvas"
  end
  return "Sketch PNG import failed: " .. err
end

return M
