local images = require("images")
local TU = require("utils.text_utils")
local colors = require("app_colors")
local Timer = require("utils.timer_utils")
local SpaceHighlightController = require("controllers.window.space_highlight_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local MIN_WINDOW_SIZE = 64
local ITEM_COUNT_LABEL_SHOW_DURATION = 0.0
local ITEM_COUNT_LABEL_FADE_DURATION = 1.0

local function getMinWindowSize(self)
  local value = tonumber(self and self.minWindowSize)
  if value and value >= 0 then
    return value
  end
  return MIN_WINDOW_SIZE
end

return function(Window)
function Window:getHeaderRect()
  local x, y, w, _ = self:getScreenRect()
  return x, y - self.headerH, w, self.headerH
end

local function getActiveLayerItemCountText(win)
  if not (win and win.layers) then return nil end
  local li = win.activeLayer or 1
  local L = win.layers[li]
  if not L then return nil end

  if L.kind == "sprite" then
    local count = 0
    for _, item in ipairs(L.items or {}) do
      if item and item.removed ~= true then
        count = count + 1
      end
    end
    return string.format("%d %s", count, (count == 1) and "sprite" or "sprites")
  end

  local count = 0
  local removed = (WindowCaps.isPpuFrame(win) and L.kind == "tile") and nil or L.removedCells
  for idx, item in pairs(L.items or {}) do
    if item ~= nil and not (removed and removed[idx]) then
      count = count + 1
    end
  end
  return string.format("%d %s", count, (count == 1) and "tile" or "tiles")
end

-- Draw layer label in content area (if toolbar has one). For windows without a
-- specialized toolbar (e.g. static art), draw item-count label on Space hold/release.
function Window:drawLayerLabelInContent(isFocused)
  if self.specializedToolbar and self.specializedToolbar.drawLayerLabelInContent then
    self.specializedToolbar:drawLayerLabelInContent()
    return
  end

  if not isFocused then
    return
  end

  local text = getActiveLayerItemCountText(self)
  if not text then return end

  local spaceDown = SpaceHighlightController.isSpaceHighlightActive()
  if spaceDown then
    self.itemCountLabelSpaceDown = true
    local sx, sy = self:getScreenRect()
    TU.print(text, sx + 4, sy + 4, {
      outline = true,
      color = { colors.white[1], colors.white[2], colors.white[3], 1.0 },
    })
    return
  end

  if self.itemCountLabelSpaceDown then
    self.itemCountLabelSpaceDown = false
    Timer.mark(self.itemCountLabelMarkName)
  end

  local elapsed = Timer.elapsed(self.itemCountLabelMarkName)
  if not elapsed then return end
  if elapsed > (ITEM_COUNT_LABEL_SHOW_DURATION + ITEM_COUNT_LABEL_FADE_DURATION) then
    return
  end

  local alpha = 1.0
  if elapsed > ITEM_COUNT_LABEL_SHOW_DURATION then
    local t = (elapsed - ITEM_COUNT_LABEL_SHOW_DURATION) / ITEM_COUNT_LABEL_FADE_DURATION
    alpha = 1.0 - math.max(0, math.min(1, t))
  end
  if alpha <= 0 then return end

  local sx, sy = self:getScreenRect()
  TU.print(text, sx + 4, sy + 4, {
    outline = true,
    color = { colors.white[1], colors.white[2], colors.white[3], alpha },
  })
end

function Window:drawHeader(isFocused)
  local hx, hy, hw, hh = self:getHeaderRect()
  local pad  = 4
  local text = self.title

  -- background bar
  if isFocused then
    love.graphics.setColor(colors.blue)
  else
    love.graphics.setColor(colors.gray20)
  end
  love.graphics.rectangle("fill", hx - 1, hy, hw + 2, hh, 2)

  -- text color (important, otherwise it inherits the dark bg color)
  love.graphics.setColor(colors.white)

  local ty = math.floor(hy + (hh - love.graphics.getFont():getHeight()) / 2)

  -- Keep marquee width stable; header toolbar draws on top when visible.
  local textWidth = hw - pad * 2
  local textX = hx + pad  -- Start text from left edge
  local startIdx, endIdx = TU.drawScrollingText(
    text,
    math.floor(textX),
    math.floor(ty),
    math.max(0, textWidth),  -- Ensure width is not negative
    {
      speed = 8,
      pause = 1,
      key   = self,
    }
  )

  self.headerStartIndex = startIdx
  self.headerEndIndex   = endIdx
end

function Window:drawBorder(isFocused)
  local x, y, w, h = self:getScreenRect()

  -- Border
  if isFocused then
    love.graphics.setColor(colors.blue)
  else
    love.graphics.setColor(colors.gray20)
  end
  love.graphics.rectangle("line", x, y, w + 1, h + 1)
  love.graphics.setColor(colors.white)
end

local function getResizeHandleCapabilities(self)
  local z = self.zoom or 1
  local cw = self.cellW or 1
  local ch = self.cellH or 1
  local visibleCols = self.visibleCols or 1
  local visibleRows = self.visibleRows or 1
  local totalCols = self.cols or visibleCols
  local totalRows = self.rows or visibleRows
  local minWindowSize = getMinWindowSize(self)

  local minVisibleCols = math.max(1, math.ceil(minWindowSize / math.max(1, cw * z)))
  local minVisibleRows = math.max(1, math.ceil(minWindowSize / math.max(1, ch * z)))

  local canResizeLess = (visibleCols > minVisibleCols) or (visibleRows > minVisibleRows)
  -- "More" means growing the viewport could reveal hidden/scrolled content.
  local canResizeMore = (visibleCols < totalCols) or (visibleRows < totalRows)

  return canResizeLess, canResizeMore
end

function Window:drawResizeHandle(isFocused, scaledMouse)
  if self.resizable and isFocused and not self._collapsed then
    local hx, hy, hw, hh = self:getResizeHandleRect()
    local canResizeLess, canResizeMore = getResizeHandleCapabilities(self)

    local handleImage = images["resize_handle"]
    if canResizeLess and not canResizeMore then
      handleImage = images["resize_handle_less"] or handleImage
    elseif canResizeMore and not canResizeLess then
      handleImage = images["resize_handle_more"] or handleImage
    end

    local blocked = (not canResizeLess) and (not canResizeMore)
    if blocked then
      love.graphics.setColor(colors.yellow)
    elseif self.resizing or self:mouseOnResizeHandle(scaledMouse.x, scaledMouse.y) then
      love.graphics.setColor(colors.blue)
    else
      love.graphics.setColor(colors.gray20)
    end

    love.graphics.draw(handleImage, hx, hy)
    love.graphics.setColor(colors.white)
  end
end

function Window:mouseOnResizeHandle(px, py)
  if not self.resizable or self._collapsed then return false end
  local hx, hy, hw, hh = self:getResizeHandleRect()
  return px >= hx and px <= hx + hw and py >= hy and py <= hy + hh
end

function Window:drawScrollBars(isFocused)
  if not isFocused then return end

  local x, y, w, h = self:getScreenRect()
  local needsH = self.cols > self.visibleCols
  local needsV = self.rows > self.visibleRows
  if not (needsH or needsV) then return end

  love.graphics.setLineStyle("rough")
  local c = colors.white
  love.graphics.setColor(c[1], c[2], c[3], self.scrollbarOpacity)

  -- Border extents (see drawBorder: rectangle("line", x, y, w + 1, h + 1))
  local leftBorder   = x - 1
  local rightBorder  = x + w + 1
  local topBorder    = y
  local bottomBorder = y + h + 1
  local separation = 1 -- form window border

  -- HORIZONTAL SCROLLBAR
  if needsH then
    local span      = self.cols
    local vis       = self.visibleCols
    local maxScroll = math.max(1, span - vis)           -- cols - visibleCols

    local trackLeft  = leftBorder
    local trackRight = rightBorder
    local trackLen   = trackRight - trackLeft

    -- Thumb size proportional to visible fraction
    local frac    = vis / span
    local thumbW  = math.max(1, math.floor(trackLen * frac))

    -- Map scrollCol in [0, maxScroll] to [trackLeft, trackRight - thumbW]
    local s       = self.scrollCol
    local posFrac = s / maxScroll
    local thumbX  = math.floor(trackLeft + posFrac * (trackLen - thumbW))

    local yLine   = bottomBorder  -- aligned with bottom border / corner
    love.graphics.rectangle("fill",
      thumbX,
      yLine + separation,
      thumbW,
      4
    )
  end

  -- VERTICAL SCROLLBAR
  if needsV then
    local span      = self.rows
    local vis       = self.visibleRows
    local maxScroll = math.max(1, span - vis)           -- rows - visibleRows

    -- IMPORTANT: track starts at the *bottom* of the header, i.e. content top = y
    local trackTop    = y               -- bottom of header
    local trackBottom = bottomBorder    -- bottom border corner
    local trackLen    = trackBottom - trackTop

    local frac    = vis / span
    local thumbH  = math.max(1, math.floor(trackLen * frac))

    -- Map scrollRow in [0, maxScroll] to [trackTop, trackBottom - thumbH]
    local s       = self.scrollRow
    local posFrac = s / maxScroll
    local thumbY  = math.floor(trackTop + posFrac * (trackLen - thumbH))

    local xLine   = rightBorder        -- aligned with right border / corner

    love.graphics.rectangle("fill",
      xLine + separation,
      thumbY,
      4,
      thumbH
    )
  end

  -- Reset color
  love.graphics.setColor(colors.white)
end

end
