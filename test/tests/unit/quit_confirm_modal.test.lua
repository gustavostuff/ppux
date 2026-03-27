local QuitConfirmModal = require("user_interface.modals.quit_confirm_modal")
local AppCoreController = require("controllers.app.core_controller")

describe("quit_confirm_modal.lua", function()
  it("executes yes callback on keyboard confirm", function()
    local yesCount = 0
    local noCount = 0
    local modal = QuitConfirmModal.new()

    modal:show({
      onYes = function() yesCount = yesCount + 1 end,
      onNo = function() noCount = noCount + 1 end,
    })

    expect(modal:isVisible()).toBe(true)
    expect(modal:handleKey("y")).toBe(true)
    expect(yesCount).toBe(1)
    expect(noCount).toBe(0)
    expect(modal:isVisible()).toBe(false)
  end)

  it("executes no callback on button click", function()
    local yesCount = 0
    local noCount = 0
    local modal = QuitConfirmModal.new()

    modal:show({
      onYes = function() yesCount = yesCount + 1 end,
      onNo = function() noCount = noCount + 1 end,
    })

    modal.yesButton:setPosition(100, 10)
    modal.yesButton:setSize(56, 20)
    modal.noButton:setPosition(10, 10)
    modal.noButton:setSize(56, 20)

    expect(modal:mousepressed(15, 15, 1)).toBe(true)
    expect(modal:mousereleased(15, 15, 1)).toBe(true)
    expect(yesCount).toBe(0)
    expect(noCount).toBe(1)
    expect(modal:isVisible()).toBe(false)
  end)

  it("closes on escape without invoking callbacks", function()
    local callbackCount = 0
    local modal = QuitConfirmModal.new()

    modal:show({
      onYes = function() callbackCount = callbackCount + 1 end,
      onNo = function() callbackCount = callbackCount + 1 end,
    })

    expect(modal:handleKey("escape")).toBe(true)
    expect(callbackCount).toBe(0)
    expect(modal:isVisible()).toBe(false)
  end)

  it("moves keyboard focus with arrows and confirms focused button on enter", function()
    local yesCount = 0
    local noCount = 0
    local modal = QuitConfirmModal.new()

    modal:show({
      onYes = function() yesCount = yesCount + 1 end,
      onNo = function() noCount = noCount + 1 end,
    })

    expect(modal.yesButton.focused).toBe(true)
    expect(modal.noButton.focused).toBe(false)

    expect(modal:handleKey("right")).toBe(true)
    expect(modal.yesButton.focused).toBe(false)
    expect(modal.noButton.focused).toBe(true)

    expect(modal:handleKey("return")).toBe(true)
    expect(yesCount).toBe(0)
    expect(noCount).toBe(1)
    expect(modal:isVisible()).toBe(false)
  end)

  it("supports y and n keyboard shortcuts regardless of focused button", function()
    local yesCount = 0
    local noCount = 0
    local modal = QuitConfirmModal.new()

    modal:show({
      onYes = function() yesCount = yesCount + 1 end,
      onNo = function() noCount = noCount + 1 end,
    })

    modal:handleKey("right")
    expect(modal.noButton.focused).toBe(true)
    expect(modal:handleKey("y")).toBe(true)
    expect(yesCount).toBe(1)
    expect(noCount).toBe(0)
    expect(modal:isVisible()).toBe(false)

    modal:show({
      onYes = function() yesCount = yesCount + 1 end,
      onNo = function() noCount = noCount + 1 end,
    })
    expect(modal:handleKey("n")).toBe(true)
    expect(yesCount).toBe(1)
    expect(noCount).toBe(1)
    expect(modal:isVisible()).toBe(false)
  end)

  it("uses transparent style for quit dialog buttons", function()
    local modal = QuitConfirmModal.new()
    expect(modal.yesButton.transparent).toBe(true)
    expect(modal.noButton.transparent).toBe(true)
  end)
end)

