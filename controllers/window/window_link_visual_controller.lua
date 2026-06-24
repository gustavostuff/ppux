-- window_link_visual_controller.lua
-- On-canvas link lines and left-edge pivot handles (pattern table + ROM palette).

local colors = require("app_colors")
local images = require("images")
local Draw = require("utils.draw_utils")
local WindowCaps = require("controllers.window.window_capabilities")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local PaletteLinkRenderController = require("controllers.palette.palette_link_render_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local Shared = require("controllers.app.core_controller_shared")
local WindowLinkVisibility = require("controllers.window.window_link_visibility")

local M = {}

local LINE_WIDTH = 1
local HANDLE_OUTER_W = 7
local HANDLE_OUTER_H = 7
local HANDLE_OUTER_RADIUS = 2
local HANDLE_INNER_W = 3
local HANDLE_INNER_H = 3
local HANDLE_OUTSIDE_TOUCH_GAP = 0
local HANDLE_COLLAPSED_LEFT_INSET = 2
local HANDLE_GROUP_BELOW_HEADER = 3
local HANDLE_GROUP_ROW_GAP = 3

M.HANDLE_OUTER_SIZE = HANDLE_OUTER_W
M.HANDLE_INNER_SIZE = HANDLE_INNER_W
M.HANDLE_ROW_GAP = HANDLE_GROUP_ROW_GAP
M.LINE_WIDTH = LINE_WIDTH

local LINK_LINE_ANIM = {
  stepPx = 1,
  intervalSeconds = 0.1,
  borderPx = 0,
  useShader = false,
}

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

local function getAppTaskbar(app)
  if not app then
    return nil
  end
  return app.taskbar or (app.wm and app.wm.taskbar)
end

--- Bottom-center of the taskbar strip button (line terminates under the icon; taskbar draws on top).
local function getTaskbarLinkAnchor(app, win)
  local tb = getAppTaskbar(app)
  if not (tb and win) then
    return nil, nil
  end
  if tb.getMinimizedWindowLinkAnchor then
    return tb:getMinimizedWindowLinkAnchor(win)
  end
  local btn = tb.minimizedButtonsByWindow and tb.minimizedButtonsByWindow[win]
  if not btn then
    return nil, nil
  end
  local w = tonumber(btn.w) or 0
  local h = tonumber(btn.h) or 0
  if w <= 0 or h <= 0 then
    h = tonumber(tb.h) or h
    w = h
  end
  if w <= 0 or h <= 0 then
    return nil, nil
  end
  if type(btn.x) ~= "number" or type(btn.y) ~= "number" then
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

local function buildHandleAnchorPositions(win, count)
  count = math.max(1, math.floor(tonumber(count) or 1))
  local hx, hy, hw, hh
  if win and win.getHeaderRect then
    hx, hy, hw, hh = win:getHeaderRect()
  end
  if not (hy and hh) then
    local x, y, w, h = getWindowBodyRect(win)
    hx = x or 0
    hy = y or 0
    hw = w or 0
    hh = h or 16
  end
  hw = tonumber(hw) or 0
  hh = tonumber(hh) or 0
  local rowStep = HANDLE_OUTER_H + HANDLE_GROUP_ROW_GAP
  local collapsed = win and win._collapsed == true
  if collapsed then
    local colStep = HANDLE_OUTER_W + HANDLE_GROUP_ROW_GAP
    local firstCenterX = roundPixel((tonumber(hx) or 0) + HANDLE_OUTER_W * 0.5 + HANDLE_COLLAPSED_LEFT_INSET)
    local centerY = roundPixel(hy + hh + HANDLE_OUTER_H * 0.5 - 1)
    local out = {}
    for i = 0, count - 1 do
      out[#out + 1] = {
        cx = roundPixel(firstCenterX + i * colStep),
        cy = centerY,
      }
    end
    return out
  end
  local anchorX = M.handleCenterXForWindowLeft(hx)
  local firstCenterY = hy + hh + HANDLE_GROUP_BELOW_HEADER + HANDLE_OUTER_H * 0.5
  local out = {}
  for i = 0, count - 1 do
    out[#out + 1] = {
      cx = anchorX,
      cy = roundPixel(firstCenterY + i * rowStep),
    }
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

function M.getConsumerLinkedPaletteWindowIncludingMinimized(consumer, wm)
  return getConsumerLinkedPaletteWindowRaw(consumer, wm, true)
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

local function linkEdgeColorForSlot(win, slot, edges)
  for _, edge in ipairs(edges or {}) do
    if edge.fromWin == win and edge.fromSlot == slot then
      return edge.color
    end
    if edge.toWin == win and edge.toSlot == slot then
      return edge.color
    end
  end
  return nil
end

local function innerColorAndSplitForHandleSlot(win, slot, wm, edges, hasLine)
  if not hasLine then
    return colors.transparent, nil
  end
  if WindowCaps.isPatternTable(win) and slot == PATTERN_TABLE_SLOT then
    local hasRed, hasGreen = patternTableOutgoingKinds(win, edges)
    if hasRed and hasGreen then
      return colors.transparent, "red_green"
    elseif hasRed then
      return colors.red, "red"
    elseif hasGreen then
      return colors.green, "green"
    end
    return colors.transparent, nil
  end
  return linkEdgeColorForSlot(win, slot, edges) or M.innerColorForSlot(win, slot, wm), nil
end

local function isInnerColorTransparent(color)
  return color and (tonumber(color[4]) or 1) <= 0
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
  local ix = ox + math.floor((HANDLE_OUTER_W - HANDLE_INNER_W) * 0.5) + 1
  local iy = oy + math.floor((HANDLE_OUTER_H - HANDLE_INNER_H) * 0.5) + 1
  return ix, iy, HANDLE_INNER_W, HANDLE_INNER_H
end

--- Center pixel of the 3×3 inner square (link line attachment point).
function M.getInnerRectCenterPoint(cx, cy)
  local ix, iy = M.getInnerRectForHandleCenter(cx, cy)
  if not ix then
    return roundPixel(cx) + 1, roundPixel(cy) + 1
  end
  return ix + 1, iy + 1
end

local function computeHandleInnerCenterPixel(cx, cy)
  local ix, iy = M.getInnerRectForHandleCenter(cx, cy)
  if not ix then
    return roundPixel(cx) + 1, roundPixel(cy) + 1
  end
  return ix + 1, iy + 1
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

--- Elbow from workspace handle to taskbar: horizontal at handle.y toward taskbar.x, then down to taskbar.
local function buildConnectorPointsHandleToTaskbar(handleX, handleY, taskbarX, taskbarY)
  local hx = roundPixel(handleX)
  local hy = roundPixel(handleY)
  local tx = roundPixel(taskbarX)
  local ty = roundPixel(taskbarY)
  return {
    hx, hy,
    tx, hy,
    tx, ty,
  }
end

local function layoutEntryUsesTaskbarAnchor(entry)
  return entry and entry.taskbarAnchor == true
end

local function edgeHasTaskbarEndpoint(edge, layouts)
  if not (edge and layouts) then
    return false
  end
  local fromEntry = layouts[edge.fromWin] and layouts[edge.fromWin][edge.fromSlot]
  local toEntry = layouts[edge.toWin] and layouts[edge.toWin][edge.toSlot]
  return layoutEntryUsesTaskbarAnchor(fromEntry) or layoutEntryUsesTaskbarAnchor(toEntry)
end

local function refreshTaskbarAnchorLayouts(app, layouts)
  if not layouts then
    return
  end
  for win, slots in pairs(layouts) do
    if not isLinkWindowMinimized(win) then
      goto continue_win
    end
    local ax, ay = getTaskbarLinkAnchor(app, win)
    if not (ax and ay) then
      goto continue_win
    end
    local lineX = roundPixel(ax)
    local lineY = roundPixel(ay)
    for _, entry in pairs(slots) do
      if entry and entry.taskbarAnchor then
        entry.taskbarLineX = lineX
        entry.taskbarLineY = lineY
        entry.cx = ax
        entry.cy = ay
      end
    end
    ::continue_win::
  end
end

local function getLinkLineAnchorPoint(entry, cx, cy)
  if entry and layoutEntryUsesTaskbarAnchor(entry) then
    if entry.taskbarLineX and entry.taskbarLineY then
      return entry.taskbarLineX, entry.taskbarLineY
    end
    if entry.cx and entry.cy then
      return roundPixel(entry.cx), roundPixel(entry.cy)
    end
  end
  if entry and entry.lineCx and entry.lineCy then
    return entry.lineCx, entry.lineCy
  end
  return computeHandleInnerCenterPixel(cx, cy)
end

local function roundPolylinePoints(points)
  local rounded = {}
  for i = 1, #points do
    rounded[i] = roundPixel(points[i])
  end
  return rounded
end

local function polylineBounds(points, padding)
  padding = tonumber(padding) or 0
  local minX, minY = math.huge, math.huge
  local maxX, maxY = -math.huge, -math.huge
  for i = 1, #points, 2 do
    local x = points[i]
    local y = points[i + 1]
    if x < minX then minX = x end
    if y < minY then minY = y end
    if x > maxX then maxX = x end
    if y > maxY then maxY = y end
  end
  if minX == math.huge then
    return 0, 0, 0, 0
  end
  minX = minX - padding
  minY = minY - padding
  return minX, minY, (maxX - minX) + (padding * 2), (maxY - minY) + (padding * 2)
end

local function drawLinkPolylineSolid(points, thickness, color, alpha)
  if not (points and #points >= 4) then
    return
  end
  alpha = math.max(0, math.min(1, tonumber(alpha) or 1))
  if alpha <= 0 then
    return
  end
  local c = color or colors.blue
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * alpha)
  love.graphics.setLineStyle("rough")
  love.graphics.setLineJoin("miter")
  love.graphics.setLineWidth(math.max(1, tonumber(thickness) or 1))
  love.graphics.line(unpack(roundPolylinePoints(points)))
end

local function drawLinkPolyline(points, thickness, color, alpha)
  if not (points and #points >= 4) then
    return
  end
  alpha = math.max(0, math.min(1, tonumber(alpha) or 1))
  if alpha <= 0 then
    return
  end
  if not (images and images.pattern_c) then
    drawLinkPolylineSolid(points, thickness, color, alpha)
    return
  end

  local rounded = roundPolylinePoints(points)
  local lineWidth = math.max(1, tonumber(thickness) or 1)
  local pad = math.ceil(lineWidth * 0.5) + 1
  local bx, by, bw, bh = polylineBounds(rounded, pad)
  if bw <= 0 or bh <= 0 then
    return
  end

  local c = color or colors.blue
  local ix = math.floor(bx)
  local iy = math.floor(by)
  local iw = math.ceil(bw)
  local ih = math.ceil(bh)

  love.graphics.push("all")
  love.graphics.stencil(function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", ix, iy, iw, ih)
  end, "replace", 0)
  love.graphics.stencil(function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineStyle("rough")
    love.graphics.setLineJoin("miter")
    love.graphics.setLineWidth(lineWidth)
    love.graphics.line(unpack(rounded))
  end, "replace", 1)
  love.graphics.setStencilTest("equal", 1)
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * alpha)
  Draw.drawRepeatingImageAnimated(images.pattern_c, ix, iy, iw, ih, LINK_LINE_ANIM)
  love.graphics.pop()
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
      return M.ppuPatternBgLinked(win, wm) and colors.red or colors.transparent
    end
    if slot == "ppu_pattern_sprite" then
      return M.ppuPatternSpriteLinked(win, wm) and colors.green or colors.transparent
    end
    if slot == "ppu_palette" then
      local linked = M.getConsumerLinkedPaletteWindowIncludingMinimized(win, wm)
      return linked and colors.blue or colors.transparent
    end
  end

  if WindowCaps.isRomPaletteWindow(win) and slot == "palette_source" then
    return M.romPaletteHasConsumers(win, wm) and colors.blue or colors.transparent
  end

  if slot == "layout_palette" then
    local linked = M.getConsumerLinkedPaletteWindowIncludingMinimized(win, wm)
    return linked and colors.blue or colors.transparent
  end

  if slot == "oam_pattern" then
    return M.oamPatternLinked(win, wm) and colors.green or colors.transparent
  end

  return colors.transparent
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
      local innerColor, innerSplit = innerColorAndSplitForHandleSlot(win, slot, wm, edges, hasLine)

      local lineCx, lineCy = computeHandleInnerCenterPixel(anchorX, cy)
      layouts[win][slot] = {
        cx = anchorX,
        cy = cy,
        lineCx = lineCx,
        lineCy = lineCy,
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
    local lineX = cx and roundPixel(cx) or nil
    local lineY = cy and roundPixel(cy) or nil
    for _, slot in ipairs(orderedActiveSlots(win, slots)) do
      local hasLine = slotHasLinkEdge(slotLinked, win, slot)
      local innerColor = innerColorAndSplitForHandleSlot(win, slot, wm, edges, hasLine)
      layouts[win][slot] = {
        cx = cx,
        cy = cy,
        taskbarLineX = lineX,
        taskbarLineY = lineY,
        taskbarAnchor = true,
        innerColor = innerColor,
        pulseInner = hasLine,
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
        if pt and isLinkWindowEligible(pt) and WindowCaps.isPatternTable(pt) then
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
        if pt and isLinkWindowEligible(pt) and WindowCaps.isPatternTable(pt) then
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

local function drawLinkInnerSolid(ix, iy, iw, ih, color)
  local c = color or colors.white
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
  love.graphics.rectangle("fill", ix, iy, iw, ih)
end

function M.drawPivotHandleChrome(cx, cy, chromeFillColor)
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
end

function M.drawPivotHandleInner(cx, cy, innerColor, pulseInner, chromeInkColor, innerSplit)
  if not (cx and cy) then
    return
  end
  local ox, oy = M.getPivotHandleRect(cx, cy)
  if not ox then
    return
  end
  local ix = ox + math.floor((HANDLE_OUTER_W - HANDLE_INNER_W) * 0.5)
  local iy = oy + math.floor((HANDLE_OUTER_H - HANDLE_INNER_H) * 0.5)
  local idle = chromeInkColor or idleInnerColorForWindow(nil, nil)

  if innerSplit == "red_green" then
    for row = 0, HANDLE_INNER_H - 1 do
      for col = 0, HANDLE_INNER_W - 1 do
        local cellColor = ((col + row) % 2 == 0) and colors.red or colors.green
        drawLinkInnerSolid(ix + col, iy + row, 1, 1, cellColor)
      end
    end
  else
    local baseInner = innerColor or idle
    if isInnerColorTransparent(baseInner) then
      return
    end
    drawLinkInnerSolid(ix, iy, HANDLE_INNER_W, HANDLE_INNER_H, baseInner)
  end
  love.graphics.setColor(colors.white)
end

function M.drawPivotHandle(cx, cy, innerColor, pulseInner, chromeFillColor, chromeInkColor, innerSplit)
  M.drawPivotHandleChrome(cx, cy, chromeFillColor)
  M.drawPivotHandleInner(cx, cy, innerColor, pulseInner, chromeInkColor, innerSplit)
end

local function isLinkHandleShadowEligible(win)
  return win
    and not win._closed
    and not win._minimized
    and win._groupHidden ~= true
    and not WindowCaps.isCrtLens(win)
end

--- Rounded 7×7 silhouettes for the shared window-shadow blur pass (see core_controller_draw.drawAllWindowShadows).
function M.drawHardShadowMasksForVisibleHandles(app, shadowOx, shadowOy)
  if not app then
    return
  end
  local state = M.prepareLinkDrawState(app)
  if not state then
    return
  end
  shadowOx = math.floor(tonumber(shadowOx) or 0)
  shadowOy = math.floor(tonumber(shadowOy) or 0)
  for _, handle in ipairs(state.handles or {}) do
    if not isLinkHandleShadowEligible(handle.win) then
      goto continue
    end
    if not WindowLinkVisibility.shouldShowSlot(app, handle.slot) then
      goto continue
    end
    local ox, oy = M.getPivotHandleRect(handle.cx, handle.cy)
    if ox then
      love.graphics.rectangle(
        "fill",
        ox + shadowOx,
        oy + shadowOy,
        HANDLE_OUTER_W,
        HANDLE_OUTER_H,
        HANDLE_OUTER_RADIUS,
        HANDLE_OUTER_RADIUS
      )
    end
    ::continue::
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

function M.drawLinkEdge(app, edge, layouts)
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
  local x1, y1 = getLinkLineAnchorPoint(fromEntry, fromCx, fromCy)
  local x2, y2 = getLinkLineAnchorPoint(toEntry, toCx, toCy)
  local lineColor = edge.color or colors.blue
  local points

  if layoutEntryUsesTaskbarAnchor(toEntry) or layoutEntryUsesTaskbarAnchor(fromEntry) then
    local handleX, handleY, taskbarX, taskbarY
    if layoutEntryUsesTaskbarAnchor(toEntry) then
      handleX, handleY = x1, y1
      taskbarX, taskbarY = x2, y2
    else
      handleX, handleY = x2, y2
      taskbarX, taskbarY = x1, y1
    end
    points = buildConnectorPointsHandleToTaskbar(handleX, handleY, taskbarX, taskbarY)
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

local function windowZIndex(wm, win)
  if not (wm and win and wm.getWindows) then
    return 0
  end
  for i, w in ipairs(wm:getWindows()) do
    if w == win then
      return i
    end
  end
  return 0
end

local function getEdgeDrawOwnerBackmost(wm, edge)
  if not edge then
    return nil
  end
  local fromWin = edge.fromWin
  local toWin = edge.toWin
  if fromWin and fromWin._minimized and toWin and not toWin._minimized then
    return toWin
  end
  if toWin and toWin._minimized and fromWin and not fromWin._minimized then
    return fromWin
  end
  if not (fromWin and toWin) then
    return fromWin or toWin
  end
  if windowZIndex(wm, fromWin) <= windowZIndex(wm, toWin) then
    return fromWin
  end
  return toWin
end

local function getEdgeDrawOwnerFrontmost(wm, edge)
  if not edge then
    return nil
  end
  local fromWin = edge.fromWin
  local toWin = edge.toWin
  if fromWin and fromWin._minimized and toWin and not toWin._minimized then
    return toWin
  end
  if toWin and toWin._minimized and fromWin and not fromWin._minimized then
    return fromWin
  end
  if not (fromWin and toWin) then
    return fromWin or toWin
  end
  if windowZIndex(wm, fromWin) >= windowZIndex(wm, toWin) then
    return fromWin
  end
  return toWin
end

local function edgeEndpointsDifferInZOrder(wm, edge)
  local back = getEdgeDrawOwnerBackmost(wm, edge)
  local front = getEdgeDrawOwnerFrontmost(wm, edge)
  return back and front and back ~= front
end

local function appendWindowScreenBounds(bounds, win)
  if not win then
    return bounds
  end
  local x, y, w, h
  if win._collapsed and win.getHeaderRect then
    x, y, w, h = win:getHeaderRect()
  elseif win.getScreenRect then
    x, y, w, h = win:getScreenRect()
  else
    return bounds
  end
  if not (x and y and w and h) then
    return bounds
  end
  local x2 = x + w
  local y2 = y + h
  if not bounds then
    return { x0 = x, y0 = y, x1 = x2, y1 = y2 }
  end
  bounds.x0 = math.min(bounds.x0, x)
  bounds.y0 = math.min(bounds.y0, y)
  bounds.x1 = math.max(bounds.x1, x2)
  bounds.y1 = math.max(bounds.y1, y2)
  return bounds
end

local function scissorForEdgeEndpoints(edge, pad)
  pad = math.max(0, math.floor(tonumber(pad) or 4))
  local bounds = appendWindowScreenBounds(nil, edge.fromWin)
  bounds = appendWindowScreenBounds(bounds, edge.toWin)
  if not bounds then
    return false
  end
  love.graphics.setScissor(
    math.floor(bounds.x0) - pad,
    math.floor(bounds.y0) - pad,
    math.ceil(bounds.x1 - bounds.x0) + pad * 2,
    math.ceil(bounds.y1 - bounds.y0) + pad * 2
  )
  return true
end

function M.prepareLinkDrawState(app)
  if app and Shared.modalBlocksWorkspaceInteractions(app) then
    return nil
  end

  local tb = getAppTaskbar(app)
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
  }
end

local function drawHandlesForWindow(app, win, state, drawFn)
  if not (app and win and state and drawFn) then
    return
  end
  for _, handle in ipairs(state.handles or {}) do
    if handle.win ~= win then
      goto continue_handle
    end
    if not WindowLinkVisibility.shouldShowSlot(app, handle.slot) then
      goto continue_handle
    end
    drawFn(
      handle.cx,
      handle.cy,
      handle.innerColor,
      handle.pulseInner,
      handle.chromeFillColor,
      handle.chromeInkColor,
      handle.innerSplit
    )
    ::continue_handle::
  end
end

--- Pass 1 for `win`: every 8×8 handle chrome rectangle (no inners, no lines).
function M.drawWindowLinkHandleChromes(app, win, state)
  if not (app and win and state) then
    return
  end
  love.graphics.push("all")
  drawHandlesForWindow(app, win, state, function(cx, cy, _, _, chromeFill)
    M.drawPivotHandleChrome(cx, cy, chromeFill)
  end)
  love.graphics.pop()
end

--- Pass 2 for `win`: every 3×3 animated-pattern inner square (no lines).
function M.drawWindowLinkHandleInners(app, win, state)
  if not (app and win and state) then
    return
  end
  love.graphics.push("all")
  drawHandlesForWindow(app, win, state, function(cx, cy, innerColor, pulseInner, _, chromeInk, innerSplit)
    M.drawPivotHandleInner(cx, cy, innerColor, pulseInner, chromeInk, innerSplit)
  end)
  love.graphics.pop()
end

--- Link lines for `win`: backmost underlay when endpoints differ in z; full line when same window.
function M.drawWindowLinkLines(app, win, state)
  if not (app and win and state) then
    return
  end
  local wm = app.wm
  if not wm then
    return
  end
  love.graphics.push("all")
  for _, edge in ipairs(state.visibleEdges or {}) do
    if edgeHasTaskbarEndpoint(edge, state.layouts) then
      goto continue_edge
    end
    if getEdgeDrawOwnerBackmost(wm, edge) ~= win then
      goto continue_edge
    end
    if edgeEndpointsDifferInZOrder(wm, edge) or getEdgeDrawOwnerFrontmost(wm, edge) == win then
      M.drawLinkEdge(app, edge, state.layouts)
    end
    ::continue_edge::
  end
  love.graphics.pop()
end

--- Lines to minimized taskbar buttons (after all windows; taskbar draws on top of the endpoint).
function M.drawWindowLinkLinesToTaskbar(app, state)
  if not (app and state) then
    return
  end
  local tb = getAppTaskbar(app)
  local canvas = app and app.canvas
  if tb and tb.updateLayout and canvas and canvas.getWidth then
    tb:updateLayout(canvas:getWidth(), canvas:getHeight())
  end
  refreshTaskbarAnchorLayouts(app, state.layouts)
  love.graphics.push("all")
  for _, edge in ipairs(state.visibleEdges or {}) do
    if edgeHasTaskbarEndpoint(edge, state.layouts) then
      M.drawLinkEdge(app, edge, state.layouts)
    end
  end
  love.graphics.pop()
end

--- Redraw lines on top of handle squares at the frontmost endpoint (clipped to both windows).
function M.drawWindowLinkLinesFrontmostOverlay(app, state)
  if not (app and state) then
    return
  end
  local wm = app and app.wm
  if not wm then
    return
  end

  love.graphics.push("all")
  for _, edge in ipairs(state.visibleEdges or {}) do
    if not edgeEndpointsDifferInZOrder(wm, edge) then
      goto continue_edge
    end
    if scissorForEdgeEndpoints(edge, 6) then
      M.drawLinkEdge(app, edge, state.layouts)
      love.graphics.setScissor()
    end
    ::continue_edge::
  end
  love.graphics.pop()
end

function M.drawWindowLinkOverlay(app, win, state)
  M.drawWindowLinkHandleChromes(app, win, state)
  M.drawWindowLinkHandleInners(app, win, state)
  M.drawWindowLinkLines(app, win, state)
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
  M.drawWindowLinkLinesFrontmostOverlay(app, state)
  M.drawWindowLinkLinesToTaskbar(app, state)
end

return M
