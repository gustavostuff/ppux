local ResolutionController = require("controllers.app.resolution_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local colors = require("app_colors")

local M = {}
local isMouseInsideSquareHoverArea

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

function M.getWindowLinkAnchor(fromWin, toWin)
  local fx, fy, fw, fh = M.getWindowLinkRect(fromWin)
  local tx, ty, tw, th = M.getWindowLinkRect(toWin)
  local fcx, fcy = fx + fw / 2, fy + fh / 2
  local tcx, tcy = tx + tw / 2, ty + th / 2
  local dx, dy = tcx - fcx, tcy - fcy

  if math.abs(dx) >= math.abs(dy) then
    if dx >= 0 then
      return fx + fw, fy + fh / 2, "horizontal", "right"
    end
    return fx, fy + fh / 2, "horizontal", "left"
  end

  if dy >= 0 then
    return fx + fw / 2, fy + fh, "vertical", "bottom"
  end
  return fx + fw / 2, fy, "vertical", "top"
end

function M.getPaletteHandleAnchor(paletteWin, focusedWin)
  if paletteWin and paletteWin._collapsed then
    return M.getWindowLinkAnchor(paletteWin, focusedWin)
  end
  local toolbar = paletteWin and paletteWin.specializedToolbar
  if toolbar and toolbar.getLinkHandleRect then
    local x, y, w, h = toolbar:getLinkHandleRect()
    if x and y and w and h then
      return x + w / 2, y + h / 2
    end
  end
  return M.getWindowLinkAnchor(paletteWin, focusedWin)
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
  local mouse = ResolutionController:getScaledMouse(true)
  local mx = mouse and mouse.x or nil
  local my = mouse and mouse.y or nil
  if type(mx) ~= "number" or type(my) ~= "number" then
    mx, my = love.mouse.getPosition()
  end
  local half = math.floor((size or 15) / 2)
  return mx >= (cx - half) and mx <= (cx + half)
    and my >= (cy - half) and my <= (cy + half)
end

function M.isMouseHoveringDestinationSquare(contentWin, paletteWin)
  if not (contentWin and paletteWin) then
    return false
  end

  local sx, sy = M.getWindowLinkAnchor(contentWin, paletteWin)
  return isMouseInsideSquareHoverArea(sx, sy, 15)
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
  local geometry = {
    showLine = (opts.showLine ~= false),
    alpha = math.max(0, math.min(1, tonumber(opts.alpha) or 1)),
    lineColor = opts.lineColor or colors.blue,
    x1 = x1,
    y1 = y1,
    x2 = x2,
    y2 = y2,
  }
  local startHorizontalLead = tonumber(opts.startHorizontalLead) or 0
  local startVerticalLead = tonumber(opts.startVerticalLead) or 0
  local endHorizontalLead = tonumber(opts.endHorizontalLead) or 0
  local endVerticalLead = tonumber(opts.endVerticalLead) or 0
  local points

  local routeStartX, routeStartY = x1, y1
  local routeEndX, routeEndY = x2, y2
  local prefix = {}
  local suffix = {}
  local hadStartHorizontalLead = false
  local hadStartVerticalLead = false
  local startVerticalLeadSign = 0

  local function sign(value)
    if value > 0 then return 1 end
    if value < 0 then return -1 end
    return 0
  end

  if startHorizontalLead ~= 0 then
    local leadX = x1 + startHorizontalLead
    prefix[#prefix + 1] = x1
    prefix[#prefix + 1] = y1
    prefix[#prefix + 1] = leadX
    prefix[#prefix + 1] = y1
    routeStartX = leadX
    hadStartHorizontalLead = true
  else
    prefix[#prefix + 1] = x1
    prefix[#prefix + 1] = y1
  end

  if startVerticalLead ~= 0 then
    routeStartY = y1 + startVerticalLead
    prefix[#prefix + 1] = routeStartX
    prefix[#prefix + 1] = routeStartY
    hadStartVerticalLead = true
    startVerticalLeadSign = sign(startVerticalLead)
  end

  if endHorizontalLead ~= 0 then
    routeEndX = x2 + endHorizontalLead
  end
  if endVerticalLead ~= 0 then
    routeEndY = y2 + endVerticalLead
  end

  if endHorizontalLead ~= 0 and endVerticalLead ~= 0 then
    suffix = {
      routeEndX, routeEndY,
      x2 + endHorizontalLead, y2,
      x2, y2,
    }
  elseif endHorizontalLead ~= 0 then
    suffix = {
      routeEndX, routeEndY,
      x2, y2,
    }
  elseif endVerticalLead ~= 0 then
    suffix = {
      routeEndX, routeEndY,
      x2, y2,
    }
  end

  local function buildMergedPoints(currentPrefix, currentRouteStartX, currentRouteStartY)
    local corePoints

    if math.abs(routeEndX - currentRouteStartX) >= math.abs(routeEndY - currentRouteStartY) then
      local mx = math.floor((currentRouteStartX + routeEndX) / 2 + 0.5)
      corePoints = {
        currentRouteStartX, currentRouteStartY,
        mx, currentRouteStartY,
        mx, routeEndY,
        routeEndX, routeEndY,
      }
    else
      local my = math.floor((currentRouteStartY + routeEndY) / 2 + 0.5)
      corePoints = {
        currentRouteStartX, currentRouteStartY,
        currentRouteStartX, my,
        routeEndX, my,
        routeEndX, routeEndY,
      }
    end

    local merged = {}
    if #currentPrefix > 2 then
      for i = 1, #currentPrefix do
        merged[#merged + 1] = currentPrefix[i]
      end
      for i = 3, #corePoints do
        merged[#merged + 1] = corePoints[i]
      end
    else
      for i = 1, #corePoints do
        merged[#merged + 1] = corePoints[i]
      end
    end

    if #suffix > 0 then
      for i = 3, #suffix do
        merged[#merged + 1] = suffix[i]
      end
    end

    return merged
  end

  local function getPoint(list, pointIndex)
    local base = (pointIndex - 1) * 2
    return list[base + 1], list[base + 2]
  end

  local function removePoint(list, pointIndex)
    local base = (pointIndex - 1) * 2
    table.remove(list, base + 2)
    table.remove(list, base + 1)
  end

  local function firstVerticalSegmentDeltaAfterLead(list)
    local pointCount = math.floor(#list / 2)
    local startPointIndex = (hadStartHorizontalLead and hadStartVerticalLead) and 3 or ((hadStartHorizontalLead or hadStartVerticalLead) and 2 or 1)
    for i = startPointIndex, pointCount - 1 do
      local ax, ay = getPoint(list, i)
      local bx, by = getPoint(list, i + 1)
      if ax == bx and ay ~= by then
        return by - ay
      end
    end
    return nil
  end

  local function simplifyEndLeadIfThirdSegmentComesBackDown(list)
    if not (endHorizontalLead ~= 0 and endVerticalLead ~= 0) then
      return
    end
    local count = math.floor(#list / 2)
    if count < 4 then
      return
    end
    local ax, ay = getPoint(list, count)
    local bx, by = getPoint(list, count - 1)
    local cx, cy = getPoint(list, count - 2)
    local dx, dy = getPoint(list, count - 3)
    local seg1Horizontal = (ay == by) and (ax ~= bx)
    local seg2Vertical = (bx == cx) and (by ~= cy)
    local seg3VerticalDown = (cx == dx) and (dy > cy)
    if seg1Horizontal and seg2Vertical and seg3VerticalDown then
      removePoint(list, count - 2)
    end
  end

  points = buildMergedPoints(prefix, routeStartX, routeStartY)

  if hadStartVerticalLead then
    local firstVerticalDelta = firstVerticalSegmentDeltaAfterLead(points)
    if firstVerticalDelta and sign(firstVerticalDelta) == -startVerticalLeadSign then
      prefix = { x1, y1, routeStartX, y1 }
      routeStartY = y1
      hadStartVerticalLead = false
      points = buildMergedPoints(prefix, routeStartX, routeStartY)
    end
  end

  simplifyEndLeadIfThirdSegmentComesBackDown(points)

  geometry.points = points
  return geometry
end

function M.drawConnector(geometry)
  if not geometry then
    return
  end

  love.graphics.push("all")
  M.drawConnectorShadowLine(geometry)
  M.drawConnectorLine(geometry)
  M.drawConnectorSquares(geometry)
  love.graphics.pop()
end

function M.drawConnectorShadowLine(geometry)
  if not (geometry and geometry.showLine) then
    return
  end
  local alpha = geometry.alpha or 1
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(3)
  love.graphics.setColor(0, 0, 0, alpha)
  love.graphics.line(geometry.points)
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
  love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], geometry.alpha)
  love.graphics.rectangle("fill", geometry.x1 - 1, geometry.y1 - 1, 3, 3)
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
    if contentWin and paletteWin then
      local sx, sy = M.getWindowLinkAnchor(contentWin, paletteWin)
      local tx, ty = M.getPaletteHandleAnchor(paletteWin, contentWin)
      local showLine, alpha = M.getPersistentVisual(app, contentWin, paletteWin)
      local endHorizontalLead = paletteWin._collapsed and 0 or -15
      local endVerticalLead = paletteWin._collapsed and 0 or -15
      geometries[#geometries + 1] = M.buildConnectorGeometry(sx, sy, tx, ty, {
        endHorizontalLead = endHorizontalLead,
        endVerticalLead = endVerticalLead,
        showLine = showLine,
        alpha = alpha,
      })
    end
  end

  love.graphics.push("all")
  for _, geometry in ipairs(geometries) do
    M.drawConnectorShadowLine(geometry)
  end
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
  if app and app.wm then
    local targetWin = PaletteLinkController.getDropTarget(app.wm, drag.sourceWin, tx, ty)
    local ok = PaletteLinkController.canApplyToTarget(targetWin, drag.sourceWin)
    if ok then
      lineColor = colors.green
    end
  end

  local startHorizontalLead = (drag.sourceWin and drag.sourceWin._collapsed) and 0 or -15
  local startVerticalLead = (drag.sourceWin and drag.sourceWin._collapsed) and 0 or -15
  M.drawRectConnector(sx, sy, tx, ty, {
    startHorizontalLead = startHorizontalLead,
    startVerticalLead = startVerticalLead,
    lineColor = lineColor,
  })
end

return M
