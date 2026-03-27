local WM = require("controllers.window.window_controller")

describe("window_controller.lua - new window creation variants", function()
  local previousCtx

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = nil
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("creates static tile windows as static_art", function()
    local wm = WM.new()
    local win = wm:createTileWindow({
      animated = false,
      cols = 8,
      rows = 8,
    })

    expect(win.kind).toBe("static_art")
    expect(win.showGrid).toBe("chess")
    expect(#win.layers).toBe(1)
    expect(win.layers[1].kind).toBe("tile")
    expect(win.layers[1].name).toBe("Layer 1")
    expect(wm:getFocus()).toBe(win)
  end)

  it("creates static sprite windows as static_art", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({
      animated = false,
      cols = 8,
      rows = 8,
    })

    expect(win.kind).toBe("static_art")
    expect(#win.layers).toBe(1)
    expect(win.layers[1].kind).toBe("sprite")
    expect(win.layers[1].mode).toBe("8x8")
    expect(win.layers[1].originX).toBe(0)
    expect(win.layers[1].originY).toBe(0)
    expect(wm:getFocus()).toBe(win)
  end)

  it("creates animated tile windows as animation with tile frames", function()
    local wm = WM.new()
    local win = wm:createTileWindow({
      animated = true,
      numFrames = 3,
      cols = 8,
      rows = 8,
    })

    expect(win.kind).toBe("animation")
    expect(#win.layers).toBe(3)
    expect(win.layers[1].kind).toBe("tile")
    expect(win.layers[2].kind).toBe("tile")
    expect(win.layers[3].kind).toBe("tile")
    expect(win.layers[1].name).toBe("Frame 1")
    expect(win.layers[2].name).toBe("Frame 2")
    expect(win.layers[3].name).toBe("Frame 3")
    expect(wm:getFocus()).toBe(win)
  end)

  it("creates animated sprite windows as animation with sprite frames", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({
      animated = true,
      numFrames = 3,
      spriteMode = "8x16",
      cols = 8,
      rows = 8,
    })

    expect(win.kind).toBe("animation")
    expect(#win.layers).toBe(3)
    expect(win.layers[1].kind).toBe("sprite")
    expect(win.layers[2].kind).toBe("sprite")
    expect(win.layers[3].kind).toBe("sprite")
    expect(win.layers[1].mode).toBe("8x16")
    expect(win.layers[2].mode).toBe("8x16")
    expect(win.layers[3].mode).toBe("8x16")
    expect(win.layers[1].name).toBe("Frame 1")
    expect(win.layers[2].name).toBe("Frame 2")
    expect(win.layers[3].name).toBe("Frame 3")

    local inserted = win:addLayerAfterActive({ name = "Frame 4" })
    expect(inserted).toBe(2)
    expect(win.layers[2].kind).toBe("sprite")
    expect(win.layers[2].mode).toBe("8x16")

    expect(wm:getFocus()).toBe(win)
  end)

  it("creates OAM animated sprite windows as oam_animation with sprite frames", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({
      animated = true,
      oamBacked = true,
      numFrames = 2,
      spriteMode = "8x8",
      cols = 8,
      rows = 8,
    })

    expect(win.kind).toBe("oam_animation")
    expect(#win.layers).toBe(2)
    expect(win.layers[1].kind).toBe("sprite")
    expect(win.layers[2].kind).toBe("sprite")
    expect(win.layers[1].mode).toBe("8x8")
    expect(win.layers[1].originX).toBe(0)
    expect(win.layers[1].originY).toBe(0)

    local inserted = win:addLayerAfterActive({ name = "Frame 3" })
    expect(inserted).toBe(2)
    expect(win.layers[2].kind).toBe("sprite")

    expect(wm:getFocus()).toBe(win)
  end)
end)

describe("window_controller.lua - collapseAll", function()
  local previousCtx

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = nil
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("zooms windows out before collapsing", function()
    local wm = WM.new()

    local w1 = wm:createTileWindow({
      animated = false,
      cols = 8,
      rows = 8,
      zoom = 3,
    })
    local w2 = wm:createTileWindow({
      animated = false,
      cols = 8,
      rows = 8,
      zoom = 4,
    })

    expect(w1.zoom).toBe(3)
    expect(w2.zoom).toBe(4)

    wm:collapseAll({
      areaX = 0,
      areaY = 30,
      areaH = 120,
      gapX = 8,
      gapY = 2,
    })

    -- 8x8 visible tiles at 1x are 64x64, which is allowed by the current min-size guard.
    expect(w1.zoom).toBe(1)
    expect(w2.zoom).toBe(1)
    expect(w1._collapsed).toBe(true)
    expect(w2._collapsed).toBe(true)
  end)

  it("respects each window minimum zoom while collapsing", function()
    local wm = WM.new()

    local w = {
      _closed = false,
      _collapsed = false,
      title = "Zoom limit",
      headerH = 15,
      x = 0,
      y = 0,
      zoom = 4,
      _minZoom = 2,
      setScroll = function(self, c, r)
        self.scrollCol = c
        self.scrollRow = r
      end,
      addZoomLevel = function(self, delta)
        if delta >= 0 then return end
        if self.zoom > self._minZoom then
          self.zoom = self.zoom - 1
        end
      end,
      getZoomLevel = function(self)
        return self.zoom
      end,
      getScreenRect = function(self)
        return self.x, self.y, 20, 40
      end,
    }

    wm.windows = { w }

    wm:collapseAll({
      areaX = 0,
      areaY = 30,
      areaH = 120,
      gapX = 8,
      gapY = 2,
    })

    expect(w.zoom).toBe(2)
    expect(w._collapsed).toBe(true)
  end)

  it("uses first window width as fixed column step when wrapping", function()
    local wm = WM.new()

    local function makeWindow(width)
      return {
        _closed = false,
        _collapsed = false,
        headerH = 15,
        x = 0,
        y = 0,
        scrollCol = 5,
        scrollRow = 6,
        setScroll = function(self, c, r)
          self.scrollCol = c
          self.scrollRow = r
        end,
        getScreenRect = function(self)
          return self.x, self.y, width, 40
        end,
      }
    end

    -- First column contains windows 1 and 2. Window 2 is much wider than window 1.
    -- Wrapping to window 3 should still use window 1 width for the column stride.
    local w1 = makeWindow(20)
    local w2 = makeWindow(80)
    local w3 = makeWindow(30)

    wm.windows = { w1, w2, w3 }

    wm:collapseAll({
      areaX = 0,
      areaY = 30,
      areaH = 40, -- fits 2 headers, 3rd wraps
      gapX = 8,
      gapY = 2,
    })

    expect(w1.x).toBe(0)
    expect(w2.x).toBe(0)
    expect(w3.x).toBe(28) -- 20 (first window width) + 8 gap
    expect(w1.scrollCol).toBe(0)
    expect(w2.scrollRow).toBe(0)
  end)

  it("orders windows alphabetically by title when collapsing", function()
    local wm = WM.new()

    local function makeWindow(title)
      return {
        _closed = false,
        _collapsed = false,
        title = title,
        headerH = 15,
        x = 0,
        y = 0,
        setScroll = function(self, c, r)
          self.scrollCol = c
          self.scrollRow = r
        end,
        getScreenRect = function(self)
          return self.x, self.y, 20, 40
        end,
      }
    end

    local w1 = makeWindow("Beta")
    local w2 = makeWindow("alpha")
    local w3 = makeWindow("Gamma")
    wm.windows = { w1, w2, w3 }

    wm:collapseAll({
      areaX = 0,
      areaY = 30,
      areaH = 120,
      gapX = 8,
      gapY = 2,
    })

    expect(w2.y).toBe(45) -- alpha
    expect(w1.y).toBe(62) -- Beta
    expect(w3.y).toBe(79) -- Gamma
  end)
end)

describe("window_controller.lua - sort helpers", function()
  it("sorts open windows by title and kind in both directions", function()
    local wm = WM.new()
    local w1 = { title = "Beta", kind = "animation", _closed = false, _minimized = false }
    local w2 = { title = "Alpha", kind = "static_art", _closed = false, _minimized = false }
    local w3 = { title = "Gamma", kind = "palette", _closed = false, _minimized = true } -- can remain minimized
    local w4 = { title = "Closed", kind = "chr", _closed = true, _minimized = false }
    wm.windows = { w1, w2, w3, w4 }

    expect(wm:sortWindowsByTitle(false)).toBeTruthy()
    expect(wm.windows[1]).toBe(w2)
    expect(wm.windows[2]).toBe(w1)
    expect(wm.windows[3]).toBe(w3)
    expect(wm.windows[4]).toBe(w4) -- closed stays at end

    expect(wm:sortWindowsByTitle(true)).toBeTruthy()
    expect(wm.windows[1]).toBe(w3)
    expect(wm.windows[2]).toBe(w1)
    expect(wm.windows[3]).toBe(w2)

    expect(wm:sortWindowsByKind(false)).toBeTruthy()
    expect(wm.windows[1]).toBe(w1) -- animation
    expect(wm.windows[2]).toBe(w3) -- palette
    expect(wm.windows[3]).toBe(w2) -- static_art

    expect(wm:sortWindowsByKind(true)).toBeTruthy()
    expect(wm.windows[1]).toBe(w2) -- static_art
    expect(wm.windows[2]).toBe(w3) -- palette
    expect(wm.windows[3]).toBe(w1) -- animation
    expect(wm.windows[4]).toBe(w4)
  end)
end)

describe("window_controller.lua - close and reopen", function()
  it("closes a focused window and can reopen it with focus restored", function()
    local wm = WM.new()
    local removeCalls = 0
    wm.taskbar = {
      removeMinimizedWindow = function()
        removeCalls = removeCalls + 1
      end,
    }

    local w1 = { title = "A", _closed = false, _minimized = false }
    local w2 = { title = "B", _closed = false, _minimized = false }
    wm.windows = { w1, w2 }
    wm.focused = w2

    expect(wm:closeWindow(w2)).toBe(true)
    expect(w2._closed).toBe(true)
    expect(w2._minimized).toBe(false)
    expect(wm:getFocus()).toBe(w1)
    expect(removeCalls).toBe(1)

    expect(wm:reopenWindow(w2, { focus = true })).toBe(true)
    expect(w2._closed).toBe(false)
    expect(wm:getFocus()).toBe(w2)
  end)
end)

describe("window_controller.lua - cascade", function()
  it("starts a new cascade after 14 items", function()
    local wm = WM.new()

    local function makeWindow(areaCols)
      return {
        _closed = false,
        _collapsed = true,
        headerH = 15,
        x = 0,
        y = 0,
        cols = areaCols,
        rows = 1,
        cellW = 1,
        cellH = 1,
        zoom = 1,
        getScreenRect = function(self)
          return self.x, self.y, 40, 40
        end,
      }
    end

    local windows = {}
    for i = 1, 15 do
      windows[i] = makeWindow(100 - i)
    end
    wm.windows = windows

    wm:cascade({
      startX = 30,
      startY = 45,
      offsetX = 15,
      offsetY = 15,
      cascadeShiftX = 80,
      maxItemsPerCascade = 14,
    })

    expect(windows[1].x).toBe(30)
    expect(windows[1].y).toBe(45)
    expect(windows[14].x).toBe(30 + (13 * 15))
    expect(windows[14].y).toBe(45 + (13 * 15))
    expect(windows[15].x).toBe(110) -- 30 + 80
    expect(windows[15].y).toBe(45)
    expect(windows[1]._collapsed).toBe(false)
    expect(windows[15]._collapsed).toBe(false)
  end)
end)
