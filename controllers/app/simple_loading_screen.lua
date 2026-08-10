local colors = require("app_colors")
local Text = require("utils.text_utils")
local LoveCompat = require("utils.love_compat")

local M = {}
local ENABLE_LOADING_PRESENT_DELAY = true
local LOADING_PRESENT_DELAY_SECONDS = 0.1
local LOADING_LABEL_FONT_SIZE = 32
local fallbackCanvas = nil
local loadingFont = nil
local DISABLE_LOADING_SCREEN_FLAG = "__PPUX_DISABLE_LOADING_SCREEN__"

local BAR_TRACK_W = 160
local BAR_SEGMENT_W = 52
local BAR_H = 4
local BAR_GAP_BELOW_TEXT = 14
local BAR_SLIDE_SPEED = 2.0

local function loadingScreenDisabled()
  return rawget(_G, DISABLE_LOADING_SCREEN_FLAG) == true
end

local function getLoadingFont(app)
  if loadingFont then
    return loadingFont
  end

  if not (love and love.graphics and love.graphics.newFont) then
    return nil
  end

  local UiFont = require("ui.ui_font")
  local font = UiFont.load(LOADING_LABEL_FONT_SIZE)
  if font then
    font:setFilter("nearest", "nearest")
    loadingFont = font
    return loadingFont
  end

  loadingFont = love.graphics.newFont(LOADING_LABEL_FONT_SIZE)
  loadingFont:setFilter("nearest", "nearest")
  return loadingFont
end

local function ensureFallbackCanvas(w, h)
  if not (love and love.graphics and love.graphics.newCanvas) then
    return nil
  end
  if fallbackCanvas
    and fallbackCanvas:getWidth() == w
    and fallbackCanvas:getHeight() == h then
    return fallbackCanvas
  end

  fallbackCanvas = love.graphics.newCanvas(w, h)
  fallbackCanvas:setFilter("nearest", "nearest")
  return fallbackCanvas
end

local function drawIndeterminateBar(cx, trackY, bg, trackW, segmentW, barH)
  trackW = trackW or BAR_TRACK_W
  segmentW = segmentW or BAR_SEGMENT_W
  barH = barH or BAR_H
  local trackX = math.floor(cx - trackW * 0.5)
  trackY = math.floor(trackY)
  local t = LoveCompat.getTime()
  local phase = (math.sin(t * BAR_SLIDE_SPEED) + 1) * 0.5
  local maxSlide = math.max(0, trackW - segmentW)
  local barX = trackX + phase * maxSlide

  love.graphics.setColor(bg[1] * 0.45 + 0.12, bg[2] * 0.45 + 0.12, bg[3] * 0.45 + 0.12, 1)
  love.graphics.rectangle("fill", trackX, trackY, trackW, barH)
  love.graphics.setColor(colors.white)
  love.graphics.rectangle("fill", barX, trackY, segmentW, barH)
end

local function drawLoadingPattern(cw, ch, message, font)
  local cx = math.floor(cw * 0.5)

  local bg = colors:appWorkspaceFill()
  love.graphics.clear(bg[1], bg[2], bg[3], 1)

  if font then
    love.graphics.setFont(font)
  end
  local label = message or "Loading..."
  local textW = select(1, Text.measure(label, { font = font }))
  local textX = math.floor((cw - textW) * 0.5)

  local textH = LOADING_LABEL_FONT_SIZE
  if font and font.getHeight then
    textH = font:getHeight()
  end
  local blockH = textH + BAR_GAP_BELOW_TEXT + BAR_H
  local textY = math.floor((ch - blockH) * 0.5)
  Text.print(label, textX, textY, { font = font, color = colors.white })

  local textBottom = textY + textH
  drawIndeterminateBar(cx, textBottom + BAR_GAP_BELOW_TEXT, bg, BAR_TRACK_W, BAR_SEGMENT_W, BAR_H)
end

local function renderLoadingPatternToCanvas(canvas, message, font)
  love.graphics.setCanvas(canvas)
  drawLoadingPattern(canvas:getWidth(), canvas:getHeight(), message, font)
  love.graphics.setCanvas()
