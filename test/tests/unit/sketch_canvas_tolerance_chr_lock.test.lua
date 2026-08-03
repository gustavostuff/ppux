local WM = require("controllers.window.window_controller")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")
local ToolbarController = require("controllers.window.toolbar_controller")
local Timer = require("utils.timer_utils")

local function paintTile(canvas, tileCol, tileRow, value)
  local ox = tileCol * 8
  local oy = tileRow * 8
  for y = 0, 7 do
    for x = 0, 7 do
      canvas:edit(ox + x, oy + y, value)
    end
  end
end

local function paintTileDiffPixels(canvas, tileCol, tileRow, baseValue, flipCount)
  paintTile(canvas, tileCol, tileRow, baseValue)
  local ox = tileCol * 8
  local oy = tileRow * 8
  local flipped = 0
  for y = 0, 7 do
    for x = 0, 7 do
      if flipped >= flipCount then
        return
      end
      canvas:edit(ox + x, oy + y, (baseValue + 1) % 4)
      flipped = flipped + 1
    end
  end
end

local function makeChrSrcWin()
  local tile = {
    index = 0,
    pixels = {},
    _bankIndex = 1,
  }
  for i = 1, 64 do
    tile.pixels[i] = 1
  end
  return {
    kind = "chr",
    currentBank = 1,
    layers = {
      {
        kind = "tile",
        items = { tile },
      },
    },
    getActiveLayerIndex = function()
      return 1
    end,
  }
end

local function makeTileGroup()
  return {
    entries = {
      { offsetCol = 0, offsetRow = 0, item = { index = 0, _bankIndex = 1 } },
    },
    minOffsetCol = 0,
    maxOffsetCol = 0,
    minOffsetRow = 0,
    maxOffsetRow = 0,
    spanCols = 1,
    spanRows = 1,
    sourceSelectionMode = "8x8",
  }
end

