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
  it("creates a source canvas layer with unique blank scratch tiles", function()
    local wm = WM.new()
    local win = wm:createPatternTableBuilderWindow()

    expect(win.kind).toBe("pattern_table_builder")
    expect(#win.layers).toBe(2)
    expect(win.layers[1].name).toBe("Source Canvas")
    expect(win.layers[2].name).toBe("Packed Pattern Table")
    expect(win.layers[1].kind).toBe("tile")
    expect(win.cols).toBe(32)
    expect(win.rows).toBe(30)

    local first = win:get(0, 0, 1)
    local second = win:get(1, 0, 1)
    expect(first).toNotBe(nil)
    expect(second).toNotBe(nil)
    expect(first).toNotBe(second)
    expect(first._isScratchTile).toBe(true)
    expect(first:getPixel(0, 0)).toBe(0)
  end)

  it("supports scratch-tile paint and undo redo on the source canvas", function()
    local wm = WM.new()
    local win = wm:createPatternTableBuilderWindow()
    local app = makeApp()

    app.undoRedo:startPaintEvent()
    local ok = BrushController.paintPixel(app, win, 0, 0, 2, 3, false)
    expect(ok).toBe(true)
    expect(app.undoRedo:finishPaintEvent()).toBe(true)

    local tile = win:get(0, 0, 1)
    expect(tile:getPixel(2, 3)).toBe(3)
    expect(app.undoRedo:undo(app)).toBe(true)
    expect(tile:getPixel(2, 3)).toBe(0)
    expect(app.undoRedo:redo(app)).toBe(true)
    expect(tile:getPixel(2, 3)).toBe(3)
  end)

  it("supports scratch-tile flood fill with undo redo", function()
    local wm = WM.new()
    local win = wm:createPatternTableBuilderWindow()
    local app = makeApp()
    local tile = win:get(0, 0, 1)

    tile:edit(7, 7, 1)
    app.currentColor = 2

    local ok = BrushController.floodFillTile(app, win, 0, 0, 0, 0)
    expect(ok).toBe(true)
    expect(tile:getPixel(0, 0)).toBe(2)
    expect(tile:getPixel(7, 7)).toBe(1)

    expect(app.undoRedo:undo(app)).toBe(true)
    expect(tile:getPixel(0, 0)).toBe(0)
    expect(tile:getPixel(7, 7)).toBe(1)

    expect(app.undoRedo:redo(app)).toBe(true)
    expect(tile:getPixel(0, 0)).toBe(2)
    expect(tile:getPixel(7, 7)).toBe(1)
  end)
end)