end

function M.present(message, app)
  if loadingScreenDisabled() then
    return true
  end

  if not (love and love.graphics and love.graphics.isActive and love.graphics.isActive()) then
    return false
  end

  local label = message or "Loading..."
  love.graphics.push("all")
  love.graphics.origin()
  local bg = colors:appWorkspaceFill()
  love.graphics.clear(bg[1], bg[2], bg[3], 1)

  local font = getLoadingFont(app)
  local canvas = ensureFallbackCanvas(love.graphics.getWidth(), love.graphics.getHeight())
  if canvas then
    renderLoadingPatternToCanvas(canvas, label, font)
    love.graphics.setColor(colors.white)
    love.graphics.draw(canvas, 0, 0)
  else
    drawLoadingPattern(love.graphics.getWidth(), love.graphics.getHeight(), label, font)
  end

  love.graphics.present()
  love.graphics.pop()
  if ENABLE_LOADING_PRESENT_DELAY then
    LoveCompat.sleep(LOADING_PRESENT_DELAY_SECONDS)
  end
  return true
end

--- Compact sliding bar overlay for a window content rect (does not block / present).
function M.drawContentOverlay(x, y, w, h, message)
  if loadingScreenDisabled() then
    return
  end
  if not (love and love.graphics) then
    return
  end
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  w = math.max(0, math.floor(tonumber(w) or 0))
  h = math.max(0, math.floor(tonumber(h) or 0))
  if w < 8 or h < 8 then
    return
  end

  love.graphics.push("all")
  love.graphics.setScissor(x, y, w, h)

  -- Fully cover content so async apply results stay hidden until the bar has been moving.
  local bg = colors:appWorkspaceFill()
  love.graphics.setColor(bg[1], bg[2], bg[3], 1)
  love.graphics.rectangle("fill", x, y, w, h)

  local cx = x + math.floor(w * 0.5)
  local trackW = math.min(BAR_TRACK_W, math.max(48, w - 16))
  local segmentW = math.min(BAR_SEGMENT_W, math.max(16, math.floor(trackW * 0.32)))
  local barH = BAR_H
  local label = message or "Loading..."
  local font = love.graphics.getFont()
  local textH = (font and font.getHeight and font:getHeight()) or 8
  local textW = select(1, Text.measure(label, { font = font })) or 0
  local blockH = textH + 8 + barH
  local textY = y + math.floor((h - blockH) * 0.5)
  Text.print(label, math.floor(cx - textW * 0.5), textY, {
    font = font,
    color = colors.white,
    shadowColor = colors.transparent,
  })
  drawIndeterminateBar(cx, textY + textH + 8, bg, trackW, segmentW, barH)

  love.graphics.setScissor()
  love.graphics.pop()
  love.graphics.setColor(colors.white)
end

--- Present a few frames with content loading overlays so the bar is visible/moving
--- before a following update hitch (decode/pack) freezes the UI.
function M.pumpContentLoadingFrames(app, windows, opts)
  if loadingScreenDisabled() then
    return false
  end
  if not (love and love.graphics and love.graphics.isActive and love.graphics.isActive()) then
    return false
  end
  opts = opts or {}
  local frames = math.max(1, math.floor(tonumber(opts.frames) or 2))
  local delay = tonumber(opts.delaySeconds)
  if delay == nil then
    delay = LOADING_PRESENT_DELAY_SECONDS
  end

  for _ = 1, frames do
    if app and type(app.draw) == "function" then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      app:draw()
    else
      for i = 1, #(windows or {}) do
        local win = windows[i]
        if win and win._contentLoading == true and win.getInsetContentScreenRect then
          local cx, cy, cw, ch = win:getInsetContentScreenRect()
          M.drawContentOverlay(cx, cy, cw, ch, win._contentLoadingMessage or "Loading...")
        end
      end
    end
    love.graphics.present()
    if ENABLE_LOADING_PRESENT_DELAY and delay > 0 then
      LoveCompat.sleep(delay)
    end
  end
  return true
end

return M
