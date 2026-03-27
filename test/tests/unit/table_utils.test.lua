-- table_utils.test.lua
-- Unit tests for utils/table_utils.lua

local TableUtils = require("utils.table_utils")

describe("table_utils.lua", function()
  
  describe("deepcopy", function()
    it("copies simple table", function()
      local original = {a = 1, b = 2, c = 3}
      local copy = TableUtils.deepcopy(original)
      expect(copy).toEqual(original)
      expect(copy).toNotBe(original) -- Should be different objects
    end)
    
    it("copies nested tables", function()
      local original = {
        a = {x = 1, y = 2},
        b = {z = {nested = "value"}}
      }
      local copy = TableUtils.deepcopy(original)
      expect(copy).toEqual(original)
      expect(copy.a).toNotBe(original.a) -- Nested table should be different object
      expect(copy.b.z).toNotBe(original.b.z) -- Deeply nested should be different
    end)
    
    it("preserves paletteData structure", function()
      local original = {
        paletteData = {
          items = {
            {"0F", "30", "28", "16"},
            {"0F", "30", "06", "16"},
            {"0F", "10", "27", "16"},
            {"0F", "30", "36", "26"},
          }
        }
      }
      local copy = TableUtils.deepcopy(original)
      expect(copy.paletteData.items[1][1]).toBe("0F")
      expect(copy.paletteData.items[2][3]).toBe("06")
      -- Modify copy, original should be unchanged
      copy.paletteData.items[1][1] = "FF"
      expect(original.paletteData.items[1][1]).toBe("0F")
    end)
    
    it("handles arrays with numeric indices", function()
      local original = {1, 2, 3, {4, 5, 6}}
      local copy = TableUtils.deepcopy(original)
      expect(copy).toEqual(original)
      expect(copy[4]).toNotBe(original[4]) -- Nested array should be different
    end)
    
    it("handles empty table", function()
      local original = {}
      local copy = TableUtils.deepcopy(original)
      expect(copy).toEqual(original)
      expect(copy).toNotBe(original)
    end)
    
    it("handles non-table values", function()
      expect(TableUtils.deepcopy(42)).toBe(42)
      expect(TableUtils.deepcopy("hello")).toBe("hello")
      expect(TableUtils.deepcopy(nil)).toBeNil()
    end)
  end)

  describe("serialize_lua_table", function()
    it("serializes romPatches numeric fields as hex constants", function()
      local body = TableUtils.serialize_lua_table({
        romPatches = {
          { address = 0x001234, value = 0x0F, reason = "Test patch" },
          { addresses = { from = 0x0000AA, to = 0x0000AB }, values = { 0x03, 0x04 }, reason = "Seq patch" },
          { addresses = { 0x000123, 0x000126 }, values = { 0x05, 0x06 }, reason = "List patch" },
        },
      })

      expect(string.find(body, "address = 0x001234", 1, true)).toBeTruthy()
      expect(string.find(body, "value = 0x0F", 1, true)).toBeTruthy()
      expect(string.find(body, "from = 0x0000AA", 1, true)).toBeTruthy()
      expect(string.find(body, "to = 0x0000AB", 1, true)).toBeTruthy()
      expect(string.find(body, "0x0000AA", 1, true)).toBeTruthy()
      expect(string.find(body, "0x03", 1, true)).toBeTruthy()
      expect(string.find(body, "0x04", 1, true)).toBeTruthy()
      expect(string.find(body, "0x000123", 1, true)).toBeTruthy()
      expect(string.find(body, "0x000126", 1, true)).toBeTruthy()
      expect(string.find(body, "0x05", 1, true)).toBeTruthy()
      expect(string.find(body, "0x06", 1, true)).toBeTruthy()
      expect(string.find(body, "reason = \"Test patch\"", 1, true)).toBeTruthy()
      expect(string.find(body, "reason = \"Seq patch\"", 1, true)).toBeTruthy()
      expect(string.find(body, "reason = \"List patch\"", 1, true)).toBeTruthy()
    end)
  end)
  
end)
