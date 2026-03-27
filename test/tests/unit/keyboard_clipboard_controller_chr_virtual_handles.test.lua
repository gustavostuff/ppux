local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")

describe("keyboard_clipboard_controller.lua - CHR virtual handles", function()
  beforeEach(function()
    KeyboardClipboardController.reset()
  end)

  it("copies CHR selections as virtual handles and materializes them on paste", function()
    local statuses = {}
    local unsavedReasons = {}
    local getCalled = false
    local pasted = nil

    local sourceWin = {
      kind = "chr",
      cols = 16,
      rows = 32,
      layers = {
        [1] = {
          kind = "tile",
          multiTileSelection = {
            [1] = true,
          },
        },
      },
      getActiveLayerIndex = function()
        return 1
      end,
      getSelected = function()
        return 0, 0, 1
      end,
      getVirtualTileHandle = function(self, col, row, layerIndex)
        return {
          kind = "chr_virtual_tile",
          index = 5,
          _bankIndex = 2,
          _virtual = true,
        }
      end,
      materializeTileHandle = function(self, item, layerIndex)
        return {
          index = item.index,
          _bankIndex = item._bankIndex,
          pixels = {},
        }
      end,
      get = function()
        getCalled = true
        return nil
      end,
    }

    local targetWin = {
      kind = "static_art",
      cols = 4,
      rows = 4,
      layers = {
        [1] = {
          kind = "tile",
        },
      },
      getActiveLayerIndex = function()
        return 1
      end,
      set = function(self, col, row, item, layerIndex)
        pasted = {
          col = col,
          row = row,
          item = item,
          layerIndex = layerIndex,
        }
      end,
      setSelected = function() end,
      clearSelected = function() end,
    }

    local ctx = {
      getMode = function()
        return "tile"
      end,
      setStatus = function(text)
        statuses[#statuses + 1] = text
      end,
      app = {
        markUnsaved = function(self, reason)
          unsavedReasons[#unsavedReasons + 1] = reason
        end,
      },
    }

    local utils = {
      ctrlDown = function() return true end,
      altDown = function() return false end,
      shiftDown = function() return false end,
    }

    expect(KeyboardClipboardController.handleCopySelection(ctx, utils, "c", sourceWin)).toBe(true)
    expect(getCalled).toBe(false)
    expect(statuses[#statuses]).toBe("Copied 1 tile")

    expect(KeyboardClipboardController.handlePasteSelection(ctx, utils, "v", targetWin)).toBe(true)
    expect(pasted).toNotBeNil()
    expect(pasted.col).toBe(1)
    expect(pasted.row).toBe(1)
    expect(pasted.layerIndex).toBe(1)
    expect(pasted.item._virtual).toBeNil()
    expect(pasted.item.index).toBe(5)
    expect(pasted.item._bankIndex).toBe(2)
    expect(unsavedReasons[#unsavedReasons]).toBe("tile_move")
    expect(statuses[#statuses]).toBe("Pasted 1 tile at center")
  end)
end)
