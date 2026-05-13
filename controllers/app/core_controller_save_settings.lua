local SaveController = require("controllers.rom.save_controller")
local RomProjectController = require("controllers.rom.rom_project_controller")
local AppSettingsController = require("controllers.app.settings_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local KeyboardWindowShortcutsController = require("controllers.input.keyboard_window_shortcuts_controller")
local SaveOptionsModal = require("user_interface.modals.save_options_modal")
local SettingsModal = require("user_interface.modals.settings_modal")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")
local Dropdown = require("user_interface.dropdown")
local TableUtils = require("utils.table_utils")
local colors = require("app_colors")

return function(AppCoreController)

-- CRT 640x360 vs 320x180: logic and settings persist; toggle row hidden while false.
local SHOW_CRT_CANVAS_RESOLUTION_SETTING_IN_UI = false

local function combineSaveMessages(projectRequested, projectOk, projectStatus, romRequested, romOk, romStatus)
  if projectRequested and romRequested and projectOk and romOk then
    return true, "Saved project and exported ROM"
  end

  if projectRequested and romRequested then
    if projectOk and not romOk then
      local detail = (romStatus and romStatus ~= "") and romStatus or "ROM export failed"
      return false, detail .. " (project saved)"
    end
    if (not projectOk) and romOk then
      local detail = (projectStatus and projectStatus ~= "") and projectStatus or "Project save failed"
      return false, detail .. " (ROM exported)"
    end
    if (not projectOk) and (not romOk) then
      local parts = {}
      if romStatus and romStatus ~= "" then parts[#parts + 1] = romStatus end
      if projectStatus and projectStatus ~= "" then parts[#parts + 1] = projectStatus end
      if #parts == 0 then
        return false, "Project and ROM save failed"
      end
      return false, table.concat(parts, "; ")
    end
  end

  if projectRequested and not romRequested then
    if projectOk then
      return true, "Saved project (no ROM loaded)"
    end
    return false, projectStatus or "Project save failed"
  end

  local parts = {}
  if projectRequested and projectStatus and projectStatus ~= "" then
    parts[#parts + 1] = projectStatus
  end
  if romRequested and romStatus and romStatus ~= "" then
    parts[#parts + 1] = romStatus
  end

  return false, table.concat(parts, "; ")
end

local function combineAllSaveMessages(luaOk, luaStatus, ppuxOk, ppuxStatus, romOk, romStatus)
  if luaOk and ppuxOk and romOk then
    return true, "Saved ROM, Lua project, and compressed PPUX project"
  end

  local parts = {}
  if not romOk then
    parts[#parts + 1] = romStatus or "ROM save failed"
  end
  if not luaOk then
    parts[#parts + 1] = luaStatus or "Lua project save failed"
  end
  if not ppuxOk then
    parts[#parts + 1] = ppuxStatus or "Compressed PPUX save failed"
  end

  if #parts == 0 then
    return false, "Save failed"
  end

  return false, table.concat(parts, "; ")
end

local OPEN_FILE_MODAL_RUNTIME_DIR_KEY = {
  project = "project",
  png = "png",
}

local function resolveOpenProjectInitialDir(app)
  if not app then
    return "."
  end
  local dirs = app._openFileModalLastDirs
  local remembered = dirs and dirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.project]
  if type(remembered) == "string" and remembered ~= "" then
    return remembered
  end
  if love and love.filesystem and love.filesystem.getWorkingDirectory then
    local dir = love.filesystem.getWorkingDirectory()
    if type(dir) == "string" and dir ~= "" then
      return dir
    end
  end
  return "."
end

local function resolveOpenReferencePngInitialDir(app)
  if not app then
    return "."
  end
  local dirs = app._openFileModalLastDirs
  local remembered = dirs and dirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.png]
  if type(remembered) == "string" and remembered ~= "" then
    return remembered
  end
  return resolveOpenProjectInitialDir(app)
end

function AppCoreController:saveEdited(opts)
  opts = opts or {}
  if not self:hasLoadedROM() then
    self:setStatus("Open a ROM before saving.")
    if opts.toast ~= false then
      self:showToast("error", self.statusText)
    end
    return false
  end
  local ok = SaveController.saveEdited(self)
  self:setStatus(self.statusText)
  if ok and opts.clearUnsaved ~= false then
    self:clearUnsavedChanges()
  end
  if opts.toast ~= false then
    self:showToast(ok and "info" or "error", self.statusText)
  end
  return ok
end

function AppCoreController:saveProject(opts)
  opts = opts or {}
  if not self:hasLoadedROM() then
    self:setStatus("Open a ROM before saving.")
    if opts.toast ~= false then
      self:showToast("error", self.statusText)
    end
    return false
  end
  local ok = RomProjectController.saveProject(self)
  self:setStatus(self.statusText)
  if ok and opts.clearUnsaved ~= false then
    self:clearUnsavedChanges()
  end
  if opts.toast ~= false then
    self:showToast(ok and "info" or "error", self.statusText)
  end
  return ok
end

function AppCoreController:saveEncodedProject(opts)
  opts = opts or {}
  if not self:hasLoadedROM() then
    self:setStatus("Open a ROM before saving.")
    if opts.toast ~= false then
      self:showToast("error", self.statusText)
    end
    return false
  end
  local ok = RomProjectController.saveEncodedProject(self)
  self:setStatus(self.statusText)
  if ok and opts.clearUnsaved ~= false then
    self:clearUnsavedChanges()
  end
  if opts.toast ~= false then
    self:showToast(ok and "info" or "error", self.statusText)
  end
  return ok
end

function AppCoreController:saveProjectAndRom(opts)
  opts = opts or {}
  if not self:hasLoadedROM() then
    self:setStatus("Open a ROM before saving.")
    if opts.toast ~= false then
      self:showToast("error", self.statusText)
    end
    return false
  end

  local projectOk = self:saveProject({
    toast = false,
    clearUnsaved = false,
  })
  local projectStatus = self.statusText

  local romRequested = not not (self.appEditState and self.appEditState.romSha1)
  local romOk = true
  local romStatus = nil
  if romRequested then
    romOk = self:saveEdited({
      toast = false,
      clearUnsaved = false,
    })
    romStatus = self.statusText
  end

  local ok, message = combineSaveMessages(true, projectOk, projectStatus, romRequested, romOk, romStatus)
  self:setStatus(message)
  if ok and opts.clearUnsaved ~= false then
    self:clearUnsavedChanges()
  end
  if opts.toast ~= false then
    self:showToast(ok and "info" or "error", self.statusText)
  end
  return ok
end

function AppCoreController:saveAllArtifacts(opts)
  opts = opts or {}
  if not self:hasLoadedROM() then
    self:setStatus("Open a ROM before saving.")
    if opts.toast ~= false then
      self:showToast("error", self.statusText)
    end
    return false
  end

  local romOk = self:saveEdited({
    toast = false,
    clearUnsaved = false,
  })
  local romStatus = self.statusText

  local luaOk = self:saveProject({
    toast = false,
    clearUnsaved = false,
  })
  local luaStatus = self.statusText

  local ppuxOk = self:saveEncodedProject({
    toast = false,
    clearUnsaved = false,
  })
  local ppuxStatus = self.statusText

  local ok, message = combineAllSaveMessages(luaOk, luaStatus, ppuxOk, ppuxStatus, romOk, romStatus)
  self:setStatus(message)
  if ok and opts.clearUnsaved ~= false then
    self:clearUnsavedChanges()
  end
  if opts.toast ~= false then
    self:showToast(ok and "info" or "error", self.statusText)
  end
  return ok
end

function AppCoreController:markUnsaved(eventType)
  if not eventType then return false end
  if not self.unsavedEventTypes[eventType] then return false end
  self.unsavedChanges = true
  self.unsavedEvents[eventType] = true
  return true
end

function AppCoreController:clearUnsavedChanges()
  self.unsavedChanges = false
  self.unsavedEvents = {}
end

function AppCoreController:getRecentProjects()
  return AppSettingsController.normalizeRecentProjects(self.recentProjects or {})
end

function AppCoreController:setRecentProjects(list, opts)
  opts = opts or {}
  self.recentProjects = AppSettingsController.normalizeRecentProjects(list or {})
  if opts.persist ~= false then
    AppSettingsController.save({ recentProjects = self.recentProjects })
  end
  return self.recentProjects
end

function AppCoreController:recordRecentProject(path, opts)
  opts = opts or {}
  local updated = AppSettingsController.addRecentProject(path, self.recentProjects or {}, 4)
  self.recentProjects = updated
  if opts.persist ~= false then
    AppSettingsController.save({ recentProjects = updated })
  end
  return updated
end

function AppCoreController:openRecentProject(basePath)
  local targetPath = RomProjectController.resolveRecentProjectLoadPath(basePath)
  if not targetPath then
    self:setStatus("Recent project files not found")
    if self.showToast then
      self:showToast("error", self.statusText)
    end
    return false
  end
  return RomProjectController.requestLoad(self, targetPath)
end

function AppCoreController:closeProject()
  return RomProjectController.closeProject(self)
end

function AppCoreController:requestCloseProject()
  if not self:hasLoadedROM() then
    return self:closeProject()
  end

  if not self:hasUnsavedChanges() then
    return self:closeProject()
  end

  local modal = self.genericActionsModal
  if not (modal and modal.show) then
    return self:closeProject()
  end

  modal:show("Unsaved Changes", {
    {
      text = "Save current and close",
      callback = function()
        local ok = true
        if self.saveAllArtifacts then
          ok = self:saveAllArtifacts({ toast = false })
        elseif self.saveBeforeQuit then
          ok = self:saveBeforeQuit()
        end
        if ok then
          self:closeProject()
        end
      end,
    },
    {
      text = "Close without saving",
      callback = function()
        self:closeProject()
      end,
    },
    {
      text = "Cancel",
      callback = function()
      end,
    },
  })
  return true
end

function AppCoreController:hasUnsavedChanges()
  return self.unsavedChanges == true
end

function AppCoreController:saveBeforeQuit()
  local ok = true
  local attempted = false
  local hasProject = not not self.projectPath
  local hasRom = self:hasLoadedROM()

  if hasProject and hasRom then
    attempted = true
    ok = self:saveProjectAndRom({ toast = false }) and ok
  elseif hasRom then
    attempted = true
    ok = self:saveEdited({ toast = false }) and ok
  end
  if not attempted then
    ok = true
  end
  if not ok then
    self:setStatus("Save failed. Quit canceled.")
  end
  return ok
end

function AppCoreController:handleQuitRequest()
  if self._allowImmediateQuit then
    return false
  end
  if not self:hasUnsavedChanges() then
    return false
  end

  if not self.quitConfirmModal:isVisible() then
    self.quitConfirmModal:show({
      onYes = function()
        if self:saveBeforeQuit() then
          self._allowImmediateQuit = true
          love.event.quit()
        end
      end,
      onNo = function()
        self._allowImmediateQuit = true
        love.event.quit()
      end,
    })
  end

  return true
end

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
  if self.canvas and self.canvas.setFilter and self.canvasFilterMode ~= key then
    self.canvas:setFilter(filter, filter)
  end
  self.canvasFilterMode = key
  if saveSetting ~= false then
    AppSettingsController.save({ canvasFilter = key })
  end
  return key
end

local function normalizePaletteLinksKey(key)
  if key == "always" then return "always" end
  if key == "on_hover" or key == "never" then return "on_hover" end
  if key == "auto_hide" then return "auto_hide" end
  return "auto_hide"
end

function AppCoreController:_getPaletteLinksForSettings()
  if self.paletteLinksMode then
    return normalizePaletteLinksKey(self.paletteLinksMode)
  end
  local settings = AppSettingsController.load()
  return normalizePaletteLinksKey(settings and settings.paletteLinks)
end

function AppCoreController:_applyPaletteLinksSetting(modeKey, saveSetting)
  local key = normalizePaletteLinksKey(modeKey)
  self.paletteLinksMode = key
  if saveSetting ~= false then
    AppSettingsController.save({ paletteLinks = key })
  end
  return key
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

function AppCoreController:_applyNeverShowResizeHandleSetting(enabled, saveSetting)
  self.neverShowResizeHandle = (enabled == true)
  if saveSetting ~= false then
    AppSettingsController.save({ neverShowResizeHandle = self.neverShowResizeHandle })
  end
  return self.neverShowResizeHandle
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
  }
  self._canvasFilterDropdown = Dropdown.new({
    getBounds = function()
      return { w = appRef.canvas:getWidth(), h = appRef.canvas:getHeight() }
    end,
    default = appRef:_getDisplayFilterDropdownMode(),
    tooltip = "Sharp or soft scaling when stretching the workspace to the window",
    items = self._canvasFilterDropdownItems,
  })
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
  return k
end

--- Settings -> Filter dropdown: sharp vs soft workspace scaling only (full-window CRT is separate).
function AppCoreController:_getDisplayFilterDropdownMode()
  if self:_getCanvasFilterForSettings() == "soft" then
    return 2
  end
  return 1
end

function AppCoreController:_applyDisplayFilterDropdownMode(mode, saveSetting)
  local m = tonumber(mode)
  if m == nil or (m ~= 1 and m ~= 2) then
    return
  end
  if m == 1 then
    self:_applyCanvasFilterSetting("sharp", saveSetting)
  else
    self:_applyCanvasFilterSetting("soft", saveSetting)
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
  self:_applyPaletteLinksSetting(D.paletteLinks, false)
  self:_applySeparateToolbarSetting(D.separateToolbar, false)
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
    paletteLinks = D.paletteLinks,
    separateToolbar = D.separateToolbar,
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
    getPaletteLinks = function()
      return appRef:_getPaletteLinksForSettings()
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
      local rows = {
        {
          id = "grouped_palette_windows",
          label = "Grouped palettes",
          buttonSpec = {
            id = "grouped_palette_windows_toggle",
            getText = function()
              return appRef:_getGroupedPaletteWindowsForSettings() and "On" or "Off"
            end,
            action = function()
              local enabled = not appRef:_getGroupedPaletteWindowsForSettings()
              appRef:_applyGroupedPaletteWindowsSetting(enabled, true)
            end,
          },
        },
      }
      if appRef.crtModeEnabled then
        if SHOW_CRT_CANVAS_RESOLUTION_SETTING_IN_UI then
          rows[#rows + 1] = {
            id = "crt_canvas_resolution",
            label = "CRT canvas",
            buttonSpec = {
              id = "crt_canvas_resolution_toggle",
              getText = function()
                local cur = appRef:_getCrtCanvasResolutionForSettings()
                return (cur == "320x180") and "320x180" or "640x360"
              end,
              action = function()
                local cur = appRef:_getCrtCanvasResolutionForSettings()
                local nextKey = (cur == "320x180") and "640x360" or "320x180"
                appRef:_applyCrtCanvasResolutionSetting(nextKey, true)
              end,
            },
          }
        end
        if appRef.crtFilterKind ~= "composite" then
          rows[#rows + 1] = {
            id = "crt_curve",
            label = "CRT curve",
            component = appRef._crtCurveSlider,
          }
        end
      end
      return rows
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
    onSetPaletteLinks = function(modeKey)
      appRef:_applyPaletteLinksSetting(modeKey, true)
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
    initialTabId = appRef._tabbedModalActiveTabIds and appRef._tabbedModalActiveTabIds.settings or nil,
    onActiveTabChange = function(tabId)
      appRef._tabbedModalActiveTabIds = appRef._tabbedModalActiveTabIds or {}
      appRef._tabbedModalActiveTabIds.settings = tabId
    end,
  })
end

function AppCoreController:showSaveOptionsModal()
  if not self.saveOptionsModal then
    self.saveOptionsModal = SaveOptionsModal.new()
  end

  if not self:hasLoadedROM() then
    self:setStatus("Open a ROM before saving.")
    return false
  end

  local options = {
    {
      text = "(1) Save edited ROM",
      callback = function()
        self:saveEdited()
      end
    },
    {
      text = "(2) Save Lua project",
      callback = function()
        self:saveProject()
      end
    },
    {
      text = "(3) Save *.ppux project",
      callback = function()
        self:saveEncodedProject()
      end
    },
    {
      text = "(4) All of the above",
      callback = function()
        self:saveAllArtifacts()
      end
    }
  }

  self.saveOptionsModal:show("Save Options", options)
  return true
end

function AppCoreController:showOpenProjectModal()
  if not self.openProjectModal then
    local OpenProjectModal = require("user_interface.modals.open_project_modal")
    self.openProjectModal = OpenProjectModal.new()
  end

  self.openProjectModal:show({
    title = "Open Project",
    initialDir = resolveOpenProjectInitialDir(self),
    onDirectoryChanged = function(path)
      self._openFileModalLastDirs = self._openFileModalLastDirs or {}
      self._openFileModalLastDirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.project] = path
    end,
    onOpen = function(path)
      self._openFileModalLastDirs = self._openFileModalLastDirs or {}
      local parent = path and path:match("^(.*)[/\\][^/\\]+$")
      self._openFileModalLastDirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.project] = parent
        or self._openFileModalLastDirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.project]
      return RomProjectController.requestLoad(self, path)
    end,
  })

  return true
