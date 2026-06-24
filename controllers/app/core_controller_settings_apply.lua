local AppSettingsController = require("controllers.app.settings_controller")
local WindowToolbarPlacement = require("controllers.window.window_toolbar_placement")
local ResolutionController = require("controllers.app.resolution_controller")
local KeyboardWindowShortcutsController = require("controllers.input.keyboard_window_shortcuts_controller")
local SettingsModal = require("user_interface.modals.settings_modal")
local SettingsFields = require("user_interface.modals.settings_modal_fields")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")
local Dropdown = require("user_interface.dropdown")
local WindowCaps = require("controllers.window.window_capabilities")
local WindowLinkVisibility = require("controllers.window.window_link_visibility")
local colors = require("app_colors")

return function(AppCoreController)

-- CRT 640x360 vs 320x180: logic and settings persist; toggle row hidden while false.
local SHOW_CRT_CANVAS_RESOLUTION_SETTING_IN_UI = false
function AppCoreController:_getSettingsShortcutContext()
  local ctx = _G.ctx or self:_buildCtx()
  ctx.app = self
  return ctx
end

function AppCoreController:_getWindowScaleForSettings()
  if not self.canvas then return 1 end
  local windowW = love.graphics.getWidth()
  local baseW = self.canvas:getWidth()
  if not (baseW and baseW > 0) then return 1 end

  local scale = math.floor((windowW / baseW) + 0.5)
  if scale >= 1 and scale <= 3 then
    return scale
  end

  local preferred = tonumber(self._windowedScalePreference)
  if preferred and preferred >= 1 and preferred <= 3 then
    return preferred
  end

  return 2
end

function AppCoreController:_getTooltipsEnabledForSettings()
  if self.tooltipsEnabled ~= nil then
    return self.tooltipsEnabled ~= false
  end
  local settings = AppSettingsController.load()
  return not (settings and settings.tooltipsEnabled == false)
end

local function normalizeCanvasImageModeKey(key)
  if key == "pixel_perfect" then return "pixel_perfect" end
  if key == "keep_aspect" then return "keep_aspect" end
  return "stretch"
end

local function canvasImageModeKeyToResolutionMode(key)
  key = normalizeCanvasImageModeKey(key)
  if key == "pixel_perfect" then
    return ResolutionController.modes.PIXEL_PERFECT
  elseif key == "keep_aspect" then
    return ResolutionController.modes.KEEP_ASPECT
  end
  return ResolutionController.modes.STRETCH
end

local function resolutionModeToCanvasImageModeKey(mode)
  if mode == ResolutionController.modes.PIXEL_PERFECT then
    return "pixel_perfect"
  elseif mode == ResolutionController.modes.KEEP_ASPECT then
    return "keep_aspect"
  end
  return "stretch"
end

local function normalizeCanvasFilterKey(key)
  if key == "soft" then return "soft" end
  return "sharp"
end

local function normalizeGroupedPaletteWindows(enabled)
  return enabled == true
end

local function windowFlagsEquivalent(currentFlags, desiredFlags)
  currentFlags = currentFlags or {}
  desiredFlags = desiredFlags or {}
  local booleanKeys = {
    fullscreen = true, resizable = true, borderless = true, centered = true,
    highdpi = true, usedpiscale = true,
  }
  local keys = {
    "fullscreen", "vsync", "msaa", "resizable", "borderless",
    "centered", "display", "highdpi", "usedpiscale", "minwidth", "minheight",
  }
  for _, k in ipairs(keys) do
    local a = currentFlags[k]
    local b = desiredFlags[k]
    if booleanKeys[k] then
      a = (a == true)
      b = (b == true)
    end
    if a ~= b then
      return false
    end
  end
  return true
end

local function copyWindowFlags(flags)
  local out = {}
  for k, v in pairs(flags or {}) do
    out[k] = v
  end
  return out
end

function AppCoreController:_getWindowResizableForSettings()
  local _, _, flags = love.window.getMode()
  if flags and flags.resizable ~= nil then
    return flags.resizable == true
  end
  return false
end

function AppCoreController:_applyWindowResizableSetting(enabled, saveSetting)
  enabled = (enabled == true)
  local w, h, currentFlags = love.window.getMode()
  local flags = copyWindowFlags(currentFlags)
  flags.x = nil
  flags.y = nil
  flags.resizable = enabled
  if (currentFlags and currentFlags.resizable) ~= enabled or (not windowFlagsEquivalent(currentFlags, flags)) then
    love.window.updateMode(w, h, flags)
  end
  return enabled
end

function AppCoreController:_getCanvasImageModeForSettings()
  if ResolutionController.mode ~= nil then
    return normalizeCanvasImageModeKey(resolutionModeToCanvasImageModeKey(ResolutionController.mode))
  end
  local settings = AppSettingsController.load()
  return normalizeCanvasImageModeKey(settings and settings.canvasImageMode)
end

function AppCoreController:_applyCanvasImageModeSetting(modeKey, saveSetting)
  local key = normalizeCanvasImageModeKey(modeKey)
  local targetMode = canvasImageModeKeyToResolutionMode(key)
  if ResolutionController.mode ~= targetMode then
    ResolutionController:setMode(targetMode)
  end
  if saveSetting ~= false then
    AppSettingsController.save({ canvasImageMode = key })
  end
  if saveSetting ~= false and self._refreshSettingsModalIfOpen then
    self:_refreshSettingsModalIfOpen()
  end
  return key
end

function AppCoreController:_getCanvasImageModeDropdownDefaultSpec()
  local m = ResolutionController.mode
  if m == ResolutionController.modes.PIXEL_PERFECT then
    return ResolutionController.modes.PIXEL_PERFECT
  end
  if m == ResolutionController.modes.STRETCH then
    return ResolutionController.modes.STRETCH
  end
  return ResolutionController.modes.KEEP_ASPECT
