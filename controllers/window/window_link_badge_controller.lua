-- window_link_badge_controller.lua
-- Badge-only window linking: click focus, right-click menus, left-drag connect/retarget.

local WindowCaps = require("controllers.window.window_capabilities")
local WindowLinkVisibility = require("controllers.window.window_link_visibility")
local WindowLinkVisualController = require("controllers.window.window_link_visual_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local MouseWindowChrome = require("controllers.input.mouse_window_chrome_controller")

local M = {}

local DRAG_THRESHOLD_PX = 4

local PALETTE_SOURCE = "palette_source"
local PATTERN_SOURCE = "pattern_source"

local PALETTE_DEST = {
  ppu_palette = true,
  layout_palette = true,
}

local PATTERN_DEST = {
  ppu_pattern_bg = true,
  ppu_pattern_sprite = true,
  oam_pattern = true,
}

local function getApp()
  local gctx = rawget(_G, "ctx")
  return gctx and gctx.app or nil
end

local function getDrag(app)
  app = app or getApp()
  if not app then
    return nil
  end
  if type(app.windowLinkBadgeDrag) ~= "table" then
    app.windowLinkBadgeDrag = {
      active = false,
      pending = false,
      sourceWin = nil,
      sourceSlot = nil,
      sourceCx = 0,
      sourceCy = 0,
      startX = 0,
      startY = 0,
      currentX = 0,
      currentY = 0,
      legalHover = false,
      hoverWin = nil,
      hoverSlot = nil,
    }
  end
  return app.windowLinkBadgeDrag
end

function M.clearDrag(app)
  local drag = getDrag(app)
  if not drag then
    return
  end
  drag.active = false
  drag.pending = false
  drag.sourceWin = nil
  drag.sourceSlot = nil
  drag.sourceCx = 0
  drag.sourceCy = 0
  drag.startX = 0
  drag.startY = 0
  drag.currentX = 0
  drag.currentY = 0
  drag.legalHover = false
  drag.hoverWin = nil
  drag.hoverSlot = nil
end

function M.isDragActive(app)
  local drag = getDrag(app)
  return drag ~= nil and drag.active == true
end

function M.isPendingOrActive(app)
  local drag = getDrag(app)
  return drag ~= nil and (drag.active == true or drag.pending == true)
end

function M.isPaletteSlot(slot)
  return slot == PALETTE_SOURCE or PALETTE_DEST[slot] == true
end

function M.isPatternSlot(slot)
  return slot == PATTERN_SOURCE or PATTERN_DEST[slot] == true
end

function M.isSourceSlot(slot)
  return slot == PALETTE_SOURCE or slot == PATTERN_SOURCE
end

function M.isDestinationSlot(slot)
  return PALETTE_DEST[slot] == true or PATTERN_DEST[slot] == true
end

--- True when two badge slots can form a palette or pattern-table link.
function M.areSlotsCompatible(slotA, slotB)
  if not (slotA and slotB) or slotA == slotB then
    return false
  end
  if M.isPaletteSlot(slotA) and M.isPaletteSlot(slotB) then
    return (slotA == PALETTE_SOURCE) ~= (slotB == PALETTE_SOURCE)
  end
  if M.isPatternSlot(slotA) and M.isPatternSlot(slotB) then
    return (slotA == PATTERN_SOURCE) ~= (slotB == PATTERN_SOURCE)
  end
  return false
end

local function findPpuNametableTileLayerIndex(window)
  if not (window and window.layers) then
    return nil
  end
  for i, layer in ipairs(window.layers) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      if type(layer.nametableStartAddr) == "number" and type(layer.nametableEndAddr) == "number" then
        return i
      end
    end
  end
  for i, layer in ipairs(window.layers) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      return i
    end
  end
  return nil
end

local function findFirstSpriteLayerIndex(window)
  if not (window and window.layers) then
    return nil
  end
  for i, layer in ipairs(window.layers) do
    if layer and layer.kind == "sprite" then
      return i
    end
  end
  return nil
end

local function getActiveLayerIndex(win)
  if not win then
    return 1
  end
  return (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
end

local function resolvePalettePair(winA, slotA, winB, slotB)
  local paletteWin, destWin, destSlot
  if slotA == PALETTE_SOURCE then
    paletteWin, destWin, destSlot = winA, winB, slotB
  elseif slotB == PALETTE_SOURCE then
    paletteWin, destWin, destSlot = winB, winA, slotA
  else
    return nil
  end
  if not (WindowCaps.isRomPaletteWindow(paletteWin) and M.isDestinationSlot(destSlot) and M.isPaletteSlot(destSlot)) then
    return nil
  end
  return paletteWin, destWin, destSlot
end

local function resolvePatternPair(winA, slotA, winB, slotB)
  local ptWin, destWin, destSlot
  if slotA == PATTERN_SOURCE then
    ptWin, destWin, destSlot = winA, winB, slotB
  elseif slotB == PATTERN_SOURCE then
    ptWin, destWin, destSlot = winB, winA, slotA
  else
    return nil
  end
  if not (WindowCaps.isPatternTable(ptWin) and PATTERN_DEST[destSlot]) then
    return nil
  end
  return ptWin, destWin, destSlot
end

function M.canLinkWindows(winA, slotA, winB, slotB)
  if not (winA and winB and slotA and slotB) or winA == winB then
    return false, "Window link failed"
  end
  if winA._closed or winB._closed or winA._minimized or winB._minimized then
    return false, "Window link failed"
  end
  if not M.areSlotsCompatible(slotA, slotB) then
    return false, "Incompatible link badges"
  end

  local paletteWin, destWin = resolvePalettePair(winA, slotA, winB, slotB)
  if paletteWin then
    if WindowCaps.isAnyPaletteWindow(destWin) or WindowCaps.isChrLike(destWin) then
      return false, "Cannot link a palette to another palette window"
    end
    if WindowCaps.isSketchCanvas(destWin) then
      if paletteWin.paletteRole ~= "sketch" then
        return false, "Sketch canvases need a sketch-mode ROM palette"
      end
    elseif paletteWin.paletteRole == "sketch" then
      return false, "Sketch-mode palettes link only to sketch canvases"
    end
    local ok = PaletteLinkController.canApplyToTarget(destWin, paletteWin)
    if not ok then
      return false, "Palette link failed"
    end
    return true
  end

  local ptWin, consumer, destSlot = resolvePatternPair(winA, slotA, winB, slotB)
  if not ptWin then
    return false, "Incompatible link badges"
  end
  if destSlot == "ppu_pattern_bg" then
    if WindowCaps.isSketchCanvas(consumer) then
      return true
    end
    if WindowCaps.isPpuFrame(consumer) and findPpuNametableTileLayerIndex(consumer) then
      return true
    end
    return false, "No background layer"
  end
  if destSlot == "ppu_pattern_sprite" then
    if WindowCaps.isSketchCanvas(consumer) then
      return false, "Sketch canvas has no sprite pattern link"
    end
    if WindowCaps.isPpuFrame(consumer) and findFirstSpriteLayerIndex(consumer) then
      return true
    end
    return false, "No sprite layer"
  end
  if destSlot == "oam_pattern" then
    if WindowCaps.isOamAnimation(consumer) then
      return true
    end
    return false, "OAM pattern link requires an OAM animation window"
  end
  return false, "Incompatible link badges"
end

local function applyPaletteLink(app, paletteWin, destWin)
  local li = getActiveLayerIndex(destWin)
  local ok, err = PaletteLinkController.linkLayerToPalette(destWin, li, paletteWin)
  if ok and app and app.setStatus then
    app:setStatus(string.format(
      "Linked %s to %s layer %d",
      tostring(paletteWin.title or "palette"),
      tostring(destWin.title or "window"),
      li
    ))
  elseif not ok and app and app.setStatus then
    app:setStatus(err or "Palette link failed")
  end
  return ok == true
end

local function applyPatternLink(app, ptWin, destWin, destSlot)
  if destSlot == "ppu_pattern_bg" and WindowCaps.isSketchCanvas(destWin) then
    local ok = SketchCanvasPackController.linkSketchToPatternTable(destWin, ptWin, app and app.wm)
    if app and app.setStatus then
      app:setStatus(ok and "Linked sketch to pattern table" or "Pattern table link failed")
    end
    return ok == true
  end
  if destSlot == "oam_pattern" and WindowCaps.isOamAnimation(destWin) then
    local ok = PatternTableDisplayController.linkAllOamSpriteLayersToPatternTableWindow(destWin, ptWin)
    if app and app.setStatus then
      app:setStatus(ok and "Linked OAM frames to pattern table" or "Pattern table link failed")
    end
    return ok == true
  end
  local layerIndex
  if destSlot == "ppu_pattern_bg" then
    layerIndex = findPpuNametableTileLayerIndex(destWin)
  elseif destSlot == "ppu_pattern_sprite" then
    layerIndex = findFirstSpriteLayerIndex(destWin)
  end
  if not layerIndex then
    if app and app.setStatus then
      app:setStatus("Pattern table link failed")
    end
    return false
  end
  local ok = PatternTableDisplayController.linkContentLayerToPatternTableWindow(destWin, layerIndex, ptWin)
  if app and app.setStatus then
    app:setStatus(ok and "Linked pattern table" or "Pattern table link failed")
  end
  return ok == true
end

function M.applyLink(app, winA, slotA, winB, slotB)
  local ok = M.canLinkWindows(winA, slotA, winB, slotB)
  if not ok then
    return false
  end
  local paletteWin, destWin = resolvePalettePair(winA, slotA, winB, slotB)
  if paletteWin then
    return applyPaletteLink(app, paletteWin, destWin)
  end
  local ptWin, consumer, destSlot = resolvePatternPair(winA, slotA, winB, slotB)
  if ptWin then
    return applyPatternLink(app, ptWin, consumer, destSlot)
  end
  return false
end

local function getLayouts(app)
  local state = WindowLinkVisualController.prepareLinkDrawState(app)
  return state and state.layouts or nil
end

local function getBadgeCenter(layouts, win, slot)
  local entry = layouts and win and layouts[win] and layouts[win][slot]
  if not entry then
    return nil, nil
  end
  if entry.lineCx and entry.lineCy then
    return entry.lineCx, entry.lineCy
  end
  return entry.cx, entry.cy
end

local function destinationSlotsForWindow(win)
  if WindowCaps.isPpuFrame(win) or WindowCaps.isSketchCanvas(win) then
    return { "ppu_pattern_bg", "ppu_pattern_sprite", "ppu_palette" }
  end
  if WindowCaps.isOamAnimation(win) then
    return { "oam_pattern", "layout_palette" }
  end
  if WindowCaps.isRomPaletteWindow(win) then
    return { PALETTE_SOURCE }
  end
  if WindowCaps.isPatternTable(win) then
    return { PATTERN_SOURCE }
  end
  if WindowCaps.isStaticArt(win) or WindowCaps.isAnimationLike(win) then
    return { "layout_palette" }
  end
  return {}
end

--- Resolve drop under (x,y): prefer compatible badge; else unambiguous body slot.
function M.resolveDropTarget(app, sourceWin, sourceSlot, x, y)
  if not (app and sourceWin and sourceSlot) then
    return nil, nil
  end
  local layouts = getLayouts(app)
  local hoverWin, hoverSlot = WindowLinkVisibility.resolveTopLinkHandleAt(app, x, y, layouts)
  if hoverWin and hoverSlot and hoverWin ~= sourceWin then
    if M.canLinkWindows(sourceWin, sourceSlot, hoverWin, hoverSlot) then
      return hoverWin, hoverSlot
    end
    -- Illegal badge under pointer: report for unavailable cursor, but not as apply target.
    return hoverWin, hoverSlot, false
  end

  local wm = app.wm
  if not (wm and wm.getWindows) then
    return nil, nil
  end
  local windows = wm:getWindows()
  for i = #windows, 1, -1 do
    local win = windows[i]
    if win
      and win ~= sourceWin
      and not win._closed
      and not win._minimized
      and MouseWindowChrome.isPointOnWindowInteractiveSurface(win, x, y)
    then
      local candidates = {}
      for _, slot in ipairs(destinationSlotsForWindow(win)) do
        if M.canLinkWindows(sourceWin, sourceSlot, win, slot) then
          candidates[#candidates + 1] = slot
        end
      end
      if #candidates == 1 then
        return win, candidates[1], true
      end
      -- Multiple or zero compatible slots: illegal hover for cursor when over body.
      return win, nil, false
    end
  end
  return nil, nil
end

function M.openContextMenuForBadge(app, win, slot, x, y, beginContextMenuClick)
  if not (app and win and slot) then
    return false
  end
  local wm = app.wm
  if wm and wm.setFocus then
    wm:setFocus(win)
  end

  if slot == PALETTE_SOURCE then
    if beginContextMenuClick then
      beginContextMenuClick("palette_link_source", x, y, 2, win, { slot = slot })
      return true
    end
    if app.showPaletteLinkSourceContextMenu then
      return app:showPaletteLinkSourceContextMenu(win, x, y) == true
    end
  end

  if PALETTE_DEST[slot] then
    local layerIndex = getActiveLayerIndex(win)
    if beginContextMenuClick then
      beginContextMenuClick("palette_link_destination", x, y, 2, win, {
        layerIndex = layerIndex,
        slot = slot,
      })
      return true
    end
    if app.showPaletteLinkDestinationContextMenu then
      return app:showPaletteLinkDestinationContextMenu(win, x, y, { layerIndex = layerIndex }) == true
    end
  end

  if slot == PATTERN_SOURCE then
    if beginContextMenuClick then
      beginContextMenuClick("pattern_table_link_source", x, y, 2, win, { slot = slot })
      return true
    end
    if app.showPatternTableLinkSourceContextMenu then
      return app:showPatternTableLinkSourceContextMenu(win, x, y) == true
    end
  end

  if PATTERN_DEST[slot] then
    if beginContextMenuClick then
      beginContextMenuClick("pattern_table_link_destination", x, y, 2, win, { slot = slot })
      return true
    end
    if app.showPatternTableLinkDestinationContextMenu then
      return app:showPatternTableLinkDestinationContextMenu(win, x, y) == true
    end
  end

  return false
end

function M.beginPress(app, x, y, button, beginContextMenuClick)
  if not app then
    return false
  end
  local win, slot = WindowLinkVisibility.resolveTopLinkHandleAt(app, x, y)
  if not win then
    return false
  end

  if button == 2 or button == 3 then
    return M.openContextMenuForBadge(app, win, slot, x, y, beginContextMenuClick)
  end

  if button ~= 1 then
    return false
  end

  local layouts = getLayouts(app)
  local cx, cy = getBadgeCenter(layouts, win, slot)
  local drag = getDrag(app)
  drag.active = false
  drag.pending = true
  drag.sourceWin = win
  drag.sourceSlot = slot
  drag.sourceCx = cx or x
  drag.sourceCy = cy or y
  drag.startX = x
  drag.startY = y
  drag.currentX = x
  drag.currentY = y
  drag.legalHover = false
  drag.hoverWin = nil
  drag.hoverSlot = nil

  local wm = app.wm
  if wm and wm.setFocus then
    wm:setFocus(win)
  end
  return true
end

function M.updateHover(app, x, y)
  local drag = getDrag(app)
  if not drag then
    return false
  end

  if drag.pending and not drag.active then
    local dx = (tonumber(x) or 0) - (drag.startX or 0)
    local dy = (tonumber(y) or 0) - (drag.startY or 0)
    if (dx * dx + dy * dy) >= (DRAG_THRESHOLD_PX * DRAG_THRESHOLD_PX) then
      drag.active = true
      drag.pending = false
    end
  end

  if not drag.active then
    return drag.pending == true
  end

  drag.currentX = x
  drag.currentY = y
  local hoverWin, hoverSlot, legal = M.resolveDropTarget(app, drag.sourceWin, drag.sourceSlot, x, y)
  if legal == nil and hoverWin and hoverSlot then
    legal = M.canLinkWindows(drag.sourceWin, drag.sourceSlot, hoverWin, hoverSlot) == true
  end
  drag.hoverWin = hoverWin
  drag.hoverSlot = hoverSlot
  drag.legalHover = legal == true

  if drag.legalHover and hoverWin and app.wm and app.wm.setFocus then
    app.wm:setFocus(hoverWin)
  end
  return true
end

function M.finish(app, x, y)
  local drag = getDrag(app)
  if not drag or (not drag.active and not drag.pending) then
    return false
  end

  local sourceWin = drag.sourceWin
  local sourceSlot = drag.sourceSlot
  local wasActive = drag.active == true
  local pendingOnly = drag.pending == true and not wasActive

  if wasActive then
    local targetWin, targetSlot, legal = M.resolveDropTarget(app, sourceWin, sourceSlot, x, y)
    if legal == nil and targetWin and targetSlot then
      legal = M.canLinkWindows(sourceWin, sourceSlot, targetWin, targetSlot) == true
    end
    M.clearDrag(app)
    if legal and targetWin and targetSlot then
      M.applyLink(app, sourceWin, sourceSlot, targetWin, targetSlot)
    elseif app and app.setStatus then
      app:setStatus("Window link canceled")
    end
    return true
  end

  M.clearDrag(app)
  if pendingOnly and sourceWin and sourceSlot then
    WindowLinkVisualController.focusWindowsLinkedToHandle(app, sourceWin, sourceSlot)
  end
  return true
end

--- Cursor name while badge-dragging, or nil to use default resolution.
function M.cursorNameForPointer(app, x, y)
  local drag = getDrag(app)
  if not (drag and drag.active) then
    return nil
  end
  M.updateHover(app, x, y)
  if drag.hoverWin and not drag.legalHover then
    return "unavailable"
  end
  if drag.legalHover then
    return "hand"
  end
  return "arrow"
end

function M.drawActiveDrag(app)
  local drag = getDrag(app)
  if not (drag and drag.active and drag.sourceWin) then
    return
  end
  local ax = drag.sourceCx
  local ay = drag.sourceCy
  local bx = drag.currentX
  local by = drag.currentY
  if type(ax) ~= "number" or type(ay) ~= "number" or type(bx) ~= "number" or type(by) ~= "number" then
    return
  end
  local colors = require("app_colors")
  local lineColor = drag.legalHover and colors.green or colors.red
  love.graphics.push("all")
  love.graphics.setScissor()
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)
  love.graphics.setColor(lineColor)
  love.graphics.line(
    math.floor(ax + 0.5),
    math.floor(ay + 0.5),
    math.floor(bx + 0.5),
    math.floor(by + 0.5)
  )
  love.graphics.pop()
end

return M
