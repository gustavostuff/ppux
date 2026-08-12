-- ppu_frame_range_modal.test.lua
-- Unit tests for ui/modals/ppu_frame_range_modal.lua selection mode / shape cache

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

local function plantStreamRom(seed, pad)
  pad = pad or 32
  local nt, at = buildFullPage(seed)
  local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
  local buf = {}
  for i = 1, pad + #compressed + 8 do
    buf[i] = 0x44
  end
  for i = 1, #compressed do
    buf[pad + i] = compressed[i]
  end
  return bytesToRomString(buf), pad, #compressed
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

  it("keeps two-click hint after hydrate from existing layer range", function()
    local modal = PPUFrameRangeModal.new()
    modal:show({
      romRaw = string.rep("\0", 256),
      codec = "konami",
      initialStartAddress = "0x000010",
      initialEndAddress = "0x00001F",
    })
    expect(modal:isSelectionMode()).toBe(false)
    expect(modal._rangeStart).toBe(0x10)
    expect(modal._rangeEnd).toBe(0x1F)
    expect(modal._hasCommittedRange).toBe(false)

    modal:_onGridSelect(0x40, { fromGrid = true })
    modal:_onGridSelect(0x4F, { fromGrid = true })
    expect(modal._hasCommittedRange).toBe(true)
    modal:hide()
  end)

  it("selection mode OFF allows manual two-click ranges without scan marks", function()
    local modal = PPUFrameRangeModal.new()
    modal:show({
      romRaw = string.rep("\0", 256),
      codec = "konami",
    })
    expect(modal:isSelectionMode()).toBe(false)
    expect(#(modal.hexGrid:getUnderlinedStarts())).toBe(0)
    expect(modal._hasCommittedRange).toBe(false)

    modal:_onGridSelect(0x40, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(0x40)
    expect(modal.startField:getText()).toBe("0x000040")
    expect(modal.endField:getText()).toBe("0x000040")
    expect(#(modal.hexGrid:getSelectedStarts())).toBe(0)
    expect(modal.hexGrid:getUnderlinedStarts()).toEqual({ 0x40 })
    expect(modal.hexGrid:getUnderlinedGroupSize(0x40)).toBe(1)
    expect(modal._hasCommittedRange).toBe(false)

    modal:_onGridSelect(0x4F, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(nil)
    expect(modal._rangeStart).toBe(0x40)
    expect(modal._rangeEnd).toBe(0x4F)
    expect(modal.startField:getText()).toBe("0x000040")
    expect(modal.endField:getText()).toBe("0x00004F")
    expect(modal.hexGrid:getSelectedGroupSize(0x40)).toBe(0x10)
    expect(#(modal.hexGrid:getUnderlinedStarts())).toBe(0)
    expect(modal._hasCommittedRange).toBe(true)

    -- Click inside committed range → starts a new anchor (not a no-op).
    modal:_onGridSelect(0x45, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(0x45)
    expect(modal._rangeStart).toBe(nil)
    expect(modal._rangeEnd).toBe(nil)
    expect(#(modal.hexGrid:getSelectedStarts())).toBe(0)
    expect(modal.hexGrid:getUnderlinedGroupSize(0x45)).toBe(1)

    -- Same-cell second click clears.
    modal:_onGridSelect(0x45, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(nil)
    expect(#(modal.hexGrid:getSelectedStarts())).toBe(0)

    -- Right-click clears a mid-range provisional before commit.
    modal:_onGridSelect(0x20, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(0x20)
    modal.hexGrid:setPosition(0, 0)
    local hx = 2 + 38 + 0 * 15 + 2
    local hy = 2 + 12 + 2 * 11 + 2 -- addr 0x20 on page 0
    expect(modal.hexGrid:contains(hx, hy)).toBe(true)
    modal:mousepressed(hx, hy, 2)
    expect(modal._rangeAnchor).toBe(nil)
    expect(#(modal.hexGrid:getUnderlinedStarts())).toBe(0)

    -- Outside / anywhere also just starts a new two-click.
    modal:_onGridSelect(0x20, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(0x20)
    modal:_onGridSelect(0x20, { fromGrid = true })
    expect(modal._rangeAnchor).toBe(nil)

    modal:_onGridSelect(0x50, { fromGrid = true })
    modal:_onGridSelect(0x40, { fromGrid = true })
    expect(modal.startField:getText()).toBe("0x000040")
    expect(modal.endField:getText()).toBe("0x000050")
    modal:hide()
  end)

  it("selection mode ON scans once and only selects whole scanned streams", function()
    local rom, pad, streamLen = plantStreamRom(9)
    local modal = PPUFrameRangeModal.new()
    modal:show({ romRaw = rom, codec = "konami" })
    expect(#(modal.hexGrid:getUnderlinedStarts())).toBe(0)

    modal.selectionModeCheckbox:setChecked(true)
    expect(modal:isSelectionMode()).toBe(true)
    expect(modal._scanComputed).toBe(true)
    local underlined = modal.hexGrid:getUnderlinedStarts()
    expect(#underlined).toBeGreaterThan(0)
    expect(modal.hexGrid:getUnderlinedGroupSize(pad)).toBe(streamLen)

    -- Mid-stream click selects the whole hit + marks clicked cell user-selected.
    modal:_onGridSelect(pad + 4, { fromGrid = true })
    expect(modal._rangeStart).toBe(pad)
    expect(modal._rangeEnd).toBe(pad + streamLen - 1)
    expect(modal.hexGrid:getSelectedGroupSize(pad)).toBe(streamLen)
    expect(modal.hexGrid:getUserSelectedStarts()).toEqual({ pad + 4 })
    expect(modal.shapePreview:isActive()).toBe(true)
    expect(#(modal.hexGrid:getUnderlinedStarts())).toBe(#underlined)
    -- Selected fill keeps the scan hit highlight color (not forced red).
    local selectedFill = modal.hexGrid:_selectedFillColorForStart(pad)
    local scanTint = modal.hexGrid:highlightColorForStart(pad)
    expect(selectedFill[1]).toBe(scanTint[1])
    expect(selectedFill[2]).toBe(scanTint[2])
    expect(selectedFill[3]).toBe(scanTint[3])

    -- Click same scanned range again → toggles selection off.
    modal:_onGridSelect(pad + 2, { fromGrid = true })
    expect(modal._rangeStart).toBe(nil)
    expect(modal._rangeEnd).toBe(nil)
    expect(#(modal.hexGrid:getSelectedStarts())).toBe(0)
    expect(#(modal.hexGrid:getUserSelectedStarts())).toBe(0)

    -- Select again for the rest of the assertions.
    modal:_onGridSelect(pad + 4, { fromGrid = true })
    expect(modal._rangeStart).toBe(pad)
    expect(modal._rangeEnd).toBe(pad + streamLen - 1)

    -- Outside any scan hit → no-op (keeps prior selection).
    modal:_onGridSelect(0x08, { fromGrid = true })
    expect(modal._rangeStart).toBe(pad)
    expect(modal._rangeEnd).toBe(pad + streamLen - 1)

    -- Clicking another cell in the same hit toggles off (not a partial re-pick).
    modal:_onGridSelect(pad + 2, { fromGrid = true })
    expect(modal._rangeStart).toBe(nil)
    modal:_onGridSelect(pad + 2, { fromGrid = true })
    expect(modal._rangeStart).toBe(pad)
    expect(modal._rangeEnd).toBe(pad + streamLen - 1)

    -- Re-toggle: scan is not recomputed.
    local hitsBefore = modal.scanHits
    modal.selectionModeCheckbox:setChecked(false)
    expect(#(modal.hexGrid:getUnderlinedStarts())).toBe(0)
    expect(modal._rangeStart).toBe(nil)
    modal.selectionModeCheckbox:setChecked(true)
    expect(modal.scanHits).toBe(hitsBefore)
    expect(modal._scanComputed).toBe(true)
    expect(#(modal.hexGrid:getUnderlinedStarts())).toBe(#underlined)
    modal:hide()
  end)

  it("manual complete range shows cached shape preview; incomplete does not", function()
    local rom, pad, streamLen = plantStreamRom(3)
    local modal = PPUFrameRangeModal.new()
    modal:show({ romRaw = rom, codec = "konami" })

    -- Partial span is not a complete page → no shape.
    modal:_onGridSelect(pad + 2, { fromGrid = true })
    modal:_onGridSelect(pad + 10, { fromGrid = true })
    expect(modal.shapePreview:isActive()).toBe(false)

    -- Exact complete stream → shape + cache entry.
    modal:_onGridSelect(pad, { fromGrid = true })
    modal:_onGridSelect(pad + streamLen - 1, { fromGrid = true })
    expect(modal._rangeStart).toBe(pad)
    expect(modal._rangeEnd).toBe(pad + streamLen - 1)
    expect(modal.shapePreview:isActive()).toBe(true)
    local key = string.format("%d:%d:konami", pad, pad + streamLen - 1)
    expect(type(modal._shapeCache[key]) == "table").toBe(true)

    -- Second refresh hits cache (same table).
    local cached = modal._shapeCache[key]
    modal:_refreshShapePreview(pad, pad + streamLen - 1)
    expect(modal._shapeCache[key]).toBe(cached)
    expect(modal.shapePreview:isActive()).toBe(true)
    modal:hide()
  end)
end)
