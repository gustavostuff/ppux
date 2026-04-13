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
      getClipboardToolbarActionState = function()
        return { allowed = true }
      end,
      setStatus = function() end,
      showToast = function() end,
    }

    AppTopToolbarController.syncLayout(app)
    local openButton = app._appTopQuickButtons.open
    local newButton = app._appTopQuickButtons.newWindow
    local saveButton = app._appTopQuickButtons.save
    local copyButton = app._appTopQuickButtons.copy
    local cutButton = app._appTopQuickButtons.cut
    local pasteButton = app._appTopQuickButtons.paste

    expect(newButton.x > openButton.x).toBe(true)
    expect(saveButton.x > newButton.x).toBe(true)
    expect(copyButton.x > saveButton.x).toBe(true)
    expect(cutButton.x > copyButton.x).toBe(true)
    expect(pasteButton.x > cutButton.x).toBe(true)

    local inferredGap = newButton.x - (openButton.x + openButton.w)
    expect(saveButton.x).toBe(newButton.x + newButton.w + inferredGap)
    expect(copyButton.x).toBe(saveButton.x + saveButton.w + inferredGap)
    expect(cutButton.x).toBe(copyButton.x + copyButton.w + inferredGap)
    expect(pasteButton.x).toBe(cutButton.x + cutButton.w + inferredGap)
  end)

  it("routes copy/cut/paste buttons through shared app clipboard actions", function()
    local actions = {}
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
      performClipboardToolbarAction = function(_, action)
        actions[#actions + 1] = action
      end,
      getClipboardToolbarActionState = function()
        return { allowed = true }
      end,
      setStatus = function() end,
      showToast = function() end,
    }

    AppTopToolbarController.syncLayout(app)
    local copyButton = app._appTopQuickButtons.copy
    local cutButton = app._appTopQuickButtons.cut
    local pasteButton = app._appTopQuickButtons.paste

    local function click(button)
      local x = button.x + math.floor(button.w * 0.5)
      local y = button.y + math.floor(button.h * 0.5)
      expect(AppTopToolbarController.mousepressed(app, x, y, 1)).toBe(true)
      AppTopToolbarController.mousereleasedQuickButtons(app, x, y, 1)
    end

    click(copyButton)
    click(cutButton)
    click(pasteButton)

    expect(actions[1]).toBe("copy")
    expect(actions[2]).toBe("cut")
    expect(actions[3]).toBe("paste")
  end)

  it("updates clipboard button enabled state from capability checks", function()
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
      getClipboardToolbarActionState = function(_, action)
        if action == "paste" then
          return { allowed = false, reason = "Clipboard is empty" }
        end
        return { allowed = true }
      end,
      setStatus = function() end,
      showToast = function() end,
    }

    AppTopToolbarController.syncLayout(app)
    expect(app._appTopQuickButtons.copy.enabled).toBe(true)
    expect(app._appTopQuickButtons.cut.enabled).toBe(true)
    expect(app._appTopQuickButtons.paste.enabled).toBe(false)
  end)
end)
