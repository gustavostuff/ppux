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
end)
