local WM = require("controllers.window.window_controller")
local GameArtController = require("controllers.game_art.game_art_controller")
local chr = require("chr")

describe("game_art_controller.lua - romPatches", function()
  it("normalizes valid patches and drops invalid entries", function()
    local normalized = GameArtController.normalizeRomPatches({
      { address = 0x10, value = 0x2A, reason = "valid" },
      { addresses = { from = 0x20, to = 0x22 }, values = { 0x30, 0x31, 0x32 }, reason = "valid range sequence" },
      { addresses = { 0x40, 0x42 }, values = { 0x50, 0x51 }, reason = "valid address list sequence" },
      { from = 0x60, to = 0x61, values = { 0x70, 0x71 }, reason = "valid top-level range sequence" },
      {
        addresses = { from = 0x80, to = 0x81, 0x90, 0x91 },
        values = { 0xA0, 0xA1 },
        reason = "range fields win over address list",
      },
      { address = -1, value = 0x10, reason = "bad addr" },
      { address = 0x20, value = 0x100, reason = "bad value" },
      { address = 0x30, value = 0x12, reason = 123 },
      { addresses = { 0x40, 0x41 }, values = { 0x50 }, reason = "bad address list length" },
      { addresses = { 0x42, 0x43 }, values = { 0x100, 0x10 }, reason = "bad address list value" },
      { addresses = { from = 0x40, to = 0x41 }, values = { 0x50 }, reason = "bad range length" },
      { addresses = { from = 0x42, to = 0x43 }, values = { 0x100, 0x10 }, reason = "bad range value" },
      { addresses = { from = 0x50, to = 0x4F }, values = { 0x01, 0x02 }, reason = "inverted range" },
      { from = 0x70, to = 0x71, values = { 0x01 }, reason = "bad top-level range length" },
      { address = 0x44, value = 0x10, addresses = { 0x45 }, values = { 0x11 }, reason = "mixed formats" },
      { address = 0x40, value = 0x7F, reason = "valid 2" },
    })

    expect(normalized).toBeTruthy()
    expect(#normalized).toBe(6)
    expect(normalized[1].address).toBe(0x10)
    expect(normalized[1].value).toBe(0x2A)
    expect(normalized[1].reason).toBe("valid")
    expect(normalized[2].addresses.from).toBe(0x20)
    expect(normalized[2].addresses.to).toBe(0x22)
    expect(normalized[2].values[1]).toBe(0x30)
    expect(normalized[2].values[2]).toBe(0x31)
    expect(normalized[2].values[3]).toBe(0x32)
    expect(normalized[2].reason).toBe("valid range sequence")
    expect(normalized[3].addresses[1]).toBe(0x40)
    expect(normalized[3].addresses[2]).toBe(0x42)
    expect(normalized[3].values[1]).toBe(0x50)
    expect(normalized[3].values[2]).toBe(0x51)
    expect(normalized[3].reason).toBe("valid address list sequence")
    expect(normalized[4].addresses.from).toBe(0x60)
    expect(normalized[4].addresses.to).toBe(0x61)
    expect(normalized[4].values[1]).toBe(0x70)
    expect(normalized[4].values[2]).toBe(0x71)
    expect(normalized[4].reason).toBe("valid top-level range sequence")
    expect(normalized[5].addresses.from).toBe(0x80)
    expect(normalized[5].addresses.to).toBe(0x81)
    expect(normalized[5].values[1]).toBe(0xA0)
    expect(normalized[5].values[2]).toBe(0xA1)
    expect(normalized[5].reason).toBe("range fields win over address list")
    expect(normalized[6].address).toBe(0x40)
    expect(normalized[6].value).toBe(0x7F)
  end)

  it("applies single, range-sequence, and address-list patches directly to romRaw bytes", function()
    local romRaw = string.char(0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06)
    local patched, err, applied = GameArtController.applyRomPatches(romRaw, {
      { address = 0, value = 0x99, reason = "patch first byte" },
      { addresses = { from = 1, to = 3 }, values = { 0xAA, 0xBB, 0xCC }, reason = "patch range bytes" },
      { addresses = { 5, 6 }, values = { 0xDD, 0xEE }, reason = "patch explicit addresses" },
      { address = 9999, value = 0xCC, reason = "out of bounds" }, -- ignored
    })

    expect(err).toBeNil()
    expect(applied).toBe(6)
    expect(string.byte(patched, 1)).toBe(0x99)
    expect(string.byte(patched, 2)).toBe(0xAA)
    expect(string.byte(patched, 3)).toBe(0xBB)
    expect(string.byte(patched, 4)).toBe(0xCC)
    expect(string.byte(patched, 5)).toBe(0x04)
    expect(string.byte(patched, 6)).toBe(0xDD)
    expect(string.byte(patched, 7)).toBe(0xEE)
  end)

  it("includes romPatches in project snapshot when provided", function()
    local wm = WM.new()
    local project = GameArtController.snapshotProject(wm, nil, 1, nil, {
      currentColor = 1,
      syncDuplicateTiles = false,
      appEditState = {
        romPatches = {
          { address = 0x1234, value = 0x0F, reason = "keep black" },
          { addresses = { from = 0x2000, to = 0x2001 }, values = { 0x80, 0x81 }, reason = "sequence" },
          { addresses = { 0x3000, 0x3003 }, values = { 0x82, 0x83 }, reason = "list sequence" },
        },
      },
    })

    expect(project.romPatches).toBeTruthy()
    expect(#project.romPatches).toBe(3)
    expect(project.romPatches[1].address).toBe(0x1234)
    expect(project.romPatches[1].value).toBe(0x0F)
    expect(project.romPatches[1].reason).toBe("keep black")
    expect(project.romPatches[2].addresses.from).toBe(0x2000)
    expect(project.romPatches[2].addresses.to).toBe(0x2001)
    expect(project.romPatches[2].values[1]).toBe(0x80)
    expect(project.romPatches[2].values[2]).toBe(0x81)
    expect(project.romPatches[2].reason).toBe("sequence")
    expect(project.romPatches[3].addresses[1]).toBe(0x3000)
    expect(project.romPatches[3].addresses[2]).toBe(0x3003)
    expect(project.romPatches[3].values[1]).toBe(0x82)
    expect(project.romPatches[3].values[2]).toBe(0x83)
    expect(project.romPatches[3].reason).toBe("list sequence")
  end)

  it("builds project edits from CHR diffs when original CHR banks are available", function()
    local wm = WM.new()
    local originalBank = {}
    local currentBank = {}
    for i = 1, 16 do
      originalBank[i] = 0
      currentBank[i] = 0
    end
    chr.setTilePixel(currentBank, 0, 4, 5, 2)

    local noisyTile = {}
    for y = 0, 7 do
      for x = 0, 7 do
        noisyTile[string.format("%d_%d", x, y)] = 0
      end
    end

    local project = GameArtController.snapshotProject(wm, nil, 1, {
      banks = {
        [1] = {
          [0] = noisyTile,
        },
      },
    }, {
      appEditState = {
        originalChrBanksBytes = { originalBank },
        chrBanksBytes = { currentBank },
      },
    })

    local decompressed = GameArtController.decompressEdits(project.edits)
    expect(decompressed.banks[1][0]["4_5"]).toBe(2)
    local count = 0
    for _ in pairs(decompressed.banks[1][0]) do
      count = count + 1
    end
    expect(count).toBe(1)
  end)
end)
