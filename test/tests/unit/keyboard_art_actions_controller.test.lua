local KeyboardArtActionsController = require("controllers.input.keyboard_art_actions_controller")
local TileSpriteOffsetController = require("controllers.input_support.tile_sprite_offset_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local chr = require("chr")

describe("keyboard_art_actions_controller.lua", function()
  local originals
  local statusMessages

  beforeEach(function()
    statusMessages = {}
    originals = {
      offsetHandleKey = TileSpriteOffsetController.handleKey,
      dupGetSyncGroup = ChrDuplicateSync.getSyncGroup,
      dupIsEnabled = ChrDuplicateSync.isEnabled,
      dupUpdateTiles = ChrDuplicateSync.updateTiles,
      spriteGetSelected = SpriteController.getSelectedSpriteIndices,
      spriteSyncShared = SpriteController.syncSharedOAMSpriteState,
      writeByteToAddress = chr.writeByteToAddress,
      nametableModule = package.loaded["controllers.ppu.nametable_tiles_controller"],
    }
  end)

  afterEach(function()
    TileSpriteOffsetController.handleKey = originals.offsetHandleKey
    ChrDuplicateSync.getSyncGroup = originals.dupGetSyncGroup
    ChrDuplicateSync.isEnabled = originals.dupIsEnabled
    ChrDuplicateSync.updateTiles = originals.dupUpdateTiles
    SpriteController.getSelectedSpriteIndices = originals.spriteGetSelected
    SpriteController.syncSharedOAMSpriteState = originals.spriteSyncShared
    chr.writeByteToAddress = originals.writeByteToAddress
    package.loaded["controllers.ppu.nametable_tiles_controller"] = originals.nametableModule
  end)

  it("delegates pixel offset handling to tile_sprite_offset_controller", function()
    local captured
    TileSpriteOffsetController.handleKey = function(key, focus, ctx, utils)
      captured = { key = key, focus = focus, ctx = ctx, utils = utils }
      return true
    end

    local ctx = {}
    local utils = {}
    local focus = { name = "focus" }
    local handled = KeyboardArtActionsController.handlePixelOffset(ctx, utils, "left", focus)

    expect(handled).toBeTruthy()
    expect(captured.key).toBe("left")
    expect(captured.focus).toBe(focus)
    expect(captured.ctx).toBe(ctx)
    expect(captured.utils).toBe(utils)
  end)

  it("rotates tile palette values across duplicate sync group and updates status", function()
    local rotated = {}
    local updateTargets

    local pixelsA = {}
    local pixelsB = {}
    for i = 1, 64 do
      pixelsA[i] = 0
      pixelsB[i] = 0
    end

    local tileA = {
      _bankIndex = 1,
      index = 10,
      pixels = pixelsA,
      rotatePaletteValues = function(self, direction)
        rotated[#rotated + 1] = { tile = "A", dir = direction }
        return true
      end,
    }
    local tileB = {
      index = 11,
      pixels = pixelsB,
      rotatePaletteValues = function(self, direction)
        rotated[#rotated + 1] = { tile = "B", dir = direction }
        return true
      end,
    }

    ChrDuplicateSync.isEnabled = function() return true end
    ChrDuplicateSync.getSyncGroup = function()
      return {
        { bank = 1, tileIndex = 10 },
        { bank = 1, tileIndex = 11 },
      }
    end
    ChrDuplicateSync.updateTiles = function(state, targets)
      updateTargets = targets
    end

    local ctx = {
      setStatus = function(text)
        statusMessages[#statusMessages + 1] = text
      end,
      app = {
        syncDuplicateTiles = true,
        appEditState = {
          tilesPool = {
            [1] = {
              [11] = tileB,
            }
          }
        }
      }
    }
    local focus = {
      getSelected = function() return 0, 0, 1 end,
      get = function() return tileA end,
    }

    local handled = KeyboardArtActionsController.handleTileRotation(ctx, {
      shiftDown = function() return true end
    }, "right", focus)

    expect(handled).toBeTruthy()
    expect(#rotated).toBe(2)
    expect(rotated[1].dir).toBe(1)
    expect(rotated[2].dir).toBe(1)
    expect(updateTargets).toBeTruthy()
    expect(#updateTargets).toBe(2)
    expect(statusMessages[#statusMessages]).toBe("Rotated tile palette values right")
  end)

  it("rotates both halves of a CHR 8x16 selection as one logical item", function()
    local rotated = {}
    local topTile = {
      _bankIndex = 1,
      index = 20,
      pixels = {},
      rotatePaletteValues = function(self, direction)
        rotated[#rotated + 1] = { tile = "top", dir = direction }
        return true
      end,
    }
    local bottomTile = {
      _bankIndex = 1,
      index = 21,
      pixels = {},
      rotatePaletteValues = function(self, direction)
        rotated[#rotated + 1] = { tile = "bottom", dir = direction }
        return true
      end,
    }
    for i = 1, 64 do
      topTile.pixels[i] = 0
      bottomTile.pixels[i] = 0
    end

    ChrDuplicateSync.isEnabled = function() return false end
    ChrDuplicateSync.getSyncGroup = function() return {} end

    local ctx = {
      setStatus = function(text)
        statusMessages[#statusMessages + 1] = text
      end,
      app = {
        appEditState = {
          tilesPool = {
            [1] = {
              [20] = topTile,
              [21] = bottomTile,
            },
          },
        },
      },
    }
    local focus = {
      kind = "chr",
      orderMode = "oddEven",
      rows = 4,
      layers = { { kind = "tile" } },
      getSelected = function() return 0, 1, 1 end,
      get = function(_, col, row)
        if col ~= 0 then return nil end
        if row == 0 then return topTile end
        if row == 1 then return bottomTile end
        return nil
      end,
    }

    local handled = KeyboardArtActionsController.handleTileRotation(ctx, {
      shiftDown = function() return true end
    }, "left", focus)

    expect(handled).toBeTruthy()
    expect(#rotated).toBe(2)
    expect(rotated[1].tile).toBe("top")
    expect(rotated[2].tile).toBe("bottom")
    expect(statusMessages[#statusMessages]).toBe("Rotated tile palette values left")
  end)

  it("assigns sprite palette numbers and syncs shared OAM state", function()
    local syncCalls = {}
    local romWrites = {}
    local layer = {
      kind = "sprite",
      selectedSpriteIndex = 1,
      items = {
        [1] = {
          paletteNumber = 1,
          attr = 0xC0,
          mirrorX = true,
          mirrorY = true,
          startAddr = 0x100,
        }
      }
    }
    local w = {
      kind = "animation",
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    SpriteController.getSelectedSpriteIndices = function() return { 1 } end
    SpriteController.syncSharedOAMSpriteState = function(win, sprite, opts)
      syncCalls[#syncCalls + 1] = { win = win, sprite = sprite, opts = opts }
    end
    chr.writeByteToAddress = function(romRaw, address, value)
      romWrites[#romWrites + 1] = { address = address, value = value }
      return "patched-rom"
    end

    local ctx = {
      getMode = function() return "tile" end,
      setStatus = function(text)
        statusMessages[#statusMessages + 1] = text
      end,
    }
    local appEditState = { romRaw = "orig-rom" }
    local handled = KeyboardArtActionsController.handlePaletteNumberAssignment(ctx, "3", w, appEditState)

    expect(handled).toBeTruthy()
    expect(layer.items[1].paletteNumber).toBe(3)
    expect(layer.items[1].attr).toBe(0xC2)
    expect(#syncCalls).toBe(1)
    expect(syncCalls[1].opts.syncVisual).toBeTruthy()
    expect(syncCalls[1].opts.syncAttr).toBeTruthy()
    expect(#romWrites).toBe(1)
    expect(romWrites[1].address).toBe(0x102)
    expect(romWrites[1].value).toBe(0xC2)
    expect(appEditState.romRaw).toBe("patched-rom")
    expect(statusMessages[#statusMessages]).toBe("Sprite palette set to 3")
  end)

  it("routes palette assignment to nametable tiles for tile layers", function()
    local calls = {}
    package.loaded["controllers.ppu.nametable_tiles_controller"] = {
      setPaletteNumberForTile = function(w, layer, col, row, paletteNum)
        calls[#calls + 1] = { w = w, layer = layer, col = col, row = row, paletteNum = paletteNum }
        return true
      end
    }

    local layer = { kind = "tile", paletteData = {} }
    local w = {
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 2, 3, 1 end,
    }
    local ctx = {
      getMode = function() return "tile" end,
      setStatus = function(text)
        statusMessages[#statusMessages + 1] = text
      end,
    }

    local handled = KeyboardArtActionsController.handlePaletteNumberAssignment(ctx, "4", w, {})

    expect(handled).toBeTruthy()
    expect(#calls).toBe(1)
    expect(calls[1].col).toBe(2)
    expect(calls[1].row).toBe(3)
    expect(calls[1].paletteNum).toBe(4)
    expect(statusMessages[#statusMessages]).toBe("Tile palette set to 4")
  end)

  it("applies palette assignment to all selected tile cells", function()
    local calls = {}
    package.loaded["controllers.ppu.nametable_tiles_controller"] = {
      setPaletteNumberForTile = function(w, layer, col, row, paletteNum)
        calls[#calls + 1] = { w = w, layer = layer, col = col, row = row, paletteNum = paletteNum }
        return true
      end
    }

    local layer = {
      kind = "tile",
      multiTileSelection = {
        [4] = true,  -- col=0,row=1 when cols=3
        [9] = true,  -- col=2,row=2 when cols=3
      },
    }
    local w = {
      cols = 3,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 1, 0, 1 end,
    }
    local ctx = {
      getMode = function() return "tile" end,
      setStatus = function(text)
        statusMessages[#statusMessages + 1] = text
      end,
    }

    local handled = KeyboardArtActionsController.handlePaletteNumberAssignment(ctx, "2", w, {})

    expect(handled).toBeTruthy()
    expect(#calls).toBe(2)
    expect(calls[1].col).toBe(0)
    expect(calls[1].row).toBe(1)
    expect(calls[1].paletteNum).toBe(2)
    expect(calls[2].col).toBe(2)
    expect(calls[2].row).toBe(2)
    expect(calls[2].paletteNum).toBe(2)
    expect(statusMessages[#statusMessages]).toBe("Tile palettes set to 2")
  end)
end)
