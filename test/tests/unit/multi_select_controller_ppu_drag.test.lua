local MultiSelectController = require("controllers.input_support.multi_select_controller")

describe("multi_select_controller.lua - ppu tile group drag", function()
  it("moves PPU nametable bytes for tile groups without dropping to empty bytes", function()
    local layer = {
      kind = "tile",
      items = {},
    }

    local win = {
      kind = "ppu_frame",
      cols = 8,
      rows = 4,
      nametableBytes = {},
      layers = { layer },
      setSelected = function(self, col, row, li)
        self._selected = { col = col, row = row, li = li }
      end,
    }

    local function idx(col, row)
      return row * win.cols + col + 1
    end

    for i = 1, win.cols * win.rows do
      win.nametableBytes[i] = 0x00
    end

    -- Two adjacent source tiles (e.g. nose and mouth) at (2,1) and (3,1).
    win.nametableBytes[idx(2, 1)] = 0x31
    win.nametableBytes[idx(3, 1)] = 0x32

    -- Minimal PPU writer used by applyTileDragGroup.
    win.setNametableByteAt = function(self, col, row, byteVal)
      self.nametableBytes[idx(col, row)] = byteVal
    end

    local group = {
      entries = {
        { srcCol = 2, srcRow = 1, offsetCol = 0, offsetRow = 0, item = { index = nil } },
        { srcCol = 3, srcRow = 1, offsetCol = 1, offsetRow = 0, item = { index = nil } },
      },
    }

    -- Move group to the right into empty cells (destination starts at col 5).
    local result = MultiSelectController.applyTileDragGroup(win, 1, group, 5, 1, {
      copyMode = false,
      srcWin = win,
      srcLayer = 1,
    })

    expect(result).toBeTruthy()
    expect(result.count).toBe(2)

    -- Source cells cleared.
    expect(win.nametableBytes[idx(2, 1)]).toBe(0x00)
    expect(win.nametableBytes[idx(3, 1)]).toBe(0x00)

    -- Destination keeps original bytes (no transparent/empty regression).
    expect(win.nametableBytes[idx(5, 1)]).toBe(0x31)
    expect(win.nametableBytes[idx(6, 1)]).toBe(0x32)
  end)

  it("clears PPU group-drag sources to byte 0x00", function()
    local layer = {
      kind = "tile",
      items = {},
    }

    local win = {
      kind = "ppu_frame",
      cols = 8,
      rows = 4,
      nametableBytes = {},
      layers = { layer },
    }

    local function idx(col, row)
      return row * win.cols + col + 1
    end

    for i = 1, win.cols * win.rows do
      win.nametableBytes[i] = 0xAB
    end

    win.nametableBytes[idx(2, 1)] = 0x31
    win.nametableBytes[idx(3, 1)] = 0x32

    win.setNametableByteAt = function(self, col, row, byteVal)
      self.nametableBytes[idx(col, row)] = byteVal
    end

    local group = {
      entries = {
        { srcCol = 2, srcRow = 1, offsetCol = 0, offsetRow = 0, item = {} },
        { srcCol = 3, srcRow = 1, offsetCol = 1, offsetRow = 0, item = {} },
      },
    }

    local result = MultiSelectController.applyTileDragGroup(win, 1, group, 5, 1, {
      copyMode = false,
      srcWin = win,
      srcLayer = 1,
    })

    expect(result).toBeTruthy()
    expect(win.nametableBytes[idx(2, 1)]).toBe(0x00)
    expect(win.nametableBytes[idx(3, 1)]).toBe(0x00)
    expect(win.nametableBytes[idx(5, 1)]).toBe(0x31)
    expect(win.nametableBytes[idx(6, 1)]).toBe(0x32)
  end)

  it("applies PPU group drag when anchor column is 0 (Lua falsy guard regression)", function()
    local layer = {
      kind = "tile",
      items = {},
    }

    local win = {
      kind = "ppu_frame",
      cols = 8,
      rows = 4,
      nametableBytes = {},
      layers = { layer },
    }

    local function idx(col, row)
      return row * win.cols + col + 1
    end

    for i = 1, win.cols * win.rows do
      win.nametableBytes[i] = 0x00
    end

    win.nametableBytes[idx(5, 1)] = 0x41

    win.setNametableByteAt = function(self, col, row, byteVal)
      self.nametableBytes[idx(col, row)] = byteVal
    end

    local group = {
      entries = {
        { srcCol = 5, srcRow = 1, offsetCol = 0, offsetRow = 0, item = {} },
      },
    }

    local result = MultiSelectController.applyTileDragGroup(win, 1, group, 0, 1, {
      copyMode = false,
      srcWin = win,
      srcLayer = 1,
    })

    expect(result).toBeTruthy()
    expect(result.count).toBe(1)
    expect(win.nametableBytes[idx(5, 1)]).toBe(0x00)
    expect(win.nametableBytes[idx(0, 1)]).toBe(0x41)
  end)

  it("moves PPU nametable bytes between two PPU frame windows without materialize/CHR tile 0", function()
    local function makeWin()
      local layer = { kind = "tile", items = {} }
      local w = {
        kind = "ppu_frame",
        cols = 8,
        rows = 4,
        nametableBytes = {},
        layers = { layer },
      }
      local function idx(col, row)
        return row * w.cols + col + 1
      end
      w._idx = idx
      for i = 1, w.cols * w.rows do
        w.nametableBytes[i] = 0x00
      end
      w.setNametableByteAt = function(self, col, row, byteVal)
        self.nametableBytes[self._idx(col, row)] = byteVal
      end
      return w
    end

    local winA = makeWin()
    local winB = makeWin()

    winA.nametableBytes[winA._idx(1, 1)] = 0x51
    winA.nametableBytes[winA._idx(2, 1)] = 0x52

    local group = {
      entries = {
        { srcCol = 1, srcRow = 1, offsetCol = 0, offsetRow = 0, item = { index = 0 } },
        { srcCol = 2, srcRow = 1, offsetCol = 1, offsetRow = 0, item = { index = 0 } },
      },
    }

    local result = MultiSelectController.applyTileDragGroup(winB, 1, group, 4, 2, {
      copyMode = false,
      srcWin = winA,
      srcLayer = 1,
    })

    expect(result).toBeTruthy()
    expect(result.count).toBe(2)
    expect(winA.nametableBytes[winA._idx(1, 1)]).toBe(0x00)
    expect(winA.nametableBytes[winA._idx(2, 1)]).toBe(0x00)
    expect(winB.nametableBytes[winB._idx(4, 2)]).toBe(0x51)
    expect(winB.nametableBytes[winB._idx(5, 2)]).toBe(0x52)
  end)
end)

