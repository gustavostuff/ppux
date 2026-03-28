local NametableUnscrambleController = require("controllers.ppu.nametable_unscramble_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

describe("nametable_unscramble_controller.lua - undo support", function()
  local originalNewFileData
  local originalNewImageData

  local function makeOpaqueImageData()
    return {
      getWidth = function() return 8 end,
      getHeight = function() return 8 end,
      getPixel = function()
        return 0.8, 0.8, 0.8, 1.0
      end,
    }
  end

  beforeEach(function()
    originalNewFileData = love.filesystem.newFileData
    originalNewImageData = love.image.newImageData

    love.filesystem.newFileData = function()
      return {}
    end
    love.image.newImageData = function()
      return makeOpaqueImageData()
    end
  end)

  afterEach(function()
    love.filesystem.newFileData = originalNewFileData
    love.image.newImageData = originalNewImageData
  end)

  it("records nametable byte changes as an undoable event", function()
    local file = {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "unscramble.png" end,
    }

    local tileRefBefore = {
      index = 0,
      pixels = {},
    }
    local tileRefAfter = {
      index = 1,
      pixels = {},
    }
    for i = 1, 64 do
      tileRefBefore.pixels[i] = 1
      tileRefAfter.pixels[i] = 0
    end

    local layer = {
      kind = "tile",
      bank = 1,
      page = 1,
    }

    local win = {
      kind = "ppu_frame",
      activeLayer = 1,
      cols = 1,
      rows = 1,
      layers = { layer },
      nametableBytes = { 0 },
      _originalNametableBytes = { 0 },
      nametableAttrBytes = {},
      _tileSwaps = {},
      setNametableByteAt = function(self, col, row, byteVal)
        self.nametableBytes[1] = byteVal
      end,
      updateCompressedBytesInROM = function() return true end,
      syncNametableLayerMetadata = function() end,
      getActiveLayerIndex = function(self) return self.activeLayer end,
    }

    local tilesPool = {
      [1] = {
        [0] = tileRefBefore,
        [1] = tileRefAfter,
      },
    }

    local undoRedo = UndoRedoController.new(10)
    local app = {
      undoRedo = undoRedo,
      appEditState = {
        tilesPool = tilesPool,
      },
    }

    local ok, msg = NametableUnscrambleController.unscrambleFromPNG(win, file, tilesPool, 0, app)

    expect(ok).toBe(true)
    expect(msg).toBeTruthy()
    expect(win.nametableBytes[1]).toBe(1)
    expect(#undoRedo.stack).toBe(1)
    expect(undoRedo.stack[1].type).toBe("tile_drag")
    expect(undoRedo.stack[1].changes[1].isNametableByte).toBe(true)

    expect(undoRedo:undo(app)).toBe(true)
    expect(win.nametableBytes[1]).toBe(0)

    expect(undoRedo:redo(app)).toBe(true)
    expect(win.nametableBytes[1]).toBe(1)
  end)

  it("batches nametable undo/redo through applyTileSwapsFrom", function()
    local undoRedo = UndoRedoController.new(10)
    local applyCalls = 0
    local setCalls = 0

    local win = {
      _closed = false,
      cols = 4,
      getActiveLayerIndex = function() return 1 end,
      applyTileSwapsFrom = function(self, swaps)
        applyCalls = applyCalls + 1
        for _, swap in ipairs(swaps or {}) do
          local idx = swap.row * self.cols + swap.col + 1
          self.nametableBytes[idx] = swap.val
        end
      end,
      setNametableByteAt = function(self, col, row, byteVal)
        setCalls = setCalls + 1
        local idx = row * self.cols + col + 1
        self.nametableBytes[idx] = byteVal
      end,
      nametableBytes = { 1, 2, 3, 4 },
    }

    local ok = undoRedo:addDragEvent({
      type = "tile_drag",
      mode = "move",
      changes = {
        { win = win, layerIndex = 1, col = 0, row = 0, before = 10, after = 1, isNametableByte = true },
        { win = win, layerIndex = 1, col = 1, row = 0, before = 20, after = 2, isNametableByte = true },
        { win = win, layerIndex = 1, col = 2, row = 0, before = 30, after = 3, isNametableByte = true },
      },
    })

    expect(ok).toBe(true)
    expect(undoRedo:undo({})).toBe(true)
    expect(applyCalls).toBe(1)
    expect(setCalls).toBe(0)
    expect(win.nametableBytes[1]).toBe(10)
    expect(win.nametableBytes[2]).toBe(20)
    expect(win.nametableBytes[3]).toBe(30)

    expect(undoRedo:redo({})).toBe(true)
    expect(applyCalls).toBe(2)
    expect(setCalls).toBe(0)
    expect(win.nametableBytes[1]).toBe(1)
    expect(win.nametableBytes[2]).toBe(2)
    expect(win.nametableBytes[3]).toBe(3)
  end)
end)
