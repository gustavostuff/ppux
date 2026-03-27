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
end)
