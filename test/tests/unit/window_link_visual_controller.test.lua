local LinkVisual = require("controllers.window.window_link_visual_controller")
local WM = require("controllers.window.window_controller")
local colors = require("app_colors")

describe("window_link_visual_controller.lua", function()
  it("computes pivot handle geometry from window left edge", function()
    local handleCx = LinkVisual.handleCenterXForWindowLeft(100)
    expect(handleCx).toBe(96.5)

    local ox, oy, ow, oh = LinkVisual.getPivotHandleRect(handleCx, 40)
    expect(ox).toBe(93)
    expect(oy).toBe(36)
    expect(ow).toBe(7)
    expect(oh).toBe(7)

    local ix, iy, iw, ih = LinkVisual.getInnerRectForHandleCenter(handleCx, 40)
    expect(iw).toBe(3)
    expect(ih).toBe(3)

    local cx, cy = LinkVisual.getInnerRectCenterPoint(handleCx, 40)
    expect(cx).toBe(ix + 1)
    expect(cy).toBe(iy + 1)
  end)

  it("detects pattern and palette link state per window kind", function()
    local wm = WM.new()
    local pt = wm:createPatternTableWindow({ title = "PT", x = 10, y = 10 })
    local ppu = wm:createPPUFrameWindow({ title = "PPU", x = 200, y = 10, romRaw = string.rep("\0", 256) })
    local oam = wm:createSpriteWindow({ animated = true, oamBacked = true, title = "OAM", x = 40, y = 180 })

    ppu.layers[1].linkedPatternTableWindowId = pt._id
    oam.layers[1].linkedPatternTableWindowId = pt._id
    table.insert(ppu.layers, {
      kind = "sprite",
      items = {},
      linkedPatternTableWindowId = "orphan",
    })

    expect(LinkVisual.ppuPatternBgLinked(ppu, wm)).toBe(true)
    expect(LinkVisual.ppuPatternSpriteLinked(ppu, wm)).toBe(true)
    expect(LinkVisual.oamPatternLinked(oam, wm)).toBe(true)
    expect(LinkVisual.innerColorForSlot(ppu, "ppu_pattern_bg", wm)[1]).toBe(colors.red[1])
    expect(LinkVisual.innerColorForSlot(oam, "oam_pattern", wm)[1]).toBe(colors.green[1])
  end)

  it("collects palette link edges and builds anchor layouts", function()
    local wm = WM.new()
    local art = wm:createTileWindow({ title = "Art", x = 20, y = 20 })
    local rom = wm:createRomPaletteWindow({ title = "ROM", x = 300, y = 20 })
    art.layers[1].paletteData = { winId = rom._id }

    local app = {
      wm = wm,
      windowLinksMode = "always",
      canvas = { getWidth = function() return 640 end, getHeight = function() return 360 end },
    }

    local edges = LinkVisual.collectWindowLinkEdges(app)
    expect(#edges).toBe(1)
    expect(edges[1].fromWin).toBe(art)
    expect(edges[1].toWin).toBe(rom)
    expect(edges[1].color).toBe(colors.blue)

    local layouts, handles = LinkVisual.buildAnchorLayouts(app, edges)
    expect(layouts[art]).toBeTruthy()
    expect(layouts[art].layout_palette).toBeTruthy()
    expect(layouts[rom]).toBeTruthy()
    expect(layouts[rom].palette_source).toBeTruthy()
    expect(#handles >= 2).toBe(true)

    local cx, cy = LinkVisual.getLeftAnchorPoint(art, "layout_palette", layouts)
    expect(type(cx)).toBe("number")
    expect(type(cy)).toBe("number")
  end)

  it("prepareLinkDrawState returns nil when modals block workspace", function()
    local app = {
      wm = WM.new(),
      windowLinksMode = "always",
      settingsModal = { isVisible = function() return true end },
    }
    expect(LinkVisual.prepareLinkDrawState(app)).toBe(nil)
  end)
end)
