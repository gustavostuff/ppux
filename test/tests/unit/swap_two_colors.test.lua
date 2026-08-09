local Tile = require("ui.windows_system.tile_item")
local SwapTwoColorsController = require("controllers.chr.swap_two_colors_controller")
local SwapTwoColorsModal = require("ui.modals.swap_two_colors_modal")

local function makePixels(pattern)
  -- pattern: map of index -> value for a few cells; rest 0
  local pixels = {}
  for i = 1, 64 do
    pixels[i] = 0
  end
  if type(pattern) == "table" then
    for i, v in pairs(pattern) do
      if type(i) == "number" then
        pixels[i] = v
      end
    end
  end
  return pixels
end

local function makeBankTile(bankIdx, tileIndex, pixels)
  local tile = Tile.blank(0)
  tile.index = tileIndex
  tile._bankIndex = bankIdx
  tile.pixels = pixels or makePixels()
  tile.swapPaletteIndices = Tile.swapPaletteIndices
  tile.refreshImage = function() end
  -- Avoid writePixelsToCHR side effects in unit tests
  tile._bankBytesRef = nil
  return tile
end

describe("Tile:swapPaletteIndices", function()
  it("swaps matching indices and leaves others alone", function()
    local tile = Tile.blank(0)
    tile.pixels = makePixels({ [1] = 1, [2] = 3, [3] = 2, [4] = 1 })
    tile.refreshImage = function() end

    expect(tile:swapPaletteIndices(1, 3)).toBe(true)
    expect(tile.pixels[1]).toBe(3)
    expect(tile.pixels[2]).toBe(1)
    expect(tile.pixels[3]).toBe(2)
    expect(tile.pixels[4]).toBe(3)
  end)

  it("returns false for identical or out-of-range indices", function()
    local tile = Tile.blank(0)
    tile.pixels = makePixels({ [1] = 1 })
    tile.refreshImage = function() end
    expect(tile:swapPaletteIndices(1, 1)).toBe(false)
    expect(tile:swapPaletteIndices(-1, 2)).toBe(false)
    expect(tile:swapPaletteIndices(0, 4)).toBe(false)
  end)

  it("returns false when neither index appears", function()
    local tile = Tile.blank(0)
    tile.pixels = makePixels({ [1] = 0, [2] = 2 })
    tile.refreshImage = function() end
    expect(tile:swapPaletteIndices(1, 3)).toBe(false)
  end)
end)

