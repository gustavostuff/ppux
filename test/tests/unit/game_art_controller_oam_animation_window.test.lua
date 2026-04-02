local WM = require("controllers.window.window_controller")
local GameArtController = require("controllers.game_art.game_art_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local chr = require("chr")

local function makeRom(size, overrides)
  local bytes = {}
  for i = 1, size do
    bytes[i] = 0
  end
  for addr, value in pairs(overrides or {}) do
    bytes[(addr + 1)] = value
  end
  local chars = {}
  for i = 1, #bytes do
    chars[i] = string.char(bytes[i] % 256)
  end
  return table.concat(chars)
end

describe("game_art_controller.lua - oam_animation hydration", function()
  local previousCtx

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = nil
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("hydrates ROM-backed sprite items from OAM bytes and preserves sprite metadata", function()
    local startAddr = 20 -- 0-based ROM address
    local romRaw = makeRom(128, {
      [startAddr + 0] = 50,   -- Y
      [startAddr + 1] = 42,   -- tile
      [startAddr + 2] = 0x41, -- attr (palette bits=1 -> palette #2 before override)
      [startAddr + 3] = 100,  -- X
    })

    local layout = {
      currentBank = 1,
      windows = {
        {
          id = "oam_anim_01",
          title = "OAM Anim 01",
          kind = "oam_animation",
          x = 20, y = 20,
          cellW = 8, cellH = 8,
          cols = 32, rows = 30,
          visibleCols = 16, visibleRows = 16,
          scrollCol = 0, scrollRow = 0,
          zoom = 2,
          activeLayer = 1,
          delaysPerLayer = { 0.25 },
          layers = {
            {
              kind = "sprite",
              name = "Frame 1",
              mode = "8x8",
              originX = 12,
              originY = 34,
              items = {
                {
                  startAddr = startAddr,
                  bank = 1,
                  -- Intentionally omit tile; OAM hydration should infer it from ROM byte #2.
                  dx = 3,
                  dy = -2,
                  mirrorX = true,
                  mirrorY = false,
                  paletteNumber = 4, -- Explicit layout override should win over attr low bits.
                }
              }
            }
          }
        }
      }
    }

    local wm = WM.new()
    local tilesPool = {
      [1] = {
        [42] = { _bankIndex = 1, index = 42, pixels = {} },
      },
    }
    local function ensureTiles(bankIdx)
      tilesPool[bankIdx] = tilesPool[bankIdx] or {}
    end

    local result, err = GameArtController.buildWindowsFromLayout(layout, {
      wm = wm,
      tilesPool = tilesPool,
      ensureTiles = ensureTiles,
      romRaw = romRaw,
    })

    expect(err).toBeNil()
    expect(result).toBeTruthy()

    local win = wm:getWindows()[1]
    expect(win).toBeTruthy()
    expect(win.kind).toBe("oam_animation")
    expect(win.activeLayer).toBe(1)
    expect(win.frameDelays[1]).toBe(0.25)

    local layer = win.layers[1]
    expect(layer).toBeTruthy()
    expect(layer.kind).toBe("sprite")
    expect(layer.originX).toBe(12)
    expect(layer.originY).toBe(34)
    expect(#(layer.items or {})).toBe(1)

    local s = layer.items[1]
    expect(s.startAddr).toBe(startAddr)
    expect(s.tile).toBe(42)
    expect(s.baseX).toBe(100)
    expect(s.baseY).toBe(50)
    expect(s.dx).toBe(3)
    expect(s.dy).toBe(-2)
    expect(s.worldX).toBe(103)
    expect(s.worldY).toBe(48)
    expect(s.x).toBe(103)
    expect(s.y).toBe(48)
    expect(s.hasMoved).toBe(true)
    expect(s.paletteNumber).toBe(4)
    expect(s.attr).toBe(0x41)
    expect(s.mirrorX).toBe(true)
    expect(s.mirrorY).toBe(false)
    expect(s.topRef).toBe(tilesPool[1][42])
  end)

  it("derives paletteNumber from attr bits when project item omits paletteNumber", function()
    local startAddr = 44 -- 0-based ROM address
    local romRaw = makeRom(128, {
      [startAddr + 0] = 10,   -- Y
      [startAddr + 1] = 99,   -- tile
      [startAddr + 2] = 0xC2, -- attr low bits=2 -> palette #3, mirrorX=true, mirrorY=true
      [startAddr + 3] = 20,   -- X
    })

    local layout = {
      currentBank = 1,
      windows = {
        {
          id = "oam_anim_02",
          title = "OAM Anim 02",
          kind = "oam_animation",
          x = 20, y = 20,
          cellW = 8, cellH = 8,
          cols = 32, rows = 30,
          visibleCols = 16, visibleRows = 16,
          scrollCol = 0, scrollRow = 0,
          zoom = 2,
          activeLayer = 1,
          layers = {
            {
              kind = "sprite",
              name = "Frame 1",
              mode = "8x8",
              items = {
                {
                  startAddr = startAddr,
                  bank = 1,
                }
              }
            }
          }
        }
      }
    }

    local wm = WM.new()
    local tilesPool = { [1] = { [99] = { _bankIndex = 1, index = 99, pixels = {} } } }
    local function ensureTiles(bankIdx)
      tilesPool[bankIdx] = tilesPool[bankIdx] or {}
    end

    local result, err = GameArtController.buildWindowsFromLayout(layout, {
      wm = wm,
      tilesPool = tilesPool,
      ensureTiles = ensureTiles,
      romRaw = romRaw,
    })

    expect(err).toBeNil()
    expect(result).toBeTruthy()

    local s = wm:getWindows()[1].layers[1].items[1]
    expect(s.paletteNumber).toBe(3)
    expect(s.attr).toBe(0xC2)
    expect(s.mirrorX).toBe(true)
    expect(s.mirrorY).toBe(true)
    expect(s._mirrorXOverrideSet).toBe(false)
    expect(s._mirrorYOverrideSet).toBe(false)
  end)

  it("applies explicit project mirror flags over ROM attr bits during hydration", function()
    local startAddr = 60
    local romRaw = makeRom(128, {
      [startAddr + 0] = 18,
      [startAddr + 1] = 12,
      [startAddr + 2] = 0xC1, -- mirrorX=true, mirrorY=true in attr
      [startAddr + 3] = 24,
    })

    local layout = {
      currentBank = 1,
      windows = {
        {
          id = "oam_anim_03",
          title = "OAM Anim 03",
          kind = "oam_animation",
          x = 20, y = 20,
          cellW = 8, cellH = 8,
          cols = 32, rows = 30,
          visibleCols = 16, visibleRows = 16,
          scrollCol = 0, scrollRow = 0,
          zoom = 2,
          activeLayer = 1,
          layers = {
            {
              kind = "sprite",
              name = "Frame 1",
              mode = "8x8",
              items = {
                {
                  startAddr = startAddr,
                  bank = 1,
                  mirrorX = false,
                  mirrorY = false,
                }
              }
            }
          }
        }
      }
    }

    local wm = WM.new()
    local tilesPool = { [1] = { [12] = { _bankIndex = 1, index = 12, pixels = {} } } }
    local function ensureTiles(bankIdx)
      tilesPool[bankIdx] = tilesPool[bankIdx] or {}
    end

    local result, err = GameArtController.buildWindowsFromLayout(layout, {
      wm = wm,
      tilesPool = tilesPool,
      ensureTiles = ensureTiles,
      romRaw = romRaw,
    })

    expect(err).toBeNil()
    expect(result).toBeTruthy()

    local s = wm:getWindows()[1].layers[1].items[1]
    expect(s.attr).toBe(0xC1)
    expect(s.mirrorX).toBe(false)
    expect(s.mirrorY).toBe(false)
    expect(s._mirrorXOverrideSet).toBe(true)
    expect(s._mirrorYOverrideSet).toBe(true)
  end)

  it("applies explicit true mirror flags over ROM attr bits during hydration", function()
    local startAddr = 66
    local romRaw = makeRom(128, {
      [startAddr + 0] = 18,
      [startAddr + 1] = 12,
      [startAddr + 2] = 0x01, -- no mirror bits in attr
      [startAddr + 3] = 24,
    })

    local layout = {
      currentBank = 1,
      windows = {
        {
          id = "oam_anim_03b",
          title = "OAM Anim 03b",
          kind = "oam_animation",
          x = 20, y = 20,
          cellW = 8, cellH = 8,
          cols = 32, rows = 30,
          visibleCols = 16, visibleRows = 16,
          scrollCol = 0, scrollRow = 0,
          zoom = 2,
          activeLayer = 1,
          layers = {
            {
              kind = "sprite",
              name = "Frame 1",
              mode = "8x8",
              items = {
                {
                  startAddr = startAddr,
                  bank = 1,
                  mirrorX = true,
                  mirrorY = true,
                }
              }
            }
          }
        }
      }
    }

    local wm = WM.new()
    local tilesPool = { [1] = { [12] = { _bankIndex = 1, index = 12, pixels = {} } } }
    local function ensureTiles(bankIdx)
      tilesPool[bankIdx] = tilesPool[bankIdx] or {}
    end

    local result, err = GameArtController.buildWindowsFromLayout(layout, {
      wm = wm,
      tilesPool = tilesPool,
      ensureTiles = ensureTiles,
      romRaw = romRaw,
    })

    expect(err).toBeNil()
    expect(result).toBeTruthy()

    local s = wm:getWindows()[1].layers[1].items[1]
    expect(s.attr).toBe(0x01)
    expect(s.mirrorX).toBe(true)
    expect(s.mirrorY).toBe(true)
    expect(s._mirrorXOverrideSet).toBe(true)
    expect(s._mirrorYOverrideSet).toBe(true)
  end)

  it("snapshots oam_animation layers with sprite metadata and frame delays", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({
      animated = true,
      oamBacked = true,
      numFrames = 2,
      cols = 32,
      rows = 30,
      spriteMode = "8x8",
      title = "OAM Snapshot",
    })

    win.layers[1].originX = 7
    win.layers[1].originY = 9
    win.layers[1].items = {
      {
        startAddr = 0x1234,
        bank = 1,
        tile = 42,
        dx = 2,
        dy = -1,
        paletteNumber = 3,
        mirrorX = true,
        mirrorY = true,
        _mirrorXOverrideSet = true,
        _mirrorYOverrideSet = true,
      }
    }
    win.frameDelays[1] = 0.15
    win.frameDelays[2] = 0.35

    local layout = GameArtController.snapshotLayout(wm, nil, 1)
    expect(layout).toBeTruthy()
    expect(#layout.windows).toBe(1)

    local entry = layout.windows[1]
    expect(entry.kind).toBe("oam_animation")
    expect(entry.delaysPerLayer).toBeTruthy()
    expect(entry.delaysPerLayer[1]).toBe(0.15)
    expect(entry.delaysPerLayer[2]).toBe(0.35)
    expect(entry.layers[1].kind).toBe("sprite")
    expect(entry.layers[1].originX).toBe(7)
    expect(entry.layers[1].originY).toBe(9)
    expect(#(entry.layers[1].items or {})).toBe(1)
    expect(entry.layers[1].items[1].startAddr).toBe(0x1234)
    expect(entry.layers[1].items[1].dx).toBe(2)
    expect(entry.layers[1].items[1].dy).toBe(-1)
    expect(entry.layers[1].items[1].mirrorX).toBe(true)
    expect(entry.layers[1].items[1].mirrorY).toBe(true)
  end)

  it("omits mirror flags for OAM sprites when no UI mirror override was set", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({
      animated = true,
      oamBacked = true,
      numFrames = 1,
      cols = 32,
      rows = 30,
      spriteMode = "8x8",
      title = "OAM Snapshot No Mirror Flags",
    })

    win.layers[1].items = {
      {
        startAddr = 0x1234,
        bank = 1,
        tile = 42,
        paletteNumber = 3,
        mirrorX = true,
        mirrorY = false,
        _mirrorXOverrideSet = false,
        _mirrorYOverrideSet = false,
      }
    }

    local layout = GameArtController.snapshotLayout(wm, nil, 1)
    local item = layout.windows[1].layers[1].items[1]
    expect(item.mirrorX).toBeNil()
    expect(item.mirrorY).toBeNil()
  end)

  it("applies ROM displacement writes for oam_animation sprite layers", function()
    local startAddr = 30
    local romRaw = makeRom(128, {
      [startAddr + 0] = 10, -- Y
      [startAddr + 1] = 5,  -- tile
      [startAddr + 2] = 0,  -- attr
      [startAddr + 3] = 20, -- X
    })

    local win = {
      kind = "oam_animation",
      layers = {
        {
          kind = "sprite",
          items = {
            {
              startAddr = startAddr,
              baseX = 20,
              baseY = 10,
              dx = 3,
              dy = -2,
              oamTile = 5,
              attr = 0,
              paletteNumber = 4, -- low bits should become 3
              mirrorX = true,    -- set bit 6
              mirrorY = true,    -- set bit 7
            }
          },
        }
      },
      getSpriteLayers = function(self)
        return { { index = 1, layer = self.layers[1] } }
      end,
    }

    local updated, err = SpriteController.applyDisplacementsToROMForWindows({ win }, romRaw)
    expect(err).toBeNil()
    expect(updated).toBeTruthy()

    local out, readErr = chr.readBytesFromRange(updated, startAddr, startAddr + 3)
    expect(readErr).toBeNil()
    expect(out[1]).toBe(8)   -- 10 + (-2)
    expect(out[2]).toBe(5)   -- tile unchanged
    expect(out[3]).toBe(195) -- 128+64 + palette bits (3)
    expect(out[4]).toBe(23)  -- 20 + 3
  end)

  it("prefers explicit mirror override when shared startAddr appears in multiple windows", function()
    local startAddr = 70
    local romRaw = makeRom(128, {
      [startAddr + 0] = 10,
      [startAddr + 1] = 5,
      [startAddr + 2] = 0x40, -- mirrored in X
      [startAddr + 3] = 20,
    })

    local spriteWithOverride = {
      startAddr = startAddr,
      baseX = 20,
      baseY = 10,
      dx = 0,
      dy = 0,
      oamTile = 5,
      attr = 0x40,
      mirrorX = false,
      _mirrorXOverrideSet = true,
    }

    local staleSprite = {
      startAddr = startAddr,
      baseX = 20,
      baseY = 10,
      dx = 0,
      dy = 0,
      oamTile = 5,
      attr = 0x40,
      mirrorX = true,
      _mirrorXOverrideSet = false,
    }

    local winA = {
      kind = "oam_animation",
      layers = { { kind = "sprite", items = { staleSprite } } },
      getSpriteLayers = function(self)
        return { { index = 1, layer = self.layers[1] } }
      end,
    }
    local winB = {
      kind = "oam_animation",
      layers = { { kind = "sprite", items = { spriteWithOverride } } },
      getSpriteLayers = function(self)
        return { { index = 1, layer = self.layers[1] } }
      end,
    }

    local updated, err = SpriteController.applyDisplacementsToROMForWindows({ winA, winB }, romRaw)
    expect(err).toBeNil()
    expect(updated).toBeTruthy()

    local out, readErr = chr.readBytesFromRange(updated, startAddr, startAddr + 3)
    expect(readErr).toBeNil()
    expect(out[3]).toBe(0x00) -- mirrorX cleared from attr bit 6
  end)
end)
