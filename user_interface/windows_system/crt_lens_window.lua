-- CRT layer visualizer: references other windows' raster layers, CRT-shaded inside the app canvas.

local Window = require("user_interface.windows_system.window")
local ResolutionController = require("controllers.app.resolution_controller")
local CrtLayerViz = require("controllers.crt.crt_layer_viz")
local ActiveLayerStatusController = require("controllers.window.active_layer_status_controller")

local CrtLensWindow = setmetatable({}, { __index = Window })
CrtLensWindow.__index = CrtLensWindow

function CrtLensWindow.new(x, y, zoom, data)
  data = data or {}
  local cellW, cellH = 8, 8
  local cols, rows = 32, 30
  local self = Window.new(x, y, cellW, cellH, cols, rows, zoom or 1, {
    title = data.title or "CRT layer visualizer",
    resizable = false,
    visibleCols = cols,
    visibleRows = rows,
  })
  setmetatable(self, CrtLensWindow)

  self.kind = "crt_lens"
  self._runtimeOnly = true
  self.layers = {}
  self.activeLayer = 1
  self._crtLensVisible = false

  --- Each entry: { windowId, layerIndex, panX = 0, panY = 0, opacity = 1 }
  self.crtRefLayers = {}

  --- Optional barrel distortion for this viewer only (falls back to global CRT distortion).
  self.crtVizDistortion = nil

  return self
end

function CrtLensWindow:contains(px, py)
  if not self._crtLensVisible then
    return false
  end
  return Window.contains(self, px, py)
end

--- Reference-stack layer count (not self.layers).
function CrtLensWindow:getLayerCount()
  return #(self.crtRefLayers or {})
end

function CrtLensWindow:getActiveLayerIndex()
  local n = self:getLayerCount()
  if n == 0 then
    return 1
  end
  local i = self.activeLayer or 1
  return math.max(1, math.min(math.floor(i), n))
end

function CrtLensWindow:setActiveLayerIndex(i)
  local n = self:getLayerCount()
  if n == 0 then
    self.activeLayer = 1
    return
  end
  i = math.max(1, math.min(n, math.floor(i or 1)))
  if self.activeLayer ~= i then
    local oldLayer = self.activeLayer
    self.activeLayer = i
    if self.specializedToolbar and self.specializedToolbar.triggerLayerLabelFlash then
      self.specializedToolbar:triggerLayerLabelFlash()
    end
    local app = _G.ctx and _G.ctx.app
    if app and app._persistCrtLayerViz then
      app:_persistCrtLayerViz()
    end
    ActiveLayerStatusController.tryNotify(self, oldLayer, i)
  end
end

function CrtLensWindow:nextLayer()
  local n = self:getLayerCount()
  if n <= 1 then
    return
  end
  local cur = self:getActiveLayerIndex()
  self:setActiveLayerIndex((cur % n) + 1)
end

function CrtLensWindow:prevLayer()
  local n = self:getLayerCount()
  if n <= 1 then
    return
  end
  local cur = self:getActiveLayerIndex()
  self:setActiveLayerIndex(((cur - 2) % n) + 1)
end

function CrtLensWindow:_panTargetRef()
  local layers = self.crtRefLayers
  if not layers or #layers == 0 then
    return nil
  end
  local idx = self:getActiveLayerIndex()
  return layers[idx]
end

function CrtLensWindow:mousepressed(x, y, button)
  if button == 1 and self._crtLensVisible and ResolutionController.crtLensPostCanvasOverlayEnabled ~= true then
    if self:isInContentArea(x, y) and not (self.resizable and self:hitResizeHandle(x, y)) then
      local app = _G.ctx and _G.ctx.app or nil
      local wm = app and app.wm
      local ref = self:_panTargetRef()
      if app and wm and ref and CrtLayerViz.refAllowsPan(app, wm, ref) then
        self._crtPanDrag = {
          startPanX = ref.panX or 0,
          startPanY = ref.panY or 0,
          startMX = x,
          startMY = y,
        }
        return
      end
    end
  end
  Window.mousepressed(self, x, y, button)
end

function CrtLensWindow:mousemoved(mx, my, dx, dy)
  if self._crtPanDrag and love.mouse.isDown(1) then
    local app = _G.ctx and _G.ctx.app or nil
    local wm = app and app.wm
    local ref = self:_panTargetRef()
    if not (app and wm and ref) then
      Window.mousemoved(self, mx, my)
      return
    end
    local z = self.zoom or 1
    ref.panX = self._crtPanDrag.startPanX + (mx - self._crtPanDrag.startMX) / z
    ref.panY = self._crtPanDrag.startPanY + (my - self._crtPanDrag.startMY) / z
    local _, sw, sh = CrtLayerViz.resolveLayerDrawable(app, wm, ref)
    ref.panX, ref.panY = CrtLayerViz.clampPan(sw, sh, ref.panX, ref.panY)
    return
  end
  Window.mousemoved(self, mx, my)
end

function CrtLensWindow:mousereleased(x, y, button)
  if button == 1 then
    local hadPan = self._crtPanDrag ~= nil
    self._crtPanDrag = nil
    if hadPan then
      local app = _G.ctx and _G.ctx.app
      if app and app._persistCrtLayerViz then
        app:_persistCrtLayerViz()
      end
    end
  end
  Window.mousereleased(self, x, y, button)
end

return CrtLensWindow
