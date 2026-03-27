-- chr_duplicate_sync.test.lua

local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local chr = require("chr")

local function makeBank(tileCount)
  local bytes = {}
  for i = 1, tileCount * 16 do
    bytes[i] = 0
  end
  return bytes
end

local function sortMatches(matches)
  table.sort(matches, function(a, b)
    if a.bank == b.bank then
      return a.tileIndex < b.tileIndex
    end
    return a.bank < b.bank
  end)
  return matches
end

describe("ChrDuplicateSync", function()
  it("builds frozen sync groups and keeps them static until rebuilt", function()
    local bank1 = makeBank(2)
    local bank2 = makeBank(1)

    -- Make bank1 tile1 and bank2 tile0 identical
    chr.setTilePixel(bank1, 1, 0, 0, 1)
    chr.setTilePixel(bank2, 0, 0, 0, 1)

    local state = { chrBanksBytes = { bank1, bank2 } }

    ChrDuplicateSync.buildSyncGroups(state)
    local matches = sortMatches(ChrDuplicateSync.getSyncGroup(state, 1, 1, true))
    expect(#matches).toBe(2)
    expect(matches[1]).toEqual({ bank = 1, tileIndex = 1 })
    expect(matches[2]).toEqual({ bank = 2, tileIndex = 0 })

    -- Diverge bank2 tile0 so it no longer matches; group should stay frozen
    chr.setTilePixel(bank2, 0, 1, 0, 2)
    ChrDuplicateSync.updateTiles(state, { { bank = 2, tileIndex = 0 } })
    local frozen = ChrDuplicateSync.getSyncGroup(state, 1, 1, true)
    expect(#frozen).toBe(2)

    -- Rebuild groups to reflect current patterns (now diverged)
    ChrDuplicateSync.buildSyncGroups(state)
    local regrouped = ChrDuplicateSync.getSyncGroup(state, 1, 1, true)
    expect(#regrouped).toBe(1)
    expect(regrouped[1]).toEqual({ bank = 1, tileIndex = 1 })
  end)

  it("reindexBank refreshes signatures and removes stale matches", function()
    local bank1 = makeBank(1)
    local bank2 = makeBank(1)

    -- Start identical
    chr.setTilePixel(bank1, 0, 2, 2, 3)
    chr.setTilePixel(bank2, 0, 2, 2, 3)

    local state = { chrBanksBytes = { bank1, bank2 } }
    ChrDuplicateSync.buildSyncGroups(state)
    expect(#ChrDuplicateSync.getSyncGroup(state, 1, 0, true)).toBe(2)

    -- Change bank1 tile0 so it no longer matches
    chr.setTilePixel(bank1, 0, 0, 7, 1)
    ChrDuplicateSync.reindexBank(state, 1)

    local match1 = ChrDuplicateSync.getSyncGroup(state, 1, 0, true)
    expect(#match1).toBe(1)
    expect(match1[1]).toEqual({ bank = 1, tileIndex = 0 })

    local match2 = ChrDuplicateSync.getSyncGroup(state, 2, 0, true)
    expect(#match2).toBe(1)
    expect(match2[1]).toEqual({ bank = 2, tileIndex = 0 })
  end)

  it("honors sync toggle defaulting to disabled", function()
    local app = {}
    expect(ChrDuplicateSync.isEnabled(app)).toBeFalsy()
    app.syncDuplicateTiles = false
    expect(ChrDuplicateSync.isEnabled(app)).toBeFalsy()
    app.syncDuplicateTiles = true
    expect(ChrDuplicateSync.isEnabled(app)).toBeTruthy()
  end)

  it("ignores flat single-color tiles when building duplicate sync groups", function()
    local bank1 = makeBank(1)
    local bank2 = makeBank(1)
    local state = { chrBanksBytes = { bank1, bank2 } }

    ChrDuplicateSync.buildSyncGroups(state)

    local matches = ChrDuplicateSync.getSyncGroup(state, 1, 0, true)
    expect(#matches).toBe(1)
    expect(matches[1]).toEqual({ bank = 1, tileIndex = 0 })
  end)

  it("ignores non-zero flat-color tiles when building duplicate sync groups", function()
    local bank1 = makeBank(1)
    local bank2 = makeBank(1)
    local state = { chrBanksBytes = { bank1, bank2 } }

    for y = 0, 7 do
      for x = 0, 7 do
        chr.setTilePixel(bank1, 0, x, y, 1)
        chr.setTilePixel(bank2, 0, x, y, 1)
      end
    end

    ChrDuplicateSync.buildSyncGroups(state)

    local matches = ChrDuplicateSync.getSyncGroup(state, 1, 0, true)
    expect(#matches).toBe(1)
    expect(matches[1]).toEqual({ bank = 1, tileIndex = 0 })
  end)

  it("does not return a frozen sync group for a tile that is currently flat-color", function()
    local bank1 = makeBank(1)
    local bank2 = makeBank(1)

    chr.setTilePixel(bank1, 0, 0, 0, 1)
    chr.setTilePixel(bank2, 0, 0, 0, 1)

    local state = { chrBanksBytes = { bank1, bank2 } }
    ChrDuplicateSync.buildSyncGroups(state)
    expect(#ChrDuplicateSync.getSyncGroup(state, 1, 0, true)).toBe(2)

    for y = 0, 7 do
      for x = 0, 7 do
        chr.setTilePixel(bank1, 0, x, y, 2)
      end
    end

    local matches = ChrDuplicateSync.getSyncGroup(state, 1, 0, true)
    expect(#matches).toBe(1)
    expect(matches[1]).toEqual({ bank = 1, tileIndex = 0 })
  end)

  it("disables sync for ROM bank windows even when the app toggle is on", function()
    local app = { syncDuplicateTiles = true }

    expect(ChrDuplicateSync.isEnabledForWindow(app, { kind = "chr", isRomWindow = true })).toBeFalsy()
    expect(ChrDuplicateSync.isEnabledForWindow(app, { kind = "chr", isRomWindow = false })).toBeTruthy()
    expect(ChrDuplicateSync.isEnabledForWindow(app, nil)).toBeTruthy()
  end)

  it("rebuilds a complete index lazily after edits happened without one", function()
    local bank1 = makeBank(1)
    local bank2 = makeBank(1)

    chr.setTilePixel(bank1, 0, 1, 1, 2)
    chr.setTilePixel(bank2, 0, 1, 1, 2)

    local state = { chrBanksBytes = { bank1, bank2 } }

    ChrDuplicateSync.updateTiles(state, {
      { bank = 1, tileIndex = 0 },
    })

    expect(state.tileSignatureIndexReady).toBeFalsy()
    expect(state.tileSignatureIndex).toBeNil()

    local matches = sortMatches(ChrDuplicateSync.getMatchingTiles(state, 1, 0))
    expect(#matches).toBe(2)
    expect(matches[1]).toEqual({ bank = 1, tileIndex = 0 })
    expect(matches[2]).toEqual({ bank = 2, tileIndex = 0 })
    expect(state.tileSignatureIndexReady).toBeTruthy()
  end)

  it("clearSyncGroups also clears duplicate indexes", function()
    local bank1 = makeBank(1)
    local bank2 = makeBank(1)

    chr.setTilePixel(bank1, 0, 0, 0, 1)
    chr.setTilePixel(bank2, 0, 0, 0, 1)

    local state = { chrBanksBytes = { bank1, bank2 } }
    ChrDuplicateSync.buildSyncGroups(state)

    expect(state.tileSignatureIndexReady).toBeTruthy()
    expect(state.tileSignatureIndex).toBeTruthy()

    ChrDuplicateSync.clearSyncGroups(state)

    expect(state.syncGroups).toBeNil()
    expect(state.tileSignatureIndex).toBeNil()
    expect(state.tileSignatureByTile).toBeNil()
    expect(state.tileSignatureIndexReady).toBeFalsy()
  end)
end)
