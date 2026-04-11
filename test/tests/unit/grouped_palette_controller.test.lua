local GroupedPaletteController = require("controllers.palette.grouped_palette_controller")
local WM = require("controllers.window.window_controller")

describe("grouped_palette_controller.lua", function()
  local previousCtx

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = {
      app = {
        appEditState = {
          romRaw = string.rep(string.char(0x0F), 64),
        },
      },
    }
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("shows one source palette window per kind when enabled", function()
    local app = { wm = WM.new() }
    local wm = app.wm

    local p1 = wm:createPaletteWindow({ title = "Palette 1" })
    p1._id = "palette_01"
    local p2 = wm:createPaletteWindow({ title = "Palette 2" })
    p2._id = "palette_02"

    local r1 = wm:createRomPaletteWindow({ title = "ROM Palette 1" })
    r1._id = "rom_palette_01"
    local r2 = wm:createRomPaletteWindow({ title = "ROM Palette 2" })
    r2._id = "rom_palette_02"

    local controller = GroupedPaletteController.new(app)
    controller:setEnabled(true, {
      enabled = true,
      global = { activeSourceWindowId = "palette_02" },
      rom = { activeSourceWindowId = "rom_palette_01" },
    })

    expect(p1._groupHidden).toBe(true)
    expect(p2._groupHidden).toBe(false)
    expect(r1._groupHidden).toBe(false)
    expect(r2._groupHidden).toBe(true)
  end)

  it("cycles grouped windows in layout order and wraps around", function()
    local app = { wm = WM.new() }
    local wm = app.wm

    local p1 = wm:createPaletteWindow({ title = "Palette 1" })
    p1._id = "palette_01"
    local p2 = wm:createPaletteWindow({ title = "Palette 2" })
    p2._id = "palette_02"
    local p3 = wm:createPaletteWindow({ title = "Palette 3" })
    p3._id = "palette_03"

    local controller = GroupedPaletteController.new(app)
    controller:setEnabled(true, {
      enabled = true,
      global = { activeSourceWindowId = "palette_01" },
      rom = {},
    })

    expect(p1._groupHidden).toBe(false)
    expect(p2._groupHidden).toBe(true)
    expect(p3._groupHidden).toBe(true)

    expect(controller:cycleWindow(p1, 1)).toBe(true)
    expect(p1._groupHidden).toBe(true)
    expect(p2._groupHidden).toBe(false)
    expect(p3._groupHidden).toBe(true)

    expect(controller:cycleWindow(p2, 1)).toBe(true)
    expect(p1._groupHidden).toBe(true)
    expect(p2._groupHidden).toBe(true)
    expect(p3._groupHidden).toBe(false)

    expect(controller:cycleWindow(p3, 1)).toBe(true)
    expect(p1._groupHidden).toBe(false)
    expect(p2._groupHidden).toBe(true)
    expect(p3._groupHidden).toBe(true)
  end)

  it("activates a specific grouped source window directly", function()
    local app = { wm = WM.new() }
    local wm = app.wm

    local r1 = wm:createRomPaletteWindow({ title = "ROM Palette 1" })
    r1._id = "rom_palette_01"
    local r2 = wm:createRomPaletteWindow({ title = "ROM Palette 2" })
    r2._id = "rom_palette_02"
    local r3 = wm:createRomPaletteWindow({ title = "ROM Palette 3" })
    r3._id = "rom_palette_03"

    local controller = GroupedPaletteController.new(app)
    controller:setEnabled(true, {
      enabled = true,
      global = {},
      rom = { activeSourceWindowId = "rom_palette_01" },
    })

    expect(r1._groupHidden).toBe(false)
    expect(r2._groupHidden).toBe(true)
    expect(r3._groupHidden).toBe(true)

    expect(controller:activateWindow(r3)).toBe(true)
    expect(r1._groupHidden).toBe(true)
    expect(r2._groupHidden).toBe(true)
    expect(r3._groupHidden).toBe(false)
  end)
end)
