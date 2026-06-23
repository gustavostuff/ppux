local SaveController = require("controllers.rom.save_controller")
local RomProjectController = require("controllers.rom.rom_project_controller")
local AppSettingsController = require("controllers.app.settings_controller")
local SaveOptionsModal = require("user_interface.modals.save_options_modal")

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

function AppCoreController:_ensureQuitConfirmModalForUnsavedQuit()
  if self.quitConfirmModal:isVisible() then
    return
  end
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

function AppCoreController:handleQuitRequest()
  if self._allowImmediateQuit then
    return false
  end
  if not self:hasUnsavedChanges() then
    return false
  end

  self:_ensureQuitConfirmModalForUnsavedQuit()
  return true
end

--- Escape: unsaved → save/discard modal (same as window close). Otherwise first Esc opens double-confirm modal.
function AppCoreController:onEscapeQuitIntent()
  if self:hasUnsavedChanges() then
    self:_ensureQuitConfirmModalForUnsavedQuit()
    return
  end
  if self.pressEscAgainExitModal then
    self.pressEscAgainExitModal:show()
  else
    love.event.quit()
  end
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

