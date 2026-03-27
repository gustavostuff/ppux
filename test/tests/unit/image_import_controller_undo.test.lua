local ImageImportController = require("controllers.rom.image_import_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local chr = require("chr")

describe("image_import_controller.lua - undo support for PNG import", function()
  local originalNewFileData
  local originalNewImageData
  local originalGetPaletteColors

  local function makeUndoRedoSpy()
    local spy = { events = {}, activeEvent = nil }

    function spy:startPaintEvent()
      self.activeEvent = { pixels = {} }
    end

    function spy:recordPixelChange(bank, tileIndex, px, py, beforeValue, afterValue)
      if not self.activeEvent then return end
      local key = string.format("%d:%d:%d:%d", bank, tileIndex, px, py)
      self.activeEvent.pixels[key] = {
        bank = bank, tileIndex = tileIndex, px = px, py = py,
        before = beforeValue, after = afterValue,
      }
    end

    function spy:finishPaintEvent()
      if not self.activeEvent then return false end
      self.events[#self.events + 1] = self.activeEvent
      self.activeEvent = nil
      return true
    end

    return spy
  end

  local function makeImageData8x8TwoColors()
    return {
      getWidth = function() return 8 end,
      getHeight = function() return 8 end,
      getPixel = function(_, x, _)
        if x < 4 then
          return 0.1, 0.1, 0.1, 1.0
        end
        return 0.9, 0.9, 0.9, 1.0
      end,
    }
  end

  local function makeImageData8x8TransparentThreeColors()
    return {
      getWidth = function() return 8 end,
      getHeight = function() return 8 end,
      getPixel = function(_, x, _)
        if x < 2 then
          return 0.0, 0.0, 0.0, 0.0 -- transparent
        elseif x < 4 then
          return 0.10, 0.10, 0.10, 1.0 -- dark
        elseif x < 6 then
          return 0.50, 0.50, 0.50, 1.0 -- mid
        end
        return 0.90, 0.90, 0.90, 1.0 -- bright
      end,
    }
  end

  local function seedNonFlatTile(bankBytes, tileIndex, color)
    chr.setTilePixel(bankBytes, tileIndex, 0, 0, color or 1)
  end

  beforeEach(function()
    originalNewFileData = love.filesystem.newFileData
    originalNewImageData = love.image.newImageData
    originalGetPaletteColors = ShaderPaletteController.getPaletteColors

    love.filesystem.newFileData = function()
      return {}
    end
    love.image.newImageData = function()
      return makeImageData8x8TwoColors()
    end
  end)

  afterEach(function()
    love.filesystem.newFileData = originalNewFileData
    love.image.newImageData = originalNewImageData
    ShaderPaletteController.getPaletteColors = originalGetPaletteColors
  end)

  it("records an undoable paint event for CHR PNG import", function()
    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "fake.png" end,
    }

    local win = { kind = "chr", cols = 16 }

    local bankBytes = {}
    for i = 1, 16 * 4 do bankBytes[i] = 0 end

    local tileRef = {
      pixels = {},
      loadFromCHR = function() end,
    }
    for i = 1, 64 do tileRef.pixels[i] = 0 end

    local appEditState = {
      currentBank = 1,
      chrBanksBytes = { bankBytes },
      tilesPool = { [1] = { [0] = tileRef } },
    }
    local edits = { banks = {} }
    local undoRedo = makeUndoRedoSpy()

    local ok, msg = ImageImportController.importImageToCHRWindow(
      file,
      win,
      0,
      0,
      appEditState,
      edits,
      "normal",
      undoRedo
    )

    expect(ok).toBe(true)
    expect(msg).toBeTruthy()
    expect(#undoRedo.events).toBe(1)

    local pixelCount = 0
    local hasChangedPixel = false
    for _, p in pairs(undoRedo.events[1].pixels or {}) do
      pixelCount = pixelCount + 1
      if (p.before or 0) ~= (p.after or 0) then
        hasChangedPixel = true
      end
    end

    expect(pixelCount).toBeGreaterThan(0)
    expect(hasChangedPixel).toBe(true)
  end)

  it("maps CHR PNG colors through global palette brightness order", function()
    ShaderPaletteController.getPaletteColors = function()
      return {
        { 0.80, 0.80, 0.80 }, -- pixel value 0 (bright)
        { 0.95, 0.95, 0.95 }, -- pixel value 1 (brightest)
        { 0.10, 0.10, 0.10 }, -- pixel value 2 (darkest)
        { 0.50, 0.50, 0.50 }, -- pixel value 3 (mid)
      }
    end

    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "fake.png" end,
    }
    local win = { kind = "chr", cols = 16 }

    local bankBytes = {}
    for i = 1, 16 * 4 do bankBytes[i] = 0 end

    local appEditState = {
      currentBank = 1,
      chrBanksBytes = { bankBytes },
      tilesPool = { [1] = { [0] = { loadFromCHR = function() end } } },
    }

    local ok = ImageImportController.importImageToCHRWindow(
      file, win, 0, 0, appEditState, { banks = {} }, "normal", nil
    )

    expect(ok).toBe(true)
    local decoded = chr.decodeTile(bankBytes, 0)
    expect(decoded[1]).toBe(2) -- darkest PNG color -> darkest palette slot (pixel value 2)
    expect(decoded[8]).toBe(3) -- brighter PNG color -> next brightness slot (pixel value 3)
  end)

  it("preserves transparency and maps opaque CHR PNG colors through visible palette slots", function()
    love.image.newImageData = function()
      return makeImageData8x8TransparentThreeColors()
    end

    ShaderPaletteController.getPaletteColors = function()
      return {
        { 0.99, 0.99, 0.99 }, -- slot 0 (transparent in shader): should not be used for opaque colors
        { 0.95, 0.95, 0.95 }, -- slot 1 brightest visible
        { 0.10, 0.10, 0.10 }, -- slot 2 darkest visible
        { 0.50, 0.50, 0.50 }, -- slot 3 mid visible
      }
    end

    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "fake.png" end,
    }
    local win = { kind = "chr", cols = 16 }
    local bankBytes = {}
    for i = 1, 16 * 4 do bankBytes[i] = 0 end

    local appEditState = {
      currentBank = 1,
      chrBanksBytes = { bankBytes },
      tilesPool = { [1] = { [0] = { loadFromCHR = function() end } } },
    }

    local ok = ImageImportController.importImageToCHRWindow(
      file, win, 0, 0, appEditState, { banks = {} }, "normal", nil
    )

    expect(ok).toBe(true)
    local decoded = chr.decodeTile(bankBytes, 0)
    expect(decoded[1]).toBe(0) -- transparent stays transparent
    expect(decoded[3]).toBe(2) -- darkest opaque -> darkest visible slot
    expect(decoded[5]).toBe(3) -- mid opaque -> mid visible slot
    expect(decoded[7]).toBe(1) -- brightest opaque -> brightest visible slot
  end)

  it("syncs duplicate tiles during CHR PNG import when syncDuplicateTiles is enabled", function()
    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "fake.png" end,
    }
    local win = { kind = "chr", cols = 16 }

    local bankBytes = {}
    for i = 1, 32 do bankBytes[i] = 0 end -- 2 tiles

    local appEditState = {
      currentBank = 1,
      chrBanksBytes = { bankBytes },
      tilesPool = {
        [1] = {
          [0] = { loadFromCHR = function() end },
          [1] = { loadFromCHR = function() end },
        }
      },
    }

    seedNonFlatTile(bankBytes, 0, 1)
    seedNonFlatTile(bankBytes, 1, 1)

    local frozenGroup = {
      { bank = 1, tileIndex = 0 },
      { bank = 1, tileIndex = 1 },
    }
    appEditState.syncGroups = {
      [1] = {
        [0] = frozenGroup,
        [1] = frozenGroup,
      }
    }

    local app = { syncDuplicateTiles = true }

    local ok = ImageImportController.importImageToCHRWindow(
      file, win, 0, 0, appEditState, { banks = {} }, "normal", nil, app
    )

    expect(ok).toBe(true)
    local decoded0 = chr.decodeTile(bankBytes, 0)
    local decoded1 = chr.decodeTile(bankBytes, 1)
    expect(decoded1[1]).toBe(decoded0[1])
    expect(decoded1[4]).toBe(decoded0[4])
    expect(decoded1[8]).toBe(decoded0[8])
  end)
end)
