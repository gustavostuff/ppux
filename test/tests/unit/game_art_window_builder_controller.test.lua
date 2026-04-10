local Builder = require("controllers.game_art.window_builder_controller")
local Factory = require("controllers.game_art.window_factory_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local PPUFrameWindow = require("user_interface.windows_system.ppu_frame_window")

describe("game_art_window_builder_controller.lua", function()
  local originals

  beforeEach(function()
    originals = {
      createPaletteWindow = Factory.createPaletteWindow,
      createRomPaletteWindow = Factory.createRomPaletteWindow,
      createChrBankWindow = Factory.createChrBankWindow,
      createStaticArtWindow = Factory.createStaticArtWindow,
      createPPUFrameWindow = Factory.createPPUFrameWindow,
      createAnimationWindow = Factory.createAnimationWindow,
      createOamAnimationWindow = Factory.createOamAnimationWindow,
      finalizeWindow = Factory.finalizeWindow,
      countSerializedTileSwaps = NametableTilesController.countSerializedTileSwaps,
      hydrateWindowNametable = NametableTilesController.hydrateWindowNametable,
      ppuFrameWindowNew = PPUFrameWindow.new,
    }
  end)

  afterEach(function()
    Factory.createPaletteWindow = originals.createPaletteWindow
    Factory.createRomPaletteWindow = originals.createRomPaletteWindow
    Factory.createChrBankWindow = originals.createChrBankWindow
    Factory.createStaticArtWindow = originals.createStaticArtWindow
    Factory.createPPUFrameWindow = originals.createPPUFrameWindow
    Factory.createAnimationWindow = originals.createAnimationWindow
    Factory.createOamAnimationWindow = originals.createOamAnimationWindow
    Factory.finalizeWindow = originals.finalizeWindow
    NametableTilesController.hydrateWindowNametable = originals.hydrateWindowNametable
    PPUFrameWindow.new = originals.ppuFrameWindowNew
  end)

  local function makeWM()
    local wm = { _windows = {}, focused = nil }
    function wm:getWindows() return self._windows end
    function wm:setFocus(win) self.focused = win end
    return wm
  end

  it("activates the last palette window when none is active and restores focus by focusedWindowId", function()
    local wm = makeWM()
    local syncCalls = 0

    Factory.createPaletteWindow = function(w)
      return {
        _id = w.id,
        kind = "palette",
        isPalette = true,
        activePalette = false,
        syncToGlobalPalette = function(self)
          syncCalls = syncCalls + 1
          self._synced = true
        end,
      }
    end

    Factory.finalizeWindow = function(win, w, windowsById, wmArg)
      if not win then return end
      windowsById[w.id] = win
      wmArg._windows[#wmArg._windows + 1] = win
    end

    local layout = {
      focusedWindowId = "palette_2",
      windows = {
        { id = "palette_1", kind = "palette" },
        { id = "palette_2", kind = "palette" },
      }
    }

    local result = Builder.buildWindowsFromLayout(layout, {
      wm = wm,
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
    })

    expect(result).toBeTruthy()
    expect(wm._windows[1].activePalette).toBeFalsy()
    expect(wm._windows[2].activePalette).toBeTruthy()
    expect(syncCalls).toBe(1)
    expect(wm.focused).toBe(wm._windows[2])
    expect(result.focusedWindow).toBe(wm._windows[2])
  end)

  it("upgrades chr windows to ROM-window mode when chrBackingMode is rom_raw", function()
    local wm = makeWM()
    local sawRomWindowFlag = false

    Factory.createChrBankWindow = function(w)
      sawRomWindowFlag = (w.isRomWindow == true)
      return {
        _id = w.id,
        kind = "chr",
        currentBank = w.currentBank or 1,
      }
    end

    Factory.finalizeWindow = function(win, w, windowsById, wmArg)
      if not win then return end
      windowsById[w.id] = win
      wmArg._windows[#wmArg._windows + 1] = win
    end

    local layout = {
      windows = {
        { id = "bank", kind = "chr", currentBank = 7 },
      }
    }

    local result = Builder.buildWindowsFromLayout(layout, {
      wm = wm,
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      chrBackingMode = "rom_raw",
    })

    expect(sawRomWindowFlag).toBeTruthy()
    expect(layout.windows[1].isRomWindow).toBeTruthy()
    expect(result.bankWindow).toBeTruthy()
    expect(result.bankWindow.kind).toBe("chr")
    expect(result.currentBank).toBe(7)
    expect(layout.currentBank).toBe(7)
  end)

  it("passes the expected hydration options to PPU frame windows", function()
    local hydrateOpts = nil

    NametableTilesController.hydrateWindowNametable = function(win, layer, opts)
      hydrateOpts = opts
      return true
    end

    PPUFrameWindow.new = function(x, y, zoom, data)
      return {
        x = x,
        y = y,
        zoom = zoom,
        title = data and data.title or "PPU",
        cols = 32,
        rows = 30,
        layers = {
          {
            kind = "tile",
            items = {},
          },
        },
      }
    end

    local win = Factory.createPPUFrameWindow({
      x = 0,
      y = 0,
      zoom = 2,
      id = "ppu_01",
      title = "PPU Frame",
      nametableStartAddr = 100,
      nametableEndAddr = 199,
      layers = {
        {
          kind = "tile",
          nametableStartAddr = 100,
          nametableEndAddr = 199,
          patternTable = {
            ranges = {
              {
                bank = 2,
                page = 1,
                from = 0,
                to = 255,
              },
            },
          },
          tileSwaps = "32x30|-1:1;9:3;-1:956",
        },
      },
    }, {}, function() end, "rom")

    expect(win).toBeTruthy()
    expect(hydrateOpts).toBeTruthy()
    expect(hydrateOpts.romRaw).toBe("rom")
    expect(hydrateOpts.nametableStartAddr).toBe(100)
    expect(hydrateOpts.nametableEndAddr).toBe(199)
    expect(hydrateOpts.patternTable).toBeTruthy()
    expect(hydrateOpts.patternTable.ranges[1].bank).toBe(2)
    expect(hydrateOpts.patternTable.ranges[1].page).toBe(1)
    expect(hydrateOpts.tileSwaps).toBe("32x30|-1:1;9:3;-1:956")
    expect(hydrateOpts.preRegisteredWork).toBeNil()
    expect(hydrateOpts.loadingProgress).toBeNil()
  end)
end)
