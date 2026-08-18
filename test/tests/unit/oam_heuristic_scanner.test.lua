-- oam_heuristic_scanner.test.lua
-- Unit tests for scanners/oam_heuristic_scanner.lua

local Scanner = require("scanners.oam_heuristic_scanner")

local function plantAt(romSize, offset, bytes, fill)
  fill = fill or 0x80
  local buf = {}
  for i = 1, romSize do
    buf[i] = fill
  end
  for i = 1, #bytes do
    buf[offset + i] = bytes[i] % 256
  end
  local parts = {}
  for i = 1, #buf do
    parts[i] = string.char(buf[i])
  end
  return table.concat(parts)
end

local function oam(y, tile, attr, x)
  return { y, tile, attr, x }
end

local function concatRecords(...)
  local out = {}
  for _, rec in ipairs({ ... }) do
    for i = 1, #rec do
      out[#out + 1] = rec[i]
    end
  end
  return out
end

describe("oam_heuristic_scanner.lua", function()
  it("accepts palette-only attr bytes 0-3 and rejects flip/priority", function()
    expect(Scanner.isPaletteAttr(0)).toBe(true)
    expect(Scanner.isPaletteAttr(1)).toBe(true)
    expect(Scanner.isPaletteAttr(2)).toBe(true)
    expect(Scanner.isPaletteAttr(3)).toBe(true)
    expect(Scanner.isPaletteAttr(0x04)).toBe(false)
    expect(Scanner.isPaletteAttr(0x20)).toBe(false)
    expect(Scanner.isPaletteAttr(0x40)).toBe(false)
    expect(Scanner.isPaletteAttr(0x80)).toBe(false)
  end)

  it("finds a planted horizontally aligned pair", function()
    local bytes = concatRecords(
      oam(16, 0x10, 0, 40),
      oam(16, 0x11, 1, 48)
    )
    local pad = 32
    local rom = plantAt(pad + 16, pad, bytes, 0x80)
    local hits = Scanner.scan(rom)
    local found = nil
    for _, hit in ipairs(hits) do
      if hit.start == pad then
        found = hit
        break
      end
    end
    expect(found).toBeTruthy()
    expect(found["end"]).toBe(pad + 7)
    expect(found.aligned_horizontally).toBe(true)
    expect(Scanner.startsForHit(found)).toEqual({ pad, pad + 4 })
  end)

  it("rejects a pair whose attr has flip bits set", function()
    local bytes = concatRecords(
      oam(16, 0x10, 0x40, 40),
      oam(16, 0x11, 0, 48)
    )
    local pad = 16
    local rom = plantAt(pad + 16, pad, bytes, 0x80)
    local hits = Scanner.scan(rom)
    for _, hit in ipairs(hits) do
      expect(hit.start == pad).toBe(false)
    end
  end)

  it("skips all-zero padding pairs", function()
    local rom = string.rep("\0", 64)
    local hits = Scanner.scan(rom)
    expect(#hits).toBe(0)
  end)

  it("merges consecutive 4-byte-stride pairs into one hit", function()
    local bytes = concatRecords(
      oam(20, 1, 0, 8),
      oam(20, 2, 1, 16),
      oam(20, 3, 2, 24)
    )
    local pad = 8
    local rom = plantAt(pad + 24, pad, bytes, 0x80)
    local hits = Scanner.scan(rom)
    local found = nil
    for _, hit in ipairs(hits) do
      if hit.start == pad then
        found = hit
        break
      end
    end
    expect(found).toBeTruthy()
    expect(found["end"]).toBe(pad + 11)
    expect(Scanner.startsForHit(found)).toEqual({ pad, pad + 4, pad + 8 })
  end)

  it("hitAt prefers an exact start then a containing range", function()
    local hits = {
      { start = 100, ["end"] = 107 },
      { start = 200, ["end"] = 211 },
    }
    expect(Scanner.hitAt(hits, 200).start).toBe(200)
    expect(Scanner.hitAt(hits, 204).start).toBe(200)
    expect(Scanner.hitAt(hits, 108)).toBe(nil)
  end)
end)
