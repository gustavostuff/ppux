local MouseInput = require("controllers.input.mouse_input")
local ResolutionController = require("controllers.app.resolution_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

local function makeTileWindow()
  local cols = 4
  local layer = {
    kind = "tile",
    items = {},
  }

  local function idx(col, row)
    return row * cols + col + 1
  end

  local win = {
    kind = "static_art",
    _closed = false,
    x = 0,
    y = 0,
    zoom = 1,
    cellW = 8,
    cellH = 8,
    cols = cols,
    rows = 4,
    scrollCol = 0,
    scrollRow = 0,
    layers = { layer },
    getActiveLayerIndex = function() return 1 end,
    getLayer = function(_, li) return layer end,
    isInHeader = function() return false end,
    get = function(_, col, row, _)
      return layer.items[idx(col, row)]
    end,
    set = function(_, col, row, item, _)
      layer.items[idx(col, row)] = item
    end,
    getStack = function(_, col, row, _)
      local item = layer.items[idx(col, row)]
      if item then return { item } end
      return nil
    end,
    removeAt = function(_, col, row, _, _)
      layer.items[idx(col, row)] = nil
    end,
    setSelected = function(self, col, row, li)
      self._sel = { col = col, row = row, li = li }
    end,
    clearSelected = function(self)
      self._sel = nil
    end,
    toGridCoords = function(_, x, y)
      if x < 20 then
        return true, 0, 0, 0, 0
      elseif x < 40 then
        return true, 1, 0, 0, 0
      end
      return false
    end,
  }

  return win, layer
end

describe("mouse_input.lua - tile ctrl+drag copy", function()
  local originalMouseIsDown

  beforeEach(function()
    if not _G.love then _G.love = {} end
    love.mouse = love.mouse or {}
    originalMouseIsDown = love.mouse.isDown
    love.mouse.isDown = function(btn) return btn == 1 end
  end)

  afterEach(function()
    if love and love.mouse then
      love.mouse.isDown = originalMouseIsDown
    end
  end)

  it("copies tile on ctrl+click drag and keeps original visible during drag", function()
    local ctrl = true
    local win = makeTileWindow()
    local tile = { id = "tileA" }
    win:set(0, 0, tile, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x < 40 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 10, 1)
    MouseInput.mousemoved(25, 10, 15, 0) -- activate drag

    -- Copy drag keeps original visible at source while previewing copy.
    expect(win:get(0, 0, 1)).toBe(tile)

    MouseInput.mousereleased(30, 10, 1)

    expect(win:get(0, 0, 1)).toBe(tile)
    expect(win:get(1, 0, 1)).toBe(tile)
  end)

  it("hides source tile during normal move drag", function()
    local ctrl = false
    local win = makeTileWindow()
    local tile = { id = "tileA" }
    win:set(0, 0, tile, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x < 40 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 10, 1)
    MouseInput.mousemoved(25, 10, 15, 0) -- activate drag

    expect(win:get(0, 0, 1)).toBeNil()

    MouseInput.mousereleased(30, 10, 1)

    expect(win:get(0, 0, 1)).toBeNil()
    expect(win:get(1, 0, 1)).toBe(tile)
  end)

  it("restores source tile when normal move drag is canceled", function()
    local ctrl = false
    local win = makeTileWindow()
    local tile = { id = "tileA" }
    win:set(0, 0, tile, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x < 40 then return win end
        return nil -- release outside window => canceled drop
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 10, 1)
    MouseInput.mousemoved(25, 10, 15, 0) -- activate drag

    expect(win:get(0, 0, 1)).toBeNil()

    MouseInput.mousereleased(100, 10, 1) -- outside any window

    expect(win:get(0, 0, 1)).toBe(tile)
    expect(win:get(1, 0, 1)).toBeNil()
  end)

  it("records undo/redo for normal single-tile move drag", function()
    local ctrl = false
    local win = makeTileWindow()
    local tile = { id = "tileA" }
    local undoRedo = UndoRedoController.new(10)
    win:set(0, 0, tile, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x < 40 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local app = { undoRedo = undoRedo }
    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
      app = app,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 10, 1)
    MouseInput.mousemoved(25, 10, 15, 0)
    MouseInput.mousereleased(30, 10, 1)

    expect(win:get(0, 0, 1)).toBeNil()
    expect(win:get(1, 0, 1)).toBe(tile)

    expect(undoRedo:undo(app)).toBeTruthy()
    expect(win:get(0, 0, 1)).toBe(tile)
    expect(win:get(1, 0, 1)).toBeNil()

    expect(undoRedo:redo(app)).toBeTruthy()
    expect(win:get(0, 0, 1)).toBeNil()
    expect(win:get(1, 0, 1)).toBe(tile)
  end)

  it("records undo/redo for single-tile ctrl copy drag", function()
    local ctrl = true
    local win = makeTileWindow()
    local tile = { id = "tileA" }
    local undoRedo = UndoRedoController.new(10)
    win:set(0, 0, tile, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x < 40 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local app = { undoRedo = undoRedo }
    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
      app = app,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 10, 1)
    MouseInput.mousemoved(25, 10, 15, 0)
    MouseInput.mousereleased(30, 10, 1)

    expect(win:get(0, 0, 1)).toBe(tile)
    expect(win:get(1, 0, 1)).toBe(tile)

    expect(undoRedo:undo(app)).toBeTruthy()
    expect(win:get(0, 0, 1)).toBe(tile)
    expect(win:get(1, 0, 1)).toBeNil()

    expect(undoRedo:redo(app)).toBeTruthy()
    expect(win:get(0, 0, 1)).toBe(tile)
    expect(win:get(1, 0, 1)).toBe(tile)
  end)

  it("shows CHR tile label text when clicking a tile", function()
    local ctrl = false
    local win = makeTileWindow()
    win.kind = "chr"
    local tile = { id = "tileA", index = 26 }
    win:set(0, 0, tile, 1)

    local flashedLabel = nil
    win.specializedToolbar = {
      triggerLayerLabelTextFlash = function(_, text)
        flashedLabel = text
      end,
    }

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x < 40 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 10, 1)

    expect(flashedLabel).toBe("tile 26 (1A hex)")
  end)
end)

