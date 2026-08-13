local PixelCanvas = require("ui.windows_system.pixel_canvas")
local WM = require("controllers.window.window_controller")
local PixelSel = require("controllers.game_art.sketch_canvas_pixel_selection_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

describe("sketch_canvas_pixel_selection_controller", function()
  local function paintRect(canvas, x, y, w, h, value)
    for py = y, y + h - 1 do
      for px = x, x + w - 1 do
        canvas:edit(px, py, value)
      end
    end
  end

  it("extractRect / loadRect round-trip on PixelCanvas", function()
    local canvas = PixelCanvas.new(32, 32, 0)
    paintRect(canvas, 2, 3, 4, 5, 2)
    local extracted, x, y, w, h = canvas:extractRect(2, 3, 4, 5)
    expect(extracted).toBeTruthy()
    expect(x).toBe(2)
    expect(y).toBe(3)
    expect(w).toBe(4)
    expect(h).toBe(5)
    expect(extracted:getPixel(0, 0)).toBe(2)

    local dest = PixelCanvas.new(32, 32, 0)
    dest:loadRect(10, 10, extracted)
    expect(dest:getPixel(10, 10)).toBe(2)
    expect(dest:getPixel(13, 14)).toBe(2)
    expect(dest:getPixel(9, 10)).toBe(0)
  end)

  it("commits a rect selection and draws bounds", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "Sel" })
    _G.ctx = { getMode = function() return "edit" end }

    expect(PixelSel.begin(win, PixelSel.KIND_RECT, 4, 5)).toBe(true)
    PixelSel.updateDrag(win, 11, 12)
    expect(PixelSel.commitDrag(win)).toBe(true)
    expect(PixelSel.hasSelection(win)).toBe(true)
    local sel = PixelSel.getSelection(win)
    expect(sel.x).toBe(4)
    expect(sel.y).toBe(5)
    expect(sel.w).toBe(8)
    expect(sel.h).toBe(8)
    expect(PixelSel.hitTest(win, 4, 5)).toBe(true)
    expect(PixelSel.hitTest(win, 20, 20)).toBe(false)

    _G.ctx = nil
  end)

  it("commits a freeform lasso closed from release back to start", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 2, 2, 6, 6, 2)
    _G.ctx = { getMode = function() return "edit" end }

    expect(PixelSel.begin(win, PixelSel.KIND_FREE, 2, 2)).toBe(true)
    PixelSel.updateDrag(win, 8, 2)
    PixelSel.updateDrag(win, 8, 8)
    PixelSel.updateDrag(win, 2, 8)
    expect(PixelSel.commitDrag(win)).toBe(true)
    expect(PixelSel.hasSelection(win)).toBe(true)
    local sel = PixelSel.getSelection(win)
    expect(sel.kind).toBe(PixelSel.KIND_FREE)
    expect(sel.mask).toBeTruthy()
    expect(PixelSel.hitTest(win, 5, 5)).toBe(true)
    expect(PixelSel.hitTest(win, 20, 20)).toBe(false)

    local app = { undoRedo = UndoRedoController.new(20) }
    expect(PixelSel.ensureLifted(win, app)).toBe(true)
    expect(canvas:getPixel(5, 5)).toBe(0)
    -- Outside the lasso but inside AABB of a square path should remain if not in mask;
    -- for a closed square 2..8 the interior is cleared. Corner outside selection stays.
    expect(canvas:getPixel(0, 0)).toBe(0)

    _G.ctx = nil
  end)

  it("lifts, moves, and stamps a selection with undo", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 0, 0, 4, 4, 3)
    _G.ctx = { getMode = function() return "edit" end }

    local ur = UndoRedoController.new(20)
    local app = { undoRedo = ur }

    PixelSel.begin(win, PixelSel.KIND_RECT, 0, 0)
    PixelSel.updateDrag(win, 3, 3)
    PixelSel.commitDrag(win)

    expect(PixelSel.ensureLifted(win, app)).toBe(true)
    expect(canvas:getPixel(0, 0)).toBe(0)
    -- Lift alone does not push undo yet (deferred until stamp/cut).
    expect(ur:canUndo()).toBe(false)
    local sel = PixelSel.getSelection(win)
    expect(sel.lifted).toBe(true)
    expect(sel.floating:getPixel(0, 0)).toBe(3)

    PixelSel.beginMove(win, 1, 1, app)
    PixelSel.updateMove(win, 9, 1)
    PixelSel.endMove(win)
    expect(sel.floatingOffsetX).toBe(8)

    expect(PixelSel.stampDown(win, app)).toBe(true)
    expect(canvas:getPixel(8, 0)).toBe(3)
    expect(canvas:getPixel(0, 0)).toBe(0)
    expect(ur:canUndo()).toBe(true)

    -- One undo restores both the origin hole and the landing stamp.
    expect(ur:undo(app)).toBe(true)
    expect(canvas:getPixel(0, 0)).toBe(3)
    expect(canvas:getPixel(8, 0)).toBe(0)
    expect(ur:redo(app)).toBe(true)
    expect(canvas:getPixel(0, 0)).toBe(0)
    expect(canvas:getPixel(8, 0)).toBe(3)

    _G.ctx = nil
  end)

  it("Ctrl+Z cancels a floating lift before it is stamped", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 0, 0, 2, 2, 2)
    _G.ctx = { getMode = function() return "edit" end }
    local app = { undoRedo = UndoRedoController.new(20) }

    PixelSel.begin(win, PixelSel.KIND_RECT, 0, 0)
    PixelSel.updateDrag(win, 1, 1)
    PixelSel.commitDrag(win)
    PixelSel.ensureLifted(win, app)
    expect(canvas:getPixel(0, 0)).toBe(0)
    expect(PixelSel.cancelFloating(win, app)).toBe(true)
    expect(PixelSel.hasSelection(win)).toBe(false)
    expect(canvas:getPixel(0, 0)).toBe(2)

    _G.ctx = nil
  end)

  it("cut is a single undoable paint event", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 1, 1, 2, 2, 3)
    _G.ctx = { getMode = function() return "edit" end }
    local ur = UndoRedoController.new(20)
    local app = { undoRedo = ur }

    PixelSel.begin(win, PixelSel.KIND_RECT, 1, 1)
    PixelSel.updateDrag(win, 2, 2)
    PixelSel.commitDrag(win)
    expect(PixelSel.cutSelection(win, app)).toBeTruthy()
    expect(canvas:getPixel(1, 1)).toBe(0)
    expect(ur:undo(app)).toBe(true)
    expect(canvas:getPixel(1, 1)).toBe(3)

    _G.ctx = nil
  end)

  it("paste stamp is undoable", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 0, 0, 2, 2, 1)
    _G.ctx = { getMode = function() return "edit" end }
    local ur = UndoRedoController.new(20)
    local app = { undoRedo = ur }

    PixelSel.begin(win, PixelSel.KIND_RECT, 0, 0)
    PixelSel.updateDrag(win, 1, 1)
    PixelSel.commitDrag(win)
    local clip = PixelSel.captureClipboard(win)
    expect(PixelSel.pasteClipboard(win, clip, app, 5, 5)).toBe(true)
    expect(PixelSel.stampDown(win, app)).toBe(true)
    expect(canvas:getPixel(5, 5)).toBe(1)
    expect(ur:undo(app)).toBe(true)
    expect(canvas:getPixel(5, 5)).toBe(0)

    _G.ctx = nil
  end)

  it("stamp skips transparent pixels so landing area is not erased", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    -- Background under the landing zone.
    paintRect(canvas, 8, 0, 4, 4, 2)
    -- Source: opaque corner + transparent rest of the 4x4 block.
    paintRect(canvas, 0, 0, 4, 4, 0)
    canvas:edit(0, 0, 3)
    canvas:edit(1, 0, 3)
    _G.ctx = { getMode = function() return "edit" end }
    local app = { undoRedo = UndoRedoController.new(20) }

    PixelSel.begin(win, PixelSel.KIND_RECT, 0, 0)
    PixelSel.updateDrag(win, 3, 3)
    PixelSel.commitDrag(win)
    PixelSel.ensureLifted(win, app)
    PixelSel.beginMove(win, 0, 0, app)
    PixelSel.updateMove(win, 8, 0)
    PixelSel.endMove(win)
    expect(PixelSel.stampDown(win, app)).toBe(true)

    expect(canvas:getPixel(8, 0)).toBe(3)
    expect(canvas:getPixel(9, 0)).toBe(3)
    -- Transparent float pixels must not overwrite background 2.
    expect(canvas:getPixel(10, 0)).toBe(2)
    expect(canvas:getPixel(8, 1)).toBe(2)
    expect(canvas:getPixel(11, 3)).toBe(2)

    _G.ctx = nil
  end)

  it("copy / cut / paste within the same sketch window", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 2, 2, 3, 3, 1)
    _G.ctx = { getMode = function() return "edit" end }
    local app = { undoRedo = UndoRedoController.new(20) }

    PixelSel.begin(win, PixelSel.KIND_RECT, 2, 2)
    PixelSel.updateDrag(win, 4, 4)
    PixelSel.commitDrag(win)

    local clip = PixelSel.captureClipboard(win)
    expect(clip).toBeTruthy()
    expect(clip.kind).toBe("sketch_pixels")
    expect(clip.width).toBe(3)
    expect(clip.height).toBe(3)

    local cut = PixelSel.cutSelection(win, app)
    expect(cut.width).toBe(3)
    expect(canvas:getPixel(2, 2)).toBe(0)
    expect(PixelSel.hasSelection(win)).toBe(false)

    expect(PixelSel.pasteClipboard(win, cut, app, 10, 10)).toBe(true)
    expect(PixelSel.hasSelection(win)).toBe(true)
    local sel = PixelSel.getSelection(win)
    expect(sel.lifted).toBe(true)
    expect(sel.floating:getPixel(0, 0)).toBe(1)
    PixelSel.stampDown(win, app)
    expect(canvas:getPixel(10, 10)).toBe(1)

    _G.ctx = nil
  end)

  it("default paste stamps floating selection and nudges +3,+3 from last origin", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 4, 4, 2, 2, 2)
    _G.ctx = { getMode = function() return "edit" end }
    local app = { undoRedo = UndoRedoController.new(20) }

    PixelSel.begin(win, PixelSel.KIND_RECT, 4, 4)
    PixelSel.updateDrag(win, 5, 5)
    PixelSel.commitDrag(win)
    local clip = PixelSel.captureClipboard(win)
    expect(clip.originX).toBe(4)
    expect(clip.originY).toBe(4)

    -- First paste: no floating yet; nudge from current selection at (4,4).
    expect(PixelSel.pasteClipboard(win, clip, app)).toBe(true)
    local sel = PixelSel.getSelection(win)
    expect(sel.lifted).toBe(true)
    expect(sel.floatingOffsetX).toBe(4 + PixelSel.PASTE_OFFSET_PX)
    expect(sel.floatingOffsetY).toBe(4 + PixelSel.PASTE_OFFSET_PX)
    expect(sel.floating:getPixel(0, 0)).toBe(2)
    -- Source pixels remain (copy, not cut).
    expect(canvas:getPixel(4, 4)).toBe(2)

    -- Second paste: stamps previous float, then nudges again from stamped origin.
    expect(PixelSel.pasteClipboard(win, clip, app)).toBe(true)
    expect(canvas:getPixel(7, 7)).toBe(2) -- stamped previous paste
    sel = PixelSel.getSelection(win)
    expect(sel.floatingOffsetX).toBe(7 + PixelSel.PASTE_OFFSET_PX)
    expect(sel.floatingOffsetY).toBe(7 + PixelSel.PASTE_OFFSET_PX)

    _G.ctx = nil
  end)

  it("copies freeform selections including the mask", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 2, 2, 6, 6, 1)
    _G.ctx = { getMode = function() return "edit" end }
    local app = { undoRedo = UndoRedoController.new(20) }

    expect(PixelSel.begin(win, PixelSel.KIND_FREE, 2, 2)).toBe(true)
    PixelSel.updateDrag(win, 8, 2)
    PixelSel.updateDrag(win, 8, 8)
    PixelSel.updateDrag(win, 2, 8)
    expect(PixelSel.commitDrag(win)).toBe(true)
    expect(PixelSel.hasSelection(win)).toBe(true)

    local clip = PixelSel.captureClipboard(win)
    expect(clip).toBeTruthy()
    expect(clip.selectionKind).toBe(PixelSel.KIND_FREE)
    expect(clip.mask).toBeTruthy()

    expect(PixelSel.pasteClipboard(win, clip, app)).toBe(true)
    local sel = PixelSel.getSelection(win)
    expect(sel.kind).toBe(PixelSel.KIND_FREE)
    expect(sel.mask).toBeTruthy()
    expect(sel.floatingOffsetX).toBe((clip.originX or 0) + PixelSel.PASTE_OFFSET_PX)

    _G.ctx = nil
  end)

  it("applies a same-color paint mask from a clicked pixel and gates painting", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 0, 0, 4, 4, 2)
    paintRect(canvas, 8, 8, 4, 4, 1)
    canvas:edit(1, 1, 3)

    local ok, count, color = PixelSel.applyColorPaintMaskAt(win, 0, 0)
    expect(ok).toBe(true)
    expect(color).toBe(2)
    expect(count).toBe(16 - 1) -- 4x4 of color 2 minus the one pixel changed to 3
    expect(PixelSel.hasColorPaintMask(win)).toBe(true)
    expect(PixelSel.allowsColorPaintAt(win, 0, 0)).toBe(true)
    expect(PixelSel.allowsColorPaintAt(win, 1, 1)).toBe(false)
    expect(PixelSel.allowsColorPaintAt(win, 8, 8)).toBe(false)

    local BrushController = require("controllers.input_support.brush_controller")
    local app = {
      currentColor = 0,
      brushSize = 1,
      undoRedo = UndoRedoController.new(20),
      setStatus = function() end,
    }
    expect(BrushController.paintPixel(app, win, 0, 0, 0, 0, false)).toBe(true)
    expect(canvas:getPixel(0, 0)).toBe(0)
    expect(BrushController.paintPixel(app, win, 0, 0, 1, 1, false)).toBe(false) -- (1,1) not in mask
    expect(canvas:getPixel(1, 1)).toBe(3)
    expect(BrushController.paintPixel(app, win, 1, 1, 0, 0, false)).toBe(false) -- color 1 region at (8,8)
    expect(canvas:getPixel(8, 8)).toBe(1)

    expect(PixelSel.clearColorPaintMask(win)).toBe(true)
    expect(PixelSel.hasColorPaintMask(win)).toBe(false)
    expect(PixelSel.allowsColorPaintAt(win, 8, 8)).toBe(true)
  end)

  it("hold C + click builds color mask from the clicked pixel color", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 5, 5, 3, 3, 2)

    local okMask, count, color = PixelSel.applyColorPaintMaskAt(win, 5, 5)
    expect(okMask).toBe(true)
    expect(color).toBe(2)
    expect(count).toBe(9)
    expect(PixelSel.hasColorPaintMask(win)).toBe(true)

    -- Re-pick a different color replaces the mask.
    canvas:edit(10, 10, 1)
    okMask, count, color = PixelSel.applyColorPaintMaskAt(win, 10, 10)
    expect(okMask).toBe(true)
    expect(color).toBe(1)
    expect(count).toBe(1)
    expect(PixelSel.allowsColorPaintAt(win, 5, 5)).toBe(false)
    expect(PixelSel.allowsColorPaintAt(win, 10, 10)).toBe(true)
  end)

  it("hold C + click samples the visually mirrored pixel under Mirror X", function()
    local MouseClickController = require("controllers.input.mouse_click_controller")
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ x = 40, y = 20, zoom = 1 })
    win._mirrorXPreview = true
    local canvas = win:getActiveCanvas()
    -- Distinct color only on the far-left buffer column; Mirror X shows it on the right.
    canvas:edit(0, 8, 2)
    canvas:edit(255, 8, 1)

    local sx, sy, sw = win:getInsetContentScreenRect()
    -- Inclusive right edge: Mirror X maps this visual X to canvas x=0.
    local clickX = sx + sw
    local clickY = sy + 8

    local cx, cy = PixelSel.screenToCanvasPixel(win, clickX, clickY)
    expect(cx).toBe(0)
    expect(cy).toBe(8)

    local focused = win
    local status = nil
    local env = {
      ctx = {
        app = { editTool = "brush", undoRedo = UndoRedoController.new(20) },
        getMode = function() return "edit" end,
        wm = function()
          return {
            getFocus = function() return focused end,
            windowAt = function() return win end,
            setFocus = function(_, target) focused = target end,
          }
        end,
        setPainting = function() end,
        setStatus = function(text) status = text end,
        paintAt = function() end,
      },
      utils = {
        shiftDown = function() return false end,
        ctrlDown = function() return false end,
        altDown = function() return false end,
        fillDown = function() return false end,
        grabDown = function() return false end,
        colorMaskDown = function() return true end,
      },
      chrome = {
        findToolbarWindowAt = function() return nil end,
        getTopInteractiveWindowAt = function() return win end,
        getTopInteractiveSurfaceWindowAt = function() return win end,
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
    }
    _G.ctx = env.ctx

    expect(MouseClickController.handleMousePressed(env, clickX, clickY, 1)).toBe(true)
    expect(PixelSel.hasColorPaintMask(win)).toBe(true)
    expect(PixelSel.getColorPaintMask(win).color).toBe(2)
    expect(PixelSel.allowsColorPaintAt(win, 0, 8)).toBe(true)
    expect(PixelSel.allowsColorPaintAt(win, 255, 8)).toBe(false)
    expect(type(status) == "string" and status:find("Color mask", 1, true) ~= nil).toBe(true)

    _G.ctx = nil
  end)

  it("left or right click outside an active selection stamps and clears it", function()
    local MouseClickController = require("controllers.input.mouse_click_controller")
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ x = 0, y = 0 })
    local canvas = win:getActiveCanvas()
    paintRect(canvas, 0, 0, 4, 4, 3)
    _G.ctx = { getMode = function() return "edit" end }

    local ur = UndoRedoController.new(20)
    local app = { undoRedo = ur, editTool = "rect_select" }

    PixelSel.begin(win, PixelSel.KIND_RECT, 0, 0)
    PixelSel.updateDrag(win, 3, 3)
    PixelSel.commitDrag(win)
    expect(PixelSel.ensureLifted(win, app)).toBe(true)
    expect(canvas:getPixel(0, 0)).toBe(0)

    PixelSel.beginMove(win, 1, 1, app)
    PixelSel.updateMove(win, 9, 1)
    PixelSel.endMove(win)

    -- Force content mapping so the press is always outside the moved selection.
    win.toContentCoords = function()
      return true, 100, 100
    end

    local env = {
      ctx = {
        app = app,
        getMode = function() return "edit" end,
        wm = function() return wm end,
        setPainting = function() end,
        setStatus = function() end,
      },
      utils = {
        shiftDown = function() return false end,
        ctrlDown = function() return false end,
        colorMaskDown = function() return false end,
      },
      chrome = {
        findToolbarWindowAt = function() return nil end,
        getTopInteractiveWindowAt = function() return win end,
        getTopInteractiveSurfaceWindowAt = function() return win end,
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
      },
      getTileClick = function() return { active = false } end,
      setTileClick = function() end,
      getSpriteClick = function() return { active = false } end,
      setSpriteClick = function() end,
      beginContextMenuClick = function() end,
    }

    wm:setFocus(win)

    expect(MouseClickController.handleMousePressed(env, 10, 10, 1)).toBe(true)
    -- Left outside applies then starts a pending gesture; unmoved release discards it.
    expect(PixelSel.getSelection(win)).toBeTruthy()
    expect(PixelSel.getSelection(win).dismissIfUnmoved).toBe(true)
    expect(PixelSel.commitDrag(win)).toBe(true)
    expect(PixelSel.hasSelection(win)).toBe(false)
    expect(canvas:getPixel(8, 0)).toBe(3)

    paintRect(canvas, 0, 0, 4, 4, 2)
    PixelSel.begin(win, PixelSel.KIND_RECT, 0, 0)
    PixelSel.updateDrag(win, 3, 3)
    PixelSel.commitDrag(win)
    expect(PixelSel.ensureLifted(win, app)).toBe(true)
    PixelSel.beginMove(win, 1, 1, app)
    PixelSel.updateMove(win, 9, 1)
    PixelSel.endMove(win)
    expect(MouseClickController.handleMousePressed(env, 10, 10, 2)).toBe(true)
    expect(PixelSel.hasSelection(win)).toBe(false)
    expect(canvas:getPixel(8, 0)).toBe(2)

    -- Left outside + drag creates a replacement selection.
    paintRect(canvas, 0, 0, 4, 4, 1)
    PixelSel.begin(win, PixelSel.KIND_RECT, 0, 0)
    PixelSel.updateDrag(win, 3, 3)
    PixelSel.commitDrag(win)
    expect(MouseClickController.handleMousePressed(env, 10, 10, 1)).toBe(true)
    local pending = PixelSel.getSelection(win)
    expect(pending).toBeTruthy()
    expect(pending.dismissIfUnmoved).toBe(true)
    PixelSel.updateDrag(win, 108, 108)
    expect(PixelSel.commitDrag(win)).toBe(true)
    expect(PixelSel.hasSelection(win)).toBe(true)
    local replaced = PixelSel.getSelection(win)
    expect(replaced.w > 1 or replaced.h > 1).toBe(true)

    _G.ctx = nil
  end)

  it("flips and rotates a rectangular pixel selection around its center", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    _G.ctx = { getMode = function() return "edit" end }
    local app = { undoRedo = UndoRedoController.new(20) }

    canvas:edit(4, 4, 1)
    canvas:edit(5, 4, 2)
    canvas:edit(4, 5, 3)
    canvas:edit(5, 5, 1)
    canvas:edit(4, 6, 2)
    canvas:edit(5, 6, 3)

    PixelSel.begin(win, PixelSel.KIND_RECT, 4, 4)
    PixelSel.updateDrag(win, 5, 6)
    expect(PixelSel.commitDrag(win)).toBe(true)

    expect(PixelSel.transformSelection(win, "flip_x", app)).toBe(true)
    expect(PixelSel.stampDown(win, app)).toBe(true)
    expect(canvas:getPixel(4, 4)).toBe(2)
    expect(canvas:getPixel(5, 4)).toBe(1)
    expect(canvas:getPixel(4, 5)).toBe(1)
    expect(canvas:getPixel(5, 5)).toBe(3)
    expect(canvas:getPixel(4, 6)).toBe(3)
    expect(canvas:getPixel(5, 6)).toBe(2)

    PixelSel.begin(win, PixelSel.KIND_RECT, 4, 4)
    PixelSel.updateDrag(win, 5, 6)
    PixelSel.commitDrag(win)
    expect(PixelSel.transformSelection(win, "flip_y", app)).toBe(true)
    expect(PixelSel.stampDown(win, app)).toBe(true)
    expect(canvas:getPixel(4, 4)).toBe(3)
    expect(canvas:getPixel(5, 4)).toBe(2)
    expect(canvas:getPixel(4, 6)).toBe(2)
    expect(canvas:getPixel(5, 6)).toBe(1)

    -- Restore a 2x3 block and rotate 90° CW: 2x3 -> 3x2, origin shifts to keep center.
    paintRect(canvas, 4, 4, 2, 3, 0)
    canvas:edit(4, 4, 1)
    canvas:edit(5, 4, 2)
    canvas:edit(4, 5, 3)
    canvas:edit(5, 5, 0)
    canvas:edit(4, 6, 1)
    canvas:edit(5, 6, 3)
    PixelSel.begin(win, PixelSel.KIND_RECT, 4, 4)
    PixelSel.updateDrag(win, 5, 6)
    PixelSel.commitDrag(win)
    expect(PixelSel.transformSelection(win, "rotate_cw", app)).toBe(true)
    local sel = PixelSel.getSelection(win)
    expect(sel.w).toBe(3)
    expect(sel.h).toBe(2)
    expect(sel.x).toBe(3)
    expect(sel.y).toBe(4)
    expect(PixelSel.stampDown(win, app)).toBe(true)
    expect(canvas:getPixel(3, 4)).toBe(1)
    expect(canvas:getPixel(4, 4)).toBe(3)
    expect(canvas:getPixel(5, 4)).toBe(1)
    expect(canvas:getPixel(3, 5)).toBe(3)
    expect(canvas:getPixel(4, 5)).toBe(0)
    expect(canvas:getPixel(5, 5)).toBe(2)
    expect(canvas:getPixel(4, 6)).toBe(0)
    expect(canvas:getPixel(5, 6)).toBe(0)

    _G.ctx = nil
  end)

  it("rotates a freeform mask with the floating pixels", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    _G.ctx = { getMode = function() return "edit" end }
    local app = { undoRedo = UndoRedoController.new(20) }

    paintRect(canvas, 2, 2, 4, 4, 2)
    PixelSel.begin(win, PixelSel.KIND_FREE, 2, 2)
    PixelSel.updateDrag(win, 5, 2)
    PixelSel.updateDrag(win, 5, 5)
    PixelSel.updateDrag(win, 2, 5)
    expect(PixelSel.commitDrag(win)).toBe(true)
    local before = PixelSel.getSelection(win)
    expect(before.mask).toBeTruthy()
    local hitBefore = PixelSel.hitTest(win, 3, 3)

    expect(PixelSel.transformSelection(win, "rotate_ccw", app)).toBe(true)
    local after = PixelSel.getSelection(win)
    expect(after.mask).toBeTruthy()
    expect(after.w).toBe(before.h)
    expect(after.h).toBe(before.w)
    expect(PixelSel.hasFloatingSelection(win)).toBe(true)
    expect(hitBefore).toBe(true)

    _G.ctx = nil
  end)

  it("H / V / R keyboard shortcuts transform a sketch pixel selection", function()
    local KeyboardSelectionActionsController = require("controllers.input.keyboard_selection_actions_controller")
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local canvas = win:getActiveCanvas()
    local statuses = {}
    local utils = {
      ctrlDown = function() return false end,
      altDown = function() return false end,
      shiftDown = function() return false end,
    }
    local ctx = {
      getMode = function() return "edit" end,
      app = { undoRedo = UndoRedoController.new(20) },
      setStatus = function(msg) statuses[#statuses + 1] = msg end,
    }
    _G.ctx = ctx

    canvas:edit(4, 4, 1)
    canvas:edit(5, 4, 2)
    canvas:edit(4, 5, 3)
    canvas:edit(5, 5, 1)
    PixelSel.begin(win, PixelSel.KIND_RECT, 4, 4)
    PixelSel.updateDrag(win, 5, 5)
    PixelSel.commitDrag(win)

    expect(KeyboardSelectionActionsController.handleSketchPixelTransform(ctx, utils, "h", win)).toBe(true)
    expect(PixelSel.hasFloatingSelection(win)).toBe(true)
    expect(PixelSel.stampDown(win, ctx.app)).toBe(true)
    expect(canvas:getPixel(4, 4)).toBe(2)
    expect(canvas:getPixel(5, 4)).toBe(1)

    PixelSel.begin(win, PixelSel.KIND_RECT, 4, 4)
    PixelSel.updateDrag(win, 5, 5)
    PixelSel.commitDrag(win)
    expect(KeyboardSelectionActionsController.handleSketchPixelTransform(ctx, utils, "v", win)).toBe(true)
    expect(PixelSel.stampDown(win, ctx.app)).toBe(true)
    expect(canvas:getPixel(4, 4)).toBe(1)
    expect(canvas:getPixel(4, 5)).toBe(2)

    PixelSel.begin(win, PixelSel.KIND_RECT, 4, 4)
    PixelSel.updateDrag(win, 5, 5)
    PixelSel.commitDrag(win)
    expect(KeyboardSelectionActionsController.handleSketchPixelTransform(ctx, utils, "r", win)).toBe(true)
    utils.shiftDown = function() return true end
    expect(KeyboardSelectionActionsController.handleSketchPixelTransform(ctx, utils, "r", win)).toBe(true)
    expect(PixelSel.stampDown(win, ctx.app)).toBe(true)
    expect(canvas:getPixel(4, 4)).toBe(1)
    expect(canvas:getPixel(5, 4)).toBe(3)
    expect(#statuses).toBeGreaterThan(0)

    ctx.getMode = function() return "tile" end
    PixelSel.begin(win, PixelSel.KIND_RECT, 4, 4)
    PixelSel.updateDrag(win, 5, 5)
    PixelSel.commitDrag(win)
    expect(KeyboardSelectionActionsController.handleSketchPixelTransform(ctx, utils, "h", win)).toBe(false)

    _G.ctx = nil
  end)
end)