end

function AppCoreController:pickReferenceBackgroundForFocusedWindow()
  if not self:hasLoadedROM() then
    self:setStatus("Open a ROM before using reference images.")
    if self.showToast then
      self:showToast("warning", self.statusText or "Open a ROM first.")
    end
    return false
  end

  local wm = self.wm
  local focus = wm and wm.getFocus and wm:getFocus() or nil
  local ReferenceBackgroundController = require("controllers.window.reference_background_controller")
  if not ReferenceBackgroundController.isEligibleWindow(focus) then
    self:setStatus("Reference images apply to layout windows only (not CHR/ROM banks or palettes).")
    if self.showToast then
      self:showToast("warning", self.statusText or "")
    end
    return false
  end

  local function openPngChooser()
    if not self.openReferencePngModal then
      local OpenReferenceBackgroundModal = require("user_interface.modals.open_reference_background_modal")
      self.openReferencePngModal = OpenReferenceBackgroundModal.new()
    end

    local targetWin = focus
    self.openReferencePngModal:show({
      title = "Set reference image layer",
      initialDir = resolveOpenReferencePngInitialDir(self),
      allowedExt = { png = true },
      onDirectoryChanged = function(path)
        self._openFileModalLastDirs = self._openFileModalLastDirs or {}
        self._openFileModalLastDirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.png] = path
      end,
      onOpen = function(path)
        self._openFileModalLastDirs = self._openFileModalLastDirs or {}
        local parent = path and path:match("^(.*)[/\\][^/\\]+$")
        self._openFileModalLastDirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.png] = parent
          or self._openFileModalLastDirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.png]
        if path and ReferenceBackgroundController.setReferenceFromAbsolutePath(targetWin, self, path) then
          local short = path:match("[^/\\]+$") or path
          self:setStatus(("Reference PNG: %s (Alt+R toggles view)"):format(short))
        end
      end,
    })
  end

  if ReferenceBackgroundController.windowHasStoredReference(focus) then
    local winRef = focus
    self.quitConfirmModal:show({
      title = "Confirm",
      message = "Remove reference background?",
      onYes = function()
        ReferenceBackgroundController.clearReference(winRef, self)
        self:setStatus("Reference image removed.")
      end,
    })
    return true
  end

  openPngChooser()
  return true
end
------------------------------------------------------------

end
