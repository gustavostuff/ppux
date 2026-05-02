local SaveController = require("controllers.rom.save_controller")
local RomProjectController = require("controllers.rom.rom_project_controller")
local ChrBackingController = require("controllers.rom.chr_backing_controller")

local RomSave = require("romsave")
local GameArtController = require("controllers.game_art.game_art_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local chr = require("chr")
local PaletteWindow = require("user_interface.windows_system.palette_window")
local RomWindow = require("user_interface.windows_system.rom_window")
local StaticArtWindow = require("user_interface.windows_system.static_art_window")
local AnimationWindow = require("user_interface.windows_system.animation_window")

describe("chr backing integration", function()
  local originals

  beforeEach(function()
    originals = {
      saveRawROM = RomSave.saveRawROM,
      saveEditedROM = RomSave.saveEditedROM,
      ioOpen = io.open,
      love = rawget(_G, "love"),
      parseINES = chr.parseINES,
      loadProjectLua = GameArtController.loadProjectLua,
      getLayout = GameArtController.getLayout,
      ensureBankTiles = BankViewController.ensureBankTiles,
      rebuildBankWindowItems = BankViewController.rebuildBankWindowItems,
      reindexAllBanks = ChrDuplicateSync.reindexAllBanks,
      buildSyncGroups = ChrDuplicateSync.buildSyncGroups,
      clearSyncGroups = ChrDuplicateSync.clearSyncGroups,
      paletteNew = PaletteWindow.new,
      romWindowNew = RomWindow.new,
      staticArtWindowNew = StaticArtWindow.new,
      animationWindowNew = AnimationWindow.new,
      toolbarModule = package.loaded["controllers.toolbar_controller"],
      toolbarModuleNewPath = package.loaded["controllers.window.toolbar_controller"],
      buildWindowsFromLayout = GameArtController.buildWindowsFromLayout,
      normalizeRomPatches = GameArtController.normalizeRomPatches,
      applyEdits = GameArtController.applyEdits,
      decompressEdits = GameArtController.decompressEdits,
      newEdits = GameArtController.newEdits,
    }
  end)

  afterEach(function()
    RomSave.saveRawROM = originals.saveRawROM
    RomSave.saveEditedROM = originals.saveEditedROM
    io.open = originals.ioOpen
    _G.love = originals.love
    chr.parseINES = originals.parseINES
    GameArtController.loadProjectLua = originals.loadProjectLua
    GameArtController.getLayout = originals.getLayout
    BankViewController.ensureBankTiles = originals.ensureBankTiles
    BankViewController.rebuildBankWindowItems = originals.rebuildBankWindowItems
    ChrDuplicateSync.reindexAllBanks = originals.reindexAllBanks
    ChrDuplicateSync.buildSyncGroups = originals.buildSyncGroups
    ChrDuplicateSync.clearSyncGroups = originals.clearSyncGroups
    PaletteWindow.new = originals.paletteNew
    RomWindow.new = originals.romWindowNew
    StaticArtWindow.new = originals.staticArtWindowNew
    AnimationWindow.new = originals.animationWindowNew
    package.loaded["controllers.toolbar_controller"] = originals.toolbarModule
    package.loaded["controllers.window.toolbar_controller"] = originals.toolbarModuleNewPath
    GameArtController.buildWindowsFromLayout = originals.buildWindowsFromLayout
    GameArtController.normalizeRomPatches = originals.normalizeRomPatches
    GameArtController.applyEdits = originals.applyEdits
    GameArtController.decompressEdits = originals.decompressEdits
    GameArtController.newEdits = originals.newEdits
  end)

  it("save_controller chooses saveRawROM when chr backing mode is rom_raw", function()
    local calls = { raw = 0, edited = 0 }

    RomSave.saveRawROM = function(path, romRaw)
      calls.raw = calls.raw + 1
      calls.rawPath = path
      calls.rawBytes = romRaw
      return true, path .. ".patched"
    end
    RomSave.saveEditedROM = function()
      calls.edited = calls.edited + 1
      return true, "should-not-be-called"
    end
    local header = string.rep("\170", 16)
    local body = string.rep("\0", 32)
    local state = {
      romRaw = header .. body,
      romOriginalPath = "/tmp/fake_rom.nes",
      chrBanksBytes = {},
    }
    local _, err = ChrBackingController.configureFromParsedINES(state, { chr = {} })
    expect(err).toBeNil()
    state.chrBanksBytes[1][1] = 0x44

    local app = {
      wm = {
        getWindows = function() return {} end,
        getWindowsOfKind = function() return {} end,
      },
      appEditState = state,
      setStatus = function(self, text)
        self.statusText = text
      end,
    }

    local ok = SaveController.saveEdited(app)
    expect(ok).toBeTruthy()
    expect(calls.raw).toBe(1)
    expect(calls.edited).toBe(0)
    expect(calls.rawPath).toBe("/tmp/fake_rom.nes")
    expect(type(calls.rawBytes)).toBe("string")
    expect(string.byte(calls.rawBytes, 17)).toBe(0x44)
  end)

  it("rom_project_controller default fallback creates ROM window from chr backing mode", function()
    local romBytes = string.rep("\0", 32)
    local fakeFileContent = string.char(
      0x4E, 0x45, 0x53, 0x1A, -- NES<EOF>
      0x01, 0x00, 0x00, 0x00, -- PRG=1, CHR=0 => CHR-RAM
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ) .. romBytes

    local calls = { romWindow = 0, palette = 0, staticArt = 0, animation = 0, statuses = {} }

    _G.love = {
      data = {
        hash = function() return "digest" end,
        encode = function() return "deadbeef" end,
      }
    }

    io.open = function(path, mode)
      return {
        read = function(self, kind)
          if kind == "*a" or kind == "*all" then
            return fakeFileContent
          end
          return fakeFileContent
        end,
        close = function() return true end,
      }
    end

    chr.parseINES = function(raw)
      expect(raw).toBe(fakeFileContent)
      return {
        meta = { prgBanks = 1, chrBanks = 0 },
        chr = {},
      }
    end

    GameArtController.loadProjectLua = function()
      return nil, "missing project"
    end
    GameArtController.getLayout = function()
      return nil
    end

    BankViewController.ensureBankTiles = function() end
    BankViewController.rebuildBankWindowItems = function() end
    ChrDuplicateSync.reindexAllBanks = function() end
    ChrDuplicateSync.buildSyncGroups = function() end
    ChrDuplicateSync.clearSyncGroups = function() end

    PaletteWindow.new = function(x, y, zoom, paletteName, rows, cols, data)
      calls.palette = calls.palette + 1
      return {
        kind = "palette",
        isPalette = true,
        title = (data and data.title) or "Global palette",
        layers = {},
      }
    end

    RomWindow.new = function(x, y, cellW, cellH, cols, rows, zoom, data)
      calls.romWindow = calls.romWindow + 1
      return {
        kind = "chr",
        isRomWindow = true,
        title = data and data.title or "ROM Banks",
        layers = { { opacity = 1.0, name = "Bank", items = {} } },
      }
    end

    StaticArtWindow.new = function(x, y, cellW, cellH, cols, rows, zoom, data)
      calls.staticArt = calls.staticArt + 1
      return {
        kind = "static_art",
        title = data and data.title or "Static Art (tiles)",
        layers = {},
        addLayer = function(self, layer)
          self.layers[#self.layers + 1] = layer
        end,
      }
    end

    AnimationWindow.new = function(x, y, cellW, cellH, cols, rows, zoom, data)
      calls.animation = calls.animation + 1
      return {
        kind = "animation",
        title = data and data.title or "Animation (sprites)",
        layers = {},
        addLayer = function(self, layer)
          self.layers[#self.layers + 1] = layer
        end,
        updateLayerOpacities = function() end,
      }
    end

    package.loaded["controllers.toolbar_controller"] = {
      createToolbarsForWindows = function() end,
    }

    local app = {
      syncDuplicateTiles = false,
      appEditState = {
        tilesPool = {},
        romPatches = nil,
      },
      clearUnsavedChanges = function() end,
      setStatus = function(self, text)
        calls.statuses[#calls.statuses + 1] = text
        self.statusText = text
      end,
    }

    local ok = RomProjectController.loadROM(app, "/tmp/fake_rom.nes")
    expect(ok).toBeTruthy()
    expect(calls.romWindow).toBe(1)
    expect(calls.palette).toBe(1)
    expect(calls.staticArt).toBe(1)
    expect(calls.animation).toBe(1)
    expect(app.winBank).toBeTruthy()
    expect(app.winBank.isRomWindow).toBeTruthy()
    expect(app.winBank.title).toBe("ROM Banks")
    expect(app.appEditState.chrBacking).toBeTruthy()
    expect(app.appEditState.chrBacking.mode).toBe("rom_raw")
    expect(app.appEditState.romTileViewMode).toBeTruthy() -- compatibility field still synced
    expect(app.statusText).toBe("Loaded default layout")
    expect(app.wm.taskbar).toBe(app.taskbar)
  end)

  it("rom_project_controller skips eager duplicate indexing when sync is disabled", function()
    local fakeFileContent = string.char(
      0x4E, 0x45, 0x53, 0x1A,
      0x01, 0x01, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ) .. string.rep("\0", 16 + 8192)

    local calls = {
      reindexAllBanks = 0,
      buildSyncGroups = 0,
      clearSyncGroups = 0,
    }

    _G.love = {
      data = {
        hash = function() return "digest" end,
        encode = function() return "deadbeef" end,
      }
    }

    io.open = function()
      return {
        read = function(_, kind)
          if kind == "*a" or kind == "*all" then
            return fakeFileContent
          end
          return fakeFileContent
        end,
        close = function() return true end,
      }
    end

    chr.parseINES = function()
      return {
        meta = { prgBanks = 1, chrBanks = 1 },
        chr = { string.rep("\0", 8192) },
      }
    end

    GameArtController.loadProjectLua = function()
      return nil, "missing project"
    end
    GameArtController.getLayout = function()
      return nil
    end

    BankViewController.ensureBankTiles = function() end
    BankViewController.rebuildBankWindowItems = function() end
    ChrDuplicateSync.reindexAllBanks = function()
      calls.reindexAllBanks = calls.reindexAllBanks + 1
    end
    ChrDuplicateSync.buildSyncGroups = function()
      calls.buildSyncGroups = calls.buildSyncGroups + 1
    end
    ChrDuplicateSync.clearSyncGroups = function()
      calls.clearSyncGroups = calls.clearSyncGroups + 1
    end

    PaletteWindow.new = function(x, y, zoom, paletteName, rows, cols, data)
      return {
        kind = "palette",
        isPalette = true,
        title = (data and data.title) or "Global palette",
        layers = {},
      }
    end

    RomWindow.new = function(x, y, cellW, cellH, cols, rows, zoom, data)
      return {
        kind = "chr",
        isRomWindow = true,
        title = data and data.title or "ROM Banks",
        layers = { { opacity = 1.0, name = "Bank", items = {} } },
      }
    end

    package.loaded["controllers.toolbar_controller"] = {
      createToolbarsForWindows = function() end,
    }

    local app = {
      syncDuplicateTiles = false,
      appEditState = {
        tilesPool = {},
        romPatches = nil,
      },
      clearUnsavedChanges = function() end,
      setStatus = function(self, text)
        self.statusText = text
      end,
    }

    local ok = RomProjectController.loadROM(app, "/tmp/fake_rom.nes")
    expect(ok).toBeTruthy()
    expect(calls.reindexAllBanks).toBe(0)
    expect(calls.buildSyncGroups).toBe(0)
    expect(calls.clearSyncGroups).toBeGreaterThan(0)
  end)

  it("rom_project_controller rebinds taskbar when project load recreates WM", function()
    local fakeFileContent = string.char(
      0x4E, 0x45, 0x53, 0x1A,
      0x01, 0x01, 0x00, 0x00, -- CHR=1 so normal chr_rom path is fine
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ) .. string.rep("\0", 16 + 8192)

    _G.love = {
      data = {
        hash = function() return "digest" end,
        encode = function() return "deadbeef" end,
      }
    }

    io.open = function()
      return {
        read = function(_, kind)
          if kind == "*a" or kind == "*all" then
            return fakeFileContent
          end
          return fakeFileContent
        end,
        close = function() return true end,
      }
    end

    chr.parseINES = function()
      return {
        meta = { prgBanks = 1, chrBanks = 1 },
        chr = { string.rep("\0", 8192) },
      }
    end

    GameArtController.loadProjectLua = function()
      return {
        kind = "project",
        windows = {},
      }
    end
    GameArtController.normalizeRomPatches = function(v) return v end
    GameArtController.buildWindowsFromLayout = function(project, opts)
      return {
        bankWindow = nil,
        currentBank = 1,
      }
    end
    GameArtController.applyEdits = function() end
    GameArtController.decompressEdits = function(edits) return edits end
    GameArtController.newEdits = function() return { banks = {} } end

    BankViewController.ensureBankTiles = function() end
    BankViewController.rebuildBankWindowItems = function() end
    ChrDuplicateSync.reindexAllBanks = function() end
    ChrDuplicateSync.buildSyncGroups = function() end
    ChrDuplicateSync.clearSyncGroups = function() end

    package.loaded["controllers.window.toolbar_controller"] = {
      createToolbarsForWindows = function() end,
    }
    package.loaded["controllers.toolbar_controller"] = package.loaded["controllers.window.toolbar_controller"]

    local resetCalls = 0
    local toolbarStub = {
      resetWindowButtons = function()
        resetCalls = resetCalls + 1
      end,
    }
    local app = {
      taskbar = toolbarStub,
      syncDuplicateTiles = false,
      appEditState = {
        tilesPool = {},
        romPatches = nil,
      },
      undoRedo = {
        clear = function() end,
      },
      clearUnsavedChanges = function() end,
      setStatus = function(self, text) self.statusText = text end,
    }

    local ok = RomProjectController.loadROM(app, "/tmp/fake_rom.nes")
    expect(ok).toBeTruthy()
    expect(app.wm).toBeTruthy()
    expect(app.wm.taskbar).toBe(toolbarStub)
    expect(resetCalls).toBe(1)
  end)

  it("rom_project_controller clears prior project runtime state before opening another project", function()
    local romPath = "/tmp/project_b.nes"
    local projectPath = "/tmp/project_b.lua"
    local encodedPath = "/tmp/project_b.ppux"
    local fakeFileContent = string.char(
      0x4E, 0x45, 0x53, 0x1A,
      0x01, 0x01, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ) .. string.rep("\0", 16 + 8192)

    local function modalStub()
      return {
        hideCalls = 0,
        hide = function(self)
          self.hideCalls = self.hideCalls + 1
        end,
      }
    end

    _G.love = {
      data = {
        hash = function() return "digest" end,
        encode = function() return "deadbeef" end,
      }
    }

    io.open = function(path)
      if path == romPath then
        return {
          read = function(_, kind)
            if kind == "*a" or kind == "*all" then
              return fakeFileContent
            end
            return fakeFileContent
          end,
          close = function() return true end,
        }
      end
      if path == projectPath then
        return {
          read = function() return "return {}" end,
          close = function() return true end,
        }
      end
      return nil, "missing"
    end

    chr.parseINES = function(raw)
      expect(raw).toBe(fakeFileContent)
      return {
        meta = { prgBanks = 1, chrBanks = 1 },
        chr = { string.rep("\0", 8192) },
      }
    end

    GameArtController.loadProjectLua = function(path)
      expect(path).toBe(projectPath)
      return {
        kind = "project",
        windows = {},
        currentBank = 1,
        currentColor = 3,
        syncDuplicateTiles = true,
        edits = {
          banks = {},
        },
      }
    end
    GameArtController.normalizeRomPatches = function(v) return v end
    GameArtController.buildWindowsFromLayout = function()
      return {
        bankWindow = nil,
        currentBank = 1,
      }
    end
    GameArtController.applyEdits = function() end
    GameArtController.decompressEdits = function(edits) return edits end
    GameArtController.newEdits = function() return { banks = {} } end

    BankViewController.ensureBankTiles = function() end
    BankViewController.rebuildBankWindowItems = function() end
    ChrDuplicateSync.reindexAllBanks = function() end
    ChrDuplicateSync.buildSyncGroups = function() end
    ChrDuplicateSync.clearSyncGroups = function() end

    package.loaded["controllers.window.toolbar_controller"] = {
      createToolbarsForWindows = function() end,
    }
    package.loaded["controllers.toolbar_controller"] = package.loaded["controllers.window.toolbar_controller"]

    local tooltipController = {
      visible = true,
      candidateText = "old tooltip",
      candidateKey = "old",
      candidateImmediate = true,
      lastMouseX = 11,
      lastMouseY = 12,
      stillSeconds = 3,
    }
    local toastController = {
      toasts = { { id = 1 } },
      pressedToast = { id = 1 },
      layoutDirty = false,
    }
    local taskbarStub = {
      resetCalls = 0,
      resetWindowButtons = function(self)
        self.resetCalls = self.resetCalls + 1
      end,
    }
    local app = {
      taskbar = taskbarStub,
      wm = { old = true },
      winBank = { old = true },
      edits = { old = true },
      projectPath = "/tmp/project_a.lua",
      encodedProjectPath = "/tmp/project_a.ppux",
      currentBank = 9,
      currentColor = 1,
      syncDuplicateTiles = false,
      undoRedo = {
        clearCalls = 0,
        clear = function(self)
          self.clearCalls = self.clearCalls + 1
        end,
      },
      tooltipController = tooltipController,
      toastController = toastController,
      genericActionsModal = modalStub(),
      quitConfirmModal = modalStub(),
      saveOptionsModal = modalStub(),
      settingsModal = modalStub(),
      newWindowModal = modalStub(),
      renameWindowModal = modalStub(),
      _windowSnapshot = { stale = true },
      _windowSnapshotTimer = 42,
      clearUnsavedCalls = 0,
      clearUnsavedChanges = function(self)
        self.clearUnsavedCalls = self.clearUnsavedCalls + 1
        self.unsavedChanges = false
        self.unsavedEvents = {}
      end,
      setStatus = function(self, text)
        self.statusText = text
      end,
      appEditState = {
        romRaw = "old-rom",
        romOriginalPath = "/tmp/project_a.nes",
        meta = { stale = true },
        chrBanksBytes = { { 1, 2, 3 } },
        originalChrBanksBytes = { { 4, 5, 6 } },
        currentBank = 9,
        romPatches = { stale = true },
        romSha1 = "oldsha",
        tilesPool = { stale = true },
        chrBacking = { mode = "rom_raw" },
        romTileViewMode = true,
        tileSignatureIndex = { stale = true },
        tileSignatureByTile = { stale = true },
        tileSignatureIndexReady = true,
      },
    }

    local ok = RomProjectController.loadROM(app, romPath)

    expect(ok).toBeTruthy()
    expect(app.wm).toBeTruthy()
    expect(app.wm.old).toBeNil()
    expect(app.wm.taskbar).toBe(taskbarStub)
    expect(taskbarStub.resetCalls).toBe(1)
    expect(app.undoRedo.clearCalls).toBe(1)
    expect(app.clearUnsavedCalls).toBe(1)

    expect(tooltipController.visible).toBe(false)
    expect(tooltipController.candidateText).toBeNil()
    expect(tooltipController.candidateKey).toBeNil()
    expect(tooltipController.candidateImmediate).toBe(false)
    expect(tooltipController.lastMouseX).toBeNil()
    expect(tooltipController.lastMouseY).toBeNil()
    expect(tooltipController.stillSeconds).toBe(0)

    expect(#toastController.toasts).toBe(0)
    expect(toastController.pressedToast).toBeNil()
    expect(toastController.layoutDirty).toBe(true)

    expect(app.genericActionsModal.hideCalls).toBe(1)
    expect(app.quitConfirmModal.hideCalls).toBe(1)
    expect(app.saveOptionsModal.hideCalls).toBe(1)
    expect(app.settingsModal.hideCalls).toBe(1)
    expect(app.newWindowModal.hideCalls).toBe(1)
    expect(app.renameWindowModal.hideCalls).toBe(1)

    expect(app._windowSnapshot).toBeNil()
    expect(app._windowSnapshotTimer).toBe(0)
    expect(app.winBank).toBeNil()
    expect(app.edits).toEqual({ banks = {} })
    expect(app.projectPath).toBe(projectPath)
    expect(app.encodedProjectPath).toBe(encodedPath)
    expect(app.currentBank).toBe(1)
    expect(app.currentColor).toBe(3)
    expect(app.syncDuplicateTiles).toBe(true)

    expect(app.appEditState.romOriginalPath).toBe(romPath)
    expect(app.appEditState.romRaw).toBe(fakeFileContent)
    expect(app.appEditState.meta.prgBanks).toBe(1)
    expect(app.appEditState.meta.chrBanks).toBe(1)
    expect(app.appEditState.currentBank).toBe(1)
    expect(app.appEditState.romSha1).toBeTruthy()
    expect(app.appEditState.tilesPool).toEqual({})
    expect(app.appEditState.romPatches).toBeNil()
    expect(app.appEditState.tileSignatureIndex).toBeNil()
    expect(app.appEditState.tileSignatureByTile).toBeNil()
    expect(app.appEditState.tileSignatureIndexReady).toBe(false)
    expect(app.appEditState.romTileViewMode).toBe(false)
    expect(app.appEditState.chrBacking).toBeTruthy()
    expect(app.appEditState.chrBacking.mode).toBe("chr_rom")
  end)
end)
