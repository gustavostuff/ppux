local E2EHarness = require("test.e2e_harness")
local PngPaletteMappingController = require("controllers.png.palette_mapping_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")

local function firstReadablePath(candidates)
  for _, path in ipairs(candidates or {}) do
    local f = io.open(path, "rb")
    if f then
      f:close()
      return path
    end
  end
  return nil
end

local function readAllBytes(path)
  local f = assert(io.open(path, "rb"), "failed to open file: " .. tostring(path))
  local bytes = assert(f:read("*a"), "failed to read file: " .. tostring(path))
  f:close()
  return bytes
end

local function loadImageData(path)
  local bytes = readAllBytes(path)
  local fileData = assert(love.filesystem.newFileData(bytes, path), "failed to build FileData")
  return assert(love.image.newImageData(fileData), "failed to decode image")
end

local function buildBrightnessIndexMap(imageData, paletteColors)
  local rankMap = PngPaletteMappingController.buildBrightnessRankMap(imageData, {
    rankStart = 0,
    maxRank = 3,
  })

  local remap = nil
  if paletteColors then
    local hasTransparency = PngPaletteMappingController.imageHasTransparency(imageData)
    remap = hasTransparency
      and PngPaletteMappingController.buildPaletteBrightnessRemap(paletteColors, {
        pixelValues = { 1, 2, 3 },
        rankStart = 0,
      })
      or PngPaletteMappingController.buildPaletteBrightnessRemap(paletteColors, {
        pixelValues = { 0, 1, 2, 3 },
        rankStart = 0,
      })
  end

  return rankMap, remap
end

local function pixelToIndex(r, g, b, a, brightnessMap, brightnessRemap)
  if a == 0 then
    return 0
  end
  local key = PngPaletteMappingController.rgbKeyFromFloats(r, g, b)
  local rank = brightnessMap[key] or 0
  if brightnessRemap then
    return brightnessRemap[rank] or 0
  end
  return rank
end

local function extractExpectedTilePixels(imageData, tileCol, tileRow, brightnessMap, brightnessRemap)
  local tilePixels = {}
  local tileX = tileCol * 8
  local tileY = tileRow * 8
  for y = 0, 7 do
    for x = 0, 7 do
      local r, g, b, a = imageData:getPixel(tileX + x, tileY + y)
      tilePixels[y * 8 + x + 1] = pixelToIndex(r, g, b, a, brightnessMap, brightnessRemap)
    end
  end
  return tilePixels
end

describe("ppu_frame PNG drop flow - CHR import then nametable unscramble", function()
  it("matches the full 32x30 tile grid against the dropped nametable PNG", function()
    local harness = E2EHarness.new()
    local ok, err = pcall(function()
      local app = harness:boot()
      harness:loadROM()

      local chrPngPath = firstReadablePath({
        "test/test_chr.png",
        "test_chr.png",
        "../test/test_chr.png",
      })
      local nametablePngPath = firstReadablePath({
        "test/test_nametable.png",
        "test_nametable.png",
        "../test/test_nametable.png",
      })
      assert(chrPngPath, "could not find test CHR PNG")
      assert(nametablePngPath, "could not find test nametable PNG")

      local chrWin = assert(
        harness:findWindow({ kind = "chr" }),
        "expected CHR window after ROM load"
      )

      local ppuWin = assert(
        app.wm:createPPUFrameWindow({
          title = "PPU Frame E2E",
          romRaw = app.appEditState and app.appEditState.romRaw,
          bankIndex = 1,
          pageIndex = 1,
        }),
        "failed to create PPU frame window"
      )

      app.wm:setFocus(chrWin)
      do
        local x, y = harness:windowCellCenter(chrWin, 0, 0)
        harness:moveMouse(x, y)
      end
      harness:dropFile(chrPngPath)

      app.wm:setFocus(ppuWin)
      do
        local x, y = harness:windowCellCenter(ppuWin, 0, 0)
        harness:moveMouse(x, y)
      end
      harness:dropFile(nametablePngPath)

      local statusText = tostring(app.statusText or "")
      assert(not statusText:find("Unscramble failed", 1, true), "unscramble reported failure: " .. statusText)

      local layer = assert(ppuWin.layers and ppuWin.layers[1], "expected tile layer in PPU frame window")
      assert(layer.kind == "tile", "expected first layer to be a tile layer")
      assert(ppuWin.cols == 32, "expected PPU frame to be 32 columns")
      assert(ppuWin.rows == 30, "expected PPU frame to be 30 rows")

      local imageData = loadImageData(nametablePngPath)
      assert(imageData:getWidth() == 256, "expected nametable PNG width 256")
      assert(imageData:getHeight() == 240, "expected nametable PNG height 240")
      local paletteSourceLayer = app.winBank and app.winBank.layers and app.winBank.layers[1] or layer
      local paletteColors = ShaderPaletteController.getPaletteColors(
        paletteSourceLayer,
        1,
        app.appEditState and app.appEditState.romRaw
      )
      local brightnessMap, brightnessRemap = buildBrightnessIndexMap(imageData, paletteColors)

      for row = 0, 29 do
        for col = 0, 31 do
          local idx = row * 32 + col + 1
          local tileRef = layer.items and layer.items[idx] or nil
          assert(tileRef and tileRef.pixels, string.format("missing tile at col=%d row=%d", col, row))

          local expectedPixels = extractExpectedTilePixels(imageData, col, row, brightnessMap, brightnessRemap)
          for i = 1, 64 do
            local actual = tileRef.pixels[i]
            local expected = expectedPixels[i]
            assert(
              actual == expected,
              string.format(
                "tile mismatch at col=%d row=%d pixel=%d expected=%d actual=%s",
                col, row, i, expected, tostring(actual)
              )
            )
          end
        end
      end
    end)

    harness:destroy()
    if not ok then
      error(err)
    end
  end)
end)
