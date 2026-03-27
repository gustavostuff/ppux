local ChrBackingController = require("controllers.rom.chr_backing_controller")

describe("chr_backing_controller.lua", function()
  it("configures chr_rom backing from parsed CHR banks and syncs legacy flags", function()
    local state = { romRaw = string.rep("\0", 32) }
    local parsed = {
      chr = {
        string.char(0x01, 0x02, 0x03),
        string.char(0x10, 0x11),
      }
    }

    local banks, err = ChrBackingController.configureFromParsedINES(state, parsed)
    expect(err).toBeNil()
    expect(banks).toBeTruthy()
    expect(#banks).toBe(2)
    expect(state.chrBacking.mode).toBe("chr_rom")
    expect(state.romTileViewMode).toBeFalsy()
    expect(state.romTileViewDataOffset).toBeNil()
    expect(banks[1][1]).toBe(0x01)
    expect(banks[1][2]).toBe(0x02)
    expect(banks[2][1]).toBe(0x10)
  end)

  it("configures rom_raw backing using pseudo banks that skip the iNES header", function()
    local header = string.rep("\255", 16)
    local body = string.rep("A", 8192) .. string.rep("B", 10)
    local state = { romRaw = header .. body }
    local parsed = { chr = {} }

    local banks, err = ChrBackingController.configureFromParsedINES(state, parsed)
    expect(err).toBeNil()
    expect(banks).toBeTruthy()
    expect(state.chrBacking.mode).toBe("rom_raw")
    expect(state.romTileViewMode).toBeTruthy()
    expect(state.chrBacking.dataOffset).toBe(16)
    expect(state.chrBacking.dataSize).toBe(#body)
    expect(state.chrBacking.originalSize).toBe(#state.romRaw)
    expect(#banks).toBe(2)
    expect(banks[1][1]).toBe(string.byte("A"))
    expect(banks[2][1]).toBe(string.byte("B"))
    expect(banks[2][10]).toBe(string.byte("B"))
    expect(banks[2][11]).toBe(0)
  end)

  it("rebuilds raw ROM from rom_raw pseudo banks while preserving header and size", function()
    local header = string.rep("\170", 16)
    local body = string.rep("\0", 32)
    local state = { romRaw = header .. body, chrBanksBytes = {} }
    local _, err = ChrBackingController.configureFromParsedINES(state, { chr = {} })
    expect(err).toBeNil()

    state.chrBanksBytes[1][1] = 0x12
    state.chrBanksBytes[1][32] = 0x34

    local rebuilt, rebuildErr = ChrBackingController.rebuildROMFromBacking(state)
    expect(rebuildErr).toBeNil()
    expect(type(rebuilt)).toBe("string")
    expect(#rebuilt).toBe(#header + #body)
    expect(rebuilt:sub(1, 16)).toBe(header)
    expect(string.byte(rebuilt, 17)).toBe(0x12)
    expect(string.byte(rebuilt, 48)).toBe(0x34)
  end)

  it("builds descriptor from legacy romTileView fields for compatibility", function()
    local state = {
      romRaw = string.rep("\0", 64),
      romTileViewMode = true,
      romTileViewOriginalSize = 64,
      romTileViewDataOffset = 16,
      romTileViewDataSize = 48,
    }

    local desc = ChrBackingController.getDescriptor(state)
    expect(desc).toBeTruthy()
    expect(desc.mode).toBe("rom_raw")
    expect(desc.dataOffset).toBe(16)
    expect(desc.dataSize).toBe(48)
    expect(ChrBackingController.isRomRawMode(state)).toBeTruthy()
  end)
end)
