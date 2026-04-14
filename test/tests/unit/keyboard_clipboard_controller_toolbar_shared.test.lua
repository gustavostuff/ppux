local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

describe("keyboard_clipboard_controller.lua - shared toolbar/keyboard actions", function()
  beforeEach(function()
    KeyboardClipboardController.reset()
  end)

  it("blocks sprite clipboard actions for PPU frame and OAM animation layers with warnings", function()
    local cases = {
      { kind = "oam_animation", action = "copy", expected = "Cannot copy sprites in OAM animation windows" },
      { kind = "oam_animation", action = "paste", expected = "Cannot add sprites to OAM animation windows" },
      { kind = "ppu_frame", action = "cut", expected = "Cannot cut sprites in PPU frame windows" },
    }

    for _, case in ipairs(cases) do
      local status = nil
      local toastKind = nil
      local toastText = nil
      local layer = {
        kind = "sprite",
        items = {
          { x = 0, y = 0 },
        },
        selectedSpriteIndex = 1,
      }
      local win = {
        kind = case.kind,
        layers = { layer },
        getActiveLayerIndex = function() return 1 end,
      }
      local ctx = {
        setStatus = function(text) status = text end,
        app = {
          showToast = function(_, k, text)
            toastKind = k
            toastText = text
          end,
        },
      }

      expect(KeyboardClipboardController.performClipboardAction(ctx, win, case.action)).toBe(true)
      expect(status).toBe(case.expected)
      expect(toastKind).toBe("warning")
      expect(toastText).toBe(case.expected)
    end
  end)

  it("cuts and pastes tiles via shared action entry points", function()
    local statuses = {}
    local unsavedReasons = {}
    local sourceLayer = {
      kind = "tile",
      items = {
        [1] = { id = 77 },
      },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }

    local sourceWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return { id = 77 } end,
      markCellRemoved = function(_, col, row, layerIndex)
        sourceLayer.removedCells[((row * 1) + col) + 1] = true
      end,
      clearSelected = function() end,
    }

    local pasted = nil
    local targetLayer = { kind = "tile" }
    local targetWin = {
      kind = "static_art",
      cols = 4,
      rows = 4,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      set = function(_, col, row, item, layerIndex)
        pasted = { col = col, row = row, item = item, layerIndex = layerIndex }
      end,
      setSelected = function() end,
      clearSelected = function() end,
    }

    local ctx = {
      setStatus = function(text) statuses[#statuses + 1] = text end,
      app = {
        markUnsaved = function(_, reason)
          unsavedReasons[#unsavedReasons + 1] = reason
        end,
      },
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "cut")).toBe(true)
    expect(statuses[#statuses]).toBe("Cut 1 tile")
    expect(sourceLayer.removedCells[1]).toBe(true)

    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(statuses[#statuses]).toBe("Pasted 1 tile")
    expect(pasted ~= nil).toBe(true)
    expect(pasted.item.id).toBe(77)
    expect(unsavedReasons[1]).toBe("tile_move")
    expect(unsavedReasons[2]).toBe("tile_move")
  end)

  it("pastes tiles at selected cell inside focused window", function()
    local statuses = {}
    local sourceLayer = {
      kind = "tile",
      items = { [1] = { id = 12 } },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }
    local sourceWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return sourceLayer.items[1] end,
      markCellRemoved = function() end,
      clearSelected = function() end,
    }
    local pasted = nil
    local targetLayer = { kind = "tile" }
    local targetWin = {
      kind = "static_art",
      cols = 8,
      rows = 8,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 4, 3, 1 end,
      set = function(_, col, row, item)
        pasted = { col = col, row = row, item = item }
      end,
      setSelected = function() end,
      clearSelected = function() end,
    }
    local ctx = {
      setStatus = function(text) statuses[#statuses + 1] = text end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(pasted ~= nil).toBe(true)
    expect(pasted.col).toBe(4)
    expect(pasted.row).toBe(3)
  end)

  it("uses cursor tile paste when there is no selected cell", function()
    local sourceLayer = {
      kind = "tile",
      items = { [1] = { id = 31 } },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }
    local sourceWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return sourceLayer.items[1] end,
      markCellRemoved = function() end,
      clearSelected = function() end,
    }
    local pasted = nil
    local targetLayer = { kind = "tile" }
    local targetWin = {
      kind = "static_art",
      cols = 8,
      rows = 8,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return nil, nil, 1 end,
      toGridCoords = function(_, x, y)
        if x == 140 and y == 90 then
          return true, 6, 2, 0, 0
        end
        return false
      end,
      set = function(_, col, row, item)
        pasted = { col = col, row = row, item = item }
      end,
      setSelected = function() end,
      clearSelected = function() end,
    }
    local ctx = {
      setStatus = function() end,
      scaledMouse = function() return { x = 140, y = 90 } end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(pasted ~= nil).toBe(true)
    expect(pasted.col).toBe(6)
    expect(pasted.row).toBe(2)
  end)

  it("syncs CHR tile refresh/bytes/edits when pasting pixels into source windows", function()
    local sourceTile = { pixels = {} }
    for i = 1, 64 do
      sourceTile.pixels[i] = (i % 4)
    end
    local sourceLayer = {
      kind = "tile",
      items = { [1] = sourceTile },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }
    local sourceWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return sourceTile end,
      clearSelected = function() end,
    }

    local refreshCalls = 0
    local targetBytes = {}
    for i = 1, 16 do targetBytes[i] = 0 end
    local targetTile = {
      pixels = {},
      _bankBytesRef = targetBytes,
      _bankIndex = 1,
      index = 0,
      refreshImage = function()
        refreshCalls = refreshCalls + 1
      end,
    }
    for i = 1, 64 do
      targetTile.pixels[i] = 0
    end

    local targetLayer = { kind = "tile" }
    local targetWin = {
      kind = "chr",
      cols = 4,
      rows = 4,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 1, 1, 1 end,
      get = function() return targetTile end,
      setSelected = function() end,
      clearSelected = function() end,
    }

    local ctx = {
      setStatus = function() end,
      app = {
        invalidateChrBankTileCanvas = function() end,
      },
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(refreshCalls).toBe(1)
    expect(targetTile.pixels[1]).toBe(sourceTile.pixels[1])
    expect(ctx.app.edits).toBeTruthy()
    expect(ctx.app.edits.banks[1]).toBeTruthy()
    expect(ctx.app.edits.banks[1][0]).toBeTruthy()
    expect(ctx.app.edits.banks[1][0]["0_0"]).toBe(sourceTile.pixels[1])
    expect(targetBytes[1]).toNotBe(0)
  end)

  it("invalidates CHR bank tile canvas after CHR pixel paste", function()
    local sourceLayer = {
      kind = "tile",
      items = { [1] = { pixels = { [1] = 3 } } },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }
    local sourceWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function()
        local tile = { pixels = {} }
        for i = 1, 64 do
          tile.pixels[i] = (i % 4)
        end
        return tile
      end,
      clearSelected = function() end,
    }

    local targetTile = {
      pixels = {},
      _bankBytesRef = {},
      _bankIndex = 2,
      index = 11,
      refreshImage = function() end,
    }
    for i = 1, 64 do
      targetTile.pixels[i] = 0
    end
    for i = 1, 16 do
      targetTile._bankBytesRef[i] = 0
    end

    local invalidated = nil
    local targetWin = {
      kind = "chr",
      cols = 16,
      rows = 32,
      layers = { { kind = "tile" } },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return targetTile end,
      setSelected = function() end,
      clearSelected = function() end,
    }
    local ctx = {
      setStatus = function() end,
      app = {
        invalidateChrBankTileCanvas = function(_, bankIdx, tileIdx)
          invalidated = { bank = bankIdx, tile = tileIdx }
        end,
      },
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(invalidated).toBeTruthy()
    expect(invalidated.bank).toBe(2)
    expect(invalidated.tile).toBe(11)
  end)

  it("uses selected cell as tile paste anchor in scrolled windows", function()
    local sourceLayer = {
      kind = "tile",
      items = { [1] = { id = 41 } },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }
    local sourceWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return sourceLayer.items[1] end,
      markCellRemoved = function() end,
      clearSelected = function() end,
    }
    local requestedCol, requestedRow = nil, nil
    local targetLayer = { kind = "tile" }
    local targetWin = {
      kind = "chr",
      cols = 16,
      rows = 32,
      scrollCol = 5,
      scrollRow = 10,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 7, 13, 1 end,
      get = function(_, col, row)
        requestedCol, requestedRow = col, row
        return { pixels = {} }
      end,
      setSelected = function() end,
      clearSelected = function() end,
    }
    local ctx = {
      setStatus = function() end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(requestedCol).toBe(7)
    expect(requestedRow).toBe(13)
  end)

  it("falls back to top-left tile paste when there is no selection and no cursor hit", function()
    local sourceLayer = {
      kind = "tile",
      items = { [1] = { id = 99 } },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }
    local sourceWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return sourceLayer.items[1] end,
      markCellRemoved = function() end,
      clearSelected = function() end,
    }
    local pasted = nil
    local targetLayer = { kind = "tile" }
    local targetWin = {
      kind = "static_art",
      cols = 6,
      rows = 6,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return nil, nil, 1 end,
      toGridCoords = function() return false end,
      set = function(_, col, row, item)
        pasted = { col = col, row = row, item = item }
      end,
      setSelected = function() end,
      clearSelected = function() end,
    }
    local ctx = {
      setStatus = function() end,
      scaledMouse = function() return 999, 999 end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(pasted ~= nil).toBe(true)
    expect(pasted.col).toBe(0)
    expect(pasted.row).toBe(0)
  end)

  it("warns when paste is requested with no focused window", function()
    local sourceLayer = {
      kind = "tile",
      items = { [1] = { id = 5 } },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }
    local sourceWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return sourceLayer.items[1] end,
      markCellRemoved = function() end,
      clearSelected = function() end,
    }
    local status = nil
    local toastKind = nil
    local toastText = nil
    local ctx = {
      setStatus = function(text) status = text end,
      app = {
        showToast = function(_, kind, text)
          toastKind = kind
          toastText = text
        end,
      },
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, nil, "paste")).toBe(true)
    expect(status).toBe("No focused window")
    expect(toastKind).toBe("warning")
    expect(toastText).toBe("No focused window")
  end)

  it("shifts tile paste anchors to fit bounds from selected cell", function()
    local sourceLayer = {
      kind = "tile",
      items = {
        [1] = { id = "A" },
        [2] = { id = "B" },
      },
      multiTileSelection = {
        [1] = true,
        [2] = true,
      },
      removedCells = {},
    }
    local sourceWin = {
      kind = "static_art",
      cols = 2,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function(_, col)
        return (col == 0) and sourceLayer.items[1] or sourceLayer.items[2]
      end,
      markCellRemoved = function() end,
      clearSelected = function() end,
    }

    local writes = {}
    local targetLayer = { kind = "tile" }
    local targetWin = {
      kind = "static_art",
      cols = 4,
      rows = 4,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 3, 3, 1 end,
      set = function(_, col, row, item)
        writes[#writes + 1] = { col = col, row = row, item = item }
      end,
      setSelected = function() end,
      clearSelected = function() end,
    }

    local statuses = {}
    local ctx = {
      setStatus = function(text) statuses[#statuses + 1] = text end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(#writes).toBe(2)
    expect(writes[1].col).toBe(2)
    expect(writes[1].row).toBe(3)
    expect(writes[2].col).toBe(3)
    expect(writes[2].row).toBe(3)
    expect(statuses[#statuses]:match("shifted to fit bounds") ~= nil).toBe(true)
  end)

  it("uses sprite selection top-left as paste anchor", function()
    local sourceLayer = {
      kind = "sprite",
      items = {
        { worldX = 0, worldY = 0, x = 0, y = 0 },
      },
      selectedSpriteIndex = 1,
    }
    local sourceWin = {
      kind = "static_art",
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
    }

    local targetLayer = {
      kind = "sprite",
      items = {
        { worldX = 18, worldY = 12, x = 18, y = 12 },
      },
      selectedSpriteIndex = 1,
    }
    local targetWin = {
      kind = "static_art",
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      setStatus = function() end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(#targetLayer.items).toBe(2)
    expect(targetLayer.items[2].worldX).toBe(18)
    expect(targetLayer.items[2].worldY).toBe(12)
  end)

  it("uses cursor sprite paste when there is no sprite selection", function()
    local sourceLayer = {
      kind = "sprite",
      items = {
        { worldX = 0, worldY = 0, x = 0, y = 0 },
      },
      selectedSpriteIndex = 1,
    }
    local sourceWin = {
      kind = "static_art",
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
    }

    local targetLayer = {
      kind = "sprite",
      items = {},
    }
    local targetWin = {
      kind = "static_art",
      cols = 4,
      rows = 4,
      cellW = 8,
      cellH = 8,
      layers = { targetLayer },
      toGridCoords = function(_, x, y)
        if x == 100 and y == 80 then
          return true, 1, 2, 4, 1
        end
        return false
      end,
      getActiveLayerIndex = function() return 1 end,
    }

    local status = nil
    local ctx = {
      setStatus = function(text) status = text end,
      scaledMouse = function() return 100, 80 end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(#targetLayer.items).toBe(1)
    expect(targetLayer.items[1].worldX).toBe(12)
    expect(targetLayer.items[1].worldY).toBe(17)
    expect(status).toBe("Pasted 1 sprite")
  end)

  it("falls back to top-left sprite paste when there is no sprite selection and no cursor hit", function()
    local sourceLayer = {
      kind = "sprite",
      items = {
        { worldX = 0, worldY = 0, x = 0, y = 0 },
      },
      selectedSpriteIndex = 1,
    }
    local sourceWin = {
      kind = "static_art",
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
    }

    local targetLayer = {
      kind = "sprite",
      items = {},
    }
    local targetWin = {
      kind = "static_art",
      cols = 4,
      rows = 4,
      cellW = 8,
      cellH = 8,
      layers = { targetLayer },
      toGridCoords = function() return false end,
      getActiveLayerIndex = function() return 1 end,
    }

    local ctx = {
      setStatus = function() end,
      scaledMouse = function() return 999, 999 end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(#targetLayer.items).toBe(1)
    expect(targetLayer.items[1].worldX).toBe(0)
    expect(targetLayer.items[1].worldY).toBe(0)
  end)

  it("records tile paste in undo/redo stack", function()
    local sourceLayer = {
      kind = "tile",
      items = { [1] = { id = 7 } },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }
    local sourceWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return sourceLayer.items[1] end,
      clearSelected = function() end,
    }

    local targetLayer = {
      kind = "tile",
      items = { [1] = { id = "old" } },
    }
    local targetWin = {
      kind = "static_art",
      cols = 2,
      rows = 2,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function(_, col, row)
        return targetLayer.items[(row * 2 + col) + 1]
      end,
      set = function(_, col, row, item)
        targetLayer.items[(row * 2 + col) + 1] = item
      end,
      setSelected = function() end,
      clearSelected = function() end,
    }

    local undoRedo = UndoRedoController.new(20)
    local app = { undoRedo = undoRedo }
    local ctx = {
      setStatus = function() end,
      app = app,
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(targetLayer.items[1].id).toBe(7)
    expect(undoRedo.stack[1].type).toBe("tile_drag")
    expect(undoRedo:undo(app)).toBe(true)
    expect(targetLayer.items[1].id).toBe("old")
    expect(undoRedo:redo(app)).toBe(true)
    expect(targetLayer.items[1].id).toBe(7)
  end)

  it("records sprite paste in undo/redo stack", function()
    local sourceLayer = {
      kind = "sprite",
      items = {
        { worldX = 0, worldY = 0, baseX = 0, baseY = 0, x = 0, y = 0, dx = 0, dy = 0, removed = false },
      },
      selectedSpriteIndex = 1,
    }
    local sourceWin = {
      kind = "static_art",
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
    }
    local targetLayer = {
      kind = "sprite",
      items = {},
    }
    local targetWin = {
      kind = "static_art",
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function(_, x, y)
        if x == 16 and y == 24 then
          return true, 2, 3, 0, 0
        end
        return false
      end,
    }
    local undoRedo = UndoRedoController.new(20)
    local app = { undoRedo = undoRedo }
    local ctx = {
      setStatus = function() end,
      scaledMouse = function() return 16, 24 end,
      app = app,
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(#targetLayer.items).toBe(1)
    expect(targetLayer.items[1].removed).toNotBe(true)
    expect(undoRedo.stack[1].type).toBe("sprite_drag")
    expect(undoRedo:undo(app)).toBe(true)
    expect(targetLayer.items[1].removed).toBe(true)
    expect(undoRedo:redo(app)).toBe(true)
    expect(targetLayer.items[1].removed).toBe(false)
  end)

  it("records CHR paste pixels in undo/redo stack", function()
    local sourceTile = { pixels = {} }
    for i = 1, 64 do
      sourceTile.pixels[i] = 3
    end
    local sourceLayer = {
      kind = "tile",
      items = { [1] = sourceTile },
      multiTileSelection = { [1] = true },
      removedCells = {},
    }
    local sourceWin = {
      kind = "static_art",
      cols = 1,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return sourceTile end,
      clearSelected = function() end,
    }

    local targetBytes = {}
    for i = 1, 16 do targetBytes[i] = 0 end
    local targetTile = {
      pixels = {},
      _bankBytesRef = targetBytes,
      _bankIndex = 1,
      index = 0,
      refreshImage = function() end,
    }
    for i = 1, 64 do targetTile.pixels[i] = 0 end

    local targetLayer = { kind = "tile" }
    local targetWin = {
      kind = "chr",
      cols = 4,
      rows = 4,
      layers = { targetLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function() return targetTile end,
      setSelected = function() end,
      clearSelected = function() end,
    }

    local undoRedo = UndoRedoController.new(20)
    local app = {
      undoRedo = undoRedo,
      edits = { banks = {} },
      appEditState = {
        chrBanksBytes = { targetBytes },
        tilesPool = { [1] = { [0] = targetTile } },
      },
      invalidateChrBankTileCanvas = function() end,
    }
    local ctx = {
      setStatus = function() end,
      app = app,
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(targetTile.pixels[1]).toBe(3)
    expect(undoRedo.stack[1].type).toBe("paint")
    expect(undoRedo:undo(app)).toBe(true)
    expect(targetTile.pixels[1]).toBe(0)
    expect(undoRedo:redo(app)).toBe(true)
    expect(targetTile.pixels[1]).toBe(3)
  end)
end)
