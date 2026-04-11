local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")

describe("app_top_toolbar_controller.lua", function()
  it("routes Open quick button to open-project modal without ROM gating", function()
    local openCalls = 0
    local warningStatus = nil
    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      separateToolbar = false,
      hasLoadedROM = function() return false end,
      showOpenProjectModal = function()
        openCalls = openCalls + 1
      end,
      setStatus = function(_, text)
        warningStatus = text
      end,
      showToast = function()
      end,
    }

    AppTopToolbarController.syncLayout(app)
    local openButton = app._appTopQuickButtons.open
    expect(openButton).toBeTruthy()

    local clickX = openButton.x + math.floor(openButton.w * 0.5)
    local clickY = openButton.y + math.floor(openButton.h * 0.5)
    expect(AppTopToolbarController.mousepressed(app, clickX, clickY, 1)).toBe(true)
    expect(openCalls).toBe(1)
    expect(warningStatus).toBe(nil)
  end)
end)
