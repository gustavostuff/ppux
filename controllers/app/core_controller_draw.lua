local ResolutionController = require("controllers.app.resolution_controller")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
local DebugController = require("controllers.dev.debug_controller")
local PaletteLinkRenderController = require("controllers.palette.palette_link_render_controller")
local WindowLinkVisualController = require("controllers.window.window_link_visual_controller")
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
local CanvasSpace = require("utils.canvas_space")
local ChrCanvasOnlyMode = require("controllers.chr.chr_canvas_only_mode")
local CrtLayerViz = require("controllers.crt.crt_layer_viz")
local UiScale = require("user_interface.ui_scale")
local GridOverlayMetrics = require("controllers.window.grid_overlay_metrics")

--- Drop-shadow mask offset defaults (pixels, code-only). Positive X -> right, Y -> down.
--- Override at runtime: app.windowShadowOffsetX / app.windowShadowOffsetY.
local WINDOW_SHADOW_OFFSET_X = 2
local WINDOW_SHADOW_OFFSET_Y = 2

local function drawEmptyStatePrompt(app)
  if app:hasLoadedROM() then return end

  -- Text.printCenter("Drop an NES ROM here", {
  --   canvas = app.canvas,
  --   font = app.emptyStateFont or app.font,
  --   shadowColor = colors.transparent,
  --   color = colors.gray20
  -- })
end

return function(AppCoreController)
local ReferenceBackgroundController = require("controllers.window.reference_background_controller")
local Shared = require("controllers.app.core_controller_shared")
local PpuRange = require("controllers.app.ppu_frame_range_helpers")
local BankViewController = require("controllers.chr.bank_view_controller")
-- Find the active global palette window (non-ROM) and return its first color,
-- or nil if none is available.

local function getActiveGlobalPaletteBgColor(wm)
  local paletteWin = nil
  local fallback = nil

  for _, win in ipairs(wm:getWindows()) do
    if WindowCaps.isGlobalPaletteWindow(win) and not win._closed and not win._minimized and win._groupHidden ~= true then
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
    if WindowCaps.isGlobalPaletteWindow(win) and not win._closed and not win._minimized and win._groupHidden ~= true then
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
  return PaletteLinkRenderController.drawOverlay(app)
end

local function drawActivePaletteLinkDrag(app)
  PaletteLinkRenderController.drawActiveDrag(app)
end

local function drawPaletteLinks(app)
  drawActivePaletteLinkDrag(app)
end

local function renderWindowChessPattern(window, wm)
  -- Pick base BG color: window ROM palette BG -> global active BG -> black
  local bgColor = getRomPaletteBgColorForWindow(window, wm) or getActiveGlobalPaletteBgColor(wm) or colors.black
  local grid = (window.getDisplayGridMetrics and window:getDisplayGridMetrics()) or {
    baseCellW = window.cellW or 8,
    baseCellH = window.cellH or 8,
    cellW = window.cellW or 8,
    cellH = window.cellH or 8,
    rowStride = 1,
  }
  local chessRowSkip = GridOverlayMetrics.chessNominalRowSkip(window, grid)
  local bandH = GridOverlayMetrics.overlayVerticalPeriodNes(window, grid)

  window:drawGrid(function(col, row, x, y, cw, ch)
    if chessRowSkip > 1 and (row % chessRowSkip) ~= 0 then
      return
    end

    love.graphics.setColor(bgColor)
    love.graphics.rectangle("fill", x, y, cw + 1, bandH + 1)

    if (math.floor(row / chessRowSkip) + col) % 2 == 0 then
      local color = colors.white
      local checkerAlpha = 0.1
      if ResolutionController.canvasCrtShaderEnabled == true
          and (ResolutionController.canvasCrtFilterKind or "crt") == "composite" then
        checkerAlpha = 0.2
      end
      love.graphics.setColor(color[1], color[2], color[3], checkerAlpha)
      love.graphics.rectangle("fill", x, y, cw + 1, bandH + 1)
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
  local vertPeriod = GridOverlayMetrics.overlayVerticalPeriodNes(window, grid)
  local stepY = vertPeriod * zoom
  if stepX <= 0 or stepY <= 0 then return end

  local x, y, w, h = window:getScreenRect()
  local thickness = 1
  local scrollOffsetX = ((window.scrollCol or 0) * (grid.baseCellW or grid.cellW) * zoom) % stepX
  local baseStepY = grid.baseCellH or grid.cellH or 8
  local scrollOffsetY = ((window.scrollRow or 0) * baseStepY * zoom) % stepY

  love.graphics.push("all")
  love.graphics.setShader(linesGridShader)
  local ox, oy = love.graphics.transformPoint(x - scrollOffsetX, y - scrollOffsetY)
  linesGridShader:send("u_origin", { ox, oy })
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
  -- DEBUG: show paletteNumber (1-4) over each tile if present
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

local function drawPatternTableRangeHoverOverlay(app, w, layerIndex)
  if not (WindowCaps.isPatternTable(w) and app and app.wm) then
    return
  end
  local layer = w.layers and w.layers[layerIndex]
  local pt = layer and layer.patternTable
  if type(pt) ~= "table" or type(pt.ranges) ~= "table" or #pt.ranges == 0 then
    return
  end

  local gctx = rawget(_G, "ctx")
  local scaledMouse = gctx and gctx.scaledMouse and gctx.scaledMouse() or nil
  if not scaledMouse then
    return
  end
  if Shared.modalBlocksWorkspaceInteractions(app) then
    return
  end
  if Shared.pointerOverOpenContextMenu(app, scaledMouse.x, scaledMouse.y) then
    return
  end 
  local topWin = (app.wm.getTopInteractiveSurfaceWindowAt and app.wm:getTopInteractiveSurfaceWindowAt(scaledMouse.x, scaledMouse.y))
    or (app.wm.windowAt and app.wm:windowAt(scaledMouse.x, scaledMouse.y))
  if topWin ~= w then
    return
  end

  local ok, hoverCol, hoverRow = w:toGridCoords(scaledMouse.x, scaledMouse.y)
  if not ok then
    return
  end

  local cols = math.max(1, math.floor(tonumber(w.cols) or 16))
  local rows = math.max(1, math.floor(tonumber(w.rows) or 16))
  local hoverPos = hoverRow * cols + hoverCol
  local layoutMode = layer and layer.mode or "8x8"
  local hoverLogical = BankViewController.chrOrderingIndexForGridPos(layoutMode, hoverPos)
  local startL, endL = PpuRange.patternLogicalSpanContainingIndex(pt, hoverLogical)
  if startL == nil or endL == nil then
    return
  end

  local cw = w.cellW or 8
  local ch = w.cellH or 8
  local grid = w.getDisplayGridMetrics and w:getDisplayGridMetrics(layerIndex) or {}
  cw = grid.cellW or cw
  ch = grid.cellH or ch
  local baseCh = grid.baseCellH or w.cellH or 8
  local pattern16 = PpuRange.patternTableUses8x16TileLayout(layer)
  local sx, sy, sw, sh = w:getInsetContentScreenRect()
  local z = (w.getZoomLevel and w:getZoomLevel()) or w.zoom or 1
  local vC0 = w.scrollCol or 0
  local vR0 = w.scrollRow or 0
  local vC1 = math.min(cols - 1, vC0 + (w.visibleCols or cols) - 1)
  local vR1 = math.min(rows - 1, vR0 + (w.visibleRows or rows) - 1)

  love.graphics.push()
  local ox, oy = w:getContentScreenOrigin()
  love.graphics.translate(ox, oy)
  love.graphics.scale(z, z)
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)
  love.graphics.translate(-(w.scrollCol or 0) * cw, -(w.scrollRow or 0) * baseCh)

  love.graphics.setColor(1, 1, 1, 0.14)
  if pattern16 then
    -- Nominal grid stays 8×8 CHR lines; 8×16 mode shows one translucent band per column pair (matches chess/lines).
    local r = vR0
    if r % 2 == 1 then
      for col = vC0, vC1 do
        local gridPos = r * cols + col
        local logical = BankViewController.chrOrderingIndexForGridPos(layoutMode, gridPos)
        if logical >= startL and logical <= endL then
          love.graphics.rectangle("fill", col * cw, r * baseCh, cw, baseCh)
        end
      end
      r = r + 1
    end
    while r + 1 <= vR1 do
      for col = vC0, vC1 do
        local log0 = BankViewController.chrOrderingIndexForGridPos(layoutMode, r * cols + col)
        local log1 = BankViewController.chrOrderingIndexForGridPos(layoutMode, (r + 1) * cols + col)
        if (log0 >= startL and log0 <= endL) or (log1 >= startL and log1 <= endL) then
          love.graphics.rectangle("fill", col * cw, r * baseCh, cw, 2 * baseCh)
        end
      end
      r = r + 2
    end
    if r == vR1 then
      for col = vC0, vC1 do
        local gridPos = r * cols + col
        local logical = BankViewController.chrOrderingIndexForGridPos(layoutMode, gridPos)
        if logical >= startL and logical <= endL then
          love.graphics.rectangle("fill", col * cw, r * baseCh, cw, baseCh)
        end
      end
    end
  else
    for row = vR0, vR1 do
      for col = vC0, vC1 do
        local gridPos = row * cols + col
        local logical = BankViewController.chrOrderingIndexForGridPos(layoutMode, gridPos)
        if logical >= startL and logical <= endL then
          love.graphics.rectangle("fill", col * cw, row * baseCh, cw, baseCh)
        end
      end
    end
  end
  love.graphics.setColor(colors.white)

  love.graphics.pop()
  love.graphics.setScissor()
