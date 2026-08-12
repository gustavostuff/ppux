-- konami_nt_scanner.test.lua
-- Unit tests for scanners/konami_nt_scanner.lua

local NametableUtils = require("utils.nametable_utils")
local Scanner = require("scanners.konami_nt_scanner")
local NtScanners = require("scanners")

local function buildFullPage(seed)
  seed = seed or 0
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

local function plantAt(romSize, offset, bytes, fill)
  fill = fill or 0x11
  local buf = {}
  for i = 1, romSize do
    buf[i] = fill
  end
  for i = 1, #bytes do
    buf[offset + i] = bytes[i] % 256
  end
  return bytesToRomString(buf)
end

describe("konami_nt_scanner.lua", function()
  describe("isKonamiCandidateStart", function()
    it("accepts 00 20 followed by a data opcode", function()
      local rom = string.char(0x00, 0x20, 0x80, 0x01, 0xFF)
      expect(Scanner.isKonamiCandidateStart(rom, 0)).toBe(true)
    end)

    it("rejects 00 20 FF / 00 20 00", function()
      expect(Scanner.isKonamiCandidateStart(string.char(0x00, 0x20, 0xFF), 0)).toBe(false)
      expect(Scanner.isKonamiCandidateStart(string.char(0x00, 0x20, 0x00), 0)).toBe(false)
    end)
  end)

  describe("boundKonamiStream", function()
    it("bounds a planted encode through FF", function()
      local nt, at = buildFullPage(7)
      local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
      local rom = bytesToRomString(compressed)
      local endAddr = Scanner.boundKonamiStream(rom, 0, 4096)
      expect(endAddr).toBe(#compressed - 1)
      expect(string.byte(rom, endAddr + 1)).toBe(0xFF)
    end)
  end)

  describe("scan", function()
    it("finds a planted complete Konami stream", function()
      local nt, at = buildFullPage(3)
      local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
      local _, _, meta = NametableUtils.decode_compressed_nametable(compressed, false, "konami")
      expect(meta.complete).toBe(true)

      local pad = 64
      local rom = plantAt(pad + #compressed + 32, pad, compressed, 0x3C)
      local hits = Scanner.scan(rom, { codec = "konami" })
      expect(#hits).toBeGreaterThan(0)

      local found = nil
      for _, hit in ipairs(hits) do
        if hit.start == pad and hit["end"] == pad + #compressed - 1 then
          found = hit
          break
        end
      end
      expect(found).toBeTruthy()
      expect(found.uniquePageWrites).toBe(1024)
      expect(found.totalPageWrites <= 1024).toBe(true)
    end)

    it("rejects incomplete streams that terminate early", function()
      -- Valid SET + short RLE + FF: nowhere near a full page.
      local incomplete = { 0x00, 0x20, 0x04, 0xAA, 0xFF }
      local rom = plantAt(128, 16, incomplete, 0x55)
      local hits = Scanner.scan(rom, { codec = "konami" })
      for _, hit in ipairs(hits) do
        expect(hit.start == 16).toBe(false)
      end
    end)

    it("ignores non-konami codecs for now", function()
      local nt, at = buildFullPage(1)
      local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
      local rom = bytesToRomString(compressed)
      local hits = Scanner.scan(rom, { codec = "zelda2" })
      expect(#hits).toBe(0)
      expect(NtScanners.supports("konami")).toBe(true)
      expect(NtScanners.supports("zelda2")).toBe(false)
      expect(#(NtScanners.scan(rom, { codec = "zelda2" }))).toBe(0)
    end)

    it("recalls Contra DB title-screen range when planted at DB offsets", function()
      -- Addresses from db/contra_japan.lua (title nametable layer).
      local dbStart = 0x012493
      local dbEnd = 0x01255A
      local nt, at = buildFullPage(21)
      local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
      -- Plant at DB start; end may differ from real Contra bytes — recall is by start
      -- and completeness, with false-positive noise elsewhere.
      local romSize = dbStart + math.max(#compressed, dbEnd - dbStart + 1) + 64
      local rom = plantAt(romSize, dbStart, compressed, 0x00)

      -- Sprinkle false-looking candidates that do not fill a page.
      local noise = { 0x00, 0x20, 0x02, 0x11, 0xFF }
      local noiseAt = 0x010000
      local decoyAt = dbStart - 32
      local buf = {}
      for i = 1, #rom do
        buf[i] = string.byte(rom, i)
      end
      for i = 1, #noise do
        buf[noiseAt + i] = noise[i]
      end
      if decoyAt > 0 then
        for i = 1, #noise do
          buf[decoyAt + i] = noise[i]
        end
      end
      rom = bytesToRomString(buf)

      local hits = Scanner.scan(rom, { codec = "konami" })
      local recalled = nil
      for _, hit in ipairs(hits) do
        if hit.start == dbStart then
          recalled = hit
          break
        end
      end
      expect(recalled).toBeTruthy()
      expect(recalled["end"]).toBe(dbStart + #compressed - 1)

      -- Decoy incomplete streams must not appear as hits.
      for _, hit in ipairs(hits) do
        expect(hit.start == noiseAt).toBe(false)
        expect(hit.start == decoyAt).toBe(false)
      end
    end)

    it("hitAt prefers exact start over containing", function()
      local hits = {
        { start = 100, ["end"] = 150, score = 1 },
        { start = 120, ["end"] = 140, score = 2 },
      }
      local exact = Scanner.hitAt(hits, 120)
      expect(exact.start).toBe(120)
      local containing = Scanner.hitAt(hits, 110)
      expect(containing.start).toBe(100)
    end)

    it("dedupeOverlapping keeps higher-score / longer hits only", function()
      local kept = Scanner.dedupeOverlapping({
        { start = 0, ["end"] = 99, score = 10 },
        { start = 50, ["end"] = 60, score = 99 }, -- nested, higher score wins
        { start = 200, ["end"] = 210, score = 1 },
        { start = 205, ["end"] = 220, score = 1 }, -- overlap, longer wins after equal score
      })
      expect(#kept).toBe(2)
      expect(kept[1].start).toBe(50)
      expect(kept[1]["end"]).toBe(60)
      expect(kept[2].start).toBe(205)
      expect(kept[2]["end"]).toBe(220)
    end)
  end)
end)