describe("multi_select_controller.lua - oam animation sprite deletion restriction", function()
  it("blocks sprite deletion in oam_animation windows", function()
    local layer = {
      kind = "sprite",
      items = {
        { removed = false, bank = 1, tile = 1 },
      },
      selectedSpriteIndex = 1,
    }
    local win = {
      kind = "oam_animation",
      layers = { layer },
    }

    local result = MultiSelectController.deleteSpriteSelection(win, 1, nil)

    expect(result).toBeTruthy()
    expect(result.count).toBe(0)
    expect(result.status).toBe("Cannot delete sprites in OAM animation windows")
    expect(layer.items[1].removed).toBe(false)
    expect(layer.selectedSpriteIndex).toBe(1)
  end)
end)

describe("multi_select_controller.lua - oam marquee selection with layer origin", function()
  it("selects sprites using wrapped content coordinates when the layer has origin offsets", function()
    local layer = {
      kind = "sprite",
      originX = 248,
      originY = 250,
      mode = "8x8",
      items = {
        { worldX = 10, worldY = 12, removed = false },
        { worldX = 40, worldY = 40, removed = false },
      },
    }

    local win = {
      kind = "oam_animation",
      cellW = 8,
      cellH = 8,
      layers = { layer },
    }

    MultiSelectController.selectSpritesInRect(win, 1, {
      x1 = 0,
      y1 = 0,
      x2 = 24,
      y2 = 24,
    }, false)

    expect(layer.multiSpriteSelection).toBeTruthy()
    expect(layer.multiSpriteSelection[1]).toBe(true)
    expect(layer.multiSpriteSelection[2]).toBeNil()
    expect(layer.multiSpriteSelectionOrder).toEqual({ 1 })
    expect(layer.selectedSpriteIndex).toBe(1)
  end)
end)
