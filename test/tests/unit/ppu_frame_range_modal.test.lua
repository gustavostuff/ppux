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
  it("hitsToMinimapMarkers spans each complete stream", function()
    local markers = PPUFrameRangeModal._hitsToMinimapMarkers({
      { start = 0x100, ["end"] = 0x10F, score = 1 },
      { start = 0x200, ["end"] = 0x2FF, score = 2 },
    })
    expect(#markers).toBe(2)
    expect(markers[1].offset).toBe(0x100)
    expect(markers[1].groupSize).toBe(0x10)
    expect(markers[2].offset).toBe(0x200)
    expect(markers[2].groupSize).toBe(0x100)
  end)

  it("opens without stream markers and Scan fills them", function()
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
      initialStartAddress = string.format("0x%06X", pad),
      initialEndAddress = string.format("0x%06X", pad + #compressed - 1),
    })
    expect(#(modal.hexGrid.minimapMarkers or {})).toBe(0)

    modal:_runScan()
    expect(#(modal.scanHits or {})).toBeGreaterThan(0)
    expect(#(modal.hexGrid.minimapMarkers or {})).toBeGreaterThan(0)

    local found = false
    for _, m in ipairs(modal.hexGrid.minimapMarkers) do
      if m.offset == pad and m.groupSize == #compressed then
        found = true
        break
      end
    end
    expect(found).toBe(true)
    modal:hide()
  end)
end)
