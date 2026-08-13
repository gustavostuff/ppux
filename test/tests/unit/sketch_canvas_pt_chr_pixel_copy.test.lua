local WM = require("controllers.window.window_controller")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")

local function paintTile(canvas, tileCol, tileRow, value)
  local ox = tileCol * 8
  local oy = tileRow * 8
  for y = 0, 7 do
    for x = 0, 7 do
      canvas:edit(ox + x, oy + y, value)
    end
  end
end

local function makeChrTargetTile()
  local bankBytes = {}
  for i = 1, 16 do
    bankBytes[i] = 0
  end
  local pixels = {}
  for i = 1, 64 do
    pixels[i] = 0
  end
  return {
    pixels = pixels,
    _bankBytesRef = bankBytes,
    _bankIndex = 1,
    index = 0,
    refreshImage = function() end,
  }
end

local function makeChrWindow(targetTile)
  return {
    kind = "chr",
    cols = 4,
    rows = 4,
    layers = { { kind = "tile" } },
    getActiveLayerIndex = function()
      return 1
    end,
    getSelected = function()
      return 0, 0, 1
    end,
    get = function()
      return targetTile
    end,
    setSelected = function() end,
  }
end

describe("sketch canvas - pixel copy PT -> CHR/ROM", function()
  beforeEach(function()
    KeyboardClipboardController.reset()
  end)

  it("freezes unique and padded PT slots from sketch pool {x,y}", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    sketch.paddingTileIndex = 1
    paintTile(sketch.layers[1].canvas, 0, 0, 1)
    paintTile(sketch.layers[1].canvas, 1, 0, 2)

    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))

    local uniquePixels = SketchCanvasPackController.extractFrozenPixelsForPatternTableCell(pt, 0, 0, wm)
    expect(uniquePixels).toBeTruthy()
    expect(uniquePixels[1]).toBe(1)

    -- Logical slot past uniqueCount uses padding pool index 1 (solid 2 at 8,0).
    local padCol = 3
    local padRow = 0
    local logical = SketchCanvasPackController.logicalIndexForPatternTableCell(pt, padCol, padRow)
    expect(logical).toBeGreaterThanOrEqual(3)
    local padPixels = SketchCanvasPackController.extractFrozenPixelsForPatternTableCell(pt, padCol, padRow, wm)
    expect(padPixels).toBeTruthy()
    expect(padPixels[1]).toBe(2)

    local entry, poolIndex = SketchCanvasPackController.poolEntryForLogicalSlot(sketch, logical)
    expect(poolIndex).toBe(1)
    expect(entry.x).toBe(8)
    expect(entry.y).toBe(0)
  end)

  it("copy from sketch PT allows CHR paste and freezes pixels against later sketch edits", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 3)

    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))

    local sourceItem = pt.layers[1].items[1]
    expect(sourceItem.pixels[1]).toBe(3)
    pt.layers[1].multiTileSelection = { [1] = true }

    local targetTile = makeChrTargetTile()
    local chrWin = makeChrWindow(targetTile)
    local status = nil
    local ctx = {
      setStatus = function(text)
        status = text
      end,
      app = { wm = wm },
    }

    expect(KeyboardClipboardController.performClipboardAction(ctx, pt, "copy")).toBe(true)
    local avail = KeyboardClipboardController.getActionAvailability(ctx, chrWin, "paste")
    expect(avail.allowed).toBe(true)

    expect(KeyboardClipboardController.performClipboardAction(ctx, chrWin, "paste")).toBe(true)
    expect(targetTile.pixels[1]).toBe(3)
    expect(status).toBe("Pasted 1 tile")

    -- Mutate sketch paint after paste; CHR must keep frozen pixels.
    paintTile(sketch.layers[1].canvas, 0, 0, 1)
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))
    expect(pt.layers[1].items[1].pixels[1]).toBe(1)
    expect(targetTile.pixels[1]).toBe(3)
  end)

  it("drag freeze marks chrPixelPaint with canvas-sampled pixels", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))

    local drag = {
      srcWin = pt,
      srcCol = 0,
      srcRow = 0,
      item = pt.layers[1].items[1],
      tileGroup = nil,
    }
    local ok = SketchCanvasPackController.freezeSketchOwnedPatternTableDrag(pt, drag, wm)
    expect(ok).toBe(true)
    expect(drag.chrPixelPaint).toBe(true)
    expect(drag.item.pixels[1]).toBe(2)
    expect(drag.item).toNotBe(pt.layers[1].items[1])

    paintTile(sketch.layers[1].canvas, 0, 0, 0)
    expect(drag.item.pixels[1]).toBe(2)
  end)

  it("freezeSketchReflectDrag materializes drawable scratch tiles for ghost overlay", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    paintTile(sketch.layers[1].canvas, 1, 0, 3)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))

    local prev = rawget(_G, "ctx")
    rawset(_G, "ctx", {
      getMode = function()
        return "tile"
      end,
      app = { wm = wm },
      wm = function()
        return wm
      end,
    })

    local handleA = sketch:get(0, 0, 1)
    local handleB = sketch:get(1, 0, 1)
    expect(handleA.kind).toBe("sketch_nt")
    expect(type(handleA.draw)).toNotBe("function")

    local drag = {
      srcWin = sketch,
      srcCol = 0,
      srcRow = 0,
      item = handleA,
      tileGroup = {
        entries = {
          { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = handleA },
          { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = handleB },
        },
      },
    }

    expect(SketchCanvasPackController.freezeSketchReflectDrag(sketch, drag)).toBe(true)
    expect(type(drag.item.draw)).toBe("function")
    expect(drag.item.pixels[1]).toBe(2)
    expect(type(drag.tileGroup.entries[1].item.draw)).toBe("function")
    expect(type(drag.tileGroup.entries[2].item.draw)).toBe("function")
    expect(drag.tileGroup.entries[2].item.pixels[1]).toBe(3)

    rawset(_G, "ctx", prev)
  end)

  it("applyFrozenPixelPaintToChr paints destination CHR pixels", function()
    local targetTile = makeChrTargetTile()
    local chrWin = makeChrWindow(targetTile)
    local payload = {
      kind = "tile",
      chrPixelPaint = true,
      sourceWin = {},
      entries = {
        {
          offsetCol = 0,
          offsetRow = 0,
          item = {
            pixels = (function()
              local p = {}
              for i = 1, 64 do
                p[i] = 1
              end
              return p
            end)(),
          },
        },
      },
      width = 1,
      height = 1,
      count = 1,
    }
    local result = KeyboardClipboardController.applyFrozenPixelPaintToChr(
      { app = {} },
      chrWin,
      1,
      payload,
      { anchorCol = 0, anchorRow = 0 }
    )
    expect(result.count).toBe(1)
    expect(targetTile.pixels[1]).toBe(1)
    expect(targetTile.pixels[64]).toBe(1)
  end)

  it("syncs sketch-owned PT paint back to sketch canvas and marks Reflect dirty", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 1)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))

    local item = pt.layers[1].items[1]
    item:edit(0, 0, 3)
    local invalidated = false
    pt.invalidateTileLayerCanvas = function()
      invalidated = true
    end

    local ok = SketchCanvasPackController.afterScratchPatternTablePaint({ wm = wm }, pt, 0, 0)
    expect(ok).toBe(true)
    expect(invalidated).toBe(true)
    expect(sketch.layers[1].canvas:getPixel(0, 0)).toBe(3)
    expect(sketch._reflectDisplayDirty).toBe(true)

    assert(SketchCanvasPackController.setReflectPatternTable(sketch, true))
    local reflect = SketchCanvasPackController.getReflectDisplayCanvas(sketch)
    expect(reflect:getPixel(0, 0)).toBe(3)
  end)

  it("undo of scratch PT paint refreshes PT canvas and Reflect immediately", function()
    local UndoRedoController = require("controllers.input_support.undo_redo_controller")
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 1)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))

    local item = pt.layers[1].items[1]
    expect(item._sketchCanvasWindowId).toBe(sketch._id)
    expect(item._sketchPoolX).toBe(0)
    expect(item._sketchPoolY).toBe(0)

    local undo = UndoRedoController.new(20)
    undo:startPaintEvent()
    undo:recordDirectPixelChange(item, 0, 0, 1, 3)
    item:edit(0, 0, 3)
    sketch.layers[1].canvas:edit(0, 0, 3)
    expect(undo:finishPaintEvent()).toBe(true)

    assert(SketchCanvasPackController.setReflectPatternTable(sketch, true))
    SketchCanvasPackController.invalidateReflectDisplay(sketch)
    expect(SketchCanvasPackController.getReflectDisplayCanvas(sketch):getPixel(0, 0)).toBe(3)

    local invalidated = false
    pt.invalidateTileLayerCanvas = function()
      invalidated = true
    end

    expect(undo:undo({ wm = wm })).toBe(true)
    expect(item:getPixel(0, 0)).toBe(1)
    expect(sketch.layers[1].canvas:getPixel(0, 0)).toBe(1)
    expect(invalidated).toBe(true)
    expect(sketch._reflectDisplayDirty).toBe(true)
    expect(SketchCanvasPackController.getReflectDisplayCanvas(sketch):getPixel(0, 0)).toBe(1)
  end)

  it("shows a fixed-width 2-character tolerance label between +/- buttons", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local ToolbarController = require("controllers.window.toolbar_controller")
    local toolbar = ToolbarController.createSpecializedToolbar(sketch, {}, wm)
    expect(toolbar.toleranceValueButton).toBeTruthy()
    expect(toolbar.toleranceValueButton.text).toBe("0")
    expect(toolbar.toleranceValueButton.w).toBe(15)
    expect(toolbar.toleranceValueButton._digitSlotW).toBe(7.5)

    sketch.tolerance = 12
    toolbar:updateIcons()
    expect(toolbar.toleranceValueButton.text).toBe("12")

    local down = toolbar.toleranceDownButton
    local label = toolbar.toleranceValueButton
    local up = toolbar.toleranceUpButton
    expect(label.x).toBeGreaterThanOrEqual(down.x + down.w)
    expect(up.x).toBeGreaterThanOrEqual(label.x + label.w)
  end)
end)
