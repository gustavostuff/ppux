local PaletteLinkRender = require("controllers.palette.palette_link_render_controller")
local WM = require("controllers.window.window_controller")

describe("palette_link_render_controller.lua", function()
  it("buildPaletteLinkLookup maps active-layer ROM palette links in one pass", function()
    local wm = WM.new()
    local content = wm:createTileWindow({ title = "Art", x = 8, y = 8, numLayers = 2 })
    local romA = wm:createRomPaletteWindow({ title = "ROM A", x = 220, y = 8 })
    local romB = wm:createRomPaletteWindow({ title = "ROM B", x = 220, y = 80 })

    content.layers[1].paletteData = { winId = romA._id }
    content.layers[2].paletteData = { winId = romB._id }
    content.activeLayer = 2

    local lookup = PaletteLinkRender.buildPaletteLinkLookup(wm)

    expect(#lookup.contentWindows).toBe(1)
    expect(lookup.contentWindows[1]).toBe(content)
    expect(#lookup.romPaletteWindows).toBe(2)
    expect(lookup.activeRomPaletteByContent[content]).toBe(romB)
    expect(#lookup.contentByRomPalette[romA]).toBe(0)
    expect(#lookup.contentByRomPalette[romB]).toBe(1)
    expect(lookup.contentByRomPalette[romB][1]).toBe(content)
  end)

  it("getFocusedLinks returns linked content windows for a focused ROM palette", function()
    local wm = WM.new()
    local content = wm:createTileWindow({ title = "Art", x = 8, y = 8 })
    local rom = wm:createRomPaletteWindow({ title = "ROM", x = 220, y = 8 })
    content.layers[1].paletteData = { winId = rom._id }

    local app = { wm = wm }
    wm:setFocus(rom)

    local links = PaletteLinkRender.getFocusedLinks(app)
    expect(#links).toBe(1)
    expect(links[1].contentWin).toBe(content)
    expect(links[1].paletteWin).toBe(rom)
  end)

  it("getFocusedLinks returns the active-layer palette for a focused content window", function()
    local wm = WM.new()
    local content = wm:createTileWindow({ title = "Art", x = 8, y = 8, numLayers = 2 })
    local romA = wm:createRomPaletteWindow({ title = "ROM A", x = 220, y = 8 })
    local romB = wm:createRomPaletteWindow({ title = "ROM B", x = 220, y = 80 })
    content.layers[1].paletteData = { winId = romA._id }
    content.layers[2].paletteData = { winId = romB._id }
    content.activeLayer = 1

    local app = { wm = wm }
    wm:setFocus(content)

    local links = PaletteLinkRender.getFocusedLinks(app)
    expect(#links).toBe(1)
    expect(links[1].contentWin).toBe(content)
    expect(links[1].paletteWin).toBe(romA)
  end)
end)
