local RomProjectController = require("controllers.rom.rom_project_controller")

describe("rom_project_controller.lua - project file loading", function()
  local originalLoadProjectFile
  local originalLoadROM
  local tempPaths

  beforeEach(function()
    originalLoadProjectFile = RomProjectController.loadProjectFile
    originalLoadROM = RomProjectController.loadROM
    tempPaths = {}
  end)

  afterEach(function()
    RomProjectController.loadProjectFile = originalLoadProjectFile
    RomProjectController.loadROM = originalLoadROM
    for _, path in ipairs(tempPaths) do
      os.remove(path)
    end
  end)

  local function touchTempFile(path, bytes)
    local f = assert(io.open(path, "wb"))
    assert(f:write(bytes or "test"))
    f:close()
    tempPaths[#tempPaths + 1] = path
  end

  it("delegates .lua project paths to loadProjectFile", function()
    local calledWith = nil
    RomProjectController.loadProjectFile = function(app, fileOrPath)
      calledWith = { app = app, fileOrPath = fileOrPath }
      return true
    end

    local app = {}
    local ok = RomProjectController.loadROM(app, "/tmp/test.lua")

    expect(ok).toBe(true)
    expect(calledWith).toBeTruthy()
    expect(calledWith.app).toBe(app)
    expect(calledWith.fileOrPath).toBe("/tmp/test.lua")
  end)

  it("delegates .ppux project paths to loadProjectFile", function()
    local calledWith = nil
    RomProjectController.loadProjectFile = function(app, fileOrPath)
      calledWith = { app = app, fileOrPath = fileOrPath }
      return true
    end

    local app = {}
    local ok = RomProjectController.loadROM(app, "/tmp/test.ppux")

    expect(ok).toBe(true)
    expect(calledWith).toBeTruthy()
    expect(calledWith.app).toBe(app)
    expect(calledWith.fileOrPath).toBe("/tmp/test.ppux")
  end)

  it("includes de-edited sibling project paths as ROM drop candidates", function()
    local candidates = RomProjectController._projectPathCandidatesForRom("/tmp/test_rom_edited.nes", "lua")

    expect(candidates).toEqual({
      "/tmp/test_rom.lua",
    })
  end)

  it("recognizes edited ROM drop paths", function()
    expect(RomProjectController._isEditedRomPath("/tmp/test_rom_edited.nes")).toBe(true)
    expect(RomProjectController._isEditedRomPath("/tmp/test_rom.nes")).toBe(false)
    expect(RomProjectController._isEditedRomPath("/tmp/test_rom_edited.lua")).toBe(false)
  end)

  it("normalizes recent project paths to their base stem", function()
    expect(RomProjectController._normalizeRecentProjectBasePath("/tmp/foo.nes")).toBe("/tmp/foo")
    expect(RomProjectController._normalizeRecentProjectBasePath("/tmp/foo.lua")).toBe("/tmp/foo")
    expect(RomProjectController._normalizeRecentProjectBasePath("/tmp/foo.ppux")).toBe("/tmp/foo")
    expect(RomProjectController._normalizeRecentProjectBasePath("/tmp/foo_edited.nes")).toBe("/tmp/foo")
  end)

  it("resolves recent project paths by preferring the base rom", function()
    local romPath = "/tmp/recent_pref_test.nes"
    local luaPath = "/tmp/recent_pref_test.lua"
    touchTempFile(romPath, "nes")
    touchTempFile(luaPath, "return {}")

    local foundPath = RomProjectController._resolveRecentProjectLoadPath("/tmp/recent_pref_test")
    expect(foundPath).toBe(romPath)
  end)

  it("finds the sibling lua project when an edited rom is dropped", function()
    local romPath = "/tmp/ppux_drop_test_edited.nes"
    local projectPath = "/tmp/ppux_drop_test.lua"
    touchTempFile(projectPath, "return {}")

    local app = {
      projectPath = "/tmp/ppux_drop_test.lua",
      encodedProjectPath = "/tmp/ppux_drop_test.ppux",
      appEditState = {
        romOriginalPath = romPath,
      },
    }

    local foundPath, foundFormat = RomProjectController._chooseAdjacentProjectPath(app)

    expect(foundPath).toBe(projectPath)
    expect(foundFormat).toBe("lua")
  end)

  it("falls back to the sibling ppux project when edited-rom lua project is absent", function()
    local romPath = "/tmp/ppux_drop_test2_edited.nes"
    local projectPath = "/tmp/ppux_drop_test2.ppux"
    touchTempFile(projectPath, "ppux-bytes")

    local app = {
      projectPath = "/tmp/ppux_drop_test2.lua",
      encodedProjectPath = "/tmp/ppux_drop_test2.ppux",
      appEditState = {
        romOriginalPath = romPath,
      },
    }

    local foundPath, foundFormat = RomProjectController._chooseAdjacentProjectPath(app)

    expect(foundPath).toBe(projectPath)
    expect(foundFormat).toBe("ppux")
  end)

  it("prompts before opening another project when there are unsaved changes", function()
    local shown = nil
    local loadCalls = 0

    RomProjectController.loadROM = function()
      loadCalls = loadCalls + 1
      return true
    end

    local app = {
      hasUnsavedChanges = function() return true end,
      genericActionsModal = {
        show = function(_, title, options)
          shown = {
            title = title,
            options = options,
          }
        end,
      },
    }

    local ok = RomProjectController.requestLoad(app, "/tmp/project_b.nes")

    expect(ok).toBe(true)
    expect(loadCalls).toBe(0)
    expect(shown).toBeTruthy()
    expect(shown.title).toBe("Unsaved Changes")
    expect(#shown.options).toBe(3)
    expect(shown.options[1].text).toBe("Save current and open")
    expect(shown.options[2].text).toBe("Open without saving")
    expect(shown.options[3].text).toBe("Cancel")

    shown.options[2].callback()
    expect(loadCalls).toBe(1)
  end)

  it("treats DB layouts with no windows as unusable", function()
    expect(RomProjectController._dbLayoutHasWindows(nil)).toBe(false)
    expect(RomProjectController._dbLayoutHasWindows({})).toBe(false)
    expect(RomProjectController._dbLayoutHasWindows({ windows = {} })).toBe(false)
    expect(RomProjectController._dbLayoutHasWindows({ windows = { { kind = "chr" } } })).toBe(true)
  end)
end)
