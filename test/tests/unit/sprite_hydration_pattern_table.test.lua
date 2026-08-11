local Hydration = require("controllers.sprite.hydration_controller")

describe("sprite hydration — pattern table + 8x16", function()
  local function identityPatternTable()
    return {
      ranges = {
        { from = 0, to = 255, bank = 1 },
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

  it("CHR-backed 8x16 ignores duplicate tileBelow when pairing bank/tile indices", function()
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
      patternTable = { ranges = {} },
    }
    local item = {
      bank = 1,
      tile = 5,
      tileBelow = 5,
    }
    Hydration.ensureTileRefsForSpriteItem(item, "8x16", tilesPool, {}, layer)
    expect(item.topRef).toBe(topTile)
    expect(item.botRef).toBe(botTile)
    expect(item.tile).toBe(4)
    expect(item.tileBelow).toBe(5)
  end)

  it("keepWorld preserves editor positions when ROM base already includes prior displacements", function()
    -- Simulates: move sprite (dx/dy), save so romRaw has base+dx, then rehydrate.
    -- keepWorld=false would double-apply stale dx and scatter sprites (Add-sprite bug).
    local addr = 0x0200
    local originalY, originalX = 20, 40
    local dx, dy = 24, -8
    local writtenY = (originalY + dy) % 256
    local writtenX = (originalX + dx) % 256
    local romPrefix = ("\0"):rep(addr)
    local oamFour = string.char(writtenY, 1, 0, writtenX)
    local romRaw = romPrefix .. oamFour

    local layer = {
      kind = "sprite",
      patternTable = identityPatternTable(),
      items = {
        {
          startAddr = addr,
          baseX = originalX,
          baseY = originalY,
          dx = dx,
          dy = dy,
          worldX = originalX + dx,
          worldY = originalY + dy,
          x = originalX + dx,
          y = originalY + dy,
        },
        {
          -- Newly added sprite: no world yet; should land on ROM base.
          startAddr = addr + 4,
        },
      },
    }

    -- Second OAM slot at ROM base (no prior move).
    local oamTwo = string.char(50, 2, 0, 80)
    romRaw = romPrefix .. oamFour .. oamTwo

    Hydration.hydrateSpriteLayer(layer, {
      romRaw = romRaw,
      tilesPool = { [1] = {} },
      appEditState = {},
      keepWorld = true,
    })

    local moved = layer.items[1]
    expect(moved.baseX).toBe(writtenX)
    expect(moved.baseY).toBe(writtenY)
    expect(moved.worldX).toBe(originalX + dx)
    expect(moved.worldY).toBe(originalY + dy)
    expect(moved.dx).toBe(0)
    expect(moved.dy).toBe(0)

    local added = layer.items[2]
    expect(added.worldX).toBe(80)
    expect(added.worldY).toBe(50)
  end)

  it("keepWorld=false double-applies displacements after ROM write-back (documents Add bug)", function()
    local addr = 0x0200
    local originalY, originalX = 20, 40
    local dx, dy = 24, -8
    local writtenY = (originalY + dy) % 256
    local writtenX = (originalX + dx) % 256
    local romPrefix = ("\0"):rep(addr)
    local oamFour = string.char(writtenY, 1, 0, writtenX)
    local romRaw = romPrefix .. oamFour

    local layer = {
      kind = "sprite",
      patternTable = identityPatternTable(),
      items = {
        {
          startAddr = addr,
          baseX = originalX,
          baseY = originalY,
          dx = dx,
          dy = dy,
          worldX = originalX + dx,
          worldY = originalY + dy,
        },
      },
    }

    Hydration.hydrateSpriteLayer(layer, {
      romRaw = romRaw,
      tilesPool = { [1] = {} },
      appEditState = {},
      keepWorld = false,
    })

    local s = layer.items[1]
    expect(s.baseX).toBe(writtenX)
    expect(s.dx).toBe(dx)
    expect(s.worldX).toBe(writtenX + dx)
    expect(s.worldX).toNotBe(originalX + dx)
  end)
end)
