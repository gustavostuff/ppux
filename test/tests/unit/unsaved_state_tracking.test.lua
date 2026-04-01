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
