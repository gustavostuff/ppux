-- window_controller.lua - z-order, focus, hit-test, borders
local DebugController    = require("controllers.dev.debug_controller")
local StaticArtWindow    = require("user_interface.windows_system.static_art_window")
local PixelSketchCanvasWindow = require("user_interface.windows_system.pixel_sketch_canvas_window")
local PatternTableWindow = require("user_interface.windows_system.pattern_table_window")
local PPUFrameWindow   = require("user_interface.windows_system.ppu_frame_window")
local AnimationWindow    = require("user_interface.windows_system.animation_window")
local OAMAnimationWindow = require("user_interface.windows_system.oam_animation_window")
local PaletteWindow      = require("user_interface.windows_system.palette_window")
local RomPaletteWindow   = require("user_interface.windows_system.rom_palette_window")
local CrtLensWindow      = require("user_interface.windows_system.crt_lens_window")
local SpriteController   = require("controllers.sprite.sprite_controller")
local ToolbarController  = require("controllers.window.toolbar_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local UiScale = require("user_interface.ui_scale")
local MouseWindowChrome = require("controllers.input.mouse_window_chrome_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local PaletteLinkRenderController = require("controllers.palette.palette_link_render_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")

local WM = {}
WM.__index = WM

----------------------------------------------------------------
-- Constructor / basic management
----------------------------------------------------------------
function WM.new()
  local instance = setmetatable({
    windows = {},
    focused = nil,
  }, WM)

  DebugController.log("info", "WM", "WindowController created")
  return instance
end

local function refreshZOrder(self)
  for i, w in ipairs(self.windows) do
    w._z = i
  end
end

--- Non-_closed windows with _alwaysOnTop are stacked above others; _closed entries stay at the end.
local function normalizeAlwaysOnTopOrdering(self)
  local normal, atop, closed = {}, {}, {}
  for _, w in ipairs(self.windows) do
    if w._closed then
      closed[#closed + 1] = w
    elseif w._alwaysOnTop then
      atop[#atop + 1] = w
    else
      normal[#normal + 1] = w
    end
  end
  local i = 1
  for _, w in ipairs(normal) do
    self.windows[i] = w
    i = i + 1
  end
  for _, w in ipairs(atop) do
    self.windows[i] = w
    i = i + 1
  end
  for _, w in ipairs(closed) do
    self.windows[i] = w
    i = i + 1
  end
  refreshZOrder(self)
end

local function isWindowVisibleForInteraction(win)
  return win and not win._closed and not win._minimized and win._groupHidden ~= true
end

local function findTopVisibleWindow(self)
  for i = #self.windows, 1, -1 do
    local w = self.windows[i]
    if isWindowVisibleForInteraction(w) then
      return w
    end
  end
  return nil
end

function WM:add(win)
  if win then
    win._wm = self
  end
  if win._alwaysOnTop then
    table.insert(self.windows, win)
  else
    local insertAt = #self.windows + 1
    for idx, w in ipairs(self.windows) do
      if w._alwaysOnTop then
        insertAt = idx
        break
      end
    end
    table.insert(self.windows, insertAt, win)
  end
  DebugController.log(
    "info", "WM",
    "Window added: %s (kind: %s, total windows: %d)",
    win.title or "untitled",
    win.kind or "normal",
    #self.windows
  )
  refreshZOrder(self)
  if win.kind ~= "crt_lens" then
    if self.taskbar and self.taskbar.addWindowButton then
      self.taskbar:addWindowButton(win)
    elseif self.taskbar and self.taskbar.addMinimizedWindow then
      self.taskbar:addMinimizedWindow(win)
    end
  end

  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app or nil
  if app and app.onWindowManagerWindowCreated then
    app:onWindowManagerWindowCreated(win)
  end
end

function WM:update(dt)
  -- Skip closed windows
  for _, w in ipairs(self.windows) do
    if not w._closed and not w._minimized and w._groupHidden ~= true then
      w:update(dt)
    end
  end
end

function WM:getWindows()
  return self.windows
end

function WM:findWindowById(id)
  for _, w in ipairs(self.windows) do
    if w._id == id then return w end
  end
  return nil
end

function WM:getWindowsOfKind(kind)
  local out = {}
  for _, w in ipairs(self.windows) do
    if w.kind == kind then
      table.insert(out, w)
    end
  end
  return out
end

-- Calculate visual area using cols/rows, cell size and zoom (for sorting).
local function windowArea(win)
  if not win then return 0 end
  local cols = win.cols or 0
  local rows = win.rows or 0
  local vCols = win.visibleCols or cols
  local vRows = win.visibleRows or rows
  if cols > 0 then vCols = math.min(vCols, cols) end
  if rows > 0 then vRows = math.min(vRows, rows) end
  local cw   = win.cellW or 0
  local ch   = win.cellH or 0
  local z    = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  return vCols * vRows * cw * ch * z * z
end

local function isPaletteWindow(win)
  return WindowCaps.isAnyPaletteWindow(win)
end

local function getUndoRedoFromCtx()
  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app or nil
  return app and app.undoRedo or nil
end

local function recordWindowMinimizeUndo(self, win, beforeMinimized, afterMinimized, beforeFocusedWin, afterFocusedWin)
  if not win or beforeMinimized == afterMinimized then
    return
  end
  local undoRedo = getUndoRedoFromCtx()
  if not (undoRedo and undoRedo.addWindowMinimizeEvent) then
    return
  end
  undoRedo:addWindowMinimizeEvent({
    type = "window_minimize",
    win = win,
    wm = self,
    beforeMinimized = (beforeMinimized == true),
    afterMinimized = (afterMinimized == true),
    beforeFocusedWin = beforeFocusedWin,
    afterFocusedWin = afterFocusedWin,
  })
end

--- One undo entry for "minimize all but this" instead of N separate minimize events.
local function recordMinimizeAllExceptUndo(self, keepWin, minimizedWins, beforeFocusedWin)
  if not keepWin or type(minimizedWins) ~= "table" or #minimizedWins == 0 then
    return
  end
  local undoRedo = getUndoRedoFromCtx()
  if not (undoRedo and undoRedo.addWindowMinimizeBatchEvent) then
    return
  end
  undoRedo:addWindowMinimizeBatchEvent({
    type = "window_minimize_batch",
    wm = self,
    keepWin = keepWin,
    targets = minimizedWins,
    beforeFocusedWin = beforeFocusedWin,
  })
end

local function shallowCopyWindowsArray(windows)
  if type(windows) ~= "table" then
    return {}
  end
  local out = {}
  for i = 1, #windows do
    out[i] = windows[i]
  end
  return out
end

local function syncCollapseIcon(win)
  if not (win and win.headerToolbar) then return end
  if win.headerToolbar.updateCollapseIcon then
    win.headerToolbar:updateCollapseIcon()
  elseif win.headerToolbar.updateIcons then
    win.headerToolbar:updateIcons()
  end
end

local function snapshotWindowChromeLayout(w)
  if not w then
    return nil
  end
  local zoom = w.zoom
  if type(w.getZoomLevel) == "function" then
    zoom = w:getZoomLevel()
  end
  return {
    x = w.x,
    y = w.y,
    collapsed = w._collapsed == true,
    scrollCol = tonumber(w.scrollCol) or 0,
    scrollRow = tonumber(w.scrollRow) or 0,
    zoom = tonumber(zoom) or 1,
    visibleCols = w.visibleCols,
    visibleRows = w.visibleRows,
  }
end

local function applyWindowChromeLayout(w, s)
  if not (w and s) then
    return
  end
  w._collapsed = s.collapsed
  w.scrollCol = s.scrollCol
  w.scrollRow = s.scrollRow
  if s.visibleCols ~= nil then
    w.visibleCols = s.visibleCols
  end
  if s.visibleRows ~= nil then
    w.visibleRows = s.visibleRows
  end
  -- Restore zoom by assignment only: `setZoomLevel` repositions x,y around a pivot and would
  -- desync from the stored collapse-all snapshot (breaks undo/redo layout restore).
  local prevZoom = w.zoom
  w.zoom = tonumber(s.zoom) or 1
  if prevZoom ~= w.zoom and w.invalidateAllTileLayerCanvases then
    w:invalidateAllTileLayerCanvases()
  end
  w.x = s.x
  w.y = s.y
  if type(w.setScroll) == "function" then
    w:setScroll(s.scrollCol, s.scrollRow)
  end
  syncCollapseIcon(w)
end

local function recordMinimizeAllUndo(self, minimizedWins, beforeFocusedWin)
  if type(minimizedWins) ~= "table" or #minimizedWins == 0 then
    return
  end
  local undoRedo = getUndoRedoFromCtx()
  if not (undoRedo and undoRedo.addWindowMinimizeAllEvent) then
    return
  end
  undoRedo:addWindowMinimizeAllEvent({
    type = "window_minimize_all",
    wm = self,
    targets = minimizedWins,
    beforeFocusedWin = beforeFocusedWin,
  })
end

local function recordRestoreMinimizedAllUndo(self, restoredWins, beforeFocusedWin, afterFocusedWin)
  if type(restoredWins) ~= "table" or #restoredWins == 0 then
    return
  end
  local undoRedo = getUndoRedoFromCtx()
  if not (undoRedo and undoRedo.addWindowRestoreMinimizedAllEvent) then
    return
  end
  undoRedo:addWindowRestoreMinimizedAllEvent({
    type = "window_restore_minimized_all",
    wm = self,
    targets = restoredWins,
    beforeFocusedWin = beforeFocusedWin,
    afterFocusedWin = afterFocusedWin,
  })
end

local function recordCollapseAllUndo(self, evt)
  local undoRedo = getUndoRedoFromCtx()
  if not (undoRedo and undoRedo.addWindowCollapseAllEvent) then
    return
  end
  undoRedo:addWindowCollapseAllEvent(evt)
end

local function recordExpandAllUndo(self, targets)
  if type(targets) ~= "table" or #targets == 0 then
    return
  end
  local undoRedo = getUndoRedoFromCtx()
  if not (undoRedo and undoRedo.addWindowExpandAllEvent) then
    return
  end
  undoRedo:addWindowExpandAllEvent({
    type = "window_expand_all",
    wm = self,
    targets = targets,
  })
end

local function zoomOutWindowToMinimum(win)
  if not win or win._closed then return end
  if type(win.addZoomLevel) ~= "function" then return end

  -- Simulate repeated user zoom-out until the window refuses to shrink more.
  for _ = 1, 16 do
    local before = (type(win.getZoomLevel) == "function" and win:getZoomLevel()) or win.zoom
    win:addZoomLevel(-1)
    local after = (type(win.getZoomLevel) == "function" and win:getZoomLevel()) or win.zoom
    if after == before then
      break
    end
  end
end

--- Shrink zoom / viewport until window content fits maxWidth x maxHeight (pixels).
--- When resetViewport is true (first layout pass), viewport is reset to minimum allowed size before fitting.
local function mosaicFitWindowToCell(win, maxContentW, maxContentH, resetViewport)
  if not win or win._closed then
    return
  end
  maxContentW = math.max(1, maxContentW)
  maxContentH = math.max(1, maxContentH)

  if win.setScroll then
    win:setScroll(0, 0)
  else
    win.scrollCol = 0
    win.scrollRow = 0
  end

  if resetViewport and win.resizeToMinimum then
    win:resizeToMinimum()
  end

  if type(win.addZoomLevel) ~= "function" or type(win.getZoomLevel) ~= "function" then
    return
  end

  local function contentFits()
    local _, _, cw, ch = win:getScreenRect()
    return cw <= maxContentW and ch <= maxContentH
  end

  for _ = 1, 24 do
    if contentFits() then
      break
    end
    local z0 = win:getZoomLevel()
    win:addZoomLevel(-1)
    if win:getZoomLevel() == z0 then
      break
    end
  end

  for _ = 1, 512 do
    if contentFits() then
      break
    end
    local vc = win.visibleCols or 1
    local vr = win.visibleRows or 1
    if vc <= 1 and vr <= 1 then
      break
    end
    local _, _, cw, ch = win:getScreenRect()
    if cw > maxContentW and vc > 1 then
      win.visibleCols = vc - 1
    elseif ch > maxContentH and vr > 1 then
      win.visibleRows = vr - 1
    elseif vc > 1 then
      win.visibleCols = vc - 1
    elseif vr > 1 then
      win.visibleRows = vr - 1
    else
      break
    end
    if win.setScroll then
      win:setScroll(0, 0)
    end
  end

  for _ = 1, 16 do
    local z0 = win:getZoomLevel()
    win:addZoomLevel(1)
    if win:getZoomLevel() == z0 then
      break
    end
    local _, _, cw, ch = win:getScreenRect()
    if cw > maxContentW or ch > maxContentH then
      win:setZoomLevel(z0)
      break
    end
  end
end

local function rebuildWindowStackWithSortedOpen(self, cmp)
  local open = {}
  local closed = {}
  local originalIndex = {}
  for i, w in ipairs(self.windows) do
    originalIndex[w] = i
    if w._closed then
      closed[#closed + 1] = w
    else
      open[#open + 1] = w
    end
  end

  if #open == 0 then
    return false
  end

  table.sort(open, function(a, b)
    local res = cmp(a, b)
    if res == nil then
      return (originalIndex[a] or 0) < (originalIndex[b] or 0)
    end
    return res
  end)

  self.windows = {}
  for _, w in ipairs(open) do
    self.windows[#self.windows + 1] = w
  end
  for _, w in ipairs(closed) do
    self.windows[#self.windows + 1] = w
  end
  normalizeAlwaysOnTopOrdering(self)

  if self.focused and (self.focused._closed or self.focused._minimized) then
    self.focused = findTopVisibleWindow(self)
  end

  return true
end

local function pickGridColumns(count, maxW, maxTotalH, areaW, areaH, gapX, gapY)
  local bestCols = 1
  local bestScore = math.huge

  for cols = 1, count do
    local rows = math.ceil(count / cols)
    local reqW = cols * maxW + math.max(0, cols - 1) * gapX
    local reqH = rows * maxTotalH + math.max(0, rows - 1) * gapY
    local overflowW = math.max(0, reqW - areaW)
    local overflowH = math.max(0, reqH - areaH)
    local overflowScore = (overflowW * overflowW) + (overflowH * overflowH)
    local emptySlots = (cols * rows) - count
    local balance = math.abs(cols - rows)

    local score = overflowScore * 1000000 + emptySlots * 100 + balance
    if score < bestScore then
      bestScore = score
      bestCols = cols
    end
  end

  return bestCols
end

-- Arrange open windows in a cascaded stack, sorted from larger to smaller area.
function WM:cascade(opts)
  opts = opts or {}
  local startX  = opts.startX or 30
  local startY  = opts.startY or 30 + UiScale.windowHeaderHeight()
  local offsetX = opts.offsetX or 15
  local offsetY = opts.offsetY or 15
  local cascadeShiftX = opts.cascadeShiftX or 80
  local maxItemsPerCascade = opts.maxItemsPerCascade or 14
  local excludePalettes = opts.excludePalettes == true

  local open = {}
  local closed = {}
  for _, w in ipairs(self.windows) do
    if w._closed or w._minimized then
      table.insert(closed, w)
    elseif excludePalettes and isPaletteWindow(w) then
      -- Keep palette windows unchanged when arranging from app toolbar.
    else
      table.insert(open, w)
    end
  end

  table.sort(open, function(a, b)
    return windowArea(a) > windowArea(b)
  end)

  local runStartX = startX
  local runStep = 0
  for _, w in ipairs(open) do
    w._collapsed = false
    syncCollapseIcon(w)

    if runStep >= maxItemsPerCascade then
      runStartX = runStartX + cascadeShiftX
      runStep = 0
    end

    w.x = runStartX + runStep * offsetX
    w.y = startY + runStep * offsetY
    runStep = runStep + 1
  end

  if excludePalettes then
    if #open > 0 then
      self.focused = open[#open]
      self:bringToFront(self.focused)
    end
    return
  end

  -- Rebuild window stack: keep open windows (largest -> smallest) first, then closed ones.
  self.windows = {}
  for _, w in ipairs(open) do
    table.insert(self.windows, w)
  end
  for _, w in ipairs(closed) do
    table.insert(self.windows, w)
  end

  normalizeAlwaysOnTopOrdering(self)

  -- Focus the front-most open window (last in the open stack) without changing order.
  if #open > 0 then
    self.focused = open[#open]
  else
    self.focused = nil
  end
end

-- Arrange open windows into a compact grid and normalize them for overview.
function WM:grid(opts)
  opts = opts or {}

  local areaX = opts.areaX or 8
  local areaY = opts.areaY or 30
  local areaW = opts.areaW or 624
  local areaH = opts.areaH or 300
  local gapX = opts.gapX or 8
  local gapY = opts.gapY or 8
  local excludePalettes = opts.excludePalettes == true
  local paletteStackRight = opts.paletteStackRight == true
  local paletteStackGap = opts.paletteStackGap or gapY
  local paletteRightPadding = opts.paletteRightPadding or 8
  local paletteStackY = opts.paletteStackY or areaY

  local open = {}
  local palettes = {}
  for _, w in ipairs(self.windows) do
    if not w._closed and not w._minimized then
      if isPaletteWindow(w) then
        if paletteStackRight then
          table.insert(palettes, w)
        elseif not excludePalettes then
          table.insert(open, w)
        end
      else
        table.insert(open, w)
      end
    end
  end
  if #open == 0 and #palettes == 0 then
    self.focused = nil
    return
  end

  -- Normalize each window before placement:
  -- zoom = 1, minimum viewport size, scroll origin.
  for _, w in ipairs(open) do
    if w.setZoomLevel then
      w:setZoomLevel(1)
    end
    w.zoom = 1

    if w.resizeToMinimum then
      w:resizeToMinimum()
    end

    if w.setScroll then
      w:setScroll(0, 0)
    else
      w.scrollCol = 0
      w.scrollRow = 0
    end
  end

  local effectiveAreaW = areaW
  local maxPaletteW = 0
  if paletteStackRight and #palettes > 0 then
    for _, p in ipairs(palettes) do
      local _, _, pw = p:getScreenRect()
      maxPaletteW = math.max(maxPaletteW, pw)
    end
    local reservedW = maxPaletteW + gapX + paletteRightPadding
    effectiveAreaW = math.max(1, areaW - reservedW)
  end

  local maxW = 1
  local maxTotalH = 1
  for _, w in ipairs(open) do
    local _, _, ww, wh = w:getScreenRect()
    local headerH = w.headerH or 0
    maxW = math.max(maxW, ww)
    maxTotalH = math.max(maxTotalH, wh + headerH)
  end

  if #open > 0 then
    local cols = pickGridColumns(#open, maxW, maxTotalH, effectiveAreaW, areaH, gapX, gapY)
    for i, w in ipairs(open) do
      local col = (i - 1) % cols
      local row = math.floor((i - 1) / cols)
      local rowTop = areaY + row * (maxTotalH + gapY)

      w.x = areaX + col * (maxW + gapX)
      w.y = rowTop + (w.headerH or 0)
    end
  end

  if paletteStackRight and #palettes > 0 then
    local stackRight = areaX + areaW - paletteRightPadding
    local stackY = paletteStackY

    for _, p in ipairs(palettes) do
      local _, _, pw = p:getScreenRect()
      p._collapsed = true
      p.x = stackRight - pw
      p.y = stackY + (p.headerH or 0)
      stackY = stackY + (p.headerH or UiScale.windowHeaderHeight()) + paletteStackGap
    end
  end

  if #open > 0 then
    self.focused = open[#open]
    self:bringToFront(self.focused)
  elseif #palettes > 0 then
    self.focused = palettes[#palettes]
    self:bringToFront(self.focused)
  else
    self.focused = nil
  end
end

-- Collapse all open windows and stack headers in columns from left to right.
function WM:collapseAll(opts)
  opts = opts or {}
  local recordUndo = (opts.recordUndo ~= false)

  local areaX = opts.areaX or 0
  local areaY = opts.areaY or 30
  local areaH = opts.areaH or 300
  local gapX = opts.gapX or 8
  local gapY = opts.gapY or 2

  local open = {}
  local originalIndex = {}
  for i, w in ipairs(self.windows) do
    originalIndex[w] = i
  end
  for _, w in ipairs(self.windows) do
    if not w._closed and not w._minimized then
      table.insert(open, w)
    end
  end
  if #open == 0 then
    self.focused = nil
    return
  end

  local beforeFocused, beforeOrder, beforeLayout
  if recordUndo then
    beforeFocused = self.focused
    beforeOrder = shallowCopyWindowsArray(self.windows)
    beforeLayout = {}
    for _, w in ipairs(open) do
      beforeLayout[w] = snapshotWindowChromeLayout(w)
    end
  end

  for _, w in ipairs(open) do
    zoomOutWindowToMinimum(w)
  end

  table.sort(open, function(a, b)
    local at = string.lower(tostring(a.title or ""))
    local bt = string.lower(tostring(b.title or ""))
    if at == bt then
      return (originalIndex[a] or 0) < (originalIndex[b] or 0)
    end
    return at < bt
  end)

  local colX = areaX
  local colY = areaY
  local maxY = areaY + areaH
  local firstColumnStepW = nil

  for _, w in ipairs(open) do
    if w.setScroll then
      w:setScroll(0, 0)
    else
      w.scrollCol = 0
      w.scrollRow = 0
    end

    w._collapsed = true
    syncCollapseIcon(w)

    local _, _, ww = w:getScreenRect()
    if not firstColumnStepW then
      firstColumnStepW = ww
    end
    local headerH = w.headerH or UiScale.windowHeaderHeight()
    local itemH = headerH

    if colY > areaY and (colY + itemH) > maxY then
      colX = colX + (firstColumnStepW or ww) + gapX
      colY = areaY
    end

    w.x = colX
    w.y = colY + headerH

    colY = colY + itemH + gapY
  end

  self.focused = open[#open]
  if self.focused then
    self:bringToFront(self.focused)
  end

  if recordUndo then
    local afterLayout = {}
    for _, w in ipairs(open) do
      afterLayout[w] = snapshotWindowChromeLayout(w)
    end
    recordCollapseAllUndo(self, {
      type = "window_collapse_all",
      wm = self,
      beforeOrder = beforeOrder,
      afterOrder = shallowCopyWindowsArray(self.windows),
      beforeFocusedWin = beforeFocused,
      afterFocusedWin = self.focused,
      beforeLayout = beforeLayout,
      afterLayout = afterLayout,
    })
  end
end

-- Non-palette windows: horizontal flow (left-to-right, wrap at mosaic band width), new "layer" with
-- (batchDispX,batchDispY) when the band is exhausted vertically. Palettes stay collapsed on the right.
function WM:mosaicAll(opts)
  opts = opts or {}

  local areaX = opts.areaX or 30
  local areaY = opts.areaY or 30
  local areaW = opts.areaW or 800
  local areaH = opts.areaH or 400
  local gapX = opts.gapX or 4
  local gapY = opts.gapY or 4
  local batchDispX = opts.batchDispX or 20
  local batchDispY = opts.batchDispY or 20
  local paletteRightPadding = opts.paletteRightPadding or 8
  local paletteStackGap = opts.paletteStackGap or gapY

  local mosaicWins = {}
  local palettes = {}
  local originalIndex = {}
  for i, w in ipairs(self.windows) do
    originalIndex[w] = i
  end

  for _, w in ipairs(self.windows) do
    if w._closed or w._minimized then
    elseif w.kind == "crt_lens" then
    elseif isPaletteWindow(w) then
      table.insert(palettes, w)
    else
      table.insert(mosaicWins, w)
    end
  end

  if #mosaicWins == 0 and #palettes == 0 then
    return
  end

  local effectiveAreaW = areaW
  if #palettes > 0 then
    for _, p in ipairs(palettes) do
      zoomOutWindowToMinimum(p)
      if p.setScroll then
        p:setScroll(0, 0)
      else
        p.scrollCol = 0
        p.scrollRow = 0
      end
      p._collapsed = true
      syncCollapseIcon(p)
    end

    local maxPaletteW = 0
    for _, p in ipairs(palettes) do
      local _, _, pw = p:getScreenRect()
      maxPaletteW = math.max(maxPaletteW, pw)
    end

    local reserved = maxPaletteW + gapX + paletteRightPadding
    effectiveAreaW = math.max(1, areaW - reserved)

    table.sort(palettes, function(a, b)
      local at = string.lower(tostring(a.title or ""))
      local bt = string.lower(tostring(b.title or ""))
      if at == bt then
        return (originalIndex[a] or 0) < (originalIndex[b] or 0)
      end
      return at < bt
    end)
  end

  local open = mosaicWins

  if #open > 0 then
    for _, w in ipairs(open) do
      w._collapsed = false
      syncCollapseIcon(w)
      if w.setScroll then
        w:setScroll(0, 0)
      else
        w.scrollCol = 0
        w.scrollRow = 0
      end
      if w.setZoomLevel then
        w:setZoomLevel(1)
      end
      w.zoom = 1
      if w.resizeToMinimum then
        w:resizeToMinimum()
      end
    end

    table.sort(open, function(a, b)
      local at = string.lower(tostring(a.title or ""))
      local bt = string.lower(tostring(b.title or ""))
      if at == bt then
        return (originalIndex[a] or 0) < (originalIndex[b] or 0)
      end
      return at < bt
    end)

    local layer = 0
    local curX = areaX
    local curY = areaY
    local rowMaxH = 0

    for _, w in ipairs(open) do
      local placed = false
      local resetVp = true
      local safety = 0
      while not placed and safety < 64 do
        safety = safety + 1
        local lox = areaX + layer * batchDispX
        local loy = areaY + layer * batchDispY
        local lBottom = loy + areaH

        local headerH = w.headerH or UiScale.windowHeaderHeight()
        local maxCH = math.max(1, lBottom - curY - headerH)

        mosaicFitWindowToCell(w, effectiveAreaW, maxCH, resetVp)
        resetVp = false

        local _, _, ww, wh = w:getScreenRect()
        local totalH = wh + headerH

        -- Need a new row: not at row start and this rect would cross the right edge of the mosaic band.
        if curX > lox and curX + ww > lox + effectiveAreaW then
          curY = curY + rowMaxH + gapY
          curX = lox
          rowMaxH = 0
          resetVp = true
        elseif curY + totalH > lBottom then
          if curX == lox and curY == loy then
            -- Taller than the work strip; still place so we do not loop forever.
            w.x = curX
            w.y = curY + headerH
            curX = curX + ww + gapX
            rowMaxH = math.max(rowMaxH, totalH)
            placed = true
          else
            layer = layer + 1
            curX = areaX + layer * batchDispX
            curY = areaY + layer * batchDispY
            rowMaxH = 0
            resetVp = true
          end
        else
          w.x = curX
          w.y = curY + headerH
          curX = curX + ww + gapX
          rowMaxH = math.max(rowMaxH, totalH)
          placed = true
        end
      end
    end
  end

  if #palettes > 0 then
    local stackRight = areaX + areaW - paletteRightPadding
    local stackY = areaY
    for _, p in ipairs(palettes) do
      local _, _, pw = p:getScreenRect()
      local headerH = p.headerH or UiScale.windowHeaderHeight()
      p.x = stackRight - pw
      p.y = stackY + headerH
      stackY = stackY + headerH + paletteStackGap
    end
  end

  if #mosaicWins > 0 then
    self.focused = mosaicWins[#mosaicWins]
    self:bringToFront(self.focused)
  elseif #palettes > 0 then
    self.focused = palettes[#palettes]
    self:bringToFront(self.focused)
  else
    self.focused = nil
  end
end

function WM:expandAll(opts)
  opts = opts or {}
  local recordUndo = (opts.recordUndo ~= false)

  local targets = {}
  for _, w in ipairs(self.windows) do
    if not w._closed and not w._minimized and w._collapsed then
      targets[#targets + 1] = w
    end
  end
  if #targets == 0 then
    return false
  end

  local any = false
  for _, w in ipairs(self.windows) do
    if not w._closed and not w._minimized and w._collapsed then
      w._collapsed = false
      syncCollapseIcon(w)
      any = true
    end
  end
  if recordUndo and any then
    recordExpandAllUndo(self, targets)
  end
  return any
end

--- Restore compositing stack to a previous window sequence (used by undo/redo for collapse-all batches).
function WM:_restoreWindowsArrayOrder(order)
  if type(order) ~= "table" then
    return
  end
  self.windows = {}
  for i = 1, #order do
    self.windows[i] = order[i]
  end
  refreshZOrder(self)
end

function WM:_applyChromeLayoutSnapshot(win, snap)
  applyWindowChromeLayout(win, snap)
end

function WM:_setCollapsedWithToolbarIcon(win, collapsed)
  if not win then
    return
  end
  win._collapsed = (collapsed == true)
  syncCollapseIcon(win)
end

----------------------------------------------------------------
-- Focus / Z-order
----------------------------------------------------------------
function WM:bringToFront(win)
  if not win or win._closed then return end
  for i, w in ipairs(self.windows) do
    if w == win then
      table.remove(self.windows, i)
      break
    end
  end
  if win._alwaysOnTop then
    table.insert(self.windows, win)
  else
    local insertAt = #self.windows + 1
    for idx, w in ipairs(self.windows) do
      if w._alwaysOnTop then
        insertAt = idx
        break
      end
    end
    table.insert(self.windows, insertAt, win)
  end
  refreshZOrder(self)
end

local function setAppStatusForPaletteFocusWindow(app, win)
  if not app or type(app.setStatus) ~= "function" or not win then
    return
  end
  if not WindowCaps.isAnyPaletteWindow(win) then
    return
  end

  local title = win.title or "Palette"
  local rows = math.max(1, math.floor(tonumber(win.rows) or 1))
  local cols = math.max(1, math.floor(tonumber(win.cols) or 4))
  local total = rows * cols

  local segments = { title }

  if WindowCaps.isRomPaletteWindow(win) then
    segments[#segments + 1] = "ROM palette"
    segments[#segments + 1] = string.format("%d×%d (%d colors)", rows, cols, total)
  else
    segments[#segments + 1] = "Global palette"
    segments[#segments + 1] = string.format("%d×%d (%d colors)", rows, cols, total)
    if win.activePalette == true then
      segments[#segments + 1] = "Active"
    else
      segments[#segments + 1] = "Inactive"
    end
    if type(win.paletteName) == "string" and win.paletteName ~= "" then
      segments[#segments + 1] = "preset " .. win.paletteName
    end
  end

  if win.compactView == true then
    segments[#segments + 1] = "compact view"
  end

  app:setStatus(table.concat(segments, " - "))
end

local function setAppStatusForLayeredFocusWindow(app, win)
  if not app or type(app.setStatus) ~= "function" or not win then
    return
  end
  -- Layer list is noisy or meaningless for pattern tables, CHR/ROM banks, and palettes
  -- (palettes use setAppStatusForPaletteFocusWindow from setFocus).
  if WindowCaps.isPatternTable(win) or WindowCaps.isChrLike(win) or WindowCaps.isAnyPaletteWindow(win) then
    app:setStatus(win.title or win.kind or "Window")
    return
  end

  local layers = win.layers
  if type(layers) ~= "table" or #layers == 0 then
    return
  end

  local n = #layers
  local li = 1
  if type(win.getActiveLayerIndex) == "function" then
    li = math.floor(tonumber(win:getActiveLayerIndex()) or win.activeLayer or 1)
  else
    li = math.floor(tonumber(win.activeLayer) or 1)
  end
  if li < 1 then
    li = 1
  end
  if li > n then
    li = n
  end

  local layer = layers[li]
  local nameStr = (layer and type(layer.name) == "string" and layer.name ~= "") and layer.name or string.format("layer %d", li)
  local title = win.title or win.kind or "Window"
  app:setStatus(string.format("%s - layer %d/%d (%s)", title, li, n, nameStr))
end

function WM:setFocus(win)
  if win == nil then
    self.focused = nil
    DebugController.log("info", "WM", "Focus cleared")
    return
  end
  if win._closed or win._minimized then
    return
  end
  -- Grouped palette mode hides non-active source palettes; focusing one must activate that slot first.
  if win._groupHidden == true and WindowCaps.isAnyPaletteWindow(win) then
    local ctx = rawget(_G, "ctx")
    local app = ctx and ctx.app or nil
    if app and app.groupedPaletteWindows == true and app.focusPaletteWindowWithGrouping then
      app:focusPaletteWindowWithGrouping(win)
    end
    if win._groupHidden == true then
      return
    end
  elseif win._groupHidden == true then
    return
  end

  local changed = (self.focused ~= win)
  if changed then
    local ctx = rawget(_G, "ctx")
    local app = ctx and ctx.app or nil
    if app and app.onWorkspaceWindowFocused then
      app:onWorkspaceWindowFocused(win)
    end
  end
  self.focused = win
  local keepSet = self.collectLinkedMinimizeKeepSet and self:collectLinkedMinimizeKeepSet(win) or nil
  if keepSet then
    for partner in pairs(keepSet) do
      if partner ~= win and isWindowVisibleForInteraction(partner) then
        self:bringToFront(partner)
      end
    end
  end
  self:bringToFront(win)
  if changed then
    DebugController.log(
      "info", "WM",
      "Focus set to: %s (kind: %s)",
      win.title or "untitled",
      win.kind or "normal"
    )
  end

  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app or nil
  if app and self.focused == win then
    if WindowCaps.isAnyPaletteWindow(win) then
      setAppStatusForPaletteFocusWindow(app, win)
    else
      setAppStatusForLayeredFocusWindow(app, win)
    end
  end
end

function WM:getFocus()
  return self.focused
end

function WM:getTopInteractiveSurfaceWindowAt(x, y)
  return MouseWindowChrome.getTopInteractiveSurfaceWindowAt(x, y, self)
end

--- Clear keyboard/window focus when the click missed every window chrome/content surface (true empty workspace).
function WM:clearFocusOnWorkspaceMiss(x, y)
  if self:getTopInteractiveSurfaceWindowAt(x, y) == nil then
    self:setFocus(nil)
  end
end

function WM:windowAt(x, y)
  -- Iterate from front to back
  for i = #self.windows, 1, -1 do
    local win = self.windows[i]
    -- Skip closed windows
    if not win._closed and not win._minimized and win._groupHidden ~= true and win:contains(x, y) then
      return win
    end
  end
  return nil
end

function WM:focusedResizeHandleAt(x, y)
  local win = self.focused
  if not isWindowVisibleForInteraction(win) then
    return false
  end
  if type(win.mouseOnResizeHandle) ~= "function" then
    return false
  end
  return win:mouseOnResizeHandle(x, y) == true
end

function WM:closeWindow(win)
  if not win or win._closed then return false end

  win._closed = true
  win._minimized = false
  win.dragging = false
  win.resizing = false

  if self.focused == win then
    self.focused = findTopVisibleWindow(self)
  end

  if self.taskbar and self.taskbar.removeMinimizedWindow then
    self.taskbar:removeMinimizedWindow(win)
  end

  return true
end

function WM:reopenWindow(win, opts)
  opts = opts or {}
  if not win or not win._closed then return false end

  local restoreMinimized = (opts.minimized == true)
  local restoreFocus = (opts.focus == true)

  win._closed = false
  win._minimized = restoreMinimized

  if self.taskbar then
    if restoreMinimized and self.taskbar.addMinimizedWindow then
      self.taskbar:addMinimizedWindow(win)
    elseif self.taskbar.removeMinimizedWindow then
      self.taskbar:removeMinimizedWindow(win)
    elseif self.taskbar.addMinimizedWindow then
      self.taskbar:addMinimizedWindow(win)
    end
  end

  if restoreFocus and not restoreMinimized then
    self:setFocus(win)
  end

  return true
end

function WM:minimizeWindow(win, opts)
  opts = opts or {}
  if not isWindowVisibleForInteraction(win) then return false end
  local recordUndo = (opts.recordUndo ~= false)
  local beforeFocusedWin = self.focused
  local beforeMinimized = (win._minimized == true)

  win._minimized = true
  win.dragging = false
  win.resizing = false

  if self.focused == win then
    self.focused = findTopVisibleWindow(self)
  end

  if self.taskbar and self.taskbar.addMinimizedWindow then
    self.taskbar:addMinimizedWindow(win)
  end

  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app or nil
  if app then
    local WindowLinkVisibility = require("controllers.window.window_link_visibility")
    WindowLinkVisibility.refreshRevealForWindow(app, self, win)
    if self:getFocus() then
      WindowLinkVisibility.refreshRevealForWindow(app, self, self:getFocus())
    end
  end

  if recordUndo then
    recordWindowMinimizeUndo(self, win, beforeMinimized, true, beforeFocusedWin, self.focused)
  end

  return true
end

function WM:restoreMinimizedWindow(win, opts)
  opts = opts or {}
  if not win or win._closed or not win._minimized then return false end
  local recordUndo = (opts.recordUndo ~= false)
  local shouldFocus = (opts.focus ~= false)
  local beforeFocusedWin = self.focused
  local beforeMinimized = (win._minimized == true)

  win._minimized = false

  if self.taskbar and self.taskbar.removeMinimizedWindow then
    self.taskbar:removeMinimizedWindow(win)
  end

  if shouldFocus then
    self:setFocus(win)
  end

  if recordUndo then
    recordWindowMinimizeUndo(self, win, beforeMinimized, false, beforeFocusedWin, self.focused)
  end

  return true
end

function WM:minimizeAll(opts)
  opts = opts or {}
  local recordUndo = (opts.recordUndo ~= false)
  local beforeFocusedWin = self.focused
  local minimized = {}
  local any = false
  for _, win in ipairs(self.windows) do
    if self:minimizeWindow(win, { recordUndo = false }) then
      minimized[#minimized + 1] = win
      any = true
    end
  end
  if recordUndo and #minimized > 0 then
    recordMinimizeAllUndo(self, minimized, beforeFocusedWin)
  end
  return any
end

local function addWindowToMinimizeKeepSet(keepSet, win)
  if win and not win._closed then
    keepSet[win] = true
  end
end

--- ROM palettes and pattern tables linked to `anchorWin`, plus consumers when anchor is a link source.
function WM:collectLinkedMinimizeKeepSet(anchorWin)
  local keep = {}
  if not anchorWin then
    return keep
  end
  addWindowToMinimizeKeepSet(keep, anchorWin)

  for key, layer in pairs(anchorWin.layers or {}) do
    if type(key) == "number" and layer then
      addWindowToMinimizeKeepSet(keep, PaletteLinkRenderController.getPaletteWindowForLayer(layer, self))
      local ptId = layer.linkedPatternTableWindowId
      if type(ptId) == "string" and ptId ~= "" and self.findWindowById then
        addWindowToMinimizeKeepSet(keep, self:findWindowById(ptId))
      end
    end
  end

  if WindowCaps.isRomPaletteWindow(anchorWin) then
    for _, entry in ipairs(PaletteLinkController.getLinkedTargetsForPalette(self, anchorWin) or {}) do
      addWindowToMinimizeKeepSet(keep, entry.win)
    end
  end

  if WindowCaps.isPatternTable(anchorWin) then
    for _, entry in ipairs(PatternTableDisplayController.getLinkedConsumersForPatternTable(self, anchorWin) or {}) do
      addWindowToMinimizeKeepSet(keep, entry.win)
    end
  end

  return keep
end

local function minimizeAllExceptKeepSet(self, keepWin, keepSet)
  if not keepWin or keepWin._closed then
    return false
  end
  keepSet = keepSet or { [keepWin] = true }
  addWindowToMinimizeKeepSet(keepSet, keepWin)

  local beforeFocusedWin = self.focused
  local candidates = {}
  for _, w in ipairs(self.windows) do
    if not keepSet[w] and isWindowVisibleForInteraction(w) then
      candidates[#candidates + 1] = w
    end
  end
  if #candidates == 0 then
    return false
  end
  local minimized = {}
  for _, w in ipairs(candidates) do
    if self:minimizeWindow(w, { recordUndo = false }) then
      minimized[#minimized + 1] = w
    end
  end
  if #minimized == 0 then
    return false
  end
  if isWindowVisibleForInteraction(keepWin) then
    self:bringToFront(keepWin)
    if self.focused ~= keepWin then
      self:setFocus(keepWin)
    end
  end
  recordMinimizeAllExceptUndo(self, keepWin, minimized, beforeFocusedWin)
  return true
end

--- Minimize every window except `keepWin`. Brings `keepWin` forward when it stays visible.
function WM:minimizeAllExcept(keepWin)
  return minimizeAllExceptKeepSet(self, keepWin, { [keepWin] = true })
end

--- Minimize windows that are not `keepWin` and not linked to it (ROM palette / pattern table).
function WM:minimizeAllExceptLinked(keepWin)
  return minimizeAllExceptKeepSet(self, keepWin, self:collectLinkedMinimizeKeepSet(keepWin))
end

function WM:maximizeAll(opts)
  opts = opts or {}
  local recordUndo = (opts.recordUndo ~= false)
  local targets = {}
  for _, win in ipairs(self.windows) do
    if win and not win._closed and win._minimized then
      targets[#targets + 1] = win
    end
  end
  if #targets == 0 then
    return false
  end

  local beforeFocusedWin = self.focused
  local any = false
  for _, win in ipairs(targets) do
    if self:restoreMinimizedWindow(win, { recordUndo = false }) then
      any = true
    end
  end
  if recordUndo and any then
    recordRestoreMinimizedAllUndo(self, targets, beforeFocusedWin, self.focused)
  end
  return any
end

function WM:sortWindowsByTitle(descending)
  local descendingFlag = (descending == true)
  return rebuildWindowStackWithSortedOpen(self, function(a, b)
    local at = string.lower(tostring(a.title or ""))
    local bt = string.lower(tostring(b.title or ""))
    if at ~= bt then
      if descendingFlag then
        return at > bt
      end
      return at < bt
    end
    return nil
  end)
end

function WM:sortWindowsByKind(descending)
  local descendingFlag = (descending == true)
  return rebuildWindowStackWithSortedOpen(self, function(a, b)
    local ak = string.lower(tostring(a.kind or ""))
    local bk = string.lower(tostring(b.kind or ""))
    if ak ~= bk then
      if descendingFlag then
        return ak > bk
      end
      return ak < bk
    end
    local at = string.lower(tostring(a.title or ""))
    local bt = string.lower(tostring(b.title or ""))
    if at ~= bt then
      if descendingFlag then
        return at > bt
      end
      return at < bt
    end
    return nil
  end)
end

--- Rebuild compositing stack from an explicit id sequence (project load uses `layout.windows` order). Honors
--- `_alwaysOnTop` buckets like other WM reorder paths.
function WM:reorderWindowsByStableIds(ids)
  if type(ids) ~= "table" or #ids == 0 then
    return false
  end

  local rank = {}
  local r = 1
  for _, id in ipairs(ids) do
    if type(id) == "string" and id ~= "" and rank[id] == nil then
      rank[id] = r
      r = r + 1
    end
  end

  local normal, atop, closed = {}, {}, {}
  local origPos = {}
  for i, w in ipairs(self.windows) do
    origPos[w] = i
    if w._closed then
      closed[#closed + 1] = w
    elseif w._alwaysOnTop then
      atop[#atop + 1] = w
    else
      normal[#normal + 1] = w
    end
  end

  local function sortBucket(bucket)
    table.sort(bucket, function(a, b)
      local ra = rank[a._id]
      local rb = rank[b._id]
      if ra and rb then
        return ra < rb
      end
      if ra and not rb then
        return true
      end
      if rb and not ra then
        return false
      end
      return (origPos[a] or 0) < (origPos[b] or 0)
    end)
  end

  sortBucket(normal)
  sortBucket(atop)

  local i = 1
  for _, w in ipairs(normal) do
    self.windows[i] = w
    i = i + 1
  end
  for _, w in ipairs(atop) do
    self.windows[i] = w
    i = i + 1
  end
  for _, w in ipairs(closed) do
    self.windows[i] = w
    i = i + 1
  end
  refreshZOrder(self)
  return true
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

-- Extract common window options with defaults
local function extractWindowOptions(opts)
  opts = opts or {}
  return {
    x      = opts.x      or 50,
    y      = opts.y      or 50,
    cellW  = opts.cellW  or 8,
    cellH  = opts.cellH  or 8,
    cols   = opts.cols   or 16,
    rows   = opts.rows   or 16,
    zoom   = opts.zoom   or 2,
    title  = opts.title  or "Window",
  }
end

local function ensureWindowId(self, win)
  if not win then return nil end
  if type(win._id) == "string" and win._id ~= "" then
    return win._id
  end

  local base = tostring(win.kind or "window"):gsub("[^%w_]+", "_")
  if base == "" then
    base = "window"
  end

  local n = 1
  local candidate = string.format("%s_%d", base, n)
  while self:findWindowById(candidate) do
    n = n + 1
    candidate = string.format("%s_%d", base, n)
  end

  win._id = candidate
  return candidate
end

--- Ensure `win._id` is non-empty before persisting/registering (`finalizeNewWindow`, layout load).
function WM:ensureStableWindowId(win)
  return ensureWindowId(self, win)
end

-- Add window, set focus, and create toolbars
function WM:finalizeNewWindow(win)
  if win.showGrid == nil then
    win.showGrid = "chess"
  end

  ensureWindowId(self, win)

  self:add(win)
  self:setFocus(win)

  local ctx = _G.ctx
  if ctx then
    ToolbarController.createToolbarsForWindow(win, ctx, self)
  end
  -- Initialize inactive layer opacity control per window.
  if win.kind ~= "chr" and not win.isPalette then
    if win.kind == "animation" or win.kind == "oam_animation" then
      win.nonActiveLayerOpacity = 0.0
    else
      win.nonActiveLayerOpacity = 1.0
    end
  end

  return win
end

----------------------------------------------------------------
-- Tile windows: static or animated
----------------------------------------------------------------
-- opts:
--   animated  (boolean)   -- false/nil: static art (StaticArtWindow)
--   numLayers (number)    -- for static art (default 2)
--   numFrames (number)    -- for animation (default 3)
--   title, x, y, cellW, cellH, cols, rows, zoom
function WM:createTileWindow(opts)
  opts = opts or {}
  local isAnimated = opts.animated == true
  local defaults  = extractWindowOptions(opts)

  if not isAnimated then
    -- STATIC TILE WINDOW
    defaults.title = opts.title or "Static Art"
    defaults.x     = opts.x or 50
    defaults.y     = opts.y or 50

    local win = StaticArtWindow.new(
      defaults.x, defaults.y,
      defaults.cellW, defaults.cellH,
      defaults.cols, defaults.rows,
      defaults.zoom,
      { title = defaults.title }
    )
    win.nonActiveLayerOpacity = 1.0

    -- Default tile layers
    local numLayers = opts.numLayers or 1
    win.layers = {}
    for i = 1, numLayers do
      win:addLayer({
        opacity = 1.0,
        name    = string.format("Layer %d", i),
        kind    = "tile",
      })
    end
    win.activeLayer = 1

    return self:finalizeNewWindow(win)
  else
    -- ANIMATED TILE WINDOW
    defaults.title = opts.title or "Tile Animation"
    defaults.x     = opts.x or 100
    defaults.y     = opts.y or 100

    local numFrames = opts.numFrames or 3

    local win = AnimationWindow.new(
      defaults.x, defaults.y,
      defaults.cellW, defaults.cellH,
      defaults.cols, defaults.rows,
      defaults.zoom,
      { title = defaults.title, nonActiveLayerOpacity = 0.0 }
    )

    win.layers = {}
    for i = 1, numFrames do
      win:addLayer({
        opacity = (i == 1) and 1.0 or 0.0,  -- first frame visible
        name    = string.format("Frame %d", i),
        kind    = "tile",
      })
    end
    win.activeLayer = 1
    if win.updateLayerOpacities then
      win:updateLayerOpacities()
    end

    return self:finalizeNewWindow(win)
  end
end

----------------------------------------------------------------
-- Sprite windows: static layout or animated
----------------------------------------------------------------
-- opts:
--   animated   (boolean)   -- true (default): multi-frame animation; false: single-frame layout
--   numFrames  (number)    -- for animated windows (default 3)
--   spriteMode (string)    -- "8x8" or "8x16" (default "8x8")
--   title, x, y, cellW, cellH, cols, rows, zoom
function WM:createSpriteWindow(opts)
  opts = opts or {}
  -- Default to animated when not specified
  local isAnimated = (opts.animated ~= false)
  local useOamBacked = (opts.oamBacked == true)
  local defaults  = extractWindowOptions(opts)

  local spriteMode = opts.spriteMode or "8x8"
  if isAnimated then
    local numFrames = opts.numFrames or 3
    defaults.title = opts.title or (useOamBacked and "OAM Animation (sprites)" or "Sprite Animation")
    defaults.x     = opts.x or 150
    defaults.y     = opts.y or 150
    local WindowClass = useOamBacked and OAMAnimationWindow or AnimationWindow
    local win = WindowClass.new(
      defaults.x, defaults.y,
      defaults.cellW, defaults.cellH,
      defaults.cols, defaults.rows,
      defaults.zoom,
      {
        title = defaults.title,
        nonActiveLayerOpacity = 0.0,
        multiRowToolbar = (opts.multiRowToolbar == true),
      }
    )

    win.layers = {}
    for i = 1, numFrames do
      win:addLayer({
        opacity = (i == 1) and 1.0 or 0.0,   -- first frame/layer visible
        name    = string.format("Frame %d", i),
        kind    = "sprite",
        mode    = spriteMode,
        originX = 0,
        originY = 0,
      })

      -- Ensure items array exists for sprite layers
      local layer = win.layers[#win.layers]
      if layer and layer.kind == "sprite" then
        layer.items = layer.items or {}
      end
    end

    win.activeLayer = 1
    if win.updateLayerOpacities then
      win:updateLayerOpacities()
    end

    -- NOTE: SpriteController is still available if you later want to
    -- hook sprite-specific behavior here.

    return self:finalizeNewWindow(win)
  end

  -- STATIC SPRITE LAYOUT WINDOW
  defaults.title = opts.title or "Sprite Layout"
  defaults.x     = opts.x or 150
  defaults.y     = opts.y or 50

  local win = StaticArtWindow.new(
    defaults.x, defaults.y,
    defaults.cellW, defaults.cellH,
    defaults.cols, defaults.rows,
    defaults.zoom,
    { title = defaults.title, nonActiveLayerOpacity = 1.0 }
  )

  win.layers = {}
  win:addLayer({
    opacity = 1.0,
    name    = "Layer 1",
    kind    = "sprite",
    mode    = spriteMode,
    originX = 0,
    originY = 0,
  })
  if win.layers[1] and win.layers[1].kind == "sprite" then
    win.layers[1].items = win.layers[1].items or {}
  end
  win.activeLayer = 1

  return self:finalizeNewWindow(win)
end

function WM:createPatternSketchCanvasWindow(opts)
  opts = opts or {}
  local defaults = extractWindowOptions(opts)
  defaults.title = opts.title or "Pixel sketch"
  defaults.x = opts.x or 80
  defaults.y = opts.y or 80
  defaults.cols = opts.cols or 32
  defaults.rows = opts.rows or 30
  defaults.cellW = opts.cellW or 8
  defaults.cellH = opts.cellH or 8
  defaults.zoom = opts.zoom or 2

  local win = PixelSketchCanvasWindow.new(
    defaults.x, defaults.y,
    defaults.cellW, defaults.cellH,
    defaults.cols, defaults.rows,
    defaults.zoom,
    {
      title = defaults.title,
      visibleCols = opts.visibleCols or defaults.cols,
      visibleRows = opts.visibleRows or defaults.rows,
    }
  )

  return self:finalizeNewWindow(win)
end

function WM:createPatternTableWindow(opts)
  opts = opts or {}
  local defaults = extractWindowOptions(opts)
  defaults.title = opts.title or "Pattern table"
  defaults.x = opts.x or 96
  defaults.y = opts.y or 96
  defaults.cols = opts.cols or 16
  defaults.rows = opts.rows or 16
  defaults.cellW = opts.cellW or 8
  defaults.cellH = opts.cellH or 8
  defaults.zoom = opts.zoom or 2

  local win = PatternTableWindow.new(
    defaults.x,
    defaults.y,
    defaults.cellW,
    defaults.cellH,
    defaults.cols,
    defaults.rows,
    defaults.zoom,
    {
      title = defaults.title,
      visibleCols = opts.visibleCols or defaults.cols,
      visibleRows = opts.visibleRows or defaults.rows,
    }
  )

  win.layers = {}
  win:addLayer({
    opacity = 1.0,
    name = "Pattern table",
    kind = "tile",
    mode = "8x8",
  })
  local L = win.layers[1]
  if L then
    L.patternTable = type(opts.patternTable) == "table" and opts.patternTable or { ranges = {} }
  end

  win._id = opts.id
  win.nonActiveLayerOpacity = 1.0

  return self:finalizeNewWindow(win)
end

function WM:createPPUFrameWindow(opts)
  opts = opts or {}
  local defaults = extractWindowOptions(opts)
  defaults.title = opts.title or "PPU Frame"
  defaults.x = opts.x or 90
  defaults.y = opts.y or 90
  defaults.zoom = opts.zoom or 2

  local win = PPUFrameWindow.new(
    defaults.x,
    defaults.y,
    defaults.zoom,
    {
      title = defaults.title,
      romRaw = opts.romRaw,
      nonActiveLayerOpacity = 1.0,
    }
  )

  local layer = win.layers and win.layers[1] or nil
  if layer then
    layer.kind = "tile"
    layer.mode = "8x8"
    layer.codec = opts.codec or "konami"
    layer.patternTable = type(opts.patternTable) == "table"
      and opts.patternTable
      or { ranges = {} }
  end
  win.activeLayer = 1

  return self:finalizeNewWindow(win)
end

function WM:createPaletteWindow(opts)
  opts = opts or {}
  local defaults = extractWindowOptions(opts)
  defaults.title = opts.title or "Palette"
  defaults.x = opts.x or 60
  defaults.y = opts.y or 60
  defaults.cols = opts.cols or 4
  defaults.rows = opts.rows or 1
  defaults.zoom = opts.zoom or 1

  local initCodes = opts.initCodes
  if initCodes == nil then
    initCodes = {}
    local n = (defaults.rows or 1) * (defaults.cols or 4)
    for i = 1, n do
      initCodes[i] = "0F"
    end
  end

  local win = PaletteWindow.new(
    defaults.x,
    defaults.y,
    defaults.zoom,
    opts.paletteName or "smooth_fbx",
    defaults.rows,
    defaults.cols,
    {
      title = defaults.title,
      activePalette = (opts.activePalette ~= false),
      initCodes = initCodes,
      compactView = (opts.compactView == true),
    }
  )

  return self:finalizeNewWindow(win)
end

function WM:createRomPaletteWindow(opts)
  opts = opts or {}
  local defaults = extractWindowOptions(opts)
  defaults.title = opts.title or "ROM Palette"
  defaults.x = opts.x or 60
  defaults.y = opts.y or 90
  defaults.cols = 4
  defaults.rows = 4
  defaults.zoom = opts.zoom or 1

  local romColors = {}
  for row = 1, defaults.rows do
    romColors[row] = {}
    for col = 1, defaults.cols do
      romColors[row][col] = false
    end
  end

  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app or nil
  local romRaw = opts.romRaw
  if type(romRaw) ~= "string" then
    romRaw = app and app.appEditState and app.appEditState.romRaw or ""
  end

  local win = RomPaletteWindow.new(
    defaults.x,
    defaults.y,
    defaults.zoom,
    opts.paletteName or "smooth_fbx",
    defaults.rows,
    defaults.cols,
    {
      title = defaults.title,
      paletteData = {
        romColors = romColors,
        userDefinedCode = {},
      },
      romRaw = romRaw,
      activePalette = false,
      compactView = (opts.compactView == true),
    }
  )

  if app and app.appEditState then
    win._updateRomRawCallback = function(newRom)
      app.appEditState.romRaw = newRom
    end
  end

  return self:finalizeNewWindow(win)
end

function WM:createCrtLensWindow(opts)
  opts = opts or {}
  local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app or nil
  local offsetY = app and AppTopToolbarController.getContentOffsetY(app) or 15
  local cw = (app and app.canvas and app.canvas.getWidth and app.canvas:getWidth()) or 640
  local ch = (app and app.canvas and app.canvas.getHeight and app.canvas:getHeight()) or 360
  local z = opts.zoom or 1
  local contentW = 32 * 8 * z
  local contentH = 30 * 8 * z
  local headerH = UiScale.windowHeaderHeight()
  local x = math.max(8, math.floor((cw - contentW) / 2))
  local y = math.max(offsetY + 8, math.floor(offsetY + (ch - offsetY - contentH - headerH) / 2))

  local win = CrtLensWindow.new(x, y, z, { title = opts.title or "CRT layer visualizer" })
  win._crtLensVisible = false
  return self:finalizeNewWindow(win)
end

return WM
