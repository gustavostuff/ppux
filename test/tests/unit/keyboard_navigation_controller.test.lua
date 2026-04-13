local KeyboardNavigationController = require("controllers.input.keyboard_navigation_controller")

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
