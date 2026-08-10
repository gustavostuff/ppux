local GalleryThumb = require("controllers.game_art.sketch_canvas_gallery_thumb_controller")
local GallerySlideThumbStrip = require("ui.gallery_slide_thumb_strip")
local GalleryRomConfirmModal = require("ui.modals.gallery_rom_confirm_modal")
local PixelCanvas = require("ui.windows_system.pixel_canvas")

describe("sketch_canvas_gallery_thumb_controller", function()
  it("averages an 8x8 tile to one RGB", function()
    local canvas = PixelCanvas.new(256, 240, 0)
    -- Fill tile (0,0) with half shade 0 and half shade 3.
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, (x < 4) and 0 or 3)
      end
    end
    local palette = {
      { 0, 0, 0 },
      { 0.25, 0.25, 0.25 },
      { 0.5, 0.5, 0.5 },
      { 1, 1, 1 },
    }
    local r, g, b = GalleryThumb.averageTileColor(canvas, 0, 0, palette)
    expect(r).toBe(0.5)
    expect(g).toBe(0.5)
    expect(b).toBe(0.5)
  end)

  it("uses default brown when sketch has no linked palette (ignores global shader codes)", function()
    local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
    local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")
    local Palettes = require("palettes")
    local prevCodes = {
      ShaderPaletteController.codes[1],
      ShaderPaletteController.codes[2],
      ShaderPaletteController.codes[3],
      ShaderPaletteController.codes[4],
    }
    -- Pollute global codes like after drawing another sketch's linked palette.
    ShaderPaletteController.codes = { "0F", "30", "16", "12" }

    local sketch = {
      layers = { { kind = "canvas", paletteData = nil } },
    }
    local colors = GalleryThumb.resolvePaletteColors(sketch, nil)
    local brown = SketchPalette.DEFAULT_BROWN_CODES
    local p = Palettes[ShaderPaletteController.paletteName] or Palettes.smooth_fbx
    for i = 1, 4 do
      expect(colors[i][1]).toBe(p[brown[i]][1])
      expect(colors[i][2]).toBe(p[brown[i]][2])
      expect(colors[i][3]).toBe(p[brown[i]][3])
    end

    ShaderPaletteController.codes = prevCodes
  end)

  it("uses linked sketch palette row 0 when present", function()
    local WM = require("controllers.window.window_controller")
    local PaletteLinkController = require("controllers.palette.palette_link_controller")
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "S" })
    local pal = wm:createRomPaletteWindow({ title = "Sketch pal", paletteRole = "sketch" })
    pal.codes2D[0][0] = "0F"
    pal.codes2D[0][1] = "30"
    pal.codes2D[0][2] = "16"
    pal.codes2D[0][3] = "12"
    local prev = rawget(_G, "ctx")
    rawset(_G, "ctx", { app = { wm = wm }, wm = function() return wm end })
    expect(PaletteLinkController.linkLayerToPalette(sketch, 1, pal)).toBe(true)

    local colors = GalleryThumb.resolvePaletteColors(sketch, { wm = wm })
    local Palettes = require("palettes")
    local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
    local p = Palettes[ShaderPaletteController.paletteName] or Palettes.smooth_fbx
    expect(colors[1][1]).toBe(p["0F"][1])
    expect(colors[2][1]).toBe(p["30"][1])
    expect(colors[3][1]).toBe(p["16"][1])
    expect(colors[4][1]).toBe(p["12"][1])

    rawset(_G, "ctx", prev)
  end)

  it("uses linked sketch palette row from tile attrs (not only row 0)", function()
    local WM = require("controllers.window.window_controller")
    local PaletteLinkController = require("controllers.palette.palette_link_controller")
    local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")
    local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
    local Palettes = require("palettes")
    local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "S" })
    local pal = wm:createRomPaletteWindow({ title = "Sketch pal", paletteRole = "sketch" })
    -- Row 0: dark; row 1: bright white-ish.
    pal.codes2D[0][0] = "0F"
    pal.codes2D[0][1] = "0F"
    pal.codes2D[0][2] = "0F"
    pal.codes2D[0][3] = "0F"
    pal.codes2D[1][0] = "30"
    pal.codes2D[1][1] = "30"
    pal.codes2D[1][2] = "30"
    pal.codes2D[1][3] = "30"

    local prev = rawget(_G, "ctx")
    rawset(_G, "ctx", {
      app = { wm = wm },
      wm = function() return wm end,
      getMode = function() return "tile" end,
    })
    expect(PaletteLinkController.linkLayerToPalette(sketch, 1, pal)).toBe(true)

    local canvas = sketch:getActiveCanvas()
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 3)
      end
    end
    local pack = assert(select(1, SketchCanvasPackController.packFromCanvas(canvas, 0)))
    assert(SketchCanvasPackController.applyPackToWindow(sketch, pack))
    -- Link a PT so isSketchReflectNametable can succeed in tile mode.
    local pt = wm:createPatternTableWindow({ title = "PT" })
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))

    SketchPalette.ensureAttrBytes(sketch)
    local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
    local layer = sketch.layers[1]
    expect(NametableTilesController.setPaletteNumberForTile(sketch, layer, 0, 0, 2)).toBe(true)
    expect(SketchPalette.getTilePaletteNumber(sketch, 0, 0)).toBe(2)
    GalleryThumb.refreshTileAt(sketch, 0, 0, { wm = wm })

    local p = Palettes[ShaderPaletteController.paletteName] or Palettes.smooth_fbx
    local bright = p["30"][1]
    local dark = p["0F"][1]
    expect(sketch.tileAverageRgb[1][1]).toBe(bright)
    expect(bright).toBeGreaterThan(dark)

    rawset(_G, "ctx", prev)
  end)

  it("builds a 32x30 ImageData from a sketch canvas", function()
    local canvas = PixelCanvas.new(256, 240, 0)
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 3)
      end
    end
    local sketch = {
      title = "Boss",
      layers = { { canvas = canvas, kind = "canvas" } },
      getActiveCanvas = function()
        return canvas
      end,
    }
    expect(GalleryThumb.refreshForSketch(sketch, nil)).toBe(true)
    expect(GalleryThumb.hasTileAverages(sketch)).toBe(true)
    expect(#sketch.tileAverageRgb).toBe(960)

    local img, err = GalleryThumb.buildThumbImageData(sketch, nil)
    expect(err).toBeNil()
    expect(img).toBeTruthy()
    expect(img:getWidth()).toBe(32)
    expect(img:getHeight()).toBe(30)
    local r = select(1, img:getPixel(0, 0))
    local rBlank = select(1, img:getPixel(1, 0))
    expect(r).toBeGreaterThan(rBlank)
    expect(r).toBeGreaterThan(0.5)
    expect(rBlank).toBeLessThan(0.25)
  end)

  it("applyPackToWindow refreshes tileAverageRgb on the sketch", function()
    local WM = require("controllers.window.window_controller")
    local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local canvas = sketch.layers[1].canvas
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 2)
      end
    end
    local pack, err = SketchCanvasPackController.packFromCanvas(canvas, 0)
    expect(err).toBeNil()
    expect(SketchCanvasPackController.applyPackToWindow(sketch, pack)).toBe(true)
    expect(GalleryThumb.hasTileAverages(sketch)).toBe(true)
    local rgb = sketch.tileAverageRgb[1]
    expect(rgb).toBeTruthy()
    expect(rgb[1]).toBeGreaterThan(0.1)
  end)

  it("swapNametableBytesAt swaps cached tile averages", function()
    local WM = require("controllers.window.window_controller")
    local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local canvas = sketch.layers[1].canvas
    -- Distinct solids in first two tiles.
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 1)
        canvas:edit(8 + x, y, 3)
      end
    end
    local pack = assert(select(1, SketchCanvasPackController.packFromCanvas(canvas, 0)))
    assert(SketchCanvasPackController.applyPackToWindow(sketch, pack))
    expect(GalleryThumb.hasTileAverages(sketch)).toBe(true)

    local before0 = {
      sketch.tileAverageRgb[1][1],
      sketch.tileAverageRgb[1][2],
      sketch.tileAverageRgb[1][3],
    }
    local before1 = {
      sketch.tileAverageRgb[2][1],
      sketch.tileAverageRgb[2][2],
      sketch.tileAverageRgb[2][3],
    }
    expect(before0[1] ~= before1[1] or before0[2] ~= before1[2] or before0[3] ~= before1[3]).toBe(true)

    expect(sketch:swapNametableBytesAt(0, 0, 1, 0)).toBe(true)
    expect(sketch.tileAverageRgb[1][1]).toBe(before1[1])
    expect(sketch.tileAverageRgb[1][2]).toBe(before1[2])
    expect(sketch.tileAverageRgb[1][3]).toBe(before1[3])
    expect(sketch.tileAverageRgb[2][1]).toBe(before0[1])
    expect(sketch.tileAverageRgb[2][2]).toBe(before0[2])
    expect(sketch.tileAverageRgb[2][3]).toBe(before0[3])
  end)

  it("setNametableByteAt refreshes that tile's average from the packed pattern", function()
    local WM = require("controllers.window.window_controller")
    local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local canvas = sketch.layers[1].canvas
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 1)
        canvas:edit(8 + x, y, 3)
      end
    end
    local pack = assert(select(1, SketchCanvasPackController.packFromCanvas(canvas, 0)))
    assert(SketchCanvasPackController.applyPackToWindow(sketch, pack))

    local bright = {
      sketch.tileAverageRgb[2][1],
      sketch.tileAverageRgb[2][2],
      sketch.tileAverageRgb[2][3],
    }
    -- Place tile 1's pattern (pool index from col1) onto col0.
    local poolIndex = sketch.nametableBytes[2]
    expect(sketch:setNametableByteAt(0, 0, poolIndex)).toBe(true)
    expect(sketch.tileAverageRgb[1][1]).toBe(bright[1])
    expect(sketch.tileAverageRgb[1][2]).toBe(bright[2])
    expect(sketch.tileAverageRgb[1][3]).toBe(bright[3])
  end)
