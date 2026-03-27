local SpriteController = require("controllers.sprite.sprite_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
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
          return 0.10, 0.10, 0.10, 1.0 -- dark
        elseif x < 6 then
          return 0.50, 0.50, 0.50, 1.0 -- mid
        end
        return 0.90, 0.90, 0.90, 1.0 -- bright
      end,
    }
  end

  local function makeTwoFrameImageData()
    return {
      getWidth = function() return 16 end,
      getHeight = function() return 8 end,
      getPixel = function(_, x, _)
        if x < 8 then
          return 0.10, 0.10, 0.10, 1.0 -- frame 1: dark
        end
        return 0.90, 0.90, 0.90, 1.0 -- frame 2: bright
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

    -- Default test behavior for layers without paletteData: deterministic identity
    -- brightness order for visible sprite colors (1..3).
    ShaderPaletteController.getPaletteColors = function(layer, paletteNumber, romRaw)
      if layer and layer.paletteData then
        return originalGetPaletteColors(layer, paletteNumber, romRaw)
      end
      return {
        { 0.00, 0.00, 0.00 }, -- transparent slot (ignored for sprite mapping)
        { 0.20, 0.20, 0.20 }, -- visible slot 1 (dark)
        { 0.50, 0.50, 0.50 }, -- visible slot 2 (mid)
        { 0.90, 0.90, 0.90 }, -- visible slot 3 (bright)
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
    expect(tileRef.pixels[1]).toBe(2) -- darkest PNG color -> darkest palette slot
    expect(tileRef.pixels[4]).toBe(3) -- middle PNG color  -> middle palette slot
    expect(tileRef.pixels[7]).toBe(1) -- brightest PNG color -> brightest palette slot
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

  it("uses global palette brightness order when layer has no assigned palette", function()
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
    expect(tileRef.pixels[1]).toBe(1)
    expect(tileRef.pixels[4]).toBe(2)
    expect(tileRef.pixels[7]).toBe(3)
  end)

  it("maps PNG brightness ranks through fallback global palette colors", function()
    ShaderPaletteController.getPaletteColors = function()
      return {
        { 0.0, 0.0, 0.0 },
        { 0.95, 0.95, 0.95 }, -- slot 1 brightest
        { 0.10, 0.10, 0.10 }, -- slot 2 darkest
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
    expect(tileRef.pixels[1]).toBe(2) -- darkest PNG -> darkest visible palette slot
    expect(tileRef.pixels[4]).toBe(3) -- mid PNG -> mid slot
    expect(tileRef.pixels[7]).toBe(1) -- brightest PNG -> brightest slot
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
    expect(tileRef1.pixels[1]).toBe(0)
    expect(tileRef2.pixels[1]).toBe(1)
    expect(tileRef3.pixels[1]).toBe(2)
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
    expect(tileRef1.pixels[1]).toBe(0)
    expect(tileRef2.pixels[1]).toBe(2)
    expect(tileRef3.pixels[1]).toBe(1)
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
    expect(tileRef1.pixels[1]).toBe(1)
    expect(tileRef2.pixels[1]).toBe(2)
    expect(tileRef3.pixels[1]).toBe(0)
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
    expect(tileRef.pixels[1]).toBe(1)
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
end)
