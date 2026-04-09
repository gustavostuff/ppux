-- love.graphics.setScissor uses canvas pixel coordinates and is not affected by transforms.
-- Window geometry (getScreenRect) is already in full-canvas space.

local M = {}

function M.setScissorFromContentRect(x, y, w, h)
  love.graphics.setScissor(x, y, w, h)
end

return M
