local BrushController = require("controllers.input_support.brush_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")
local BankCanvasSupport = require("controllers.chr.bank_canvas_support")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local chr = require("chr")

local function makeTile(initialColor)
  local t = { _bankIndex = 1, index = 0, pixels = {} }
  for i = 1, 64 do
    t.pixels[i] = initialColor or 0
  end
  function t:getPixel(x, y)
    return self.pixels[y * 8 + x + 1]
  end
  function t:edit(x, y, color)
    self.pixels[y * 8 + x + 1] = color
  end
  function t:loadFromCHR(bankBytes, tileIndex)
    local decoded = chr.decodeTile(bankBytes, tileIndex)
    for i = 1, 64 do
      self.pixels[i] = decoded[i] or 0
    end
  end
  return t
end

local function makeApp(initialColor)
  local bankBytes = {}
  for i = 1, 16 do bankBytes[i] = 0 end

  local tile = makeTile(initialColor or 0)
  local tilesPool = { [1] = { [0] = tile } }

  local app = {
    appEditState = {
      chrBanksBytes = { bankBytes },
      tilesPool     = tilesPool,
    },
    undoRedo = UndoRedoController.new(10),
    currentColor = 2,
    syncDuplicateTiles = false,
    setStatus = function(self, text)
      self.statusText = text
    end,
  }

  return app, tile, bankBytes
end

local function makeWin(tile)
  return {
    cols = 1,
    rows = 1,
    cellW = 8,
    cellH = 8,
    layers = { { kind = "tile" } },
    getActiveLayerIndex = function() return 1 end,
    get = function(_, col, row)
      if col == 0 and row == 0 then return tile end
    end,
    getStack = function(_, col, row)
      if col == 0 and row == 0 then return { tile } end
    end,
  }
end

