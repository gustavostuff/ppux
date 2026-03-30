local DebugController = require("controllers.dev.debug_controller")
local Timer = require("utils.timer_utils")

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
  return self.visibleCols * self.cellW, self.visibleRows * self.cellH
end

function Window:getRealContentSize()
  return self.cols * self.cellW, self.rows * self.cellH
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

function Window:getScreenRect()
  local cw, ch = self:getContentSize()

  return self.x,
         self.y,
         cw * self.zoom,
         ch * self.zoom
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
  
  -- Normal window bounds check
  local x, y, w, h = self:getScreenRect()
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
  
  local x, y, w, h = self:getScreenRect()
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
  if layer and layer.mode == "8x16" then
    rowStride = 2
  elseif self.kind == "chr" and self.orderMode == "oddEven" then
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
  local z = self.zoom or 1
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

-- Convert screen → content (viewport) → grid, accounting for scroll
function Window:toContentCoords(px,py)
  if not self:contains(px,py) then return false end
  local cx = (px - self.x)/self.zoom
  local cy = (py - self.y)/self.zoom
  return true, math.floor(cx), math.floor(cy)
end

function Window:toGridCoords(px, py)
  local ok,cx,cy = self:toContentCoords(px,py)
  if not ok then return false end

  -- Map within viewport first
  local localCol = math.floor(cx/self.cellW)
  local localRow = math.floor(cy/self.cellH)

  if localCol < 0 or localRow < 0 or
     localCol >= self.visibleCols or localRow >= self.visibleRows then
    return false
  end

  -- Then shift by scroll to absolute grid coords
  local col = localCol + self.scrollCol
  local row = localRow + self.scrollRow
  if col<0 or col>=self.cols or row<0 or row>=self.rows then return false end

  local lx = cx - localCol*self.cellW
  local ly = cy - localRow*self.cellH
  return true, col, row, lx, ly
end

end