local function makeMarqueeWindow(kind)
  local cols = 4
  local rows = 4
  local layer = {
    kind = "tile",
    items = {},
  }

  local function idx(col, row)
    return row * cols + col + 1
  end

  local win = {
    kind = kind or "static_art",
    _closed = false,
    x = 0,
    y = 0,
    zoom = 1,
    cellW = 8,
    cellH = 8,
    cols = cols,
    rows = rows,
    scrollCol = 0,
    scrollRow = 0,
    layers = { layer },
    getActiveLayerIndex = function() return 1 end,
    isInHeader = function() return false end,
    get = function(_, col, row, _)
      return layer.items[idx(col, row)]
    end,
    set = function(_, col, row, item, _)
      layer.items[idx(col, row)] = item
    end,
    getStack = function(_, col, row, _)
      local item = layer.items[idx(col, row)]
      if item then return { item } end
      return nil
    end,
    setSelected = function(self, col, row, li)
      self._sel = { col = col, row = row, li = li }
    end,
    clearSelected = function(self)
      self._sel = nil
    end,
    toGridCoords = function(_, x, y)
      local col = math.floor(x / 8)
      local row = math.floor(y / 8)
      if col >= 0 and col < cols and row >= 0 and row < rows then
        return true, col, row, 0, 0
      end
      return false
    end,
  }

  return win, layer
end

