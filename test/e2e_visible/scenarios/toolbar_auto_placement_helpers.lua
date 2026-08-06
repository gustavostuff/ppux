-- Shared asserts for window-attached specialized toolbars (top strip + viewport clamp).

local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")

-- Match ui/toolbars/toolbar_base.lua TOOLBAR_OUTSIDE_GAP.
local GAP = 4

local M = {}

--- Programmatic drag (same math as Window:mousepressed + mousemoved + mousereleased on header center).
function M.dragWindowContentToward(win, targetContentX, targetContentY)
  local hx, hy, hw, hh = win:getHeaderRect()
  local px = hx + math.floor(hw * 0.5)
  local py = hy + math.floor(hh * 0.5)
  win:mousepressed(px, py, 1)
  local mx = targetContentX + win.dx
  local my = targetContentY + win.dy
  win:mousemoved(mx, my)
  win:mousereleased(mx, my, 1)
end

local function canvasWidth(app)
  if app and app.canvas and app.canvas.getWidth then
    local w = app.canvas:getWidth()
    if type(w) == "number" and w > 0 then
      return w
    end
  end
  return nil
end

--- After updatePosition, specialized toolbar stays in-view (Y: app top bar; X: canvas ± gap).
function M.assertSpecializedToolbarMatchesTopClamp(win, app)
  local wm = app.wm
  assert(wm and wm:getFocus() == win, "window must stay focused for toolbar layout")
  local tb = win.specializedToolbar
  assert(tb and tb.updatePosition, "expected specialized toolbar")

  tb:updatePosition()

  assert(tb._verticalLayout ~= true, "attached toolbar should use horizontal layout")

  local hx, hy, hw = win:getHeaderRect()
  local minY = AppTopToolbarController.getContentOffsetY(app) + GAP
  local preferredY = math.floor(hy - tb.h - 1)
  local expectedY = math.max(preferredY, minY)

  assert(
    tb.y == expectedY,
    string.format("toolbar y: expected %s (preferred=%s min=%s) got %s", expectedY, preferredY, minY, tb.y)
  )

  if preferredY >= minY then
    local bottom = tb.y + tb.h
    assert(
      math.abs(bottom - (hy - 1)) <= 1,
      string.format("top strip bottom: expected ~%s got %s", hy - 1, bottom)
    )
  else
    assert(tb.y == minY, string.format("clamped toolbar y should be minY=%s got %s", minY, tb.y))
  end

  local cw = canvasWidth(app)
  assert(cw, "expected canvas width for horizontal clamp assert")
  local drawLeft = tb.x - 1
  local drawRight = drawLeft + tb.w
  local minLeft = GAP
  local maxRight = cw - GAP

  assert(drawLeft >= minLeft, string.format("toolbar left edge %s should be >= %s", drawLeft, minLeft))
  assert(drawRight <= maxRight, string.format("toolbar right edge %s should be <= %s", drawRight, maxRight))

  -- When the natural centered strip fits, X should match header centering (unless clamped).
  local preferredLeft = hx + math.floor((hw - tb.w) / 2)
  local maxLeft = maxRight - tb.w
  local expectedLeft = preferredLeft
  if maxLeft < minLeft then
    expectedLeft = minLeft
  elseif preferredLeft < minLeft then
    expectedLeft = minLeft
  elseif preferredLeft > maxLeft then
    expectedLeft = maxLeft
  end
  assert(
    drawLeft == expectedLeft,
    string.format("toolbar left: expected %s (preferred=%s) got %s", expectedLeft, preferredLeft, drawLeft)
  )
end

-- Back-compat alias for older scenario/test names.
M.assertSpecializedToolbarMatchesAutoLayout = M.assertSpecializedToolbarMatchesTopClamp

return M
