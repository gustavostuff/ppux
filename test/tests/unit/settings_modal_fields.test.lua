local SettingsFields = require("user_interface.modals.settings_modal_fields")

describe("settings_modal_fields.lua", function()
  it("builds general tab rows with core toggles", function()
    local modal = {
      getFullscreen = function() return false end,
      getTooltipsEnabled = function() return true end,
      getSeparateToolbar = function() return false end,
      getNeverShowResizeHandle = function() return false end,
    }
    local rows = SettingsFields.buildGeneralTabRows(modal)
    expect(#rows).toBe(4)
    expect(rows[1].id).toBe("fullscreen")
    expect(rows[#rows].id).toBe("never_show_resize_handle")
  end)

  it("includes appearance dropdowns when widgets are present", function()
    local modal = {
      getTheme = function() return "dark" end,
      _canvasImageModeDropdown = { id = "scale" },
      _windowLinksDropdown = { id = "links" },
    }
    local rows = SettingsFields.buildAppearanceTabRows(modal)
    expect(rows[1].id).toBe("theme")
    expect(rows[2].dropdown.id).toBe("scale")
    expect(rows[#rows].dropdown.id).toBe("links")
  end)

  it("builds CRT extra rows when CRT mode is enabled", function()
    local slider = { id = "crt_curve" }
    local rows = SettingsFields.buildExtraGeneralRows({
      getGroupedPaletteWindows = function() return false end,
      applyGroupedPaletteWindows = function() end,
      crtModeEnabled = true,
      crtFilterKind = "curve",
      crtCurveSlider = slider,
      showCrtCanvasResolutionSetting = false,
    })
    expect(#rows).toBe(2)
    expect(rows[1].id).toBe("grouped_palette_windows")
    expect(rows[2].component).toBe(slider)
  end)
end)
