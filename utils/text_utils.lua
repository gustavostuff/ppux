-- text-utils.lua
-- Pixel-friendly text: optional shadow and optional 8-direction black outline.
local Timer = require("utils.timer_utils")
local colors = require("app_colors")
local LoveCompat = require("utils.love_compat")

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
-- Marquee advances in pixels; `speed` is px/s (opts.speedPx overrides if set).
TU.CHROME_SCROLL_TEXT_OPTS = { speed = 52, pause = 1 }

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

-- LÖVE's font measurement expects well-formed UTF-8; truncation by raw byte
-- count (e.g. status ellipsis) can split code units and trigger decode errors.
local luaUtf8 = rawget(_G, "utf8")

local function longestValidUtf8Prefix(s)
  s = tostring(s or "")
  local n = #s
  local i = 1
  local last = 0
  while i <= n do
    local c1 = string.byte(s, i)
    if c1 < 0x80 then
      last = i
      i = i + 1
    elseif c1 < 0xC2 then
      break
    elseif c1 < 0xE0 then
      if i + 1 > n then
        break
      end
      local c2 = string.byte(s, i + 1)
      if c2 < 0x80 or c2 > 0xBF then
        break
      end
      last = i + 1
      i = i + 2
    elseif c1 < 0xF0 then
      if i + 2 > n then
        break
      end
      local c2, c3 = string.byte(s, i + 1, i + 2)
      if c1 == 0xE0 and c2 < 0xA0 then
        break
      end
      if c1 == 0xED and c2 > 0x9F then
        break
      end
      if c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF then
        break
      end
      last = i + 2
      i = i + 3
    elseif c1 < 0xF5 then
      if i + 3 > n then
        break
      end
      local c2, c3, c4 = string.byte(s, i + 1, i + 3)
      if c1 == 0xF0 and c2 < 0x90 then
        break
      end
      if c1 == 0xF4 and c2 > 0x8F then
        break
      end
      if c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF or c4 < 0x80 or c4 > 0xBF then
        break
      end
      last = i + 3
      i = i + 4
    else
      break
    end
  end
  return s:sub(1, last)
end

local function dropLastUtf8Codepoint(s)
  s = longestValidUtf8Prefix(tostring(s or ""))
  if s == "" then
    return ""
  end
  if luaUtf8 and type(luaUtf8.offset) == "function" then
    local ok, pos = pcall(function()
      return luaUtf8.offset(s, -1)
    end)
    if ok and type(pos) == "number" then
      if pos <= 1 then
        return ""
      end
      return longestValidUtf8Prefix(s:sub(1, pos - 1))
    end
  end
  return longestValidUtf8Prefix(s:sub(1, -2))
end

--- Safe for love.graphics.print / Font:getWidth: valid UTF-8, no split sequences.
function TU.sanitizeForLoveFont(s)
  return longestValidUtf8Prefix(s)
end

--- Prefer this over Font:getWidth when the string may be malformed UTF-8.
function TU.safeGetFontWidth(text, font)
  font = resolveFont(font)
  local safe = longestValidUtf8Prefix(text)
  local ok, w = pcall(function()
    return font:getWidth(safe)
  end)
  if ok and type(w) == "number" then
    return w
  end
  while #safe > 0 do
    safe = dropLastUtf8Codepoint(safe)
    ok, w = pcall(function()
      return font:getWidth(safe)
    end)
    if ok and type(w) == "number" then
      return w
    end
  end
  return 0
end

-- Shrink text with an optional suffix so measured width fits `maxWidth` without
-- splitting UTF-8 code units (avoids Font:getWidth decode errors).
function TU.fitTextToPixelWidth(text, maxWidth, font, ellipsis)
  text = longestValidUtf8Prefix(tostring(text or ""))
  ellipsis = tostring(ellipsis or "")
  maxWidth = tonumber(maxWidth) or 0
  font = resolveFont(font)
  if maxWidth <= 0 then
    return ""
  end
  if TU.safeGetFontWidth(text, font) <= maxWidth then
    return text
  end
  local ew = TU.safeGetFontWidth(ellipsis, font)
  if ew >= maxWidth then
    return ""
  end
  local trimmed = text
  while #trimmed > 0 do
    if TU.safeGetFontWidth(trimmed, font) + ew <= maxWidth then
      return trimmed .. ellipsis
    end
    trimmed = dropLastUtf8Codepoint(trimmed)
  end
  return ""
end

