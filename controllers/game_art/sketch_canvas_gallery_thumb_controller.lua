-- sketch_canvas_gallery_thumb_controller.lua
-- Tile-average RGB cache for gallery-slide thumbnails (32x30).
-- Averages are stored on the sketch window and refreshed on generate / PNG / tolerance.

local Palettes = require("palettes")
local colors = require("app_colors")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")

local M = {}

M.THUMB_W = 32
M.THUMB_H = 30
M.CELL = 8
M.TILE_COUNT = M.THUMB_W * M.THUMB_H
M.CANVAS_W = M.THUMB_W * M.CELL
M.CANVAS_H = M.THUMB_H * M.CELL

local function hex2rgb(code)
  local paletteName = ShaderPaletteController.paletteName or "smooth_fbx"
  local p = Palettes[paletteName] or Palettes.smooth_fbx
  local rgb = p and p[code]
  if type(rgb) == "table" then
    return {
      tonumber(rgb[1]) or 0,
      tonumber(rgb[2]) or 0,
      tonumber(rgb[3]) or 0,
    }
  end
  local black = colors.black or { 0, 0, 0 }
  return {
    tonumber(black[1]) or 0,
    tonumber(black[2]) or 0,
    tonumber(black[3]) or 0,
  }
end

local function colorsFromCodes(codes)
  local out = {}
  for i = 1, 4 do
    local code = codes and codes[i]
    if type(code) ~= "string" or #code < 2 then
      code = SketchPalette.DEFAULT_BROWN_CODES[i] or "0F"
    else
      code = string.upper(code:sub(1, 2))
    end
    out[i] = hex2rgb(code)
  end
  return out
end

local function codesFromPaletteRow(paletteWin, rowIdx)
  if not SketchPalette.isSketchModePalette(paletteWin) then
    return nil
  end
  local rowTbl = paletteWin.codes2D and paletteWin.codes2D[rowIdx]
  if type(rowTbl) ~= "table" then
    return nil
  end
  local out = {}
  for col = 0, 3 do
    local code = rowTbl[col]
    if type(code) ~= "string" or #code < 2 then
      return nil
    end
    out[col + 1] = string.upper(code:sub(1, 2))
  end
  return out
end

local function brownColors()
  return colorsFromCodes({
    SketchPalette.DEFAULT_BROWN_CODES[1],
    SketchPalette.DEFAULT_BROWN_CODES[2],
    SketchPalette.DEFAULT_BROWN_CODES[3],
    SketchPalette.DEFAULT_BROWN_CODES[4],
  })
end

