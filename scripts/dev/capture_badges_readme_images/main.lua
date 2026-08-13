-- Standalone Love2D capture of README window-link badges.
-- Does not boot PPUX. Colors come from app_colors.lua.
-- Run: ./scripts/dev/capture_badges_readme_images.sh

local OUTER = 7
local INNER = 3
local RADIUS = 2
local GAP = 3
local PAD = 4
local SCALE = 3
local BADGE_COUNT = 4

local function repoRoot()
  local source = love.filesystem.getSource()
  return source .. "/../../.."
end

local function join(a, b)
  return (tostring(a):gsub("/+$", "")) .. "/" .. tostring(b):gsub("^/+", "")
end

love.filesystem.setIdentity("ppux-badge-capture")
package.path = repoRoot() .. "/?.lua;" .. package.path

local colors = require("app_colors")

local INNER_COLORS = {
  colors.red,
  colors.green,
  colors.blue,
  colors.brown,
}

local function drawBadge(x, y, inner)
  local outer = colors:focusedChromeColor()
  love.graphics.setColor(outer[1], outer[2], outer[3], 1)
  love.graphics.rectangle("fill", x, y, OUTER, OUTER, RADIUS, RADIUS)
  local ix = x + math.floor((OUTER - INNER) * 0.5)
  local iy = y + math.floor((OUTER - INNER) * 0.5)
  love.graphics.setColor(inner[1], inner[2], inner[3], inner[4] or 1)
  love.graphics.rectangle("fill", ix, iy, INNER, INNER)
end

local function writeScaledPng(imgData, destPath)
  local tmpPath = destPath .. ".tmp.png"
  local fileData = assert(imgData:encode("png"), "encode png failed")
  local f = assert(io.open(tmpPath, "wb"), "open for write: " .. tmpPath)
  f:write(fileData:getString())
  f:close()
  local outW = imgData:getWidth() * SCALE
  local outH = imgData:getHeight() * SCALE
  local cmd = string.format(
    'ffmpeg -v error -y -i %q -vf scale=%d:%d:flags=neighbor -pix_fmt rgba %q',
    tmpPath, outW, outH, destPath)
  local ok = os.execute(cmd)
  os.remove(tmpPath)
  assert(ok == true or ok == 0, "ffmpeg rgba convert failed for " .. destPath)
  print(string.format("[capture-badges] wrote %s (%dx%d from %dx%d)",
    destPath, outW, outH, imgData:getWidth(), imgData:getHeight()))
end

function love.load()
  local canvasW = PAD * 2 + BADGE_COUNT * OUTER + (BADGE_COUNT - 1) * GAP
  local canvasH = PAD * 2 + OUTER
  local canvas = love.graphics.newCanvas(canvasW, canvasH)
  canvas:setFilter("nearest", "nearest")

  love.graphics.setCanvas(canvas)
  love.graphics.clear(colors:appWorkspaceFill())
  local x = PAD
  local y = PAD
  for _, inner in ipairs(INNER_COLORS) do
    drawBadge(x, y, inner)
    x = x + OUTER + GAP
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setCanvas()

  local dest = join(repoRoot(), "img/readme_images/badges.png")
  writeScaledPng(canvas:newImageData(), dest)
  love.event.quit(0)
end
