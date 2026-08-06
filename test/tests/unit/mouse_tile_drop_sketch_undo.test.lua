local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local function makeSketchReflectWin(opts)
  opts = opts or {}
  local cols = opts.cols or 32
  local rows = opts.rows or 30
  local bytes = {}
  for i = 1, cols * rows do
    bytes[i] = 0
  end
  -- Distinct bytes for swap source/dest.
  bytes[1] = 0x11 -- col 0, row 0
  bytes[2] = 0x22 -- col 1, row 0

  local layer = { kind = "canvas", items = {} }

  local win = {
    kind = "sketch_canvas",
    _closed = false,
    x = 0,
    y = 0,
    zoom = 1,
    cellW = 8,
    cellH = 8,
    cols = cols,
    rows = rows,
    scrollCol = 0,
    scrollRow = 0,
    linkedPatternTableWindowId = "pt-1",
    tilesPool = { { pixels = {} } },
    nametableBytes = bytes,
    layers = { layer },
    getActiveLayerIndex = function()
      return 1
    end,
    getLayer = function()
      return layer
    end,
    isInHeader = function()
      return false
    end,
    -- Ephemeral handles (the bug path if recorder uses get/set).
    get = function(self, col, row, _)
      local idx = row * cols + col + 1
      local byte = self.nametableBytes[idx] or 0
      return { kind = "sketch_nt", id = byte, poolIndex = byte }
    end,
    set = function(self, col, row, item, _)
      -- Wrong store for Tile-mode reflect; used to detect regressions.
      layer.items[row * cols + col + 1] = item
      self._setCalls = (self._setCalls or 0) + 1
    end,
    setNametableByteAt = function(self, col, row, byteVal, _, _)
      local idx = row * cols + col + 1
      self.nametableBytes[idx] = math.floor(tonumber(byteVal) or 0)
      self._ntSetCalls = (self._ntSetCalls or 0) + 1
    end,
    swapNametableBytesAt = function(self, c1, r1, c2, r2)
      local i1 = r1 * cols + c1 + 1
      local i2 = r2 * cols + c2 + 1
      local a = self.nametableBytes[i1]
      self.nametableBytes[i1] = self.nametableBytes[i2]
      self.nametableBytes[i2] = a
      self._swapCalls = (self._swapCalls or 0) + 1
      return true
    end,
    setSelected = function(self, col, row, li)
      self._sel = { col = col, row = row, li = li }
    end,
    toGridCoords = function(_, x, y)
      if y < 0 or y >= 8 then
        return false
      end
      local col = math.floor(x / 8)
      if col >= 0 and col < cols then
        return true, col, 0, 0, 0
      end
      return false
    end,
  }
  return win
end

describe("mouse_tile_drop_controller.lua - sketch tile-mode swap undo", function()
  it("records nametable bytes so undo/redo restores sketch reflect layout", function()
    local win = makeSketchReflectWin()
    local pt = { id = "pt-1", kind = "pattern_table", _closed = false }
    local ur = UndoRedoController.new(20)
    local app = {
      undoRedo = ur,
      appEditState = { tilesPool = win.tilesPool },
    }

    local prevCtx = rawget(_G, "ctx")
    rawset(_G, "ctx", {
      getMode = function()
        return "tile"
      end,
      app = app,
      wm = function()
        return {
          windows = { win, pt },
          findWindowById = function(_, id)
            if id == "pt-1" then
              return pt
            end
          end,
        }
      end,
    })

    expect(WindowCaps.isSketchReflectNametable(win)).toBe(true)

    local cleared = false
    local env = {
      drag = {
        active = true,
        item = win:get(0, 0, 1),
        srcWin = win,
        srcCol = 0,
        srcRow = 0,
        srcLayer = 1,
        copyMode = false,
      },
      ctx = {
        app = app,
      },
      clearDragState = function()
        cleared = true
      end,
      markUnsaved = function() end,
    }

    local wm = {
      windowAt = function()
        return win
      end,
      setFocus = function() end,
    }

    -- Drop onto col 1, row 0.
    expect(MouseTileDropController.handleTileDrop(env, 8 + 1, 1, wm)).toBe(true)
    expect(cleared).toBe(true)
    expect(win._swapCalls).toBe(1)
    expect(win.nametableBytes[1]).toBe(0x22)
    expect(win.nametableBytes[2]).toBe(0x11)

    local event = ur.stack[#ur.stack]
    expect(event).toBeTruthy()
    expect(event.type).toBe("tile_drag")
    expect(#event.changes).toBe(2)
    for _, ch in ipairs(event.changes) do
      expect(ch.isNametableByte).toBe(true)
      expect(type(ch.before)).toBe("number")
      expect(type(ch.after)).toBe("number")
    end

    expect(ur:undo(app)).toBeTruthy()
    expect(win.nametableBytes[1]).toBe(0x11)
    expect(win.nametableBytes[2]).toBe(0x22)
    expect((win._setCalls or 0)).toBe(0)
    expect((win._ntSetCalls or 0) >= 2).toBe(true)

    expect(ur:redo(app)).toBeTruthy()
    expect(win.nametableBytes[1]).toBe(0x22)
    expect(win.nametableBytes[2]).toBe(0x11)

    rawset(_G, "ctx", prevCtx)
  end)
end)