end

function AppCoreController:_ensureSettingsCanvasImageModeDropdown()
  if self._canvasImageModeDropdown then
    return
  end
  local appRef = self
  self._canvasImageModeDropdownItems = {
    {
      value = ResolutionController.modes.KEEP_ASPECT,
      text = "Keep aspect",
      onPick = function(entry)
        appRef:_applyCanvasImageModeSetting(resolutionModeToCanvasImageModeKey(entry.value), true)
      end,
    },
    {
      value = ResolutionController.modes.PIXEL_PERFECT,
      text = "Pixel-perfect",
      onPick = function(entry)
        appRef:_applyCanvasImageModeSetting(resolutionModeToCanvasImageModeKey(entry.value), true)
      end,
    },
    {
      value = ResolutionController.modes.STRETCH,
      text = "Stretch",
      onPick = function(entry)
        appRef:_applyCanvasImageModeSetting(resolutionModeToCanvasImageModeKey(entry.value), true)
      end,
    },
  }
  self._canvasImageModeDropdown = Dropdown.new({
    getBounds = function()
      return { w = appRef.canvas:getWidth(), h = appRef.canvas:getHeight() }
    end,
    default = self:_getCanvasImageModeDropdownDefaultSpec(),
    tooltip = "How the workspace is scaled to fit the OS window",
    items = self._canvasImageModeDropdownItems,
  })
end

function AppCoreController:_syncSettingsCanvasImageModeDropdown()
  local dd = self._canvasImageModeDropdown
  if not dd or not self._canvasImageModeDropdownItems then
    return
  end
  dd:setGetBounds(function()
    return { w = self.canvas:getWidth(), h = self.canvas:getHeight() }
  end)
  dd._defaultSpec = self:_getCanvasImageModeDropdownDefaultSpec()
  dd:setItems(self._canvasImageModeDropdownItems)
end

function AppCoreController:_getCanvasFilterForSettings()
  if self.canvasFilterMode then
    return normalizeCanvasFilterKey(self.canvasFilterMode)
  end
  local settings = AppSettingsController.load()
  return normalizeCanvasFilterKey(settings and settings.canvasFilter)
end

function AppCoreController:_applyCanvasFilterSetting(filterKey, saveSetting)
  local key = normalizeCanvasFilterKey(filterKey)
  local filter = (key == "soft") and "linear" or "nearest"
  --- Always push filter onto the canvas: initGraphics recreates the canvas with a fresh texture,
  --- so canvasFilterMode can match `key` while the drawable still has the default/min filter.
  if self.canvas and self.canvas.setFilter then
    self.canvas:setFilter(filter, filter)
  end
  self.canvasFilterMode = key
  if saveSetting ~= false then
    AppSettingsController.save({ canvasFilter = key })
  end
  return key
end

local LINK_MODE_DROPDOWN_LABELS = {
  auto_hide = "Auto-hide",
  on_hover = "On hover",
  always = "Always",
  never = "Never",
}

local function linkModeDropdownValueForKey(key)
  key = WindowLinkVisibility.normalizeLinkMode(key)
  if key == "on_hover" then
    return 2
  end
  if key == "always" then
    return 3
  end
  if key == "never" then
    return 4
  end
  return 1
end

local function linkModeKeyForDropdownValue(value)
  if value == 2 then
    return "on_hover"
  end
  if value == 3 then
    return "always"
  end
  if value == 4 then
    return "never"
  end
  return "auto_hide"
end

local function buildLinkModeDropdownItems(onPickMode)
  local items = {}
  for _, key in ipairs({ "auto_hide", "on_hover", "always", "never" }) do
    items[#items + 1] = {
      value = linkModeDropdownValueForKey(key),
      text = LINK_MODE_DROPDOWN_LABELS[key],
      onPick = function(entry)
        onPickMode(linkModeKeyForDropdownValue(entry and entry.value))
      end,
    }
  end
  return items
end

function AppCoreController:_getWindowLinksForSettings()
  if self.windowLinksMode then
    return WindowLinkVisibility.normalizeLinkMode(self.windowLinksMode)
  end
  local settings = AppSettingsController.load()
  return WindowLinkVisibility.normalizeLinkMode(settings and settings.windowLinks)
end

function AppCoreController:_applyWindowLinksSetting(modeKey, saveSetting)
  local key = WindowLinkVisibility.normalizeLinkMode(modeKey)
  self.windowLinksMode = key
  if saveSetting ~= false then
    AppSettingsController.save({ windowLinks = key })
  end
  if saveSetting ~= false and self._refreshSettingsModalIfOpen then
    self:_refreshSettingsModalIfOpen()
  end
  return key
end

function AppCoreController:_ensureSettingsWindowLinksDropdown()
  if self._windowLinksDropdown then
    return
  end
  local appRef = self
  self._windowLinksDropdown = Dropdown.new({
    getBounds = function()
      return { w = appRef.canvas:getWidth(), h = appRef.canvas:getHeight() }
    end,
    default = linkModeDropdownValueForKey(appRef:_getWindowLinksForSettings()),
    tooltip = "On-canvas ROM palette and pattern table link lines and pivot handles.",
    items = buildLinkModeDropdownItems(function(modeKey)
      appRef:_applyWindowLinksSetting(modeKey, true)
    end),
  })
end

function AppCoreController:_syncSettingsWindowLinksDropdown()
  local dd = self._windowLinksDropdown
  if not dd then
    return
  end
  dd:setGetBounds(function()
    return { w = self.canvas:getWidth(), h = self.canvas:getHeight() }
  end)
  dd._defaultSpec = linkModeDropdownValueForKey(self:_getWindowLinksForSettings())
  dd:setItems(buildLinkModeDropdownItems(function(modeKey)
    self:_applyWindowLinksSetting(modeKey, true)
  end))
