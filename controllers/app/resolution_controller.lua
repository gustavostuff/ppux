local crtShaderLoadAttempted = false
local cachedCrtShader = nil
local compositeShaderLoadAttempted = false
local cachedCompositeScanlinesShader = nil

local SLICE_W = 320
local SLICE_H = 180

local function resolveCrtShader()
  if cachedCrtShader ~= nil or crtShaderLoadAttempted then
    return cachedCrtShader
  end

  crtShaderLoadAttempted = true
  local ok = pcall(require, "shaders")
  if not ok then
    return nil
  end

  cachedCrtShader = rawget(_G, "crtShader")
  return cachedCrtShader
end

local function resolveCompositeScanlinesShader()
  if cachedCompositeScanlinesShader ~= nil or compositeShaderLoadAttempted then
    return cachedCompositeScanlinesShader
  end

  compositeShaderLoadAttempted = true
  local ok = pcall(require, "shaders")
  if not ok then
    return nil
  end

  cachedCompositeScanlinesShader = rawget(_G, "compositeScanlinesShader")
  return cachedCompositeScanlinesShader
end

local ResolutionController = {
  modes = {
    KEEP_ASPECT = 1,
    PIXEL_PERFECT = 2,
    STRETCH = 3,
  },
}

function ResolutionController:init(canvas)
  self._crtSourceQuad = nil
  self.canvas = canvas
  self.canvasWidth = self.canvas:getWidth()
  self.canvasHeight = self.canvas:getHeight()
  self.displayWidth = self.canvasWidth
  self.displayHeight = self.canvasHeight
  self.canvasScaleX = 1
  self.canvasScaleY = 1
  self.defaultMode = self.modes.KEEP_ASPECT
  self.canvasCrtShaderEnabled = false
  self.canvasCrtFilterKind = "crt"
  self.canvasCrtFlat = (rawget(_G, "__PPUX_CRT_FLAT__") == true)
  self.canvasCrtDistortion = tonumber(rawget(_G, "__PPUX_CRT_DISTORTION__")) or 0.1
  self.crtLowResPresentation = false
  self.crtViewportX = self.crtViewportX or 0
  self.crtViewportY = self.crtViewportY or 0
  self.crtSliceCanvas = nil
  self._crtSourceQuad = nil
  -- Legacy path: draw CRT lens sampling the composed workspace after renderCanvas (disabled by default).
  self.crtLensPostCanvasOverlayEnabled = false
  self:setMode(self.defaultMode)

  self:recalculate()
end

function ResolutionController:setMode(mode)
  self.mode = mode
  self:recalculate()
end

function ResolutionController:normalizeScale()
  if self.canvasScaleX > self.canvasScaleY then
    self.canvasScaleX = self.canvasScaleY
  else
    self.canvasScaleY = self.canvasScaleX
  end
end

function ResolutionController:setCanvasPosition()
  local w = love.graphics.getWidth()
  local h = love.graphics.getHeight()
  local dw = self.displayWidth or self.canvasWidth
  local dh = self.displayHeight or self.canvasHeight
  self.canvasX = math.floor(w / 2 - dw * self.canvasScaleX / 2)
  self.canvasY = math.floor(h / 2 - dh * self.canvasScaleY / 2)
end

function ResolutionController:recalculate()
  local w = love.graphics.getWidth()
  local h = love.graphics.getHeight()
  local dw = self.displayWidth or self.canvasWidth
  local dh = self.displayHeight or self.canvasHeight

  if self.mode == self.modes.KEEP_ASPECT then
    self.canvasScaleX = w / dw
    self.canvasScaleY = h / dh
    self:normalizeScale()
  elseif self.mode == self.modes.PIXEL_PERFECT then
    self.canvasScaleX = math.floor(w / dw)
    self.canvasScaleY = math.floor(h / dh)
    self:normalizeScale()
  elseif self.mode == self.modes.STRETCH then
    self.canvasScaleX = w / dw
    self.canvasScaleY = h / dh
  end

  self:setCanvasPosition()
end

function ResolutionController:applyCrtPresentationFromApp(app)
  local low = app
    and app.crtModeEnabled == true
    and app.crtCanvasResolution == "320x180"
  self.crtLowResPresentation = low == true
  if self.crtLowResPresentation then
    self.displayWidth = SLICE_W
    self.displayHeight = SLICE_H
  else
    self.displayWidth = self.canvasWidth
    self.displayHeight = self.canvasHeight
  end
  self:clampCrtViewport()
  self:recalculate()
end

function ResolutionController:clampCrtViewport()
  if not (self.canvasWidth and self.canvasHeight) then
    return
  end
  local maxX = math.max(0, self.canvasWidth - SLICE_W)
  local maxY = math.max(0, self.canvasHeight - SLICE_H)
  self.crtViewportX = math.max(0, math.min(maxX, self.crtViewportX or 0))
  self.crtViewportY = math.max(0, math.min(maxY, self.crtViewportY or 0))
