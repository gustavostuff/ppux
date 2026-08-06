local WM = require("controllers.window.window_controller")
local PixelCanvas = require("ui.windows_system.pixel_canvas")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")

describe("sketch_canvas_pack_controller.lua - PNG import", function()
  local originalNewFileData
  local originalNewImageData
  local originalGetPaletteColors

  local function makeSolidImageData(width, height, shade)
    shade = shade or 0.5
    return {
      getWidth = function() return width end,
      getHeight = function() return height end,
      getPixel = function()
        return shade, shade, shade, 1.0
      end,
    }
  end

  local function makeTooManyUniquesImageData()
    -- Four brightness ranks; encode a unique base-4 pattern per 8x8 so pack exceeds 256.
    local shades = { 0.0, 0.33, 0.66, 1.0 }
    return {
      getWidth = function() return 256 end,
      getHeight = function() return 240 end,
      getPixel = function(_, x, y)
        local tileCol = math.floor(x / 8)
        local tileRow = math.floor(y / 8)
        local tileId = tileRow * 32 + tileCol
        local px = x % 8
        local py = y % 8
        local pixelIndex = py * 8 + px
        local digit = 0
        if pixelIndex < 6 then
          digit = math.floor(tileId / (4 ^ pixelIndex)) % 4
        end
        local s = shades[digit + 1]
        return s, s, s, 1.0
      end,
    }
  end

  local function makeFile()
    return {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "sketch.png" end,
    }
  end

  local function linkSketchAndPt()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "Sketch" })
    local pt = wm:createPatternTableWindow({ title = "PT" })
    sketch.linkedPatternTableWindowId = pt._id
    return wm, sketch, pt
  end

  beforeEach(function()
    originalNewFileData = love.filesystem.newFileData
    originalNewImageData = love.image.newImageData
    originalGetPaletteColors = ShaderPaletteController.getPaletteColors

    love.filesystem.newFileData = function()
      return {}
    end
    love.image.newImageData = function()
      return makeSolidImageData(256, 240, 0.6)
    end
    ShaderPaletteController.getPaletteColors = function()
      return {
        { 0.0, 0.0, 0.0 },
        { 0.2, 0.2, 0.2 },
        { 0.6, 0.6, 0.6 },
        { 0.9, 0.9, 0.9 },
      }
    end
  end)

  afterEach(function()
    love.filesystem.newFileData = originalNewFileData
    love.image.newImageData = originalNewImageData
    ShaderPaletteController.getPaletteColors = originalGetPaletteColors
  end)

  it("imports PNG into paint, pack, and linked Pattern table (256 slots)", function()
    local wm, sketch, pt = linkSketchAndPt()
    local ok, pack = SketchCanvasPackController.importPngToSketchCanvas(
      sketch,
      makeFile(),
      wm,
      { confirmed = true }
    )
    expect(ok).toBe(true)
    expect(type(pack)).toBe("table")
    expect(pack.uniqueCount).toBe(1)
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(true)

    local canvas = sketch:getActiveCanvas()
    expect(canvas).toBeTruthy()
    expect(canvas.width).toBe(256)
    expect(canvas.height).toBe(240)

    local layer = pt.layers[1]
    local itemCount = 0
    for _, item in pairs(layer.items or {}) do
      if item ~= nil then
        itemCount = itemCount + 1
      end
    end
    expect(itemCount).toBe(256)
    expect(pt.linkedSketchCanvasWindowId).toBe(sketch._id)

    local reflect = SketchCanvasPackController.getReflectDisplayCanvas(sketch)
    expect(reflect).toBeTruthy()
    expect(reflect:getPixel(0, 0)).toBe(canvas:getPixel(0, 0))
  end)

  it("rejects missing linked Pattern table", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "Sketch" })
    local ok, err = SketchCanvasPackController.importPngToSketchCanvas(sketch, makeFile(), wm, {})
    expect(ok).toBe(false)
    expect(err).toBe("no_linked_pattern_table")
  end)

  it("rejects non-256x240 images", function()
    love.image.newImageData = function()
      return makeSolidImageData(128, 128, 0.5)
    end
    local wm, sketch = linkSketchAndPt()
    local ok, err = SketchCanvasPackController.importPngToSketchCanvas(sketch, makeFile(), wm, {})
    expect(ok).toBe(false)
    expect(err).toBe("bad_dimensions")
  end)

  it("rejects more than 256 unique patterns", function()
    love.image.newImageData = function()
      return makeTooManyUniquesImageData()
    end
    local wm, sketch = linkSketchAndPt()
    local ok, err = SketchCanvasPackController.importPngToSketchCanvas(sketch, makeFile(), wm, {})
    expect(ok).toBe(false)
    expect(err).toBe("too_many_unique")
  end)

  it("returns needs_confirm when pack already exists and confirmed is false", function()
    local wm, sketch = linkSketchAndPt()
    local canvas = sketch:getActiveCanvas()
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 2)
      end
    end
    local packOk = SketchCanvasPackController.generate(sketch)
    expect(packOk).toBe(true)
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(true)

    local ok, err, pending = SketchCanvasPackController.importPngToSketchCanvas(
      sketch,
      makeFile(),
      wm,
      {}
    )
    expect(ok).toBe(false)
    expect(err).toBe(SketchCanvasPackController.PNG_IMPORT_NEEDS_CONFIRM)
    expect(pending).toBeTruthy()
    expect(SketchCanvasPackController.hasPackData(sketch)).toBe(true)

    local ok2, pack2 = SketchCanvasPackController.importPngToSketchCanvas(
      sketch,
      makeFile(),
      wm,
      { confirmed = true, pending = pending }
    )
    expect(ok2).toBe(true)
    expect(pack2.uniqueCount).toBe(1)
  end)

  it("cancel path leaves paint/pack unchanged when confirm is not granted", function()
    local wm, sketch = linkSketchAndPt()
    local canvas = sketch:getActiveCanvas()
    canvas:edit(0, 0, 3)
    SketchCanvasPackController.generate(sketch)
    local before = canvas:getPixel(0, 0)

    local ok = SketchCanvasPackController.importPngToSketchCanvas(sketch, makeFile(), wm, {})
    expect(ok).toBe(false)
    expect(canvas:getPixel(0, 0)).toBe(before)
  end)
end)
