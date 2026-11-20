local SpriteController = require("controllers.sprite.sprite_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")
local Hydration = require("controllers.sprite.hydration_controller")
local chr = require("chr")

describe("sprite_controller.lua - PNG import palette mapping", function()
  local originalNewFileData
  local originalNewImageData
  local originalSetSpriteSelection
  local originalBeginDrag
  local originalUpdateDrag
  local originalEndDrag
  local originalGetPaletteColors
  local beginDragCallCount

  local function makeImageData()
    return {
      getWidth = function() return 8 end,
      getHeight = function() return 8 end,
      getPixel = function(_, x, _)
        if x < 3 then
          return 0.10, 0.10, 0.10, 1.0 -- dark (NES transparent / BG)
        elseif x < 6 then
          return 0.50, 0.50, 0.50, 1.0 -- mid
        end
        return 0.90, 0.90, 0.90, 1.0 -- bright
      end,
    }
  end

  local function makeTwoFrameImageData()
    -- Black corner marks NES transparent; frame bodies use mid/bright so imports stay non-zero.
    return {
      getWidth = function() return 16 end,
      getHeight = function() return 8 end,
      getPixel = function(_, x, y)
        if (x % 8) == 0 and y == 0 then
          return 0.0, 0.0, 0.0, 1.0 -- darkest -> index 0
        end
        if x < 8 then
          return 0.50, 0.50, 0.50, 1.0 -- frame 1: mid -> 1
        end
        return 0.90, 0.90, 0.90, 1.0 -- frame 2: bright -> 2
      end,
    }
  end

  local function makeFourFrame8x16ImageData()
    return {
      getWidth = function() return 32 end,
      getHeight = function() return 16 end,
      getPixel = function(_, x, y)
        local frame = math.floor(x / 8) + 1 -- 1..4
        local localX = x % 8
        local localY = y
        if frame == 1 and localX == 0 and localY == 0 then
          return 0.9, 0.9, 0.9, 1.0
        end
        if frame == 2 and localX == 1 and localY == 1 then
          return 0.9, 0.9, 0.9, 1.0
        end
        if frame == 3 and localX == 2 and localY == 2 then
          return 0.9, 0.9, 0.9, 1.0
        end
        if frame == 4 and localX == 3 and localY == 3 then
          return 0.9, 0.9, 0.9, 1.0
        end
        return 0, 0, 0, 0
      end,
    }
  end

  local function makeDroppedFile()
    return {
      open = function() end,
      read = function() return "fake_png_bytes" end,
      close = function() end,
      getFilename = function() return "fake.png" end,
    }
  end

  local function makeTileRef()
    local pixels = {}
    for i = 1, 64 do pixels[i] = 0 end
    return {
      _bankBytesRef = {},
      _bankIndex = 1,
      index = 0,
      pixels = pixels,
      refreshImage = function() end,
    }
  end

  local function seedNonFlatTile(bankBytes, tileRef, color)
    color = color or 1
    chr.setTilePixel(bankBytes, tileRef.index, 0, 0, color)
    tileRef.pixels[1] = color
  end

  local function makeUndoRedoSpy()
    local spy = {
      events = {},
      activeEvent = nil,
    }

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

  local function makeSprite8x16()
    return {
      removed = false,
      paletteNumber = 1,
      topRef = makeTileRef(),
      botRef = makeTileRef(),
      x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
    }
  end

  local function makeWindow(layer)
    return {
      x = 0,
      y = 0,
      zoom = 1,
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      scrollCol = 0,
      scrollRow = 0,
      layers = { layer },
      getZoomLevel = function() return 1 end,
      getActiveLayerIndex = function() return 1 end,
    }
  end

  local function makeApp(opts)
    opts = opts or {}
    return {
      appEditState = opts.appEditState or { romRaw = "" },
      edits = opts.edits or { banks = {} },
      undoRedo = opts.undoRedo,
      syncDuplicateTiles = opts.syncDuplicateTiles,
      setStatus = function(self, text)
        self.statusText = text
      end,
    }
  end

  beforeEach(function()
    beginDragCallCount = 0

    originalNewFileData = love.filesystem.newFileData
    originalNewImageData = love.image.newImageData
    originalSetSpriteSelection = SpriteController.setSpriteSelection
    originalBeginDrag = SpriteController.beginDrag
    originalUpdateDrag = SpriteController.updateDrag
    originalEndDrag = SpriteController.endDrag
    originalGetPaletteColors = ShaderPaletteController.getPaletteColors

    love.filesystem.newFileData = function()
      return {}
    end
    love.image.newImageData = function()
      return makeImageData()
    end

    -- PNG import reuses drag logic to reposition sprites. Stub it here so this
    -- test isolates color-index mapping only.
    SpriteController.setSpriteSelection = function() end
    SpriteController.beginDrag = function()
      beginDragCallCount = beginDragCallCount + 1
    end
    SpriteController.updateDrag = function() end
    SpriteController.endDrag = function() end

    -- Default: identity brightness order across all NES slots (0..3).
    -- Darkest PNG color maps to slot 0 (transparent / BG).
    ShaderPaletteController.getPaletteColors = function(layer, paletteNumber, romRaw)
      if layer and layer.paletteData then
        return originalGetPaletteColors(layer, paletteNumber, romRaw)
      end
      return {
        { 0.00, 0.00, 0.00 }, -- slot 0 transparent / BG (darkest)
        { 0.20, 0.20, 0.20 }, -- slot 1
        { 0.50, 0.50, 0.50 }, -- slot 2
        { 0.90, 0.90, 0.90 }, -- slot 3
      }
    end
  end)

  afterEach(function()
    love.filesystem.newFileData = originalNewFileData
    love.image.newImageData = originalNewImageData
    SpriteController.setSpriteSelection = originalSetSpriteSelection
    SpriteController.beginDrag = originalBeginDrag
    SpriteController.updateDrag = originalUpdateDrag
    SpriteController.endDrag = originalEndDrag
    ShaderPaletteController.getPaletteColors = originalGetPaletteColors
  end)

  it("maps PNG brightness ranks to assigned palette brightness order", function()
    local tileRef = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      paletteData = {
        items = {
          { "0F", "30", "16", "28" }, -- visible slots are bright, dark, mid
        },
      },
      items = {
        {
          removed = false,
          paletteNumber = 1,
          topRef = tileRef,
          x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
        },
      },
    }
    local win = makeWindow(layer)
    local app = makeApp()

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(tileRef.pixels[1]).toBe(0) -- darkest PNG color -> NES transparent / BG
    expect(tileRef.pixels[4]).toBe(2) -- middle PNG color
    expect(tileRef.pixels[7]).toBe(3) -- brightest PNG color
  end)

  it("keeps opaque black visible when PNG also has alpha transparency", function()
    -- Transparent + black + mid + bright: alpha -> index 0, opaque black must not collapse to 0.
    love.image.newImageData = function()
      return {
        getWidth = function() return 8 end,
        getHeight = function() return 8 end,
        getPixel = function(_, x, _)
          if x < 2 then
            return 0, 0, 0, 0 -- transparent
          elseif x < 4 then
            return 0, 0, 0, 1 -- opaque black
          elseif x < 6 then
            return 0.50, 0.50, 0.50, 1
          end
          return 0.90, 0.90, 0.90, 1
        end,
      }
    end

    local tileRef = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          removed = false,
          paletteNumber = 1,
          topRef = tileRef,
          x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
        },
      },
    }
    local win = makeWindow(layer)
    local app = makeApp()

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(tileRef.pixels[1]).toBe(0) -- transparent -> BG
    expect(tileRef.pixels[3]).toNotBe(0) -- opaque black stays visible
    expect(tileRef.pixels[5]).toNotBe(0)
    expect(tileRef.pixels[7]).toNotBe(0)
  end)

  it("records an undoable paint event for sprite PNG import", function()
    local tileRef = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          removed = false,
          paletteNumber = 1,
          topRef = tileRef,
          x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
        },
      },
    }
    local win = makeWindow(layer)
    local undoRedo = makeUndoRedoSpy()
    local app = makeApp({ undoRedo = undoRedo })

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(#undoRedo.events).toBe(1)

    local pixelCount = 0
    local hasNonZeroAfter = false
    for _, px in pairs(undoRedo.events[1].pixels or {}) do
      pixelCount = pixelCount + 1
      if (px.after or 0) ~= 0 then
        hasNonZeroAfter = true
      end
    end
    expect(pixelCount).toBeGreaterThan(0)
    expect(hasNonZeroAfter).toBe(true)
  end)

  it("undos sprite PNG import positions and pixel edits together", function()
    local bankBytes = {}
    for i = 1, 16 do bankBytes[i] = 0 end

    local tileRef = makeTileRef()
    tileRef._bankBytesRef = bankBytes
    tileRef._bankIndex = 1
    tileRef.index = 0
    tileRef.loadFromCHR = function(self, sourceBytes, tileIndex)
      self.pixels = chr.decodeTile(sourceBytes, tileIndex)
    end

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          removed = false,
          paletteNumber = 1,
          topRef = tileRef,
          x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
          dx = 0, dy = 0, hasMoved = false,
        },
      },
    }
    local win = makeWindow(layer)
    local undoRedo = UndoRedoController.new(10)
    local app = makeApp({
      undoRedo = undoRedo,
      appEditState = {
        romRaw = "",
        chrBanksBytes = { [1] = bankBytes },
        tilesPool = { [1] = { [0] = tileRef } },
      },
    })

    SpriteController.beginDrag = function() end
    SpriteController.updateDrag = function()
      local sprite = layer.items[1]
      sprite.worldX, sprite.worldY = 24, 16
      sprite.x, sprite.y = 24, 16
      sprite.dx, sprite.dy = 24, 16
      sprite.hasMoved = true
    end
    SpriteController.endDrag = function() end

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(#undoRedo.stack).toBe(1)
    expect(undoRedo.stack[1].type).toBe("composite")
    expect(layer.items[1].worldX).toBe(24)
    expect(layer.items[1].worldY).toBe(16)
    expect(tileRef.pixels[4]).toNotBe(0)

    expect(undoRedo:undo(app)).toBe(true)
    expect(layer.items[1].worldX).toBe(0)
    expect(layer.items[1].worldY).toBe(0)
    expect(layer.items[1].dx).toBe(0)
    expect(layer.items[1].dy).toBe(0)
    expect(tileRef.pixels[4]).toBe(0)

    expect(undoRedo:redo(app)).toBe(true)
    expect(layer.items[1].worldX).toBe(24)
    expect(layer.items[1].worldY).toBe(16)
    expect(tileRef.pixels[4]).toNotBe(0)
  end)

  it("uses generic palette brightness order when layer has no assigned palette", function()
    local tileRef = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          removed = false,
          paletteNumber = 1,
          topRef = tileRef,
          x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
        },
      },
    }
    local win = makeWindow(layer)
    local app = makeApp()

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(tileRef.pixels[1]).toBe(0)
    expect(tileRef.pixels[4]).toBe(1)
    expect(tileRef.pixels[7]).toBe(2)
  end)

  it("maps PNG brightness ranks through fallback generic palette colors", function()
    ShaderPaletteController.getPaletteColors = function()
      return {
        { 0.0, 0.0, 0.0 },
        { 0.95, 0.95, 0.95 }, -- slot 1 brightest
        { 0.10, 0.10, 0.10 }, -- slot 2
        { 0.50, 0.50, 0.50 }, -- slot 3 mid
      }
    end

    local tileRef = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          removed = false,
          paletteNumber = 1,
          topRef = tileRef,
          x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
        },
      },
    }
    local win = makeWindow(layer)
    local app = makeApp()

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(tileRef.pixels[1]).toBe(0) -- darkest PNG -> darkest palette slot (BG)
    expect(tileRef.pixels[4]).toBe(2) -- mid PNG -> next darkest slot
    expect(tileRef.pixels[7]).toBe(3) -- brightest PNG -> next slot
  end)

  it("syncs duplicate CHR tiles during sprite PNG import when syncDuplicateTiles is enabled", function()
    local bankBytes = {}
    for i = 1, 32 do bankBytes[i] = 0 end

    local tileRef1 = makeTileRef()
    tileRef1.index = 0
    tileRef1._bankIndex = 1
    tileRef1._bankBytesRef = bankBytes

    local tileRef2 = makeTileRef()
    tileRef2.index = 1
    tileRef2._bankIndex = 1
    tileRef2._bankBytesRef = bankBytes

    seedNonFlatTile(bankBytes, tileRef1, 1)
    seedNonFlatTile(bankBytes, tileRef2, 1)

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          removed = false,
          paletteNumber = 1,
          topRef = tileRef1,
          x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
        },
      },
    }
    local win = makeWindow(layer)
    local frozenGroup = {
      { bank = 1, tileIndex = 0 },
      { bank = 1, tileIndex = 1 },
    }
    local app = makeApp({
      syncDuplicateTiles = true,
      appEditState = {
        romRaw = "",
        chrBanksBytes = { bankBytes },
        tilesPool = { [1] = { [0] = tileRef1, [1] = tileRef2 } },
        syncGroups = {
          [1] = {
            [0] = frozenGroup,
            [1] = frozenGroup,
          }
        },
      },
    })

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(tileRef2.pixels[1]).toBe(tileRef1.pixels[1])
    expect(tileRef2.pixels[4]).toBe(tileRef1.pixels[4])
    expect(tileRef2.pixels[7]).toBe(tileRef1.pixels[7])
  end)

  it("maps PNG frames to selected sprites when selection exists", function()
    love.image.newImageData = function()
      return makeTwoFrameImageData()
    end

    local tileRef1 = makeTileRef()
    local tileRef2 = makeTileRef()
    local tileRef3 = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { removed = false, paletteNumber = 1, topRef = tileRef1, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tileRef2, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tileRef3, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
      },
      multiSpriteSelection = {
        [2] = true,
        [3] = true,
      },
      selectedSpriteIndex = 2,
    }
    local win = makeWindow(layer)
    local app = makeApp()

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(tileRef1.pixels[2]).toBe(0)
    expect(tileRef2.pixels[2]).toBe(1)
    expect(tileRef3.pixels[2]).toBe(2)
    expect(beginDragCallCount).toBe(0)
  end)

  it("maps selected sprites using preserved selection order", function()
    love.image.newImageData = function()
      return makeTwoFrameImageData()
    end

    local tileRef1 = makeTileRef()
    local tileRef2 = makeTileRef()
    local tileRef3 = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { removed = false, paletteNumber = 1, topRef = tileRef1, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tileRef2, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tileRef3, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
      },
      multiSpriteSelection = {
        [2] = true,
        [3] = true,
      },
      multiSpriteSelectionOrder = { 3, 2 },
      selectedSpriteIndex = 3,
    }
    local win = makeWindow(layer)
    local app = makeApp()

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(tileRef1.pixels[2]).toBe(0)
    expect(tileRef2.pixels[2]).toBe(2)
    expect(tileRef3.pixels[2]).toBe(1)
    expect(beginDragCallCount).toBe(0)
  end)

  it("keeps existing import order when no sprites are selected", function()
    love.image.newImageData = function()
      return makeTwoFrameImageData()
    end

    local tileRef1 = makeTileRef()
    local tileRef2 = makeTileRef()
    local tileRef3 = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { removed = false, paletteNumber = 1, topRef = tileRef1, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tileRef2, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tileRef3, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
      },
    }
    local win = makeWindow(layer)
    local app = makeApp()

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(tileRef1.pixels[2]).toBe(1)
    expect(tileRef2.pixels[2]).toBe(2)
    expect(tileRef3.pixels[2]).toBe(0)
    expect(beginDragCallCount).toBe(2)
  end)

  it("imports into sprite layers even when active layer is non-sprite", function()
    local tileRef = makeTileRef()
    local tileLayer = {
      kind = "tile",
      items = {},
    }
    local spriteLayer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          removed = false,
          paletteNumber = 1,
          topRef = tileRef,
          x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
        },
      },
      multiSpriteSelection = { [1] = true },
      multiSpriteSelectionOrder = { 1 },
      selectedSpriteIndex = 1,
    }
    local win = {
      x = 0,
      y = 0,
      zoom = 1,
      cols = 8,
      rows = 8,
      cellW = 8,
      cellH = 8,
      scrollCol = 0,
      scrollRow = 0,
      layers = { tileLayer, spriteLayer },
      getZoomLevel = function() return 1 end,
      getActiveLayerIndex = function() return 1 end, -- non-sprite active layer
      getSpriteLayers = function()
        return {
          { index = 2, layer = spriteLayer },
        }
      end,
    }
    local app = makeApp()

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    expect(tileRef.pixels[1]).toBe(0)
    expect(beginDragCallCount).toBe(0)
  end)

  it("maps 32x16 (4x 8x16) PNG frames left-to-right into selected sprite order", function()
    love.image.newImageData = function()
      return makeFourFrame8x16ImageData()
    end

    local s1 = makeSprite8x16()
    local s2 = makeSprite8x16()
    local s3 = makeSprite8x16()
    local s4 = makeSprite8x16()
    local layer = {
      kind = "sprite",
      mode = "8x16",
      items = { s1, s2, s3, s4 },
      multiSpriteSelection = { [1] = true, [2] = true, [3] = true, [4] = true },
      multiSpriteSelectionOrder = { 3, 1, 4, 2 },
      selectedSpriteIndex = 3,
    }
    local win = makeWindow(layer)
    local app = makeApp()

    local handled = SpriteController.handleSpritePngDrop(app, makeDroppedFile(), win)

    expect(handled).toBe(true)
    -- Frame 1 marker at (0,0) -> sprite index 3
    expect(s3.topRef.pixels[1]).toBe(1)
    -- Frame 2 marker at (1,1) -> sprite index 1
    expect(s1.topRef.pixels[1 * 8 + 1 + 1]).toBe(1)
    -- Frame 3 marker at (2,2) -> sprite index 4
    expect(s4.topRef.pixels[2 * 8 + 2 + 1]).toBe(1)
    -- Frame 4 marker at (3,3) -> sprite index 2
    expect(s2.topRef.pixels[3 * 8 + 3 + 1]).toBe(1)
    expect(beginDragCallCount).toBe(0)
  end)

  it("importSpriteImageData fills selected sprites in selection order", function()
    local tileRef1 = makeTileRef()
    local tileRef2 = makeTileRef()
    local tileRef3 = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { removed = false, paletteNumber = 1, topRef = tileRef1, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tileRef2, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tileRef3, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
      },
      multiSpriteSelection = { [2] = true, [3] = true },
      multiSpriteSelectionOrder = { 3, 2 },
      selectedSpriteIndex = 3,
    }
    local win = makeWindow(layer)
    local app = makeApp()

    local ok = SpriteController.importSpriteImageData(app, makeTwoFrameImageData(), win)

    expect(ok).toBe(true)
    expect(tileRef1.pixels[2]).toBe(0)
    expect(tileRef2.pixels[2]).toBe(2)
    expect(tileRef3.pixels[2]).toBe(1)
    expect(beginDragCallCount).toBe(0)
  end)

  it("flips imported pixels when the sprite is mirrored so the drawing matches the PNG", function()
    local function markedImage(height)
      return {
        getWidth = function() return 8 end,
        getHeight = function() return height end,
        getPixel = function(_, x, y)
          if x == 0 and y == 0 then
            return 0.90, 0.90, 0.90, 1.0
          end
          if x == 7 and y == (height - 1) then
            return 0.50, 0.50, 0.50, 1.0
          end
          return 0.10, 0.10, 0.10, 1.0
        end,
      }
    end

    local function importInto(sprite, mode, height)
      local layer = {
        kind = "sprite",
        mode = mode,
        items = { sprite },
        multiSpriteSelection = { [1] = true },
        multiSpriteSelectionOrder = { 1 },
        selectedSpriteIndex = 1,
      }
      return SpriteController.importSpriteImageData(makeApp(), markedImage(height), makeWindow(layer))
    end

    local plainX = {
      removed = false,
      paletteNumber = 1,
      topRef = makeTileRef(),
      x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
    }
    local mirrorX = {
      removed = false,
      paletteNumber = 1,
      mirrorX = true,
      topRef = makeTileRef(),
      x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
    }
    expect(importInto(plainX, "8x8", 8)).toBe(true)
    expect(importInto(mirrorX, "8x8", 8)).toBe(true)
    -- PNG x=0 is stored at x=7, which horizontal flip draws back on the left.
    expect(plainX.topRef.pixels[1]).toBe(2)
    expect(mirrorX.topRef.pixels[8]).toBe(2)
    expect(mirrorX.topRef.pixels[1]).toBe(0)

    local plainY = makeSprite8x16()
    local mirrorY = makeSprite8x16()
    mirrorY.mirrorY = true
    expect(importInto(plainY, "8x16", 16)).toBe(true)
    expect(importInto(mirrorY, "8x16", 16)).toBe(true)
    -- PNG top-left moves to the bottom tile's top row, then vertical flip puts it on that tile's last row.
    expect(plainY.topRef.pixels[1]).toBe(2)
    expect(mirrorY.botRef.pixels[8 * 7 + 1]).toBe(2)
    -- PNG bottom-right moves to the top tile and lands on its last column, first row.
    expect(plainY.botRef.pixels[8 * 7 + 8]).toBe(1)
    expect(mirrorY.topRef.pixels[8]).toBe(1)
  end)

  it("importSpriteImageData fills sprites in list order when nothing is selected", function()
    local tileRef1 = makeTileRef()
    local tileRef2 = makeTileRef()
    local tileRef3 = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { removed = false, paletteNumber = 1, topRef = tileRef1, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tileRef2, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tileRef3, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
      },
    }
    local win = makeWindow(layer)
    local app = makeApp()

    local ok = SpriteController.importSpriteImageData(app, makeTwoFrameImageData(), win)

    expect(ok).toBe(true)
    expect(tileRef1.pixels[2]).toBe(1)
    expect(tileRef2.pixels[2]).toBe(2)
    expect(tileRef3.pixels[2]).toBe(0)
    expect(beginDragCallCount).toBe(2)
  end)

  it("importSpriteImageData rejects more than 4 colors", function()
    local tileRef = makeTileRef()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { removed = false, paletteNumber = 1, topRef = tileRef, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
      },
      multiSpriteSelection = { [1] = true },
      multiSpriteSelectionOrder = { 1 },
      selectedSpriteIndex = 1,
    }
    local img = {
      getWidth = function() return 8 end,
      getHeight = function() return 8 end,
      getPixel = function(_, x)
        if x == 0 then return 1, 0, 0, 1 end
        if x == 1 then return 0, 1, 0, 1 end
        if x == 2 then return 0, 0, 1, 1 end
        if x == 3 then return 1, 1, 0, 1 end
        return 1, 0, 1, 1
      end,
    }
    local app = makeApp()

    local ok = SpriteController.importSpriteImageData(app, img, makeWindow(layer))

    expect(ok).toBe(false)
    expect(tostring(app.statusText):find("too many colors", 1, true)).toBeTruthy()
    expect(tileRef.pixels[1]).toBe(0)
  end)

  it("importSpriteImageData rejects sizes that are not a multiple of the sprite grid", function()
    local function reject(mode, w, h, needle)
      local tileRef = makeTileRef()
      local layer = {
        kind = "sprite",
        mode = mode,
        items = {
          { removed = false, paletteNumber = 1, topRef = tileRef, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        },
        multiSpriteSelection = { [1] = true },
        multiSpriteSelectionOrder = { 1 },
        selectedSpriteIndex = 1,
      }
      local img = {
        getWidth = function() return w end,
        getHeight = function() return h end,
        getPixel = function() return 0.2, 0.2, 0.2, 1 end,
      }
      local app = makeApp()
      local ok = SpriteController.importSpriteImageData(app, img, makeWindow(layer))
      expect(ok).toBe(false)
      expect(tostring(app.statusText):find(needle, 1, true)).toBeTruthy()
      expect(tileRef.pixels[1]).toBe(0)
    end

    reject("8x8", 7, 8, "8x8")
    reject("8x16", 8, 8, "8x16")
  end)

  it("importSpriteImageData paints a selected sprite whose tile object is not the pool tile", function()
    local function blankPixels()
      local pixels = {}
      for i = 1, 64 do pixels[i] = 0 end
      return pixels
    end
    local spriteRef = {
      _bankIndex = 1,
      index = 4,
      pixels = blankPixels(),
      refreshImage = function() end,
    }
    local poolRef = {
      _bankIndex = 1,
      index = 4,
      pixels = blankPixels(),
      refreshImage = function() end,
    }
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        {
          removed = false,
          paletteNumber = 1,
          topRef = spriteRef,
          x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
        },
      },
      multiSpriteSelection = { [1] = true },
      multiSpriteSelectionOrder = { 1 },
      selectedSpriteIndex = 1,
    }
    local app = makeApp({
      appEditState = {
        romRaw = "",
        tilesPool = { [1] = { [4] = poolRef } },
      },
    })

    local ok = SpriteController.importSpriteImageData(app, makeTwoFrameImageData(), makeWindow(layer))

    expect(ok).toBe(true)
    -- Frame 1's first visible pixel is the mid gray at (1, 0) -> palette index 1.
    expect(layer.items[1].topRef.pixels[2]).toBe(1)
    expect(spriteRef.pixels[2]).toBe(1)
    expect(poolRef.pixels[2]).toBe(1)
  end)

  it("writes each selected sprite's frame into that sprite's CHR slot", function()
    local function blankPixels()
      local pixels = {}
      for i = 1, 64 do pixels[i] = 0 end
      return pixels
    end
    local function makeBoundTile(bankBytes, index)
      return {
        _bankIndex = 1,
        _bankBytesRef = bankBytes,
        index = index,
        pixels = blankPixels(),
        refreshImage = function() end,
      }
    end

    local bankBytes = {}
    for i = 1, 21 * 16 do bankBytes[i] = 0 end
    local detached10 = makeBoundTile(bankBytes, 10)
    local detached20 = makeBoundTile(bankBytes, 20)
    local pool10 = makeBoundTile(bankBytes, 10)
    local pool20 = makeBoundTile(bankBytes, 20)
    -- Identical starting bytes would be one sync group if duplicate sync were on.
    chr.setTilePixel(bankBytes, 10, 0, 0, 1)
    chr.setTilePixel(bankBytes, 20, 0, 0, 1)
    detached10.pixels[1] = 1
    detached20.pixels[1] = 1
    pool10.pixels[1] = 1
    pool20.pixels[1] = 1

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { removed = false, paletteNumber = 1, topRef = detached10, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = detached20, x = 8, y = 0, worldX = 8, worldY = 0, baseX = 8, baseY = 0 },
      },
      multiSpriteSelection = { [1] = true, [2] = true },
      multiSpriteSelectionOrder = { 1, 2 },
      selectedSpriteIndex = 1,
    }
    local app = makeApp({
      appEditState = {
        romRaw = "",
        chrBanksBytes = { [1] = bankBytes },
        tilesPool = { [1] = { [10] = pool10, [20] = pool20 } },
      },
      syncDuplicateTiles = false,
    })

    local ok = SpriteController.importSpriteImageData(app, makeTwoFrameImageData(), makeWindow(layer))

    expect(ok).toBe(true)
    expect(layer.items[1].topRef).toBe(pool10)
    expect(layer.items[2].topRef).toBe(pool20)
    expect(pool10.pixels[2]).toBe(1)
    expect(pool20.pixels[2]).toBe(2)
    local chr10 = chr.decodeTile(bankBytes, 10)
    local chr20 = chr.decodeTile(bankBytes, 20)
    expect(chr10[2]).toBe(1)
    expect(chr20[2]).toBe(2)
    expect(chr10[2]).toBe(pool10.pixels[2])
    expect(chr20[2]).toBe(pool20.pixels[2])
  end)

  it("writes pattern-mapped sprites into the physical CHR tiles they display", function()
    local function blankPixels()
      local pixels = {}
      for i = 1, 64 do pixels[i] = 0 end
      return pixels
    end
    local bankBytes = {}
    for i = 1, 32 * 16 do bankBytes[i] = 0 end
    local function poolTile(index)
      local tile = {
        _bankIndex = 1,
        _bankBytesRef = bankBytes,
        index = index,
        pixels = blankPixels(),
        refreshImage = function() end,
      }
      return tile
    end
    local tilesPool = { [1] = {} }
    for i = 0, 31 do
      tilesPool[1][i] = poolTile(i)
    end

    local explicit = {}
    for logical = 0, 255 do
      local physical = logical
      if logical == 0 then physical = 10
      elseif logical == 1 then physical = 20
      elseif logical == 10 then physical = 0
      elseif logical == 20 then physical = 1
      end
      explicit[#explicit + 1] = { bank = 1, tileIndex = physical }
    end

    local addr = 0x0200
    local romRaw = ("\0"):rep(addr) .. string.char(10, 0, 0, 40) .. string.char(10, 1, 0, 56)
    local layer = {
      kind = "sprite",
      mode = "8x8",
      patternTable = { ranges = { { bank = 1, tiles = explicit } } },
      items = {
        { startAddr = addr, dx = 0, dy = 0 },
        { startAddr = addr + 4, dx = 0, dy = 0 },
      },
      multiSpriteSelection = { [1] = true, [2] = true },
      multiSpriteSelectionOrder = { 1, 2 },
      selectedSpriteIndex = 1,
    }
    Hydration.hydrateSpriteLayer(layer, {
      romRaw = romRaw,
      tilesPool = tilesPool,
      appEditState = { chrBanksBytes = { [1] = bankBytes }, tilesPool = tilesPool },
    })
    expect(layer.items[1].topRef).toBe(tilesPool[1][10])
    expect(layer.items[2].topRef).toBe(tilesPool[1][20])

    local app = makeApp({
      appEditState = {
        romRaw = romRaw,
        chrBanksBytes = { [1] = bankBytes },
        tilesPool = tilesPool,
      },
    })

    local ok = SpriteController.importSpriteImageData(app, makeTwoFrameImageData(), makeWindow(layer))

    expect(ok).toBe(true)
    expect(layer.items[1].topRef.pixels[2]).toBe(1)
    expect(layer.items[2].topRef.pixels[2]).toBe(2)
    expect(chr.decodeTile(bankBytes, 10)[2]).toBe(1)
    expect(chr.decodeTile(bankBytes, 20)[2]).toBe(2)
    expect(chr.decodeTile(bankBytes, 0)[2]).toBe(0)
    expect(chr.decodeTile(bankBytes, 1)[2]).toBe(0)
  end)

  it("keeps 8x16 top and bottom halves in their own CHR tiles", function()
    local function blankPixels()
      local pixels = {}
      for i = 1, 64 do pixels[i] = 0 end
      return pixels
    end
    local bankBytes = {}
    for i = 1, 8 * 16 do bankBytes[i] = 0 end
    local function tile(index)
      return {
        _bankIndex = 1,
        _bankBytesRef = bankBytes,
        index = index,
        pixels = blankPixels(),
        refreshImage = function() end,
      }
    end
    local top = tile(4)
    local bot = tile(5)
    local img = {
      getWidth = function() return 8 end,
      getHeight = function() return 16 end,
      getPixel = function(_, x, y)
        if y < 8 then
          if x == 1 and y == 0 then return 0.50, 0.50, 0.50, 1 end
          return 0, 0, 0, 1
        end
        if x == 2 and y == 8 then return 0.90, 0.90, 0.90, 1 end
        return 0, 0, 0, 1
      end,
    }
    local layer = {
      kind = "sprite",
      mode = "8x16",
      items = {
        {
          removed = false,
          paletteNumber = 1,
          topRef = top,
          botRef = bot,
          x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0,
        },
      },
      multiSpriteSelection = { [1] = true },
      multiSpriteSelectionOrder = { 1 },
      selectedSpriteIndex = 1,
    }
    local app = makeApp({
      appEditState = {
        romRaw = "",
        chrBanksBytes = { [1] = bankBytes },
        tilesPool = { [1] = { [4] = top, [5] = bot } },
      },
    })

    local ok = SpriteController.importSpriteImageData(app, img, makeWindow(layer))

    expect(ok).toBe(true)
    expect(top.pixels[2]).toBe(1)
    expect(bot.pixels[3]).toBe(2)
    expect(chr.decodeTile(bankBytes, 4)[2]).toBe(1)
    expect(chr.decodeTile(bankBytes, 4)[3]).toBe(0)
    expect(chr.decodeTile(bankBytes, 5)[3]).toBe(2)
    expect(chr.decodeTile(bankBytes, 5)[2]).toBe(0)
  end)

  it("invalidates cached canvases for each pasted CHR tile", function()
    local function blankPixels()
      local pixels = {}
      for i = 1, 64 do pixels[i] = 0 end
      return pixels
    end
    local bankBytes = {}
    for i = 1, 21 * 16 do bankBytes[i] = 0 end
    local function tile(index)
      return {
        _bankIndex = 1,
        _bankBytesRef = bankBytes,
        index = index,
        pixels = blankPixels(),
        refreshImage = function() end,
      }
    end
    local tile10 = tile(10)
    local tile20 = tile(20)
    local calls = {}
    local function record(kind)
      return function(_, bank, tileIndex)
        calls[#calls + 1] = { kind = kind, bank = bank, tile = tileIndex }
      end
    end
    local function count(kind, tileIndex)
      local n = 0
      for _, call in ipairs(calls) do
        if call.kind == kind and call.bank == 1 and call.tile == tileIndex then
          n = n + 1
        end
      end
      return n
    end

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { removed = false, paletteNumber = 1, topRef = tile10, x = 0, y = 0, worldX = 0, worldY = 0, baseX = 0, baseY = 0 },
        { removed = false, paletteNumber = 1, topRef = tile20, x = 8, y = 0, worldX = 8, worldY = 0, baseX = 8, baseY = 0 },
      },
      multiSpriteSelection = { [1] = true, [2] = true },
      multiSpriteSelectionOrder = { 1, 2 },
      selectedSpriteIndex = 1,
    }
    local app = makeApp({
      appEditState = {
        romRaw = "",
        chrBanksBytes = { [1] = bankBytes },
        tilesPool = { [1] = { [10] = tile10, [20] = tile20 } },
      },
    })
    app.invalidateChrBankTileCanvas = record("chr")
    app.invalidatePpuFrameNametableTile = record("nametable")
    app.invalidatePpuFrameSpriteTilesForChrTile = record("sprite")
    app.invalidateStaticAnimationTileLayerCanvasForChrTile = record("tileLayer")

    local ok = SpriteController.importSpriteImageData(app, makeTwoFrameImageData(), makeWindow(layer))

    expect(ok).toBe(true)
    expect(count("chr", 10)).toBe(1)
    expect(count("chr", 20)).toBe(1)
    expect(count("nametable", 10)).toBe(1)
    expect(count("nametable", 20)).toBe(1)
    expect(count("sprite", 10)).toBe(1)
    expect(count("sprite", 20)).toBe(1)
    expect(count("tileLayer", 10)).toBe(1)
    expect(count("tileLayer", 20)).toBe(1)
    expect(count("chr", 0)).toBe(0)
  end)
end)
