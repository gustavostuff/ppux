local DebugController = require("controllers.dev.debug_controller")
local Timer = require("utils.timer_utils")
local WindowCaps = require("controllers.window.window_capabilities")

local SCROLL_BAR_OPACITY_TIME = 1.5
local MIN_WINDOW_SIZE = 64
local ZOOM_STEPS = { 1, 2, 3, 4, 8, 12, 20 }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function getMinWindowSize(self)
  local value = tonumber(self and self.minWindowSize)
  if value and value >= 0 then
    return value
  end
  return MIN_WINDOW_SIZE
end

return function(Window)
-- ==== Size helpers (viewport vs full content) ====
function Window:getVisibleSize()
  local grid = self.getDisplayGridMetrics and self:getDisplayGridMetrics()
  local cw = (grid and grid.cellW) or self.cellW or 8
  local ch = (grid and grid.cellH) or self.cellH or 8
  return self.visibleCols * cw, self.visibleRows * ch
end

function Window:getRealContentSize()
  local grid = self.getDisplayGridMetrics and self:getDisplayGridMetrics()
  local cw = (grid and grid.cellW) or self.cellW or 8
  local ch = (grid and grid.cellH) or self.cellH or 8
  return self.cols * cw, self.rows * ch
end

function Window:getContentSize()
  -- NOTE: "content" in screen terms is the VISIBLE viewport size now
  return self:getVisibleSize()
end

-- ==== Discrete zoom (unchanged) ====
local function nearestZoomStep(z)
  local bestIdx = 1
  local bestStep = ZOOM_STEPS[1]
  local bestDiff = math.huge
  for i, step in ipairs(ZOOM_STEPS) do
    local diff = math.abs(step - z)
    if diff < bestDiff or (diff == bestDiff and step > bestStep) then
      bestDiff = diff
      bestStep = step
      bestIdx = i
    end
  end
  return bestStep, bestIdx
end

function Window:getZoomLevel()
  return nearestZoomStep(self.zoom or 1)
end

function Window:setZoomLevel(level, pivotX, pivotY)
  local newZ = nearestZoomStep(level or 1)
  local oldZ = self.zoom
  if newZ == oldZ then return end

  -- Enforce minimum visual content size when zooming
  local vCols = self.visibleCols or 1
  local vRows = self.visibleRows or 1
  local newWidthPixels  = vCols * self.cellW * newZ
  local newHeightPixels = vRows * self.cellH * newZ
  local minWindowSize = getMinWindowSize(self)

  -- If zooming out would make the content smaller than 128x128, reject it
  if newWidthPixels < minWindowSize or newHeightPixels < minWindowSize then
    DebugController.log("info", "WIN", "Window '%s' zoom rejected: would be too small (%.0fx%.0f < %d)", self.title or "untitled", newWidthPixels, newHeightPixels, minWindowSize)
    return
  end

  if pivotX == nil or pivotY == nil then
    local cw, ch = self:getContentSize()
    pivotX = self.x + (cw * self.zoom) * 0.5
    pivotY = self.y + (ch * self.zoom) * 0.5
  end

  local cx = (pivotX - self.x) / oldZ
  local cy = (pivotY - self.y) / oldZ

  self.x = math.floor(pivotX - cx * newZ)
  self.y = math.floor(pivotY - cy * newZ)

  self.zoom = newZ
  DebugController.log("info", "WIN", "Window '%s' zoom changed: %.1f -> %.1f", self.title or "untitled", oldZ, newZ)

  if self.invalidateAllTileLayerCanvases then
    self:invalidateAllTileLayerCanvases()
  end
end

