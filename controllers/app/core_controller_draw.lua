local ResolutionController = require("controllers.app.resolution_controller")
local DebugController = require("controllers.dev.debug_controller")
local PaletteLinkRenderController = require("controllers.palette.palette_link_render_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local BrushController = require("controllers.input_support.brush_controller")
local CursorsController = require("controllers.input_support.cursors_controller")
local GridModeUtils = require("controllers.grid_mode_utils")
local WindowCaps = require("controllers.window.window_capabilities")
local UserInput = require("controllers.input")
local Text = require("utils.text_utils")
local Timer = require("utils.timer_utils")
local Draw = require("utils.draw_utils")
local colors = require("app_colors")
local images = require("images")

local function drawEmptyStatePrompt(app)
  if app:hasLoadedROM() then return end

  Text.printCenter("Drop an NES ROM here", {
    canvas = app.canvas,
    font = app.emptyStateFont or app.font,
    shadowColor = colors.transparent,
    color = colors.gray20
  })
end

return function(AppCoreController)
-- Find the active global palette window (non-ROM) and return its first color,
-- or nil if none is available.

local function getActiveGlobalPaletteBgColor(wm)
  local paletteWin = nil
  local fallback = nil

  for _, win in ipairs(wm:getWindows()) do
    if WindowCaps.isGlobalPaletteWindow(win) and not win._closed and not win._minimized then
      if not fallback then
        fallback = win
      end
      if win.activePalette then
        paletteWin = win
        break
      end
    end
  end

  paletteWin = paletteWin or fallback
  if paletteWin and paletteWin.getFirstColor then
    return paletteWin:getFirstColor()
  end

  return nil
end

local function getActiveGlobalPaletteWindow(wm)
  local fallback = nil

  for _, win in ipairs(wm:getWindows()) do
    if WindowCaps.isGlobalPaletteWindow(win) and not win._closed and not win._minimized then
      if not fallback then
        fallback = win
      end
      if win.activePalette then
        return win
      end
    end
  end

  return fallback
end

local function getRomPaletteBgColorForWindow(win, wm)
  local layers = win.layers
  if not layers then
    return nil
  end

  -- Find the first layer with paletteData.winId
  for _, L in ipairs(layers) do
    local pd = L.paletteData
    if pd and pd.winId then
      local paletteWin = wm:findWindowById(pd.winId)
      if paletteWin and paletteWin.getFirstColor then
        local c = paletteWin:getFirstColor()
        -- getFirstColor() already returns a color table consistent with app_colors
        return c
      end
      -- We only expect one such layer, so we can stop looking
      break
    end
  end

  return nil
end

local function drawPaletteLinkOverlay(app)
  PaletteLinkRenderController.drawOverlay(app)
end

local function drawActivePaletteLinkDrag(app)
  PaletteLinkRenderController.drawActiveDrag(app)
end

local function drawPaletteLinks(app)
  drawActivePaletteLinkDrag(app)
  drawPaletteLinkOverlay(app)
end

local function renderWindowChessPattern(window, wm)
  -- Pick base BG color: window ROM palette BG -> global active BG -> black
  local bgColor = getRomPaletteBgColorForWindow(window, wm) or getActiveGlobalPaletteBgColor(wm) or colors.black
  local grid = (window.getDisplayGridMetrics and window:getDisplayGridMetrics()) or {
    cellW = window.cellW or 8,
    cellH = window.cellH or 8,
    rowStride = 1,
  }
  local rowStride = grid.rowStride or 1
  local drawH = grid.cellH + 1

  window:drawGrid(function(col, row, x, y, cw, ch)
    if rowStride > 1 and (row % rowStride) ~= 0 then
      return
    end

    love.graphics.setColor(bgColor)
    love.graphics.rectangle("fill", x, y, cw + 1, drawH)

    if ((math.floor(row / rowStride)) + col) % 2 == 0 then
      local color = colors.white
      love.graphics.setColor(color[1], color[2], color[3], 0.1)
      love.graphics.rectangle("fill", x, y, cw + 1, drawH)
    end
  end)

  love.graphics.setColor(colors.white)
end

local linesGridShader = love.graphics.newShader([[
extern vec2 u_origin;
extern vec2 u_step;
extern number u_thickness;

vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 screenCoord)
{
    float stepx = max(u_step.x, 1.0);
    float stepy = max(u_step.y, 1.0);
    float t = max(u_thickness, 1.0);
    vec2 rel = screenCoord - u_origin;
    float mx = mod(rel.x, stepx);
    float my = mod(rel.y, stepy);

    bool onLine = (mx <= t) || (stepx - mx <= t) || (my <= t) || (stepy - my <= t);
    if (!onLine) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    return Texel(tex, texCoord) * color;
}
]])

