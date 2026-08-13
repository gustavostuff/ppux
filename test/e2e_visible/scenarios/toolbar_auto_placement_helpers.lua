-- Shared asserts for window-attached specialized toolbars.
-- Always a horizontal top strip (never left/right/bottom). If that would leave
-- the workspace, the strip moves: Y clamps under the app top bar, X inside the canvas.

local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")

-- Match ui/toolbars/toolbar_base.lua TOOLBAR_OUTSIDE_GAP.
local GAP = 1

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

--- After updatePosition: always top + visible (no T/B/L/R auto-side).
function M.assertSpecializedToolbarMatchesTopClamp(win, app)
  local wm = app.wm
  assert(wm and wm:getFocus() == win, "window must stay focused for toolbar layout")
  local tb = win.specializedToolbar
  assert(tb and tb.updatePosition, "expected specialized toolbar")

  tb:updatePosition()

  assert(tb._verticalLayout ~= true, "attached toolbar must stay horizontal (not a left/right strip)")
  assert((win._toolbarInsetLeft or 0) == 0, "left toolbar inset must stay 0 (no side strip)")
  assert((win._toolbarInsetRight or 0) == 0, "right toolbar inset must stay 0 (no side strip)")
  assert((win._toolbarInsetTop or 0) == 0, "top toolbar inset must stay 0")
  assert((win._toolbarInsetBottom or 0) == 0, "bottom toolbar inset must stay 0")

  local hx, hy, hw = win:getHeaderRect()
  local bx, by, bw, bh = win:getBaseContentScreenRect()
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

  -- Old auto-placement parked a strip under the window when the header was low.
  local oldBottomY = by + bh + GAP
  assert(
    math.abs(tb.y - oldBottomY) > 2,
    string.format("toolbar must not sit below the window (y=%s bottom-slot=%s)", tb.y, oldBottomY)
  )
  assert(tb.y < by + bh, "toolbar must not start at or below the window bottom")

  -- Old auto-placement used a vertical strip just outside the content left/right.
  local oldLeftX = bx - GAP - tb.w
  local oldRightX = bx + bw + GAP
  local drawLeft = tb.x - 1
  assert(
    math.abs(drawLeft - oldLeftX) > 2,
    string.format("toolbar must not sit as a left side strip (x=%s left-slot=%s)", drawLeft, oldLeftX)
  )
  assert(
    math.abs(drawLeft - oldRightX) > 2,
    string.format("toolbar must not sit as a right side strip (x=%s right-slot=%s)", drawLeft, oldRightX)
  )

  local cw = canvasWidth(app)
  assert(cw, "expected canvas width for horizontal clamp assert")
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

return M
