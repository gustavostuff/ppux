-- Per-cell nametable canvas cache for PPU frame windows.

local NametableHelpers = require("user_interface.windows_system.ppu_frame_nametable_helpers")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local CanvasSpace = require("utils.canvas_space")
local colors = require("app_colors")

local lin = NametableHelpers.lin
local getNametableLayer = NametableHelpers.getNametableLayer
local getCurrentRomRaw = NametableHelpers.getCurrentRomRaw
local decodePaletteNumberFromAttributes = NametableHelpers.decodePaletteNumberFromAttributes
local getPaletteLayerForRender = NametableHelpers.getPaletteLayerForRender

local function makeNametableCanvas(self)
  local w = math.max(1, (self.cols or 32) * (self.cellW or 8))
  local h = math.max(1, (self.rows or 30) * (self.cellH or 8))
  local canvas = love.graphics.newCanvas(w, h)
  canvas:setFilter("nearest", "nearest")
  return canvas, w, h
end

return function(PPUFrameWindow)
  function PPUFrameWindow:_ensureNametableLayerCanvasState(layerIndex)
    local li = layerIndex or select(2, getNametableLayer(self)) or self.activeLayer or 1
    self._nametableLayerCanvas = self._nametableLayerCanvas or {}
    local state = self._nametableLayerCanvas[li]
    local expectedW = math.max(1, (self.cols or 32) * (self.cellW or 8))
    local expectedH = math.max(1, (self.rows or 30) * (self.cellH or 8))

    if not state then
      local canvas, cw, ch = makeNametableCanvas(self)
      state = {
        canvas = canvas,
        width = cw,
        height = ch,
        dirtyAll = true,
        dirtyCells = {},
      }
      self._nametableLayerCanvas[li] = state
      return state, li
    end

    if not state.canvas or state.width ~= expectedW or state.height ~= expectedH then
      local canvas, cw, ch = makeNametableCanvas(self)
      state.canvas = canvas
      state.width = cw
      state.height = ch
      state.dirtyAll = true
      state.dirtyCells = {}
    end

    return state, li
  end

  function PPUFrameWindow:invalidateNametableLayerCanvas(layerIndex, col, row)
    local state, li = self:_ensureNametableLayerCanvasState(layerIndex)
    if not state then
      return false
    end

    if col == nil or row == nil then
      state.dirtyAll = true
      state.dirtyCells = {}
      return true
    end

    local idx = lin(self.cols or 32, col, row)
    state.dirtyCells = state.dirtyCells or {}
    state.dirtyCells[idx] = true
    return true
  end

  function PPUFrameWindow:_paintNametableCellToCanvas(layer, idx)
    if not layer or not idx then
      return
    end

    local cols = self.cols or 32
    local col = (idx - 1) % cols
    local row = math.floor((idx - 1) / cols)
    local x = col * (self.cellW or 8)
    local y = row * (self.cellH or 8)
    local w = self.cellW or 8
    local h = self.cellH or 8
    local item = layer.items and layer.items[idx] or nil
    local paletteNum = layer.paletteNumbers and layer.paletteNumbers[(row * cols) + col] or nil
    if paletteNum == nil then
      paletteNum = decodePaletteNumberFromAttributes(self, col, row)
    end
    local paletteLayer = getPaletteLayerForRender(self, layer)

    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(0, 0, 0, 0)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setBlendMode("alpha", "alphamultiply")

    if item and item.draw then
      ShaderPaletteController.applyLayerItemPalette(
        paletteLayer,
        item,
        true,
        getCurrentRomRaw(self),
        paletteNum,
        1.0
      )
      love.graphics.setColor(colors.white)
      item:draw(x, y, 1)
      ShaderPaletteController.releaseShader()
    end
  end

  function PPUFrameWindow:_repaintNametableLayerCanvas(layerIndex)
    local state, li = self:_ensureNametableLayerCanvasState(layerIndex)
    local layer = self:getLayer(li)
    if not (state and layer and layer.kind == "tile" and state.canvas) then
      return false
    end

    local dirtyCells = state.dirtyCells or {}
    local hasDirtyCells = next(dirtyCells) ~= nil
    if state.dirtyAll ~= true and not hasDirtyCells then
      return false
    end
    local repaintAll = state.dirtyAll == true

    love.graphics.push("all")
    love.graphics.setCanvas(state.canvas)
    love.graphics.origin()
    if repaintAll then
      love.graphics.clear(0, 0, 0, 0)
      local max = math.max(0, (self.cols or 32) * (self.rows or 30))
      for idx = 1, max do
        self:_paintNametableCellToCanvas(layer, idx)
      end
    else
      for idx in pairs(dirtyCells) do
        self:_paintNametableCellToCanvas(layer, idx)
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

  function PPUFrameWindow:drawNametableLayerCanvas(layerIndex)
    local state, li = self:_ensureNametableLayerCanvasState(layerIndex)
    local layer = self:getLayer(li)
    if not (state and layer and layer.kind == "tile" and state.canvas) then
      return false
    end
    if layer.attrMode == true then
      return false
    end

    if state.dirtyAll or (state.dirtyCells and next(state.dirtyCells) ~= nil) then
      self:_repaintNametableLayerCanvas(li)
    end

    local sx, sy, sw, sh = self:getInsetContentScreenRect()
    local layerOpacity = (layer.opacity ~= nil) and layer.opacity or 1.0
    local z = self.zoom or 1
    local cw, ch = self.cellW or 8, self.cellH or 8

    love.graphics.push()
    local ox, oy = self:getContentScreenOrigin()
    love.graphics.translate(ox, oy)
    love.graphics.scale(z, z)
    CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)
    love.graphics.translate(-(self.scrollCol or 0) * cw, -(self.scrollRow or 0) * ch)
    love.graphics.setColor(1, 1, 1, layerOpacity)
    love.graphics.draw(state.canvas, 0, 0)
    local rangeHighlight = self.getHoveredPatternRangeHighlight
      and self:getHoveredPatternRangeHighlight(layer)
    if rangeHighlight and self.drawPatternRangeHoverOverlay then
      local vC0 = self.scrollCol or 0
      local vR0 = self.scrollRow or 0
      local vC1 = math.min((self.cols or 32) - 1, vC0 + (self.visibleCols or 1) - 1)
      local vR1 = math.min((self.rows or 30) - 1, vR0 + (self.visibleRows or 1) - 1)
      self:drawPatternRangeHoverOverlay(cw, ch, vC0, vR0, vC1, vR1, rangeHighlight)
    end
    love.graphics.pop()
    love.graphics.setScissor()
    love.graphics.setColor(colors.white)
    return true
  end
end