local function renderWindowLinesGrid(window)
  if not window or window._collapsed then return end
  local grid = (window.getDisplayGridMetrics and window:getDisplayGridMetrics()) or {
    baseCellW = window.cellW or 8,
    baseCellH = window.cellH or 8,
    cellW = window.cellW or 8,
    cellH = window.cellH or 8,
  }
  local zoom = window.zoom or 1
  local stepX = grid.cellW * zoom
  local stepY = grid.cellH * zoom
  if stepX <= 0 or stepY <= 0 then return end

  local x, y, w, h = window:getScreenRect()
  local thickness = 1
  local scrollOffsetX = ((window.scrollCol or 0) * (grid.baseCellW or grid.cellW) * zoom) % stepX
  local scrollOffsetY = ((window.scrollRow or 0) * (grid.baseCellH or grid.cellH) * zoom) % stepY

  love.graphics.push("all")
  love.graphics.setShader(linesGridShader)
  linesGridShader:send("u_origin", { x - scrollOffsetX, y - scrollOffsetY })
  linesGridShader:send("u_step", { stepX, stepY })
  linesGridShader:send("u_thickness", thickness)
  local c = colors.gray50
  love.graphics.setColor(c[1], c[2], c[3], 0.5)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.pop()
end

-- Helper to decode palette number from PPU attribute bytes for a given tile position
local function getPaletteFromAttrBytes(attrBytes, cols, tileCol, tileRow)
  if not attrBytes or #attrBytes == 0 then return nil end
  
  -- Each attribute byte covers a 4x4 tile area
  local attrCols = math.floor(cols / 4)  -- typically 8 for 32 cols
  
  -- Which attribute byte covers this tile?
  local attrCol = math.floor(tileCol / 4)
  local attrRow = math.floor(tileRow / 4)
  local attrIndex = attrRow * attrCols + attrCol + 1  -- 1-based index
  
  if attrIndex < 1 or attrIndex > #attrBytes then return nil end
  
  local attrByte = attrBytes[attrIndex] or 0
  
  -- Determine which quadrant of the 4x4 area this tile is in
  local localCol = tileCol % 4  -- 0-3
  local localRow = tileRow % 4  -- 0-3
  
  local quadrant
  if localRow < 2 then
    -- Top half
    if localCol < 2 then
      quadrant = "topLeft"      -- bits 0-1
    else
      quadrant = "topRight"     -- bits 2-3
    end
  else
    -- Bottom half
    if localCol < 2 then
      quadrant = "bottomLeft"   -- bits 4-5
    else
      quadrant = "bottomRight"  -- bits 6-7
    end
  end
  
  -- Extract palette index (0-3) from the attribute byte
  local palIndex = 0
  if quadrant == "topLeft" then
    palIndex = attrByte % 4
  elseif quadrant == "topRight" then
    palIndex = math.floor((attrByte % 16) / 4)
  elseif quadrant == "bottomLeft" then
    palIndex = math.floor((attrByte % 64) / 16)
  else -- bottomRight
    palIndex = math.floor(attrByte / 64)
  end
  
  -- Convert 0-based palette index to 1-based palette number (1-4)
  return palIndex + 1
end

-- Draw attribute mode visualization for PPU frame windows
-- Shows colored squares based on attribute bytes where each 2x2 quadrant shares a palette
local function drawTileInAttrMode(app, w, layer, col, row, x, y, cw, ch, layerOpacity)
  if not (w.nametableAttrBytes and layer) then
    return false
  end

  local palNum = getPaletteFromAttrBytes(w.nametableAttrBytes, w.cols, col, row)
  if not palNum then
    return false
  end

  -- Get all 4 RGB colors from the palette
  local paletteColors = ShaderPaletteController.getPaletteColors(
    layer,
    palNum,
    app.appEditState and app.appEditState.romRaw
  )
  
  if not paletteColors then
    return false
  end

  -- Determine position within the 2x2 quadrant that shares this palette
  -- The 4x4 attribute area is divided into 4 quadrants of 2x2 tiles each
  local localColIn4x4 = col % 4  -- 0-3
  local localRowIn4x4 = row % 4  -- 0-3
  
  -- Position within the 2x2 quadrant (0-1 for both)
  local posInQuadX = localColIn4x4 % 2  -- 0 or 1
  local posInQuadY = localRowIn4x4 % 2  -- 0 or 1
  
  -- Color index within the palette (1-4)
  -- Top-left (0,0): 1, Top-right (1,0): 2, Bottom-left (0,1): 3, Bottom-right (1,1): 4
  local colorIndex = posInQuadY * 2 + posInQuadX + 1
  
  -- Get the RGB color for this position
  local rgb = paletteColors[colorIndex]
  if rgb then
    love.graphics.setColor(rgb[1] or 0, rgb[2] or 0, rgb[3] or 0, layerOpacity or 1.0)
    love.graphics.rectangle("fill", x, y, cw - 1, ch - 1)
    love.graphics.setColor(colors.white)
    return true
  end

  return false
end

