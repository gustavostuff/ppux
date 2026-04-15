-- text-utils.lua
-- Pixel-friendly text: optional shadow and optional 8-direction black outline.
local Timer = require("utils.timer_utils")
local colors = require("app_colors")

local TU = {}

local function setColor(c)
  if type(c) == "table" then
    love.graphics.setColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
  else
    love.graphics.setColor(colors.white)
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
  font = font or love.graphics.getFont()
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
  font = font or love.graphics.getFont()
  if not font then
    return 8 -- safe fallback
  end
  -- Monospace font: any glyph should be representative
  return font:getWidth("M")
end

-- Single low-level Love2D text draw primitive.
local function rawPrint(text, x, y)
  local EXTRA_Y = 1
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
  local font        = data.font or love.graphics.getFont()
  local color       = data.color or colors.white
  local shadowColor = data.shadowColor or colors.black
  local shadow      = data.shadow == true
  local dx          = (data.dx ~= nil) and data.dx or 1  -- shadow offset X
  local dy          = (data.dy ~= nil) and data.dy or 1  -- shadow offset Y
  local outline     = data.outline == true
  local ox          = data.ox or 1  -- outline offsets (usually 1 px)
  local oy          = data.oy or 1

  local oldFont = love.graphics.getFont()
  if font ~= oldFont then love.graphics.setFont(font) end

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
  setColor(color)
  rawPrintBlock(text, x, y, lh)

  if font ~= oldFont then love.graphics.setFont(oldFont) end
end

-- Public API ---------------------------------------------------------------

function TU.print(text, x, y, data)
  printCore(text, x, y, data)
end

function TU.printCenter(text, data)
  data = data or {}
  local font = data.font or love.graphics.getFont()
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
  local font = data.font or love.graphics.getFont()
  local W, _ = getCanvasSize(data.canvas)
  local m = (data.margin ~= nil) and data.margin or 8
  local w = select(1, measureBlock(text, font, data.lineHeight))
  printCore(text, math.floor(W - w - m), m, data)
end

function TU.printBottomLeft(text, data)
  data = data or {}
  local font = data.font or love.graphics.getFont()
  local _, H = getCanvasSize(data.canvas)
  local m = (data.margin ~= nil) and data.margin or 8
  local _, h = measureBlock(text, font, data.lineHeight)
  printCore(text, m, math.floor(H - h - m), data)
end

function TU.printBottomRight(text, data)
  data = data or {}
  local font = data.font or love.graphics.getFont()
  local W, H = getCanvasSize(data.canvas)
  local m = (data.margin ~= nil) and data.margin or 8
  local w, h = measureBlock(text, font, data.lineHeight)
  printCore(text, math.floor(W - w - m), math.floor(H - h - m), data)
end

-- Optional: quick measure
function TU.measure(text, data)
  data = data or {}
  return measureBlock(text, data.font or love.graphics.getFont(), data.lineHeight)
end

function TU.getFontWidth(text, font)
  font = font or love.graphics.getFont()
  return font:getWidth(text or "")
end

function TU.getFontHeight(font)
  return font:getHeight()
end

local scrollingState = scrollingState or {}

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

function TU.drawScrollingText(text, x, y, width, opts)
  opts  = opts or {}
  local charsPerSecond = opts.speed or 8      -- chars per second
  local pause          = opts.pause or 0.75   -- seconds at each end
  local key            = opts.key or text     -- unique id per header
  local loop           = opts.loop == true
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

  local font = love.graphics.getFont()
  local len  = #text

  -- how many characters fit in the header width?
  local maxChars = len
  while maxChars > 0 do
    local sub = text:sub(1, maxChars)
    if font:getWidth(sub) <= width then
      break
    end
    maxChars = maxChars - 1
  end

  if maxChars <= 0 then
    maxChars = 1
  end

  -- fits completely: no scrolling
  if len <= maxChars then
    rawPrint(text, x, y)
    scrollingState[key] = nil
    return 1, len
  end

  local range = len - maxChars        -- 0..range are valid start positions
  local st = scrollingState[key]
  if not st then
    st = {
      pos  = 0,                       -- 0..range
      dir  = 1,                       -- 1 = forward, -1 = backward
      mode = "pause",                 -- "pause" or "move"
      mark = "scroll_" .. tostring(key),
      range = range,
      text = text,
      maxChars = maxChars,
      loop = loop,
    }
    scrollingState[key] = st
    Timer.mark(st.mark)
  else
    if st.text ~= text or st.maxChars ~= maxChars or st.loop ~= loop then
      st.pos = 0
      st.dir = 1
      st.mode = "pause"
      st.text = text
      st.maxChars = maxChars
      st.loop = loop
      Timer.mark(st.mark)
    end

    -- clamp if text/width changed
    st.range = range
    if st.pos > range then
      st.pos = range
    end
  end

  local stepDelay = 1 / charsPerSecond
  local elapsed   = Timer.elapsed(st.mark) or 0

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
  local endIdx   = startIdx + maxChars - 1
  if endIdx > len then endIdx = len end

  local visible = text:sub(startIdx, endIdx)
  rawPrint(visible, x, y)

  return startIdx, endIdx
end

function TU.drawScrollingHeader(text, x, y, width, opts)
  return TU.drawScrollingText(text, x, y, width, opts)
end

return TU