end

function AppCoreController:_getSeparateToolbarForSettings()
  if self.separateToolbar ~= nil then
    return self.separateToolbar == true
  end
  local settings = AppSettingsController.load()
  return settings and settings.separateToolbar == true
end

function AppCoreController:_applySeparateToolbarSetting(enabled, saveSetting)
  self.separateToolbar = (enabled == true)
  if saveSetting ~= false then
    AppSettingsController.save({ separateToolbar = self.separateToolbar })
  end
  return self.separateToolbar
end

function AppCoreController:_getNeverShowResizeHandleForSettings()
  if self.neverShowResizeHandle ~= nil then
    return self.neverShowResizeHandle == true
  end
  local settings = AppSettingsController.load()
  return settings and settings.neverShowResizeHandle == true
end

function AppCoreController:onWorkspaceWindowFocused(win)
  WindowLinkVisibility.onWindowFocused(self, self.wm, win)
end

function AppCoreController:_applyNeverShowResizeHandleSetting(enabled, saveSetting)
  self.neverShowResizeHandle = (enabled == true)
  if saveSetting ~= false then
    AppSettingsController.save({ neverShowResizeHandle = self.neverShowResizeHandle })
  end
  return self.neverShowResizeHandle
end

function AppCoreController:_getWindowToolbarPlacementForSettings()
  if self.windowToolbarPlacement ~= nil then
    return WindowToolbarPlacement.normalizeKey(self.windowToolbarPlacement)
  end
  local settings = AppSettingsController.load()
  return WindowToolbarPlacement.normalizeKey(settings and settings.windowToolbarPlacement)
end

function AppCoreController:_applyWindowToolbarPlacementSetting(placementKey, saveSetting)
  local key = WindowToolbarPlacement.normalizeKey(placementKey)
  self.windowToolbarPlacement = key
  if saveSetting ~= false then
    AppSettingsController.save({ windowToolbarPlacement = key })
  end
  if saveSetting ~= false and self._refreshSettingsModalIfOpen then
    self:_refreshSettingsModalIfOpen()
  end
  return key
end

function AppCoreController:_ensureSettingsWindowToolbarPlacementDropdown()
  if self._windowToolbarPlacementDropdown then
    return
  end
  local appRef = self
  self._windowToolbarPlacementDropdownItems = {
    {
      value = WindowToolbarPlacement.dropdownValueForKey(WindowToolbarPlacement.KEY_AUTO),
      text = "Auto",
      onPick = function(entry)
        appRef:_applyWindowToolbarPlacementSetting(
          WindowToolbarPlacement.keyForDropdownValue(entry.value),
          true
        )
      end,
    },
    {
      value = WindowToolbarPlacement.dropdownValueForKey(WindowToolbarPlacement.KEY_TOP),
      text = "Top",
      onPick = function(entry)
        appRef:_applyWindowToolbarPlacementSetting(
          WindowToolbarPlacement.keyForDropdownValue(entry.value),
          true
        )
      end,
    },
    {
      value = WindowToolbarPlacement.dropdownValueForKey(WindowToolbarPlacement.KEY_LEFT),
      text = "Left",
      onPick = function(entry)
        appRef:_applyWindowToolbarPlacementSetting(
          WindowToolbarPlacement.keyForDropdownValue(entry.value),
          true
        )
      end,
    },
    {
      value = WindowToolbarPlacement.dropdownValueForKey(WindowToolbarPlacement.KEY_RIGHT),
      text = "Right",
      onPick = function(entry)
        appRef:_applyWindowToolbarPlacementSetting(
          WindowToolbarPlacement.keyForDropdownValue(entry.value),
          true
        )
      end,
    },
    {
      value = WindowToolbarPlacement.dropdownValueForKey(WindowToolbarPlacement.KEY_BOTTOM),
      text = "Bottom",
      onPick = function(entry)
        appRef:_applyWindowToolbarPlacementSetting(
          WindowToolbarPlacement.keyForDropdownValue(entry.value),
          true
        )
      end,
    },
  }
  self._windowToolbarPlacementDropdown = Dropdown.new({
    getBounds = function()
      return { w = appRef.canvas:getWidth(), h = appRef.canvas:getHeight() }
    end,
    default = WindowToolbarPlacement.dropdownValueForKey(appRef:_getWindowToolbarPlacementForSettings()),
    tooltip = "Where to attach the focused window's toolbar strip (when not using Detached Window Toolbar)",
    items = self._windowToolbarPlacementDropdownItems,
  })
end

function AppCoreController:_syncSettingsWindowToolbarPlacementDropdown()
  local dd = self._windowToolbarPlacementDropdown
  if not dd or not self._windowToolbarPlacementDropdownItems then
    return
  end
  dd:setGetBounds(function()
    return { w = self.canvas:getWidth(), h = self.canvas:getHeight() }
  end)
  dd._defaultSpec = WindowToolbarPlacement.dropdownValueForKey(self:_getWindowToolbarPlacementForSettings())
  dd:setItems(self._windowToolbarPlacementDropdownItems)
end

function AppCoreController:_getWindowShadowEnabledForSettings()
  if self.windowShadowEnabled ~= nil then
    return self.windowShadowEnabled == true
  end
  local settings = AppSettingsController.load()
  return settings and settings.windowShadowEnabled ~= false
end

