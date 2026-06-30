local NametableUtils = require("utils.nametable_utils")

local function read_fixture_hex(name)
  local path = "fixtures/" .. name
  local f = io.open(path, "r")
  if not f then
    error("missing fixture: " .. path)
  end
  local text = f:read("*a")
  f:close()
  return NametableUtils.hex_to_bytes(text)
end

describe("zelda2.lua codec", function()
  it("decodes the documented Game Over compressed stream", function()
    local compressed = read_fixture_hex("zelda2_game_over_compressed.hex")
    expect(#compressed).toBe(201)

    local nt, at, meta = NametableUtils.decode_compressed_nametable(compressed, false, "zelda2")
    expect(#nt).toBe(960)
    expect(#at).toBe(64)
    expect(meta.totalPageWrites).toBeGreaterThan(100)
    expect(meta.uniquePageWrites).toBeGreaterThan(100)

    local f4Count, ffCount = 0, 0
    for i = 1, #nt do
      if nt[i] == 0xF4 then
        f4Count = f4Count + 1
      elseif nt[i] == 0xFF then
        ffCount = ffCount + 1
      end
    end
    expect(f4Count).toBeGreaterThan(700)
    expect(ffCount).toBeGreaterThan(100)
  end)

  it("uses F4 nametable and 00 attribute defaults before applying the macro stream", function()
    local compressed = { 0xFF }
    local nt, at = NametableUtils.decode_compressed_nametable(compressed, false, "zelda2")
    for i = 1, 960 do
      expect(nt[i]).toBe(0xF4)
    end
    for i = 1, 64 do
      expect(at[i]).toBe(0x00)
    end
  end)

  it("decodes horizontal repeat commands (ctrl 0x40-0x7F)", function()
    -- $2000: repeat tile $AA eight times to the right
    local compressed = { 0x20, 0x00, 0x48, 0xAA, 0xFF }
    local nt = NametableUtils.decode_compressed_nametable(compressed, false, "zelda2")
    for i = 1, 8 do
      expect(nt[i]).toBe(0xAA)
    end
    expect(nt[9]).toBe(0xF4)
  end)

  it("decodes vertical literal commands (ctrl 0x80+)", function()
    -- $2000: three bytes written downward
    local compressed = { 0x20, 0x00, 0x83, 0x11, 0x22, 0x33, 0xFF }
    local nt = NametableUtils.decode_compressed_nametable(compressed, false, "zelda2")
    expect(nt[1]).toBe(0x11)
    expect(nt[33]).toBe(0x22)
    expect(nt[65]).toBe(0x33)
  end)

  it("round-trips synthetic nametable data", function()
    local nt = {}
    for i = 1, 960 do
      nt[i] = (i % 251)
    end
    local at = {}
    for i = 1, 64 do
      at[i] = i % 4
    end

    local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "zelda2")
    expect(compressed[#compressed]).toBe(0xFF)

    local decodedNt, decodedAt = NametableUtils.decode_compressed_nametable(compressed, false, "zelda2")
    for i = 1, 960 do
      expect(decodedNt[i]).toBe(nt[i])
    end
    for i = 1, 64 do
      expect(decodedAt[i]).toBe(at[i])
    end
  end)

  it("round-trips the Game Over fixture after decode", function()
    local compressed = read_fixture_hex("zelda2_game_over_compressed.hex")
    local nt, at = NametableUtils.decode_compressed_nametable(compressed, false, "zelda2")
    local recompressed = NametableUtils.encode_decompressed_nametable(nt, at, "zelda2")
    local nt2, at2 = NametableUtils.decode_compressed_nametable(recompressed, false, "zelda2")

    for i = 1, 960 do
      expect(nt2[i]).toBe(nt[i])
    end
    for i = 1, 64 do
      expect(at2[i]).toBe(at[i])
    end
  end)

  it("re-encodes Game Over compactly (not full-grid expansion)", function()
    local compressed = read_fixture_hex("zelda2_game_over_compressed.hex")
    local nt, at = NametableUtils.decode_compressed_nametable(compressed, false, "zelda2")
    local recompressed = NametableUtils.encode_decompressed_nametable(nt, at, "zelda2", compressed)
    expect(#recompressed).toBe(201)
  end)

  it("keeps the original command start address when re-encoding horizontal spans", function()
    local compressed = read_fixture_hex("zelda2_game_over_compressed.hex")
    local nt, at = NametableUtils.decode_compressed_nametable(compressed, false, "zelda2")

    local row = 21
    nt[row * 32 + 8 + 1] = 0x30
    nt[row * 32 + 14 + 1] = 0xF4
    nt[row * 32 + 15 + 1] = 0xF4

    local patched = NametableUtils.encode_decompressed_nametable(nt, at, "zelda2", compressed)
    expect(patched[65]).toBe(0x22)
    expect(patched[66]).toBe(0xA9)

    local nt2, at2 = NametableUtils.decode_compressed_nametable(patched, false, "zelda2")
    expect(nt2[row * 32 + 14 + 1]).toBe(0xF4)
    expect(nt2[row * 32 + 15 + 1]).toBe(0xF4)
    for i = 1, 960 do
      expect(nt2[i]).toBe(nt[i])
    end
    for i = 1, 64 do
      expect(at2[i]).toBe(at[i])
    end
  end)

  it("round-trips Game Over after editing tiles past a horizontal repeat span", function()
    local compressed = read_fixture_hex("zelda2_game_over_compressed.hex")
    local nt, at = NametableUtils.decode_compressed_nametable(compressed, false, "zelda2")

    local row = 21
    nt[row * 32 + 14 + 1] = 0xF4
    nt[row * 32 + 15 + 1] = 0xF4
    nt[row * 32 + 19 + 1] = 0x36
    nt[row * 32 + 20 + 1] = 0x36

    local patched = NametableUtils.encode_decompressed_nametable(nt, at, "zelda2", compressed)
    local nt2, at2 = NametableUtils.decode_compressed_nametable(patched, false, "zelda2")

    expect(nt2[row * 32 + 14 + 1]).toBe(0xF4)
    expect(nt2[row * 32 + 15 + 1]).toBe(0xF4)
    for i = 1, 960 do
      expect(nt2[i]).toBe(nt[i])
    end
    for i = 1, 64 do
      expect(at2[i]).toBe(at[i])
    end
  end)

  it("patches Game Over with a small size increase for a single tile edit", function()
    local compressed = read_fixture_hex("zelda2_game_over_compressed.hex")
    local nt, at = NametableUtils.decode_compressed_nametable(compressed, false, "zelda2")

    local row = 21
    for col = 9, 13 do
      if nt[row * 32 + col + 1] == 0x30 and nt[row * 32 + col + 2] == 0x31 then
        nt[row * 32 + col + 2] = 0x30
        break
      end
    end

    local patched = NametableUtils.encode_decompressed_nametable(nt, at, "zelda2", compressed)
    expect(#patched).toBe(201)

    local nt2, at2 = NametableUtils.decode_compressed_nametable(patched, false, "zelda2")
    for i = 1, 960 do
      expect(nt2[i]).toBe(nt[i])
    end
    for i = 1, 64 do
      expect(at2[i]).toBe(at[i])
    end
  end)
end)
