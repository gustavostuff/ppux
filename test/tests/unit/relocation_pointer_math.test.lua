local RelocationPointerMath = require("utils.relocation_pointer_math")

describe("relocation_pointer_math.lua", function()
  it("parses and formats 6-digit file offsets", function()
    expect(RelocationPointerMath.parseFileOffset("13300")).toBe(0x013300)
    expect(RelocationPointerMath.parseFileOffset("0x013300")).toBe(0x013300)
    expect(RelocationPointerMath.parseFileOffset("$01255B")).toBe(0x01255B)
    expect(RelocationPointerMath.formatFileOffset(0x013300)).toBe("0x013300")
    expect(RelocationPointerMath.formatFileOffset(0x10)).toBe("0x000010")
  end)

  it("rejects invalid offsets", function()
    local v, err = RelocationPointerMath.parseFileOffset("")
    expect(v).toBeNil()
    expect(err).toBe("empty")
    v, err = RelocationPointerMath.parseFileOffset("GG")
    expect(v).toBeNil()
    expect(err).toBe("invalid_hex")
  end)

  it("computes cutscene1 relocate pointer F0 B2 from 0x013300", function()
    local cpu, lo, hi = RelocationPointerMath.fileOffsetToPointer(0x013300)
    expect(cpu).toBe(0xB2F0)
    expect(lo).toBe(0xF0)
    expect(hi).toBe(0xB2)
    expect(RelocationPointerMath.formatByte(lo)).toBe("F0")
    expect(RelocationPointerMath.formatByte(hi)).toBe("B2")
  end)

  it("computes original cutscene1 pointer 83 A4 from 0x012493", function()
    local cpu, lo, hi = RelocationPointerMath.fileOffsetToPointer(0x012493)
    expect(cpu).toBe(0xA483)
    expect(lo).toBe(0x83)
    expect(hi).toBe(0xA4)
  end)

  it("rejects offsets inside the iNES header", function()
    local cpu, lo, hi, err = RelocationPointerMath.fileOffsetToPointer(0x08)
    expect(cpu).toBeNil()
    expect(lo).toBeNil()
    expect(hi).toBeNil()
    expect(err).toBe("before_header")
  end)

  it("supports alternate bank window and CPU base", function()
    local cpu, lo, hi = RelocationPointerMath.fileOffsetToPointer(0x005010, {
      headerSize = 0x10,
      bankSize = 0x2000,
      cpuMapBase = 0xA000,
    })
    -- prg = 0x5000; % 0x2000 = 0x1000; + 0xA000 = 0xB000
    expect(cpu).toBe(0xB000)
    expect(lo).toBe(0x00)
    expect(hi).toBe(0xB0)

    cpu, lo, hi = RelocationPointerMath.fileOffsetToPointer(0x000210, {
      headerSize = 0x00,
      bankSize = 0x8000,
      cpuMapBase = 0x8000,
    })
    expect(cpu).toBe(0x8210)
    expect(lo).toBe(0x10)
    expect(hi).toBe(0x82)
  end)

  it("formats the formula from mapping opts", function()
    expect(RelocationPointerMath.formatFormula()).toBe("cpu = ((offset - 0x10) % 0x4000) + 0x8000")
    expect(RelocationPointerMath.formatFormula({
      headerSize = 0,
      bankSize = 0x2000,
      cpuMapBase = 0xA000,
    })).toBe("cpu = ((offset - 0x0) % 0x2000) + 0xA000")
  end)
end)
