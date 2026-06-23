-- window_link_visibility.lua
-- Settings-driven visibility for on-canvas palette / pattern-table link lines and handles.

local colors = require("app_colors")
local ResolutionController = require("controllers.app.resolution_controller")
local MouseWindowChrome = require("controllers.input.mouse_window_chrome_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local LoveCompat = require("utils.love_compat")

--- Keep in sync with `HANDLE_OUTER_W` in window_link_visual_controller.lua.
local HANDLE_OUTER_HIT_HALF = 4

local M = {}

-- Code-only auto_hide timing/behavior (no settings UI).
--- Seconds link lines stay visible after a reveal trigger before hiding.
M.REVEAL_VISIBLE_SECONDS = 1.5
--- When true, alpha ramps 1→0 over REVEAL_VISIBLE_SECONDS; when false, full opacity then instant hide.
M.USE_REVEAL_FADE_OUT = true

--- @deprecated Use REVEAL_VISIBLE_SECONDS.
M.REVEAL_DURATION = M.REVEAL_VISIBLE_SECONDS

M.PALETTE_REVEAL_FIELD = "_paletteLinkRevealUntil"
M.PATTERN_REVEAL_FIELD = "_patternTableLinkRevealUntil"

local PALETTE_SLOTS = {
  ppu_palette = true,
  layout_palette = true,
  palette_source = true,
}

local PATTERN_SLOTS = {
  pattern_source = true,
  ppu_pattern_bg = true,
  ppu_pattern_sprite = true,
  oam_pattern = true,
}

function M.normalizeLinkMode(mode)
  if mode == "never" then
    return "never"
  end
  if mode == "on_hover" then
    return "on_hover"
  end
  if mode == "always" then
    return "always"
  end
  if mode == "auto_hide" then
    return "auto_hide"
  end
  return "auto_hide"
end

function M.getWindowLinksMode(app)
  return M.normalizeLinkMode(app and app.windowLinksMode)
end

function M.getPaletteLinksMode(app)
  return M.getWindowLinksMode(app)
end

function M.getPatternTableLinksMode(app)
  return M.getWindowLinksMode(app)
end

function M.getModeForKind(app, _kind)
  return M.getWindowLinksMode(app)
end

function M.slotKind(slot)
  if PALETTE_SLOTS[slot] then
    return "palette"
  end
  if PATTERN_SLOTS[slot] then
    return "pattern"
  end
  return nil
end

function M.edgeKind(edge)
  if edge and edge.color == colors.blue then
    return "palette"
  end
  return "pattern"
end

function M.shouldShowHandlesForKind(app, kind)
  return M.getModeForKind(app, kind) ~= "never"
end

function M.shouldShowSlot(app, slot)
  local kind = M.slotKind(slot)
  if not kind then
    return true
  end
  return M.shouldShowHandlesForKind(app, kind)
end

function M.shouldShowEdge(app, edge)
  if not edge then
    return false
  end
  return M.shouldShowHandlesForKind(app, M.edgeKind(edge))
end

local function isLinkWindowVisible(win)
  return win
    and win._closed ~= true
    and win._minimized ~= true
    and win._groupHidden ~= true
end

local function isLinkWindowEligible(win)
  return win and win._closed ~= true and win._groupHidden ~= true
end

local function isHoveringTaskbarButton(app, win)
  if not (app and win) then
    return false
  end
  local tb = app.taskbar or (app.wm and app.wm.taskbar)
  local btn = tb and tb.minimizedButtonsByWindow and tb.minimizedButtonsByWindow[win]
  if not (btn and btn.contains) then
    return false
  end
  local mouse = ResolutionController:getScaledMouse(true)
  local mx = mouse and mouse.x
  local my = mouse and mouse.y
  if type(mx) ~= "number" or type(my) ~= "number" then
    mx, my = LoveCompat.getMousePosition()
  end
  if type(mx) ~= "number" or type(my) ~= "number" then
    return false
  end
  return btn:contains(mx, my)
end

function M.touchReveal(win, field, duration)
  if not (win and field) then
    return
  end
  win[field] = LoveCompat.getTime() + (tonumber(duration) or M.REVEAL_VISIBLE_SECONDS)
end

function M.getRevealAlpha(win, field)
  if not win then
    return 0
  end
  local untilT = tonumber(win[field]) or 0
  local now = LoveCompat.getTime()
  local remaining = untilT - now
  if remaining <= 0 then
    return 0
  end
  if M.USE_REVEAL_FADE_OUT then
    return remaining / M.REVEAL_VISIBLE_SECONDS
  end
  return 1
end

function M.getRevealAlphaForEdge(edge)
  if not edge then
    return 0
  end
  local field = (M.edgeKind(edge) == "pattern") and M.PATTERN_REVEAL_FIELD or M.PALETTE_REVEAL_FIELD
  return math.max(
    M.getRevealAlpha(edge.fromWin, field),
    M.getRevealAlpha(edge.toWin, field)
  )
end

function M.isPointInHandle(cx, cy, x, y, pad)
  if not (cx and cy and x and y) then
    return false
  end
  pad = tonumber(pad) or 0
  local half = HANDLE_OUTER_HIT_HALF + pad
  return x >= (cx - half) and x <= (cx + half) and y >= (cy - half) and y <= (cy + half)
end

local function isPointOccludedByForegroundWindowBody(windows, ownerIndex, x, y)
  for j = ownerIndex + 1, #windows do
    local frontWin = windows[j]
    if isLinkWindowVisible(frontWin)
      and MouseWindowChrome.isPointOnWindowInteractiveSurface(frontWin, x, y)
    then
      return true
    end
  end
  return false
end

--- Frontmost visible pivot handle at (x,y), or nil when occluded by a window body in front.
function M.getTopLinkHandleAt(app, x, y, layouts)
  if not (app and layouts and type(x) == "number" and type(y) == "number") then
    return nil, nil
  end
  local wm = app.wm
  if not (wm and wm.getWindows) then
    return nil, nil
  end

  local windows = wm:getWindows()
  for i = #windows, 1, -1 do
    local win = windows[i]
    if not isLinkWindowVisible(win) then
      goto continue_win
    end
    local slots = layouts[win]
    if not slots then
      goto continue_win
    end
    for slot, entry in pairs(slots) do
      if M.shouldShowSlot(app, slot)
        and entry
        and M.isPointInHandle(entry.cx, entry.cy, x, y, 0)
      then
        if isPointOccludedByForegroundWindowBody(windows, i, x, y) then
          return nil, nil
        end
        return win, slot
      end
    end
    ::continue_win::
  end
  return nil, nil
end

function M.isHoveringEdgeHandles(app, edge, layouts)
  if not (edge and layouts) then
    return false
  end
  local mouse = ResolutionController:getScaledMouse(true)
  local mx = mouse and mouse.x
  local my = mouse and mouse.y
  if type(mx) ~= "number" or type(my) ~= "number" then
    mx, my = LoveCompat.getMousePosition()
  end
  if type(mx) ~= "number" or type(my) ~= "number" then
    return false
  end
  if isHoveringTaskbarButton(app, edge.fromWin) or isHoveringTaskbarButton(app, edge.toWin) then
    return true
  end
  local hoverWin, hoverSlot = M.getTopLinkHandleAt(app, mx, my, layouts)
  if not hoverWin then
    return false
  end
  return (hoverWin == edge.fromWin and hoverSlot == edge.fromSlot)
    or (hoverWin == edge.toWin and hoverSlot == edge.toSlot)
end

function M.getLineAlpha(app, edge, layouts)
  if not M.shouldShowEdge(app, edge) then
    return 0
  end
  local mode = M.getModeForKind(app, M.edgeKind(edge))
  if mode == "never" then
    return 0
  end
  if mode == "on_hover" then
    return M.isHoveringEdgeHandles(app, edge, layouts) and 1 or 0
  end
  if mode == "always" then
    return 1
  end
  local alpha = M.getRevealAlphaForEdge(edge)
  if alpha > 0 then
    return alpha
  end
  return 0
end

local function collectPatternTableIdsForFocusedConsumer(win)
  local ids = {}
  if WindowCaps.isOamAnimation(win) then
    for _, layer in ipairs(win.layers or {}) do
      if layer and layer.kind == "sprite" then
        local id = layer.linkedPatternTableWindowId
        if type(id) == "string" and id ~= "" then
          ids[id] = true
        end
      end
    end
  elseif WindowCaps.isPpuFrame(win) then
    local idx = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
    local layer = win.layers and win.layers[idx]
    local id = layer and layer.linkedPatternTableWindowId
    if type(id) == "string" and id ~= "" then
      ids[id] = true
    end
  end
  return ids
end

local function refreshPaletteRevealForWindow(app, wm, win)
  if M.getWindowLinksMode(app) ~= "auto_hide" then
    return
  end
  if not (win and isLinkWindowEligible(win)) then
    return
  end

  if WindowCaps.isRomPaletteWindow(win) then
    M.touchReveal(win, M.PALETTE_REVEAL_FIELD)
    for _, entry in ipairs(PaletteLinkController.getLinkedTargetsForPalette(wm, win) or {}) do
      local target = entry and entry.win
      if isLinkWindowEligible(target) then
        M.touchReveal(target, M.PALETTE_REVEAL_FIELD)
      end
    end
    return
  end

  local WindowLinkVisual = require("controllers.window.window_link_visual_controller")
  local paletteWin = WindowLinkVisual.getConsumerLinkedPaletteWindowIncludingMinimized(win, wm)
  if paletteWin and isLinkWindowEligible(paletteWin) then
    M.touchReveal(win, M.PALETTE_REVEAL_FIELD)
    M.touchReveal(paletteWin, M.PALETTE_REVEAL_FIELD)
  end
end

local function refreshPatternRevealForWindow(app, wm, win)
  if M.getWindowLinksMode(app) ~= "auto_hide" then
    return
  end
  if not (win and isLinkWindowEligible(win)) then
    return
  end

  if WindowCaps.isPatternTable(win) then
    M.touchReveal(win, M.PATTERN_REVEAL_FIELD)
    for _, entry in ipairs(PatternTableDisplayController.getLinkedConsumersForPatternTable(wm, win) or {}) do
      local consumer = entry and entry.win
      if isLinkWindowEligible(consumer) then
        M.touchReveal(consumer, M.PATTERN_REVEAL_FIELD)
      end
    end
    return
  end

  if WindowCaps.isPpuFrame(win) or WindowCaps.isOamAnimation(win) then
    for id in pairs(collectPatternTableIdsForFocusedConsumer(win)) do
      local ptWin = wm.findWindowById and wm:findWindowById(id)
      if ptWin and isLinkWindowEligible(ptWin) and WindowCaps.isPatternTable(ptWin) then
        M.touchReveal(win, M.PATTERN_REVEAL_FIELD)
        M.touchReveal(ptWin, M.PATTERN_REVEAL_FIELD)
      end
    end
  end
end

--- Reset auto-hide line visibility timer for this window and its link partners (once per call).
function M.refreshRevealForWindow(app, wm, win)
  if not (app and wm and win) then
    return
  end
  refreshPaletteRevealForWindow(app, wm, win)
  refreshPatternRevealForWindow(app, wm, win)
end

function M.onWindowFocused(app, wm, win)
  if not (app and wm and win and isLinkWindowEligible(win)) then
    return
  end

  M.refreshRevealForWindow(app, wm, win)

  if M.getWindowLinksMode(app) ~= "auto_hide" then
    return
  end

  if WindowCaps.isRomPaletteWindow(win) then
    wm:bringToFront(win)
    for _, entry in ipairs(PaletteLinkController.getLinkedTargetsForPalette(wm, win) or {}) do
      local target = entry and entry.win
      if isLinkWindowVisible(target) then
        wm:bringToFront(target)
      end
    end
  else
    local WindowLinkVisual = require("controllers.window.window_link_visual_controller")
    local paletteWin = WindowLinkVisual.getConsumerLinkedPaletteWindow(win, wm)
    if paletteWin and isLinkWindowVisible(paletteWin) then
      wm:bringToFront(paletteWin)
    end
  end

  if WindowCaps.isPatternTable(win) then
    wm:bringToFront(win)
    for _, entry in ipairs(PatternTableDisplayController.getLinkedConsumersForPatternTable(wm, win) or {}) do
      local consumer = entry and entry.win
      if isLinkWindowVisible(consumer) then
        wm:bringToFront(consumer)
      end
    end
  elseif WindowCaps.isPpuFrame(win) or WindowCaps.isOamAnimation(win) then
    for id in pairs(collectPatternTableIdsForFocusedConsumer(win)) do
      local ptWin = wm.findWindowById and wm:findWindowById(id)
      if ptWin and isLinkWindowVisible(ptWin) and WindowCaps.isPatternTable(ptWin) then
        wm:bringToFront(ptWin)
      end
    end
  end
end

return M
