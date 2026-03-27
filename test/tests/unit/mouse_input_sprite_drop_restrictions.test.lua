local MouseInput = require("controllers.input.mouse_input")
local SpriteController = require("controllers.sprite.sprite_controller")

describe("mouse_input.lua - sprite drop restrictions", function()
  local originalMouseIsDown
  local originalAddSpriteToLayer
  local originalSetSpriteSelection

  local function runDropScenario(targetKind)
    local draggedTile = { index = 7, _bankIndex = 1 }
    local addCalls = 0
    local addArgs = nil
    local selectionCalls = 0
    SpriteController.addSpriteToLayer = function(layer, tile, pixelX, pixelY)
      addCalls = addCalls + 1
      addArgs = { layer = layer, tile = tile, pixelX = pixelX, pixelY = pixelY }
      layer.items[#layer.items + 1] = { tile = tile, worldX = pixelX, worldY = pixelY }
      return #layer.items
    end
    SpriteController.setSpriteSelection = function()
      selectionCalls = selectionCalls + 1
    end

    local srcLayer = { kind = "tile", items = { [1] = draggedTile } }
    local srcWin = {
      kind = "chr",
      _closed = false,
      x = 0, y = 0, zoom = 1, cellW = 8, cellH = 8,
      cols = 1, rows = 1, scrollCol = 0, scrollRow = 0,
      layers = { srcLayer },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
      hitResizeHandle = function() return false end,
      toGridCoords = function() return true, 0, 0 end,
      get = function() return draggedTile end,
      getStack = function() return { draggedTile } end,
      setSelected = function() end,
      clearSelected = function() end,
    }

    local dstLayer = { kind = "sprite", items = {} }
    local dstWin = {
      kind = targetKind,
      _closed = false,
      x = 20, y = 0, zoom = 1, cellW = 8, cellH = 8,
      cols = 8, rows = 8, scrollCol = 0, scrollRow = 0,
      layers = { dstLayer },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
      hitResizeHandle = function() return false end,
      setSelected = function() end,
    }

    local focused = nil
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, w) focused = w end,
      windowAt = function(_, x)
        if x < 20 then return srcWin end
        return dstWin
      end,
      getWindows = function() return { srcWin, dstWin } end,
    }

    local app = {
      appEditState = {
        tilesPool = { [1] = { [7] = draggedTile } },
      },
      statusText = "",
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
      app = app,
      setStatus = function(text)
        app.statusText = text
      end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(win)
        if win == srcWin then
          return true, 0, 0, draggedTile
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 10, 1)
    MouseInput.mousemoved(30, 10, 20, 0)
    MouseInput.mousereleased(30, 10, 1)

    return {
      addCalls = addCalls,
      addArgs = addArgs,
      selectionCalls = selectionCalls,
      dstLayer = dstLayer,
      app = app,
      draggedTile = draggedTile,
    }
  end

  beforeEach(function()
    if not _G.love then _G.love = {} end
    love.mouse = love.mouse or {}
    originalMouseIsDown = love.mouse.isDown
    love.mouse.isDown = function(btn) return btn == 1 end

    originalAddSpriteToLayer = SpriteController.addSpriteToLayer
    originalSetSpriteSelection = SpriteController.setSpriteSelection
  end)

  afterEach(function()
    if love and love.mouse then
      love.mouse.isDown = originalMouseIsDown
    end
    SpriteController.addSpriteToLayer = originalAddSpriteToLayer
    SpriteController.setSpriteSelection = originalSetSpriteSelection
  end)

  it("blocks CHR drop onto sprite layers in PPU frame windows", function()
    local res = runDropScenario("ppu_frame")
    expect(res.addCalls).toBe(0)
    expect(#res.dstLayer.items).toBe(0)
    expect(res.app.statusText).toBe("Cannot drop items onto sprite layers in this window")
  end)

  it("blocks CHR drop onto sprite layers in OAM animation windows", function()
    local res = runDropScenario("oam_animation")
    expect(res.addCalls).toBe(0)
    expect(#res.dstLayer.items).toBe(0)
    expect(res.app.statusText).toBe("Cannot drop items onto sprite layers in this window")
  end)

  it("allows CHR drop onto sprite layers in static_art and animation windows", function()
    local cases = { "static_art", "animation" }

    for _, kind in ipairs(cases) do
      local res = runDropScenario(kind)
      expect(res.addCalls).toBe(1)
      expect(res.selectionCalls).toBe(1)
      expect(#res.dstLayer.items).toBe(1)
      expect(res.addArgs).toBeTruthy()
      expect(res.addArgs.tile).toBe(res.draggedTile)
      expect(res.app.statusText).toBe("")
    end
  end)
end)
