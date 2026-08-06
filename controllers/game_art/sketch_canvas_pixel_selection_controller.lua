-- sketch_canvas_pixel_selection_controller.lua
-- Rectangular and freeform pixel selection for sketch canvas windows.
--
-- Tool: editTool "rect_select" (toggle with S). Plain drag = rect; Shift+drag = freeform.
-- Freeform follows the mouse path and closes from the release point back to the start.
--
-- Selection lives on a floating PixelCanvas layer when lifted (move/cut), so
-- dragging does not rewrite the base paint buffer until stamp-down.

local WindowCaps = require("controllers.window.window_capabilities")
local PixelCanvas = require("ui.windows_system.pixel_canvas")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local images = require("images")
local Draw = require("utils.draw_utils")
local colors = require("app_colors")
local CanvasSpace = require("utils.canvas_space")
local UiPulse = require("utils.ui_pulse")

local M = {}

M.KIND_RECT = "rect"
M.KIND_FREE = "free"

-- Pulsating color-mask outline: "outside" (empty neighbors) or "inside" (rim of mask pixels).
M.COLOR_MASK_OUTLINE_SIDE = "inside"

local SELECTION_RECT_ANIM = {
  stepPx = 1,
  intervalSeconds = 0.1,
}

-- Perimeter outline for color paint masks: pulse black↔white on exposed pixel edges.
-- Checkerboard parity flips every COLOR_MASK_PARITY_INTERVAL for a marching-ants feel.
-- Black↔white pulse period is independent (COLOR_MASK_PULSE_PERIOD).
local COLOR_MASK_PARITY_INTERVAL = 0.1
local COLOR_MASK_PULSE_PERIOD = 1.0

local colorMaskPerimeterShader = nil
local function ensureColorMaskPerimeterShader()
  -- Always rebuild if the cached shader predates screen-space parity (missing uniform).
  if colorMaskPerimeterShader then
    local ok, _ = pcall(function()
      colorMaskPerimeterShader:send("u_wantOdd", 0)
    end)
    if ok then
      return colorMaskPerimeterShader
    end
    colorMaskPerimeterShader = nil
  end
  colorMaskPerimeterShader = love.graphics.newShader([[
extern vec2 u_size;      // mask width/height in canvas pixels
extern vec2 u_origin;    // content origin in screen pixels
extern number u_zoom;    // window zoom
extern number u_edgeFrac; // fraction of a canvas pixel for edge thickness (≈ 1/zoom)
extern number u_pulse;    // 0=black .. 1=white
extern number u_inside;   // 0=outside neighbors, 1=inside mask rim
extern number u_wantOdd;  // 1=draw odd screen pixels, 0=draw even

float maskAt(Image mask, vec2 cell) {
  if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= u_size.x || cell.y >= u_size.y) {
    return 0.0;
  }
  vec2 uv = (cell + vec2(0.5, 0.5)) / u_size;
  return Texel(mask, uv).r;
}

vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 screenCoord)
{
  vec2 canvas = (screenCoord - u_origin) / max(u_zoom, 1.0);
  vec2 cell = floor(canvas);
  vec2 frac = canvas - cell;

  float here = maskAt(tex, cell);
  bool insideMode = u_inside >= 0.5;

  // Outside: only empty cells. Inside: only mask cells.
  if (insideMode) {
    if (here < 0.5) {
      return vec4(0.0);
    }
  } else if (here >= 0.5) {
    return vec4(0.0);
  }

  float mL = maskAt(tex, cell + vec2(-1.0, 0.0));
  float mR = maskAt(tex, cell + vec2( 1.0, 0.0));
  float mU = maskAt(tex, cell + vec2( 0.0,-1.0));
  float mD = maskAt(tex, cell + vec2( 0.0, 1.0));
  float mUL = maskAt(tex, cell + vec2(-1.0,-1.0));
  float mUR = maskAt(tex, cell + vec2( 1.0,-1.0));
  float mDL = maskAt(tex, cell + vec2(-1.0, 1.0));
  float mDR = maskAt(tex, cell + vec2( 1.0, 1.0));

  float edge = max(u_edgeFrac, 0.05);
  bool onEdge;
  bool onCorner;

  if (insideMode) {
    // Draw on the rim of mask pixels facing empty neighbors.
    onEdge =
      (mL < 0.5 && frac.x <= edge) ||
      (mR < 0.5 && frac.x >= 1.0 - edge) ||
      (mU < 0.5 && frac.y <= edge) ||
      (mD < 0.5 && frac.y >= 1.0 - edge);
    // Concave exterior corners are covered by the two orthogonal rim strips.
    onCorner = false;
  } else {
    // Draw in empty neighbors just outside the mask.
    onEdge =
      (mL >= 0.5 && frac.x <= edge) ||
      (mR >= 0.5 && frac.x >= 1.0 - edge) ||
      (mU >= 0.5 && frac.y <= edge) ||
      (mD >= 0.5 && frac.y >= 1.0 - edge);
    // Convex corners: diagonal exterior cell has no orthogonal mask neighbor.
    onCorner =
      (mUL >= 0.5 && mL < 0.5 && mU < 0.5 && frac.x <= edge && frac.y <= edge) ||
      (mUR >= 0.5 && mR < 0.5 && mU < 0.5 && frac.x >= 1.0 - edge && frac.y <= edge) ||
      (mDL >= 0.5 && mL < 0.5 && mD < 0.5 && frac.x <= edge && frac.y >= 1.0 - edge) ||
      (mDR >= 0.5 && mR < 0.5 && mD < 0.5 && frac.x >= 1.0 - edge && frac.y >= 1.0 - edge);
  }

  if (!onEdge && !onCorner) {
    return vec4(0.0);
  }

  // Marching checkerboard in *screen* pixels (not canvas cells) so zoomed
  // art-pixel edges show many dots instead of one solid segment per cell.
  vec2 sp = floor(screenCoord);
  float parity = mod(sp.x + sp.y, 2.0);
  if (parity < 0.0) {
    parity += 2.0;
  }
  bool pixelOdd = parity >= 1.0;
  bool wantOdd = u_wantOdd >= 0.5;
  if (pixelOdd != wantOdd) {
    return vec4(0.0);
  }

  float p = clamp(u_pulse, 0.0, 1.0);
  return vec4(p, p, p, 1.0) * color;
}
]])
  return colorMaskPerimeterShader
