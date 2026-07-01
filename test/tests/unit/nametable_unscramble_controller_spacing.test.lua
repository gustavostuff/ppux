local NametableUnscrambleController = require("controllers.ppu.nametable_unscramble_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")

describe("nametable_unscramble_controller.lua - spacing layout shifts", function()
  local originalNewFileData
  local originalNewImageData
  local originalGetPaletteColors

  local BYTE = {
    S1 = 0x20,
    S2 = 0x21,
    O = 0x14,
    V = 0x15,
    E2 = 0x16,
    FILL = 0xF4,
  }

  local RANK_COLORS = {
    [1] = { 0.20, 0.20, 0.20 },
    [2] = { 0.50, 0.50, 0.50 },
    [3] = { 0.90, 0.90, 0.90 },
  }

  local function makeTile(pixelValue)
    local pixels = {}
    for i = 1, 64 do
      pixels[i] = pixelValue
    end
    return {
      index = pixelValue,
      pixels = pixels,
    }
  end

  local function buildTilesPool()
    local bank = {}
    bank[BYTE.S1] = makeTile(0)
    bank[BYTE.S2] = makeTile(0)
    bank[BYTE.O] = makeTile(1)
    bank[BYTE.V] = makeTile(2)
    bank[BYTE.E2] = makeTile(3)
    bank[BYTE.FILL] = makeTile(0)
    return { [1] = bank }
  end

  local function makeImageData(tileRanksByCol)
    return {
      getWidth = function() return #tileRanksByCol * 8 end,
      getHeight = function() return 8 end,
      getPixel = function(_, x, _)
        local col = math.floor(x / 8)
        local rank = tileRanksByCol[col + 1]
        if not rank or rank == 0 then
          return 0, 0, 0, 0
        end
        local rgb = RANK_COLORS[rank]
        return rgb[1], rgb[2], rgb[3], 1.0
      end,
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
      return {
        { 0.0, 0.0, 0.0 },
        RANK_COLORS[1],
        RANK_COLORS[2],
        RANK_COLORS[3],
      }
    end
  end)

  afterEach(function()
    love.filesystem.newFileData = originalNewFileData
    love.image.newImageData = originalNewImageData
    ShaderPaletteController.getPaletteColors = originalGetPaletteColors
  end)

  it("applies OVER with one space when original nametable had two spaces", function()
    local pngLayout = { 0, 1, 2, 3, 0 }
    love.image.newImageData = function()
      return makeImageData(pngLayout)
    end

    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "game_over_one_space.png" end,
    }

    local layer = {
      kind = "tile",
      bank = 1,
      page = 1,
      codec = "zelda2",
    }

    local original = {
      BYTE.S1, BYTE.S2,
      BYTE.O, BYTE.V, BYTE.E2,
    }

    local originalCopy = {}
    for i, v in ipairs(original) do
      originalCopy[i] = v
    end

    local win = {
      kind = "ppu_frame",
      activeLayer = 1,
      cols = #original,
      rows = 1,
      layers = { layer },
      nametableBytes = original,
      _originalNametableBytes = originalCopy,
      _tileSwaps = {},
      updateCompressedBytesInROM = function() return true end,
      syncNametableLayerMetadata = function() end,
    }

    local tilesPool = buildTilesPool()
    local ok = NametableUnscrambleController.unscrambleFromPNG(win, file, tilesPool, 0, nil)
    expect(ok).toBe(true)

    expect(win.nametableBytes[1]).toBe(BYTE.FILL)
    expect(win.nametableBytes[2]).toBe(BYTE.O)
    expect(win.nametableBytes[3]).toBe(BYTE.V)
    expect(win.nametableBytes[4]).toBe(BYTE.E2)
    expect(win.nametableBytes[5]).toBe(BYTE.FILL)
  end)

  it("updates shifted OVER letters even when the PNG pattern is a near match", function()
    local pngLayout = { 0, 1, 2, 3, 0 }
    love.image.newImageData = function()
      return {
        getWidth = function() return #pngLayout * 8 end,
        getHeight = function() return 8 end,
        getPixel = function(_, x, y)
          local col = math.floor(x / 8)
          local rank = pngLayout[col + 1]
          if not rank or rank == 0 then
            return 0, 0, 0, 0
          end
          if col == 3 and x == 24 and y == 0 then
            rank = 2
          end
          local rgb = RANK_COLORS[rank]
          return rgb[1], rgb[2], rgb[3], 1.0
        end,
      }
    end

    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "game_over_near_match.png" end,
    }

    local layer = {
      kind = "tile",
      bank = 1,
      page = 1,
      codec = "zelda2",
    }

    local original = {
      BYTE.S1, BYTE.S2,
      BYTE.O, BYTE.V, BYTE.E2,
    }

    local originalCopy = {}
    for i, v in ipairs(original) do
      originalCopy[i] = v
    end

    local win = {
      kind = "ppu_frame",
      activeLayer = 1,
      cols = #original,
      rows = 1,
      layers = { layer },
      nametableBytes = original,
      _originalNametableBytes = originalCopy,
      _tileSwaps = {},
      updateCompressedBytesInROM = function() return true end,
      syncNametableLayerMetadata = function() end,
    }

    local ok = NametableUnscrambleController.unscrambleFromPNG(
      win,
      file,
      buildTilesPool(),
      0,
      nil
    )
    expect(ok).toBe(true)
    expect(win.nametableBytes[4]).toBe(BYTE.E2)
  end)
end)