end

local function drawTileLayer(app, w, layerIndex, isFocused)
  local isPalWindow = WindowCaps.isGlobalPaletteWindow(w)
  local isPPUFrame = WindowCaps.isPpuFrame(w)
  local layer = w.layers and w.layers[layerIndex]
  local attrMode = isPPUFrame and layer and layer.attrMode == true
  if isPPUFrame and w.isPatternTableInteractionLocked then
    local locked = w:isPatternTableInteractionLocked(layerIndex)
    if locked then
      return
    end
  end

  if isPPUFrame and not attrMode and w.drawNametableLayerCanvas then
    local handledCanvas = w:drawNametableLayerCanvas(layerIndex)
    if handledCanvas then
      return
    end
  end

  if not isPPUFrame and layer and layer.kind == "tile" and w.drawTileLayerCanvas then
    local handledLayoutCanvas = w:drawTileLayerCanvas(app, layerIndex)
    if handledLayoutCanvas then
      local activeLi = (w.getActiveLayerIndex and w:getActiveLayerIndex()) or w.activeLayer or 1
      if WindowCaps.isPatternTable(w) and layerIndex == activeLi then
        drawPatternTableRangeHoverOverlay(app, w, layerIndex)
      end
      return
    end
  end

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
  local sx, sy, sw, sh = w:getInsetContentScreenRect()

  love.graphics.push()
  local ox, oy = w:getContentScreenOrigin()
  love.graphics.translate(ox, oy)
  local z = (w.getZoomLevel and w:getZoomLevel()) or w.zoom or 1
  love.graphics.scale(z, z)
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)

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
  local okImg = controller:drawWindowImage(app.appEditState, w, layerOpacity)
  ShaderPaletteController.releaseShader()
  local okOv = controller:drawWindowDiffOverlay(app.appEditState, w, layerOpacity)
  return okImg and okOv
end

local function isAnimationKind(win)
  return WindowCaps.isAnimationLike(win)
end

local shadowMaskCanvas = nil
local shadowBlurTempCanvas = nil
local shadowCanvasW = 0
local shadowCanvasH = 0

local SHADOW_BLUR_ZERO_EPS = 1e-5

local shadowBlurHShaderCached = nil
local shadowBlurVShaderCached = nil
local shadowBlurShadersAttempted = false

local shadowMaskCompositeShaderCached = nil
local shadowMaskCompositeShaderAttempted = false

local function normalizedWindowShadowBlurT(app)
  local blurT = tonumber(app.windowShadowBlur)
  if blurT == nil then
    blurT = 0.2
  end
  return math.max(0, math.min(1, blurT))
end

local function resolveShadowBlurShaders()
  if shadowBlurShadersAttempted then
    return shadowBlurHShaderCached, shadowBlurVShaderCached
  end
  shadowBlurShadersAttempted = true
  local ok = pcall(require, "shaders")
  if not ok then
    return nil, nil
  end
  shadowBlurHShaderCached = rawget(_G, "windowShadowBlurHShader")
  shadowBlurVShaderCached = rawget(_G, "windowShadowBlurVCompositeShader")
  return shadowBlurHShaderCached, shadowBlurVShaderCached
