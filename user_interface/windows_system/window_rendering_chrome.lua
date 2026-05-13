local images = require("images")
local TU = require("utils.text_utils")
local colors = require("app_colors")
local Timer = require("utils.timer_utils")
local SpaceHighlightController = require("controllers.window.space_highlight_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local MIN_WINDOW_SIZE = 64
local ITEM_COUNT_LABEL_SHOW_DURATION = 0.0
local ITEM_COUNT_LABEL_FADE_DURATION = 1.0
local SCROLL_BAR_THICKNESS_PX = 1

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
  local focusColor = colors:focusedChromeColor()
  if isFocused then
    love.graphics.setColor(focusColor)
  else
    love.graphics.setColor(colors:chromeBackgroundUnfocused())
  end
  love.graphics.rectangle("fill", hx - 1, hy, hw + 2, hh, 2)

  -- Title on chrome: use Appearance "Text/Icons" when focused; body text when not.
  local textColor
  if isFocused then
    textColor = colors:chromeTextIconsColorFocused()
  else
    textColor = colors:chromeTextIconsColorNonFocused()
  end

  love.graphics.setColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)

  local indicators = rawget(images, "icons") and images.icons.indicators
  local iconMirrored = indicators and indicators.icon_mirrored
  local iconTop = indicators and indicators.icon_always_on_top
  local showMirror = self._mirrorXPreview == true
  local showAlwaysOnTop = self._alwaysOnTop == true
  local headerIcon = nil
  if showMirror and showAlwaysOnTop and iconMirrored and iconTop then
    local wave = math.floor((love.timer.getTime() or 0) / 0.5) % 2
    headerIcon = wave == 0 and iconMirrored or iconTop
  elseif showMirror and iconMirrored then
    headerIcon = iconMirrored
  elseif showAlwaysOnTop and iconTop then
    headerIcon = iconTop
  end

  local headerIconInset = pad -- title margin from header left when no status icon
  if headerIcon then
    love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], colors.white[4] or 1)
    -- Offset from header origin (shared for mirror / always-on-top icons).
    love.graphics.draw(headerIcon, hx - 4, hy - 3)
    love.graphics.setColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
    headerIconInset = headerIcon:getWidth() + pad
  end

  local textX = hx + headerIconInset
  local textWidth = math.max(0, hw - pad - headerIconInset)

  local font = love.graphics.getFont()
  local fh = (font and font:getHeight()) or 0
  local ty = math.floor(hy + (hh - fh) / 2)
  local startIdx, endIdx = TU.drawScrollingText(
    text,
    math.floor(textX),
    math.floor(ty),
    math.max(0, textWidth),
    { key = self }
  )

  self.headerStartIndex = startIdx
  self.headerEndIndex   = endIdx
end

function Window:drawBorder(isFocused)
  local x, y, w, h = self:getScreenRect()

  -- Border
  local focusColor = colors:focusedChromeColor()
  if isFocused then
    love.graphics.setColor(focusColor)
  else
    love.graphics.setColor(colors:chromeBackgroundUnfocused())
  end
  love.graphics.setLineWidth(1)
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

function Window:drawResizeHandle(isFocused, scaledMouse, neverShowResizeHandle)
  if self.resizable and isFocused and not self._collapsed then
    if neverShowResizeHandle == true then
      love.graphics.setColor(colors.white)
      return
    end
    local mx = scaledMouse and scaledMouse.x
    local my = scaledMouse and scaledMouse.y
    local hideHandle = self.resizing == true
    if not hideHandle and type(mx) == "number" and type(my) == "number" and self:mouseOnResizeHandle(mx, my) then
      hideHandle = true
    end
    if hideHandle then
      love.graphics.setColor(colors.white)
      return
    end

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
    else
      love.graphics.setColor(colors:focusedChromeColor())
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
  -- Appearance "Toolbar/menu text (default)" (muted chrome ink).
  local ink = colors:chromeTextIconsColorNonFocused()
  love.graphics.setColor(ink[1], ink[2], ink[3], self.scrollbarOpacity)

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
      yLine + separation - 2,
      thumbW,
      SCROLL_BAR_THICKNESS_PX
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
      xLine + separation - 2,
      thumbY,
      SCROLL_BAR_THICKNESS_PX,
      thumbH
    )
  end

  -- Reset color
  love.graphics.setColor(colors.white)
end

end
