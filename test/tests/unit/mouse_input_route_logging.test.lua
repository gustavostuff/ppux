local MouseInput = require("controllers.input.mouse_input")
local DebugController = require("controllers.dev.debug_controller")
local MouseClickController = require("controllers.input.mouse_click_controller")
local MouseWheelController = require("controllers.input.mouse_wheel_controller")
local MouseMoveController = require("controllers.input.mouse_move_controller")
local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")
local MouseWindowChromeController = require("controllers.input.mouse_window_chrome_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local MultiSelectController = require("controllers.input_support.multi_select_controller")

describe("mouse_input.lua - INPUT_ROUTE logging", function()
  local originals
  local logCalls

  local function formatLogCall(call)
    return string.format(call.message, unpack(call.args or {}))
  end

  local function makeWM(focusWin, winUnderMouse)
    return {
      getFocus = function() return focusWin end,
      windowAt = function() return winUnderMouse end,
    }
  end

  beforeEach(function()
    logCalls = {}
    originals = {
      log = DebugController.log,
      click = MouseClickController.handleMousePressed,
      wheel = MouseWheelController.handleWheel,
      move = MouseMoveController.handleMouseMoved,
      tileDrop = MouseTileDropController.handleTileDrop,
      toolbarRelease = MouseWindowChromeController.handleToolbarRelease,
      resizeEnd = MouseWindowChromeController.handleResizeEnd,
      windowDragEnd = MouseWindowChromeController.handleWindowDragEnd,
      finishSpriteMarquee = SpriteController.finishSpriteMarquee,
      isDragging = SpriteController.isDragging,
      finishDrag = SpriteController.finishDrag,
      endDrag = SpriteController.endDrag,
      finishTileMarquee = MultiSelectController.finishTileMarquee,
      resetMulti = MultiSelectController.reset,
    }

    DebugController.log = function(level, category, message, ...)
      logCalls[#logCalls + 1] = {
        level = level,
        category = category,
        message = message,
        args = { ... },
      }
    end

    MouseClickController.handleMousePressed = function() return false end
    MouseWheelController.handleWheel = function() return false end
    MouseMoveController.handleMouseMoved = function() end
    MouseTileDropController.handleTileDrop = function() return false end
    MouseWindowChromeController.handleToolbarRelease = function() return false end
    MouseWindowChromeController.handleResizeEnd = function() return false end
    MouseWindowChromeController.handleWindowDragEnd = function() return false end
    SpriteController.finishSpriteMarquee = function() return false end
    SpriteController.isDragging = function() return false end
    SpriteController.finishDrag = function() end
    SpriteController.endDrag = function() end
    MultiSelectController.finishTileMarquee = function() return false end
    MultiSelectController.reset = function() end

    local focusWin = { kind = "chr", _id = "bank", title = "ROM Banks" }
    local wm = makeWM(focusWin, nil)
    MouseInput.setup({
      wm = function() return wm end,
      getMode = function() return "tile" end,
      getPainting = function() return false end,
      setPainting = function() end,
      app = nil,
    }, { active = false, pending = false }, { active = false }, {})
  end)

  afterEach(function()
    DebugController.log = originals.log
    MouseClickController.handleMousePressed = originals.click
    MouseWheelController.handleWheel = originals.wheel
    MouseMoveController.handleMouseMoved = originals.move
    MouseTileDropController.handleTileDrop = originals.tileDrop
    MouseWindowChromeController.handleToolbarRelease = originals.toolbarRelease
    MouseWindowChromeController.handleResizeEnd = originals.resizeEnd
    MouseWindowChromeController.handleWindowDragEnd = originals.windowDragEnd
    SpriteController.finishSpriteMarquee = originals.finishSpriteMarquee
    SpriteController.isDragging = originals.isDragging
    SpriteController.finishDrag = originals.finishDrag
    SpriteController.endDrag = originals.endDrag
    MultiSelectController.finishTileMarquee = originals.finishTileMarquee
    MultiSelectController.reset = originals.resetMulti
  end)

  it("logs mousepressed route labels", function()
    MouseClickController.handleMousePressed = function() return true end
    MouseInput.mousepressed(10, 20, 1)

    expect(#logCalls).toBeGreaterThan(0)
    local last = logCalls[#logCalls]
    expect(last.category).toBe("INPUT_ROUTE")
    local text = formatLogCall(last)
    expect(string.find(text, "event=mousepressed", 1, true)).toNotBe(nil)
    expect(string.find(text, "route=mouse_click_controller", 1, true)).toNotBe(nil)
  end)

  it("logs mousereleased route labels", function()
    MouseTileDropController.handleTileDrop = function() return true end
    MouseInput.mousereleased(11, 22, 1)

    expect(#logCalls).toBeGreaterThan(0)
    local last = logCalls[#logCalls]
    expect(last.category).toBe("INPUT_ROUTE")
    local text = formatLogCall(last)
    expect(string.find(text, "event=mousereleased", 1, true)).toNotBe(nil)
    expect(string.find(text, "route=tile_drop", 1, true)).toNotBe(nil)
  end)

  it("logs wheelmoved route labels", function()
    MouseWheelController.handleWheel = function() return true end
    MouseInput.wheelmoved(0, -1)

    expect(#logCalls).toBeGreaterThan(0)
    local last = logCalls[#logCalls]
    expect(last.category).toBe("INPUT_ROUTE")
    local text = formatLogCall(last)
    expect(string.find(text, "event=wheelmoved", 1, true)).toNotBe(nil)
    expect(string.find(text, "route=mouse_wheel_controller", 1, true)).toNotBe(nil)
  end)

  it("does not log input route messages for mousemoved", function()
    local beforeCount = #logCalls
    MouseInput.mousemoved(20, 30, 1, 1)
    expect(#logCalls).toBe(beforeCount)
  end)
end)