describe("mouse_input.lua - tile ctrl+drag multi-selection copy", function()
  local originalMouseIsDown

  beforeEach(function()
    if not _G.love then _G.love = {} end
    love.mouse = love.mouse or {}
    originalMouseIsDown = love.mouse.isDown
    love.mouse.isDown = function(btn) return btn == 1 end
  end)

  afterEach(function()
    if love and love.mouse then
      love.mouse.isDown = originalMouseIsDown
    end
  end)

  local function makePickByVisual(win)
    return function(_, x, y, li)
      local ok, col, row = win:toGridCoords(x, y)
      if not ok then return false end
      local item = win:get(col, row, li)
      if not item then return false end
      return true, col, row, item
    end
  end

  it("copies selected tile group and replaces destination tiles", function()
    local ctrl = true
    local win, layer = makeMarqueeWindow("static_art")
    local a = { id = "a" }
    local b = { id = "b" }
    local oldC = { id = "oldC" }
    local oldD = { id = "oldD" }

    win:set(0, 0, a, 1)
    win:set(1, 0, b, 1)
    win:set(2, 0, oldC, 1)
    win:set(3, 0, oldD, 1)
    layer.multiTileSelection = { [1] = true, [2] = true }

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x >= 0 and x < 32 and y >= 0 and y < 32 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = makePickByVisual(win),
    })

    MouseInput.mousepressed(1, 1, 1)        -- anchor (0,0) within selected group
    MouseInput.mousemoved(31, 1, 30, 0)     -- drag toward col 3 (will clamp anchor)
    MouseInput.mousereleased(31, 1, 1)

    -- Originals remain (copy operation).
    expect(win:get(0, 0, 1)).toBe(a)
    expect(win:get(1, 0, 1)).toBe(b)

    -- Destination tiles were replaced by copied group.
    expect(win:get(2, 0, 1)).toBe(a)
    expect(win:get(3, 0, 1)).toBe(b)

    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[3]).toBe(true) -- (2,0)
    expect(layer.multiTileSelection[4]).toBe(true) -- (3,0)
  end)

  it("clamps copied tile group to layer bounds on both axes", function()
    local ctrl = true
    local win, layer = makeMarqueeWindow("static_art")
    local a = { id = "a" }
    local b = { id = "b" }
    local c = { id = "c" }
    local d = { id = "d" }

    win:set(0, 0, a, 1)
    win:set(1, 0, b, 1)
    win:set(0, 1, c, 1)
    win:set(1, 1, d, 1)
    layer.multiTileSelection = { [1] = true, [2] = true, [5] = true, [6] = true }

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x >= 0 and x < 32 and y >= 0 and y < 32 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = makePickByVisual(win),
    })

    MouseInput.mousepressed(1, 1, 1)         -- anchor (0,0)
    MouseInput.mousemoved(31, 31, 30, 30)    -- drag toward bottom-right corner
    MouseInput.mousereleased(31, 31, 1)

    -- 2x2 selection copied and clamped so it fully fits within 4x4 bounds.
    expect(win:get(2, 2, 1)).toBe(a)
    expect(win:get(3, 2, 1)).toBe(b)
    expect(win:get(2, 3, 1)).toBe(c)
    expect(win:get(3, 3, 1)).toBe(d)
  end)
end)

describe("mouse_input.lua - tile multi-selection drag move", function()
  local originalMouseIsDown
  local originalGetScaledMouse

  beforeEach(function()
    if not _G.love then _G.love = {} end
    love.mouse = love.mouse or {}
    originalMouseIsDown = love.mouse.isDown
    love.mouse.isDown = function(btn) return btn == 1 end
    originalGetScaledMouse = ResolutionController.getScaledMouse
    ResolutionController.getScaledMouse = function()
      return { x = 0, y = 0 }
    end
  end)

  afterEach(function()
    if love and love.mouse then
      love.mouse.isDown = originalMouseIsDown
    end
    ResolutionController.getScaledMouse = originalGetScaledMouse
  end)

  local function makePickByVisual(win)
    return function(_, x, y, li)
      local ok, col, row = win:toGridCoords(x, y)
      if not ok then return false end
      local item = win:get(col, row, li)
      if not item then return false end
      return true, col, row, item
    end
  end

  it("drags the whole selected tile group when dragging one selected tile", function()
    local ctrl = false
    local win, layer = makeMarqueeWindow("static_art")
    local a = { id = "a" }
    local b = { id = "b" }
    win:set(0, 0, a, 1)
    win:set(1, 0, b, 1)
    layer.multiTileSelection = { [1] = true, [2] = true }

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x >= 0 and x < 32 and y >= 0 and y < 32 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = makePickByVisual(win),
    })

    MouseInput.mousepressed(1, 1, 1)      -- (0,0), part of multi-selection
    MouseInput.mousemoved(17, 1, 16, 0)   -- target anchor near col 2
    MouseInput.mousereleased(17, 1, 1)

    -- Source group moved from (0,0)-(1,0) to (2,0)-(3,0).
    expect(win:get(0, 0, 1)).toBeNil()
    expect(win:get(1, 0, 1)).toBeNil()
    expect(win:get(2, 0, 1)).toBe(a)
    expect(win:get(3, 0, 1)).toBe(b)

    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[3]).toBe(true) -- (2,0)
    expect(layer.multiTileSelection[4]).toBe(true) -- (3,0)
  end)

  it("draws overlay ghost for all tiles in group during normal multi drag", function()
    local ctrl = false
    local drawA, drawB = 0, 0
    local a = { id = "a", draw = function() drawA = drawA + 1 end }
    local b = { id = "b", draw = function() drawB = drawB + 1 end }
    local win, layer = makeMarqueeWindow("static_art")
    win:set(0, 0, a, 1)
    win:set(1, 0, b, 1)
    layer.multiTileSelection = { [1] = true, [2] = true }

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x >= 0 and x < 32 and y >= 0 and y < 32 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = makePickByVisual(win),
    })

    MouseInput.mousepressed(1, 1, 1)
    MouseInput.mousemoved(17, 1, 16, 0)
    MouseInput.drawOverlay()

    expect(drawA).toBeGreaterThan(0)
    expect(drawB).toBeGreaterThan(0)
  end)

  it("draws overlay ghost for all tiles in group during ctrl copy drag", function()
    local ctrl = true
    local drawA, drawB = 0, 0
    local a = { id = "a", draw = function() drawA = drawA + 1 end }
    local b = { id = "b", draw = function() drawB = drawB + 1 end }
    local win, layer = makeMarqueeWindow("static_art")
    win:set(0, 0, a, 1)
    win:set(1, 0, b, 1)
    layer.multiTileSelection = { [1] = true, [2] = true }

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x >= 0 and x < 32 and y >= 0 and y < 32 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = makePickByVisual(win),
    })

    MouseInput.mousepressed(1, 1, 1)
    MouseInput.mousemoved(17, 1, 16, 0)
    MouseInput.drawOverlay()

    expect(drawA).toBeGreaterThan(0)
    expect(drawB).toBeGreaterThan(0)
  end)
