-- Horizontal tab strip for modals (mouse-only switching for now).
-- With chromeOverBlue, tab labels only: panel paints active tab + content + footer as one "normal"
-- chrome surface (see panel rendering._tabbedModalChrome).
local colors = require("app_colors")
local Text = require("utils.text_utils")

local M = {}
M.__index = M

local PAD_X = 6
local GAP = 0
local IDLE_ALPHA = 0.42
local HOVER_ALPHA = 0.72

function M.new(opts)
  opts = opts or {}
  return setmetatable({
    tabs = opts.tabs or {},
    activeId = opts.activeId,
    onSelect = opts.onSelect,
    chromeOverBlue = opts.chromeOverBlue == true,
    x = 0,
    y = 0,
    w = 0,
    h = 0,
    _hoverIndex = nil,
  }, M)
end

function M:setActiveId(id)
  self.activeId = id
end

function M:setPosition(x, y)
  self.x = x or 0
  self.y = y or 0
end

function M:setSize(w, h)
  self.w = w or 0
  self.h = h or 0
end

function M:_font()
  return love.graphics.getFont()
end

function M:_segmentBounds(i)
  local n = #(self.tabs or {})
  if n <= 0 or i < 1 or i > n then
    return self.x, self.y, 0, self.h
  end
  local font = self:_font()
  local x = self.x
  for j = 1, i do
    local tab = self.tabs[j]
    local label = tab and tab.label or ""
    local tw = (font and font:getWidth(label) or 0) + PAD_X * 2
    if j == i then
      return x, self.y, tw, self.h
    end
    x = x + tw + GAP
  end
  return self.x, self.y, 0, self.h
end

--- Screen-space bounds (x, y, w, h) of the active tab label area, or nil.
function M:getActiveSegmentBounds()
  for i = 1, #(self.tabs or {}) do
    local t = self.tabs[i]
    if t and t.id == self.activeId then
      return self:_segmentBounds(i)
    end
  end
  return nil
end

function M:_hitSegment(px, py)
  local n = #(self.tabs or {})
  if n <= 0 then
    return nil
  end
  if py < self.y or py >= self.y + self.h then
    return nil
  end
  for i = 1, n do
    local sx, sy, sw, sh = self:_segmentBounds(i)
    if px >= sx and px < sx + sw then
      return i
    end
  end
  return nil
end

function M:contains(px, py)
  return self:_hitSegment(px, py) ~= nil
end

function M:mousemoved(px, py)
  self._hoverIndex = self:_hitSegment(px, py)
end

function M:mousepressed(px, py, button)
  if button ~= 1 then
    return false
  end
  local i = self:_hitSegment(px, py)
  if not i then
    return false
  end
  local tab = self.tabs[i]
  if tab and tab.id and tab.id ~= self.activeId then
    self.activeId = tab.id
    if self.onSelect then
      self.onSelect(tab.id)
    end
  end
  return true
end

function M:draw()
  local n = #(self.tabs or {})
  if n <= 0 or self.h <= 0 then
    return
  end

  local font = self:_font()
  local textH = font and font:getHeight() or self.h
  local idleRgb = self.chromeOverBlue and colors:chromeTextIconsColorNonFocused()
    or (colors.textPrimary or colors.white)
  local hotRgb = self.chromeOverBlue and colors:chromeTextIconsColorFocused()
    or (colors.textPrimary or colors.white)

  for i = 1, n do
    local sx, sy, sw, sh = self:_segmentBounds(i)
    local tab = self.tabs[i]
    local active = tab and tab.id == self.activeId
    local hover = (self._hoverIndex == i)
    local label = tab and tab.label or ""
    local tx = sx + PAD_X
    local ty = sy + math.floor((sh - textH) * 0.5)

    local c = idleRgb
    local a = 1.0
    if self.chromeOverBlue then
      if active then
        c = hotRgb
        a = 1.0
      elseif hover then
        c = hotRgb
        a = HOVER_ALPHA
      else
        c = idleRgb
        a = 1.0
      end
    else
      if not active then
        a = hover and HOVER_ALPHA or IDLE_ALPHA
      end
    end

    Text.print(label, tx, ty, {
      shadowColor = colors.transparent,
      color = { c[1], c[2], c[3], (c[4] or 1) * a },
      literalColor = self.chromeOverBlue == true,
    })
  end
  love.graphics.setColor(colors.white)
end

return M