function AppCoreController:_applyWindowShadowSetting(enabled, saveSetting)
  self.windowShadowEnabled = (enabled == true)
  if saveSetting ~= false then
    AppSettingsController.save({ windowShadowEnabled = self.windowShadowEnabled })
  end
  if self._windowShadowBlurSlider then
    self._windowShadowBlurSlider:setEnabled(self.windowShadowEnabled == true)
  end
  if self._windowShadowStrengthSlider then
    self._windowShadowStrengthSlider:setEnabled(self.windowShadowEnabled == true)
  end
  if self._refreshSettingsModalIfOpen then
    self:_refreshSettingsModalIfOpen()
  end
  return self.windowShadowEnabled
end

function AppCoreController:_getWindowShadowBlurForSettings()
  if type(self.windowShadowBlur) == "number" then
    return AppSettingsController.normalizeWindowShadowBlur(self.windowShadowBlur)
  end
  local settings = AppSettingsController.load()
  return AppSettingsController.normalizeWindowShadowBlur(settings and settings.windowShadowBlur)
end

function AppCoreController:_applyWindowShadowBlurSetting(value, saveSetting)
  local n = AppSettingsController.normalizeWindowShadowBlur(value)
  self.windowShadowBlur = n
  if saveSetting ~= false then
    AppSettingsController.save({ windowShadowBlur = n })
  end
  return n
end

function AppCoreController:_ensureSettingsWindowShadowBlurSlider()
  if self._windowShadowBlurSlider then
    return
  end
  local Slider = require("user_interface.slider")
  local appRef = self
  self._windowShadowBlurSlider = Slider.new({
    min = 0,
    max = 1,
    value = 0.2,
    tooltip = "Soft edge falloff for window shadows (0 = crisp, 100 = softest)",
    onChange = function(v)
      appRef:_applyWindowShadowBlurSetting(v, false)
    end,
    onCommit = function(v)
      AppSettingsController.save({
        windowShadowBlur = AppSettingsController.normalizeWindowShadowBlur(v),
      })
    end,
  })
end

function AppCoreController:_ensureSettingsCanvasFilterDropdown()
  if self._canvasFilterDropdown then
    return
  end
  local appRef = self
  self._canvasFilterDropdownItems = {
    {
      value = 1,
      text = "Sharp",
      onPick = function()
        appRef:_applyDisplayFilterDropdownMode(1, true)
      end,
    },
    {
      value = 2,
      text = "Soft",
      onPick = function()
        appRef:_applyDisplayFilterDropdownMode(2, true)
      end,
    },
    {
      value = 3,
      text = "CRT",
      onPick = function()
        appRef:_applyDisplayFilterDropdownMode(3, true)
      end,
    },
    --[[ Composite: hidden from Settings dropdown for now; `_applyDisplayFilterDropdownMode(4)` and
        `crtFilterKind == "composite"` remain supported for saved settings / internal use.
    {
      value = 4,
      text = "Composite",
      onPick = function()
        appRef:_applyDisplayFilterDropdownMode(4, true)
      end,
    },
    ]]
  }
  self._canvasFilterDropdown = Dropdown.new({
    getBounds = function()
      return { w = appRef.canvas:getWidth(), h = appRef.canvas:getHeight() }
    end,
    default = appRef:_getDisplayFilterDropdownMode(),
    tooltip = "Without CRT: sharp or soft scaling. When CRT is on, barrel scanline shader.",
    items = self._canvasFilterDropdownItems,
  })
  self:_syncCanvasFilterDropdownLabelForHiddenComposite()
end

function AppCoreController:_syncCanvasFilterDropdownLabelForHiddenComposite()
  local dd = self._canvasFilterDropdown
  if not dd then
    return
  end
  if self.crtModeEnabled == true and self:_normalizeCrtFilterKind(self.crtFilterKind) == "composite" then
    dd.trigger.text = "Composite"
    dd.selectedText = "Composite"
  end
end

function AppCoreController:_syncSettingsCanvasFilterDropdown()
  local dd = self._canvasFilterDropdown
  if not dd or not self._canvasFilterDropdownItems then
    return
  end
  dd:setGetBounds(function()
    return { w = self.canvas:getWidth(), h = self.canvas:getHeight() }
  end)
  dd._defaultSpec = self:_getDisplayFilterDropdownMode()
  dd:setItems(self._canvasFilterDropdownItems)
  self:_syncCanvasFilterDropdownLabelForHiddenComposite()
end

function AppCoreController:_getWindowShadowStrengthForSettings()
  if type(self.windowShadowStrength) == "number" then
    return AppSettingsController.normalizeWindowShadowStrength(self.windowShadowStrength)
  end
  local settings = AppSettingsController.load()
  return AppSettingsController.normalizeWindowShadowStrength(settings and settings.windowShadowStrength)
end

function AppCoreController:_applyWindowShadowStrengthSetting(value, saveSetting)
  local n = AppSettingsController.normalizeWindowShadowStrength(value)
  self.windowShadowStrength = n
  if saveSetting ~= false then
    AppSettingsController.save({ windowShadowStrength = n })
  end
  return n
end

function AppCoreController:_ensureSettingsWindowShadowStrengthSlider()
  if self._windowShadowStrengthSlider then
    return
  end
  local Slider = require("user_interface.slider")
  local appRef = self
  self._windowShadowStrengthSlider = Slider.new({
    min = 0,
    max = 1,
    value = 0.5,
    tooltip = "Shadow opacity relative to the theme baseline (0% = invisible)",
    onChange = function(v)
      appRef:_applyWindowShadowStrengthSetting(v, false)
    end,
    onCommit = function(v)
      AppSettingsController.save({
        windowShadowStrength = AppSettingsController.normalizeWindowShadowStrength(v),
      })
    end,
  })
end