--- Resolve 4 palette rows (each 4 RGB colors) for thumbs.
--- Linked sketch palette uses all codes2D rows; unlinked uses brown for every row.
--- Never use the global ShaderPaletteController.codes (that leaks other windows' palettes).
function M.resolvePaletteRows(sketchWin, app)
  local wm = app and app.wm or nil
  local linked = SketchPalette.getLinkedSketchPalette(sketchWin, wm)
  local rows = {}
  local brown = brownColors()
  for row = 0, 3 do
    local codes = codesFromPaletteRow(linked, row)
    rows[row + 1] = codes and colorsFromCodes(codes) or brown
  end
  return rows
end

--- Back-compat: row 0 / palette number 1 colors.
function M.resolvePaletteColors(sketchWin, app)
  local rows = M.resolvePaletteRows(sketchWin, app)
  return rows[1]
end

local function resolveSourceCanvas(sketchWin)
  if not sketchWin then
    return nil
  end
  if type(sketchWin.getActiveCanvas) == "function" then
    return sketchWin:getActiveCanvas()
  end
  local layer = sketchWin.layers and sketchWin.layers[sketchWin.activeLayer or 1]
  return layer and layer.canvas or nil
end

function M.hasTileAverages(sketchWin)
  local avg = sketchWin and sketchWin.tileAverageRgb
  return type(avg) == "table" and #avg == M.TILE_COUNT
end

function M.clearTileAverages(sketchWin)
  if type(sketchWin) == "table" then
    sketchWin.tileAverageRgb = nil
    sketchWin._tileAveragePaletteKey = nil
  end
end

local function paletteCacheKey(sketchWin, app)
  local wm = app and app.wm or nil
  local linked = SketchPalette.getLinkedSketchPalette(sketchWin, wm)
  if linked and type(linked._id) == "string" and linked._id ~= "" then
    -- v2: thumbs sample all 4 palette rows via tile attrs.
    local parts = { "pal", linked._id, "v2" }
    if type(linked.codes2D) == "table" then
      for row = 0, 3 do
        local rowTbl = linked.codes2D[row]
        for col = 0, 3 do
          local code = rowTbl and rowTbl[col]
          parts[#parts + 1] = (type(code) == "string" and code) or "?"
        end
      end
    end
    return table.concat(parts, ":")
  end
  return "brown:v2"
end

--- Average RGB of a 64-pixel shade list (palette-mapped).
--- @return r, g, b in 0..1
function M.averagePixelsColor(pixels, paletteColors)
  local sr, sg, sb = 0, 0, 0
  local count = 0
  if type(pixels) ~= "table" then
    return 0, 0, 0
  end
  for i = 1, 64 do
    local idx = math.max(0, math.min(3, math.floor(tonumber(pixels[i]) or 0)))
    local rgb = paletteColors and paletteColors[idx + 1]
    if type(rgb) ~= "table" then
      rgb = hex2rgb(SketchPalette.DEFAULT_BROWN_CODES[idx + 1] or "0F")
    end
    sr = sr + (rgb[1] or 0)
    sg = sg + (rgb[2] or 0)
    sb = sb + (rgb[3] or 0)
    count = count + 1
  end
  if count < 1 then
    return 0, 0, 0
  end
  return sr / count, sg / count, sb / count
end

--- Average RGB of one 8x8 tile from the paint canvas (palette-mapped).
--- @return r, g, b in 0..1
function M.averageTileColor(canvas, tileCol, tileRow, paletteColors)
  tileCol = math.floor(tonumber(tileCol) or 0)
  tileRow = math.floor(tonumber(tileRow) or 0)
  local pixels = nil
  if canvas and type(canvas.extractTilePixels) == "function" then
    pixels = canvas:extractTilePixels(tileCol * M.CELL, tileRow * M.CELL, M.CELL)
  else
    pixels = {}
    local ox = tileCol * M.CELL
    local oy = tileRow * M.CELL
    local i = 1
    for py = 0, M.CELL - 1 do
      for px = 0, M.CELL - 1 do
        local idx = 0
        if canvas and type(canvas.getPixel) == "function" then
          idx = canvas:getPixel(ox + px, oy + py) or 0
        elseif canvas and type(canvas.pixels) == "table" then
          local w = math.floor(tonumber(canvas.width) or M.CANVAS_W)
          idx = canvas.pixels[(oy + py) * w + (ox + px) + 1] or 0
        end
        pixels[i] = idx
        i = i + 1
      end
    end
  end
  return M.averagePixelsColor(pixels, paletteColors)
end

--- Average the tile currently shown at (col,row): pack/nametable when present, else paint.
--- Uses the tile's attribute palette row (1-4) when a linked sketch palette exists.
function M.averageDisplayedTileColor(sketchWin, tileCol, tileRow, paletteRows)
  tileCol = math.floor(tonumber(tileCol) or 0)
  tileRow = math.floor(tonumber(tileRow) or 0)
  local Pack = require("controllers.game_art.sketch_canvas_pack_controller")
  local canvas = resolveSourceCanvas(sketchWin)
  local palNum = SketchPalette.getTilePaletteNumber(sketchWin, tileCol, tileRow) or 1
  if palNum < 1 then
    palNum = 1
  elseif palNum > 4 then
    palNum = 4
  end
  local paletteColors = (type(paletteRows) == "table" and paletteRows[palNum]) or nil
  if type(paletteColors) ~= "table" and type(paletteRows) == "table" and type(paletteRows[1]) == "table" then
    -- Legacy callers passed a single 4-color row.
    if type(paletteRows[1][1]) == "number" then
      paletteColors = paletteRows
    else
      paletteColors = paletteRows[1]
    end
  end
  if Pack.hasPackData(sketchWin) then
    local nt = sketchWin.nametableBytes
    local idx = tileRow * M.THUMB_W + tileCol + 1
    local poolIndex = math.floor(tonumber(nt and nt[idx]) or 0)
    local entry = sketchWin.tilesPool and sketchWin.tilesPool[poolIndex + 1]
    local pixels = Pack.pixelsForPoolEntry(canvas, entry)
    if type(pixels) == "table" then
      return M.averagePixelsColor(pixels, paletteColors)
    end
  end
  return M.averageTileColor(canvas, tileCol, tileRow, paletteColors)
end

local function tileAverageIndex(tileCol, tileRow)
  return math.floor(tonumber(tileRow) or 0) * M.THUMB_W + math.floor(tonumber(tileCol) or 0) + 1
end

--- Recompute one tile's cached average (after set/remove / palette attr change).
function M.refreshTileAt(sketchWin, tileCol, tileRow, app)
  if type(sketchWin) ~= "table" then
    return false
  end
  if not M.hasTileAverages(sketchWin) then
    return M.refreshForSketch(sketchWin, app)
  end
  tileCol = math.floor(tonumber(tileCol) or 0)
  tileRow = math.floor(tonumber(tileRow) or 0)
  if tileCol < 0 or tileRow < 0 or tileCol >= M.THUMB_W or tileRow >= M.THUMB_H then
    return false
  end
  local rows = M.resolvePaletteRows(sketchWin, app)
  local r, g, b = M.averageDisplayedTileColor(sketchWin, tileCol, tileRow, rows)
  sketchWin.tileAverageRgb[tileAverageIndex(tileCol, tileRow)] = { r, g, b }
  return true
end

--- Swap two cached tile averages (after nametable swap / move).
function M.swapTileAverages(sketchWin, col1, row1, col2, row2)
  if type(sketchWin) ~= "table" then
    return false
  end
  if not M.hasTileAverages(sketchWin) then
    return M.refreshForSketch(sketchWin, nil)
  end
  local i1 = tileAverageIndex(col1, row1)
  local i2 = tileAverageIndex(col2, row2)
  local avg = sketchWin.tileAverageRgb
  if not (avg[i1] and avg[i2]) then
    return M.refreshForSketch(sketchWin, nil)
  end
  avg[i1], avg[i2] = avg[i2], avg[i1]
  return true
end

--- Recompute and store `sketchWin.tileAverageRgb` (960 entries of {r,g,b}).
--- Uses packed nametable layout when pack data exists.
--- @return ok, err
function M.refreshForSketch(sketchWin, app)
  if type(sketchWin) ~= "table" then
    return false, "no_sketch"
  end
  local canvas = resolveSourceCanvas(sketchWin)
  if not canvas then
    M.clearTileAverages(sketchWin)
    return false, "no_canvas"
  end
  local palette = M.resolvePaletteRows(sketchWin, app)
  local averages = {}
  for ty = 0, M.THUMB_H - 1 do
    for tx = 0, M.THUMB_W - 1 do
      local r, g, b = M.averageDisplayedTileColor(sketchWin, tx, ty, palette)
      averages[ty * M.THUMB_W + tx + 1] = { r, g, b }
    end
  end
  sketchWin.tileAverageRgb = averages
  sketchWin._tileAveragePaletteKey = paletteCacheKey(sketchWin, app)
  return true
end

--- Ensure cache exists and matches the sketch's current palette (brown vs linked).
function M.ensureTileAverages(sketchWin, app)
  local key = paletteCacheKey(sketchWin, app)
  if M.hasTileAverages(sketchWin) and sketchWin._tileAveragePaletteKey == key then
    return true
  end
  return M.refreshForSketch(sketchWin, app)
end

--- Build a 32x30 ImageData from the sketch's cached tile averages.
--- @return ImageData|nil, err
function M.buildThumbImageData(sketchWin, app)
  local ok = M.ensureTileAverages(sketchWin, app)
  if not ok or not M.hasTileAverages(sketchWin) then
    return nil, "no_tile_averages"
  end
  if not (love and love.image and love.image.newImageData) then
    return nil, "no_love_image"
  end
  local averages = sketchWin.tileAverageRgb
  local img = love.image.newImageData(M.THUMB_W, M.THUMB_H)
  for ty = 0, M.THUMB_H - 1 do
    for tx = 0, M.THUMB_W - 1 do
      local rgb = averages[ty * M.THUMB_W + tx + 1] or { 0, 0, 0 }
      img:setPixel(tx, ty, rgb[1] or 0, rgb[2] or 0, rgb[3] or 0, 1)
    end
  end
  return img
end

--- @return Image|nil, err
function M.buildThumbImage(sketchWin, app)
  local imgData, err = M.buildThumbImageData(sketchWin, app)
  if not imgData then
    return nil, err
  end
  if not (love and love.graphics and love.graphics.newImage) then
    return nil, "no_love_graphics"
  end
  local image = love.graphics.newImage(imgData)
  if image.setFilter then
    image:setFilter("nearest", "nearest")
  end
  return image
end

--- Build strip entries `{ sketch, image, title }` in order.
function M.buildStripEntries(sketches, app)
  local entries = {}
  if type(sketches) ~= "table" then
    return entries
  end
  for _, win in ipairs(sketches) do
    local image = select(1, M.buildThumbImage(win, app))
    local title = (win and (win.title or win.name)) or "Sketch"
    entries[#entries + 1] = {
      sketch = win,
      image = image,
      title = tostring(title),
    }
  end
  return entries
end

return M
