local Window = require("user_interface.windows_system.window")
local MouseClickController = require("controllers.input.mouse_click_controller")

describe("chr odd-even selection mode", function()
  it("normalizes CHR selections to the top row of the 8x16 pair", function()
    local win = setmetatable({
      kind = "chr",
      orderMode = "oddEven",
      activeLayer = 1,
      selectedByLayer = {},
      cols = 16,
      rows = 32,
    }, { __index = Window })

    win:setSelected(3, 5, 1)

    local col, row, layer = win:getSelected()
    expect(col).toBe(3)
    expect(row).toBe(4)
    expect(layer).toBe(1)
  end)

  it("starts CHR drags from the top half when clicking the bottom half in 8x16 mode", function()
    local topTile = { id = "top", index = 10, _bankIndex = 1 }
    local bottomTile = { id = "bottom", index = 11, _bankIndex = 1 }
    local selected = nil
    local drag = {
      pending = false,
      active = false,
      tileGroup = nil,
    }
    local tileClick = { active = false }
    local spriteClick = { active = false }

    local win
    win = {
      kind = "chr",
      orderMode = "oddEven",
      cols = 16,
      rows = 32,
      layers = { { kind = "tile" } },
      getActiveLayerIndex = function() return 1 end,
      get = function(_, col, row)
        if col ~= 2 then return nil end
        if row == 4 then return topTile end
        if row == 5 then return bottomTile end
        return nil
      end,
      getStack = function(_, col, row)
        local item = win:get(col, row, 1)
        if item then return { item } end
        return nil
      end,
      setSelected = function(_, col, row, layerIdx)
        selected = { col = col, row = row, layerIdx = layerIdx }
      end,
      clearSelected = function() end,
    }

    local wm = {
      setFocus = function() end,
      getFocus = function() return nil end,
      windowAt = function() return win end,
    }
    local chrome = {
      handleToolbarClicks = function() return false end,
      handleHeaderClick = function() return false end,
      handleResizeHandle = function() return false end,
    }

    local handled = MouseClickController.handleMousePressed({
      ctx = {
        getMode = function() return "tile" end,
        wm = function() return wm end,
      },
      drag = drag,
      tilePaintState = {},
      utils = {
        ctrlDown = function() return false end,
        shiftDown = function() return false end,
        altDown = function() return false end,
        pickByVisual = function()
          return true, 2, 5, bottomTile
        end,
      },
      chrome = chrome,
      getTileClick = function() return tileClick end,
      setTileClick = function(v) tileClick = v end,
      getSpriteClick = function() return spriteClick end,
      setSpriteClick = function(v) spriteClick = v end,
    }, 0, 0, 1)

    expect(handled).toBe(true)
    expect(selected.col).toBe(2)
    expect(selected.row).toBe(4)
    expect(drag.srcCol).toBe(2)
    expect(drag.srcRow).toBe(4)
    expect(drag.item).toBe(topTile)
    expect(drag.tileGroup).toBeTruthy()
    expect(drag.tileGroup.sourceSelectionMode).toBe("8x16")
  end)
end)
