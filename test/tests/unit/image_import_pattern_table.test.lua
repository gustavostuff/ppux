local ImageImportController = require("controllers.rom.image_import_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local chr = require("chr")

describe("image_import_controller.lua - Pattern table PNG import", function()
  local originalNewFileData
  local originalNewImageData
  local originalGetPaletteColors

  local function makeImageData16x8()
    -- Two tiles side by side: left mid-gray, right bright (both opaque, both non-zero after remap).
    return {
      getWidth = function() return 16 end,
      getHeight = function() return 8 end,
      getPixel = function(_, x, _)
        if x < 8 then
          return 0.50, 0.50, 0.50, 1.0
        end
        return 0.90, 0.90, 0.90, 1.0
      end,
    }
  end

  local function emptyBankBytes()
    local bytes = {}
    for i = 1, 512 * 16 do
      bytes[i] = 0
    end
    return bytes
  end

  local function tileHasNonZero(bankBytes, tileIndex)
    local base = tileIndex * 16
    for i = 1, 16 do
      if (bankBytes[base + i] or 0) ~= 0 then
        return true
      end
    end
    return false
  end

  local function makeTileRef()
    local tile = {
      pixels = {},
      loadFromCHR = function(self, bankBytes, tileIndex)
        local decoded = chr.decodeTile(bankBytes, tileIndex)
        if decoded then
          self.pixels = decoded
        end
      end,
    }
    for i = 1, 64 do
      tile.pixels[i] = 0
    end
    return tile
  end

  beforeEach(function()
    originalNewFileData = love.filesystem.newFileData
    originalNewImageData = love.image.newImageData
    originalGetPaletteColors = ShaderPaletteController.getPaletteColors

    love.filesystem.newFileData = function()
      return {}
    end
    love.image.newImageData = function()
      return makeImageData16x8()
    end
    ShaderPaletteController.getPaletteColors = function()
      return {
        { 0.0, 0.0, 0.0 },
        { 0.1, 0.1, 0.1 },
        { 0.5, 0.5, 0.5 },
        { 0.9, 0.9, 0.9 },
      }
    end
  end)

  afterEach(function()
    love.filesystem.newFileData = originalNewFileData
    love.image.newImageData = originalNewImageData
    ShaderPaletteController.getPaletteColors = originalGetPaletteColors
  end)

  it("writes PNG frames into mapped CHR bank tiles (not sequential bank order)", function()
    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "pt.png" end,
    }

    -- Logical slots 0 and 1 map to bank1 tile 10 and bank2 tile 20.
    local win = {
      kind = "pattern_table",
      cols = 16,
      rows = 16,
      layers = {
        {
          kind = "tile",
          mode = "8x8",
          patternTable = {
            ranges = {
              { bank = 1, from = 10, to = 10 },
              { bank = 2, from = 20, to = 20 },
            },
          },
          items = {},
        },
      },
    }

    local bank1 = emptyBankBytes()
    local bank2 = emptyBankBytes()
    -- Seed mapped tiles so we can detect overwrites even if a color remaps to 0.
    chr.setTilePixel(bank1, 10, 0, 0, 2)
    chr.setTilePixel(bank2, 20, 0, 0, 2)
    local before10 = chr.decodeTile(bank1, 10)[1]
    local before20 = chr.decodeTile(bank2, 20)[1]

    local tile10 = makeTileRef()
    local tile20 = makeTileRef()
    local appEditState = {
      romRaw = "rom",
      chrBanksBytes = {
        [1] = bank1,
        [2] = bank2,
      },
      tilesPool = {
        [1] = { [10] = tile10 },
        [2] = { [20] = tile20 },
      },
    }

    local ok, msg = ImageImportController.importImageToPatternTableWindow(
      file,
      win,
      0,
      0,
      appEditState,
      nil,
      nil,
      { wm = { getWindows = function() return { win } end } }
    )

    expect(ok).toBe(true)
    expect(msg).toBeTruthy()

    local after10 = chr.decodeTile(bank1, 10)[1]
    local after20 = chr.decodeTile(bank2, 20)[1]
    expect(after10 ~= before10 or after20 ~= before20).toBe(true)
    expect(after10 ~= after20).toBe(true)
    expect(tileHasNonZero(bank1, 0)).toBe(false)
  end)

  it("rejects sketch-owned Pattern table windows", function()
    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "pt.png" end,
    }

    local win = {
      kind = "pattern_table",
      cols = 16,
      rows = 16,
      linkedSketchCanvasWindowId = "sketch_a",
      layers = {
        {
          kind = "tile",
          patternTable = {
            ranges = {
              { bank = 1, from = 0, to = 255 },
            },
          },
        },
      },
    }

    local appEditState = {
      romRaw = "rom",
      chrBanksBytes = { [1] = emptyBankBytes() },
      tilesPool = { [1] = {} },
    }

    local ok, msg = ImageImportController.importImageToPatternTableWindow(
      file,
      win,
      0,
      0,
      appEditState,
      nil,
      nil,
      nil
    )
    expect(ok).toBe(false)
    expect(type(msg)).toBe("string")
    expect(msg:find("sketch", 1, true) ~= nil).toBe(true)
  end)

  it("skips unmapped holes while writing later mapped slots", function()
    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "pt.png" end,
    }

    -- Only logical index 1 is mapped (visual col 1 on row 0 in 8x8).
    -- PNG has two tiles; first lands on unmapped slot 0, second on mapped slot 1.
    local win = {
      kind = "pattern_table",
      cols = 16,
      rows = 16,
      layers = {
        {
          kind = "tile",
          mode = "8x8",
          patternTable = {
            ranges = {
              { bank = 1, tiles = {
                { bank = 1, tileIndex = 0 }, -- logical 0
                { bank = 1, tileIndex = 50 }, -- logical 1
              } },
            },
          },
          items = {},
        },
      },
    }
    -- Make logical 0 a hole by using a partial contiguous map that starts at index 1 only.
    -- Explicit tiles list always fills from 0; instead use from/to for a single tile at logical 0
    -- and start PNG at col=1 so first frame maps to logical 1... simpler:
    win.layers[1].patternTable = {
      ranges = {
        { bank = 1, from = 50, to = 50 }, -- only logical 0 mapped to tile 50
      },
    }

    local bank1 = emptyBankBytes()
    chr.setTilePixel(bank1, 50, 0, 0, 2)
    local before50 = chr.decodeTile(bank1, 50)[1]
    local tile50 = makeTileRef()
    local appEditState = {
      romRaw = "rom",
      chrBanksBytes = { [1] = bank1 },
      tilesPool = { [1] = { [50] = tile50 } },
    }

    -- Start at col 0: first PNG tile writes logical 0 -> tile 50.
    -- Second PNG tile is logical 1 (unmapped) and should be skipped.
    local ok = ImageImportController.importImageToPatternTableWindow(
      file,
      win,
      0,
      0,
      appEditState,
      nil,
      nil,
      { wm = { getWindows = function() return { win } end } }
    )
    expect(ok).toBe(true)
    local after50 = chr.decodeTile(bank1, 50)[1]
    expect(after50 ~= before50).toBe(true)
    expect(tileHasNonZero(bank1, 0)).toBe(false)
  end)
end)
