local WM = require("controllers.window.window_controller")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local BrushController = require("controllers.input_support.brush_controller")
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

describe("sketch canvas phase 6 - Reflect view", function()
  it("composes Reflect from nametableBytes + pool without mutating paint canvas", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local paint = sketch.layers[1].canvas
    paintTile(paint, 0, 0, 1)
    paintTileDiffPixels(paint, 1, 0, 1, 3)

    assert(SketchCanvasPackController.generate(sketch))
    sketch.tolerance = 3
    assert(SketchCanvasPackController.generate(sketch))
    expect(#sketch.tilesPool).toBe(2) -- blank + merged painted

    local beforePaint = paint:extractTilePixels(8, 0, 8)
    expect(beforePaint[1]).toBe(2) -- first flipped pixel of near-match tile

    local ok = SketchCanvasPackController.setReflectPatternTable(sketch, true)
    expect(ok).toBe(true)
    expect(sketch.reflectPatternTable).toBe(true)

    local reflect = SketchCanvasPackController.getReflectDisplayCanvas(sketch)
    expect(reflect).toBeTruthy()
    expect(reflect).toNotBe(paint)

    -- Cell (1,0) should show the canonical pool sample (first painted solid at 0,0),
    -- not the near-match paint at 8,0.
    local reflected = reflect:extractTilePixels(8, 0, 8)
    local canonical = paint:extractTilePixels(0, 0, 8)
    expect(reflected[1]).toBe(canonical[1])
    expect(reflected[1]).toBe(1)

    -- Paint buffer still has the original near-match pixels.
    local afterPaint = paint:extractTilePixels(8, 0, 8)
    expect(afterPaint[1]).toBe(beforePaint[1])

    SketchCanvasPackController.setReflectPatternTable(sketch, false)
    expect(sketch.reflectPatternTable).toBe(false)
    expect(paint:extractTilePixels(8, 0, 8)[1]).toBe(beforePaint[1])
  end)

  it("blocks paint while Reflect is on and Generate still packs the paint buffer", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.generate(sketch))
    assert(SketchCanvasPackController.setReflectPatternTable(sketch, true))

    local app = { brushSize = 1, currentColor = 3 }
    local painted = BrushController.paintPixel(app, sketch, 2, 0, 0, 0, false)
    expect(painted).toBe(false)
    expect(sketch.layers[1].canvas:getPixel(16, 0)).toBe(0)

    SketchCanvasPackController.setReflectPatternTable(sketch, false)
    sketch.layers[1].canvas:edit(16, 0, 3)
    assert(SketchCanvasPackController.generate(sketch))
    -- New unique from paint edit should be present.
    expect(#sketch.tilesPool >= 2).toBe(true)
  end)

  it("enables Reflect toolbar after Generate and toggles state", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 1)
    local statuses = {}
    local toolbar = ToolbarController.createSpecializedToolbar(sketch, {
      app = {
        setStatus = function(_app, text)
          statuses[#statuses + 1] = text
        end,
      },
    }, wm)

    expect(toolbar.reflectButton.enabled).toBe(false)
    assert(SketchCanvasPackController.generate(sketch))
    toolbar:updateIcons()
    expect(toolbar.reflectButton.enabled).toBe(true)

    toolbar.reflectButton.action()
    expect(sketch.reflectPatternTable).toBe(true)
    expect(statuses[#statuses]:find("Reflect on", 1, true)).toBeTruthy()

    toolbar.reflectButton.action()
    expect(sketch.reflectPatternTable).toBe(false)
  end)
end)
