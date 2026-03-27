local Window = require("user_interface.windows_system.window")
local ResolutionController = require("controllers.app.resolution_controller")

describe("window.lua - drag bounds", function()
  local previousCtx
  local previousCanvasWidth
  local previousCanvasHeight

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    previousCanvasWidth = ResolutionController.canvasWidth
    previousCanvasHeight = ResolutionController.canvasHeight

    ResolutionController.canvasWidth = 320
    ResolutionController.canvasHeight = 240
    _G.ctx = {
      taskbar = {
        getTopY = function()
          return 225
        end,
      },
    }
  end)

  afterEach(function()
    _G.ctx = previousCtx
    ResolutionController.canvasWidth = previousCanvasWidth
    ResolutionController.canvasHeight = previousCanvasHeight
  end)

  local function makeWindow()
    local win = Window.new(20, 20, 10, 10, 10, 5, 1, {
      title = "Drag Bounds",
    })
    win.dragging = true
    win.dx = 0
    win.dy = 0
    return win
  end

  it("keeps at least 15 pixels visible when dragged off the right edge", function()
    local win = makeWindow()

    win:mousemoved(500, 20)

    expect(win.x).toBe(305)
  end)

  it("keeps at least 15 pixels visible when dragged off the left edge", function()
    local win = makeWindow()

    win:mousemoved(-500, 20)

    expect(win.x).toBe(-85)
  end)

  it("keeps at least 15 pixels visible when dragged off the top edge", function()
    local win = makeWindow()

    win:mousemoved(20, -500)

    expect(win.y).toBe(-35)
  end)

  it("keeps 15 pixels visible above the taskbar when dragged downward", function()
    local win = makeWindow()

    win:mousemoved(20, 500)

    expect(win.y).toBe(210)
  end)

  it("keeps a collapsed window header above the taskbar", function()
    local win = makeWindow()
    win._collapsed = true

    win:mousemoved(20, 500)

    expect(win.y).toBe(225)
  end)
end)
