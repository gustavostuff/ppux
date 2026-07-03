local WM = require("controllers.window.window_controller")
local PatternLayerGate = require("controllers.window.pattern_layer_gate")

local FULL_PATTERN_TABLE = {
  ranges = { { bank = 1, from = 0, to = 255 } },
}

describe("oam_animation_window.lua", function()
  it("inherits pattern table link when adding a new sprite layer", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({
      animated = true,
      oamBacked = true,
      numFrames = 1,
      spriteMode = "8x8",
      cols = 8,
      rows = 8,
    })

    win.layers[1].patternTable = FULL_PATTERN_TABLE
    win.layers[1].linkedPatternTableWindowId = "pt_main"

    local inserted = win:addLayerAfterActive({ name = "Frame 2" })
    expect(inserted).toBe(2)

    local newLayer = win.layers[2]
    expect(newLayer.patternTable).toBe(FULL_PATTERN_TABLE)
    expect(newLayer.linkedPatternTableWindowId).toBe("pt_main")

    local locked, reason = PatternLayerGate.isLayerInteractionLocked(win, 2)
    expect(locked).toBe(false)
    expect(reason).toBeNil()
  end)
end)