end

function ResolutionController:_ensureSliceCanvas()
  if self.crtSliceCanvas then
    return
  end
  if not (love and love.graphics and love.graphics.newCanvas) then
    return
  end
  self.crtSliceCanvas = love.graphics.newCanvas(SLICE_W, SLICE_H)
  self.crtSliceCanvas:setFilter("nearest", "nearest")
end

function ResolutionController:_ensureCrtSourceQuad()
  if self._crtSourceQuad then
    return
  end
  self._crtSourceQuad = love.graphics.newQuad(0, 0, SLICE_W, SLICE_H, self.canvasWidth, self.canvasHeight)
end

--- Edge auto-pan when CRT shows a 320x180 slice of the 640x360 workspace.
function ResolutionController:updateCrtViewportPan(dt)
  if not (self.crtLowResPresentation and self.canvasCrtShaderEnabled) then
    return
  end
  if not (love and love.mouse and love.mouse.getPosition) then
    return
  end

  local mx, my = love.mouse.getPosition()
  local l, t = self.canvasX, self.canvasY
  local dw = self.displayWidth or SLICE_W
  local dh = self.displayHeight or SLICE_H
  local rw = dw * self.canvasScaleX
  local rh = dh * self.canvasScaleY
  local r, b = l + rw, t + rh
  if mx < l or mx > r or my < t or my > b then
    return
  end

  local margin = 64
  local maxSpeed = 520

  local function edgeFactor(distFromEdge)
    if distFromEdge >= margin then
      return 0
    end
    return 1 - (distFromEdge / margin)
  end

  local dx, dy = 0, 0
  local dl = mx - l
  local dr = r - mx
  local dtt = my - t
  local db = b - my

  if dl < margin then
    dx = dx - edgeFactor(dl)
  end
  if dr < margin then
    dx = dx + edgeFactor(dr)
  end
  if dtt < margin then
    dy = dy - edgeFactor(dtt)
  end
  if db < margin then
    dy = dy + edgeFactor(db)
  end

  if dx ~= 0 or dy ~= 0 then
    self.crtViewportX = (self.crtViewportX or 0) + dx * maxSpeed * dt
    self.crtViewportY = (self.crtViewportY or 0) + dy * maxSpeed * dt
    self:clampCrtViewport()
  end
end

function ResolutionController:renderCanvas()
  local drawTarget = self.canvas

  if self.canvasCrtShaderEnabled == true and self.crtLowResPresentation then
    self:_ensureSliceCanvas()
    self:_ensureCrtSourceQuad()
    if self.crtSliceCanvas and self._crtSourceQuad and self.canvas then
      love.graphics.setCanvas(self.crtSliceCanvas)
      love.graphics.clear(0, 0, 0, 1)
      love.graphics.setColor(1, 1, 1, 1)
      self._crtSourceQuad:setViewport(
        self.crtViewportX,
        self.crtViewportY,
        SLICE_W,
        SLICE_H,
        self.canvasWidth,
        self.canvasHeight
      )
      love.graphics.draw(self.canvas, self._crtSourceQuad, 0, 0)
      love.graphics.setCanvas()
      drawTarget = self.crtSliceCanvas
    end
  end

  -- Pixel dimensions of the texture actually drawn (workspace canvas or CRT slice),
  -- always from the Canvas object so they stay in sync with the drawable.
  local texW = drawTarget:getWidth()
  local texH = drawTarget:getHeight()

  local shaderApplied = false
  if self.canvasCrtShaderEnabled == true then
    local kind = self.canvasCrtFilterKind or "crt"
    if kind == "composite" then
      local compositeShader = resolveCompositeScanlinesShader()
      if compositeShader then
        compositeShader:send("screen", { texW, texH })
        love.graphics.setShader(compositeShader)
        shaderApplied = true
      end
    else
      local crtShader = resolveCrtShader()
      if crtShader then
        crtShader:send("inputSize", { texW, texH })
        crtShader:send("outputSize", { love.graphics.getWidth(), love.graphics.getHeight() })
        crtShader:send("textureSize", { texW, texH })
        local curve = self.canvasCrtFlat and 0 or (self.canvasCrtDistortion or 0.1)
        crtShader:send("distortion", curve)
        love.graphics.setShader(crtShader)
        shaderApplied = true
      end
    end
  end

  love.graphics.draw(
    drawTarget,
    self.canvasX,
    self.canvasY,
    0,
    self.canvasScaleX,
    self.canvasScaleY
  )

  if shaderApplied then
    love.graphics.setShader()
  end
end

local CRT_LENS_NES_W = 256
local CRT_LENS_NES_H = 240

function ResolutionController:_ensureCrtLensScratchCanvas()
  if self._crtLensScratch
    and self._crtLensScratch:getWidth() == CRT_LENS_NES_W
    and self._crtLensScratch:getHeight() == CRT_LENS_NES_H
  then
    return self._crtLensScratch
  end
  if self._crtLensScratch then
    self._crtLensScratch:release()
    self._crtLensScratch = nil
  end
  self._crtLensScratch = love.graphics.newCanvas(CRT_LENS_NES_W, CRT_LENS_NES_H)
  self._crtLensScratch:setFilter("linear", "linear")
  return self._crtLensScratch