-- Draw a single tile item with palette application
local function drawTileStackItem(app, w, layer, item, col, row, x, y, idx, li, isPalWindow, layerOpacity)
  if not (item and item.draw) then
    return
  end

  love.graphics.setColor(colors.white)

  if not isPalWindow then
    local overridePalNum = nil
    if layer and layer.paletteNumbers then
      overridePalNum = layer.paletteNumbers[idx]
    end

    local layerOpacityOverride = (layer and layer.opacity ~= nil) and layer.opacity or nil

    ShaderPaletteController.applyLayerItemPalette(
      layer,
      item,
      li == w.activeLayer,
      app.appEditState and app.appEditState.romRaw,
      overridePalNum,
      layerOpacityOverride
    )
  end

  -- Draw the tile itself
  item:draw(x, y, 1)

  if not isPalWindow then
    -- Turn off palette shader before drawing debug text
    ShaderPaletteController.releaseShader()
  end

  ----------------------------------------------------------------
  -- DEBUG: show paletteNumber (1–4) over each tile if present
  ----------------------------------------------------------------
  -- if layer and layer.paletteNumbers then
  --   local palNum = layer.paletteNumbers[idx]
  --   if palNum ~= nil then
  --     -- Small white number with black outline for readability
  --     Text.print(
  --       tostring(palNum),
  --       x + 1,
  --       y + 1,
  --       { outline = true }
  --     )
  --   end
  -- end
  ----------------------------------------------------------------
end

local function drawTileLayerCell(app, w, layer, col, row, x, y, cw, ch, idx, li, isPalWindow, layerOpacity, item)
  local isPPUFrame = WindowCaps.isPpuFrame(w)
  local attrMode = isPPUFrame and layer and layer.attrMode == true

  if attrMode then
    if drawTileInAttrMode(app, w, layer, col, row, x, y, cw, ch, layerOpacity) then
      return
    end
  end

  if item ~= nil then
    drawTileStackItem(app, w, layer, item, col, row, x, y, idx, li, isPalWindow, layerOpacity)
    love.graphics.setColor(colors.white)
    return
  end

  local stack = w:getStack(col, row, li)
  if stack and #stack > 0 then
    for i = 1, #stack do
      drawTileStackItem(app, w, layer, stack[i], col, row, x, y, idx, li, isPalWindow, layerOpacity)
    end
    love.graphics.setColor(colors.white)
  end
end

local function drawTileLayer(app, w, layerIndex, isFocused)
  local isPalWindow = WindowCaps.isGlobalPaletteWindow(w)
  local isPPUFrame = WindowCaps.isPpuFrame(w)
  local layer = w.layers and w.layers[layerIndex]
  local attrMode = isPPUFrame and layer and layer.attrMode == true

  if isPPUFrame and not attrMode and w.drawVisibleNametableCells then
    local handled = w:drawVisibleNametableCells(function(col, row, x, y, cw, ch, li, layerOpacity, item, zeroBasedIdx)
      drawTileLayerCell(app, w, layer, col, row, x, y, cw, ch, zeroBasedIdx, li, isPalWindow, layerOpacity, item)
    end, layerIndex)
    if handled then
      return
    end
  end

  w:drawGrid(function(col, row, x, y, cw, ch, li, layerOpacity)
    local idx = row * w.cols + col
    local currentLayer = w.layers and w.layers[li]
    drawTileLayerCell(app, w, currentLayer, col, row, x, y, cw, ch, idx, li, isPalWindow, layerOpacity)
  end, isFocused, layerIndex)
end

local function drawCanvasLayer(app, w, layerIndex, isFocused)
  local layer = w.layers and w.layers[layerIndex]
  local canvas = layer and layer.canvas or nil
  if not canvas then
    return false
  end

  local layerOpacity = (layer and layer.opacity ~= nil) and layer.opacity or 1.0
  local sx, sy, sw, sh = w:getScreenRect()

  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  local z = (w.getZoomLevel and w:getZoomLevel()) or w.zoom or 1
  love.graphics.scale(z, z)
  love.graphics.setScissor(sx, sy, sw, sh)

  ShaderPaletteController.applyLayerItemPalette(
    layer,
    canvas,
    true,
    app.appEditState and app.appEditState.romRaw,
    nil,
    layerOpacity
  )
  canvas:draw(0, 0, 1)
  ShaderPaletteController.releaseShader()

  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.setColor(colors.white)
  return true
end

local function drawChrBankLayer(app, w, layerIndex)
  local controller = app and app.chrBankCanvasController
  if not controller then
    return false
  end

  local layer = w.layers and w.layers[layerIndex]
  local layerOpacity = (layer and layer.opacity ~= nil) and layer.opacity or 1.0
  if layerOpacity <= 0.001 then
    return true
  end

  ShaderPaletteController.applyShader(true, layer, nil, layerOpacity)
  local ok = controller:drawWindow(app.appEditState, w, layerOpacity)
  ShaderPaletteController.releaseShader()
  return ok
