local WM = require("controllers.window.window_controller")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local BrushController = require("controllers.input_support.brush_controller")
local ToolbarController = require("controllers.window.toolbar_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local function paintTile(canvas, tileCol, tileRow, value)
  local ox = tileCol * 8
  local oy = tileRow * 8
  for y = 0, 7 do
    for x = 0, 7 do
      canvas:edit(ox + x, oy + y, value)
    end
  end
end

local function paintTileDiffPixels(canvas, tileCol, tileRow, baseValue, flipCount)
  paintTile(canvas, tileCol, tileRow, baseValue)
  local ox = tileCol * 8
  local oy = tileRow * 8
  local flipped = 0
  for y = 0, 7 do
    for x = 0, 7 do
      if flipped >= flipCount then
        return
      end
      canvas:edit(ox + x, oy + y, (baseValue + 1) % 4)
      flipped = flipped + 1
    end
  end
end

local function withMode(mode, fn, wm)
  local prev = rawget(_G, "ctx")
  rawset(_G, "ctx", {
    getMode = function()
      return mode
    end,
    app = wm and { wm = wm } or nil,
    wm = wm and function()
      return wm
    end or nil,
  })
  local ok, err = pcall(fn)
  rawset(_G, "ctx", prev)
  if not ok then
    error(err)
  end
end

describe("sketch canvas - tile-mode mirror view", function()
  it("composes mirror display from nametableBytes + pool without mutating paint canvas", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local paint = sketch.layers[1].canvas
    paintTile(paint, 0, 0, 1)
    paintTileDiffPixels(paint, 1, 0, 1, 3)

    assert(SketchCanvasPackController.generate(sketch))
    sketch.tolerance = 3
    assert(SketchCanvasPackController.generate(sketch))
    expect(#sketch.tilesPool).toBe(2)

    local beforePaint = paint:extractTilePixels(8, 0, 8)
    expect(beforePaint[1]).toBe(2)

    local reflect = SketchCanvasPackController.getReflectDisplayCanvas(sketch)
    expect(reflect).toBeTruthy()
    expect(reflect).toNotBe(paint)

    local reflected = reflect:extractTilePixels(8, 0, 8)
    local canonical = paint:extractTilePixels(0, 0, 8)
    expect(reflected[1]).toBe(canonical[1])
    expect(reflected[1]).toBe(1)

    local afterPaint = paint:extractTilePixels(8, 0, 8)
    expect(afterPaint[1]).toBe(beforePaint[1])
  end)

  it("blocks paint in global tile mode when a pack exists", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generate(sketch))

    withMode("tile", function()
      expect(WindowCaps.isSketchReflectNametable(sketch)).toBe(true)
      local app = { brushSize = 1, currentColor = 3 }
      local painted = BrushController.paintPixel(app, sketch, 2, 0, 0, 0, false)
      expect(painted).toBe(false)
      expect(sketch.layers[1].canvas:getPixel(16, 0)).toBe(0)
    end, wm)

    withMode("edit", function()
      expect(WindowCaps.isSketchReflectNametable(sketch)).toBe(false)
    end, wm)
  end)

  it("tile mode without a linked pattern table is not reflect (edit paint stays hidden)", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(true)

    -- Unlink in edit mode: pack + paint kept.
    assert(SketchCanvasPackController.unlinkSketchPatternTable(sketch, wm, { clearPack = false }))
    expect(sketch.layers[1].canvas:getPixel(0, 0)).toBe(2)
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(true)

    withMode("tile", function()
      -- Tile mode must not treat an unlinked sketch as a nametable mirror.
      expect(WindowCaps.isSketchReflectNametable(sketch)).toBe(false)
    end, wm)
  end)

  it("bakes nametable composition into paint when leaving tile mode after NT edits", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local paint = sketch.layers[1].canvas
    paintTile(paint, 0, 0, 1)
    paintTile(paint, 1, 0, 2)
    assert(SketchCanvasPackController.generate(sketch))

    -- Swap NT cells (0,0) <-> (1,0)
    sketch:swapNametableBytesAt(0, 0, 1, 0)
    expect(SketchCanvasPackController.isReflectLayoutDirty(sketch)).toBe(true)

    expect(SketchCanvasPackController.bakeReflectIntoPaint(sketch)).toBe(true)
    expect(SketchCanvasPackController.isReflectLayoutDirty(sketch)).toBe(false)
    -- After bake, screen cell (0,0) should show former tile-1 content (color 2)
    expect(paint:getPixel(0, 0)).toBe(2)
    expect(paint:getPixel(8, 0)).toBe(1)
  end)

  it("does not bake paint away when toggling tile/edit without nametable edits", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local paint = sketch.layers[1].canvas
    paintTile(paint, 0, 0, 1)
    assert(SketchCanvasPackController.generate(sketch))

    paint:edit(3, 3, 2)
    SketchCanvasPackController.markGenerateDirty(sketch)

    expect(SketchCanvasPackController.isReflectLayoutDirty(sketch)).toBe(false)
    expect(SketchCanvasPackController.bakeReflectIntoPaint(sketch)).toBe(false)
    expect(paint:getPixel(3, 3)).toBe(2)
  end)

  it("marks Generate dirty (NES 07) after paint and clears after Generate", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow({ title = "PT" })
    sketch.linkedPatternTableWindowId = pt._id
    paintTile(sketch.layers[1].canvas, 0, 0, 1)

    local toolbar = ToolbarController.createSpecializedToolbar(sketch, { app = {} }, wm)
    expect(toolbar.reflectButton).toBeNil()
    expect(SketchCanvasPackController.isGenerateDirty(sketch)).toBe(false)

    local app = {
      brushSize = 1,
      currentColor = 2,
      undoRedo = {
        recordDirectPixelChange = function() end,
      },
      setStatus = function() end,
    }
    expect(BrushController.paintPixel(app, sketch, 0, 0, 0, 0, false)).toBe(true)
    expect(SketchCanvasPackController.isGenerateDirty(sketch)).toBe(true)
    toolbar:updateIcons()
    local dirtyBg = toolbar.generateButton.bgColor
    expect(dirtyBg).toBeTruthy()
    expect(dirtyBg[1] > 0.2).toBe(true)

    assert(SketchCanvasPackController.generateAndApply(sketch, wm))
    expect(SketchCanvasPackController.isGenerateDirty(sketch)).toBe(false)
    toolbar:updateIcons()
  end)

  it("keeps packed tile-mode view when Generate is dirty (paint edits wait for Generate)", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    local paint = sketch.layers[1].canvas
    paintTile(paint, 0, 0, 3)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generate(sketch))

    local before = SketchCanvasPackController.getReflectDisplayCanvas(sketch)
    expect(before).toBeTruthy()
    expect(before:getPixel(0, 0)).toBe(3)

    -- Paint without invalidating reflect (same as brush path now).
    paintTile(paint, 0, 0, 1)
    SketchCanvasPackController.markGenerateDirty(sketch)

    expect(SketchCanvasPackController.isGenerateDirty(sketch)).toBe(true)
    local after = SketchCanvasPackController.getReflectDisplayCanvas(sketch)
    expect(after).toBeTruthy()
    expect(after:getPixel(0, 0)).toBe(3)
    withMode("tile", function()
      expect(WindowCaps.isSketchReflectNametable(sketch)).toBe(true)
    end, wm)
  end)

  it("marks Generate dirty on load when pack samples disagree with paint", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    local paint = sketch.layers[1].canvas
    -- Two identical non-solid tiles share one pool sample at the first occurrence.
    local function paintMark(col, row)
      local ox, oy = col * 8, row * 8
      for y = 0, 7 do
        for x = 0, 7 do
          paint:edit(ox + x, oy + y, 0)
        end
      end
      paint:edit(ox + 1, oy + 1, 3)
      paint:edit(ox + 2, oy + 3, 2)
      paint:edit(ox + 5, oy + 6, 1)
    end
    paintMark(0, 0)
    paintMark(2, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generate(sketch))
    expect(SketchCanvasPackController.isGenerateDirty(sketch)).toBe(false)

    -- Clear only the pool sample cell; the other shared occurrence still has paint.
    paintTile(paint, 0, 0, 0)
    expect(SketchCanvasPackController.markGenerateDirtyIfPackDisagreesWithPaint(sketch)).toBe(true)
    expect(SketchCanvasPackController.isGenerateDirty(sketch)).toBe(true)
    withMode("tile", function()
      expect(WindowCaps.isSketchReflectNametable(sketch)).toBe(true)
    end, wm)
  end)

  it("does not collapse near-transparent skirt edges into blank solidShade 0", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local paint = sketch.layers[1].canvas
    -- Exact blank elsewhere; near-empty "skirt" tile with a few opaque pixels.
    for y = 0, 7 do
      for x = 0, 7 do
        paint:edit(x, y, 0)
      end
    end
    local ox, oy = 16, 16
    for y = 0, 7 do
      for x = 0, 7 do
        paint:edit(ox + x, oy + y, 0)
      end
    end
    paint:edit(ox + 1, oy + 2, 2)
    paint:edit(ox + 2, oy + 3, 2)
    paint:edit(ox + 3, oy + 4, 1)

    local pack = assert(SketchCanvasPackController.packFromCanvas(paint, 8))
    local skirtNt = (2 * 32 + 2) + 1 -- col=2,row=2
    local poolIndex = pack.nametableBytes[skirtNt]
    local entry = pack.tilesPool[poolIndex + 1]
    expect(entry.solidShade).toBeNil()
    local pixels = SketchCanvasPackController.pixelsForPoolEntry(paint, entry)
    -- Local (1,2) was painted 2 → flat index py*8+px+1.
    expect(pixels[2 * 8 + 1 + 1]).toBe(2)
  end)
end)
