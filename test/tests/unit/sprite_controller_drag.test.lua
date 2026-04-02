local SpriteController = require("controllers.sprite.sprite_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

local function makeWin()
  local layer = {
    kind = "sprite",
    mode = "8x8",
    items = {
      { bank = 0, tile = 1, baseX = 0, baseY = 0, worldX = 0, worldY = 0, x = 0, y = 0 },
      { bank = 0, tile = 2, baseX = 10, baseY = 10, worldX = 10, worldY = 10, x = 10, y = 10 },
    },
  }

  local win = {
    x = 0, y = 0,
    cellW = 8, cellH = 8,
    scrollCol = 0, scrollRow = 0,
    getZoomLevel = function() return 1 end,
    layers = { layer },
    getActiveLayerIndex = function() return 1 end,
  }

  return win, layer
end

local function makeOAMWinWithSharedSprite()
  local sharedA = {
    bank = 0, tile = 1, startAddr = 0x1234,
    baseX = 20, baseY = 30, worldX = 20, worldY = 30, x = 20, y = 30,
    dx = 0, dy = 0, attr = 0x00, paletteNumber = 1, mirrorX = false, mirrorY = false,
  }
  local sharedB = {
    bank = 0, tile = 1, startAddr = 0x1234,
    baseX = 20, baseY = 30, worldX = 20, worldY = 30, x = 20, y = 30,
    dx = 0, dy = 0, attr = 0x00, paletteNumber = 1, mirrorX = false, mirrorY = false,
  }
  local other = {
    bank = 0, tile = 2, startAddr = 0x9999,
    baseX = 40, baseY = 10, worldX = 40, worldY = 10, x = 40, y = 10,
    dx = 0, dy = 0,
  }

  local layer1 = { kind = "sprite", mode = "8x8", items = { sharedA } }
  local layer2 = { kind = "sprite", mode = "8x8", items = { other } }
  local layer3 = { kind = "sprite", mode = "8x8", items = { sharedB } }

  local win = {
    kind = "oam_animation",
    x = 0, y = 0,
    cellW = 8, cellH = 8,
    cols = 32, rows = 30,
    visibleCols = 32, visibleRows = 30,
    scrollCol = 0, scrollRow = 0,
    getZoomLevel = function() return 1 end,
    layers = { layer1, layer2, layer3 },
    getActiveLayerIndex = function() return 1 end,
  }

  return win, layer1, layer3, sharedA, sharedB
end

describe("sprite_controller.lua - ctrl+drag copy", function()
  it("duplicates dragged sprites when ctrl is held at start and end", function()
    local win, layer = makeWin()
    SpriteController.setSpriteSelection(layer, { 1 })

    -- Start drag with copy mode on
    SpriteController.beginDrag(win, 1, 1, 0, 0, true)
    expect(#layer.items).toBe(3) -- clone created immediately for visual copy-drag

    -- Simulate sprite moved during drag
    local clone = layer.items[3]
    clone.worldX, clone.worldY = 16, 8
    clone.x, clone.y = 16, 8
    clone.dx, clone.dy = 16, 8

    SpriteController.finishDrag(true)

    expect(#layer.items).toBe(3) -- original 2 + clone
    expect(layer.items[1].worldX).toBe(0) -- original stayed put
    expect(layer.items[1].worldY).toBe(0)
    expect(clone.worldX).toBe(16)
    expect(clone.worldY).toBe(8)
    expect(layer.selectedSpriteIndex).toBe(3)
  end)

  it("duplicates dragged sprites when copy state is omitted at drop", function()
    local win, layer = makeWin()
    SpriteController.setSpriteSelection(layer, { 1 })

    -- Start drag with copy mode on
    SpriteController.beginDrag(win, 1, 1, 0, 0, true)
    expect(#layer.items).toBe(3)

    -- Simulate sprite moved during drag
    local clone = layer.items[3]
    clone.worldX, clone.worldY = 18, 6
    clone.x, clone.y = 18, 6
    clone.dx, clone.dy = 18, 6

    -- No explicit ctrl state on drop: should still copy based on drag start.
    SpriteController.finishDrag()

    expect(#layer.items).toBe(3)
    expect(layer.items[1].worldX).toBe(0)
    expect(layer.items[1].worldY).toBe(0)
    expect(clone.worldX).toBe(18)
    expect(clone.worldY).toBe(6)
    expect(layer.selectedSpriteIndex).toBe(3)
  end)

  it("moves without duplicating when ctrl not held at drop", function()
    local win, layer = makeWin()
    SpriteController.setSpriteSelection(layer, { 1 })

    SpriteController.beginDrag(win, 1, 1, 0, 0, true)
    expect(#layer.items).toBe(3)

    local clone = layer.items[3]
    clone.worldX, clone.worldY = 12, 4
    clone.x, clone.y = 12, 4
    clone.dx, clone.dy = 12, 4

    SpriteController.finishDrag(false)

    expect(#layer.items).toBe(2)
    expect(layer.items[1].worldX).toBe(12)
    expect(layer.items[1].worldY).toBe(4)
  end)

  it("keeps original visible in place while dragging copied clone", function()
    local win, layer = makeWin()
    SpriteController.setSpriteSelection(layer, { 1 })

    SpriteController.beginDrag(win, 1, 1, 0, 0, true)
    expect(#layer.items).toBe(3)

    -- Move mouse enough to drag the clone.
    SpriteController.updateDrag(20, 12)

    -- Original remains in place while clone moves.
    expect(layer.items[1].worldX).toBe(0)
    expect(layer.items[1].worldY).toBe(0)
    expect(layer.items[3].worldX).toNotBe(0)
    expect(layer.items[3].worldY).toNotBe(0)
  end)

  it("removes temporary clones when copy-drag is canceled", function()
    local win, layer = makeWin()
    SpriteController.setSpriteSelection(layer, { 1 })

    SpriteController.beginDrag(win, 1, 1, 0, 0, true)
    expect(#layer.items).toBe(3)

    SpriteController.endDrag()

    expect(#layer.items).toBe(2)
    expect(layer.items[1].worldX).toBe(0)
    expect(layer.items[1].worldY).toBe(0)
    local selected = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selected).toBe(1)
    expect(selected[1]).toBe(1)
  end)

  it("preserves explicit selection order when copy-drag is canceled", function()
    local win, layer = makeWin()
    SpriteController.setSpriteSelection(layer, { 2, 1 })

    local orderedBefore = SpriteController.getSelectedSpriteIndicesInOrder(layer)
    expect(#orderedBefore).toBe(2)
    expect(orderedBefore[1]).toBe(2)
    expect(orderedBefore[2]).toBe(1)

    SpriteController.beginDrag(win, 1, 2, 0, 0, true)
    expect(#layer.items).toBe(4)
    SpriteController.endDrag()

    expect(#layer.items).toBe(2)
    local orderedAfter = SpriteController.getSelectedSpriteIndicesInOrder(layer)
    expect(#orderedAfter).toBe(2)
    expect(orderedAfter[1]).toBe(2)
    expect(orderedAfter[2]).toBe(1)
  end)
end)

describe("sprite_controller.lua - dragging with scroll", function()
  it("uses full layer bounds instead of viewport bounds when scrolled", function()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 0, tile = 1, baseX = 200, baseY = 40, worldX = 200, worldY = 40, x = 200, y = 40 },
      },
    }

    local win = {
      x = 0, y = 0,
      cellW = 8, cellH = 8,
      cols = 32, rows = 30,
      visibleCols = 8, visibleRows = 8,
      scrollCol = 10, scrollRow = 2,
      getZoomLevel = function() return 1 end,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    SpriteController.setSpriteSelection(layer, { 1 })

    local _, anchorIndex, offsetX, offsetY = SpriteController.pickSpriteAt(win, 124, 28, 1)
    expect(anchorIndex).toBe(1)

    SpriteController.beginDrag(win, 1, anchorIndex, offsetX, offsetY, false)
    SpriteController.updateDrag(125, 28)
    SpriteController.finishDrag(false)

    local s = layer.items[1]
    expect(s.worldX).toBe(201)
    expect(s.worldY).toBe(40)
  end)
end)

describe("sprite_controller.lua - oam multi-drag bounds", function()
  it("does not jump with 3 selected sprites when one starts outside y-range", function()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 0, tile = 1, baseX = 8, baseY = 252, worldX = 8, worldY = 252, x = 8, y = 252 },
        { bank = 0, tile = 2, baseX = 16, baseY = 20, worldX = 16, worldY = 20, x = 16, y = 20 },
        { bank = 0, tile = 3, baseX = 40, baseY = 60, worldX = 40, worldY = 60, x = 40, y = 60 },
      },
    }

    local win = {
      kind = "oam_animation",
      x = 0, y = 0,
      cellW = 8, cellH = 8,
      cols = 32, rows = 30,
      visibleCols = 32, visibleRows = 30,
      scrollCol = 0, scrollRow = 0,
      getZoomLevel = function() return 1 end,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    SpriteController.setSpriteSelection(layer, { 2, 1, 3 })

    local _, anchorIndex, offsetX, offsetY = SpriteController.pickSpriteAt(win, 20, 24, 1)
    expect(anchorIndex).toBe(2)

    SpriteController.beginDrag(win, 1, anchorIndex, offsetX, offsetY, false)
    SpriteController.updateDrag(20, 24)
    SpriteController.finishDrag(false)

    expect(layer.items[1].worldY).toBe(252)
    expect(layer.items[2].worldY).toBe(20)
    expect(layer.items[3].worldY).toBe(60)
  end)

  it("does not jump when anchor sprite world coords are outside wrapped range", function()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 0, tile = 1, baseX = 300, baseY = 20, worldX = 300, worldY = 20, x = 300, y = 20 },
        { bank = 0, tile = 2, baseX = 16, baseY = 20, worldX = 16, worldY = 20, x = 16, y = 20 },
        { bank = 0, tile = 3, baseX = 40, baseY = 60, worldX = 40, worldY = 60, x = 40, y = 60 },
      },
    }

    local win = {
      kind = "oam_animation",
      x = 0, y = 0,
      cellW = 8, cellH = 8,
      cols = 32, rows = 30,
      visibleCols = 32, visibleRows = 30,
      scrollCol = 0, scrollRow = 0,
      getZoomLevel = function() return 1 end,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    SpriteController.setSpriteSelection(layer, { 1, 2, 3 })

    local _, anchorIndex, offsetX, offsetY = SpriteController.pickSpriteAt(win, 48, 24, 1) -- wrapped hit for worldX=300
    expect(anchorIndex).toBe(1)

    SpriteController.beginDrag(win, 1, anchorIndex, offsetX, offsetY, false)
    SpriteController.updateDrag(48, 24) -- no cursor delta
    SpriteController.finishDrag(false)

    expect(layer.items[1].worldX).toBe(300)
    expect(layer.items[1].worldY).toBe(20)
    expect(layer.items[2].worldX).toBe(16)
    expect(layer.items[2].worldY).toBe(20)
    expect(layer.items[3].worldX).toBe(40)
    expect(layer.items[3].worldY).toBe(60)
  end)

  it("moves continuously (no invisible wall) with origin offsets and out-of-range worldX", function()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      originX = 120,
      originY = 0,
      items = {
        { bank = 0, tile = 1, baseX = 300, baseY = 20, worldX = 300, worldY = 20, x = 300, y = 20 },
      },
    }

    local win = {
      kind = "oam_animation",
      x = 0, y = 0,
      cellW = 8, cellH = 8,
      cols = 32, rows = 30,
      visibleCols = 32, visibleRows = 30,
      scrollCol = 0, scrollRow = 0,
      getZoomLevel = function() return 1 end,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
    }

    SpriteController.setSpriteSelection(layer, { 1 })

    local _, anchorIndex, offsetX, offsetY = SpriteController.pickSpriteAt(win, 168, 24, 1)
    expect(anchorIndex).toBe(1)

    SpriteController.beginDrag(win, 1, anchorIndex, offsetX, offsetY, false)
    SpriteController.updateDrag(169, 24)
    SpriteController.finishDrag(false)

    expect(layer.items[1].worldX).toBe(301)
    expect(layer.items[1].worldY).toBe(20)
  end)
end)

describe("sprite_controller.lua - drag undo/redo", function()
  it("undoes and redoes a normal sprite move drag", function()
    local win, layer = makeWin()
    local ur = UndoRedoController.new(10)
    SpriteController.setSpriteSelection(layer, { 1 })

    SpriteController.beginDrag(win, 1, 1, 0, 0, false)
    SpriteController.updateDrag(20, 12)
    local movedX = layer.items[1].worldX
    local movedY = layer.items[1].worldY
    SpriteController.finishDrag(nil, ur)

    expect(movedX).toNotBe(0)
    expect(movedY).toNotBe(0)

    expect(ur:undo({})).toBeTruthy()
    expect(layer.items[1].worldX).toBe(0)
    expect(layer.items[1].worldY).toBe(0)

    expect(ur:redo({})).toBeTruthy()
    expect(layer.items[1].worldX).toBe(movedX)
    expect(layer.items[1].worldY).toBe(movedY)
  end)

  it("undoes and redoes a sprite copy drag", function()
    local win, layer = makeWin()
    local ur = UndoRedoController.new(10)
    SpriteController.setSpriteSelection(layer, { 1 })

    SpriteController.beginDrag(win, 1, 1, 0, 0, true)
    SpriteController.updateDrag(20, 12)
    SpriteController.finishDrag(nil, ur)

    expect(#layer.items).toBe(3)
    local clone = layer.items[3]
    expect(clone.removed).toNotBe(true)

    expect(ur:undo({})).toBeTruthy()
    expect(clone.removed).toBe(true)

    expect(ur:redo({})).toBeTruthy()
    expect(clone.removed).toBe(false)
  end)
end)

describe("sprite_controller.lua - shared OAM item sync", function()
  it("syncs dx/dy and world position across oam_animation layers during drag", function()
    local win, layer1, layer3, s1, s3 = makeOAMWinWithSharedSprite()
    SpriteController.setSpriteSelection(layer1, { 1 })

    SpriteController.beginDrag(win, 1, 1, 0, 0, false)
    SpriteController.updateDrag(40, 44)
    SpriteController.finishDrag(false)

    expect(s1.dx).toBe(s3.dx)
    expect(s1.dy).toBe(s3.dy)
    expect(s1.worldX).toBe(s3.worldX)
    expect(s1.worldY).toBe(s3.worldY)
    expect(layer3.items[1].hasMoved).toBe(s1.hasMoved)
  end)

  it("keeps shared OAM item instances in sync on drag undo/redo", function()
    local win, layer1, _, s1, s3 = makeOAMWinWithSharedSprite()
    local ur = UndoRedoController.new(10)
    SpriteController.setSpriteSelection(layer1, { 1 })

    SpriteController.beginDrag(win, 1, 1, 0, 0, false)
    SpriteController.updateDrag(40, 44)
    SpriteController.finishDrag(nil, ur)

    expect(s1.worldX).toBe(s3.worldX)
    expect(s1.worldY).toBe(s3.worldY)
    expect(s1.dx).toBe(s3.dx)
    expect(s1.dy).toBe(s3.dy)

    expect(ur:undo({})).toBeTruthy()
    expect(s1.worldX).toBe(20)
    expect(s1.worldY).toBe(30)
    expect(s3.worldX).toBe(20)
    expect(s3.worldY).toBe(30)
    expect(s1.dx).toBe(0)
    expect(s3.dx).toBe(0)

    expect(ur:redo({})).toBeTruthy()
    expect(s1.worldX).toBe(s3.worldX)
    expect(s1.worldY).toBe(s3.worldY)
    expect(s1.dx).toBe(s3.dx)
    expect(s1.dy).toBe(s3.dy)
  end)

  it("syncs palette/mirror attributes across shared OAM items by startAddr", function()
    local win, _, _, s1, s3 = makeOAMWinWithSharedSprite()

    s1.paletteNumber = 4
    s1.mirrorX = true
    s1.mirrorY = true
    s1.attr = 0x20 -- preserve unrelated bits

    local count = SpriteController.syncSharedOAMSpriteState(win, s1, {
      syncPosition = false,
      syncVisual = true,
      syncAttr = true,
    })

    expect(count).toBe(2)
    expect(s3.paletteNumber).toBe(4)
    expect(s3.mirrorX).toBe(true)
    expect(s3.mirrorY).toBe(true)
    expect(s3.attr).toBe(0xE3) -- 0x20 + mirror bits (0xC0) + palette bits (0x03)
  end)

  it("syncs shared OAM state across different oam_animation windows", function()
    local winA, _, _, sA, sAOther = makeOAMWinWithSharedSprite()
    local sB = {
      bank = 0, tile = 3, startAddr = 0x1234,
      baseX = 20, baseY = 30, worldX = 20, worldY = 30, x = 20, y = 30,
      dx = 0, dy = 0, attr = 0x00, paletteNumber = 1, mirrorX = false, mirrorY = false,
    }
    local winB = {
      kind = "oam_animation",
      layers = {
        { kind = "sprite", mode = "8x8", items = { sB } },
      },
      _closed = false,
      _minimized = false,
    }
    local wm = {
      getWindows = function()
        return { winA, winB }
      end,
    }
    winA._wm = wm
    winB._wm = wm

    sA.worldX = 25
    sA.worldY = 28
    sA.x = 25
    sA.y = 28
    sA.dx = 5
    sA.dy = -2
    sA.paletteNumber = 4
    sA.mirrorX = true
    sA.mirrorY = false
    sA.attr = 0x20

    local count = SpriteController.syncSharedOAMSpriteState(winA, sA, {
      syncPosition = true,
      syncVisual = true,
      syncAttr = true,
    })

    expect(count).toBe(3)

    expect(sAOther.worldX).toBe(25)
    expect(sAOther.worldY).toBe(28)
    expect(sB.worldX).toBe(25)
    expect(sB.worldY).toBe(28)

    expect(sAOther.paletteNumber).toBe(4)
    expect(sAOther.mirrorX).toBe(true)
    expect(sAOther.mirrorY).toBe(false)
    expect(sB.paletteNumber).toBe(4)
    expect(sB.mirrorX).toBe(true)
    expect(sB.mirrorY).toBe(false)

    expect(sAOther.attr).toBe(sA.attr)
    expect(sB.attr).toBe(sA.attr)
  end)

  it("syncs shared OAM state to minimized oam_animation windows too", function()
    local winA, _, _, sA = makeOAMWinWithSharedSprite()
    local sB = {
      bank = 0, tile = 3, startAddr = 0x1234,
      baseX = 20, baseY = 30, worldX = 20, worldY = 30, x = 20, y = 30,
      dx = 0, dy = 0, attr = 0x00, paletteNumber = 1, mirrorX = false, mirrorY = false,
    }
    local winB = {
      kind = "oam_animation",
      layers = {
        { kind = "sprite", mode = "8x8", items = { sB } },
      },
      _closed = false,
      _minimized = true,
    }
    local wm = {
      getWindows = function()
        return { winA, winB }
      end,
    }
    winA._wm = wm
    winB._wm = wm

    sA.mirrorX = true
    sA._mirrorXOverrideSet = true
    sA.attr = 0x40

    local count = SpriteController.syncSharedOAMSpriteState(winA, sA, {
      syncPosition = false,
      syncVisual = true,
      syncAttr = true,
    })

    expect(count).toBe(3)
    expect(sB.mirrorX).toBe(true)
    expect(sB.attr).toBe(sA.attr)
  end)
end)

describe("sprite_controller.lua - oam animation restrictions", function()
  it("applies ctrl+drag copy rules by window kind (static/animation copy, oam no-copy)", function()
    local cases = {
      { kind = "static_art", shouldClone = true },
      { kind = "animation", shouldClone = true },
      { kind = "oam_animation", shouldClone = false },
    }

    for _, case in ipairs(cases) do
      local win, layer = makeWin()
      win.kind = case.kind
      SpriteController.setSpriteSelection(layer, { 1 })

      local countBefore = #layer.items
      SpriteController.beginDrag(win, 1, 1, 0, 0, true)

      if case.shouldClone then
        expect(#layer.items).toBe(countBefore + 1)
      else
        expect(#layer.items).toBe(countBefore)
      end

      SpriteController.endDrag()
    end
  end)

  it("does not duplicate sprites on ctrl+drag copy in oam_animation windows", function()
    local win, layer1 = makeOAMWinWithSharedSprite()
    SpriteController.setSpriteSelection(layer1, { 1 })

    local countBefore = #layer1.items
    SpriteController.beginDrag(win, 1, 1, 0, 0, true)
    expect(#layer1.items).toBe(countBefore) -- no clone created

    SpriteController.updateDrag(40, 44)
    SpriteController.finishDrag(true)

    expect(#layer1.items).toBe(countBefore)
    expect(layer1.items[1].worldX).toNotBe(20) -- still moved as normal drag
  end)
end)
