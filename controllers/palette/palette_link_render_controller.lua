local ResolutionController = require("controllers.app.resolution_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local colors = require("app_colors")

local M = {}
local isMouseInsideSquareHoverArea

local SOURCE_SQUARE_SIZE = 3
local DESTINATION_SQUARE_SIZE = 7
local DESTINATION_HIT_SIZE = DESTINATION_SQUARE_SIZE + 4

local function isPointInsideSquare(cx, cy, size, x, y)
  local half = math.floor((size or 1) / 2)
  return x >= (cx - half) and x <= (cx + half)
    and y >= (cy - half) and y <= (cy + half)
end

local function getScaledMousePosition()
  local mouse = ResolutionController:getScaledMouse(true)
  local mx = mouse and mouse.x or nil
  local my = mouse and mouse.y or nil
  if type(mx) ~= "number" or type(my) ~= "number" then
    mx, my = love.mouse.getPosition()
  end
  return mx, my
end

local function roundPixel(value)
  return math.floor((tonumber(value) or 0) + 0.5)
end

local function buildElbowControlPoints(ax, ay, bx, by)
  local axq = roundPixel(ax)
  local ayq = roundPixel(ay)
  local bxq = roundPixel(bx)
  local byq = roundPixel(by)
  local dx = bxq - axq
  local dy = byq - ayq
  if math.abs(dx) >= math.abs(dy) then
    local midX = axq + math.floor(dx * 0.5)
    -- Horizontal, then vertical, then horizontal (3 segments).
    return midX, ayq, midX, byq
  end
  local midY = ayq + math.floor(dy * 0.5)
  -- Vertical, then horizontal, then vertical (3 segments).
  return axq, midY, bxq, midY
end

local function buildRectilinearPoints(ax, ay, bx, by)
  local axq = roundPixel(ax)
  local ayq = roundPixel(ay)
  local bxq = roundPixel(bx)
  local byq = roundPixel(by)
  local c1x, c1y, c2x, c2y = buildElbowControlPoints(axq, ayq, bxq, byq)
  return {
    axq, ayq,
    roundPixel(c1x), roundPixel(c1y),
    roundPixel(c2x), roundPixel(c2y),
    bxq, byq,
  }
end

local function eachLayer(layers, fn)
  if type(layers) ~= "table" or type(fn) ~= "function" then
    return
  end

  local numericKeys = {}
  for key, value in pairs(layers) do
    if type(key) == "number" and value ~= nil then
      numericKeys[#numericKeys + 1] = key
    end
  end
  table.sort(numericKeys)

  for _, key in ipairs(numericKeys) do
    fn(layers[key], key)
  end
end

local function collectLinkedPaletteWindowsForWindow(win, wm)
  local paletteWindows = {}
  local seen = {}
  local layers = win and win.layers or nil
  if not (layers and wm) then
    return paletteWindows
  end

  eachLayer(layers, function(layer)
    local paletteWin = M.getPaletteWindowForLayer(layer, wm)
    if paletteWin and not seen[paletteWin] then
      seen[paletteWin] = true
      paletteWindows[#paletteWindows + 1] = paletteWin
    end
  end)

  return paletteWindows
end

local function windowHasPaletteLinkTo(win, paletteWin, wm)
  if not (win and paletteWin and wm) then
    return false
  end

  for _, linkedPaletteWin in ipairs(collectLinkedPaletteWindowsForWindow(win, wm)) do
    if linkedPaletteWin == paletteWin then
      return true
    end
  end

  return false
end

local function paletteHasLinkedTargets(paletteWin, wm)
  if not (paletteWin and wm and wm.getWindows and WindowCaps.isRomPaletteWindow(paletteWin)) then
    return false
  end

  for _, win in ipairs(wm:getWindows()) do
    if win ~= paletteWin and not win._closed and not win._minimized and not WindowCaps.isAnyPaletteWindow(win) then
      if windowHasPaletteLinkTo(win, paletteWin, wm) then
        return true
      end
    end
  end

  return false
end

local function paletteHasVisibleLinks(app, paletteWin)
  local wm = app and app.wm
  if not (paletteWin and wm and wm.getWindows and WindowCaps.isRomPaletteWindow(paletteWin)) then
    return false
  end

  for _, win in ipairs(wm:getWindows()) do
    if win ~= paletteWin and not win._closed and not win._minimized and not WindowCaps.isAnyPaletteWindow(win) then
      if windowHasPaletteLinkTo(win, paletteWin, wm) then
        local showLine = M.getPersistentVisual(app, win, paletteWin)
        if showLine then
          return true
        end
      end
    end
  end

  return false
end

function M.getPaletteWindowForLayer(layer, wm)
  if not (layer and layer.paletteData and wm) then
    return nil
  end

  local pd = layer.paletteData
  if pd.winId then
    local linked = wm:findWindowById(pd.winId)
    if linked and not linked._closed and not linked._minimized and WindowCaps.isRomPaletteWindow(linked) then
      return linked
    end
  end

  return nil
end

function M.getFocusedLinks(app)
  local wm = app and app.wm
  if not (wm and wm.getFocus) then
    return {}
  end

  local focused = wm:getFocus()
  if not focused or focused._closed or focused._minimized then
    return {}
  end

  if not WindowCaps.isAnyPaletteWindow(focused) then
    local li = (focused.getActiveLayerIndex and focused:getActiveLayerIndex()) or focused.activeLayer or 1
    local layer = focused.layers and focused.layers[li] or nil
    if not (layer and layer.paletteData) then
      return {}
    end

    local paletteWin = M.getPaletteWindowForLayer(layer, wm)
    if not paletteWin or paletteWin == focused then
      return {}
    end

    return {
      { contentWin = focused, paletteWin = paletteWin }
    }
  end

  if not WindowCaps.isRomPaletteWindow(focused) then
    return {}
  end

  local links = {}
  for _, win in ipairs(wm:getWindows()) do
    if win ~= focused and not win._closed and not win._minimized and not WindowCaps.isAnyPaletteWindow(win) then
      if windowHasPaletteLinkTo(win, focused, wm) then
        links[#links + 1] = { contentWin = win, paletteWin = focused }
      end
    end
  end

  return links
end

function M.getWindowLinkRect(win)
  if win and win._collapsed and win.getHeaderRect then
    return win:getHeaderRect()
  end
  return win:getScreenRect()
end

local function getWindowCorners(win)
  local x, y, w, h = M.getWindowLinkRect(win)
  return {
    { x = x,     y = y },
    { x = x + w, y = y },
    { x = x,     y = y + h },
    { x = x + w, y = y + h },
  }
end

function M.getClosestCornerPair(winA, winB)
  if not (winA and winB) then
    return nil, nil, nil, nil
  end

  local cornersA = getWindowCorners(winA)
  local cornersB = getWindowCorners(winB)
  local bestA, bestB = nil, nil
  local bestDist2 = math.huge

  for _, a in ipairs(cornersA) do
    for _, b in ipairs(cornersB) do
      local dx = (b.x - a.x)
      local dy = (b.y - a.y)
      local dist2 = dx * dx + dy * dy
      if dist2 < bestDist2 then
        bestDist2 = dist2
        bestA = a
        bestB = b
      end
    end
  end

  if not (bestA and bestB) then
    return nil, nil, nil, nil
  end

  return bestA.x, bestA.y, bestB.x, bestB.y
end

function M.getWindowLinkAnchor(fromWin, toWin)
  local fx, fy = M.getClosestCornerPair(fromWin, toWin)
  if fx and fy then
    return fx, fy
  end
  local x, y, w, h = M.getWindowLinkRect(fromWin)
  return x + math.floor(w / 2), y + math.floor(h / 2)
end

function M.getDestinationLayerAnchor(contentWin)
  if not contentWin then
    return nil, nil
  end
  if contentWin.getScreenRect then
    local x, y = contentWin:getScreenRect()
    if x and y then
      return x - 4, y + 4
    end
  end
  local x, y = M.getWindowLinkRect(contentWin)
  return x, y
end

function M.getPaletteSourceAnchor(paletteWin, targetWin)
  if not paletteWin then
    return nil, nil
  end

  if WindowCaps.isRomPaletteWindow(paletteWin) then
    local sx, sy = M.getPaletteLinkDragAnchor(paletteWin)
    if sx and sy then
      return sx, sy
    end
  end

  local sx, sy = M.getWindowLinkAnchor(paletteWin, targetWin)
  if sx and sy then
    return sx, sy
  end

  local x, y, w, h = M.getWindowLinkRect(paletteWin)
  return x + math.floor(w / 2), y + math.floor(h / 2)
end

function M.getPaletteHandleAnchor(paletteWin, focusedWin)
  return M.getPaletteSourceAnchor(paletteWin, focusedWin)
end

function M.getPaletteLinkDragAnchor(paletteWin)
  if not paletteWin then return nil, nil end
  if paletteWin._collapsed then
    local x, y, orientation, side = M.getWindowLinkAnchor(paletteWin, {
      getScreenRect = function()
        return 0, 0, 0, 0
      end,
      _collapsed = false,
    })
    return x, y, orientation, side
  end
  local toolbar = paletteWin.specializedToolbar
  if toolbar and toolbar.getLinkHandleRect then
    local x, y, w, h = toolbar:getLinkHandleRect()
    if x and y and w and h then
      return x + w / 2, y + h / 2, nil, nil
    end
  end
  local x, y, w, _ = M.getWindowLinkRect(paletteWin)
  return x + w / 2, y, nil, nil
end

function M.getSourcePaletteProxyRect(paletteWin, app)
  local wm = app and app.wm or nil
  local focusedWin = wm and wm.getFocus and wm:getFocus() or nil
  if not paletteWin or paletteWin._collapsed or paletteWin._closed or paletteWin._minimized then
    return nil
  end
  if focusedWin == paletteWin then
    return nil
  end
  if not paletteHasLinkedTargets(paletteWin, wm) then
    return nil
  end
  if not paletteHasVisibleLinks(app, paletteWin) then
    return nil
  end

  local toolbar = paletteWin.specializedToolbar
  if not (toolbar and toolbar.getLinkHandleRect) then
    return nil
  end
  local x, y, w, h = toolbar:getLinkHandleRect()
  if not (x and y and w and h) then
    return nil
  end
  return x, y, w, h
end

function M.getSourcePaletteProxyWindowAt(app, x, y)
  local wm = app and app.wm
  if not (wm and wm.getWindows) then
    return nil
  end

  local windows = wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local win = windows[i]
    local px, py, pw, ph = M.getSourcePaletteProxyRect(win, app)
    if px and x >= px and x <= (px + pw) and y >= py and y <= (py + ph) then
      return win
    end
  end
  return nil
end

function M.isMouseHoveringPaletteSourceSquare(paletteWin)
  if not paletteWin then
    return false
  end
  local sx, sy = M.getPaletteLinkDragAnchor(paletteWin)
  if not (sx and sy) then
    return false
  end
  return isMouseInsideSquareHoverArea(sx, sy, 15)
end

function M.getHoveredSourceSquareLinks(app)
  local wm = app and app.wm
  if not (wm and wm.getWindows) then
    return {}
  end

  local hoveredPalette = nil
  for _, win in ipairs(wm:getWindows()) do
    if win and not win._closed and not win._minimized and WindowCaps.isAnyPaletteWindow(win) then
      if M.isMouseHoveringPaletteSourceSquare(win) then
        hoveredPalette = win
        break
      end
    end
  end

  if not hoveredPalette or not WindowCaps.isRomPaletteWindow(hoveredPalette) then
    return {}
  end

  local links = {}
  for _, win in ipairs(wm:getWindows()) do
    if win ~= hoveredPalette and not win._closed and not win._minimized and not WindowCaps.isAnyPaletteWindow(win) then
      if windowHasPaletteLinkTo(win, hoveredPalette, wm) then
        links[#links + 1] = { contentWin = win, paletteWin = hoveredPalette }
      end
    end
  end

  return links
end

isMouseInsideSquareHoverArea = function(cx, cy, size)
  local mx, my = getScaledMousePosition()
  return isPointInsideSquare(cx, cy, size or 15, mx, my)
end

function M.isPointHoveringDestinationSquare(contentWin, paletteWin, x, y, hitSize)
  if not (contentWin and paletteWin) then
    return false
  end

  local sx, sy = M.getDestinationLayerAnchor(contentWin)
  if not (sx and sy and x and y) then
    return false
  end
  return isPointInsideSquare(sx, sy, hitSize or DESTINATION_HIT_SIZE, x, y)
end

function M.isMouseHoveringDestinationSquare(contentWin, paletteWin)
  local mx, my = getScaledMousePosition()
  return M.isPointHoveringDestinationSquare(contentWin, paletteWin, mx, my, DESTINATION_HIT_SIZE)
end

function M.getLinkAtDestinationPoint(app, x, y)
  local wm = app and app.wm
  if not (wm and wm.getWindows) then
    return nil
  end

  local windows = wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local win = windows[i]
    if win and not win._closed and not win._minimized and not WindowCaps.isAnyPaletteWindow(win) then
      local linkedPaletteWindows = collectLinkedPaletteWindowsForWindow(win, wm)
      for _, paletteWin in ipairs(linkedPaletteWindows) do
        if paletteWin and not paletteWin._closed and not paletteWin._minimized and WindowCaps.isRomPaletteWindow(paletteWin) then
          local showLine = M.getPersistentVisual(app, win, paletteWin)
          if showLine and M.isPointHoveringDestinationSquare(win, paletteWin, x, y, DESTINATION_HIT_SIZE) then
            return { contentWin = win, paletteWin = paletteWin }
          end
        end
      end
    end
  end

  return nil
end

function M.getHoveredDestinationLinks(app)
  local wm = app and app.wm
  if not (wm and wm.getWindows) then
    return {}
  end

  local links = {}
  for _, win in ipairs(wm:getWindows()) do
    if win and not win._closed and not win._minimized and not WindowCaps.isAnyPaletteWindow(win) then
      local linkedPaletteWindows = collectLinkedPaletteWindowsForWindow(win, wm)
      for _, paletteWin in ipairs(linkedPaletteWindows) do
        if not paletteWin._closed and not paletteWin._minimized and WindowCaps.isRomPaletteWindow(paletteWin) then
          if M.isMouseHoveringDestinationSquare(win, paletteWin) then
            links[#links + 1] = { contentWin = win, paletteWin = paletteWin }
          end
        end
      end
    end
  end

  return links
end

function M.normalizeLinksMode(mode)
  if mode == "on_hover" or mode == "never" then return "on_hover" end
  if mode == "auto_hide" then return "auto_hide" end
  return "always"
end

function M.getRevealAlpha(contentWin, paletteWin)
  if (contentWin and contentWin.dragging) or (paletteWin and paletteWin.dragging) then
    return 1
  end

  local now = os.clock()
  if love and love.timer and love.timer.getTime then
    now = love.timer.getTime()
  end
  local revealUntil = math.max(
    tonumber(contentWin and contentWin._paletteLinkRevealUntil) or 0,
    tonumber(paletteWin and paletteWin._paletteLinkRevealUntil) or 0
  )
  if revealUntil <= now then
    return 0
  end
  return math.max(0, math.min(1, revealUntil - now))
end

function M.getPersistentVisual(app, contentWin, paletteWin)
  local focusedWin = app and app.wm and app.wm.getFocus and app.wm:getFocus() or nil
  local mode = M.normalizeLinksMode(app and app.paletteLinksMode)
  if mode == "always" then
    return (focusedWin == paletteWin or focusedWin == contentWin), 1
  end
  if mode == "on_hover" then
    return M.isMouseHoveringPaletteSourceSquare(paletteWin) or M.isMouseHoveringDestinationSquare(contentWin, paletteWin), 1
  end

  local revealAlpha = M.getRevealAlpha(contentWin, paletteWin)
  if revealAlpha > 0 then
    return true, revealAlpha
  end

  return false, 1
end

function M.buildConnectorGeometry(x1, y1, x2, y2, opts)
  opts = opts or {}
  local snappedPoints = buildRectilinearPoints(x1, y1, x2, y2)

  local geometry = {
    showLine = (opts.showLine ~= false),
    alpha = math.max(0, math.min(1, tonumber(opts.alpha) or 1)),
    lineColor = opts.lineColor or colors.blue,
    x1 = x1,
    y1 = y1,
    x2 = x2,
    y2 = y2,
    rawPoints = snappedPoints,
  }
  geometry.points = snappedPoints
  return geometry
end

function M.drawConnector(geometry)
  if not geometry then
    return
  end

  love.graphics.push("all")
  M.drawConnectorLine(geometry)
  M.drawConnectorSquares(geometry)
  love.graphics.pop()
end

function M.drawConnectorLine(geometry)
  if not (geometry and geometry.showLine) then
    return
  end
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)
  local lineColor = geometry.lineColor or colors.blue
  local alpha = geometry.alpha or 1
  love.graphics.setColor(lineColor[1], lineColor[2], lineColor[3], alpha)
  love.graphics.line(geometry.points)
end

function M.drawConnectorSquares(geometry)
  if not geometry then
    return
  end
  local lineColor = geometry.lineColor or colors.blue
  local alpha = geometry.alpha or 1

  -- Source marker (palette handle): compact white 3x3.
  love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], alpha)
  love.graphics.rectangle("fill", geometry.x1 - math.floor(SOURCE_SQUARE_SIZE / 2), geometry.y1 - math.floor(SOURCE_SQUARE_SIZE / 2), SOURCE_SQUARE_SIZE, SOURCE_SQUARE_SIZE)

  -- Destination marker (window anchor): 7x7 button style (blue border, white center).
  love.graphics.setColor(lineColor[1], lineColor[2], lineColor[3], alpha)
  love.graphics.rectangle("fill", geometry.x2 - math.floor(DESTINATION_SQUARE_SIZE / 2), geometry.y2 - math.floor(DESTINATION_SQUARE_SIZE / 2), DESTINATION_SQUARE_SIZE, DESTINATION_SQUARE_SIZE)
  love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], alpha)
  love.graphics.rectangle("fill", geometry.x2 - 1, geometry.y2 - 1, 3, 3)
end

function M.drawRectConnector(x1, y1, x2, y2, opts)
  M.drawConnector(M.buildConnectorGeometry(x1, y1, x2, y2, opts))
end

local function sortLinksStable(links)
  table.sort(links, function(a, b)
    local aTitle = tostring(a.contentWin and (a.contentWin.title or a.contentWin._id or "") or "")
    local bTitle = tostring(b.contentWin and (b.contentWin.title or b.contentWin._id or "") or "")
    if aTitle ~= bTitle then
      return aTitle < bTitle
    end
    local aId = tostring(a.contentWin and (a.contentWin._id or "") or "")
    local bId = tostring(b.contentWin and (b.contentWin._id or "") or "")
    if aId ~= bId then
      return aId < bId
    end
    return tostring(a.contentWin) < tostring(b.contentWin)
  end)
end

function M.drawOverlay(app)
  local mode = M.normalizeLinksMode(app and app.paletteLinksMode)
  local drag = app and app.paletteLinkDrag or nil
  local suppressPaletteWin = (drag and drag.active and drag.mode == "move_all" and drag.sourceWin) or nil
  local links = {}
  local seen = {}
  local function appendLinks(list)
    for _, link in ipairs(list or {}) do
      local contentKey = link.contentWin and tostring(link.contentWin) or "?"
      local paletteKey = link.paletteWin and tostring(link.paletteWin) or "?"
      local key = contentKey .. "->" .. paletteKey
      if not seen[key] then
        seen[key] = true
        links[#links + 1] = link
      end
    end
  end

  appendLinks(M.getFocusedLinks(app))
  if mode == "on_hover" then
    appendLinks(M.getHoveredSourceSquareLinks(app))
    appendLinks(M.getHoveredDestinationLinks(app))
  end
  sortLinksStable(links)

  local geometries = {}

  for _, link in ipairs(links) do
    local contentWin = link.contentWin
    local paletteWin = link.paletteWin
    if contentWin and paletteWin and paletteWin ~= suppressPaletteWin then
      local sx, sy = M.getPaletteSourceAnchor(paletteWin, contentWin)
      local tx, ty = M.getDestinationLayerAnchor(contentWin)
      local showLine, alpha = M.getPersistentVisual(app, contentWin, paletteWin)
      geometries[#geometries + 1] = M.buildConnectorGeometry(sx, sy, tx, ty, {
        showLine = showLine,
        alpha = alpha,
      })
    end
  end

  love.graphics.push("all")
  for _, geometry in ipairs(geometries) do
    M.drawConnectorLine(geometry)
  end
  for _, geometry in ipairs(geometries) do
    M.drawConnectorSquares(geometry)
  end
  love.graphics.pop()
end

function M.drawSourcePaletteProxyForWindow(app, win)
  local px, py, pw, ph = M.getSourcePaletteProxyRect(win, app)
  if not px then
    return
  end

  love.graphics.push("all")
  love.graphics.setColor(colors.gray20)
  love.graphics.rectangle("fill", px, py, pw, ph)
  love.graphics.pop()
end

function M.drawActiveDrag(app)
  local drag = app and app.paletteLinkDrag
  if not (drag and drag.active and drag.sourceWin) then
    return
  end

  local sx, sy = M.getPaletteLinkDragAnchor(drag.sourceWin)
  local tx = drag.currentX or sx
  local ty = drag.currentY or sy
  if not (sx and sy and tx and ty) then
    return
  end

  local lineColor = colors.red
  local wm = app and app.wm or nil
  if wm then
    if drag.mode == "move_all" then
      local targetPalette = PaletteLinkController.getMoveAllTarget(wm, drag.sourceWin, tx, ty, { allowSource = true })
      if targetPalette then
        lineColor = colors.green
      end
    else
      local targetWin = PaletteLinkController.getDropTarget(wm, drag.sourceWin, tx, ty)
      local ok = PaletteLinkController.canApplyToTarget(targetWin, drag.sourceWin)
      if ok then
        lineColor = colors.green
      end
    end
  end

  if drag.mode == "move_all" and wm and wm.getWindows then
    local drawn = 0
    for _, contentWin in ipairs(wm:getWindows()) do
      if contentWin
        and contentWin ~= drag.sourceWin
        and not contentWin._closed
        and not contentWin._minimized
        and not WindowCaps.isAnyPaletteWindow(contentWin)
        and windowHasPaletteLinkTo(contentWin, drag.sourceWin, wm)
      then
        local dx, dy = M.getDestinationLayerAnchor(contentWin)
        if dx and dy then
          M.drawRectConnector(tx, ty, dx, dy, {
            lineColor = lineColor,
          })
          drawn = drawn + 1
        end
      end
    end

    if drawn > 0 then
      return
    end
  end

  M.drawRectConnector(sx, sy, tx, ty, {
    lineColor = lineColor,
  })
end

return M
