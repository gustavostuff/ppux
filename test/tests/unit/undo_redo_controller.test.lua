-- undo_redo_controller.test.lua

local UndoRedoController = require("controllers.input_support.undo_redo_controller")
local WM = require("controllers.window.window_controller")

describe("UndoRedoController - sprite removals", function()
  it("undoes multiple sprite removals in order", function()
    local ur = UndoRedoController.new(10)

    -- Minimal window/layer/sprite setup
    local s1 = { removed = false }
    local s2 = { removed = false }
    local s3 = { removed = false }
    local layer = { kind = "sprite", items = { s1, s2, s3 } }
    local win = { layers = { layer }, _closed = false }

    -- Simulate three delete operations (mark removed, push events newest first)
    ur:addRemovalEvent({
      type    = "remove_tile",
      subtype = "sprite",
      actions = {
        { win = win, layerIndex = 1, spriteIndex = 1, sprite = s1, prevRemoved = false },
      },
    })
    s1.removed = true

    ur:addRemovalEvent({
      type    = "remove_tile",
      subtype = "sprite",
      actions = {
        { win = win, layerIndex = 1, spriteIndex = 2, sprite = s2, prevRemoved = false },
      },
    })
    s2.removed = true

    ur:addRemovalEvent({
      type    = "remove_tile",
      subtype = "sprite",
      actions = {
        { win = win, layerIndex = 1, spriteIndex = 3, sprite = s3, prevRemoved = false },
      },
    })
    s3.removed = true

    -- Shuffle items to ensure undo uses refs not indices
    layer.items = { s3, s2, s1 }

    -- Undo should restore in reverse order (last removed -> first removed)
    local appStub = {}
    expect(ur:undo(appStub)).toBeTruthy()
    expect(s1.removed).toBe(true)
    expect(s2.removed).toBe(true)
    expect(s3.removed).toBe(false)

    expect(ur:undo(appStub)).toBeTruthy()
    expect(s1.removed).toBe(true)
    expect(s2.removed).toBe(false)
    expect(s3.removed).toBe(false)

    expect(ur:undo(appStub)).toBeTruthy()
    expect(s1.removed).toBe(false)
    expect(s2.removed).toBe(false)
    expect(s3.removed).toBe(false)

    -- Redo should reapply removals in original order
    expect(ur:redo(appStub)).toBeTruthy()
    expect(s1.removed).toBe(true)
    expect(s2.removed).toBe(false)
    expect(s3.removed).toBe(false)

    expect(ur:redo(appStub)).toBeTruthy()
    expect(s1.removed).toBe(true)
    expect(s2.removed).toBe(true)
    expect(s3.removed).toBe(false)

    expect(ur:redo(appStub)).toBeTruthy()
    expect(s1.removed).toBe(true)
    expect(s2.removed).toBe(true)
    expect(s3.removed).toBe(true)

    -- Further redo should fail (no redo left)
    expect(ur:redo(appStub)).toBeFalsy()
  end)
end)