end)

describe("mouse_input.lua - tile shift marquee selection", function()
  local originalMouseIsDown

  beforeEach(function()
    if not _G.love then _G.love = {} end
    love.mouse = love.mouse or {}
    originalMouseIsDown = love.mouse.isDown
    love.mouse.isDown = function(btn) return btn == 1 end
  end)

  afterEach(function()
    if love and love.mouse then
      love.mouse.isDown = originalMouseIsDown
    end
  end)

  it("selects a rectangle of tiles in tile mode when shift is held", function()
    local win, layer = makeMarqueeWindow("static_art")
    win:set(0, 0, { id = "a" }, 1)
    win:set(1, 0, { id = "b" }, 1)
    win:set(0, 1, { id = "c" }, 1)
    win:set(1, 1, { id = "d" }, 1)
    win:set(2, 2, { id = "outside-rect" }, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local dragState = {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, dragState, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1)   -- cell (0,0)
    MouseInput.mousemoved(15, 15, 14, 14) -- cell (1,1)

    -- Selection should update immediately while marquee is being dragged.
    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[1]).toBe(true) -- (0,0)
    expect(layer.multiTileSelection[2]).toBe(true) -- (1,0)
    expect(layer.multiTileSelection[5]).toBe(true) -- (0,1)
    expect(layer.multiTileSelection[6]).toBe(true) -- (1,1)

    MouseInput.mousereleased(15, 15, 1)

    expect(dragState.pending).toBe(false)
    expect(dragState.active).toBe(false)
    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[1]).toBe(true) -- (0,0)
    expect(layer.multiTileSelection[2]).toBe(true) -- (1,0)
    expect(layer.multiTileSelection[5]).toBe(true) -- (0,1)
    expect(layer.multiTileSelection[6]).toBe(true) -- (1,1)
    expect(layer.multiTileSelection[11]).toBeNil() -- (2,2) not in marquee
    expect(win._sel.col).toBe(0)
    expect(win._sel.row).toBe(0)
  end)

  it("updates tile marquee selection in real time as rectangle changes", function()
    local win, layer = makeMarqueeWindow("static_art")
    win:set(0, 0, { id = "a" }, 1)
    win:set(1, 0, { id = "b" }, 1)
    win:set(0, 1, { id = "c" }, 1)
    win:set(1, 1, { id = "d" }, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local dragState = {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, dragState, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1) -- (0,0)
    MouseInput.mousemoved(15, 15, 14, 14) -- (1,1)
    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[1]).toBe(true)
    expect(layer.multiTileSelection[2]).toBe(true)
    expect(layer.multiTileSelection[5]).toBe(true)
    expect(layer.multiTileSelection[6]).toBe(true)

    MouseInput.mousemoved(7, 7, -8, -8) -- back to (0,0)
    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[1]).toBe(true)
    expect(layer.multiTileSelection[2]).toBeNil()
    expect(layer.multiTileSelection[5]).toBeNil()
    expect(layer.multiTileSelection[6]).toBeNil()

    MouseInput.mousereleased(7, 7, 1)
  end)

  it("supports shift marquee selection in animation windows", function()
    local win, layer = makeMarqueeWindow("animation")
    win:set(0, 0, { id = "a" }, 1)
    win:set(1, 0, { id = "b" }, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local dragState = {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, dragState, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1)
    MouseInput.mousemoved(15, 1, 14, 0)
    MouseInput.mousereleased(15, 1, 1)

    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[1]).toBe(true) -- (0,0)
    expect(layer.multiTileSelection[2]).toBe(true) -- (1,0)
  end)

  it("supports shift marquee selection in CHR windows", function()
    local win, layer = makeMarqueeWindow("chr")
    win:set(0, 0, { id = "a" }, 1)
    win:set(1, 0, { id = "b" }, 1)
    win:set(0, 1, { id = "c" }, 1)
    win:set(1, 1, { id = "d" }, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local dragState = {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, dragState, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1)
    MouseInput.mousemoved(15, 15, 14, 14)
    MouseInput.mousereleased(15, 15, 1)

    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[1]).toBe(true)
    expect(layer.multiTileSelection[2]).toBe(true)
    expect(layer.multiTileSelection[5]).toBe(true)
    expect(layer.multiTileSelection[6]).toBe(true)
  end)

  it("supports shift marquee selection in ROM windows", function()
    local win, layer = makeMarqueeWindow("chr")
    win.isRomWindow = true
    win:set(0, 0, { id = "a" }, 1)
    win:set(1, 0, { id = "b" }, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local dragState = {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, dragState, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1)
    MouseInput.mousemoved(15, 1, 14, 0)
    MouseInput.mousereleased(15, 1, 1)

    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[1]).toBe(true)
    expect(layer.multiTileSelection[2]).toBe(true)
  end)

  it("supports shift marquee selection in PPU frame tile layers", function()
    local win, layer = makeMarqueeWindow("ppu_frame")
    win:set(0, 0, { id = "a" }, 1)
    win:set(1, 0, { id = "b" }, 1)
    win:set(0, 1, { id = "c" }, 1)
    win:set(1, 1, { id = "d" }, 1)

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local dragState = {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, dragState, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1)
    MouseInput.mousemoved(15, 15, 14, 14)
    MouseInput.mousereleased(15, 15, 1)

    expect(layer.multiTileSelection).toBeTruthy()
    expect(layer.multiTileSelection[1]).toBe(true)
    expect(layer.multiTileSelection[2]).toBe(true)
    expect(layer.multiTileSelection[5]).toBe(true)
    expect(layer.multiTileSelection[6]).toBe(true)
  end)

  it("does not start tile marquee in edit mode", function()
    local win, layer = makeMarqueeWindow("static_art")
    win.toGridCoords = function() return false end

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local dragState = {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }

    local ctx = {
      getMode = function() return "edit" end,
      wm = function() return wm end,
      setPainting = function() end,
      paintAt = function() end,
      setStatus = function() end,
      getPainting = function() return false end,
      app = {},
    }

    MouseInput.setup(ctx, dragState, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return true end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1)
    MouseInput.mousemoved(15, 15, 14, 14)
    MouseInput.mousereleased(15, 15, 1)

    expect(layer.multiTileSelection).toBeNil()
    expect(dragState.pending).toBe(false)
    expect(dragState.active).toBe(false)
  end)
