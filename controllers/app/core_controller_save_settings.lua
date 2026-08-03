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

local function combineProjectOnlySaveMessages(luaOk, luaStatus, ppuxOk, ppuxStatus)
  if luaOk and ppuxOk then
    return true, "Saved Lua project and compressed PPUX project"
  end
  local parts = {}
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

local function appHasOpenWindows(app)
  local wm = app and app.wm
  if not (wm and wm.getWindows) then
    return false
  end
  for _, w in ipairs(wm:getWindows() or {}) do
    if w and w._closed ~= true then
      return true
    end
  end
  return false
end

local OPEN_FILE_MODAL_RUNTIME_DIR_KEY = {
  project = "project",
  png = "png",
  saveProject = "saveProject",
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

local function resolveSaveProjectFolderInitialDir(app)
  if not app then
    return "."
  end
  -- Prefer the folder of the currently loaded / last-saved project.
  for _, path in ipairs({ app.projectPath, app.encodedProjectPath }) do
    if type(path) == "string" and path ~= "" then
      local parent = path:match("^(.*)[/\\][^/\\]+$")
      if type(parent) == "string" and parent ~= "" then
        return parent
      end
    end
  end
  local dirs = app._openFileModalLastDirs
  local remembered = dirs and dirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.saveProject]
  if type(remembered) == "string" and remembered ~= "" then
    return remembered
  end
  return resolveOpenProjectInitialDir(app)
end

local function projectStemFromPath(path)
  if type(path) ~= "string" or path == "" then
    return "untitled"
  end
  local base = path:match("([^/\\]+)$") or path
  base = base:gsub("%.lua$", ""):gsub("%.ppux$", ""):gsub("%.nes$", "")
  base = base:gsub("_edited$", ""):gsub("_project$", "")
  if base == "" then
    return "untitled"
  end
  return base
end

local function sanitizeProjectStem(stemOverride, app)
  local stem = nil
  if type(stemOverride) == "string" and stemOverride ~= "" then
    stem = stemOverride:gsub("[/\\]", "")
    stem = stem:gsub("%.lua$", ""):gsub("%.ppux$", ""):gsub("%.nes$", "")
    stem = stem:match("^%s*(.-)%s*$")
  end
  if not stem or stem == "" then
    stem = projectStemFromPath(app and app.projectPath)
    if stem == "untitled" and type(app and app.encodedProjectPath) == "string" then
      local encodedStem = projectStemFromPath(app.encodedProjectPath)
      if encodedStem ~= "untitled" then
        stem = encodedStem
      end
    end
  end
  if not stem or stem == "" then
    stem = "untitled"
  end
  return stem
end

local function buildNoRomProjectPaths(dir, stem)
  local FilesystemPath = require("utils.filesystem_path")
  return FilesystemPath.join(dir, stem .. ".lua"), FilesystemPath.join(dir, stem .. ".ppux")
end

