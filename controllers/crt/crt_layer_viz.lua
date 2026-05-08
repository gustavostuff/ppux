-- CRT layer visualizer: sample referenced window layers into a 256x240 viewport for in-window CRT shading.

local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local VW, VH = 256, 240

function M.viewportSize()
  return VW, VH
end

--- Pan is disabled only when the layer pixel size matches the NES viewport exactly.
function M.layerAllowsPan(sw, sh)
  return not (sw == VW and sh == VH)
end

function M.clampPan(sw, sh, panX, panY)
  local px = panX or 0
  local py = panY or 0

  local function clampDim(sourceSize, viewSize, p)
    if sourceSize > viewSize then
      return math.max(0, math.min(p, sourceSize - viewSize))
    elseif sourceSize < viewSize then
      return math.max(0, math.min(p, viewSize - sourceSize))
    end
    return 0
  end

  return clampDim(sw, VW, px), clampDim(sh, VH, py)
end

function M.resolveLayerDrawable(app, wm, ref)
  if not (wm and ref and ref.windowId ~= nil) then
    return nil, 0, 0
  end

  local win = wm:findWindowById(ref.windowId)
  if not win or win._closed or win._minimized or win._groupHidden == true then
    return nil, 0, 0
  end

  local li = ref.layerIndex or 1
  local layer = win.layers and win.layers[li]
  if not layer then
    return nil, 0, 0
  end

  if layer.kind == "canvas" and layer.canvas then
    local c = layer.canvas
    -- Love Canvas/Image expose getWidth/getHeight. PixelCanvas stores .width/.height and draws via .image.
    if type(c.getWidth) == "function" and type(c.getHeight) == "function" then
      local w, h = c:getWidth(), c:getHeight()
      if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
        return c, w, h
      end
    end
    if c.ensureImage then
      c:ensureImage()
    end
    if c._imageDirty and c.refreshImage then
      c:refreshImage()
    end
    local pw = tonumber(c.width) or tonumber(layer.canvasWidth)
    local ph = tonumber(c.height) or tonumber(layer.canvasHeight)
    if c.image and pw and ph and pw > 0 and ph > 0 then
      return c.image, pw, ph
    end
    return nil, 0, 0
  end

  if WindowCaps.isPpuFrame(win) and win._ensureNametableLayerCanvasState then
    local state = select(1, win:_ensureNametableLayerCanvasState(li))
    if state and state.canvas then
      if win._repaintNametableLayerCanvas then
        win:_repaintNametableLayerCanvas(li)
      end
      return state.canvas, state.width, state.height
    end
  end

  if layer.kind == "tile" and win._tileLayerCanvas and win._tileLayerCanvas[li] then
    local st = win._tileLayerCanvas[li]
    if win._repaintTileLayerCanvas and app then
      win:_repaintTileLayerCanvas(app, li)
    end
    if st.canvas then
      return st.canvas, st.width, st.height
    end
  end

  if layer.kind == "sprite" and app and win.ensureCrtSpriteExportCanvas then
    if WindowCaps.isAnimationLike(win) or WindowCaps.isPpuFrame(win) then
      local sc, sw, sh = win:ensureCrtSpriteExportCanvas(app, li)
      if sc and sw > 0 and sh > 0 then
        return sc, sw, sh
      end
    end
  end

  local cw, ch = win.cellW or 8, win.cellH or 8
  return nil, math.max(1, (win.cols or 1) * cw), math.max(1, (win.rows or 1) * ch)
end

function M.refAllowsPan(app, wm, ref)
  local canvas, sw, sh = M.resolveLayerDrawable(app, wm, ref)
  if sw <= 0 or sh <= 0 then
    return false
  end
  -- Without a resolved drawable we often fall back to full grid size (e.g. 256x240); that made
  -- layerAllowsPan false and blocked panning for small layers until a tile cache existed.
  if not canvas then
    return true
  end
  return M.layerAllowsPan(sw, sh)
end

--- Blit one drawable into the 256x240 scratch using crop / inset semantics stored in pan.
function M.blitDrawableOntoScratch(canvas, sw, sh, panX, panY, opacity)
  if not canvas then
    return
  end

  love.graphics.setBlendMode("alpha", "alphamultiply")
  love.graphics.setColor(1, 1, 1, opacity or 1)

  local sx = (sw > VW) and panX or 0
  local sy = (sh > VH) and panY or 0
  local ox = (sw <= VW) and panX or 0
  local oy = (sh <= VH) and panY or 0

  local rw = math.min(VW, sw - sx)
  local rh = math.min(VH, sh - sy)
  rw = math.max(0, math.min(rw, sw))
  rh = math.max(0, math.min(rh, sh))

  if rw <= 0 or rh <= 0 then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  local quad = love.graphics.newQuad(sx, sy, rw, rh, sw, sh)
  love.graphics.draw(canvas, quad, ox, oy)
  love.graphics.setColor(1, 1, 1, 1)
end

function M.compositeRefsOntoScratch(app, wm, scratch, crtWin)
  if not (scratch and crtWin) then
    return false
  end

  local destCanvas = app and app.canvas or nil
  local refs = crtWin.crtRefLayers or {}
  local n = #refs

  love.graphics.setCanvas(scratch)
  love.graphics.clear(0, 0, 0, 0)

  -- Solo view: only the active reference is CRT-previewed. Stacking all refs made switching layers appear to do nothing.
  if n > 0 then
    local idx = 1
    if crtWin.getActiveLayerIndex then
      idx = crtWin:getActiveLayerIndex()
    end
    idx = math.max(1, math.min(math.floor(idx), n))

    local ref = refs[idx]
    local canvas, sw, sh = M.resolveLayerDrawable(app, wm, ref)
    love.graphics.setCanvas(scratch)

    local px, py = M.clampPan(sw, sh, ref.panX or 0, ref.panY or 0)
    ref.panX, ref.panY = px, py
    local op = (ref.opacity ~= nil) and ref.opacity or 1.0
    if canvas and sw > 0 and sh > 0 then
      M.blitDrawableOntoScratch(canvas, sw, sh, px, py, op)
    end
  end

  -- Never leave setCanvas() on the window mid-frame - restore the workspace canvas.
  if destCanvas then
    love.graphics.setCanvas({ destCanvas, depthstencil = true })
  else
    love.graphics.setCanvas()
  end
  love.graphics.setBlendMode("alpha", "alphamultiply")
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

return M