end)

describe("mouse_input.lua - tile normal click vs drag on multi-selection", function()
  local originalMouseIsDown

  beforeEach(function()
    if not _G.love then _G.love = {} end
    love.mouse = love.mouse or {}
    originalMouseIsDown = love.mouse.isDown
    love.mouse.isDown = function(btn) return btn == 1 end
  end)

  afterEach(function()
    if love and love.mouse then
      love.mouse.isDown = originalMouseIsDown
    end
  end)

  it("collapses tile multi-selection on normal click", function()
    local ctrl = false
    local win = makeTileWindow()
    win:set(0, 0, { id = "tileA" }, 1)
    win.layers[1].multiTileSelection = { [1] = true, [2] = true }

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x < 40 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 10, 1)
    MouseInput.mousereleased(10, 10, 1)

    expect(win.layers[1].multiTileSelection).toBeNil()
    expect(win._sel).toBeTruthy()
    expect(win._sel.col).toBe(0)
    expect(win._sel.row).toBe(0)
  end)

  it("keeps tile multi-selection on click-drag", function()
    local ctrl = false
    local win = makeTileWindow()
    win:set(0, 0, { id = "tileA" }, 1)
    win.layers[1].multiTileSelection = { [1] = true, [2] = true }

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x < 40 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 10, 1)
    MouseInput.mousemoved(25, 10, 15, 0)
    MouseInput.mousereleased(30, 10, 1)

    expect(win.layers[1].multiTileSelection).toBeTruthy()
    expect(win.layers[1].multiTileSelection[1]).toBe(true)
    expect(win.layers[1].multiTileSelection[2]).toBe(true)
  end)
end)
