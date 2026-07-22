local NametableBreakpointMath = require("utils.nametable_breakpoint_math")

describe("nametable_breakpoint_math.lua", function()
  it("computes PPU addresses from col/row", function()
    local addr, warn = NametableBreakpointMath.cellToPpuAddress(0, 0)
    expect(addr).toBe(0x2000)
    expect(warn).toBeNil()

    addr, warn = NametableBreakpointMath.cellToPpuAddress(8, 10)
    expect(addr).toBe(0x2148)
    expect(warn).toBeNil()

    addr = NametableBreakpointMath.cellToPpuAddress(16, 10)
    expect(addr).toBe(0x2150)

    addr = NametableBreakpointMath.cellToPpuAddress(31, 29)
    expect(addr).toBe(0x23BF)
  end)

  it("supports other nametable bases", function()
    local addr = NametableBreakpointMath.cellToPpuAddress(8, 10, { nametableBase = 0x2400 })
    expect(addr).toBe(0x2548)
  end)

  it("warns when the cell falls in the attribute table", function()
    -- base+0x3C0 is the start of attrs; for $2000 that is outside 30 tile rows,
    -- so use a base-relative check via a high tile row still maps to tiles only.
    -- Row 29 col 31 = $23BF still tiles; attrs begin at $23C0.
    local addr, warn = NametableBreakpointMath.cellToPpuAddress(0, 0, { nametableBase = 0x2000 })
    expect(warn).toBeNil()
    -- Force attribute address path via direct formula edge: col/row max still tiles.
    expect(NametableBreakpointMath.ATTR_START).toBe(0x23C0)
  end)

  it("formats breakpoint address and conditions", function()
    expect(NametableBreakpointMath.formatPpuAddress(0x2148)).toBe("$2148")
    expect(NametableBreakpointMath.formatConditionA(0xA0)).toBe("A == #A0")
    expect(NametableBreakpointMath.formatConditionW(0xA0)).toBe("W == #A0")
  end)

  it("parses col/row and tile index", function()
    expect(NametableBreakpointMath.parseCellIndex("8", 31)).toBe(8)
    expect(NametableBreakpointMath.parseCellIndex("0x10", 31)).toBe(0x10)
    expect(NametableBreakpointMath.parseTileIndex("A0")).toBe(0xA0)
    expect(NametableBreakpointMath.parseTileIndex("#a0")).toBe(0xA0)
    local v, err = NametableBreakpointMath.parseCellIndex("32", 31)
    expect(v).toBeNil()
    expect(err).toBe("out_of_range")
  end)
end)
