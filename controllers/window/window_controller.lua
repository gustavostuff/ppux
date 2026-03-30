-- window_controller.lua — z-order, focus, hit-test, borders
local DebugController    = require("controllers.dev.debug_controller")
local StaticArtWindow    = require("user_interface.windows_system.static_art_window")
local PatternTableBuilderWindow = require("user_interface.windows_system.pattern_table_builder_window")
local AnimationWindow    = require("user_interface.windows_system.animation_window")
local OAMAnimationWindow = require("user_interface.windows_system.oam_animation_window")
local PaletteWindow      = require("user_interface.windows_system.palette_window")
local SpriteController   = require("controllers.sprite.sprite_controller")
local ToolbarController  = require("controllers.window.toolbar_controller")
local WindowCaps = require("controllers.window.window_capabilities")

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

local function isWindowVisibleForInteraction(win)
  return win and not win._closed and not win._minimized
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
  table.insert(self.windows, win)
  DebugController.log(
    "info", "WM",
    "Window added: %s (kind: %s, total windows: %d)",
    win.title or "untitled",
    win.kind or "normal",
    #self.windows
  )
  refreshZOrder(self)
  if self.taskbar and self.taskbar.addWindowButton then
    self.taskbar:addWindowButton(win)
  elseif self.taskbar and self.taskbar.addMinimizedWindow then
    self.taskbar:addMinimizedWindow(win)
  end
end

function WM:update(dt)
  -- Skip closed windows
  for _, w in ipairs(self.windows) do
    if not w._closed and not w._minimized then
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

local function syncCollapseIcon(win)
  if not (win and win.headerToolbar) then return end
  if win.headerToolbar.updateCollapseIcon then
    win.headerToolbar:updateCollapseIcon()
  elseif win.headerToolbar.updateIcons then
    win.headerToolbar:updateIcons()
  end
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
  refreshZOrder(self)

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
  local startY  = opts.startY or 30 + 15
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
    end
    return
  end

  -- Rebuild window stack: keep open windows (largest → smallest) first, then closed ones.
  self.windows = {}
  for _, w in ipairs(open) do
    table.insert(self.windows, w)
  end
  for _, w in ipairs(closed) do
    table.insert(self.windows, w)
  end

  refreshZOrder(self)

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
      stackY = stackY + (p.headerH or 15) + paletteStackGap
    end
  end

  if #open > 0 then
    self.focused = open[#open]
  elseif #palettes > 0 then
    self.focused = palettes[#palettes]
  else
    self.focused = nil
  end
end

-- Collapse all open windows and stack headers in columns from left to right.
function WM:collapseAll(opts)
  opts = opts or {}

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
    local headerH = w.headerH or 15
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
end

function WM:expandAll()
  local any = false
  for _, w in ipairs(self.windows) do
    if not w._closed and not w._minimized and w._collapsed then
      w._collapsed = false
      syncCollapseIcon(w)
      any = true
    end
  end
  return any
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
  table.insert(self.windows, win)
  refreshZOrder(self)
end

function WM:setFocus(win)
  if win and (win._closed or win._minimized) then
    return
  end
  if win and self.focused ~= win then
    self.focused = win
    self:bringToFront(win)
    DebugController.log(
      "info", "WM",
      "Focus set to: %s (kind: %s)",
      win.title or "untitled",
      win.kind or "normal"
    )
  elseif win == nil then
    self.focused = nil
    DebugController.log("info", "WM", "Focus cleared")
  end
end

function WM:getFocus()
  return self.focused
end

function WM:windowAt(x, y)
  -- Iterate from front to back
  for i = #self.windows, 1, -1 do
    local win = self.windows[i]
    -- Skip closed windows
    if not win._closed and not win._minimized and win:contains(x, y) then
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

function WM:minimizeWindow(win)
  if not isWindowVisibleForInteraction(win) then return false end

  win._minimized = true
  win.dragging = false
  win.resizing = false

  if self.focused == win then
    self.focused = findTopVisibleWindow(self)
  end

  if self.taskbar and self.taskbar.addMinimizedWindow then
    self.taskbar:addMinimizedWindow(win)
  end

  return true
end

function WM:restoreMinimizedWindow(win)
  if not win or win._closed or not win._minimized then return false end

  win._minimized = false

  if self.taskbar and self.taskbar.removeMinimizedWindow then
    self.taskbar:removeMinimizedWindow(win)
  end

  self:setFocus(win)
  return true
end

function WM:minimizeAll()
  local any = false
  for _, win in ipairs(self.windows) do
    if self:minimizeWindow(win) then
      any = true
    end
  end
  return any
end

function WM:maximizeAll()
  local targets = {}
  for _, win in ipairs(self.windows) do
    if win and not win._closed and win._minimized then
      targets[#targets + 1] = win
    end
  end

  local any = false
  for _, win in ipairs(targets) do
    if self:restoreMinimizedWindow(win) then
      any = true
    end
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

-- Add window, set focus, and create toolbars
function WM:finalizeNewWindow(win)
  if win.showGrid == nil then
    win.showGrid = "chess"
  end

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
      { title = defaults.title, nonActiveLayerOpacity = 0.0 }
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

function WM:createPatternTableBuilderWindow(opts)
  opts = opts or {}
  local defaults = extractWindowOptions(opts)
  defaults.title = opts.title or "Pattern Table Builder"
  defaults.x = opts.x or 80
  defaults.y = opts.y or 80
  defaults.cols = opts.cols or 32
  defaults.rows = opts.rows or 30
  defaults.cellW = opts.cellW or 8
  defaults.cellH = opts.cellH or 8
  defaults.zoom = opts.zoom or 2

  local win = PatternTableBuilderWindow.new(
    defaults.x, defaults.y,
    defaults.cellW, defaults.cellH,
    defaults.cols, defaults.rows,
    defaults.zoom,
    {
      title = defaults.title,
      visibleCols = opts.visibleCols or defaults.cols,
      visibleRows = opts.visibleRows or defaults.rows,
      patternTolerance = opts.patternTolerance or 0,
    }
  )

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
      initCodes = opts.initCodes,
    }
  )

  return self:finalizeNewWindow(win)
end

----------------------------------------------------------------
-- Optional border debug draw (kept commented-out)
----------------------------------------------------------------
-- function WM:drawBorders()
--   for _, w in ipairs(self.windows) do
--     local x, y, wpx, hpx = w:getScreenRect()
--     if w == self.focused then
--       love.graphics.setColor(0.2, 0.55, 1.0, 1) -- blue
--     else
--       love.graphics.setColor(0.6, 0.6, 0.6, 1) -- gray
--     end
--     love.graphics.rectangle("line", x + 0.5, y + 0.5, wpx - 1, hpx - 1)
--   end
--   love.graphics.setColor(1, 1, 1, 1)
-- end

return WM
