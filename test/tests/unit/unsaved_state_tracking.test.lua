local UndoRedoController = require("controllers.input_support.undo_redo_controller")

describe("undo_redo_controller.lua - unsaved tracking", function()
  it("marks pixel edits as unsaved when a paint event is stored", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    undo:startPaintEvent()
    undo:recordPixelChange(1, 2, 3, 4, 0, 1)
    expect(undo:finishPaintEvent()).toBe(true)
    expect(events[#events]).toBe("pixel_edit")
  end)

  it("marks tile move drag as unsaved", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    local ok = undo:addDragEvent({
      type = "tile_drag",
      mode = "move",
      changes = {
        { col = 0, row = 0, before = "A", after = "B" },
      },
    })

    expect(ok).toBe(true)
    expect(events[#events]).toBe("tile_move")
  end)

  it("does not mark tile copy drag as unsaved move", function()
    local undo = UndoRedoController.new(10)
    local called = false
    undo:setUnsavedTracker(function()
      called = true
    end)

    local ok = undo:addDragEvent({
      type = "tile_drag",
      mode = "copy",
      changes = {
        { col = 0, row = 0, before = nil, after = "A" },
      },
    })

    expect(ok).toBe(true)
    expect(called).toBe(false)
  end)

  it("marks sprite removal as unsaved", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    local ok = undo:addRemovalEvent({
      type = "remove_tile",
      subtype = "sprite",
      actions = {
        { spriteIndex = 1 },
      },
    })

    expect(ok).toBe(true)
    expect(events[#events]).toBe("sprite_remove")
  end)

  it("marks tile palette drag as unsaved", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    local ok = undo:addDragEvent({
      type = "tile_drag",
      mode = "palette",
      changes = {
        {
          win = { layers = { { paletteNumbers = {} } } }, _closed = false,
          layerIndex = 1,
          col = 0,
          row = 0,
          linearIndex = 0,
          before = 1,
          after = 2,
          isPaletteNumber = true,
        },
      },
    })

    expect(ok).toBe(true)
    expect(events[#events]).toBe("tile_move")
  end)

  it("marks sprite palette drag as unsaved", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    local ok = undo:addDragEvent({
      type = "sprite_drag",
      mode = "palette",
      actions = {
        { before = { paletteNumber = 1 }, after = { paletteNumber = 2 } },
      },
    })

    expect(ok).toBe(true)
    expect(events[#events]).toBe("sprite_move")
  end)

  it("marks sprite copy drag as unsaved", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    local ok = undo:addDragEvent({
      type = "sprite_drag",
      mode = "copy",
      actions = {
        { before = { removed = true }, after = { removed = false } },
      },
    })

    expect(ok).toBe(true)
    expect(events[#events]).toBe("sprite_move")
  end)

  it("marks animation timeline undo events as unsaved", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    local AnimationWindowUndo = require("controllers.input_support.animation_window_undo")
    local win = { layers = { {} }, activeLayer = 1, frameDelays = {}, nonActiveLayerOpacity = 1.0 }
    local beforeState = AnimationWindowUndo.snapshot(win)
    table.insert(win.layers, {})
    local afterState = AnimationWindowUndo.snapshot(win)

    local ok = undo:addAnimationWindowStateEvent({
      type = "animation_window_state",
      win = win,
      beforeState = beforeState,
      afterState = afterState,
    })

    expect(ok).toBe(true)
    expect(events[#events]).toBe("animation_timeline_change")
  end)

  it("marks sprite mirror drag as unsaved", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    local ok = undo:addDragEvent({
      type = "sprite_drag",
      mode = "mirror",
      actions = {
        { before = { mirrorX = false }, after = { mirrorX = true } },
      },
    })

    expect(ok).toBe(true)
    expect(events[#events]).toBe("sprite_move")
  end)

  it("marks sprite_binding edit as unsaved", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    local ok = undo:addDragEvent({
      type = "sprite_drag",
      mode = "sprite_binding",
      actions = {
        {
          sprite = {},
          before = { bank = 1, tile = 0, startAddr = 0x100, tileBelow = nil },
          after = { bank = 1, tile = 1, startAddr = 0x100, tileBelow = nil },
        },
      },
    })

    expect(ok).toBe(true)
    expect(events[#events]).toBe("sprite_move")
  end)

  it("marks window close as unsaved", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    local ok = undo:addWindowEvent({
      type = "window_close",
      win = { _closed = true },
      prevClosed = false,
      prevMinimized = false,
      prevFocused = true,
    })

    expect(ok).toBe(true)
    expect(events[#events]).toBe("window_close")
  end)

  it("marks window minimize as unsaved", function()
    local undo = UndoRedoController.new(10)
    local events = {}
    undo:setUnsavedTracker(function(eventType)
      events[#events + 1] = eventType
    end)

    local ok = undo:addWindowMinimizeEvent({
      type = "window_minimize",
      win = { _closed = false, _minimized = true },
      beforeMinimized = false,
      afterMinimized = true,
    })

    expect(ok).toBe(true)
    expect(events[#events]).toBe("window_minimize")
  end)
end)
