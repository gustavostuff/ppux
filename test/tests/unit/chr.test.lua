-- chr.test.lua
-- Unit tests for chr.lua

local chr = require("chr")

describe("chr.lua", function()
  
  describe("stringToBytes", function()
    it("converts string to byte array", function()
      local result = chr.stringToBytes("ABC")
      expect(result).toEqual({65, 66, 67})
    end)
    
    it("handles empty string", function()
      local result = chr.stringToBytes("")
      expect(result).toEqual({})
    end)
    
    it("handles single character", function()
      local result = chr.stringToBytes("X")
      expect(result).toEqual({88})
    end)
  end)
  
  describe("bytesToString", function()
    it("converts byte array to string", function()
      local result = chr.bytesToString({65, 66, 67})
      expect(result).toBe("ABC")
    end)
    
    it("handles empty array", function()
      local result = chr.bytesToString({})
      expect(result).toBe("")
    end)
    
    it("handles single byte", function()
      local result = chr.bytesToString({65})
      expect(result).toBe("A")
    end)
  end)
  
  describe("decimalToHex", function()
    it("converts decimal to hex string", function()
      expect(chr.decimalToHex(0)).toBe("00")
      expect(chr.decimalToHex(255)).toBe("FF")
      expect(chr.decimalToHex(15)).toBe("0F")
      expect(chr.decimalToHex(170)).toBe("AA")
    end)
  end)
  
  describe("readByteFromAddress", function()
    it("reads byte at valid address", function()
      local rom = "ABCD"
      local byte, err = chr.readByteFromAddress(rom, 0)
      expect(err).toBeNil()
      expect(byte).toBe(65) -- 'A'
    end)
    
    it("returns error for out of range address", function()
      local rom = "ABC"
      local byte, err = chr.readByteFromAddress(rom, 100)
      expect(byte).toBeNil()
      expect(err).toBeTruthy()
    end)
    
    it("returns error for invalid romRaw type", function()
      local byte, err = chr.readByteFromAddress(123, 0)
      expect(byte).toBeNil()
      expect(err).toBeTruthy()
    end)
  end)
  
  describe("writeByteToAddress", function()
    it("writes byte at valid address", function()
      local rom = "ABCD"
      local newRom, err = chr.writeByteToAddress(rom, 1, 88) -- 'X'
      expect(err).toBeNil()
      expect(newRom).toBe("AXCD")
    end)
    
    it("writes byte at beginning", function()
      local rom = "ABC"
      local newRom = chr.writeByteToAddress(rom, 0, 88)
      expect(newRom).toBe("XBC")
    end)
    
    it("writes byte at end", function()
      local rom = "ABC"
      local newRom = chr.writeByteToAddress(rom, 2, 88)
      expect(newRom).toBe("ABX")
    end)
  end)
  
  describe("readBytesFromRange", function()
    it("reads bytes from valid range", function()
      local rom = "ABCDEF"
      local bytes, err = chr.readBytesFromRange(rom, 1, 3)
      expect(err).toBeNil()
      expect(bytes).toEqual({66, 67, 68}) -- 'B', 'C', 'D'
    end)
    
    it("reads single byte", function()
      local rom = "ABC"
      local bytes = chr.readBytesFromRange(rom, 0, 0)
      expect(bytes).toEqual({65}) -- 'A'
    end)
    
    it("handles reversed range", function()
      local rom = "ABCD"
      local bytes = chr.readBytesFromRange(rom, 2, 0)
      expect(bytes).toEqual({65, 66, 67}) -- 'A', 'B', 'C'
    end)
    
    it("returns error for out of range", function()
      local rom = "ABC"
      local bytes, err = chr.readBytesFromRange(rom, 0, 100)
      expect(bytes).toBeNil()
      expect(err).toBeTruthy()
    end)
  end)
  
  describe("writeBytesToRange", function()
    it("writes bytes to valid range", function()
      local rom = "ABCDEF"
      local newRom, err = chr.writeBytesToRange(rom, 1, 3, {88, 89, 90}) -- 'X', 'Y', 'Z'
      expect(err).toBeNil()
      expect(newRom).toBe("AXYZEF")
    end)
    
    it("writes bytes as string", function()
      local rom = "ABC"
      local newRom = chr.writeBytesToRange(rom, 0, 2, "XY")
      expect(newRom).toBe("XYC")
    end)
    
    it("pads with 0xFF if bytes are shorter", function()
      local rom = "ABCD"
      local newRom = chr.writeBytesToRange(rom, 0, 4, {88}) -- Only 1 byte
      expect(newRom:byte(1)).toBe(88)
      expect(newRom:byte(2)).toBe(255)
      expect(newRom:byte(3)).toBe(255)
      expect(newRom:byte(4)).toBe(255)
    end)
    
    it("returns original ROM if span is 0", function()
      local rom = "ABC"
      local newRom = chr.writeBytesToRange(rom, 0, 0, {88})
      expect(newRom).toBe(rom)
    end)
  end)
  
  describe("decodeTile", function()
    it("decodes a simple tile", function()
      -- Create a minimal CHR bank with a single tile
      -- Tile 0: simple pattern where all pixels are color 0
      local bank = string.rep(string.char(0), 16)
      local pixels, err = chr.decodeTile(bank, 0)
      expect(err).toBeNil()
      expect(#pixels).toBe(64) -- 8x8 = 64 pixels
      -- All pixels should be 0
      for i = 1, 64 do
        expect(pixels[i]).toBe(0)
      end
    end)
    
    it("returns error for out of range tile", function()
      local bank = string.rep(string.char(0), 16) -- Only 1 tile (16 bytes)
      local pixels, err = chr.decodeTile(bank, 1)
      expect(pixels).toBeNil()
      expect(err).toBeTruthy()
    end)
  end)
  
  describe("setTilePixel", function()
    it("sets pixel color in tile", function()
      -- Create a tile bank as a byte array
      local bankBytes = {}
      for i = 1, 16 do bankBytes[i] = 0 end
      
      -- Set pixel at (0, 0) to color 3
      chr.setTilePixel(bankBytes, 0, 0, 0, 3)
      
      -- Verify the bytes were modified
      -- Color 3 = binary 11, so both planes should have bit 7 set
      expect(bankBytes[1]).toBeGreaterThan(0) -- Plane 0, row 0
      expect(bankBytes[9]).toBeGreaterThan(0) -- Plane 1, row 0
    end)
  end)
  
  describe("parseINES", function()
    it("throws error for too small input", function()
      expect(function()
        chr.parseINES("ABC")
      end).toThrow("too small")
    end)
    
    it("throws error for invalid header", function()
      local invalidRom = string.rep(string.char(0), 100)
      expect(function()
        chr.parseINES(invalidRom)
      end).toThrow("valid iNES header")
    end)
  end)
  
  describe("concatBanksToString", function()
    it("concatenates multiple banks", function()
      local banks = {
        {65, 66}, -- "AB"
        {67, 68}, -- "CD"
      }
      local result = chr.concatBanksToString(banks)
      expect(result).toBe("ABCD")
    end)
    
    it("handles empty banks array", function()
      local result = chr.concatBanksToString({})
      expect(result).toBe("")
    end)
    
    it("handles single bank", function()
      local banks = {{65, 66}}
      local result = chr.concatBanksToString(banks)
      expect(result).toBe("AB")
    end)
  end)
  
end)