end

local function colorMaskOutlineIsInside()
  return M.COLOR_MASK_OUTLINE_SIDE == "inside"
end

local function colorMaskWantOddParity()
  local t = UiPulse.nowSeconds()
  return (math.floor(t / COLOR_MASK_PARITY_INTERVAL) % 2) == 0
end

--- Luminance 0=black → 1=white → 0 over COLOR_MASK_PULSE_PERIOD seconds.
local function colorMaskPulse01(t)
  local w = (2 * math.pi) / COLOR_MASK_PULSE_PERIOD
  return (1 - math.cos(w * t)) / 2
end

local function resolvePaint(win)
  if not WindowCaps.isSketchCanvas(win) then
    return nil
  end
  if win.getActiveCanvas then
    return win:getActiveCanvas()
  end
  return nil
end

local function markSketchDirty(win)
  if SketchCanvasPackController.markGenerateDirty then
    SketchCanvasPackController.markGenerateDirty(win)
  end
end

local function normalizeRect(x0, y0, x1, y1)
  local x = math.min(x0, x1)
  local y = math.min(y0, y1)
  local w = math.abs(x1 - x0) + 1
  local h = math.abs(y1 - y0) + 1
  return x, y, w, h
end

local function clampRectToCanvas(paint, x, y, w, h)
  if not paint then
    return nil
  end
  local x2 = x + w - 1
  local y2 = y + h - 1
  if x < 0 then x = 0 end
  if y < 0 then y = 0 end
  if x2 >= paint.width then x2 = paint.width - 1 end
  if y2 >= paint.height then y2 = paint.height - 1 end
  local rw = x2 - x + 1
  local rh = y2 - y + 1
  if rw < 1 or rh < 1 then
    return nil
  end
  return x, y, rw, rh
end

local function clampPointToCanvas(paint, x, y)
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  if not paint then
    return x, y
  end
  if x < 0 then x = 0 end
  if y < 0 then y = 0 end
  if x >= paint.width then x = paint.width - 1 end
  if y >= paint.height then y = paint.height - 1 end
  return x, y
end

