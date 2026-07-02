local WM = require("controllers.window.window_controller")
local PaletteActivationController = require("controllers.palette.palette_activation_controller")

describe("palette_activation_controller.lua", function()
  it("activates only the first created global palette by default", function()
    local wm = WM.new()
    local p1 = wm:createPaletteWindow({ title = "Palette 1" })
    local p2 = wm:createPaletteWindow({ title = "Palette 2", activePalette = false })

    expect(p1.activePalette).toBe(true)
    expect(p2.activePalette).toBe(false)
  end)

  it("does not change shader-active palette when focusing another global palette", function()
    local wm = WM.new()
    local p1 = wm:createPaletteWindow({ title = "Palette 1" })
    local p2 = wm:createPaletteWindow({ title = "Palette 2", activePalette = false })

    wm:setFocus(p2)

    expect(wm:getFocus()).toBe(p2)
    expect(p1.activePalette).toBe(true)
    expect(p2.activePalette).toBe(false)
  end)

  it("activates a global palette only through activateGlobalPalette", function()
    local wm = WM.new()
    local app = { wm = wm, invalidateConsumersOfPaletteWindow = function() end }
    local p1 = wm:createPaletteWindow({ title = "Palette 1" })
    local p2 = wm:createPaletteWindow({ title = "Palette 2", activePalette = false })

    expect(PaletteActivationController.activateGlobalPalette(p2, app)).toBe(true)

    expect(p1.activePalette).toBe(false)
    expect(p2.activePalette).toBe(true)
  end)
end)