end

local function isAnimationKind(win)
  return WindowCaps.isAnimationLike(win)
end

local function drawWindows(app)
  local wm = app.wm

  for _, w in ipairs(wm:getWindows()) do
    -- Skip closed windows
    if w._closed or w._minimized then
      goto continue
    end

    PaletteLinkRenderController.drawSourcePaletteProxyForWindow(app, w)

    local isFocused   = (w == wm:getFocus())
    local isCollapsed = w._collapsed or false

    -- If collapsed, only draw header and toolbars
    if isCollapsed then
      -- Draw header
      w:drawHeader(isFocused)
      -- Draw header toolbar (inside header)
      if w.headerToolbar then
        w.headerToolbar:draw()
      end
      goto continue
    end

    -- Background priority:
    -- 1) ROM-linked palette color (per-window)
    -- 2) Active global palette BG color
    -- 3) Plain black
    local bgColor = getRomPaletteBgColorForWindow(w, wm) or getActiveGlobalPaletteBgColor(wm) or colors.black
    local x, y, ww, wh = w:getScreenRect()
    love.graphics.setColor(bgColor)
    love.graphics.rectangle("fill", x, y, ww, wh)
    love.graphics.setColor(colors.white)

    ----------------------------------------------------------------
    -- Content drawing
    ----------------------------------------------------------------
    local isPaletteWindow = WindowCaps.isAnyPaletteWindow(w)

    if isPaletteWindow then
      -- Palette windows (global + ROM) draw their own grids
      if w.drawGrid then
        w:drawGrid()
      end
    elseif WindowCaps.isChrLike(w) and drawChrBankLayer(app, w, w:getActiveLayerIndex() or 1) then
      -- CHR / ROM windows use the bank-canvas fast path.
    else
      -- Normal windows: draw tile/sprite layers
      local layers = w.layers or {}
      local drawOrder
      local gridMode = GridModeUtils.normalize(w.showGrid)
      w.showGrid = gridMode

      if gridMode == "chess" then
        renderWindowChessPattern(w, wm)
      end
      
      if w.drawOnlyActiveLayer == true then
        local activeIdx = w:getActiveLayerIndex() or w.activeLayer or 1
        drawOrder = { activeIdx }
      elseif isAnimationKind(w) then
        -- Draw non-active layers first, then active layer last
        local activeIdx = w:getActiveLayerIndex() or w.activeLayer or 1
        drawOrder = {}
        for li = 1, #layers do
          if li ~= activeIdx then table.insert(drawOrder, li) end
        end
        table.insert(drawOrder, activeIdx)
      else
        drawOrder = {}
        for li = 1, #layers do table.insert(drawOrder, li) end
      end

      for _, li in ipairs(drawOrder) do
        local L = layers[li]
        if L then
          -- Skip layers with opacity 0 (for animation windows, only visible layers are drawn)
          local layerOpacity = (L.opacity ~= nil) and L.opacity or 1.0
          if layerOpacity > 0.001 then
            if L.kind == "sprite" then
              w:drawSprites(nil, isFocused, li, app.appEditState.romRaw)
            elseif L.kind == "canvas" then
              drawCanvasLayer(app, w, li, isFocused)
            else
              drawTileLayer(app, w, li, isFocused)
            end
          end
        end
      end

      if gridMode == "lines" then
        renderWindowLinesGrid(w)
      end
    end

    ----------------------------------------------------------------
    -- Common window chrome
    ----------------------------------------------------------------
    w:drawResizeHandle(isFocused, ResolutionController:getScaledMouse(true))
    w:drawScrollBars(isFocused)
    -- w:drawGridLines()

    if w.drawSelectionOverlays then
      w:drawSelectionOverlays(isFocused)
    end
    -- Draw active sprite marquee (multi-select) if it belongs to this window
    local marquee = SpriteController.getSpriteMarquee()
    if marquee and marquee.win == w then
      local x1, y1 = marquee.startX, marquee.startY
      local x2, y2 = marquee.currentX, marquee.currentY
      local rx = math.min(x1, x2)
      local ry = math.min(y1, y2)
      local rw = math.abs(x2 - x1)
      local rh = math.abs(y2 - y1)
      love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 0.2)
      love.graphics.rectangle("fill", rx, ry, rw, rh)
      love.graphics.setColor(colors.white)
      love.graphics.rectangle("line", rx, ry, rw, rh)
    end
    local tileMarquee = UserInput.getTileMarquee and UserInput.getTileMarquee()
    if tileMarquee and tileMarquee.win == w then
      local x1, y1 = tileMarquee.startX, tileMarquee.startY
      local x2, y2 = tileMarquee.currentX, tileMarquee.currentY
      local rx = math.min(x1, x2)
      local ry = math.min(y1, y2)
      local rw = math.abs(x2 - x1)
      local rh = math.abs(y2 - y1)
      love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 0.2)
      love.graphics.rectangle("fill", rx, ry, rw, rh)
      love.graphics.setColor(colors.white)
      love.graphics.rectangle("line", rx, ry, rw, rh)
    end

    -- Draw layer label in content area (before border)
    w:drawLayerLabelInContent(isFocused)

    w:drawBorder(isFocused)

    -- Draw specialized toolbar first (above header, left side)
    if w.specializedToolbar then
      w.specializedToolbar:draw()
    end

    -- Draw header
    w:drawHeader(isFocused)

    -- Draw header toolbar (inside header, right side)
    if w.headerToolbar then
      w.headerToolbar:draw()
    end

    -- draw grid with vertical and horizontal lines
    -- if w.showGrid and not isPaletteWindow then
    --   w:drawLinesGrid()
    -- end

    ::continue::
  end
