-- gallery_slide_thumb_strip.lua
-- Horizontal scrollable strip of gallery-slide thumbnails with drag-to-reorder.

local colors = require("app_colors")
local GalleryThumb = require("controllers.game_art.sketch_canvas_gallery_thumb_controller")

local Strip = {}
Strip.__index = Strip

local THUMB_W = GalleryThumb.THUMB_W
local THUMB_H = GalleryThumb.THUMB_H
local GAP = 4
local PAD = 0
local DRAG_THRESHOLD = 3
local SCROLLBAR_H = 1
local SCROLL_BAR_OPACITY_TIME = 1.5

local function clamp(v, lo, hi)
  if v < lo then
    return lo
  end
  if v > hi then
    return hi
  end
  return v
end

function Strip.new(opts)
  opts = opts or {}
  local self = setmetatable({
    x = 0,
    y = 0,
    w = opts.w or 200,
    h = opts.h or (THUMB_H + SCROLLBAR_H + 2),
    entries = {},
    scrollX = 0,
    hoveredIndex = nil,
    drag = nil,
    enabled = true,
    scrollbarOpacity = 0,
  }, Strip)
  return self
end

function Strip:setPosition(x, y)
  self.x = math.floor(tonumber(x) or 0)
  self.y = math.floor(tonumber(y) or 0)
end

function Strip:setSize(w, h)
  if type(w) == "number" then
    self.w = math.max(1, math.floor(w))
  end
  if type(h) == "number" then
    self.h = math.max(1, math.floor(h))
  end
  self:_clampScroll()
end

function Strip:setEntries(entries)
  self.entries = type(entries) == "table" and entries or {}
  self.scrollX = 0
  self.hoveredIndex = nil
  self.drag = nil
  self.scrollbarOpacity = 0
  self:_clampScroll()
end

