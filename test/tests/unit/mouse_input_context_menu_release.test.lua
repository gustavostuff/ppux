local MouseInput = require("controllers.input.mouse_input")
local MouseMoveController = require("controllers.input.mouse_move_controller")
local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")
local MouseWheelController = require("controllers.input.mouse_wheel_controller")
local MouseWindowChromeController = require("controllers.input.mouse_window_chrome_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local MultiSelectController = require("controllers.input_support.multi_select_controller")

describe("mouse_input.lua - context menus on release", function()
  local originals

  beforeEach(function()
    originals = {
      move = MouseMoveController.handleMouseMoved,
      tileDrop = MouseTileDropController.handleTileDrop,
      wheel = MouseWheelController.handleWheel,
      toolbarRelease = MouseWindowChromeController.handleToolbarRelease,
      resizeEnd = MouseWindowChromeController.handleResizeEnd,
      finishSpriteMarquee = SpriteController.finishSpriteMarquee,
      isDragging = SpriteController.isDragging,
      finishDrag = SpriteController.finishDrag,
      endDrag = SpriteController.endDrag,
      finishTileMarquee = MultiSelectController.finishTileMarquee,
      reset = MultiSelectController.reset,
    }

    MouseMoveController.handleMouseMoved = function() end
    MouseTileDropController.handleTileDrop = function() return false end
    MouseWheelController.handleWheel = function() return false end
    MouseWindowChromeController.handleToolbarRelease = function() return false end
    MouseWindowChromeController.handleResizeEnd = function() return false end
    SpriteController.finishSpriteMarquee = function() return false end
    SpriteController.isDragging = function() return false end
    SpriteController.finishDrag = function() end
    SpriteController.endDrag = function() end
    MultiSelectController.finishTileMarquee = function() return false end
    MultiSelectController.reset = function() end

    if MouseWindowChromeController._resetHeaderDoubleClickState then
      MouseWindowChromeController._resetHeaderDoubleClickState()
    end
  end)

  afterEach(function()
    MouseMoveController.handleMouseMoved = originals.move
    MouseTileDropController.handleTileDrop = originals.tileDrop
    MouseWheelController.handleWheel = originals.wheel
    MouseWindowChromeController.handleToolbarRelease = originals.toolbarRelease
    MouseWindowChromeController.handleResizeEnd = originals.resizeEnd
    SpriteController.finishSpriteMarquee = originals.finishSpriteMarquee
    SpriteController.isDragging = originals.isDragging
    SpriteController.finishDrag = originals.finishDrag
    SpriteController.endDrag = originals.endDrag
    MultiSelectController.finishTileMarquee = originals.finishTileMarquee
    MultiSelectController.reset = originals.reset
  end)

  local function makeUndoRedo()
    return {
      started = 0,
      finished = 0,
      canceled = 0,
      startPaintEvent = function(self)
        self.started = self.started + 1
      end,
      finishPaintEvent = function(self)
        self.finished = self.finished + 1
        return true
      end,
      cancelPaintEvent = function(self)
        self.canceled = self.canceled + 1
      end,
    }
  end

  local function makeHeaderWindow()
    return {
      kind = "static_art",
      _id = "w1",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      x = 10,
      y = 40,
      headerH = 15,
      dragging = false,
      isInHeader = function(_, x, y)
        return x >= 10 and x <= 210 and y >= 25 and y <= 40
      end,
      getHeaderRect = function()
        return 10, 25, 200, 15
      end,
      contains = function(_, x, y)
        return x >= 10 and x <= 210 and y >= 25 and y <= 180
      end,
      mousepressed = function(self, x, y, button)
        if button == 2 or button == 3 then
          self.dragging = true
          self.dx = x - self.x
          self.dy = y - self.y
        end
      end,
      mousereleased = function(self)
        self.dragging = false
      end,
      headerToolbar = {
        updatePosition = function() end,
        mousepressed = function() return false end,
        x = 170,
        y = 25,
        w = 40,
        h = 15,
      },
    }
  end

  it("opens the window header context menu on right-button release without movement", function()
    local headerMenuCalls = 0
    local headerMenuWin = nil
    local focusWin = nil
    local win = makeHeaderWindow()
    local wm = {
      getFocus = function() return focusWin end,
      setFocus = function(_, next) focusWin = next end,
      windowAt = function(_, x, y)
        if win:contains(x, y) then
          return win
        end
        return nil
      end,
    }

    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      setPainting = function() end,
      app = {
        showWindowHeaderContextMenu = function(_, targetWin)
          headerMenuCalls = headerMenuCalls + 1
          headerMenuWin = targetWin
        end,
      },
    }, { active = false, pending = false }, { active = false }, {})

    MouseInput.mousepressed(40, 30, 2)
    expect(win.dragging).toBe(true)

    MouseInput.mousereleased(40, 30, 2)

    expect(headerMenuCalls).toBe(1)
    expect(headerMenuWin).toBe(win)
    expect(win.dragging).toBe(false)
  end)

  it("does not open the window header context menu after a right-button drag", function()
    local headerMenuCalls = 0
    local focusWin = nil
    local win = makeHeaderWindow()
    local wm = {
      getFocus = function() return focusWin end,
      setFocus = function(_, next) focusWin = next end,
      windowAt = function(_, x, y)
        if win:contains(x, y) then
          return win
        end
        return nil
      end,
    }

    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      setPainting = function() end,
      app = {
        showWindowHeaderContextMenu = function()
          headerMenuCalls = headerMenuCalls + 1
        end,
      },
    }, { active = false, pending = false }, { active = false }, {})

    MouseInput.mousepressed(40, 30, 2)
    MouseInput.mousemoved(50, 30, 10, 0)
    MouseInput.mousereleased(50, 30, 2)

    expect(headerMenuCalls).toBe(0)
    expect(win.dragging).toBe(false)
  end)

  it("does not open the window header context menu after a tiny right-button drag", function()
    local headerMenuCalls = 0
    local focusWin = nil
    local win = makeHeaderWindow()
    local wm = {
      getFocus = function() return focusWin end,
      setFocus = function(_, next) focusWin = next end,
      windowAt = function(_, x, y)
        if win:contains(x, y) then
          return win
        end
        return nil
      end,
    }

    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      setPainting = function() end,
      app = {
        showWindowHeaderContextMenu = function()
          headerMenuCalls = headerMenuCalls + 1
        end,
      },
    }, { active = false, pending = false }, { active = false }, {})

    MouseInput.mousepressed(40, 30, 2)
    MouseInput.mousemoved(42, 30, 2, 0)
    MouseInput.mousereleased(42, 30, 2)

    expect(headerMenuCalls).toBe(0)
  end)

  it("does not open the window header context menu when release position differs without mousemoved", function()
    local headerMenuCalls = 0
    local focusWin = nil
    local win = makeHeaderWindow()
    local wm = {
      getFocus = function() return focusWin end,
      setFocus = function(_, next) focusWin = next end,
      windowAt = function(_, x, y)
        if win:contains(x, y) then
          return win
        end
        return nil
      end,
    }

    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      setPainting = function() end,
      app = {
        showWindowHeaderContextMenu = function()
          headerMenuCalls = headerMenuCalls + 1
        end,
      },
    }, { active = false, pending = false }, { active = false }, {})

    MouseInput.mousepressed(40, 30, 2)
    MouseInput.mousereleased(50, 30, 2)

    expect(headerMenuCalls).toBe(0)
  end)

  it("opens the empty-space context menu on right-button release without movement", function()
    local emptyMenuCalls = 0
    local lastX = nil
    local lastY = nil
    local focusWin = nil
    local wm = {
      getFocus = function() return focusWin end,
      setFocus = function(_, next) focusWin = next end,
      windowAt = function()
        return nil
      end,
    }

    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      setPainting = function() end,
      app = {
        showEmptySpaceContextMenu = function(_, x, y)
          emptyMenuCalls = emptyMenuCalls + 1
          lastX = x
          lastY = y
        end,
      },
    }, { active = false, pending = false }, { active = false }, {})

    MouseInput.mousepressed(300, 200, 2)
    MouseInput.mousereleased(300, 200, 2)

    expect(emptyMenuCalls).toBe(1)
    expect(lastX).toBe(300)
    expect(lastY).toBe(200)
  end)

  it("opens select-in-CHR context menu on right-button release for sprite layer items", function()
    local openCalls = 0
    local lastArgs = nil
    local focusWin = nil
    local win = {
      kind = "static_art",
      _id = "spr_ctx",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      x = 10,
      y = 40,
      dragging = false,
      layers = {
        { kind = "sprite", items = { { bank = 1, tile = 0x22 } } },
      },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
      toGridCoords = function()
        return true, 0, 0
      end,
      contains = function(_, x, y)
        return x >= 10 and x <= 210 and y >= 25 and y <= 180
      end,
      mousepressed = function(self, x, y, button)
        if button == 2 or button == 3 then
          self.dragging = true
          self.dx = x - self.x
          self.dy = y - self.y
        end
      end,
      mousereleased = function(self)
        self.dragging = false
      end,
    }
    local wm = {
      getFocus = function() return focusWin end,
      setFocus = function(_, next) focusWin = next end,
      windowAt = function(_, x, y)
        if win:contains(x, y) then
          return win
        end
        return nil
      end,
      getWindows = function()
        return { win }
      end,
    }

    local SpriteController = require("controllers.sprite.sprite_controller")
    local originalPickSpriteAt = SpriteController.pickSpriteAt
    SpriteController.pickSpriteAt = function()
      return 1, 1, 0, 0
    end

    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      setPainting = function() end,
      app = {
        showSelectInChrContextMenu = function(_, targetWin, layerIndex, col, row, itemIndex)
          openCalls = openCalls + 1
          lastArgs = {
            win = targetWin,
            layerIndex = layerIndex,
            col = col,
            row = row,
            itemIndex = itemIndex,
          }
        end,
      },
    }, { active = false, pending = false }, { active = false }, {
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(40, 30, 2)
    MouseInput.mousereleased(40, 30, 2)

    SpriteController.pickSpriteAt = originalPickSpriteAt

    expect(openCalls).toBe(1)
    expect(lastArgs.win).toBe(win)
    expect(lastArgs.layerIndex).toBe(1)
    expect(lastArgs.col).toBeNil()
    expect(lastArgs.row).toBeNil()
    expect(lastArgs.itemIndex).toBe(1)
  end)

  it("opens OAM empty-space context menu on right-button release over empty sprite space", function()
    local openCalls = 0
    local lastArgs = nil
    local focusWin = nil
    local win = {
      kind = "oam_animation",
      _id = "oam_ctx",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      x = 10,
      y = 40,
      dragging = false,
      layers = {
        { kind = "sprite", items = {} },
      },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 0, 0 end,
      isInHeader = function() return false end,
      contains = function(_, x, y)
        return x >= 10 and x <= 210 and y >= 25 and y <= 180
      end,
      mousepressed = function(self, x, y, button)
        if button == 2 or button == 3 then
          self.dragging = true
          self.dx = x - self.x
          self.dy = y - self.y
        end
      end,
      mousereleased = function(self)
        self.dragging = false
      end,
    }
    local wm = {
      getFocus = function() return focusWin end,
      setFocus = function(_, next) focusWin = next end,
      windowAt = function(_, x, y)
        if win:contains(x, y) then
          return win
        end
        return nil
      end,
      getWindows = function()
        return { win }
      end,
    }

    local SpriteController = require("controllers.sprite.sprite_controller")
    local originalPickSpriteAt = SpriteController.pickSpriteAt
    SpriteController.pickSpriteAt = function()
      return nil
    end

    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      setPainting = function() end,
      app = {
        showOamSpriteEmptySpaceContextMenu = function(_, targetWin, layerIndex)
          openCalls = openCalls + 1
          lastArgs = {
            win = targetWin,
            layerIndex = layerIndex,
          }
        end,
      },
    }, { active = false, pending = false }, { active = false }, {
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(40, 30, 2)
    MouseInput.mousereleased(40, 30, 2)

    SpriteController.pickSpriteAt = originalPickSpriteAt

    expect(openCalls).toBe(1)
    expect(lastArgs.win).toBe(win)
    expect(lastArgs.layerIndex).toBe(1)
  end)

  it("finishes shift-drag rectangle fill shapes on left-button release without crashing", function()
    local focusWin = {
      kind = "static_art",
      editShapeDrag = {
        kind = "rect_or_line",
        startX = 1,
        startY = 2,
        currentX = 4,
        currentY = 5,
        moved = true,
      },
      editLastPoint = nil,
    }
    local undoRedo = makeUndoRedo()
    local wm = {
      getFocus = function() return focusWin end,
      setFocus = function() end,
      windowAt = function() return focusWin end,
    }

    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "edit" end,
      getPainting = function() return false end,
      setPainting = function() end,
      setStatus = function() end,
      app = {
        undoRedo = undoRedo,
      },
    }, { active = false, pending = false }, { active = false }, {})

    local BrushController = require("controllers.input_support.brush_controller")
    local originalFillRect = BrushController.fillRect
    BrushController.fillRect = function(app, win, x0, y0, x1, y1, pickOnly)
      expect(app.undoRedo).toBe(undoRedo)
      expect(win).toBe(focusWin)
      expect(x0).toBe(1)
      expect(y0).toBe(2)
      expect(x1).toBe(4)
      expect(y1).toBe(5)
      expect(pickOnly).toBe(false)
      return true
    end

    MouseInput.mousereleased(10, 10, 1)

    BrushController.fillRect = originalFillRect

    expect(undoRedo.started).toBe(1)
    expect(undoRedo.finished).toBe(1)
    expect(undoRedo.canceled).toBe(0)
    expect(focusWin.editShapeDrag).toBeNil()
    expect(focusWin.editLastPoint.x).toBe(4)
    expect(focusWin.editLastPoint.y).toBe(5)
  end)