describe("UndoRedoController - paint and removal combos", function()
  it("undos/redos paint then removal then paint again", function()
    local ur = UndoRedoController.new(10)

    -- Fake app state for paint operations
    local chrBanks = { [1] = {} }
    local tilesPool = {
      [1] = {
        [0] = { loadFromCHR = function() end },
        [1] = { loadFromCHR = function() end },
      }
    }
    local app = { appEditState = { chrBanksBytes = chrBanks, tilesPool = tilesPool } }

    -- Seed a paint event
    ur:startPaintEvent()
    ur:recordPixelChange(1, 0, 0, 0, 2, 3)
    ur:finishPaintEvent()

    -- Seed a removal event (static tile)
    local win = { cols = 2, rows = 2, layers = { { kind = "tile", removedCells = {} } }, _closed = false }
    ur:addRemovalEvent({
      type    = "remove_tile",
      subtype = "static",
      actions = {
        { win = win, layerIndex = 1, col = 0, row = 0, prevRemoved = false },
      },
    })
    win.layers[1].removedCells[1] = true

    -- Another paint event
    ur:startPaintEvent()
    ur:recordPixelChange(1, 1, 1, 1, 4, 5)
    ur:finishPaintEvent()

    -- Undo 3 steps
    expect(ur:undo(app)).toBeTruthy() -- undo last paint
    expect(ur:undo(app)).toBeTruthy() -- undo removal
    expect(win.layers[1].removedCells[1]).toBeFalsy()
    expect(ur:undo(app)).toBeTruthy() -- undo first paint

    -- Redo 3 steps
    expect(ur:redo(app)).toBeTruthy() -- redo first paint
    expect(ur:redo(app)).toBeTruthy() -- redo removal
    expect(win.layers[1].removedCells[1]).toBeTruthy()
    expect(ur:redo(app)).toBeTruthy() -- redo last paint
    expect(ur:redo(app)).toBeFalsy()
  end)

  it("handles interleaved events across windows and layers", function()
    local ur = UndoRedoController.new(10)

    -- Fake app state for paint operations
    local chrBanks = { [1] = {}, [2] = {} }
    local tilesPool = {
      [1] = { [0] = { loadFromCHR = function() end } },
      [2] = { [0] = { loadFromCHR = function() end } },
    }
    local app = { appEditState = { chrBanksBytes = chrBanks, tilesPool = tilesPool } }

    -- Window A (static)
    local winA = { cols = 2, rows = 2, layers = { { kind = "tile", removedCells = {} } }, _closed = false }
    -- Window B (ppu)
    local winB = {
      cols = 2,
      rows = 2,
      layers = { { kind = "tile", removedCells = {} } },
      _closed = false,
      nametableBytes = { 0, 0, 0, 0 },
      setNametableByteAt = function(self, c, r, val)
        local idx = r * 2 + c + 1
        self.nametableBytes[idx] = val
      end,
    }

    -- Paint in bank 1/tile 0
    ur:startPaintEvent()
    ur:recordPixelChange(1, 0, 0, 0, 1, 9)
    ur:finishPaintEvent()

    -- Remove from winA
    ur:addRemovalEvent({
      type    = "remove_tile",
      subtype = "static",
      actions = {
        { win = winA, layerIndex = 1, col = 0, row = 0, prevRemoved = false },
      },
    })
    winA.layers[1].removedCells[1] = true

    -- Paint in bank 2/tile 0
    ur:startPaintEvent()
    ur:recordPixelChange(2, 0, 1, 1, 2, 7)
    ur:finishPaintEvent()

    -- PPU removal (sets byte)
    ur:addRemovalEvent({
      type    = "remove_tile",
      subtype = "ppu",
      actions = {
        { win = winB, layerIndex = 1, col = 1, row = 1, prevByte = 0, newByte = 55 },
      },
    })
    winB.nametableBytes[4] = 55

    -- Remove again from winB at a different cell
    ur:addRemovalEvent({
      type    = "remove_tile",
      subtype = "ppu",
      actions = {
        { win = winB, layerIndex = 1, col = 0, row = 0, prevByte = 0, newByte = 99 },
      },
    })
    winB.nametableBytes[1] = 99

    -- Paint again affecting bank1/tile0 (same as first paint, different pixels)
    ur:startPaintEvent()
    ur:recordPixelChange(1, 0, 1, 1, 9, 8)
    ur:finishPaintEvent()

    -- Remove again from winA at a different cell
    ur:addRemovalEvent({
      type    = "remove_tile",
      subtype = "static",
      actions = {
        { win = winA, layerIndex = 1, col = 1, row = 1, prevRemoved = false },
      },
    })
    winA.layers[1].removedCells[4] = true

    -- Undo all events in stack order (LIFO)
    expect(ur:undo(app)).toBeTruthy() -- undo static removal (winA cell 1,1)
    expect(winA.layers[1].removedCells[4]).toBeFalsy()
    expect(ur:undo(app)).toBeTruthy() -- undo paint bank1 second
    expect(ur:undo(app)).toBeTruthy() -- undo ppu removal (winB 0,0)
    expect(winB.nametableBytes[1]).toBe(0)
    expect(ur:undo(app)).toBeTruthy() -- undo ppu removal (winB 1,1)
    expect(winB.nametableBytes[4]).toBe(0)
    expect(ur:undo(app)).toBeTruthy() -- undo paint bank2
    expect(ur:undo(app)).toBeTruthy() -- undo static removal (winA 0,0)
    expect(winA.layers[1].removedCells[1]).toBeFalsy()
    expect(ur:undo(app)).toBeTruthy() -- undo paint bank1 first
    expect(ur:undo(app)).toBeFalsy()

    -- Redo all
    expect(ur:redo(app)).toBeTruthy() -- redo paint bank1 first
    expect(ur:redo(app)).toBeTruthy() -- redo static removal (winA 0,0)
    expect(winA.layers[1].removedCells[1]).toBeTruthy()
    expect(ur:redo(app)).toBeTruthy() -- redo paint bank2
    expect(ur:redo(app)).toBeTruthy() -- redo ppu removal (winB 1,1)
    expect(winB.nametableBytes[4]).toBe(55)
    expect(ur:redo(app)).toBeTruthy() -- redo ppu removal (winB 0,0)
    expect(winB.nametableBytes[1]).toBe(99)
    expect(ur:redo(app)).toBeTruthy() -- redo paint bank1 second
    expect(ur:redo(app)).toBeTruthy() -- redo static removal (winA 1,1)
    expect(winA.layers[1].removedCells[4]).toBeTruthy()
    expect(ur:redo(app)).toBeFalsy()
  end)
end)

