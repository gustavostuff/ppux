local Hydration = require("controllers.sprite.hydration_controller")

describe("sprite hydration — pattern table + 8x16", function()
  local function identityPatternTable()
    return {
      ranges = {
        { from = 0, to = 255, bank = 1, page = 1 },
      },
    }
  end

  it("OAM-backed sprites ignore stale tileBelow when resolving logical pair (no duplicated top half)", function()
    local topTile = {}
    local botTile = {}
    local tilesPool = {
      [1] = {
        [4] = topTile,
        [5] = botTile,
      },
    }

    local layer = {
      kind = "sprite",
      patternTable = identityPatternTable(),
    }

    local item = {
      startAddr = 0x0200,
      tile = 5,
      tileBelow = 5,
    }

    Hydration.ensureTileRefsForSpriteItem(item, "8x16", tilesPool, {}, layer)

    expect(item.topRef).toBe(topTile)
    expect(item.botRef).toBe(botTile)
    expect(item.tile).toBe(4)
    expect(item.tileBelow).toBe(5)
  end)

  it("hydrate clears stale tileBelow for OAM + pattern map before resolving 8x16 refs", function()
    local topTile = {}
    local botTile = {}
    local tilesPool = {
      [1] = {
        [2] = topTile,
        [3] = botTile,
      },
    }

    local addr = 0x0200
    local romPrefix = ("\0"):rep(addr)
    local oamFour = string.char(10, 3, 0, 40)
    local romRaw = romPrefix .. oamFour

    local layer = {
      kind = "sprite",
      mode = "8x16",
      patternTable = identityPatternTable(),
      items = {
        {
          startAddr = addr,
          bank = 1,
          tile = 0,
          tileBelow = 3,
          dx = 0,
          dy = 0,
        },
      },
    }

    Hydration.hydrateSpriteLayer(layer, {
      romRaw = romRaw,
      tilesPool = tilesPool,
      appEditState = {},
    })

    local s = layer.items[1]
    expect(s.tileBelow).toBe(3)
    expect(s.bank).toBeNil()
    expect(s.tile).toBe(2)
    expect(s.topRef).toBe(topTile)
    expect(s.botRef).toBe(botTile)
  end)
end)
