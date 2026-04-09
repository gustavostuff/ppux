local MouseClickController = require("controllers.input.mouse_click_controller")
local MouseWheelController = require("controllers.input.mouse_wheel_controller")
local ResolutionController = require("controllers.app.resolution_controller")

describe("mouse extracted controllers (smoke)", function()
  local originals

  beforeEach(function()
    originals = {
      getScaledMouse = ResolutionController.getScaledMouse,
    }
    if MouseClickController._resetRomPaletteDoubleClickState then
      MouseClickController._resetRomPaletteDoubleClickState()
    end
  end)

  afterEach(function()
    ResolutionController.getScaledMouse = originals.getScaledMouse
    if MouseClickController._resetRomPaletteDoubleClickState then
      MouseClickController._resetRomPaletteDoubleClickState()
    end
  end)

  it("mouse_click_controller gives focused toolbar clicks first priority", function()
    local calls = {}
    local focusWin = { _id = "focus" }
    local winUnderMouse = { _id = "under" }
    local wm = {
      getFocus = function() return focusWin end,
      windowAt = function() return winUnderMouse end,
    }
    local env = {
      ctx = {
        wm = function() return wm end,
        getMode = function() return "tile" end,
      },
      chrome = {
        getTopInteractiveWindowAt = function() return focusWin end,
        handleToolbarClicks = function(button, x, y, win, wmArg)
          calls[#calls + 1] = { fn = "toolbar", win = win and win._id or "nil" }
          return win == focusWin
        end,
        handleResizeHandle = function()
          calls[#calls + 1] = { fn = "resize" }
          return false
        end,
        handleHeaderClick = function()
          calls[#calls + 1] = { fn = "header" }
          return false
        end,
      },
    }

    local handled = MouseClickController.handleMousePressed(env, 10, 20, 1)

    expect(handled).toBeTruthy()
    expect(#calls).toBe(1)
    expect(calls[1].fn).toBe("toolbar")
    expect(calls[1].win).toBe("focus")
  end)

  it("mouse_click_controller can route clicks to an unfocused specialized toolbar window", function()
    local calls = {}
    local focusWin = { _id = "focus" }
    local toolbarWin = { _id = "rom_palette" }
    local wm = {
      getFocus = function() return focusWin end,
      windowAt = function() return nil end,
    }
    local env = {
      ctx = {
        wm = function() return wm end,
        getMode = function() return "tile" end,
      },
      chrome = {
        getTopInteractiveWindowAt = function() return toolbarWin end,
        handleToolbarClicks = function(button, x, y, win, wmArg)
          calls[#calls + 1] = { fn = "toolbar", win = win and win._id or "nil" }
          return win == toolbarWin
        end,
        findToolbarWindowAt = function(x, y, wmArg)
          calls[#calls + 1] = { fn = "findToolbarWindowAt" }
          return toolbarWin
        end,
        handleResizeHandle = function()
          calls[#calls + 1] = { fn = "resize" }
          return false
        end,
        handleHeaderClick = function()
          calls[#calls + 1] = { fn = "header" }
          return false
        end,
      },
    }

    local handled = MouseClickController.handleMousePressed(env, 10, 20, 1)

    expect(handled).toBeTruthy()
    expect(calls[1].fn).toBe("findToolbarWindowAt")
    expect(calls[2].fn).toBe("toolbar")
    expect(calls[2].win).toBe("rom_palette")
  end)

  it("mouse_wheel_controller prioritizes ctrl+alt brush size in edit mode before zoom/scroll", function()
    local calls = { brush = 0, zoom = 0, scroll = 0, focus = 0 }

    -- Below the app top strip (getContentOffsetY defaults to 15px when layout not synced).
    ResolutionController.getScaledMouse = function()
      return { x = 5, y = 22 }
    end

    local win = {
      addZoomLevel = function() calls.zoom = calls.zoom + 1 end,
      scrollBy = function() calls.scroll = calls.scroll + 1 end,
    }
    local wm = {
      getFocus = function() return win end,
      windowAt = function() return win end,
      setFocus = function() calls.focus = calls.focus + 1 end,
    }
    local app = { brushSize = 2 }
    local ctx = {
      wm = function() return wm end,
      getMode = function() return "edit" end,
      app = app,
    }

    MouseWheelController.handleWheel({
      ctx = ctx,
      utils = {
        ctrlDown = function() return true end,
        altDown = function() return true end,
        shiftDown = function() return false end,
        changeBrushSize = function(appArg, newSize)
          calls.brush = calls.brush + 1
          calls.brushSize = newSize
          expect(appArg).toBe(app)
        end,
      }
    }, 0, 1)

    expect(calls.brush).toBe(1)
    expect(calls.brushSize).toBe(3)
    expect(calls.zoom).toBe(0)
    expect(calls.scroll).toBe(0)
    expect(calls.focus).toBe(0)
  end)

  it("mouse_wheel_controller consumes wheel on toolbar minimized buttons before window scroll", function()
    local calls = { toolbarWheel = 0, scroll = 0, focus = 0 }

    ResolutionController.getScaledMouse = function()
      return { x = 10, y = 22 }
    end

    local win = {
      scrollBy = function() calls.scroll = calls.scroll + 1 end,
    }
    local wm = {
      getFocus = function() return win end,
      windowAt = function() return win end,
      setFocus = function() calls.focus = calls.focus + 1 end,
    }
    local app = {
      taskbar = {
        wheelmoved = function(_, dx, dy)
          calls.toolbarWheel = calls.toolbarWheel + 1
          return true
        end,
      },
    }
    local ctx = {
      wm = function() return wm end,
      getMode = function() return "tile" end,
      app = app,
    }

    local handled = MouseWheelController.handleWheel({
      ctx = ctx,
      utils = {
        ctrlDown = function() return false end,
        altDown = function() return false end,
        shiftDown = function() return false end,
      },
    }, 0, -1)

    expect(handled).toBeTruthy()
    expect(calls.toolbarWheel).toBe(1)
    expect(calls.scroll).toBe(0)
    expect(calls.focus).toBe(0)
  end)

  it("mouse_click_controller starts edit shape drag on shift-click in edit mode", function()
    local focused = nil
    local painting = nil
    local win = {
      _id = "edit_win",
      isPalette = false,
      cellW = 8,
      cellH = 8,
      cols = 4,
      rows = 4,
      layers = { { kind = "tile" } },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 0, 0, 2, 3 end,
    }
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, next) focused = next end,
      windowAt = function() return win end,
    }
    local env = {
      ctx = {
        app = {},
        wm = function() return wm end,
        getMode = function() return "edit" end,
        setPainting = function(v) painting = v end,
      },
      chrome = {
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
      utils = {
        shiftDown = function() return true end,
        fillDown = function() return false end,
        grabDown = function() return false end,
      },
    }
    focused = win

    local handled = MouseClickController.handleMousePressed(env, 10, 20, 1)

    expect(handled).toBeTruthy()
    expect(focused).toBe(win)
    expect(painting).toBe(false)
    expect(win.editShapeDrag).toBeTruthy()
    expect(win.editShapeDrag.kind).toBe("rect_or_line")
    expect(win.editShapeDrag.startX).toBe(2)
    expect(win.editShapeDrag.startY).toBe(3)
  end)

  it("mouse_click_controller starts rect fill drag when the rect tool is active", function()
    local focused = nil
    local painting = nil
    local win = {
      _id = "edit_win",
      isPalette = false,
      cellW = 8,
      cellH = 8,
      cols = 4,
      rows = 4,
      layers = { { kind = "tile" } },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 0, 0, 2, 3 end,
    }
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, next) focused = next end,
      windowAt = function() return win end,
    }
    local env = {
      ctx = {
        app = { editTool = "rect_fill" },
        wm = function() return wm end,
        getMode = function() return "edit" end,
        setPainting = function(v) painting = v end,
      },
      chrome = {
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
      utils = {
        shiftDown = function() return false end,
        fillDown = function() return false end,
        grabDown = function() return false end,
      },
    }
    focused = win

    local handled = MouseClickController.handleMousePressed(env, 10, 20, 1)

    expect(handled).toBeTruthy()
    expect(focused).toBe(win)
    expect(painting).toBe(false)
    expect(win.editShapeDrag).toBeTruthy()
    expect(win.editShapeDrag.kind).toBe("rect_fill")
  end)

  it("mouse_click_controller opens ROM palette address modal on double click of a locked cell", function()
    local modalCalls = {}
    local selected = nil
    local win = {
      _id = "rom_palette",
      isPalette = true,
      kind = "rom_palette",
      cols = 4,
      rows = 4,
      toGridCoords = function() return true, 0, 0 end,
      isCellEditable = function() return false end,
      setSelected = function(_, col, row)
        selected = { col = col, row = row }
      end,
    }
    local wm = {
      getFocus = function() return nil end,
      setFocus = function() end,
      windowAt = function() return win end,
    }
    local env = {
      nowSeconds = (function()
        local times = { 1.0, 1.2 }
        local idx = 0
        return function()
          idx = idx + 1
          return times[idx] or 2.0
        end
      end)(),
      ctx = {
        app = {
          showRomPaletteAddressModal = function(_, modalWin, col, row)
            modalCalls[#modalCalls + 1] = { win = modalWin, col = col, row = row }
          end,
        },
        wm = function() return wm end,
        setStatus = function() end,
      },
      chrome = {
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
    }

    expect(MouseClickController.handleMousePressed(env, 10, 10, 1)).toBe(true)
    expect(#modalCalls).toBe(0)
    expect(selected).toBeNil()

    expect(MouseClickController.handleMousePressed(env, 10, 10, 1)).toBe(true)
    expect(#modalCalls).toBe(1)
    expect(modalCalls[1].win).toBe(win)
    expect(modalCalls[1].col).toBe(0)
    expect(modalCalls[1].row).toBe(0)
  end)

  it("mouse_click_controller starts drag on right-click over a PPU tile item while preparing context menu", function()
    local focused = nil
    local contextArgs = nil
    local win = {
      _id = "ppu",
      kind = "ppu_frame",
      layers = { { kind = "tile" } },
      x = 12,
      y = 34,
      dragging = false,
      getActiveLayerIndex = function() return 1 end,
      mousepressed = function(self, x, y, button)
        if button == 2 or button == 3 then
          self.dragging = true
          self.dx = x - self.x
          self.dy = y - self.y
        end
      end,
      contains = function()
        return true
      end,
    }
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, next) focused = next end,
      windowAt = function() return win end,
    }
    local env = {
      ctx = {
        wm = function() return wm end,
        getMode = function() return "tile" end,
      },
      chrome = {
        getTopInteractiveWindowAt = function() return win end,
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
      utils = {
        pickByVisual = function()
          return true, 1, 2, { index = 0x21 }
        end,
      },
      beginContextMenuClick = function(kind, x, y, button, targetWin, extra)
        contextArgs = {
          kind = kind,
          x = x,
          y = y,
          button = button,
          win = targetWin,
          layerIndex = extra and extra.layerIndex or nil,
          col = extra and extra.col or nil,
          row = extra and extra.row or nil,
        }
      end,
    }

    local handled = MouseClickController.handleMousePressed(env, 40, 55, 2)

    expect(handled).toBeTruthy()
    expect(focused).toBe(win)
    expect(win.dragging).toBeTruthy()
    expect(contextArgs.kind).toBe("ppu_tile")
    expect(contextArgs.button).toBe(2)
    expect(contextArgs.win).toBe(win)
    expect(contextArgs.layerIndex).toBe(1)
    expect(contextArgs.col).toBe(1)
    expect(contextArgs.row).toBe(2)
  end)

  it("mouse_click_controller opens select-in-CHR context for right-click on PPU sprite layer items", function()
    local SpriteController = require("controllers.sprite.sprite_controller")
    local originalPickSpriteAt = SpriteController.pickSpriteAt
    local focused = nil
    local contextArgs = nil

    local win = {
      _id = "ppu_spr",
      kind = "ppu_frame",
      layers = { { kind = "sprite", items = { { bank = 1, tile = 0x2A } } } },
      x = 4,
      y = 8,
      dragging = false,
      getActiveLayerIndex = function() return 1 end,
      mousepressed = function(self, x, y, button)
        if button == 2 or button == 3 then
          self.dragging = true
          self.dx = x - self.x
          self.dy = y - self.y
        end
      end,
      contains = function() return true end,
    }
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, next) focused = next end,
      windowAt = function() return win end,
    }
    local env = {
      ctx = {
        wm = function() return wm end,
        getMode = function() return "tile" end,
      },
      chrome = {
        getTopInteractiveWindowAt = function() return win end,
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
      beginContextMenuClick = function(kind, x, y, button, targetWin, extra)
        contextArgs = {
          kind = kind,
          button = button,
          win = targetWin,
          layerIndex = extra and extra.layerIndex or nil,
          itemIndex = extra and extra.itemIndex or nil,
        }
      end,
    }

    SpriteController.pickSpriteAt = function()
      return 1, 1, 0, 0
    end
    local handled = MouseClickController.handleMousePressed(env, 20, 20, 2)
    SpriteController.pickSpriteAt = originalPickSpriteAt

    expect(handled).toBeTruthy()
    expect(focused).toBe(win)
    expect(win.dragging).toBeTruthy()
    expect(contextArgs.kind).toBe("select_in_chr")
    expect(contextArgs.button).toBe(2)
    expect(contextArgs.win).toBe(win)
    expect(contextArgs.layerIndex).toBe(1)
    expect(contextArgs.itemIndex).toBe(1)
  end)

  it("mouse_click_controller opens select-in-CHR context for right-click on static tile layers", function()
    local focused = nil
    local contextArgs = nil
    local win = {
      _id = "static_tile",
      kind = "static_art",
      layers = { { kind = "tile" } },
      x = 10,
      y = 12,
      dragging = false,
      getActiveLayerIndex = function() return 1 end,
      mousepressed = function(self, x, y, button)
        if button == 2 or button == 3 then
          self.dragging = true
          self.dx = x - self.x
          self.dy = y - self.y
        end
      end,
      contains = function() return true end,
    }
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, next) focused = next end,
      windowAt = function() return win end,
    }
    local env = {
      ctx = {
        wm = function() return wm end,
        getMode = function() return "tile" end,
      },
      chrome = {
        getTopInteractiveWindowAt = function() return win end,
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
      utils = {
        pickByVisual = function()
          return true, 2, 3, { index = 0x11, _bankIndex = 1 }
        end,
      },
      beginContextMenuClick = function(kind, x, y, button, targetWin, extra)
        contextArgs = {
          kind = kind,
          button = button,
          win = targetWin,
          layerIndex = extra and extra.layerIndex or nil,
          col = extra and extra.col or nil,
          row = extra and extra.row or nil,
        }
      end,
    }

    local handled = MouseClickController.handleMousePressed(env, 40, 55, 2)

    expect(handled).toBeTruthy()
    expect(focused).toBe(win)
    expect(win.dragging).toBeTruthy()
    expect(contextArgs.kind).toBe("select_in_chr")
    expect(contextArgs.button).toBe(2)
    expect(contextArgs.win).toBe(win)
    expect(contextArgs.layerIndex).toBe(1)
    expect(contextArgs.col).toBe(2)
    expect(contextArgs.row).toBe(3)
  end)
end)
