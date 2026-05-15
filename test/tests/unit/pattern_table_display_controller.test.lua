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
