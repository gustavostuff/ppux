local PatternTableMapping = require("utils.pattern_table_mapping")

describe("pattern_table_mapping.lua cache", function()
  local function fullBankRange(bank)
    return {
      ranges = {
        { bank = bank or 1, from = 0, to = 255 },
      },
    }
  end

  it("getMapForLayer reuses the same map for the same patternTable object", function()
    local patternTable = fullBankRange(2)
    local layer = { patternTable = patternTable }
    local map1 = assert(select(1, PatternTableMapping.getMapForLayer(layer)))
    local map2 = assert(select(1, PatternTableMapping.getMapForLayer(layer)))
    expect(map1).toBe(map2)
    expect(map1[0].bank).toBe(2)
    expect(map1[0].tileIndex).toBe(0)
  end)

  it("getMapForLayer rebuilds when patternTable object changes", function()
    local layer = { patternTable = fullBankRange(1) }
    local map1 = assert(select(1, PatternTableMapping.getMapForLayer(layer)))
    layer.patternTable = fullBankRange(3)
    local map2 = assert(select(1, PatternTableMapping.getMapForLayer(layer)))
    expect(map1 == map2).toBeFalsy()
    expect(map2[0].bank).toBe(3)
  end)

  it("resolveTileFromMap looks up tiles without rebuilding", function()
    local patternTable = fullBankRange(1)
    local map = assert(select(1, PatternTableMapping.buildMap(patternTable)))
    local tile = { index = 7 }
    local tilesPool = {
      [1] = {
        [7] = tile,
      },
    }
    local resolved = assert(select(1, PatternTableMapping.resolveTileFromMap(tilesPool, map, 7)))
    expect(resolved).toBe(tile)
  end)

  it("invalidateMapCache forces a rebuild", function()
    local layer = { patternTable = fullBankRange(1) }
    local map1 = assert(select(1, PatternTableMapping.getMapForLayer(layer)))
    PatternTableMapping.invalidateMapCache(layer)
    local map2 = assert(select(1, PatternTableMapping.getMapForLayer(layer)))
    expect(map1 == map2).toBeFalsy()
    expect(map2[0].bank).toBe(1)
  end)
end)