end

--- Map workspace canvas pixel rect to on-screen rect (uses slice viewport when low-res CRT presentation is active).
function ResolutionController:workspaceRectToScreen(x, y, w, h)
  local sx0, sy0 = self.canvasX, self.canvasY
  local scx, scy = self.canvasScaleX, self.canvasScaleY
  if self.crtLowResPresentation == true and self.canvasCrtShaderEnabled == true then
    local vx = self.crtViewportX or 0
    local vy = self.crtViewportY or 0
    return sx0 + (x - vx) * scx, sy0 + (y - vy) * scy, w * scx, h * scy
  end
  return sx0 + x * scx, sy0 + y * scy, w * scx, h * scy
end

--- After renderCanvas: draw CRT-filtered regions from the finished workspace canvas (samples 256x240 NES-equivalent, presents at scaled screen size).
function ResolutionController:renderCrtLensOverlays(app)
  if self.crtLensPostCanvasOverlayEnabled ~= true then
    return
  end
  if not (app and app.canvas and app.wm) then
    return
  end
  local crtShader = resolveCrtShader()
  if not crtShader then
    return
  end
  local WindowCaps = require("controllers.window.window_capabilities")
  local scratch = self:_ensureCrtLensScratchCanvas()
  if not scratch then
    return
  end

  local canvas = app.canvas
  local cw = canvas:getWidth()
  local ch = canvas:getHeight()

  local dist = self.canvasCrtFlat and 0
    or ((type(app.crtDistortionSetting) == "number") and app.crtDistortionSetting or self:getCanvasCrtDistortion() or 0.1)

  for _, win in ipairs(app.wm:getWindows()) do
    if not WindowCaps.isCrtLens(win)
      or not win._crtLensVisible
      or win._closed
      or win._minimized
      or win._groupHidden == true
    then
      goto crt_lens_continue
    end

    local sx, sy, sw, sh = win:getScreenRect()
    if sw <= 0 or sh <= 0 then
      goto crt_lens_continue
    end
    if sx >= cw or sy >= ch or sx + sw <= 0 or sy + sh <= 0 then
      goto crt_lens_continue
    end

    love.graphics.setCanvas(scratch)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    local quad = love.graphics.newQuad(sx, sy, sw, sh, cw, ch)
    love.graphics.draw(canvas, quad, 0, 0, 0, CRT_LENS_NES_W / sw, CRT_LENS_NES_H / sh)
    love.graphics.setCanvas()

    local screenX, screenY, screenW, screenH = self:workspaceRectToScreen(sx, sy, sw, sh)

    crtShader:send("inputSize", { CRT_LENS_NES_W, CRT_LENS_NES_H })
    crtShader:send("textureSize", { CRT_LENS_NES_W, CRT_LENS_NES_H })
    crtShader:send("outputSize", { screenW, screenH })
    crtShader:send("distortion", dist)

    love.graphics.setShader(crtShader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(scratch, screenX, screenY, 0, screenW / CRT_LENS_NES_W, screenH / CRT_LENS_NES_H)
    love.graphics.setShader()

    ::crt_lens_continue::
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function ResolutionController:setCanvasCrtShaderEnabled(enabled)
  self.canvasCrtShaderEnabled = (enabled == true)
end

function ResolutionController:setCanvasCrtFilterKind(kind)
  self.canvasCrtFilterKind = (kind == "composite") and "composite" or "crt"
end

function ResolutionController:isCanvasCrtShaderEnabled()
  return self.canvasCrtShaderEnabled == true
end

function ResolutionController:setCanvasCrtFlat(flat)
  self.canvasCrtFlat = (flat == true)
end

function ResolutionController:setCanvasCrtDistortion(value)
  local n = tonumber(value)
  if not n then
    return false
  end
  n = math.max(0, math.min(0.45, n))
  self.canvasCrtDistortion = n
  return true
end

function ResolutionController:getCanvasCrtDistortion()
  return tonumber(self.canvasCrtDistortion) or 0.1
end

function ResolutionController:getScaledMouse(asInteger, touchX, touchY)
  local x, y = love.mouse.getPosition()

  if touchX and touchY then
    x, y = touchX, touchY
  end

  local lx = (x - self.canvasX) / self.canvasScaleX
  local ly = (y - self.canvasY) / self.canvasScaleY

  if self.crtLowResPresentation and self.canvasCrtShaderEnabled then
    lx = (self.crtViewportX or 0) + lx
    ly = (self.crtViewportY or 0) + ly
  end

  if asInteger then
    return {
      x = math.floor(lx),
      y = math.floor(ly),
    }
  end

  return {
    x = lx,
    y = ly,
  }
end

return ResolutionController
