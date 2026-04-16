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
