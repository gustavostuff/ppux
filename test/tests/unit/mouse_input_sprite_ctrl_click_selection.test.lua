local MouseInput = require("controllers.input.mouse_input")
local SpriteController = require("controllers.sprite.sprite_controller")

describe("mouse_input.lua - ctrl+click sprite copy selection", function()
  local originalPickSpriteAt
  local originalBeginDrag
  local originalUpdateSpriteMarquee
  local originalIsDragging
  local originalFinishDrag
  local originalFinishSpriteMarquee

  beforeEach(function()
    originalPickSpriteAt = SpriteController.pickSpriteAt
    originalBeginDrag = SpriteController.beginDrag
    originalUpdateSpriteMarquee = SpriteController.updateSpriteMarquee
    originalIsDragging = SpriteController.isDragging
    originalFinishDrag = SpriteController.finishDrag
    originalFinishSpriteMarquee = SpriteController.finishSpriteMarquee
  end)

  afterEach(function()
    SpriteController.pickSpriteAt = originalPickSpriteAt
    SpriteController.beginDrag = originalBeginDrag
    SpriteController.updateSpriteMarquee = originalUpdateSpriteMarquee
    SpriteController.isDragging = originalIsDragging
    SpriteController.finishDrag = originalFinishDrag
    SpriteController.finishSpriteMarquee = originalFinishSpriteMarquee
  end)

  it("adds clicked sprite to current selection when ctrl-clicking", function()
    local dragArgs = nil
    SpriteController.pickSpriteAt = function()
      return 1, 2, 0, 0
    end
    SpriteController.beginDrag = function(win, layerIndex, anchorIndex, offX, offY, copyMode)
      dragArgs = {
        win = win,
        layerIndex = layerIndex,
        anchorIndex = anchorIndex,
        offX = offX,
        offY = offY,
        copyMode = copyMode,
      }
      return true
    end
    SpriteController.updateSpriteMarquee = function() end

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 1, tile = 10, x = 4, y = 4 },
        { bank = 1, tile = 11, x = 12, y = 4 },
      },
      multiSpriteSelection = { [1] = true },
      selectedSpriteIndex = 1,
    }

    local win = {
      kind = "static_art",
      _closed = false,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
      hitResizeHandle = function() return false end,
    }

    local focused = nil
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, w) focused = w end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, { pending = false, active = false }, {}, {
      ctrlDown = function() return true end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    MouseInput.mousepressed(10, 10, 1)

    local selected = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selected).toBe(2)
    expect(selected[1]).toBe(1)
    expect(selected[2]).toBe(2)
    expect(layer.multiSpriteSelectionOrder).toBeTruthy()
    expect(layer.multiSpriteSelectionOrder[1]).toBe(1)
    expect(layer.multiSpriteSelectionOrder[2]).toBe(2)
    expect(layer.selectedSpriteIndex).toBe(2)
    expect(layer.hoverSpriteIndex).toBe(2)
    expect(dragArgs).toBeTruthy()
    expect(dragArgs.anchorIndex).toBe(2)
    expect(dragArgs.copyMode).toBe(true)
  end)

  it("keeps existing multi-selection when ctrl-clicking a selected sprite", function()
    local dragArgs = nil
    SpriteController.pickSpriteAt = function()
      return 1, 2, 0, 0
    end
    SpriteController.beginDrag = function(win, layerIndex, anchorIndex, offX, offY, copyMode)
      dragArgs = {
        win = win,
        layerIndex = layerIndex,
        anchorIndex = anchorIndex,
        offX = offX,
        offY = offY,
        copyMode = copyMode,
      }
      return true
    end
    SpriteController.updateSpriteMarquee = function() end

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 1, tile = 10, x = 4, y = 4 },
        { bank = 1, tile = 11, x = 12, y = 4 },
      },
      multiSpriteSelection = { [1] = true, [2] = true },
      selectedSpriteIndex = 1,
    }

    local win = {
      kind = "static_art",
      _closed = false,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
      hitResizeHandle = function() return false end,
    }

    local focused = nil
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, w) focused = w end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, { pending = false, active = false }, {}, {
      ctrlDown = function() return true end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    MouseInput.mousepressed(10, 10, 1)

    local selected = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selected).toBe(2)
    expect(selected[1]).toBe(1)
    expect(selected[2]).toBe(2)
    expect(layer.multiSpriteSelectionOrder).toBeTruthy()
    expect(layer.multiSpriteSelectionOrder[1]).toBe(1)
    expect(layer.multiSpriteSelectionOrder[2]).toBe(2)
    expect(layer.selectedSpriteIndex).toBe(2)
    expect(layer.hoverSpriteIndex).toBe(2)
    expect(dragArgs).toBeTruthy()
    expect(dragArgs.anchorIndex).toBe(2)
    expect(dragArgs.copyMode).toBe(true)
  end)

  it("keeps copy when ctrl is released before mouse-up", function()
    local finishArg = "__unset__"
    SpriteController.isDragging = function() return true end
    SpriteController.finishDrag = function(arg)
      finishArg = arg
      return true
    end
    SpriteController.finishSpriteMarquee = function() return false end

    local wm = {
      getFocus = function() return nil end,
      windowAt = function() return nil end,
      getWindows = function() return {} end,
    }
    local ctx = {
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      app = {},
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, { pending = false, active = false }, {}, {
      ctrlDown = function() return false end, -- simulate Ctrl released before drop
      shiftDown = function() return false end,
      altDown = function() return false end,
    })

    MouseInput.mousereleased(0, 0, 1)

    -- finishDrag called without overriding copy mode from current Ctrl key state
    expect(finishArg).toBeNil()
  end)