describe("swap_two_colors_controller.lua", function()
  it("collectSwapTargets expands multi-selected CHR tiles", function()
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
        return { index = row * 16 + col, _bankIndex = 1, pixels = makePixels() }
      end,
    }
    layer.multiTileSelection = { [1] = true, [3] = true }

    local pairs = SwapTwoColorsController.collectSwapTargets({
      win = win,
      layer = layer,
      layerIndex = 1,
      col = 0,
      row = 0,
      item = { index = 0, _bankIndex = 1, pixels = makePixels() },
      sourceBank = 1,
    })
    expect(pairs).toBeTruthy()
    expect(#pairs).toBe(2)
  end)

  it("collectSwapTargets expands multi-selected sprites when context is included", function()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      bank = 1,
      items = {
        { tile = 10, _bankIndex = 1, topRef = { index = 10, _bankIndex = 1 } },
        { tile = 20, _bankIndex = 1, topRef = { index = 20, _bankIndex = 1 } },
        { tile = 30, _bankIndex = 1, topRef = { index = 30, _bankIndex = 1 } },
      },
      multiSpriteSelection = { [1] = true, [3] = true },
    }

    local pairs = SwapTwoColorsController.collectSwapTargets({
      layer = layer,
      layerIndex = 1,
      itemIndex = 1,
      item = layer.items[1],
      sourceBank = 1,
    })
    expect(pairs).toBeTruthy()
    expect(#pairs).toBe(2)
    local tis = { pairs[1].tileIndex, pairs[2].tileIndex }
    table.sort(tis)
    expect(tis[1]).toBe(10)
    expect(tis[2]).toBe(30)
  end)

  it("collectSwapTargets uses only the context sprite when it is outside multi-selection", function()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      bank = 1,
      items = {
        { tile = 10, _bankIndex = 1, topRef = { index = 10, _bankIndex = 1 } },
        { tile = 20, _bankIndex = 1, topRef = { index = 20, _bankIndex = 1 } },
      },
      multiSpriteSelection = { [1] = true },
    }

    local pairs = SwapTwoColorsController.collectSwapTargets({
      layer = layer,
      itemIndex = 2,
      item = layer.items[2],
      sourceBank = 1,
    })
    expect(#pairs).toBe(1)
    expect(pairs[1].tileIndex).toBe(20)
  end)

  it("collectSwapTargets uses CHR refs for pattern-table OAM sprites, not logical tile bytes", function()
    local layer = {
      kind = "sprite",
      mode = "8x16",
      patternTable = { ranges = { { bank = 2, from = 0, to = 255 } } },
      items = {
        {
          startAddr = 0x100,
          tile = 16, -- logical PT slot
          tileBelow = 17,
          topRef = { index = 272, _bankIndex = 2 }, -- mapped CHR
          botRef = { index = 273, _bankIndex = 2 },
        },
      },
    }

    local pairs = SwapTwoColorsController.collectSwapTargets({
      layer = layer,
      itemIndex = 1,
      item = layer.items[1],
      sourceBank = 1, -- wrong on purpose; refs must win
    })
    expect(#pairs).toBe(2)
    expect(pairs[1].bank).toBe(2)
    expect(pairs[1].tileIndex).toBe(272)
    expect(pairs[2].bank).toBe(2)
    expect(pairs[2].tileIndex).toBe(273)
  end)

  it("applySwap records one paint event and mutates both selected tiles", function()
    local tileA = makeBankTile(1, 0, makePixels({ [1] = 1, [2] = 2 }))
    local tileB = makeBankTile(1, 1, makePixels({ [1] = 1, [2] = 0 }))
    local paintStarted = 0
    local paintFinished = 0
    local recorded = {}

    local app = {
      appEditState = {
        chrBanksBytes = { [1] = {} },
        tilesPool = {
          [1] = {
            [0] = tileA,
            [1] = tileB,
            __ready = true,
          },
        },
      },
      undoRedo = {
        startPaintEvent = function()
          paintStarted = paintStarted + 1
        end,
        finishPaintEvent = function()
          paintFinished = paintFinished + 1
        end,
        cancelPaintEvent = function() end,
        recordPixelChange = function(_, bank, tileIndex, px, py, before, after)
          recorded[#recorded + 1] = {
            bank = bank,
            tileIndex = tileIndex,
            px = px,
            py = py,
            before = before,
            after = after,
          }
        end,
      },
      setStatus = function() end,
    }

    local layer = { kind = "tile", bank = 1 }
    local win = {
      kind = "chr",
      orderMode = "normal",
      cols = 16,
      activeLayer = 1,
      layers = { layer },
      getActiveLayerIndex = function()
        return 1
      end,
      get = function(self, col, row)
        local idx = row * 16 + col
        if idx == 0 then
          return tileA
        end
        return tileB
      end,
    }
    layer.multiTileSelection = { [1] = true, [2] = true }

    local ok = SwapTwoColorsController.applySwap(app, {
      win = win,
      layer = layer,
      layerIndex = 1,
      col = 0,
      row = 0,
      item = tileA,
      sourceBank = 1,
    }, 1, 2)

    expect(ok).toBe(true)
    expect(paintStarted).toBe(1)
    expect(paintFinished).toBe(1)
    expect(tileA.pixels[1]).toBe(2)
    expect(tileA.pixels[2]).toBe(1)
    expect(tileB.pixels[1]).toBe(2)
    expect(#recorded > 0).toBe(true)
  end)

  it("remapPixelsCopy swaps without mutating source", function()
    local src = makePixels({ [1] = 0, [2] = 1, [3] = 2 })
    local out = SwapTwoColorsController.remapPixelsCopy(src, 0, 1)
    expect(out[1]).toBe(1)
    expect(out[2]).toBe(0)
    expect(out[3]).toBe(2)
    expect(src[1]).toBe(0)
    expect(src[2]).toBe(1)
  end)

  it("resolveContextPaletteNumber uses sprite paletteNumber and tile paletteNumbers", function()
    expect(SwapTwoColorsController.resolveContextPaletteNumber({
      layer = { kind = "sprite" },
      item = { paletteNumber = 3 },
    })).toBe(3)

    expect(SwapTwoColorsController.resolveContextPaletteNumber({
      layer = {
        kind = "tile",
        paletteNumbers = { [5] = 4 },
      },
      win = { cols = 16 },
      col = 5,
      row = 0,
    })).toBe(4)
  end)

  it("resolvePreviewTiles stacks CHR oddEven pairs as 8x16", function()
    local top = makeBankTile(1, 0, makePixels({ [1] = 1 }))
    local bot = makeBankTile(1, 1, makePixels({ [1] = 2 }))
    local layer = { kind = "tile", bank = 1 }
    local win = {
      kind = "chr",
      orderMode = "oddEven",
      cols = 16,
      rows = 32,
      layers = { layer },
      get = function(_, col, row)
        if col == 0 and row == 0 then return top end
        if col == 0 and row == 1 then return bot end
        return nil
      end,
      getTileIndexAt = function(_, col, row)
        if col == 0 and row == 0 then return 0 end
        if col == 0 and row == 1 then return 1 end
        return nil
      end,
    }

    local preview = SwapTwoColorsController.resolvePreviewTiles({}, {
      win = win,
      layer = layer,
      layerIndex = 1,
      col = 0,
      row = 1, -- click bottom half
      item = bot,
      sourceBank = 1,
    })
    expect(preview).toBeTruthy()
    expect(preview.mode).toBe("8x16")
    expect(preview.top).toBe(top)
    expect(preview.bot).toBe(bot)
  end)

  it("resolvePreviewTiles stacks pattern-table 8x16 tile index pairs", function()
    local top = makeBankTile(1, 4, makePixels({ [1] = 1 }))
    local bot = makeBankTile(1, 5, makePixels({ [1] = 3 }))
    local app = {
      appEditState = {
        chrBanksBytes = { [1] = {} },
        tilesPool = {
          [1] = {
            [4] = top,
            [5] = bot,
            __ready = true,
          },
        },
      },
    }
    local preview = SwapTwoColorsController.resolvePreviewTiles(app, {
      win = { kind = "pattern_table" },
      layer = { kind = "tile", mode = "8x16", bank = 1 },
      item = { index = 5, _bankIndex = 1, pixels = bot.pixels },
      tileIndex = 5,
      sourceBank = 1,
    })
    expect(preview.mode).toBe("8x16")
    expect(preview.top.index).toBe(4)
    expect(preview.bot.index).toBe(5)
  end)

  it("resolvePreviewTiles uses sprite topRef/botRef in 8x16 mode", function()
    local top = makeBankTile(1, 10, makePixels({ [1] = 1 }))
    local bot = makeBankTile(1, 11, makePixels({ [1] = 2 }))
    local preview = SwapTwoColorsController.resolvePreviewTiles({}, {
      layer = { kind = "sprite", mode = "8x16", bank = 1 },
      item = {
        tile = 10,
        tileBelow = 11,
        topRef = top,
        botRef = bot,
        paletteNumber = 1,
      },
      sourceBank = 1,
    })
    expect(preview.mode).toBe("8x16")
    expect(preview.top).toBe(top)
    expect(preview.bot).toBe(bot)
  end)
end)

describe("swap_two_colors_modal.lua - color ramp selection", function()
  it("selects at most two indices and replaces the oldest", function()
    local changes = 0
    local ramp = SwapTwoColorsModal._ColorRamp.new(function()
      changes = changes + 1
    end)
    ramp:toggleIndex(0)
    ramp:toggleIndex(2)
    local a, b = ramp:getSelectedPair()
    expect(a).toBe(0)
    expect(b).toBe(2)

    ramp:toggleIndex(3)
    a, b = ramp:getSelectedPair()
    expect(a).toBe(2)
    expect(b).toBe(3)

    ramp:toggleIndex(2)
    a, b = ramp:getSelectedPair()
    expect(a).toBeNil()
    expect(b).toBeNil()
    expect(changes > 0).toBe(true)
  end)
end)
