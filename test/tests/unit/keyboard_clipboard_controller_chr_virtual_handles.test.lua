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
    expect(pasted.col).toBe(0)
    expect(pasted.row).toBe(0)
    expect(pasted.layerIndex).toBe(1)
    expect(pasted.item._virtual).toBeNil()
    expect(pasted.item.index).toBe(5)
    expect(pasted.item._bankIndex).toBe(2)
    expect(unsavedReasons[#unsavedReasons]).toBe("tile_move")
    expect(statuses[#statuses]).toBe("Pasted 1 tile")
  end)

  it("pastes into CHR targets by pixel value without tile reference assignment (same window)", function()
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

    local selectedCol, selectedRow = 1, 0
    local chrWin = {
      kind = "chr",
      cols = 2,
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
        return selectedCol, selectedRow, 1
      end,
      getVirtualTileHandle = function()
        return { _virtual = true, index = 1, _bankIndex = 1 }
      end,
      materializeTileHandle = function()
        return sourceTile
      end,
      get = function(_, col)
        if col == 0 then return sourceTile end
        return targetTile
      end,
      setSelected = function(_, col, row)
        selectedCol, selectedRow = col, row
      end,
      clearSelected = function()
        selectedCol, selectedRow = nil, nil
      end,
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

    expect(KeyboardClipboardController.handleCopySelection(ctx, utils, "c", chrWin)).toBe(true)
    selectedCol, selectedRow = 1, 0
    expect(KeyboardClipboardController.handlePasteSelection(ctx, utils, "v", chrWin)).toBe(true)
    expect(statuses[#statuses]).toBe("Pasted 1 tile")
    expect(targetTile.pixels[1]).toBe(sourceTile.pixels[1])
    expect(targetTile.pixels[16]).toBe(sourceTile.pixels[16])
    expect(targetTile.pixels[64]).toBe(sourceTile.pixels[64])
  end)

  it("supports CHR same-window copy, cut and paste by pixel value", function()
    local statuses = {}
    local tileA = { pixels = {} }
    local tileB = { pixels = {} }
    local tileC = { pixels = {} }
    for i = 1, 64 do
      tileA.pixels[i] = i % 4
      tileB.pixels[i] = 0
      tileC.pixels[i] = (i + 1) % 4
    end

    local sourceLayer = {
      kind = "tile",
      multiTileSelection = { [1] = true },
      removedCells = {},
    }
    local selectedCol, selectedRow = 1, 0
    local chrWin = {
      kind = "chr",
      cols = 3,
      rows = 1,
      layers = { sourceLayer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return selectedCol, selectedRow, 1 end,
      getVirtualTileHandle = function(_, col)
        local idx = (col == 0 and 1) or (col == 1 and 2) or 3
        return { _virtual = true, index = idx, _bankIndex = 1 }
      end,
      materializeTileHandle = function(_, handle)
        if handle.index == 1 then return tileA end
        if handle.index == 2 then return tileB end
        if handle.index == 3 then return tileC end
        return nil
      end,
      get = function(_, col)
        if col == 0 then return tileA end
        if col == 1 then return tileB end
        return tileC
      end,
      setSelected = function(_, col, row)
        selectedCol, selectedRow = col, row
      end,
      clearSelected = function() end,
    }
    local ctx = {
      getMode = function() return "tile" end,
      setStatus = function(text) statuses[#statuses + 1] = text end,
      app = {
        markUnsaved = function() end,
      },
    }
    expect(KeyboardClipboardController.performClipboardAction(ctx, chrWin, "copy")).toBe(true)
    selectedCol, selectedRow = 1, 0
    expect(KeyboardClipboardController.performClipboardAction(ctx, chrWin, "paste")).toBe(true)
    expect(tileB.pixels[1]).toBe(tileA.pixels[1])
    expect(tileB.pixels[64]).toBe(tileA.pixels[64])

    sourceLayer.multiTileSelection = { [1] = true }
    selectedCol, selectedRow = 0, 0
    expect(KeyboardClipboardController.performClipboardAction(ctx, chrWin, "cut")).toBe(true)
    expect(tileA.pixels[1]).toBe(0)
    expect(tileA.pixels[64]).toBe(0)

    selectedCol, selectedRow = 2, 0
    expect(KeyboardClipboardController.performClipboardAction(ctx, chrWin, "paste")).toBe(true)
    expect(tileC.pixels[1]).toBe((1 % 4))
    expect(tileC.pixels[64]).toBe((64 % 4))
    expect(statuses[#statuses]).toBe("Pasted 1 tile")
  end)

  it("copies full 8x16 CHR pair from a single selected cell in same CHR window", function()
    local topSrc = { pixels = {} }
    local botSrc = { pixels = {} }
    local topDst = { pixels = {}, _bankBytesRef = {}, _bankIndex = 1, index = 20, refreshImage = function() end }
    local botDst = { pixels = {}, _bankBytesRef = {}, _bankIndex = 1, index = 21, refreshImage = function() end }
    for i = 1, 64 do
      topSrc.pixels[i] = 1
      botSrc.pixels[i] = 2
      topDst.pixels[i] = 0
      botDst.pixels[i] = 0
    end
    for i = 1, 16 do
      topDst._bankBytesRef[i] = 0
      botDst._bankBytesRef[i] = 0
    end

    local selectedCol, selectedRow = 3, 10
    local chrWin = {
      kind = "chr",
      orderMode = "oddEven",
      cols = 16,
      rows = 32,
      layers = {
        [1] = { kind = "tile" },
      },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return selectedCol, selectedRow, 1 end, -- single selected cell
      getVirtualTileHandle = function(_, col, row)
        if col ~= 3 then return nil end
        if row == 10 then return { _virtual = true, index = 100, _bankIndex = 1 } end
        if row == 11 then return { _virtual = true, index = 101, _bankIndex = 1 } end
        return nil
      end,
      materializeTileHandle = function(_, handle)
        if handle.index == 100 then return topSrc end
        if handle.index == 101 then return botSrc end
        return nil
      end,
      get = function(_, col, row)
        if col == 3 and row == 10 then return topSrc end
        if col == 3 and row == 11 then return botSrc end
        if col ~= 8 then return nil end
        if row == 20 then return topDst end
        if row == 21 then return botDst end
        return nil
      end,
      setSelected = function(_, col, row)
        selectedCol, selectedRow = col, row
      end,
      clearSelected = function() end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      setStatus = function() end,
      app = {
        markUnsaved = function() end,
        invalidateChrBankTileCanvas = function() end,
      },
    }
    local utils = {
      ctrlDown = function() return true end,
      altDown = function() return false end,
      shiftDown = function() return false end,
    }

    expect(KeyboardClipboardController.handleCopySelection(ctx, utils, "c", chrWin)).toBe(true)
    selectedCol, selectedRow = 8, 20
    expect(KeyboardClipboardController.handlePasteSelection(ctx, utils, "v", chrWin)).toBe(true)
    expect(topDst.pixels[1]).toBe(1)
    expect(topDst.pixels[64]).toBe(1)
    expect(botDst.pixels[1]).toBe(2)
    expect(botDst.pixels[64]).toBe(2)
  end)
end)
