local KeyboardNavigationController = require("controllers.input.keyboard_navigation_controller")
local AnimationWindowUndo = require("controllers.input_support.animation_window_undo")

describe("keyboard_navigation_controller.lua - animation undo", function()
  it("records animation_window_state when a frame layer is added", function()
    local events = {}
    local focus = {
      kind = "animation",
      layers = { { name = "Frame 1" } },
      activeLayer = 1,
      frameDelays = {},
      nonActiveLayerOpacity = 1.0,
      getActiveLayerIndex = function(self)
        return self.activeLayer
      end,
      getLayerCount = function(self)
        return #self.layers
      end,
      addLayerAfterActive = function(self)
        table.insert(self.layers, { name = "Frame 2" })
        return #self.layers
      end,
    }

    local ctx = {
      app = {
        undoRedo = {
          addAnimationWindowStateEvent = function(_, ev)
            events[#events + 1] = ev
          end,
        },
      },
    }

    local handled = KeyboardNavigationController.handleAnimationWindowKeys(ctx, "+", focus)
    expect(handled).toBe(true)
    expect(#events).toBe(1)
    expect(events[1].type).toBe("animation_window_state")
    expect(#focus.layers).toBe(2)

    AnimationWindowUndo.apply(focus, events[1].beforeState)
    expect(#focus.layers).toBe(1)
  end)

  it("records animation_window_state when a frame layer is removed", function()
    local events = {}
    local focus = {
      kind = "animation",
      layers = {
        { name = "Frame 1" },
        { name = "Frame 2" },
      },
      activeLayer = 2,
      frameDelays = {},
      nonActiveLayerOpacity = 1.0,
      selectedByLayer = {},
      getActiveLayerIndex = function(self)
        return self.activeLayer
      end,
      getLayerCount = function(self)
        return #self.layers
      end,
      removeActiveLayer = function(self)
        if #self.layers <= 1 then
          return false
        end
        table.remove(self.layers, self.activeLayer)
        if self.selectedByLayer then
          local idx = self.activeLayer
          self.selectedByLayer[idx] = nil
          for li = idx, #self.layers do
            self.selectedByLayer[li] = self.selectedByLayer[li + 1]
          end
          self.selectedByLayer[#self.layers + 1] = nil
        end
        self.activeLayer = math.min(self.activeLayer, #self.layers)
        if self.activeLayer < 1 then
          self.activeLayer = 1
        end
        return true
      end,
    }

    local ctx = {
      app = {
        undoRedo = {
          addAnimationWindowStateEvent = function(_, ev)
            events[#events + 1] = ev
          end,
        },
      },
    }

    local handled = KeyboardNavigationController.handleAnimationWindowKeys(ctx, "-", focus)
    expect(handled).toBe(true)
    expect(#events).toBe(1)
    expect(events[1].type).toBe("animation_window_state")
    expect(#focus.layers).toBe(1)

    AnimationWindowUndo.apply(focus, events[1].beforeState)
    expect(#focus.layers).toBe(2)
    expect(focus.activeLayer).toBe(2)
  end)
end)

describe("keyboard_navigation_controller.lua - inactive layer opacity", function()
  it("blocks ctrl+up/down opacity changes in PPU pattern layer mode", function()
    local statusText = nil
    local focus = {
      kind = "ppu_frame",
      patternLayerSoloMode = true,
      nonActiveLayerOpacity = 1.0,
      layers = {
        { kind = "tile", opacity = 1.0 },
        { kind = "sprite", opacity = 1.0 },
      },
      getActiveLayerIndex = function() return 1 end,
    }

    local handled = KeyboardNavigationController.handleInactiveLayerOpacity({
      setStatus = function(text) statusText = text end,
    }, {
      ctrlDown = function() return true end,
    }, "up", focus)

    expect(handled).toBe(true)
    expect(statusText).toBe("Inactive layer opacity is disabled in pattern layer mode")
    expect(focus.nonActiveLayerOpacity).toBe(1.0)
    expect(focus.layers[2].opacity).toBe(1.0)
  end)
end)

describe("keyboard_navigation_controller.lua - animation frame delay", function()
  local KeyboardNavigationController = require("controllers.input.keyboard_navigation_controller")
  local WM = require("controllers.window.window_controller")

  local function makeCtx(statusOut)
    return {
      app = {
        undoRedo = {
          addAnimationWindowStateEvent = function() end,
        },
      },
      setStatus = function(text)
        statusOut[1] = text
      end,
    }
  end

  local function shiftUtils()
    return { shiftDown = function() return true end }
  end

  it("adjusts frame delay for tile animation windows with Shift+Left/Right", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({ animated = true, numFrames = 2 })
    local status = {}
    local handled = KeyboardNavigationController.handleAnimationDelayAdjust(
      makeCtx(status),
      shiftUtils(),
      "right",
      win
    )
    expect(handled).toBe(true)
    expect(win.frameDelays[1]).toBe(0.25)
    expect(win.frameDelays[2]).toBe(0.25)
    expect(status[1]).toBe("Frame delay: 0.25s")
  end)

  it("adjusts frame delay for OAM animation windows with Shift+Left/Right", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({ animated = true, oamBacked = true, numFrames = 2 })
    local status = {}
    local handled = KeyboardNavigationController.handleAnimationDelayAdjust(
      makeCtx(status),
      shiftUtils(),
      "left",
      win
    )
    expect(handled).toBe(true)
    expect(win.frameDelays[1]).toBe(0.15)
    expect(status[1]).toBe("Frame delay: 0.15s")
  end)

  it("reports minimum frame delay when already at the lower clamp", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({ animated = true, numFrames = 1 })
    win.frameDelays[1] = 0.1
    local status = {}
    KeyboardNavigationController.handleAnimationDelayAdjust(makeCtx(status), shiftUtils(), "left", win)
    expect(win.frameDelays[1]).toBe(0.1)
    expect(status[1]).toBe("Frame delay: 0.10s (minimum)")
  end)
end)