end

local function resolveWindowShadowMaskCompositeShader()
  if shadowMaskCompositeShaderAttempted then
    return shadowMaskCompositeShaderCached
  end
  shadowMaskCompositeShaderAttempted = true
  local ok = pcall(require, "shaders")
  if not ok then
    return nil
  end
  shadowMaskCompositeShaderCached = rawget(_G, "windowShadowMaskCompositeShader")
  return shadowMaskCompositeShaderCached
end

local function ensureShadowMaskCanvases(app)
  local cw = app.canvas:getWidth()
  local ch = app.canvas:getHeight()
  if shadowMaskCanvas and shadowBlurTempCanvas and shadowCanvasW == cw and shadowCanvasH == ch then
    return true
  end
  if shadowMaskCanvas then
    shadowMaskCanvas:release()
    shadowMaskCanvas = nil
  end
  if shadowBlurTempCanvas then
    shadowBlurTempCanvas:release()
    shadowBlurTempCanvas = nil
  end
  shadowCanvasW = cw
  shadowCanvasH = ch
  shadowMaskCanvas = love.graphics.newCanvas(cw, ch)
  shadowBlurTempCanvas = love.graphics.newCanvas(cw, ch)
  if shadowMaskCanvas and shadowBlurTempCanvas then
    -- Hard mask: nearest avoids bilinear fringe when blitting 1:1 to the blur temp canvas.
    shadowMaskCanvas:setFilter("nearest", "nearest")
    -- Blurred intermediate: keep linear so soft shadows composite smoothly.
    shadowBlurTempCanvas:setFilter("linear", "linear")
    shadowMaskCanvas:setWrap("clamp", "clamp")
    shadowBlurTempCanvas:setWrap("clamp", "clamp")
    return true
  end
  return false
end

--- Header + content + bottom border line (drawBorder uses h+1). Collapsed -> header strip only
--- (`drawBorder` is not used collapsed, so `hh` matches chrome - see branch below).
local function computeWindowChromeShadowRect(w)
  if w._collapsed and type(w.getHeaderRect) == "function" then
    local hx, hy, hw, hh = w:getHeaderRect()
    return hx - 1, hy, hw + 2, hh
  end

  local cx, cy, cw, ch = w:getScreenRect()
  local hx, hy, hw, hh = w:getHeaderRect()
  local left = hx - 1
  local right = cx + cw + 1
  local width = right - left
  -- Match window_rendering_chrome.drawBorder: rectangle("line", cx, cy, cw + 1, ch + 1).
  local height = (cy + ch + 1) - hy
  return left, hy, width, height
end

--- Specialized toolbar bounds when docked on the window (narrow strip above header). Nil if N/A.
local function computeSpecializedToolbarShadowRect(app, w, wm)
  if w._collapsed then
    return nil
  end
  local isFocused = wm and wm.getFocus and (w == wm:getFocus())
  if not isFocused or app.separateToolbar == true then
    return nil
  end
  local tb = w.specializedToolbar
  if not tb then
    return nil
  end
  if tb.updateIcons then
    tb:updateIcons()
  end
  if tb.updatePosition then
    tb:updatePosition()
  end
  local drawX = (tonumber(tb.x) or 0) - 1
  local drawY = tonumber(tb.y) or 0
  local drawW = math.max(0, tonumber(tb.w) or 0)
  local drawH = math.max(0, tonumber(tb.h) or 0)
  if drawW <= 0 or drawH <= 0 then
    return nil
  end
  return drawX, drawY, drawW, drawH
end

local function shadowRoundedRadiusForRect(ww, wh)
  local cell = UiScale.menuCellSize()
  local radius = math.min(4, math.floor(cell * 0.25))
  radius = math.min(radius, math.floor(math.min(ww, wh) * 0.5))
  return radius
end

--- Pixel offset for the drop-shadow mask (defaults above; optional app overrides).
local function windowShadowPixelOffsets(app)
  local ox = WINDOW_SHADOW_OFFSET_X
  local oy = WINDOW_SHADOW_OFFSET_Y
  if app then
    if app.windowShadowOffsetX ~= nil then
      ox = tonumber(app.windowShadowOffsetX) or ox
    end
    if app.windowShadowOffsetY ~= nil then
      oy = tonumber(app.windowShadowOffsetY) or oy
    end
  end
  return ox, oy
end

--- Hard-edged rounded rects into the shadow mask (overlap stays opaque via max blend).
local function drawHardShadowRoundedFill(x, y, ww, wh)
  local r = shadowRoundedRadiusForRect(ww, wh)
  love.graphics.rectangle("fill", x, y, ww, wh, r, r)
end

--- Title-bar strip (window header slab): rounded **top** corners only; bottom edge stays sharp so it meets the body
--- (and so blur does not inherit rounded bottom corners from `rectangle(..., r, r)` on the full strip).
--- LOVE angles: 0 = right, clockwise; pie slices use quadrants at top-left / top-right arc centers.
local function drawHardShadowTopRoundedStripFill(x, y, ww, wh)
  if ww <= 0 or wh <= 0 then
    return
  end
  local r = shadowRoundedRadiusForRect(ww, wh)
  if r <= 0 then
    love.graphics.rectangle("fill", x, y, ww, wh)
    return
  end
  r = math.min(r, math.floor(math.min(ww, wh) * 0.5))
  if ww <= 2 * r then
    love.graphics.rectangle("fill", x, y, ww, wh)
    return
  end
  -- Thin strip: avoid `rectangle(..., r, r)` (rounds bottom corners too); blur then corrupts distant corners.
  if wh <= r then
    love.graphics.rectangle("fill", x, y, ww, wh)
    return
  end
  love.graphics.rectangle("fill", x + r, y + r, ww - 2 * r, wh - r)
  love.graphics.rectangle("fill", x, y + r, r, wh - r)
  love.graphics.rectangle("fill", x + ww - r, y + r, r, wh - r)
  love.graphics.rectangle("fill", x + r, y, ww - 2 * r, r)
  love.graphics.arc("fill", "pie", x + r, y + r, r, math.pi, math.pi * 1.5)
  love.graphics.arc("fill", "pie", x + ww - r, y + r, r, math.pi * 1.5, math.pi * 2)
