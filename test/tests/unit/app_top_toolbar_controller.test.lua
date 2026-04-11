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
    local newButton = app._appTopQuickButtons.newWindow
    local saveButton = app._appTopQuickButtons.save
    expect(openButton).toBeTruthy()
    expect(newButton.x).toBe(0)
    expect(saveButton.x).toBe(0)

    local clickX = openButton.x + math.floor(openButton.w * 0.5)
    local clickY = openButton.y + math.floor(openButton.h * 0.5)
    expect(AppTopToolbarController.mousepressed(app, clickX, clickY, 1)).toBe(true)
    expect(openCalls).toBe(1)
    expect(warningStatus).toBe(nil)
  end)

  it("keeps Open first and shows New/Save when project is loaded", function()
    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      separateToolbar = false,
      hasLoadedROM = function() return true end,
      showOpenProjectModal = function() end,
      showNewWindowModal = function() end,
      showSaveOptionsModal = function() end,
      setStatus = function() end,
      showToast = function() end,
    }

    AppTopToolbarController.syncLayout(app)
    local openButton = app._appTopQuickButtons.open
    local newButton = app._appTopQuickButtons.newWindow
    local saveButton = app._appTopQuickButtons.save

    expect(openButton.x).toBe(0)
    expect(newButton.x).toBe(openButton.w)
    expect(saveButton.x).toBe(openButton.w + newButton.w)
  end)
end)
