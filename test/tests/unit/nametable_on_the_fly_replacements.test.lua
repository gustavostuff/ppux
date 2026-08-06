local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local PatternTableMapping = require("utils.pattern_table_mapping")

describe("nametable onTheFlyReplacements", function()
  local function makeWin(layer)
    return {
      kind = "ppu_frame",
      cols = 32,
      rows = 30,
      nametableBytes = {},
      layers = { layer },
      getLayer = function(self, li)
        return self.layers[li]
      end,
      syncNametableVisualCell = function(self, col, row, byteVal, tilesPool, li)
        local L = self.layers[li or 1]
        L.items = L.items or {}
        local tileRef = PatternTableMapping.resolveTile(tilesPool, L, byteVal)
        L.items[row * self.cols + col + 1] = tileRef
      end,
      invalidateNametableLayerCanvas = function() end,
    }
  end

  local function makeTile(fill, opts)
    opts = opts or {}
    local pixels = {}
    for i = 1, 64 do
      pixels[i] = fill
    end
    return {
      pixels = pixels,
      index = opts.index,
      _bankIndex = opts.bank,
    }
  end

  it("patches nametableBytes and resolves visuals through the normal patternTable path", function()
    -- Contra-style multi-range PT: logical 160 → bank 6 CHR 160 (not bank 16 CHR 160).
    local patternTable = {
      ranges = {
        { bank = 16, from = 128, to = 191 },
        { bank = 6, from = 64, to = 255 },
      },
    }
    local map = assert(select(1, PatternTableMapping.buildMap(patternTable)))
    expect(map[160].bank).toBe(6)
    expect(map[160].tileIndex).toBe(160)

    local tilesPool = {
      [6] = {
        [160] = makeTile(2, { bank = 6, index = 160 }),
        [161] = makeTile(3, { bank = 6, index = 161 }),
      },
      [16] = {
        [160] = makeTile(1, { bank = 16, index = 160 }),
      },
    }

    local layer = {
      kind = "tile",
      items = {},
      onTheFlyReplacements = {
        { col = 8, row = 8, tileIndex = 160 },
        { col = 9, row = 8, tileIndex = 161 },
      },
      patternTable = patternTable,
    }
    local win = makeWin(layer)
    for i = 1, 32 * 30 do
      win.nametableBytes[i] = 0x05
    end
    local idx = 8 * 32 + 8 + 1
    expect(win.nametableBytes[idx]).toBe(0x05)

    local n = NametableTilesController.applyOnTheFlyReplacements(win, layer, tilesPool)
    expect(n).toBe(2)
    expect(win.nametableBytes[idx]).toBe(160)
    expect(win.nametableBytes[8 * 32 + 9 + 1]).toBe(161)
    expect(win._onTheFlyBaseByIdx[idx]).toBe(0x05)

    local tile = layer.items[idx]
    expect(tile).toBeTruthy()
    expect(tile._bankIndex).toBe(6)
    expect(tile.index).toBe(160)
    expect(tile.pixels[1]).toBe(2)

    expect(NametableTilesController.isOnTheFlyReplacementCell(layer, 8, 8, 32)).toBe(true)
    expect(NametableTilesController.onTheFlyLogicalIndexAt(layer, 8, 8, 32)).toBe(160)

    local forRom = NametableTilesController.copyNametableBytesWithoutOnTheFly(win)
    expect(forRom[idx]).toBe(0x05)
    expect(win.nametableBytes[idx]).toBe(160)
  end)

  it("re-apply restores prior overlay bases before patching again", function()
    local patternTable = { ranges = { { bank = 1, from = 0, to = 255 } } }
    local tilesPool = {
      [1] = {
        [10] = makeTile(1, { bank = 1, index = 10 }),
        [20] = makeTile(2, { bank = 1, index = 20 }),
      },
    }
    local layer = {
      kind = "tile",
      items = {},
      onTheFlyReplacements = {
        { col = 0, row = 0, tileIndex = 10 },
      },
      patternTable = patternTable,
    }
    local win = makeWin(layer)
    win.nametableBytes[1] = 7

    NametableTilesController.applyOnTheFlyReplacements(win, layer, tilesPool)
    expect(win.nametableBytes[1]).toBe(10)
    expect(win._onTheFlyBaseByIdx[1]).toBe(7)

    layer.onTheFlyReplacements = {
      { col = 0, row = 0, tileIndex = 20 },
    }
    NametableTilesController.applyOnTheFlyReplacements(win, layer, tilesPool)
    expect(win.nametableBytes[1]).toBe(20)
    expect(win._onTheFlyBaseByIdx[1]).toBe(7)
  end)

  it("snapshots onTheFlyReplacements on nametable layers", function()
    local layer = {
      kind = "tile",
      name = "nt",
      nametableStartAddr = 0x1000,
      nametableEndAddr = 0x10FF,
      onTheFlyReplacements = {
        { col = 8, row = 8, tileIndex = 160 },
      },
      patternTable = { ranges = { { bank = 1, from = 0, to = 255 } } },
    }
    local win = {
      cols = 32,
      rows = 30,
      nametableBytes = {},
      _tileSwaps = {},
    }
    for i = 1, 960 do
      win.nametableBytes[i] = 0
    end
    win._originalNametableBytes = {}
    for i = 1, 960 do
      win._originalNametableBytes[i] = 0
    end

    local snap = NametableTilesController.snapshotNametableLayer(win, layer)
    expect(snap).toBeTruthy()
    expect(snap.onTheFlyReplacements).toBeTruthy()
    expect(#snap.onTheFlyReplacements).toBe(1)
    expect(snap.onTheFlyReplacements[1].tileIndex).toBe(160)
  end)
end)
