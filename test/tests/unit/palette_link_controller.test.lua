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
end)
