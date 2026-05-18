-- Shared sprite-layer raster path for OAM animation windows, PPU Frame sprite layers, and CRT layer viz export.
-- Single implementation of NES torus wrap, OAM wrap-preview copies, base+dx positioning, and tile draw.

local SpriteController = require("controllers.sprite.sprite_controller")
local SpriteHydrationController = require("controllers.sprite.hydration_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local colors = require("app_colors")
local images = require("images")

local M = {}

function M.nesMod(v, m)
  local mm = tonumber(m) or 1
  if mm <= 0 then
    return 0
  end
  return ((tonumber(v) or 0) % mm + mm) % mm
end

--- NES sprite position in pixels before applying layer origin + torus wrap.
--- When ROM-backed bases exist, uses baseX/Y + dx/dy; otherwise worldX/Y / x/y.
function M.spriteWorldPixelsBeforeOrigin(s)
  if not s then
    return 0, 0
  end
  local dx = math.floor(tonumber(s.dx) or 0)
  local dy = math.floor(tonumber(s.dy) or 0)
  local bx = s.baseX
  local by = s.baseY
  if type(bx) == "number" and type(by) == "number" then
    return math.floor(bx + dx + 0.5), math.floor(by + dy + 0.5)
  end
  local wx = tonumber(s.worldX)
  local wy = tonumber(s.worldY)
  if wx == nil then wx = tonumber(s.x) end
  if wy == nil then wy = tonumber(s.y) end
  return math.floor((wx or 0) + 0.5), math.floor((wy or 0) + 0.5)
end

local function intersectsRange(startPos, size, minPos, maxPos)
  local a0 = startPos
  local a1 = startPos + size
  return a0 < maxPos and a1 > minPos
end

--- Torus wrap candidates that intersect the view (same for raster + pointer hit-testing).
function M.collectWrappedPositions(basePos, size, range, viewMin, viewMax)
  local positions = {}
  local seen = {}
  for _, candidate in ipairs({ basePos - range, basePos, basePos + range }) do
    if not seen[candidate] and intersectsRange(candidate, size, viewMin, viewMax) then
      positions[#positions + 1] = candidate
      seen[candidate] = true
    end
  end
  if #positions == 0 then
    positions[1] = basePos
  end
  table.sort(positions)
  return positions
end

function M.wrapPreviewEnabledForKind(windowKind)
  return windowKind == "oam_animation"
end

--- Draw dotted/fallback origin axes (content space). Caller sets transform + scissor.
function M.drawSpriteOriginGuidesIfNeeded(opts)
  opts = opts or {}
  local kind = opts.windowKind
  local show = opts.showSpriteOriginGuides == true
  local L = opts.layer
  local isActiveLayer = opts.isActiveLayer == true
  if not (show and L and isActiveLayer and (kind == "ppu_frame" or kind == "oam_animation")) then
    return
  end

  local axisX = L.originX or 0
  local axisY = L.originY or 0
  love.graphics.setColor(colors.gray75[1], colors.gray75[2], colors.gray75[3], 0.85)
  local dotted = images and images.dotted_line or nil
  local ok = false
  if dotted then
    for i = 0, 7 do
      love.graphics.draw(dotted, i * 32, axisY)
    end
    for i = 0, 7 do
      love.graphics.draw(dotted, axisX, i * 32, math.pi * 0.5, 1, 1)
    end
    ok = true
  end
  if not ok then
    love.graphics.line(0, axisY, 256, axisY)
    love.graphics.line(axisX, 0, axisX, 256)
  end
  love.graphics.setColor(colors.white)
end

function M.drawDefaultSpriteBody(L, s, isActiveLayer, cw, ch, mode, layerOpacity, romRaw)
  local alpha = (L.opacity ~= nil) and L.opacity or layerOpacity or 1.0
  love.graphics.setColor(1.0, 1.0, 1.0, alpha)

  local layerOpacityOverride = (L and L.opacity ~= nil) and L.opacity or nil
  ShaderPaletteController.applyLayerItemPalette(
    L,
    s,
    isActiveLayer,
    romRaw,
    nil,
    layerOpacityOverride
  )

  local top = s.topRef
  local needRefs =
    mode == "8x16"
      and (not top or not s.botRef)
      or (mode ~= "8x16" and not top)
  if needRefs then
    local ctx = rawget(_G, "ctx")
    local app = ctx and ctx.app or nil
    local state = app and app.appEditState or nil
    if state and state.tilesPool then
      SpriteHydrationController.ensureTileRefsForSpriteItem(s, mode, state.tilesPool, state, L)
      top = s.topRef
    end
  end
  if not (top and top.draw) then
    ShaderPaletteController.releaseShader()
    return
  end
  local mirrorX = s.mirrorX or false
  local mirrorY = s.mirrorY or false
  local scaleX = mirrorX and -1 or 1
  local scaleY = mirrorY and -1 or 1

  love.graphics.push()
  local offsetX = mirrorX and cw or 0
  local offsetY = 0
  if mirrorY then
    offsetY = (mode == "8x16") and (2 * ch) or ch
  end
  if offsetX ~= 0 or offsetY ~= 0 then
    love.graphics.translate(offsetX, offsetY)
  end

  if mode == "8x16" and mirrorY then
    if s.botRef and s.botRef.draw then
      s.botRef:draw(0, -ch, scaleX, scaleY)
    end
    top:draw(0, 0, scaleX, scaleY)
  else
    top:draw(0, 0, scaleX, scaleY)
    if mode == "8x16" and s.botRef and s.botRef.draw then
      s.botRef:draw(0, ch, scaleX, scaleY)
    end
  end

  love.graphics.pop()
  ShaderPaletteController.releaseShader()
end

--- Draw every sprite in one layer in **current content pixel space** (caller applies window pan/zoom/scissor).
--- opts.layer, opts.romRaw, opts.cellW, opts.cellH
--- opts.viewMinX/Y, viewMaxX/Y - rectangle used for OAM wrap-preview culling
--- opts.windowKind - "oam_animation" enables wrap copies; PPU Frame uses same torus without duplicate wraps if not oam_animation
--- opts.isActiveLayer - shader palette active flag
--- opts.spriteLayerIndex - passed to renderSprite as index (optional)
--- opts.renderSprite - optional function(L, s, isActiveLayer, ch, mode, idx, spriteW, spriteH, layerOpacity, romRaw)
function M.drawSpriteLayerInContentSpace(opts)
  opts = opts or {}
  local L = opts.layer
  if not (L and L.kind == "sprite") then
    return
  end
  local items = L.items
  if not (items and #items > 0) then
    return
  end

  local cw = tonumber(opts.cellW) or 8
  local ch = tonumber(opts.cellH) or 8
  local romRaw = opts.romRaw
  local originX = L.originX or 0
  local originY = L.originY or 0
  local mode = L.mode or "8x8"
  local spriteW = cw
  local spriteH = (mode == "8x16") and (2 * ch) or ch

  local NES_W = SpriteController.SPRITE_X_RANGE
  local NES_H = SpriteController.SPRITE_Y_RANGE

  local isActiveLayer = opts.isActiveLayer ~= false
  local layerOpacity = (L.opacity ~= nil) and L.opacity or 1.0

  local viewMinX = tonumber(opts.viewMinX) or 0
  local viewMinY = tonumber(opts.viewMinY) or 0
  local viewMaxX = tonumber(opts.viewMaxX) or NES_W
  local viewMaxY = tonumber(opts.viewMaxY) or NES_H

  local windowKind = opts.windowKind
  local wrapPreview = opts.wrapPreview
  if wrapPreview == nil then
    wrapPreview = M.wrapPreviewEnabledForKind(windowKind)
  end

  local renderSprite = opts.renderSprite
  local liIdx = tonumber(opts.spriteLayerIndex) or 1

  for idx, s in ipairs(items) do
    if s.removed == true then
      goto sprite_draw_continue
    end

    local wx, wy = M.spriteWorldPixelsBeforeOrigin(s)
    local drawX = M.nesMod(originX + wx, NES_W)
    local drawY = M.nesMod(originY + wy, NES_H)

    local drawXs = wrapPreview
      and M.collectWrappedPositions(drawX, spriteW, NES_W, viewMinX, viewMaxX)
      or { drawX }
    local drawYs = wrapPreview
      and M.collectWrappedPositions(drawY, spriteH, NES_H, viewMinY, viewMaxY)
      or { drawY }

    for _, screenY in ipairs(drawYs) do
      for _, screenX in ipairs(drawXs) do
        love.graphics.push()
        love.graphics.translate(screenX, screenY)

        if renderSprite then
          renderSprite(L, s, isActiveLayer, ch, mode, idx, spriteW, spriteH, layerOpacity, romRaw)
        else
          M.drawDefaultSpriteBody(L, s, isActiveLayer, cw, ch, mode, layerOpacity, romRaw)
        end

        love.graphics.pop()
      end
    end
    ::sprite_draw_continue::
  end
end

--- Hydrate + allocate canvas + rasterize layer for CRT viewer / sampling.
function M.rasterizeSpriteLayerForCrt(window, app, layerIndex)
  local li = tonumber(layerIndex) or 1
  local L = window.layers and window.layers[li]
  if not (L and L.kind == "sprite") then
    return nil, 0, 0
  end

  local state = app and app.appEditState
  SpriteHydrationController.hydrateSpriteLayer(L, {
    romRaw = state and state.romRaw or "",
    tilesPool = state and state.tilesPool,
    appEditState = state,
  })

  local cw, ch = window.cellW or 8, window.cellH or 8
  local NES_W = SpriteController.SPRITE_X_RANGE
  local NES_H = SpriteController.SPRITE_Y_RANGE
  local gridW = math.max(1, (window.cols or 1) * cw)
  local gridH = math.max(1, (window.rows or 1) * ch)
  local wpx = math.max(gridW, NES_W)
  local hpx = math.max(gridH, NES_H)

  window._crtSpriteExportCanvasByLayer = window._crtSpriteExportCanvasByLayer or {}
  local slot = window._crtSpriteExportCanvasByLayer
  local entry = slot[li]
  local canvas = entry and entry.canvas
  if not canvas or canvas:getWidth() ~= wpx or canvas:getHeight() ~= hpx then
    if canvas then
      canvas:release()
    end
    canvas = love.graphics.newCanvas(wpx, hpx)
    canvas:setFilter("nearest", "nearest")
    slot[li] = { canvas = canvas }
  end

  local romRaw = state and state.romRaw

  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()

  M.drawSpriteLayerInContentSpace({
    layer = L,
    romRaw = romRaw,
    cellW = cw,
    cellH = ch,
    viewMinX = 0,
    viewMinY = 0,
    viewMaxX = wpx,
    viewMaxY = hpx,
    windowKind = window.kind,
    isActiveLayer = true,
    spriteLayerIndex = li,
    renderSprite = nil,
  })

  love.graphics.pop()

  return canvas, wpx, hpx
end

return M
