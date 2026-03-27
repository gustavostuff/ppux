local WM = require("controllers.window.window_controller")

describe("window_controller.lua - focused resize handle hit test", function()
  it("checks only the focused window resize handle", function()
    local focusedCalls = 0
    local otherCalls = 0
    local wm = WM.new()
    local other = {
      _closed = false,
      _minimized = false,
      mouseOnResizeHandle = function()
        otherCalls = otherCalls + 1
        return true
      end,
    }
    local focused = {
      _closed = false,
      _minimized = false,
      mouseOnResizeHandle = function(_, x, y)
        focusedCalls = focusedCalls + 1
        return x == 12 and y == 34
      end,
    }

    wm:add(other)
    wm:add(focused)
    wm:setFocus(focused)

    expect(wm:focusedResizeHandleAt(12, 34)).toBe(true)
    expect(wm:focusedResizeHandleAt(0, 0)).toBe(false)
    expect(focusedCalls).toBe(2)
    expect(otherCalls).toBe(0)
  end)
end)
