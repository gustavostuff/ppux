local Shared = require("controllers.app.core_controller_shared")

describe("core_controller_shared.lua - modal routing", function()
  local function modal(visible, handlers)
    handlers = handlers or {}
    return {
      isVisible = function() return visible == true end,
      handleKey = handlers.handleKey,
      mousepressed = handlers.mousepressed,
      mousereleased = handlers.mousereleased,
      wheelmoved = handlers.wheelmoved,
      textinput = handlers.textinput,
    }
  end

  it("getTopModal returns the first visible modal in registry order", function()
    local app = {
      quitConfirmModal = modal(false),
      pressEscAgainExitModal = modal(false),
      saveOptionsModal = modal(true),
      settingsModal = modal(true),
    }
    local key, m = Shared.getTopModal(app)
    expect(key).toBe("saveOptionsModal")
    expect(m).toBe(app.saveOptionsModal)
  end)

  it("dispatchTopModalKey routes to the top visible modal", function()
    local seen = nil
    local app = {
      quitConfirmModal = modal(false),
      renameWindowModal = modal(true, {
        handleKey = function(_, key) seen = key end,
      }),
    }
    local handled, modalKey = Shared.dispatchTopModalKey(app, "return")
    expect(handled).toBe(true)
    expect(modalKey).toBe("renameWindowModal")
    expect(seen).toBe("return")
  end)

  it("dispatchModalWheel blocks quit confirm without calling wheelmoved", function()
    local wheelCalls = 0
    local app = {
      quitConfirmModal = modal(true, {
        wheelmoved = function()
          wheelCalls = wheelCalls + 1
        end,
      }),
    }
    expect(Shared.dispatchModalWheel(app, 0, -1)).toBe(true)
    expect(wheelCalls).toBe(0)
  end)

  it("dispatchModalWheel forwards wheel to registered file-picker modals", function()
    local wheelDy = nil
    local app = {
      quitConfirmModal = modal(false),
      pressEscAgainExitModal = modal(false),
      saveOptionsModal = modal(false),
      genericActionsModal = modal(false),
      settingsModal = modal(false),
      newWindowTypeModal = modal(false),
      newWindowModal = modal(false),
      openProjectModal = modal(true, {
        wheelmoved = function(_, dx, dy)
          wheelDy = dy
        end,
      }),
    }
    expect(Shared.dispatchModalWheel(app, 0, -2)).toBe(true)
    expect(wheelDy).toBe(-2)
  end)

  it("routeModalTextInput respects consume-only modals", function()
    local textCalls = 0
    local app = {
      newWindowTypeModal = modal(true),
      newWindowModal = modal(true, {
        textinput = function()
          textCalls = textCalls + 1
        end,
      }),
    }
    expect(Shared.routeModalTextInput(app, "x")).toBe(true)
    expect(textCalls).toBe(0)
  end)

  it("routeModalTextInput calls textinput on the first matching visible modal", function()
    local seen = nil
    local app = {
      newWindowTypeModal = modal(false),
      newWindowModal = modal(true, {
        textinput = function(_, text)
          seen = text
        end,
      }),
    }
    expect(Shared.routeModalTextInput(app, "abc")).toBe(true)
    expect(seen).toBe("abc")
  end)
end)
