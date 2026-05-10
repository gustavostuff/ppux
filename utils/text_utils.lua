-- text-utils.lua
-- Pixel-friendly text: optional shadow and optional 8-direction black outline.
local Timer = require("utils.timer_utils")
local colors = require("app_colors")

local TU = {}

-- Unit tests sometimes load this module without a full LOVE graphics backend.
local FONT_FALLBACK_ADVANCE_X = 8
local FONT_FALLBACK_LINE_H = 12

local fallbackFont = {
  getWidth = function(self, s)
    return #tostring(s or "") * FONT_FALLBACK_ADVANCE_X
  end,
  getHeight = function(self)
    return FONT_FALLBACK_LINE_H
  end,
}

local function resolveDefaultFont()
  local g = love and love.graphics
  if not (g and type(g.getFont) == "function") then
    return nil
  end
  local ok, f = pcall(function()
    return g.getFont()
  end)
  if ok and f and type(f.getWidth) == "function" and type(f.getHeight) == "function" then
    return f
  end
  return nil
end

local function resolveFont(font)
  if font and type(font.getWidth) == "function" and type(font.getHeight) == "function" then
    return font
  end
  font = resolveDefaultFont()
  if font then
    return font
  end
  return fallbackFont
end

-- literalColor: when true, do not remap near-white to textPrimary (e.g. white on blue modal chrome).
local function setColor(c, literalColor)
  local fallback = colors.textPrimary or colors.gray10 or colors.white
  if type(c) == "table" then
    local r = c[1] or 1
    local g = c[2] or 1
    local b = c[3] or 1
    local a = c[4] or 1
    if literalColor ~= true and r >= 0.95 and g >= 0.95 and b >= 0.95 then
      love.graphics.setColor(fallback[1], fallback[2], fallback[3], a)
      return
    end
    love.graphics.setColor(r, g, b, a)
  else
    love.graphics.setColor(fallback[1], fallback[2], fallback[3], fallback[4] or 1)
  end
end

local function getCanvasSize(optCanvas)
  if optCanvas then
    return optCanvas:getWidth(), optCanvas:getHeight()
  else
    return love.graphics.getWidth(), love.graphics.getHeight()
  end
end

