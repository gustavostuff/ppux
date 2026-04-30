-- Read-only color square for Settings Appearance grid (picker wiring later).
local colors = require("app_colors")

local M = {}
M.__index = M

local function copyRgb(c)
  if type(c) ~= "table" then
    return { 1, 1, 1, 1 }
  end
  return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] }
end

function M.new(opts)
  opts = opts or {}
  return setmetatable({
    slotId = opts.slotId,
    color = copyRgb(opts.color),
    x = 0,
    y = 0,
    w = 0,
    h = 0,
  }, M)
end

function M:setPosition(x, y)
  self.x = x or 0
  self.y = y or 0
end

function M:setSize(w, h)
  self.w = w or 0
  self.h = h or 0
end

function M:draw()
  local cell = math.min(self.w, self.h)
  local size = math.max(10, math.min(22, math.floor(cell * 0.55)))
  local sx = self.x + math.floor((self.w - size) / 2)
  local sy = self.y + math.floor((self.h - size) / 2)
  local c = self.color
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
  love.graphics.rectangle("fill", sx, sy, size, size, 1)
  love.graphics.setColor(colors.black[1], colors.black[2], colors.black[3], 0.35)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", sx + 0.5, sy + 0.5, size - 1, size - 1, 1)
  love.graphics.setColor(colors.white)
end

return M
