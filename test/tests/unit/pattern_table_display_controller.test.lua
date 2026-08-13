local PTDisplay = require("controllers.game_art.pattern_table_display_controller")
local PatternTableMapping = require("utils.pattern_table_mapping")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")
local WM = require("controllers.window.window_controller")

describe("pattern_table_display_controller.lua", function()
  it("getLinkedConsumersForPatternTable lists layers that reference the pattern table id", function()
    local ptWin = { _id = "pt_src", kind = "pattern_table", layers = { { kind = "tile", patternTable = { ranges = {} } } } }
    local ppuWin = {
      kind = "ppu_frame",
      layers = {
        { kind = "tile", linkedPatternTableWindowId = "pt_src", patternTable = { ranges = {} } },
        { kind = "sprite", linkedPatternTableWindowId = "other", patternTable = { ranges = {} } },
      },
    }
    local wm = {
      getWindows = function()
        return { ptWin, ppuWin }
      end,
    }
    local targets = PTDisplay.getLinkedConsumersForPatternTable(wm, ptWin)
    expect(#targets).toBe(1)
    expect(targets[1].win).toBe(ppuWin)
    expect(targets[1].layerIndex).toBe(1)
  end)

  local function patternTableIdentity256()
    return {
      ranges = {
        { from = 0, to = 255, bank = 1, page = 1 },
      },
    }
  end

  it("invalidateConsumersUsingPatternTable rewires OAM sprite layer patternTable when linked by window id", function()
    local shared = patternTableIdentity256()
    local stale = { ranges = {} }

    local ptWin = {
      _id = "pt_oam_link",
      kind = "pattern_table",
      layers = {
        {
          kind = "tile",
          patternTable = shared,
        },
      },
    }

    local spr = {
      kind = "sprite",
      linkedPatternTableWindowId = "pt_oam_link",
      patternTable = stale,
      items = {},
    }

    local oamWin = { kind = "oam_animation", layers = { spr } }
    local app = {
      wm = {
        getWindows = function()
          return { ptWin, oamWin }
        end,
      },
      appEditState = { romRaw = "", tilesPool = {} },
    }

    PTDisplay.invalidateConsumersUsingPatternTable(app, shared)

    expect(spr.patternTable).toBe(shared)
    expect(PatternTableMapping.validate(spr.patternTable)).toBe(true)
  end)

  it("invalidateConsumersUsingPatternTable rewires linked PPU nametable tile layer patternTable", function()
    local shared = patternTableIdentity256()
    local stale = { ranges = {} }

    local ptWin = {
      _id = "pt_nt_link",
      kind = "pattern_table",
      layers = {
        {
          kind = "tile",
          patternTable = shared,
        },
      },
    }

    local ntLayer = {
      kind = "tile",
      nametableStartAddr = 0x1000,
      nametableEndAddr = 0x10ff,
      linkedPatternTableWindowId = "pt_nt_link",
      patternTable = stale,
    }

    local ppuWin = {
      kind = "ppu_frame",
      nametableBytes = { 0, 1 },
      cols = 32,
      rows = 1,
      refreshNametableVisuals = function() end,
      layers = { ntLayer },
    }

    local app = {
      wm = {
        getWindows = function()
          return { ptWin, ppuWin }
        end,
      },
      appEditState = { romRaw = "", tilesPool = {} },
      _ensurePpuPatternTableReferenceLayer = function() end,
    }

    PTDisplay.invalidateConsumersUsingPatternTable(app, shared)

    expect(ntLayer.patternTable).toBe(shared)
    expect(PatternTableMapping.validate(ntLayer.patternTable)).toBe(true)
  end)

  it("unlink clears PPU sprite pattern map so CHR no longer resolves through linked ranges", function()
    local pt = patternTableIdentity256()
    local spriteLayer = {
      kind = "sprite",
      linkedPatternTableWindowId = "pt_win_a",
      patternTable = pt,
    }
    local win = {
      kind = "ppu_frame",
      layers = {
        { kind = "tile", patternTable = { ranges = {} } },
        spriteLayer,
      },
    }
    local ok = PTDisplay.unlinkContentLayerPatternTable(win, 2)
    expect(ok).toBe(true)
    expect(spriteLayer.linkedPatternTableWindowId).toBeNil()
    local valid = PatternTableMapping.validate(spriteLayer.patternTable)
    expect(valid).toBe(false)
    expect(#spriteLayer.patternTable.ranges).toBe(0)
  end)

  it("unlink keeps detached deepcopy for non-PPU sprite layers", function()
    local pt = patternTableIdentity256()
    local spriteLayer = {
      kind = "sprite",
      linkedPatternTableWindowId = "pt_win_a",
      patternTable = pt,
    }
    local win = {
      kind = "static_art",
      layers = { spriteLayer },
    }
    PTDisplay.unlinkContentLayerPatternTable(win, 1)
    expect(spriteLayer.linkedPatternTableWindowId).toBeNil()
    expect(PatternTableMapping.validate(spriteLayer.patternTable)).toBe(true)
    expect(spriteLayer.patternTable).toNotBe(pt)
  end)

  it("closing a linked pattern table stashes PPU consumer restore and undo restores the link", function()
    local wm = WM.new()
    local pt = wm:createPatternTableWindow({ title = "PT", x = 10, y = 10 })
    local ppu = wm:createPPUFrameWindow({ title = "PPU", x = 200, y = 10, romRaw = string.rep("\0", 256) })
    pt.layers[1].patternTable = patternTableIdentity256()
    assert(PTDisplay.linkContentLayerToPatternTableWindow(ppu, 1, pt))
    ppu.nametableBytes = { 16, 17, 18 }
    ppu.nametableAttrBytes = { 0x50, 0x00 }
    ppu._tileSwaps = { [1] = 99 }
    ppu.layers[1].tileSwaps = { { col = 0, row = 0, val = 99 } }
    ppu.layers[1].userDefinedAttrs = "50" .. string.rep("00", 63)
    expect(ppu.layers[1].linkedPatternTableWindowId).toBe(pt._id)

    local hydrateCalls = 0
    local prevCtx = rawget(_G, "ctx")
    rawset(_G, "ctx", {
      app = {
        wm = wm,
        _afterPatternTableLinkChange = function()
          hydrateCalls = hydrateCalls + 1
          ppu.nametableBytes = { 1, 2, 3 }
        end,
      },
    })

    local undo = UndoRedoController.new(10)
    local app = { wm = wm, undoRedo = undo }
    assert(wm:closeWindow(pt))
    expect(hydrateCalls).toBe(0)
    expect(ppu.layers[1].linkedPatternTableWindowId).toBeNil()
    expect(ppu.nametableBytes[1]).toBe(16)
    expect(type(pt._ptConsumerCloseUndoRestore)).toBe("table")
    expect(#pt._ptConsumerCloseUndoRestore).toBe(1)
    expect(pt._ptConsumerCloseUndoRestore[1].nametable).toBeTruthy()
    expect(pt._ptConsumerCloseUndoRestore[1].nametable.nametableBytes[1]).toBe(16)

    -- Simulate the old close-hydrate wipe; undo must restore bytes from the snapshot.
    ppu.nametableBytes = { 9, 9, 9 }
    ppu.nametableAttrBytes = { 0x00 }
    ppu._tileSwaps = {}
    ppu.layers[1].tileSwaps = nil
    ppu.layers[1].userDefinedAttrs = nil

    local restore = pt._ptConsumerCloseUndoRestore
    pt._ptConsumerCloseUndoRestore = nil
    undo:addWindowEvent({
      type = "window_close",
      win = pt,
      wm = wm,
      prevClosed = false,
      prevMinimized = false,
      prevFocused = true,
      ptConsumerRestore = restore,
    })

    assert(undo:undo(app))
    expect(pt._closed).toBe(false)
    expect(ppu.layers[1].linkedPatternTableWindowId).toBe(pt._id)
    expect(PatternTableMapping.validate(ppu.layers[1].patternTable)).toBe(true)
    expect(ppu.nametableBytes[1]).toBe(16)
    expect(ppu.nametableBytes[3]).toBe(18)
    expect(ppu.nametableAttrBytes[1]).toBe(0x50)
    expect(ppu._tileSwaps[1]).toBe(99)
    expect(ppu.layers[1].tileSwaps[1].val).toBe(99)
    expect(ppu.layers[1].userDefinedAttrs).toBe("50" .. string.rep("00", 63))

    assert(undo:redo(app))
    expect(pt._closed).toBe(true)
    expect(ppu.layers[1].linkedPatternTableWindowId).toBeNil()
    expect(hydrateCalls).toBe(0)

    rawset(_G, "ctx", prevCtx)
  end)
end)
