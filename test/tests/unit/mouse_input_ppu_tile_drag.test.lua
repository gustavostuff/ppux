local MouseInput = require("controllers.input.mouse_input")

local function makePpuWindow(opts)
  opts = opts or {}
  local cols = 4
  local layer = {
    kind = "tile",
    items = {},
    transparentTileByte = 0x00,
  }

  local function idx(col, row)
    return row * cols + col + 1
  end

  local function itemForByte(byte)
    return { index = byte, _byte = byte }
  end

  local win = {
    kind = "ppu_frame",
    _closed = false,
    x = 0,
    y = 0,
    zoom = 1,
    cellW = 8,
    cellH = 8,
    cols = cols,
    rows = 1,
    scrollCol = 0,
    scrollRow = 0,
    layers = { layer },
    nametableBytes = { 0x21, 0x00, 0x00, 0x00 },
    getActiveLayerIndex = function() return 1 end,
    getLayer = function(_, li) return layer end,
    isInHeader = function() return false end,
    get = function(_, col, row, _)
      return layer.items[idx(col, row)]
    end,
    set = function(self, col, row, item, _)
      local byte = (item and item._byte) or 0x00
      self.nametableBytes[idx(col, row)] = byte
      layer.items[idx(col, row)] = item and itemForByte(byte) or nil
    end,
    setNametableByteAt = function(self, col, row, byteVal, _, _)
      local byte = tonumber(byteVal) or 0x00
      self.nametableBytes[idx(col, row)] = byte
      layer.items[idx(col, row)] = itemForByte(byte)
    end,
    getStack = function(_, col, row, _)
      local item = layer.items[idx(col, row)]
      if item then return { item } end
      return nil
    end,
    removeAt = function(self, col, row, _, _)
      self.nametableBytes[idx(col, row)] = 0x00
      layer.items[idx(col, row)] = nil
    end,
    setSelected = function(self, col, row, li)
      self._sel = { col = col, row = row, li = li }
    end,
    clearSelected = function(self)
      self._sel = nil
    end,
    toGridCoords = function(_, x, y)
      if y < 0 or y >= 8 then return false end
      local col = math.floor(x / 20)
      if col >= 0 and col < cols then
        return true, col, 0, 0, 0
      end
      return false
    end,
  }

  if opts.withSwapCells then
    win.swapCells = function(self, c1, r1, c2, r2)
      local i1 = idx(c1, r1)
      local i2 = idx(c2, r2)
      local b1 = self.nametableBytes[i1]
      local b2 = self.nametableBytes[i2]
      self.nametableBytes[i1] = b2
      self.nametableBytes[i2] = b1
      layer.items[i1] = itemForByte(self.nametableBytes[i1])
      layer.items[i2] = itemForByte(self.nametableBytes[i2])
      self._swapCalls = (self._swapCalls or 0) + 1
    end
  end

  for col = 0, cols - 1 do
    win:setNametableByteAt(col, 0, win.nametableBytes[idx(col, 0)])
  end

  return win
end

describe("mouse_input.lua - ppu frame single-tile drag", function()
  local originalMouseIsDown

  beforeEach(function()
    if not _G.love then _G.love = {} end
    love.mouse = love.mouse or {}
    originalMouseIsDown = love.mouse.isDown
    love.mouse.isDown = function(btn) return btn == 1 end
  end)

  afterEach(function()
    if love and love.mouse then
      love.mouse.isDown = originalMouseIsDown
    end
  end)

  it("does not clear source nametable byte during drag activation", function()
    local ctrl = false
    local win = makePpuWindow()

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x >= 0 and x < 80 and y >= 0 and y < 8 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 and y >= 0 and y < 8 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 4, 1)
    MouseInput.mousemoved(25, 4, 15, 0)

    expect(win.nametableBytes[1]).toBe(0x21)
  end)

  it("moves bytes on drop instead of writing transparent source to destination", function()
    local ctrl = false
    local win = makePpuWindow()

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x >= 0 and x < 80 and y >= 0 and y < 8 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 and y >= 0 and y < 8 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 4, 1)
    MouseInput.mousemoved(25, 4, 15, 0)
    MouseInput.mousereleased(30, 4, 1)

    expect(win.nametableBytes[1]).toBe(0x00)
    expect(win.nametableBytes[2]).toBe(0x21)
  end)

  it("uses swapCells for same-window ppu moves when available", function()
    local ctrl = false
    local win = makePpuWindow({ withSwapCells = true })

    local focused = nil
    local wm = {
      setFocus = function(_, w) focused = w end,
      getFocus = function() return focused end,
      windowAt = function(_, x, y)
        if x >= 0 and x < 80 and y >= 0 and y < 8 then return win end
        return nil
      end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, {
      pending = false,
      active = false,
      ghostAlpha = 0.5,
    }, {}, {
      ctrlDown = function() return ctrl end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function(_, x, y, li)
        if x < 20 and y >= 0 and y < 8 then
          return true, 0, 0, win:get(0, 0, li)
        end
        return false
      end,
    })

    MouseInput.mousepressed(10, 4, 1)
    MouseInput.mousemoved(25, 4, 15, 0)
    MouseInput.mousereleased(30, 4, 1)

    expect(win._swapCalls).toBe(1)
    expect(win.nametableBytes[1]).toBe(0x00)
    expect(win.nametableBytes[2]).toBe(0x21)
  end)
end)