end

-- Cached 1x1 image for pixel brush indicator (grayscale values encoding palette indices 0-3)
local pixelBrushImages = {}
local BRUSH_PREVIEW_SELECTION_RECT_ANIM = {
  stepPx = 1,
  intervalSeconds = 0.1,
}

local function drawBrushPreviewSelectionRect(x, y, size)
  local pad = 1
  local sx = math.floor(x) - pad
  local sy = math.floor(y) - pad
  local sw = size + (pad * 2)
  local sh = size + (pad * 2)
  if images and images.pattern_a then
    local c = colors.white
    love.graphics.setColor(c[1], c[2], c[3], 0.5)
    Draw.drawRepeatingImageAnimated(
      images.pattern_a,
      sx,
      sy,
      sw,
      sh,
      BRUSH_PREVIEW_SELECTION_RECT_ANIM
    )
    return
  end
  love.graphics.rectangle("line", sx, sy, sw, sh)
end

local function getPixelBrushImage(colorIndex)
  if not pixelBrushImages[colorIndex] then
    -- Create 1x1 image with grayscale value encoding the palette index
    -- Shader expects: 0, 1/3, 2/3, 1 for indices 0, 1, 2, 3
    local imgData = love.image.newImageData(1, 1)
    local gray = colorIndex / 3.0
    imgData:setPixel(0, 0, gray, gray, gray, 1)
    pixelBrushImages[colorIndex] = love.graphics.newImage(imgData)
    pixelBrushImages[colorIndex]:setFilter("nearest", "nearest")
  end
  return pixelBrushImages[colorIndex]
end

local function resolveTransparentPreviewColor(app, win, layer, paletteNum, romRaw)
  if layer and paletteNum then
    local paletteColors = ShaderPaletteController.getPaletteColors(layer, paletteNum, romRaw)
    if paletteColors and paletteColors[1] then
      return paletteColors[1]
    end
  end

  local wm = app and app.wm
  return getRomPaletteBgColorForWindow(win, wm)
    or (wm and getActiveGlobalPaletteBgColor(wm))
    or colors.black
end

local function drawPatternBuilderRectPreview(win, startX, startY, endX, endY, zoom, color)
  local minX = math.min(math.floor(startX or 0), math.floor(endX or 0))
  local maxX = math.max(math.floor(startX or 0), math.floor(endX or 0))
  local minY = math.min(math.floor(startY or 0), math.floor(endY or 0))
  local maxY = math.max(math.floor(startY or 0), math.floor(endY or 0))

  local sx = win.x + minX * zoom
  local sy = win.y + minY * zoom
  local sw = (maxX - minX + 1) * zoom
  local sh = (maxY - minY + 1) * zoom

  love.graphics.setColor(color[1] or 1, color[2] or 1, color[3] or 1, 0.35)
  love.graphics.rectangle("fill", sx, sy, sw, sh)
  love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 0.85)
  love.graphics.rectangle("line", sx, sy, sw, sh)
  love.graphics.setColor(colors.white)
end

local function drawPatternBuilderPointPreview(win, brushScreenPoints, colorIndex, layer, hoveredItem, romRaw, paletteNum, backgroundColor)
  if colorIndex == 0 then
    love.graphics.setColor(backgroundColor[1] or 0, backgroundColor[2] or 0, backgroundColor[3] or 0, 1)
    for _, pt in ipairs(brushScreenPoints) do
      love.graphics.rectangle("fill", pt.x, pt.y, pt.size, pt.size)
    end
    love.graphics.setColor(colors.white)
    return
  end

  if layer and hoveredItem then
    local layerOpacity = (layer.opacity ~= nil) and layer.opacity or 1.0
    ShaderPaletteController.applyLayerItemPalette(
      layer,
      hoveredItem,
      true,
      romRaw,
      paletteNum,
      layerOpacity
    )
  elseif layer and paletteNum then
    local layerOpacity = (layer.opacity ~= nil) and layer.opacity or 1.0
    local codes = ShaderPaletteController.resolveLayerPaletteCodes(layer, paletteNum, romRaw)
    ShaderPaletteController.applyShader(true, layer, codes, layerOpacity)
  else
    ShaderPaletteController.applyShader(true)
  end

  local brushImg = getPixelBrushImage(colorIndex)
  for _, pt in ipairs(brushScreenPoints) do
    love.graphics.draw(brushImg, pt.x, pt.y, 0, pt.size, pt.size)
  end
  ShaderPaletteController.releaseShader()
  love.graphics.setColor(colors.white)
