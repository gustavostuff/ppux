local RomPatchController = require("controllers.game_art.rom_patch_controller")
local DebugController = require("controllers.dev.debug_controller")
local chr = require("chr")

describe("game_art_rom_patch_controller.lua", function()
  local originals

  beforeEach(function()
    originals = {
      writeByteToAddress = chr.writeByteToAddress,
      log = DebugController.log,
    }
  end)

  afterEach(function()
    chr.writeByteToAddress = originals.writeByteToAddress
    DebugController.log = originals.log
  end)

  it("returns an error for non-string romRaw", function()
    local patched, err, applied = RomPatchController.applyRomPatches({}, {
      { address = 0, value = 1, reason = "x" }
    })

    expect(patched).toBeNil()
    expect(err).toBe("romRaw must be string")
    expect(applied).toBe(0)
  end)

  it("returns original rom and zero applied when patches are invalid or empty", function()
    local romRaw = string.char(1, 2, 3)

    local patched1, err1, applied1 = RomPatchController.applyRomPatches(romRaw, nil)
    expect(patched1).toBe(romRaw)
    expect(err1).toBeNil()
    expect(applied1).toBe(0)

    local patched2, err2, applied2 = RomPatchController.applyRomPatches(romRaw, {
      { address = -1, value = 0x10, reason = "bad" },
      { address = 0x01, value = 0x10, reason = 123 },
    })
    expect(patched2).toBe(romRaw)
    expect(err2).toBeNil()
    expect(applied2).toBe(0)
  end)

  it("continues applying patches when one write fails and logs a warning", function()
    local romRaw = string.char(0x00, 0x01, 0x02, 0x03)
    local logCalls = {}

    DebugController.log = function(level, category, message, ...)
      logCalls[#logCalls + 1] = {
        level = level,
        category = category,
        message = message,
        args = { ... },
      }
    end

    chr.writeByteToAddress = function(raw, address, value)
      if address == 1 then
        return nil, "forced-failure"
      end
      return originals.writeByteToAddress(raw, address, value)
    end

    local patched, err, applied = RomPatchController.applyRomPatches(romRaw, {
      { addresses = { from = 0, to = 2 }, values = { 0x10, 0x11, 0x12 }, reason = "seq" }
    })

    expect(err).toBeNil()
    expect(applied).toBe(2)
    expect(string.byte(patched, 1)).toBe(0x10)
    expect(string.byte(patched, 2)).toBe(0x01) -- failed write unchanged
    expect(string.byte(patched, 3)).toBe(0x12)
    expect(#logCalls).toBe(1)
    expect(logCalls[1].level).toBe("warning")
    expect(logCalls[1].category).toBe("ROM_PATCH")
    expect(string.find(logCalls[1].message, "Skipping sequence patch", 1, true)).toNotBe(nil)
  end)

  it("normalizes address-list and range-sequence patch formats directly", function()
    local normalized = RomPatchController.normalizeRomPatches({
      { addresses = { 0x20, 0x22 }, values = { 0xAA, 0xBB }, reason = "list" },
      { from = 0x30, to = 0x31, values = { 0xCC, 0xDD }, reason = "range" },
      { addresses = { from = 0x40, to = 0x41, 0x99 }, values = { 0xEE, 0xEF }, reason = "range-priority" },
    })

    expect(#normalized).toBe(3)
    expect(normalized[1].addresses[1]).toBe(0x20)
    expect(normalized[1].values[2]).toBe(0xBB)
    expect(normalized[2].addresses.from).toBe(0x30)
    expect(normalized[2].addresses.to).toBe(0x31)
    expect(normalized[3].addresses.from).toBe(0x40)
    expect(normalized[3].addresses.to).toBe(0x41)
    expect(normalized[3].values[1]).toBe(0xEE)
    expect(normalized[3].values[2]).toBe(0xEF)
  end)
end)

