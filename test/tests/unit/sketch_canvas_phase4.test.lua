local WM = require("controllers.window.window_controller")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")
local ToolbarController = require("controllers.window.toolbar_controller")

local function paintTile(canvas, tileCol, tileRow, value)
  local ox = tileCol * 8
  local oy = tileRow * 8
  for y = 0, 7 do
    for x = 0, 7 do
      canvas:edit(ox + x, oy + y, value)
    end
  end
end

local function uniquePattern(id)
  local p = {}
  for i = 1, 64 do
    p[i] = 0
  end
  local n = math.floor(tonumber(id) or 0)
  p[1] = n % 4
  p[2] = math.floor(n / 4) % 4
  p[3] = math.floor(n / 16) % 4
  p[4] = math.floor(n / 64) % 4
  p[5] = math.floor(n / 256) % 4
  return p
end

describe("sketch canvas phase 4 - link + pattern table apply", function()
  it("links sketch to pattern table both ways and clears CHR ranges", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow({ title = "PT" })
    pt.layers[1].patternTable = { ranges = { { bank = 1, from = 0, to = 15 } } }

    local ok = SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm)
    expect(ok).toBe(true)
    expect(sketch.linkedPatternTableWindowId).toBe(pt._id)
    expect(pt.linkedSketchCanvasWindowId).toBe(sketch._id)
    expect(#(pt.layers[1].patternTable.ranges or {})).toBe(0)

    local consumers = PatternTableDisplayController.getLinkedConsumersForPatternTable(wm, pt)
    expect(#consumers).toBe(1)
    expect(consumers[1].kind).toBe("sketch_canvas")
  end)

  it("applies 256 scratch tiles with padding from paddingTileIndex", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    sketch.paddingTileIndex = 1
    paintTile(sketch.layers[1].canvas, 0, 0, 1)
    paintTile(sketch.layers[1].canvas, 1, 0, 2)

    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    local ok, pack = SketchCanvasPackController.generateAndApply(sketch, wm)
    expect(ok).toBe(true)
    expect(pack.uniqueCount).toBe(3) -- blank + two solids
    expect(pack.appliedToPatternTable).toBe(true)

    local items = pt.layers[1].items
    expect(#items).toBe(256)
    expect(items[1]._isScratchTile).toBe(true)
    expect(items[1].pixels[1]).toBe(1) -- first unique is painted solid 1 at 0,0
    expect(items[2].pixels[1]).toBe(2)
    -- padding uses pool index 1 (second unique)
    expect(items[4]).toBe(items[2])
    expect(items[256]).toBe(items[2])
  end)

  it("does not mutate linked PT when pack exceeds 256 uniques", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))

    -- Seed one scratch tile so we can detect wipe/mutation.
    pt.layers[1].items = {}
    pt.layers[1].items[1] = SketchCanvasPackController.makeScratchTileFromPixels(uniquePattern(9))
    local sentinel = pt.layers[1].items[1]

    sketch.layers[1].canvas.extractTilePixels = function(_self, ox, oy)
      local col = math.floor(ox / 8)
      local row = math.floor(oy / 8)
      return uniquePattern(row * 32 + col)
    end

    local ok, err = SketchCanvasPackController.generateAndApply(sketch, wm)
    expect(ok).toBe(false)
    expect(err).toBe("too_many_unique")
    expect(pt.layers[1].items[1]).toBe(sentinel)
  end)

  it("8x8/8x16 toggle relayouts sketch-owned pattern table items", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 1)
    paintTile(sketch.layers[1].canvas, 1, 0, 2)
    paintTile(sketch.layers[1].canvas, 2, 0, 3)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))

    -- In 8x8, grid pos N shows logical N. Mark logical 1 and 2 by first pixel.
    expect(pt.layers[1].mode).toBe("8x8")
    expect(pt.layers[1].items[2].pixels[1]).toBe(2)
    expect(pt.layers[1].items[3].pixels[1]).toBe(3)

    local label = PatternTableDisplayController.toggleTileLayerChrLayout(pt, 1, { wm = wm })
    expect(label).toBe("8x16 pairs")
    expect(pt.layers[1].mode).toBe("8x16")
    -- Same CHR mapping as bank windows: grid pos 1 shows logical 2.
    expect(BankViewController.chrOrderingIndexForGridPos("8x16", 1)).toBe(2)
    expect(pt.layers[1].items[2].pixels[1]).toBe(3)

    PatternTableDisplayController.toggleTileLayerChrLayout(pt, 1, { wm = wm })
    expect(pt.layers[1].mode).toBe("8x8")
    expect(pt.layers[1].items[2].pixels[1]).toBe(2)
  end)

  it("refreshAllPatternTableWindows skips sketch-owned pattern tables", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 3)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))

    local before = pt.layers[1].items[1]
    PatternTableDisplayController.refreshAllPatternTableWindows(wm, { tilesPool = {} })
    expect(pt.layers[1].items[1]).toBe(before)
    expect(before._isScratchTile).toBe(true)
  end)

  it("undo restores sketch pattern table link", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    local undo = UndoRedoController.new(10)
    local app = { wm = wm, undoRedo = undo }

    local before = sketch.linkedPatternTableWindowId
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    undo:addSketchCanvasPatternTableLinkEvent({
      type = "sketch_canvas_pattern_table_link",
      sketchWin = sketch,
      beforeLinkedId = before,
      afterLinkedId = sketch.linkedPatternTableWindowId,
    })

    expect(sketch.linkedPatternTableWindowId).toBe(pt._id)
    undo:undo(app)
    expect(sketch.linkedPatternTableWindowId).toBeNil()
    expect(pt.linkedSketchCanvasWindowId).toBeNil()
    undo:redo(app)
    expect(sketch.linkedPatternTableWindowId).toBe(pt._id)
    expect(pt.linkedSketchCanvasWindowId).toBe(sketch._id)
  end)

  it("unlink clears pattern table scratch items and ranges", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))
    expect(#pt.layers[1].items).toBe(256)

    assert(SketchCanvasPackController.unlinkSketchPatternTable(sketch, wm))
    expect(sketch.linkedPatternTableWindowId).toBeNil()
    expect(pt.linkedSketchCanvasWindowId).toBeNil()
    expect(#(pt.layers[1].items or {})).toBe(0)
    expect(#(pt.layers[1].patternTable.ranges or {})).toBe(0)
  end)

  it("toolbar Generate applies to linked PT and records undo", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))

    local undo = UndoRedoController.new(10)
    local statuses = {}
    local app = {
      wm = wm,
      undoRedo = undo,
      setStatus = function(_app, text)
        statuses[#statuses + 1] = text
      end,
      showPatternTableLinkDestinationContextMenu = function()
        return true
      end,
    }
    local toolbar = ToolbarController.createSpecializedToolbar(sketch, { app = app }, wm)
    expect(toolbar.linkButton.enabled).toBe(true)

    toolbar.generateButton.action()
    expect(#pt.layers[1].items).toBe(256)
    expect(statuses[#statuses]:find("pattern table", 1, true)).toBeTruthy()

    undo:undo(app)
    expect(#(sketch.tilesPool or {})).toBe(0)
  end)

  it("pattern table source Jump menu lists sketch consumers without crashing on nil layerIndex", function()
    local AppCoreController = require("controllers.app.core_controller")
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    sketch.title = "My sketch"
    local pt = wm:createPatternTableWindow()
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))

    local app = setmetatable({ wm = wm }, AppCoreController)
    local items = app:_buildPatternTableLinkSourceContextMenuItems(pt)
    local jump = nil
    for _, item in ipairs(items) do
      if item.text == "Jump to linked layer" then
        jump = item
        break
      end
    end
    expect(jump).toBeTruthy()
    local children = jump.children()
    expect(#children).toBe(1)
    expect(children[1].text).toBe("My sketch")
  end)
end)
