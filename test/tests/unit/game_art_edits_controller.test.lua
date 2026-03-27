local GameArtEditsController = require("controllers.game_art.edits_controller")
local chr = require("chr")

describe("game_art_edits_controller.lua", function()
  it("compressEditsRLE/decompressEditsRLE round-trip preserves pixel edits", function()
    local edits = GameArtEditsController.newEdits()
    GameArtEditsController.recordEdit(edits, 1, 10, 0, 0, 1)
    GameArtEditsController.recordEdit(edits, 1, 10, 7, 7, 2)
    GameArtEditsController.recordEdit(edits, 2, 3, 4, 5, 3)

    local compressed = GameArtEditsController.compressEditsRLE(edits)
    expect(compressed).toBeTruthy()
    expect(type(compressed.banks[1]["10"])).toBe("string")
    expect(type(compressed.banks[2]["3"])).toBe("string")

    local roundtrip = GameArtEditsController.decompressEditsRLE(compressed)
    expect(roundtrip).toEqual(edits)
  end)

  it("decompressEdits expands tile ranges and pixel rectangle ranges", function()
    local decompressed = GameArtEditsController.decompressEdits({
      banks = {
        [1] = {
          ["4-5"] = {
            ["1_1-2_2"] = 3,
            ["7_0"] = 1,
          },
        },
      },
    })

    expect(decompressed.banks[1][4]).toBeTruthy()
    expect(decompressed.banks[1][5]).toBeTruthy()
    expect(decompressed.banks[1][4]["1_1"]).toBe(3)
    expect(decompressed.banks[1][4]["2_1"]).toBe(3)
    expect(decompressed.banks[1][4]["1_2"]).toBe(3)
    expect(decompressed.banks[1][4]["2_2"]).toBe(3)
    expect(decompressed.banks[1][4]["7_0"]).toBe(1)
    expect(decompressed.banks[1][5]).toEqual(decompressed.banks[1][4])
    decompressed.banks[1][5]["0_0"] = 2
    expect(decompressed.banks[1][4]["0_0"]).toBeNil()
    expect(decompressed.banks[1][5]["0_0"]).toBe(2)
  end)

  it("buildEditsFromChrDiff keeps only real pixel differences from CHR bytes", function()
    local originalBank = {}
    local currentBank = {}
    for i = 1, 16 do
      originalBank[i] = 0
      currentBank[i] = 0
    end

    chr.setTilePixel(currentBank, 0, 2, 3, 1)

    local edits = GameArtEditsController.buildEditsFromChrDiff(
      { originalBank },
      { currentBank }
    )
    local compressed = GameArtEditsController.compressEdits(edits)

    expect(compressed.banks[1]).toBeTruthy()
    local roundtrip = GameArtEditsController.decompressEdits(compressed)
    expect(roundtrip.banks[1][0]["2_3"]).toBe(1)
    local count = 0
    for _ in pairs(roundtrip.banks[1][0]) do
      count = count + 1
    end
    expect(count).toBe(1)
  end)

  it("applyEdits supports string RLE and legacy table formats", function()
    local originalSetTilePixel = chr.setTilePixel
    local setCalls = {}
    chr.setTilePixel = function(bankBytes, tileIdx, x, y, color)
      setCalls[#setCalls + 1] = {
        bankBytes = bankBytes,
        tileIdx = tileIdx,
        x = x, y = y, color = color,
      }
    end

    local tileEdits = {}
    local tilesPool = {
      [1] = {
        [2] = {
          edit = function(_, x, y, color)
            tileEdits[#tileEdits + 1] = { tile = 2, x = x, y = y, color = color }
          end
        },
        [3] = {
          edit = function(_, x, y, color)
            tileEdits[#tileEdits + 1] = { tile = 3, x = x, y = y, color = color }
          end
        },
      }
    }
    local chrBanksBytes = { [1] = {} }
    local ensured = {}

    local ok, err = pcall(function()
      local legacyForTile3 = {
        ["0_0-1_0"] = 2, -- expands to 0_0 and 1_0
      }
      local compressedForTile2 = GameArtEditsController.compressEdits({
        banks = { [1] = { [2] = { ["3_4"] = 1 } } }
      })

      GameArtEditsController.applyEdits({
        banks = {
          [1] = {
            ["2"] = compressedForTile2.banks[1]["2"], -- string RLE path
            ["3"] = legacyForTile3,                   -- legacy table path
          }
        }
      }, tilesPool, chrBanksBytes, function(bankIdx)
        ensured[#ensured + 1] = bankIdx
      end)
    end)

    chr.setTilePixel = originalSetTilePixel
    if not ok then error(err) end

    expect(#ensured).toBe(0)

    -- tile 2 from RLE string
    local foundTile2 = false
    local foundTile3_00 = false
    local foundTile3_10 = false
    for _, c in ipairs(setCalls) do
      if c.tileIdx == 2 and c.x == 3 and c.y == 4 and c.color == 1 then
        foundTile2 = true
      end
      if c.tileIdx == 3 and c.x == 0 and c.y == 0 and c.color == 2 then
        foundTile3_00 = true
      end
      if c.tileIdx == 3 and c.x == 1 and c.y == 0 and c.color == 2 then
        foundTile3_10 = true
      end
    end
    expect(foundTile2).toBeTruthy()
    expect(foundTile3_00).toBeTruthy()
    expect(foundTile3_10).toBeTruthy()

    -- tileRef:edit should be called for both tiles too
    local editCountByTile = { [2] = 0, [3] = 0 }
    for _, e in ipairs(tileEdits) do
      editCountByTile[e.tile] = (editCountByTile[e.tile] or 0) + 1
    end
    expect(editCountByTile[2]).toBeGreaterThan(0)
    expect(editCountByTile[3]).toBeGreaterThan(0)
  end)

  it("applyEdits updates CHR bytes even when a bank has no loaded tile refs", function()
    local originalSetTilePixel = chr.setTilePixel
    local setCalls = {}
    chr.setTilePixel = function(bankBytes, tileIdx, x, y, color)
      setCalls[#setCalls + 1] = {
        bankBytes = bankBytes,
        tileIdx = tileIdx,
        x = x, y = y, color = color,
      }
    end

    local chrBanksBytes = { [2] = {} }
    local ensureCalls = {}

    local ok, err = pcall(function()
      GameArtEditsController.applyEdits({
        banks = {
          [2] = {
            [7] = {
              ["4_5"] = 3,
            },
          },
        },
      }, {}, chrBanksBytes, function(bankIdx)
        ensureCalls[#ensureCalls + 1] = bankIdx
      end)
    end)

    chr.setTilePixel = originalSetTilePixel
    if not ok then error(err) end

    expect(#ensureCalls).toBe(0)
    expect(#setCalls).toBe(1)
    expect(setCalls[1].tileIdx).toBe(7)
    expect(setCalls[1].x).toBe(4)
    expect(setCalls[1].y).toBe(5)
    expect(setCalls[1].color).toBe(3)
  end)
end)