describe("sketch canvas - live tolerance + CHR lock", function()
  it("setFocus does not clobber status when the window is already focused", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "sketch test" })
    local other = wm:createSketchCanvasWindow({ title = "other" })
    local statuses = {}
    rawset(_G, "ctx", {
      app = {
        setStatus = function(_app, text)
          statuses[#statuses + 1] = text
        end,
      },
    })
    -- create already focused `other`; switching to sketch should write layer status once.
    wm:setFocus(sketch)
    expect(#statuses).toBe(1)
    expect(statuses[1]:find("layer 1/1", 1, true)).toBeTruthy()

    rawget(_G, "ctx").app:setStatus("Sketch generate: keep me")
    local keepIndex = #statuses
    expect(statuses[keepIndex]).toBe("Sketch generate: keep me")
    wm:setFocus(sketch) -- already focused (toolbar click path)
    expect(statuses[keepIndex]).toBe("Sketch generate: keep me")
    expect(#statuses).toBe(keepIndex)
    rawset(_G, "ctx", nil)
  end)

  it("tolerance change while linked regenerates and applies to the pattern table", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 1)
    paintTileDiffPixels(sketch.layers[1].canvas, 1, 0, 1, 3)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generateAndApply(sketch, wm))
    expect(sketch.tilesPool and #sketch.tilesPool).toBe(3) -- blank + solid + near

    local toasts = {}
    local app = {
      wm = wm,
      showToast = function(_app, kind, text)
        toasts[#toasts + 1] = { kind = kind, text = text }
      end,
    }
    local toolbar = ToolbarController.createSpecializedToolbar(sketch, {
      app = app,
      showToast = function(kind, text)
        toasts[#toasts + 1] = { kind = kind, text = text }
      end,
    }, wm)

    local origAfter = Timer.after
    Timer.after = function(_delay, fn)
      fn()
      return 99
    end
    local ok, err = pcall(function()
      toolbar.toleranceUpButton.action()
      toolbar.toleranceUpButton.action()
      toolbar.toleranceUpButton.action()
    end)
    Timer.after = origAfter
    assert(ok, err)

    expect(sketch.tolerance).toBe(3)
    expect(#sketch.tilesPool).toBe(2) -- blank + merged painted pair
    expect(#pt.layers[1].items).toBe(256)
    expect(toasts[#toasts].text:find("unique pattern", 1, true)).toBeTruthy()
  end)

  it("blocks CHR group drops onto sketch-owned pattern tables", function()
    local sketch = {
      kind = "sketch_canvas",
      _id = "sketch_lock_1",
      linkedPatternTableWindowId = "pt_lock_1",
    }
    local pt = {
      kind = "pattern_table",
      _id = "pt_lock_1",
      linkedSketchCanvasWindowId = "sketch_lock_1",
      layers = { { kind = "tile", patternTable = { ranges = {} }, items = {} } },
      isInContentArea = function()
        return true
      end,
    }
    local wm = {
      windowAt = function()
        return pt
      end,
      getWindows = function()
        return { sketch, pt }
      end,
      findWindowById = function(_, id)
        if id == sketch._id then
          return sketch
        end
        if id == pt._id then
          return pt
        end
        return nil
      end,
      setFocus = function() end,
    }

    local toasts = {}
    local applyCalled = false
    local src = makeChrSrcWin()
    local item = src.layers[1].items[1]
    local env = {
      wm = wm,
      drag = {
        active = true,
        item = item,
        srcWin = src,
        srcLayer = 1,
        tileGroup = makeTileGroup(),
      },
      ctx = {
        app = {
          wm = wm,
          setStatus = function() end,
          showToast = function(_app, kind, text)
            toasts[#toasts + 1] = { kind = kind, text = text }
          end,
          applyChrTileGroupToPatternTableWindow = function()
            applyCalled = true
            return true
          end,
        },
      },
      clearDragState = function() end,
    }

    local state = MouseTileDropController.getHoverDropState(env, 8, 8, wm)
    expect(state).toBeTruthy()
    expect(state.valid).toBe(false)
    expect(state.reason).toBe("sketch_owned_pattern_table")

    local handled = MouseTileDropController.handleTileDrop(env, 8, 8, wm)
    expect(handled).toBe(true)
    expect(applyCalled).toBe(false)
    expect(#toasts).toBe(1)
    expect(toasts[1].kind).toBe("warning")
    expect(toasts[1].text:find("sketch canvas", 1, true)).toBeTruthy()
  end)

  it("allows CHR drops again after unlink", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    SketchCanvasPackController.unlinkSketchPatternTable(sketch, wm)
    expect(SketchCanvasPackController.isSketchOwnedPatternTable(pt, wm)).toBe(false)

    local mockWm = {
      windowAt = function()
        return pt
      end,
      getWindows = function()
        return wm:getWindows()
      end,
      findWindowById = function(_, id)
        return wm:findWindowById(id)
      end,
    }
    pt.isInContentArea = function()
      return true
    end

    local src = makeChrSrcWin()
    local env = {
      wm = mockWm,
      drag = {
        active = true,
        srcWin = src,
        srcLayer = 1,
        tileGroup = makeTileGroup(),
      },
      ctx = { app = { wm = mockWm } },
    }
    local state = MouseTileDropController.getHoverDropState(env, 8, 8, mockWm)
    expect(state).toBeTruthy()
    expect(state.reason).toNotBe("sketch_owned_pattern_table")
  end)

  it("applyChrTileGroupToPatternTableWindow rejects sketch-owned PT", function()
    local AppCoreController = require("controllers.app.core_controller")
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))

    local toasts = {}
    local app = setmetatable({
      wm = wm,
      setStatus = function() end,
      showToast = function(_self, kind, text)
        toasts[#toasts + 1] = { kind = kind, text = text }
      end,
    }, { __index = AppCoreController })

    local ok = app:applyChrTileGroupToPatternTableWindow(pt, {
      srcWin = makeChrSrcWin(),
      srcLayer = 1,
      tileGroup = makeTileGroup(),
    })
    expect(ok).toBe(false)
    expect(#toasts).toBe(1)
    expect(toasts[1].kind).toBe("warning")
  end)

  it("Add tile range modal refuses sketch-owned pattern tables", function()
    local AppCoreController = require("controllers.app.core_controller")
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))

    local toasts = {}
    local modalShown = false
    local app = setmetatable({
      wm = wm,
      ppuFramePatternRangeModal = {
        show = function()
          modalShown = true
        end,
      },
      setStatus = function() end,
      showToast = function(_self, kind, text)
        toasts[#toasts + 1] = { kind = kind, text = text }
      end,
    }, { __index = AppCoreController })

    local ok = app:showPpuFramePatternRangeModal(pt)
    expect(ok).toBe(false)
    expect(modalShown).toBe(false)
    expect(#toasts).toBe(1)
    expect(toasts[1].text:find("sketch canvas", 1, true)).toBeTruthy()
  end)
end)