local function fileExistsOnDisk(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local f = io.open(path, "rb")
  if not f then
    return false
  end
  f:close()
  return true
end

--- @param formats "lua"|"ppux"|"both"
local function existingNoRomSaveTargets(luaPath, ppuxPath, formats)
  local targets = {}
  if formats == "lua" or formats == "both" then
    if fileExistsOnDisk(luaPath) then
      targets[#targets + 1] = luaPath
    end
  end
  if formats == "ppux" or formats == "both" then
    if fileExistsOnDisk(ppuxPath) then
      targets[#targets + 1] = ppuxPath
    end
  end
  return targets
end

--- Point no-ROM project save targets at `dir` with optional explicit `stem`.
local function applyNoRomProjectSaveFolder(app, dir, stemOverride)
  if type(dir) ~= "string" or dir == "" then
    return false
  end
  local stem = sanitizeProjectStem(stemOverride, app)
  local luaPath, ppuxPath = buildNoRomProjectPaths(dir, stem)
  app.projectPath = luaPath
  app.encodedProjectPath = ppuxPath
  _G.projectPath = app.projectPath
  return true, stem, luaPath, ppuxPath
end

function AppCoreController:canSaveProjectWorkspace()
  return self:hasLoadedROM() or appHasOpenWindows(self)
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
  if not self:canSaveProjectWorkspace() then
    self:setStatus("Nothing to save (create a window or open a ROM first).")
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
  if not self:canSaveProjectWorkspace() then
    self:setStatus("Nothing to save (create a window or open a ROM first).")
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
  if not self:canSaveProjectWorkspace() then
    self:setStatus("Nothing to save (create a window or open a ROM first).")
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

  local romRequested = self:hasLoadedROM()
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
  if not self:canSaveProjectWorkspace() then
    self:setStatus("Nothing to save (create a window or open a ROM first).")
    if opts.toast ~= false then
      self:showToast("error", self.statusText)
    end
    return false
  end

  local hasRom = self:hasLoadedROM()
  local romOk = true
  local romStatus = nil
  if hasRom then
    romOk = self:saveEdited({
      toast = false,
      clearUnsaved = false,
    })
    romStatus = self.statusText
  end

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

  local ok, message
  if hasRom then
    ok, message = combineAllSaveMessages(luaOk, luaStatus, ppuxOk, ppuxStatus, romOk, romStatus)
  else
    ok, message = combineProjectOnlySaveMessages(luaOk, luaStatus, ppuxOk, ppuxStatus)
  end
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

function AppCoreController:clearRecentProjects(opts)
  opts = opts or {}
  local cleared = self:setRecentProjects({}, opts)
  if opts.status ~= false and self.setStatus then
    self:setStatus("Recent projects cleared.")
  end
  if opts.toast ~= false and self.showToast then
    self:showToast("info", "Recent projects cleared.")
  end
  return cleared
end

function AppCoreController:recordRecentProject(path, opts)
  opts = opts or {}
  local DebugController = require("controllers.dev.debug_controller")
  DebugController.log("info", "RECENT_PROJECT", "recordRecentProject: input=%q", tostring(path))
  local updated = AppSettingsController.addRecentProject(path, self.recentProjects or {}, 4)
  self.recentProjects = updated
  for i, stored in ipairs(updated) do
    DebugController.log("info", "RECENT_PROJECT", "recordRecentProject: stored[%d]=%q", i, tostring(stored))
  end
  if opts.persist ~= false then
    AppSettingsController.save({ recentProjects = updated })
  end
  return updated
end

function AppCoreController:openRecentProject(basePath)
  local DebugController = require("controllers.dev.debug_controller")
  local recent = self.getRecentProjects and self:getRecentProjects() or {}
  DebugController.log(
    "info",
    "RECENT_PROJECT",
    "openRecentProject: requested=%q recentCount=%d",
    tostring(basePath),
    #recent
  )
  for i, stored in ipairs(recent) do
    DebugController.log("info", "RECENT_PROJECT", "openRecentProject: recent[%d]=%q", i, tostring(stored))
  end

  local targetPath = RomProjectController.resolveRecentProjectLoadPath(basePath, { log = true })
  if not targetPath then
    DebugController.log(
      "error",
      "RECENT_PROJECT",
      "openRecentProject: NOT FOUND for basePath=%q",
      tostring(basePath)
    )
    self:setStatus("Recent project files not found")
    if self.showToast then
      self:showToast("error", self.statusText)
    end
    return false
  end
  local FilesystemPath = require("utils.filesystem_path")
  targetPath = FilesystemPath.toAbsolutePath(targetPath) or targetPath
  DebugController.log("info", "RECENT_PROJECT", "openRecentProject: loading %q", tostring(targetPath))
  return RomProjectController.requestLoad(self, targetPath)
end

function AppCoreController:closeProject()
  return RomProjectController.closeProject(self)
end

function AppCoreController:requestCloseProject()
  if not self:hasLoadedROM() and not appHasOpenWindows(self) then
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
  local hasWindows = appHasOpenWindows(self)

  if hasRom and (hasProject or hasWindows) then
    attempted = true
    ok = self:saveProjectAndRom({ toast = false }) and ok
  elseif hasRom then
    attempted = true
    ok = self:saveEdited({ toast = false }) and ok
  elseif hasProject or hasWindows then
    attempted = true
    ok = self:saveAllArtifacts({ toast = false }) and ok
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

  if not self:canSaveProjectWorkspace() then
    self:setStatus("Nothing to save (create a window or open a ROM first).")
    if self.showToast then
      self:showToast("warning", self.statusText)
    end
    return false
  end

  local options
  if self:hasLoadedROM() then
    options = {
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
  else
    options = {
      {
        text = "Save Lua project",
        callback = function()
          self:showSaveProjectFolderModal({
            title = "Save Lua Project Folder",
            formats = "lua",
            onConfirm = function()
              self:saveProject()
            end,
          })
        end
      },
      {
        text = "Save *.ppux project",
        callback = function()
          self:showSaveProjectFolderModal({
            title = "Save PPUX Project Folder",
            formats = "ppux",
            onConfirm = function()
              self:saveEncodedProject()
            end,
          })
        end
      },
      {
        text = "Save both project formats",
        callback = function()
          self:showSaveProjectFolderModal({
            title = "Save Project Folder",
            formats = "both",
            onConfirm = function()
              self:saveAllArtifacts()
            end,
          })
        end
      }
    }
  end

  self.saveOptionsModal:show(
    self:hasLoadedROM() and "Save Options" or "Save Options (no ROM)",
    options
  )
  return true
end

function AppCoreController:showSaveProjectFolderModal(opts)
  opts = opts or {}
  if not self.saveProjectFolderModal then
    local SaveProjectFolderModal = require("user_interface.modals.save_project_folder_modal")
    self.saveProjectFolderModal = SaveProjectFolderModal.new()
  end

  local formats = opts.formats or "both"
  if formats ~= "lua" and formats ~= "ppux" and formats ~= "both" then
    formats = "both"
  end

  local initialName = opts.initialProjectName
  if type(initialName) ~= "string" or initialName == "" then
    initialName = projectStemFromPath(self.projectPath)
    if initialName == "untitled" then
      initialName = projectStemFromPath(self.encodedProjectPath)
    end
  end

  self.saveProjectFolderModal:show({
    title = opts.title or "Save Project Folder",
    confirmLabel = opts.confirmLabel or "Save here",
    directoriesOnly = true,
    initialDir = resolveSaveProjectFolderInitialDir(self),
    initialProjectName = initialName,
    onDirectoryChanged = function(path)
      self._openFileModalLastDirs = self._openFileModalLastDirs or {}
      self._openFileModalLastDirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.saveProject] = path
    end,
    onOpen = function(dir, entry)
      self._openFileModalLastDirs = self._openFileModalLastDirs or {}
      self._openFileModalLastDirs[OPEN_FILE_MODAL_RUNTIME_DIR_KEY.saveProject] = dir
      local stem = entry and (entry.projectName or entry.name) or nil
      stem = sanitizeProjectStem(stem, self)
      local luaPath, ppuxPath = buildNoRomProjectPaths(dir, stem)
      local existing = existingNoRomSaveTargets(luaPath, ppuxPath, formats)

      local function proceed()
        self.projectPath = luaPath
        self.encodedProjectPath = ppuxPath
        _G.projectPath = self.projectPath
        if type(opts.onConfirm) == "function" then
          opts.onConfirm(dir, stem)
        end
      end

      if #existing == 0 or self.skipOverwriteConfirm == true then
        proceed()
        return
      end

      local modal = self.genericActionsModal
      if not (modal and modal.show) then
        proceed()
        return
      end

      local label
      if #existing == 1 then
        local base = existing[1]:match("([^/\\]+)$") or existing[1]
        label = "Overwrite " .. tostring(base) .. "?"
      else
        label = "Overwrite existing project files?"
      end

      modal:show(label, {
        {
          text = "Overwrite",
          callback = function()
            if modal.isCheckboxChecked and modal:isCheckboxChecked() then
              self.skipOverwriteConfirm = true
            end
            proceed()
          end,
        },
        {
          text = "Cancel",
          callback = function()
          end,
        },
      }, {
        checkbox = {
          text = "Don't ask again",
          checked = false,
        },
      })
    end,
  })

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

