local MouseClickController = require("controllers.input.mouse_click_controller")
local SpriteController = require("controllers.sprite.sprite_controller")

describe("mouse_click_controller.lua - PPU sprite empty space", function()
  local originalPickSpriteAt

  beforeEach(function()
    originalPickSpriteAt = SpriteController.pickSpriteAt
  end)

  afterEach(function()
    SpriteController.pickSpriteAt = originalPickSpriteAt
  end)

  it("does not start a nametable tile-drag ghost when dragging empty sprite space", function()
    SpriteController.pickSpriteAt = function()
      return nil
    end

    local ntLayer = {
      kind = "tile",
      nametableStartAddr = 0x2000,
      nametableEndAddr = 0x23bf,
      patternTable = { ranges = { { bank = 1, from = 0, to = 255 } } },
      items = {},
    }
    local spriteLayer = {
      kind = "sprite",
      items = {},
      selectedSpriteIndex = 1,
    }
    local tileItem = { index = 3, _byte = 3 }
    local win = {
      kind = "ppu_frame",
      _closed = false,
      _minimized = false,
      layers = { ntLayer, spriteLayer },
      activeLayer = 2,
      getActiveLayerIndex = function()
        return 2
      end,
      toGridCoords = function()
        return true, 1, 0
      end,
      get = function()
        return tileItem
      end,
      getVirtualTileHandle = function()
        return tileItem
      end,
      setSelected = function() end,
      clearSelected = function() end,
      isPatternTableInteractionLocked = function()
        return false
      end,
    }

    local drag = {
      pending = false,
      active = false,
      item = nil,
    }
    local wm = {
      setFocus = function() end,
      getFocus = function()
        return win
      end,
      getWindows = function()
        return { win }
      end,
      windowAt = function()
        return win
      end,
    }

    local env = {
      ctx = {
        wm = function()
          return wm
        end,
        getMode = function()
          return "tile"
        end,
        app = {},
      },
      drag = drag,
      tilePaintState = { active = false },
      utils = {
        pickByVisual = function()
          return true, 1, 0, tileItem
        end,
        ctrlDown = function()
          return false
        end,
        shiftDown = function()
          return false
        end,
      },
      chrome = {
        findToolbarWindowAt = function()
          return nil
        end,
        getTopInteractiveWindowAt = function()
          return win
        end,
        getTopInteractiveSurfaceWindowAt = function()
          return win
        end,
        handleToolbarClicks = function()
          return false
        end,
        handleResizeHandle = function()
          return false
        end,
        handleHeaderClick = function()
          return false
        end,
      },
      getTileClick = function()
        return { active = false }
      end,
      setTileClick = function() end,
      getSpriteClick = function()
        return { active = false }
      end,
      setSpriteClick = function() end,
      beginContextMenuClick = function() end,
    }

    expect(MouseClickController.handleMousePressed(env, 20, 20, 1)).toBe(true)
    expect(drag.pending).toBe(false)
    expect(drag.item).toBeNil()
  end)
end)
