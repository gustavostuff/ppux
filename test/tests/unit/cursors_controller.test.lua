local CursorsController = require("controllers.input_support.cursors_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local SpriteController = require("controllers.sprite.sprite_controller")

describe("cursors_controller.lua", function()
  local originalLove
  local originalGetScaledMouse
  local originalPickSpriteAt

  -- Default app top strip height when `_appTopToolbarLayout` is unset; keep mouse below it so
  -- tests are not spuriously "over" quick buttons at (0,0).
  local MY = 100

  beforeEach(function()
    originalLove = _G.love
    originalGetScaledMouse = ResolutionController.getScaledMouse
    originalPickSpriteAt = SpriteController.pickSpriteAt

    _G.love = _G.love or {}
    love.mouse = love.mouse or {}
    love.keyboard = love.keyboard or {}
    love.mouse.setCursor = function() end
    love.mouse.getPosition = function() return 0, 0 end
    love.keyboard.isDown = function() return false end
  end)

  afterEach(function()
    ResolutionController.getScaledMouse = originalGetScaledMouse
    SpriteController.pickSpriteAt = originalPickSpriteAt
    _G.love = originalLove
  end)

  it("uses arrow cursor by default in tile mode when not hovering tile/sprite", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local app = {
      hardwareCursors = { arrow = "arrow", hand = "hand" },
      wm = {
        windowAt = function() return nil end,
      },
    }

    CursorsController.applyModeCursor(app, "tile")
    expect(setTo).toBe("arrow")
  end)

  it("uses hand cursor in tile mode when hovering a tile item", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local layer = { kind = "tile", removedCells = {} }
    local win = {
      cols = 4,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 0, 0 end,
      get = function() return { id = "tile" } end,
    }

    local app = {
      hardwareCursors = { arrow = "arrow", hand = "hand" },
      wm = {
        windowAt = function() return win end,
      },
    }

    CursorsController.applyModeCursor(app, "tile")
    expect(setTo).toBe("hand")
  end)

  it("uses hand cursor in tile mode when hovering a sprite item", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end
    SpriteController.pickSpriteAt = function()
      return 1, 2, 0, 0
    end

    local layer = { kind = "sprite", items = {} }
    local win = {
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    local app = {
      hardwareCursors = { arrow = "arrow", hand = "hand" },
      wm = {
        windowAt = function() return win end,
      },
    }

    CursorsController.applyModeCursor(app, "tile")
    expect(setTo).toBe("hand")
  end)

  it("uses arrow in edit mode when not over any window content", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local app = {
      hardwareCursors = { arrow = "arrow", pencil = "pencil" },
      wm = {
        windowAt = function() return nil end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("arrow")
  end)

  it("uses arrow in edit mode over palette windows", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local win = { isPalette = true, kind = "palette" }
    local app = {
      hardwareCursors = { arrow = "arrow", pencil = "pencil" },
      wm = {
        windowAt = function() return win end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("arrow")
  end)

  it("uses arrow in edit mode over window header", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local layer = { kind = "tile" }
    local win = {
      isPalette = false,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 0, 0 end,
      isInHeader = function() return true end,
    }

    local app = {
      hardwareCursors = { arrow = "arrow", pencil = "pencil" },
      wm = {
        windowAt = function() return win end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("arrow")
  end)

  it("uses pencil in edit mode over tile layer content", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local layer = { kind = "tile", removedCells = {} }
    local win = {
      isPalette = false,
      cols = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 1, 2 end,
      get = function() return { id = "tile" } end,
      isInHeader = function() return false end,
    }

    local app = {
      hardwareCursors = { arrow = "arrow", pencil = "pencil" },
      wm = {
        windowAt = function() return win end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("pencil")
  end)

  it("uses pick/fill in edit mode over layer content when G/F are held", function()
    local setTo = nil
    local grab = false
    local fill = false
    love.mouse.setCursor = function(cursor) setTo = cursor end
    love.keyboard.isDown = function(key)
      if key == "g" then return grab end
      if key == "f" then return fill end
      return false
    end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local layer = { kind = "tile", removedCells = {} }
    local win = {
      isPalette = false,
      cols = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 1, 2 end,
      get = function() return { id = "tile" } end,
      isInHeader = function() return false end,
    }

    local app = {
      hardwareCursors = { arrow = "arrow", pencil = "pencil", pick = "pick", fill = "fill" },
      wm = {
        windowAt = function() return win end,
      },
    }

    grab = true
    fill = false
    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("pick")

    grab = false
    fill = true
    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("fill")
  end)

  it("uses the color_select cursor when C is held over editable content", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    love.keyboard.isDown = function(key)
      return key == "c"
    end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local layer = { kind = "tile", removedCells = {} }
    local win = {
      isPalette = false,
      cols = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 1, 2 end,
      get = function() return { id = "tile" } end,
      isInHeader = function() return false end,
    }

    local app = {
      hardwareCursors = {
        arrow = "arrow",
        pencil = "pencil",
        pick = "pick",
        color_select = "color_select",
      },
      wm = {
        windowAt = function() return win end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("color_select")
  end)

  it("uses the rect cursor when the sketch select tool is active in edit mode", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    love.keyboard.isDown = function() return false end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local layer = { kind = "tile", removedCells = {} }
    local win = {
      isPalette = false,
      cols = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 1, 2 end,
      get = function() return { id = "tile" } end,
      isInHeader = function() return false end,
    }

    local app = {
      editTool = "rect_select",
      hardwareCursors = { arrow = "arrow", pencil = "pencil", rect_fill = "rect_fill" },
      wm = {
        windowAt = function() return win end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("rect_fill")
  end)

  it("uses the rect cursor for sketch select even when not hovering content", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    love.keyboard.isDown = function() return false end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local app = {
      editTool = "rect_select",
      hardwareCursors = { arrow = "arrow", pencil = "pencil", rect_fill = "rect_fill", hand = "hand" },
      wm = {
        windowAt = function() return nil end,
        getFocus = function() return nil end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("rect_fill")
  end)

  it("uses hand over an active sketch pixel selection and rect outside it", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    love.keyboard.isDown = function() return false end

    local win = {
      kind = "sketch_canvas",
      isPalette = false,
      layers = { { kind = "canvas", canvas = true } },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 0, 0 end,
      toContentCoords = function(_, x, y)
        return true, x, y
      end,
      isInHeader = function() return false end,
      pixelSelection = { x = 2, y = 2, w = 4, h = 4 },
    }

    local app = {
      editTool = "rect_select",
      hardwareCursors = { arrow = "arrow", pencil = "pencil", rect_fill = "rect_fill", hand = "hand" },
      wm = {
        windowAt = function() return win end,
        getFocus = function() return win end,
      },
    }

    ResolutionController.getScaledMouse = function()
      return { x = 3, y = 3 }
    end
    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("hand")

    ResolutionController.getScaledMouse = function()
      return { x = 20, y = 20 }
    end
    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("rect_fill")

    -- While move-dragging, keep the hand even if the pointer leaves the AABB briefly.
    win.pixelSelection.moveDrag = { grabX = 3, grabY = 3, origOffsetX = 2, origOffsetY = 2 }
    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("hand")
  end)

  it("uses arrow in edit mode over empty tile cells", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local layer = { kind = "tile", removedCells = {} }
    local win = {
      isPalette = false,
      cols = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 1, 2 end,
      get = function() return nil end,
      isInHeader = function() return false end,
    }

    local app = {
      hardwareCursors = { arrow = "arrow", pencil = "pencil" },
      wm = {
        windowAt = function() return win end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("arrow")
  end)

  it("does not force arrow when a modal is visible (edit cursor still applies over content)", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local layer = { kind = "tile", removedCells = {} }
    local win = {
      isPalette = false,
      cols = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 1, 2 end,
      get = function() return { id = "tile" } end,
      isInHeader = function() return false end,
    }

    local app = {
      hardwareCursors = { arrow = "arrow", pencil = "pencil", hand = "hand" },
      wm = {
        windowAt = function() return win end,
      },
      quitConfirmModal = {
        isVisible = function() return true end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("pencil")
  end)

  it("does not force arrow when PPU frame range/add-sprite modals are visible", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local layer = { kind = "tile", removedCells = {} }
    local win = {
      isPalette = false,
      cols = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 1, 2 end,
      get = function() return { id = "tile" } end,
      isInHeader = function() return false end,
    }

    local app = {
      hardwareCursors = { arrow = "arrow", pencil = "pencil", hand = "hand" },
      wm = {
        windowAt = function() return win end,
      },
      ppuFrameRangeModal = {
        isVisible = function() return true end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("pencil")

    app.ppuFrameRangeModal = { isVisible = function() return false end }
    app.ppuFrameAddSpriteModal = { isVisible = function() return true end }
    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("pencil")
  end)

  it("uses arrow over window content while reference tracing view is active", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = MY }
    end

    local layer = { kind = "tile", removedCells = {} }
    local win = {
      isPalette = false,
      referenceDisplayReference = true,
      referenceImageStoredPath = "/tmp/ref.png",
      referenceImageDrawable = {},
      cols = 8,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 1, 2 end,
      get = function() return { id = "tile" } end,
      isInHeader = function() return false end,
      isInContentArea = function() return true end,
    }

    local app = {
      hardwareCursors = { arrow = "arrow", pencil = "pencil", hand = "hand" },
      wm = {
        windowAt = function() return win end,
      },
    }

    CursorsController.applyModeCursor(app, "edit")
    expect(setTo).toBe("arrow")

    CursorsController.applyModeCursor(app, "tile")
    expect(setTo).toBe("arrow")
  end)

  it("does not apply hardware cursor changes from CursorsController.update", function()
    local setCalls = 0
    love.mouse.setCursor = function()
      setCalls = setCalls + 1
    end

    local app = {
      mode = "edit",
      hardwareCursors = { arrow = "arrow", pencil = "pencil" },
      wm = {
        windowAt = function() return nil end,
      },
    }

    CursorsController.update(app)
    expect(setCalls).toBe(0)
  end)

  it("uses hand cursor on Swap 2 colors modal only over ramp swatches", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end

    local modal = {
      isVisible = function() return true end,
      _containsBox = function() return true end,
      isHoveringColorRampSwatchAt = function(_, x, y)
        return x == 20 and y == MY
      end,
      panel = {
        getButtonAt = function(_, x, y)
          if x == 80 and y == MY then
            return { text = "Swap" }
          end
          return nil
        end,
        getComponentAt = function() return { id = "contentRow" } end,
        isHoveringDisabledButtonAt = function() return false end,
      },
    }

    local app = {
      hardwareCursors = { arrow = "arrow", hand = "hand", unavailable = "unavailable" },
      swapTwoColorsModal = modal,
      wm = {
        windowAt = function() return nil end,
      },
    }

    ResolutionController.getScaledMouse = function()
      return { x = 20, y = MY }
    end
    CursorsController.applyModeCursor(app, "tile")
    expect(setTo).toBe("hand")

    ResolutionController.getScaledMouse = function()
      return { x = 80, y = MY }
    end
    CursorsController.applyModeCursor(app, "tile")
    expect(setTo).toBe("hand")

    ResolutionController.getScaledMouse = function()
      return { x = 50, y = MY }
    end
    CursorsController.applyModeCursor(app, "tile")
    expect(setTo).toBe("arrow")
  end)
end)
