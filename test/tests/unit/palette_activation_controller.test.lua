local WM = require("controllers.window.window_controller")
local PaletteActivationController = require("controllers.palette.palette_activation_controller")

describe("palette_activation_controller.lua", function()
  it("activates only the first created generic palette by default", function()
    local wm = WM.new()
    local p1 = wm:createPaletteWindow({ title = "Palette 1" })
    local p2 = wm:createPaletteWindow({ title = "Palette 2", activePalette = false })

    expect(p1.activePalette).toBe(true)
    expect(p2.activePalette).toBe(false)
  end)

  it("does not change shader-active palette when focusing another generic palette", function()
    local wm = WM.new()
    local p1 = wm:createPaletteWindow({ title = "Palette 1" })
    local p2 = wm:createPaletteWindow({ title = "Palette 2", activePalette = false })

    wm:setFocus(p2)

    expect(wm:getFocus()).toBe(p2)
    expect(p1.activePalette).toBe(true)
    expect(p2.activePalette).toBe(false)
  end)

  it("activates a generic palette only through activateGlobalPalette", function()
    local wm = WM.new()
    local app = { wm = wm, invalidateConsumersOfPaletteWindow = function() end }
    local p1 = wm:createPaletteWindow({ title = "Palette 1" })
    local p2 = wm:createPaletteWindow({ title = "Palette 2", activePalette = false })

    expect(PaletteActivationController.activateGlobalPalette(p2, app)).toBe(true)

    expect(p1.activePalette).toBe(false)
    expect(p2.activePalette).toBe(true)
  end)

  it("uses shader-active palette background color even when minimized", function()
    local wm = WM.new()
    local p1 = wm:createPaletteWindow({
      title = "Palette 1",
      initCodes = { "0F", "30", "37", "2B" },
    })
    local p2 = wm:createPaletteWindow({
      title = "Palette 2",
      activePalette = false,
      initCodes = { "21", "22", "23", "24" },
    })

    PaletteActivationController.activateGlobalPalette(p1, { wm = wm })
    p1._minimized = true

    local bg = PaletteActivationController.getBackgroundColor(wm)
    expect(bg).toBe(p1:getFirstColor())
    expect(bg[1]).toBe(p1:getFirstColor()[1])
    expect(bg[1]).toNotBe(p2:getFirstColor()[1])
  end)
end)
