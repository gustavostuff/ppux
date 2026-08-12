local Badge = require("controllers.window.window_link_badge_controller")
local WM = require("controllers.window.window_controller")

describe("window_link_badge_controller.lua", function()
  it("treats palette and pattern slot pairs as compatible only across source/dest", function()
    expect(Badge.areSlotsCompatible("palette_source", "layout_palette")).toBe(true)
    expect(Badge.areSlotsCompatible("layout_palette", "palette_source")).toBe(true)
    expect(Badge.areSlotsCompatible("palette_source", "palette_source")).toBe(false)
    expect(Badge.areSlotsCompatible("pattern_source", "ppu_pattern_bg")).toBe(true)
    expect(Badge.areSlotsCompatible("pattern_source", "ppu_palette")).toBe(false)
    expect(Badge.areSlotsCompatible("ppu_pattern_bg", "ppu_pattern_sprite")).toBe(false)
  end)

  it("rejects illegal window pairs for canLinkWindows", function()
    local wm = WM.new()
    local romA = wm:createRomPaletteWindow({ title = "A" })
    local romB = wm:createRomPaletteWindow({ title = "B" })
    local pt = wm:createPatternTableWindow({ title = "PT" })
    local art = wm:createTileWindow({ title = "Art" })

    expect(Badge.canLinkWindows(romA, "palette_source", romB, "palette_source")).toBe(false)
    expect(Badge.canLinkWindows(romA, "palette_source", pt, "pattern_source")).toBe(false)
    expect(Badge.canLinkWindows(romA, "palette_source", art, "layout_palette")).toBe(true)
    expect(Badge.canLinkWindows(pt, "pattern_source", art, "layout_palette")).toBe(false)
  end)

  it("runs after-link refresh when applying a pattern-table badge link", function()
    local wm = WM.new()
    local pt = wm:createPatternTableWindow({ title = "PT" })
    local ppu = wm:createPPUFrameWindow({ title = "PPU", romRaw = string.rep("\0", 256) })
    local afterCalls = {}
    local undoEvents = {}
    local app = {
      wm = wm,
      setStatus = function() end,
      _afterPatternTableLinkChange = function(_, contentWin, layerIndex)
        afterCalls[#afterCalls + 1] = { win = contentWin, layerIndex = layerIndex }
      end,
      undoRedo = {
        addPatternTableLinkEvent = function(_, event)
          undoEvents[#undoEvents + 1] = event
          return true
        end,
      },
    }

    expect(Badge.applyLink(app, pt, "pattern_source", ppu, "ppu_pattern_bg")).toBe(true)
    expect(#afterCalls).toBe(1)
    expect(afterCalls[1].win).toBe(ppu)
    expect(type(afterCalls[1].layerIndex)).toBe("number")
    expect(#undoEvents).toBe(1)
    expect(undoEvents[1].type).toBe("pattern_table_link")
    expect(#undoEvents[1].actions).toBe(1)
    expect(undoEvents[1].actions[1].afterLinkedId).toBe(pt._id)
  end)
end)
