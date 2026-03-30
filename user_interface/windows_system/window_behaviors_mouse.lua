local ResolutionController = require("controllers.app.resolution_controller")
local Timer = require("utils.timer_utils")

local SCROLL_BAR_OPACITY_TIME = 1.5
local MIN_WINDOW_SIZE = 64
local DRAG_VISIBLE_MARGIN = 15

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function getMinWindowSize(self)
  local value = tonumber(self and self.minWindowSize)
  if value and value >= 0 then
    return value
  end
  return MIN_WINDOW_SIZE
end

local function getCanvasBounds()
  local canvasW = ResolutionController.canvasWidth or love.graphics.getWidth()
  local canvasH = ResolutionController.canvasHeight or love.graphics.getHeight()
  local taskbar = _G.ctx and _G.ctx.taskbar or nil
  local bottomY = canvasH

  if taskbar and taskbar.getTopY then
    bottomY = taskbar:getTopY() or bottomY
  elseif taskbar and taskbar.y then
    bottomY = taskbar.y
  end

  return 0, 0, canvasW, bottomY
end

local function clampDraggedWindowPosition(self, nextX, nextY)
  local _, _, width, height = self:getScreenRect()
  local _, _, canvasW, usableBottomY = getCanvasBounds()

  local minX = DRAG_VISIBLE_MARGIN - width
  local maxX = canvasW - DRAG_VISIBLE_MARGIN
  local minY = DRAG_VISIBLE_MARGIN - height
  local maxY = self._collapsed and usableBottomY or (usableBottomY - DRAG_VISIBLE_MARGIN)

  return clamp(nextX, minX, maxX), clamp(nextY, minY, maxY)
end

return function(Window)
function Window:mousepressed(x, y, button)
  -- Start resizing when clicking the external 20x20 handle
  if button == 1 then
    if self.resizable and not self._collapsed and self:hitResizeHandle(x, y) then
      self.resizing = true
      return
    end

    -- LEFT-CLICK DRAG: only when pressing inside the header area
    if self:isInHeader(x, y) then
      self.dragging = true
      self.dx = x - self.x
      self.dy = y - self.y
      return
    end
  end

  -- Existing non-left-button drag-to-move behavior
  if (button == 2 or button == 3) and self:contains(x, y) then
    self.dragging = true
    self.dx = x - self.x
    self.dy = y - self.y
  end
end

function Window:mousereleased(_, _, button)
  if button == 1 and self.resizing then
    self.resizing = false
    return
  end

  if self.dragging then
    self.dragging = false
  end
end

function Window:mousemoved(mx, my)
  if self.resizing then
    -- Convert pointer to unscaled local coords relative to window top-left.
    local lx = (mx - self.x) / self.zoom
    local ly = (my - self.y) / self.zoom

    -- Remember previous visible area
    local oldVisibleCols = self.visibleCols or 1
    local oldVisibleRows = self.visibleRows or 1

    -- How many full cells fit? (min 1). Clamp to available cols/rows.
    local newVisibleCols = math.max(1, math.floor(lx / self.cellW + 0.00001))
    local newVisibleRows = math.max(1, math.floor(ly / self.cellH + 0.00001))

    newVisibleCols = math.min(newVisibleCols, self.cols or newVisibleCols)
    newVisibleRows = math.min(newVisibleRows, self.rows or newVisibleRows)

    -- Enforce minimum visual size (content only), in screen pixels
    local newWidthPixels  = newVisibleCols * self.cellW * self.zoom
    local newHeightPixels = newVisibleRows * self.cellH * self.zoom
    local minWindowSize = getMinWindowSize(self)

    if newWidthPixels < minWindowSize then
      newVisibleCols = oldVisibleCols
    end
    if newHeightPixels < minWindowSize then
      newVisibleRows = oldVisibleRows
    end

    Timer.mark("fadeScrolling")
    self.scrollbarOpacity = SCROLL_BAR_OPACITY_TIME

    if newVisibleCols ~= self.visibleCols or newVisibleRows ~= self.visibleRows then
      self.visibleCols = newVisibleCols
      self.visibleRows = newVisibleRows
      -- Re-clamp scroll so viewport stays inside content after resize (if scrolling is present).
      if self.setScroll then self:setScroll(self.scrollCol or 0, self.scrollRow or 0) end
    end
    return
  end

  -- Existing right-button drag-to-move behavior (unchanged)
  if self.dragging then
    self.x, self.y = clampDraggedWindowPosition(self, mx - self.dx, my - self.dy)
  end
end

end
