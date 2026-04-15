local AppSettingsController = require("controllers.app.settings_controller")

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
    expect(loaded).toEqual({
      skipSplash = true,
      theme = "dark",
      tooltipsEnabled = false,
      canvasImageMode = "stretch",
      canvasFilter = "soft",
      paletteLinks = "on_hover",
      separateToolbar = false,
      groupedPaletteWindows = true,
      recentProjects = {
        "/tmp/foo",
        "/tmp/bar",
      },
    })
  end)
end)
