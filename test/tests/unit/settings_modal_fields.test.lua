local SettingsFields = require("ui.modals.settings_modal_fields")
local SettingsModal = require("ui.modals.settings_modal")

describe("settings_modal_fields.lua", function()
  it("builds general tab rows with core toggles", function()
    local modal = {
      getFullscreen = function() return false end,
      getTooltipsEnabled = function() return true end,
      getSeparateToolbar = function() return false end,
      getNeverShowResizeHandle = function() return false end,
    }
    local enabled = false
    modal.getGroupTaskbarByKind = function()
      return enabled
    end
    modal.onSetGroupTaskbarByKind = function(value)
      enabled = value == true
    end
    local rows = SettingsFields.buildGeneralTabRows(modal)
    expect(#rows).toBe(5)
    expect(rows[1].id).toBe("fullscreen")
    expect(rows[4].id).toBe("never_show_resize_handle")
    expect(rows[5].id).toBe("group_taskbar_by_kind")
    expect(rows[5].label).toBe("Group per kind")
    expect(rows[5].buttonSpec.getText()).toBe("Off")
    rows[5].buttonSpec.action()
    expect(enabled).toBe(true)
    expect(rows[5].buttonSpec.getText()).toBe("On")
  end)

  it("toggles Group per kind from the settings dialog", function()
    local enabled = false
    local dialog = SettingsModal.new()
    dialog:show({
      getFullscreen = function() return false end,
      getTooltipsEnabled = function() return true end,
      getSeparateToolbar = function() return false end,
      getNeverShowResizeHandle = function() return false end,
      getGroupTaskbarByKind = function() return enabled end,
      onSetGroupTaskbarByKind = function(value)
        enabled = value == true
      end,
      getExtraRows = function() return {} end,
    })

    local function groupButton()
      for _, entry in ipairs(dialog.buttons) do
        if entry.id == "group_taskbar_by_kind_toggle" then
          return entry
        end
      end
      return nil
    end

    local entry = groupButton()
    expect(entry).toBeTruthy()
    expect(entry.button.text).toBe("Off")
    dialog:_activateButton(entry)
    expect(enabled).toBe(true)
    entry = groupButton()
    expect(entry.button.text).toBe("On")
  end)

  it("includes appearance dropdowns when widgets are present", function()
    local modal = {
      getTheme = function() return "dark" end,
      _canvasImageModeDropdown = { id = "scale" },
      _windowShadowStrengthSlider = { id = "strength" },
      _modalOverlayOpacitySlider = { id = "overlay" },
      _windowLinksDropdown = { id = "links" },
    }
    local rows = SettingsFields.buildAppearanceTabRows(modal)
    expect(rows[1].id).toBe("theme")
    expect(rows[2].dropdown.id).toBe("scale")
    local overlayRow = nil
    local strengthRow = nil
    for _, row in ipairs(rows) do
      if row.id == "modal_overlay_opacity" then
        overlayRow = row
      elseif row.id == "window_shadow_strength" then
        strengthRow = row
      end
    end
    expect(strengthRow).toBeTruthy()
    expect(overlayRow).toBeTruthy()
    expect(overlayRow.component.id).toBe("overlay")
    expect(rows[#rows].dropdown.id).toBe("links")
  end)

  it("builds CRT extra rows when CRT mode is enabled", function()
    local slider = { id = "crt_curve" }
    local rows = SettingsFields.buildExtraGeneralRows({
      getGroupedPaletteWindows = function() return false end,
      applyGroupedPaletteWindows = function() end,
      getRecentProjectsCount = function() return 0 end,
      clearRecentProjects = function() end,
      crtModeEnabled = true,
      crtFilterKind = "curve",
      crtCurveSlider = slider,
      showCrtCanvasResolutionSetting = false,
    })
    expect(#rows).toBe(3)
    expect(rows[1].id).toBe("grouped_palette_windows")
    expect(rows[2].id).toBe("clear_recent_projects")
    expect(rows[3].component).toBe(slider)
  end)

  it("shows recent project count on the clear button", function()
    local cleared = false
    local rows = SettingsFields.buildExtraGeneralRows({
      getGroupedPaletteWindows = function() return false end,
      getRecentProjectsCount = function() return 3 end,
      clearRecentProjects = function()
        cleared = true
      end,
    })
    local clearRow = rows[2]
    expect(clearRow.id).toBe("clear_recent_projects")
    expect(clearRow.buttonSpec.getText()).toBe("Clear (3)")
    clearRow.buttonSpec.action()
    expect(cleared).toBe(true)
  end)
end)
