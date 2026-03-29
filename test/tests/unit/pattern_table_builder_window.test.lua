local WM = require("controllers.window.window_controller")
local BrushController = require("controllers.input_support.brush_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

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

describe("pattern_table_builder_window.lua", function()
  it("creates source and packed canvas layers", function()
    local wm = WM.new()
    local win = wm:createPatternTableBuilderWindow()

    expect(win.kind).toBe("pattern_table_builder")
    expect(#win.layers).toBe(2)
    expect(win.layers[1].name).toBe("Source Canvas")
    expect(win.layers[2].name).toBe("Packed Pattern Table")
    expect(win.layers[1].kind).toBe("canvas")
    expect(win.layers[2].kind).toBe("canvas")
    expect(win.layers[1].canvas.width).toBe(256)
    expect(win.layers[1].canvas.height).toBe(240)
    expect(win.layers[2].canvas.width).toBe(128)
    expect(win.layers[2].canvas.height).toBe(128)
    local w1, h1 = win:getContentSize()
    expect(w1).toBe(256)
    expect(h1).toBe(240)
    win:setActiveLayerIndex(2)
    local w2, h2 = win:getContentSize()
    expect(w2).toBe(128)
    expect(h2).toBe(128)
  end)

  it("supports canvas paint and undo redo on the source canvas", function()
    local wm = WM.new()
    local win = wm:createPatternTableBuilderWindow()
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
    local win = wm:createPatternTableBuilderWindow()
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
    local win = wm:createPatternTableBuilderWindow()
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
    local win = wm:createPatternTableBuilderWindow()
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

  it("uses color 0 when the eraser tool is active", function()
    local wm = WM.new()
    local win = wm:createPatternTableBuilderWindow()
    local app = makeApp()
    local canvas = win.layers[1].canvas

    canvas:edit(4, 5, 3)
    expect(win:setBuilderTool("eraser")).toBe(true)

    app.undoRedo:startPaintEvent()
    local ok = BrushController.paintPixel(app, win, 0, 0, 4, 5, false)
    expect(ok).toBe(true)
    expect(app.undoRedo:finishPaintEvent()).toBe(true)
    expect(canvas:getPixel(4, 5)).toBe(0)
  end)
end)
