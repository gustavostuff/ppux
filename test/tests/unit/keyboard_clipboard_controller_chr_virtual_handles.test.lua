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
    expect(pasted ~= nil).toBe(true)
    expect(pasted.col).toBe(1)
    expect(pasted.row).toBe(1)
    expect(pasted.layerIndex).toBe(1)
    expect(pasted.item._virtual).toBeNil()
    expect(pasted.item.index).toBe(5)
    expect(pasted.item._bankIndex).toBe(2)
    expect(unsavedReasons[#unsavedReasons]).toBe("tile_move")
    expect(statuses[#statuses]).toBe("Pasted 1 tile at center")
  end)

  it("pastes into CHR targets by pixel value without tile reference assignment", function()
    local statuses = {}
    local sourceTile = {
      pixels = {},
    }
    for i = 1, 64 do
      sourceTile.pixels[i] = (i % 4)
    end
    local targetTile = {
      pixels = {},
    }
    for i = 1, 64 do
      targetTile.pixels[i] = 0
    end

    local sourceWin = {
      kind = "chr",
      cols = 1,
      rows = 1,
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
      getVirtualTileHandle = function()
        return { _virtual = true, index = 1, _bankIndex = 1 }
      end,
      materializeTileHandle = function()
        return sourceTile
      end,
    }

    local targetWin = {
      kind = "chr",
      cols = 1,
      rows = 1,
      layers = {
        [1] = {
          kind = "tile",
        },
      },
      getActiveLayerIndex = function()
        return 1
      end,
      get = function()
        return targetTile
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
        markUnsaved = function() end,
      },
    }
    local utils = {
      ctrlDown = function() return true end,
      altDown = function() return false end,
      shiftDown = function() return false end,
    }

    expect(KeyboardClipboardController.handleCopySelection(ctx, utils, "c", sourceWin)).toBe(true)
    expect(KeyboardClipboardController.handlePasteSelection(ctx, utils, "v", targetWin)).toBe(true)
    expect(statuses[#statuses]).toBe("Pasted 1 tile at center")
    expect(targetTile.pixels[1]).toBe(sourceTile.pixels[1])
    expect(targetTile.pixels[16]).toBe(sourceTile.pixels[16])
    expect(targetTile.pixels[64]).toBe(sourceTile.pixels[64])
  end)
end)