-- Clip to marquee viewport (`width` px wide), intersecting current scissor if any.
local function withMarqueeClip(x, y, width, fh, drawFn)
  local g = love and love.graphics
  if not (g and type(drawFn) == "function") then
    drawFn()
    return
  end
  local padY = math.max(6, fh + 2)
  local clipX = math.floor(x + 1e-6)
  local clipY = math.floor(y + 1e-6 - 4)
  local clipW = math.ceil(math.max(tonumber(width) or 0, 1))
  local clipH = math.ceil(math.max(padY, 1))

  love.graphics.push("all")
  if g.intersectScissor then
    g.intersectScissor(clipX, clipY, clipW, clipH)
  else
    g.setScissor(clipX, clipY, clipW, clipH)
  end
  local ok, err = pcall(drawFn)
  love.graphics.pop()
  if not ok then
    error(err, 2)
  end
end

function TU.drawScrollingText(text, x, y, width, opts)
  opts = opts or {}
  local defs = TU.CHROME_SCROLL_TEXT_OPTS or { speed = 52, pause = 1 }
  local pause = opts.pause or defs.pause
  local speedPxSec = tonumber(opts.speedPx) or tonumber(opts.speed or defs.speed) or 52
  speedPxSec = math.max(speedPxSec, 1e-3)
  local key = opts.key or text -- unique id per header
  local loop = opts.loop == true
  text = longestValidUtf8Prefix(tostring(text or ""))
  width = tonumber(width) or 0
  local font = resolveFont()

  if width <= 0 then
    scrollingState[key] = nil
    return 1, 0
  end

  if not text or text == "" then
    scrollingState[key] = nil
    return 1, 0
  end

  local len = #text
  local tw = TU.safeGetFontWidth(text, font)

  -- Whole line fits: no scrolling.
  if tw <= width then
    rawPrint(text, math.floor(x + 1e-6), y)
    scrollingState[key] = nil
    return 1, len
  end

  local scrollMaxPx = tw - width
  local fh = math.max(font:getHeight() or 12, 1)
  local now = LoveCompat.getTime()
  local mark = "scroll_" .. tostring(key)

  local st = scrollingState[key]
  if st and (st.pixelMarquee ~= true or type(st.scrollPx) ~= "number" or st.pos ~= nil) then
    scrollingState[key] = nil
    st = nil
  end

  if not st then
    st = {
      scrollPx = 0,
      dir = 1,
      mode = "pause",
      mark = mark,
      text = text,
      layoutWidth = width,
      loop = loop,
      lastT = now,
      pixelMarquee = true,
    }
    scrollingState[key] = st
    Timer.mark(mark)
    st.lastT = now or 0
  else
    if st.text ~= text or st.layoutWidth ~= width or st.loop ~= loop then
      st.scrollPx = 0
      st.dir = 1
      st.mode = "pause"
      st.text = text
      st.layoutWidth = width
      st.loop = loop
      Timer.mark(mark)
      st.lastT = now or st.lastT or 0
    end
    st.mark = mark
    if type(st.scrollPx) ~= "number" then st.scrollPx = 0 end
    if st.scrollPx > scrollMaxPx then st.scrollPx = scrollMaxPx end
    if st.scrollPx < 0 then st.scrollPx = 0 end
  end

  local elapsedPause = Timer.elapsed(mark) or 0

  if st.mode == "pause" then
    if elapsedPause >= pause then
      st.mode = "move"
      st.lastT = now or 0
    end
  else
    local t1 = now
    local t0 = st.lastT or t1 or 0
    local dt = (t1 and t1 - t0) or 0
    if dt < 0 then dt = 0 end
    dt = math.min(dt, 0.25)
    st.lastT = t1 or t0

    if st.loop then
      st.scrollPx = st.scrollPx + speedPxSec * dt
      if scrollMaxPx > 0 and st.scrollPx >= scrollMaxPx then
        -- Continuous loop: normalize offset; discrete wrap matched old checkbox loop.
        st.scrollPx = st.scrollPx % scrollMaxPx
        if pause > 0 then
          st.mode = "pause"
          Timer.mark(mark)
        end
      end
    else
      st.scrollPx = st.scrollPx + st.dir * speedPxSec * dt
      if st.scrollPx <= 0 then
        st.scrollPx = 0
        st.dir = 1
        st.mode = "pause"
        Timer.mark(mark)
      elseif st.scrollPx >= scrollMaxPx then
        st.scrollPx = scrollMaxPx
        st.dir = -1
        st.mode = "pause"
        Timer.mark(mark)
      end
    end
  end

  local drawX = math.floor(x + 1e-6 - st.scrollPx)
  local drawY = y
  withMarqueeClip(x, drawY, width, fh, function()
    rawPrint(text, drawX, drawY)
  end)

  return 1, len
end

function TU.drawScrollingHeader(text, x, y, width, opts)
  return TU.drawScrollingText(text, x, y, width, opts)
end

return TU