describe("UndoRedoController - tile_drag palette numbers on static layers", function()
  it("applies palette number changes on undo and redo", function()
    local ur = UndoRedoController.new(10)
    local layer = { kind = "tile", paletteNumbers = { [0] = 1 } }
    local win = { cols = 8, rows = 8, layers = { layer }, _closed = false }

    ur:addDragEvent({
      type = "tile_drag",
      mode = "palette",
      changes = {
        {
          win = win,
          layerIndex = 1,
          col = 0,
          row = 0,
          linearIndex = 0,
          before = 1,
          after = 3,
          isPaletteNumber = true,
        },
      },
    })

    layer.paletteNumbers[0] = 3
    expect(ur:undo({})).toBe(true)
    expect(layer.paletteNumbers[0]).toBe(1)

    expect(ur:redo({})).toBe(true)
    expect(layer.paletteNumbers[0]).toBe(3)
  end)
end)

describe("UndoRedoController - animation_window_state", function()
  it("restores layers and frame delays on undo", function()
    local ur = UndoRedoController.new(10)
    local AnimationWindowUndo = require("controllers.input_support.animation_window_undo")

    local frameA = { name = "A" }
    local frameB = { name = "B" }
    local win = {
      layers = { frameA },
      activeLayer = 1,
      frameDelays = { [1] = 0.1 },
      nonActiveLayerOpacity = 1.0,
      selectedByLayer = { [1] = nil },
      updateLayerOpacities = function() end,
    }

    local beforeState = AnimationWindowUndo.snapshot(win)
    win.layers = { frameA, frameB }
    win.activeLayer = 2
    win.frameDelays = { [1] = 0.2, [2] = 0.2 }
    local afterState = AnimationWindowUndo.snapshot(win)

    ur:addAnimationWindowStateEvent({
      type = "animation_window_state",
      win = win,
      beforeState = beforeState,
      afterState = afterState,
    })

    expect(#win.layers).toBe(2)
    expect(ur:undo({})).toBe(true)
    expect(#win.layers).toBe(1)
    expect(win.activeLayer).toBe(1)
    expect(win.frameDelays[1]).toBe(0.1)

    expect(ur:redo({})).toBe(true)
    expect(#win.layers).toBe(2)
    expect(win.activeLayer).toBe(2)
    expect(win.frameDelays[2]).toBe(0.2)
  end)
end)

describe("UndoRedoController - grid_layout", function()
  it("undoes and redoes grid dimensions and tile layer maps", function()
    local ur = UndoRedoController.new(10)
    local GridLayoutUndo = require("controllers.input_support.grid_layout_undo")
    local tileRef = { index = 5 }
    local win = {
      kind = "animation",
      cols = 8,
      rows = 8,
      visibleCols = 8,
      visibleRows = 8,
      scrollCol = 0,
      scrollRow = 0,
      activeLayer = 1,
      selectedByLayer = {},
      setScroll = function(self, c, r)
        self.scrollCol = c
        self.scrollRow = r
      end,
      updateLayerOpacities = function() end,
      layers = {
        {
          kind = "tile",
          items = { [17] = tileRef },
          paletteNumbers = { [13] = 2 },
        },
      },
    }

    local beforeState = GridLayoutUndo.snapshot(win)
    win.cols = 9
    win.visibleCols = 9
    win.layers[1].items = { [18] = tileRef }
    win.layers[1].paletteNumbers = { [14] = 2 }
    local afterState = GridLayoutUndo.snapshot(win)

    ur:addGridLayoutEvent({
      type = "grid_layout",
      win = win,
      beforeState = beforeState,
      afterState = afterState,
    })

    expect(win.cols).toBe(9)
    expect(ur:undo({})).toBe(true)
    expect(win.cols).toBe(8)
    expect(win.layers[1].items[17]).toBe(tileRef)
    expect(win.layers[1].paletteNumbers[13]).toBe(2)

    expect(ur:redo({})).toBe(true)
    expect(win.cols).toBe(9)
    expect(win.layers[1].items[18]).toBe(tileRef)
    expect(win.layers[1].paletteNumbers[14]).toBe(2)
  end)
end)

describe("UndoRedoController - sprite mirror drag events", function()
  it("undoes and redoes mirror fields with shared OAM sync options", function()
    local ur = UndoRedoController.new(10)

    local source = {
      startAddr = 0x1200,
      baseX = 20, baseY = 30,
      worldX = 20, worldY = 30, x = 20, y = 30,
      dx = 0, dy = 0, hasMoved = false, removed = false,
      mirrorX = true, mirrorY = false,
      attr = 0x40, paletteNumber = 1,
    }
    local shared = {
      startAddr = 0x1200,
      baseX = 40, baseY = 30,
      worldX = 40, worldY = 30, x = 40, y = 30,
      dx = 0, dy = 0, hasMoved = false, removed = false,
      mirrorX = true, mirrorY = false,
      attr = 0x40, paletteNumber = 1,
    }
    local layer = { kind = "sprite", items = { source, shared } }
    local win = { kind = "oam_animation", layers = { layer } }

    local ok = ur:addDragEvent({
      type = "sprite_drag",
      mode = "mirror",
      sync = {
        syncPosition = false,
        syncVisual = true,
        syncAttr = true,
      },
      actions = {
        {
          win = win,
          layerIndex = 1,
          sprite = source,
          before = {
            worldX = 20, worldY = 30, x = 20, y = 30,
            dx = 0, dy = 0, hasMoved = false, removed = false,
            mirrorXSet = true, mirrorX = false, mirrorYSet = true, mirrorY = false,
            attrSet = true, attr = 0x00,
            paletteNumberSet = true, paletteNumber = 1,
          },
          after = {
            worldX = 20, worldY = 30, x = 20, y = 30,
            dx = 0, dy = 0, hasMoved = false, removed = false,
            mirrorXSet = true, mirrorX = true, mirrorYSet = true, mirrorY = false,
            attrSet = true, attr = 0x40,
            paletteNumberSet = true, paletteNumber = 1,
          },
        },
      },
    })

    expect(ok).toBe(true)
    expect(source.mirrorX).toBe(true)
    expect(shared.mirrorX).toBe(true)
    expect(source.attr).toBe(0x40)
    expect(shared.attr).toBe(0x40)
    expect(shared.worldX).toBe(40)

    expect(ur:undo({})).toBe(true)
    expect(source.mirrorX).toBe(false)
    expect(shared.mirrorX).toBe(false)
    expect(source.mirrorY).toBe(false)
    expect(shared.mirrorY).toBe(false)
    expect(source.attr).toBe(0x00)
    expect(shared.attr).toBe(0x00)
    expect(shared.worldX).toBe(40)

    expect(ur:redo({})).toBe(true)
    expect(source.mirrorX).toBe(true)
    expect(shared.mirrorX).toBe(true)
    expect(source.attr).toBe(0x40)
    expect(shared.attr).toBe(0x40)
    expect(shared.worldX).toBe(40)
  end)
end)

describe("UndoRedoController - sprite binding (edit sprite modal)", function()
  it("undoes and redoes bank, tile, startAddr, and tileBelow", function()
    local ur = UndoRedoController.new(10)
    local layer = { kind = "sprite", mode = "8x8", items = {} }
    local s = {
      bank = 2,
      tile = 20,
      startAddr = 0x0200,
      tileBelow = nil,
    }
    layer.items[1] = s
    local win = { kind = "oam_animation", layers = { layer } }

    local ok = ur:addDragEvent({
      type = "sprite_drag",
      mode = "sprite_binding",
      actions = {
        {
          win = win,
          layerIndex = 1,
          sprite = s,
          before = {
            bank = 1,
            tile = 10,
            startAddr = 0x0100,
            tileBelow = nil,
          },
          after = {
            bank = 2,
            tile = 20,
            startAddr = 0x0200,
            tileBelow = nil,
          },
        },
      },
    })

    expect(ok).toBe(true)
    expect(s.bank).toBe(2)
    expect(s.tile).toBe(20)
    expect(s.startAddr).toBe(0x0200)

    local app = { appEditState = { romRaw = "", tilesPool = {} } }
    expect(ur:undo(app)).toBe(true)
    expect(s.bank).toBe(1)
    expect(s.tile).toBe(10)
    expect(s.startAddr).toBe(0x0100)

    expect(ur:redo(app)).toBe(true)
    expect(s.bank).toBe(2)
    expect(s.tile).toBe(20)
    expect(s.startAddr).toBe(0x0200)
  end)
end)

describe("UndoRedoController - sprite layer origin", function()
  it("undoes and redoes sprite layer originX/originY", function()
    local ur = UndoRedoController.new(10)
    local layer = { kind = "sprite", originX = 10, originY = 20 }
    local toolbar = { refreshes = 0 }
    function toolbar:updateOriginButtons()
      self.refreshes = self.refreshes + 1
    end

    local win = {
      kind = "ppu_frame",
      layers = { layer },
      specializedToolbar = toolbar,
    }

    layer.originX = 50
    layer.originY = 88

    expect(ur:addSpriteLayerOriginEvent({
      type = "sprite_layer_origin",
      win = win,
      layerIndex = 1,
      beforeOriginX = 10,
      beforeOriginY = 20,
      afterOriginX = 50,
      afterOriginY = 88,
    })).toBe(true)

    expect(toolbar.refreshes).toBe(0)

    expect(ur:undo({})).toBe(true)
    expect(layer.originX).toBe(10)
    expect(layer.originY).toBe(20)
    expect(toolbar.refreshes).toBe(1)

    expect(ur:redo({})).toBe(true)
    expect(layer.originX).toBe(50)
    expect(layer.originY).toBe(88)
    expect(toolbar.refreshes).toBe(2)

    local ur2 = UndoRedoController.new(5)
    expect(ur2:addSpriteLayerOriginEvent({
      type = "sprite_layer_origin",
      win = win,
      layerIndex = 1,
      beforeOriginX = 12,
      beforeOriginY = 12,
      afterOriginX = 12,
      afterOriginY = 12,
    })).toBe(false)
    expect(#ur2.stack).toBe(0)
  end)
end)

describe("UndoRedoController - window close", function()
  it("undos/redos a closed window and restores prior focus", function()
    local ur = UndoRedoController.new(10)

    local winA = { title = "A", _closed = false, _minimized = false }
    local winB = { title = "B", _closed = false, _minimized = false }
    local wm = {
      focused = winB,
      getFocus = function(self)
        return self.focused
      end,
      closeWindow = function(self, win)
        if not win or win._closed then return false end
        win._closed = true
        win._minimized = false
        if self.focused == win then
          self.focused = winA
        end
        return true
      end,
      reopenWindow = function(self, win, opts)
        opts = opts or {}
        if not win or not win._closed then return false end
        win._closed = false
        win._minimized = (opts.minimized == true)
        if opts.focus == true and not win._minimized then
          self.focused = win
        end
        return true
      end,
    }

    local event = {
      type = "window_close",
      win = winB,
      wm = wm,
      prevClosed = false,
      prevMinimized = false,
      prevFocused = true,
    }

    expect(ur:addWindowEvent(event)).toBe(true)
    expect(wm:closeWindow(winB)).toBe(true)
    expect(winB._closed).toBe(true)
    expect(wm:getFocus()).toBe(winA)

    expect(ur:undo({ wm = wm })).toBe(true)
    expect(winB._closed).toBe(false)
    expect(wm:getFocus()).toBe(winB)

    expect(ur:redo({ wm = wm })).toBe(true)
    expect(winB._closed).toBe(true)
    expect(wm:getFocus()).toBe(winA)
  end)

  it("supports fallback apply when window manager helpers are unavailable", function()
    local ur = UndoRedoController.new(10)
    local win = { _closed = false, _minimized = false }

    expect(ur:addWindowEvent({
      type = "window_close",
      win = win,
      prevClosed = false,
      prevMinimized = false,
      prevFocused = false,
    })).toBe(true)

    win._closed = true
    expect(ur:undo({})).toBe(true)
    expect(win._closed).toBe(false)

    expect(ur:redo({})).toBe(true)
    expect(win._closed).toBe(true)
  end)
end)

describe("UndoRedoController - window minimize", function()
  it("undos/redos window minimize transitions and restores focus snapshot", function()
    local ur = UndoRedoController.new(10)

    local winA = { title = "A", _closed = false, _minimized = false }
    local winB = { title = "B", _closed = false, _minimized = false }
    local wm = {
      focused = winB,
      getFocus = function(self)
        return self.focused
      end,
      minimizeWindow = function(self, win)
        if not win or win._closed or win._minimized then
          return false
        end
        win._minimized = true
        if self.focused == win then
          self.focused = winA
        end
        return true
      end,
      restoreMinimizedWindow = function(self, win, opts)
        opts = opts or {}
        if not win or win._closed or not win._minimized then
          return false
        end
        win._minimized = false
        if opts.focus ~= false then
          self.focused = win
        end
        return true
      end,
      setFocus = function(self, win)
        self.focused = win
      end,
    }

    expect(wm:minimizeWindow(winB)).toBe(true)
    expect(winB._minimized).toBe(true)
    expect(wm:getFocus()).toBe(winA)

    expect(ur:addWindowMinimizeEvent({
      type = "window_minimize",
      win = winB,
      wm = wm,
      beforeMinimized = false,
      afterMinimized = true,
      beforeFocusedWin = winB,
      afterFocusedWin = winA,
    })).toBe(true)

    expect(ur:undo({ wm = wm })).toBe(true)
    expect(winB._minimized).toBe(false)
    expect(wm:getFocus()).toBe(winB)

    expect(ur:redo({ wm = wm })).toBe(true)
    expect(winB._minimized).toBe(true)
    expect(wm:getFocus()).toBe(winA)
  end)

  it("minimize all except records one batch event; undo restores all in one step", function()
    local ur = UndoRedoController.new(10)
    local wm = WM.new()

    local winA = { title = "A", _closed = false, _minimized = false }
    local winB = { title = "B", _closed = false, _minimized = false }
    local winKeep = { title = "Keep", _closed = false, _minimized = false }
    wm:add(winA)
    wm:add(winB)
    wm:add(winKeep)
    wm:setFocus(winB)

    local prevCtx = rawget(_G, "ctx")
    _G.ctx = { app = { undoRedo = ur, wm = wm } }
    expect(wm:minimizeAllExcept(winKeep)).toBe(true)
    _G.ctx = prevCtx

    expect(winA._minimized).toBe(true)
    expect(winB._minimized).toBe(true)
    expect(winKeep._minimized).toBe(false)
    expect(wm:getFocus()).toBe(winKeep)
    expect(#ur.stack).toBe(1)
    expect(ur.stack[1].type).toBe("window_minimize_batch")

    local app = { wm = wm }
    expect(ur:undo(app)).toBe(true)
    expect(winA._minimized).toBe(false)
    expect(winB._minimized).toBe(false)
    expect(wm:getFocus()).toBe(winB)

    expect(ur:redo(app)).toBe(true)
    expect(winA._minimized).toBe(true)
    expect(winB._minimized).toBe(true)
    expect(wm:getFocus()).toBe(winKeep)
  end)

  it("minimize all records one batch; undo restores all in one step", function()
    local ur = UndoRedoController.new(10)
    local wm = WM.new()
    local winA = { title = "A", _closed = false, _minimized = false }
    local winB = { title = "B", _closed = false, _minimized = false }
    wm:add(winA)
    wm:add(winB)
    wm:setFocus(winB)

    local prevCtx = rawget(_G, "ctx")
    _G.ctx = { app = { undoRedo = ur, wm = wm } }
    expect(wm:minimizeAll()).toBe(true)
    _G.ctx = prevCtx

    expect(winA._minimized).toBe(true)
    expect(winB._minimized).toBe(true)
    expect(#ur.stack).toBe(1)
    expect(ur.stack[1].type).toBe("window_minimize_all")

    local app = { wm = wm }
    expect(ur:undo(app)).toBe(true)
    expect(winA._minimized).toBe(false)
    expect(winB._minimized).toBe(false)
    expect(wm:getFocus()).toBe(winB)

    expect(ur:redo(app)).toBe(true)
    expect(winA._minimized).toBe(true)
    expect(winB._minimized).toBe(true)
  end)

  it("maximize all records one batch; undo re-minimizes all restored windows in one step", function()
    local ur = UndoRedoController.new(10)
    local wm = WM.new()
    local winA = { title = "A", _closed = false, _minimized = true, _collapsed = false }
    local winB = { title = "B", _closed = false, _minimized = true, _collapsed = false }
    wm:add(winA)
    wm:add(winB)
    wm.focused = nil

    local prevCtx = rawget(_G, "ctx")
    _G.ctx = { app = { undoRedo = ur, wm = wm } }
    expect(wm:maximizeAll()).toBe(true)
    _G.ctx = prevCtx

    expect(winA._minimized).toBe(false)
    expect(winB._minimized).toBe(false)
    expect(#ur.stack).toBe(1)
    expect(ur.stack[1].type).toBe("window_restore_minimized_all")

    local app = { wm = wm }
    expect(ur:undo(app)).toBe(true)
    expect(winA._minimized).toBe(true)
    expect(winB._minimized).toBe(true)

    expect(ur:redo(app)).toBe(true)
    expect(winA._minimized).toBe(false)
    expect(winB._minimized).toBe(false)
  end)

  it("collapse all records one batch; undo restores layout", function()
    local ur = UndoRedoController.new(10)
    local wm = WM.new()

    local wB = wm:createTileWindow({
      animated = false,
      cols = 4,
      rows = 4,
      zoom = 2,
      title = "B",
    })
    local wA = wm:createTileWindow({
      animated = false,
      cols = 4,
      rows = 4,
      zoom = 2,
      title = "A",
    })
    wB.x, wB.y = 100, 200
    wA.x, wA.y = 300, 400
    wm:setFocus(wA)

    local prevCtx = rawget(_G, "ctx")
    _G.ctx = { app = { undoRedo = ur, wm = wm } }
    wm:collapseAll({
      areaX = 0,
      areaY = 0,
      areaH = 500,
      gapX = 8,
      gapY = 2,
    })
    _G.ctx = prevCtx

    expect(wA._collapsed).toBe(true)
    expect(#ur.stack).toBe(1)
    expect(ur.stack[1].type).toBe("window_collapse_all")

    expect(ur:undo({ wm = wm })).toBe(true)
    expect(wA._collapsed).toBe(false)
    expect(wA.x).toBe(300)
    expect(wA.y).toBe(400)
    expect(wB.x).toBe(100)
    expect(wB.y).toBe(200)
    expect(wA.zoom).toBe(2)

    expect(ur:redo({ wm = wm })).toBe(true)
    expect(wA._collapsed).toBe(true)
    expect(wB._collapsed).toBe(true)
  end)

  it("expand all records one batch; undo re-collapses in one step", function()
    local ur = UndoRedoController.new(10)
    local wm = WM.new()
    local w1 = { _closed = false, _minimized = false, _collapsed = true }
    local w2 = { _closed = false, _minimized = false, _collapsed = true }
    wm.windows = { w1, w2 }

    local prevCtx = rawget(_G, "ctx")
    _G.ctx = { app = { undoRedo = ur, wm = wm } }
    expect(wm:expandAll()).toBe(true)
    _G.ctx = prevCtx

    expect(w1._collapsed).toBe(false)
    expect(w2._collapsed).toBe(false)
    expect(#ur.stack).toBe(1)
    expect(ur.stack[1].type).toBe("window_expand_all")

    expect(ur:undo({ wm = wm })).toBe(true)
    expect(w1._collapsed).toBe(true)
    expect(w2._collapsed).toBe(true)

    expect(ur:redo({ wm = wm })).toBe(true)
    expect(w1._collapsed).toBe(false)
    expect(w2._collapsed).toBe(false)
  end)
end)

describe("UndoRedoController - ppu frame range", function()
  it("undos/redos ppu_frame_range events through applyPpuFrameRangeState", function()
    local ur = UndoRedoController.new(10)

    local win = { kind = "ppu_frame" }
    local beforeState = { win = win, layerState = { patternTable = { ranges = {} } } }
    local afterState = { win = win, layerState = { patternTable = { ranges = { { bank = 1, page = 1, from = 0, to = 15 } } } } }

    local pushed = ur:addPpuFrameRangeEvent({
      type = "ppu_frame_range",
      win = win,
      layerIndex = 1,
      beforeState = beforeState,
      afterState = afterState,
    })
    expect(pushed).toBe(true)

    local appliedStates = {}
    local app = {
      applyPpuFrameRangeState = function(_, state)
        appliedStates[#appliedStates + 1] = state
        return true
      end,
    }

    expect(ur:undo(app)).toBe(true)
    expect(appliedStates[1]).toBe(beforeState)

    expect(ur:redo(app)).toBe(true)
    expect(appliedStates[2]).toBe(afterState)
  end)
end)

describe("UndoRedoController - pattern table link", function()
  it("undo restores pre-link state; redo reattaches live pattern table from window manager", function()
    local TableUtils = require("utils.table_utils")

    local ptShared = { ranges = { { from = 0, to = 255, bank = 1, page = 1 } } }
    local ptWin = { _id = "pt_a", layers = { { patternTable = ptShared } } }
    local wm = {
      _windows = { ptWin },
      getWindows = function(self)
        return self._windows
      end,
    }

    local spriteLayer = {
      kind = "sprite",
      linkedPatternTableWindowId = nil,
      patternTable = { ranges = {} },
    }
    local contentWin = { kind = "ppu_frame", layers = { spriteLayer } }

    local refreshCalls = 0
    local app = {
      wm = wm,
      _afterPatternTableLinkChange = function()
        refreshCalls = refreshCalls + 1
      end,
    }

    spriteLayer.linkedPatternTableWindowId = "pt_a"
    spriteLayer.patternTable = ptShared

    local ur = UndoRedoController.new(10)
    ur:addPatternTableLinkEvent({
      type = "pattern_table_link",
      actions = {
        {
          win = contentWin,
          layerIndex = 1,
          beforeLinkedId = nil,
          afterLinkedId = "pt_a",
          beforePatternTable = { ranges = {} },
          afterPatternTable = TableUtils.deepcopy(ptShared),
        },
      },
    })

    expect(ur:undo(app)).toBe(true)
    expect(spriteLayer.linkedPatternTableWindowId).toBeNil()
    expect(#spriteLayer.patternTable.ranges).toBe(0)

    expect(ur:redo(app)).toBe(true)
    expect(spriteLayer.linkedPatternTableWindowId).toBe("pt_a")
    expect(spriteLayer.patternTable).toBe(ptShared)

    expect(refreshCalls).toBe(2)
  end)
end)