--- Bresenham: append pixels from (x0,y0) to (x1,y1). Skips the first point when it
--- matches the current path tip (avoids duplicates while chaining segments).
local function appendLineToPath(path, x0, y0, x1, y1)
  x0, y0 = math.floor(x0), math.floor(y0)
  x1, y1 = math.floor(x1), math.floor(y1)
  local dx = math.abs(x1 - x0)
  local dy = math.abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx - dy
  local x, y = x0, y0
  local first = true
  while true do
    if not first or #path == 0 then
      local tip = path[#path]
      if not (tip and tip.x == x and tip.y == y) then
        path[#path + 1] = { x = x, y = y }
      end
    elseif #path > 0 then
      local tip = path[#path]
      if not (tip and tip.x == x and tip.y == y) then
        path[#path + 1] = { x = x, y = y }
      end
    else
      path[1] = { x = x, y = y }
    end
    first = false
    if x == x1 and y == y1 then
      break
    end
    local e2 = 2 * err
    if e2 > -dy then
      err = err - dy
      x = x + sx
    end
    if e2 < dx then
      err = err + dx
      y = y + sy
    end
  end
end

local function maskIndex(w, lx, ly)
  return ly * w + lx + 1
end

local function maskGet(sel, lx, ly)
  if not (sel and sel.mask and sel.w and sel.h) then
    return true
  end
  if lx < 0 or ly < 0 or lx >= sel.w or ly >= sel.h then
    return false
  end
  return sel.mask[maskIndex(sel.w, lx, ly)] == true
end

--- Build an axis-aligned mask covering the polygon (even-odd fill) plus the stroke.
--  Returns mask, x, y, w, h or nil.
local function buildMaskFromClosedPath(path, paint)
  if type(path) ~= "table" or #path < 1 then
    return nil
  end

  local pts = {}
  local minX, minY = math.huge, math.huge
  local maxX, maxY = -math.huge, -math.huge
  for i = 1, #path do
    local px, py = clampPointToCanvas(paint, path[i].x, path[i].y)
    pts[#pts + 1] = { x = px, y = py }
    if px < minX then minX = px end
    if py < minY then minY = py end
    if px > maxX then maxX = px end
    if py > maxY then maxY = py end
  end

  -- Ensure closed for fill (duplicate start at end if needed).
  local first, last = pts[1], pts[#pts]
  if not (last.x == first.x and last.y == first.y) then
    pts[#pts + 1] = { x = first.x, y = first.y }
  end

  local x, y, w, h = clampRectToCanvas(paint, minX, minY, maxX - minX + 1, maxY - minY + 1)
  if not x then
    return nil
  end

  local mask = {}
  for i = 1, w * h do
    mask[i] = false
  end

  local function setLocal(lx, ly)
    if lx >= 0 and ly >= 0 and lx < w and ly < h then
      mask[maskIndex(w, lx, ly)] = true
    end
  end

  -- Stroke: every path pixel is selected (thin lassos still work).
  for i = 1, #pts do
    setLocal(pts[i].x - x, pts[i].y - y)
  end

  -- Even-odd scanline fill for the interior.
  if #pts >= 4 then
    for row = 0, h - 1 do
      local scanY = y + row + 0.5
      local xs = {}
      for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        local y0, y1 = a.y + 0.0, b.y + 0.0
        if (y0 <= scanY and b.y > scanY) or (y1 <= scanY and a.y > scanY) then
          local t = (scanY - y0) / (y1 - y0)
          xs[#xs + 1] = a.x + t * (b.x - a.x)
        end
      end
      table.sort(xs)
      for i = 1, #xs - 1, 2 do
        local x0 = math.floor(xs[i] - x + 0.5)
        local x1 = math.floor(xs[i + 1] - x + 0.5)
        if x0 > x1 then
          x0, x1 = x1, x0
        end
        for lx = x0, x1 do
          setLocal(lx, row)
        end
      end
    end
  end

  local any = false
  for i = 1, #mask do
    if mask[i] then
      any = true
      break
    end
  end
  if not any then
    return nil
  end
  return mask, x, y, w, h
end

function M.getSelection(win)
  return win and win.pixelSelection or nil
end

function M.hasSelection(win)
  local sel = M.getSelection(win)
  return not not (sel and type(sel.w) == "number" and sel.w > 0 and type(sel.h) == "number" and sel.h > 0)
end

function M.isSelectTool(editTool)
  return editTool == "rect_select" or editTool == "free_select"
end

----------------------------------------------------------------
-- Same-color paint mask (hold C + click): paint/fill only those pixels.
----------------------------------------------------------------

function M.getColorPaintMask(win)
  return win and win.colorPaintMask or nil
end

function M.hasColorPaintMask(win)
  local mask = M.getColorPaintMask(win)
  return not not (mask and type(mask.bits) == "table" and (mask.count or 0) > 0)
end

function M.clearColorPaintMask(win)
  if not win or not win.colorPaintMask then
    return false
  end
  win.colorPaintMask = nil
  return true
end

local function colorMaskIndex(width, x, y)
  return y * width + x + 1
end

local function ensureColorMaskOutlineTexture(mask)
  if not mask or type(mask.bits) ~= "table" then
    return nil
  end
  if mask._outlineImage then
    return mask._outlineImage
  end
  if not (love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then
    return nil
  end

  local w = math.floor(tonumber(mask.width) or 0)
  local h = math.floor(tonumber(mask.height) or 0)
  if w < 1 or h < 1 then
    return nil
  end

  local id = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if mask.bits[colorMaskIndex(w, x, y)] == true then
        id:setPixel(x, y, 1, 1, 1, 1)
      else
        id:setPixel(x, y, 0, 0, 0, 0)
      end
    end
  end
  local img = love.graphics.newImage(id)
  img:setFilter("nearest", "nearest")
  img:setWrap("clamp", "clamp")
  mask._outlineImage = img
  return img
end

--- Build a static mask of every canvas pixel equal to `color` (0..3).
--  Returns mask table or nil, count.
function M.buildColorPaintMask(win, color)
  local paint = resolvePaint(win)
  if not paint then
    return nil, 0
  end
  color = math.floor(tonumber(color) or 0)
  if color < 0 then color = 0 end
  if color > 3 then color = 3 end

  local w = paint.width
  local h = paint.height
  local bits = {}
  local count = 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if (paint:getPixel(x, y) or 0) == color then
        bits[colorMaskIndex(w, x, y)] = true
        count = count + 1
      end
    end
  end

  local mask = {
    color = color,
    width = w,
    height = h,
    bits = bits,
    count = count,
  }
  return mask, count
end

--- Sample the color at (px, py) and mask every canvas pixel of that color.
--  @return ok boolean, count number, color number|nil, err string|nil
function M.applyColorPaintMaskAt(win, px, py)
  if not WindowCaps.isSketchCanvas(win) then
    return false, 0, nil, "not_sketch_canvas"
  end
  if WindowCaps.isSketchReflectNametable(win) then
    return false, 0, nil, "tile_mode"
  end
  local paint = resolvePaint(win)
  if not paint then
    return false, 0, nil, "no_canvas"
  end
  px, py = clampPointToCanvas(paint, px, py)
  local color = math.floor(tonumber(paint:getPixel(px, py)) or 0)
  local mask, count = M.buildColorPaintMask(win, color)
  if not mask then
    return false, 0, color, "build_failed"
  end
  win.colorPaintMask = mask
  return true, count, color, nil
end

--- When a color paint mask is active, only masked pixels may be painted.
function M.allowsColorPaintAt(win, px, py)
  local mask = M.getColorPaintMask(win)
  if not mask then
    return true
  end
  px = math.floor(tonumber(px) or 0)
  py = math.floor(tonumber(py) or 0)
  if px < 0 or py < 0 or px >= mask.width or py >= mask.height then
    return false
  end
  return mask.bits[colorMaskIndex(mask.width, px, py)] == true
end

function M.clearSelection(win, opts)
  opts = opts or {}
  local sel = M.getSelection(win)
  if not sel then
    return false
  end
  if sel.lifted and sel.floating then
    if opts.stamp ~= false then
      M.stampDown(win, opts.app)
    else
      M.cancelFloating(win, opts.app)
      return true
    end
  end
  win.pixelSelection = nil
  return true
end

--- Begin a new selection gesture.
--  kind: "rect" or "free" (Shift+drag while select tool is active).
function M.begin(win, kind, x, y, app)
  kind = kind or M.KIND_RECT
  if kind ~= M.KIND_RECT and kind ~= M.KIND_FREE then
    return false, "unknown_selection_kind"
  end
  if not WindowCaps.isSketchCanvas(win) then
    return false, "not_sketch_canvas"
  end
  if WindowCaps.isSketchReflectNametable(win) then
    return false, "tile_mode"
  end

  if win.pixelSelection and win.pixelSelection.lifted and win.pixelSelection.floating then
    M.stampDown(win, app)
  end

  local paint = resolvePaint(win)
  x, y = clampPointToCanvas(paint, x, y)
  local freePath = nil
  if kind == M.KIND_FREE then
    freePath = { { x = x, y = y } }
  end

  win.pixelSelection = {
    kind = kind,
    dragging = {
      startX = x,
      startY = y,
      currentX = x,
      currentY = y,
    },
    x = nil,
    y = nil,
    w = nil,
    h = nil,
    floating = nil,
    floatingOffsetX = 0,
    floatingOffsetY = 0,
    lifted = false,
    liftUndo = nil,
    moveDrag = nil,
    freePath = freePath,
    mask = nil,
  }
  return true
end

function M.updateDrag(win, x, y)
  local sel = M.getSelection(win)
  if not (sel and sel.dragging) then
    return false
  end
  local paint = resolvePaint(win)
  x, y = clampPointToCanvas(paint, x, y)
  local prevX = sel.dragging.currentX
  local prevY = sel.dragging.currentY
  sel.dragging.currentX = x
  sel.dragging.currentY = y

  if sel.kind == M.KIND_FREE and sel.freePath then
    appendLineToPath(sel.freePath, prevX, prevY, x, y)
  end
  return true
end

function M.commitDrag(win)
  local sel = M.getSelection(win)
  if not (sel and sel.dragging) then
    return false
  end

  local paint = resolvePaint(win)
  local d = sel.dragging

  if sel.kind == M.KIND_FREE then
    if not sel.freePath or #sel.freePath < 1 then
      win.pixelSelection = nil
      return false
    end
    -- Close release → start (lasso closure).
    appendLineToPath(sel.freePath, d.currentX, d.currentY, d.startX, d.startY)
    local mask, cx, cy, cw, ch = buildMaskFromClosedPath(sel.freePath, paint)
    sel.dragging = nil
    if not mask then
      win.pixelSelection = nil
      return false
    end
    sel.x, sel.y, sel.w, sel.h = cx, cy, cw, ch
    sel.mask = mask
    sel.floating = nil
    sel.lifted = false
    sel.floatingOffsetX = sel.x
    sel.floatingOffsetY = sel.y
    return true
  end

  local x, y, w, h = normalizeRect(d.startX, d.startY, d.currentX, d.currentY)
  local cx, cy, cw, ch = clampRectToCanvas(paint, x, y, w, h)
  sel.dragging = nil
  if not cx then
    win.pixelSelection = nil
    return false
  end
  sel.x, sel.y, sel.w, sel.h = cx, cy, cw, ch
  sel.mask = nil
  sel.freePath = nil
  sel.floating = nil
  sel.lifted = false
  sel.floatingOffsetX = sel.x
  sel.floatingOffsetY = sel.y
  return true
end

function M.hitTest(win, canvasX, canvasY)
  local sel = M.getSelection(win)
  if not M.hasSelection(win) then
    return false
  end
  local ox = sel.lifted and (sel.floatingOffsetX or sel.x) or sel.x
  local oy = sel.lifted and (sel.floatingOffsetY or sel.y) or sel.y
  local px = math.floor(tonumber(canvasX) or -1)
  local py = math.floor(tonumber(canvasY) or -1)
  local lx = px - ox
  local ly = py - oy
  if lx < 0 or ly < 0 or lx >= sel.w or ly >= sel.h then
    return false
  end
  if sel.mask then
    return maskGet(sel, lx, ly)
  end
  return true
end

local function recordPixelChange(app, canvas, x, y, before, after)
  if not (app and app.undoRedo and app.undoRedo.recordDirectPixelChange) then
    return
  end
  if before == after then
    return
  end
  app.undoRedo:recordDirectPixelChange(canvas, x, y, before, after)
end

local function scrubAndFinishPaintEvent(app)
  if not (app and app.undoRedo) then
    return false
  end
  local ur = app.undoRedo
  if not ur.takePaintEvent or not ur.addPaintEvent then
    if ur.finishPaintEvent then
      return ur:finishPaintEvent()
    end
    return false
  end
  local event = ur:takePaintEvent()
  if not event then
    return false
  end
  if type(event.pixels) == "table" then
    for key, pixel in pairs(event.pixels) do
      if pixel and pixel.before == pixel.after then
        event.pixels[key] = nil
      end
    end
  end
  return ur:addPaintEvent(event)
end

local function replayLiftUndoIntoPaintEvent(app, canvas, liftUndo)
  if not (liftUndo and canvas) then
    return
  end
  for i = 1, #liftUndo do
    local ch = liftUndo[i]
    recordPixelChange(app, canvas, ch.x, ch.y, ch.before, ch.after)
  end
end

local function restoreLiftUndo(paint, liftUndo)
  if not (paint and liftUndo) then
    return false
  end
  local any = false
  for i = 1, #liftUndo do
    local ch = liftUndo[i]
    if paint:edit(ch.x, ch.y, ch.before) then
      any = true
    end
  end
  return any
end

--- Lift selection pixels onto the floating layer (clears the base under the mask/rect).
--- Undo for the hole is deferred until stamp/cut so move+apply is one undo step.
function M.ensureLifted(win, app)
  local sel = M.getSelection(win)
  if not M.hasSelection(win) then
    return false
  end
  if sel.lifted and sel.floating then
    return true
  end
  local paint = resolvePaint(win)
  if not paint then
    return false
  end

  local extracted = paint:extractRect(sel.x, sel.y, sel.w, sel.h)
  if not extracted then
    return false
  end

  local fill = paint.fillValue or 0
  local liftUndo = {}
  for py = 0, sel.h - 1 do
    for px = 0, sel.w - 1 do
      local inMask = maskGet(sel, px, py)
      if not inMask then
        extracted:edit(px, py, fill)
      else
        local bx, by = sel.x + px, sel.y + py
        local before = paint:getPixel(bx, by)
        if before ~= nil and before ~= fill and paint:edit(bx, by, fill) then
          liftUndo[#liftUndo + 1] = {
            x = bx,
            y = by,
            before = before,
            after = fill,
          }
        end
      end
    end
  end

  sel.floating = extracted
  sel.floatingOffsetX = sel.x
  sel.floatingOffsetY = sel.y
  sel.lifted = true
  sel.liftUndo = liftUndo
  markSketchDirty(win)
  return true
end

function M.beginMove(win, canvasX, canvasY, app)
  if not M.hitTest(win, canvasX, canvasY) then
    return false
  end
  if not M.ensureLifted(win, app) then
    return false
  end
  local sel = M.getSelection(win)
  sel.moveDrag = {
    grabX = math.floor(tonumber(canvasX) or 0),
    grabY = math.floor(tonumber(canvasY) or 0),
    origOffsetX = sel.floatingOffsetX or sel.x,
    origOffsetY = sel.floatingOffsetY or sel.y,
  }
  return true
end

function M.updateMove(win, canvasX, canvasY)
  local sel = M.getSelection(win)
  if not (sel and sel.moveDrag and sel.lifted) then
    return false
  end
  local dx = math.floor(tonumber(canvasX) or 0) - sel.moveDrag.grabX
  local dy = math.floor(tonumber(canvasY) or 0) - sel.moveDrag.grabY
  sel.floatingOffsetX = sel.moveDrag.origOffsetX + dx
  sel.floatingOffsetY = sel.moveDrag.origOffsetY + dy
  return true
end

function M.endMove(win)
  local sel = M.getSelection(win)
  if not (sel and sel.moveDrag) then
    return false
  end
  sel.moveDrag = nil
  sel.x = sel.floatingOffsetX
  sel.y = sel.floatingOffsetY
  return true
end

--- Stamp floating pixels back onto the base paint buffer and keep selection bounds.
--- Index 0 (canvas fill / ROM palette transparent) is treated as a hole.
function M.stampDown(win, app)
  local sel = M.getSelection(win)
  if not (sel and sel.lifted and sel.floating) then
    return false
  end
  local paint = resolvePaint(win)
  if not paint then
    return false
  end

  local ox = sel.floatingOffsetX or sel.x or 0
  local oy = sel.floatingOffsetY or sel.y or 0
  local fw, fh = sel.floating.width, sel.floating.height
  local transparent = paint.fillValue or 0
  local liftUndo = sel.liftUndo

  if app and app.undoRedo and app.undoRedo.startPaintEvent then
    app.undoRedo:startPaintEvent()
  end
  replayLiftUndoIntoPaintEvent(app, paint, liftUndo)
  for py = 0, fh - 1 do
    for px = 0, fw - 1 do
      if maskGet(sel, px, py) then
        local after = sel.floating:getPixel(px, py)
        if after ~= nil and after ~= transparent then
          local dx, dy = ox + px, oy + py
          local before = paint:getPixel(dx, dy)
          if before ~= nil and paint:edit(dx, dy, after) then
            recordPixelChange(app, paint, dx, dy, before, after)
          end
        end
      end
    end
  end
  scrubAndFinishPaintEvent(app)

  sel.x = ox
  sel.y = oy
  sel.w = fw
  sel.h = fh
  sel.floating = nil
  sel.lifted = false
  sel.liftUndo = nil
  sel.floatingOffsetX = ox
  sel.floatingOffsetY = oy
  markSketchDirty(win)
  return true
end

function M.cancelFloating(win, _app)
  local sel = M.getSelection(win)
  if not (sel and sel.lifted) then
    return false
  end
  local paint = resolvePaint(win)
  if sel.liftUndo and paint then
    restoreLiftUndo(paint, sel.liftUndo)
    markSketchDirty(win)
  end
  win.pixelSelection = nil
  return true
end

function M.hasFloatingSelection(win)
  local sel = M.getSelection(win)
  return not not (sel and sel.lifted and sel.floating)
end

function M.captureClipboard(win)
  local sel = M.getSelection(win)
  if not M.hasSelection(win) then
    return nil
  end
  local paint = resolvePaint(win)
  if not paint then
    return nil
  end

  local source
  if sel.lifted and sel.floating then
    source = sel.floating
  else
    source = paint:extractRect(sel.x, sel.y, sel.w, sel.h)
    if not source then
      return nil
    end
    if sel.mask then
      local fill = paint.fillValue or 0
      for py = 0, sel.h - 1 do
        for px = 0, sel.w - 1 do
          if not maskGet(sel, px, py) then
            source:edit(px, py, fill)
          end
        end
      end
    end
  end

  local pixels = {}
  for i = 1, #source.pixels do
    pixels[i] = source.pixels[i]
  end
  local oxPos = sel.lifted and (sel.floatingOffsetX or sel.x) or sel.x
  local oyPos = sel.lifted and (sel.floatingOffsetY or sel.y) or sel.y
  local maskCopy = nil
  if sel.mask then
    maskCopy = {}
    for i = 1, #sel.mask do
      maskCopy[i] = sel.mask[i]
    end
  end
  return {
    kind = "sketch_pixels",
    width = source.width,
    height = source.height,
    pixels = pixels,
    selectionKind = sel.kind or M.KIND_RECT,
    originX = oxPos,
    originY = oyPos,
    mask = maskCopy,
  }
end

function M.cutSelection(win, app)
  local clip = M.captureClipboard(win)
  if not clip then
    return nil
  end
  if not M.ensureLifted(win, app) then
    return clip
  end
  local sel = M.getSelection(win)
  local paint = resolvePaint(win)
  local liftUndo = sel and sel.liftUndo

  if app and app.undoRedo and app.undoRedo.startPaintEvent then
    app.undoRedo:startPaintEvent()
  end
  replayLiftUndoIntoPaintEvent(app, paint, liftUndo)
  scrubAndFinishPaintEvent(app)

  win.pixelSelection = nil
  markSketchDirty(win)
  return clip
end

function M.pasteClipboard(win, clipboard, app, atX, atY)
  if not (clipboard and clipboard.kind == "sketch_pixels") then
    return false, "empty_or_wrong_kind"
  end
  if not WindowCaps.isSketchCanvas(win) then
    return false, "not_sketch_canvas"
  end
  if WindowCaps.isSketchReflectNametable(win) then
    return false, "tile_mode"
  end
  local paint = resolvePaint(win)
  if not paint then
    return false, "no_canvas"
  end

  local w = math.floor(tonumber(clipboard.width) or 0)
  local h = math.floor(tonumber(clipboard.height) or 0)
  if w < 1 or h < 1 or type(clipboard.pixels) ~= "table" then
    return false, "bad_payload"
  end

  if win.pixelSelection and win.pixelSelection.lifted then
    M.stampDown(win, app)
  end

  local x = math.floor(tonumber(atX) or 0)
  local y = math.floor(tonumber(atY) or 0)
  if x < 0 then x = 0 end
  if y < 0 then y = 0 end
  if x >= paint.width then x = math.max(0, paint.width - w) end
  if y >= paint.height then y = math.max(0, paint.height - h) end

  local floating = PixelCanvas.new(w, h, paint.fillValue or 0)
  for i = 1, w * h do
    floating.pixels[i] = clipboard.pixels[i] or floating.fillValue
  end
  floating._imageDirty = true

  local mask = nil
  if type(clipboard.mask) == "table" and #clipboard.mask == w * h then
    mask = {}
    for i = 1, w * h do
      mask[i] = clipboard.mask[i] == true
    end
  end

  win.pixelSelection = {
    kind = clipboard.selectionKind == M.KIND_FREE and M.KIND_FREE or M.KIND_RECT,
    dragging = nil,
    x = x,
    y = y,
    w = w,
    h = h,
    floating = floating,
    floatingOffsetX = x,
    floatingOffsetY = y,
    lifted = true,
    liftUndo = nil,
    moveDrag = nil,
    freePath = nil,
    mask = mask,
  }
  return true
end

function M.screenToCanvasPixel(win, screenX, screenY)
  if not (win and win.toContentCoords) then
    return nil
  end
  local ok, cx, cy = win:toContentCoords(screenX, screenY)
  if not ok then
    return nil
  end
  return math.floor(cx), math.floor(cy)
end

local function drawAntsRect(ox, oy, z, cx, cy, cw, ch)
  local rx = ox + cx * z
  local ry = oy + cy * z
  local rw = cw * z
  local rh = ch * z
  if rw < 1 or rh < 1 then
    return
  end
  Draw.drawRepeatingImageAnimated(
    images.pattern_a,
    math.floor(rx),
    math.floor(ry),
    math.max(1, math.floor(rw)),
    math.max(1, math.floor(rh)),
    SELECTION_RECT_ANIM
  )
end

local function drawPathAnts(ox, oy, z, path, closeToStart)
  if type(path) ~= "table" or #path < 1 then
    return
  end
  love.graphics.setColor(colors.white)
  for i = 1, #path do
    local p = path[i]
    drawAntsRect(ox, oy, z, p.x, p.y, 1, 1)
  end
  if closeToStart and #path >= 1 then
    local a = path[#path]
    local b = path[1]
    local tmp = {}
    appendLineToPath(tmp, a.x, a.y, b.x, b.y)
    for i = 2, #tmp do
      local p = tmp[i]
      drawAntsRect(ox, oy, z, p.x, p.y, 1, 1)
    end
  end
end

local function drawMaskOutlineAnts(ox, oy, z, sel, bx, by, inside, wantOdd)
  if not (sel and sel.mask and sel.w and sel.h) then
    drawAntsRect(ox, oy, z, bx, by, sel.w, sel.h)
    return
  end

  local w, h = sel.w, sel.h

  -- Color-mask path (wantOdd set): 1 screen-pixel dots along edges, screen parity.
  if wantOdd ~= nil then
    local function screenParityOk(sx, sy)
      local odd = ((sx + sy) % 2) ~= 0
      return odd == wantOdd
    end
    local function dot(sx, sy)
      if screenParityOk(sx, sy) then
        love.graphics.rectangle("fill", sx, sy, 1, 1)
      end
    end
    local function edgeStripHorizontal(x0, x1, sy)
      local xa, xb = math.min(x0, x1), math.max(x0, x1)
      for sx = xa, xb - 1 do
        dot(sx, sy)
      end
    end
    local function edgeStripVertical(sx, y0, y1)
      local ya, yb = math.min(y0, y1), math.max(y0, y1)
      for sy = ya, yb - 1 do
        dot(sx, sy)
      end
    end

    local function emitCellEdges(lx, ly)
      local x0 = math.floor(ox + (bx + lx) * z)
      local y0 = math.floor(oy + (by + ly) * z)
      local x1 = math.floor(ox + (bx + lx + 1) * z)
      local y1 = math.floor(oy + (by + ly + 1) * z)
      if inside then
        if not maskGet(sel, lx - 1, ly) then edgeStripVertical(x0, y0, y1) end
        if not maskGet(sel, lx + 1, ly) then edgeStripVertical(x1 - 1, y0, y1) end
        if not maskGet(sel, lx, ly - 1) then edgeStripHorizontal(x0, x1, y0) end
        if not maskGet(sel, lx, ly + 1) then edgeStripHorizontal(x0, x1, y1 - 1) end
      else
        if maskGet(sel, lx - 1, ly) then edgeStripVertical(x0, y0, y1) end
        if maskGet(sel, lx + 1, ly) then edgeStripVertical(x1 - 1, y0, y1) end
        if maskGet(sel, lx, ly - 1) then edgeStripHorizontal(x0, x1, y0) end
        if maskGet(sel, lx, ly + 1) then edgeStripHorizontal(x0, x1, y1 - 1) end
      end
    end

    if inside then
      for ly = 0, h - 1 do
        for lx = 0, w - 1 do
          if maskGet(sel, lx, ly) then
            emitCellEdges(lx, ly)
          end
        end
      end
    else
      for ly = -1, h do
        for lx = -1, w do
          if not maskGet(sel, lx, ly) then
            emitCellEdges(lx, ly)
          end
        end
      end
    end
    return
  end

  -- Selection overlay path: canvas-cell ants rects (unchanged).
  if inside then
    for ly = 0, h - 1 do
      for lx = 0, w - 1 do
        if maskGet(sel, lx, ly) then
          local edge = not maskGet(sel, lx - 1, ly)
            or not maskGet(sel, lx + 1, ly)
            or not maskGet(sel, lx, ly - 1)
            or not maskGet(sel, lx, ly + 1)
          if edge then
            drawAntsRect(ox, oy, z, bx + lx, by + ly, 1, 1)
          end
        end
      end
    end
    return
  end

  for ly = -1, h do
    for lx = -1, w do
      if not maskGet(sel, lx, ly) then
        local edge = maskGet(sel, lx - 1, ly)
          or maskGet(sel, lx + 1, ly)
          or maskGet(sel, lx, ly - 1)
          or maskGet(sel, lx, ly + 1)
        if edge then
          drawAntsRect(ox, oy, z, bx + lx, by + ly, 1, 1)
        end
      end
    end
  end
end

function M.drawOverlay(win, isFocused)
  local sel = M.getSelection(win)
  if not sel then
    return
  end

  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local ox, oy = win:getContentScreenOrigin()
  local sx, sy, sw, sh = win:getInsetContentScreenRect()
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)

  if sel.dragging then
    if sel.kind == M.KIND_FREE and sel.freePath then
      drawPathAnts(ox, oy, z, sel.freePath, true)
    else
      local x, y, w, h = normalizeRect(
        sel.dragging.startX,
        sel.dragging.startY,
        sel.dragging.currentX,
        sel.dragging.currentY
      )
      love.graphics.setColor(colors.white)
      drawAntsRect(ox, oy, z, x, y, w, h)
    end
    love.graphics.setScissor()
    return
  end

  if not M.hasSelection(win) then
    love.graphics.setScissor()
    return
  end

  local bx = sel.lifted and (sel.floatingOffsetX or sel.x) or sel.x
  local by = sel.lifted and (sel.floatingOffsetY or sel.y) or sel.y

  if sel.lifted and sel.floating then
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(z, z)
    local layer = win.layers and win.layers[(win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1]
    local romRaw = nil
    if _G.ctx and _G.ctx.app and _G.ctx.app.appEditState then
      romRaw = _G.ctx.app.appEditState.romRaw
    end
    if layer then
      ShaderPaletteController.applyLayerItemPalette(layer, sel.floating, true, romRaw, nil, 1.0)
    end
    love.graphics.setColor(1, 1, 1, 1)
    sel.floating:draw(bx, by, 1)
    if layer then
      ShaderPaletteController.releaseShader()
    end
    love.graphics.pop()
  end

  love.graphics.setColor(colors.white)
  if sel.mask then
    drawMaskOutlineAnts(ox, oy, z, sel, bx, by, true)
  else
    drawAntsRect(ox, oy, z, bx, by, sel.w, sel.h)
  end
  love.graphics.setScissor()
end

function M.drawColorPaintMaskOverlay(win)
  local mask = M.getColorPaintMask(win)
  if not (mask and mask.bits and mask.count and mask.count > 0) then
    return
  end

  local inside = colorMaskOutlineIsInside()
  local wantOdd = colorMaskWantOddParity()
  local outline = ensureColorMaskOutlineTexture(mask)
  local shader = outline and ensureColorMaskPerimeterShader() or nil
  if not (outline and shader) then
    -- Fallback: CPU marching-ants edge rects if Image/Shader unavailable.
    local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
    local ox, oy = win:getContentScreenOrigin()
    local sx, sy, sw, sh = win:getInsetContentScreenRect()
    local pad = inside and 0 or z
    CanvasSpace.setScissorFromContentRect(sx - pad, sy - pad, sw + 2 * pad, sh + 2 * pad)
    love.graphics.setColor(colors.white)
    drawMaskOutlineAnts(ox, oy, z, { mask = mask.bits, w = mask.width, h = mask.height }, 0, 0, inside, wantOdd)
    love.graphics.setScissor()
    return
  end

  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  if z < 1 then z = 1 end
  local ox, oy = win:getContentScreenOrigin()
  local sx, sy, sw, sh = win:getInsetContentScreenRect()
  -- Outside mode needs one canvas-pixel of pad so border edges remain visible.
  local pad = inside and 0 or z
  CanvasSpace.setScissorFromContentRect(sx - pad, sy - pad, sw + 2 * pad, sh + 2 * pad)

  local pulse = colorMaskPulse01(UiPulse.nowSeconds())
  shader:send("u_size", { mask.width, mask.height })
  shader:send("u_origin", { ox, oy })
  shader:send("u_zoom", z)
  -- ~1 screen pixel of edge thickness.
  -- Cap at 1.0 (full canvas cell) so zoom 1 still covers the single screen pixel.
  shader:send("u_edgeFrac", math.min(1.0, 1.0 / z))
  shader:send("u_pulse", pulse)
  shader:send("u_inside", inside and 1 or 0)
  shader:send("u_wantOdd", wantOdd and 1 or 0)

  love.graphics.setShader(shader)
  love.graphics.setColor(1, 1, 1, 1)
  if pad > 0 then
    local scaleX = ((mask.width + 2) * z) / mask.width
    local scaleY = ((mask.height + 2) * z) / mask.height
    love.graphics.draw(outline, ox - pad, oy - pad, 0, scaleX, scaleY)
  else
    love.graphics.draw(outline, ox, oy, 0, z, z)
  end
  love.graphics.setShader()
  love.graphics.setColor(colors.white)
  love.graphics.setScissor()
end

return M
