local colors = require("app_colors")
local Text = require("utils.text_utils")

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

  local candidates = {
    "user_interface/fonts/AsepriteFont.ttf",
    "../user_interface/fonts/AsepriteFont.ttf",
    "user_interface/fonts/proggy-tiny.ttf",
    "../user_interface/fonts/proggy-tiny.ttf",
  }

  for _, path in ipairs(candidates) do
    local ok, font = pcall(love.graphics.newFont, path, LOADING_LABEL_FONT_SIZE)
    if ok and font then
      font:setFilter("nearest", "nearest")
      loadingFont = font
      return loadingFont
    end
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

local function drawIndeterminateBar(cx, trackY, bg)
  local trackX = math.floor(cx - BAR_TRACK_W * 0.5)
  trackY = math.floor(trackY)
  local t = 0
  if love and love.timer and love.timer.getTime then
    t = love.timer.getTime()
  end
  local phase = (math.sin(t * BAR_SLIDE_SPEED) + 1) * 0.5
  local maxSlide = BAR_TRACK_W - BAR_SEGMENT_W
  local barX = trackX + phase * maxSlide

  love.graphics.setColor(bg[1] * 0.45 + 0.12, bg[2] * 0.45 + 0.12, bg[3] * 0.45 + 0.12, 1)
  love.graphics.rectangle("fill", trackX, trackY, BAR_TRACK_W, BAR_H)
  love.graphics.setColor(colors.white)
  love.graphics.rectangle("fill", barX, trackY, BAR_SEGMENT_W, BAR_H)
end

local function drawLoadingPattern(cw, ch, message, font)
  local cx = math.floor(cw * 0.5)
  local cy = math.floor(ch * 0.5) - 8

  local bg = colors:appWorkspaceFill()
  love.graphics.clear(bg[1], bg[2], bg[3], 1)

  if font then
    love.graphics.setFont(font)
  end
  local label = message or "Loading..."
  local textW = select(1, Text.measure(label, { font = font }))
  local textX = math.floor((cw - textW) * 0.5)
  local textY = cy + 90
  Text.print(label, textX, textY, { font = font, color = colors.white })

  local textBottom = textY
  if font and font.getHeight then
    textBottom = textY + font:getHeight()
  else
    textBottom = textY + LOADING_LABEL_FONT_SIZE
  end
  drawIndeterminateBar(cx, textBottom + BAR_GAP_BELOW_TEXT, bg)
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
  if ENABLE_LOADING_PRESENT_DELAY and love and love.timer and love.timer.sleep then
    love.timer.sleep(LOADING_PRESENT_DELAY_SECONDS)
  end
  return true
end

return M
