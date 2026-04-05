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

  it("blocks save-both when no ROM is loaded", function()
    local toastCalls = {}
    local clearCount = 0
    local app = setmetatable({
      appEditState = {},
      saveProject = function(self, opts)
        self.projectOpts = opts
        self.statusText = "Saved project: /tmp/test_project.lua"
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

    expect(ok).toBe(false)
    expect(app.projectOpts).toBeNil()
    expect(clearCount).toBe(0)
    expect(#toastCalls).toBe(1)
    expect(toastCalls[1].kind).toBe("error")
    expect(toastCalls[1].text).toBe("Open a ROM before saving.")
  end)

  it("does not open save options from Ctrl+S when no ROM is loaded", function()
    local status
    local showCount = 0
    local oldIsDown = love.keyboard.isDown

    love.keyboard.isDown = function(key)
      return key == "lctrl" or key == "rctrl"
    end

    local hiddenModal = {
      isVisible = function() return false end,
      handleKey = function() return false end,
      show = function() showCount = showCount + 1 end,
    }

    local app = setmetatable({
      appEditState = {},
      quitConfirmModal = { isVisible = function() return false end },
      saveOptionsModal = hiddenModal,
      genericActionsModal = { isVisible = function() return false end, handleKey = function() return false end },
      settingsModal = { isVisible = function() return false end, handleKey = function() return false end },
      newWindowModal = { isVisible = function() return false end, handleKey = function() return false end },
      splash = { isVisible = function() return false end, keypressed = function() return false end },
      setStatus = function(self, text)
        status = text
        self.statusText = text
      end,
    }, AppCoreController)

    app:keypressed("s")

    love.keyboard.isDown = oldIsDown

    expect(showCount).toBe(0)
    expect(status).toBe("Open a ROM before saving.")
  end)

  it("does not open new window modal from Ctrl+N when no ROM is loaded", function()
    local status
    local showCount = 0
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
      newWindowModal = {
        isVisible = function() return false end,
        handleKey = function() return false end,
        show = function() showCount = showCount + 1 end,
      },
      splash = { isVisible = function() return false end, keypressed = function() return false end },
      setStatus = function(self, text)
        status = text
        self.statusText = text
      end,
    }, AppCoreController)

    app:keypressed("n")

    love.keyboard.isDown = oldIsDown

    expect(showCount).toBe(0)
    expect(status).toBe("Open a ROM before creating windows.")
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
