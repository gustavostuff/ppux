-- Build a 1:1 transparent sprite sheet from every sprite layer in a window
-- and copy the PNG to the OS clipboard.

local SpriteLayerDraw = require("ui.windows_system.sprite_layer_draw")
local SpriteHydrationController = require("controllers.sprite.hydration_controller")

local M = {}

local MAX_DIM = 8192

local function positiveInt(value, fallback)
  local n = math.floor(tonumber(value) or fallback)
  if n < 1 then
    return fallback
  end
  return n
end

function M.spriteLayerIndices(win)
  local indices = {}
  local layers = win and win.layers
  if type(layers) ~= "table" then
    return indices
  end
  for i, layer in ipairs(layers) do
    if layer and layer.kind == "sprite" then
      indices[#indices + 1] = i
    end
  end
  return indices
end

function M.sheetLayout(win)
  local indices = M.spriteLayerIndices(win)
  if #indices == 0 then
    return nil, "No sprite layers"
  end

  local cellW = positiveInt(win.cellW, 8)
  local cellH = positiveInt(win.cellH, 8)
  local frameW = positiveInt(win.cols, 1) * cellW
  local frameH = positiveInt(win.rows, 1) * cellH
  if frameW > MAX_DIM or frameH > MAX_DIM then
    return nil, "Sprite sheet is too large"
  end

  local frameCols = #indices
  if frameW * frameCols > MAX_DIM then
    frameCols = math.max(1, math.floor(MAX_DIM / frameW))
  end
  local frameRows = math.ceil(#indices / frameCols)
  if frameH * frameRows > MAX_DIM then
    return nil, "Sprite sheet is too large"
  end

  return {
    indices = indices,
    cellW = cellW,
    cellH = cellH,
    frameW = frameW,
    frameH = frameH,
    frameCols = frameCols,
    frameRows = frameRows,
    sheetW = frameW * frameCols,
    sheetH = frameH * frameRows,
  }
end

local function ensureSpriteRefs(layer, state)
  if not (state and state.tilesPool and layer and layer.items) then
    return
  end
  local mode = layer.mode or "8x8"
  for _, sprite in ipairs(layer.items) do
    if sprite and sprite.removed ~= true then
      SpriteHydrationController.ensureTileRefsForSpriteItem(
        sprite,
        mode,
        state.tilesPool,
        state,
        layer
      )
    end
  end
end

local function drawLayer(win, layer, layerIndex, layout, state)
  ensureSpriteRefs(layer, state)
  SpriteLayerDraw.drawSpriteLayerInContentSpace({
    layer = layer,
    romRaw = state and state.romRaw or nil,
    cellW = layout.cellW,
    cellH = layout.cellH,
    viewMinX = 0,
    viewMinY = 0,
    viewMaxX = layout.frameW,
    viewMaxY = layout.frameH,
    windowKind = win.kind,
    isActiveLayer = true,
    spriteLayerIndex = layerIndex,
  })
end

function M.renderWindowSpriteSheet(win, app)
  if not (love and love.graphics and love.image) then
    return nil, "Could not generate sprite sheet"
  end
  local layout, layoutErr = M.sheetLayout(win)
  if not layout then
    return nil, layoutErr
  end

  local state = app and app.appEditState or nil
  local canvas
  local sheet
  local pushed = false

  local function restoreGraphics()
    if pushed then
      love.graphics.pop()
      pushed = false
    end
    if canvas then
      canvas:release()
      canvas = nil
    end
  end

  local ok, result = xpcall(function()
    canvas = love.graphics.newCanvas(layout.frameW, layout.frameH)
    canvas:setFilter("nearest", "nearest")
    sheet = love.image.newImageData(layout.sheetW, layout.sheetH)
    for frame, layerIndex in ipairs(layout.indices) do
      local layer = win.layers[layerIndex]
      local previousOpacity = layer.opacity
      layer.opacity = 1
      local drawOk, drawErr = pcall(function()
        love.graphics.push("all")
        pushed = true
        love.graphics.setCanvas(canvas)
        love.graphics.origin()
        love.graphics.clear(0, 0, 0, 0)
        drawLayer(win, layer, layerIndex, layout, state)
      end)
      if pushed then
        love.graphics.pop()
        pushed = false
      end
      layer.opacity = previousOpacity
      if not drawOk then
        error(drawErr, 0)
      end

      local frameData = canvas:newImageData()
      local col = (frame - 1) % layout.frameCols
      local row = math.floor((frame - 1) / layout.frameCols)
      sheet:paste(frameData, col * layout.frameW, row * layout.frameH)
      frameData:release()
    end
    local image = sheet
    sheet = nil
    return image
  end, debug.traceback)

  restoreGraphics()
  if not ok then
    if sheet then
      sheet:release()
    end
    return nil, "Could not generate sprite sheet"
  end
  return result
end

function M.copyWindowSpriteSheet(win, app)
  local image, err = M.renderWindowSpriteSheet(win, app)
  if not image then
    return false, err or "Could not generate sprite sheet"
  end

  local encodedOk, encoded = pcall(function()
    return image:encode("png")
  end)
  image:release()
  if not encodedOk or not encoded or not encoded.getString then
    return false, "Could not encode sprite sheet"
  end
  local bytes = encoded:getString()
  if type(bytes) ~= "string" or #bytes < 8 then
    return false, "Could not encode sprite sheet"
  end

  local Clipboard = require("utils.ppux_clipboard_native")
  local copied, clipErr = Clipboard.setPng(bytes)
  if copied then
    return true
  end
  if clipErr == "unavailable" then
    return false, "Clipboard image copy is unavailable"
  end
  return false, "Could not copy sprite sheet"
end

return M
