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

  it("starts palette link drag from the toolbar handle and links onto a target layer on release", function()
    local previousCtx = rawget(_G, "ctx")
    local statuses = {}
    local marked = {}
    _G.ctx = {
      app = {
        paletteLinkDrag = {
          active = false,
          sourceWin = nil,
          sourceWinId = nil,
          currentX = 0,
          currentY = 0,
        },
        setStatus = function(_, text)
          statuses[#statuses + 1] = text
        end,
        markUnsaved = function(_, eventType)
          marked[#marked + 1] = eventType
        end,
        showToast = function() end,
      },
    }

    local focused
    local source = {
      _id = "palette_1",
      title = "Sprite Palette",
      kind = "rom_palette",
      isPalette = true,
      _closed = false,
      _minimized = false,
      _collapsed = false,
      specializedToolbar = {
        updatePosition = function() end,
        getLinkHandleRect = function()
          return 10, 10, 32, 15
        end,
        contains = function() return true end,
        mousepressed = function()
          return false
        end,
        mousereleased = function()
          return false
        end,
      },
    }
    local target = {
      _id = "art_1",
      title = "Target Art",
      kind = "static_art",
      _closed = false,
      _minimized = false,
      contains = function(_, x, y)
        return x == 80 and y == 90
      end,
      getActiveLayerIndex = function()
        return 1
      end,
      activeLayer = 1,
      layers = {
        { kind = "tile" },
      },
    }
    local wm = {
      setFocus = function(_, next)
        focused = next
      end,
      getFocus = function()
        return source
      end,
      getWindows = function()
        return { source, target }
      end,
    }

    local pressed = MouseWindowChromeController.handleToolbarClicks(1, 12, 12, source, wm)
    local released = MouseWindowChromeController.handleToolbarRelease(1, 80, 90, wm)
    _G.ctx = previousCtx

    expect(pressed).toBeTruthy()
    expect(released).toBeTruthy()
    expect(target.layers[1].paletteData.winId).toBe("palette_1")
    expect(focused).toBe(target)
    expect(marked[1]).toBe("palette_link_change")
    expect(statuses[#statuses]).toBeTruthy()
  end)

  it("allows linking to non-CHR non-palette windows with non-tile active layers", function()
    local previousCtx = rawget(_G, "ctx")
    _G.ctx = {
      app = {
        paletteLinkDrag = {
          active = false,
          sourceWin = nil,
          sourceWinId = nil,
          currentX = 0,
          currentY = 0,
        },
        setStatus = function() end,
        markUnsaved = function() end,
        showToast = function() end,
      },
    }

    local source = {
      _id = "palette_1",
      title = "Sprite Palette",
      kind = "rom_palette",
      isPalette = true,
      _closed = false,
      _minimized = false,
      _collapsed = false,
      specializedToolbar = {
        updatePosition = function() end,
        getLinkHandleRect = function()
          return 10, 10, 32, 15
        end,
        contains = function() return true end,
        mousepressed = function() return false end,
        mousereleased = function() return false end,
      },
    }
    local target = {
      _id = "builder_1",
      title = "Pattern Builder",
      kind = "pattern_table_builder",
      _closed = false,
      _minimized = false,
      contains = function(_, x, y)
        return x == 80 and y == 90
      end,
      getActiveLayerIndex = function()
        return 1
      end,
      activeLayer = 1,
      layers = {
        { kind = "canvas" },
      },
    }
    local wm = {
      setFocus = function() end,
      getFocus = function()
        return source
      end,
      getWindows = function()
        return { source, target }
      end,
    }

    local pressed = MouseWindowChromeController.handleToolbarClicks(1, 12, 12, source, wm)
    local released = MouseWindowChromeController.handleToolbarRelease(1, 80, 90, wm)
    _G.ctx = previousCtx

    expect(pressed).toBeTruthy()
    expect(released).toBeTruthy()
    expect(target.layers[1].paletteData.winId).toBe("palette_1")
  end)

  it("does not allow linking onto chr windows", function()
    local previousCtx = rawget(_G, "ctx")
    local toasts = {}
    _G.ctx = {
      app = {
        paletteLinkDrag = {
          active = false,
          sourceWin = nil,
          sourceWinId = nil,
          currentX = 0,
          currentY = 0,
        },
        setStatus = function() end,
        markUnsaved = function() end,
        showToast = function(_, kind, message)
          toasts[#toasts + 1] = { kind = kind, message = message }
        end,
      },
    }

    local source = {
      _id = "palette_1",
      title = "Sprite Palette",
      kind = "rom_palette",
      isPalette = true,
      _closed = false,
      _minimized = false,
      _collapsed = false,
      specializedToolbar = {
        updatePosition = function() end,
        getLinkHandleRect = function()
          return 10, 10, 32, 15
        end,
        contains = function() return true end,
        mousepressed = function() return false end,
        mousereleased = function() return false end,
      },
    }
    local chrTarget = {
      _id = "chr_1",
      title = "CHR Banks",
      kind = "chr",
      _closed = false,
      _minimized = false,
      contains = function(_, x, y)
        return x == 80 and y == 90
      end,
      getActiveLayerIndex = function()
        return 1
      end,
      activeLayer = 1,
      layers = {
        { kind = "tile" },
      },
    }
    local wm = {
      setFocus = function() end,
      getFocus = function()
        return source
      end,
      getWindows = function()
        return { source, chrTarget }
      end,
    }

    MouseWindowChromeController.handleToolbarClicks(1, 12, 12, source, wm)
    local released = MouseWindowChromeController.handleToolbarRelease(1, 80, 90, wm)
    _G.ctx = previousCtx

    expect(released).toBeTruthy()
    expect(chrTarget.layers[1].paletteData).toBeNil()
    expect(toasts[1].kind).toBe("error")
  end)

  it("double clicks the palette link handle to unlink all destination windows using that palette", function()
    local previousCtx = rawget(_G, "ctx")
    local statuses = {}
    local marked = {}
    _G.ctx = {
      app = {
        paletteLinkDrag = {
          active = false,
          sourceWin = nil,
          sourceWinId = nil,
          currentX = 0,
          currentY = 0,
        },
        setStatus = function(_, text)
          statuses[#statuses + 1] = text
        end,
        markUnsaved = function(_, eventType)
          marked[#marked + 1] = eventType
        end,
        showToast = function() end,
      },
    }

    local source = {
      _id = "palette_1",
      title = "Sprite Palette",
      kind = "rom_palette",
      isPalette = true,
      _closed = false,
      _minimized = false,
      _collapsed = false,
      specializedToolbar = {
        updatePosition = function() end,
        getLinkHandleRect = function()
          return 10, 10, 15, 15
        end,
        contains = function() return true end,
        mousepressed = function()
          return false
        end,
        mousereleased = function()
          return false
        end,
      },
    }
    local target = {
      _id = "art_1",
      title = "Target Art",
      kind = "static_art",
      _closed = false,
      _minimized = false,
      contains = function(_, x, y)
        return x == 80 and y == 90
      end,
      getActiveLayerIndex = function()
        return 1
      end,
      activeLayer = 1,
      layers = {
        { kind = "tile", paletteData = { winId = "palette_1" } },
      },
    }

    local target2 = {
      _id = "art_2",
      title = "Target Art 2",
      kind = "static_art",
      _closed = false,
      _minimized = false,
      contains = function()
        return false
      end,
      getActiveLayerIndex = function()
        return 1
      end,
      activeLayer = 1,
      layers = {
        { kind = "tile", paletteData = { winId = "palette_1" } },
      },
    }

    local focused = target
    local wm = {
      setFocus = function(_, next)
        focused = next
      end,
      getFocus = function()
        return focused
      end,
      getWindows = function()
        return { source, target, target2 }
      end,
    }

    MouseWindowChromeController.handleToolbarClicks(1, 12, 12, source, wm)
    MouseWindowChromeController.handleToolbarRelease(1, 12, 12, wm)
    MouseWindowChromeController.handleToolbarClicks(1, 12, 12, source, wm)

    _G.ctx = previousCtx

    expect(target.layers[1].paletteData).toBeNil()
    expect(target2.layers[1].paletteData).toBeNil()
    expect(focused).toBe(source)
    expect(marked[1]).toBe("palette_link_change")
    expect(statuses[#statuses]).toBe("Unlinked 2 palette connections from Sprite Palette")
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