end

--- Integer pixel bounds for shadow mask geometry (fractional window rects blur badly at corners).
local function pixelEnvelope(left, top, width, height)
  local L = math.floor(left + 1e-6)
  local T = math.floor(top + 1e-6)
  local R = math.ceil(left + width - 1e-6)
  local B = math.ceil(top + height - 1e-6)
  return L, T, math.max(0, R - L), math.max(0, B - T)
end

--- Expanded windows: one silhouette = top-rounded header slab + sharp body slab.
--- Header height follows content top (`cy - hy`) so the split matches real chrome; optional 1px vertical
--- overlap removes a twin-rectangle seam after blur (max blend keeps alpha 1).
local function drawExpandedWindowChromeShadowMask(ox, oy, w)
  local left, top, width, fullHeight = computeWindowChromeShadowRect(w)
  local cy = select(2, w:getScreenRect())
  local _, hy = w:getHeaderRect()
  local L, T, W, FH = pixelEnvelope(left, top, width, fullHeight)
  local headerSpanPx = cy - hy
  local hhPx = math.min(FH, math.max(0, math.ceil(headerSpanPx - 1e-9)))
  local bodyPx = FH - hhPx
  local x0 = L + ox
  local y0 = T + oy
  drawHardShadowTopRoundedStripFill(x0, y0, W, hhPx)
  if bodyPx > 0 then
    local overlap = (hhPx > 0) and 1 or 0
    love.graphics.rectangle("fill", x0, y0 + hhPx - overlap, W, bodyPx + overlap)
  end
end

local function drawHardShadowRectsForWindow(app, w, wm)
  local ox, oy = windowShadowPixelOffsets(app)
  ox = math.floor(ox + 1e-6)
  oy = math.floor(oy + 1e-6)
  if w._collapsed and type(w.getHeaderRect) == "function" then
    local left, top, width, height = computeWindowChromeShadowRect(w)
    local L, T, W, H = pixelEnvelope(left, top, width, height)
    drawHardShadowRoundedFill(L + ox, T + oy, W, H)
  else
    drawExpandedWindowChromeShadowMask(ox, oy, w)
  end

  local tx, ty, tw, th = computeSpecializedToolbarShadowRect(app, w, wm)
  if tx then
    local L, T, W, H = pixelEnvelope(tx, ty, tw, th)
    drawHardShadowRoundedFill(L + ox, T + oy, W, H)
  end

  if WindowCaps.isAnyPaletteWindow(w) then
    local stripRects = w:getSelectionStripShadowRectsCanvas(wm)
    local r1 = stripRects and stripRects[1]
    local r2 = stripRects and stripRects[2]
    if r1 and r2 then
      local L2, T2, W2, H2 = pixelEnvelope(r2[1], r2[2], r2[3], r2[4])
      local L1, T1, W1, H1 = pixelEnvelope(r1[1], r1[2], r1[3], r1[4])
      love.graphics.rectangle("fill", L2 + ox, T2 + oy - 1, W2 + 1, H2 + 2)
      love.graphics.rectangle("fill", L1 + ox - 1, T1 + oy, W1 + 2, H1 + 1)
    end
  end
end

--- Used only when blur slider > 0 (separable Gaussian). At blur 0 we skip blur passes entirely.
local function computeShadowBlurSigma(app)
  local cell = UiScale.menuCellSize()
  local blurT = normalizedWindowShadowBlurT(app)
  local featherMax = math.max(22, math.floor(cell * 2.0))
  -- Map blurT 0->1 to sigma min->max. Do not floor at a large "featherMin": the old
  -- featherMin + (featherMax - featherMin) * blurT made any tiny blurT land near
  -- featherMin * 0.38 (~1+ px sigma), so the first slider tick looked heavily blurred.
  local sigmaMax = math.min(featherMax * 0.38, 12)
  local sigmaMin = 0.25
  return sigmaMin + (sigmaMax - sigmaMin) * blurT
end

local function computeShadowCompositeAlpha(app)
  local themeLight = app.themeMode == "light"
  local baseAlpha = themeLight and 0.26 or 0.4
  local strength = tonumber(app.windowShadowStrength)
  if strength == nil then
    strength = 1
  end
  strength = math.max(0, math.min(1, strength))
  return baseAlpha * strength
end

--- Collect open ContextualMenuController trees (app menus, taskbar main menu, submenus) into the shared mask.
local function drawHardShadowMasksForOpenContextMenus(app, ox, oy)
  local rects = {}
  local function addFrom(menu)
    if menu
      and menu.isVisible
      and menu:isVisible()
      and menu.accumulateVisiblePanelShadowRectsInto
    then
      menu:accumulateVisiblePanelShadowRectsInto(rects)
    end
  end
  for _, key in ipairs(Shared.APP_OVERLAY_CONTEXT_MENU_KEYS) do
    addFrom(app[key])
  end
  if app.taskbar and app.taskbar.menuController then
    addFrom(app.taskbar.menuController)
  end
  for _, r in ipairs(rects) do
    drawHardShadowRoundedFill(r[1] + ox, r[2] + oy, r[3], r[4])
  end
end

