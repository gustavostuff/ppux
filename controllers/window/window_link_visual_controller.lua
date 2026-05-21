-- window_link_visual_controller.lua
-- On-canvas link lines and left-edge pivot handles (pattern table + ROM palette).

local colors = require("app_colors")
local UiPulse = require("utils.ui_pulse")
local WindowCaps = require("controllers.window.window_capabilities")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local PaletteLinkRenderController = require("controllers.palette.palette_link_render_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local Shared = require("controllers.app.core_controller_shared")
local WindowLinkVisibility = require("controllers.window.window_link_visibility")

local M = {}

local LINE_WIDTH = 2
local HANDLE_OUTER_W = 8
local HANDLE_OUTER_H = 8
local HANDLE_OUTER_RADIUS = 2
local HANDLE_INNER_W = 4
local HANDLE_INNER_H = 4
local HANDLE_OUTSIDE_TOUCH_GAP = 0
local HANDLE_GROUP_BELOW_HEADER = 3
local HANDLE_GROUP_ROW_GAP = 2

local PATTERN_TABLE_SLOT = "pattern_source"
local PPU_SLOTS = { "ppu_pattern_bg", "ppu_pattern_sprite", "ppu_palette" }
local OAM_SLOTS = { "oam_pattern", "layout_palette" }

local function roundPixel(value)
  return math.floor((tonumber(value) or 0) + 0.5)
end

local function isLinkWindowEligible(win)
  return win and win._closed ~= true and win._groupHidden ~= true
end

local function isLinkWindowVisible(win)
  return isLinkWindowEligible(win) and win._minimized ~= true
end

local function isLinkWindowMinimized(win)
  return isLinkWindowEligible(win) and win._minimized == true
end

--- Bottom-center of the taskbar strip button (line terminates under the icon; taskbar draws on top).
local function getTaskbarLinkAnchor(app, win)
  local tb = app and app.taskbar
  if not (tb and win) then
    return nil, nil
  end
  local btn = tb.minimizedButtonsByWindow and tb.minimizedButtonsByWindow[win]
  if not (btn and type(btn.x) == "number" and type(btn.y) == "number") then
    return nil, nil
  end
  local w = tonumber(btn.w) or 0
  local h = tonumber(btn.h) or 0
  if w <= 0 or h <= 0 then
    return nil, nil
  end
  return btn.x + w * 0.5, btn.y + h
end

local function getWindowBodyRect(win)
  if not win then
    return nil
  end
  if win._collapsed and win.getHeaderRect then
    return win:getHeaderRect()
  end
  if win.getScreenRect then
    return win:getScreenRect()
  end
  return nil
end

local function idleInnerColorForWindow(win, wm)
  if wm and wm.getFocus and win == wm:getFocus() then
    return colors:chromeTextIconsColorFocused()
  end
  return colors:chromeTextIconsColorNonFocused()
end

local function chromeFillColorForWindow(win, wm)
  if wm and wm.getFocus and win == wm:getFocus() then
    return colors:focusedChromeColor()
  end
  return colors:chromeBackgroundUnfocused()
end

local function buildSlotLinkedMap(edges)
  local linked = {}
  for _, edge in ipairs(edges or {}) do
    if edge.fromWin and edge.fromSlot then
      linked[edge.fromWin] = linked[edge.fromWin] or {}
      linked[edge.fromWin][edge.fromSlot] = true
    end
    if edge.toWin and edge.toSlot then
      linked[edge.toWin] = linked[edge.toWin] or {}
      linked[edge.toWin][edge.toSlot] = true
    end
  end
  return linked
end

local function slotHasLinkEdge(linkedMap, win, slot)
  local byWin = linkedMap and linkedMap[win]
  return byWin ~= nil and byWin[slot] == true
end

local function consumerSupportsPaletteLink(win)
  if not win or WindowCaps.isAnyPaletteWindow(win) or WindowCaps.isPatternTable(win) or WindowCaps.isChrLike(win) then
    return false
  end
  return WindowCaps.isPpuFrame(win)
    or WindowCaps.isAnimationLike(win)
    or WindowCaps.isStaticArt(win)
end

local function isPaletteOnlyConsumer(win)
  if not consumerSupportsPaletteLink(win) then
    return false
  end
  return not WindowCaps.isPpuFrame(win) and not WindowCaps.isOamAnimation(win)
end

local function isWindowCollapsed(win)
  return win and win._collapsed == true
end

local function buildHandleAnchorPositions(win, count)
  count = math.max(1, math.floor(tonumber(count) or 1))
  local hx, hy, _, hh
  if win and win.getHeaderRect then
    hx, hy, _, hh = win:getHeaderRect()
  end
  if not (hy and hh) then
    local x, y, _, h = getWindowBodyRect(win)
    hx = x or 0
    hy = y or 0
    hh = h or 16
  end
  local rowStep = HANDLE_OUTER_W + HANDLE_GROUP_ROW_GAP
  local out = {}
  if isWindowCollapsed(win) then
    local cy = roundPixel(hy + hh + HANDLE_OUTER_H * 0.5 - 1)
    local firstCenterX = hx + HANDLE_GROUP_BELOW_HEADER + HANDLE_OUTER_W * 0.5
    for i = 0, count - 1 do
      out[#out + 1] = {
        cx = roundPixel(firstCenterX + i * rowStep),
        cy = cy,
      }
    end
  else
    local anchorX = M.handleCenterXForWindowLeft(hx)
    local firstCenterY = hy + hh + HANDLE_GROUP_BELOW_HEADER + HANDLE_OUTER_H * 0.5
    for i = 0, count - 1 do
      out[#out + 1] = {
        cx = anchorX,
        cy = roundPixel(firstCenterY + i * rowStep),
      }
    end
  end
  return out
end

local function getPpuPaletteLinkLayer(ppu)
  if not (ppu and ppu.layers) then
    return nil
  end
  local activeIdx = (ppu.getActiveLayerIndex and ppu:getActiveLayerIndex()) or ppu.activeLayer or 1
  local active = ppu.layers[activeIdx]
  if active and type(active.paletteData) == "table" and type(active.paletteData.winId) == "string" and active.paletteData.winId ~= "" then
    return active
  end
  for _, layer in ipairs(ppu.layers) do
    if layer
      and layer.kind == "tile"
      and layer._runtimePatternTableRefLayer ~= true
      and type(layer.paletteData) == "table"
      and type(layer.paletteData.winId) == "string"
      and layer.paletteData.winId ~= ""
    then
      return layer
    end
  end
  return nil
end

local function getConsumerLinkedPaletteWindowRaw(consumer, wm, allowMinimized)
  if WindowCaps.isPpuFrame(consumer) then
    local layer = getPpuPaletteLinkLayer(consumer)
    local winId = layer and layer.paletteData and layer.paletteData.winId
    if type(winId) == "string" and winId ~= "" and wm and wm.findWindowById then
      local linked = wm:findWindowById(winId)
      if linked and isLinkWindowEligible(linked) and WindowCaps.isRomPaletteWindow(linked) then
        if allowMinimized or isLinkWindowVisible(linked) then
          return linked
        end
      end
    end
    return nil
  end
  local layer = consumer and consumer.layers
    and consumer.layers[(consumer.getActiveLayerIndex and consumer:getActiveLayerIndex()) or consumer.activeLayer or 1]
  local pd = layer and layer.paletteData
  if pd and pd.winId and wm and wm.findWindowById then
    local linked = wm:findWindowById(pd.winId)
    if linked and isLinkWindowEligible(linked) and WindowCaps.isRomPaletteWindow(linked) then
      if allowMinimized or isLinkWindowVisible(linked) then
        return linked
      end
    end
  end
  return PaletteLinkController.getActiveLayerLinkedPaletteWindow(consumer, wm)
end

function M.getConsumerLinkedPaletteWindow(consumer, wm)
  return getConsumerLinkedPaletteWindowRaw(consumer, wm, false)
end

local function consumerPaletteLinkSlot(win)
  if WindowCaps.isPpuFrame(win) then
    return "ppu_palette"
  end
  return "layout_palette"
end

local function orderedActiveSlots(win, slotSet)
  local order
  if WindowCaps.isPpuFrame(win) then
    order = PPU_SLOTS
  elseif WindowCaps.isPatternTable(win) then
    order = { PATTERN_TABLE_SLOT }
  elseif WindowCaps.isOamAnimation(win) then
    order = OAM_SLOTS
  elseif WindowCaps.isRomPaletteWindow(win) then
    order = { "palette_source" }
  elseif isPaletteOnlyConsumer(win) then
    order = { "layout_palette" }
  else
    order = {}
  end

  local active = {}
  for _, slot in ipairs(order) do
    if slotSet[slot] then
      active[#active + 1] = slot
    end
  end
  return active
end

local function patternTableOutgoingKinds(ptWin, edges)
  local hasRed, hasGreen = false, false
  for _, edge in ipairs(edges or {}) do
    if edge.fromWin == ptWin then
      if edge.color == colors.red then
        hasRed = true
      elseif edge.color == colors.green then
        hasGreen = true
      end
    end
  end
  return hasRed, hasGreen
end

function M.handleCenterXForWindowLeft(windowLeftX)
  local left = math.floor(tonumber(windowLeftX) or 0) - math.floor(HANDLE_OUTSIDE_TOUCH_GAP)
  return left - HANDLE_OUTER_W * 0.5
end

function M.getPivotHandleRect(cx, cy)
  if not (cx and cy) then
    return nil
  end
  local ox = math.floor((tonumber(cx) or 0) - HANDLE_OUTER_W * 0.5)
  local oy = math.floor((tonumber(cy) or 0) - HANDLE_OUTER_H * 0.5)
  return ox, oy, HANDLE_OUTER_W, HANDLE_OUTER_H
end

function M.getInnerRectForHandleCenter(cx, cy)
  local ox, oy = M.getPivotHandleRect(cx, cy)
  if not ox then
    return nil
  end
  local ix = ox + math.floor((HANDLE_OUTER_W - HANDLE_INNER_W) * 0.5)
  local iy = oy + math.floor((HANDLE_OUTER_H - HANDLE_INNER_H) * 0.5)
  return ix, iy, HANDLE_INNER_W, HANDLE_INNER_H
end

function M.getInnerRectCenterPoint(cx, cy)
  local ix, iy, iw, ih = M.getInnerRectForHandleCenter(cx, cy)
  if not ix then
    return roundPixel(cx), roundPixel(cy)
  end
  return ix + math.floor(iw * 0.5), iy + math.floor(ih * 0.5)
end

local function pinPolylineEndpoints(points, x1, y1, x2, y2)
  if not (points and #points >= 4) then
    return points
  end
  points[1] = x1
  points[2] = y1
  points[#points - 1] = x2
  points[#points] = y2
  return points
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
    return midX, ayq, midX, byq
  end
  local midY = ayq + math.floor(dy * 0.5)
  return axq, midY, bxq, midY
end

--- Route the last segment along the taskbar top so the line sits behind the bar and icon.
local function buildConnectorPointsViaTaskbar(x1, y1, x2, y2, taskbarTopY)
  local axq = roundPixel(x1)
  local ayq = roundPixel(y1)
  local bxq = roundPixel(x2)
  local byq = roundPixel(y2)
  local barY = roundPixel(taskbarTopY)
  local c1x, c1y, c2x, c2y = buildElbowControlPoints(axq, ayq, bxq, barY)
  return {
    axq, ayq,
    roundPixel(c1x), roundPixel(c1y),
    roundPixel(c2x), roundPixel(c2y),
    bxq, barY,
    bxq, byq,
  }
end

local function layoutEntryUsesTaskbarAnchor(entry)
  return entry and entry.taskbarAnchor == true
end

local function getTaskbarTopY(app)
  local tb = app and app.taskbar
  if tb and type(tb.y) == "number" then
    return tb.y
  end
  return nil
end

local function drawLinkPolyline(points, thickness, color, alpha)
  if not (points and #points >= 4) then
    return
  end
  alpha = math.max(0, math.min(1, tonumber(alpha) or 1))
  if alpha <= 0 then
    return
  end
  local r, g, b, a = color[1], color[2], color[3], (color[4] or 1) * alpha
  love.graphics.setColor(r, g, b, a)
  love.graphics.setLineStyle("rough")
  love.graphics.setLineJoin("miter")
  love.graphics.setLineWidth(math.max(1, math.floor(thickness)))
  local rounded = {}
  for i = 1, #points do
    rounded[i] = roundPixel(points[i])
  end
  love.graphics.line(unpack(rounded))
end

function M.getLeftAnchorPoint(win, slot, layouts)
  local byWin = layouts and layouts[win]
  local entry = byWin and byWin[slot]
  if entry then
    return entry.cx, entry.cy
  end
  return nil, nil
end

function M.innerColorForSlot(win, slot, wm)
  if WindowCaps.isPpuFrame(win) then
    if slot == "ppu_pattern_bg" then
      return M.ppuPatternBgLinked(win, wm) and colors.red or idleInnerColorForWindow(win, wm)
    end
    if slot == "ppu_pattern_sprite" then
      return M.ppuPatternSpriteLinked(win, wm) and colors.green or idleInnerColorForWindow(win, wm)
    end
    if slot == "ppu_palette" then
      local linked = M.getConsumerLinkedPaletteWindow(win, wm)
      return linked and colors.blue or idleInnerColorForWindow(win, wm)
    end
  end

  if WindowCaps.isRomPaletteWindow(win) and slot == "palette_source" then
    return M.romPaletteHasConsumers(win, wm) and colors.blue or idleInnerColorForWindow(win, wm)
  end

  if slot == "layout_palette" then
    local linked = M.getConsumerLinkedPaletteWindow(win, wm)
    return linked and colors.blue or idleInnerColorForWindow(win, wm)
  end

  if slot == "oam_pattern" then
    return M.oamPatternLinked(win, wm) and colors.green or idleInnerColorForWindow(win, wm)
  end

  return idleInnerColorForWindow(win, wm)
end

function M.buildAnchorLayouts(app, edges)
  local layouts = {}
  local handles = {}
  local wm = app and app.wm
  if not wm then
    return layouts, handles
  end

  local slotNeeded = {}
  local slotLinked = buildSlotLinkedMap(edges)

  local function needSlot(win, slot)
    if not win or not WindowLinkVisibility.shouldShowSlot(app, slot) then
      return
    end
    slotNeeded[win] = slotNeeded[win] or {}
    slotNeeded[win][slot] = true
  end

  for _, edge in ipairs(edges or {}) do
    needSlot(edge.fromWin, edge.fromSlot)
    needSlot(edge.toWin, edge.toSlot)
  end

  for _, win in ipairs(wm:getWindows()) do
    if not isLinkWindowVisible(win) then
      goto continue
    end
    if WindowCaps.isPpuFrame(win) then
      for _, slot in ipairs(PPU_SLOTS) do
        if WindowLinkVisibility.shouldShowSlot(app, slot) then
          needSlot(win, slot)
        end
      end
    elseif WindowCaps.isOamAnimation(win) then
      for _, slot in ipairs(OAM_SLOTS) do
        if WindowLinkVisibility.shouldShowSlot(app, slot) then
          needSlot(win, slot)
        end
      end
    elseif WindowCaps.isRomPaletteWindow(win) then
      needSlot(win, "palette_source")
    elseif isPaletteOnlyConsumer(win) then
      needSlot(win, "layout_palette")
    elseif WindowCaps.isPatternTable(win) then
      local consumers = PatternTableDisplayController.getLinkedConsumersForPatternTable(wm, win)
      if #consumers > 0 or slotHasLinkEdge(slotLinked, win, PATTERN_TABLE_SLOT) then
        needSlot(win, PATTERN_TABLE_SLOT)
      end
    end
    ::continue::
  end

  for win, slots in pairs(slotNeeded) do
    if not isLinkWindowVisible(win) then
      goto next_win
    end
    local x, y, _, h = getWindowBodyRect(win)
    if not (x and y and h and h > 0) then
      goto next_win
    end

    local active = orderedActiveSlots(win, slots)
    if #active == 0 then
      goto next_win
    end

    local anchors = buildHandleAnchorPositions(win, #active)
    layouts[win] = layouts[win] or {}

    for i, slot in ipairs(active) do
      local anchor = anchors[i]
      local anchorX = anchor and anchor.cx
      local cy = anchor and anchor.cy
      local hasLine = slotHasLinkEdge(slotLinked, win, slot)
      local innerSplit = nil
      local innerColor = idleInnerColorForWindow(win, wm)

      if WindowCaps.isPatternTable(win) and slot == PATTERN_TABLE_SLOT then
        local hasRed, hasGreen = patternTableOutgoingKinds(win, edges)
        if hasLine then
          if hasRed and hasGreen then
            innerSplit = "red_green"
          elseif hasRed then
            innerSplit = "red"
            innerColor = colors.red
          elseif hasGreen then
            innerSplit = "green"
            innerColor = colors.green
          end
        end
      elseif hasLine then
        innerColor = M.innerColorForSlot(win, slot, wm)
      else
        innerColor = M.innerColorForSlot(win, slot, wm)
      end

      layouts[win][slot] = {
        cx = anchorX,
        cy = cy,
        innerColor = innerColor,
        innerSplit = innerSplit,
        pulseInner = hasLine,
      }
      handles[#handles + 1] = {
        win = win,
        slot = slot,
        cx = anchorX,
        cy = cy,
        innerColor = innerColor,
        innerSplit = innerSplit,
        pulseInner = hasLine,
        chromeFillColor = chromeFillColorForWindow(win, wm),
        chromeInkColor = idleInnerColorForWindow(win, wm),
      }
    end

    ::next_win::
  end

  for win, slots in pairs(slotNeeded) do
    if not isLinkWindowMinimized(win) then
      goto next_minimized
    end
    layouts[win] = layouts[win] or {}
    local cx, cy = getTaskbarLinkAnchor(app, win)
    if not (cx and cy) then
      goto next_minimized
    end
    for _, slot in ipairs(orderedActiveSlots(win, slots)) do
      layouts[win][slot] = {
        cx = cx,
        cy = cy,
        taskbarAnchor = true,
        innerColor = M.innerColorForSlot(win, slot, wm),
        pulseInner = slotHasLinkEdge(slotLinked, win, slot),
      }
    end
    ::next_minimized::
  end

  return layouts, handles
end

function M.ppuPatternBgLinked(ppu, wm)
  if not (ppu and ppu.layers and wm) then
    return false
  end
  for _, layer in ipairs(ppu.layers) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      local id = layer.linkedPatternTableWindowId
      if type(id) == "string" and id ~= "" and wm.findWindowById then
        local pt = wm:findWindowById(id)
        if pt and isLinkWindowVisible(pt) and WindowCaps.isPatternTable(pt) then
          return true
        end
      end
    end
  end
  return false
end

function M.oamPatternLinked(oam, wm)
  if not (oam and oam.layers and wm) then
    return false
  end
  for _, layer in ipairs(oam.layers) do
    if layer and layer.kind == "sprite" then
      local id = layer.linkedPatternTableWindowId
      if type(id) == "string" and id ~= "" and wm.findWindowById then
        local pt = wm:findWindowById(id)
        if pt and isLinkWindowVisible(pt) and WindowCaps.isPatternTable(pt) then
          return true
        end
      end
    end
  end
  return false
end

function M.ppuPatternSpriteLinked(ppu, wm)
  if not (ppu and ppu.layers) then
    return false
  end
  for _, layer in ipairs(ppu.layers) do
    if layer and layer.kind == "sprite" then
      local id = layer.linkedPatternTableWindowId
      if type(id) == "string" and id ~= "" then
        return true
      end
    end
  end
  return false
end

function M.romPaletteHasConsumers(paletteWin, wm)
  if not (paletteWin and wm) then
    return false
  end
  local targets = PaletteLinkController.getLinkedTargetsForPalette(wm, paletteWin)
  return #(targets or {}) > 0
end

function M.pulseLinkColor(semanticColor, t)
  local c = semanticColor or colors.blue
  local lum = UiPulse.luminanceBackdrop01(t or UiPulse.nowSeconds())
  local b = colors.black
  return {
    (b[1] or 0) + ((c[1] or 0) - (b[1] or 0)) * lum,
    (b[2] or 0) + ((c[2] or 0) - (b[2] or 0)) * lum,
    (b[3] or 0) + ((c[3] or 0) - (b[3] or 0)) * lum,
    1,
  }
end

function M.drawPivotHandle(cx, cy, innerColor, pulseT, pulseInner, chromeFillColor, chromeInkColor, innerSplit)
  if not (cx and cy) then
    return
  end
  local ox, oy = M.getPivotHandleRect(cx, cy)
  if not ox then
    return
  end

  local outer = chromeFillColor or colors:chromeBackgroundUnfocused()
  love.graphics.setColor(outer[1], outer[2], outer[3], outer[4] or 1)
  love.graphics.rectangle("fill", ox, oy, HANDLE_OUTER_W, HANDLE_OUTER_H, HANDLE_OUTER_RADIUS, HANDLE_OUTER_RADIUS)

  local ix = ox + math.floor((HANDLE_OUTER_W - HANDLE_INNER_W) * 0.5)
  local iy = oy + math.floor((HANDLE_OUTER_H - HANDLE_INNER_H) * 0.5)
  local idle = chromeInkColor or idleInnerColorForWindow(nil, nil)

  if innerSplit == "red_green" and pulseInner then
    local red = M.pulseLinkColor(colors.red, pulseT)
    local green = M.pulseLinkColor(colors.green, pulseT)
    local halfW = math.floor(HANDLE_INNER_W * 0.5)
    love.graphics.setColor(red[1], red[2], red[3], red[4] or 1)
    love.graphics.rectangle("fill", ix, iy, halfW, HANDLE_INNER_H)
    love.graphics.setColor(green[1], green[2], green[3], green[4] or 1)
    love.graphics.rectangle("fill", ix + halfW, iy, HANDLE_INNER_W - halfW, HANDLE_INNER_H)
  elseif innerSplit == "red_green" then
    local halfW = math.floor(HANDLE_INNER_W * 0.5)
    love.graphics.setColor(colors.red[1], colors.red[2], colors.red[3], 1)
    love.graphics.rectangle("fill", ix, iy, halfW, HANDLE_INNER_H)
    love.graphics.setColor(colors.green[1], colors.green[2], colors.green[3], 1)
    love.graphics.rectangle("fill", ix + halfW, iy, HANDLE_INNER_W - halfW, HANDLE_INNER_H)
  else
    local baseInner = innerColor or idle
    local inner = pulseInner and M.pulseLinkColor(baseInner, pulseT) or baseInner
    love.graphics.setColor(inner[1], inner[2], inner[3], inner[4] or 1)
    love.graphics.rectangle("fill", ix, iy, HANDLE_INNER_W, HANDLE_INNER_H)
  end
end

local function patternConsumerAnchorSlot(win, layer)
  if WindowCaps.isPpuFrame(win) then
    if layer and layer.kind == "sprite" then
      return "ppu_pattern_sprite"
    end
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      return "ppu_pattern_bg"
    end
    return nil
  end
  if WindowCaps.isOamAnimation(win) and layer and layer.kind == "sprite" then
    return "oam_pattern"
  end
  return nil
end

local function patternEdgeColorForLayer(layer)
  if layer and layer.kind == "sprite" then
    return colors.green
  end
  if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
    return colors.red
  end
  return nil
end

function M.collectWindowLinkEdges(app)
  local edges = {}
  local wm = app and app.wm
  if not (wm and wm.getWindows) then
    return edges
  end

  local paletteSeen = {}

  for _, consumer in ipairs(wm:getWindows()) do
    if isLinkWindowEligible(consumer) and consumerSupportsPaletteLink(consumer) then
      local paletteWin = getConsumerLinkedPaletteWindowRaw(consumer, wm, true)
      if paletteWin and isLinkWindowEligible(paletteWin) then
        local key = tostring(consumer._id or consumer) .. "->" .. tostring(paletteWin._id or paletteWin)
        if not paletteSeen[key] then
          paletteSeen[key] = true
          edges[#edges + 1] = {
            fromWin = consumer,
            fromSlot = consumerPaletteLinkSlot(consumer),
            toWin = paletteWin,
            toSlot = "palette_source",
            color = colors.blue,
          }
        end
      end
    end
  end

  for _, ptWin in ipairs(PatternTableDisplayController.collectPatternTableWindows(wm)) do
    if isLinkWindowEligible(ptWin) then
      local consumers = PatternTableDisplayController.getLinkedConsumersForPatternTable(wm, ptWin)
      for _, entry in ipairs(consumers) do
        local consumer = entry.win
        local layer = consumer and consumer.layers and consumer.layers[entry.layerIndex]
        local lineColor = patternEdgeColorForLayer(layer)
        local toSlot = consumer and patternConsumerAnchorSlot(consumer, layer)
        if lineColor and toSlot and isLinkWindowEligible(consumer) then
          edges[#edges + 1] = {
            fromWin = ptWin,
            fromSlot = PATTERN_TABLE_SLOT,
            toWin = consumer,
            toSlot = toSlot,
            color = lineColor,
          }
        end
      end
    end
  end

  return edges
end

function M.drawLinkEdge(app, edge, layouts, pulseT)
  if not edge then
    return
  end
  local lineAlpha = WindowLinkVisibility.getLineAlpha(app, edge, layouts)
  if lineAlpha <= 0 then
    return
  end
  local fromCx, fromCy = M.getLeftAnchorPoint(edge.fromWin, edge.fromSlot, layouts)
  local toCx, toCy = M.getLeftAnchorPoint(edge.toWin, edge.toSlot, layouts)
  if not (fromCx and fromCy and toCx and toCy) then
    return
  end

  local fromEntry = layouts[edge.fromWin] and layouts[edge.fromWin][edge.fromSlot]
  local toEntry = layouts[edge.toWin] and layouts[edge.toWin][edge.toSlot]
  local function anchorLinePoint(entry, cx, cy)
    if layoutEntryUsesTaskbarAnchor(entry) then
      return roundPixel(cx), roundPixel(cy)
    end
    return M.getInnerRectCenterPoint(cx, cy)
  end
  local x1, y1 = anchorLinePoint(fromEntry, fromCx, fromCy)
  local x2, y2 = anchorLinePoint(toEntry, toCx, toCy)
  local lineColor = M.pulseLinkColor(edge.color, pulseT)
  local points

  local taskbarTopY = getTaskbarTopY(app)
  if taskbarTopY and layoutEntryUsesTaskbarAnchor(toEntry) then
    points = buildConnectorPointsViaTaskbar(x1, y1, x2, y2, taskbarTopY)
    pinPolylineEndpoints(points, x1, y1, x2, y2)
  elseif taskbarTopY and layoutEntryUsesTaskbarAnchor(fromEntry) then
    points = buildConnectorPointsViaTaskbar(x1, y1, x2, y2, taskbarTopY)
    pinPolylineEndpoints(points, x1, y1, x2, y2)
  else
    local geometry = PaletteLinkRenderController.buildConnectorGeometry(x1, y1, x2, y2, {
      showLine = true,
      alpha = 1,
      lineColor = lineColor,
    })
    if not (geometry and geometry.points and #geometry.points >= 4) then
      return
    end
    points = geometry.points
    pinPolylineEndpoints(points, x1, y1, x2, y2)
  end

  drawLinkPolyline(points, LINE_WIDTH, lineColor, lineAlpha)
end

local function shouldDrawEdgeForWindow(edge, win)
  if not (edge and win) then
    return false
  end
  if edge.fromWin == win then
    return true
  end
  if edge.toWin == win and edge.fromWin and edge.fromWin._minimized == true then
    return true
  end
  return false
end

function M.prepareLinkDrawState(app)
  if app and Shared.modalBlocksWorkspaceInteractions(app) then
    return nil
  end

  local tb = app and app.taskbar
  local canvas = app and app.canvas
  if tb and tb.updateLayout and canvas and canvas.getWidth then
    tb:updateLayout(canvas:getWidth(), canvas:getHeight())
  end

  local edges = M.collectWindowLinkEdges(app)
  local layouts, handles = M.buildAnchorLayouts(app, edges)
  local visibleEdges = {}
  for _, edge in ipairs(edges) do
    if WindowLinkVisibility.shouldShowEdge(app, edge, layouts) then
      visibleEdges[#visibleEdges + 1] = edge
    end
  end
  if #visibleEdges == 0 and #handles == 0 then
    return nil
  end

  return {
    app = app,
    layouts = layouts,
    handles = handles,
    visibleEdges = visibleEdges,
    pulseT = UiPulse.nowSeconds(),
  }
end

function M.drawWindowLinkOverlay(app, win, state)
  if not (app and win and state) then
    return
  end

  love.graphics.push("all")

  for _, handle in ipairs(state.handles or {}) do
    if handle.win ~= win then
      goto continue_handle
    end
    if not WindowLinkVisibility.shouldShowSlot(app, handle.slot) then
      goto continue_handle
    end
    M.drawPivotHandle(
      handle.cx,
      handle.cy,
      handle.innerColor,
      state.pulseT,
      handle.pulseInner,
      handle.chromeFillColor,
      handle.chromeInkColor,
      handle.innerSplit
    )
    ::continue_handle::
  end

  for _, edge in ipairs(state.visibleEdges or {}) do
    if shouldDrawEdgeForWindow(edge, win) then
      M.drawLinkEdge(app, edge, state.layouts, state.pulseT)
    end
  end

  love.graphics.pop()
end

function M.drawLinkLines(app)
  if app and Shared.modalBlocksWorkspaceInteractions(app) then
    return
  end

  local wm = app and app.wm
  if not (wm and wm.getWindows) then
    return
  end

  local state = M.prepareLinkDrawState(app)
  if not state then
    return
  end

  for _, win in ipairs(wm:getWindows()) do
    if isLinkWindowVisible(win) then
      M.drawWindowLinkOverlay(app, win, state)
    end
  end
end

return M
