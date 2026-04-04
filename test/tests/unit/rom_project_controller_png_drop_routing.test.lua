local RomProjectController = require("controllers.rom.rom_project_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local ImageImportController = require("controllers.rom.image_import_controller")
local NametableUnscrambleController = require("controllers.ppu.nametable_unscramble_controller")

describe("rom_project_controller.lua - PNG drop routing", function()
  local originalGetScaledMouse
  local originalHandleSpritePngDrop
  local originalGetSelectedSpriteIndicesInOrder
  local originalImportImageToCHRWindow
  local originalUnscrambleFromPNG

  local calls

  local function makeFile(name)
    return {
      getFilename = function() return name or "test.png" end,
    }
  end

  local function makeWM(focusedWin, winUnderMouse)
    return {
      _focus = focusedWin,
      getFocus = function(self) return self._focus end,
      setFocus = function(self, win) self._focus = win end,
      windowAt = function() return winUnderMouse end,
    }
  end

  local function makeApp(focusedWin, winUnderMouse)
    local wm = makeWM(focusedWin, winUnderMouse)
    return {
      wm = wm,
      appEditState = {
        tilesPool = {},
        romRaw = "rom-bytes",
        romSha1 = "abc123",
        romOriginalPath = "/tmp/test.nes",
        currentBank = 1,
      },
      edits = { banks = {} },
      winBank = nil,
      setStatus = function(self, text)
        calls.status[#calls.status + 1] = { app = self, text = text }
        self.statusText = text
      end,
    }
  end

  local function spriteLayer(opts)
    opts = opts or {}
    return {
      kind = "sprite",
      items = opts.items or {
        { removed = false },
      },
      selectedSpriteIndex = opts.selectedSpriteIndex,
      _selectedOrder = opts.selectedOrder or {},
    }
  end

  local function makeWin(kind, id, layers)
    return {
      kind = kind,
      _id = id or kind,
      title = id or kind,
      layers = layers,
      activeLayer = 1,
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0 end,
      orderMode = "normal",
    }
  end

  beforeEach(function()
    calls = {
      sprite = {},
      chr = {},
      ppu = {},
      status = {},
    }

    originalGetScaledMouse = ResolutionController.getScaledMouse
    originalHandleSpritePngDrop = SpriteController.handleSpritePngDrop
    originalGetSelectedSpriteIndicesInOrder = SpriteController.getSelectedSpriteIndicesInOrder
    originalImportImageToCHRWindow = ImageImportController.importImageToCHRWindow
    originalUnscrambleFromPNG = NametableUnscrambleController.unscrambleFromPNG

    ResolutionController.getScaledMouse = function()
      return { x = 10, y = 10 }
    end

    SpriteController.getSelectedSpriteIndicesInOrder = function(layer)
      return layer._selectedOrder or {}
    end

    SpriteController.handleSpritePngDrop = function(app, file, win)
      calls.sprite[#calls.sprite + 1] = { app = app, file = file, win = win }
      return true
    end

    ImageImportController.importImageToCHRWindow = function(file, win, col, row, appEditState, edits)
      calls.chr[#calls.chr + 1] = {
        file = file, win = win, col = col, row = row,
        appEditState = appEditState, edits = edits,
      }
      return true, "ok"
    end

    NametableUnscrambleController.unscrambleFromPNG = function(win, file, tilesPool, threshold, app)
      calls.ppu[#calls.ppu + 1] = { win = win, file = file, tilesPool = tilesPool, threshold = threshold, app = app }
      return true, "ok"
    end

  end)

  afterEach(function()
    ResolutionController.getScaledMouse = originalGetScaledMouse
    SpriteController.handleSpritePngDrop = originalHandleSpritePngDrop
    SpriteController.getSelectedSpriteIndicesInOrder = originalGetSelectedSpriteIndicesInOrder
    ImageImportController.importImageToCHRWindow = originalImportImageToCHRWindow
    NametableUnscrambleController.unscrambleFromPNG = originalUnscrambleFromPNG
  end)

  it("routes PNG to sprite importer for sprite-layer windows across static/animation/oam kinds", function()
    local cases = {
      { kind = "static_art" },
      { kind = "animation" },
      { kind = "oam_animation" },
    }

    for _, case in ipairs(cases) do
      calls.sprite = {}
      calls.chr = {}
      calls.ppu = {}

      local win = makeWin(case.kind, case.kind .. "_win", { spriteLayer() })
      local app = makeApp(win, win)

      RomProjectController.handleFileDropped(app, makeFile("sheet.png"))

      expect(#calls.sprite).toBe(1)
      expect(calls.sprite[1].win).toBe(win)
      expect(#calls.chr).toBe(0)
      expect(#calls.ppu).toBe(0)
    end
  end)

  it("prefers focused sprite window with selection over CHR target under mouse", function()
    local focusedSpriteWin = makeWin("animation", "anim", {
      spriteLayer({ selectedOrder = { 1 }, selectedSpriteIndex = 1 }),
    })
    local chrWin = makeWin("chr", "bank", {})
    local app = makeApp(focusedSpriteWin, chrWin)

    RomProjectController.handleFileDropped(app, makeFile("sheet.png"))

    expect(#calls.sprite).toBe(1)
    expect(calls.sprite[1].win).toBe(focusedSpriteWin)
    expect(#calls.chr).toBe(0)
    expect(#calls.ppu).toBe(0)
  end)

  it("routes PNG to PPU unscramble for ppu_frame when no sprite target is available", function()
    local ppuWin = makeWin("ppu_frame", "ppu", {
      { kind = "tile" },
    })
    local app = makeApp(ppuWin, ppuWin)

    RomProjectController.handleFileDropped(app, makeFile("nt.png"))

    expect(#calls.ppu).toBe(1)
    expect(calls.ppu[1].win).toBe(ppuWin)
    expect(#calls.sprite).toBe(0)
    expect(#calls.chr).toBe(0)
  end)

  it("routes PNG to PPU unscramble for ppu_frame when active layer is tile even if sprite overlay exists", function()
    local ppuWin = makeWin("ppu_frame", "ppu", {
      { kind = "tile" },
      spriteLayer(),
    })
    ppuWin.activeLayer = 1
    ppuWin.getActiveLayerIndex = function() return ppuWin.activeLayer end
    local app = makeApp(ppuWin, ppuWin)

    RomProjectController.handleFileDropped(app, makeFile("nt.png"))

    expect(#calls.ppu).toBe(1)
    expect(calls.ppu[1].win).toBe(ppuWin)
    expect(#calls.sprite).toBe(0)
    expect(#calls.chr).toBe(0)
  end)

  it("uses the window under mouse for PPU unscramble even when focus is on another window", function()
    local ppuWin = makeWin("ppu_frame", "ppu_under_mouse", {
      { kind = "tile" },
    })
    local focusedChrWin = makeWin("chr", "focused_chr", {})
    local app = makeApp(focusedChrWin, ppuWin)

    RomProjectController.handleFileDropped(app, makeFile("nt.png"))

    expect(#calls.ppu).toBe(1)
    expect(calls.ppu[1].win).toBe(ppuWin)
    expect(#calls.sprite).toBe(0)
    expect(#calls.chr).toBe(0)
  end)

  it("routes PNG to sprite importer for ppu_frame when active layer is sprite", function()
    local ppuWin = makeWin("ppu_frame", "ppu", {
      { kind = "tile" },
      spriteLayer(),
    })
    ppuWin.activeLayer = 2
    ppuWin.getActiveLayerIndex = function() return ppuWin.activeLayer end
    local app = makeApp(ppuWin, ppuWin)

    RomProjectController.handleFileDropped(app, makeFile("sheet.png"))

    expect(#calls.sprite).toBe(1)
    expect(calls.sprite[1].win).toBe(ppuWin)
    expect(#calls.ppu).toBe(0)
    expect(#calls.chr).toBe(0)
  end)

  it("routes PNG to CHR import for CHR window when no sprite target is available", function()
    local chrWin = makeWin("chr", "bank", {})
    chrWin.getSelected = function() return 3, 4 end
    local app = makeApp(chrWin, chrWin)

    RomProjectController.handleFileDropped(app, makeFile("tiles.png"))

    expect(#calls.chr).toBe(1)
    expect(calls.chr[1].win).toBe(chrWin)
    expect(calls.chr[1].col).toBe(3)
    expect(calls.chr[1].row).toBe(4)
    expect(#calls.sprite).toBe(0)
    expect(#calls.ppu).toBe(0)
  end)

  it("shows status when PNG drop has no compatible target window", function()
    local unsupported = makeWin("palette", "palette01", {})
    local app = makeApp(unsupported, unsupported)

    RomProjectController.handleFileDropped(app, makeFile("x.png"))

    expect(#calls.sprite).toBe(0)
    expect(#calls.chr).toBe(0)
    expect(#calls.ppu).toBe(0)
    expect(app.statusText).toBe("Please select a CHR bank window or PPU frame window")
  end)

  it("blocks PNG import when no ROM is loaded", function()
    local chrWin = makeWin("chr", "bank", {})
    local app = makeApp(chrWin, chrWin)
    app.appEditState.romRaw = nil
    app.appEditState.romSha1 = nil
    app.appEditState.romOriginalPath = nil

    RomProjectController.handleFileDropped(app, makeFile("tiles.png"))

    expect(#calls.sprite).toBe(0)
    expect(#calls.chr).toBe(0)
    expect(#calls.ppu).toBe(0)
    expect(app.statusText).toBe("Open a ROM before importing PNGs.")
  end)
end)
