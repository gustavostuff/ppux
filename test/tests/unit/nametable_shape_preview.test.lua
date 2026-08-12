-- nametable_shape_preview.test.lua

local ShapePreview = require("ui.nametable_shape_preview")
local NametableUtils = require("utils.nametable_utils")

describe("nametable_shape_preview.lua", function()
  it("maps most-repeated tile to black and rarer counts toward white", function()
    local nt = {}
    -- 500 of tile 0x10, 300 of 0x20, 160 of 0x30
    for i = 1, 500 do nt[i] = 0x10 end
    for i = 501, 800 do nt[i] = 0x20 end
    for i = 801, 960 do nt[i] = 0x30 end

    local shade = ShapePreview.luminanceByFrequency(nt)
    expect(shade[0x10]).toBe(0)
    expect(shade[0x20]).toBe(0.5)
    expect(shade[0x30]).toBe(1)
    expect(shade[0x20] < shade[0x30]).toBe(true)
  end)

  it("quantizes luminance to five discrete grays including black and white", function()
    local nt = {}
    -- Counts 320/256/192/128/64 → luminances 0, 0.25, 0.5, 0.75, 1 before/after quantize.
    local sizes = { 320, 256, 192, 128, 64 }
    local tiles = { 0x11, 0x22, 0x33, 0x44, 0x55 }
    local at = 1
    for i, n in ipairs(sizes) do
      for _ = 1, n do
        nt[at] = tiles[i]
        at = at + 1
      end
    end
    expect(#nt).toBe(960)
    local shade = ShapePreview.luminanceByFrequency(nt)
    expect(shade[0x11]).toBe(0)
    expect(shade[0x22]).toBe(0.25)
    expect(shade[0x33]).toBe(0.5)
    expect(shade[0x44]).toBe(0.75)
    expect(shade[0x55]).toBe(1)
  end)

  it("gives equal-frequency tiles the same shade (no tile-ID gradient)", function()
    local nt = {}
    for i = 1, 960 do
      -- Dominant background, then many unique tiles each used once.
      if i <= 900 then
        nt[i] = 0x00
      else
        nt[i] = (i - 900) -- 1..60, each once
      end
    end
    local shade = ShapePreview.luminanceByFrequency(nt)
    expect(shade[0x00]).toBe(0)
    expect(shade[1]).toBe(1)
    expect(shade[2]).toBe(1)
    expect(shade[60]).toBe(1)
  end)

  it("builds a 960-luminance grid from a decoded stream", function()
    local nt = {}
    local at = {}
    for i = 1, 960 do nt[i] = (i % 3 == 0) and 0xAA or 0x01 end
    for i = 1, 64 do at[i] = 0 end
    local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
    local decoded = NametableUtils.decode_compressed_nametable(compressed, false, "konami")
    local grid = ShapePreview.buildLuminanceGrid(decoded)
    expect(#grid).toBe(960)
    expect(grid[1] >= 0 and grid[1] <= 1).toBe(true)
  end)

  it("setFromStream activates preview for a complete planted stream", function()
    local nt = {}
    local at = {}
    for i = 1, 960 do nt[i] = (i - 1) % 16 end
    for i = 1, 64 do at[i] = 0 end
    local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
    local parts = {}
    for i = 1, #compressed do
      parts[i] = string.char(compressed[i] % 256)
    end
    local rom = table.concat(parts)

    local preview = ShapePreview.new()
    local ok = preview:setFromStream(rom, 0, #compressed - 1, "konami")
    expect(ok).toBe(true)
    expect(preview:isActive()).toBe(true)
    preview:clear()
    expect(preview:isActive()).toBe(false)
  end)
end)