--- Hard mask -> separable blur -> single premultiplied composite (no extra darkening where silhouettes overlap).
--- All base silhouettes are rasterized into shadowMaskCanvas first; menus use the same pass as windows/chrome.
local function drawAllWindowShadows(app)
  if app.windowShadowEnabled == false then
    return
  end

  local strength = tonumber(app.windowShadowStrength)
  if strength == nil then
    strength = 1
  end
  strength = math.max(0, math.min(1, strength))
  if strength <= 0 then
    return
  end

  local blurT = normalizedWindowShadowBlurT(app)
  local useGaussianBlur = blurT > SHADOW_BLUR_ZERO_EPS

  local blurH, blurV
  local maskComposite
  if useGaussianBlur then
    blurH, blurV = resolveShadowBlurShaders()
    if not blurH or not blurV then
      return
    end
  else
    maskComposite = resolveWindowShadowMaskCompositeShader()
    if not maskComposite then
      return
    end
  end

  if not ensureShadowMaskCanvases(app) then
    return
  end

  local wm = app.wm
  if not wm or not wm.getWindows then
    return
  end

  local cw, ch = shadowCanvasW, shadowCanvasH
  local sigma = useGaussianBlur and computeShadowBlurSigma(app) or 0
  local shadowAlpha = computeShadowCompositeAlpha(app)

  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setScissor()
  if love.graphics.setDepthMode then
    love.graphics.setDepthMode("always", false)
  end

  love.graphics.setCanvas(shadowMaskCanvas)
  love.graphics.clear(0, 0, 0, 0)
  if not pcall(function()
    love.graphics.setBlendMode("max", "premultiplied")
  end) then
    love.graphics.setBlendMode("alpha", "premultiplied")
  end
  -- Premultiplied silhouette: RGB stays (0,0,0); only alpha feeds blur/composite (see shaders.lua).
  love.graphics.setColor(0, 0, 0, 1)
  local shadowOx, shadowOy = windowShadowPixelOffsets(app)
  shadowOx = math.floor(shadowOx + 1e-6)
  shadowOy = math.floor(shadowOy + 1e-6)
  for _, w in ipairs(wm:getWindows()) do
    if not w or w._closed or w._minimized or w._groupHidden == true then
      goto shadow_continue
    end
    if WindowCaps.isCrtLens(w) then
      goto shadow_continue
    end
    drawHardShadowRectsForWindow(app, w, wm)
    ::shadow_continue::
  end

  -- Base silhouettes (max blend): windows, top/taskbar strips, then open menus - then one blur/composite pass.
  do
    local topH = AppTopToolbarController.getContentOffsetY(app)
    if type(topH) == "number" and topH > 0 then
      drawHardShadowRoundedFill(shadowOx, shadowOy, cw, topH)
    end
    local tbH = (app.taskbar and tonumber(app.taskbar.h)) or UiScale.taskbarHeight()
    tbH = math.max(0, tbH)
    local tbY = ch - tbH
    if tbH > 0 and tbY >= 0 then
      drawHardShadowRoundedFill(shadowOx, tbY + shadowOy, cw, tbH)
    end
  end

  drawHardShadowMasksForOpenContextMenus(app, shadowOx, shadowOy)

  love.graphics.setBlendMode("alpha", "alphamultiply")

  if useGaussianBlur then
    love.graphics.setCanvas(shadowBlurTempCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setShader(blurH)
    blurH:send("textureSize", { cw, ch })
    blurH:send("sigma", sigma)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(shadowMaskCanvas, 0, 0)
    love.graphics.setShader()

    love.graphics.setCanvas(app.canvas)
    love.graphics.setShader(blurV)
    blurV:send("textureSize", { cw, ch })
    blurV:send("sigma", sigma)
    blurV:send("shadowAlpha", shadowAlpha)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(shadowBlurTempCanvas, 0, 0)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha", "alphamultiply")
  else
    love.graphics.setCanvas(app.canvas)
    love.graphics.setShader(maskComposite)
    maskComposite:send("shadowAlpha", shadowAlpha)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(shadowMaskCanvas, 0, 0)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha", "alphamultiply")
  end

  love.graphics.pop()
end

local crtLensDrawShaderCached = nil
local crtLensDrawShaderLoadAttempted = false

local function resolveCrtLensDrawShader()
  if crtLensDrawShaderCached ~= nil or crtLensDrawShaderLoadAttempted then
    return crtLensDrawShaderCached
  end
  crtLensDrawShaderLoadAttempted = true
  local ok = pcall(require, "shaders")
  if not ok then
    return nil
  end
  crtLensDrawShaderCached = rawget(_G, "crtShader")
  return crtLensDrawShaderCached
end

--- Full in-canvas CRT visualization (default). Legacy post-render sampling uses chrome-only + overlay flag.
local function drawCrtLensVisualizerWindow(app, w, wm)
  PaletteLinkRenderController.drawSourcePaletteProxyForWindow(app, w)

  local isFocused = (w == wm:getFocus())
  local isCollapsed = w._collapsed or false

  if isCollapsed then
    w:drawHeader(isFocused)
    if w.headerToolbar then
      w.headerToolbar:draw()
    end
    return
  end

  local sx, sy, sw, sh = w:getScreenRect()
  local refs = w.crtRefLayers or {}
  if #refs == 0 then
    local bg = isFocused and colors:focusedChromeColor() or colors:chromeBackgroundUnfocused()
    love.graphics.setColor(bg)
    love.graphics.rectangle("fill", sx, sy, sw, sh)
    love.graphics.setColor(isFocused and colors:chromeTextIconsColorFocused() or colors:chromeTextIconsColorNonFocused())
    if app.font then
      love.graphics.setFont(app.font)
    end
    love.graphics.print("Right-click to add a layer", sx + 8, sy + 10)
    love.graphics.setColor(colors.white)
  else
    local scratch = ResolutionController:_ensureCrtLensScratchCanvas()
    if scratch then
      CrtLayerViz.compositeRefsOntoScratch(app, wm, scratch, w)
      local shader = resolveCrtLensDrawShader()
      local dist
      if ResolutionController.canvasCrtFlat then
        dist = 0
      elseif type(w.crtVizDistortion) == "number" then
        dist = w.crtVizDistortion
      elseif type(app.crtDistortionSetting) == "number" then
        dist = app.crtDistortionSetting
      else
        dist = ResolutionController:getCanvasCrtDistortion() or 0.1
      end

      if shader then
        love.graphics.setShader(shader)
        shader:send("inputSize", { 256, 240 })
        shader:send("textureSize", { 256, 240 })
        shader:send("outputSize", { sw, sh })
        shader:send("distortion", dist)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(scratch, sx, sy, 0, sw / 256, sh / 240)
        love.graphics.setShader()
      else
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(scratch, sx, sy, 0, sw / 256, sh / 240)
      end
      love.graphics.setColor(colors.white)
    end
  end

  w:drawResizeHandle(isFocused, ResolutionController:getScaledMouse(true), app.neverShowResizeHandle == true)

  if w.drawSelectionOverlays then
    w:drawSelectionOverlays(isFocused)
  end

  w:drawLayerLabelInContent(isFocused)

  w:drawBorder(isFocused)

  w:drawScrollBars(isFocused)

  if w.specializedToolbar
    and not (app.separateToolbar == true and w == wm:getFocus()) then
    w.specializedToolbar:draw()
  end

  w:drawHeader(isFocused)

  if w.headerToolbar then
    w.headerToolbar:draw()
  end
end

local function drawCrtLensWindowChromeOnly(app, w, wm)
  PaletteLinkRenderController.drawSourcePaletteProxyForWindow(app, w)

  local isFocused = (w == wm:getFocus())
  local isCollapsed = w._collapsed or false

  if isCollapsed then
    w:drawHeader(isFocused)
    if w.headerToolbar then
      w.headerToolbar:draw()
    end
    return
  end

  -- Legacy: post-render "lens" samples the composed workspace; use only when crtLensPostCanvasOverlayEnabled.
  w:drawResizeHandle(isFocused, ResolutionController:getScaledMouse(true), app.neverShowResizeHandle == true)

  if w.drawSelectionOverlays then
    w:drawSelectionOverlays(isFocused)
  end

  w:drawLayerLabelInContent(isFocused)

  w:drawBorder(isFocused)

  w:drawScrollBars(isFocused)

  if w.specializedToolbar
    and not (app.separateToolbar == true and w == wm:getFocus()) then
    w.specializedToolbar:draw()
  end

  w:drawHeader(isFocused)

  if w.headerToolbar then
    w.headerToolbar:draw()
  end
end

-- Forward declaration: drawWindows calls this; a later `local function` would be out of scope here (Lua resolves it as global).
local drawNormalWindow

local function drawWindows(app)
  local wm = app.wm
  local linkDrawState = WindowLinkVisualController.prepareLinkDrawState(app)

  for _, w in ipairs(wm:getWindows()) do
    if w._closed or w._minimized or w._groupHidden == true then
      goto continue
    end

    if WindowCaps.isCrtLens(w) then
      if not w._crtLensVisible then
        goto continue
      end
      if ResolutionController.crtLensPostCanvasOverlayEnabled then
        drawCrtLensWindowChromeOnly(app, w, wm)
      else
        drawCrtLensVisualizerWindow(app, w, wm)
      end
      goto continue
    end

    drawNormalWindow(app, w, wm)
    WindowLinkVisualController.drawWindowLinkOverlay(app, w, linkDrawState)

    ::continue::
  end
end

drawNormalWindow = function(app, w, wm)
  local isFocused   = (w == wm:getFocus())
  if w.specializedToolbar and app.separateToolbar ~= true then
    if isFocused then
      w.specializedToolbar:updatePosition()
    else
      w._toolbarInsetLeft = 0
      w._toolbarInsetRight = 0
      w._toolbarInsetTop = 0
      w._toolbarInsetBottom = 0
    end
  end

  PaletteLinkRenderController.drawSourcePaletteProxyForWindow(app, w)

  local isCollapsed = w._collapsed or false

  if isCollapsed then
    w:drawHeader(isFocused)
    if w.headerToolbar then
      w.headerToolbar:draw()
    end
    return
  end

  local bgColor = getRomPaletteBgColorForWindow(w, wm) or getActiveGlobalPaletteBgColor(wm) or colors.black
  local x, y, ww, wh = w:getScreenRect()
  love.graphics.setColor(bgColor)
  love.graphics.rectangle("fill", x, y, ww, wh)
  love.graphics.setColor(colors.white)

  local isPaletteWindow = WindowCaps.isAnyPaletteWindow(w)
  -- Per-window Mirror X reflects layer data for any window that has it on (even when unfocused).
  local mirrorLayerPreview = (not isPaletteWindow) and w._mirrorXPreview == true

  if mirrorLayerPreview then
    love.graphics.push()
    love.graphics.translate(x + ww, y)
    love.graphics.scale(-1, 1)
    love.graphics.translate(-x, -y)
  end

  local gridMode = GridModeUtils.normalize(w.showGrid)
  w.showGrid = gridMode

  if (not isPaletteWindow) and gridMode == "chess" then
    renderWindowChessPattern(w, wm)
  end

  local refOnly = (not isPaletteWindow) and ReferenceBackgroundController.isReferenceTracingViewActive(w)

  if refOnly then
    ReferenceBackgroundController.drawReferenceBehindLayers(w)
  elseif isPaletteWindow then
    if w.drawGrid then
      w:drawGrid()
    end
  elseif WindowCaps.isChrLike(w) and drawChrBankLayer(app, w, w:getActiveLayerIndex() or 1) then
  else
    local layers = w.layers or {}
    local drawOrder

    if w.drawOnlyActiveLayer == true then
      local activeIdx = w:getActiveLayerIndex() or w.activeLayer or 1
      drawOrder = { activeIdx }
    elseif isAnimationKind(w) then
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
        if WindowCaps.isPpuFrame(w) and w.isLayerVisibleInMode and not w:isLayerVisibleInMode(li) then
          goto continue_layer
        end
        local layerOpacity = (L.opacity ~= nil) and L.opacity or 1.0
        if layerOpacity > 0.001 then
          if L.kind == "sprite" then
            local skipSprites = w.isPatternTableInteractionLocked
              and select(1, w:isPatternTableInteractionLocked(li))
            if not skipSprites then
              w:drawSprites(nil, isFocused, li, app.appEditState.romRaw)
            end
          elseif L.kind == "canvas" then
            drawCanvasLayer(app, w, li, isFocused)
          else
            drawTileLayer(app, w, li, isFocused)
          end
        end
      end
      ::continue_layer::
    end
  end

  if (not isPaletteWindow) and gridMode == "lines" then
    renderWindowLinesGrid(w)
  end

  if w.drawSelectionOverlays then
    w:drawSelectionOverlays(isFocused)
  end
  local marquee = SpriteController.getSpriteMarquee()
  if marquee and marquee.win == w then
    local x1, y1 = marquee.startX, marquee.startY
    local x2, y2 = marquee.currentX, marquee.currentY
    if mirrorLayerPreview and w.remapPreviewMirrorScreenXYIfNeeded then
      x1, y1 = w:remapPreviewMirrorScreenXYIfNeeded(x1, y1)
      x2, y2 = w:remapPreviewMirrorScreenXYIfNeeded(x2, y2)
    end
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
    if mirrorLayerPreview and w.remapPreviewMirrorScreenXYIfNeeded then
      x1, y1 = w:remapPreviewMirrorScreenXYIfNeeded(x1, y1)
      x2, y2 = w:remapPreviewMirrorScreenXYIfNeeded(x2, y2)
    end
    local rx = math.min(x1, x2)
    local ry = math.min(y1, y2)
    local rw = math.abs(x2 - x1)
    local rh = math.abs(y2 - y1)
    love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 0.2)
    love.graphics.rectangle("fill", rx, ry, rw, rh)
    love.graphics.setColor(colors.white)
    love.graphics.rectangle("line", rx, ry, rw, rh)
  end

  w:drawLayerLabelInContent(isFocused)

  if mirrorLayerPreview then
    love.graphics.pop()
  end

  -- Border, scrollbars, and resize handle use 1px line math tied to screen axes; drawing them inside a
  -- horizontal flip duplicates/skews edge pixels. Chrome stays unmirrored like the window header.
  w:drawResizeHandle(isFocused, ResolutionController:getScaledMouse(true), app.neverShowResizeHandle == true)
  w:drawBorder(isFocused)
  w:drawScrollBars(isFocused)

  if w.specializedToolbar
    and not (app.separateToolbar == true and w == wm:getFocus()) then
    w.specializedToolbar:draw()
  end

  w:drawHeader(isFocused)

  if w.headerToolbar then
    w.headerToolbar:draw()
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

