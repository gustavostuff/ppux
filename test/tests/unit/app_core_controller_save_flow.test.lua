local AppCoreController = require("controllers.app.core_controller")
local RomProjectController = require("controllers.rom.rom_project_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local KeyboardDebugController = require("controllers.input.keyboard_debug_controller")
local KeyboardWindowShortcutsController = require("controllers.input.keyboard_window_shortcuts_controller")

describe("core_controller.lua - combined save flow", function()
  local originalSaveEncodedProject
  local originalHandleDebugKeys
  local originalHandleWindowScaling
  local originalHandleFullscreen
  local originalGetScaledMouse

  beforeEach(function()
    originalSaveEncodedProject = RomProjectController.saveEncodedProject
    originalHandleDebugKeys = KeyboardDebugController.handleDebugKeys
    originalHandleWindowScaling = KeyboardWindowShortcutsController.handleWindowScaling
    originalHandleFullscreen = KeyboardWindowShortcutsController.handleFullscreen
    originalGetScaledMouse = ResolutionController.getScaledMouse
  end)

  afterEach(function()
    RomProjectController.saveEncodedProject = originalSaveEncodedProject
    KeyboardDebugController.handleDebugKeys = originalHandleDebugKeys
    KeyboardWindowShortcutsController.handleWindowScaling = originalHandleWindowScaling
    KeyboardWindowShortcutsController.handleFullscreen = originalHandleFullscreen
    ResolutionController.getScaledMouse = originalGetScaledMouse
  end)

  it("shows one success toast when saving both project and ROM", function()
    local toastCalls = {}
    local clearCount = 0
    local app = setmetatable({
      appEditState = {
        romSha1 = "abc123",
        romRaw = "rom-bytes",
        romOriginalPath = "/tmp/test.nes",
      },
      saveProject = function(self, opts)
        self.projectOpts = opts
        self.statusText = "Saved project: /tmp/test_project.lua"
        return true
      end,
      saveEdited = function(self, opts)
        self.romOpts = opts
        self.statusText = "Saved ROM & edits: /tmp/test.nes"
        return true
      end,
      clearUnsavedChanges = function()
        clearCount = clearCount + 1
      end,
      showToast = function(_, kind, text)
        toastCalls[#toastCalls + 1] = {
          kind = kind,
          text = text,
        }
      end,
    }, AppCoreController)

    local ok = app:saveProjectAndRom()

    expect(ok).toBe(true)
    expect(app.projectOpts).toEqual({
      toast = false,
      clearUnsaved = false,
    })
    expect(app.romOpts).toEqual({
      toast = false,
      clearUnsaved = false,
    })
    expect(clearCount).toBe(1)
    expect(#toastCalls).toBe(1)
    expect(toastCalls[1].kind).toBe("info")
    expect(toastCalls[1].text).toBe("Saved project and exported ROM")
  end)

  it("shows one error toast and preserves failure detail when ROM save fails", function()
    local toastCalls = {}
    local clearCount = 0
    local app = setmetatable({
      appEditState = {
        romSha1 = "abc123",
        romRaw = "rom-bytes",
        romOriginalPath = "/tmp/test.nes",
      },
      saveProject = function(self, opts)
        self.projectOpts = opts
        self.statusText = "Saved project: /tmp/test_project.lua"
        return true
      end,
      saveEdited = function(self, opts)
        self.romOpts = opts
        self.statusText = "Save failed: disk full"
        return false
      end,
      clearUnsavedChanges = function()
        clearCount = clearCount + 1
      end,
      showToast = function(_, kind, text)
        toastCalls[#toastCalls + 1] = {
          kind = kind,
          text = text,
        }
      end,
    }, AppCoreController)

    local ok = app:saveProjectAndRom()

    expect(ok).toBe(false)
    expect(app.projectOpts).toEqual({
      toast = false,
      clearUnsaved = false,
    })
    expect(app.romOpts).toEqual({
      toast = false,
      clearUnsaved = false,
    })
    expect(clearCount).toBe(0)
    expect(#toastCalls).toBe(1)
    expect(toastCalls[1].kind).toBe("error")
    expect(toastCalls[1].text).toBe("Save failed: disk full (project saved)")
  end)

  it("shows one success toast when saving encoded project", function()
    local toastCalls = {}
    local clearCount = 0
    RomProjectController.saveEncodedProject = function(self)
      self.statusText = "Saved encoded project: /tmp/test_project.ppux"
      return true
    end
    local app = setmetatable({
      appEditState = {
        romSha1 = "abc123",
        romRaw = "rom-bytes",
        romOriginalPath = "/tmp/test.nes",
      },
      clearUnsavedChanges = function()
        clearCount = clearCount + 1
      end,
      showToast = function(_, kind, text)
        toastCalls[#toastCalls + 1] = {
          kind = kind,
          text = text,
        }
      end,
    }, AppCoreController)

    local ok = app:saveEncodedProject()

    expect(ok).toBe(true)
    expect(clearCount).toBe(1)
    expect(#toastCalls).toBe(1)
    expect(toastCalls[1].kind).toBe("info")
    expect(toastCalls[1].text).toBe("Saved encoded project: /tmp/test_project.ppux")
  end)

  it("shows one success toast when saving all artifacts", function()
    local toastCalls = {}
    local clearCount = 0
    local app = setmetatable({
      appEditState = {
        romSha1 = "abc123",
        romRaw = "rom-bytes",
        romOriginalPath = "/tmp/test.nes",
      },
      saveEdited = function(self, opts)
        self.romOpts = opts
        self.statusText = "Saved ROM & edits: /tmp/test_edited.nes"
        return true
      end,
      saveProject = function(self, opts)
        self.luaOpts = opts
        self.statusText = "Saved project: /tmp/test_project.lua"
        return true
      end,
      saveEncodedProject = function(self, opts)
        self.ppuxOpts = opts
        self.statusText = "Saved encoded project: /tmp/test_project.ppux"
        return true
      end,
      clearUnsavedChanges = function()
        clearCount = clearCount + 1
      end,
      showToast = function(_, kind, text)
        toastCalls[#toastCalls + 1] = {
          kind = kind,
          text = text,
        }
      end,
    }, AppCoreController)

    local ok = app:saveAllArtifacts()

    expect(ok).toBe(true)
    expect(app.romOpts).toEqual({
      toast = false,
      clearUnsaved = false,
    })
    expect(app.luaOpts).toEqual({
      toast = false,
      clearUnsaved = false,
    })
    expect(app.ppuxOpts).toEqual({
      toast = false,
      clearUnsaved = false,
    })
    expect(clearCount).toBe(1)
    expect(#toastCalls).toBe(1)
    expect(toastCalls[1].kind).toBe("info")
    expect(toastCalls[1].text).toBe("Saved ROM, Lua project, and compressed PPUX project")
  end)

  it("closes the project immediately when there are no unsaved changes", function()
    local closed = 0
    local app = setmetatable({
      hasLoadedROM = function() return true end,
      hasUnsavedChanges = function() return false end,
      closeProject = function()
        closed = closed + 1
        return true
      end,
    }, AppCoreController)

    local ok = app:requestCloseProject()
    expect(ok).toBe(true)
    expect(closed).toBe(1)
  end)

  it("prompts before closing the project when there are unsaved changes", function()
    local shown = nil
    local closed = 0
    local app = setmetatable({
      hasLoadedROM = function() return true end,
      hasUnsavedChanges = function() return true end,
      closeProject = function()
        closed = closed + 1
        return true
      end,
      genericActionsModal = {
        show = function(_, title, options)
          shown = {
            title = title,
            options = options,
          }
        end,
      },
    }, AppCoreController)

    local ok = app:requestCloseProject()
    expect(ok).toBe(true)
    expect(shown).toBeTruthy()
    expect(shown.title).toBe("Unsaved Changes")
    expect(#shown.options).toBe(3)
    expect(shown.options[1].text).toBe("Save current and close")
    expect(shown.options[2].text).toBe("Close without saving")
    shown.options[2].callback()
    expect(closed).toBe(1)
  end)

  it("saves project-only when no ROM is loaded but sketch windows exist", function()
    local toastCalls = {}
    local clearCount = 0
    local app = setmetatable({
      appEditState = {},
      wm = {
        getWindows = function()
          return { { kind = "sketch_canvas", _closed = false } }
        end,
      },
      saveProject = function(self, opts)
        self.projectOpts = opts
        self.statusText = "Saved project: /tmp/untitled.lua"
        return true
      end,
      saveEdited = function()
        error("saveEdited should not be called without a loaded ROM")
      end,
      clearUnsavedChanges = function()
        clearCount = clearCount + 1
      end,
      showToast = function(_, kind, text)
        toastCalls[#toastCalls + 1] = {
          kind = kind,
          text = text,
        }
      end,
    }, AppCoreController)

    local ok = app:saveProjectAndRom()

    expect(ok).toBe(true)
    expect(app.projectOpts).toBeTruthy()
    expect(clearCount).toBe(1)
    expect(#toastCalls).toBe(1)
    expect(toastCalls[1].kind).toBe("info")
    expect(toastCalls[1].text).toBe("Saved project (no ROM loaded)")
  end)

  it("opens no-ROM save options from Ctrl+S when a sketch window exists", function()
    local status
    local showCount = 0
    local shownTitle = nil
    local shownOptions = nil
    local oldIsDown = love.keyboard.isDown

    love.keyboard.isDown = function(key)
      return key == "lctrl" or key == "rctrl"
    end

    local app = setmetatable({
      appEditState = {},
      wm = {
        getWindows = function()
          return { { kind = "sketch_canvas", _closed = false } }
        end,
      },
      quitConfirmModal = { isVisible = function() return false end },
      saveOptionsModal = {
        isVisible = function() return false end,
        handleKey = function() return false end,
        show = function(_, title, options)
          showCount = showCount + 1
          shownTitle = title
          shownOptions = options
        end,
      },
      genericActionsModal = { isVisible = function() return false end, handleKey = function() return false end },
      settingsModal = { isVisible = function() return false end, handleKey = function() return false end },
      newWindowModal = { isVisible = function() return false end, handleKey = function() return false end },
      splash = { isVisible = function() return false end, keypressed = function() return false end },
      hasLoadedROM = function() return false end,
      setStatus = function(self, text)
        status = text
        self.statusText = text
      end,
    }, AppCoreController)

    app:keypressed("s")

    love.keyboard.isDown = oldIsDown

    expect(showCount).toBe(1)
    expect(status).toBe(nil)
    expect(shownTitle).toBe("Save Options (no ROM)")
    expect(#shownOptions).toBe(3)
    expect(shownOptions[1].text).toBe("Save Lua project")
    expect(shownOptions[2].text).toBe("Save *.ppux project")
    expect(shownOptions[3].text).toBe("Save both project formats")
  end)

  it("toggles Mirror X on a sketch window without requiring a ROM", function()
    local sketch = {
      kind = "sketch_canvas",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      _mirrorXPreview = false,
    }
    local app = setmetatable({
      hasLoadedROM = function() return false end,
      wm = {
        getFocus = function()
          return sketch
        end,
      },
      setStatus = function() end,
    }, AppCoreController)

    local changed, on = app:togglePreviewMirrorX()
    expect(changed).toBe(true)
    expect(on).toBe(true)
    expect(sketch._mirrorXPreview).toBe(true)

    changed, on = app:togglePreviewMirrorX()
    expect(changed).toBe(true)
    expect(on).toBe(false)
    expect(sketch._mirrorXPreview).toBe(false)
  end)

  it("toggles Mirror X from M on a focused sketch window without a ROM", function()
    local status = nil
    local sketch = {
      kind = "sketch_canvas",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      _mirrorXPreview = false,
    }
    local oldIsDown = love.keyboard.isDown
    love.keyboard.isDown = function()
      return false
    end

    local app = setmetatable({
      hasLoadedROM = function() return false end,
      wm = {
        getFocus = function()
          return sketch
        end,
      },
      quitConfirmModal = { isVisible = function() return false end },
      saveOptionsModal = { isVisible = function() return false end, handleKey = function() return false end },
      genericActionsModal = { isVisible = function() return false end, handleKey = function() return false end },
      settingsModal = { isVisible = function() return false end, handleKey = function() return false end },
      newWindowModal = { isVisible = function() return false end, handleKey = function() return false end },
      splash = { isVisible = function() return false end, keypressed = function() return false end },
      setStatus = function(_, text)
        status = text
      end,
    }, AppCoreController)

    app:keypressed("m")
    love.keyboard.isDown = oldIsDown

    expect(sketch._mirrorXPreview).toBe(true)
    expect(status).toBe("Mirror X on for this window.")
  end)

  it("opens folder picker before no-ROM Lua project save", function()
    local folderShown = nil
    local saveCalls = 0
    local app = setmetatable({
      appEditState = {},
      wm = {
        getWindows = function()
          return { { kind = "sketch_canvas", _closed = false } }
        end,
      },
      hasLoadedROM = function() return false end,
      projectPath = nil,
      encodedProjectPath = nil,
      _openFileModalLastDirs = {},
      saveProject = function(self)
        saveCalls = saveCalls + 1
        self.statusText = "Saved project: " .. tostring(self.projectPath)
        return true
      end,
      showToast = function() end,
      setStatus = function(self, text)
        self.statusText = text
      end,
      saveProjectFolderModal = {
        show = function(_, opts)
          folderShown = opts
        end,
        isVisible = function() return false end,
      },
      saveOptionsModal = {
        show = function() end,
        isVisible = function() return false end,
      },
      genericActionsModal = {
        show = function()
          error("overwrite modal should not open when target is missing")
        end,
      },
    }, AppCoreController)

    expect(app:showSaveOptionsModal()).toBe(true)
    local items = nil
    app.saveOptionsModal.show = function(_, _title, options)
      items = options
    end
    app:showSaveOptionsModal()
    expect(items).toBeTruthy()
    items[1].callback()
    expect(folderShown).toBeTruthy()
    expect(folderShown.title).toBe("Save Lua Project Folder")
    expect(folderShown.directoriesOnly).toBe(true)
    expect(type(folderShown.initialDir)).toBe("string")
    expect(type(folderShown.onOpen)).toBe("function")

    folderShown.onOpen("/tmp/sketch_out", { projectName = "my_art", name = "my_art" })
    expect(app.projectPath).toBe("/tmp/sketch_out/my_art.lua")
    expect(app.encodedProjectPath).toBe("/tmp/sketch_out/my_art.ppux")
    expect(saveCalls).toBe(1)
  end)

  it("prefers the loaded project folder when opening the no-ROM save dialog", function()
    local folderShown = nil
    local app = setmetatable({
      appEditState = {},
      wm = {
        getWindows = function()
          return { { kind = "sketch_canvas", _closed = false } }
        end,
      },
      hasLoadedROM = function() return false end,
      projectPath = "/home/g/art/gallery.lua",
      encodedProjectPath = "/home/g/art/gallery.ppux",
      _openFileModalLastDirs = {
        saveProject = "/tmp/other",
      },
      saveProjectFolderModal = {
        show = function(_, opts)
          folderShown = opts
        end,
      },
    }, AppCoreController)

    app:showSaveProjectFolderModal({
      formats = "lua",
      onConfirm = function() end,
    })
    expect(folderShown.initialDir).toBe("/home/g/art")
    expect(folderShown.initialProjectName).toBe("gallery")
  end)

  it("asks to overwrite when the no-ROM save target already exists", function()
    local overwriteTitle = nil
    local overwriteOptions = nil
    local overwriteOpts = nil
    local folderOpts = nil
    local saveCalls = 0
    local tmpDir = "/tmp"
    local stem = "ppux_overwrite_test_" .. tostring(os.time())
    local luaPath = tmpDir .. "/" .. stem .. ".lua"
    local f = assert(io.open(luaPath, "wb"))
    f:write("-- existing\n")
    f:close()

    local app = setmetatable({
      appEditState = {},
      wm = {
        getWindows = function()
          return { { kind = "sketch_canvas", _closed = false } }
        end,
      },
      hasLoadedROM = function() return false end,
      projectPath = nil,
      encodedProjectPath = nil,
      skipOverwriteConfirm = false,
      _openFileModalLastDirs = {},
      saveProject = function()
        saveCalls = saveCalls + 1
        return true
      end,
      saveProjectFolderModal = {
        show = function(_, opts)
          folderOpts = opts
        end,
      },
      genericActionsModal = {
        checkboxChecked = false,
        isCheckboxChecked = function(self)
          return self.checkboxChecked == true
        end,
        show = function(self, title, options, opts)
          overwriteTitle = title
          overwriteOptions = options
          overwriteOpts = opts
          self.checkboxChecked = opts and opts.checkbox and opts.checkbox.checked == true
        end,
      },
    }, AppCoreController)

    app:showSaveProjectFolderModal({
      formats = "lua",
      onConfirm = function()
        app:saveProject()
      end,
    })
    expect(folderOpts).toBeTruthy()
    folderOpts.onOpen(tmpDir, { projectName = stem, name = stem })
    expect(saveCalls).toBe(0)
    expect(overwriteTitle).toBe("Overwrite " .. stem .. ".lua?")
    expect(overwriteOptions[1].text).toBe("Overwrite")
    expect(overwriteOpts.checkbox.text).toBe("Don't ask again")
    overwriteOptions[1].callback()
    expect(saveCalls).toBe(1)
    expect(app.projectPath).toBe(luaPath)
    expect(app.skipOverwriteConfirm).toBe(false)

    os.remove(luaPath)
  end)

  it("skips overwrite confirm when the project flag is set", function()
    local overwriteShown = false
    local saveCalls = 0
    local tmpDir = "/tmp"
    local stem = "ppux_skip_overwrite_" .. tostring(os.time())
    local luaPath = tmpDir .. "/" .. stem .. ".lua"
    local f = assert(io.open(luaPath, "wb"))
    f:write("-- existing\n")
    f:close()

    local folderOpts = nil
    local app = setmetatable({
      appEditState = {},
      hasLoadedROM = function() return false end,
      skipOverwriteConfirm = true,
      projectPath = nil,
      encodedProjectPath = nil,
      _openFileModalLastDirs = {},
      saveProject = function()
        saveCalls = saveCalls + 1
        return true
      end,
      saveProjectFolderModal = {
        show = function(_, opts)
          folderOpts = opts
        end,
      },
      genericActionsModal = {
        show = function()
          overwriteShown = true
        end,
      },
    }, AppCoreController)

    app:showSaveProjectFolderModal({
      formats = "lua",
      onConfirm = function()
        app:saveProject()
      end,
    })
    folderOpts.onOpen(tmpDir, { projectName = stem, name = stem })
    expect(overwriteShown).toBe(false)
    expect(saveCalls).toBe(1)
    expect(app.projectPath).toBe(luaPath)

    os.remove(luaPath)
  end)

  it("stores don't-ask-again as skipOverwriteConfirm on the project", function()
    local overwriteOptions = nil
    local folderOpts = nil
    local tmpDir = "/tmp"
    local stem = "ppux_dont_ask_" .. tostring(os.time())
    local luaPath = tmpDir .. "/" .. stem .. ".lua"
    local f = assert(io.open(luaPath, "wb"))
    f:write("-- existing\n")
    f:close()

    local app = setmetatable({
      appEditState = {},
      hasLoadedROM = function() return false end,
      skipOverwriteConfirm = false,
      projectPath = nil,
      encodedProjectPath = nil,
      _openFileModalLastDirs = {},
      saveProject = function() return true end,
      saveProjectFolderModal = {
        show = function(_, opts)
          folderOpts = opts
        end,
      },
      genericActionsModal = {
        checkboxChecked = true,
        isCheckboxChecked = function(self)
          return self.checkboxChecked == true
        end,
        show = function(self, _title, options)
          overwriteOptions = options
        end,
      },
    }, AppCoreController)

    app:showSaveProjectFolderModal({
      formats = "lua",
      onConfirm = function() end,
    })
    folderOpts.onOpen(tmpDir, { projectName = stem, name = stem })
    overwriteOptions[1].callback()
    expect(app.skipOverwriteConfirm).toBe(true)

    os.remove(luaPath)
  end)

  it("opens new window modal from Ctrl+N when no ROM is loaded (sketch/PT/sketch palette)", function()
    local status
    local showCount = 0
    local shownOptions = nil
    local oldIsDown = love.keyboard.isDown

    love.keyboard.isDown = function(key)
      return key == "lctrl" or key == "rctrl"
    end

    local app = setmetatable({
      appEditState = {},
      wm = {},
      quitConfirmModal = { isVisible = function() return false end },
      saveOptionsModal = { isVisible = function() return false end, handleKey = function() return false end },
      genericActionsModal = { isVisible = function() return false end, handleKey = function() return false end },
      settingsModal = { isVisible = function() return false end, handleKey = function() return false end },
      newWindowTypeModal = {
        isVisible = function() return false end,
        handleKey = function() return false end,
        show = function(_, _title, options)
          showCount = showCount + 1
          shownOptions = options
        end,
      },
      newWindowModal = {
        isVisible = function() return false end,
        handleKey = function() return false end,
      },
      splash = { isVisible = function() return false end, keypressed = function() return false end },
      hasLoadedROM = function() return false end,
      setStatus = function(self, text)
        status = text
        self.statusText = text
      end,
    }, AppCoreController)

    app:keypressed("n")

    love.keyboard.isDown = oldIsDown

    expect(showCount).toBe(1)
    expect(status).toBe(nil)
    expect(#shownOptions).toBe(3)
    expect(shownOptions[1].text).toBe("ROM Palette window")
    expect(shownOptions[2].text).toBe("Sketch canvas window")
    expect(shownOptions[3].text).toBe("Pattern table window")
  end)

  it("opens open project modal from Ctrl+O", function()
    local openCalls = 0
    local oldIsDown = love.keyboard.isDown

    love.keyboard.isDown = function(key)
      return key == "lctrl" or key == "rctrl"
    end

    local app = setmetatable({
      appEditState = {},
      quitConfirmModal = { isVisible = function() return false end },
      saveOptionsModal = { isVisible = function() return false end, handleKey = function() end },
      genericActionsModal = { isVisible = function() return false end, handleKey = function() end },
      settingsModal = { isVisible = function() return false end, handleKey = function() end },
      newWindowTypeModal = { isVisible = function() return false end, handleKey = function() end },
      newWindowModal = { isVisible = function() return false end, handleKey = function() end },
      openProjectModal = { isVisible = function() return false end, handleKey = function() end },
      renameWindowModal = { isVisible = function() return false end, handleKey = function() end },
      romPaletteAddressModal = { isVisible = function() return false end, handleKey = function() end },
      ppuFrameSpriteLayerModeModal = { isVisible = function() return false end, handleKey = function() end },
      ppuFrameAddSpriteModal = { isVisible = function() return false end, handleKey = function() end },
      ppuFrameRangeModal = { isVisible = function() return false end, handleKey = function() end },
      ppuFramePatternRangeModal = { isVisible = function() return false end, handleKey = function() end },
      textFieldDemoModal = { isVisible = function() return false end, handleKey = function() end },
      splash = { isVisible = function() return false end, keypressed = function() end },
      showOpenProjectModal = function()
        openCalls = openCalls + 1
      end,
    }, AppCoreController)

    app:keypressed("o")

    love.keyboard.isDown = oldIsDown

    expect(openCalls).toBe(1)
  end)

  it("handles debug hotkeys before splash interception", function()
    local oldIsDown = love.keyboard.isDown
    local debugCalls = 0

    love.keyboard.isDown = function()
      return false
    end

    KeyboardDebugController.handleDebugKeys = function(ctx, utils, key)
      debugCalls = debugCalls + 1
      return key == "f8"
    end

    local splashCalls = 0
    local app = setmetatable({
      appEditState = {},
      wm = {
        getFocus = function() return nil end,
      },
      quitConfirmModal = { isVisible = function() return false end },
      saveOptionsModal = { isVisible = function() return false end, handleKey = function() return false end },
      genericActionsModal = { isVisible = function() return false end, handleKey = function() return false end },
      settingsModal = { isVisible = function() return false end, handleKey = function() return false end },
      newWindowModal = { isVisible = function() return false end, handleKey = function() return false end },
      renameWindowModal = { isVisible = function() return false end, handleKey = function() return false end },
      splash = {
        isVisible = function() return true end,
        keypressed = function() splashCalls = splashCalls + 1 end,
      },
      setStatus = function(self, text)
        self.statusText = text
      end,
    }, AppCoreController)

    app:keypressed("f8")

    love.keyboard.isDown = oldIsDown

    expect(debugCalls).toBe(1)
    expect(splashCalls).toBe(0)
  end)

  it("keeps window scale and fullscreen shortcuts active while a modal is visible", function()
    local oldIsDown = love.keyboard.isDown
    local scalingCalls = 0
    local fullscreenCalls = 0
    local modalKeyCalls = 0

    love.keyboard.isDown = function(key)
      return key == "lctrl" or key == "rctrl"
    end

    KeyboardWindowShortcutsController.handleWindowScaling = function(_, _, key, app)
      scalingCalls = scalingCalls + 1
      return key == "2" and app ~= nil
    end
    KeyboardWindowShortcutsController.handleFullscreen = function(_, _, key)
      fullscreenCalls = fullscreenCalls + 1
      return key == "f"
    end

    local app = setmetatable({
      appEditState = {},
      wm = {
        getFocus = function() return nil end,
      },
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      quitConfirmModal = { isVisible = function() return false end },
      saveOptionsModal = {
        isVisible = function() return true end,
        handleKey = function() modalKeyCalls = modalKeyCalls + 1 end,
      },
      genericActionsModal = { isVisible = function() return false end, handleKey = function() return false end },
      settingsModal = { isVisible = function() return false end, handleKey = function() return false end },
      newWindowModal = { isVisible = function() return false end, handleKey = function() return false end },
      renameWindowModal = { isVisible = function() return false end, handleKey = function() return false end },
      splash = { isVisible = function() return false end, keypressed = function() return false end },
      setStatus = function(self, text)
        self.statusText = text
      end,
    }, AppCoreController)

    app:keypressed("2")
    app:keypressed("f")

    love.keyboard.isDown = oldIsDown

    expect(scalingCalls).toBeGreaterThan(0)
    expect(fullscreenCalls).toBeGreaterThan(0)
    expect(modalKeyCalls).toBe(0)
  end)

  it("routes mouse press/release to save options modal when visible", function()
    local pressed = 0
    local released = 0
    local moved = 0

    ResolutionController.getScaledMouse = function()
      return { x = 123, y = 77 }
    end

    local saveModal = {
      isVisible = function() return true end,
      mousepressed = function(_, x, y, b)
        pressed = pressed + 1
        expect(x).toBe(123)
        expect(y).toBe(77)
        expect(b).toBe(1)
      end,
      mousereleased = function(_, x, y, b)
        released = released + 1
        expect(x).toBe(123)
        expect(y).toBe(77)
        expect(b).toBe(1)
      end,
      mousemoved = function(_, x, y)
        moved = moved + 1
        expect(x).toBe(123)
        expect(y).toBe(77)
      end,
    }

    local app = setmetatable({
      quitConfirmModal = { isVisible = function() return false end },
      splash = { isVisible = function() return false end },
      saveOptionsModal = saveModal,
      genericActionsModal = { isVisible = function() return false end },
      settingsModal = { isVisible = function() return false end },
      newWindowModal = { isVisible = function() return false end },
      renameWindowModal = { isVisible = function() return false end },
      romPaletteAddressModal = { isVisible = function() return false end },
      ppuFrameSpriteLayerModeModal = { isVisible = function() return false end },
      ppuFrameAddSpriteModal = { isVisible = function() return false end },
      ppuFrameRangeModal = { isVisible = function() return false end },
      textFieldDemoModal = { isVisible = function() return false end },
      toastController = nil,
      taskbar = nil,
      hideAppContextMenus = function() end,
    }, AppCoreController)

    app:mousepressed(0, 0, 1)
    app:mousereleased(0, 0, 1)
    app:mousemoved(0, 0, 4, 2)

    expect(pressed).toBe(1)
    expect(released).toBe(1)
    expect(moved).toBe(1)
  end)

  it("can close save options modal from outside click via forwarded mouse press", function()
    local visible = true
    local saveModal = {
      isVisible = function() return visible end,
      mousepressed = function()
        visible = false
      end,
    }

    ResolutionController.getScaledMouse = function()
      return { x = 8, y = 9 }
    end

    local app = setmetatable({
      quitConfirmModal = { isVisible = function() return false end },
      splash = { isVisible = function() return false end },
      saveOptionsModal = saveModal,
      genericActionsModal = { isVisible = function() return false end },
      settingsModal = { isVisible = function() return false end },
      newWindowModal = { isVisible = function() return false end },
      renameWindowModal = { isVisible = function() return false end },
      romPaletteAddressModal = { isVisible = function() return false end },
      ppuFrameSpriteLayerModeModal = { isVisible = function() return false end },
      ppuFrameAddSpriteModal = { isVisible = function() return false end },
      ppuFrameRangeModal = { isVisible = function() return false end },
      textFieldDemoModal = { isVisible = function() return false end },
      toastController = nil,
      taskbar = nil,
      hideAppContextMenus = function() end,
    }, AppCoreController)

    expect(visible).toBe(true)
    app:mousepressed(0, 0, 1)
    expect(visible).toBe(false)
  end)

end)
