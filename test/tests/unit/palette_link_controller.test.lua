local PaletteLinkController = require("controllers.palette.palette_link_controller")
local WM = require("controllers.window.window_controller")

describe("palette_link_controller.lua", function()
  local function centerPoint(win)
    local x, y, w, h = win:getScreenRect()
    return x + math.floor(w * 0.5), y + math.floor(h * 0.5)
  end

  it("ignores grouped-hidden ROM palettes when picking drop target", function()
    local wm = WM.new()
    local contentWin = wm:createTileWindow({ title = "Content", x = 8, y = 8 })
    local visiblePalette = wm:createRomPaletteWindow({ title = "Visible Palette", x = 220, y = 140 })
    local hiddenPalette = wm:createRomPaletteWindow({ title = "Hidden Palette", x = 220, y = 140 })

    hiddenPalette._groupHidden = true

    local x, y = centerPoint(hiddenPalette)
    local target = PaletteLinkController.getContentToPaletteLinkDropTarget(wm, contentWin, x, y)

    expect(target).toBe(visiblePalette)
  end)

  it("returns nil when only grouped-hidden ROM palettes are under cursor", function()
    local wm = WM.new()
    local contentWin = wm:createTileWindow({ title = "Content", x = 8, y = 8 })
    local hiddenPalette = wm:createRomPaletteWindow({ title = "Hidden Palette", x = 220, y = 140 })

    hiddenPalette._groupHidden = true

    local x, y = centerPoint(hiddenPalette)
    local target = PaletteLinkController.getContentToPaletteLinkDropTarget(wm, contentWin, x, y)

    expect(target).toBe(nil)
  end)

  it("lists minimized ROM palettes for link-by-id menus", function()
    local wm = WM.new()
    local visiblePalette = wm:createRomPaletteWindow({ title = "Visible Palette", x = 220, y = 8 })
    local minimizedPalette = wm:createRomPaletteWindow({ title = "Minimized Palette", x = 220, y = 80 })
    minimizedPalette._minimized = true

    local listed = PaletteLinkController.getRomPaletteWindows(wm)
    expect(#listed).toBe(2)
    expect(listed[1]).toBe(minimizedPalette)
    expect(listed[2]).toBe(visiblePalette)
  end)

  it("resolves ROM palette links even when the palette is minimized", function()
    local wm = WM.new()
    local contentWin = wm:createTileWindow({ title = "Content", x = 8, y = 8 })
    local romPalette = wm:createRomPaletteWindow({ title = "ROM Palette", x = 220, y = 8 })
    romPalette._minimized = true
    contentWin.layers[1].paletteData = { winId = romPalette._id }

    expect(PaletteLinkController.getLinkedRomPaletteWindowForLayer(contentWin, wm, 1)).toBe(romPalette)
    expect(PaletteLinkController.getActiveLayerLinkedPaletteWindow(contentWin, wm)).toBe(romPalette)
  end)

  it("removeLinkForLayer uses the target layer's ROM link, not the active layer", function()
    local wm = WM.new()
    local contentWin = wm:createTileWindow({ title = "Two layers", x = 8, y = 8, numLayers = 2 })
    local romA = wm:createRomPaletteWindow({ title = "ROM A", x = 220, y = 8 })
    local romB = wm:createRomPaletteWindow({ title = "ROM B", x = 220, y = 80 })
    contentWin.layers[1].paletteData = { winId = romA._id }
    contentWin.layers[2].paletteData = { winId = romB._id }
    contentWin.activeLayer = 1

    local prev = rawget(_G, "ctx")
    _G.ctx = {
      app = {
        wm = wm,
        undoRedo = {
          addPaletteLinkEvent = function()
            return true
          end,
        },
      },
    }

    expect(PaletteLinkController.getLinkedRomPaletteWindowForLayer(contentWin, wm, 1)).toBe(romA)
    expect(PaletteLinkController.getLinkedRomPaletteWindowForLayer(contentWin, wm, 2)).toBe(romB)

    PaletteLinkController.removeLinkForLayer(contentWin, 2)
    expect(contentWin.layers[2].paletteData).toBeNil()
    expect(contentWin.layers[1].paletteData and contentWin.layers[1].paletteData.winId).toBe(romA._id)

    _G.ctx = prev
  end)

  it("linking a ROM palette to a PPU frame keeps nametable attribute palettes", function()
    local wm = WM.new()
    local ppu = wm:createPPUFrameWindow({
      title = "PPU",
      x = 8,
      y = 8,
      romRaw = string.rep("\0", 256),
    })
    local romPalette = wm:createRomPaletteWindow({ title = "BG palettes", x = 220, y = 8 })
    local layer = ppu.layers[1]
    ppu.activeLayer = 1

    -- Non-zero attrs: top-left quadrant uses palette index 2 (paletteNumbers = 3).
    ppu.nametableAttrBytes = {}
    for i = 1, 64 do
      ppu.nametableAttrBytes[i] = 0x00
    end
    ppu.nametableAttrBytes[1] = 0x02
    layer.paletteNumbers = { [0] = 3, [1] = 3, [32] = 3, [33] = 3 }

    local prev = rawget(_G, "ctx")
    local compositeEvents = nil
    _G.ctx = {
      app = {
        wm = wm,
        setStatus = function() end,
        invalidatePpuFramePaletteLayer = function() end,
        snapshotPpuFrameUndoState = function()
          return { attrs = { ppu.nametableAttrBytes[1] } }
        end,
        undoRedo = {
          addPaletteLinkEvent = function()
            return true
          end,
          addCompositeEvent = function(_, ev)
            compositeEvents = ev
            return true
          end,
        },
      },
      wm = function()
        return wm
      end,
    }

    local ok, err = PaletteLinkController.linkLayerToPalette(ppu, 1, romPalette)
    expect(ok).toBe(true)
    expect(err).toBeNil()
    expect(layer.paletteData and layer.paletteData.winId).toBe(romPalette._id)
    -- Must not force every tile onto ROM palette row 0 / wipe attribute bytes.
    expect(ppu.nametableAttrBytes[1]).toBe(0x02)
    expect(layer.paletteNumbers[0]).toBe(3)
    expect(compositeEvents).toBeNil()

    _G.ctx = prev
  end)
end)