--- Edit overlays are drawn outside `drawNormalWindow`'s horizontal flip; mirror screen X to match the
--- visible canvas when this window is focused with Mirror X on.
local function overlayMirrorXActiveForWindow(win)
  if not win or win._mirrorXPreview ~= true then
    return false
  end
  if WindowCaps.isAnyPaletteWindow(win) then
    return false
  end
  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app
  local wm = app and app.wm
  if not (wm and wm.getFocus) then
    return false
  end
  return wm:getFocus() == win
end

local function mirrorBrushOverlayScreenX(win, screenX, elemW)
  if not overlayMirrorXActiveForWindow(win) then
    return screenX
  end
  local cx, _, cw = win:getInsetContentScreenRect()
  if not (type(screenX) == "number" and type(cx) == "number" and type(cw) == "number" and cw > 0) then
    return screenX
  end
  local ew = tonumber(elemW) or 0
  return cx + cw - (screenX - cx) - ew
end

local function contentPixelToScreen(win, px, py, zoom)
  local cw = win.cellW or 8
  local ch = win.cellH or 8
  local scrollX = (win.scrollCol or 0) * cw
  local scrollY = (win.scrollRow or 0) * ch
  local ox, oy = win.x, win.y
  if type(win.getContentScreenOrigin) == "function" then
    ox, oy = win:getContentScreenOrigin()
  end
  local sx = ox + (px - scrollX) * zoom
  local sy = oy + (py - scrollY) * zoom
  return sx, sy