function AppCoreController:_refreshSettingsModalIfOpen()
  if self.settingsModal and self.settingsModal.isVisible and self.settingsModal:isVisible() then
    self:_syncSettingsCanvasFilterDropdown()
    self:_syncSettingsCanvasImageModeDropdown()
    self:_syncSettingsWindowLinksDropdown()
    self:_syncSettingsWindowToolbarPlacementDropdown()
    ModalPanelUtils.refreshTargetMetrics(self.settingsModal)
    if self.settingsModal._rebuildRows then
      self.settingsModal:_rebuildRows()
    end
  end
end

function AppCoreController:_normalizeCrtCanvasResolutionKey(key)
  if key == "320x180" then
    return "320x180"
  end
  return "640x360"
end

function AppCoreController:_getCrtCanvasResolutionForSettings()
  return self:_normalizeCrtCanvasResolutionKey(self.crtCanvasResolution)
end

function AppCoreController:_applyCrtCanvasResolutionSetting(key, saveSetting)
  local prev = self.crtCanvasResolution
  local k = self:_normalizeCrtCanvasResolutionKey(key)
  self.crtCanvasResolution = k
  if k == "320x180" and prev ~= "320x180" then
    ResolutionController.crtViewportX = 0
    ResolutionController.crtViewportY = 0
  end
  if ResolutionController.applyCrtPresentationFromApp then
    ResolutionController:applyCrtPresentationFromApp(self)
  end
  if saveSetting ~= false then
    AppSettingsController.save({ crtCanvasResolution = k })
  end
  return k
end

function AppCoreController:_getCrtDistortionForSettings()
  if type(self.crtDistortionSetting) == "number" then
    return self.crtDistortionSetting
  end
  return ResolutionController:getCanvasCrtDistortion()
end

function AppCoreController:_applyCrtDistortionSetting(value, saveSetting)
  local n = tonumber(value)
  if n == nil then
    n = 0.1
  end
  n = math.max(0, math.min(0.45, n))
  self.crtDistortionSetting = n
  ResolutionController:setCanvasCrtDistortion(n)
  if saveSetting ~= false then
    AppSettingsController.save({ crtDistortion = n })
  end
  return n
end

function AppCoreController:_applyCrtModeSetting(enabled, saveSetting)
  self:setCrtModeEnabled(enabled == true)
  if saveSetting ~= false then
    AppSettingsController.save({ crtEnabled = self.crtModeEnabled == true })
  end
  return self.crtModeEnabled == true
end

function AppCoreController:_normalizeCrtFilterKind(key)
  if key == "composite" then
    return "composite"
  end
  return "crt"
end

function AppCoreController:_applyCrtFilterKindSetting(kind, saveSetting)
  local k = self:_normalizeCrtFilterKind(kind)
  self.crtFilterKind = k
  if ResolutionController.setCanvasCrtFilterKind then
    ResolutionController:setCanvasCrtFilterKind(k)
  end
  if saveSetting ~= false then
    AppSettingsController.save({ crtFilterKind = k })
  end
  --- Composite scanline shader expects smoothly interpolated workspace sampling.
  if k == "composite" and self._applyCanvasFilterSetting then
    self:_applyCanvasFilterSetting("soft", saveSetting)
  end
  return k
end

--- Settings -> Canvas filter dropdown: sharp/soft (CRT off) or CRT vs composite scanlines (CRT on).
function AppCoreController:_getDisplayFilterDropdownMode()
  if self.crtModeEnabled == true then
    if self:_normalizeCrtFilterKind(self.crtFilterKind) == "composite" then
      -- No menu row for composite; use CRT as the matching item, then fix the label.
      return 3
    end
    return 3
  end
  if self:_getCanvasFilterForSettings() == "soft" then
    return 2
  end
  return 1
end

function AppCoreController:_applyDisplayFilterDropdownMode(mode, saveSetting)
  local m = tonumber(mode)
  if m == nil or m < 1 or m > 4 then
    return
  end
  if m == 1 then
    self:_applyCrtModeSetting(false, saveSetting)
    self:_applyCanvasFilterSetting("sharp", saveSetting)
  elseif m == 2 then
    self:_applyCrtModeSetting(false, saveSetting)
    self:_applyCanvasFilterSetting("soft", saveSetting)
  elseif m == 3 then
    self:_applyCrtFilterKindSetting("crt", saveSetting)
    self:_applyCrtModeSetting(true, saveSetting)
  else
    self:_applyCrtFilterKindSetting("composite", saveSetting)
    self:_applyCrtModeSetting(true, saveSetting)
  end
  if self._refreshSettingsModalIfOpen then
    self:_refreshSettingsModalIfOpen()
  end
end

function AppCoreController:_ensureSettingsCrtCurveSlider()
  if self._crtCurveSlider then
    return
  end
  local Slider = require("user_interface.slider")
  local appRef = self
  self._crtCurveSlider = Slider.new({
    min = 0,
    max = 0.45,
    value = 0.1,
    tooltip = "CRT barrel distortion when the CRT filter is on",
    onChange = function(v)
      appRef:_applyCrtDistortionSetting(v, false)
    end,
    onCommit = function(v)
      AppSettingsController.save({ crtDistortion = tonumber(v) })
    end,
  })
end

function AppCoreController:_ensureGroupedPaletteController()
  local GroupedPaletteController = require("controllers.palette.grouped_palette_controller")
  if not self.groupedPaletteController then
    self.groupedPaletteController = GroupedPaletteController.new(self)
    if self.paletteGroupState then
      self.groupedPaletteController:setState(self.paletteGroupState)
    end
  end
  local c = self.groupedPaletteController
  local wantEnabled = (self.groupedPaletteWindows == true)
  if c.enabled ~= wantEnabled then
    c:setEnabled(wantEnabled, self.paletteGroupState)
  end
  return c
end