describe("app_core_controller.lua - quit handling", function()
  local originalQuit
  local originalUserInputKeypressed
  local originalUserInputKeyreleased
  local originalKeyboardIsDown

  beforeEach(function()
    originalQuit = love.event.quit
    originalUserInputKeypressed = require("controllers.input").keypressed
    originalUserInputKeyreleased = require("controllers.input").keyreleased
    originalKeyboardIsDown = love.keyboard.isDown
  end)

  afterEach(function()
    love.event.quit = originalQuit
    require("controllers.input").keypressed = originalUserInputKeypressed
    require("controllers.input").keyreleased = originalUserInputKeyreleased
    love.keyboard.isDown = originalKeyboardIsDown
  end)

  it("aborts first quit request and opens the confirm modal", function()
    local quitCalls = 0
    local modalState = { visible = false, opts = nil }
    local app = setmetatable({
      _allowImmediateQuit = false,
      quitConfirmModal = {
        isVisible = function() return modalState.visible end,
        show = function(_, opts)
          modalState.visible = true
          modalState.opts = opts
        end,
      },
      saveBeforeQuit = function(self)
        self.saved = true
        return true
      end,
      hasUnsavedChanges = function()
        return true
      end,
    }, AppCoreController)

    love.event.quit = function()
      quitCalls = quitCalls + 1
    end

    expect(app:handleQuitRequest()).toBe(true)
    expect(modalState.visible).toBe(true)
    expect(type(modalState.opts.onYes)).toBe("function")
    expect(type(modalState.opts.onNo)).toBe("function")

    modalState.opts.onNo()
    expect(app._allowImmediateQuit).toBe(true)
    expect(app.saved).toBeNil()
    expect(quitCalls).toBe(1)
  end)

  it("saves before quitting when yes is selected", function()
    local quitCalls = 0
    local modalState = { visible = false, opts = nil }
    local app = setmetatable({
      _allowImmediateQuit = false,
      quitConfirmModal = {
        isVisible = function() return modalState.visible end,
        show = function(_, opts)
          modalState.visible = true
          modalState.opts = opts
        end,
      },
      saveBeforeQuit = function(self)
        self.saved = true
        return true
      end,
      hasUnsavedChanges = function()
        return true
      end,
    }, AppCoreController)

    love.event.quit = function()
      quitCalls = quitCalls + 1
    end

    expect(app:handleQuitRequest()).toBe(true)
    modalState.opts.onYes()
    expect(app.saved).toBe(true)
    expect(app._allowImmediateQuit).toBe(true)
    expect(quitCalls).toBe(1)
  end)

  it("allows quit immediately after confirmation flag is set", function()
    local app = setmetatable({
      _allowImmediateQuit = true,
      quitConfirmModal = {
        isVisible = function() return false end,
        show = function() end,
      },
    }, AppCoreController)

    expect(app:handleQuitRequest()).toBe(false)
  end)

  it("does not show confirm modal when there are no unsaved changes", function()
    local showCount = 0
    local app = setmetatable({
      _allowImmediateQuit = false,
      quitConfirmModal = {
        isVisible = function() return false end,
        show = function()
          showCount = showCount + 1
        end,
      },
      hasUnsavedChanges = function()
        return false
      end,
    }, AppCoreController)

    expect(app:handleQuitRequest()).toBe(false)
    expect(showCount).toBe(0)
  end)

  it("dismisses splash on escape without quitting app", function()
    local quitCalls = 0
    local inputCalls = 0
    local userInput = require("controllers.input")

    local app = setmetatable({
      quitConfirmModal = { isVisible = function() return false end },
      genericActionsModal = {
        isVisible = function() return false end,
        handleKey = function() return false end,
      },
      newWindowModal = {
        isVisible = function() return false end,
        handleKey = function() return false end,
      },
      splash = {
        visible = true,
        isVisible = function(self) return self.visible end,
        keypressed = function(self, key)
          if key == "escape" then
            self.visible = false
            return true
          end
          return false
        end,
      },
    }, AppCoreController)

    love.event.quit = function()
      quitCalls = quitCalls + 1
    end
    userInput.keypressed = function()
      inputCalls = inputCalls + 1
    end

    app:keypressed("escape")

    expect(app.splash.visible).toBe(false)
    expect(quitCalls).toBe(0)
    expect(inputCalls).toBe(0)
  end)

  it("does not pass keypress to shortcuts or normal input while a modal is visible", function()
    local userInput = require("controllers.input")
    local keypressCalls = 0
    local modalHandleCalls = 0
    local showNewWindowCalls = 0

    love.keyboard.isDown = function(key)
      return key == "lctrl" or key == "rctrl"
    end

    local app = setmetatable({
      quitConfirmModal = { isVisible = function() return false end, handleKey = function() end },
      saveOptionsModal = { isVisible = function() return false end, handleKey = function() end },
      genericActionsModal = {
        isVisible = function() return false end,
        handleKey = function() end,
      },
      settingsModal = {
        isVisible = function() return true end,
        handleKey = function()
          modalHandleCalls = modalHandleCalls + 1
          return false
        end,
      },
      newWindowModal = {
        isVisible = function() return false end,
        handleKey = function() end,
        show = function()
          showNewWindowCalls = showNewWindowCalls + 1
        end,
      },
      renameWindowModal = {
        isVisible = function() return false end,
        handleKey = function() end,
      },
      splash = {
        isVisible = function() return false end,
        keypressed = function() return false end,
      },
      wm = {},
      hasLoadedROM = function() return true end,
      setStatus = function() end,
    }, AppCoreController)

    userInput.keypressed = function()
      keypressCalls = keypressCalls + 1
    end

    app:keypressed("n")

    expect(modalHandleCalls).toBe(1)
    expect(showNewWindowCalls).toBe(0)
    expect(keypressCalls).toBe(0)
  end)

  it("does not pass keyreleased to normal input while a modal is visible", function()
    local userInput = require("controllers.input")
    local keyreleasedCalls = 0

    local app = setmetatable({
      quitConfirmModal = { isVisible = function() return false end },
      saveOptionsModal = { isVisible = function() return false end },
      genericActionsModal = { isVisible = function() return false end },
      settingsModal = { isVisible = function() return false end },
      newWindowModal = { isVisible = function() return false end },
      renameWindowModal = { isVisible = function() return true end },
      splash = {
        isVisible = function() return false end,
      },
    }, AppCoreController)

    userInput.keyreleased = function()
      keyreleasedCalls = keyreleasedCalls + 1
    end

    app:keyreleased("a")

    expect(keyreleasedCalls).toBe(0)
  end)
end)