end

local function tryDrawGenericEditShapePreview(app, win, layer, hoveredItem, romRaw, paletteNum, colorIndex, mouse, zoom)
  if not (app and app.mode == "edit" and win and layer) then
    return false
  end

  local BrushController = require("controllers.input_support.brush_controller")
  local ok, col, row, lx, ly = win:toGridCoords(mouse.x, mouse.y)
  if not ok then
    return false
  end

  local pixelX = col * (win.cellW or 8) + math.floor(lx or 0)
  local pixelY = row * (win.cellH or 8) + math.floor(ly or 0)
  local bgPreviewColor = resolveTransparentPreviewColor(app, win, layer, paletteNum, romRaw)

  if win.editShapeDrag
    and (win.editShapeDrag.kind == "rect_or_line" or win.editShapeDrag.kind == "rect_fill")
    and win.editShapeDrag.moved then
    local shape = win.editShapeDrag
    drawPatternBuilderRectPreview(
      win,
      shape.startX,
      shape.startY,
      shape.currentX or shape.startX,
      shape.currentY or shape.startY,
      zoom,
      (colorIndex == 0) and bgPreviewColor or colors.white
    )
    return true
  end

  if app.editTool == "rect_fill" then
    return false
  end

  local shiftDown = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  if shiftDown and win.editLastPoint then
    local points = BrushController.getLinePoints(win.editLastPoint.x, win.editLastPoint.y, pixelX, pixelY)
    local pattern = BrushController.getBrushPattern(app.brushSize or 1) or {{0, 0}}
    local previewPoints = {}
    local seen = {}

    for _, p in ipairs(points) do
      for _, offset in ipairs(pattern) do
        local px = p.x + offset[1]
        local py = p.y + offset[2]
        if px >= 0 and py >= 0 then
          local key = string.format("%d:%d", px, py)
          if not seen[key] then
            seen[key] = true
            previewPoints[#previewPoints + 1] = {
              x = win.x + px * zoom,
              y = win.y + py * zoom,
              size = zoom,
            }
          end
        end
      end
    end

    drawPatternBuilderPointPreview(win, previewPoints, colorIndex, layer, hoveredItem, romRaw, paletteNum, bgPreviewColor)
    love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 0.9)
    love.graphics.rectangle("line", win.x + win.editLastPoint.x * zoom, win.y + win.editLastPoint.y * zoom, zoom, zoom)
    love.graphics.setColor(colors.white)
    return true
  end

  return false
end

