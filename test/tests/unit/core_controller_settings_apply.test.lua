local AppCoreController = {}
AppCoreController.__index = AppCoreController
require("controllers.app.core_controller_settings_apply")(AppCoreController)

local AppSettingsController = require("controllers.app.settings_controller")

describe("core_controller_settings_apply.lua", function()
  local savedPatches = {}
  local originalSave = AppSettingsController.save

  beforeEach(function()
    savedPatches = {}
    AppSettingsController.save = function(patch)
      savedPatches[#savedPatches + 1] = patch
      return true
    end
  end)

  afterEach(function()
    AppSettingsController.save = originalSave
  end)

  local function newApp(overrides)
    local app = setmetatable({
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
        setFilter = function() end,
      },
      tooltipController = { visible = true },
    }, AppCoreController)
    if overrides then
      for k, v in pairs(overrides) do
        app[k] = v
      end
    end
    return app
  end

  it("_applyWindowLinksSetting updates runtime mode and persists when requested", function()
    local app = newApp()
    local key = app:_applyWindowLinksSetting("on_hover", true)
    expect(key).toBe("on_hover")
    expect(app.windowLinksMode).toBe("on_hover")
    expect(savedPatches[#savedPatches].windowLinks).toBe("on_hover")
  end)

  it("_applyWindowLinksSetting can skip persistence", function()
    local app = newApp()
    app:_applyWindowLinksSetting("never", false)
    expect(app.windowLinksMode).toBe("never")
    expect(#savedPatches).toBe(0)
  end)

  it("_applyTooltipsEnabledSetting toggles runtime flag and hides active tooltip", function()
    local app = newApp()
    app:_applyTooltipsEnabledSetting(false, true)
    expect(app.tooltipsEnabled).toBe(false)
    expect(app.tooltipController.visible).toBe(false)
    expect(savedPatches[#savedPatches].tooltipsEnabled).toBe(false)
  end)

  it("_applyCanvasFilterSetting updates canvas filter mode", function()
    local app = newApp()
    local filterCalls = {}
    app.canvas.setFilter = function(self, a, b)
      filterCalls[#filterCalls + 1] = { self, a, b }
    end
    local key = app:_applyCanvasFilterSetting("soft", false)
    expect(key).toBe("soft")
    expect(app.canvasFilterMode).toBe("soft")
    expect(filterCalls[1][1]).toBe(app.canvas)
    expect(filterCalls[1][2]).toBe("linear")
    expect(filterCalls[1][3]).toBe("linear")
    expect(#savedPatches).toBe(0)
  end)

  it("_getWindowLinksForSettings prefers runtime mode over file settings", function()
    local app = newApp({ windowLinksMode = "always" })
    expect(app:_getWindowLinksForSettings()).toBe("always")
  end)
end)
