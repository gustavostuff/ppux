local RevertTilePixelsController = require("controllers.chr.revert_tile_pixels_controller")

describe("revert_tile_pixels_controller.lua", function()
  it("collectTileRevertPairs includes every multi-selected CHR tile when menu targets a selected cell", function()
    local layer = { kind = "tile", bank = 1 }
    local win = {
      kind = "chr",
      orderMode = "normal",
      cols = 16,
      rows = 32,
      activeLayer = 1,
      currentBank = 1,
      layers = { layer },
      getActiveLayerIndex = function(self)
        return 1
      end,
      get = function(self, col, row, li)
        local idx = row * 16 + col
        return { index = idx, _bankIndex = 1 }
      end,
    }
    layer.multiTileSelection = { [1] = true, [2] = true }

    local pairs = RevertTilePixelsController.collectTileRevertPairs({
      win = win,
      layer = layer,
      layerIndex = 1,
      col = 0,
      row = 0,
      item = { index = 0, _bankIndex = 1 },
      sourceBank = 1,
    })

    expect(pairs).toBeTruthy()
    expect(#pairs).toBe(2)
    expect(pairs[1].bank).toBe(1)
    expect(pairs[2].bank).toBe(1)
    local ti = { pairs[1].tileIndex, pairs[2].tileIndex }
    table.sort(ti)
    expect(ti[1]).toBe(0)
    expect(ti[2]).toBe(1)
  end)

  it("collectTileRevertPairs uses only the clicked cell when multi-selection exists but click is outside it", function()
    local layer = { kind = "tile", bank = 1 }
    local win = {
      kind = "chr",
      orderMode = "normal",
      cols = 16,
      rows = 32,
      activeLayer = 1,
      currentBank = 1,
      layers = { layer },
      getActiveLayerIndex = function()
        return 1
      end,
      get = function(self, col, row)
        return { index = row * 16 + col, _bankIndex = 1 }
      end,
    }
    layer.multiTileSelection = { [1] = true, [2] = true }

    local pairs = RevertTilePixelsController.collectTileRevertPairs({
      win = win,
      layer = layer,
      layerIndex = 1,
      col = 5,
      row = 0,
      item = { index = 5, _bankIndex = 1 },
      sourceBank = 1,
    })

    expect(pairs).toBeTruthy()
    expect(#pairs).toBe(1)
    expect(pairs[1].tileIndex).toBe(5)
  end)
end)
