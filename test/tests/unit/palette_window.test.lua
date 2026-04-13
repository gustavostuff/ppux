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
    expect(win.cellW).toBe(20)
    expect(win.cellH).toBe(15)

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
    expect(win.cellW).toBe(20)
    expect(win.cellH).toBe(15)
  end)

  it("builds row and column strip codes from the selected color", function()
    local win = PaletteWindow.new(0, 0, 1, "smooth_fbx", 1, 4, {
      title = "Global Palette Strips",
      initCodes = { "0F", "30", "37", "2B" },
    })

    win:setSelected(3, 0)
    local strips = win:getSelectedStripCodes()

    expect(strips).toBeTruthy()
    expect(strips.code).toBe("2B")
    expect(strips.rowIndex).toBe(2)
    expect(strips.colIndex).toBe(11)
    expect(strips.rowCodes[1]).toBe("20")
    expect(strips.rowCodes[16]).toBe("2F")
    expect(strips.colCodes[1]).toBe("0B")
    expect(strips.colCodes[4]).toBe("3B")
  end)

  it("uses quarter-cell strip sizes in normal mode and hides strips in compact mode", function()
    local win = PaletteWindow.new(0, 0, 1, "smooth_fbx", 4, 4, {
      title = "Global Palette Strip Metrics",
      initCodes = {
        "00", "01", "02", "03",
        "10", "11", "12", "13",
        "20", "21", "22", "23",
        "30", "31", "32", "33",
      },
    })

    win:setSelected(2, 1)
    local metrics = win:getStripMetrics()
    expect(metrics).toBeTruthy()
    expect(metrics.horizontalCellW).toBe(8)
    expect(metrics.horizontalCellH).toBe(6)
    expect(metrics.verticalCellW).toBe(8)
    expect(metrics.verticalCellH).toBe(6)
    expect(metrics.verticalY).toBe(24)

    win:setCompactMode(true)
    expect(win:getStripMetrics()).toBe(nil)
  end)

  it("bypasses the shared minimum window size constraint", function()
    local win = PaletteWindow.new(0, 0, 2, "smooth_fbx", 1, 4, {
      title = "Global Palette Small Compact",
      compactView = true,
    })

    expect(win.minWindowSize).toBe(0)
    expect(win.zoom).toBe(2)

    win:setZoomLevel(1)
    expect(win.zoom).toBe(1)
  end)
end)
