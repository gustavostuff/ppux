local WM = require("controllers.window.window_controller")
local GameArtController = require("controllers.game_art.game_art_controller")
local SpriteController = require("controllers.sprite.sprite_controller")

describe("game_art_controller.lua - static sprite window persistence", function()
  local previousCtx

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = nil
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("round-trips sprite items in static_art windows through snapshot/load", function()
    local sourceWM = WM.new()
    local sourceWin = sourceWM:createSpriteWindow({
      animated = false,
      title = "Static Sprites Persist",
      cols = 16,
      rows = 16,
      spriteMode = "8x8",
    })

    local sourceLayer = sourceWin.layers[1]
    expect(sourceWin.kind).toBe("static_art")
    expect(sourceLayer.kind).toBe("sprite")

    -- Simulate drag-drop from CHR by using SpriteController helper.
    local sourceTilesPool = {
      [1] = {
        [42] = { _bankIndex = 1, index = 42 },
      },
    }
    local addedIndex = SpriteController.addSpriteToLayer(sourceLayer, sourceTilesPool[1][42], 12, 20, sourceTilesPool)
    expect(addedIndex).toBe(1)

    local layout = GameArtController.snapshotLayout(sourceWM, nil, 1)
    expect(layout).toBeTruthy()
    expect(#layout.windows).toBe(1)
    expect(layout.windows[1].kind).toBe("static_art")
    expect(layout.windows[1].layers[1].kind).toBe("sprite")
    expect(#layout.windows[1].layers[1].items).toBe(1)
    expect(layout.windows[1].layers[1].items[1].bank).toBe(1)
    expect(layout.windows[1].layers[1].items[1].tile).toBe(42)
    expect(layout.windows[1].layers[1].items[1].x).toBe(12)
    expect(layout.windows[1].layers[1].items[1].y).toBe(20)

    local targetWM = WM.new()
    local targetTilesPool = {
      [1] = {
        [42] = { _bankIndex = 1, index = 42 },
      },
    }
    local function ensureTiles(bank)
      targetTilesPool[bank] = targetTilesPool[bank] or {}
    end

    local result, err = GameArtController.buildWindowsFromLayout(layout, {
      wm = targetWM,
      tilesPool = targetTilesPool,
      ensureTiles = ensureTiles,
      romRaw = "",
    })
    expect(err).toBeNil()
    expect(result).toBeTruthy()

    local targetWin = targetWM:getWindows()[1]
    expect(targetWin.kind).toBe("static_art")
    expect(targetWin.title).toBe("Static Sprites Persist")
    expect(targetWin.layers[1].kind).toBe("sprite")
    expect(#targetWin.layers[1].items).toBe(1)

    local loadedSprite = targetWin.layers[1].items[1]
    expect(loadedSprite.bank).toBe(1)
    expect(loadedSprite.tile).toBe(42)
    expect(loadedSprite.x).toBe(12)
    expect(loadedSprite.y).toBe(20)
    expect(loadedSprite.topRef).toBeTruthy()
  end)
end)