end)

describe("mouse_input.lua - editLastPoint after paint", function()
  local originals

  beforeEach(function()
    originals = {
      toolbarRelease = MouseWindowChromeController.handleToolbarRelease,
      resizeEnd = MouseWindowChromeController.handleResizeEnd,
      finishSpriteMarquee = SpriteController.finishSpriteMarquee,
      isDragging = SpriteController.isDragging,
      finishDrag = SpriteController.finishDrag,
      endDrag = SpriteController.endDrag,
      finishTileMarquee = MultiSelectController.finishTileMarquee,
      reset = MultiSelectController.reset,
    }
    MouseWindowChromeController.handleToolbarRelease = function() return false end
    MouseWindowChromeController.handleResizeEnd = function() return false end
    SpriteController.finishSpriteMarquee = function() return false end
    SpriteController.isDragging = function() return false end
    SpriteController.finishDrag = function() end
    SpriteController.endDrag = function() end
    MultiSelectController.finishTileMarquee = function() return false end
    MultiSelectController.reset = function() end
  end)

  afterEach(function()
    MouseWindowChromeController.handleToolbarRelease = originals.toolbarRelease
    MouseWindowChromeController.handleResizeEnd = originals.resizeEnd
    SpriteController.finishSpriteMarquee = originals.finishSpriteMarquee
    SpriteController.isDragging = originals.isDragging
    SpriteController.finishDrag = originals.finishDrag
    SpriteController.endDrag = originals.endDrag
    MultiSelectController.finishTileMarquee = originals.finishTileMarquee
    MultiSelectController.reset = originals.reset
  end)

  it("updates the Shift line/rect anchor even when the paint stroke changed no pixels", function()
    local painting = true
    local focusWin = {
      kind = "static_art",
      cellW = 8,
      cellH = 8,
      editLastPoint = { x = 1, y = 1 },
      toGridCoords = function()
        return true, 2, 3, 4, 5
      end,
    }
    local undoRedo = {
      finished = 0,
      canceled = 0,
      finishPaintEvent = function(self)
        self.finished = self.finished + 1
        return false
      end,
      cancelPaintEvent = function(self)
        self.canceled = self.canceled + 1
      end,
    }
    local wm = {
      getFocus = function() return focusWin end,
      setFocus = function() end,
      windowAt = function() return focusWin end,
    }

    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "edit" end,
      getPainting = function() return painting end,
      setPainting = function(v) painting = v end,
      setStatus = function() end,
      app = { undoRedo = undoRedo },
    }, { active = false, pending = false }, { active = false }, {})

    MouseInput.mousereleased(40, 30, 1)

    expect(undoRedo.finished).toBe(1)
    expect(undoRedo.canceled).toBe(1)
    expect(painting).toBe(false)
    -- col*cellW + lx = 2*8 + 4 = 20; row*cellH + ly = 3*8 + 5 = 29
    expect(focusWin.editLastPoint.x).toBe(20)
    expect(focusWin.editLastPoint.y).toBe(29)
  end)

  it("updates the Shift line/rect anchor after a same-color Shift line click", function()
    local focusWin = {
      kind = "static_art",
      editShapeDrag = {
        kind = "rect_or_line",
        startX = 9,
        startY = 10,
        currentX = 9,
        currentY = 10,
        moved = false,
      },
      editLastPoint = { x = 1, y = 2 },
    }
    local undoRedo = {
      started = 0,
      finished = 0,
      canceled = 0,
      startPaintEvent = function(self)
        self.started = self.started + 1
      end,
      finishPaintEvent = function(self)
        self.finished = self.finished + 1
        return true
      end,
      cancelPaintEvent = function(self)
        self.canceled = self.canceled + 1
      end,
    }
    local wm = {
      getFocus = function() return focusWin end,
      setFocus = function() end,
      windowAt = function() return focusWin end,
    }

    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "edit" end,
      getPainting = function() return false end,
      setPainting = function() end,
      setStatus = function() end,
      app = { undoRedo = undoRedo },
    }, { active = false, pending = false }, { active = false }, {})

    local BrushController = require("controllers.input_support.brush_controller")
    local originalDrawLine = BrushController.drawLine
    BrushController.drawLine = function()
      return false
    end

    MouseInput.mousereleased(10, 10, 1)

    BrushController.drawLine = originalDrawLine

    expect(undoRedo.started).toBe(1)
    expect(undoRedo.canceled).toBe(1)
    expect(focusWin.editShapeDrag).toBeNil()
    expect(focusWin.editLastPoint.x).toBe(9)
    expect(focusWin.editLastPoint.y).toBe(10)
  end)
end)
