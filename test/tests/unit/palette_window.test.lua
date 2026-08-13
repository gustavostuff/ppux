local PaletteWindow = require("ui.windows_system.palette_window")

describe("palette_window.lua - compact mode", function()
  it("builds row and column strip codes from the selected color", function()
    local win = PaletteWindow.new(0, 0, 1, "smooth_fbx", 1, 4, {
      title = "Generic Palette Strips",
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

  it("hides nibble selection strips while compact-only is forced", function()
    local win = PaletteWindow.new(0, 0, 1, "smooth_fbx", 4, 4, {
      title = "Generic Palette Strip Metrics",
      initCodes = {
        "00", "01", "02", "03",
        "10", "11", "12", "13",
        "20", "21", "22", "23",
        "30", "31", "32", "33",
      },
    })

    win:setSelected(2, 1)
    expect(win:getStripMetrics()).toBe(nil)
  end)

  it("keeps selection usable when not shader-active (compact has no strip shadows)", function()
    local win = PaletteWindow.new(0, 0, 1, "smooth_fbx", 1, 4, {
      title = "Inactive Global",
      activePalette = false,
      initCodes = { "0C", "14", "24", "34" },
    })
    win:setSelected(0, 0)

    local wm = {
      getFocus = function()
        return win
      end,
    }
    expect(win:getSelectionStripShadowRectsCanvas(wm)).toBe(nil)

    expect(win.selected).toBeTruthy()
    expect(win.selected.col).toBe(0)
    expect(win.codes2D[0][0]).toBe("0C")

    win.activePalette = true
    -- Compact-only: nibble strips stay hidden even when shader-active.
    expect(win:getSelectionStripShadowRectsCanvas(wm)).toBe(nil)
  end)

  it("adjusts colors on inactive generic palettes without syncing the shader", function()
    local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
    local before = { ShaderPaletteController.getCodes()[1], ShaderPaletteController.getCodes()[2], ShaderPaletteController.getCodes()[3], ShaderPaletteController.getCodes()[4] }

    local win = PaletteWindow.new(0, 0, 1, "smooth_fbx", 1, 4, {
      title = "Inactive Editable",
      activePalette = false,
      initCodes = { "0C", "14", "24", "34" },
    })
    win:setSelected(0, 0)
    win:adjustSelectedByArrows(1, 0)

    expect(win.codes2D[0][0]).toNotBe("0C")
    local after = ShaderPaletteController.getCodes()
    expect(after[1]).toBe(before[1])
    expect(after[2]).toBe(before[2])
    expect(after[3]).toBe(before[3])
    expect(after[4]).toBe(before[4])
  end)

  it("can leave 0F via nibble adjust (skips invalid blacks)", function()
    local win = PaletteWindow.new(0, 0, 1, "smooth_fbx", 1, 4, {
      title = "Leave 0F",
      activePalette = false,
      initCodes = { "0F", "30", "37", "2B" },
    })
    win:setSelected(0, 0)
    win:adjustSelectedByArrows(-1, 0)
    expect(win.codes2D[0][0]).toBe("0C")

    win:adjustSelectedByArrows(1, 0)
    expect(win.codes2D[0][0]).toBe("0F")
  end)

  it("stores 0F when nibble adjust would land on an invalid black", function()
    local win = PaletteWindow.new(0, 0, 1, "smooth_fbx", 1, 4, {
      title = "Normalize black",
      activePalette = false,
      initCodes = { "0C", "30", "37", "2B" },
    })
    win:setSelected(0, 0)
    -- 0C +1 skips 0D/0E and lands on canonical 0F.
    win:adjustSelectedByArrows(1, 0)
    expect(win.codes2D[0][0]).toBe("0F")
  end)

  it("bypasses the shared minimum window size constraint", function()
    local win = PaletteWindow.new(0, 0, 2, "smooth_fbx", 1, 4, {
      title = "Generic Palette Small Compact",
      compactView = true,
    })

    expect(win.minWindowSize).toBe(0)
    expect(win.zoom).toBe(2)

    win:setZoomLevel(1)
    expect(win.zoom).toBe(1)
  end)
end)
