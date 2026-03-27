local RomProjectController = require("controllers.rom.rom_project_controller")
local GameArtController = require("controllers.game_art.game_art_controller")

describe("rom_project_controller.lua - save path normalization", function()
  local originals

  beforeEach(function()
    originals = {
      snapshotProject = GameArtController.snapshotProject,
      saveProjectLua = GameArtController.saveProjectLua,
      saveProjectPpux = GameArtController.saveProjectPpux,
      newEdits = GameArtController.newEdits,
    }
  end)

  afterEach(function()
    GameArtController.snapshotProject = originals.snapshotProject
    GameArtController.saveProjectLua = originals.saveProjectLua
    GameArtController.saveProjectPpux = originals.saveProjectPpux
    GameArtController.newEdits = originals.newEdits
  end)

  it("forces distinct lua and ppux save targets when app state paths collide", function()
    local savedLuaPath
    local savedPpuxPath

    GameArtController.snapshotProject = function()
      return { windows = {}, currentBank = 1 }
    end
    GameArtController.newEdits = function()
      return { banks = {} }
    end
    GameArtController.saveProjectLua = function(path)
      savedLuaPath = path
      return true
    end
    GameArtController.saveProjectPpux = function(path)
      savedPpuxPath = path
      return true
    end

    local app = {
      appEditState = {
        romSha1 = "abc123",
        romOriginalPath = "/tmp/test_rom.nes",
        currentBank = 1,
      },
      projectPath = "/tmp/test_rom.ppux",
      encodedProjectPath = "/tmp/test_rom.ppux",
      wm = {},
      winBank = nil,
      setStatus = function(self, text)
        self.statusText = text
      end,
    }

    expect(RomProjectController.saveProject(app)).toBe(true)
    expect(RomProjectController.saveEncodedProject(app)).toBe(true)

    expect(savedLuaPath).toBe("/tmp/test_rom.lua")
    expect(savedPpuxPath).toBe("/tmp/test_rom.ppux")
    expect(app.projectPath).toBe("/tmp/test_rom.lua")
    expect(app.encodedProjectPath).toBe("/tmp/test_rom.ppux")
  end)
end)
