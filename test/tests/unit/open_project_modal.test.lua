local OpenProjectModal = require("user_interface.modals.open_project_modal")

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

describe("open_project_modal.lua", function()
  it("filters to folders plus lua/ppux files", function()
    local originalPopen = io.popen
    io.popen = makePopenStub({
      ["ls -1Ap '/tmp/work' 2>/dev/null"] = {
        "folderA/",
        "folderB/",
        "alpha.lua",
        "beta.ppux",
        "ignore.txt",
        ".git/",
      },
    })

    local modal = OpenProjectModal.new()
    modal:show({
      initialDir = "/tmp/work",
    })

    local entries = modal:getEntries()
    expect(#entries).toBe(5)
    expect(entries[1].isDir).toBe(true)
    expect(entries[1].name).toBe(".git")
    expect(entries[2].name).toBe("folderA")
    expect(entries[3].name).toBe("folderB")
    expect(entries[4].name).toBe("alpha.lua")
    expect(entries[5].name).toBe("beta.ppux")

    io.popen = originalPopen
  end)

  it("supports folder navigation, back history, fixed slots, and file open callback", function()
    local originalPopen = io.popen
    io.popen = makePopenStub({
      ["ls -1Ap '/tmp/work' 2>/dev/null"] = {
        "child/",
        "proj01.lua",
        "proj02.lua",
        "proj03.lua",
        "proj04.lua",
        "proj05.lua",
        "proj06.lua",
        "proj07.lua",
        "proj08.lua",
        "proj09.lua",
      },
      ["ls -1Ap '/tmp/work/child' 2>/dev/null"] = {
        "inside.ppux",
      },
    })

    local opened = nil
    local modal = OpenProjectModal.new()
    modal:show({
      initialDir = "/tmp/work",
      onOpen = function(path)
        opened = path
        return true
      end,
    })

    local firstVisible = modal:getVisibleEntries()
    expect(#firstVisible).toBe(8)
    expect(firstVisible[1].name).toBe("child")
    expect(firstVisible[8].name).toBe("proj07.lua")

    modal:wheelmoved(0, -1)
    local afterScroll = modal:getVisibleEntries()
    expect(afterScroll[1].name).toBe("proj01.lua")
    expect(afterScroll[8].name).toBe("proj08.lua")

    modal:_setScrollOffset(0)
    expect(modal:_activateVisibleSlot(1)).toBe(true)
    expect(modal:getCurrentDir()).toBe("/tmp/work/child")

    expect(modal:_goBack()).toBe(true)
    expect(modal:getCurrentDir()).toBe("/tmp/work")

    modal:_setScrollOffset(1)
    expect(modal:_activateVisibleSlot(1)).toBe(true)
    expect(opened).toBe("/tmp/work/proj01.lua")
    expect(modal:isVisible()).toBe(false)

    io.popen = originalPopen
  end)
end)
