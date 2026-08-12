-- ppu_frame_range_modal.test.lua
-- Unit tests for ui/modals/ppu_frame_range_modal.lua scan markers / open behavior

local PPUFrameRangeModal = require("ui.modals.ppu_frame_range_modal")
local NametableUtils = require("utils.nametable_utils")

local function buildFullPage(seed)
  local nt = {}
  for i = 1, 960 do
    nt[i] = (seed + i - 1) % 256
  end
  local at = {}
  for i = 1, 64 do
    at[i] = (seed + i) % 4
  end
  return nt, at
end

local function bytesToRomString(bytes)
  local parts = {}
  for i = 1, #bytes do
    parts[i] = string.char(bytes[i] % 256)
  end
  return table.concat(parts)
end

describe("ppu_frame_range_modal.lua", function()
  it("hitsToMinimapMarkers spans each complete stream with OAM color cycle", function()
    local markers = PPUFrameRangeModal._hitsToMinimapMarkers({
      { start = 0x100, ["end"] = 0x10F, score = 1 },
      { start = 0x200, ["end"] = 0x2FF, score = 2 },
      { start = 0x300, ["end"] = 0x301, score = 3 },
    })
    expect(#markers).toBe(3)
    expect(markers[1].offset).toBe(0x100)
    expect(markers[1].groupSize).toBe(0x10)
    expect(markers[1].color).toBe("red")
    expect(markers[2].color).toBe("green")
    expect(markers[3].color).toBe("blue")
  end)

  it("Scan marks streams as semi-selected and keeps them after selecting a hit", function()
    local nt, at = buildFullPage(9)
    local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
    local pad = 32
    local buf = {}
    for i = 1, pad + #compressed + 8 do
      buf[i] = 0x44
    end
    for i = 1, #compressed do
      buf[pad + i] = compressed[i]
    end
    local rom = bytesToRomString(buf)

    local modal = PPUFrameRangeModal.new()
    modal:show({
      romRaw = rom,
      codec = "konami",
    })
    expect(#(modal.hexGrid:getSemiSelectedStarts())).toBe(0)

    modal:_runScan()
    local semi = modal.hexGrid:getSemiSelectedStarts()
    expect(#semi).toBeGreaterThan(0)
    expect(modal.hexGrid:getSemiGroupSize(pad)).toBe(#compressed)

    modal:_onGridSelect(pad + 4, { fromGrid = true })
    expect(#(modal.hexGrid:getSemiSelectedStarts())).toBe(#semi)
    expect(modal.hexGrid:highlightColorForStart(pad)[1]).toBeTruthy()
    modal:hide()
  end)

  it("two-click grid selection sets start then end; same cell clears", function()
    local modal = PPUFrameRangeModal.new()
    modal:show({
      romRaw = string.rep("\0", 256),
      codec = "konami",
    })

    modal:_onGridSelect(0x40, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(0x40)
    expect(modal.startField:getText()).toBe("0x000040")
    expect(modal.endField:getText()).toBe("0x000040")
    expect(modal.hexGrid:getSelectedGroupSize(0x40)).toBe(1)

    modal:_onGridSelect(0x4F, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(nil)
    expect(modal._rangeStart).toBe(0x40)
    expect(modal._rangeEnd).toBe(0x4F)
    expect(modal.startField:getText()).toBe("0x000040")
    expect(modal.endField:getText()).toBe("0x00004F")
    expect(modal.hexGrid:getSelectedGroupSize(0x40)).toBe(0x10)

    -- Click inside committed range → no-op.
    modal:_onGridSelect(0x45, { fromGrid = true })
    expect(modal._rangeStart).toBe(0x40)
    expect(modal._rangeEnd).toBe(0x4F)
    expect(modal.hexGrid:getSelectedGroupSize(0x40)).toBe(0x10)

    -- Click outside → clear and re-anchor at that cell.
    modal:_onGridSelect(0x20, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(0x20)
    expect(modal._rangeStart).toBe(nil)
    expect(modal._rangeEnd).toBe(nil)
    expect(modal.hexGrid:getSelectedGroupSize(0x20)).toBe(1)

    -- Mid two-click: same cell clears.
    modal:_onGridSelect(0x20, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(nil)
    expect(#(modal.hexGrid:getSelectedStarts())).toBe(0)

    -- End before start still normalizes.
    modal:_onGridSelect(0x50, { fromGrid = true })
    modal:_onGridSelect(0x40, { fromGrid = true })
    expect(modal.startField:getText()).toBe("0x000040")
    expect(modal.endField:getText()).toBe("0x000050")
    modal:hide()
  end)

  it("user ranges can be created overlapping scan semi-selected marks", function()
    local nt, at = buildFullPage(3)
    local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
    local pad = 32
    local buf = {}
    for i = 1, pad + #compressed + 8 do
      buf[i] = 0x44
    end
    for i = 1, #compressed do
      buf[pad + i] = compressed[i]
    end
    local rom = bytesToRomString(buf)

    local modal = PPUFrameRangeModal.new()
    modal:show({ romRaw = rom, codec = "konami" })
    modal:_runScan()
    expect(#(modal.hexGrid:getSemiSelectedStarts())).toBeGreaterThan(0)

    -- Two-click entirely inside the scanned stream span.
    modal:_onGridSelect(pad + 2, { fromGrid = true })
    modal:_onGridSelect(pad + 10, { fromGrid = true })
    expect(modal._rangeStart).toBe(pad + 2)
    expect(modal._rangeEnd).toBe(pad + 10)
    expect(modal.hexGrid:getSelectedGroupSize(pad + 2)).toBe(9)
    modal:hide()
  end)
end)
