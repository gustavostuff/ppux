local PaletteEdit = require("utils.palette_edit_helpers")

describe("palette_edit_helpers.lua", function()
  it("normalizes invalid blacks to 0F and leaves valid codes alone", function()
    expect(PaletteEdit.normalizeInvalidBlack("0D")).toBe("0F")
    expect(PaletteEdit.normalizeInvalidBlack("0e")).toBe("0F")
    expect(PaletteEdit.normalizeInvalidBlack("1F")).toBe("0F")
    expect(PaletteEdit.normalizeInvalidBlack("2E")).toBe("0F")
    expect(PaletteEdit.normalizeInvalidBlack("3F")).toBe("0F")
    expect(PaletteEdit.normalizeInvalidBlack("0F")).toBe("0F")
    expect(PaletteEdit.normalizeInvalidBlack("0C")).toBe("0C")
    expect(PaletteEdit.normalizeInvalidBlack("1D")).toBe("1D")
    expect(PaletteEdit.normalizeInvalidBlack("2A")).toBe("2A")
  end)

  it("nibbleAdjust skips invalid blacks so navigation can leave 0F", function()
    -- Immediate neighbors of 0F are invalid; skip to the next valid code.
    expect(PaletteEdit.nibbleAdjust("0F", -1, 0)).toBe("0C")
    expect(PaletteEdit.nibbleAdjust("0C", 1, 0)).toBe("0F")
    -- Down from 0F only hits invalid column-F blacks — stay on 0F.
    expect(PaletteEdit.nibbleAdjust("0F", 0, 1)).toBe("0F")
    -- Right/up from 0F are already at the nibble edge.
    expect(PaletteEdit.nibbleAdjust("0F", 1, 0)).toBe("0F")
    expect(PaletteEdit.nibbleAdjust("0F", 0, -1)).toBe("0F")
  end)

  it("nibbleAdjust skips 0D/0E when stepping toward 0F from 0C", function()
    expect(PaletteEdit.nibbleAdjust("0C", 1, 0)).toBe("0F")
    expect(PaletteEdit.nibbleAdjust("0C", 0, 1)).toBe("1C")
    expect(PaletteEdit.nibbleAdjust("1C", 0, -1)).toBe("0C")
  end)

  it("nibbleAdjust cannot step past 1D into invalid 1E/1F", function()
    expect(PaletteEdit.nibbleAdjust("1D", 1, 0)).toBe("1D")
    expect(PaletteEdit.nibbleAdjust("2D", 1, 0)).toBe("2D")
    expect(PaletteEdit.nibbleAdjust("3D", 1, 0)).toBe("3D")
  end)

  it("nibbleAdjust can leave an invalid black toward a valid neighbor", function()
    -- If a cell somehow still holds 0E, left skips 0D and lands on 0C.
    expect(PaletteEdit.nibbleAdjust("0E", -1, 0)).toBe("0C")
    expect(PaletteEdit.nibbleAdjust("0E", 1, 0)).toBe("0F")
    expect(PaletteEdit.nibbleAdjust("1F", 0, -1)).toBe("0F")
  end)
end)
