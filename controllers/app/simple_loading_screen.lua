local colors = require("app_colors")
local Palettes = require("palettes")

local M = {}
local ENABLE_LOADING_PRESENT_DELAY = true
local LOADING_PRESENT_DELAY_SECONDS = 0.1
local LOADING_LABEL_FONT_SIZE = 32
local fallbackCanvas = nil
local loadingFont = nil
local cachedPaletteColors = nil
local DISABLE_LOADING_SCREEN_FLAG = "__PPUX_DISABLE_LOADING_SCREEN__"

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

local function getLoadingPaletteColors()
  if cachedPaletteColors then
    return cachedPaletteColors
  end

  cachedPaletteColors = {}
  local palette = Palettes and Palettes.smooth_fbx or nil
  if type(palette) == "table" then
    for _, color in pairs(palette) do
      if type(color) == "table" and color[1] and color[2] and color[3] then
        cachedPaletteColors[#cachedPaletteColors + 1] = color
      end
    end
  end

  if #cachedPaletteColors == 0 then
    cachedPaletteColors = { colors.white }
  end

  return cachedPaletteColors
end

local function randomPaletteColor()
  local paletteColors = getLoadingPaletteColors()
  local index = love.math and love.math.random and love.math.random(#paletteColors) or math.random(#paletteColors)
  return paletteColors[index] or colors.white
end

local function drawRandomSquares(cw, ch)
  local boxSize = 128
  local squareSize = 16
  local squareCount = 8
  local cx = math.floor(cw * 0.5)
  local cy = math.floor(ch * 0.5) - 8
  local boxX = math.floor(cx - (boxSize * 0.5))
  local boxY = math.floor(cy - (boxSize * 0.5))
  local cellsPerAxis = math.max(1, math.floor(boxSize / squareSize))
  local used = {}

  for _ = 1, squareCount do
    local cellIndex
    repeat
      cellIndex = (love.math and love.math.random and love.math.random(cellsPerAxis * cellsPerAxis))
        or math.random(cellsPerAxis * cellsPerAxis)
    until not used[cellIndex]
    used[cellIndex] = true

    local zeroIndex = cellIndex - 1
    local gridX = zeroIndex % cellsPerAxis
    local gridY = math.floor(zeroIndex / cellsPerAxis)
    local color = randomPaletteColor()
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.rectangle("fill", boxX + gridX * squareSize, boxY + gridY * squareSize, squareSize, squareSize)
  end
end

local function drawLoadingPattern(cw, ch, message, font)
  local cx = math.floor(cw * 0.5)
  local cy = math.floor(ch * 0.5) - 8

  love.graphics.clear(colors.gray10)
  drawRandomSquares(cw, ch)

  if font then
    love.graphics.setFont(font)
  end
  love.graphics.setColor(colors.white)
  love.graphics.printf(message or "Loading...", 0, cy + 64 + 18, cw, "center")
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
  love.graphics.clear(colors.gray10)

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
