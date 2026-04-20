local KeyboardInput = require("controllers.input.keyboard_input")
local CursorsController = require("controllers.input_support.cursors_controller")
local Tile = require("user_interface.windows_system.tile_item")
local Window = require("user_interface.windows_system.window")

describe("keyboard_input.lua - delete key on sprite selections", function()
  it("applies sprite delete rules by window kind (static/animation/oam allow)", function()
    local cases = {
      { kind = "static_art", expectBlocked = false, expectedStatus = "Deleted sprite" },
      { kind = "animation", expectBlocked = false, expectedStatus = "Deleted sprite" },
      { kind = "oam_animation", expectBlocked = false, expectedStatus = "Deleted sprite" },
    }

    for _, case in ipairs(cases) do
      local status
      local events = {}
      local undoRedo = {
        addRemovalEvent = function(self, ev)
          table.insert(events, ev)
        end,
      }

      local layer = {
        kind = "sprite",
        items = {
          { bank = 0, tile = 1 },
        },
        selectedSpriteIndex = 1,
        multiSpriteSelection = nil,
      }

      local win = {
        kind = case.kind,
        layers = { layer },
        getActiveLayerIndex = function() return 1 end,
      }

      local ctx = {
        getMode = function() return "tile" end,
        setMode = function() end,
        getFocus = function() return win end,
        setStatus = function(msg) status = msg end,
        setColor = function() end,
        wm = function() return nil end,
        app = { undoRedo = undoRedo },
      }

      KeyboardInput.setup(ctx, {
        ctrlDown = function() return false end,
        shiftDown = function() return false end,
        altDown = function() return false end,
      })

      KeyboardInput.keypressed("delete", ctx.app)

      expect(status).toBe(case.expectedStatus)
      if case.expectBlocked then
        expect(layer.items[1].removed).toBeNil()
        expect(#events).toBe(0)
      else
        expect(layer.items[1].removed).toBe(true)
        expect(#events).toBe(1)
      end
    end
  end)

  it("deletes all selected sprites and records undo actions", function()
    local status
    local events = {}
    local undoRedo = {
      addRemovalEvent = function(self, ev)
        table.insert(events, ev)
      end,
    }

    local layer = {
      kind = "sprite",
      items = {
        { bank = 0, tile = 1 },
        { bank = 0, tile = 2 },
        { bank = 0, tile = 3, removed = true }, -- already removed, should be skipped
      },
      selectedSpriteIndex = 2,
      multiSpriteSelection = { [1] = true, [2] = true, [3] = true },
    }

    local win = {
      kind = "animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      wm = function() return nil end,
      app = { undoRedo = undoRedo },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("delete", ctx.app)

    expect(layer.items[1].removed).toBe(true)
    expect(layer.items[2].removed).toBe(true)
    expect(layer.items[3].removed).toBe(true) -- unchanged (already removed)

    expect(layer.selectedSpriteIndex).toBeNil()
    expect(layer.multiSpriteSelection).toBeNil()
    expect(layer.hoverSpriteIndex).toBeNil()

    expect(status).toBe("Deleted 2 sprites")

    expect(#events).toBe(1)
    expect(#events[1].actions).toBe(2)
    expect(events[1].actions[1].spriteIndex).toBe(1)
    expect(events[1].actions[2].spriteIndex).toBe(2)
  end)
end)

describe("keyboard_input.lua - modifier status hints", function()
  it("restores previous status after releasing Shift when no item is selected", function()
    local status = "Ready"
    local shiftDown = false

    local layer = { kind = "tile" }
    local win = {
      kind = "static_art",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return nil, nil, nil end,
      get = function() return nil end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      getStatus = function() return status end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return shiftDown end,
      altDown = function() return false end,
    })

    shiftDown = true
    KeyboardInput.keypressed("lshift", ctx.app)
    expect(status).toBe("Up/Down = change layer, Left/Right = change frame delay")

    shiftDown = false
    KeyboardInput.keyreleased("lshift", ctx.app)
    expect(status).toBe("Ready")
  end)

  it("shows tile marquee hint while Shift is pressed with a tile selected", function()
    local status = "Idle"
    local shiftDown = false
    local tile = { index = 1 }
    local layer = { kind = "tile", items = { [1] = tile } }
    local win = {
      kind = "static_art",
      cols = 1,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return tile end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      getStatus = function() return status end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return shiftDown end,
      altDown = function() return false end,
    })

    shiftDown = true
    KeyboardInput.keypressed("lshift", ctx.app)

    expect(status).toBe("Shift + Drag = marquee select copy")
  end)

  it("shows edit-mode flood fill hint while F is pressed", function()
    local status = "Idle"
    local fillDown = false

    local ctx = {
      getMode = function() return "edit" end,
      setMode = function() end,
      getFocus = function() return nil end,
      getStatus = function() return status end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      fillDown = function() return fillDown end,
      grabDown = function() return false end,
      altDown = function() return false end,
    })

    fillDown = true
    KeyboardInput.keypressed("f", ctx.app)
    expect(status).toBe("Hold F + Click = flood fill")

    fillDown = false
    KeyboardInput.keyreleased("f", ctx.app)
    expect(status).toBe("Idle")
  end)

  it("shows edit-mode color grab hint while G is pressed", function()
    local status = "Idle"
    local grabDown = false

    local ctx = {
      getMode = function() return "edit" end,
      setMode = function() end,
      getFocus = function() return nil end,
      getStatus = function() return status end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      fillDown = function() return false end,
      grabDown = function() return grabDown end,
      altDown = function() return false end,
    })

    grabDown = true
    KeyboardInput.keypressed("g", ctx.app)
    expect(status).toBe("Hold G + Click/Drag = grab color")

    grabDown = false
    KeyboardInput.keyreleased("g", ctx.app)
    expect(status).toBe("Idle")
  end)

  it("toggles the rect fill tool with R in edit mode", function()
    local status = "Idle"
    local app = { editTool = "pencil" }
    local appliedCursorMode = nil
    local originalApplyModeCursor = CursorsController.applyModeCursor
    CursorsController.applyModeCursor = function(_, mode)
      appliedCursorMode = mode
    end

    local ctx = {
      getMode = function() return "edit" end,
      setMode = function() end,
      getFocus = function() return nil end,
      getStatus = function() return status end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = app,
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      fillDown = function() return false end,
      grabDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("r", ctx.app)
    expect(app.editTool).toBe("rect_fill")
    expect(appliedCursorMode).toBe("edit")
    expect(status).toBe("Rect fill tool")

    appliedCursorMode = nil
    KeyboardInput.keypressed("r", ctx.app)
    expect(app.editTool).toBe("pencil")
    expect(appliedCursorMode).toBe("edit")
    expect(status).toBe("Pencil tool")

    CursorsController.applyModeCursor = originalApplyModeCursor
  end)

  it("routes Ctrl+G to grid toggle outside edit mode", function()
    local status = "Idle"
    local focus = { showGrid = "off" }
    local ctrlDown = false

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return focus end,
      getStatus = function() return status end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return ctrlDown end,
      shiftDown = function() return false end,
      fillDown = function() return false end,
      grabDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("g", ctx.app)
    expect(status).toBe("Idle")

    ctrlDown = true
    KeyboardInput.keypressed("g", ctx.app)
    expect(status).toBe("Grid: chess")
  end)

  it("shows offset hint while Alt is pressed with an active selection", function()
    local status = "Idle"
    local altDown = false
    local tile = { index = 1 }
    local layer = { kind = "tile", items = { [1] = tile } }
    local win = {
      kind = "static_art",
      cols = 1,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return tile end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      getStatus = function() return status end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return altDown end,
    })

    altDown = true
    KeyboardInput.keypressed("lalt", ctx.app)

    expect(status).toBe("Alt + Arrows = offset pixels")
  end)

  it("shows animation add-layer hint while Ctrl is pressed", function()
    local status = "Idle"
    local ctrlDown = false
    local layer = { kind = "tile" }
    local win = {
      kind = "animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return nil, nil, nil end,
      get = function() return nil end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      getStatus = function() return status end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return ctrlDown end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    ctrlDown = true
    KeyboardInput.keypressed("lctrl", ctx.app)

    expect(status).toBe("Press + or = to add a new layer")
  end)
end)

describe("keyboard_input.lua - CHR mode status", function()
  it("formats order mode status correctly when toggled with keyboard", function()
    local status = nil
    local win = {
      kind = "chr",
      orderMode = "normal",
      currentBank = 1,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      rebuildChrBankWindow = function() end,
      wm = function()
        return {
          getFocus = function() return win end,
        }
      end,
      app = {
        appEditState = {
          chrBanksBytes = { "bank1" },
        }
      },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("m", ctx.app)

    expect(win.orderMode).toBe("oddEven")
    expect(status).toBe("Order mode: 8x16")
  end)

  it("switches CHR banks by changing the active layer instead of rebuilding the window", function()
    local status = nil
    local shiftCalls = 0
    local rebuildCalls = 0
    local win = {
      kind = "chr",
      orderMode = "normal",
      currentBank = 2,
      activeLayer = 2,
      shiftBank = function(self, delta)
        shiftCalls = shiftCalls + 1
        self.currentBank = self.currentBank + delta
        self.activeLayer = self.currentBank
      end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      rebuildChrBankWindow = function()
        rebuildCalls = rebuildCalls + 1
      end,
      wm = function()
        return {
          getFocus = function() return win end,
        }
      end,
      app = {
        appEditState = {
          chrBanksBytes = { "bank1", "bank2", "bank3" },
          currentBank = 2,
        }
      },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("right", ctx.app)

    expect(shiftCalls).toBe(1)
    expect(rebuildCalls).toBe(0)
    expect(win.currentBank).toBe(3)
    expect(win.activeLayer).toBe(3)
    expect(ctx.app.appEditState.currentBank).toBe(3)
    expect(status).toBe("Bank 3/3")
  end)
end)

describe("keyboard_input.lua - ctrl+a select all", function()
  it("selects all non-removed sprites in the active sprite layer", function()
    local status
    local layer = {
      kind = "sprite",
      items = {
        { tile = 1 },
        { tile = 2 },
        { tile = 3, removed = true },
        { tile = 4 },
      },
    }

    local win = {
      kind = "animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return true end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("a", ctx.app)

    expect(layer.selectedSpriteIndex).toBe(1)
    expect(layer.multiSpriteSelection).toBeTruthy()
    expect(layer.multiSpriteSelection[1]).toBe(true)
    expect(layer.multiSpriteSelection[2]).toBe(true)
    expect(layer.multiSpriteSelection[3]).toBeNil()
    expect(layer.multiSpriteSelection[4]).toBe(true)
    expect(status).toBe("Selected 3 sprites")
  end)

  it("selects all non-removed tiles in the active tile layer", function()
    local status
    local selected = nil
    local cols = 4
    local layer = {
      kind = "tile",
      items = {
        [1] = { id = "a" },
        [2] = { id = "b" },
        [6] = { id = "removed" },
      },
      removedCells = { [6] = true },
    }

    local win = {
      kind = "static_art",
      cols = cols,
      rows = 2,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      get = function(_, c, r, _)
        local idx = (r * cols + c) + 1
        return layer.items[idx]
      end,
      setSelected = function(_, c, r, li)
        selected = { col = c, row = r, layer = li }
      end,
      clearSelected = function() end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return true end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("a", ctx.app)

    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[1]).toBe(true)
    expect(layer.multiTileSelection[2]).toBe(true)
    expect(layer.multiTileSelection[6]).toBeNil()
    expect(selected.col).toBe(0)
    expect(selected.row).toBe(0)
    expect(selected.layer).toBe(1)
    expect(status).toBe("Selected 2 tiles")
  end)
end)

describe("keyboard_input.lua - ctrl+c / ctrl+v", function()
  it("copies selected tiles and pastes them at the active selection anchor", function()
    local status = nil
    local unsavedEvents = {}
    local ctrl = true
    local cols, rows = 6, 4
    local selectedCol, selectedRow, selectedLayer = 0, 0, 1

    local tileA = { id = "A" }
    local tileB = { id = "B" }
    local layer = {
      kind = "tile",
      items = {
        [1] = tileA, -- (0,0)
        [2] = tileB, -- (1,0)
      },
      multiTileSelection = { [1] = true, [2] = true },
      removedCells = {},
    }

    local win = {
      kind = "static_art",
      cols = cols,
      rows = rows,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return selectedCol, selectedRow, selectedLayer end,
      setSelected = function(_, c, r, li)
        selectedCol, selectedRow, selectedLayer = c, r, li
      end,
      clearSelected = function() end,
      get = function(_, c, r, _)
        local idx = (r * cols + c) + 1
        return layer.items[idx]
      end,
      set = function(_, c, r, item, _)
        local idx = (r * cols + c) + 1
        layer.items[idx] = item
      end,
    }

    local app = {
      markUnsaved = function(_, eventType)
        unsavedEvents[#unsavedEvents + 1] = eventType
      end,
    }
    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = app,
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("c", ctx.app)
    selectedCol, selectedRow = 2, 1
    KeyboardInput.keypressed("v", ctx.app)

    local dstIdx1 = (1 * cols + 2) + 1 -- (2,1)
    local dstIdx2 = (1 * cols + 3) + 1 -- (3,1)
    expect(layer.items[1]).toBe(tileA)
    expect(layer.items[2]).toBe(tileB)
    expect(layer.items[dstIdx1]).toBe(tileA)
    expect(layer.items[dstIdx2]).toBe(tileB)
    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[dstIdx1]).toBe(true)
    expect(layer.multiTileSelection[dstIdx2]).toBe(true)
    expect(selectedCol).toBe(2)
    expect(selectedRow).toBe(1)
    expect(selectedLayer).toBe(1)
    expect(status).toBe("Pasted 2 tiles")
    expect(#unsavedEvents).toBe(1)
    expect(unsavedEvents[1]).toBe("tile_move")
  end)

  it("copies selected sprites and pastes them at sprite selection bounds anchor", function()
    local status = nil
    local unsavedEvents = {}
    local ctrl = true

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { worldX = 0, worldY = 0, baseX = 0, baseY = 0, x = 0, y = 0, dx = 0, dy = 0, removed = false },
        { worldX = 16, worldY = 8, baseX = 16, baseY = 8, x = 16, y = 8, dx = 0, dy = 0, removed = false },
      },
      selectedSpriteIndex = 1,
      multiSpriteSelection = { [1] = true, [2] = true },
    }

    local win = {
      kind = "animation",
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local app = {
      markUnsaved = function(_, eventType)
        unsavedEvents[#unsavedEvents + 1] = eventType
      end,
    }
    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = app,
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("c", ctx.app)
    KeyboardInput.keypressed("v", ctx.app)

    expect(#layer.items).toBe(4)

    local pastedA = layer.items[3]
    local pastedB = layer.items[4]
    expect(pastedA.worldX).toBe(0)
    expect(pastedA.worldY).toBe(0)
    expect(pastedB.worldX).toBe(16)
    expect(pastedB.worldY).toBe(8)
    expect(layer.multiSpriteSelection).toBeTruthy()
    expect(layer.multiSpriteSelection[3]).toBe(true)
    expect(layer.multiSpriteSelection[4]).toBe(true)
    expect(layer.selectedSpriteIndex).toBe(3)
    expect(status).toBe("Pasted 2 sprites")
    expect(#unsavedEvents).toBe(1)
    expect(unsavedEvents[1]).toBe("sprite_move")
  end)

  it("cuts selected tiles with ctrl+x and pastes with ctrl+v using shared clipboard flow", function()
    local status = nil
    local unsavedEvents = {}
    local ctrl = true
    local cols, rows = 4, 4
    local sourceLayer = {
      kind = "tile",
      items = {
        [1] = { id = "cut-me" },
      },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }

    local sourceWin = {
      kind = "static_art",
      cols = cols,
      rows = rows,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      clearSelected = function() end,
      get = function(_, c, r)
        return sourceLayer.items[(r * cols + c) + 1]
      end,
      markCellRemoved = function(_, c, r, _)
        sourceLayer.removedCells[(r * cols + c) + 1] = true
      end,
    }

    local targetLayer = { kind = "tile" }
    local targetWin = {
      kind = "static_art",
      cols = cols,
      rows = rows,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      clearSelected = function() end,
      setSelected = function() end,
      set = function(_, c, r, item, _)
        targetLayer.items = targetLayer.items or {}
        targetLayer.items[(r * cols + c) + 1] = item
      end,
    }

    local focus = sourceWin
    local app = {
      markUnsaved = function(_, eventType)
        unsavedEvents[#unsavedEvents + 1] = eventType
      end,
    }
    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return focus end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = app,
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("x", ctx.app)
    expect(status).toBe("Cut 1 tile")
    expect(sourceLayer.removedCells[1]).toBe(true)

    focus = targetWin
    KeyboardInput.keypressed("v", ctx.app)
    expect(status).toBe("Pasted 1 tile")
    expect(targetLayer.items).toBeTruthy()
    expect(#unsavedEvents).toBe(2)
    expect(unsavedEvents[1]).toBe("tile_move")
    expect(unsavedEvents[2]).toBe("tile_move")
  end)

  it("applies sprite paste rules by window kind (static/animation allow, oam blocks)", function()
    local cases = {
      { kind = "static_art", expectPasted = true, expectedStatus = "Pasted 1 sprite" },
      { kind = "animation", expectPasted = true, expectedStatus = "Pasted 1 sprite" },
      { kind = "oam_animation", expectPasted = false, expectedStatus = "Cannot add sprites to OAM animation windows" },
    }

    for _, case in ipairs(cases) do
      local status = nil
      local unsavedEvents = {}
      local ctrl = true

      local layer = {
        kind = "sprite",
        mode = "8x8",
        items = {
          { worldX = 0, worldY = 0, baseX = 0, baseY = 0, x = 0, y = 0, dx = 0, dy = 0, removed = false },
        },
        selectedSpriteIndex = 1,
        multiSpriteSelection = nil,
      }

      local win = {
        kind = case.kind,
        cols = 8,
        rows = 8,
        cellW = 8,
        cellH = 8,
        layers = { layer },
        getActiveLayerIndex = function() return 1 end,
      }

      local app = {
        markUnsaved = function(_, eventType)
          unsavedEvents[#unsavedEvents + 1] = eventType
        end,
      }
      local ctx = {
        getMode = function() return "tile" end,
        setMode = function() end,
        getFocus = function() return win end,
        setStatus = function(msg) status = msg end,
        setColor = function() end,
        wm = function() return nil end,
        app = app,
      }

      KeyboardInput.setup(ctx, {
        ctrlDown = function() return ctrl end,
        shiftDown = function() return false end,
        altDown = function() return false end,
      })

      KeyboardInput.keypressed("c", ctx.app)
      KeyboardInput.keypressed("v", ctx.app)

      expect(status).toBe(case.expectedStatus)
      if case.expectPasted then
        expect(#layer.items).toBe(2)
        expect(#unsavedEvents).toBe(1)
        expect(unsavedEvents[1]).toBe("sprite_move")
      else
        expect(#layer.items).toBe(1)
        expect(#unsavedEvents).toBe(0)
      end
    end
  end)

  it("allows cross-window tile-to-sprite paste via keyboard shortcuts", function()
    local status = nil
    local ctrl = true

    local tile = { _bankIndex = 1, index = 6, pixels = {} }
    for i = 1, 64 do tile.pixels[i] = (i % 4) end
    local tileLayer = {
      kind = "tile",
      items = { [1] = tile },
      multiTileSelection = { [1] = true },
    }
    local tileWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { tileLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return tile end,
    }

    local spriteLayer = { kind = "sprite", mode = "8x8", items = {} }
    local spriteWin = {
      kind = "animation",
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      layers = { spriteLayer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 1, 2, 0, 0 end,
    }

    local focus = tileWin
    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return focus end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("c", ctx.app)
    focus = spriteWin
    KeyboardInput.keypressed("v", ctx.app)

    expect(#spriteLayer.items).toBe(1)
    expect(spriteLayer.items[1].topRef).toBe(tile)
    expect(status).toBe("Pasted 1 sprite")
  end)

  it("allows cross-window sprite-to-tile paste via keyboard shortcuts", function()
    local status = nil
    local ctrl = true

    local topRef = { _bankIndex = 1, index = 9, pixels = {} }
    for i = 1, 64 do topRef.pixels[i] = (i % 4) end
    local spriteLayer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { topRef = topRef, worldX = 0, worldY = 0, x = 0, y = 0, baseX = 0, baseY = 0 },
      },
      selectedSpriteIndex = 1,
      multiSpriteSelection = { [1] = true },
    }
    local spriteWin = {
      kind = "animation",
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      layers = { spriteLayer },
      getActiveLayerIndex = function() return 1 end,
    }

    local tileLayer = { kind = "tile", items = {} }
    local tileWin = {
      kind = "static_art",
      cols = 8,
      rows = 8,
      layers = { tileLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 3, 1, 1 end,
      get = function(_, c, r)
        return tileLayer.items[(r * 8 + c) + 1]
      end,
      set = function(_, c, r, item)
        tileLayer.items[(r * 8 + c) + 1] = item
      end,
      setSelected = function() end,
    }

    local focus = spriteWin
    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return focus end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("c", ctx.app)
    focus = tileWin
    KeyboardInput.keypressed("v", ctx.app)

    expect(tileLayer.items[(1 * 8 + 3) + 1]).toBe(topRef)
    expect(status).toBe("Pasted 1 tile")
  end)
end)

describe("keyboard_input.lua - delete key on tile multi-selection", function()
  it("deletes all selected non-removed tiles and records undo actions", function()
    local status
    local events = {}
    local undoRedo = {
      addRemovalEvent = function(self, ev)
        table.insert(events, ev)
      end,
    }

    local cols = 4
    local layer = {
      kind = "tile",
      items = {
        [1] = { id = "a" },
        [2] = { id = "b" },
        [6] = { id = "already-removed" },
      },
      removedCells = { [6] = true },
      multiTileSelection = { [1] = true, [2] = true, [6] = true },
    }

    local win = {
      kind = "static_art",
      cols = cols,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      markCellRemoved = function(_, c, r, li)
        local idx = (r * cols + c) + 1
        layer.removedCells[idx] = true
      end,
      clearSelected = function(self, li)
        self._clearedLayer = li
      end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      wm = function() return nil end,
      app = { undoRedo = undoRedo },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("delete", ctx.app)

    expect(layer.removedCells[1]).toBe(true)
    expect(layer.removedCells[2]).toBe(true)
    expect(layer.removedCells[6]).toBe(true)
    expect(layer.multiTileSelection).toBeNil()
    expect(win._clearedLayer).toBe(1)
    expect(status).toBe("Deleted 2 items")

    expect(#events).toBe(1)
    expect(events[1].subtype).toBe("static")
    expect(#events[1].actions).toBe(2)
    expect(events[1].actions[1].col).toBe(0)
    expect(events[1].actions[1].row).toBe(0)
    expect(events[1].actions[2].col).toBe(1)
    expect(events[1].actions[2].row).toBe(0)
  end)
end)

describe("keyboard_input.lua - sprite palette assignment", function()
  it("applies palette to all selected sprites and updates ROM", function()
    local status
    local appEditState = { romRaw = string.rep("\0", 8) }

    local layer = {
      kind = "sprite",
      paletteData = {},
      items = {
        { bank = 0, tile = 1, attr = 0, startAddr = 0 },
        { bank = 0, tile = 2, attr = 0, startAddr = 1 },
        { bank = 0, tile = 3, attr = 0, removed = true, startAddr = 2 },
      },
      selectedSpriteIndex = 2,
      multiSpriteSelection = { [1] = true, [2] = true, [3] = true },
    }

    local win = {
      kind = "animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = { appEditState = appEditState },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("3", ctx.app)

    expect(layer.items[1].paletteNumber).toBe(3)
    expect(layer.items[2].paletteNumber).toBe(3)
    expect(layer.items[1].attr % 4).toBe(2) -- palette index stored in lower bits
    expect(layer.items[2].attr % 4).toBe(2)
    expect(layer.items[3].paletteNumber).toBeNil() -- skipped (removed)

    expect(string.byte(appEditState.romRaw, 3)).toBe(2) -- startAddr 0 + 2 (1-based idx 3)
    expect(string.byte(appEditState.romRaw, 4)).toBe(2) -- startAddr 1 + 2 (1-based idx 4)

    expect(status).toBe("Sprite palettes set to 3")
  end)

  it("applies sprite palette even when layer has no paletteData", function()
    local status
    local appEditState = { romRaw = string.rep("\0", 8) }

    local layer = {
      kind = "sprite",
      items = {
        { bank = 0, tile = 1, attr = 0, startAddr = 0 },
      },
      selectedSpriteIndex = 1,
      multiSpriteSelection = nil,
    }

    local win = {
      kind = "oam_animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = { appEditState = appEditState },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("4", ctx.app)

    expect(layer.items[1].paletteNumber).toBe(4)
    expect(layer.items[1].attr % 4).toBe(3)
    expect(string.byte(appEditState.romRaw, 3)).toBe(3)
    expect(status).toBe("Sprite palette set to 4")
  end)

  it("preserves mirror bits when writing sprite attr for palette change", function()
    local appEditState = { romRaw = string.rep("\0", 8) }

    local layer = {
      kind = "sprite",
      paletteData = {},
      items = {
        { bank = 0, tile = 1, attr = 0x00, mirrorX = true, mirrorY = true, startAddr = 0 },
      },
      selectedSpriteIndex = 1,
      multiSpriteSelection = nil,
    }

    local win = {
      kind = "animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = { appEditState = appEditState },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("2", ctx.app)

    expect(layer.items[1].attr).toBe(0xC1) -- mirror bits kept + palette bits for #2
    expect(string.byte(appEditState.romRaw, 3)).toBe(0xC1)
  end)
end)

describe("keyboard_input.lua - sprite mirroring", function()
  it("applies horizontal mirror toggle to all selected sprites", function()
    local status

    local layer = {
      kind = "sprite",
      items = {
        { bank = 0, tile = 1, mirrorX = false },
        { bank = 0, tile = 2, mirrorX = true },
        { bank = 0, tile = 3, removed = true, mirrorX = false },
      },
      selectedSpriteIndex = 2,
      multiSpriteSelection = { [1] = true, [2] = true, [3] = true },
    }

    local win = {
      kind = "animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("h", ctx.app)

    expect(layer.items[1].mirrorX).toBe(true)
    expect(layer.items[2].mirrorX).toBe(false)
    expect(layer.items[3].mirrorX).toBe(false)
    expect(status).toBe("Mirrored 2 sprites horizontally")
  end)

  it("records sprite mirror as an undoable sprite_drag event", function()
    local events = {}

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          bank = 0, tile = 1, attr = 0, paletteNumber = 1,
          mirrorX = false, mirrorY = false,
          baseX = 10, baseY = 20, worldX = 10, worldY = 20, x = 10, y = 20, dx = 0, dy = 0,
        },
        {
          bank = 0, tile = 2, attr = 0, paletteNumber = 1,
          mirrorX = false, mirrorY = false,
          baseX = 18, baseY = 20, worldX = 18, worldY = 20, x = 18, y = 20, dx = 0, dy = 0,
        },
      },
      selectedSpriteIndex = 1,
      multiSpriteSelection = { [1] = true, [2] = true },
    }

    local win = {
      kind = "animation",
      cellW = 8,
      cellH = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {
        undoRedo = {
          addDragEvent = function(_, ev)
            events[#events + 1] = ev
          end,
        },
      },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("h", ctx.app)

    expect(#events).toBe(1)
    local ev = events[1]
    expect(ev.type).toBe("sprite_drag")
    expect(ev.mode).toBe("mirror")
    expect(ev.sync.syncPosition).toBe(true)
    expect(ev.sync.syncVisual).toBe(true)
    expect(ev.sync.syncAttr).toBe(true)
    expect(#ev.actions).toBe(2)
    expect(ev.actions[1].before.mirrorX).toBe(false)
    expect(ev.actions[1].after.mirrorX).toBe(true)
    expect(ev.actions[1].before.worldX).toBe(10)
    expect(ev.actions[1].after.worldX).toBe(18)
    expect(ev.actions[2].before.worldX).toBe(18)
    expect(ev.actions[2].after.worldX).toBe(10)
  end)

  it("applies vertical mirror toggle to all selected sprites", function()
    local status

    local layer = {
      kind = "sprite",
      items = {
        { bank = 0, tile = 1, mirrorY = false },
        { bank = 0, tile = 2, mirrorY = false },
        { bank = 0, tile = 3, removed = true, mirrorY = true },
      },
      selectedSpriteIndex = 1,
      multiSpriteSelection = { [1] = true, [2] = true, [3] = true },
    }

    local win = {
      kind = "animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("v", ctx.app)

    expect(layer.items[1].mirrorY).toBe(true)
    expect(layer.items[2].mirrorY).toBe(true)
    expect(layer.items[3].mirrorY).toBe(true)
    expect(status).toBe("Mirrored 2 sprites vertically")
  end)
end)

describe("keyboard_input.lua - sprite group position mirroring", function()
  it("mirrors selected sprite world X positions across group bounds on H", function()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          bank = 0, tile = 1,
          mirrorX = false,
          baseX = 5, baseY = 10, worldX = 5, worldY = 10, x = 5, y = 10,
          dx = 0, dy = 0,
        },
        {
          bank = 0, tile = 2,
          mirrorX = false,
          baseX = 13, baseY = 12, worldX = 13, worldY = 12, x = 13, y = 12,
          dx = 0, dy = 0,
        },
      },
      selectedSpriteIndex = 1,
      multiSpriteSelection = { [1] = true, [2] = true },
    }

    local win = {
      kind = "animation",
      cellW = 8,
      cellH = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("h", ctx.app)

    expect(layer.items[1].mirrorX).toBe(true)
    expect(layer.items[2].mirrorX).toBe(true)
    expect(layer.items[1].worldX).toBe(13)
    expect(layer.items[2].worldX).toBe(5)
    expect(layer.items[1].x).toBe(13)
    expect(layer.items[2].x).toBe(5)
    expect(layer.items[1].dx).toBe(8)
    expect(layer.items[2].dx).toBe(-8)
  end)

  it("mirrors selected sprite world Y positions across group bounds on V (8x16)", function()
    local layer = {
      kind = "sprite",
      mode = "8x16",
      items = {
        {
          bank = 0, tile = 1,
          mirrorY = false,
          baseX = 40, baseY = 20, worldX = 40, worldY = 20, x = 40, y = 20,
          dx = 0, dy = 0,
        },
        {
          bank = 0, tile = 2,
          mirrorY = false,
          baseX = 48, baseY = 29, worldX = 48, worldY = 29, x = 48, y = 29,
          dx = 0, dy = 0,
        },
      },
      selectedSpriteIndex = 1,
      multiSpriteSelection = { [1] = true, [2] = true },
    }

    local win = {
      kind = "animation",
      cellW = 8,
      cellH = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("v", ctx.app)

    expect(layer.items[1].mirrorY).toBe(true)
    expect(layer.items[2].mirrorY).toBe(true)
    expect(layer.items[1].worldY).toBe(29)
    expect(layer.items[2].worldY).toBe(20)
    expect(layer.items[1].y).toBe(29)
    expect(layer.items[2].y).toBe(20)
    expect(layer.items[1].dy).toBe(9)
    expect(layer.items[2].dy).toBe(-9)
  end)
end)

describe("tile_item.lua - offsetPixels", function()
  it("offsets without wrapping by default", function()
    local bankBytes = {}
    for i = 1, 16 do bankBytes[i] = 0 end

    local tile = Tile.fromCHR(bankBytes, 0)
    tile._bankBytesRef = bankBytes
    tile._bankIndex = 1
    tile.index = 0

    for i = 1, 64 do tile.pixels[i] = 0 end
    tile.pixels[8] = 2 -- x=7, y=0
    tile:refreshImage()

    expect(tile:offsetPixels(1, 0)).toBe(true)
    expect(tile:getPixel(0, 0)).toBe(0)
    expect(tile:getPixel(7, 0)).toBe(0)

    expect(tile:offsetPixels(-1, 0)).toBe(true)
    expect(tile:getPixel(7, 0)).toBe(2)
  end)

  it("supports optional wrap mode", function()
    local bankBytes = {}
    for i = 1, 16 do bankBytes[i] = 0 end

    local tile = Tile.fromCHR(bankBytes, 0)
    tile._bankBytesRef = bankBytes
    tile._bankIndex = 1
    tile.index = 0

    for i = 1, 64 do tile.pixels[i] = 0 end
    tile.pixels[8] = 3 -- x=7, y=0
    tile:refreshImage()

    expect(tile:offsetPixels(1, 0, { wrap = true })).toBe(true)
    expect(tile:getPixel(0, 0)).toBe(3)
  end)
end)

describe("keyboard_input.lua - alt+arrow pixel offset", function()
  it("offsets selected tile pixels on alt+arrow", function()
    local status
    local unsavedEvents = {}

    local bankBytes = {}
    for i = 1, 16 do bankBytes[i] = 0 end
    local tile = Tile.fromCHR(bankBytes, 0)
    tile._bankBytesRef = bankBytes
    tile._bankIndex = 1
    tile.index = 0
    for i = 1, 64 do tile.pixels[i] = 0 end
    tile.pixels[1] = 3 -- x=0, y=0
    tile:refreshImage()

    local layer = { kind = "tile", items = { [1] = tile } }
    local win = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return tile end,
    }

    local app = {
      edits = {
        banks = {
          [1] = {
            [0] = {
              ["0_0"] = 3,
              ["1_0"] = 0,
            },
          },
        },
      },
      markUnsaved = function(_, eventType)
        unsavedEvents[#unsavedEvents + 1] = eventType
      end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = app,
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return true end,
    })

    KeyboardInput.keypressed("right", ctx.app)

    expect(tile:getPixel(0, 0)).toBe(0)
    expect(tile:getPixel(1, 0)).toBe(3)
    expect(status).toBe("Offset tile pixels right")
    expect(unsavedEvents[1]).toBe("pixel_edit")
    expect(app.edits.banks[1][0]["0_0"]).toBe(0)
    expect(app.edits.banks[1][0]["1_0"]).toBe(3)

    KeyboardInput.keypressed("left", ctx.app)
    expect(tile:getPixel(0, 0)).toBe(3)
    expect(app.edits.banks[1][0]["0_0"]).toBe(3)
    expect(app.edits.banks[1][0]["1_0"]).toBe(0)
  end)

  it("creates and stores tile edits when offsetting and app.edits is nil", function()
    local bankBytes = {}
    for i = 1, 16 do bankBytes[i] = 0 end
    local tile = Tile.fromCHR(bankBytes, 0)
    tile._bankBytesRef = bankBytes
    tile._bankIndex = 1
    tile.index = 0
    for i = 1, 64 do tile.pixels[i] = 0 end
    tile.pixels[1] = 2
    tile:refreshImage()

    local layer = { kind = "tile", items = { [1] = tile } }
    local win = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return tile end,
    }

    local app = {
      markUnsaved = function() end,
    }
    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = app,
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return true end,
    })

    KeyboardInput.keypressed("right", ctx.app)

    expect(app.edits).toBeTruthy()
    expect(app.edits.banks).toBeTruthy()
    expect(app.edits.banks[1]).toBeTruthy()
    expect(app.edits.banks[1][0]).toBeTruthy()
    expect(app.edits.banks[1][0]["0_0"]).toBe(0)
    expect(app.edits.banks[1][0]["1_0"]).toBe(2)
  end)

  it("offsets selected sprite tile pixels on alt+arrow", function()
    local status
    local unsavedEvents = {}

    local bankBytes = {}
    for i = 1, 16 do bankBytes[i] = 0 end
    local topTile = Tile.fromCHR(bankBytes, 0)
    topTile._bankBytesRef = bankBytes
    topTile._bankIndex = 1
    topTile.index = 0
    for i = 1, 64 do topTile.pixels[i] = 0 end
    topTile.pixels[1] = 1 -- x=0, y=0
    topTile:refreshImage()

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { topRef = topTile, removed = false },
      },
      selectedSpriteIndex = 1,
    }

    local win = {
      kind = "animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local app = {
      edits = {
        banks = {
          [1] = {
            [0] = {
              ["0_0"] = 1,
              ["0_1"] = 0,
            },
          },
        },
      },
      markUnsaved = function(_, eventType)
        unsavedEvents[#unsavedEvents + 1] = eventType
      end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = app,
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return true end,
    })

    KeyboardInput.keypressed("down", ctx.app)

    expect(topTile:getPixel(0, 0)).toBe(0)
    expect(topTile:getPixel(0, 1)).toBe(1)
    expect(status).toBe("Offset sprite pixels down")
    expect(unsavedEvents[1]).toBe("pixel_edit")
    expect(app.edits.banks[1][0]["0_0"]).toBe(0)
    expect(app.edits.banks[1][0]["0_1"]).toBe(1)
  end)

  it("offsets 8x16 sprite pixels as a continuous surface", function()
    local status
    local bankBytes = {}
    for i = 1, 32 do bankBytes[i] = 0 end

    local topTile = Tile.fromCHR(bankBytes, 0)
    topTile._bankBytesRef = bankBytes
    topTile._bankIndex = 1
    topTile.index = 0
    for i = 1, 64 do topTile.pixels[i] = 0 end
    topTile.pixels[60] = 2 -- row 7, col 3
    topTile:refreshImage()

    local botTile = Tile.fromCHR(bankBytes, 1)
    botTile._bankBytesRef = bankBytes
    botTile._bankIndex = 1
    botTile.index = 1
    for i = 1, 64 do botTile.pixels[i] = 0 end
    botTile:refreshImage()

    local layer = {
      kind = "sprite",
      mode = "8x16",
      items = {
        { topRef = topTile, botRef = botTile, removed = false },
      },
      selectedSpriteIndex = 1,
    }

    local win = {
      kind = "animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local app = {
      edits = { banks = {} },
    }
    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = app,
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return true end,
    })

    KeyboardInput.keypressed("down", ctx.app)
    expect(topTile:getPixel(3, 7)).toBe(0)
    expect(botTile:getPixel(3, 0)).toBe(2)
    expect(status).toBe("Offset sprite pixels down")
    expect(app.edits.banks[1]).toBeTruthy()
    expect(app.edits.banks[1][0]["3_7"]).toBe(0)
    expect(app.edits.banks[1][1]["3_0"]).toBe(2)

    KeyboardInput.keypressed("up", ctx.app)
    expect(topTile:getPixel(3, 7)).toBe(2)
    expect(botTile:getPixel(3, 0)).toBe(0)
    expect(status).toBe("Offset sprite pixels up")
    expect(app.edits.banks[1][0]["3_7"]).toBe(2)
    expect(app.edits.banks[1][1]["3_0"]).toBe(0)
  end)

  it("offsets selected CHR tile pixels on alt+arrow without bank switching", function()
    local status
    local unsavedEvents = {}

    local bankBytes = {}
    for i = 1, 16 do bankBytes[i] = 0 end
    local tile = Tile.fromCHR(bankBytes, 0)
    tile._bankBytesRef = bankBytes
    tile._bankIndex = 1
    tile.index = 0
    for i = 1, 64 do tile.pixels[i] = 0 end
    tile.pixels[1] = 3 -- x=0, y=0
    tile:refreshImage()

    local layer = { kind = "tile", items = { [1] = tile } }
    local win = {
      kind = "chr",
      layers = { layer },
      currentBank = 1,
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return tile end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function()
        return {
          getFocus = function() return win end,
        }
      end,
      app = {
        markUnsaved = function(_, eventType)
          unsavedEvents[#unsavedEvents + 1] = eventType
        end,
      },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return true end,
    })

    KeyboardInput.keypressed("right", ctx.app)

    expect(win.currentBank).toBe(1)
    expect(tile:getPixel(0, 0)).toBe(0)
    expect(tile:getPixel(1, 0)).toBe(3)
    expect(status).toBe("Offset tile pixels right")
    expect(unsavedEvents[1]).toBe("pixel_edit")
  end)

  it("offsets all selected ROM tiles on alt+arrow", function()
    local status
    local unsavedEvents = {}

    local bankBytesA = {}
    local bankBytesB = {}
    for i = 1, 16 do
      bankBytesA[i] = 0
      bankBytesB[i] = 0
    end

    local tileA = Tile.fromCHR(bankBytesA, 0)
    tileA._bankBytesRef = bankBytesA
    tileA._bankIndex = 1
    tileA.index = 0
    for i = 1, 64 do tileA.pixels[i] = 0 end
    tileA.pixels[1] = 1
    tileA:refreshImage()

    local tileB = Tile.fromCHR(bankBytesB, 1)
    tileB._bankBytesRef = bankBytesB
    tileB._bankIndex = 1
    tileB.index = 1
    for i = 1, 64 do tileB.pixels[i] = 0 end
    tileB.pixels[1] = 2
    tileB:refreshImage()

    local layer = {
      kind = "tile",
      items = {
        [1] = tileA,
        [2] = tileB,
      },
      multiTileSelection = {
        [1] = true,
        [2] = true,
      },
    }
    local win = {
      kind = "chr",
      isRomWindow = true,
      cols = 2,
      rows = 1,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function(_, col, row)
        if col == 0 and row == 0 then return tileA end
        if col == 1 and row == 0 then return tileB end
        return nil
      end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function()
        return {
          getFocus = function() return win end,
        }
      end,
      app = {
        markUnsaved = function(_, eventType)
          unsavedEvents[#unsavedEvents + 1] = eventType
        end,
      },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return true end,
    })

    KeyboardInput.keypressed("right", ctx.app)

    expect(tileA:getPixel(0, 0)).toBe(0)
    expect(tileA:getPixel(1, 0)).toBe(1)
    expect(tileB:getPixel(0, 0)).toBe(0)
    expect(tileB:getPixel(1, 0)).toBe(2)
    expect(status).toBe("Offset pixels on 2 tiles right")
    expect(unsavedEvents[1]).toBe("pixel_edit")
  end)
end)

describe("keyboard_input.lua - shift+left/right palette rotation", function()
  it("rotates all selected CHR tiles individually", function()
    local status

    local bankBytesA = {}
    local bankBytesB = {}
    for i = 1, 16 do
      bankBytesA[i] = 0
      bankBytesB[i] = 0
    end

    local tileA = Tile.fromCHR(bankBytesA, 0)
    tileA._bankBytesRef = bankBytesA
    tileA._bankIndex = 1
    tileA.index = 0
    for i = 1, 64 do tileA.pixels[i] = 0 end
    tileA.pixels[1] = 1
    tileA:refreshImage()

    local tileB = Tile.fromCHR(bankBytesB, 1)
    tileB._bankBytesRef = bankBytesB
    tileB._bankIndex = 1
    tileB.index = 1
    for i = 1, 64 do tileB.pixels[i] = 0 end
    tileB.pixels[1] = 2
    tileB:refreshImage()

    local layer = {
      kind = "tile",
      items = {
        [1] = tileA,
        [2] = tileB,
      },
      multiTileSelection = {
        [1] = true,
        [2] = true,
      },
    }
    local win = {
      kind = "chr",
      cols = 2,
      rows = 1,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function(_, col, row)
        if col == 0 and row == 0 then return tileA end
        if col == 1 and row == 0 then return tileB end
        return nil
      end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {
        appEditState = {
          tilesPool = {},
        },
      },
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("right", ctx.app)

    expect(tileA:getPixel(0, 0)).toBe(2)
    expect(tileB:getPixel(0, 0)).toBe(3)
    expect(status).toBe("Rotated tile palette values right on 2 tiles")
  end)
end)

describe("keyboard_input.lua - tile selection arrow navigation", function()
  it("moves selection to the first tile found in the arrow direction", function()
    local selectedCol, selectedRow, selectedLayer = 1, 1, 1

    local layer = { kind = "tile" }
    local win = {
      kind = "animation",
      cols = 4,
      rows = 4,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return selectedCol, selectedRow, selectedLayer end,
      setSelected = function(_, c, r, li)
        selectedCol, selectedRow, selectedLayer = c, r, li
      end,
      get = function(_, c, r, _)
        if c == 3 and r == 1 then return { index = 99 } end
        return nil
      end,
      nextLayer = function() end,
      prevLayer = function() end,
      getLayerCount = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("right", ctx.app)

    expect(selectedCol).toBe(3)
    expect(selectedRow).toBe(1)
    expect(selectedLayer).toBe(1)
  end)

  it("keeps current selection when next coordinate has no tile", function()
    local selectedCol, selectedRow, selectedLayer = 1, 1, 1
    local nextLayerCalls = 0
    local prevLayerCalls = 0

    local layer = { kind = "tile" }
    local win = {
      kind = "animation",
      cols = 4,
      rows = 4,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return selectedCol, selectedRow, selectedLayer end,
      setSelected = function(_, c, r, li)
        selectedCol, selectedRow, selectedLayer = c, r, li
      end,
      get = function(_, c, r, _)
        if c == 1 and r == 1 then return { index = 20 } end
        return nil
      end,
      nextLayer = function() nextLayerCalls = nextLayerCalls + 1 end,
      prevLayer = function() prevLayerCalls = prevLayerCalls + 1 end,
      getLayerCount = function() return 3 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("up", ctx.app)

    expect(selectedCol).toBe(1)
    expect(selectedRow).toBe(1)
    expect(selectedLayer).toBe(1)
    expect(nextLayerCalls).toBe(0)
    expect(prevLayerCalls).toBe(0)
  end)

  it("keeps current selection when no tile is found before the wall", function()
    local selectedCol, selectedRow, selectedLayer = 1, 1, 1

    local layer = { kind = "tile" }
    local win = {
      kind = "animation",
      cols = 4,
      rows = 4,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return selectedCol, selectedRow, selectedLayer end,
      setSelected = function(_, c, r, li)
        selectedCol, selectedRow, selectedLayer = c, r, li
      end,
      get = function(_, c, r, _)
        if c == 1 and r == 1 then return { index = 20 } end
        return nil
      end,
      nextLayer = function() end,
      prevLayer = function() end,
      getLayerCount = function() return 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("right", ctx.app)

    expect(selectedCol).toBe(1)
    expect(selectedRow).toBe(1)
    expect(selectedLayer).toBe(1)
  end)

  it("uses Shift+Up/Down only for layer change", function()
    local selectedCol, selectedRow, selectedLayer = 1, 1, 1
    local nextLayerCalls = 0
    local prevLayerCalls = 0

    local layer = { kind = "tile" }
    local win = {
      kind = "animation",
      cols = 4,
      rows = 4,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return selectedCol, selectedRow, selectedLayer end,
      setSelected = function(_, c, r, li)
        selectedCol, selectedRow, selectedLayer = c, r, li
      end,
      get = function(_, c, r, _)
        if c == 1 and r == 0 then return { index = 7 } end
        if c == 1 and r == 1 then return { index = 20 } end
        return nil
      end,
      nextLayer = function() nextLayerCalls = nextLayerCalls + 1 end,
      prevLayer = function() prevLayerCalls = prevLayerCalls + 1 end,
      getLayerCount = function() return 3 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("up", ctx.app)

    expect(selectedCol).toBe(1)
    expect(selectedRow).toBe(1)
    expect(selectedLayer).toBe(1)
    expect(nextLayerCalls).toBe(1)
    expect(prevLayerCalls).toBe(0)
  end)

  it("wraps layer index with Shift+Up/Down", function()
    local status
    local win = Window.new(0, 0, 8, 8, 4, 4, 1, { title = "wrap-test" })
    win.kind = "static_art"
    win:addLayer({ name = "Layer 2" })
    win:addLayer({ name = "Layer 3" })
    win:setActiveLayerIndex(3)

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function(msg) status = msg end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("up", ctx.app)
    expect(win:getActiveLayerIndex()).toBe(1)
    expect(status).toBe("Layer 1/3")

    KeyboardInput.keypressed("down", ctx.app)
    expect(win:getActiveLayerIndex()).toBe(3)
    expect(status).toBe("Layer 3/3")
  end)

  it("does not change layer on Up/Down without Shift when no tile is selected", function()
    local nextLayerCalls = 0
    local prevLayerCalls = 0

    local layer = { kind = "tile" }
    local win = {
      kind = "animation",
      cols = 4,
      rows = 4,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return nil, nil, nil end,
      setSelected = function() end,
      get = function() return nil end,
      nextLayer = function() nextLayerCalls = nextLayerCalls + 1 end,
      prevLayer = function() prevLayerCalls = prevLayerCalls + 1 end,
      getLayerCount = function() return 3 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("up", ctx.app)
    KeyboardInput.keypressed("down", ctx.app)

    expect(nextLayerCalls).toBe(0)
    expect(prevLayerCalls).toBe(0)
  end)
end)

describe("keyboard_input.lua - palette window arrow behavior", function()
  it("moves palette selection with plain arrows", function()
    local moveDx, moveDy
    local adjustCalls = 0

    local win = {
      kind = "palette",
      isPalette = true,
      activePalette = true,
      moveSelectedByArrows = function(_, dx, dy)
        moveDx, moveDy = dx, dy
      end,
      adjustSelectedByArrows = function()
        adjustCalls = adjustCalls + 1
      end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("right", ctx.app)

    expect(moveDx).toBe(1)
    expect(moveDy).toBe(0)
    expect(adjustCalls).toBe(0)
  end)

  it("uses Shift+arrows for palette color adjustment without layer navigation fallback", function()
    local adjustDx, adjustDy
    local moveCalls = 0
    local nextLayerCalls = 0
    local prevLayerCalls = 0

    local win = {
      kind = "palette",
      isPalette = true,
      activePalette = true,
      moveSelectedByArrows = function()
        moveCalls = moveCalls + 1
      end,
      adjustSelectedByArrows = function(_, dx, dy)
        adjustDx, adjustDy = dx, dy
      end,
      getActiveLayerIndex = function() return 1 end,
      getLayerCount = function() return 3 end,
      nextLayer = function() nextLayerCalls = nextLayerCalls + 1 end,
      prevLayer = function() prevLayerCalls = prevLayerCalls + 1 end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("up", ctx.app)

    expect(adjustDx).toBe(0)
    expect(adjustDy).toBe(-1)
    expect(moveCalls).toBe(0)
    expect(nextLayerCalls).toBe(0)
    expect(prevLayerCalls).toBe(0)
  end)

  it("moves ROM palette selection with plain arrows", function()
    local moveDx, moveDy
    local adjustCalls = 0

    local win = {
      kind = "rom_palette",
      isPalette = true,
      moveSelectedByArrows = function(_, dx, dy)
        moveDx, moveDy = dx, dy
      end,
      adjustSelectedByArrows = function()
        adjustCalls = adjustCalls + 1
      end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setMode = function() end,
      getFocus = function() return win end,
      setStatus = function() end,
      setColor = function() end,
      wm = function() return nil end,
      app = {},
    }

    KeyboardInput.setup(ctx, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    KeyboardInput.keypressed("left", ctx.app)

    expect(moveDx).toBe(-1)
    expect(moveDy).toBe(0)
    expect(adjustCalls).toBe(0)
  end)
end)
