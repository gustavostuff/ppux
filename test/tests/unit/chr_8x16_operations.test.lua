local MultiSelectController = require("controllers.input_support.multi_select_controller")
local TileSpriteOffsetController = require("controllers.input_support.tile_sprite_offset_controller")

describe("chr 8x16 operations", function()
  it("builds a single CHR odd-even drag as one logical 8x16 unit", function()
    local topTile = { index = 10, _bankIndex = 1 }
    local bottomTile = { index = 11, _bankIndex = 1 }
    local win = {
      kind = "chr",
      orderMode = "oddEven",
      cols = 2,
      rows = 4,
      layers = {
        { kind = "tile" },
      },
      get = function(_, col, row)
        if col ~= 0 then return nil end
        if row == 0 then return topTile end
        if row == 1 then return bottomTile end
        return nil
      end,
    }

    local group = MultiSelectController.buildTileDragGroup(win, 1, 0, 1)

    expect(group).toBeTruthy()
    expect(group.sourceSelectionMode).toBe("8x16")
    expect(group.anchorRow).toBe(0)
    expect(#group.entries).toBe(2)
    expect(#group.spriteEntries).toBe(1)
    expect(group.entries[1].item).toBe(topTile)
    expect(group.entries[2].item).toBe(bottomTile)
    expect(group.spriteEntries[1].item).toBe(topTile)
  end)

  it("offsets CHR odd-even pairs as one continuous 8x16 surface", function()
    local function makeTile(index)
      local pixels = {}
      for i = 1, 64 do pixels[i] = 0 end
      return {
        index = index,
        _bankIndex = 1,
        pixels = pixels,
        refreshImage = function() end,
      }
    end

    local topTile = makeTile(0)
    local bottomTile = makeTile(1)
    topTile.pixels[60] = 2 -- x=3, y=7

    local status
    local unsavedEvents = {}
    local focus = {
      kind = "chr",
      orderMode = "oddEven",
      rows = 4,
      layers = {
        { kind = "tile" },
      },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 1, 1 end,
      get = function(_, col, row)
        if col ~= 0 then return nil end
        if row == 0 then return topTile end
        if row == 1 then return bottomTile end
        return nil
      end,
    }
    local ctx = {
      getMode = function() return "tile" end,
      setStatus = function(msg) status = msg end,
      app = {
        appEditState = {
          tilesPool = {},
        },
        markUnsaved = function(_, eventType)
          unsavedEvents[#unsavedEvents + 1] = eventType
        end,
      },
    }

    local handled = TileSpriteOffsetController.handleKey("down", focus, ctx, {
      altDown = function() return true end,
      ctrlDown = function() return false end,
    })

    expect(handled).toBe(true)
    expect(topTile.pixels[60]).toBe(0)
    expect(bottomTile.pixels[4]).toBe(2)
    expect(status).toBe("Offset tile pixels down")
    expect(unsavedEvents[1]).toBe("pixel_edit")
  end)

  it("writes an 8x16 CHR pair shift into bank bytes and refreshes the bank canvas", function()
    local chr = require("chr")
    local Tile = require("ui.windows_system.tile_item")
    local BankCanvasSupport = require("controllers.chr.bank_canvas_support")

    local bankBytes = {}
    for i = 1, 32 do bankBytes[i] = 0 end

    local topTile = Tile.fromCHR(bankBytes, 0)
    topTile._bankBytesRef = bankBytes
    topTile._bankIndex = 1
    for i = 1, 64 do topTile.pixels[i] = 0 end
    topTile.pixels[60] = 2 -- x=3, y=7

    local bottomTile = Tile.fromCHR(bankBytes, 1)
    bottomTile._bankBytesRef = bankBytes
    bottomTile._bankIndex = 1
    for i = 1, 64 do bottomTile.pixels[i] = 0 end

    local invalidated = {}
    local originalInvalidate = BankCanvasSupport.invalidateTile
    BankCanvasSupport.invalidateTile = function(_, bank, tile)
      invalidated[#invalidated + 1] = { bank = bank, tile = tile }
    end

    local focus = {
      kind = "chr",
      isRomWindow = true,
      orderMode = "oddEven",
      rows = 4,
      layers = {
        { kind = "tile" },
      },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function(_, col, row)
        if col ~= 0 then return nil end
        if row == 0 then return topTile end
        if row == 1 then return bottomTile end
        return nil
      end,
    }
    local ctx = {
      getMode = function() return "tile" end,
      setStatus = function() end,
      app = {
        appEditState = { tilesPool = {} },
        markUnsaved = function() end,
      },
    }

    local handled = TileSpriteOffsetController.handleKey("down", focus, ctx, {
      altDown = function() return true end,
      ctrlDown = function() return false end,
    })

    BankCanvasSupport.invalidateTile = originalInvalidate

    expect(handled).toBe(true)
    local topPixels = chr.decodeTile(bankBytes, 0)
    local bottomPixels = chr.decodeTile(bankBytes, 1)
    expect(topPixels[60]).toBe(0)
    expect(bottomPixels[4]).toBe(2)
    expect(#invalidated).toBe(2)
    expect(invalidated[1].bank).toBe(1)
    expect(invalidated[1].tile).toBe(0)
    expect(invalidated[2].bank).toBe(1)
    expect(invalidated[2].tile).toBe(1)
  end)

  it("restores pixels that leave an 8x16 CHR pair or sprite viewport", function()
    local chr = require("chr")
    local Tile = require("ui.windows_system.tile_item")

    local function blankPair()
      local bankBytes = {}
      for i = 1, 32 do bankBytes[i] = 0 end
      local top = Tile.fromCHR(bankBytes, 0)
      local bot = Tile.fromCHR(bankBytes, 1)
      top._bankBytesRef = bankBytes
      bot._bankBytesRef = bankBytes
      top._bankIndex = 1
      bot._bankIndex = 1
      for i = 1, 64 do
        top.pixels[i] = 0
        bot.pixels[i] = 0
      end
      return bankBytes, top, bot
    end

    local function press(focus, key)
      return TileSpriteOffsetController.handleKey(key, focus, {
        getMode = function() return "tile" end,
        setStatus = function() end,
        app = { appEditState = { tilesPool = {} }, markUnsaved = function() end },
      }, {
        altDown = function() return true end,
        ctrlDown = function() return false end,
      })
    end

    local bankBytes, top, bot = blankPair()
    bot.pixels[60] = 2 -- bottom row, x=3
    local chrFocus = {
      kind = "chr",
      orderMode = "oddEven",
      rows = 4,
      layers = { { kind = "tile" } },
      getActiveLayerIndex = function() return 1 end,
      getSelected = function() return 0, 0, 1 end,
      get = function(_, col, row)
        if col ~= 0 then return nil end
        if row == 0 then return top end
        if row == 1 then return bot end
        return nil
      end,
    }

    expect(press(chrFocus, "down")).toBe(true)
    expect(bot.pixels[60]).toBe(0)
    expect(chr.decodeTile(bankBytes, 1)[60]).toBe(0)
    expect(press(chrFocus, "up")).toBe(true)
    expect(bot.pixels[60]).toBe(2)
    expect(chr.decodeTile(bankBytes, 1)[60]).toBe(2)

    top.pixels[1] = 3 -- top-left
    expect(press(chrFocus, "left")).toBe(true)
    expect(top.pixels[1]).toBe(0)
    expect(press(chrFocus, "right")).toBe(true)
    expect(top.pixels[1]).toBe(3)
    expect(chr.decodeTile(bankBytes, 0)[1]).toBe(3)

    local _, spriteTop, spriteBot = blankPair()
    spriteBot.pixels[60] = 1
    local spriteFocus = {
      kind = "oam_animation",
      layers = {
        {
          kind = "sprite",
          mode = "8x16",
          items = {
            { topRef = spriteTop, botRef = spriteBot, removed = false },
          },
          selectedSpriteIndex = 1,
        },
      },
      getActiveLayerIndex = function() return 1 end,
    }

    expect(press(spriteFocus, "down")).toBe(true)
    expect(spriteBot.pixels[60]).toBe(0)
    expect(press(spriteFocus, "up")).toBe(true)
    expect(spriteBot.pixels[60]).toBe(1)
  end)
end)
