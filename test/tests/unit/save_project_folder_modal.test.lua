local OpenFileModal = require("ui.modals.open_file_modal")
local SaveProjectFolderModal = require("ui.modals.save_project_folder_modal")

local function makePopenStub(commandOutputs)
  return function(command)
    local lines = commandOutputs[command] or {}
    local index = 0
    return {
      lines = function()
        return function()
          index = index + 1
          return lines[index]
        end
      end,
      close = function()
        return true
      end,
    }
  end
end

describe("save_project_folder_modal.lua", function()
  it("lists folders only and confirms the current directory with a project name", function()
    local originalPopen = io.popen
    io.popen = makePopenStub({
      ["ls -1Ap '/tmp/work' 2>/dev/null"] = {
        "folderA/",
        "folderB/",
        "alpha.lua",
        "game.nes",
      },
    })

    local pickedDir = nil
    local pickedName = nil
    local modal = SaveProjectFolderModal.new()
    modal:show({
      initialDir = "/tmp/work",
      initialProjectName = "my_gallery",
      onOpen = function(path, entry)
        pickedDir = path
        pickedName = entry and entry.projectName
      end,
    })

    local entries = modal:getEntries()
    expect(#entries).toBe(2)
    expect(entries[1].isDir).toBe(true)
    expect(entries[1].name).toBe("folderA")
    expect(entries[2].name).toBe("folderB")
    expect(modal:getProjectName()).toBe("my_gallery")

    expect(modal:_confirmCurrentDirectory()).toBe(true)
    expect(pickedDir).toBe("/tmp/work")
    expect(pickedName).toBe("my_gallery")
    expect(modal:isVisible()).toBe(false)

    io.popen = originalPopen
  end)

  it("refuses confirm when the project name is empty", function()
    local originalPopen = io.popen
    io.popen = makePopenStub({
      ["ls -1Ap '/tmp/work' 2>/dev/null"] = {
        "folderA/",
      },
    })

    local called = false
    local modal = SaveProjectFolderModal.new()
    modal:show({
      initialDir = "/tmp/work",
      initialProjectName = "x",
      onOpen = function()
        called = true
      end,
    })
    modal.nameField:setText("   ")
    expect(modal:_confirmCurrentDirectory()).toBe(false)
    expect(called).toBe(false)
    expect(modal:isVisible()).toBe(true)

    io.popen = originalPopen
  end)

  it("exposes saveProjectFolder preset on OpenFileModal", function()
    expect(OpenFileModal.presets.saveProjectFolder).toBeTruthy()
    expect(OpenFileModal.presets.saveProjectFolder.directoriesOnly).toBe(true)
  end)

  it("does not append the first textinput after show (Save Options digit leak)", function()
    local originalPopen = io.popen
    io.popen = makePopenStub({
      ["ls -1Ap '/tmp/work' 2>/dev/null"] = {
        "folderA/",
      },
    })

    local modal = SaveProjectFolderModal.new()
    modal:show({
      initialDir = "/tmp/work",
      initialProjectName = "test_01",
    })
    expect(modal:getProjectName()).toBe("test_01")
    expect(modal:textinput("1")).toBe(true)
    expect(modal:getProjectName()).toBe("test_01")
    expect(modal:textinput("a")).toBe(true)
    expect(modal:getProjectName()).toBe("test_01a")

    io.popen = originalPopen
  end)

  it("clears textinput suppression when the modal is clicked", function()
    local originalPopen = io.popen
    io.popen = makePopenStub({
      ["ls -1Ap '/tmp/work' 2>/dev/null"] = {
        "folderA/",
      },
    })

    local modal = SaveProjectFolderModal.new()
    modal:show({
      initialDir = "/tmp/work",
      initialProjectName = "test_01",
    })
    expect(modal._suppressNextTextInput).toBe(true)
    local contains = modal._containsBox
    modal._containsBox = function() return true end
    modal:mousepressed(10, 10, 1)
    modal._containsBox = contains
    expect(modal._suppressNextTextInput).toBe(false)

    io.popen = originalPopen
  end)

  it("accepts typed characters after textinput suppression is cleared", function()
    local originalPopen = io.popen
    io.popen = makePopenStub({
      ["ls -1Ap '/tmp/work' 2>/dev/null"] = {
        "folderA/",
      },
    })

    local modal = SaveProjectFolderModal.new()
    modal:show({
      initialDir = "/tmp/work",
      initialProjectName = "test_01",
    })
    -- Same as first paint / mouse interaction clearing the Save Options digit gate.
    modal._suppressNextTextInput = false
    expect(modal:textinput("z")).toBe(true)
    expect(modal:getProjectName()).toBe("test_01z")

    io.popen = originalPopen
  end)
end)