describe("brush_controller.lua - flood fill undo/redo integration", function()
  it("records flood fill as a paint event and undoes/redoes bytes", function()
    local app, tile, bankBytes = makeApp(0)
    local win = makeWin(tile)

    local ok = BrushController.floodFillTile(app, win, 0, 0, 0, 0)
    expect(ok).toBe(true)

    expect(#app.undoRedo.stack).toBe(1)
    local ev = app.undoRedo.stack[1]
    expect(ev.type).toBe("paint")
    local count = 0
    for _ in pairs(ev.pixels) do count = count + 1 end
    expect(count).toBe(64) -- all pixels in the 8x8 tile
    expect(ev.pixels["1:0:0:0"].before).toBe(0)
    expect(ev.pixels["1:0:0:0"].after).toBe(app.currentColor)

    local pixels = chr.decodeTile(bankBytes, 0)
    for i = 1, #pixels do
      expect(pixels[i]).toBe(app.currentColor)
    end

    expect(app.undoRedo:undo(app)).toBeTruthy()
    local undoPixels = chr.decodeTile(bankBytes, 0)
    for i = 1, #undoPixels do
      expect(undoPixels[i]).toBe(0)
    end

    expect(app.undoRedo:redo(app)).toBeTruthy()
    local redoPixels = chr.decodeTile(bankBytes, 0)
    for i = 1, #redoPixels do
      expect(redoPixels[i]).toBe(app.currentColor)
    end
  end)

  it("cancels undo event when flood fill makes no changes", function()
    local app, tile = makeApp(3)
    app.currentColor = 3 -- Same as tile pixels, so no-op fill
    local win = makeWin(tile)

    local ok = BrushController.floodFillTile(app, win, 0, 0, 0, 0)
    expect(ok).toBe(false)
    expect(#app.undoRedo.stack).toBe(0)
    expect(app.undoRedo.activeEvent).toBeNil()
  end)
end)

describe("brush_controller.lua - color picking", function()
  it("uses the center pixel for ctrl-click regardless of brush size", function()
    local app, tile = makeApp(0)
    local win = makeWin(tile)
    app.brushSize = 4

    tile:edit(0, 0, 1)
    tile:edit(4, 5, 3)

    local ok = BrushController.paintPixel(app, win, 0, 0, 4, 5, true)

    expect(ok).toBe(true)
    expect(app.currentColor).toBe(3)
  end)
end)

describe("brush_controller.lua - generic line and rectangle painting", function()
  it("draws undoable lines on normal tile windows", function()
    local app, tile = makeApp(0)
    local win = makeWin(tile)

    app.undoRedo:startPaintEvent()
    local ok = BrushController.drawLine(app, win, 0, 0, 3, 3, false)
    expect(ok).toBe(true)
    expect(app.undoRedo:finishPaintEvent()).toBe(true)

    expect(tile:getPixel(0, 0)).toBe(2)
    expect(tile:getPixel(1, 1)).toBe(2)
    expect(tile:getPixel(2, 2)).toBe(2)
    expect(tile:getPixel(3, 3)).toBe(2)
    expect(app.undoRedo:undo(app)).toBeTruthy()
    expect(tile:getPixel(2, 2)).toBe(0)
  end)

  it("draws undoable filled rectangles on normal tile windows", function()
    local app, tile = makeApp(0)
    local win = makeWin(tile)

    app.undoRedo:startPaintEvent()
    local ok = BrushController.fillRect(app, win, 1, 1, 2, 3, false)
    expect(ok).toBe(true)
    expect(app.undoRedo:finishPaintEvent()).toBe(true)

    expect(tile:getPixel(1, 1)).toBe(2)
    expect(tile:getPixel(2, 3)).toBe(2)
    expect(tile:getPixel(0, 0)).toBe(0)
    expect(app.undoRedo:undo(app)).toBeTruthy()
    expect(tile:getPixel(1, 1)).toBe(0)
    expect(tile:getPixel(2, 3)).toBe(0)
  end)

  it("fills rectangles exactly regardless of brush size", function()
    local app, tile = makeApp(0)
    local win = makeWin(tile)
    app.brushSize = 4

    app.undoRedo:startPaintEvent()
    local ok = BrushController.fillRect(app, win, 1, 1, 2, 2, false)
    expect(ok).toBe(true)
    expect(app.undoRedo:finishPaintEvent()).toBe(true)

    expect(tile:getPixel(1, 1)).toBe(2)
    expect(tile:getPixel(2, 2)).toBe(2)
    expect(tile:getPixel(0, 0)).toBe(0)
    expect(tile:getPixel(4, 1)).toBe(0)
    expect(tile:getPixel(1, 4)).toBe(0)
  end)
end)

describe("brush_controller.lua - batched chr painting", function()
  local originals

  beforeEach(function()
    originals = {
      invalidateTile = BankCanvasSupport.invalidateTile,
      getSyncGroup = ChrDuplicateSync.getSyncGroup,
      isEnabled = ChrDuplicateSync.isEnabled,
    }
  end)

  afterEach(function()
    BankCanvasSupport.invalidateTile = originals.invalidateTile
    ChrDuplicateSync.getSyncGroup = originals.getSyncGroup
    ChrDuplicateSync.isEnabled = originals.isEnabled
  end)

  it("batches large-brush tile painting to one sync lookup and one tile invalidation", function()
    local app, tile, bankBytes = makeApp(0)
    local win = makeWin(tile)
    app.brushSize = 4

    local invalidations = 0
    local syncCalls = 0
    BankCanvasSupport.invalidateTile = function()
      invalidations = invalidations + 1
    end
    ChrDuplicateSync.isEnabled = function()
      return false
    end
    ChrDuplicateSync.getSyncGroup = function(_, bankIdx, tileIndex)
      syncCalls = syncCalls + 1
      return { { bank = bankIdx, tileIndex = tileIndex } }
    end

    app.undoRedo:startPaintEvent()
    local ok = BrushController.paintPixel(app, win, 0, 0, 3, 3, false)

    expect(ok).toBe(true)
    expect(syncCalls).toBe(1)
    expect(invalidations).toBe(1)

    local pixelCount = 0
    for _ in pairs(app.undoRedo.activeEvent.pixels) do
      pixelCount = pixelCount + 1
    end
    expect(pixelCount).toBe(37)

    local paintedPixels = 0
    for _, value in ipairs(chr.decodeTile(bankBytes, 0)) do
      if value == app.currentColor then
        paintedPixels = paintedPixels + 1
      end
    end
    expect(paintedPixels).toBe(37)
  end)

  it("coalesces repeated duplicate-sync target writes within one paint step", function()
    local app, tile = makeApp(0)
    local win = makeWin(tile)

    local invalidations = 0
    BankCanvasSupport.invalidateTile = function()
      invalidations = invalidations + 1
    end
    ChrDuplicateSync.isEnabled = function()
      return true
    end
    ChrDuplicateSync.getSyncGroup = function(_, bankIdx, tileIndex)
      return {
        { bank = bankIdx, tileIndex = tileIndex },
        { bank = bankIdx, tileIndex = tileIndex },
      }
    end

    app.undoRedo:startPaintEvent()
    local ok = BrushController.paintPixel(app, win, 0, 0, 1, 1, false)

    expect(ok).toBe(true)
    expect(invalidations).toBe(1)
    expect(app.undoRedo.activeEvent.pixels["1:0:1:1"]).toNotBe(nil)

    local pixelCount = 0
    for _ in pairs(app.undoRedo.activeEvent.pixels) do
      pixelCount = pixelCount + 1
    end
    expect(pixelCount).toBe(1)
  end)

  it("does not sync paint edits across duplicates from ROM bank windows", function()
    local bankBytes = {}
    for i = 1, 32 do
      bankBytes[i] = 0
    end

    local tileA = makeTile(0)
    tileA._bankIndex = 1
    tileA.index = 0

    local tileB = makeTile(0)
    tileB._bankIndex = 1
    tileB.index = 1

    local app = {
      appEditState = {
        chrBanksBytes = { bankBytes },
        tilesPool = {
          [1] = {
            [0] = tileA,
            [1] = tileB,
          },
        },
        syncGroups = {
          [1] = {
            [0] = {
              { bank = 1, tileIndex = 0 },
              { bank = 1, tileIndex = 1 },
            },
          },
        },
      },
      undoRedo = UndoRedoController.new(10),
      currentColor = 2,
      syncDuplicateTiles = true,
      setStatus = function(self, text)
        self.statusText = text
      end,
    }

    local win = makeWin(tileA)
    win.kind = "chr"
    win.isRomWindow = true

    app.undoRedo:startPaintEvent()
    local ok = BrushController.paintPixel(app, win, 0, 0, 1, 1, false)

    expect(ok).toBe(true)
    expect(chr.decodeTile(bankBytes, 0)[10]).toBe(app.currentColor)
    for _, value in ipairs(chr.decodeTile(bankBytes, 1)) do
      expect(value).toBe(0)
    end
  end)
end)

describe("brush_controller.lua - fractional drag paint coordinates", function()
  it("undoes large-brush paint cleanly when fed fractional local coordinates", function()
    local app, tile, bankBytes = makeApp(0)
    local win = makeWin(tile)
    app.brushSize = 2

    app.undoRedo:startPaintEvent()
    local ok = BrushController.paintPixel(app, win, 0, 0, 3.7, 3.2, false)

    expect(ok).toBe(true)
    expect(app.undoRedo:finishPaintEvent()).toBe(true)
    expect(app.undoRedo:undo(app)).toBe(true)

    local pixels = chr.decodeTile(bankBytes, 0)
    for i = 1, #pixels do
      expect(pixels[i]).toBe(0)
      expect(tile.pixels[i]).toBe(0)
    end

    for key in pairs(tile.pixels) do
      expect(type(key)).toBe("number")
      expect(key).toBeGreaterThanOrEqual(1)
      expect(key).toBeLessThan(65)
      expect(key % 1).toBe(0)
    end
  end)
end)
