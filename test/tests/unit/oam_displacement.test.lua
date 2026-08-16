-- Unit tests for OAM displacement wrap normalization (±256 no-ops).

local OamDisplacement = require("controllers.sprite.oam_displacement")
local SpriteController = require("controllers.sprite.sprite_controller")
local Hydration = require("controllers.sprite.hydration_controller")

describe("oam_displacement.lua", function()
  it("folds ±256 identity deltas to 0", function()
    expect(OamDisplacement.normalizeAxisDelta(256)).toBe(0)
    expect(OamDisplacement.normalizeAxisDelta(-256)).toBe(0)
    expect(OamDisplacement.normalizeAxisDelta(512)).toBe(0)
    expect(OamDisplacement.normalizeAxisDelta(-512)).toBe(0)
  end)

  it("keeps real short moves and folds wrap-crossing to shortest delta", function()
    expect(OamDisplacement.normalizeAxisDelta(20)).toBe(20)
    expect(OamDisplacement.normalizeAxisDelta(-20)).toBe(-20)
    -- 250 -> 5 is +11 the short way, not -245
    expect(OamDisplacement.normalizeAxisDelta(5 - 250)).toBe(11)
    expect(OamDisplacement.normalizeAxisDelta(250 - 5)).toBe(-11)
  end)

  it("applyNormalizedDisplacement clears wrap-lane dx and rewrites world", function()
    local s = {
      startAddr = 0x200,
      baseX = 9,
      baseY = 239,
      worldX = 9 - 256,
      worldY = 239,
      x = 9 - 256,
      y = 239,
      dx = -256,
      dy = 0,
      hasMoved = true,
    }
    local dx, dy = OamDisplacement.applyNormalizedDisplacement(s)
    expect(dx).toBe(0)
    expect(dy).toBe(0)
    expect(s.dx).toBe(0)
    expect(s.dy).toBe(0)
    expect(s.worldX).toBe(9)
    expect(s.worldY).toBe(239)
    expect(s.hasMoved).toBe(false)
  end)

  it("hydrate folds project dx=±256 so reload does not look moved", function()
    local addr = 0x0200
    local romRaw = ("\0"):rep(addr) .. string.char(239, 150, 1, 9)
    local layer = {
      kind = "sprite",
      items = {
        {
          startAddr = addr,
          dx = -256,
          dy = 0,
        },
        {
          startAddr = addr + 4,
          dx = 256,
          dy = 0,
        },
      },
    }
    -- second OAM slot
    romRaw = ("\0"):rep(addr) .. string.char(239, 150, 1, 9) .. string.char(239, 152, 1, 1)

    Hydration.hydrateSpriteLayer(layer, {
      romRaw = romRaw,
      tilesPool = {},
      appEditState = {},
    })

    expect(layer.items[1].dx).toBe(0)
    expect(layer.items[1].dy).toBe(0)
    expect(layer.items[1].worldX).toBe(9)
    expect(layer.items[1].hasMoved).toBe(false)
    expect(layer.items[2].dx).toBe(0)
    expect(layer.items[2].worldX).toBe(1)
    expect(layer.items[2].hasMoved).toBe(false)
  end)

  it("snapshot omits identity wrap dx so projects do not persist ±256", function()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          startAddr = 0x200,
          baseX = 9,
          baseY = 10,
          worldX = 9 + 256,
          worldY = 10,
          dx = 256,
          dy = 0,
          hasMoved = true,
        },
        {
          startAddr = 0x204,
          baseX = 1,
          baseY = 10,
          worldX = 1 + 20,
          worldY = 10,
          dx = 20,
          dy = 0,
          hasMoved = true,
        },
      },
    }
    local snap = Hydration.snapshotSpriteLayer(layer)
    expect(snap.items[1].dx).toBeNil()
    expect(snap.items[1].dy).toBeNil()
    expect(snap.items[2].dx).toBe(20)
    expect(snap.items[2].dy).toBeNil()
  end)

  it("ROM write treats ±256 as no position change", function()
    local startAddr = 80
    local chr = require("chr")
    local bytes = {}
    for i = 1, 128 do bytes[i] = "\0" end
    bytes[startAddr + 1] = string.char(40)
    bytes[startAddr + 2] = string.char(7)
    bytes[startAddr + 3] = string.char(0)
    bytes[startAddr + 4] = string.char(100)
    local romRaw = table.concat(bytes)

    local sprite = {
      startAddr = startAddr,
      baseX = 100,
      baseY = 40,
      dx = -256,
      dy = 0,
      oamTile = 7,
      attr = 0,
      hasMoved = true,
    }
    local win = {
      kind = "oam_animation",
      layers = { { kind = "sprite", items = { sprite } } },
      getSpriteLayers = function(self)
        return { { index = 1, layer = self.layers[1] } }
      end,
    }
    local updated, err = SpriteController.applyDisplacementsToROMForWindows({ win }, romRaw)
    expect(err).toBeNil()
    local out = chr.readBytesFromRange(updated, startAddr, startAddr + 3)
    expect(out[4]).toBe(100)
    expect(out[1]).toBe(40)
  end)
end)