function Window:addZoomLevel(delta, pivotX, pivotY)
  local _, idx = nearestZoomStep(self.zoom or 1)
  local newIdx = math.max(1, math.min(#ZOOM_STEPS, idx + (delta or 0)))
  self:setZoomLevel(ZOOM_STEPS[newIdx], pivotX, pivotY)
end

function Window:getZoom() return self.zoom end
function Window:setZoom(z) self:setZoomLevel(z, nil, nil) end
function Window:addZoomSteps(steps) self:addZoomLevel(steps or 0, nil, nil) end
function Window:addZoomCoarse(delta)
  self:addZoomLevel((delta and (delta>0 and 1 or -1)) or 0, nil, nil)
end

--- Full on-canvas content rectangle (stable geometry: position and size must not depend on toolbar placement).
function Window:getScreenRect()
  return self:getBaseContentScreenRect()
end

--- Same footprint as `getScreenRect`, minus space reserved for a window-attached specialized toolbar
--- (scissor, grid draw origin, pointer mapping). Does not change window frame or chrome layout.
function Window:getInsetContentScreenRect()
  local x, y, w, h = self:getBaseContentScreenRect()
  local li = self._toolbarInsetLeft or 0
  local ri = self._toolbarInsetRight or 0
  local ti = self._toolbarInsetTop or 0
  local bi = self._toolbarInsetBottom or 0
  local nx = x + li
  local ny = y + ti
  local nw = math.max(0, w - li - ri)
  local nh = math.max(0, h - ti - bi)
  return nx, ny, nw, nh
end

--- Content rectangle without window-toolbar placement insets (logical grid / full viewport).
function Window:getBaseContentScreenRect()
  local cw, ch = self:getContentSize()
  local z = self:getZoomLevel()

  return self.x,
         self.y,
         cw * z,
         ch * z
end

function Window:getResizeHandleRect()
  local x, y, w, h = self:getScreenRect()
  local handle = 8
  return x + w + 1, y + h + 1, handle, handle
end

function Window:hitResizeHandle(px, py)
  if not self.resizable or self._collapsed then return false end
  local hx, hy, hw, hh = self:getResizeHandleRect()
  return px >= hx and px <= hx + hw and py >= hy and py <= hy + hh
end

function Window:contains(px, py)
  if self._closed then return false end
  -- If collapsed, only check header area
  if self._collapsed then
    local hx, hy, hw, hh = self:getHeaderRect()
    return px >= hx and px <= hx + hw and py >= hy and py <= hy + hh
  end
  
  -- Normal window bounds check (full grid footprint; use base rect so toolbar side strips count).
  local x, y, w, h = self:getBaseContentScreenRect()
  return (
    px >= x                    and
    px <= x + w                and
    py >= y - self.headerH     and
    py <= y + h
  )
end

function Window:isInContentArea(px, py)
  -- Check if point is in the window's content area (not header)
  -- Content area is the main window rectangle (header is above at y - headerH)
  if self._closed then return false end
  
  local x, y, w, h = self:getInsetContentScreenRect()
  return (
    px >= x                    and
    px <= x + w                and
    py >= y                    and  -- Content starts at y (header is above at y - headerH)
    py <= y + h
  )
end

-- ==== SCROLL API ====
function Window:getScroll() return self.scrollCol, self.scrollRow end

function Window:getDisplayGridMetrics(layerIndex)
  local baseCellW = self.cellW or 8
  local baseCellH = self.cellH or 8
  local rowStride = 1

  local li = layerIndex or self.activeLayer or 1
  local layer = self.layers and self.layers[li] or nil
  -- Tile/sprite layers: each logical row occupies 16px height (CHR tile scaled ×2 vertically).
  -- CHR oddEven and pattern_table "8x16" layout only *reindex* within an 8px grid — do not inflate cellH.
  if layer and layer.mode == "8x16" and not WindowCaps.isPatternTable(self) then
    rowStride = 2
  end

  return {
    baseCellW = baseCellW,
    baseCellH = baseCellH,
    cellW = baseCellW,
    cellH = baseCellH * rowStride,
    rowStride = rowStride,
  }
end

function Window:setScroll(col, row)
  -- Snap to whole cells; clamp to content limits so the viewport stays within bounds.
  local maxCol = math.max(0, self.cols - self.visibleCols)
  local maxRow = math.max(0, self.rows - self.visibleRows)
  self.scrollCol = clamp(math.floor(col or 0), 0, maxCol)
  self.scrollRow = clamp(math.floor(row or 0), 0, maxRow)

  Timer.mark("fadeScrolling")
  self.scrollbarOpacity = SCROLL_BAR_OPACITY_TIME
end

function Window:scrollBy(dcol, drow)
  self:setScroll(self.scrollCol + math.floor(dcol or 0), self.scrollRow + math.floor(drow or 0))
end

-- Programmatically shrink viewport to the minimum size allowed by resize constraints.
function Window:resizeToMinimum()
  local z = self:getZoomLevel()
  local cols = self.cols or 1
  local rows = self.rows or 1
  local cw = self.cellW or 1
  local ch = self.cellH or 1
  local minWindowSize = getMinWindowSize(self)

  local minVisibleCols = math.max(1, math.ceil(minWindowSize / math.max(1, cw * z)))
  local minVisibleRows = math.max(1, math.ceil(minWindowSize / math.max(1, ch * z)))

  self.visibleCols = math.min(cols, minVisibleCols)
  self.visibleRows = math.min(rows, minVisibleRows)

  if self.setScroll then
    self:setScroll(self.scrollCol or 0, self.scrollRow or 0)
  end
end

--- Horizontal mirror preview for this window (body flipped around `getInsetContentScreenRect()` when focused).
--- Remap pointer X so editing uses the same coordinate space as unmirrored layer data.
function Window:remapPreviewMirrorScreenXYIfNeeded(px, py)
  if self._mirrorXPreview ~= true then
    return px, py
  end
  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app
  local wm = (ctx and ctx.wm and ctx.wm()) or (app and app.wm)
  if not wm or wm:getFocus() ~= self then
    return px, py
  end
  if WindowCaps.isAnyPaletteWindow(self) then
    return px, py
  end
  if not self.isInContentArea or not self:isInContentArea(px, py) then
    return px, py
  end
  local sx, _, sw = self:getInsetContentScreenRect()
  if not (type(px) == "number" and type(sx) == "number" and type(sw) == "number" and sw > 0) then
    return px, py
  end
  local lx = px - sx
  return sx + sw - lx, py
end

--- Screen-space top-left of the drawn grid/content (respects window-attached toolbar insets).
function Window:getContentScreenOrigin()
  local sx, sy = self:getInsetContentScreenRect()
  return sx, sy
end

--- Absolute canvas X/Y (layer coords) from screen position; matches draw translate + scroll.
function Window:screenToAbsoluteCanvasXY(px, py)
  local z = self:getZoomLevel()
  local sx, sy = self:getInsetContentScreenRect()
  local scol = self.scrollCol or 0
  local srow = self.scrollRow or 0
  local grid = self.getDisplayGridMetrics and self:getDisplayGridMetrics()
  local cw = (grid and grid.cellW) or self.cellW or 8
  local ch = (grid and grid.cellH) or self.cellH or 8
  return scol * cw + (px - sx) / z, srow * ch + (py - sy) / z
end

-- Convert screen -> content (viewport) -> grid, accounting for scroll
function Window:toContentCoords(px,py)
  px, py = self:remapPreviewMirrorScreenXYIfNeeded(px, py)
  if not self:contains(px,py) then return false end
  local z = self:getZoomLevel()
  if type(self.isInContentArea) == "function" and self:isInContentArea(px, py) then
    local sx, sy = self:getInsetContentScreenRect()
    local cx = (px - sx) / z
    local cy = (py - sy) / z
    return true, math.floor(cx), math.floor(cy)
  end
  local cx = (px - self.x) / z
  local cy = (py - self.y) / z
  return true, math.floor(cx), math.floor(cy)
end

function Window:toGridCoords(px, py)
  local ok,cx,cy = self:toContentCoords(px,py)
  if not ok then return false end

  local grid = self.getDisplayGridMetrics and self:getDisplayGridMetrics()
  local gcw = (grid and grid.cellW) or self.cellW or 8
  local gch = (grid and grid.cellH) or self.cellH or 8

  -- Map within viewport first
  local localCol = math.floor(cx / gcw)
  local localRow = math.floor(cy / gch)

  if localCol < 0 or localRow < 0 or
     localCol >= self.visibleCols or localRow >= self.visibleRows then
    return false
  end

  -- Then shift by scroll to absolute grid coords
  local col = localCol + self.scrollCol
  local row = localRow + self.scrollRow
  if col<0 or col>=self.cols or row<0 or row>=self.rows then return false end

  local lx = cx - localCol * gcw
  local ly = cy - localRow * gch
  return true, col, row, lx, ly
end

end
