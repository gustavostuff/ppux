local Badge = require("controllers.window.window_link_badge_controller")
local Visual = require("controllers.window.window_link_visual_controller")
local WM = require("controllers.window.window_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local colors = require("app_colors")

describe("window_link_badge_controller.lua", function()
  it("treats palette and pattern slot pairs as compatible across source/dest and same-side", function()
    expect(Badge.areSlotsCompatible("palette_source", "layout_palette")).toBe(true)
    expect(Badge.areSlotsCompatible("layout_palette", "palette_source")).toBe(true)
    expect(Badge.areSlotsCompatible("palette_source", "palette_source")).toBe(true)
    expect(Badge.areSlotsCompatible("layout_palette", "ppu_palette")).toBe(true)
    expect(Badge.areSlotsCompatible("pattern_source", "pattern_source")).toBe(true)
    expect(Badge.areSlotsCompatible("pattern_source", "ppu_pattern_bg")).toBe(true)
    expect(Badge.areSlotsCompatible("ppu_pattern_sprite", "oam_pattern")).toBe(true)
    expect(Badge.areSlotsCompatible("pattern_source", "ppu_palette")).toBe(false)
    expect(Badge.areSlotsCompatible("ppu_pattern_bg", "ppu_pattern_sprite")).toBe(false)
  end)

  it("rejects illegal window pairs for canLinkWindows", function()
    local wm = WM.new()
    local romA = wm:createRomPaletteWindow({ title = "A" })
    local romB = wm:createRomPaletteWindow({ title = "B" })
    local pt = wm:createPatternTableWindow({ title = "PT" })
    local art = wm:createTileWindow({ title = "Art" })
    local app = { wm = wm }

    expect(Badge.canLinkWindows(romA, "palette_source", romB, "palette_source", app)).toBe(false)
    expect(Badge.canLinkWindows(romA, "palette_source", pt, "pattern_source", app)).toBe(false)
    expect(Badge.canLinkWindows(romA, "palette_source", art, "layout_palette", app)).toBe(true)
    expect(Badge.canLinkWindows(pt, "pattern_source", art, "layout_palette", app)).toBe(false)
  end)

  it("moves all palette consumers from one ROM palette source badge to another", function()
    local wm = WM.new()
    local romA = wm:createRomPaletteWindow({ title = "A" })
    local romB = wm:createRomPaletteWindow({ title = "B" })
    local art = wm:createTileWindow({ title = "Art" })
    local anim = wm:createTileWindow({ animated = true, numFrames = 2, title = "Anim" })
    assert(PaletteLinkController.linkLayerToPalette(art, 1, romA))
    assert(PaletteLinkController.linkLayerToPalette(anim, 1, romA))
    anim.activeLayer = 2
    assert(PaletteLinkController.linkLayerToPalette(anim, 2, romA))

    local app = { wm = wm, setStatus = function() end }
    local prevCtx = rawget(_G, "ctx")
    rawset(_G, "ctx", { app = app })

    expect(Badge.canLinkWindows(romA, "palette_source", romB, "palette_source", app)).toBe(true)
    expect(Badge.applyLink(app, romA, "palette_source", romB, "palette_source")).toBe(true)
    expect(art.layers[1].paletteData.winId).toBe(romB._id)
    expect(anim.layers[1].paletteData.winId).toBe(romB._id)
    expect(anim.layers[2].paletteData.winId).toBe(romB._id)
    expect(#PaletteLinkController.getLinkedTargetsForPalette(wm, romA)).toBe(0)
    expect(#PaletteLinkController.getLinkedTargetsForPalette(wm, romB)).toBe(3)

    rawset(_G, "ctx", prevCtx)
  end)

  it("moves a dest palette badge link onto another dest window", function()
    local wm = WM.new()
    local rom = wm:createRomPaletteWindow({ title = "ROM" })
    local artA = wm:createTileWindow({ title = "ArtA" })
    local artB = wm:createTileWindow({ title = "ArtB" })
    assert(PaletteLinkController.linkLayerToPalette(artA, 1, rom))

    local app = { wm = wm, setStatus = function() end }
    local prevCtx = rawget(_G, "ctx")
    rawset(_G, "ctx", { app = app })

    expect(Badge.canLinkWindows(artA, "layout_palette", artB, "layout_palette", app)).toBe(true)
    expect(Badge.applyLink(app, artA, "layout_palette", artB, "layout_palette")).toBe(true)
    expect(artB.layers[1].paletteData.winId).toBe(rom._id)
    local aId = artA.layers[1].paletteData and artA.layers[1].paletteData.winId
    expect(aId == nil or aId == "").toBe(true)

    rawset(_G, "ctx", prevCtx)
  end)

  it("moves all pattern-table consumers from one source badge to another", function()
    local wm = WM.new()
    local ptA = wm:createPatternTableWindow({ title = "PTA" })
    local ptB = wm:createPatternTableWindow({ title = "PTB" })
    local ppu = wm:createPPUFrameWindow({ title = "PPU", romRaw = string.rep("\0", 256) })
    ptA.layers[1].patternTable = { ranges = { { from = 0, to = 255, bank = 1, page = 1 } } }
    ptB.layers[1].patternTable = { ranges = { { from = 0, to = 255, bank = 1, page = 1 } } }
    assert(PatternTableDisplayController.linkContentLayerToPatternTableWindow(ppu, 1, ptA))

    local afterCalls = {}
    local app = {
      wm = wm,
      setStatus = function() end,
      _afterPatternTableLinkChange = function(_, contentWin, layerIndex)
        afterCalls[#afterCalls + 1] = { win = contentWin, layerIndex = layerIndex }
      end,
      undoRedo = {
        addPatternTableLinkEvent = function()
          return true
        end,
      },
    }

    expect(Badge.canLinkWindows(ptA, "pattern_source", ptB, "pattern_source", app)).toBe(true)
    expect(Badge.applyLink(app, ptA, "pattern_source", ptB, "pattern_source")).toBe(true)
    expect(ppu.layers[1].linkedPatternTableWindowId).toBe(ptB._id)
    expect(#PatternTableDisplayController.getLinkedConsumersForPatternTable(wm, ptA)).toBe(0)
    expect(#afterCalls >= 1).toBe(true)
  end)

  it("moves a dest pattern badge link onto another dest window", function()
    local wm = WM.new()
    local pt = wm:createPatternTableWindow({ title = "PT" })
    local ppuA = wm:createPPUFrameWindow({ title = "PPUA", romRaw = string.rep("\0", 256) })
    local ppuB = wm:createPPUFrameWindow({ title = "PPUB", romRaw = string.rep("\0", 256) })
    pt.layers[1].patternTable = { ranges = { { from = 0, to = 255, bank = 1, page = 1 } } }
    assert(PatternTableDisplayController.linkContentLayerToPatternTableWindow(ppuA, 1, pt))

    local app = {
      wm = wm,
      setStatus = function() end,
      _afterPatternTableLinkChange = function() end,
      undoRedo = {
        addPatternTableLinkEvent = function()
          return true
        end,
      },
    }

    expect(Badge.canLinkWindows(ppuA, "ppu_pattern_bg", ppuB, "ppu_pattern_bg", app)).toBe(true)
    expect(Badge.applyLink(app, ppuA, "ppu_pattern_bg", ppuB, "ppu_pattern_bg")).toBe(true)
    expect(ppuB.layers[1].linkedPatternTableWindowId).toBe(pt._id)
    expect(ppuA.layers[1].linkedPatternTableWindowId).toBeNil()
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

  it("uses slot role colors for drag preview (not legal/illegal green/red)", function()
    expect(Visual.semanticColorForSlot("ppu_pattern_bg")).toBe(colors.red)
    expect(Visual.semanticColorForSlot("ppu_pattern_sprite")).toBe(colors.green)
    expect(Visual.semanticColorForSlot("oam_pattern")).toBe(colors.green)
    expect(Visual.semanticColorForSlot("palette_source")).toBe(colors.blue)
    expect(Visual.semanticColorForSlot("layout_palette")).toBe(colors.blue)
    expect(Visual.semanticColorForSlot("pattern_source")).toBe(colors.brown)
    expect(Visual.dragPreviewColorForSlots("pattern_source", "ppu_pattern_bg")).toBe(colors.red)
    expect(Visual.dragPreviewColorForSlots("pattern_source", nil)).toBe(colors.brown)
  end)

  it("pulses unlinked badge hint alpha twice per second between 0 and 1", function()
    local function near(actual, expected)
      return math.abs((tonumber(actual) or 0) - expected) < 1e-6
    end
    expect(near(Visual.unlinkedBadgeDragPulseAlpha(0), 0)).toBe(true)
    expect(near(Visual.unlinkedBadgeDragPulseAlpha(0.25), 1)).toBe(true)
    expect(near(Visual.unlinkedBadgeDragPulseAlpha(0.5), 0)).toBe(true)
    expect(near(Visual.unlinkedBadgeDragPulseAlpha(0.75), 1)).toBe(true)
    expect(near(Visual.unlinkedBadgeDragPulseAlpha(1.0), 0)).toBe(true)
  end)
end)
