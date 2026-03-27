local PngPaletteMappingController = require("controllers.png.palette_mapping_controller")

describe("png_palette_mapping_controller.lua", function()
  local function makeImage(pixels, width, height)
    width = width or #pixels[1]
    height = height or #pixels
    return {
      getWidth = function() return width end,
      getHeight = function() return height end,
      getPixel = function(_, x, y)
        local p = pixels[y + 1][x + 1]
        return p[1], p[2], p[3], p[4]
      end,
    }
  end

  it("builds brightness ranks darkest to lightest and ignores transparent pixels", function()
    local img = makeImage({
      {
        { 0.0, 0.0, 0.0, 1.0 }, -- black
        { 1.0, 1.0, 1.0, 1.0 }, -- white
      },
      {
        { 0.5, 0.5, 0.5, 1.0 }, -- gray
        { 0.2, 0.2, 0.2, 0.0 }, -- transparent (ignored)
      },
    })

    local map, count = PngPaletteMappingController.buildBrightnessRankMap(img)
    expect(count).toBe(3)
    expect(map["0_0_0"]).toBe(0)
    expect(map["128_128_128"]).toBe(1)
    expect(map["255_255_255"]).toBe(2)
    expect(map["51_51_51"]).toBeNil()
  end)

  it("uses key tie-break ordering for equal luminance colors", function()
    -- Pure red and pure green intentionally forced to equal luminance in this test
    -- by stubbing calculateLuminance, so sort falls back to key string order.
    local originalCalc = PngPaletteMappingController.calculateLuminance
    PngPaletteMappingController.calculateLuminance = function() return 1 end

    local ok, err = pcall(function()
      local img = makeImage({
        {
          { 1.0, 0.0, 0.0, 1.0 }, -- key "255_0_0"
          { 0.0, 1.0, 0.0, 1.0 }, -- key "0_255_0"
        },
      })

      local map, count = PngPaletteMappingController.buildBrightnessRankMap(img)
      expect(count).toBe(2)
      -- Lexicographic key order: "0_255_0" < "255_0_0"
      expect(map["0_255_0"]).toBe(0)
      expect(map["255_0_0"]).toBe(1)
    end)

    PngPaletteMappingController.calculateLuminance = originalCalc
    if not ok then error(err) end
  end)

  it("clamps ranks at maxRank and respects rankStart", function()
    local img = makeImage({
      {
        { 0.0, 0.0, 0.0, 1.0 },
        { 0.25, 0.25, 0.25, 1.0 },
        { 0.5, 0.5, 0.5, 1.0 },
        { 0.75, 0.75, 0.75, 1.0 },
        { 1.0, 1.0, 1.0, 1.0 },
      },
    })

    local map, count = PngPaletteMappingController.buildBrightnessRankMap(img, {
      rankStart = 1,
      maxRank = 3,
    })

    expect(count).toBe(5)
    expect(map["0_0_0"]).toBe(1)
    expect(map["64_64_64"]).toBe(2)
    expect(map["128_128_128"]).toBe(3)
    expect(map["191_191_191"]).toBe(3)
    expect(map["255_255_255"]).toBe(3)
  end)

  it("builds palette brightness remap for full 4 slots", function()
    local paletteColors = {
      { 1.0, 1.0, 1.0 }, -- slot 0 bright
      { 0.0, 0.0, 0.0 }, -- slot 1 dark
      { 0.5, 0.5, 0.5 }, -- slot 2 mid
      { 0.8, 0.8, 0.8 }, -- slot 3 high
    }

    local remap = PngPaletteMappingController.buildPaletteBrightnessRemap(paletteColors)
    expect(remap[0]).toBe(1) -- darkest palette slot
    expect(remap[1]).toBe(2)
    expect(remap[2]).toBe(3)
    expect(remap[3]).toBe(0) -- brightest palette slot
  end)

  it("builds palette brightness remap for visible sprite slots with rankStart", function()
    local paletteColors = {
      { 0.1, 0.1, 0.1 }, -- slot 0 unused in test
      { 0.8, 0.8, 0.8 }, -- slot 1 bright
      { 0.2, 0.2, 0.2 }, -- slot 2 dark
      { 0.5, 0.5, 0.5 }, -- slot 3 mid
    }

    local remap = PngPaletteMappingController.buildPaletteBrightnessRemap(paletteColors, {
      pixelValues = { 1, 2, 3 },
      rankStart = 1,
    })

    expect(remap[1]).toBe(2)
    expect(remap[2]).toBe(3)
    expect(remap[3]).toBe(1)
    expect(remap[0]).toBeNil()
  end)

  it("returns nil when palette remap cannot resolve a requested slot", function()
    local remap = PngPaletteMappingController.buildPaletteBrightnessRemap({
      { 0, 0, 0 },
      { 1, 1, 1 },
    }, {
      pixelValues = { 0, 1, 2 },
    })
    expect(remap).toBeNil()
  end)

  it("detects image transparency", function()
    local transparentImg = makeImage({
      {
        { 0, 0, 0, 1 },
        { 1, 1, 1, 0 },
      },
    })
    local opaqueImg = makeImage({
      {
        { 0, 0, 0, 1 },
        { 1, 1, 1, 1 },
      },
    })

    expect(PngPaletteMappingController.imageHasTransparency(transparentImg)).toBeTruthy()
    expect(PngPaletteMappingController.imageHasTransparency(opaqueImg)).toBeFalsy()
  end)

  it("rounds RGB float values to nearest 8-bit key", function()
    expect(PngPaletteMappingController.rgbKeyFromFloats(0.0, 0.5, 1.0)).toBe("0_128_255")
    expect(PngPaletteMappingController.rgbKeyFromFloats(0.499, 0, 0)).toBe("127_0_0")
    expect(PngPaletteMappingController.rgbKeyFromFloats(0.501, 0, 0)).toBe("128_0_0")
  end)
end)
