-- Cached offscreen canvas for tile layers on static_art / animation windows (see ppu nametable canvas).

local WindowCaps = require("controllers.window.window_capabilities")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local CanvasSpace = require("utils.canvas_space")
local colors = require("app_colors")

local function shouldUseTileLayerCanvas(win)
  if not win then
    return false
  end
  if WindowCaps.isPpuFrame(win) or WindowCaps.isChrLike(win) then
    return false
  end
  return WindowCaps.isStaticArt(win) or WindowCaps.isAnimationLike(win)
end

local function lin(cols, col, row)
  return row * cols + col + 1
end

local function makeTileLayerCanvas(self)
  local cw = math.max(1, self.cellW or 8)
  local ch = math.max(1, self.cellH or 8)
  local w = math.max(1, (self.cols or 1) * cw)
  local h = math.max(1, (self.rows or 1) * ch)
  return love.graphics.newCanvas(w, h), w, h
end

return function(Window)
  function Window:_ensureTileLayerCanvasState(layerIndex)
    local li = layerIndex or self.activeLayer or 1
    self._tileLayerCanvas = self._tileLayerCanvas or {}
    local state = self._tileLayerCanvas[li]
    local cw = math.max(1, self.cellW or 8)
    local ch = math.max(1, self.cellH or 8)
    local expectedW = math.max(1, (self.cols or 1) * cw)
    local expectedH = math.max(1, (self.rows or 1) * ch)

    if not state then
      local canvas, w, h = makeTileLayerCanvas(self)
      state = {
        canvas = canvas,
        width = w,
        height = h,
        dirtyAll = true,
        dirtyCells = {},
      }
      self._tileLayerCanvas[li] = state
      return state, li
    end

    if not state.canvas or state.width ~= expectedW or state.height ~= expectedH then
      local canvas, w, h = makeTileLayerCanvas(self)
      state.canvas = canvas
      state.width = w
      state.height = h
      state.dirtyAll = true
      state.dirtyCells = {}
    end

    return state, li
  end

  function Window:invalidateTileLayerCanvas(layerIndex, col, row)
    if not shouldUseTileLayerCanvas(self) then
      return false
    end
    local layer = self:getLayer(layerIndex)
    if not (layer and layer.kind == "tile") then
      return false
    end

    local state = select(1, self:_ensureTileLayerCanvasState(layerIndex))
    if not state then
      return false
    end

    if col == nil or row == nil then
      state.dirtyAll = true
      state.dirtyCells = {}
      return true
    end

    local cols = self.cols or 1
    local idx = lin(cols, col, row)
    state.dirtyCells = state.dirtyCells or {}
    state.dirtyCells[idx] = true
    return true
  end

  function Window:invalidateAllTileLayerCanvases()
    if not shouldUseTileLayerCanvas(self) then
      return
    end
    for li, L in ipairs(self.layers or {}) do
      if L and L.kind == "tile" then
        self:invalidateTileLayerCanvas(li)
      end
    end
  end

  function Window:_drawTileStackItemForCanvas(app, layer, item, x, y, idx0, li)
    if not (item and item.draw) then
      return
    end

    love.graphics.setColor(colors.white)

    local isPalWindow = WindowCaps.isGlobalPaletteWindow(self)
    if not isPalWindow then
      local overridePalNum = nil
      if layer and layer.paletteNumbers then
        overridePalNum = layer.paletteNumbers[idx0]
      end

      local layerOpacityOverride = (layer and layer.opacity ~= nil) and layer.opacity or nil

      ShaderPaletteController.applyLayerItemPalette(
        layer,
        item,
        li == self.activeLayer,
        app and app.appEditState and app.appEditState.romRaw,
        overridePalNum,
        layerOpacityOverride
      )
    end

    item:draw(x, y, 1)

    if not isPalWindow then
      ShaderPaletteController.releaseShader()
    end
  end

  function Window:_paintTileLayerCellToCanvas(app, layer, li, idx1)
    if not layer then
      return
    end

    local cols = self.cols or 1
    local cw = self.cellW or 8
    local ch = self.cellH or 8
    local z = idx1 - 1
    local col = z % cols
    local row = math.floor(z / cols)
    local x = col * cw
    local y = row * ch

    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(0, 0, 0, 0)
    love.graphics.rectangle("fill", x, y, cw, ch)
    love.graphics.setBlendMode("alpha", "alphamultiply")

    local removedCells = self:getRemovedCells(li)
    if removedCells and removedCells[idx1] then
      love.graphics.setColor(colors.white)
      return
    end

    local idx0 = row * cols + col
    local stack = self:getStack(col, row, li)
    if stack and #stack > 0 then
      for i = 1, #stack do
        self:_drawTileStackItemForCanvas(app, layer, stack[i], x, y, idx0, li)
      end
    end

    love.graphics.setColor(colors.white)
  end

  function Window:_repaintTileLayerCanvas(app, layerIndex)
    local state, li = self:_ensureTileLayerCanvasState(layerIndex)
    local layer = self:getLayer(li)
    if not (state and layer and layer.kind == "tile" and state.canvas) then
      return false
    end

    local dirtyCells = state.dirtyCells or {}
    local hasDirtyCells = next(dirtyCells) ~= nil
    local repaintAll = state.dirtyAll == true or not hasDirtyCells

    love.graphics.push("all")
    love.graphics.setCanvas(state.canvas)
    if repaintAll then
      love.graphics.clear(0, 0, 0, 0)
      local maxCells = math.max(0, (self.cols or 1) * (self.rows or 1))
      for idx1 = 1, maxCells do
        self:_paintTileLayerCellToCanvas(app, layer, li, idx1)
      end
    else
      for idx1 in pairs(dirtyCells) do
        self:_paintTileLayerCellToCanvas(app, layer, li, idx1)
      end
    end
    love.graphics.setCanvas()
    love.graphics.pop()
    love.graphics.setScissor()
    love.graphics.setColor(colors.white)
    ShaderPaletteController.releaseShader()

    state.dirtyAll = false
    state.dirtyCells = {}
    return true
  end

  --- Returns true when the cached path drew the layer (caller skips per-cell grid draw).
  function Window:drawTileLayerCanvas(app, layerIndex)
    if not shouldUseTileLayerCanvas(self) then
      return false
    end

    local layer = self:getLayer(layerIndex)
    if not (layer and layer.kind == "tile") then
      return false
    end

    local layerOpacity = (layer.opacity ~= nil) and layer.opacity or 1.0
    if layerOpacity <= 0.001 then
      return false
    end

    local state, li = self:_ensureTileLayerCanvasState(layerIndex)
    if not (state and state.canvas) then
      return false
    end

    if state.dirtyAll or (state.dirtyCells and next(state.dirtyCells) ~= nil) then
      self:_repaintTileLayerCanvas(app, li)
    end

    local sx, sy, sw, sh = self:getScreenRect()
    local z = (self.getZoomLevel and self:getZoomLevel()) or self.zoom or 1
    local cw, ch = self.cellW or 8, self.cellH or 8

    love.graphics.push()
    love.graphics.translate(self.x, self.y)
    love.graphics.scale(z, z)
    CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)
    love.graphics.translate(-(self.scrollCol or 0) * cw, -(self.scrollRow or 0) * ch)
    love.graphics.setColor(1, 1, 1, layerOpacity)
    love.graphics.draw(state.canvas, 0, 0)

    love.graphics.pop()
    love.graphics.setScissor()
    love.graphics.setColor(colors.white)
    return true
  end
end
