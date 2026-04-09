-- Canvas vs content coordinates: main window content is drawn after translate(0, contentOffsetY).
-- love.graphics.setScissor uses screen/canvas pixels and is NOT affected by transforms (LÖVE 0.9+).
-- Use these helpers when clipping in "content" space while the content translate is active.

local M = {}

local function contentOffsetY()
  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app
  local oy = app and app._canvasContentOffsetY
  if type(oy) == "number" and oy > 0 then
    return oy
  end
  return 0
end

function M.setScissorFromContentRect(x, y, w, h)
  local oy = contentOffsetY()
  love.graphics.setScissor(x, y + oy, w, h)
end

return M
