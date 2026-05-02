local KeyboardWindowShortcutsController = require("controllers.input.keyboard_window_shortcuts_controller")
local ResolutionController = require("controllers.app.resolution_controller")
describe("keyboard_window_shortcuts_controller.lua - fullscreen handling", function()
  it("always restores 2x window scale when exiting fullscreen", function()
    local oldGetFullscreen = love.window.getFullscreen
    local oldGetMode = love.window.getMode
    local oldUpdateMode = love.window.updateMode
    local oldRecalculate = ResolutionController.recalculate
    local fullscreen = true
    local updateCall = nil

    love.window.getFullscreen = function()
      return fullscreen
    end
    love.window.getMode = function()
      return 1920, 1080, {
        fullscreen = fullscreen,
        resizable = true,
        borderless = false,
        centered = true,
        vsync = 1,
        msaa = 0,
      }
    end
    love.window.updateMode = function(w, h, flags)
      updateCall = { w = w, h = h, flags = flags }
      return true
    end
    ResolutionController.recalculate = function() end

    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      _windowedScalePreference = 3,
    }
    local ctx = { app = app }
    local utils = {
      ctrlDown = function() return true end,
    }

    local handled = KeyboardWindowShortcutsController.handleFullscreen(ctx, utils, "f")

    love.window.getFullscreen = oldGetFullscreen
    love.window.getMode = oldGetMode
    love.window.updateMode = oldUpdateMode
    ResolutionController.recalculate = oldRecalculate

    expect(handled).toBe(true)
    expect(updateCall).toBeTruthy()
    expect(updateCall.w).toBe(1280)
    expect(updateCall.h).toBe(720)
    expect(updateCall.flags.fullscreen).toBe(false)
    expect(updateCall.flags.resizable).toBe(true)
    expect(updateCall.flags.borderless).toBe(false)
    expect(updateCall.flags.centered).toBe(true)
    expect(updateCall.flags.vsync).toBe(1)
    expect(updateCall.flags.msaa).toBe(0)
    expect(updateCall.flags.x).toBeNil()
    expect(updateCall.flags.y).toBeNil()
    expect(app._windowedScalePreference).toBe(2)
  end)

  it("exits fullscreen with a single updateMode call when changing window scale", function()
    local oldGetFullscreen = love.window.getFullscreen
    local oldGetMode = love.window.getMode
    local oldUpdateMode = love.window.updateMode
    local oldRecalculate = ResolutionController.recalculate

    local fullscreen = true
    local updateCall = nil

    love.window.getFullscreen = function()
      return fullscreen
    end
    love.window.getMode = function()
      return 1920, 1080, {
        fullscreen = fullscreen,
        resizable = false,
        borderless = false,
        centered = true,
        vsync = 1,
        msaa = 0,
      }
    end
    love.window.updateMode = function(w, h, flags)
      fullscreen = (flags.fullscreen == true)
      updateCall = { w = w, h = h, flags = flags }
      return true
    end
    ResolutionController.recalculate = function() end

    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
    }
    local ctx = { app = app }
    local utils = {
      ctrlDown = function() return true end,
    }

    local handled = KeyboardWindowShortcutsController.handleWindowScaling(ctx, utils, "3", app)

    love.window.getFullscreen = oldGetFullscreen
    love.window.getMode = oldGetMode
    love.window.updateMode = oldUpdateMode
    ResolutionController.recalculate = oldRecalculate

    expect(handled).toBe(true)
    expect(updateCall).toBeTruthy()
    expect(updateCall.w).toBe(1920)
    expect(updateCall.h).toBe(1080)
    expect(updateCall.flags.fullscreen).toBe(false)
  end)
end)

describe("keyboard_window_shortcuts_controller.lua - space highlight toggle", function()
  it("toggles show-all-items mode on space", function()
    local active = false
    local statuses = {}

    local ctx = {
      toggleSpaceHighlightActive = function()
        active = not active
        return active
      end,
      setStatus = function(text)
        statuses[#statuses + 1] = text
      end,
    }
    local utils = {
      ctrlDown = function() return false end,
      altDown = function() return false end,
    }

    expect(KeyboardWindowShortcutsController.handleSpaceHighlightToggle(ctx, utils, "space")).toBe(true)
    expect(active).toBe(true)
    expect(#statuses).toBe(0)

    expect(KeyboardWindowShortcutsController.handleSpaceHighlightToggle(ctx, utils, "space")).toBe(true)
    expect(active).toBe(false)
    expect(#statuses).toBe(0)
  end)
end)

describe("keyboard_window_shortcuts_controller.lua - grid toggle shortcut", function()
  it("requires Ctrl+G to toggle the focused window grid", function()
    local ctx = {
      setStatus = function() end,
    }
    local focus = {
      showGrid = "off",
    }
    local utils = {
      ctrlDown = function() return false end,
    }

    expect(KeyboardWindowShortcutsController.handleGridToggleInWindow(ctx, utils, "g", focus)).toBe(false)
    expect(focus.showGrid).toBe("off")

    utils.ctrlDown = function() return true end
    expect(KeyboardWindowShortcutsController.handleGridToggleInWindow(ctx, utils, "g", focus)).toBe(true)
    expect(focus.showGrid).toBe("chess")
  end)
end)

describe("keyboard_edit_toggle_controller.lua - shader toggle shortcut", function()
  it("requires Ctrl+R to toggle layer shader rendering", function()
    local KeyboardEditToggleController = require("controllers.input.keyboard_edit_toggle_controller")
    local status = nil
    local focus = {
      layers = { { kind = "tile", shaderEnabled = true } },
      getActiveLayerIndex = function() return 1 end,
    }
    local ctx = {
      setStatus = function(text) status = text end,
    }
    local utils = {
      ctrlDown = function() return false end,
    }

    expect(KeyboardEditToggleController.handleShaderToggle(ctx, utils, "r", focus)).toBe(false)
    expect(focus.layers[1].shaderEnabled).toBe(true)

    utils.ctrlDown = function() return true end
    expect(KeyboardEditToggleController.handleShaderToggle(ctx, utils, "r", focus)).toBe(true)
    expect(focus.layers[1].shaderEnabled).toBe(false)
    expect(status).toBe(nil)
  end)
end)
