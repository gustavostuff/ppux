local CursorsController = require("controllers.input_support.cursors_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local SpriteController = require("controllers.sprite.sprite_controller")

describe("cursors_controller.lua", function()
  local originalLove
  local originalGetScaledMouse
  local originalPickSpriteAt

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
      return { x = 10, y = 10 }
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
      return { x = 10, y = 10 }
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
      return { x = 10, y = 10 }
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
      return { x = 10, y = 10 }
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
      return { x = 10, y = 10 }
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
      return { x = 10, y = 10 }
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
      return { x = 10, y = 10 }
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
      return { x = 10, y = 10 }
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

  it("uses arrow in edit mode over empty tile cells", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = 10 }
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

  it("uses arrow when any modal is visible", function()
    local setTo = nil
    love.mouse.setCursor = function(cursor) setTo = cursor end
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = 10 }
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
    expect(setTo).toBe("arrow")
  end)
end)
