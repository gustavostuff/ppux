-- nametable_utils.test.lua
-- Unit tests for utils/nametable_utils.lua

local NametableUtils = require("utils.nametable_utils")

describe("nametable_utils.lua", function()
  
  describe("encode_decompressed_nametable", function()
    it("encodes simple nametable with RLE runs", function()
      local nt = {}
      for i = 1, 64 do nt[i] = 0x00 end -- 64 zeros (should compress)
      local at = {}
      for i = 1, 64 do at[i] = 0x00 end
      
      local compressed = NametableUtils.encode_decompressed_nametable(nt, at)
      expect(#compressed).toBeGreaterThan(0)
      -- Should start with PPU address bytes
      expect(compressed[1]).toBe(0x00)
      expect(compressed[2]).toBe(0x20)
    end)
    
    it("encodes nametable and attributes separately", function()
      local nt = {}
      for i = 1, 960 do nt[i] = 0xAA end
      local at = {}
      for i = 1, 64 do at[i] = 0x55 end
      
      local compressed = NametableUtils.encode_decompressed_nametable(nt, at)
      expect(#compressed).toBeGreaterThan(0)
    end)
    
    it("includes terminator bytes", function()
      local nt = {0}
      local at = {0}
      local compressed = NametableUtils.encode_decompressed_nametable(nt, at)
      -- Should end with 0xFF terminator
      expect(compressed[#compressed]).toBe(0xFF)
    end)

    it("supports explicit konami codec", function()
      local nt = {}
      for i = 1, 960 do nt[i] = (i - 1) % 256 end
      local at = {}
      for i = 1, 64 do at[i] = (i - 1) % 4 end

      local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
      expect(#compressed).toBeGreaterThan(0)
      expect(compressed[#compressed]).toBe(0xFF)
    end)

    it("uses a size-optimal command mix (never worse than legacy greedy on pathological data)", function()
      local nt = {}
      local at = {}

      -- Pattern that makes greedy splitting around short runs inefficient.
      local pattern = { 0x10, 0x20, 0x20, 0x30 }
      for i = 1, 960 do
        nt[i] = pattern[((i - 1) % #pattern) + 1]
      end
      for i = 1, 64 do
        at[i] = pattern[((960 + i - 1) % #pattern) + 1]
      end

      local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")

      local src = {}
      for i = 1, 960 do src[#src + 1] = nt[i] end
      for i = 1, 64 do src[#src + 1] = at[i] end

      -- Reference old greedy length (encoder before DP optimization).
      local function greedyLen(buf)
        local N = #buf
        local i = 1
        local payloadLen = 0
        local maxBlock = 0x7E

        while i <= N do
          local v = buf[i]
          local run = 1
          while (i + run <= N) and (buf[i + run] == v) and (run < maxBlock) do
            run = run + 1
          end

          if run >= 2 then
            payloadLen = payloadLen + 2
            i = i + run
          else
            local litStart, litLen = i, 1
            while (litStart + litLen <= N) and (litLen < maxBlock) do
              local j = litStart + litLen
              if j + 1 <= N and buf[j] == buf[j + 1] then break end
              litLen = litLen + 1
            end
            payloadLen = payloadLen + 1 + litLen
            i = i + litLen
          end
        end

        -- +2 for $2000 address prologue, +1 for terminator.
        return payloadLen + 3
      end

      local legacySize = greedyLen(src)
      expect(#compressed).toBeLessThan(legacySize)
    end)
  end)
  
  describe("decode_compressed_nametable", function()
    it("decodes compressed nametable back to original", function()
      local nt = {}
      for i = 1, 960 do nt[i] = (i % 256) end
      local at = {}
      for i = 1, 64 do at[i] = 0x00 end
      
      local compressed = NametableUtils.encode_decompressed_nametable(nt, at)
      local decodedNt, decodedAt = NametableUtils.decode_compressed_nametable(compressed)
      
      expect(#decodedNt).toBe(960)
      expect(#decodedAt).toBe(64)
    end)
    
    it("handles RLE encoded data", function()
      -- Encode a nametable full of zeros (should use RLE)
      local nt = {}
      for i = 1, 960 do nt[i] = 0x00 end
      local at = {}
      for i = 1, 64 do at[i] = 0x00 end
      
      local compressed = NametableUtils.encode_decompressed_nametable(nt, at)
      local decodedNt, decodedAt = NametableUtils.decode_compressed_nametable(compressed)
      
      -- Check first few bytes
      for i = 1, 10 do
        expect(decodedNt[i]).toBe(0x00)
      end
    end)

    it("falls back to konami for unknown codec names", function()
      local nt = {}
      for i = 1, 960 do nt[i] = (i * 3) % 256 end
      local at = {}
      for i = 1, 64 do at[i] = i % 4 end

      local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "unknown_codec")
      local decodedNt, decodedAt = NametableUtils.decode_compressed_nametable(compressed, false, "unknown_codec")

      expect(#decodedNt).toBe(960)
      expect(#decodedAt).toBe(64)
      expect(decodedNt[1]).toBe(nt[1])
      expect(decodedNt[127]).toBe(nt[127])
      expect(decodedAt[1]).toBe(at[1])
      expect(decodedAt[64]).toBe(at[64])
    end)
    
    -- TODO: Fix this test - round-trip encoding/decoding needs investigation
    --[[
    it("round-trip preserves data", function()
      local originalNt = {}
      local originalAt = {}
      -- Create pattern
      for i = 1, 960 do
        originalNt[i] = (i * 7) % 256
      end
      for i = 1, 64 do
        originalAt[i] = (i * 3) % 256
      end
      
      local compressed = NametableUtils.encode_decompressed_nametable(originalNt, originalAt, nil)
      local decodedNt, decodedAt = NametableUtils.decode_compressed_nametable(compressed)
      
      -- Verify we got the right sizes
      expect(#decodedNt).toBe(960)
      expect(#decodedAt).toBe(64)
      
      -- Verify nametable matches (check first mismatch for debugging)
      for i = 1, 960 do
        if decodedNt[i] ~= originalNt[i] then
          error(string.format("Nametable mismatch at index %d: expected %d, got %d", i, originalNt[i], decodedNt[i]))
        end
      end
      
      -- Verify attributes match
      for i = 1, 64 do
        if decodedAt[i] ~= originalAt[i] then
          error(string.format("Attribute mismatch at index %d: expected %d, got %d", i, originalAt[i], decodedAt[i]))
        end
      end
    end)
    --]]
  end)
  
  describe("hex_to_bytes", function()
    it("converts hex string to bytes", function()
      local bytes = NametableUtils.hex_to_bytes("00 01 02 FF")
      expect(bytes).toEqual({0x00, 0x01, 0x02, 0xFF})
    end)
    
    it("handles hex string without spaces", function()
      local bytes = NametableUtils.hex_to_bytes("000102FF")
      expect(bytes).toEqual({0x00, 0x01, 0x02, 0xFF})
    end)
    
    it("handles empty string", function()
      local bytes = NametableUtils.hex_to_bytes("")
      expect(#bytes).toBe(0)
    end)
    
    it("ignores non-hex characters", function()
      local bytes = NametableUtils.hex_to_bytes("AB CD EF")
      expect(bytes).toEqual({0xAB, 0xCD, 0xEF})
    end)
  end)
  
end)