end

local function drawPatternBuilderRectPreview(win, startX, startY, endX, endY, zoom, color)
  local minX = math.min(math.floor(startX or 0), math.floor(endX or 0))
  local maxX = math.max(math.floor(startX or 0), math.floor(endX or 0))
  local minY = math.min(math.floor(startY or 0), math.floor(endY or 0))
  local maxY = math.max(math.floor(startY or 0), math.floor(endY or 0))

  local sx, sy = contentPixelToScreen(win, minX, minY, zoom)
  local sw = (maxX - minX + 1) * zoom
  local sh = (maxY - minY + 1) * zoom
  sx = mirrorBrushOverlayScreenX(win, sx, sw)

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
      local xDraw = mirrorBrushOverlayScreenX(win, pt.x, pt.size)
      love.graphics.rectangle("fill", xDraw, pt.y, pt.size, pt.size)
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
    local xDraw = mirrorBrushOverlayScreenX(win, pt.x, pt.size)
    love.graphics.draw(brushImg, xDraw, pt.y, 0, pt.size, pt.size)
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
            local sx, sy = contentPixelToScreen(win, px, py, zoom)
            previewPoints[#previewPoints + 1] = {
              x = sx,
              y = sy,
              size = zoom,
            }
          end
        end
      end
    end

    drawPatternBuilderPointPreview(win, previewPoints, colorIndex, layer, hoveredItem, romRaw, paletteNum, bgPreviewColor)
    local anchorX, anchorY = contentPixelToScreen(win, win.editLastPoint.x, win.editLastPoint.y, zoom)
    anchorX = mirrorBrushOverlayScreenX(win, anchorX, zoom)
    love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 0.9)
    love.graphics.rectangle("line", anchorX, anchorY, zoom, zoom)
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
  if Shared.modalBlocksWorkspaceInteractions(app) then
    return
  end
  if Shared.pointerOverOpenContextMenu(app, mouse.x, mouse.y) then
    return
  end
  local win = app.wm.getTopInteractiveSurfaceWindowAt and app.wm:getTopInteractiveSurfaceWindowAt(mouse.x, mouse.y)
    or app.wm:windowAt(mouse.x, mouse.y)
  
  -- Only show inside window content area (not header, chrome toolbars, not outside window)
  if not win or win.isPalette or win:isInHeader(mouse.x, mouse.y) then
    return
  end
  if win.specializedToolbar and win.specializedToolbar.contains and win.specializedToolbar:contains(mouse.x, mouse.y) then
    return
  end
  if win.headerToolbar and win.headerToolbar.contains and win.headerToolbar:contains(mouse.x, mouse.y) then
    return
  end

  if ReferenceBackgroundController.isReferenceTracingViewActive(win) then
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

    if (not WindowCaps.isPpuFrame(win)) and layer.removedCells and win.cols then
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
  
  -- Snap brush preview to logical grid cells (window pointer remap in `toGridCoords`; overlay X flip in `mirrorBrushOverlayScreenX`).
  local okGfx, gfxCol, gfxRow, glx, gly = win:toGridCoords(mouse.x, mouse.y)
  if not okGfx then
    return
  end

  local pixelX = gfxCol * cw + math.floor(glx or 0)
  local pixelY = gfxRow * ch + math.floor(gly or 0)

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
      size = z,
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
      local zs = pt.size or z
      local xDraw = mirrorBrushOverlayScreenX(win, pt.x, zs)
      love.graphics.rectangle("fill", xDraw, pt.y, zs, zs)
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
    local zs = pt.size or z
    local xDraw = mirrorBrushOverlayScreenX(win, pt.x, zs)
    love.graphics.draw(brushImg, xDraw, pt.y, 0, zs, zs)
  end
  
  ShaderPaletteController.releaseShader()
  love.graphics.setColor(colors.white)
