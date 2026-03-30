local PaletteWindow = require("user_interface.windows_system.palette_window")

describe("palette_window.lua - compact mode", function()
  it("supports compact mode and switches between normal and compact cell sizes", function()
    local win = PaletteWindow.new(0, 0, 1, "smooth_fbx", 1, 4, {
      title = "Global Palette Compact",
    })

    expect(win:supportsCompactMode()).toBe(true)
    expect(win.compactView).toBe(false)
    expect(win.cellW).toBe(32)
    expect(win.cellH).toBe(24)

    win:setCompactMode(true)
    expect(win.compactView).toBe(true)
    expect(win.cellW).toBe(24)
    expect(win.cellH).toBe(16)

    win:setCompactMode(false)
    expect(win.compactView).toBe(false)
    expect(win.cellW).toBe(32)
    expect(win.cellH).toBe(24)
  end)

  it("applies compact mode from constructor data", function()
    local win = PaletteWindow.new(0, 0, 1, "smooth_fbx", 1, 4, {
      title = "Global Palette Compact Init",
      compactView = true,
    })

    expect(win.compactView).toBe(true)
    expect(win.cellW).toBe(24)
    expect(win.cellH).toBe(16)
  end)
end)
