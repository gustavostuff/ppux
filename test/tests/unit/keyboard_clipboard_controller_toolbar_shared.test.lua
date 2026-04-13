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
    expect(pasted).toNotBeNil()
    expect(pasted.item.id).toBe(77)
    expect(unsavedReasons[1]).toBe("tile_move")
    expect(unsavedReasons[2]).toBe("tile_move")
  end)
end)
