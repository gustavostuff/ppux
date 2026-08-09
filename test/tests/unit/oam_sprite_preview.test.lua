local OamSpritePreview = require("ui.oam_sprite_preview")

describe("OamSpritePreview", function()
  local function identityPatternTable()
    return {
      ranges = {
        { from = 0, to = 255, bank = 1 },
      },
    }
  end

  it("reports invalid OAM when fewer than 4 bytes remain", function()
    local preview = OamSpritePreview.new()
    preview:setContext({
      romRaw = string.rep("\0", 10),
      spriteLayer = {
        kind = "sprite",
        mode = "8x8",
        linkedPatternTableWindowId = "pt",
        patternTable = identityPatternTable(),
      },
      tilesPool = { [1] = {} },
    })
    preview:setSelectedAddr(8)
    expect(preview:hasValidOamBytes()).toBe(false)
    expect(preview:canDrawSprite()).toBe(false)
  end)

  it("can draw when 4 bytes exist and pattern tile resolves", function()
    local topTile = { draw = function() end }
    local preview = OamSpritePreview.new()
    -- Y=0, tile=3, attr=0, X=0
    local rom = string.char(0, 3, 0, 0) .. string.rep("\0", 60)
    preview:setContext({
      romRaw = rom,
      spriteLayer = {
        kind = "sprite",
        mode = "8x8",
        linkedPatternTableWindowId = "pt",
        patternTable = identityPatternTable(),
      },
      tilesPool = {
        [1] = {
          [3] = topTile,
        },
      },
    })
    preview:setSelectedAddr(0)
    expect(preview:hasValidOamBytes()).toBe(true)
    expect(preview:canDrawSprite()).toBe(true)
  end)

  it("falls back to icon_x path when tile cannot be resolved", function()
    local preview = OamSpritePreview.new()
    local rom = string.char(0, 9, 0, 0) .. string.rep("\0", 60)
    preview:setContext({
      romRaw = rom,
      spriteLayer = {
        kind = "sprite",
        mode = "8x8",
        linkedPatternTableWindowId = "pt",
        patternTable = identityPatternTable(),
      },
      tilesPool = {
        [1] = {},
      },
    })
    preview:setSelectedAddr(0)
    expect(preview:hasValidOamBytes()).toBe(true)
    expect(preview:canDrawSprite()).toBe(false)
  end)

  it("uses the live appearance sprite when previewing its OAM address", function()
    local topTile = { draw = function() end }
    local live = {
      startAddr = 0,
      topRef = topTile,
      mirrorX = true,
      _mirrorXOverrideSet = true,
      paletteNumber = 3,
    }
    local preview = OamSpritePreview.new()
    preview:setContext({
      romRaw = string.char(0, 3, 0, 0) .. string.rep("\0", 60),
      spriteLayer = {
        kind = "sprite",
        mode = "8x8",
        linkedPatternTableWindowId = "pt",
        patternTable = identityPatternTable(),
      },
      tilesPool = { [1] = { [3] = topTile } },
      appearanceSprite = live,
    })
    preview:setSelectedAddr(0)
    expect(preview:canDrawSprite()).toBe(true)
    expect(preview._slots[1].item).toBe(live)
  end)

  it("keeps appearance flip/palette when hydrating a different OAM address", function()
    local topTile = { draw = function() end }
    -- addr 0: tile 1; addr 4: tile 2, attr with palette 0 / no flip
    local rom = string.char(0, 1, 0, 0, 0, 2, 0, 0) .. string.rep("\0", 60)
    local appearance = {
      startAddr = 0,
      mirrorX = true,
      _mirrorXOverrideSet = true,
      mirrorY = true,
      _mirrorYOverrideSet = true,
      paletteNumber = 4,
    }
    local preview = OamSpritePreview.new()
    preview:setContext({
      romRaw = rom,
      spriteLayer = {
        kind = "sprite",
        mode = "8x8",
        linkedPatternTableWindowId = "pt",
        patternTable = identityPatternTable(),
      },
      tilesPool = { [1] = { [1] = topTile, [2] = topTile } },
      appearanceSprite = appearance,
    })
    preview:setSelectedAddr(4)
    expect(preview:canDrawSprite()).toBe(true)
    expect(preview._slots[1].item).toNotBe(appearance)
    expect(preview._slots[1].item.mirrorX).toBe(true)
    expect(preview._slots[1].item.mirrorY).toBe(true)
    expect(preview._slots[1].item.paletteNumber).toBe(4)
  end)

  it("builds one preview slot per selected OAM start with ants colors", function()
    local topTile = { draw = function() end }
    local rom = string.char(0, 1, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0) .. string.rep("\0", 60)
    local preview = OamSpritePreview.new()
    preview:setContext({
      romRaw = rom,
      spriteLayer = {
        kind = "sprite",
        mode = "8x8",
        linkedPatternTableWindowId = "pt",
        patternTable = identityPatternTable(),
      },
      tilesPool = { [1] = { [1] = topTile, [2] = topTile } },
    })
    preview:setSelectedStarts({ 0, 4 }, {
      { 1, 0, 0, 1 },
      { 0, 1, 0, 1 },
    })
    expect(#preview._slots).toBe(2)
    expect(preview._slots[1].addr).toBe(0)
    expect(preview._slots[2].addr).toBe(4)
    expect(preview._slots[1].antsColor[1]).toBe(1)
    expect(preview._slots[2].antsColor[2]).toBe(1)
  end)
end)
