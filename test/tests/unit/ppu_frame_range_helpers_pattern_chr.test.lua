local PpuRange = require("controllers.app.ppu_frame_range_helpers")

describe("ppu_frame_range_helpers — CHR → pattern range plan", function()
  it("orders LRTB then packs holes into one explicit tiles range", function()
    local win = { currentBank = 1 }
    local g = {
      entries = {
        { srcCol = 2, srcRow = 0, item = { index = 11, _bankIndex = 1 } },
        { srcCol = 0, srcRow = 0, item = { index = 10, _bankIndex = 1 } },
        { srcCol = 1, srcRow = 0, item = { index = 20, _bankIndex = 1 } },
      },
    }
    local r, n, err, ord = PpuRange.planPatternRangesFromChrTileGroup(win, 1, g)
    expect(err).toBeNil()
    expect(#ord).toBe(3)
    expect(#r).toBe(1)
    expect(n).toBe(3)
    local tiles = r[1].tiles
    expect(#tiles).toBe(3)
    expect(tiles[1].byte).toBe(10)
    expect(tiles[2].byte).toBe(20)
    expect(tiles[3].byte).toBe(11)
  end)

  it("keeps consecutive bytes in one tiles list (still one logical range)", function()
    local win = { currentBank = 1 }
    local g = {
      entries = {
        { srcCol = 0, srcRow = 0, item = { index = 5, _bankIndex = 1 } },
        { srcCol = 2, srcRow = 0, item = { index = 7, _bankIndex = 1 } },
        { srcCol = 1, srcRow = 0, item = { index = 6, _bankIndex = 1 } },
      },
    }
    local r, n, err = PpuRange.planPatternRangesFromChrTileGroup(win, 1, g)
    expect(err).toBeNil()
    expect(#r).toBe(1)
    expect(#r[1].tiles).toBe(3)
    expect(r[1].tiles[1].byte).toBe(5)
    expect(r[1].tiles[2].byte).toBe(6)
    expect(r[1].tiles[3].byte).toBe(7)
    expect(n).toBe(3)
  end)

  it("uses page 2 when tile index >= 256", function()
    local win = { currentBank = 3 }
    local g = {
      entries = {
        { srcCol = 0, srcRow = 0, item = { index = 300, _bankIndex = 2 } },
      },
    }
    local r, n, err = PpuRange.planPatternRangesFromChrTileGroup(win, 1, g)
    expect(err).toBeNil()
    expect(n).toBe(1)
    expect(#r).toBe(1)
    expect(#r[1].tiles).toBe(1)
    expect(r[1].tiles[1].page).toBe(2)
    expect(r[1].tiles[1].byte).toBe(44)
    expect(r[1].tiles[1].bank).toBe(2)
  end)

  it("grid cell for logical 0 is top-left in 8x8 mode", function()
    local win = { cols = 16, rows = 16 }
    local layer = { mode = "8x8" }
    local c, rrow = PpuRange.patternTableGridCellForLogicalIndex(win, layer, 0)
    expect(c).toBe(0)
    expect(rrow).toBe(0)
  end)

  it("matches CHR oddEven layout against pattern-table 8×16 tile layer mode only", function()
    local chrOdd = { orderMode = "oddEven" }
    local chrNm = { orderMode = "normal" }
    expect(PpuRange.chrLayoutMatchesPatternTableLayer(chrOdd, { mode = "8x16" })).toBe(true)
    expect(PpuRange.chrLayoutMatchesPatternTableLayer(chrOdd, { mode = "8x8" })).toBe(false)
    expect(PpuRange.chrLayoutMatchesPatternTableLayer(chrNm, { mode = "8x8" })).toBe(true)
    expect(PpuRange.chrLayoutMatchesPatternTableLayer(chrNm, { mode = "8x16" })).toBe(false)
  end)

  it("rejects odd CHR increments on 8×16 pattern layouts", function()
    expect(select(1, PpuRange.patternTableAppendChrParityOk({ mode = "8x16" }, 0, 1))).toBe(false)
    expect(select(1, PpuRange.patternTableAppendChrParityOk({ mode = "8x16" }, 1, 2))).toBe(false)
    expect(select(1, PpuRange.patternTableAppendChrParityOk({ mode = "8x16" }, 0, 2))).toBe(true)
    expect(select(1, PpuRange.patternTableAppendChrParityOk({ mode = "8x8" }, 0, 1))).toBe(true)
  end)

  it("plans 8x16 CHR selection as one explicit tiles range (four bytes)", function()
    local win = { orderMode = "oddEven", currentBank = 1 }
    local g = {
      sourceSelectionMode = "8x16",
      spriteEntries = {
        {
          srcCol = 1,
          srcRow = 0,
          item = { index = 40, _bankIndex = 1 },
          bottomItem = { index = 41, _bankIndex = 1 },
        },
        {
          srcCol = 0,
          srcRow = 0,
          item = { index = 50, _bankIndex = 1 },
          bottomItem = { index = 51, _bankIndex = 1 },
        },
      },
    }
    local r, n, err = PpuRange.planPatternRangesFromChrTileGroup(win, 1, g)
    expect(err).toBeNil()
    expect(n).toBe(4)
    expect(#r).toBe(1)
    local tiles = r[1].tiles
    expect(#tiles).toBe(4)
    expect(tiles[1].byte).toBe(50)
    expect(tiles[2].byte).toBe(51)
    expect(tiles[3].byte).toBe(40)
    expect(tiles[4].byte).toBe(41)
  end)

  it("compactPatternTableForPersistence merges explicit tiles into from/to rows", function()
    local pt = {
      ranges = {
        {
          tiles = {
            { bank = 1, tileIndex = 10 },
            { bank = 1, tileIndex = 20 },
            { bank = 1, tileIndex = 11 },
          },
        },
        {
          tiles = {
            { bank = 2, tileIndex = 5 },
            { bank = 2, tileIndex = 6 },
            { bank = 2, tileIndex = 7 },
          },
        },
      },
    }
    local out = PpuRange.compactPatternTableForPersistence(pt)
    expect(#out.ranges).toBe(4)
    expect(out.ranges[1]).toEqual({ bank = 1, from = 10, to = 10 })
    expect(out.ranges[2]).toEqual({ bank = 1, from = 20, to = 20 })
    expect(out.ranges[3]).toEqual({ bank = 1, from = 11, to = 11 })
    expect(out.ranges[4]).toEqual({ bank = 2, from = 5, to = 7 })
  end)

  it("compactPatternTableForPersistence normalizes legacy page+from/to rows", function()
    local pt = {
      ranges = {
        { bank = 3, page = 2, from = 0, to = 15 },
      },
    }
    local out = PpuRange.compactPatternTableForPersistence(pt)
    expect(#out.ranges).toBe(1)
    expect(out.ranges[1]).toEqual({ bank = 3, from = 256, to = 271 })
  end)
end)