end)

describe("gallery_slide_thumb_strip", function()
  it("reorders entries on drag and returns sketches in new order", function()
    local a = { title = "A" }
    local b = { title = "B" }
    local c = { title = "C" }
    local strip = GallerySlideThumbStrip.new({ w = 200, h = 40 })
    strip:setPosition(10, 20)
    strip:setEntries({
      { sketch = a, title = "A", image = nil },
      { sketch = b, title = "B", image = nil },
      { sketch = c, title = "C", image = nil },
    })

    -- Press first thumb, drag past second into third slot.
    local x0 = 10 + 2 + 16 -- PAD + mid of first thumb
    local y0 = 20 + 5
    strip:mousepressed(x0, y0, 1)
    strip:mousemoved(x0 + 40, y0) -- activate drag + hover second
    strip:mousemoved(10 + 2 + 2 * (32 + 4) + 16, y0) -- third
    strip:mousereleased(10 + 2 + 2 * (32 + 4) + 16, y0, 1)

    local ordered = strip:getOrderedSketches()
    expect(#ordered).toBe(3)
    expect(ordered[1]).toBe(b)
    expect(ordered[2]).toBe(c)
    expect(ordered[3]).toBe(a)
  end)

  it("scrolls horizontally with the mouse wheel", function()
    local strip = GallerySlideThumbStrip.new({ w = 40, h = 40 })
    strip:setPosition(0, 0)
    local entries = {}
    for i = 1, 8 do
      entries[i] = { sketch = { id = i }, title = tostring(i) }
    end
    strip:setEntries(entries)
    expect(strip:wheelmoved(0, -1)).toBe(true)
    expect(strip.scrollX).toBeGreaterThan(0)
  end)
end)

describe("gallery_rom_confirm_modal thumb strip", function()
  it("confirm callback receives strip order after reorder", function()
    local modal = GalleryRomConfirmModal.new()
    local a = {
      _id = "sketch_a",
      title = "A",
      getActiveCanvas = function()
        return PixelCanvas.new(256, 240, 1)
      end,
      layers = { { kind = "canvas" } },
    }
    a.layers[1].canvas = a:getActiveCanvas()
    local b = {
      _id = "sketch_b",
      title = "B",
      getActiveCanvas = function()
        return PixelCanvas.new(256, 240, 2)
      end,
      layers = { { kind = "canvas" } },
    }
    b.layers[1].canvas = b:getActiveCanvas()

    local got = nil
    local savedOrder = nil
    local AppSettingsController = require("controllers.app.settings_controller")
    local originalSave = AppSettingsController.save
    AppSettingsController.save = function(opts)
      if opts and opts.galleryRom then
        savedOrder = opts.galleryRom.slideOrder
      end
      return true
    end

    modal:show({
      sketches = { a, b },
      onConfirm = function(selected)
        got = selected
      end,
    })
    expect(#modal.thumbStrip.entries).toBe(2)

    -- Swap A and B via strip API.
    modal.thumbStrip:_moveEntry(1, 2)
    modal:_confirm()
    AppSettingsController.save = originalSave

    expect(got).toBeTruthy()
    expect(#got).toBe(2)
    expect(got[1]).toBe(b)
    expect(got[2]).toBe(a)
    expect(savedOrder).toBeTruthy()
    expect(savedOrder[1]).toBe("sketch_b")
    expect(savedOrder[2]).toBe("sketch_a")
  end)
end)