function AppCoreController:_getGroupedPaletteWindowsForSettings()
  if self.groupedPaletteWindows ~= nil then
    return normalizeGroupedPaletteWindows(self.groupedPaletteWindows)
  end
  local settings = AppSettingsController.load()
  return normalizeGroupedPaletteWindows(settings and settings.groupedPaletteWindows)
end

function AppCoreController:isGroupedPaletteWindowsEnabled()
  return self.groupedPaletteWindows == true
end

function AppCoreController:getPaletteGroupStateForSave()
  if self.groupedPaletteWindows ~= true then
    return nil
  end
  local controller = self:_ensureGroupedPaletteController()
  if not (controller and controller.getState) then
    return nil
  end
  -- getState() copies controller.state and, when grouping is active, refreshes
  -- logicalWindow (x,y,collapsed,...), activeIndex, and activeSourceWindowId
  -- from the live WM so saves match the grouped palette chrome.
  self.paletteGroupState = controller:getState()
  return self.paletteGroupState
end

function AppCoreController:_applyGroupedPaletteWindowsSetting(enabled, saveSetting)
  self.groupedPaletteWindows = normalizeGroupedPaletteWindows(enabled)
  if saveSetting ~= false then
    AppSettingsController.save({ groupedPaletteWindows = self.groupedPaletteWindows })
  end

  local controller = self:_ensureGroupedPaletteController()
  controller:setEnabled(self.groupedPaletteWindows, self.paletteGroupState)
  self.paletteGroupState = controller:getState()
  return self.groupedPaletteWindows
end

function AppCoreController:refreshGroupedPaletteWindows()
  local controller = self:_ensureGroupedPaletteController()
  controller:setState(self.paletteGroupState)
  controller:setEnabled(self.groupedPaletteWindows == true, self.paletteGroupState)
  self.paletteGroupState = controller:getState()
  return self.paletteGroupState
end

function AppCoreController:cycleGroupedPaletteWindow(window, delta)
  if self.groupedPaletteWindows ~= true then
    return false
  end
  local controller = self:_ensureGroupedPaletteController()
  local changed = controller:cycleWindow(window, delta)
  if changed then
    self.paletteGroupState = controller:getState()
  end
  return changed
end

