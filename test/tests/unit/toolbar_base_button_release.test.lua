local ToolbarBase = require("user_interface.toolbars.toolbar_base")

describe("toolbar_base.lua - button activation", function()
  local function fakeIcon(w, h)
    return {
      getWidth = function() return w or 15 end,
      getHeight = function() return h or 15 end,
    }
  end

  it("cancels button action when press starts inside and release happens outside", function()
    local actionCalls = 0
    local win = {
      getHeaderRect = function() return 10, 20, 100, 15 end,
    }
    local wm = {
      getFocus = function() return win end,
    }

    local toolbar = ToolbarBase.new(win, { h = 15 })
    toolbar.windowController = wm
    toolbar:addButton(fakeIcon(15, 15), function()
      actionCalls = actionCalls + 1
    end, "Test")

    local btn = toolbar.buttons[1]
    expect(btn).toBeTruthy()

    local insideX = btn.x + math.floor(btn.w / 2)
    local insideY = btn.y + math.floor(btn.h / 2)
    local outsideX = btn.x + btn.w + 20
    local outsideY = insideY

    expect(toolbar:mousepressed(insideX, insideY, 1)).toBeTruthy()
    expect(toolbar:mousereleased(outsideX, outsideY, 1)).toBeTruthy()
    expect(actionCalls).toBe(0)
  end)

  it("triggers button action when released inside the pressed button", function()
    local actionCalls = 0
    local win = {
      getHeaderRect = function() return 10, 20, 100, 15 end,
    }
    local wm = {
      getFocus = function() return win end,
    }

    local toolbar = ToolbarBase.new(win, { h = 15 })
    toolbar.windowController = wm
    toolbar:addButton(fakeIcon(15, 15), function()
      actionCalls = actionCalls + 1
    end, "Test")

    local btn = toolbar.buttons[1]
    local x = btn.x + math.floor(btn.w / 2)
    local y = btn.y + math.floor(btn.h / 2)

    expect(toolbar:mousepressed(x, y, 1)).toBeTruthy()
    expect(toolbar:mousereleased(x, y, 1)).toBeTruthy()
    expect(actionCalls).toBe(1)
  end)
end)
