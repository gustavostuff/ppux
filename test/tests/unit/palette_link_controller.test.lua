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
end)
