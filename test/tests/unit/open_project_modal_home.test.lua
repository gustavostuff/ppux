local OpenProjectModal = require("user_interface.modals.open_project_modal")

describe("open_project_modal.lua - home directory", function()
  it("resolves a non-empty home directory when Home is used", function()
    local originalGetenv = os.getenv
    local originalPopen = io.popen

    os.getenv = function(key)
      if key == "HOME" then
        return "/tmp/modal_home_test"
      end
      return nil
    end

    io.popen = function(command)
      local lines = {}
      if command == "ls -1Ap '/tmp/work' 2>/dev/null" then
        lines = { "project.lua" }
      elseif command == "ls -1Ap '/tmp/modal_home_test' 2>/dev/null" then
        lines = {}
      end
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

    local modal = OpenProjectModal.new()
    modal:show({
      initialDir = "/tmp/work",
    })

    local ok = modal:_goHome()
    local homePath = modal:getCurrentDir()

    expect(ok).toBe(true)
    expect(type(homePath)).toBe("string")
    expect(homePath ~= "").toBe(true)

    os.getenv = originalGetenv
    io.popen = originalPopen
  end)
end)
