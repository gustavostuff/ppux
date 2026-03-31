local SaveController = require("controllers.rom.save_controller")
local RomProjectController = require("controllers.rom.rom_project_controller")
local AppSettingsController = require("controllers.app.settings_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local SaveOptionsModal = require("user_interface.modals.save_options_modal")
local SettingsModal = require("user_interface.modals.settings_modal")

return function(AppCoreController)
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
  return key
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

function AppCoreController:showSettingsModal()
  if not self.settingsModal then
    self.settingsModal = SettingsModal.new()
  end

  local appRef = self

  self.settingsModal:show({
    title = "Settings",
    getCanvasImageMode = function()
      return appRef:_getCanvasImageModeForSettings()
    end,
    getCanvasFilter = function()
      return appRef:_getCanvasFilterForSettings()
    end,
    getTooltipsEnabled = function()
      return appRef:_getTooltipsEnabledForSettings()
    end,
    getPaletteLinks = function()
      return appRef:_getPaletteLinksForSettings()
    end,
    onSetCanvasImageMode = function(modeKey)
      local key = appRef:_applyCanvasImageModeSetting(modeKey, true)
      local labels = {
        pixel_perfect = "Pixel Perfect",
        stretch = "Stretch",
        keep_aspect = "Keep Aspect Ratio",
      }
      appRef:setStatus(string.format("Canvas image: %s", labels[key] or key))
    end,
    onSetCanvasFilter = function(filterKey)
      local key = appRef:_applyCanvasFilterSetting(filterKey, true)
      appRef:setStatus(string.format("Canvas filter: %s", key == "soft" and "Soft" or "Sharp"))
    end,
    onSetTooltipsEnabled = function(enabled)
      local applied = appRef:_applyTooltipsEnabledSetting(enabled, true)
      appRef:setStatus(string.format("Tooltips: %s", applied and "On" or "Off"))
    end,
    onSetPaletteLinks = function(modeKey)
      local applied = appRef:_applyPaletteLinksSetting(modeKey, true)
      local labels = {
        always = "Always",
        auto_hide = "Auto-hide",
        on_hover = "On-hover",
      }
      appRef:setStatus(string.format("Palette links: %s", labels[applied] or applied))
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
      text = "Save edited ROM",
      callback = function()
        self:saveEdited()
      end
    },
    {
      text = "Save Lua project",
      callback = function()
        self:saveProject()
      end
    },
    {
      text = "Save *.ppux project",
      callback = function()
        self:saveEncodedProject()
      end
    },
    {
      text = "All of the above",
      callback = function()
        self:saveAllArtifacts()
      end
    }
  }

  self.saveOptionsModal:show("Save Options", options)
  return true
end

------------------------------------------------------------

end
