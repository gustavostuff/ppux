-- Declarative row specs for the settings modal (General / Appearance tabs).

local M = {}

function M.normalizeThemeKey(key)
  if key == "light" then
    return "light"
  end
  return "dark"
end

function M.buildGeneralTabRows(modal)
  local tooltipsEnabled = not (modal.getTooltipsEnabled and modal.getTooltipsEnabled() == false)
  local rows = {
    {
      id = "fullscreen",
      label = "Full screen",
      buttonSpec = {
        id = "fullscreen_toggle",
        getText = function()
          return (modal.getFullscreen and modal.getFullscreen() == true) and "On" or "Off"
        end,
        action = function()
          if modal.onToggleFullscreen then
            modal.onToggleFullscreen()
          end
        end,
      },
    },
    {
      id = "tooltips_enabled",
      label = "Tooltips",
      buttonSpec = {
        id = "tooltips_enabled_toggle",
        text = tooltipsEnabled and "On" or "Off",
        action = function()
          if modal.onSetTooltipsEnabled then
            modal.onSetTooltipsEnabled(not tooltipsEnabled)
          end
        end,
      },
    },
    {
      id = "separate_toolbar",
      label = "Detached Window Toolbar",
      buttonSpec = {
        id = "separate_toolbar_toggle",
        text = (modal.getSeparateToolbar and modal.getSeparateToolbar() == true) and "On" or "Off",
        action = function()
          if modal.onSetSeparateToolbar then
            modal.onSetSeparateToolbar(not (modal.getSeparateToolbar and modal.getSeparateToolbar() == true))
          end
        end,
      },
    },
  }
  if modal._windowToolbarPlacementDropdown then
    rows[#rows + 1] = {
      id = "window_toolbar_placement",
      label = "Window toolbar position",
      dropdown = modal._windowToolbarPlacementDropdown,
    }
  end
  rows[#rows + 1] = {
    id = "never_show_resize_handle",
    label = "Never show resize handle",
    buttonSpec = {
      id = "never_show_resize_handle_toggle",
      text = (modal.getNeverShowResizeHandle and modal.getNeverShowResizeHandle() == true) and "On" or "Off",
      action = function()
        if modal.onSetNeverShowResizeHandle then
          modal.onSetNeverShowResizeHandle(
            not (modal.getNeverShowResizeHandle and modal.getNeverShowResizeHandle() == true)
          )
        end
      end,
    },
  }
  return rows
end

function M.buildAppearanceTabRows(modal)
  local theme = M.normalizeThemeKey(modal.getTheme and modal.getTheme() or nil)

  local rows = {
    {
      id = "theme",
      label = "Theme",
      buttonSpec = {
        id = "theme_toggle",
        text = (theme == "light") and "Light" or "Dark",
        action = function()
          if modal.onSetTheme then
            modal.onSetTheme((theme == "light") and "dark" or "light")
          end
        end,
      },
    },
  }

  if modal._canvasImageModeDropdown then
    rows[#rows + 1] = {
      id = "canvas_image_mode",
      label = "Canvas scale",
      dropdown = modal._canvasImageModeDropdown,
    }
  end

  if modal._canvasFilterDropdown then
    rows[#rows + 1] = {
      id = "canvas_filter",
      label = "Canvas filter",
      dropdown = modal._canvasFilterDropdown,
    }
  end

  if modal._windowShadowBlurSlider then
    rows[#rows + 1] = {
      id = "window_shadow_blur",
      label = "Window shadow blur",
      component = modal._windowShadowBlurSlider,
    }
  end
  if modal._windowShadowStrengthSlider then
    rows[#rows + 1] = {
      id = "window_shadow_strength",
      label = "Window shadow strength",
      component = modal._windowShadowStrengthSlider,
    }
  end

  if modal._windowLinksDropdown then
    rows[#rows + 1] = {
      id = "window_links",
      label = "Window links",
      dropdown = modal._windowLinksDropdown,
    }
  end

  return rows
end

function M.buildExtraGeneralRows(ctx)
  ctx = ctx or {}
  local rows = {
    {
      id = "grouped_palette_windows",
      label = "Grouped palettes",
      buttonSpec = {
        id = "grouped_palette_windows_toggle",
        getText = function()
          return ctx.getGroupedPaletteWindows and ctx.getGroupedPaletteWindows() and "On" or "Off"
        end,
        action = function()
          if ctx.getGroupedPaletteWindows and ctx.applyGroupedPaletteWindows then
            local enabled = not ctx.getGroupedPaletteWindows()
            ctx.applyGroupedPaletteWindows(enabled)
          end
        end,
      },
    },
  }
  if ctx.crtModeEnabled then
    if ctx.showCrtCanvasResolutionSetting then
      rows[#rows + 1] = {
        id = "crt_canvas_resolution",
        label = "CRT canvas",
        buttonSpec = {
          id = "crt_canvas_resolution_toggle",
          getText = function()
            local cur = ctx.getCrtCanvasResolution and ctx.getCrtCanvasResolution() or "640x360"
            return (cur == "320x180") and "320x180" or "640x360"
          end,
          action = function()
            if ctx.getCrtCanvasResolution and ctx.applyCrtCanvasResolution then
              local cur = ctx.getCrtCanvasResolution()
              local nextKey = (cur == "320x180") and "640x360" or "320x180"
              ctx.applyCrtCanvasResolution(nextKey)
            end
          end,
        },
      }
    end
    if ctx.crtFilterKind ~= "composite" and ctx.crtCurveSlider then
      rows[#rows + 1] = {
        id = "crt_curve",
        label = "CRT curve",
        component = ctx.crtCurveSlider,
      }
    end
  end
  return rows
end

return M