end)

describe("mouse_input.lua - sprite ctrl+click additive selection", function()
  local originalPickSpriteAt
  local originalBeginDrag
  local originalIsDragging
  local originalEndDrag
  local originalFinishDrag
  local originalUpdateSpriteMarquee
  local originalFinishSpriteMarquee

  beforeEach(function()
    originalPickSpriteAt = SpriteController.pickSpriteAt
    originalBeginDrag = SpriteController.beginDrag
    originalIsDragging = SpriteController.isDragging
    originalEndDrag = SpriteController.endDrag
    originalFinishDrag = SpriteController.finishDrag
    originalUpdateSpriteMarquee = SpriteController.updateSpriteMarquee
    originalFinishSpriteMarquee = SpriteController.finishSpriteMarquee
  end)

  afterEach(function()
    SpriteController.pickSpriteAt = originalPickSpriteAt
    SpriteController.beginDrag = originalBeginDrag
    SpriteController.isDragging = originalIsDragging
    SpriteController.endDrag = originalEndDrag
    SpriteController.finishDrag = originalFinishDrag
    SpriteController.updateSpriteMarquee = originalUpdateSpriteMarquee
    SpriteController.finishSpriteMarquee = originalFinishSpriteMarquee
  end)

  it("builds multi-selection one-by-one with ctrl-click without committing copy", function()
    local dragging = false
    local finishCalls = 0
    local endCalls = 0

    SpriteController.pickSpriteAt = function(_, x)
      if x < 20 then
        return 1, 1, 0, 0
      end
      return 1, 2, 0, 0
    end
    SpriteController.beginDrag = function()
      dragging = true
      return true
    end
    SpriteController.isDragging = function()
      return dragging
    end
    SpriteController.endDrag = function()
      endCalls = endCalls + 1
      dragging = false
      return true
    end
    SpriteController.finishDrag = function()
      finishCalls = finishCalls + 1
      dragging = false
      return true
    end
    SpriteController.updateSpriteMarquee = function() end
    SpriteController.finishSpriteMarquee = function() return false end

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 1, tile = 10, x = 4, y = 4 },
        { bank = 1, tile = 11, x = 12, y = 4 },
      },
    }

    local win = {
      kind = "static_art",
      _closed = false,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
      hitResizeHandle = function() return false end,
    }

    local focused = nil
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, w) focused = w end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      app = {},
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, { pending = false, active = false }, {}, {
      ctrlDown = function() return true end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
    })

    MouseInput.mousepressed(10, 10, 1) -- sprite 1
    MouseInput.mousereleased(10, 10, 1)
    MouseInput.mousepressed(30, 10, 1) -- sprite 2
    MouseInput.mousereleased(30, 10, 1)

    local selected = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selected).toBe(2)
    expect(selected[1]).toBe(1)
    expect(selected[2]).toBe(2)
    expect(layer.selectedSpriteIndex).toBe(2)
    expect(endCalls).toBe(2)
    expect(finishCalls).toBe(0)
  end)
end)

