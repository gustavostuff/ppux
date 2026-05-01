local AppSettingsController = require("controllers.app.settings_controller")
local app_colors = require("app_colors")

describe("settings_controller.lua - defaults", function()
  it("exposes the persisted base settings table", function()
    expect(AppSettingsController.defaults()).toEqual({
      skipSplash = false,
      theme = "dark",
      tooltipsEnabled = true,
      canvasImageMode = "pixel_perfect",
      canvasFilter = "sharp",
      paletteLinks = "auto_hide",
      separateToolbar = false,
      groupedPaletteWindows = false,
      recentProjects = {},
    })
  end)
end)

describe("settings_controller.lua - persistence", function()
  it("stores splash and canvas settings through love.filesystem", function()
    local function expectAppearanceChromeClose(actual, expected)
      expect(type(actual)).toBe("table")
      for slotId, rgb in pairs(expected) do
        local got = actual[slotId]
        expect(type(got)).toBe("table")
        for i = 1, 3 do
          local d = math.abs((got[i] or 0) - (rgb[i] or 0))
          expect(d < 1e-5).toBe(true)
        end
      end
    end

    local oldFilesystem = love.filesystem
    local files = {}

    love.filesystem = {
      getInfo = function(path)
        if files[path] ~= nil then
          return { type = "file" }
        end
        return nil
      end,
      load = function(path)
        local source = files[path]
        if not source then return nil end
        return load(source, "@" .. path, "t", {})
      end,
      write = function(path, contents)
        files[path] = contents
        return true
      end,
    }

    local ok = AppSettingsController.save({
      canvasImageMode = "stretch",
      canvasFilter = "soft",
      paletteLinks = "on_hover",
      skipSplash = true,
      tooltipsEnabled = false,
      groupedPaletteWindows = true,
      recentProjects = {
        "/tmp/foo.lua",
        "/tmp/foo_edited.nes",
        "/tmp/bar.ppux",
      },
    })
    local loaded = AppSettingsController.load()

    love.filesystem = oldFilesystem

    expect(ok).toBe(true)
    expect(loaded.skipSplash).toBe(true)
    expect(loaded.theme).toBe("dark")
    expect(loaded.tooltipsEnabled).toBe(false)
    expect(loaded.canvasImageMode).toBe("stretch")
    expect(loaded.canvasFilter).toBe("soft")
    expect(loaded.paletteLinks).toBe("on_hover")
    expect(loaded.separateToolbar).toBe(false)
    expect(loaded.groupedPaletteWindows).toBe(true)
    expect(loaded.recentProjects).toEqual({
      "/tmp/foo",
      "/tmp/bar",
    })
    expectAppearanceChromeClose(loaded.appearanceChrome, app_colors.defaultAppearanceChromeAsRgb())
  end)
end)
