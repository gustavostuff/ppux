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
  it("filters to non-hidden folders plus lua/ppux files by default", function()
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
    expect(#entries).toBe(4)
    expect(entries[1].isDir).toBe(true)
    expect(entries[1].name).toBe("folderA")
    expect(entries[2].name).toBe("folderB")
    expect(entries[3].name).toBe("alpha.lua")
    expect(entries[4].name).toBe("beta.ppux")

    io.popen = originalPopen
  end)

  it("shows hidden files/folders when showHidden=true", function()
    local originalPopen = io.popen
    io.popen = makePopenStub({
      ["ls -1Ap '/tmp/work' 2>/dev/null"] = {
        ".cache/",
        ".project.lua",
        "visible.lua",
      },
    })

    local modal = OpenProjectModal.new()
    modal:show({
      initialDir = "/tmp/work",
      showHidden = true,
    })

    local entries = modal:getEntries()
    expect(#entries).toBe(3)
    expect(entries[1].name).toBe(".cache")
    expect(entries[2].name).toBe(".project.lua")
    expect(entries[3].name).toBe("visible.lua")

    io.popen = originalPopen
  end)

  it("supports parent navigation, fixed slots, and file open callback", function()
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
        "proj10.lua",
        "proj11.lua",
        "proj12.lua",
        "proj13.lua",
        "proj14.lua",
        "proj15.lua",
        "proj16.lua",
        "proj17.lua",
        "proj18.lua",
        "proj19.lua",
        "proj20.lua",
        "proj21.lua",
        "proj22.lua",
        "proj23.lua",
        "proj24.lua",
        "proj25.lua",
        "proj26.lua",
        "proj27.lua",
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
    expect(#firstVisible).toBe(24)
    expect(firstVisible[1].name).toBe("child")
    expect(firstVisible[24].name).toBe("proj23.lua")

    modal:wheelmoved(0, -1)
    local afterScroll = modal:getVisibleEntries()
    expect(afterScroll[1].name).toBe("proj03.lua")
    expect(afterScroll[24].name).toBe("proj26.lua")

    modal:_setScrollOffset(0)
    expect(modal:_activateVisibleSlot(1)).toBe(true)
    expect(modal:getCurrentDir()).toBe("/tmp/work/child")

    expect(modal:_goUp()).toBe(true)
    expect(modal:getCurrentDir()).toBe("/tmp/work")

    modal:_setScrollOffset(0)
    expect(modal:_activateVisibleSlot(2)).toBe(true)
    expect(opened).toBe("/tmp/work/proj01.lua")
    expect(modal:isVisible()).toBe(false)

    io.popen = originalPopen
  end)
end)
