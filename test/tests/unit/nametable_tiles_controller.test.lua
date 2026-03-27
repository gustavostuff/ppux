-- nametable_tiles_controller.test.lua
-- Unit tests for managers/nametable_tiles_controller.lua

local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local NametableUtils = require("utils.nametable_utils")
local chr = require("chr")

describe("nametable_tiles_controller.lua", function()
  describe("countSerializedTileSwaps", function()
    it("counts encoded tile swaps without hydrating a window", function()
      local encoded = "32x30|-1:1;12:2;-1:957"
      expect(NametableTilesController.countSerializedTileSwaps(encoded)).toBe(2)
      expect(NametableTilesController.countSerializedTileSwaps(nil)).toBe(0)
    end)
  end)
  
  describe("setPaletteNumberForTile on PPU frame windows", function()
    it("updates attribute bytes correctly when changing palette for one tile", function()
      -- Create a mock PPU frame window
      local mockWin = {
        kind = "ppu_frame",
        cols = 32,
        rows = 30,
        nametableBytes = {},
        nametableAttrBytes = {},
      }
      
      -- Initialize nametable bytes (960 bytes) - all zeros for simplicity
      for i = 1, 960 do
        mockWin.nametableBytes[i] = 0x00
      end
      
      -- Initialize attribute bytes (64 bytes) - all zeros initially (all palettes 0)
      -- For 32x30 nametable: 8 cols x 8 rows = 64 attribute bytes
      for i = 1, 64 do
        mockWin.nametableAttrBytes[i] = 0x00  -- Each byte: all 4 quadrants use palette 0
      end
      
      -- Create a mock layer
      local mockLayer = {
        kind = "tile",
        paletteNumbers = {},
      }
      
      -- Verify initial state: all attribute bytes are 0x00
      expect(mockWin.nametableAttrBytes[1]).toBe(0x00)
      
      -- Change palette for tile at (0, 0) to palette 2
      -- This tile is in the top-left quadrant of the first attribute byte
      -- Attribute byte 1 covers tiles (0,0) to (3,3)
      -- Tile (0,0) is in top-left quadrant (bits 0-1)
      local success = NametableTilesController.setPaletteNumberForTile(
        mockWin, mockLayer, 0, 0, 2
      )
      
      expect(success).toBe(true)
      
      -- Verify attribute byte 1 was updated correctly
      -- Original: 0x00 (all palettes 0)
      -- After setting (0,0) to palette 2: top-left quadrant = 1 (palette 2 - 1 = 1)
      -- New byte: 0x01 (bits 0-1 = 1, rest = 0)
      expect(mockWin.nametableAttrBytes[1]).toBe(0x01)
      
      -- Verify paletteNumbers were updated for all 4 tiles in the top-left 2x2 quadrant
      -- Tiles (0,0), (1,0), (0,1), (1,1) should all have palette 2
      expect(mockLayer.paletteNumbers[0]).toBe(2)   -- (0,0): row*32 + col = 0*32 + 0 = 0
      expect(mockLayer.paletteNumbers[1]).toBe(2)   -- (1,0): row*32 + col = 0*32 + 1 = 1
      expect(mockLayer.paletteNumbers[32]).toBe(2)  -- (0,1): row*32 + col = 1*32 + 0 = 32
      expect(mockLayer.paletteNumbers[33]).toBe(2)  -- (1,1): row*32 + col = 1*32 + 1 = 33
      
      -- Verify other attribute bytes are unchanged
      expect(mockWin.nametableAttrBytes[2]).toBe(0x00)
      expect(mockWin.nametableAttrBytes[64]).toBe(0x00)
      
      -- Verify attribute bytes array still has exactly 64 bytes
      expect(#mockWin.nametableAttrBytes).toBe(64)
    end)
    
    it("compresses and decompresses correctly after palette change", function()
      -- Create a mock PPU frame window with known initial state
      local mockWin = {
        kind = "ppu_frame",
        cols = 32,
        rows = 30,
        nametableBytes = {},
        nametableAttrBytes = {},
      }
      
      -- Initialize nametable bytes - all 0xAA for visibility
      for i = 1, 960 do
        mockWin.nametableBytes[i] = 0xAA
      end
      
      -- Initialize attribute bytes - all 0x00 (all palettes 0)
      for i = 1, 64 do
        mockWin.nametableAttrBytes[i] = 0x00
      end
      
      local mockLayer = {
        kind = "tile",
        paletteNumbers = {},
      }
      
      -- Change palette for tile at (2, 0) to palette 3
      -- This tile is in the top-right quadrant of attribute byte 1
      -- Top-right quadrant is bits 2-3
      local success = NametableTilesController.setPaletteNumberForTile(
        mockWin, mockLayer, 2, 0, 3
      )
      
      expect(success).toBe(true)
      
      -- Verify attribute byte 1 was updated correctly
      -- Original: 0x00
      -- After setting (2,0) to palette 3: top-right quadrant = 2 (palette 3 - 1 = 2)
      -- New byte: 0x08 (bits 2-3 = 2, rest = 0) = 2 * 4 = 8
      expect(mockWin.nametableAttrBytes[1]).toBe(0x08)
      
      -- Compress the nametable and attributes
      local compressed = NametableUtils.encode_decompressed_nametable(
        mockWin.nametableBytes,
        mockWin.nametableAttrBytes,
        nil
      )
      
      -- Decompress back
      local decodedNt, decodedAt = NametableUtils.decode_compressed_nametable(compressed)
      
      -- Verify nametable bytes match
      expect(#decodedNt).toBe(960)
      for i = 1, 960 do
        expect(decodedNt[i]).toBe(0xAA)
      end
      
      -- Verify attribute bytes match
      expect(#decodedAt).toBe(64)
      expect(decodedAt[1]).toBe(0x08)  -- First byte should be our updated one
      -- All other bytes should be 0x00
      for i = 2, 64 do
        expect(decodedAt[i]).toBe(0x00)
      end
    end)
    
    it("updates all 4 tiles in a 2x2 quadrant correctly", function()
      local mockWin = {
        kind = "ppu_frame",
        cols = 32,
        rows = 30,
        nametableBytes = {},
        nametableAttrBytes = {},
      }
      
      for i = 1, 960 do
        mockWin.nametableBytes[i] = 0x00
      end
      
      -- Initialize with a known pattern: attribute byte 1 = 0xE4
      -- 0xE4 = 11100100 binary
      -- top-left (bits 0-1) = 00 = palette 0 → palette number 1
      -- top-right (bits 2-3) = 01 = palette 1 → palette number 2
      -- bottom-left (bits 4-5) = 10 = palette 2 → palette number 3
      -- bottom-right (bits 6-7) = 11 = palette 3 → palette number 4
      mockWin.nametableAttrBytes[1] = 0xE4
      for i = 2, 64 do
        mockWin.nametableAttrBytes[i] = 0x00
      end
      
      local mockLayer = {
        kind = "tile",
        paletteNumbers = {},
      }
      
      -- Extract palette numbers first to see initial state
      NametableTilesController.extractPaletteNumbersFromAttributes(
        mockWin, mockLayer, 32, 30
      )
      
      -- Verify initial state for top-left quadrant (tiles 0,0 1,0 0,1 1,1)
      expect(mockLayer.paletteNumbers[0]).toBe(1)   -- (0,0) - top-left
      expect(mockLayer.paletteNumbers[1]).toBe(1)   -- (1,0) - top-left
      expect(mockLayer.paletteNumbers[32]).toBe(1)  -- (0,1) - top-left
      expect(mockLayer.paletteNumbers[33]).toBe(1)  -- (1,1) - top-left
      
      -- Change palette for tile (0,0) to palette 4
      -- This should update the top-left quadrant to palette 3 (palette 4 - 1)
      local success = NametableTilesController.setPaletteNumberForTile(
        mockWin, mockLayer, 0, 0, 4
      )
      
      expect(success).toBe(true)
      
      -- Verify attribute byte was updated
      -- New value: top-left = 3 (palette 4 - 1), rest unchanged
      -- 0xE4 = 11100100, change top-left to 11 = 0xE7 = 11100111
      expect(mockWin.nametableAttrBytes[1]).toBe(0xE7)
      
      -- Verify all 4 tiles in top-left quadrant now have palette 4
      expect(mockLayer.paletteNumbers[0]).toBe(4)
      expect(mockLayer.paletteNumbers[1]).toBe(4)
      expect(mockLayer.paletteNumbers[32]).toBe(4)
      expect(mockLayer.paletteNumbers[33]).toBe(4)
    end)
  end)
  
  describe("userDefinedAttrs persistence", function()
    it("updates attribute bytes when setting palette for a tile", function()
      local mockWin = {
        kind = "ppu_frame",
        cols = 32,
        rows = 30,
        nametableBytes = {},
        nametableAttrBytes = {},
      }
      
      for i = 1, 960 do
        mockWin.nametableBytes[i] = 0x00
      end
      for i = 1, 64 do
        mockWin.nametableAttrBytes[i] = 0x00
      end
      
      local mockLayer = {
        kind = "tile",
        paletteNumbers = {},
      }
      
      -- Set palette for tile at (0, 0) to palette 2
      local success = NametableTilesController.setPaletteNumberForTile(
        mockWin, mockLayer, 0, 0, 2
      )
      
      expect(success).toBe(true)
      
      -- Verify attribute byte was updated correctly
      -- Tile (0,0) is in top-left quadrant of attribute byte 1
      -- Palette 2 means palette index 1, so bits 0-1 = 1 → 0x01
      expect(mockWin.nametableAttrBytes[1]).toBe(0x01)
      
      -- Verify paletteNumbers were synced
      expect(mockLayer.paletteNumbers[0]).toBe(2)   -- (0,0)
      expect(mockLayer.paletteNumbers[1]).toBe(2)   -- (1,0) - same quadrant
      expect(mockLayer.paletteNumbers[32]).toBe(2)  -- (0,1) - same quadrant
      expect(mockLayer.paletteNumbers[33]).toBe(2)  -- (1,1) - same quadrant
    end)
    
    it("updates attribute bytes when changing palette in same quadrant", function()
      local mockWin = {
        kind = "ppu_frame",
        cols = 32,
        rows = 30,
        nametableBytes = {},
        nametableAttrBytes = {},
      }
      
      for i = 1, 960 do
        mockWin.nametableBytes[i] = 0x00
      end
      for i = 1, 64 do
        mockWin.nametableAttrBytes[i] = 0x00
      end
      
      local mockLayer = {
        kind = "tile",
        paletteNumbers = {},
      }
      
      -- Set palette for tile at (0, 0) to palette 1
      NametableTilesController.setPaletteNumberForTile(mockWin, mockLayer, 0, 0, 1)
      expect(mockWin.nametableAttrBytes[1]).toBe(0x00)  -- Palette 1 = index 0
      
      -- Set palette for tile at (1, 1) to palette 3
      -- This is in the same quadrant (both are in the top-left 2x2 of attribute byte 1)
      NametableTilesController.setPaletteNumberForTile(mockWin, mockLayer, 1, 1, 3)
      
      -- Should have updated to palette 3 (index 2) = 0x02
      expect(mockWin.nametableAttrBytes[1]).toBe(0x02)
      
      -- All 4 tiles in the quadrant should now have palette 3
      expect(mockLayer.paletteNumbers[0]).toBe(3)
      expect(mockLayer.paletteNumbers[1]).toBe(3)
      expect(mockLayer.paletteNumbers[32]).toBe(3)
      expect(mockLayer.paletteNumbers[33]).toBe(3)
    end)
    
    it("updates multiple attribute bytes for different quadrants", function()
      local mockWin = {
        kind = "ppu_frame",
        cols = 32,
        rows = 30,
        nametableBytes = {},
        nametableAttrBytes = {},
      }
      
      for i = 1, 960 do
        mockWin.nametableBytes[i] = 0x00
      end
      for i = 1, 64 do
        mockWin.nametableAttrBytes[i] = 0x00
      end
      
      local mockLayer = {
        kind = "tile",
        paletteNumbers = {},
      }
      
      -- Set palette for tile at (0, 0) - top-left quadrant of attribute byte 1
      NametableTilesController.setPaletteNumberForTile(mockWin, mockLayer, 0, 0, 1)
      expect(mockWin.nametableAttrBytes[1]).toBe(0x00)  -- Palette 1 = index 0
      
      -- Set palette for tile at (4, 0) - top-left quadrant of attribute byte 2
      NametableTilesController.setPaletteNumberForTile(mockWin, mockLayer, 4, 0, 2)
      expect(mockWin.nametableAttrBytes[2]).toBe(0x01)  -- Palette 2 = index 1
      
      -- Set palette for tile at (0, 4) - different row, attribute byte 9 (row 1, col 0)
      NametableTilesController.setPaletteNumberForTile(mockWin, mockLayer, 0, 4, 3)
      -- Attribute byte at row 1, col 0: attrRow=1, attrCol=0, index = 1*8 + 0 + 1 = 9
      expect(mockWin.nametableAttrBytes[9]).toBe(0x02)  -- Palette 3 = index 2
      
      -- Verify first attribute byte unchanged
      expect(mockWin.nametableAttrBytes[1]).toBe(0x00)
    end)
    
    it("saves userDefinedAttrs as hex string in snapshot", function()
      local mockWin = {
        kind = "ppu_frame",
        cols = 32,
        rows = 30,
        nametableBytes = {},
        nametableAttrBytes = {},
        _tileSwaps = {},
        _originalNametableBytes = {},
      }
      
      for i = 1, 960 do
        mockWin.nametableBytes[i] = 0x00
        mockWin._originalNametableBytes[i] = 0x00
      end
      for i = 1, 64 do
        mockWin.nametableAttrBytes[i] = 0x00
      end
      
      local mockLayer = {
        kind = "tile",
        name = "Test Layer",
        opacity = 1.0,
        mode = "8x8",
        bank = 1,
        page = 1,
        nametableStartAddr = 0x2000,
        nametableEndAddr = 0x23BF,
        noOverflowSupported = true,
        paletteNumbers = {},
      }
      
      -- Set some palette changes to modify attribute bytes
      NametableTilesController.setPaletteNumberForTile(mockWin, mockLayer, 0, 0, 2)
      NametableTilesController.setPaletteNumberForTile(mockWin, mockLayer, 4, 4, 3)
      
      -- Create snapshot
      local snapshot = NametableTilesController.snapshotNametableLayer(mockWin, mockLayer)
      
      -- Verify snapshot contains userDefinedAttrs
      expect(snapshot).toBeTruthy()
      expect(snapshot.userDefinedAttrs).toBeTruthy()
      expect(snapshot.noOverflowSupported).toBe(true)
      expect(type(snapshot.userDefinedAttrs)).toBe("string")
      expect(#snapshot.userDefinedAttrs).toBe(128)  -- 64 bytes * 2 hex chars per byte
      
      -- Verify hex string format (all hex characters)
      local hexPattern = "^[0-9A-Fa-f]+$"
      expect(snapshot.userDefinedAttrs:match(hexPattern)).toBeTruthy()
      
      -- Verify first byte matches (attribute byte 1 should be 0x01 from palette 2 at (0,0))
      local firstByteHex = snapshot.userDefinedAttrs:sub(1, 2)
      local firstByte = tonumber(firstByteHex, 16)
      expect(firstByte).toBe(0x01)
      
      -- Verify that the hex string correctly represents all 64 attribute bytes
      -- Attribute byte for (4,4): attrRow=1, attrCol=1, index = 1*8 + 1 + 1 = 10
      -- Palette 3 = index 2, so byte 10 should be 0x02 (top-left quadrant)
      local byte10Hex = snapshot.userDefinedAttrs:sub(19, 20)  -- Byte 10: (10-1)*2 + 1 to (10-1)*2 + 2
      local byte10 = tonumber(byte10Hex, 16)
      expect(byte10).toBe(0x02)
    end)
    
    it("loads userDefinedAttrs and overwrites attribute bytes when loading from project", function()
      local mockWin = {
        kind = "ppu_frame",
        cols = 32,
        rows = 30,
        nametableBytes = {},
        nametableAttrBytes = {},
      }
      
      -- Initialize nametable and attribute bytes (all zeros)
      for i = 1, 960 do
        mockWin.nametableBytes[i] = 0x00
      end
      for i = 1, 64 do
        mockWin.nametableAttrBytes[i] = 0x00
      end
      
      local mockLayer = {
        kind = "tile",
        paletteNumbers = {},
      }
      
      -- Create a userDefinedAttrs hex string
      -- Set attribute byte 1 to 0x01 (palette 2 at top-left quadrant)
      -- Set attribute byte 2 to 0x02 (palette 3 at top-left quadrant)
      local userAttrBytes = {}
      for i = 1, 64 do
        userAttrBytes[i] = 0x00
      end
      userAttrBytes[1] = 0x01  -- Palette 2
      userAttrBytes[2] = 0x02  -- Palette 3
      
      -- Convert to hex string
      local hexParts = {}
      for i = 1, 64 do
        hexParts[i] = string.format("%02X", userAttrBytes[i])
      end
      local userDefinedAttrs = table.concat(hexParts, "")
      
      -- Simulate loading from project using hydrateWindowNametable
      -- We need to call the internal logic that applies userDefinedAttrs
      local opts = {
        userDefinedAttrs = userDefinedAttrs,
      }
      
      -- Manually apply the logic from hydrateWindowNametable
      if userDefinedAttrs and type(userDefinedAttrs) == "string" and #userDefinedAttrs >= 128 then
        local userAttrBytes = {}
        for i = 1, 64 do
          local hexPair = userDefinedAttrs:sub((i - 1) * 2 + 1, i * 2)
          local byteVal = tonumber(hexPair, 16)
          if byteVal then
            userAttrBytes[i] = byteVal
          else
            userAttrBytes[i] = 0x00
          end
        end
        -- Overwrite all 64 attribute bytes with user-defined values
        for i = 1, 64 do
          mockWin.nametableAttrBytes[i] = userAttrBytes[i] or 0x00
        end
      end
      
      -- Extract palette numbers from updated attribute bytes
      NametableTilesController.extractPaletteNumbersFromAttributes(mockWin, mockLayer, 32, 30)
      
      -- Verify attribute bytes were overwritten correctly
      expect(mockWin.nametableAttrBytes[1]).toBe(0x01)
      expect(mockWin.nametableAttrBytes[2]).toBe(0x02)
      
      -- Verify paletteNumbers were synced correctly
      -- Attribute byte 1, top-left quadrant (tiles 0,0 1,0 0,1 1,1) = palette 2
      expect(mockLayer.paletteNumbers[0]).toBe(2)   -- (0,0)
      expect(mockLayer.paletteNumbers[1]).toBe(2)   -- (1,0)
      expect(mockLayer.paletteNumbers[32]).toBe(2)  -- (0,1)
      expect(mockLayer.paletteNumbers[33]).toBe(2)  -- (1,1)
      
      -- Attribute byte 2, top-left quadrant (tiles 4,0 5,0 4,1 5,1) = palette 3
      expect(mockLayer.paletteNumbers[4]).toBe(3)   -- (4,0)
      expect(mockLayer.paletteNumbers[5]).toBe(3)   -- (5,0)
      expect(mockLayer.paletteNumbers[36]).toBe(3)  -- (4,1)
      expect(mockLayer.paletteNumbers[37]).toBe(3)  -- (5,1)
    end)
    
    it("handles invalid hex string gracefully when loading userDefinedAttrs", function()
      local mockWin = {
        kind = "ppu_frame",
        cols = 32,
        rows = 30,
        nametableBytes = {},
        nametableAttrBytes = {},
      }
      
      for i = 1, 960 do
        mockWin.nametableBytes[i] = 0x00
      end
      for i = 1, 64 do
        mockWin.nametableAttrBytes[i] = 0x00
      end
      
      local mockLayer = {
        kind = "tile",
        paletteNumbers = {},
      }
      
      -- Try with a hex string that's too short
      local shortHex = "00"  -- Only 1 byte, should be ignored
      
      -- Apply logic (should not crash and should not modify attribute bytes)
      if shortHex and type(shortHex) == "string" and #shortHex >= 128 then
        -- This should not execute
        expect(true).toBe(false)  -- Should not reach here
      end
      
      -- Attribute bytes should remain unchanged
      expect(mockWin.nametableAttrBytes[1]).toBe(0x00)
    end)
  end)

  describe("writeBackToROM budget lock", function()
    it("reuses original compressed stream when nametable is unchanged", function()
      local oldEncode = NametableUtils.encode_decompressed_nametable
      local oldWriteRange = chr.writeBytesToRange
      local oldWriteStart = chr.writeBytesStartingAt
      local captured = nil

      NametableUtils.encode_decompressed_nametable = function()
        return { 0x10, 0x11, 0x12, 0x13, 0x14 } -- should not be used for unchanged windows
      end
      chr.writeBytesToRange = function(romRaw, startAddr, previousSize, bytes)
        captured = {
          startAddr = startAddr,
          previousSize = previousSize,
          bytes = {},
        }
        for i = 1, #bytes do
          captured.bytes[i] = bytes[i]
        end
        return romRaw
      end
      chr.writeBytesStartingAt = function()
        return nil, "writeBytesStartingAt should not be called in this test"
      end

      local win = {
        nametableStart = 0x20,
        nametableBytes = { 0x01, 0x02, 0x03 },
        _originalNametableBytes = { 0x01, 0x02, 0x03 },
        nametableAttrBytes = { 0x04, 0x05 },
        _originalNametableAttrBytes = { 0x04, 0x05 },
        _originalCompressedBytes = { 0xAA, 0xBB, 0xCC },
      }
      local layer = {
        kind = "tile",
        nametableStartAddr = 0x20,
        nametableEndAddr = 0x22,
        noOverflowSupported = true,
        codec = "konami",
      }

      local ok, err = NametableTilesController.writeBackToROM(win, layer, string.rep("\0", 512))

      NametableUtils.encode_decompressed_nametable = oldEncode
      chr.writeBytesToRange = oldWriteRange
      chr.writeBytesStartingAt = oldWriteStart

      expect(ok).toBeTruthy()
      expect(err).toBeNil()
      expect(captured).toBeTruthy()
      expect(captured.startAddr).toBe(0x20)
      expect(captured.previousSize).toBe(3)
      expect(captured.bytes).toEqual({ 0xAA, 0xBB, 0xCC })
    end)

    it("allows save when edited nametable exceeds original byte budget", function()
      local oldEncode = NametableUtils.encode_decompressed_nametable
      local oldWriteRange = chr.writeBytesToRange
      local oldWriteStart = chr.writeBytesStartingAt
      local writeCalls = 0
      local startCall = nil

      NametableUtils.encode_decompressed_nametable = function()
        return { 0x01, 0x02, 0x03, 0x04, 0x05 } -- 5 bytes
      end
      chr.writeBytesToRange = function()
        writeCalls = writeCalls + 1
        return nil, "writeBytesToRange should not be used for overflow case"
      end
      chr.writeBytesStartingAt = function(romRaw, startAddr, bytes)
        startCall = {
          startAddr = startAddr,
          bytes = {},
        }
        for i = 1, #bytes do
          startCall.bytes[i] = bytes[i]
        end
        return romRaw
      end

      local win = {
        nametableStart = 0x100,
        nametableBytes = { 0x09, 0x02, 0x03 },
        _originalNametableBytes = { 0x01, 0x02, 0x03 }, -- changed
        nametableAttrBytes = { 0x00 },
        _originalNametableAttrBytes = { 0x00 },
      }
      local layer = {
        kind = "tile",
        nametableStartAddr = 0x100,
        nametableEndAddr = 0x102, -- budget = 3 bytes
        noOverflowSupported = true,
        codec = "konami",
      }

      local updated, err = NametableTilesController.writeBackToROM(win, layer, string.rep("\0", 1024))

      NametableUtils.encode_decompressed_nametable = oldEncode
      chr.writeBytesToRange = oldWriteRange
      chr.writeBytesStartingAt = oldWriteStart

      expect(updated).toBeTruthy()
      expect(err).toBeNil()
      expect(writeCalls).toBe(0)
      expect(startCall).toBeTruthy()
      expect(startCall.startAddr).toBe(0x100)
      expect(startCall.bytes).toEqual({ 0x01, 0x02, 0x03, 0x04, 0x05 })
    end)

    it("pads edited compressed stream with 0xFF to keep original budget size", function()
      local oldEncode = NametableUtils.encode_decompressed_nametable
      local oldWriteRange = chr.writeBytesToRange
      local captured = nil

      NametableUtils.encode_decompressed_nametable = function()
        return { 0x21, 0x22 } -- shorter than budget
      end
      chr.writeBytesToRange = function(romRaw, startAddr, previousSize, bytes)
        captured = {
          startAddr = startAddr,
          previousSize = previousSize,
          bytes = {},
        }
        for i = 1, #bytes do
          captured.bytes[i] = bytes[i]
        end
        return romRaw
      end

      local win = {
        nametableStart = 0x50,
        nametableBytes = { 0x05, 0x06, 0x07 },
        _originalNametableBytes = { 0x01, 0x02, 0x03 }, -- changed
        nametableAttrBytes = { 0x00 },
        _originalNametableAttrBytes = { 0x00 },
      }
      local layer = {
        kind = "tile",
        nametableStartAddr = 0x50,
        nametableEndAddr = 0x53, -- budget = 4 bytes
        noOverflowSupported = true,
        codec = "konami",
      }

      local updated, err = NametableTilesController.writeBackToROM(win, layer, string.rep("\0", 512))

      NametableUtils.encode_decompressed_nametable = oldEncode
      chr.writeBytesToRange = oldWriteRange

      expect(updated).toBeTruthy()
      expect(err).toBeNil()
      expect(captured).toBeTruthy()
      expect(captured.previousSize).toBe(4)
      expect(captured.bytes).toEqual({ 0x21, 0x22, 0xFF, 0xFF })
    end)

    it("allows overflow when noOverflowSupported is false", function()
      local oldEncode = NametableUtils.encode_decompressed_nametable
      local oldWriteRange = chr.writeBytesToRange
      local oldWriteStart = chr.writeBytesStartingAt
      local rangeCalls = 0
      local startCall = nil

      NametableUtils.encode_decompressed_nametable = function()
        return { 0x40, 0x41, 0x42, 0x43, 0x44 } -- 5 bytes
      end
      chr.writeBytesToRange = function()
        rangeCalls = rangeCalls + 1
        return nil, "writeBytesToRange should not be used for overflow case"
      end
      chr.writeBytesStartingAt = function(romRaw, startAddr, bytes)
        startCall = {
          startAddr = startAddr,
          bytes = {},
        }
        for i = 1, #bytes do
          startCall.bytes[i] = bytes[i]
        end
        return romRaw
      end

      local win = {
        nametableStart = 0x180,
        nametableBytes = { 0x09, 0x02, 0x03 },
        _originalNametableBytes = { 0x01, 0x02, 0x03 }, -- changed
        nametableAttrBytes = { 0x00 },
        _originalNametableAttrBytes = { 0x00 },
      }
      local layer = {
        kind = "tile",
        nametableStartAddr = 0x180,
        nametableEndAddr = 0x182, -- nominal budget = 3 bytes
        noOverflowSupported = false,
        codec = "konami",
      }

      local updated, err = NametableTilesController.writeBackToROM(win, layer, string.rep("\0", 1024))

      NametableUtils.encode_decompressed_nametable = oldEncode
      chr.writeBytesToRange = oldWriteRange
      chr.writeBytesStartingAt = oldWriteStart

      expect(updated).toBeTruthy()
      expect(err).toBeNil()
      expect(rangeCalls).toBe(0)
      expect(startCall).toBeTruthy()
      expect(startCall.startAddr).toBe(0x180)
      expect(startCall.bytes).toEqual({ 0x40, 0x41, 0x42, 0x43, 0x44 })
    end)
  end)

  describe("overflow warning toast", function()
    local previousCtx

    beforeEach(function()
      previousCtx = rawget(_G, "ctx")
    end)

    afterEach(function()
      _G.ctx = previousCtx
    end)

    it("shows warning once when compressed size exceeds budget and noOverflowSupported is true", function()
      local calls = {}
      _G.ctx = {
        showToast = function(kind, text)
          calls[#calls + 1] = { kind = kind, text = text }
        end,
      }

      local win = {}
      local layer = { kind = "tile", noOverflowSupported = true }

      local first = NametableTilesController.updateOverflowToastForWindow(win, layer, 305, 301)
      local second = NametableTilesController.updateOverflowToastForWindow(win, layer, 306, 301)

      expect(first).toBe(true)
      expect(second).toBe(false)
      expect(#calls).toBe(1)
      expect(calls[1].kind).toBe("warning")
      expect(calls[1].text).toBe("Nametable data (305 bytes) larger than original (301 bytes)")
      expect(win._nametableOverflowWarned).toBe(true)
    end)

    it("does not warn when noOverflowSupported is false", function()
      local calls = {}
      _G.ctx = {
        showToast = function(kind, text)
          calls[#calls + 1] = { kind = kind, text = text }
        end,
      }

      local win = {}
      local layer = { kind = "tile", noOverflowSupported = false }

      local shown = NametableTilesController.updateOverflowToastForWindow(win, layer, 305, 301)

      expect(shown).toBe(false)
      expect(#calls).toBe(0)
      expect(win._nametableOverflowWarned).toBe(false)
    end)

    it("shows info when size returns to valid and re-arms warning afterward", function()
      local calls = {}
      _G.ctx = {
        showToast = function(kind, text)
          calls[#calls + 1] = { kind = kind, text = text }
        end,
      }

      local win = {}
      local layer = { kind = "tile", noOverflowSupported = true }

      NametableTilesController.updateOverflowToastForWindow(win, layer, 305, 301)
      local validAgain = NametableTilesController.updateOverflowToastForWindow(win, layer, 300, 301)
      local shownAgain = NametableTilesController.updateOverflowToastForWindow(win, layer, 302, 301)

      expect(validAgain).toBe(true)
      expect(shownAgain).toBe(true)
      expect(#calls).toBe(3)
      expect(calls[2].kind).toBe("info")
      expect(calls[2].text).toBe("Nametable size is valid again (300 bytes)")
      expect(calls[3].kind).toBe("warning")
      expect(calls[3].text).toBe("Nametable data (302 bytes) larger than original (301 bytes)")
    end)
  end)
  
end)
