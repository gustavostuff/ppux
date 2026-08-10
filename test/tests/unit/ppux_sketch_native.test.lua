local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local PpuxSketchNative = require("utils.ppux_sketch_native")
local ImageImportController = require("controllers.rom.image_import_controller")

describe("ppux_sketch native helper", function()
  local function makePalette()
    return {
      { 0.0, 0.0, 0.0 },
      { 0.25, 0.25, 0.25 },
      { 0.6, 0.6, 0.6 },
      { 1.0, 1.0, 1.0 },
    }
  end

  local function fillCheckerImageData()
    local img = love.image.newImageData(256, 240)
    for y = 0, 239 do
      for x = 0, 255 do
        local tile = math.floor(x / 8) + math.floor(y / 8)
        local shade = (tile % 4) / 3
        img:setPixel(x, y, shade, shade, shade, 1)
      end
    end
    return img
  end

  it("matches Lua index+pack for a checker pattern when lib is available", function()
    if not PpuxSketchNative.isAvailable() then
      -- Soft skip: CI / machines without the built .so still pass the suite.
      expect(true).toBe(true)
      return
    end

    local palette = makePalette()
    local img = fillCheckerImageData()

    local flatNative, packNative, w, h =
      PpuxSketchNative.imageDataToIndexedAndPack(img, palette)
    expect(flatNative).toBeTruthy()
    expect(type(packNative)).toBe("table")
    expect(w).toBe(256)
    expect(h).toBe(240)

    -- Lua path: decode via ImageImport using the same ImageData bytes through a stub file,
    -- then packFromCanvas.
    local originalLoad = ImageImportController.loadImageDataFromFile
    ImageImportController.loadImageDataFromFile = function()
      return img
    end
    local flatLua, width, height =
      ImageImportController.decodePngFileToIndexedPixels({ open = function() end }, palette)
    ImageImportController.loadImageDataFromFile = originalLoad

    expect(flatLua).toBeTruthy()
    expect(width).toBe(256)
    expect(height).toBe(240)

    for i = 1, 256 * 240 do
      expect(flatNative[i]).toBe(flatLua[i])
    end

    local flatCanvas = {
      width = 256,
      height = 240,
      extractTilePixels = function(_, ox, oy, cell)
        cell = cell or 8
        local pixels = {}
        local i = 1
        for py = 0, cell - 1 do
          for px = 0, cell - 1 do
            pixels[i] = flatLua[(oy + py) * 256 + (ox + px) + 1]
            i = i + 1
          end
        end
        return pixels
      end,
    }
    local packLua, err = SketchCanvasPackController.packFromCanvas(flatCanvas, 0)
    expect(err).toBeNil()
    expect(packLua).toBeTruthy()
    expect(packNative.uniqueCount).toBe(packLua.uniqueCount)
    expect(#packNative.nametableBytes).toBe(960)
    expect(#packLua.nametableBytes).toBe(960)
    for i = 1, 960 do
      expect(packNative.nametableBytes[i]).toBe(packLua.nametableBytes[i])
    end
    for i = 1, packLua.uniqueCount do
      expect(packNative.tilesPool[i].x).toBe(packLua.tilesPool[i].x)
      expect(packNative.tilesPool[i].y).toBe(packLua.tilesPool[i].y)
      expect(packNative.tilesPool[i].solidShade).toBe(packLua.tilesPool[i].solidShade)
    end
  end)

  it("matches Lua when two colors share luminance (string-key tie-break)", function()
    if not PpuxSketchNative.isAvailable() then
      expect(true).toBe(true)
      return
    end

    -- Equal luminance; Lua string keys sort "139_39_88" before "75_85_19"
    -- while numeric (r,g,b) would reverse them.
    local cA = { 139 / 255, 39 / 255, 88 / 255 }
    local cB = { 75 / 255, 85 / 255, 19 / 255 }
    local img = love.image.newImageData(256, 240)
    for y = 0, 239 do
      for x = 0, 255 do
        local c = (x < 128) and cA or cB
        img:setPixel(x, y, c[1], c[2], c[3], 1)
      end
    end
    -- Two more unique colors so remap uses a full 4-slot palette path.
    for y = 0, 7 do
      for x = 0, 7 do
        img:setPixel(x, y, 0, 0, 0, 1)
        img:setPixel(200 + x, y, 1, 1, 1, 1)
      end
    end

    local palette = makePalette()
    local flatNative = select(1, PpuxSketchNative.imageDataToIndexedAndPack(img, palette))
    local originalLoad = ImageImportController.loadImageDataFromFile
    ImageImportController.loadImageDataFromFile = function()
      return img
    end
    local flatLua = ImageImportController.decodePngFileToIndexedPixels({ open = function() end }, palette)
    ImageImportController.loadImageDataFromFile = originalLoad

    expect(flatNative).toBeTruthy()
    expect(flatLua).toBeTruthy()
    for i = 1, 256 * 240 do
      expect(flatNative[i]).toBe(flatLua[i])
    end
  end)

  it("keeps grey brightness ranks as indices (no palette-slot remap)", function()
    if not PpuxSketchNative.isAvailable() then
      expect(true).toBe(true)
      return
    end

    -- Palette with white in slot 1 and darker in slot 2 would scramble mid greys
    -- if we remapped ranks through palette luminance order.
    local palette = {
      { 0.0, 0.0, 0.0 },
      { 1.0, 1.0, 1.0 },
      { 0.4, 0.25, 0.2 },
      { 0.7, 0.55, 0.35 },
    }
    local greys = { 0.0, 0.33, 0.66, 1.0 }
    local img = love.image.newImageData(256, 240)
    for y = 0, 239 do
      for x = 0, 255 do
        local g = greys[(y < 60 and 1) or (y < 120 and 2) or (y < 180 and 3) or 4]
        img:setPixel(x, y, g, g, g, 1)
      end
    end

    local flatNative = select(1, PpuxSketchNative.imageDataToIndexedAndPack(img, palette))
    local originalLoad = ImageImportController.loadImageDataFromFile
    ImageImportController.loadImageDataFromFile = function()
      return img
    end
    local flatLua = ImageImportController.decodePngFileToIndexedPixels({ open = function() end }, palette)
    ImageImportController.loadImageDataFromFile = originalLoad

    expect(flatNative).toBeTruthy()
    expect(flatLua).toBeTruthy()
    expect(flatNative[30 * 256 + 10 + 1]).toBe(0)
    expect(flatNative[90 * 256 + 10 + 1]).toBe(1)
    expect(flatNative[150 * 256 + 10 + 1]).toBe(2)
    expect(flatNative[210 * 256 + 10 + 1]).toBe(3)
    for i = 1, 256 * 240 do
      expect(flatNative[i]).toBe(flatLua[i])
    end
  end)

  -- Lua-only canvas stub (no .pixels) so packFromCanvas cannot take the native shortcut.
  local function luaPackCanvasFromFlat(flat)
    return {
      width = 256,
      height = 240,
      extractTilePixels = function(_, ox, oy, cell)
        cell = cell or 8
        local pixels = {}
        local i = 1
        for py = 0, cell - 1 do
          for px = 0, cell - 1 do
            pixels[i] = flat[(oy + py) * 256 + (ox + px) + 1] or 0
            i = i + 1
          end
        end
        return pixels
      end,
    }
  end

  local function assertPackParity(packNative, packLua)
    expect(packNative).toBeTruthy()
    expect(packLua).toBeTruthy()
    expect(packNative.uniqueCount).toBe(packLua.uniqueCount)
    expect(#packNative.nametableBytes).toBe(960)
    expect(#packLua.nametableBytes).toBe(960)
    for i = 1, 960 do
      expect(packNative.nametableBytes[i]).toBe(packLua.nametableBytes[i])
    end
    for i = 1, packLua.uniqueCount do
      expect(packNative.tilesPool[i].x).toBe(packLua.tilesPool[i].x)
      expect(packNative.tilesPool[i].y).toBe(packLua.tilesPool[i].y)
      expect(packNative.tilesPool[i].solidShade).toBe(packLua.tilesPool[i].solidShade)
      expect(packNative.tilesPool[i].exactSolid == true).toBe(packLua.tilesPool[i].exactSolid == true)
    end
  end

  local function makeToleranceStressFlat()
    local flat = {}
    for i = 1, 256 * 240 do
      flat[i] = 0
    end
    local function fillTile(col, row, shade)
      local ox, oy = col * 8, row * 8
      for py = 0, 7 do
        for px = 0, 7 do
          flat[(oy + py) * 256 + (ox + px) + 1] = shade
        end
      end
    end
    -- Exact solids for shades 1-3.
    fillTile(0, 0, 1)
    fillTile(1, 0, 2)
    fillTile(2, 0, 3)
    -- Near-solid shade 2 with 3 outlier pixels (collapses at tol>=3).
    fillTile(3, 0, 2)
    do
      local ox, oy = 3 * 8, 0
      flat[oy * 256 + ox + 1] = 0
      flat[oy * 256 + ox + 2] = 1
      flat[oy * 256 + ox + 3] = 3
    end
    -- Near-empty shade 0 with one freehand pixel (must NOT collapse to blank).
    fillTile(4, 0, 0)
    flat[0 * 256 + 4 * 8 + 1] = 2
    -- Freehand checker that must stay unique (not absorb into solids via greedy).
    do
      local ox, oy = 5 * 8, 0
      for py = 0, 7 do
        for px = 0, 7 do
          flat[(oy + py) * 256 + (ox + px) + 1] = ((px + py) % 2 == 0) and 1 or 2
        end
      end
    end
    -- Duplicate freehand at another cell (tol>0 greedy should match first unique).
    do
      local ox, oy = 6 * 8, 0
      for py = 0, 7 do
        for px = 0, 7 do
          local v = ((px + py) % 2 == 0) and 1 or 2
          -- Flip two pixels so exact match fails but tol>=2 matches.
          if px == 0 and py == 0 then
            v = 3
          elseif px == 1 and py == 0 then
            v = 0
          end
          flat[(oy + py) * 256 + (ox + px) + 1] = v
        end
      end
    end
    return flat
  end

  it("packFlat matches Lua packFromCanvas at tolerance 0", function()
    if not PpuxSketchNative.isAvailable() then
      expect(true).toBe(true)
      return
    end

    local flat = makeToleranceStressFlat()
    local packNative, nErr = PpuxSketchNative.packFlat(flat, 256, 240, 0)
    expect(nErr).toBeNil()
    local packLua, lErr = SketchCanvasPackController.packFromCanvas(luaPackCanvasFromFlat(flat), 0)
    expect(lErr).toBeNil()
    assertPackParity(packNative, packLua)
  end)

  it("packFlat matches Lua packFromCanvas at tolerance 3", function()
    if not PpuxSketchNative.isAvailable() then
      expect(true).toBe(true)
      return
    end

    local flat = makeToleranceStressFlat()
    local packNative, nErr = PpuxSketchNative.packFlat(flat, 256, 240, 3)
    expect(nErr).toBeNil()
    local packLua, lErr = SketchCanvasPackController.packFromCanvas(luaPackCanvasFromFlat(flat), 3)
    expect(lErr).toBeNil()
    assertPackParity(packNative, packLua)
    -- Near-solid tile at (3,0) should collapse into shade-2 solid pool.
    expect(packLua.uniqueCount).toBeLessThan(10)
  end)

  it("packFromCanvas prefers native when canvas.pixels is present", function()
    if not PpuxSketchNative.isAvailable() then
      expect(true).toBe(true)
      return
    end

    local flat = makeToleranceStressFlat()
    local canvas = {
      width = 256,
      height = 240,
      pixels = flat,
      extractTilePixels = function(_, ox, oy, cell)
        cell = cell or 8
        local pixels = {}
        local i = 1
        for py = 0, cell - 1 do
          for px = 0, cell - 1 do
            pixels[i] = flat[(oy + py) * 256 + (ox + px) + 1] or 0
            i = i + 1
          end
        end
        return pixels
      end,
    }
    local pack, err = SketchCanvasPackController.packFromCanvas(canvas, 2)
    expect(err).toBeNil()
    expect(pack).toBeTruthy()
    local packNative = PpuxSketchNative.packFlat(flat, 256, 240, 2)
    assertPackParity(pack, packNative)
  end)

  it("copyCanvasPixels and floodFillCanvas work on PixelCanvas", function()
    if not PpuxSketchNative.isAvailable() then
      expect(true).toBe(true)
      return
    end
    local PixelCanvas = require("ui.windows_system.pixel_canvas")
    local src = PixelCanvas.new(256, 240, 0)
    local dst = PixelCanvas.new(256, 240, 3)
    for y = 0, 7 do
      for x = 0, 7 do
        src.pixels[y * 256 + x + 1] = 2
      end
    end
    expect(PpuxSketchNative.copyCanvasPixels(dst, src)).toBe(true)
    expect(dst.pixels[1]).toBe(2)
    expect(dst.pixels[9]).toBe(0)

    local indices, n = PpuxSketchNative.floodFillCanvas(dst, 0, 0, 1, nil)
    expect(n).toBe(64)
    expect(#indices).toBe(64)
    expect(dst.pixels[1]).toBe(1)
  end)

  it("buildShadeMask counts matching pixels", function()
    if not PpuxSketchNative.isAvailable() then
      expect(true).toBe(true)
      return
    end
    local PixelCanvas = require("ui.windows_system.pixel_canvas")
    local canvas = PixelCanvas.new(256, 240, 0)
    canvas.pixels[1] = 2
    canvas.pixels[2] = 2
    local mask, count = PpuxSketchNative.buildShadeMask(canvas, 2)
    expect(mask).toBeTruthy()
    expect(count).toBe(2)
    expect(mask.dense[1]).toBe(1)
    expect(mask.bits[1]).toBe(true)
  end)

  it("composeNametableInto matches loadTilePixels path for solids", function()
    if not PpuxSketchNative.isAvailable() then
      expect(true).toBe(true)
      return
    end
    local PixelCanvas = require("ui.windows_system.pixel_canvas")
    local paint = PixelCanvas.new(256, 240, 0)
    for py = 0, 7 do
      for px = 0, 7 do
        paint.pixels[py * 256 + px + 1] = 1
        paint.pixels[py * 256 + (8 + px) + 1] = 2
      end
    end
    local pack = assert(select(1, SketchCanvasPackController.packFromCanvas(paint, 0)))
    local sketch = {
      tilesPool = pack.tilesPool,
      nametableBytes = {},
    }
    for i = 1, 960 do
      sketch.nametableBytes[i] = pack.nametableBytes[i]
    end
    sketch.nametableBytes[1], sketch.nametableBytes[2] =
      sketch.nametableBytes[2], sketch.nametableBytes[1]

    local display = PixelCanvas.new(256, 240, 0)
    expect(PpuxSketchNative.composeNametableInto(display, paint, sketch)).toBe(true)
    expect(display.pixels[1]).toBe(2)
    expect(display.pixels[9]).toBe(1)
  end)

  it("averageTilesRgb returns 960 entries", function()
    if not PpuxSketchNative.isAvailable() then
      expect(true).toBe(true)
      return
    end
    local PixelCanvas = require("ui.windows_system.pixel_canvas")
    local paint = PixelCanvas.new(256, 240, 3)
    local rows = {
      { { 0, 0, 0 }, { 0.25, 0.25, 0.25 }, { 0.5, 0.5, 0.5 }, { 1, 1, 1 } },
      { { 0, 0, 0 }, { 0.25, 0.25, 0.25 }, { 0.5, 0.5, 0.5 }, { 1, 1, 1 } },
      { { 0, 0, 0 }, { 0.25, 0.25, 0.25 }, { 0.5, 0.5, 0.5 }, { 1, 1, 1 } },
      { { 0, 0, 0 }, { 0.25, 0.25, 0.25 }, { 0.5, 0.5, 0.5 }, { 1, 1, 1 } },
    }
    local averages = PpuxSketchNative.averageTilesRgb(paint, nil, rows, nil)
    expect(averages).toBeTruthy()
    expect(#averages).toBe(960)
    expect(averages[1][1]).toBe(1)
  end)
end)
