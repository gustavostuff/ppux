-- Cached palettized blit for sketch canvases with a linked sketch ROM palette.
-- Live draw used to bind the NES palette shader once per 8x8 tile (960+ draws per
-- 32x30 window). Rebuild an RGB canvas only when pixels, attrs, or codes change.

local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")

local M = {}

local function paletteCodesFingerprint(layer, romRaw)
  local parts = {}
  for palNum = 1, 4 do
    local codes = ShaderPaletteController.resolveLayerPaletteCodes(layer, palNum, romRaw)
    if type(codes) == "table" then
      parts[#parts + 1] = table.concat(codes, ",")
    else
      parts[#parts + 1] = "-"
    end
  end
  return table.concat(parts, ";")
end

local function attrFingerprint(sketchWin)
  local attrs = sketchWin and sketchWin.nametableAttrBytes
  if type(attrs) ~= "table" or #attrs < 1 then
    return ""
  end
  return table.concat(attrs, ",")
end

function M.sourceFingerprint(sketchWin, sourceCanvas, layer, romRaw)
  return table.concat({
    tostring(sourceCanvas),
    tostring(sourceCanvas and sourceCanvas._rev or 0),
    tostring(sourceCanvas and sourceCanvas.width or 0),
    tostring(sourceCanvas and sourceCanvas.height or 0),
    paletteCodesFingerprint(layer, romRaw),
    attrFingerprint(sketchWin),
  }, "|")
end

local function paintAttrTilesToCurrentCanvas(sketchWin, sourceCanvas, layer, romRaw)
  local cell = sketchWin.cellW or 8
  local cols = sketchWin.cols or 32
  local rows = sketchWin.rows or 30
  local buckets = { {}, {}, {}, {} }
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local palNum = SketchPalette.getTilePaletteNumber(sketchWin, col, row) or 1
      if palNum < 1 or palNum > 4 then
        palNum = 1
      end
      local bucket = buckets[palNum]
      bucket[#bucket + 1] = col
      bucket[#bucket + 1] = row
    end
  end

  local opaqueBgZero = { transparentZero = false }
  for palNum = 1, 4 do
    local bucket = buckets[palNum]
    if #bucket > 0 then
      ShaderPaletteController.applyLayerItemPalette(
        layer,
        sourceCanvas,
        true,
        romRaw,
        palNum,
        1,
        opaqueBgZero
      )
      for i = 1, #bucket, 2 do
        local col = bucket[i]
        local row = bucket[i + 1]
        local px = col * cell
        local py = row * cell
        sourceCanvas:drawRegion(px, py, px, py, cell, cell, 1)
      end
    end
  end
  ShaderPaletteController.releaseShader()
end

local function ensureRgbCanvas(sketchWin, width, height)
  local state = sketchWin._sketchPalettized
  if state
    and state.canvas
    and state.width == width
    and state.height == height
  then
    return state
  end
  local canvas = love.graphics.newCanvas(width, height)
  canvas:setFilter("nearest", "nearest")
  state = {
    canvas = canvas,
    width = width,
    height = height,
    fingerprint = nil,
    rebuilds = 0,
  }
  sketchWin._sketchPalettized = state
  return state
end

--- Draw palettized sketch pixels. Rebuilds an offscreen RGB canvas when the
--- source, attribute table, or linked palette codes change.
function M.drawAttrPalettized(app, sketchWin, sourceCanvas, layer, layerOpacity, romRaw)
  if not (sketchWin and sourceCanvas and sourceCanvas.drawRegion) then
    return false
  end

  local width = math.max(1, math.floor(tonumber(sourceCanvas.width) or 1))
  local height = math.max(1, math.floor(tonumber(sourceCanvas.height) or 1))
  local fingerprint = M.sourceFingerprint(sketchWin, sourceCanvas, layer, romRaw)
  local state = ensureRgbCanvas(sketchWin, width, height)

  if state.fingerprint ~= fingerprint then
    love.graphics.push("all")
    love.graphics.setCanvas(state.canvas)
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.clear(0, 0, 0, 0)
    paintAttrTilesToCurrentCanvas(sketchWin, sourceCanvas, layer, romRaw)
    love.graphics.pop()
    state.fingerprint = fingerprint
    state.rebuilds = (state.rebuilds or 0) + 1
  end

  local alpha = (layerOpacity ~= nil) and layerOpacity or 1.0
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.draw(state.canvas, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

return M
