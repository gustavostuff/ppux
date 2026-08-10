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

describe("sketch canvas - link + pattern table apply", function()
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

    -- Paint real unique tiles into the canvas buffer (native pack reads .pixels,
    -- so stubbing extractTilePixels alone is not enough).
    local canvas = sketch.layers[1].canvas
    for id = 0, 256 do
      local col = id % 32
      local row = math.floor(id / 32)
      canvas:loadTilePixels(col * 8, row * 8, uniquePattern(id), 8)
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

    assert(SketchCanvasPackController.unlinkSketchPatternTable(sketch, wm, { clearPack = false }))
    expect(sketch.linkedPatternTableWindowId).toBeNil()
    expect(pt.linkedSketchCanvasWindowId).toBeNil()
    expect(#(pt.layers[1].items or {})).toBe(0)
    expect(#(pt.layers[1].patternTable.ranges or {})).toBe(0)
    -- Edit/pixel path: pack data stays when clearPack is false (or when not in tile mode).
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(true)
  end)

  it("unlink in tile mode clears sketch pack catalog but keeps paint", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(true)
    expect(sketch.layers[1].canvas:getPixel(0, 0)).toBe(2)

    local toasts = {}
    local prevCtx = rawget(_G, "ctx")
    rawset(_G, "ctx", {
      getMode = function()
        return "tile"
      end,
      app = {
        showToast = function(_, kind, text)
          toasts[#toasts + 1] = { kind = kind, text = text }
        end,
      },
    })

    assert(SketchCanvasPackController.unlinkSketchPatternTable(sketch, wm, { clearPack = true }))
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(false)
    expect(#(sketch.tilesPool or {})).toBe(0)
    expect(sketch.nametableBytes).toBeNil()
    -- Paint must survive so switching back to Edit mode still shows the canvas.
    expect(sketch.layers[1].canvas:getPixel(0, 0)).toBe(2)
    expect(#toasts).toBe(1)
    expect(toasts[1].kind).toBe("info")
    expect(toasts[1].text).toBe("Sketch tiles cleared; Edit-mode paint kept")

    rawset(_G, "ctx", prevCtx)
  end)

  it("undo of tile-mode unlink restores pack, paint, and pattern table tiles", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))
    local beforePack = SketchCanvasPackController.snapshotPackFields(sketch)
    local beforeItems = SketchCanvasPackController.snapshotPatternTableItemPixels(pt)
    expect(#pt.layers[1].items).toBe(256)

    local undo = UndoRedoController.new(10)
    local app = { wm = wm, undoRedo = undo }
    assert(SketchCanvasPackController.unlinkSketchPatternTable(sketch, wm, { clearPack = true }))
    undo:addSketchCanvasPatternTableLinkEvent({
      type = "sketch_canvas_pattern_table_link",
      sketchWin = sketch,
      beforeLinkedId = pt._id,
      afterLinkedId = nil,
      beforePack = beforePack,
      afterPack = SketchCanvasPackController.snapshotPackFields(sketch),
      beforeItemsPixels = beforeItems,
      afterItemsPixels = nil,
    })

    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(false)
    expect(#(pt.layers[1].items or {})).toBe(0)

    assert(undo:undo(app))
    expect(sketch.linkedPatternTableWindowId).toBe(pt._id)
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(true)
    expect(sketch.layers[1].canvas:getPixel(0, 0)).toBe(2)
    expect(#(pt.layers[1].items or {})).toBe(256)
    expect(pt.layers[1].items[1].pixels[1]).toBe(2)
  end)

  it("closing a linked pattern table unlinks the sketch and clears tile-mode pack", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))
    expect(#(pt.layers[1].items or {}) > 0).toBe(true)

    local prevGetMode = nil
    local ctx = rawget(_G, "ctx")
    if type(ctx) ~= "table" then
      ctx = {}
      _G.ctx = ctx
    end
    prevGetMode = ctx.getMode
    ctx.getMode = function()
      return "tile"
    end

    assert(wm:closeWindow(pt))
    expect(sketch.linkedPatternTableWindowId).toBeNil()
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(false)
    expect(#(pt.layers[1].items or {})).toBe(0)
    expect(pt.linkedSketchCanvasWindowId).toBeNil()
    expect(sketch.layers[1].canvas:getPixel(0, 0)).toBe(2)
    expect(type(pt._sketchCloseUndoRestore)).toBe("table")

    ctx.getMode = prevGetMode
  end)

  it("undo of closing a linked pattern table restores link, pack, paint, and tiles", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 3)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))

    local ctx = rawget(_G, "ctx")
    if type(ctx) ~= "table" then
      ctx = {}
      _G.ctx = ctx
    end
    local prevGetMode = ctx.getMode
    ctx.getMode = function()
      return "tile"
    end

    local undo = UndoRedoController.new(10)
    local app = { wm = wm, undoRedo = undo }
    assert(wm:closeWindow(pt))
    local restore = pt._sketchCloseUndoRestore
    pt._sketchCloseUndoRestore = nil
    undo:addWindowEvent({
      type = "window_close",
      win = pt,
      wm = wm,
      prevClosed = false,
      prevMinimized = false,
      prevFocused = true,
      sketchPtRestore = restore,
    })

    assert(undo:undo(app))
    expect(pt._closed).toBe(false)
    expect(sketch.linkedPatternTableWindowId).toBe(pt._id)
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(true)
    expect(sketch.layers[1].canvas:getPixel(0, 0)).toBe(3)
    expect(#(pt.layers[1].items or {})).toBe(256)

    ctx.getMode = prevGetMode
  end)

  it("closing a linked pattern table in edit mode keeps pack data", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))

    local ctx = rawget(_G, "ctx")
    if type(ctx) ~= "table" then
      ctx = {}
      _G.ctx = ctx
    end
    local prevGetMode = ctx.getMode
    ctx.getMode = function()
      return "edit"
    end

    assert(wm:closeWindow(pt))
    expect(sketch.linkedPatternTableWindowId).toBeNil()
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(true)
    expect(sketch.layers[1].canvas:getPixel(0, 0)).toBe(2)

    ctx.getMode = prevGetMode
  end)

  it("toolbar Generate applies to linked PT and records undo", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))

    local undo = UndoRedoController.new(10)
    local toasts = {}
    local app = {
      wm = wm,
      undoRedo = undo,
      showToast = function(_app, kind, text)
        toasts[#toasts + 1] = { kind = kind, text = text }
      end,
      showPatternTableLinkDestinationContextMenu = function()
        return true
      end,
    }
    local toolbar = ToolbarController.createSpecializedToolbar(sketch, {
      app = app,
      showToast = function(kind, text)
        toasts[#toasts + 1] = { kind = kind, text = text }
      end,
    }, wm)
    expect(toolbar.linkButton.enabled).toBe(true)

    toolbar.generateButton.action()
    expect(#pt.layers[1].items).toBe(256)
    expect(toasts[#toasts].text:find("pattern table", 1, true)).toBeTruthy()

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
      if item.text == "Jump to sketch canvas" then
        jump = item
        break
      end
    end
    expect(jump).toBeTruthy()
    local children = jump.children()
    expect(#children).toBe(1)
    expect(children[1].text).toBe("My sketch")

    local unlink = nil
    for _, item in ipairs(items) do
      if item.text == "Unlink sketch canvas" then
        unlink = item
        break
      end
    end
    expect(unlink).toBeTruthy()
  end)
end)
