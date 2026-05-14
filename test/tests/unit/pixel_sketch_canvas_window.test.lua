local WM = require("controllers.window.window_controller")
local BrushController = require("controllers.input_support.brush_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")
local MouseClickController = require("controllers.input.mouse_click_controller")
local CursorsController = require("controllers.input_support.cursors_controller")

local function makeApp()
  return {
    appEditState = {
      chrBanksBytes = {},
      tilesPool = {},
    },
    undoRedo = UndoRedoController.new(20),
    currentColor = 3,
    brushSize = 1,
    setStatus = function(self, text)
      self.statusText = text
    end,
  }
end

describe("pixel_sketch_canvas_window.lua", function()
  it("creates a single sketch canvas layer at NES framebuffer resolution", function()
    local wm = WM.new()
    local win = wm:createPatternSketchCanvasWindow()

    expect(win.kind).toBe("pattern_sketch_canvas")
    expect(#win.layers).toBe(1)
    expect(win.layers[1].name).toBe("Sketch")
    expect(win.layers[1].kind).toBe("canvas")
    expect(win.layers[1].canvas.width).toBe(256)
    expect(win.layers[1].canvas.height).toBe(240)
    local w1, h1 = win:getContentSize()
    expect(w1).toBe(256)
    expect(h1).toBe(240)
  end)

  it("supports canvas paint and undo redo on the sketch canvas", function()
    local wm = WM.new()
    local win = wm:createPatternSketchCanvasWindow()
    local app = makeApp()

    app.undoRedo:startPaintEvent()
    local ok = BrushController.paintPixel(app, win, 0, 0, 2, 3, false)
    expect(ok).toBe(true)
    expect(app.undoRedo:finishPaintEvent()).toBe(true)

    local canvas = win.layers[1].canvas
    expect(canvas:getPixel(2, 3)).toBe(3)
    expect(app.undoRedo:undo(app)).toBe(true)
    expect(canvas:getPixel(2, 3)).toBe(0)
    expect(app.undoRedo:redo(app)).toBe(true)
    expect(canvas:getPixel(2, 3)).toBe(3)
  end)

  it("supports canvas flood fill with undo redo", function()
    local wm = WM.new()
    local win = wm:createPatternSketchCanvasWindow()
    local app = makeApp()
    local canvas = win.layers[1].canvas

    canvas:edit(7, 7, 1)
    app.currentColor = 2

    local ok = BrushController.floodFillTile(app, win, 0, 0, 0, 0)
    expect(ok).toBe(true)
    expect(canvas:getPixel(0, 0)).toBe(2)
    expect(canvas:getPixel(7, 7)).toBe(1)

    expect(app.undoRedo:undo(app)).toBe(true)
    expect(canvas:getPixel(0, 0)).toBe(0)
    expect(canvas:getPixel(7, 7)).toBe(1)

    expect(app.undoRedo:redo(app)).toBe(true)
    expect(canvas:getPixel(0, 0)).toBe(2)
    expect(canvas:getPixel(7, 7)).toBe(1)
  end)

  it("draws undoable canvas lines", function()
    local wm = WM.new()
    local win = wm:createPatternSketchCanvasWindow()
    local app = makeApp()
    local canvas = win.layers[1].canvas

    app.undoRedo:startPaintEvent()
    local ok = BrushController.drawLine(app, win, 0, 0, 3, 3, false)
    expect(ok).toBe(true)
    expect(app.undoRedo:finishPaintEvent()).toBe(true)

    expect(canvas:getPixel(0, 0)).toBe(3)
    expect(canvas:getPixel(1, 1)).toBe(3)
    expect(canvas:getPixel(2, 2)).toBe(3)
    expect(canvas:getPixel(3, 3)).toBe(3)
    expect(app.undoRedo:undo(app)).toBe(true)
    expect(canvas:getPixel(2, 2)).toBe(0)
  end)

  it("fills undoable rectangles on the canvas", function()
    local wm = WM.new()
    local win = wm:createPatternSketchCanvasWindow()
    local app = makeApp()
    local canvas = win.layers[1].canvas

    app.undoRedo:startPaintEvent()
    local ok = BrushController.fillRect(app, win, 1, 1, 2, 3, false)
    expect(ok).toBe(true)
    expect(app.undoRedo:finishPaintEvent()).toBe(true)

    expect(canvas:getPixel(1, 1)).toBe(3)
    expect(canvas:getPixel(2, 3)).toBe(3)
    expect(canvas:getPixel(0, 0)).toBe(0)
    expect(app.undoRedo:undo(app)).toBe(true)
    expect(canvas:getPixel(1, 1)).toBe(0)
  end)

  it("uses G-click color pick on the sketch canvas through the shared edit workflow", function()
    local wm = WM.new()
    local win = wm:createPatternSketchCanvasWindow()
    local app = makeApp()
    local canvas = win.layers[1].canvas
    canvas:edit(4, 5, 2)
    local wmStub

    local painting = false
    local focused = win
    local env = {
      ctx = {
        app = app,
        getMode = function() return "edit" end,
        wm = function()
          return wmStub
        end,
        setPainting = function(v) painting = not not v end,
        paintAt = function(targetWin, col, row, lx, ly, pickOnly)
          return BrushController.paintPixel(app, targetWin, col, row, lx, ly, pickOnly)
        end,
        setStatus = function(text) app:setStatus(text) end,
      },
      chrome = {
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
      utils = {
        grabDown = function() return true end,
        fillDown = function() return false end,
        ctrlDown = function() return false end,
        shiftDown = function() return false end,
      },
    }
    wmStub = {
      getFocus = function() return focused end,
      windowAt = function() return win end,
      setFocus = function(_, target) focused = target end,
    }

    local handled = MouseClickController.handleMousePressed(env, (win.x or 0) + 8, (win.y or 0) + 10, 1)

    expect(handled).toBe(true)
    expect(focused).toBe(win)
    expect(app.currentColor).toBe(2)
    expect(painting).toBe(false)
    expect(win.editShapeDrag).toBeNil()
  end)

  it("uses F-click flood fill on the sketch canvas through the shared edit workflow", function()
    local wm = WM.new()
    local win = wm:createPatternSketchCanvasWindow()
    local app = makeApp()
    local canvas = win.layers[1].canvas
    canvas:edit(0, 0, 1)
    canvas:edit(1, 0, 1)
    canvas:edit(2, 0, 1)
    app.currentColor = 2
    win.editLastPoint = { x = 7, y = 7 }
    local wmStub
    local focused = win

    local env = {
      ctx = {
        app = app,
        getMode = function() return "edit" end,
        wm = function()
          return wmStub
        end,
        setPainting = function() end,
        paintAt = function(targetWin, col, row, lx, ly, pickOnly)
          return BrushController.paintPixel(app, targetWin, col, row, lx, ly, pickOnly)
        end,
        setStatus = function(text) app:setStatus(text) end,
      },
      chrome = {
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
      utils = {
        grabDown = function() return false end,
        fillDown = function() return true end,
        ctrlDown = function() return false end,
        shiftDown = function() return false end,
      },
    }
    wmStub = {
      getFocus = function() return focused end,
      windowAt = function() return win end,
      setFocus = function(_, target) focused = target end,
    }

    local handled = MouseClickController.handleMousePressed(env, (win.x or 0), (win.y or 0), 1)

    expect(handled).toBe(true)
    expect(canvas:getPixel(0, 0)).toBe(2)
    expect(canvas:getPixel(1, 0)).toBe(2)
    expect(canvas:getPixel(2, 0)).toBe(2)
    expect(canvas:getPixel(7, 7)).toBe(0)
    expect(app.statusText).toBe(nil)
  end)

  it("starts shared shift shape drag on the sketch canvas", function()
    local wm = WM.new()
    local win = wm:createPatternSketchCanvasWindow()
    local app = makeApp()
    local wmStub
    local focused = win

    local env = {
      ctx = {
        app = app,
        getMode = function() return "edit" end,
        wm = function()
          return wmStub
        end,
        setPainting = function() end,
        paintAt = function(targetWin, col, row, lx, ly, pickOnly)
          return BrushController.paintPixel(app, targetWin, col, row, lx, ly, pickOnly)
        end,
        setStatus = function(text) app:setStatus(text) end,
      },
      chrome = {
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
      utils = {
        grabDown = function() return false end,
        fillDown = function() return false end,
        ctrlDown = function() return false end,
        shiftDown = function() return true end,
      },
    }
    wmStub = {
      getFocus = function() return focused end,
      windowAt = function() return win end,
      setFocus = function(_, target) focused = target end,
    }

    local z = win.zoom or 1
    local handled = MouseClickController.handleMousePressed(env, (win.x or 0) + (3 * z), (win.y or 0) + (4 * z), 1)

    expect(handled).toBe(true)
    expect(win.editShapeDrag).toBeTruthy()
    expect(win.editShapeDrag.kind).toBe("rect_or_line")
    expect(win.editShapeDrag.startX).toBe(3)
    expect(win.editShapeDrag.startY).toBe(4)
  end)

  it("uses pick and fill cursors over sketch canvas when G or F are held", function()
    local setTo = nil
    local grab = false
    local fill = false
    local win = {
      _closed = false,
      isPalette = false,
      layers = {
        {
          kind = "canvas",
          canvas = {},
        },
      },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 0, 0, 0, 0 end,
    }

    love.mouse.setCursor = function(cursor) setTo = cursor end
    love.keyboard.isDown = function(key)
      if key == "g" then return grab end
      if key == "f" then return fill end
      return false
    end
    local ResolutionController = require("controllers.app.resolution_controller")
    ResolutionController.getScaledMouse = function()
      -- Below default app top strip height (see cursors_controller tests) so hits are not treated as quick buttons.
      return { x = 4, y = 100 }
    end

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
end)
