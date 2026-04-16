local MouseWindowChromeController = require("controllers.input.mouse_window_chrome_controller")

describe("mouse_window_chrome_controller", function()
  beforeEach(function()
    if MouseWindowChromeController._resetHeaderDoubleClickState then
      MouseWindowChromeController._resetHeaderDoubleClickState()
    end
  end)

  it("starts window drag on right click over specialized toolbar", function()
    local focused
    local win = {
      _id = "w1",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      x = 4,
      y = 7,
      dragging = false,
      specializedToolbar = {
        updatePosition = function() end,
        contains = function(_, x, y)
          return x == 10 and y == 20
        end,
        mousepressed = function()
          return false
        end,
      },
    }
    local wm = {
      setFocus = function(_, next)
        focused = next
      end,
    }

    local handled = MouseWindowChromeController.handleToolbarClicks(2, 10, 20, win, wm)

    expect(handled).toBeTruthy()
    expect(focused).toBe(win)
    expect(win.dragging).toBeTruthy()
    expect(win.dx).toBe(6)
    expect(win.dy).toBe(13)
  end)

  it("starts window drag on middle click over header toolbar", function()
    local win = {
      _id = "w2",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      x = 12,
      y = 9,
      dragging = false,
      headerToolbar = {
        updatePosition = function() end,
        contains = function(_, x, y)
          return x == 40 and y == 50
        end,
        mousepressed = function()
          return false
        end,
      },
    }
    local wm = {
      setFocus = function() end,
    }

    local handled = MouseWindowChromeController.handleToolbarClicks(3, 40, 50, win, wm)

    expect(handled).toBeTruthy()
    expect(win.dragging).toBeTruthy()
    expect(win.dx).toBe(28)
    expect(win.dy).toBe(41)
  end)

  it("starts window drag on right click over a header toolbar control", function()
    local win = {
      _id = "w3",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      x = 12,
      y = 9,
      dragging = false,
      headerToolbar = {
        updatePosition = function() end,
        contains = function(_, x, y)
          return x == 200 and y == 30
        end,
        getButtonAt = function()
          return { w = 15, h = 15 }
        end,
        mousepressed = function()
          return false
        end,
      },
    }
    local wm = {
      setFocus = function() end,
    }

    local handled = MouseWindowChromeController.handleToolbarClicks(2, 200, 30, win, wm)

    expect(handled).toBeTruthy()
    expect(win.dragging).toBeTruthy()
    expect(win.dx).toBe(188)
    expect(win.dy).toBe(21)
  end)

  it("starts drag on docked specialized toolbar with right click on a button (separate toolbar)", function()
    local previousCtx = rawget(_G, "ctx")
    _G.ctx = {
      app = { separateToolbar = true },
    }
    local win = {
      _id = "dock",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      x = 0,
      y = 100,
      dragging = false,
      specializedToolbar = {
        updatePosition = function() end,
        contains = function(_, x, y)
          return x == 180 and y == 8
        end,
        getButtonAt = function()
          return { w = 15, h = 15 }
        end,
      },
    }
    local wm = {
      getFocus = function()
        return win
      end,
      setFocus = function() end,
    }

    local handled = MouseWindowChromeController.handleToolbarClicks(2, 180, 8, win, wm)
    _G.ctx = previousCtx

    expect(handled).toBeTruthy()
    expect(win.dragging).toBeTruthy()
    expect(win.dx).toBe(180)
    expect(win.dy).toBe(-92)
  end)

  it("triggers callback on double click over window title area", function()
    local renameCalls = 0
    local mousepressedCalls = 0
    local win = {
      _id = "rename-target",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      x = 10,
      y = 40,
      headerH = 15,
      isInHeader = function(_, x, y)
        return x >= 10 and x <= 210 and y >= 25 and y <= 40
      end,
      getHeaderRect = function()
        return 10, 25, 200, 15
      end,
      mousepressed = function()
        mousepressedCalls = mousepressedCalls + 1
      end,
      headerToolbar = {
        updatePosition = function() end,
        mousepressed = function()
          return false
        end,
        x = 170,
        y = 25,
        w = 40,
        h = 15,
      },
    }
    local wm = {
      setFocus = function() end,
    }

    local first = MouseWindowChromeController.handleHeaderClick(1, 40, 30, win, wm, {
      nowSeconds = 1.00,
      onWindowTitleDoubleClick = function()
        renameCalls = renameCalls + 1
      end,
    })

    local second = MouseWindowChromeController.handleHeaderClick(1, 41, 30, win, wm, {
      nowSeconds = 1.20,
      onWindowTitleDoubleClick = function()
        renameCalls = renameCalls + 1
      end,
    })

    expect(first).toBeTruthy()
    expect(second).toBeTruthy()
    expect(renameCalls).toBe(1)
    expect(mousepressedCalls).toBe(1)
  end)

  it("does not trigger title double click when clicking header toolbar area", function()
    local renameCalls = 0
    local win = {
      _id = "no-rename",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      x = 10,
      y = 40,
      headerH = 15,
      isInHeader = function(_, x, y)
        return x >= 10 and x <= 210 and y >= 25 and y <= 40
      end,
      getHeaderRect = function()
        return 10, 25, 200, 15
      end,
      mousepressed = function() end,
      headerToolbar = {
        updatePosition = function() end,
        contains = function(_, x, y)
          return x >= 170 and x <= 210 and y >= 25 and y <= 40
        end,
        mousepressed = function()
          return true
        end,
        x = 170,
        y = 25,
        w = 40,
        h = 15,
      },
    }
    local wm = {
      setFocus = function() end,
    }

    MouseWindowChromeController.handleHeaderClick(1, 175, 30, win, wm, {
      nowSeconds = 1.00,
      onWindowTitleDoubleClick = function()
        renameCalls = renameCalls + 1
      end,
    })
    MouseWindowChromeController.handleHeaderClick(1, 176, 30, win, wm, {
      nowSeconds = 1.20,
      onWindowTitleDoubleClick = function()
        renameCalls = renameCalls + 1
      end,
    })

    expect(renameCalls).toBe(0)
  end)
end)
