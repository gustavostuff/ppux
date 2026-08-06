local RomProjectController = require("controllers.rom.rom_project_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local SpriteController = require("controllers.sprite.sprite_controller")

describe("rom_project_controller.lua - PNG drop routing", function()
  local originalGetScaledMouse
  local originalHandleSpritePngDrop
  local originalGetSelectedSpriteIndicesInOrder

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
      getWindows = function()
        local list = {}
        if focusedWin then list[#list + 1] = focusedWin end
        if winUnderMouse and winUnderMouse ~= focusedWin then
          list[#list + 1] = winUnderMouse
        end
        return list
      end,
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
      status = {},
    }

    originalGetScaledMouse = ResolutionController.getScaledMouse
    originalHandleSpritePngDrop = SpriteController.handleSpritePngDrop
    originalGetSelectedSpriteIndicesInOrder = SpriteController.getSelectedSpriteIndicesInOrder

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
  end)

  afterEach(function()
    ResolutionController.getScaledMouse = originalGetScaledMouse
    SpriteController.handleSpritePngDrop = originalHandleSpritePngDrop
    SpriteController.getSelectedSpriteIndicesInOrder = originalGetSelectedSpriteIndicesInOrder
  end)

  it("routes PNG to sprite importer for OAM Animation windows", function()
    local win = makeWin("oam_animation", "oam_win", { spriteLayer() })
    local app = makeApp(win, win)

    RomProjectController.handleFileDropped(app, makeFile("sheet.png"))

    expect(#calls.sprite).toBe(1)
    expect(calls.sprite[1].win).toBe(win)
  end)

  it("routes PNG to sprite importer for PPU Frame when sprite layer is active", function()
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
  end)

  it("does not route PNG to PPU Frame when tile layer is active", function()
    local ppuWin = makeWin("ppu_frame", "ppu", {
      { kind = "tile" },
      spriteLayer(),
    })
    ppuWin.activeLayer = 1
    ppuWin.getActiveLayerIndex = function() return ppuWin.activeLayer end
    local app = makeApp(ppuWin, ppuWin)

    RomProjectController.handleFileDropped(app, makeFile("sheet.png"))

    expect(#calls.sprite).toBe(0)
    expect(app.statusText).toBe("Drop a PNG on a Sketch canvas, OAM Animation, or PPU Frame sprite layer")
  end)

  it("does not route PNG to Static Art or Animation sprite windows", function()
    local cases = {
      { kind = "static_art" },
      { kind = "animation" },
    }

    for _, case in ipairs(cases) do
      calls.sprite = {}
      local win = makeWin(case.kind, case.kind .. "_win", { spriteLayer() })
      local app = makeApp(win, win)

      RomProjectController.handleFileDropped(app, makeFile("sheet.png"))

      expect(#calls.sprite).toBe(0)
      expect(app.statusText).toBe("Drop a PNG on a Sketch canvas, OAM Animation, or PPU Frame sprite layer")
    end
  end)

  it("uses focused OAM window as drop target when pointer is not over any window", function()
    local oamWin = makeWin("oam_animation", "oam", {
      spriteLayer({ selectedOrder = { 1 }, selectedSpriteIndex = 1 }),
    })
    local app = makeApp(oamWin, nil)

    RomProjectController.handleFileDropped(app, makeFile("sheet.png"))

    expect(#calls.sprite).toBe(1)
    expect(calls.sprite[1].win).toBe(oamWin)
  end)

  it("uses the OAM window under mouse even when focus is elsewhere", function()
    local focusedChrWin = makeWin("chr", "focused_chr", {})
    local oamWin = makeWin("oam_animation", "oam_under_mouse", { spriteLayer() })
    local app = makeApp(focusedChrWin, oamWin)

    RomProjectController.handleFileDropped(app, makeFile("sheet.png"))

    expect(#calls.sprite).toBe(1)
    expect(calls.sprite[1].win).toBe(oamWin)
  end)

  it("shows status when PNG drop has no compatible target window", function()
    local unsupported = makeWin("palette", "palette01", {})
    local app = makeApp(unsupported, unsupported)

    RomProjectController.handleFileDropped(app, makeFile("x.png"))

    expect(#calls.sprite).toBe(0)
    expect(app.statusText).toBe("Drop a PNG on a Sketch canvas, OAM Animation, or PPU Frame sprite layer")
  end)

  it("routes PNG to Sketch canvas import without requiring a loaded ROM", function()
    local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
    local originalImport = SketchCanvasPackController.importPngToSketchCanvas
    local sketchCalls = {}
    SketchCanvasPackController.importPngToSketchCanvas = function(win, file, wm, opts)
      sketchCalls[#sketchCalls + 1] = { win = win, file = file, wm = wm, opts = opts }
      return true, { uniqueCount = 2, appliedToPatternTable = true }
    end

    local sketchWin = makeWin("sketch_canvas", "sketch01", {
      { kind = "canvas" },
    })
    local app = makeApp(sketchWin, sketchWin)
    app.appEditState.romRaw = nil
    app.appEditState.romSha1 = nil
    app.appEditState.romOriginalPath = nil

    RomProjectController.handleFileDropped(app, makeFile("bg.png"))

    SketchCanvasPackController.importPngToSketchCanvas = originalImport

    expect(#sketchCalls).toBe(1)
    expect(sketchCalls[1].win).toBe(sketchWin)
    expect(#calls.sprite).toBe(0)
    expect(type(app.statusText)).toBe("string")
    expect(app.statusText:find("Sketch PNG", 1, true) ~= nil).toBe(true)
  end)

  it("opens confirm modal when Sketch PNG import needs replace confirmation", function()
    local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
    local originalImport = SketchCanvasPackController.importPngToSketchCanvas
    local pending = { needsConfirm = true, pack = { uniqueCount = 1 } }
    local importCalls = 0
    SketchCanvasPackController.importPngToSketchCanvas = function(_, _, _, opts)
      importCalls = importCalls + 1
      opts = opts or {}
      if opts.confirmed then
        return true, { uniqueCount = 1, appliedToPatternTable = true }
      end
      return false, SketchCanvasPackController.PNG_IMPORT_NEEDS_CONFIRM, pending
    end

    local sketchWin = makeWin("sketch_canvas", "sketch01", {
      { kind = "canvas" },
    })
    local app = makeApp(sketchWin, sketchWin)
    local shown = nil
    app.confirmModal = {
      show = function(_, opts)
        shown = opts
      end,
    }

    RomProjectController.handleFileDropped(app, makeFile("bg.png"))

    expect(importCalls).toBe(1)
    expect(shown).toBeTruthy()
    expect(shown.title:find("Replace", 1, true) ~= nil).toBe(true)
    shown.onYes()
    expect(importCalls).toBe(2)
    expect(app.statusText:find("imported", 1, true) ~= nil).toBe(true)

    SketchCanvasPackController.importPngToSketchCanvas = originalImport
  end)

  it("blocks non-sketch PNG import when no ROM is loaded", function()
    local oamWin = makeWin("oam_animation", "oam", { spriteLayer() })
    local app = makeApp(oamWin, oamWin)
    app.appEditState.romRaw = nil
    app.appEditState.romSha1 = nil
    app.appEditState.romOriginalPath = nil

    RomProjectController.handleFileDropped(app, makeFile("sheet.png"))

    expect(#calls.sprite).toBe(0)
    expect(app.statusText).toBe("Open a ROM before importing PNGs.")
  end)
end)
