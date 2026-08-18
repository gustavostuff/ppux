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

  it("creates generic palette windows as palette", function()
    local wm = WM.new()
    local win = wm:createPaletteWindow({
      title = "Generic Palette",
    })

    expect(win.kind).toBe("palette")
    expect(win.isPalette).toBe(true)
    expect(win.title).toBe("Generic Palette")
    expect(win.rows).toBe(1)
    expect(win.cols).toBe(4)
    expect(win.activePalette).toBe(true)
    expect(win.showGrid).toBe("chess")
    expect(win.codes2D[0][0]).toBe("0F")
    expect(win.codes2D[0][3]).toBe("0F")
    expect(wm:getFocus()).toBe(win)
  end)

  it("creates ROM palette windows with unassigned cells by default", function()
    local previousCtx = rawget(_G, "ctx")
    _G.ctx = {
      app = {
        appEditState = {
          romRaw = string.rep(string.char(0x0F), 64),
        },
      },
    }

    local wm = WM.new()
    local win = wm:createRomPaletteWindow({
      title = "ROM Palette",
    })

    _G.ctx = previousCtx

    expect(win.kind).toBe("rom_palette")
    expect(win.isPalette).toBe(true)
    expect(win.title).toBe("ROM Palette")
    expect(win.rows).toBe(4)
    expect(win.cols).toBe(4)
    expect(win.activePalette).toBe(false)
    expect(win:isCellEditable(0, 0)).toBe(false)
    expect(win.paletteData.romColors[1][1]).toBe(false)
    expect(win.codes2D[0][0]).toBe("0F")
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

describe("window_controller.lua - mosaicAll", function()
  local previousCtx

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = nil
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("uncollapses windows and tiles them in title order", function()
    local wm = WM.new()

    local wA = wm:createTileWindow({
      animated = false,
      title = "Beta",
      cols = 8,
      rows = 8,
      zoom = 2,
    })
    local wB = wm:createTileWindow({
      animated = false,
      title = "Alpha",
      cols = 8,
      rows = 8,
      zoom = 2,
    })

    wA._collapsed = true
    wB._collapsed = true

    wm:mosaicAll({
      areaX = 0,
      areaY = 30,
      areaW = 900,
      areaH = 500,
      gapX = 4,
      gapY = 4,
      batchDispX = 15,
      batchDispY = 12,
    })

    expect(wB._collapsed).toBe(false)
    expect(wA._collapsed).toBe(false)
    expect(wB.x).toBeLessThan(wA.x)
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

describe("window_controller.lua - layoutCollapsedStacks", function()
  local previousCtx

  local function makeWindow(opts)
    opts = opts or {}
    return {
      _closed = false,
      _minimized = opts.minimized == true,
      _collapsed = false,
      title = opts.title or "Win",
      kind = opts.kind or "ppu_frame",
      headerH = opts.headerH or 15,
      x = opts.x or 400,
      y = opts.y or 400,
      width = opts.width or 20,
      setScroll = function(self, c, r)
        self.scrollCol = c
        self.scrollRow = r
      end,
      getScreenRect = function(self)
        return self.x, self.y, self.width, 40
      end,
    }
  end

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = nil
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("stacks non-minimized windows by title, top-to-bottom then left-to-right", function()
    local wm = WM.new()
    local wBeta = makeWindow({ title = "Beta" })
    local wAlpha = makeWindow({ title = "alpha" })
    local wGamma = makeWindow({ title = "Gamma" })
    local wMini = makeWindow({ title = "Mini", minimized = true, x = 90, y = 90 })
    wm.windows = { wBeta, wAlpha, wGamma, wMini }

    expect(wm:layoutCollapsedStacks({
      mode = "title",
      collapse = true,
      areaX = 0,
      areaY = 30,
      areaH = 40,
      areaW = 200,
      gapX = 8,
      gapY = 7,
      recordUndo = false,
    })).toBe(true)

    expect(wAlpha._collapsed).toBe(true)
    expect(wBeta._collapsed).toBe(true)
    expect(wGamma._collapsed).toBe(true)
    expect(wMini._collapsed).toBe(false)
    expect(wMini.x).toBe(90)
    expect(wMini.y).toBe(90)

    -- areaH=40 fits two 15px headers with 7px badge gap; Gamma wraps to column 2.
    -- Packed widths 20+8+20=48 fit in 200, so leftover is spread: last stack flush right.
    expect(wAlpha.x).toBe(wBeta.x)
    expect(wGamma.x).toBeGreaterThan(wAlpha.x)
    expect(wAlpha.x).toBe(0)
    expect(wGamma.x).toBe(180)
    expect(wAlpha.y).toBe(45)
    expect(wBeta.y).toBe(67)
    expect(wGamma.y).toBe(45)
  end)

  it("moves later stacks right so headers do not overlap, even off the viewport", function()
    local wm = WM.new()
    local w1 = makeWindow({ title = "A", width = 40 })
    local w2 = makeWindow({ title = "B", width = 40 })
    local w3 = makeWindow({ title = "C", width = 40 })
    wm.windows = { w1, w2, w3 }

    wm:layoutCollapsedStacks({
      mode = "title",
      areaX = 0,
      areaY = 0,
      areaH = 15,
      areaW = 50,
      gapX = 8,
      gapY = 2,
      recordUndo = false,
    })

    -- 3x40 plus gaps cannot fit in 50px: stubs cannot resize, so hang off the right.
    expect(w1.x).toBe(0)
    expect(w2.x).toBe(48)
    expect(w3.x).toBe(96)
    expect(w1.x + 40 + 8).toBe(w2.x)
    expect(w2.x + 40 + 8).toBe(w3.x)
    expect(w3.x + 40).toBeGreaterThan(50)
  end)

  it("shrinks every column together so the last stack stays on-screen", function()
    local wm = WM.new()
    local function gridWin(title)
      return {
        _closed = false,
        _minimized = false,
        _collapsed = false,
        title = title,
        kind = "ppu_frame",
        headerH = 15,
        x = 0,
        y = 0,
        zoom = 1,
        cellW = 8,
        cellH = 8,
        cols = 20,
        rows = 8,
        visibleCols = 5,
        visibleRows = 8,
        minWindowSize = 0,
        getScreenRect = function(self)
          return self.x, self.y, self.visibleCols * self.cellW * self.zoom, 40
        end,
      }
    end
    local w1 = gridWin("A")
    local w2 = gridWin("B")
    local w3 = gridWin("C")
    wm.windows = { w1, w2, w3 }

    wm:layoutCollapsedStacks({
      mode = "title",
      areaX = 0,
      areaY = 0,
      areaH = 15,
      areaW = 50,
      gapX = 8,
      gapY = 7,
      recordUndo = false,
    })

    local w1w = w1.visibleCols * 8
    local w2w = w2.visibleCols * 8
    local w3w = w3.visibleCols * 8
    expect(w1.visibleCols).toBeLessThan(5)
    expect(w2.visibleCols).toBeLessThan(5)
    expect(w3.visibleCols).toBeLessThan(5)
    expect(w2.x >= w1.x + w1w + 8).toBe(true)
    expect(w3.x >= w2.x + w2w + 8).toBe(true)
    expect(w3.x + w3w <= 50).toBe(true)
  end)

  it("puts each kind in its own header stack", function()
    local wm = WM.new()
    local ppuA = makeWindow({ title = "Frame B", kind = "ppu_frame" })
    local ppuB = makeWindow({ title = "Frame A", kind = "ppu_frame" })
    local pal = makeWindow({ title = "Colors", kind = "rom_palette" })
    wm.windows = { pal, ppuA, ppuB }

    wm:layoutCollapsedStacks({
      mode = "kind",
      collapse = true,
      areaX = 10,
      areaY = 20,
      areaH = 200,
      areaW = 400,
      gapX = 8,
      gapY = 2,
      recordUndo = false,
    })

    expect(ppuB.x).toBe(10)
    expect(ppuA.x).toBe(10)
    expect(ppuB.y).toBeLessThan(ppuA.y)
    expect(pal.x).toBe(390)
    expect(pal.y).toBe(35)
    expect(ppuA._collapsed).toBe(true)
    expect(pal._collapsed).toBe(true)
  end)

  it("skips layout when every open window is minimized", function()
    local wm = WM.new()
    local w = makeWindow({ title = "Only", minimized = true, x = 11, y = 22 })
    wm.windows = { w }
    expect(wm:layoutCollapsedStacks({
      mode = "title",
      recordUndo = false,
    })).toBe(false)
    expect(w.x).toBe(11)
    expect(w.y).toBe(22)
    expect(w._collapsed).toBe(false)
  end)

  it("does not shrink a window that already fits its column slot", function()
    local wm = WM.new()
    local w = makeWindow({ title = "Zoomed", width = 160 })
    w.zoom = 4
    w.cellW = 8
    w.cellH = 8
    w.cols = 5
    w.rows = 16
    w.visibleCols = 5
    w.visibleRows = 16
    w.minWindowSize = 64
    w.getScreenRect = function(self)
      return self.x, self.y, self.visibleCols * self.cellW * self.zoom, 40
    end
    w.resizeToMinimum = function(self)
      self.visibleCols = 2
      self.visibleRows = 2
    end
    wm.windows = { w }

    wm:layoutCollapsedStacks({
      mode = "title",
      collapse = true,
      areaX = 0,
      areaY = 0,
      areaH = 120,
      areaW = 200,
      recordUndo = false,
    })

    -- 5*8*4=160 fits in a 200px single-column slot; do not min-resize.
    expect(w.visibleCols).toBe(5)
    expect(w.visibleRows).toBe(16)
    expect(w.zoom).toBe(4)
    expect(w.x).toBe(0)
    expect(w._collapsed).toBe(true)
  end)

  it("shrinks via resize when a header would overlap the next column", function()
    local wm = WM.new()
    local function gridWin(title)
      return {
        _closed = false,
        _minimized = false,
        _collapsed = false,
        title = title,
        kind = "ppu_frame",
        headerH = 15,
        x = 0,
        y = 0,
        zoom = 1,
        cellW = 8,
        cellH = 8,
        cols = 32,
        rows = 30,
        visibleCols = 32,
        visibleRows = 30,
        minWindowSize = 64,
        getScreenRect = function(self)
          return self.x, self.y, self.visibleCols * self.cellW * self.zoom, 40
        end,
      }
    end
    local left = gridWin("A")
    local right = gridWin("B")
    wm.windows = { left, right }

    wm:layoutCollapsedStacks({
      mode = "title",
      areaX = 0,
      areaY = 0,
      areaH = 20,
      areaW = 200,
      gapX = 8,
      recordUndo = false,
    })

    -- Two columns: 32*8=256 overlaps the equal slot, so shrink, then stacks
    -- are shifted so the headers no longer overlap.
    expect(left.x).toBe(0)
    expect(left.visibleCols).toBeLessThan(32)
    expect(right.visibleCols).toBeLessThan(32)
    local leftW = left.visibleCols * 8
    local rightW = right.visibleCols * 8
    expect(right.x >= left.x + leftW + 8).toBe(true)
    expect(right.x + rightW).toBe(200)
  end)

  it("zooms in when the next zoom still fits the column slot", function()
    local wm = WM.new()
    local steps = { 1, 2, 3, 4, 8 }
    local w = makeWindow({ title = "Small", width = 16 })
    w.zoom = 1
    w.cellW = 8
    w.cellH = 8
    w.cols = 4
    w.rows = 4
    w.visibleCols = 2
    w.visibleRows = 2
    w.minWindowSize = 0
    w.getZoomLevel = function(self)
      return self.zoom
    end
    w.addZoomLevel = function(self, delta)
      local idx = 1
      for i, step in ipairs(steps) do
        if step == self.zoom then
          idx = i
          break
        end
      end
      idx = math.max(1, math.min(#steps, idx + (delta or 0)))
      self.zoom = steps[idx]
    end
    w.getScreenRect = function(self)
      return self.x, self.y, self.visibleCols * self.cellW * self.zoom, 40
    end
    wm.windows = { w }

    wm:layoutCollapsedStacks({
      mode = "title",
      areaX = 0,
      areaY = 0,
      areaH = 120,
      areaW = 80,
      recordUndo = false,
    })

    -- 2*8*1=16; zoom 4 → 64 fits in 80; zoom 8 → 128 does not.
    expect(w.zoom).toBe(4)
    expect(w.x).toBe(0)
  end)

  it("does not resize palette windows even when they overlap a slot", function()
    local wm = WM.new()
    local pal = makeWindow({ title = "Colors", kind = "rom_palette", width = 300 })
    pal.zoom = 2
    pal.cellW = 24
    pal.cellH = 16
    pal.cols = 4
    pal.rows = 4
    pal.visibleCols = 4
    pal.visibleRows = 4
    pal.resizeToMinimum = function(self)
      self.visibleCols = 1
      self.visibleRows = 1
    end
    pal.addZoomLevel = function(self, delta)
      self.zoom = (self.zoom or 1) + (delta or 0)
    end
    pal.getScreenRect = function(self)
      return self.x, self.y, self.visibleCols * self.cellW * self.zoom, 40
    end
    local frame = makeWindow({ title = "Frame", kind = "ppu_frame", width = 32 })
    frame.zoom = 1
    frame.cellW = 8
    frame.cellH = 8
    frame.cols = 8
    frame.rows = 8
    frame.visibleCols = 4
    frame.visibleRows = 4
    frame.minWindowSize = 0
    frame.getScreenRect = function(self)
      return self.x, self.y, self.visibleCols * self.cellW * self.zoom, 40
    end
    wm.windows = { pal, frame }

    wm:layoutCollapsedStacks({
      mode = "kind",
      collapse = true,
      areaX = 0,
      areaY = 0,
      areaH = 200,
      areaW = 200,
      gapX = 8,
      recordUndo = false,
    })

    expect(pal.visibleCols).toBe(4)
    expect(pal.visibleRows).toBe(4)
    expect(pal.zoom).toBe(2)
    expect(frame._collapsed).toBe(true)
    expect(pal._collapsed).toBe(true)
    local frameW = frame.visibleCols * frame.cellW * frame.zoom
    expect(pal.x >= frame.x + frameW + 8).toBe(true)
  end)

  it("sorts and stacks without collapsing when collapse is false", function()
    local wm = WM.new()
    local wBeta = makeWindow({ title = "Beta" })
    local wAlpha = makeWindow({ title = "Alpha" })
    wm.windows = { wBeta, wAlpha }

    expect(wm:layoutCollapsedStacks({
      mode = "title",
      collapse = false,
      areaX = 0,
      areaY = 30,
      areaH = 200,
      areaW = 200,
      gapX = 8,
      gapY = 7,
      recordUndo = false,
    })).toBe(true)

    expect(wAlpha._collapsed).toBe(false)
    expect(wBeta._collapsed).toBe(false)
    expect(wAlpha.x).toBe(wBeta.x)
    expect(wAlpha.x).toBe(0)
    expect(wAlpha.y).toBe(45)
    -- Same header-stack spacing as collapsed layout (bodies overlap).
    expect(wBeta.y).toBe(67)
    expect(wm.windows[1]).toBe(wAlpha)
    expect(wm.windows[2]).toBe(wBeta)
    expect(wAlpha._z).toBeLessThan(wBeta._z)
  end)

  it("raises z-index down each column so titles stay in front", function()
    local wm = WM.new()
    local wBeta = makeWindow({ title = "Beta" })
    local wAlpha = makeWindow({ title = "Alpha" })
    local wGamma = makeWindow({ title = "Gamma" })
    wm.windows = { wGamma, wBeta, wAlpha }

    wm:layoutCollapsedStacks({
      mode = "title",
      collapse = false,
      areaX = 0,
      areaY = 30,
      areaH = 40,
      areaW = 200,
      gapX = 8,
      gapY = 7,
      recordUndo = false,
    })

    -- Col1 Alpha/Beta, col2 Gamma. Lower in a column is higher z.
    expect(wAlpha.y).toBe(45)
    expect(wBeta.y).toBe(67)
    expect(wGamma.y).toBe(45)
    expect(wGamma.x).toBeGreaterThan(wAlpha.x)
    expect(wm.windows[1]).toBe(wAlpha)
    expect(wm.windows[2]).toBe(wBeta)
    expect(wm.windows[3]).toBe(wGamma)
    expect(wAlpha._z).toBeLessThan(wBeta._z)
    expect(wBeta._z).toBeLessThan(wGamma._z)
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

describe("window_controller.lua - grouped hidden windows", function()
  it("ignores grouped-hidden windows for interaction hit tests", function()
    local wm = WM.new()
    local w1 = wm:createTileWindow({
      animated = false,
      title = "A",
      x = 10,
      y = 10,
      cols = 2,
      rows = 2,
      cellW = 8,
      cellH = 8,
      zoom = 1,
    })
    local w2 = wm:createTileWindow({
      animated = false,
      title = "B",
      x = 10,
      y = 10,
      cols = 2,
      rows = 2,
      cellW = 8,
      cellH = 8,
      zoom = 1,
    })
    w2._groupHidden = true

    local found = wm:windowAt(12, 12)
    expect(found).toBe(w1)
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
