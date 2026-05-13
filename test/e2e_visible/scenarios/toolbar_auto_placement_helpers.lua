-- Shared asserts for window-attached toolbar when windowToolbarPlacement = auto.

local WindowToolbarPlacement = require("controllers.window.window_toolbar_placement")

local GAP = 4 -- TOOLBAR_OUTSIDE_GAP (match user_interface/toolbars/toolbar_base.lua)

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

--- After updatePosition, geometry must match placement from resolveAutoPlacement.
function M.assertSpecializedToolbarMatchesAutoLayout(win, app)
  local wm = app.wm
  assert(wm and wm:getFocus() == win, "window must stay focused for toolbar layout")
  local tb = win.specializedToolbar
  assert(tb and tb.updatePosition, "expected specialized toolbar")

  tb:updatePosition()

  local placement = WindowToolbarPlacement.effectiveForLayout(app.windowToolbarPlacement, win, app, tb)
  local resolved = WindowToolbarPlacement.resolveAutoPlacement(win, app, tb)
  assert(placement == resolved, string.format("effective placement %q should match resolveAutoPlacement %q", placement, resolved))

  local hx, hy, hw, hh = win:getHeaderRect()
  local bx, by, bw, bh = win:getBaseContentScreenRect()

  if placement == "top" then
    assert(tb._verticalLayout ~= true, "top placement should use horizontal toolbar layout")
    local bottom = tb.y + tb.h
    assert(math.abs(bottom - (hy - 1)) <= 1, string.format("top strip bottom: expected ~%s got %s", hy - 1, bottom))
  elseif placement == "bottom" then
    assert(tb._verticalLayout ~= true, "bottom placement should use horizontal toolbar layout")
    local ey = math.floor(by + bh + GAP)
    assert(tb.y == ey, string.format("bottom strip y: expected %s got %s", ey, tb.y))
  elseif placement == "left" then
    assert(tb._verticalLayout == true, "left placement should use vertical toolbar layout")
    local leftEdge = tb.x - 1
    assert(leftEdge + tb.w == bx - GAP, string.format("left strip: expected right edge bx-gap=%s, got %s", bx - GAP, leftEdge + tb.w))
  elseif placement == "right" then
    assert(tb._verticalLayout == true, "right placement should use vertical toolbar layout")
    local leftEdge = tb.x - 1
    assert(leftEdge == bx + bw + GAP, string.format("right strip: expected left edge %s got %s", bx + bw + GAP, leftEdge))
  else
    error("unexpected placement key: " .. tostring(placement))
  end
end

return M