describe("mouse_input.lua - sprite shift marquee selection", function()
  local originalPickSpriteAt
  local originalBeginDrag
  local originalUpdateSpriteMarquee
  local originalFinishSpriteMarquee

  beforeEach(function()
    originalPickSpriteAt = SpriteController.pickSpriteAt
    originalBeginDrag = SpriteController.beginDrag
    originalUpdateSpriteMarquee = SpriteController.updateSpriteMarquee
    originalFinishSpriteMarquee = SpriteController.finishSpriteMarquee
  end)

  afterEach(function()
    SpriteController.pickSpriteAt = originalPickSpriteAt
    SpriteController.beginDrag = originalBeginDrag
    SpriteController.updateSpriteMarquee = originalUpdateSpriteMarquee
    SpriteController.finishSpriteMarquee = originalFinishSpriteMarquee
  end)

  it("starts sprite marquee only when shift is held and continues after shift release", function()
    local shift = true
    local beginDragCalls = 0
    SpriteController.beginDrag = function()
      beginDragCalls = beginDragCalls + 1
      return true
    end
    SpriteController.pickSpriteAt = function()
      return nil
    end

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 1, tile = 10, x = 0, y = 0 },
        { bank = 1, tile = 11, x = 10, y = 0 },
      },
    }

    local win = {
      kind = "static_art",
      _closed = false,
      x = 0,
      y = 0,
      zoom = 1,
      cellW = 8,
      cellH = 8,
      scrollCol = 0,
      scrollRow = 0,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
    }

    local focused = nil
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, w) focused = w end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      app = {},
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, { pending = false, active = false }, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return shift end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1)
    shift = false
    MouseInput.mousemoved(18, 6, 17, 5)

    -- Selection should update immediately while marquee is being dragged.
    local selectedDuringDrag = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selectedDuringDrag).toBe(2)
    expect(selectedDuringDrag[1]).toBe(1)
    expect(selectedDuringDrag[2]).toBe(2)

    MouseInput.mousereleased(18, 6, 1)

    local selected = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selected).toBe(2)
    expect(selected[1]).toBe(1)
    expect(selected[2]).toBe(2)
    expect(beginDragCalls).toBe(0)
  end)

  it("updates sprite marquee selection in real time as rectangle changes", function()
    local shift = true
    SpriteController.beginDrag = function()
      return true
    end
    SpriteController.pickSpriteAt = function()
      return nil
    end

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 1, tile = 10, x = 0, y = 0 },
        { bank = 1, tile = 11, x = 10, y = 0 },
      },
    }

    local win = {
      kind = "static_art",
      _closed = false,
      x = 0,
      y = 0,
      zoom = 1,
      cellW = 8,
      cellH = 8,
      scrollCol = 0,
      scrollRow = 0,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
    }

    local focused = nil
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, w) focused = w end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      app = {},
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, { pending = false, active = false }, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return shift end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1)
    MouseInput.mousemoved(18, 6, 17, 5)

    local selectedWide = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selectedWide).toBe(2)
    expect(selectedWide[1]).toBe(1)
    expect(selectedWide[2]).toBe(2)

    MouseInput.mousemoved(6, 6, -12, 0)

    local selectedNarrow = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selectedNarrow).toBe(1)
    expect(selectedNarrow[1]).toBe(1)
    expect(layer.selectedSpriteIndex).toBe(1)

    MouseInput.mousereleased(6, 6, 1)
  end)

  it("supports shift marquee selection in PPU frame sprite layers", function()
    local shift = true
    SpriteController.beginDrag = function()
      return true
    end
    SpriteController.pickSpriteAt = function()
      return nil
    end

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 1, tile = 10, x = 0, y = 0 },
        { bank = 1, tile = 11, x = 10, y = 0 },
      },
    }

    local win = {
      kind = "ppu_frame",
      _closed = false,
      x = 0,
      y = 0,
      zoom = 1,
      cellW = 8,
      cellH = 8,
      scrollCol = 0,
      scrollRow = 0,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
    }

    local focused = nil
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, w) focused = w end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      app = {},
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, { pending = false, active = false }, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return shift end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1)
    MouseInput.mousemoved(18, 6, 17, 5)
    MouseInput.mousereleased(18, 6, 1)

    local selected = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selected).toBe(2)
    expect(selected[1]).toBe(1)
    expect(selected[2]).toBe(2)
  end)

  it("does not start sprite marquee without shift", function()
    local shift = false
    local beginDragCalls = 0
    SpriteController.beginDrag = function()
      beginDragCalls = beginDragCalls + 1
      return true
    end
    SpriteController.pickSpriteAt = function()
      return nil
    end

    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 1, tile = 10, x = 0, y = 0 },
        { bank = 1, tile = 11, x = 10, y = 0 },
      },
      multiSpriteSelection = { [1] = true, [2] = true },
      selectedSpriteIndex = 1,
    }

    local win = {
      kind = "static_art",
      _closed = false,
      x = 0,
      y = 0,
      zoom = 1,
      cellW = 8,
      cellH = 8,
      scrollCol = 0,
      scrollRow = 0,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
    }

    local focused = nil
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, w) focused = w end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      app = {},
      wm = function() return wm end,
    }

    MouseInput.setup(ctx, { pending = false, active = false }, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return shift end,
      altDown = function() return false end,
      DRAG_TOL = 4,
      pickByVisual = function() return false end,
    })

    MouseInput.mousepressed(1, 1, 1)
    MouseInput.mousemoved(18, 6, 17, 5)
    MouseInput.mousereleased(18, 6, 1)

    local selected = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selected).toBe(0)
    expect(layer.selectedSpriteIndex).toBeNil()
    expect(beginDragCalls).toBe(0)
  end)
