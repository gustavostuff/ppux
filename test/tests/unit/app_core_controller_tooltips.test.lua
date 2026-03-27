local AppCoreController = require("controllers.app.core_controller")
local UserInput = require("controllers.input")

local function hiddenModal()
  return {
    isVisible = function() return false end,
  }
end

local function buildApp(windows)
  return setmetatable({
    wm = {
      getWindows = function() return windows end,
    },
    quitConfirmModal = hiddenModal(),
    saveOptionsModal = hiddenModal(),
    genericActionsModal = hiddenModal(),
    settingsModal = hiddenModal(),
    newWindowModal = hiddenModal(),
    splash = hiddenModal(),
  }, AppCoreController)
end

describe("app_core_controller.lua - tooltip hit testing", function()
  it("does not show a lower window tooltip through an overlapping top window", function()
    local oldGetTooltipCandidate = UserInput.getTooltipCandidate
    UserInput.getTooltipCandidate = function() return nil end

    local lower = {
      _closed = false,
      _minimized = false,
      _collapsed = false,
      headerToolbar = {
        contains = function() return true end,
        getTooltipAt = function()
          return { text = "Lower tooltip" }
        end,
      },
      contains = function() return true end,
    }
    local upper = {
      _closed = false,
      _minimized = false,
      _collapsed = false,
      contains = function() return true end,
    }

    local app = buildApp({ lower, upper })
    local candidate = app:getTooltipCandidateAt(40, 20)

    UserInput.getTooltipCandidate = oldGetTooltipCandidate

    expect(candidate).toBeNil()
  end)

  it("does not show a lower window tooltip through an overlapping top toolbar with no tooltip", function()
    local oldGetTooltipCandidate = UserInput.getTooltipCandidate
    UserInput.getTooltipCandidate = function() return nil end

    local lower = {
      _closed = false,
      _minimized = false,
      _collapsed = false,
      headerToolbar = {
        contains = function() return true end,
        getTooltipAt = function()
          return { text = "Lower tooltip" }
        end,
      },
      contains = function() return false end,
    }
    local upper = {
      _closed = false,
      _minimized = false,
      _collapsed = false,
      headerToolbar = {
        contains = function() return true end,
        getTooltipAt = function() return nil end,
      },
      contains = function() return false end,
    }

    local app = buildApp({ lower, upper })
    local candidate = app:getTooltipCandidateAt(40, 20)

    UserInput.getTooltipCandidate = oldGetTooltipCandidate

    expect(candidate).toBeNil()
  end)

  it("still returns the topmost window tooltip when it is the hovered target", function()
    local oldGetTooltipCandidate = UserInput.getTooltipCandidate
    UserInput.getTooltipCandidate = function() return nil end

    local lower = {
      _closed = false,
      _minimized = false,
      _collapsed = false,
      headerToolbar = {
        contains = function() return true end,
        getTooltipAt = function()
          return { text = "Lower tooltip" }
        end,
      },
      contains = function() return false end,
    }
    local upper = {
      _closed = false,
      _minimized = false,
      _collapsed = false,
      headerToolbar = {
        contains = function() return true end,
        getTooltipAt = function()
          return { text = "Upper tooltip" }
        end,
      },
      contains = function() return false end,
    }

    local app = buildApp({ lower, upper })
    local candidate = app:getTooltipCandidateAt(40, 20)

    UserInput.getTooltipCandidate = oldGetTooltipCandidate

    expect(candidate).toEqual({ text = "Upper tooltip" })
  end)

  it("returns no tooltip candidate when tooltips are disabled", function()
    local oldGetTooltipCandidate = UserInput.getTooltipCandidate
    UserInput.getTooltipCandidate = function()
      return { text = "Input tooltip" }
    end

    local app = buildApp({})
    app.tooltipsEnabled = false

    local candidate = app:getTooltipCandidateAt(40, 20)

    UserInput.getTooltipCandidate = oldGetTooltipCandidate

    expect(candidate).toBeNil()
  end)
end)