-- Measure a single line or a table of lines; returns (w,h,lh,count)
local function measureBlock(text, font, lineHeight)
  font = resolveFont(font)
  local lh = lineHeight or font:getHeight()
  if type(text) == "table" then
    local wmax = 0
    for i = 1, #text do
      local w = font:getWidth(text[i] or "")
      if w > wmax then wmax = w end
    end
    return wmax, (#text) * lh, lh, #text
  else
    return font:getWidth(text or ""), lh, lh, 1
  end
end

local function getCharWidth(font)
  font = resolveFont(font)
  -- Monospace font: any glyph should be representative
  return font:getWidth("M")
end

-- Single low-level Love2D text draw primitive.
local function rawPrint(text, x, y)
  local EXTRA_Y = -1
  love.graphics.print(text or "", x, y + EXTRA_Y)
end

local function rawPrintBlock(text, x, y, lineHeight)
  if type(text) == "table" then
    for i = 1, #text do
      rawPrint(text[i] or "", x, y + (i - 1) * lineHeight)
    end
    return
  end
  rawPrint(text or "", x, y)
end

-- Core: prints with optional shadow and optional outline.
local function printCore(text, x, y, data)
  data = data or {}
  local literalColor = data.literalColor == true
  local font        = resolveFont(data.font)
  local color       = data.color or colors.textPrimary or colors.white
  local shadowColor = data.shadowColor or colors.black
  local shadow      = data.shadow == true
  local dx          = (data.dx ~= nil) and data.dx or 1  -- shadow offset X
  local dy          = (data.dy ~= nil) and data.dy or 1  -- shadow offset Y
  local outline     = data.outline == true
  local ox          = data.ox or 1  -- outline offsets (usually 1 px)
  local oy          = data.oy or 1

  local gGfx = love and love.graphics
  local oldFont = nil
  if gGfx and type(gGfx.getFont) == "function" then
    oldFont = gGfx.getFont()
  end
  if gGfx and type(gGfx.setFont) == "function" and font ~= oldFont then
    gGfx.setFont(font)
  end

  local w, h, lh, n = measureBlock(text, font, data.lineHeight)

  if outline then
    -- 8-direction black outline
    setColor(colors.black)
    local dirs = {
      {-ox, 0}, { ox, 0}, {0, -oy}, {0,  oy},
      {-ox,-oy},{ ox,-oy},{-ox, oy},{ ox, oy},
    }
    if type(text) == "table" then
      for i=1,n do
        local yy = y + (i-1)*lh
        for d=1,#dirs do
          local vx, vy = dirs[d][1], dirs[d][2]
          rawPrint(text[i] or "", x + vx, yy + vy)
        end
      end
    else
      for d=1,#dirs do
        local vx, vy = dirs[d][1], dirs[d][2]
        rawPrint(text or "", x + vx, y + vy)
      end
    end
  elseif shadow then
    -- bottom-right shadow
    setColor(shadowColor)
    if type(text) == "table" then
      for i=1,n do
        rawPrint(text[i] or "", x + dx, y + dy + (i - 1) * lh)
      end
    else
      rawPrint(text or "", x + dx, y + dy)
    end
  end

  -- main fill
  setColor(color, literalColor)
  rawPrintBlock(text, x, y, lh)

  if font ~= oldFont then
    if gGfx and type(gGfx.setFont) == "function" then
      gGfx.setFont(oldFont)
    end
  end
end

-- Public API ---------------------------------------------------------------

function TU.print(text, x, y, data)
  printCore(text, x, y, data)
end

function TU.printCenter(text, data)
  data = data or {}
  local font = resolveFont(data.font)
  local W, H = getCanvasSize(data.canvas)
  local w, h = measureBlock(text, font, data.lineHeight)
  local x = math.floor((W - w) / 2)
  local y = math.floor((H - h) / 2)
  printCore(text, x, y, data)
end

function TU.printTopLeft(text, data)
  data = data or {}
  local m = (data.margin ~= nil) and data.margin or 8
  printCore(text, m, m, data)
end

function TU.printTopRight(text, data)
  data = data or {}
  local font = resolveFont(data.font)
  local W, _ = getCanvasSize(data.canvas)
  local m = (data.margin ~= nil) and data.margin or 8
  local w = select(1, measureBlock(text, font, data.lineHeight))
  printCore(text, math.floor(W - w - m), m, data)
end

function TU.printBottomLeft(text, data)
  data = data or {}
  local font = resolveFont(data.font)
  local _, H = getCanvasSize(data.canvas)
  local m = (data.margin ~= nil) and data.margin or 8
  local _, h = measureBlock(text, font, data.lineHeight)
  printCore(text, m, math.floor(H - h - m), data)
end

function TU.printBottomRight(text, data)
  data = data or {}
  local font = resolveFont(data.font)
  local W, H = getCanvasSize(data.canvas)
  local m = (data.margin ~= nil) and data.margin or 8
  local w, h = measureBlock(text, font, data.lineHeight)
  printCore(text, math.floor(W - w - m), math.floor(H - h - m), data)
end

-- Optional: quick measure
function TU.measure(text, data)
  data = data or {}
  return measureBlock(text, data.font, data.lineHeight)
end

function TU.getFontWidth(text, font)
  font = resolveFont(font)
  return font:getWidth(text or "")
end

function TU.getFontHeight(font)
  font = resolveFont(font)
  return font:getHeight()
end

local scrollingState = scrollingState or {}

-- Defaults for `drawScrollingText`: window chrome titles, app status strip, modal path labels.
TU.CHROME_SCROLL_TEXT_OPTS = { speed = 8, pause = 1 }

function TU.limitChars(text, maxChars, opts)
  text = tostring(text or "")
  if type(maxChars) ~= "number" then
    return text
  end

  maxChars = math.floor(maxChars)
  if maxChars <= 0 then
    return ""
  end

  if #text <= maxChars then
    return text
  end

  opts = opts or {}
  local suffix = tostring(opts.suffix or "")
  if suffix == "" then
    return text:sub(1, maxChars)
  end

  if #suffix >= maxChars then
    return text:sub(1, maxChars)
  end

  return text:sub(1, maxChars - #suffix) .. suffix
end

-- Largest end index `e >= s` such that text:sub(s, e) fits in `width` (pixel width).
local function scrollingMaxEndIndex(text, font, len, s, width)
  if s > len then
    return len
  end
  local best = s - 1
  for k = s, len do
    if font:getWidth(text:sub(s, k)) <= width then
      best = k
    else
      break
    end
  end
  if best < s then
    return s
  end
  return best
end

-- Smallest start index `s` such that the tail text:sub(s, len) fits in `width`.
local function scrollingLastStartIndex(text, font, len, width)
  for s = 1, len do
    if font:getWidth(text:sub(s, len)) <= width then
      return s
    end
  end
  return len
end

function TU.drawScrollingText(text, x, y, width, opts)
  opts = opts or {}
  local defs = TU.CHROME_SCROLL_TEXT_OPTS or { speed = 8, pause = 1 }
  local charsPerSecond = opts.speed or defs.speed
  local pause = opts.pause or defs.pause
  local key = opts.key or text -- unique id per header
  local loop = opts.loop == true
  text = tostring(text or "")
  width = tonumber(width) or 0

  if width <= 0 then
    scrollingState[key] = nil
    return 1, 0
  end

  if not text or text == "" then
    scrollingState[key] = nil
    return 1, 0
  end

  local font = resolveFont()
  local len = #text

  -- Whole line fits: no scrolling (width must be measured, not character counts — proportional fonts).
  if font:getWidth(text) <= width then
    rawPrint(text, x, y)
    scrollingState[key] = nil
    return 1, len
  end

  -- Scroll range: start index runs from 1 to lastStart where the tail from lastStart fits.
  local lastStart = scrollingLastStartIndex(text, font, len, width)
  local range = math.max(0, lastStart - 1)

  local st = scrollingState[key]
  if not st then
    st = {
      pos = 0,
      dir = 1,
      mode = "pause",
      mark = "scroll_" .. tostring(key),
      range = range,
      text = text,
      layoutWidth = width,
      loop = loop,
    }
    scrollingState[key] = st
    Timer.mark(st.mark)
  else
    if st.text ~= text or st.layoutWidth ~= width or st.loop ~= loop then
      st.pos = 0
      st.dir = 1
      st.mode = "pause"
      st.text = text
      st.layoutWidth = width
      st.loop = loop
      Timer.mark(st.mark)
    end
    st.range = range
    if st.pos > range then
      st.pos = range
    end
  end

  local stepDelay = 1 / charsPerSecond
  local elapsed = Timer.elapsed(st.mark) or 0

  if st.mode == "pause" then
    if elapsed >= pause then
      st.mode = "move"
      Timer.mark(st.mark)
    end
  else -- "move"
    if elapsed >= stepDelay then
      if st.loop then
        st.pos = st.pos + 1
        if st.pos > range then
          st.pos = 0
          if pause > 0 then
            st.mode = "pause"
          end
        end
      else
        st.pos = st.pos + st.dir

        if st.pos <= 0 then
          st.pos = 0
          st.dir = 1
          st.mode = "pause"
        elseif st.pos >= range then
          st.pos = range
          st.dir = -1
          st.mode = "pause"
        end
      end

      Timer.mark(st.mark)
    end
  end

  local startIdx = 1 + st.pos
  local endIdx = scrollingMaxEndIndex(text, font, len, startIdx, width)
  local visible = text:sub(startIdx, endIdx)
  -- Guard against float/rounding or font quirks: never draw wider than the viewport.
  while #visible > 1 and font:getWidth(visible) > width do
    visible = visible:sub(1, -2)
  end

  rawPrint(visible, x, y)

  local outEnd = startIdx + math.max(0, #visible) - 1
  return startIdx, outEnd
end

function TU.drawScrollingHeader(text, x, y, width, opts)
  return TU.drawScrollingText(text, x, y, width, opts)
end

return TU