--- Keyboard: cycle which **global** (non-ROM) palette window is active — `WindowCaps.isGlobalPaletteWindow`
--- only; **ROM palette** windows are never part of this shortcut. Same net effect as "Set as active palette"
--- on a global palette toolbar. Does not focus palette windows. If **Grouped palettes** is enabled,
--- updates the grouped **global** slot (active index / which palette is shown) without `setFocus`.
--- Requires at least two global palette windows.
function AppCoreController:cycleGlobalPaletteFromKeyboard(delta)
  local wm = self.wm
  if not (wm and wm.getWindows) then
    return false
  end

  delta = tonumber(delta) or 0
  if delta == 0 then
    return false
  end

  local orderField = "_groupOrderGlobal"
  local windows = wm:getWindows() or {}
  local runningMaxOrder = 0
  for _, win in ipairs(windows) do
    local existing = tonumber(win and win[orderField]) or 0
    if existing > runningMaxOrder then
      runningMaxOrder = existing
    end
  end

  local palettes = {}
  for _, win in ipairs(windows) do
    if WindowCaps.isGlobalPaletteWindow(win)
      and win._runtimeOnly ~= true
      and win._closed ~= true
    then
      if tonumber(win[orderField]) == nil then
        runningMaxOrder = runningMaxOrder + 1
        win[orderField] = runningMaxOrder
      end
      palettes[#palettes + 1] = win
    end
  end

  table.sort(palettes, function(a, b)
    local ao = tonumber(a and a[orderField]) or math.huge
    local bo = tonumber(b and b[orderField]) or math.huge
    if ao == bo then
      return tostring(a and a._id or "") < tostring(b and b._id or "")
    end
    return ao < bo
  end)

  if #palettes == 0 then
    if self.setStatus then
      self:setStatus("Open a global palette window to cycle.")
    end
    return true
  end

  if #palettes < 2 then
    if self.setStatus then
      self:setStatus("Need at least two global palettes to cycle.")
    end
    return true
  end

  local curIdx = nil
  for i, win in ipairs(palettes) do
    if win.activePalette then
      curIdx = i
      break
    end
  end
  if not curIdx then
    curIdx = 1
  end

  local n = #palettes
  local nextIdx = ((curIdx - 1 + delta) % n) + 1
  local target = palettes[nextIdx]
  if not target then
    return false
  end

  local allWindows = wm:getWindows() or {}
  for _, win in ipairs(allWindows) do
    if win.isPalette then
      win.activePalette = false
    end
  end
  target.activePalette = true

  if target.syncToGlobalPalette then
    target:syncToGlobalPalette()
  end
  if self.invalidatePpuFrameLayersAffectedByPaletteWin then
    self:invalidatePpuFrameLayersAffectedByPaletteWin(target)
  end

  for _, win in ipairs(allWindows) do
    if win.isPalette and win.specializedToolbar and win.specializedToolbar.updateActiveIcon then
      win.specializedToolbar:updateActiveIcon()
    end
  end

  if self.groupedPaletteWindows == true then
    local controller = self:_ensureGroupedPaletteController()
    if controller and controller.syncGlobalGroupedDisplayToWindow then
      if controller:syncGlobalGroupedDisplayToWindow(target) then
        self.paletteGroupState = controller:getState()
      end
    end
  end

  return true
end

function AppCoreController:focusPaletteWindowWithGrouping(window)
  if not window then
    return false
  end
  local focusedViaGroup = false
  if self.groupedPaletteWindows == true then
    local controller = self:_ensureGroupedPaletteController()
    focusedViaGroup = controller:activateWindow(window) == true
    if focusedViaGroup then
      self.paletteGroupState = controller:getState()
    end
  end
  if (not focusedViaGroup) and self.wm and self.wm.setFocus then
    self.wm:setFocus(window)
  end
  return true
end

function AppCoreController:onWindowManagerWindowCreated(win)
  if win and win.kind == "crt_lens" then
    return false
  end
  if self.groupedPaletteWindows ~= true then
    return false
  end
  if not win then
    return false
  end
  local WindowCaps = require("controllers.window.window_capabilities")
  if WindowCaps.isGlobalPaletteWindow(win) or WindowCaps.isRomPaletteWindow(win) then
    return self:focusPaletteWindowWithGrouping(win)
  end
  self:refreshGroupedPaletteWindows()
  return true
end

function AppCoreController:_applyTooltipsEnabledSetting(enabled, saveSetting)
  self.tooltipsEnabled = (enabled ~= false)
  if self.tooltipController and self.tooltipsEnabled == false then
    self.tooltipController.visible = false
    self.tooltipController.candidateText = nil
    self.tooltipController.candidateKey = nil
    self.tooltipController.candidateImmediate = false
  end
  if saveSetting ~= false then
    AppSettingsController.save({ tooltipsEnabled = self.tooltipsEnabled })
  end
  return self.tooltipsEnabled
end

local function normalizeThemeKey(key)
  if key == "light" then
    return "light"
  end
  return "dark"
end

function AppCoreController:_getThemeForSettings()
  if self.themeMode then
    return normalizeThemeKey(self.themeMode)
  end
  local settings = AppSettingsController.load()
  return normalizeThemeKey(settings and settings.theme)
end

function AppCoreController:_applyThemeSetting(themeKey, saveSetting)
  local key = normalizeThemeKey(themeKey)
  self.themeMode = key
  if colors and colors.setTheme then
    colors:setTheme(key)
  end
  ModalPanelUtils.refreshModalChromeFromAppearanceChange(self)
  if saveSetting ~= false then
    AppSettingsController.save({ theme = key })
  end
  return key
end

function AppCoreController:_applyAppearanceChromeFromSettings(appearanceChrome)
  if colors and colors.setAppearanceChromeOverrides then
    colors:setAppearanceChromeOverrides(appearanceChrome)
  end
  ModalPanelUtils.refreshModalChromeFromAppearanceChange(self)
  if self.settingsModal and self.settingsModal.syncAppearancePickersFromAppColors then
    self.settingsModal:syncAppearancePickersFromAppColors()
  end
end

--- Reset General + Appearance settings controlled by the settings modal to file defaults.
--- Preserves recent projects list and skip-splash preference.
function AppCoreController:resetSettingsModalPreferencesToDefaults()
  local cur = AppSettingsController.load()
  local recentProjects = cur and cur.recentProjects
  local skipSplash = cur and cur.skipSplash == true
  local D = AppSettingsController.defaults()
  self:_applyThemeSetting(D.theme, false)
  self:_applyTooltipsEnabledSetting(D.tooltipsEnabled, false)
  self:_applyCanvasImageModeSetting(D.canvasImageMode, false)
  self:_applyCanvasFilterSetting(D.canvasFilter, false)
  self:_applyWindowLinksSetting(D.windowLinks, false)
  self:_applySeparateToolbarSetting(D.separateToolbar, false)
  self:_applyWindowToolbarPlacementSetting(D.windowToolbarPlacement or "auto", false)
  self:_applyNeverShowResizeHandleSetting(D.neverShowResizeHandle == true, false)
  self:_applyWindowShadowSetting(D.windowShadowEnabled == true, false)
  self:_applyWindowShadowBlurSetting(D.windowShadowBlur, false)
  self:_applyWindowShadowStrengthSetting(D.windowShadowStrength, false)
  self:_applyGroupedPaletteWindowsSetting(D.groupedPaletteWindows, false)
  self:_applyCrtFilterKindSetting(D.crtFilterKind, false)
  self:_applyCrtModeSetting(D.crtEnabled == true, false)
  self:_applyCrtDistortionSetting(D.crtDistortion, false)
  self:_applyCrtCanvasResolutionSetting(D.crtCanvasResolution, false)
  self:_applyAppearanceChromeFromSettings({})
  AppSettingsController.save({
    theme = D.theme,
    tooltipsEnabled = D.tooltipsEnabled,
    canvasImageMode = D.canvasImageMode,
    canvasFilter = D.canvasFilter,
    windowLinks = D.windowLinks,
    separateToolbar = D.separateToolbar,
    windowToolbarPlacement = D.windowToolbarPlacement or "auto",
    neverShowResizeHandle = D.neverShowResizeHandle,
    windowShadowEnabled = D.windowShadowEnabled,
    windowShadowBlur = D.windowShadowBlur,
    windowShadowStrength = D.windowShadowStrength,
    groupedPaletteWindows = D.groupedPaletteWindows,
    crtEnabled = D.crtEnabled,
    crtFilterKind = D.crtFilterKind,
    crtDistortion = D.crtDistortion,
    crtCanvasResolution = D.crtCanvasResolution,
    appearanceChrome = {},
    mergeAppearanceChrome = false,
    recentProjects = recentProjects,
    skipSplash = skipSplash,
  })
  if self._windowShadowBlurSlider then
    self._windowShadowBlurSlider:setValue(self:_getWindowShadowBlurForSettings(), { silent = true })
  end
  if self._windowShadowStrengthSlider then
    self._windowShadowStrengthSlider:setValue(self:_getWindowShadowStrengthForSettings(), { silent = true })
  end
  if self._refreshSettingsModalIfOpen then
    self:_refreshSettingsModalIfOpen()
  end
end

function AppCoreController:showSettingsModal()
  if not self.settingsModal then
    self.settingsModal = SettingsModal.new()
  end

  local appRef = self
  self:_ensureSettingsCrtCurveSlider()
  self._crtCurveSlider:setValue(self:_getCrtDistortionForSettings(), { silent = true })
  self._crtCurveSlider:setEnabled(self.crtModeEnabled == true and self.crtFilterKind ~= "composite")

  self:_ensureSettingsWindowShadowBlurSlider()
  self._windowShadowBlurSlider:setValue(self:_getWindowShadowBlurForSettings(), { silent = true })
  self._windowShadowBlurSlider:setEnabled(self.windowShadowEnabled ~= false)

  self:_ensureSettingsWindowShadowStrengthSlider()
  self._windowShadowStrengthSlider:setValue(self:_getWindowShadowStrengthForSettings(), { silent = true })
  self._windowShadowStrengthSlider:setEnabled(self.windowShadowEnabled ~= false)

  self:_ensureSettingsCanvasFilterDropdown()
  self:_syncSettingsCanvasFilterDropdown()

  self:_ensureSettingsCanvasImageModeDropdown()
  self:_syncSettingsCanvasImageModeDropdown()

  self:_ensureSettingsWindowToolbarPlacementDropdown()
  self:_syncSettingsWindowToolbarPlacementDropdown()

  self:_ensureSettingsWindowLinksDropdown()
  self:_syncSettingsWindowLinksDropdown()

  self.settingsModal:show({
    title = "Settings",
    getMenuBounds = function()
      return {
        w = appRef.canvas:getWidth(),
        h = appRef.canvas:getHeight(),
      }
    end,
    getCanvasImageMode = function()
      return appRef:_getCanvasImageModeForSettings()
    end,
    getTooltipsEnabled = function()
      return appRef:_getTooltipsEnabledForSettings()
    end,
    getTheme = function()
      return appRef:_getThemeForSettings()
    end,
    getWindowLinks = function()
      return appRef:_getWindowLinksForSettings()
    end,
    getSeparateToolbar = function()
      return appRef:_getSeparateToolbarForSettings()
    end,
    getNeverShowResizeHandle = function()
      return appRef:_getNeverShowResizeHandleForSettings()
    end,
    getFullscreen = function()
      return love.window.getFullscreen() == true
    end,
    getExtraRows = function()
      return SettingsFields.buildExtraGeneralRows({
        getGroupedPaletteWindows = function()
          return appRef:_getGroupedPaletteWindowsForSettings()
        end,
        applyGroupedPaletteWindows = function(enabled)
          appRef:_applyGroupedPaletteWindowsSetting(enabled, true)
        end,
        crtModeEnabled = appRef.crtModeEnabled,
        crtFilterKind = appRef.crtFilterKind,
        crtCurveSlider = appRef._crtCurveSlider,
        getCrtCanvasResolution = function()
          return appRef:_getCrtCanvasResolutionForSettings()
        end,
        applyCrtCanvasResolution = function(nextKey)
          appRef:_applyCrtCanvasResolutionSetting(nextKey, true)
        end,
        showCrtCanvasResolutionSetting = SHOW_CRT_CANVAS_RESOLUTION_SETTING_IN_UI,
      })
    end,
    onSetCanvasImageMode = function(modeKey)
      appRef:_applyCanvasImageModeSetting(modeKey, true)
    end,
    onSetTooltipsEnabled = function(enabled)
      appRef:_applyTooltipsEnabledSetting(enabled, true)
    end,
    onSetTheme = function(themeKey)
      appRef:_applyThemeSetting(themeKey, true)
    end,
    onSetWindowLinks = function(modeKey)
      appRef:_applyWindowLinksSetting(modeKey, true)
    end,
    onSetSeparateToolbar = function(enabled)
      appRef:_applySeparateToolbarSetting(enabled, true)
    end,
    onSetNeverShowResizeHandle = function(enabled)
      appRef:_applyNeverShowResizeHandleSetting(enabled, true)
    end,
    onToggleFullscreen = function()
      KeyboardWindowShortcutsController.toggleFullscreen(appRef)
      if appRef._refreshSettingsModalIfOpen then
        appRef:_refreshSettingsModalIfOpen()
      end
    end,
    getAppearanceChromeRgb = function(slotId)
      local c = colors:appearanceChromeResolved(slotId)
      return { r = c[1], g = c[2], b = c[3] }
    end,
    onAppearanceChromeChange = function(slotId, rgb)
      colors:setAppearanceChromeOverride(slotId, rgb)
      AppSettingsController.save({ appearanceChrome = colors:getAppearanceChromeOverridesForSave() })
      ModalPanelUtils.refreshModalChromeFromAppearanceChange(appRef)
    end,
    onResetAll = function()
      appRef:resetSettingsModalPreferencesToDefaults()
    end,
    windowShadowBlurSlider = appRef._windowShadowBlurSlider,
    windowShadowStrengthSlider = appRef._windowShadowStrengthSlider,
    canvasImageModeDropdown = appRef._canvasImageModeDropdown,
    canvasFilterDropdown = appRef._canvasFilterDropdown,
    windowLinksDropdown = appRef._windowLinksDropdown,
    windowToolbarPlacementDropdown = appRef._windowToolbarPlacementDropdown,
    initialTabId = appRef._tabbedModalActiveTabIds and appRef._tabbedModalActiveTabIds.settings or nil,
    onActiveTabChange = function(tabId)
      appRef._tabbedModalActiveTabIds = appRef._tabbedModalActiveTabIds or {}
      appRef._tabbedModalActiveTabIds.settings = tabId
    end,
  })
end

end