end)

describe("mouse_input.lua - sprite normal click vs drag on multi-selection", function()
  local originalPickSpriteAt
  local originalBeginDrag
  local originalUpdateSpriteMarquee
  local originalIsDragging
  local originalFinishDrag
  local originalUpdateDrag
  local originalFinishSpriteMarquee

  beforeEach(function()
    originalPickSpriteAt = SpriteController.pickSpriteAt
    originalBeginDrag = SpriteController.beginDrag
    originalUpdateSpriteMarquee = SpriteController.updateSpriteMarquee
    originalIsDragging = SpriteController.isDragging
    originalFinishDrag = SpriteController.finishDrag
    originalUpdateDrag = SpriteController.updateDrag
    originalFinishSpriteMarquee = SpriteController.finishSpriteMarquee
  end)

  afterEach(function()
    SpriteController.pickSpriteAt = originalPickSpriteAt
    SpriteController.beginDrag = originalBeginDrag
    SpriteController.updateSpriteMarquee = originalUpdateSpriteMarquee
    SpriteController.isDragging = originalIsDragging
    SpriteController.finishDrag = originalFinishDrag
    SpriteController.updateDrag = originalUpdateDrag
    SpriteController.finishSpriteMarquee = originalFinishSpriteMarquee
  end)

  local function setupSpriteClickHarness(layer)
    local dragging = false
    SpriteController.pickSpriteAt = function()
      return 1, 2, 0, 0
    end
    SpriteController.beginDrag = function()
      dragging = true
      return true
    end
    SpriteController.isDragging = function()
      return dragging
    end
    SpriteController.finishDrag = function()
      dragging = false
      return true
    end
    SpriteController.updateDrag = function() end
    SpriteController.updateSpriteMarquee = function() end
    SpriteController.finishSpriteMarquee = function() return false end

    local win = {
      kind = "static_art",
      _closed = false,
      layers = { layer },
      getActiveLayerIndex = function() return 1 end,
      isInHeader = function() return false end,
    }

    local focused = nil
    local wm = {
      getFocus = function() return focused end,
      setFocus = function(_, w) focused = w end,
      windowAt = function() return win end,
      getWindows = function() return { win } end,
    }

    local ctx = {
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      app = {},
      wm = function() return wm end,
    }

    return ctx
  end

  it("collapses sprite multi-selection on normal click", function()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 1, tile = 10, x = 4, y = 4 },
        { bank = 1, tile = 11, x = 12, y = 4 },
      },
      multiSpriteSelection = { [1] = true, [2] = true },
      selectedSpriteIndex = 1,
    }

    local ctx = setupSpriteClickHarness(layer)
    MouseInput.setup(ctx, { pending = false, active = false }, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
    })

    MouseInput.mousepressed(10, 10, 1)
    MouseInput.mousereleased(10, 10, 1)

    local selected = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selected).toBe(1)
    expect(selected[1]).toBe(2)
    expect(layer.selectedSpriteIndex).toBe(2)
  end)

  it("keeps sprite multi-selection on click-drag", function()
    local layer = {
      kind = "sprite",
      mode = "8x8",
      items = {
        { bank = 1, tile = 10, x = 4, y = 4 },
        { bank = 1, tile = 11, x = 12, y = 4 },
      },
      multiSpriteSelection = { [1] = true, [2] = true },
      selectedSpriteIndex = 1,
    }

    local ctx = setupSpriteClickHarness(layer)
    MouseInput.setup(ctx, { pending = false, active = false }, {}, {
      ctrlDown = function() return false end,
      shiftDown = function() return false end,
      altDown = function() return false end,
      DRAG_TOL = 4,
    })

    MouseInput.mousepressed(10, 10, 1)
    MouseInput.mousemoved(20, 10, 10, 0)
    MouseInput.mousereleased(20, 10, 1)

    local selected = SpriteController.getSelectedSpriteIndices(layer)
    expect(#selected).toBe(2)
    expect(selected[1]).toBe(1)
    expect(selected[2]).toBe(2)
  end)
end)