function Strip:getOrderedSketches()
  local out = {}
  for i = 1, #self.entries do
    local e = self.entries[i]
    if e and e.sketch then
      out[#out + 1] = e.sketch
    end
  end
  return out
end

function Strip:contains(px, py)
  return px >= self.x and px <= self.x + self.w
    and py >= self.y and py <= self.y + self.h
end

function Strip:_contentWidth()
  local n = #self.entries
  if n < 1 then
    return 0
  end
  return PAD * 2 + n * THUMB_W + math.max(0, n - 1) * GAP
end

function Strip:_maxScroll()
  return math.max(0, self:_contentWidth() - self.w)
end

function Strip:_clampScroll()
  self.scrollX = clamp(math.floor(tonumber(self.scrollX) or 0), 0, self:_maxScroll())
end

function Strip:_bumpScrollbar()
  self.scrollbarOpacity = SCROLL_BAR_OPACITY_TIME
end

function Strip:_thumbRect(index)
  local x = self.x + PAD + (index - 1) * (THUMB_W + GAP) - self.scrollX
  -- Top-align thumbs; leave room for the 1px scrollbar at the bottom of the cell.
  local y = self.y
  return x, y, THUMB_W, THUMB_H
end

function Strip:_indexAt(px, py)
  if not self:contains(px, py) then
    return nil
  end
  for i = 1, #self.entries do
    local tx, ty, tw, th = self:_thumbRect(i)
    if px >= tx and px < tx + tw and py >= ty and py < ty + th then
      return i
    end
  end
  return nil
end

function Strip:_moveEntry(fromIdx, toIdx)
  fromIdx = math.floor(tonumber(fromIdx) or 0)
  toIdx = math.floor(tonumber(toIdx) or 0)
  if fromIdx < 1 or fromIdx > #self.entries then
    return false
  end
  if toIdx < 1 or toIdx > #self.entries then
    return false
  end
  if fromIdx == toIdx then
    return false
  end
  local entry = table.remove(self.entries, fromIdx)
  table.insert(self.entries, toIdx, entry)
  return true
end

function Strip:getTooltipAt(px, py)
  local idx = self:_indexAt(px, py)
  if not idx then
    return nil
  end
  local entry = self.entries[idx]
  if not entry or not entry.title or entry.title == "" then
    return nil
  end
  return {
    text = entry.title,
    immediate = false,
    key = entry,
  }
end

function Strip:mousepressed(x, y, button)
  if self.enabled == false or button ~= 1 then
    return false
  end
  if not self:contains(x, y) then
    return false
  end
  local idx = self:_indexAt(x, y)
  self.drag = {
    index = idx,
    startX = x,
    startY = y,
    active = false,
    reordered = false,
  }
  return true
end

function Strip:mousemoved(x, y)
  self.hoveredIndex = self:_indexAt(x, y)
  local drag = self.drag
  if not (drag and drag.index) then
    return
  end
  local moved = math.abs(x - (drag.startX or 0)) + math.abs(y - (drag.startY or 0))
  if moved >= DRAG_THRESHOLD then
    drag.active = true
  end
  if not drag.active then
    return
  end
  local over = self:_indexAt(x, y)
  if over and over ~= drag.index then
    if self:_moveEntry(drag.index, over) then
      drag.index = over
      drag.reordered = true
      self.hoveredIndex = over
    end
  end
end

function Strip:mousereleased(_x, _y, button)
  if button ~= 1 then
    return false
  end
  local had = self.drag ~= nil
  self.drag = nil
  return had
end

function Strip:wheelmoved(dx, dy)
  local delta = 0
  if type(dx) == "number" and dx ~= 0 then
    delta = -dx * (THUMB_W + GAP)
  elseif type(dy) == "number" and dy ~= 0 then
    delta = -dy * (THUMB_W + GAP)
  end
  if delta == 0 then
    return false
  end
  local before = self.scrollX
  self.scrollX = self.scrollX + delta
  self:_clampScroll()
  if self:_maxScroll() > 0 then
    self:_bumpScrollbar()
  end
  return self.scrollX ~= before or self:_maxScroll() > 0
end

function Strip:wheelmovedAt(dx, dy, px, py)
  if not self:contains(px, py) then
    return false
  end
  return self:wheelmoved(dx, dy)
end

function Strip:update(dt)
  if type(dt) ~= "number" then
    return
  end
  -- Same fade rate as window scrollbars (opacity units per second ≈ 1/3 of peak time).
  self.scrollbarOpacity = math.max(0.0, math.min(SCROLL_BAR_OPACITY_TIME, (self.scrollbarOpacity or 0) - dt / 3))
end

function Strip:draw()
  local x = math.floor(self.x)
  local y = math.floor(self.y)
  local w = math.floor(self.w)
  local h = math.floor(self.h)
  if w <= 0 or h <= 0 then
    return
  end

  love.graphics.setScissor(x, y, w, h)

  local dragIdx = self.drag and self.drag.active and self.drag.index or nil

  for i = 1, #self.entries do
    local entry = self.entries[i]
    local tx, ty, tw, th = self:_thumbRect(i)
    if tx + tw >= x and tx <= x + w then
      if entry and entry.image then
        love.graphics.setColor(1, 1, 1, (dragIdx == i) and 0.85 or 1)
        love.graphics.draw(entry.image, tx, ty)
      else
        love.graphics.setColor(0.15, 0.15, 0.15, 1)
        love.graphics.rectangle("fill", tx, ty, tw, th)
      end
    end
  end

  love.graphics.setScissor()

  local maxScroll = self:_maxScroll()
  local opacity = tonumber(self.scrollbarOpacity) or 0
  if maxScroll > 0 and opacity > 0.01 then
    local ink = colors:chromeTextIconsColorNonFocused()
    local trackY = y + h - SCROLLBAR_H
    local trackW = math.max(1, w)
    local trackX = x
    local thumbW = math.max(8, math.floor(trackW * (w / math.max(w, self:_contentWidth()))))
    local travel = math.max(0, trackW - thumbW)
    local thumbX = trackX + math.floor(travel * (self.scrollX / maxScroll))
    love.graphics.setColor(ink[1], ink[2], ink[3], opacity)
    love.graphics.rectangle("fill", thumbX, trackY, thumbW, SCROLLBAR_H)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return Strip