end

local function drawTranslatedNonModalOverlays(app)
  ShaderPaletteController.applyShader(true)
  UserInput.drawOverlay()
  ShaderPaletteController.releaseShader()
  drawEditModeColorIndicator(app)
end

local function drawVisibleOverlayContextMenu(menu)
  if not menu or not menu:isVisible() then
    return
  end
  if menu.update then
    menu:update()
  end
  menu:draw()
end

local function drawNonModalOverlays(app)
  for _, key in ipairs(Shared.APP_OVERLAY_CONTEXT_MENU_KEYS) do
    drawVisibleOverlayContextMenu(app[key])
  end
end

local function drawToasts(app)
  if app.toastController and app.canvas then
    app.toastController:draw(app.canvas:getWidth(), app.canvas:getHeight())
  end
end

local function drawOverlays(app)
  if app.newWindowTypeModal then
    app.newWindowTypeModal:draw(app.canvas)
  end
  app.newWindowModal:draw(app.canvas)
  if app.openProjectModal then
    app.openProjectModal:draw(app.canvas)
  end
  if app.openReferencePngModal and app.openReferencePngModal:isVisible() then
    app.openReferencePngModal:draw(app.canvas)
  end
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
  if app.ppuFrameSpriteLayerModeModal then
    app.ppuFrameSpriteLayerModeModal:draw(app.canvas)
  end
  if app.ppuFrameAddSpriteModal then
    app.ppuFrameAddSpriteModal:draw(app.canvas)
  end
  if app.ppuFrameRangeModal then
    app.ppuFrameRangeModal:draw(app.canvas)
  end
  if app.ppuFramePatternRangeModal then
    app.ppuFramePatternRangeModal:draw(app.canvas)
  end
  if app.textFieldDemoModal then
    app.textFieldDemoModal:draw(app.canvas)
  end
  drawToasts(app)
end

-- F1 debug HUD: 2x app UI font size (16 -> 32), white fill + black outline (Text.print outline).
local HUD_DEBUG_FONT_PX = 32
local HUD_DEBUG_FONT_CANDIDATES = {
  "user_interface/fonts/AsepriteFont.ttf",
  "../user_interface/fonts/AsepriteFont.ttf",
  "user_interface/fonts/proggy-tiny.ttf",
  "../user_interface/fonts/proggy-tiny.ttf",
  "user_interface/fonts/proggy-clean-sz.ttf",
  "../user_interface/fonts/proggy-clean-sz.ttf",
  "user_interface/fonts/Tiny5-Regular.ttf",
}
local hudDebugFontCache

local function getHudDebugFont()
  if hudDebugFontCache then
    return hudDebugFontCache
  end
  for _, candidate in ipairs(HUD_DEBUG_FONT_CANDIDATES) do
    local ok, f = pcall(love.graphics.newFont, candidate, HUD_DEBUG_FONT_PX)
    if ok and f then
      f:setFilter("nearest", "nearest")
      hudDebugFontCache = f
      return f
    end
  end
  local f = love.graphics.newFont(HUD_DEBUG_FONT_PX)
  f:setFilter("nearest", "nearest")
  hudDebugFontCache = f
  return f
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
  local state = app.appEditState or {}
  local romLoaded = type(state.romRaw) == "string" and #state.romRaw > 0
  local bankCount = #(state.chrBanksBytes or {})
  local currentBank = tonumber(state.currentBank) or 1
  local windows = (app.wm and app.wm.getWindows and app.wm:getWindows()) or {}
  local visibleWindows = 0
  for _, win in ipairs(windows) do
    if win and not win._closed and not win._minimized and win._groupHidden ~= true then
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
  Text.print(lines, 12, 12, {
    outline = true,
    color = colors.white,
    literalColor = true,
    font = getHudDebugFont(),
  })
end

function AppCoreController:draw()  
  DebugController.perfBeginFrame()
  love.graphics.setCanvas({ self.canvas, depthstencil = true })
  if ChrCanvasOnlyMode.isActive(self) then
    ChrCanvasOnlyMode.draw(self)
    if self.tooltipController and self.canvas then
      self.tooltipController:draw(self.canvas:getWidth(), self.canvas:getHeight())
    end
    if self.pressEscAgainExitModal then
      self.pressEscAgainExitModal:draw(self.canvas)
    end
    self.quitConfirmModal:draw(self.canvas)
    drawToasts(self)
    CursorsController.draw(self)
    love.graphics.setCanvas()
    love.graphics.setColor(colors.white)
    ResolutionController:renderCanvas()
    if ResolutionController.crtLensPostCanvasOverlayEnabled then
      ResolutionController:renderCrtLensOverlays(self)
    end
    if self.showDebugInfo then
      drawHUD(self)
    end
    DebugController.perfEndFrame()
    return
  end

  local bg = colors:appWorkspaceFill()
  -- Canvas uses depth/stencil; clear those too so UI draws are not partially rejected.
  love.graphics.clear(bg[1], bg[2], bg[3], 1, true, true)

  drawAllWindowShadows(self)
  -- Windows use full-canvas coordinates (y includes the top toolbar strip height).
  drawWindows(self)
  drawPaletteLinks(self)
  drawEmptyStatePrompt(self)
  -- Keep app top toolbar/status strip above all window content.
  AppTopToolbarController.draw(self)

  drawTranslatedNonModalOverlays(self)

  drawStatus(self)
  drawNonModalOverlays(self)
  drawOverlays(self)
  if self.tooltipController and self.canvas then
    self.tooltipController:draw(self.canvas:getWidth(), self.canvas:getHeight())
  end
  if self.splash and self.splash:isVisible() then
    self.splash:draw(self.canvas)
  end
  if self.pressEscAgainExitModal then
    self.pressEscAgainExitModal:draw(self.canvas)
  end
  self.quitConfirmModal:draw(self.canvas)
  CursorsController.draw(self)

  love.graphics.setCanvas()
  love.graphics.setColor(colors.white)

  ResolutionController:renderCanvas()
  if ResolutionController.crtLensPostCanvasOverlayEnabled then
    ResolutionController:renderCrtLensOverlays(self)
  end
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
