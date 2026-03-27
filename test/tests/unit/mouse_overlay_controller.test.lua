local MouseOverlayController = require("controllers.input.mouse_overlay_controller")

describe("mouse_overlay_controller.lua", function()
  local originalScaledMouse

  beforeEach(function()
    if not _G.love then _G.love = {} end
    love.graphics = love.graphics or {}
    love.graphics.setColor = love.graphics.setColor or function() end
    love.graphics.push = love.graphics.push or function() end
    love.graphics.pop = love.graphics.pop or function() end
    love.graphics.translate = love.graphics.translate or function() end
    love.graphics.scale = love.graphics.scale or function() end

    local ResolutionController = require("controllers.app.resolution_controller")
    originalScaledMouse = ResolutionController.getScaledMouse
    ResolutionController.getScaledMouse = function()
      return { x = 4, y = 4 }
    end
  end)

  afterEach(function()
    local ResolutionController = require("controllers.app.resolution_controller")
    ResolutionController.getScaledMouse = originalScaledMouse
  end)

  it("draws both halves for single CHR previews over 8x16 sprite layers", function()
    local drawTop = 0
    local drawBottom = 0
    local topTile = {
      index = 4,
      _bankIndex = 1,
      draw = function() drawTop = drawTop + 1 end,
    }
    local bottomTile = {
      index = 5,
      _bankIndex = 1,
      draw = function() drawBottom = drawBottom + 1 end,
    }
    local win = {
      kind = "static_art",
      x = 0, y = 0, zoom = 1, cellW = 8, cellH = 8,
      scrollCol = 0, scrollRow = 0,
      layers = { { kind = "sprite", mode = "8x16" } },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 0, 0 end,
      isInContentArea = function() return true end,
    }
    local wm = {
      windowAt = function() return win end,
    }

    MouseOverlayController.drawOverlay({
      ctx = {
        wm = function() return wm end,
        app = {
          appEditState = {
            tilesPool = {
              [1] = {
                [4] = topTile,
                [5] = bottomTile,
              },
            },
          },
        },
      },
      drag = {
        active = true,
        srcWin = { kind = "chr" },
        item = topTile,
        ghostAlpha = 0.5,
        currentX = 4,
        currentY = 4,
      },
    })

    expect(drawTop).toBeGreaterThan(0)
    expect(drawBottom).toBeGreaterThan(0)
  end)

  it("draws both halves for grouped CHR 8x16 previews over 8x16 sprite layers", function()
    local drawTop = 0
    local drawBottom = 0
    local topTile = {
      index = 8,
      _bankIndex = 1,
      draw = function() drawTop = drawTop + 1 end,
    }
    local bottomTile = {
      index = 9,
      _bankIndex = 1,
      draw = function() drawBottom = drawBottom + 1 end,
    }
    local win = {
      kind = "static_art",
      x = 0, y = 0, zoom = 1, cellW = 8, cellH = 8,
      scrollCol = 0, scrollRow = 0,
      layers = { { kind = "sprite", mode = "8x16" } },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 0, 0 end,
      isInContentArea = function() return true end,
    }
    local wm = {
      windowAt = function() return win end,
    }

    MouseOverlayController.drawOverlay({
      ctx = {
        wm = function() return wm end,
        app = {
          appEditState = {
            tilesPool = {
              [1] = {
                [8] = topTile,
                [9] = bottomTile,
              },
            },
          },
        },
      },
      drag = {
        active = true,
        srcWin = { kind = "chr" },
        item = topTile,
        tileGroup = {
          entries = {
            { item = topTile, offsetCol = 0, offsetRow = 0 },
            { item = bottomTile, offsetCol = 0, offsetRow = 1 },
          },
          sourceSelectionMode = "8x16",
          spriteEntries = {
            { item = topTile, bottomItem = bottomTile, offsetCol = 0, offsetRow = 0 },
          },
        },
        ghostAlpha = 0.5,
        currentX = 4,
        currentY = 4,
      },
      isSpriteLayerDropBlocked = function() return false end,
    })

    expect(drawTop).toBeGreaterThan(0)
    expect(drawBottom).toBeGreaterThan(0)
  end)
end)
