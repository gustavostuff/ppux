local PTDisplay = require("controllers.game_art.pattern_table_display_controller")
local PatternTableMapping = require("utils.pattern_table_mapping")

describe("pattern_table_display_controller.lua", function()
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
end)
