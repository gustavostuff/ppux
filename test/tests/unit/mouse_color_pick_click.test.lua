local WM = require("controllers.window.window_controller")
local MouseClickController = require("controllers.input.mouse_click_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

describe("edit-mode right-click color pick (press+release)", function()
  local function makeApp()
    return {
      currentColor = 0,
      brushSize = 1,
      undoRedo = UndoRedoController.new(20),
      setStatus = function() end,
    }
  end

  local function makeEnv(app, win, extras)
    extras = extras or {}
    local focused = win
    local painting = false
    local colorPickPending = nil
    local wmStub
    wmStub = {
      getFocus = function() return focused end,
      windowAt = function() return win end,
      setFocus = function(_, target) focused = target end,
      getWindows = function() return { win } end,
    }
    app.wm = wmStub
    local env = {
      ctx = {
        app = app,
        getMode = function() return "edit" end,
        wm = function() return wmStub end,
        setPainting = function(v) painting = not not v end,
        getPainting = function() return painting end,
        paintAt = function(targetWin, col, row, lx, ly, pickOnly)
          return BrushController.paintPixel(app, targetWin, col, row, lx, ly, pickOnly)
        end,
        setStatus = function() end,
      },
      chrome = {
        handleToolbarClicks = function() return false end,
        handleResizeHandle = function() return false end,
        handleHeaderClick = function() return false end,
        getTopInteractiveSurfaceWindowAt = function(x, y)
          return win
        end,
      },
      utils = {
        grabDown = function() return false end,
        fillDown = function() return false end,
        colorMaskDown = function() return false end,
        ctrlDown = function() return false end,
        shiftDown = function() return false end,
        altDown = function() return false end,
      },
      beginColorPickClick = function(x, y, hitWin, opts)
        colorPickPending = {
          x = x,
          y = y,
          win = hitWin,
          clearMask = opts and opts.clearMask == true,
        }
      end,
      beginContextMenuClick = function() end,
    }
    for k, v in pairs(extras) do
      env[k] = v
    end
    return env, function() return colorPickPending end, function() return painting end
  end

  it("defers color pick until finishEditModeColorPickClick (not on press)", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ x = 10, y = 40 })
    local app = makeApp()
    local canvas = win.layers[1].canvas
    local sx, sy = win:getInsetContentScreenRect()
    canvas:edit(0, 0, 2)

    local pickCalls = {}
    local env, getPending = makeEnv(app, win)
    env.ctx.paintAt = function(targetWin, col, row, lx, ly, pickOnly)
      pickCalls[#pickCalls + 1] = { pickOnly = pickOnly }
      app.currentColor = 2 -- simulate pick
      return true
    end

    local clickX, clickY = sx + 0.5, sy + 0.5
    local handled = MouseClickController.handleMousePressed(env, clickX, clickY, 2)
    expect(handled).toBe(true)
    expect(app.currentColor).toBe(0) -- not picked on press
    expect(#pickCalls).toBe(0)
    expect(getPending()).toBeTruthy()
    expect(getPending().win).toBe(win)

    local finished = MouseClickController.finishEditModeColorPickClick(env, clickX, clickY, win, {})
    expect(finished).toBe(true)
    expect(#pickCalls).toBe(1)
    expect(pickCalls[1].pickOnly).toBe(true)
    expect(app.currentColor).toBe(2)
  end)

  it("does not begin color pick on middle mouse (button 3)", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ x = 10, y = 40 })
    local app = makeApp()
    local sx, sy = win:getInsetContentScreenRect()
    win.layers[1].canvas:edit(0, 0, 2)

    local env, getPending = makeEnv(app, win)
    MouseClickController.handleMousePressed(env, sx + 0.5, sy + 0.5, 3)
    expect(getPending()).toBeNil()
    expect(app.currentColor).toBe(0)
  end)

  it("finishEditModeColorPickClick still picks after small release offset", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ x = 10, y = 40 })
    local app = makeApp()
    local sx, sy = win:getInsetContentScreenRect()
    local env = makeEnv(app, win)
    env.ctx.paintAt = function()
      app.currentColor = 3
      return true
    end
    local clickX, clickY = sx + 0.5, sy + 0.5
    MouseClickController.handleMousePressed(env, clickX, clickY, 2)
    expect(MouseClickController.finishEditModeColorPickClick(
      env, clickX + 0.5, clickY, win, {}
    )).toBe(true)
    expect(app.currentColor).toBe(3)
  end)
end)
