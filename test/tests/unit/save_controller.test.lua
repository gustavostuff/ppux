local SaveController = require("controllers.rom.save_controller")
local ChrBackingController = require("controllers.rom.chr_backing_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local RomSave = require("romsave")
local chr = require("chr")

describe("save_controller.lua", function()
  local originals

  local function makeChrRomState(romBody)
    local header = string.rep("\0", 16)
    local state = {
      romRaw = header .. (romBody or string.rep("\0", 32)),
      romOriginalPath = "/tmp/test.nes",
      meta = { prgBanks = 1, chrBanks = 1 },
      chrBanksBytes = {},
    }
    local _, err = ChrBackingController.configureFromParsedINES(state, {
      chr = { string.rep("\0", 8192) },
    })
    expect(err).toBeNil()
    return state
  end

  local function makeApp(state, opts)
    opts = opts or {}
    local ppuFrames = opts.ppuFrames or {}
    local romPalettes = opts.romPalettes or {}
    local allWindows = opts.allWindows or ppuFrames

    return {
      appEditState = state,
      wm = {
        getWindowsOfKind = function(_, kind)
          if kind == "ppu_frame" then
            return ppuFrames
          end
          if kind == "rom_palette" then
            return romPalettes
          end
          return {}
        end,
        getWindows = function()
          return allWindows
        end,
      },
      setStatus = function(self, text)
        self.statusText = text
      end,
    }
  end

  local function ppuFrameWithNametable(title, ntLayer)
    return {
      kind = "ppu_frame",
      title = title,
      layers = {
        ntLayer or {
          kind = "tile",
          nametableStartAddr = 0x2000,
        },
      },
    }
  end

  local function makeRomPaletteWindow(title, romAddr, hexCode, row, col)
    row = row or 0
    col = col or 0
    return {
      title = title,
      paletteData = {
        romColors = {
          [row + 1] = {
            [col + 1] = romAddr,
          },
        },
      },
      codes2D = {
        [row] = {
          [col] = hexCode,
        },
      },
    }
  end

  beforeEach(function()
    originals = {
      writeBackToROM = NametableTilesController.writeBackToROM,
      applyDisplacementsToROMForWindows = SpriteController.applyDisplacementsToROMForWindows,
      saveRawROM = RomSave.saveRawROM,
      saveEditedROM = RomSave.saveEditedROM,
      writeByteToAddress = chr.writeByteToAddress,
      rebuildROMFromBacking = ChrBackingController.rebuildROMFromBacking,
    }
  end)

  afterEach(function()
    NametableTilesController.writeBackToROM = originals.writeBackToROM
    SpriteController.applyDisplacementsToROMForWindows = originals.applyDisplacementsToROMForWindows
    RomSave.saveRawROM = originals.saveRawROM
    RomSave.saveEditedROM = originals.saveEditedROM
    chr.writeByteToAddress = originals.writeByteToAddress
    ChrBackingController.rebuildROMFromBacking = originals.rebuildROMFromBacking
  end)

  it("returns false when no ROM bytes are loaded", function()
    local state = makeChrRomState()
    state.romRaw = ""

    local app = makeApp(state)
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeFalsy()
    expect(app.statusText).toBe("No ROM loaded to save.")
  end)

  it("returns false when rom_raw rebuild fails before save stages run", function()
    local header = string.rep("\170", 16)
    local state = {
      romRaw = header .. string.rep("\0", 32),
      romOriginalPath = "/tmp/fake_rom.nes",
      chrBanksBytes = {},
    }
    ChrBackingController.configureFromParsedINES(state, { chr = {} })

    ChrBackingController.rebuildROMFromBacking = function()
      return nil, "missing banks"
    end

    local stageCalls = { nametable = 0, final = 0 }
    NametableTilesController.writeBackToROM = function()
      stageCalls.nametable = stageCalls.nametable + 1
      return "should-not-run", nil
    end
    RomSave.saveRawROM = function()
      stageCalls.final = stageCalls.final + 1
      return true, "/tmp/out.nes"
    end

    local app = makeApp(state)
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeFalsy()
    expect(app.statusText).toBe("No ROM loaded to save: missing banks")
    expect(stageCalls.nametable).toBe(0)
    expect(stageCalls.final).toBe(0)
  end)

  it("aborts save on nametable write-back failure without running later stages", function()
    local state = makeChrRomState()
    local order = {}

    NametableTilesController.writeBackToROM = function(win, layer, rom)
      order[#order + 1] = "nametable:" .. tostring(win.title)
      return nil, "bad nametable bytes"
    end
    SpriteController.applyDisplacementsToROMForWindows = function()
      order[#order + 1] = "sprite"
      return "sprite-rom", nil
    end
    chr.writeByteToAddress = function()
      order[#order + 1] = "palette"
      return "palette-rom"
    end
    RomSave.saveEditedROM = function()
      order[#order + 1] = "final"
      return true, "/tmp/out.nes"
    end

    local app = makeApp(state, {
      ppuFrames = { ppuFrameWithNametable("Frame A") },
      allWindows = { ppuFrameWithNametable("Frame A") },
    })
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeFalsy()
    expect(app.statusText).toBe("Nametable save error (Frame A): bad nametable bytes")
    expect(order).toEqual({ "nametable:Frame A" })
    expect(state.romRaw:sub(1, 16)).toBe(string.rep("\0", 16))
  end)

  it("chains nametable write-back across multiple ppu_frame windows", function()
    local state = makeChrRomState()
    local baseRom = state.romRaw
    local order = {}

    NametableTilesController.writeBackToROM = function(win, layer, rom)
      order[#order + 1] = win.title
      return rom .. ("+" .. win.title), nil
    end
    RomSave.saveEditedROM = function(_, romBytes)
      expect(romBytes).toBe(state.romRaw .. "+Frame A+Frame B")
      return true, "/tmp/out.nes"
    end

    local app = makeApp(state, {
      ppuFrames = {
        ppuFrameWithNametable("Frame A"),
        ppuFrameWithNametable("Frame B"),
      },
      allWindows = {
        ppuFrameWithNametable("Frame A"),
        ppuFrameWithNametable("Frame B"),
      },
    })
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeTruthy()
    expect(order).toEqual({ "Frame A", "Frame B" })
    expect(state.romRaw).toBe(baseRom .. "+Frame A+Frame B")
  end)

  it("skips ppu_frame windows without a nametable tile layer", function()
    local state = makeChrRomState()
    local writeCount = 0

    NametableTilesController.writeBackToROM = function()
      writeCount = writeCount + 1
      return "updated", nil
    end
    RomSave.saveEditedROM = function(_, romBytes)
      expect(romBytes).toBe(state.romRaw)
      return true, "/tmp/out.nes"
    end

    local app = makeApp(state, {
      ppuFrames = {
        {
          kind = "ppu_frame",
          title = "No NT",
          layers = { { kind = "tile" } },
        },
      },
    })
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeTruthy()
    expect(writeCount).toBe(0)
  end)

  it("applies sprite displacements before palette and final ROM write", function()
    local state = makeChrRomState()
    local order = {}
    local baseRom = state.romRaw

    NametableTilesController.writeBackToROM = function(_, _, rom)
      order[#order + 1] = "nametable"
      return rom .. "+nt", nil
    end
    SpriteController.applyDisplacementsToROMForWindows = function(windows, rom)
      order[#order + 1] = "sprite"
      expect(windows).toBeTruthy()
      expect(rom).toBe(baseRom .. "+nt")
      return rom .. "+spr", nil
    end
    chr.writeByteToAddress = function(rom)
      order[#order + 1] = "palette"
      return rom .. "+pal"
    end
    RomSave.saveEditedROM = function(_, romBytes, meta, chrBanks)
      order[#order + 1] = "final"
      expect(romBytes).toBe(baseRom .. "+nt+spr+pal")
      expect(meta).toBe(state.meta)
      expect(chrBanks).toBe(state.chrBanksBytes)
      return true, "/tmp/out.nes"
    end

    local app = makeApp(state, {
      ppuFrames = { ppuFrameWithNametable("Frame A") },
      romPalettes = { makeRomPaletteWindow("Palette", 0x10, "FF") },
      allWindows = { ppuFrameWithNametable("Frame A") },
    })
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeTruthy()
    expect(order).toEqual({ "nametable", "sprite", "palette", "final" })
    expect(state.romRaw).toBe(baseRom .. "+nt+spr+pal")
  end)

  it("continues save when sprite displacement reports an error without updated ROM", function()
    local state = makeChrRomState()
    local baseRom = state.romRaw

    NametableTilesController.writeBackToROM = function(_, _, rom)
      return rom, nil
    end
    SpriteController.applyDisplacementsToROMForWindows = function()
      return nil, "sprite patch failed"
    end
    RomSave.saveEditedROM = function(_, romBytes)
      expect(romBytes).toBe(baseRom)
      return true, "/tmp/out.nes"
    end

    local app = makeApp(state, {
      ppuFrames = { ppuFrameWithNametable("Frame A") },
      allWindows = { ppuFrameWithNametable("Frame A") },
    })
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeTruthy()
    expect(app.statusText).toBe("Saved ROM & edits: /tmp/out.nes")
    expect(state.romRaw).toBe(baseRom)
  end)

  it("writes palette colors from all ROM palette windows into the ROM before final save", function()
    local state = makeChrRomState()
    local baseRom = state.romRaw
    local writes = {}

    NametableTilesController.writeBackToROM = function(_, _, rom)
      return rom, nil
    end
    SpriteController.applyDisplacementsToROMForWindows = function(_, rom)
      return rom, nil
    end
    chr.writeByteToAddress = function(rom, addr, value)
      writes[#writes + 1] = { addr = addr, value = value }
      return rom .. string.char(value)
    end
    RomSave.saveEditedROM = function(_, romBytes)
      expect(#writes).toBe(2)
      expect(writes[1]).toEqual({ addr = 0x20, value = 0x0F })
      expect(writes[2]).toEqual({ addr = 0x21, value = 0x30 })
      expect(romBytes).toBe(baseRom .. string.char(0x0F) .. string.char(0x30))
      return true, "/tmp/out.nes"
    end

    local app = makeApp(state, {
      romPalettes = {
        makeRomPaletteWindow("Palette A", 0x20, "0F"),
        makeRomPaletteWindow("Palette B", 0x21, "30"),
      },
    })
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeTruthy()
    expect(state.romRaw).toBe(baseRom .. string.char(0x0F) .. string.char(0x30))
  end)

  it("uses saveEditedROM for chr_rom backing mode", function()
    local state = makeChrRomState()
    local calls = { raw = 0, edited = 0 }

    RomSave.saveRawROM = function()
      calls.raw = calls.raw + 1
      return true, "raw-path"
    end
    RomSave.saveEditedROM = function(path, romBytes, meta, chrBanks)
      calls.edited = calls.edited + 1
      expect(path).toBe("/tmp/test.nes")
      expect(romBytes).toBe(state.romRaw)
      expect(meta).toBe(state.meta)
      expect(chrBanks).toBe(state.chrBanksBytes)
      return true, "/tmp/edited.nes"
    end

    local app = makeApp(state)
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeTruthy()
    expect(calls.raw).toBe(0)
    expect(calls.edited).toBe(1)
    expect(app.statusText).toBe("Saved ROM & edits: /tmp/edited.nes")
    expect(state.romRaw).toBe(state.romRaw)
  end)

  it("uses saveRawROM for rom_raw backing mode and rebuilds ROM from pseudo banks first", function()
    local header = string.rep("\170", 16)
    local body = string.rep("\0", 32)
    local state = {
      romRaw = header .. body,
      romOriginalPath = "/tmp/fake_rom.nes",
      chrBanksBytes = {},
    }
    ChrBackingController.configureFromParsedINES(state, { chr = {} })
    state.chrBanksBytes[1][1] = 0x44

    local calls = { raw = 0, edited = 0 }
    RomSave.saveRawROM = function(path, romRaw)
      calls.raw = calls.raw + 1
      expect(path).toBe("/tmp/fake_rom.nes")
      expect(string.byte(romRaw, 17)).toBe(0x44)
      return true, "/tmp/raw_saved.nes"
    end
    RomSave.saveEditedROM = function()
      calls.edited = calls.edited + 1
      return true, "should-not-be-called"
    end

    local app = makeApp(state)
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeTruthy()
    expect(calls.raw).toBe(1)
    expect(calls.edited).toBe(0)
    expect(string.byte(state.romRaw, 17)).toBe(0x44)
    expect(app.statusText).toBe("Saved ROM & edits: /tmp/raw_saved.nes")
  end)

  it("returns false and preserves romRaw when final ROM write fails", function()
    local state = makeChrRomState()
    local originalRom = state.romRaw

    NametableTilesController.writeBackToROM = function(_, _, rom)
      return rom, nil
    end
    SpriteController.applyDisplacementsToROMForWindows = function(_, rom)
      return rom, nil
    end
    RomSave.saveEditedROM = function()
      return false, "disk full"
    end

    local app = makeApp(state)
    local ok = SaveController.saveEdited(app)

    expect(ok).toBeFalsy()
    expect(app.statusText:find("Save failed:", 1, true)).toBeTruthy()
    expect(app.statusText:find("disk full", 1, true)).toBeTruthy()
    expect(state.romRaw).toBe(originalRom)
  end)
end)
