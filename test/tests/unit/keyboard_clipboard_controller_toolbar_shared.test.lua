local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")

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
    expect(statuses[#statuses]).toBe("Pasted 1 tile at center")
    expect(pasted ~= nil).toBe(true)
    expect(pasted.item.id).toBe(77)
    expect(unsavedReasons[1]).toBe("tile_move")
    expect(unsavedReasons[2]).toBe("tile_move")
  end)

  it("pastes tiles at cursor cell inside focused window", function()
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
      toGridCoords = function(_, x, y)
        if x == 100 and y == 80 then
          return true, 4, 3, 0, 0
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
      setStatus = function(text) statuses[#statuses + 1] = text end,
      scaledMouse = function() return 100, 80 end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(pasted ~= nil).toBe(true)
    expect(pasted.col).toBe(4)
    expect(pasted.row).toBe(3)
  end)

  it("uses table-shaped scaledMouse coordinates when resolving paste anchor", function()
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

  it("falls back to centered tile paste when cursor is outside layer area", function()
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
      toGridCoords = function() return false end,
      set = function(_, col, row, item)
        pasted = { col = col, row = row, item = item }
      end,
      setSelected = function() end,
      clearSelected = function() end,
    }
    local ctx = {
      scaledMouse = function() return 999, 999 end,
      setStatus = function() end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste")).toBe(true)
    expect(pasted ~= nil).toBe(true)
    expect(pasted.col).toBe(2)
    expect(pasted.row).toBe(2)
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

  it("shifts tile paste anchors to fit bounds", function()
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
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste", {
      anchorCol = -3,
      anchorRow = -2,
    })).toBe(true)
    expect(#writes).toBe(2)
    expect(writes[1].col).toBe(0)
    expect(writes[1].row).toBe(0)
    expect(writes[2].col).toBe(1)
    expect(writes[2].row).toBe(0)
    expect(statuses[#statuses]:match("shifted to fit bounds") ~= nil).toBe(true)

    writes = {}
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste", {
      anchorCol = 99,
      anchorRow = 99,
    })).toBe(true)
    expect(#writes).toBe(2)
    expect(writes[1].col).toBe(2)
    expect(writes[1].row).toBe(3)
    expect(writes[2].col).toBe(3)
    expect(writes[2].row).toBe(3)
    expect(statuses[#statuses]:match("shifted to fit bounds") ~= nil).toBe(true)
  end)

  it("shifts sprite paste anchors to fit pixel bounds", function()
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
      getActiveLayerIndex = function() return 1 end,
    }

    local status = nil
    local ctx = {
      setStatus = function(text) status = text end,
      app = {},
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, sourceWin, "copy")).toBe(true)
    expect(KeyboardClipboardController.performClipboardAction(ctx, targetWin, "paste", {
      anchorX = 999,
      anchorY = 999,
    })).toBe(true)
    expect(#targetLayer.items).toBe(1)
    expect(targetLayer.items[1].worldX).toBe(24)
    expect(targetLayer.items[1].worldY).toBe(24)
    expect(status:match("shifted to fit bounds") ~= nil).toBe(true)
  end)
end)