local function drawEditModeColorIndicator(app)
  if app.mode ~= "edit" then return end
  
  local mouse = ResolutionController:getScaledMouse(true)
  if app.wm and app.wm.focusedResizeHandleAt and app.wm:focusedResizeHandleAt(mouse.x, mouse.y) then
    return
  end
  local win = app.wm:windowAt(mouse.x, mouse.y)
  
  -- Only show inside window content area (not header, not outside window)
  if not win or win.isPalette or win:isInHeader(mouse.x, mouse.y) then
    return
  end
  
  -- Get window properties for pixel snapping and scaling
  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local cw = win.cellW or 8
  local ch = win.cellH or 8
  local scol = win.scrollCol or 0
  local srow = win.scrollRow or 0

  local li = win:getActiveLayerIndex()
  local layer = win.layers and win.layers[li]
  if not layer then
    return
  end

  local hoveredItem = nil
  local paletteNum = nil
  if layer.kind == "sprite" then
    local SpriteController = require("controllers.sprite.sprite_controller")
    if not (SpriteController and SpriteController.pickSpriteAt) then
      return
    end
    local pickedLayer, itemIndex = SpriteController.pickSpriteAt(win, mouse.x, mouse.y, li)
    if pickedLayer == nil or itemIndex == nil then
      return
    end
    hoveredItem = layer.items and layer.items[itemIndex] or nil
    paletteNum = hoveredItem and hoveredItem.paletteNumber or nil
  elseif layer.kind == "tile" then
    local ok, col, row = win:toGridCoords(mouse.x, mouse.y)
    if not ok then
      return
    end

    if layer.removedCells and win.cols then
      local idx = (row * win.cols + col) + 1
      if layer.removedCells[idx] then
        return
      end
    end

    hoveredItem = (win.getVirtualTileHandle and win:getVirtualTileHandle(col, row, li))
      or (win.get and win:get(col, row, li))
    if layer.paletteNumbers and win.cols then
      local idx = row * win.cols + col
      paletteNum = layer.paletteNumbers[idx]
    elseif WindowCaps.isPpuFrame(win) and win.nametableAttrBytes and win.cols then
      paletteNum = getPaletteFromAttrBytes(win.nametableAttrBytes, win.cols, col, row)
    end
  elseif layer.kind == "canvas" and layer.canvas then
    hoveredItem = layer.canvas
    cw = 1
    ch = 1
    scol = 0
    srow = 0
  else
    return
  end
  
  -- Convert mouse to window content coordinates and snap to pixel grid
  local cx = (mouse.x - win.x) / z
  local cy = (mouse.y - win.y) / z
  local pixelX = math.floor(cx + scol * cw)
  local pixelY = math.floor(cy + srow * ch)
  
  -- Convert back to screen coordinates for drawing
  local screenX = win.x + ((pixelX - scol * cw) * z)
  local screenY = win.y + ((pixelY - srow * ch) * z)
  
  local romRaw = app.appEditState and app.appEditState.romRaw
  local colorIndex = app.currentColor or 0
  local brushSize = app.brushSize or 1

  if tryDrawGenericEditShapePreview(app, win, layer, hoveredItem, romRaw, paletteNum, colorIndex, mouse, z) then
    return
  end

  if layer.kind == "tile" and not hoveredItem then
    return
  end
  
  -- Get brush pattern from BrushController
  local BrushController = require("controllers.input_support.brush_controller")
  local pattern = BrushController.getBrushPattern(brushSize) or {{0, 0}}
  local brushScreenPoints = {}
  for _, offset in ipairs(pattern) do
    local dx, dy = offset[1], offset[2]
    brushScreenPoints[#brushScreenPoints + 1] = {
      x = math.floor(screenX + dx * z),
      y = math.floor(screenY + dy * z),
    }
  end
  
  -- Draw each pixel in the brush pattern
  love.graphics.setColor(colors.white)
  -- show brush only in edit mode and when normal edit mode is set
  local shiftDown = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  local ctrlDown = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
  local fillDown = love.keyboard.isDown("f")
  local grabDown = love.keyboard.isDown("g")
  local altDown = love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt")
  local nothingDown = not shiftDown and not ctrlDown and not altDown and not fillDown and not grabDown
  local showBrushPixels = (ctrlDown and altDown) or nothingDown

  if not showBrushPixels then
    ShaderPaletteController.releaseShader()
    love.graphics.setColor(colors.white)
    return
  end

  -- Draw selection-style rectangles behind each brush pixel preview.
  ShaderPaletteController.releaseShader()
  -- love.graphics.setColor(colors.white)
  -- for _, pt in ipairs(brushScreenPoints) do
  --   drawBrushPreviewSelectionRect(pt.x, pt.y, z)
  -- end

  love.graphics.setColor(colors.white)
  if colorIndex == 0 then
  local bgPreviewColor = resolveTransparentPreviewColor(app, win, layer, paletteNum, romRaw)
    ShaderPaletteController.releaseShader()
    love.graphics.setColor(bgPreviewColor[1] or 0, bgPreviewColor[2] or 0, bgPreviewColor[3] or 0, 1)
    for _, pt in ipairs(brushScreenPoints) do
      love.graphics.rectangle("fill", pt.x, pt.y, z, z)
    end
    love.graphics.setColor(colors.white)
    return
  end

  -- Apply palette shader matching hovered item.
  if layer and hoveredItem then
    local layerOpacity = (layer.opacity ~= nil) and layer.opacity or 1.0
    ShaderPaletteController.applyLayerItemPalette(
      layer,
      hoveredItem,
      true,  -- isActiveLayer
      romRaw,
      paletteNum,
      isAnimationKind(win) and layerOpacity or nil
    )
  else
    ShaderPaletteController.applyShader(true)
  end

  -- Draw brush pattern using shader (color index encoded in grayscale)
  local brushImg = getPixelBrushImage(colorIndex)
  for _, pt in ipairs(brushScreenPoints) do
    love.graphics.draw(brushImg, pt.x, pt.y, 0, z, z)
  end
  
  ShaderPaletteController.releaseShader()
  love.graphics.setColor(colors.white)
end

