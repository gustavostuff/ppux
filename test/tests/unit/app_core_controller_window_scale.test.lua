local AppCoreController = require("controllers.app.core_controller")

describe("app_core_controller.lua - window scale fallback", function()
  it("falls back to 2x when fullscreen width cannot be mapped to a valid window scale", function()
    local oldGetWidth = love.graphics.getWidth

    love.graphics.getWidth = function()
      return 2560
    end

    local app = setmetatable({
      canvas = {
        getWidth = function() return 640 end,
      },
    }, AppCoreController)

    local scale = app:_getWindowScaleForSettings()

    love.graphics.getWidth = oldGetWidth

    expect(scale).toBe(2)
  end)
end)
