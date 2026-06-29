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
end)