local function drawNonModalOverlays(app)
  ShaderPaletteController.applyShader(true)
  UserInput.drawOverlay()
  ShaderPaletteController.releaseShader()
  drawEditModeColorIndicator(app)
  if app.windowHeaderContextMenu and app.windowHeaderContextMenu.isVisible and app.windowHeaderContextMenu:isVisible() then
    if app.windowHeaderContextMenu.update then
      app.windowHeaderContextMenu:update()
    end
    app.windowHeaderContextMenu:draw()
  end
  if app.emptySpaceContextMenu and app.emptySpaceContextMenu.isVisible and app.emptySpaceContextMenu:isVisible() then
    if app.emptySpaceContextMenu.update then
      app.emptySpaceContextMenu:update()
    end
    app.emptySpaceContextMenu:draw()
  end
  if app.e2eOverlayMenu and app.e2eOverlayMenu.isVisible and app.e2eOverlayMenu:isVisible() then
    if app.e2eOverlayMenu.update then
      app.e2eOverlayMenu:update()
    end
    app.e2eOverlayMenu:draw()
  end
  if app.toastController and app.canvas then
    app.toastController:draw(app.canvas:getWidth(), app.canvas:getHeight())
  end
  if app.tooltipController and app.canvas then
    app.tooltipController:draw(app.canvas:getWidth(), app.canvas:getHeight())
  end
end

local function drawOverlays(app)
  app.newWindowModal:draw(app.canvas)
  if app.saveOptionsModal then
    app.saveOptionsModal:draw(app.canvas)
  end
  app.genericActionsModal:draw(app.canvas)
  if app.settingsModal then
    app.settingsModal:draw(app.canvas)
  end
  if app.renameWindowModal then
    app.renameWindowModal:draw(app.canvas)
  end
  if app.romPaletteAddressModal then
    app.romPaletteAddressModal:draw(app.canvas)
  end
  if app.ppuFrameRangeModal then
    app.ppuFrameRangeModal:draw(app.canvas)
  end
  if app.textFieldDemoModal then
    app.textFieldDemoModal:draw(app.canvas)
  end
end

local function drawStatus(app)
  local eventText = app.lastEventText or app.statusText or ""
  if app.taskbar then
    app.taskbar:draw(eventText)
  else
    love.graphics.setColor(0.9, 0.9, 0.9)
    Text.print("" .. eventText, 12, app.canvas:getHeight() - 16, { outline = true })
    love.graphics.setColor(colors.white)
  end
end

local function drawHUD(app)
  love.graphics.setColor(colors.white)
  local state = app.appEditState or {}
  local romLoaded = type(state.romRaw) == "string" and #state.romRaw > 0
  local bankCount = #(state.chrBanksBytes or {})
  local currentBank = tonumber(state.currentBank) or 1
  local windows = (app.wm and app.wm.getWindows and app.wm:getWindows()) or {}
  local visibleWindows = 0
  for _, win in ipairs(windows) do
    if win and not win._closed and not win._minimized then
      visibleWindows = visibleWindows + 1
    end
  end
  local focus = app.wm and app.wm.getFocus and app.wm:getFocus() or nil
  local focusLabel = "none"
  if focus then
    focusLabel = string.format("%s:%s",
      tostring(focus.kind or "?"),
      tostring(focus._id or focus.title or "?")
    )
  end
  local romLabel = "none"
  if romLoaded then
    local sha = tostring(state.romSha1 or "")
    if #sha > 8 then
      sha = sha:sub(1, 8)
    end
    romLabel = sha ~= "" and sha or "loaded"
  end
  local lines = {
    "FPS: " .. love.timer.getFPS(),
    "Mode: " .. app.mode:upper(),
    "ROM: " .. romLabel,
    string.format("Bank: %d/%d", currentBank, math.max(1, bankCount)),
    string.format("Windows: %d/%d", visibleWindows, #windows),
    "Focus: " .. focusLabel,
    "Unsaved: " .. ((app.unsavedChanges == true) and "yes" or "no"),
  }
  if DebugController.getHudMode and DebugController.getHudMode() ~= "off" then
    local hudLines = DebugController.getHudSummaryLines()
    for _, line in ipairs(hudLines) do
      lines[#lines + 1] = line
    end
  end
  Text.print(lines, 12, 12, { outline = true })
end

function AppCoreController:draw()  
  DebugController.perfBeginFrame()
  love.graphics.setCanvas({ self.canvas, depthstencil = true })
  love.graphics.clear(colors.gray10)

  drawWindows(self)
  drawPaletteLinks(self)
  drawEmptyStatePrompt(self)
  drawStatus(self)
  drawNonModalOverlays(self)
  drawOverlays(self)
  if self.splash and self.splash:isVisible() then
    self.splash:draw(self.canvas)
  end
  self.quitConfirmModal:draw(self.canvas)
  CursorsController.draw(self)

  love.graphics.setCanvas()
  love.graphics.setColor(colors.white)

  ResolutionController:renderCanvas(self.canvas)
  if self.showDebugInfo then
    drawHUD(self)
  end
  DebugController.perfEndFrame()
end

function AppCoreController:resize(w, h)
  ResolutionController:recalculate()
  self:_persistWindowSnapshotIfNeeded(true)
  if self.taskbar and self.canvas then
    self.taskbar:updateLayout(self.canvas:getWidth(), self.canvas:getHeight())
  end
  if self.toastController and self.canvas then
    self.toastController:updateLayout(self.canvas:getWidth(), self.canvas:getHeight())
  end
end

end
