local NametableUnscrambleController = require("controllers.ppu.nametable_unscramble_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")

describe("nametable_unscramble_controller.lua - pattern table catalog", function()
  local originalNewFileData
  local originalNewImageData
  local originalGetPaletteColors

  local function makeTile(pixelValue, index)
    local pixels = {}
    for i = 1, 64 do
      pixels[i] = pixelValue
    end
    return {
      index = index or pixelValue,
      pixels = pixels,
    }
  end

  beforeEach(function()
    originalNewFileData = love.filesystem.newFileData
    originalNewImageData = love.image.newImageData
    originalGetPaletteColors = ShaderPaletteController.getPaletteColors

    love.filesystem.newFileData = function()
      return {}
    end
    ShaderPaletteController.getPaletteColors = function()
      return nil
    end
  end)

  afterEach(function()
    love.filesystem.newFileData = originalNewFileData
    love.image.newImageData = originalNewImageData
    ShaderPaletteController.getPaletteColors = originalGetPaletteColors
  end)

  it("fails when the PPU frame has no pattern table mapping", function()
    love.image.newImageData = function()
      return {
        getWidth = function() return 8 end,
        getHeight = function() return 8 end,
        getPixel = function()
          return 0.9, 0.9, 0.9, 1.0
        end,
      }
    end

    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "no_pt.png" end,
    }

    local win = {
      kind = "ppu_frame",
      activeLayer = 1,
      cols = 1,
      rows = 1,
      layers = { { kind = "tile" } },
      nametableBytes = { 0 },
      _originalNametableBytes = { 0 },
      _tileSwaps = {},
      updateCompressedBytesInROM = function() return true end,
      syncNametableLayerMetadata = function() end,
    }

    local tilesPool = {
      [1] = {
        [0] = makeTile(3, 0),
      },
    }

    local ok, msg = NametableUnscrambleController.unscrambleFromPNG(win, file, tilesPool, 0, nil)
    expect(ok).toBe(false)
    expect(type(msg)).toBe("string")
    expect(msg:find("Pattern table", 1, true) ~= nil or msg:find("patternTable", 1, true) ~= nil).toBe(true)
  end)

  it("matches PNG tiles using linked Pattern table items instead of raw CHR byte order", function()
    -- Single opaque PNG color maps to pixel index 0 without a palette remap.
    love.image.newImageData = function()
      return {
        getWidth = function() return 8 end,
        getHeight = function() return 8 end,
        getPixel = function()
          return 0.9, 0.9, 0.9, 1.0
        end,
      }
    end

    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "linked_pt.png" end,
    }

    -- CHR byte 0 is a different pattern. Matching tile lives at CHR index 50.
    -- Linked pattern table places that tile at logical nametable byte 7.
    local matchTile = makeTile(0, 50)
    local wrongTile = makeTile(2, 0)

    local patternTable = {
      ranges = {
        { bank = 1, from = 50, to = 50 },
      },
    }

    local ptWin = {
      _id = "pt_unscramble",
      kind = "pattern_table",
      title = "Pattern table",
      cols = 16,
      rows = 16,
      layers = {
        {
          kind = "tile",
          mode = "8x8",
          patternTable = patternTable,
          -- Only slot 7 is filled; that is logical index 7 in 8x8 ordering.
          items = {},
        },
      },
    }
    for i = 1, 256 do
      ptWin.layers[1].items[i] = nil
    end
    ptWin.layers[1].items[8] = matchTile -- pos 7 (1-based index 8)

    local layer = {
      kind = "tile",
      linkedPatternTableWindowId = "pt_unscramble",
      patternTable = {},
    }

    local win = {
      kind = "ppu_frame",
      activeLayer = 1,
      cols = 1,
      rows = 1,
      layers = { layer },
      nametableBytes = { 0 },
      _originalNametableBytes = { 0 },
      _tileSwaps = {},
      updateCompressedBytesInROM = function() return true end,
      syncNametableLayerMetadata = function() end,
    }

    local tilesPool = {
      [1] = {
        [0] = wrongTile,
        [50] = matchTile,
      },
    }

    local app = {
      wm = {
        getWindows = function()
          return { win, ptWin }
        end,
      },
      appEditState = {
        tilesPool = tilesPool,
      },
    }

    local ok, msg = NametableUnscrambleController.unscrambleFromPNG(win, file, tilesPool, 0, app)
    expect(ok).toBe(true)
    expect(msg).toBeTruthy()
    -- Logical byte 7 comes from the linked pattern table item slot, not CHR index 50 / 0.
    expect(win.nametableBytes[1]).toBe(7)
    -- Linked resolve should have attached the shared patternTable object.
    expect(layer.patternTable).toBe(patternTable)
  end)
end)
